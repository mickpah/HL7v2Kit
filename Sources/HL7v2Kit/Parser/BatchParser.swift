// BatchParser.swift
// HL7 v2 batch / file grammar — recognise FHS / BHS / BTS / FTS framing
// and split into individual `Message` values. The bare `Parser` treats
// a stream with multiple MSH segments as one `Message` with multiple
// MSH segments inside; `BatchParser` is the explicit-batch alternative
// for callers that want each message returned separately. v0.3-T2.

import Foundation

/// A parsed HL7 v2 batch / file. The HL7 v2 batch grammar is
/// optionally-nested: a file may contain zero or more batches, each
/// batch contains zero or more messages. `FHS` / `FTS` mark the file
/// boundary; `BHS` / `BTS` mark each batch boundary. All four markers
/// are optional — a batch file may carry only MSH segments, or only
/// BHS+MSH+BTS, or the full FHS+BHS+...+BTS+FTS envelope.
public struct BatchFile: Sendable, Equatable, Hashable {
    /// The `FHS` segment as a raw wire string (without the trailing
    /// segment terminator), or `nil` if the file had no FHS.
    public let fileHeader: String?

    /// Batch groups in document order. A bare-MSH stream with no BHS
    /// markers produces a single ``BatchGroup`` with `header == nil`,
    /// `trailer == nil`, and one or more messages.
    public let batches: [BatchGroup]

    /// The `FTS` segment as a raw wire string, or `nil` if absent.
    public let fileTrailer: String?

    public init(fileHeader: String?, batches: [BatchGroup], fileTrailer: String?) {
        self.fileHeader = fileHeader
        self.batches = batches
        self.fileTrailer = fileTrailer
    }

    /// Convenience: flat list of every message across every batch
    /// group, in document order.
    public var allMessages: [Message] {
        batches.flatMap(\.messages)
    }
}

/// A single batch within a ``BatchFile``. May carry zero or more
/// messages between an optional `BHS` and an optional `BTS`.
public struct BatchGroup: Sendable, Equatable, Hashable {
    /// The `BHS` segment as a raw wire string, or `nil` if absent.
    public let header: String?
    /// Parsed messages between this batch's header and trailer, in
    /// document order.
    public let messages: [Message]
    /// The `BTS` segment as a raw wire string, or `nil` if absent.
    public let trailer: String?

    public init(header: String?, messages: [Message], trailer: String?) {
        self.header = header
        self.messages = messages
        self.trailer = trailer
    }
}

/// Parses an HL7 v2 batch / file stream into a structured ``BatchFile``.
///
/// `BatchParser` walks the input segment-by-segment, recognising the
/// FHS / BHS / BTS / FTS framing markers and grouping the message
/// segments between them. Each message run is passed through ``Parser``
/// for the per-message structural parse (so character-encoding detection,
/// composite parsing, escape-sequence decoding, etc. all behave
/// identically to `Parser.parse(_:)`).
///
/// The bare ``Parser`` keeps its v0.1.0 behaviour of treating a stream
/// with multiple MSH segments as one ``Message`` with multiple MSH
/// segments inside (pinned by `ParseErrorTests.multipleMSHSegmentsAcceptedAsIs`).
/// `BatchParser` is the opt-in alternative when the caller wants those
/// MSH-starting runs split into separate messages.
public struct BatchParser: Sendable {
    public let options: ParserOptions

    public init(options: ParserOptions = .default) {
        self.options = options
    }

    /// Parse a batch from raw bytes. Encoding handling mirrors
    /// ``Parser/parse(_:)-data``: BOM stripping, NUL rejection, MSH-18
    /// detection. The MSH-18 detection probes the *first* message in
    /// the stream (the first MSH after any FHS / BHS) — all messages
    /// in a single batch file are expected to share the same charset.
    public func parse(_ data: Data) throws -> BatchFile {
        guard !data.isEmpty else { throw ParseError.emptyInput }
        let payload: Data = data.starts(with: [0xEF, 0xBB, 0xBF])
            ? data.dropFirst(3)
            : data
        guard !payload.isEmpty else { throw ParseError.emptyInput }
        if let nulIndex = payload.firstIndex(of: 0x00) {
            throw ParseError.truncatedMessage(
                atByte: payload.distance(from: payload.startIndex, to: nulIndex)
            )
        }
        let probe = String(data: payload, encoding: .isoLatin1) ?? ""
        let characterEncoding = try CharacterEncoding.detect(in: probe)
        guard let decoded = String(data: payload, encoding: characterEncoding.stringEncoding) else {
            throw ParseError.unsupportedCharacterEncoding(declared: characterEncoding.wireValue)
        }
        return try parseString(decoded)
    }

    /// Parse a batch from an already-decoded string.
    public func parse(_ raw: String) throws -> BatchFile {
        try parseString(raw)
    }

    private func parseString(_ raw: String) throws -> BatchFile {
        // Normalise line terminators — accept any of `\r\n`, `\n`, `\r`.
        // Per-message parsing then runs through `Parser` which enforces
        // its own line-terminator policy.
        let normalised = raw
            .replacingOccurrences(of: "\r\n", with: "\r")
            .replacingOccurrences(of: "\n", with: "\r")

        let lines = normalised
            .split(separator: "\r", omittingEmptySubsequences: true)
            .map(String.init)
        guard !lines.isEmpty else { throw ParseError.emptyInput }

        var fileHeader: String? = nil
        var fileTrailer: String? = nil
        var batches: [BatchGroup] = []
        var currentBHS: String? = nil
        var currentMessages: [Message] = []
        var currentMessageSegments: [String] = []
        let parser = Parser(options: options)

        func closeMessage() throws {
            guard !currentMessageSegments.isEmpty else { return }
            let wire = currentMessageSegments.joined(separator: "\r") + "\r"
            let message = try parser.parse(wire)
            currentMessages.append(message)
            currentMessageSegments.removeAll(keepingCapacity: true)
        }

        func closeBatch(trailer: String? = nil) throws {
            try closeMessage()
            let hasContent = currentBHS != nil || !currentMessages.isEmpty || trailer != nil
            if hasContent {
                batches.append(BatchGroup(
                    header: currentBHS,
                    messages: currentMessages,
                    trailer: trailer
                ))
            }
            currentBHS = nil
            currentMessages.removeAll(keepingCapacity: true)
        }

        for line in lines {
            // Segment IDs are 3 ASCII characters; anything shorter is
            // malformed — treat it as a body segment so `Parser` can
            // raise the appropriate error when the message closes.
            let id = line.prefix(3)
            switch id {
            case "FHS":
                fileHeader = line
            case "FTS":
                try closeBatch()
                fileTrailer = line
            case "BHS":
                try closeBatch()
                currentBHS = line
            case "BTS":
                try closeBatch(trailer: line)
            case "MSH":
                try closeMessage()
                currentMessageSegments.append(line)
            default:
                currentMessageSegments.append(line)
            }
        }
        try closeBatch()

        return BatchFile(
            fileHeader: fileHeader,
            batches: batches,
            fileTrailer: fileTrailer
        )
    }
}
