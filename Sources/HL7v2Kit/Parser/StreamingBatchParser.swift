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
/// stays bounded by ``maxMessageBytes`` per in-flight message —
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
/// batches should pre-decode and use ``BatchParser/parse(_:)-(String)``,
/// or use the non-streaming ``BatchParser`` directly.
public struct StreamingBatchParser: Sendable {
    public let options: ParserOptions
    /// The most bytes one message may hold, segment terminators excluded.
    /// A longer message is dropped and reported as
    /// ``ParseError/messageTooLarge(limit:)``.
    public let maxMessageBytes: Int

    /// Byte-level buffer for the in-progress segment. Drained on every
    /// CR/LF.
    private var segmentBuffer: [UInt8]
    /// Already-terminated segment lines accumulated for the current
    /// open message. Drained when an MSH / batch marker closes the run.
    private var messageSegments: [String]
    /// Running byte offset, used for ``ParseError/truncatedMessage(atByte:)``
    /// reporting when a NUL is encountered mid-stream.
    private var bytesConsumed: Int
    /// Bytes in `messageSegments`, checked against `maxMessageBytes`.
    private var messageBytes: Int
    /// Input not yet read: the rest of a chunk after a failure.
    private var unread: [UInt8]
    /// Messages completed before a failure, returned first by the next call.
    private var ready: [Message]
    /// After a failure inside a message, its remaining lines are dropped
    /// until the next MSH or batch marker.
    private var skippingMessage: Bool

    /// Segment IDs that start a new run: a message or a batch / file marker.
    private static let runStarts = ["MSH", "FHS", "FTS", "BHS", "BTS"]

    /// - Parameters:
    ///   - options: parser options applied to each message.
    ///   - maxMessageBytes: the most bytes one message may hold; 64 MiB
    ///     by default. Pass `.max` for no limit.
    public init(options: ParserOptions = .default, maxMessageBytes: Int = 64 << 20) {
        self.options = options
        self.maxMessageBytes = maxMessageBytes
        self.messageBytes = 0
        self.segmentBuffer = []
        self.messageSegments = []
        self.bytesConsumed = 0
        self.unread = []
        self.ready = []
        self.skippingMessage = false
    }

    /// Feed an incremental byte chunk. Returns any messages that
    /// completed based on the bytes received so far — typically zero
    /// or one per call, but can be more if a chunk spans multiple
    /// MSH-starting runs.
    ///
    /// Throws ``ParseError/truncatedMessage(atByte:)`` if a `0x00`
    /// byte is encountered (real HL7 v2 wire never carries NUL), or the
    /// ``Parser`` error for a message that fails to parse.
    ///
    /// A failure loses only the failed message. The parser keeps the
    /// messages completed before it and the input after it, and the next
    /// call to ``feed(_:)`` or ``finish()`` returns those messages first
    /// and carries on reading. After a NUL, the message it falls in is
    /// dropped up to the next MSH or batch marker.
    public mutating func feed(_ bytes: Data) throws -> [Message] {
        unread.append(contentsOf: bytes)
        return try read(finishing: false)
    }

    /// Close the stream. Flushes any unterminated trailing segment
    /// and emits any in-flight message. Call after the last
    /// ``feed(_:)``; if it throws, call it again to collect the
    /// messages that follow the failure.
    public mutating func finish() throws -> [Message] {
        try read(finishing: true)
    }

    /// True if the parser holds input or messages not yet returned: a
    /// partial segment, an open MSH run, or what a failure kept for the
    /// next call. Useful for half-frame timeout detection.
    public var hasPending: Bool {
        !segmentBuffer.isEmpty || !messageSegments.isEmpty || !unread.isEmpty || !ready.isEmpty
    }

    // MARK: - Internals

    /// Reads `unread` and, at the end of the stream, closes the open
    /// message. On a failure, keeps the messages completed so far and
    /// the input after the failing byte for the next call.
    private mutating func read(finishing: Bool) throws -> [Message] {
        var emitted = ready
        ready = []
        var index = 0
        defer { unread.removeFirst(index) }
        do {
            while index < unread.count {
                let byte = unread[index]
                index += 1
                if let message = try step(byte) {
                    emitted.append(message)
                }
            }
            if finishing {
                if let message = try flushPendingSegment() {
                    emitted.append(message)
                }
                if let message = try drainOpenMessage() {
                    emitted.append(message)
                }
            }
        } catch {
            ready = emitted
            throw error
        }
        return emitted
    }

