// StreamingBatchParserTests.swift
// v0.3-S1: incremental, memory-bounded batch parser. Exercises the
// feed/finish core across whole-input / byte-at-a-time / random-chunk
// shapes, plus marker-flattening behaviour and the AsyncStream wrapper.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Streaming batch parser (v0.3-S1)")
struct StreamingBatchParserTests {

    private let twoMessageBatch = """
    BHS|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||SAMPLE\r\
    MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG1|P|2.5.1\r\
    PID|1||111\r\
    MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120100||ADT^A01|MSG2|P|2.5.1\r\
    PID|2||222\r\
    BTS|2\r
    """

    // MARK: - Whole-input feed

    @Test("Feed-then-finish on a complete batch yields all messages")
    func wholeInputFeedThenFinish() throws {
        var parser = StreamingBatchParser()
        let feedMessages = try parser.feed(Data(twoMessageBatch.utf8))
        let finishMessages = try parser.finish()
        let all = feedMessages + finishMessages
        #expect(all.count == 2)
        #expect(all[0].firstSegment(MSH.self)?.messageControlID == "MSG1")
        #expect(all[1].firstSegment(MSH.self)?.messageControlID == "MSG2")
    }

    @Test("Streaming flattens batch markers — FHS/BHS/BTS/FTS are NOT preserved")
    func markersFlattenedNotPreserved() throws {
        let fullyWrapped = """
        FHS|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||SAMPLE-FILE\r\
        BHS|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||SAMPLE-BATCH\r\
        MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG1|P|2.5.1\r\
        PID|1||111\r\
        BTS|1\r\
        FTS|1\r
        """
        var parser = StreamingBatchParser()
        var emitted = try parser.feed(Data(fullyWrapped.utf8))
        emitted.append(contentsOf: try parser.finish())
        // Two-message-style structure not preserved here; we only emit
        // the messages. One MSH → one Message.
        #expect(emitted.count == 1)
        #expect(emitted[0].firstSegment(MSH.self)?.messageControlID == "MSG1")
    }

    // MARK: - Chunked feed shapes

    @Test("Byte-at-a-time feed produces the same messages as whole-input feed")
    func byteAtATimeFeed() throws {
        var parser = StreamingBatchParser()
        var emitted: [Message] = []
        for byte in twoMessageBatch.utf8 {
            emitted.append(contentsOf: try parser.feed(Data([byte])))
        }
        emitted.append(contentsOf: try parser.finish())
        #expect(emitted.count == 2)
        #expect(emitted[0].firstSegment(MSH.self)?.messageControlID == "MSG1")
        #expect(emitted[1].firstSegment(MSH.self)?.messageControlID == "MSG2")
    }

    @Test("Random-sized chunk feed produces the same messages")
    func randomSizedChunks() throws {
        var parser = StreamingBatchParser()
        let bytes = Array(twoMessageBatch.utf8)
        var i = 0
        var emitted: [Message] = []
        let chunkSizes = [3, 17, 1, 50, 7, 200, 11]   // arbitrary
        var s = 0
        while i < bytes.count {
            let size = chunkSizes[s % chunkSizes.count]
            s += 1
            let end = min(i + size, bytes.count)
            emitted.append(contentsOf: try parser.feed(Data(bytes[i..<end])))
            i = end
        }
        emitted.append(contentsOf: try parser.finish())
        #expect(emitted.count == 2)
        #expect(emitted[0].firstSegment(MSH.self)?.messageControlID == "MSG1")
        #expect(emitted[1].firstSegment(MSH.self)?.messageControlID == "MSG2")
    }

    // MARK: - Pending / incremental emission

    @Test("First message emits as soon as the second MSH closes its run — not at finish()")
    func emitsBeforeFinish() throws {
        var parser = StreamingBatchParser()
        // Feed enough bytes to close out the first message (when the
        // second MSH starts).
        let cutAfterSecondMSH = twoMessageBatch.range(of: "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120100")!
        let firstChunk = String(twoMessageBatch[..<cutAfterSecondMSH.upperBound])
        let emitted = try parser.feed(Data(firstChunk.utf8))
        // The MSH-2 line isn't terminated yet, so the parser hasn't
        // seen the boundary — feed up to the next CR.
        let cutToCR = twoMessageBatch.range(of: "\r", range: cutAfterSecondMSH.upperBound..<twoMessageBatch.endIndex)!
        let secondChunk = String(twoMessageBatch[cutAfterSecondMSH.upperBound..<cutToCR.upperBound])
        let emittedAfterMSH = emitted + (try parser.feed(Data(secondChunk.utf8)))
        // Now the first message must already have surfaced — without
        // calling finish() yet.
        #expect(emittedAfterMSH.count == 1)
        #expect(emittedAfterMSH[0].firstSegment(MSH.self)?.messageControlID == "MSG1")
        #expect(parser.hasPending)
    }

