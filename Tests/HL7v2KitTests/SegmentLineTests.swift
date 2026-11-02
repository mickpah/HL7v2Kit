// SegmentLineTests.swift
// EG-1: a segment line comes back as written. A line with no field separator keeps no field, the
// ID follows the kind of field separator (v2.5.1 sections 2.5.2 and 2.5.4), and a later line
// starting MSH is a header only when its fourth character is the message's field separator.

import Foundation
import Testing
import HL7v2Kit

@Suite("Segment lines")
struct SegmentLineTests {
    static func msh(separator: String = "|") -> String {
        ["MSH", #"^~\&"#, "APP", "FAC", "", "", "20260101", "", "ADT^A01^ADT_A01", "C1", "P", "2.5.1"]
            .joined(separator: separator)
    }

    static func wire(_ line: String, separator: String = "|") -> String {
        msh(separator: separator) + "\r" + line + "\r"
    }

    @Test("A line with no field separator keeps no field and comes back as written", arguments: [
        ("ZZZ", "ZZZ", 1), ("ZABC", "ZABC", 1), ("BHS", "BHS", 1), ("FHS", "FHS", 1), ("ZZZ|", "ZZZ", 2),
    ])
    func fieldlessLine(_ row: (line: String, id: String, fields: Int)) throws {
        let wire = Self.wire(row.line)
        let message = try Parser().parse(wire)
        #expect(message.segments[1].segmentID == row.id)
        #expect(message.segments[1].fields.count == row.fields)
        #expect(message.serialize() == Data(wire.utf8))
    }

    @Test("A built segment holding only its ID is written as its ID; MSH keeps MSH-1 and MSH-2")
    func builtFieldlessSegment() {
        let bare = ["MSH", "BHS", "FHS", "ZAU"].map {
            Segment.unknown(UnknownSegment(segmentID: $0, fields: [Field(repetitions: [])]))
        }
        let built = Message(version: .v2_5_1, encodingCharacters: .default, segments: bare)
        #expect(built.serialize() == Data("MSH|^~\\&\rBHS\rFHS\rZAU\r".utf8))
    }

    static let idRows: [(separator: String, line: String, id: String, fields: [String])] = [
        ("|", "A|B|c", "A", ["B", "c"]),
        ("|", "A|B", "A", ["B"]),
        ("X", "TXA", "TXA", []),
        ("X", "TXAX1X2", "TXA", ["1", "2"]),
        ("X", "ZABCX1", "ZABC", ["1"]),
        ("9", "ZA9", "ZA9", []),
        ("9", "ZA991", "ZA9", ["1"]),
        ("é", "AéBé1", "A", ["B", "1"]),
    ]

    @Test("The ID is the text before the first separator, or three characters when a letter or digit separates",
          arguments: idRows)
    func idFollowsTheSeparator(_ row: (separator: String, line: String, id: String, fields: [String])) throws {
        let wire = Self.wire(row.line, separator: row.separator)
        let message = try Parser().parse(wire)
        let segment = message.segments[1]
        #expect(segment.segmentID == row.id)
        #expect(segment.fields.dropFirst().map { $0.stringValue ?? "" } == row.fields)
        #expect(message.serialize() == Data(wire.utf8))
        let malformed = Validator().validate(message).issues.filter { $0.code == .segmentIDMalformed }
        #expect(malformed.map(\.location.segmentID) == (row.id.count == 3 ? [] : [row.id]))
    }

    @Test("A later line starting MSH whose fourth character is not the field separator is an ordinary line")
    func laterMSHLikeLine() throws {
        let wire = Self.wire("MSHX|1|2")
        let message = try Parser().parse(wire)
        let segment = message.segments[1]
        #expect(segment.segmentID == "MSHX")
        #expect(segment.fields.dropFirst().map { $0.stringValue ?? "" } == ["1", "2"])
        #expect(message.serialize() == Data(wire.utf8))
        let malformed = Validator().validate(message).issues.filter { $0.code == .segmentIDMalformed }
        #expect(malformed.map(\.location.segmentID) == ["MSHX"])
    }

    @Test("A later MSH line with the message's field separator is still a header")
    func laterMSHLine() throws {
        let wire = Self.wire(Self.msh())
        let message = try Parser().parse(wire)
        #expect(message.segments[1].segmentID == "MSH")
        #expect(message.segments[1].field(2)?.stringValue == #"^~\&"#)
        #expect(message.serialize() == Data(wire.utf8))
    }
}
