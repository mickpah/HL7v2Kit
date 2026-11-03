// BatchTrailerLineTests.swift
// EG-1: a line starting BTS or FTS is a trailer only when it is that ID alone or its fourth
// character is the field separator of the last MSH, BHS or FHS read (v2.5.1 sections
// 2.10.3.1 and 2.15.2.1); otherwise it is a body line of the open message, on both batch parsers.

import Foundation
import Testing
import HL7v2Kit

@Suite("Batch trailer lines")
struct BatchTrailerLineTests {
    static func msh(_ id: String, separator: String = "|") -> String {
        ["MSH", #"^~\&"#, "APP", "FAC", "", "", "20260101", "", "ADT^A01^ADT_A01", id, "P", "2.5.1"]
            .joined(separator: separator)
    }

    static func wire(_ lines: [String]) -> String { lines.joined(separator: "\r") + "\r" }

    static let bodyLines: [(line: String, id: String)] = [("BTSX|1", "BTSX"), ("FTSX|1", "FTSX")]

    @Test("BatchParser keeps a BTSX or FTSX line in its message", arguments: bodyLines)
    func batchParserKeepsBodyLine(_ row: (line: String, id: String)) throws {
        let file = try BatchParser().parse(Self.wire(
            [#"FHS|^~\&|APP"#, #"BHS|^~\&|APP"#, Self.msh("C1"), row.line, "BTS|1", "FTS|1"]))
        #expect(file.batches.map(\.trailer) == ["BTS|1"])
        #expect(file.fileTrailer == "FTS|1")
        let message = try #require(file.allMessages.first)
        #expect(file.allMessages.count == 1)
        #expect(message.segments.map(\.segmentID) == ["MSH", row.id])
        #expect(message.serialize() == Data(Self.wire([Self.msh("C1"), row.line]).utf8))
    }

    @Test("StreamingBatchParser keeps a BTSX or FTSX line in its message", arguments: bodyLines)
    func streamingKeepsBodyLine(_ row: (line: String, id: String)) throws {
        var parser = StreamingBatchParser()
        let fed = try parser.feed(Data(Self.wire([Self.msh("C1"), row.line]).utf8))
        #expect(fed.isEmpty)
        let finished = try parser.finish()
        #expect(finished.map { $0.segments.map(\.segmentID) } == [["MSH", row.id]])
    }

    @Test("A trailer alone or with the separator in force still closes the batch or file")
    func trailerCloses() throws {
        let file = try BatchParser().parse(Self.wire(
            [#"BHS|^~\&|APP"#, Self.msh("C1"), "BTS", #"BHS|^~\&|APP"#, Self.msh("C2"), "BTS|1", "FTS"]))
        #expect(file.batches.map(\.trailer) == ["BTS", "BTS|1"])
        #expect(file.batches.map(\.messages.count) == [1, 1])
        #expect(file.fileTrailer == "FTS")
        for trailer in ["BTS|1", "FTS|1", "BTS", "FTS"] {
            var parser = StreamingBatchParser()
            let fed = try parser.feed(Data(Self.wire([Self.msh("C1"), trailer]).utf8))
            #expect(fed.map(\.segments.count) == [1], "\(trailer)")
            let finished = try parser.finish()
            #expect(finished.isEmpty, "\(trailer)")
        }
    }

    @Test("The separator in force is the last MSH, BHS or FHS line's fourth character")
    func separatorInForce() throws {
        let hashed = Self.wire([#"BHS#^~\&#APP"#, Self.msh("C1", separator: "#"), "BTS|1", "BTS#1"])
        let file = try BatchParser().parse(hashed)
        #expect(file.batches.map(\.trailer) == ["BTS#1"])
        #expect(file.allMessages.map { $0.segments.map(\.segmentID) } == [["MSH", "BTS|1"]])
        var parser = StreamingBatchParser()
        let hashedFed = try parser.feed(Data(hashed.utf8))
        #expect(hashedFed.map(\.segments.count) == [2])
        let lettered = Self.wire([Self.msh("C2", separator: "X"), "BTSX1"])
        let letteredFile = try BatchParser().parse(lettered)
        #expect(letteredFile.batches.map(\.trailer) == ["BTSX1"])
        var streaming = StreamingBatchParser()
        let letteredFed = try streaming.feed(Data(lettered.utf8))
        #expect(letteredFed.map(\.segments.count) == [1])
    }

    // C1: the envelope's separator may differ from its messages'. A trailer is read with the
    // separator of the last MSH, BHS or FHS (v2.5.1 section 2.15.2.1: BHS-1 is defined as MSH-1).
    static let envelopeHash = #"FHS#^~\&#A\rBHS#^~\&#A\rMSH|^~\&|APP|FAC|||20260101||ADT^A01^ADT_A01|C1|P|2.5.1\rPID|1\rBTS#99\rFTS#99\r"#
    static let messageHash = #"FHS|^~\&|A\rBHS|^~\&|A\rMSH#^~\&#APP#FAC###20260101##ADT^A01^ADT_A01#C1#P#2.5.1\rPID#1\rBTS|1\rFTS|1\r"#
    static let mixed: [(wire: String, bts: String, fts: String, last: String)] = [
        (envelopeHash.replacingOccurrences(of: #"\r"#, with: "\r"), "BTS#99", "FTS#99", "PID|1\r"),
        (messageHash.replacingOccurrences(of: #"\r"#, with: "\r"), "BTS|1", "FTS|1", "PID#1\r"),
    ]

    @Test("BatchParser reads a trailer by the envelope's separator, not only the last MSH's", arguments: mixed)
    func batchParserMixedSeparators(_ row: (wire: String, bts: String, fts: String, last: String)) throws {
        let file = try BatchParser().parse(row.wire)
        #expect(file.batches.map(\.trailer) == [row.bts])
        #expect(file.fileTrailer == row.fts)
        let message = try #require(file.allMessages.first)
        #expect(file.allMessages.count == 1)
        #expect(message.segments.map(\.segmentID) == ["MSH", "PID"])
        #expect(message.serialize().suffix(row.last.utf8.count) == Data(row.last.utf8))
    }

    @Test("BatchValidator counts against a trailer read by the envelope's separator")
    func validatorMixedSeparators() throws {
        let file = try BatchParser().parse(Self.mixed[0].wire)
        let report = BatchValidator().validate(file)
        let numbers = report.batchIssues.map(\.code.number)
        #expect(numbers.filter { $0 == 2009 }.count == 2)
        #expect(!numbers.contains(1014))
        #expect(report.messageReports.allSatisfy { !$0.issues.map(\.code.number).contains(1014) })
    }

    @Test("StreamingBatchParser reads a trailer by the envelope's separator, at any chunk size",
          arguments: [1, 2, 3, 7, 4096])
    func streamingMixedSeparators(_ size: Int) throws {
        for row in Self.mixed {
            var parser = StreamingBatchParser()
            var messages: [Message] = []
            let bytes = Array(row.wire.utf8)
            for start in stride(from: 0, to: bytes.count, by: size) {
                messages += try parser.feed(Data(bytes[start..<min(start + size, bytes.count)]))
            }
            messages += try parser.finish()
            #expect(messages.map { $0.segments.map(\.segmentID) } == [["MSH", "PID"]], "chunk \(size)")
        }
    }
}
