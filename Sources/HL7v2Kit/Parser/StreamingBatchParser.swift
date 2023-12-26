// StreamingBatchParser.swift
// Incremental, memory-bounded variant of `BatchParser`. Consumes bytes
// in arbitrary chunks via `feed(_:)` and yields complete `Message`
// values as soon as each MSH-starting run closes. Designed for
// very-large historical-extract files that don't fit comfortably in
// memory. v0.3-S1.

import Foundation

/// Streaming parser for HL7 v2 batch files. Operates on incremental
/// byte chunks via ``StreamingBatchParser/feed(_:)`` / ``finish()``
/// and emits ``Message`` values as soon as the next MSH (or batch
/// marker, or EOF) closes the current message run. Memory footprint
/// stays bounded by the size of the largest in-flight message —
/// previously-emitted messages don't accumulate on the parser.
///
/// **Scope note**. Streaming mode flattens the batch grammar — FHS /
/// FTS / BHS / BTS markers are recognised (so they correctly close
/// any open message) but their wire strings are NOT preserved.
/// Callers that need the batch / file structure should use the
/// non-streaming ``BatchParser`` instead.
///
/// **Charset note**. Streaming mode assumes UTF-8 input. MSH-18
/// charset detection requires the whole first message to be buffered,
/// which defeats the streaming property; callers parsing non-UTF-8
/// batches should pre-decode and use ``BatchParser/parse(_:)-string``,
/// or use the non-streaming ``BatchParser`` directly.
public struct StreamingBatchParser: Sendable {
    public let options: ParserOptions

    /// Byte-level buffer for the in-progress segment. Drained on every
    /// CR/LF.
    private var segmentBuffer: [UInt8]
    /// Already-terminated segment lines accumulated for the current
    /// open message. Drained when an MSH / batch marker closes the run.
    private var messageSegments: [String]
    /// Running byte offset, used for ``ParseError/truncatedMessage(atByte:)``
    /// reporting when a NUL is encountered mid-stream.
    private var bytesConsumed: Int

    public init(options: ParserOptions = .default) {
        self.options = options
        self.segmentBuffer = []
        self.messageSegments = []
        self.bytesConsumed = 0
    }

    /// Feed an incremental byte chunk. Returns any messages that
    /// completed based on the bytes received so far — typically zero
    /// or one per call, but can be more if a chunk spans multiple
    /// MSH-starting runs.
    ///
    /// Throws ``ParseError/truncatedMessage(atByte:)`` if a `0x00`
    /// byte is encountered (real HL7 v2 wire never carries NUL).
    public mutating func feed(_ bytes: Data) throws -> [Message] {
        var emitted: [Message] = []
        for byte in bytes {
            defer { bytesConsumed += 1 }
            if byte == 0x00 {
                throw ParseError.truncatedMessage(atByte: bytesConsumed)
            }
            if byte == 0x0D || byte == 0x0A {
                if let message = try flushPendingSegment() {
                    emitted.append(message)
                }
            } else {
                segmentBuffer.append(byte)
            }
        }
        return emitted
    }

    /// Close the stream. Flushes any unterminated trailing segment
    /// and emits any in-flight message. Call exactly once after the
    /// last ``feed(_:)``.
    public mutating func finish() throws -> [Message] {
        var emitted: [Message] = []
        if let message = try flushPendingSegment() {
            emitted.append(message)
        }
        if let message = try drainOpenMessage() {
            emitted.append(message)
        }
        return emitted
    }

    /// True if the parser has buffered bytes that haven't yet been
    /// emitted as a message — i.e., there's a partial segment or an
    /// open MSH run. Useful for half-frame timeout detection.
    public var hasPending: Bool {
        !segmentBuffer.isEmpty || !messageSegments.isEmpty
    }

    // MARK: - Internals

    private mutating func flushPendingSegment() throws -> Message? {
        guard !segmentBuffer.isEmpty else { return nil }
        let line = String(decoding: segmentBuffer, as: UTF8.self)
        segmentBuffer.removeAll(keepingCapacity: true)
        return try classify(line)
    }

    private mutating func classify(_ line: String) throws -> Message? {
        let id = line.prefix(3)
        switch id {
        case "FHS", "FTS", "BHS", "BTS":
            // Batch / file marker. Close any in-flight message; the
            // marker line itself is intentionally discarded — streaming
            // mode flattens to messages only.
            return try drainOpenMessage()
        case "MSH":
            let emitted = try drainOpenMessage()
            messageSegments.append(line)
            return emitted
        default:
            messageSegments.append(line)
            return nil
        }
    }

    private mutating func drainOpenMessage() throws -> Message? {
        guard !messageSegments.isEmpty else { return nil }
        let wire = messageSegments.joined(separator: "\r") + "\r"
        messageSegments.removeAll(keepingCapacity: true)
        return try Parser(options: options).parse(wire)
    }
}

// MARK: - AsyncStream wrapper

extension StreamingBatchParser {
    /// Stream messages from an async byte sequence (e.g. a
    /// `FileHandle.AsyncBytes` or a network read loop). Yields each
    /// ``Message`` as soon as the parser identifies it and finishes
    /// the stream when the upstream sequence ends.
    ///
    /// The stream throws on the first parser error (NUL byte, malformed
    /// MSH, etc.).
    public static func messages<S: AsyncSequence & Sendable>(
        from bytes: S,
        options: ParserOptions = .default
    ) -> AsyncThrowingStream<Message, any Error> where S.Element == UInt8 {
        AsyncThrowingStream { continuation in
            let task = Task {
                var parser = StreamingBatchParser(options: options)
                do {
                    var chunk = Data()
                    for try await byte in bytes {
                        chunk.append(byte)
                        if chunk.count >= 4096 {
                            for message in try parser.feed(chunk) {
                                continuation.yield(message)
                            }
                            chunk.removeAll(keepingCapacity: true)
                        }
                    }
                    if !chunk.isEmpty {
                        for message in try parser.feed(chunk) {
                            continuation.yield(message)
                        }
                    }
                    for message in try parser.finish() {
                        continuation.yield(message)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