    private mutating func step(_ byte: UInt8) throws -> Message? {
        defer { bytesConsumed += 1 }
        switch byte {
        case 0x00:
            dropFailingMessage()
            throw ParseError.truncatedMessage(atByte: bytesConsumed)
        case 0x0D, 0x0A:
            return try flushPendingSegment()
        default:
            // While skipping, a segment ID is enough to spot the next run.
            if skippingMessage && segmentBuffer.count >= 3 && !startsMessageRun(segmentBuffer) {
                return nil
            }
            segmentBuffer.append(byte)
            if messageBytes + segmentBuffer.count > maxMessageBytes && overLimit() {
                dropFailingMessage()
                throw ParseError.messageTooLarge(limit: maxMessageBytes)
            }
            return nil
        }
    }

    private mutating func flushPendingSegment() throws -> Message? {
        guard !segmentBuffer.isEmpty else { return nil }
        let line = String(decoding: segmentBuffer, as: UTF8.self)
        let byteCount = segmentBuffer.count
        segmentBuffer.removeAll(keepingCapacity: true)
        return try classify(line, byteCount: byteCount)
    }

    private mutating func classify(_ line: String, byteCount: Int) throws -> Message? {
        let id = line.prefix(3)
        switch id {
        case "FHS", "FTS", "BHS", "BTS":
            // Batch / file marker. Close any in-flight message; the
            // marker line itself is intentionally discarded — streaming
            // mode flattens to messages only.
            skippingMessage = false
            return try drainOpenMessage()
        case "MSH":
            // Start the new message before parsing the one it closes, so
            // a failure in the old message cannot lose this line.
            skippingMessage = false
            let closed = messageSegments
            messageSegments = [line]
            messageBytes = byteCount
            return try parse(closed)
        default:
            if !skippingMessage {
                messageSegments.append(line)
                messageBytes += byteCount
            }
            return nil
        }
    }

    private mutating func drainOpenMessage() throws -> Message? {
        let closed = messageSegments
        messageSegments.removeAll(keepingCapacity: true)
        messageBytes = 0
        return try parse(closed)
    }

    private func parse(_ segments: [String]) throws -> Message? {
        guard !segments.isEmpty else { return nil }
        return try Parser(options: options).parse(segments.joined(separator: "\r") + "\r")
    }

    /// Drops the message a failing byte belongs to and skips its
    /// remaining lines up to the next MSH or batch marker. A segment
    /// that has already started a new run belongs to the next message,
    /// so the open message is kept and parses when that run closes.
    private mutating func dropFailingMessage() {
        if !startsMessageRun(segmentBuffer) {
            messageSegments.removeAll(keepingCapacity: true)
            messageBytes = 0
        }
        segmentBuffer.removeAll(keepingCapacity: true)
        skippingMessage = true
    }

    /// True when the message the buffered segment belongs to passes
    /// `maxMessageBytes`. A segment that starts a new run counts on its
    /// own; while skipping, the open message is not growing.
    private func overLimit() -> Bool {
        if skippingMessage || startsMessageRun(segmentBuffer) {
            return segmentBuffer.count > maxMessageBytes
        }
        return messageBytes + segmentBuffer.count > maxMessageBytes
    }

    /// True when `bytes` begins with MSH or a batch / file marker.
    private func startsMessageRun(_ bytes: [UInt8]) -> Bool {
        Self.runStarts.contains { bytes.starts(with: $0.utf8) }
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
    /// MSH, etc.), after yielding every message that completed before it.
    public static func messages<S: AsyncSequence & Sendable>(
        from bytes: S,
        options: ParserOptions = .default,
        maxMessageBytes: Int = 64 << 20
    ) -> AsyncThrowingStream<Message, any Error> where S.Element == UInt8 {
        AsyncThrowingStream { continuation in
            let task = Task {
                var parser = StreamingBatchParser(options: options, maxMessageBytes: maxMessageBytes)
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
                    // Messages completed before the failure are still on
                    // the parser; deliver them before the error.
                    for message in parser.ready {
                        continuation.yield(message)
                    }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
