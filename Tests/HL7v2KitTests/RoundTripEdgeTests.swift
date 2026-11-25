// RoundTripEdgeTests.swift
// P00 S1: inputs the round-trip guarantee missed. A message whose last segment has no
// terminator serialises without one (S1-1); an MSH-2 carrying the v2.7+ truncation
// character parses and round-trips (S1-2).

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Round-trip edge cases")
struct RoundTripEdgeTests {
    /// Two segments and no final terminator.
    static let body = "MSH|^~\\&|SND|FAC|RCV|FAC|20260101120000||ADT^A01^ADT_A01|M1|P|2.5.1\r"
        + "PID|1||SYN-1^^^FAC^MR||Synthetic^Pat"

    // MARK: - S1-1 the final segment terminator

    @Test("P00 S1-1: a message with no final terminator serialises without one")
    func noTrailingTerminator() throws {
        let message = try Parser().parse(Self.body)
        #expect(message.trailingSegmentTerminator == false)
        #expect(message.serialize() == Data(Self.body.utf8))
    }

    @Test("P00 S1-1: a message with a final terminator keeps it")
    func trailingTerminator() throws {
        let wire = Self.body + "\r"
        let message = try Parser().parse(wire)
        #expect(message.trailingSegmentTerminator)
        #expect(message.serialize() == Data(wire.utf8))
    }

    @Test("P00 S1-1: the final terminator takes no part in equality or hashing")
    func terminatorOutsideEquality() throws {
        let without = try Parser().parse(Self.body)
        let with = try Parser().parse(Self.body + "\r")
        #expect(without == with)
        #expect(Set([without, with]).count == 1)
    }

    @Test("P00 S1-1: a message built in code ends with a terminator")
    func builtMessageTerminates() throws {
        let parsed = try Parser().parse(Self.body)
        let built = Message(version: parsed.version, encodingCharacters: parsed.encodingCharacters,
                            segments: parsed.segments)
        #expect(built.trailingSegmentTerminator)
        #expect(built.serialize().last == 0x0D)
    }

    @Test("P00 S1-1: the anonymiser keeps a missing final terminator")
    func anonymiserKeepsTerminator() throws {
        let output = Anonymiser(key: 7).anonymise(try Parser().parse(Self.body))
        #expect(output.trailingSegmentTerminator == false)
        #expect(output.serialize().last != 0x0D)
    }

    @Test("P00 S1-1: under .strict an LF is data, not a segment terminator, and is written back as \\X0A\\")
    func strictKeepsLineFeed() throws {
        let wire = "MSH|^~\\&|SND|FAC|RCV|FAC|20260101120000||ADT^A01^ADT_A01|M1|P|2.5.1\r"
            + "NTE|1||line one\nline two\r"
        let message = try Parser(options: ParserOptions(lineTerminator: .strict)).parse(wire)
        #expect(message.segments.count == 2)
        #expect(message["NTE-3"] == "line one\nline two")
        #expect(message.serialize() == Data(wire.replacingOccurrences(of: "\n", with: "\\X0A\\").utf8))
    }

    static let crlf = "MSH|^~\\&|SND|FAC|RCV|FAC|20260101120000||ADT^A01^ADT_A01|M1|P|2.5.1\r\n"
        + "PID|1||X\r"

