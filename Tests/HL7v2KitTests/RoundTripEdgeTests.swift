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

    // A recorded limitation, not a promise: the parser splits on Characters and "\r\n" is one
    // Character, so .strict does not end a segment at a CRLF. Fixing the parser flips this test.
    @Test("P00 S1: under .strict a CRLF is not a segment terminator, so the next line folds into the value")
    func strictCRLFFolds() throws {
        let wire = "MSH|^~\\&|SND|FAC|RCV|FAC|20260101120000||ADT^A01^ADT_A01|M1|P|2.5.1\r\n"
            + "PID|1||X\r"
        let message = try Parser(options: ParserOptions(lineTerminator: .strict)).parse(wire)
        #expect(message.segments.count == 1)
        #expect(message.serialize() == Data(wire.replacingOccurrences(of: "\r\n", with: "\\X0D0A\\").utf8))
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
}