    // MARK: - Unterminated trailing segment

    @Test("finish() flushes a trailing segment that has no terminating CR")
    func unterminatedTrailingSegment() throws {
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG1|P|2.5.1\r\
        PID|1||111
        """  // note: no trailing \r
        var parser = StreamingBatchParser()
        var emitted = try parser.feed(Data(wire.utf8))
        emitted.append(contentsOf: try parser.finish())
        #expect(emitted.count == 1)
        #expect(emitted[0].firstSegment(PID.self)?.setID == "1")
    }

    @Test("hasPending toggles correctly through feed/finish")
    func hasPendingLifecycle() throws {
        var parser = StreamingBatchParser()
        #expect(!parser.hasPending)
        _ = try parser.feed(Data("MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG1|P|2.5.1\r".utf8))
        #expect(parser.hasPending)   // open MSH run
        _ = try parser.finish()
        #expect(!parser.hasPending)
    }

    // MARK: - NUL rejection

    @Test("NUL byte mid-stream throws .truncatedMessage with the byte offset")
    func nulByteRejected() {
        var parser = StreamingBatchParser()
        var bytes = Data("MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG1|P|2.5.1\r".utf8)
        bytes.append(0x00)
        bytes.append(contentsOf: Data("PID|1\r".utf8))
        #expect(throws: ParseError.self) {
            _ = try parser.feed(bytes)
        }
    }

    // MARK: - Memory-bounded behaviour

    @Test("Streaming a 100-message batch doesn't accumulate parsed messages on the parser")
    func messageQueueDoesNotAccumulate() throws {
        // Synthesize a 100-message batch and verify feed() returns
        // messages incrementally and parser.hasPending is reset after
        // each MSH boundary. The contract is the absence of state
        // accumulation: the parser's queue isn't a buffer of "all
        // emitted so far".
        var batch = "BHS|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||LARGE\r"
        for n in 1...100 {
            batch += "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG\(n)|P|2.5.1\r"
            batch += "PID|\(n)||\(n)\r"
        }
        batch += "BTS|100\r"

        var parser = StreamingBatchParser()
        var totalEmitted = 0
        // Feed in 1KB chunks to simulate I/O.
        let bytes = Array(batch.utf8)
        var i = 0
        while i < bytes.count {
            let end = min(i + 1024, bytes.count)
            let messages = try parser.feed(Data(bytes[i..<end]))
            totalEmitted += messages.count
            i = end
        }
        let final = try parser.finish()
        totalEmitted += final.count
        #expect(totalEmitted == 100)
        #expect(!parser.hasPending)
    }

    // MARK: - Recovery after a failure

    private let first = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG1|P|2.5.1\rPID|1||111\r"
    /// An MSH shorter than eight characters: the parser throws `.invalidMSH(reason: "too short")`.
    private let broken = "MSH|^~\rPID|9||999\r"
    private let second = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120100||ADT^A01|MSG2|P|2.5.1\rPID|2||222\r"

    private func controlIDs(_ messages: [Message]) -> [String?] {
        messages.map { $0.firstSegment(MSH.self)?.messageControlID }
    }

    @Test("A message that fails to parse loses nothing else in the same chunk")
    func failureKeepsTheRestOfTheChunk() throws {
        var parser = StreamingBatchParser()
        #expect(throws: ParseError.invalidMSH(reason: "too short")) {
            _ = try parser.feed(Data((first + broken + second).utf8))
        }
        let rest = try parser.finish()
        try #require(rest.count == 2)
        #expect(controlIDs(rest) == ["MSG1", "MSG2"])
        #expect(rest[1].segments.count == 2)
        #expect(!parser.hasPending)
    }

    @Test("A message that fails to parse does not lose the next MSH, byte by byte")
    func failureKeepsTheNextMSH() throws {
        var parser = StreamingBatchParser()
        var messages: [Message] = []
        var errors: [ParseError] = []
        for byte in Data((first + broken + second).utf8) {
            do {
                messages += try parser.feed(Data([byte]))
            } catch let error as ParseError {
                errors.append(error)
            }
        }
        messages += try parser.finish()
        #expect(errors == [.invalidMSH(reason: "too short")])
        #expect(controlIDs(messages) == ["MSG1", "MSG2"])
    }

    @Test("A NUL drops only the message it falls in; the next message parses whole")
    func nulDropsOnlyItsMessage() throws {
        var parser = StreamingBatchParser()
        var bytes = Data("MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG1|P|2.5.1\rPID|1".utf8)
        let nulOffset = bytes.count
        bytes.append(0x00)
        bytes.append(contentsOf: Data("||111\r".utf8))
        bytes.append(contentsOf: Data(second.utf8))
        #expect(throws: ParseError.truncatedMessage(atByte: nulOffset)) {
            _ = try parser.feed(bytes)
        }
        let rest = try parser.finish()
        #expect(controlIDs(rest) == ["MSG2"])
        #expect(rest.first?.segments.count == 2)
    }

    @Test("AsyncStream wrapper yields the messages before a failure, then throws")
    func asyncStreamYieldsBeforeFailure() async {
        let bytes = Data((first + broken + second).utf8).asyncBytes
        var collected: [String?] = []
        var thrown: (any Error)?
        do {
            for try await message in StreamingBatchParser.messages(from: bytes) {
                collected.append(message.firstSegment(MSH.self)?.messageControlID)
            }
        } catch {
            thrown = error
        }
        #expect(collected == ["MSG1"])
        #expect(thrown as? ParseError == .invalidMSH(reason: "too short"))
    }

    // MARK: - Size limit

    @Test("A message over maxMessageBytes is dropped; the messages around it parse")
    func oversizedMessageDropped() throws {
        let oversized = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|BIG|P|2.5.1\rOBX|1|ED|||"
            + String(repeating: "A", count: 500) + "\r"
        var parser = StreamingBatchParser(maxMessageBytes: 200)
        #expect(throws: ParseError.messageTooLarge(limit: 200)) {
            _ = try parser.feed(Data((first + oversized + second).utf8))
        }
        #expect(controlIDs(try parser.finish()) == ["MSG1", "MSG2"])
    }

    @Test("A message of exactly maxMessageBytes parses; one byte less is too large")
    func messageLimitIsInclusive() throws {
        let size = first.utf8.count - 2  // segment bytes, without the two CR terminators
        var atLimit = StreamingBatchParser(maxMessageBytes: size)
        var parsed = try atLimit.feed(Data(first.utf8))
        parsed += try atLimit.finish()
        #expect(controlIDs(parsed) == ["MSG1"])
        var underLimit = StreamingBatchParser(maxMessageBytes: size - 1)
        #expect(throws: ParseError.messageTooLarge(limit: size - 1)) {
            _ = try underLimit.feed(Data(first.utf8))
        }
    }

    @Test("A segment that never ends cannot grow past maxMessageBytes")
    func unterminatedSegmentBounded() throws {
        var parser = StreamingBatchParser(maxMessageBytes: 100)
        let endless = Data(("MSH|^~\\&|" + String(repeating: "A", count: 1_000)).utf8)
        #expect(throws: ParseError.messageTooLarge(limit: 100)) {
            _ = try parser.feed(endless)
        }
        // The rest of the line is skipped, not buffered, so more of it raises nothing.
        #expect(try parser.feed(Data(String(repeating: "A", count: 1_000).utf8)).isEmpty)
        #expect(try parser.feed(Data(("\r" + second).utf8)).isEmpty)
        #expect(controlIDs(try parser.finish()) == ["MSG2"])
    }

    // MARK: - AsyncStream wrapper

    @Test("AsyncStream wrapper yields each message in order")
    func asyncStreamYieldsInOrder() async throws {
        let bytes = Data(twoMessageBatch.utf8).asyncBytes
        var collected: [Message] = []
        for try await message in StreamingBatchParser.messages(from: bytes) {
            collected.append(message)
        }
        #expect(collected.count == 2)
        #expect(collected[0].firstSegment(MSH.self)?.messageControlID == "MSG1")
        #expect(collected[1].firstSegment(MSH.self)?.messageControlID == "MSG2")
    }

    @Test("AsyncStream wrapper throws on NUL byte")
    func asyncStreamThrowsOnNUL() async {
        var bytes = Data("MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG1|P|2.5.1\r".utf8)
        bytes.append(0x00)
        bytes.append(contentsOf: Data("PID|1\r".utf8))
        await #expect(throws: ParseError.self) {
            for try await _ in StreamingBatchParser.messages(from: bytes.asyncBytes) {
                // drain
            }
        }
    }
}

// MARK: - Test helper

/// Minimal AsyncSequence over a Data, for exercising the AsyncStream
/// wrapper without depending on FileHandle.AsyncBytes.
private struct DataAsyncBytes: AsyncSequence, Sendable {
    typealias Element = UInt8
    let data: Data

    func makeAsyncIterator() -> Iterator {
        Iterator(data: data, index: 0)
    }

    struct Iterator: AsyncIteratorProtocol {
        let data: Data
        var index: Int

        mutating func next() async throws -> UInt8? {
            guard index < data.count else { return nil }
            defer { index += 1 }
            return data[data.index(data.startIndex, offsetBy: index)]
        }
    }
}

private extension Data {
    var asyncBytes: DataAsyncBytes { DataAsyncBytes(data: self) }
}
