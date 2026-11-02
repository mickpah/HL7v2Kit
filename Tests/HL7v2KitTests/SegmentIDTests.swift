// SegmentIDTests.swift
// #11: outside MSH, BHS and FHS a segment ID runs to the first field separator, so a line comes
// back as written, and the validator reports an ID that is not three characters (1014; v2.5.1
// section 2.5.2).

import Foundation
import Testing
import HL7v2Kit

@Suite("Segment ID")
struct SegmentIDTests {
    static let msh = #"MSH|^~\&|APP|FAC|||20260101||ADT^A01^ADT_A01|C1|P|2.5.1"#

    static func wire(_ line: String) -> String { msh + "\r" + line + "\r" }

    @Test("The ID runs to the first field separator and the line round-trips", arguments: [
        ("ZABC|1", "ZABC", ["1"]),
        ("AB|x", "AB", ["x"]),
        ("PIDX|1", "PIDX", ["1"]),
        ("|ab", "", ["ab"]),
        ("ZAU|1|2", "ZAU", ["1", "2"]),
    ])
    func idRunsToSeparator(_ row: (line: String, id: String, fields: [String])) throws {
        let wire = Self.wire(row.line)
        let message = try Parser().parse(wire)
        let segment = message.segments[1]
        #expect(segment.segmentID == row.id)
        #expect(segment.fields.dropFirst().map { $0.stringValue ?? "" } == row.fields)
        #expect(message.serialize() == Data(wire.utf8))
    }

    @Test("With a letter as the field separator a three-character ID holding it stays whole")
    func alphanumericSeparator() throws {
        let wire = #"MSHX^~\&XAPPXFACXXX20260101XXADT^A01^ADT_A01XC1XPX2.5.1"# + "\rTXAX1X2\r"
        let message = try Parser().parse(wire)
        let segment = message.segments[1]
        #expect(segment.segmentID == "TXA")
        #expect(segment.fields.dropFirst().map { $0.stringValue ?? "" } == ["1", "2"])
        #expect(message.serialize() == Data(wire.utf8))
        #expect(!Validator().validate(message).issues.contains { $0.code == .segmentIDMalformed })
    }

    @Test("A line whose ID is not a known one stays unknown, not typed")
    func fourCharacterIDIsUnknown() throws {
        let message = try Parser().parse(Self.wire("PIDX|1"))
        guard case .unknown = message.segments[1] else {
            Issue.record("PIDX was hydrated as a typed segment")
            return
        }
        #expect(message.firstSegment(PID.self) == nil)
    }

    @Test("With allowUnknownSegments off a four-character ID throws under its whole ID")
    func strictParseThrows() {
        #expect(throws: ParseError.unknownSegment(id: "ZABC", position: 2)) {
            try Parser(options: ParserOptions(allowUnknownSegments: false)).parse(Self.wire("ZABC|1"))
        }
    }

    @Test("A line under three characters still throws")
    func shortLineThrows() {
        #expect(throws: ParseError.invalidMSH(reason: "segment too short: 'AB'")) {
            try Parser().parse(Self.wire("AB"))
        }
    }

    @Test("An ID that is not three characters draws one 1014 and no Z-segment or grammar notice",
          arguments: ["ZABC", "PIDX", "AB"])
    func malformedIDReported(_ id: String) throws {
        let message = try Parser().parse(Self.wire(id + "|1"))
        let issues = Validator().validate(message).issues
        let atSegment = issues.filter { $0.location.segmentID == id }.map(\.code.number)
        #expect(atSegment.filter { $0 == 1014 }.count == 1)
        #expect(!atSegment.contains(1002) && !atSegment.contains(1004))
        let issue = try #require(issues.first { $0.code == .segmentIDMalformed })
        #expect(issue.severity == .error)
        #expect(issue.location.segmentIndex == 1)
        #expect(issue.message == "Segment ID '\(id)' is not three characters (v2.5.1 section 2.5.2)")
    }

    @Test("A three-character ID draws no 1014")
    func threeCharacterIDNotReported() throws {
        let message = try Parser().parse(Self.wire("ZAU|1"))
        #expect(!Validator().validate(message).issues.contains { $0.code == .segmentIDMalformed })
    }

    @Test("A message built in code with a four-character ID draws 1014")
    func builtMessageReported() throws {
        let parsed = try Parser().parse(Self.wire("ZAU|1"))
        let built = Message(
            version: parsed.version, encodingCharacters: parsed.encodingCharacters,
            segments: [parsed.segments[0],
                       .unknown(UnknownSegment(segmentID: "ABCD", fields: [Field(repetitions: []), .scalar("1")]))])
        let issues = Validator().validate(built).issues.filter { $0.code == .segmentIDMalformed }
        #expect(issues.map(\.location.segmentID) == ["ABCD"])
    }
}
