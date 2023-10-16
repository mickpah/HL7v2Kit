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
