// EscapeWireTextTests.swift
// #13: a parsed value keeps the wire text it was read from. The serialiser writes it back,
// and the AU escape prohibition and the length check read it, while it is still a faithful
// encoding under the message's delimiters. Equality stays on the decoded value.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Escape wire text")
struct EscapeWireTextTests {
    static let msh = #"MSH|^~\&|APP|FAC|||20260101||ADT^A01^ADT_A01|C1|P|2.5.1"#

    /// An ADT whose NTE-3 values are `notes`, one NTE each.
    static func wire(_ notes: String...) -> String {
        msh + "\r" + notes.enumerated().map { "NTE|\($0.offset + 1)||\($0.element)\r" }.joined()
    }

    static func nte3(_ message: Message, _ occurrence: Int = 1) throws -> Subcomponent {
        let nte = message.segments.filter { $0.segmentID == "NTE" }[occurrence - 1]
        return try #require(nte.field(3)?.first?.components.first?.subcomponents.first)
    }

    @Test("A parsed value is written back exactly as it was read", arguments: [
        #"C:\E\Users\E\me"#,
        #"\X0D\\X0A\"#,
        #"\X41\"#,
        #"\XZZ\"#,
        #"\H\240\N\"#,
        #"\Z1\"#,
        #"\.br\\.in+4\"#,
        #"a\E\b\F\c\Z9\d\X41\"#,
        // A lone escape character with no closing one is kept literally by the decoder.
        #"a\b"#,
        #"\"#,
    ])
    func roundTrip(_ value: String) throws {
        let wire = Self.wire(value)
        #expect(try Parser().parse(wire).serialize() == Data(wire.utf8))
    }