    @Test("P00 S1-3: under .strict a CRLF line ending is rejected, not folded into the value")
    func strictRejectsCRLF() {
        #expect(throws: ParseError.lineFeedAfterSegmentTerminator(position: 2)) {
            try Parser(options: ParserOptions(lineTerminator: .strict)).parse(Self.crlf)
        }
    }

    @Test("P00 S1-3: under .strict a CRLF after the last segment is rejected too")
    func strictRejectsTrailingCRLF() {
        let wire = "MSH|^~\\&|SND|FAC|RCV|FAC|20260101120000||ADT^A01^ADT_A01|M1|P|2.5.1\r\n"
        #expect(throws: ParseError.lineFeedAfterSegmentTerminator(position: 2)) {
            try Parser(options: ParserOptions(lineTerminator: .strict)).parse(wire)
        }
    }

    @Test("#33: under .strict an all-LF message is rejected, not read as one MSH segment")
    func strictRejectsLineFeedTerminators() throws {
        let url = FixtureCorpus.fixtureURL(named: "au_oru_r01_pathology.hl7")
        let wire = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\r", with: "\n")
        #expect(throws: ParseError.lineFeedAfterSegmentTerminator(position: 2)) {
            try Parser(options: ParserOptions(lineTerminator: .strict)).parse(wire)
        }
        let lenient = try Parser().parse(wire)
        #expect(lenient.segments.count > 1)
    }

    @Test("#33: the position is the segment that follows the first bare line feed")
    func strictLineFeedPosition() {
        let wire = ["MSH|^~\\&|SND|FAC|RCV|FAC|20260101120000||ADT^A01^ADT_A01|M1|P|2.5.1\r",
                    "PID|1||X\nPV1|1|I\r"].joined()
        #expect(throws: ParseError.lineFeedAfterSegmentTerminator(position: 3)) {
            try Parser(options: ParserOptions(lineTerminator: .strict)).parse(wire)
        }
    }

    @Test("#33: the check reads bytes: a value shaped like a segment start is rejected, others kept")
    func strictLineFeedInValueByShape() throws {
        let msh = "MSH|^~\\&|SND|FAC|RCV|FAC|20260101120000||ADT^A01^ADT_A01|M1|P|2.5.1\r"
        let strict = Parser(options: ParserOptions(lineTerminator: .strict))
        #expect(throws: ParseError.lineFeedAfterSegmentTerminator(position: 3)) {
            try strict.parse(msh + "NTE|1||see\nOBX|x\r")
        }
        let kept = try strict.parse(msh + "NTE|1||see\nABC x\r")
        #expect(kept["NTE-3"] == "see\nABC x")
    }

    @Test("#33: under .strict a line feed as the last byte of the input is rejected")
    func strictRejectsFinalLineFeed() {
        let msh = "MSH|^~\\&|SND|FAC|RCV|FAC|20260101120000||ADT^A01^ADT_A01|M1|P|2.5.1"
        let strict = Parser(options: ParserOptions(lineTerminator: .strict))
        #expect(throws: ParseError.lineFeedAfterSegmentTerminator(position: 2)) {
            try strict.parse(msh + "\n")
        }
        #expect(throws: ParseError.lineFeedAfterSegmentTerminator(position: 3)) {
            try strict.parse(msh + "\rPID|1||X\n")
        }
    }

    @Test("#33: under .strict a line feed ending a field that does not end the input is data")
    func strictKeepsLineFeedEndingField() throws {
        let msh = "MSH|^~\\&|SND|FAC|RCV|FAC|20260101120000||ADT^A01^ADT_A01|M1|P|2.5.1\r"
        let strict = Parser(options: ParserOptions(lineTerminator: .strict))
        let beforeField = try strict.parse(msh + "NTE|1||see\n|more")
        #expect(beforeField["NTE-3"] == "see\n")
        let beforeTerminator = try strict.parse(msh + "NTE|1||see\n\r")
        #expect(beforeTerminator["NTE-3"] == "see\n")
    }

    // #43: one message, then the same message inside a file and batch envelope.
    static let batchMSH = "MSH|^~\\&|SND|FAC|RCV|FAC|20260101120000||ADT^A01^ADT_A01|M1|P|2.5.1"
    static let batchLines = [batchMSH, "PID|1||X"]
    static let envelopeLines = ["FHS|^~\\&|SND", "BHS|^~\\&|SND", batchMSH, "PID|1||X", "BTS|1", "FTS|1"]

    static func isLineFeedError(_ body: () throws -> Void) -> Bool {
        do { try body() } catch ParseError.lineFeedAfterSegmentTerminator { return true } catch { return false }
        return false
    }

    @Test("#43: under .strict the batch parsers reject a line feed standing as a segment terminator",
          arguments: ["\n", "\r\n"], [batchLines, envelopeLines])
    func batchParsersRejectLineFeeds(ending: String, lines: [String]) throws {
        let wire = lines.joined(separator: ending) + ending
        let strict = ParserOptions(lineTerminator: .strict)
        #expect(Self.isLineFeedError { _ = try BatchParser(options: strict).parse(wire) })
        #expect(Self.isLineFeedError { _ = try BatchParser(options: strict).parse(Data(wire.utf8)) })
        #expect(Self.isLineFeedError {
            var parser = StreamingBatchParser(options: strict)
            _ = try parser.feed(Data(wire.utf8))
            _ = try parser.finish()
        })
        // Under .lenient, the default, both still read the message.
        #expect(try BatchParser().parse(wire).allMessages.first?.segments.count == 2)
        var lenient = StreamingBatchParser()
        let messages = try lenient.feed(Data(wire.utf8)) + lenient.finish()
        #expect(messages.first?.segments.count == 2)
    }

    @Test("#43: under .strict the batch parsers keep a line feed that is data, and reject one ending the input")
    func batchParsersKeepDataLineFeeds() throws {
        let strict = ParserOptions(lineTerminator: .strict)
        let wire = Self.envelopeLines.joined(separator: "\r").replacingOccurrences(of: "PID|1||X", with: "NTE|1||see\n|more") + "\r"
        #expect(try BatchParser(options: strict).parse(wire).allMessages.first?["NTE-3"] == "see\n")
        var parser = StreamingBatchParser(options: strict)
        let messages = try parser.feed(Data(wire.utf8)) + parser.finish()
        #expect(messages.first?["NTE-3"] == "see\n")

        // An envelope line is checked against its own separator and a message's lines against
        // the message's, so `ABC#` after a line feed is data in a `|` message under an FHS# file.
        let mixed = "FHS#^~\\&#SND\r" + Self.batchMSH + "\rNTE|1||a\nABC#x\r"
        #expect(try BatchParser(options: strict).parse(mixed).allMessages.first?["NTE-3"] == "a\nABC#x")

        // A marker line with line feed endings is rejected, and the message before it survives.
        for tail in ["BTS|1\n", "BTS|1\nFTS|1\r"] {
            var stream = StreamingBatchParser(options: strict)
            let wire = Self.batchLines.joined(separator: "\r") + "\r" + tail
            #expect(Self.isLineFeedError { _ = try stream.feed(Data(wire.utf8)) + stream.finish() }, "\(tail.debugDescription)")
            #expect(try stream.finish().first?.segments.count == 2, "\(tail.debugDescription)")
        }

        let unterminated = Self.batchLines.joined(separator: "\r") + "\n"   // `Parser` throws here too
        #expect(Self.isLineFeedError { _ = try Parser(options: strict).parse(unterminated) })
        #expect(Self.isLineFeedError { _ = try BatchParser(options: strict).parse(unterminated) })
        #expect(Self.isLineFeedError {
            var parser = StreamingBatchParser(options: strict)
            _ = try parser.feed(Data(unterminated.utf8))
            _ = try parser.finish()
        })
    }

    @Test("P00 S1-3: under .lenient the same CRLF message parses into its segments")
    func lenientSplitsCRLF() throws {
        let message = try Parser().parse(Self.crlf)
        #expect(message.segments.map(\.segmentID) == ["MSH", "PID"])
        #expect(message["PID-3"] == "X")
    }

    @Test("P00 S1-1: a blank line between segments is dropped (a documented exception)")
    func blankLineDropped() throws {
        let message = try Parser().parse(Self.body + "\r\rNTE|1\r")
        #expect(message.serialize() == Data((Self.body + "\rNTE|1\r").utf8))
    }

    // MARK: - S1-2 the truncation character in MSH-2

    static func wire(msh2: String, version: String) -> String {
        "MSH|\(msh2)|SND|FAC|RCV|FAC|20260101120000||ADT^A01^ADT_A01|M1|P|\(version)\r"
            + "PID|1||SYN-1^^^FAC^MR||Synthetic^Pat\r"
    }

    static func msh2Issues(_ report: ValidationReport) -> [ValidationIssue] {
        report.issues.filter { $0.location.segmentID == "MSH" && $0.location.fieldIndex == 2 }
    }

    @Test("P00 S1-2: a five-character MSH-2 parses, keeps its literal and round-trips",
          arguments: ["2.7.1", "2.8.2"])
    func truncationCharacterRoundTrips(_ version: String) throws {
        let wire = Self.wire(msh2: "^~\\&#", version: version)
        let message = try Parser().parse(wire)
        #expect(message["MSH-2"] == "^~\\&#")
        #expect(message["MSH-3"] == "SND")
        #expect(message.encodingCharacters == .default)
        #expect(message.serialize() == Data(wire.utf8))
    }

    @Test("P00 S1-2: \\P\\ passes through verbatim")
    func truncationEscapePassesThrough() throws {
        let wire = Self.wire(msh2: "^~\\&#", version: "2.8.2") + "NTE|1||cut short\\P\\\r"
        let message = try Parser().parse(wire)
        #expect(message["NTE-3"] == "cut short\\P\\")
        #expect(message.serialize() == Data(wire.utf8))
    }

    @Test("P00 S1-2: v2.7.1 and v2.8.2 print MSH-2 LEN 4..5, so five characters are clean",
          arguments: ["2.7.1", "2.8.2"])
    func fiveCharactersCleanFromV27(_ version: String) throws {
        let report = Validator(options: .strict).validate(try Parser().parse(Self.wire(msh2: "^~\\&#", version: version)))
        #expect(Self.msh2Issues(report).isEmpty)
    }

    @Test("P00 S1-2: v2.3 to v2.6 print MSH-2 LEN 4, so a fifth character is a length warning",
          arguments: ["2.3", "2.3.1", "2.4", "2.5.1", "2.6"])
    func fifthCharacterBeforeV27(_ version: String) throws {
        let report = Validator().validate(try Parser().parse(Self.wire(msh2: "^~\\&#", version: version)))
        let found = Self.msh2Issues(report)
        #expect(found.map(\.code) == [.fieldLengthOutOfRange(length: "4", actual: 5)])
        #expect(found.first?.severity == .warning)
    }

    @Test("P00 S1-2: a four-character MSH-2 stays clean on every version",
          arguments: ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.7.1", "2.8.2"])
    func fourCharactersClean(_ version: String) throws {
        let report = Validator(options: .strict).validate(try Parser().parse(Self.wire(msh2: "^~\\&", version: version)))
        #expect(Self.msh2Issues(report).isEmpty)
    }

    @Test("P00 S1-2: a fifth character repeating a delimiter is rejected")
    func duplicateFifthCharacter() {
        #expect(throws: ParseError.invalidMSH(reason: "encoding characters not distinct")) {
            try Parser().parse(Self.wire(msh2: "^~\\&^", version: "2.8.2"))
        }
    }

    @Test("P00 S1-2: six characters before the field separator are rejected")
    func sixCharacters() {
        #expect(throws: ParseError.invalidMSH(reason: "MSH-2 not followed by field separator")) {
            try Parser().parse(Self.wire(msh2: "^~\\&#X", version: "2.8.2"))
        }
    }

    @Test("P00 S3: a parsed value whose escapes decode to a run holding a delimiter or CR is written back as read",
          arguments: ["NTE|1||\\E\\a\\F\\b\\E\\", "NTE|1||\\E\\x\\X0D\\ZZZ\\F\\evil\\E\\"])
    func escapedRunsRoundTrip(_ line: String) throws {
        let wire = "MSH|^~\\&|SND|FAC|RCV|FAC|20260101120000||ADT^A01^ADT_A01|M1|P|2.5.1\r" + line + "\r"
        let message = try Parser().parse(wire)
        #expect(message.serialize() == Data(wire.utf8))
        let back = try Parser().parse(message.serialize())
        #expect(back.segments.count == 2)
        #expect(back["NTE-3"] == message["NTE-3"])
    }
}
