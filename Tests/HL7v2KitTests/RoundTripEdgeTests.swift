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

    @Test("P00 S1-1: a blank line between segments is dropped (a documented exception)")
    func blankLineDropped() throws {
        let message = try Parser().parse(Self.body + "\r\rNTE|1\r")
        #expect(message.serialize() == Data((Self.body + "\rNTE|1\r").utf8))
    }
}