    @Test("Values that decode alike are equal and hash alike")
    func equalityOnValue() throws {
        let hex = try Parser().parse(Self.wire(#"\X41\"#))
        let plain = try Parser().parse(Self.wire("A"))
        #expect(hex == plain)
        #expect(hex.hashValue == plain.hashValue)
        #expect(try Self.nte3(hex).value == "A")
    }

    @Test("Wire text is used only while it is faithful under the target delimiters")
    func wireFormTrust() throws {
        let message = try Parser().parse(Self.wire(#"C:\E\Users\E\me"#, #"a#b\F\c"#))
        let backslash = try Self.nte3(message, 1)
        let hash = try Self.nte3(message, 2)
        let standard = message.encodingCharacters
        #expect(EscapeSequences.wireForm(of: backslash, encoding: standard) == #"C:\E\Users\E\me"#)
        // Escape character `#`: the wire text no longer decodes to the value, so the value is encoded.
        let hashEscape = EncodingCharacters(fieldSeparator: "|", componentSeparator: "^",
                                            repetitionSeparator: "~", escapeCharacter: "#",
                                            subcomponentSeparator: "&")
        #expect(EscapeSequences.wireForm(of: backslash, encoding: hashEscape) == #"C:\Users\me"#)
        // Component separator `#`: the wire text holds it literally, so the value is encoded.
        let hashComponent = EncodingCharacters(fieldSeparator: "|", componentSeparator: "#",
                                               repetitionSeparator: "~", escapeCharacter: "\\",
                                               subcomponentSeparator: "&")
        #expect(EscapeSequences.wireForm(of: hash, encoding: hashComponent) == #"a\S\b\F\c"#)
        // A value built in code has no wire text.
        #expect(EscapeSequences.wireForm(of: Subcomponent("a|b"), encoding: standard) == #"a\F\b"#)
    }

    @Test("An edit leaves the wire text of every node it does not touch")
    func editKeepsNeighbours() throws {
        var message = try Parser().parse(Self.wire(#"C:\E\Users\E\me"#, "second"))
        try message.set("x", at: Path("NTE[2]-3"))
        try message.set("y", at: Path("NTE[1]-3.2"))
        let expected = Self.wire(#"C:\E\Users\E\me^y"#, "x")
        #expect(message.serialize() == Data(expected.utf8))
    }

    /// The AU escape-prohibition findings (ADRM-prose:P-4) for an AU ORU whose OBX-5 is `text`.
    static func auEscapeFindings(_ text: String) throws -> [String] {
        let wire = #"MSH|^~\&|LAB|FAC|HOSP|FAC|||ORU^R01|MSG1|P|2.5.1"# + "\r"
            + "PID|1||999999^^^HOSP^MR\r"
            + "OBX|1|FT|8251-1^Notes^LN||\(text)||||||F\r"
        let report = Validator(locale: .auLocalisation).validate(try Parser(locale: .auLocalisation).parse(wire))
        return report.errors.compactMap { $0.message.contains("ADRM-prose:P-4") ? $0.message : nil }
    }

    @Test("Under the AU locale escaped text that spells a prohibited escape is not reported", arguments: [
        #"a\E\C2842\E\b"#, #"a\E\Cx\E\b"#, #"a\E\M2442\E\b"#, #"a\E\X0D\E\b"#,
    ])
    func auEscapedTextClean(_ text: String) throws {
        #expect(try Self.auEscapeFindings(text).isEmpty)
    }

    @Test("Under the AU locale every prohibited escape on the wire is reported", arguments: [
        #"caf\XC3A9\"#, #"a\X0D\b"#, #"a\C2842\b"#, #"a\M2442\b"#,
    ])
    func auWireEscapesReported(_ text: String) throws {
        #expect(try Self.auEscapeFindings(text).count == 1)
    }

    @Test("Under the AU locale a raw control character is reported as the \\X..\\ it would be written as")
    func auRawControlReportedAsHex() throws {
        // No field may hold a raw TAB; it is written \X09\, and that is what the check reads.
        #expect(try Self.auEscapeFindings("a\tb").count == 1)
    }

    @Test("Length counts a non-canonical escape as written (v2.8.2 section 2.7)")
    func lengthAsWritten() throws {
        for (value, expected) in [(#"\X41\"#, 3), (#"\X0D\\X0A\"#, 6), (#"\X0D0A\"#, 5)] {
            let message = try Parser().parse(Self.wire(value))
            let nte = try #require(message.segments.first { $0.segmentID == "NTE" })
            let repetition = try #require(nte.field(3)?.repetitions.first)
            #expect(Validator.occupiedLength(repetition, encoding: message.encodingCharacters) == expected, "\(value)")
        }
    }

    @Test("The accepted part of a primitive field keeps its wire text when measured")
    func acceptedContentMeasuredAsWritten() throws {
        // v2.3.1 MSH-10 is ST, LEN 20. Eighteen X and \X41\ is 21 characters as written; the
        // extra component is reported separately, and the length is that of the accepted part.
        let controlID = String(repeating: "X", count: 18) + #"\X41\^extra"#
        let wire = #"MSH|^~\&|APP|FAC|||20260101||ADT^A01|"# + controlID + "|P|2.3.1\r"
        let issues = Validator().validate(try Parser().parse(wire)).issues
            .filter { $0.location.segmentID == "MSH" && $0.location.fieldIndex == 10 }
        #expect(issues.contains { $0.code == .fieldLengthOutOfRange(length: "20", actual: 21) })
    }
}

// Wire text is trusted only under the escape character it was read under (#13).
extension EscapeWireTextTests {
    static let std = EncodingCharacters.default

    /// The NTE segment parsed from `wire`.
    static func parsedNTE(_ wire: String) throws -> Segment {
        try #require(Parser().parse(wire).segments.first { $0.segmentID == "NTE" })
    }

    /// The parsed NTE copied into a bare message under `encoding`, serialised.
    static func copied(_ nte: Segment, under encoding: EncodingCharacters) -> String {
        let copy = Message(version: .v2_5_1, encodingCharacters: encoding, segments: [nte])
        return String(decoding: copy.serialize(), as: UTF8.self)
    }

    @Test("A copy under another escape character, or other delimiters, is encoded afresh", arguments: [
        // parsed under `\`, copied under escape `#`
        (#"a#b#c\H\x\N\"#, "|^~#&", #"NTE|1||a#E#b#E#c\H\x\N\"# + "\r"),
        (#"p#q\Z1\"#, "|^~#&", #"NTE|1||p#E#q\Z1\"# + "\r"),
        // parsed under `\`, copied under component separator `#`
        (#"a#b\F\c"#, "|#~\\&", #"NTE|1||a\S\b\F\c"# + "\r"),
        // the same encoding as parsed
        (#"C:\E\Users\E\me"#, #"|^~\&"#, #"NTE|1||C:\E\Users\E\me"# + "\r"),
    ])
    func copyUnderOtherEncoding(_ row: (value: String, enc: String, expected: String)) throws {
        let nte = try Self.parsedNTE(Self.wire(row.value))
        let chars = Array(row.enc)
        let enc = EncodingCharacters(fieldSeparator: chars[0], componentSeparator: chars[1],
                                     repetitionSeparator: chars[2], escapeCharacter: chars[3],
                                     subcomponentSeparator: chars[4])
        #expect(Self.copied(nte, under: enc) == row.expected)
    }

    @Test("Parsed under escape #, copied under backslash: the backslash runs are escaped")
    func copyFromHashEscape() throws {
        let wire = #"MSH|^~#&|APP|FAC|||20260101||ADT^A01^ADT_A01|C1|P|2.5.1"# + "\r"
            + #"NTE|1||C:\scans\a.jpg#.br#"# + "\r"
        let nte = try Self.parsedNTE(wire)
        #expect(Self.copied(nte, under: Self.std) == #"NTE|1||C:\E\scans\E\a.jpg#.br#"# + "\r")
    }

    @Test("MSH-18 encodability reads the text that will be written")
    func asciiEditKeepsEscapedText() throws {
        var m = try Parser().parse(Self.wire(#"caf\XC3A9\"#))
        try m.set("ASCII", at: Path("MSH-18"))
        let bytes = m.serialize()
        #expect(bytes.allSatisfy { $0 < 0x80 })
        #expect(String(decoding: bytes, as: UTF8.self).contains(#"caf\XC3A9\"#))

        var built = try Parser().parse(Self.wire("x"))
        try built.set("caf\u{E9}", at: Path("NTE-3"))
        #expect(throws: MessageEditError.characterNotEncodable(.ascii)) {
            try built.set("ASCII", at: Path("MSH-18"))
        }
    }

    @Test("The acknowledgement echoes an escaped MSH-10 as written")
    func ackEchoesEscapedControlID() throws {
        let wire = #"MSH|^~\&|APP|FAC|||20260101||ADT^A01^ADT_A01|C\X41\1|P|2.5.1"# + "\r"
        let ack = try MessageBuilder.acknowledgment(to: Parser().parse(wire), code: .applicationAccept,
                                                    messageControlID: "ACK1", dateTime: "20260101")
        #expect(String(decoding: ack.serialize(), as: UTF8.self).contains(#"MSA|AA|C\X41\1"#))
    }
}
