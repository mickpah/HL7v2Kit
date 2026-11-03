// DeclaredCharacterSetTests.swift
// #16: text the declared character set cannot encode. Both parse paths refuse it, a message
// built in code that holds it draws characterNotEncodable, and serialize() falls back to UTF-8.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Declared character set")
struct DeclaredCharacterSetTests {
    static func adt(_ msh18: String, nte: String) -> String {
        #"MSH|^~\&|APP|FAC|||20260101||ADT^A01^ADT_A01|C1|P|2.5.1||||||"# + msh18 + "\rNTE|1||\(nte)\r"
    }

    static func isCharacterSetIssue(_ issue: ValidationIssue) -> Bool {
        if case .characterNotEncodable = issue.code { return true }
        return false
    }

    @Test("Text the declared character set cannot encode is refused from a String", arguments: [
        ("ASCII", "Caf\u{E9}", "ASCII"),
        ("US-ASCII", "Caf\u{E9}", "ASCII"),
        ("8859/1", "Caf\u{E9} \u{20AC}5", "8859/1"),
    ])
    func stringRefused(_ row: (msh18: String, nte: String, declared: String)) {
        #expect(throws: ParseError.unsupportedCharacterEncoding(declared: row.declared)) {
            try Parser().parse(Self.adt(row.msh18, nte: row.nte))
        }
    }

    @Test("Text that fits is accepted, and an empty MSH-18 accepts any text (read as UTF-8)")
    func stringAccepted() throws {
        let wire = Self.adt("8859/1", nte: "Caf\u{E9}")
        let latin = try Parser().parse(wire)
        #expect(latin.characterEncoding == .iso8859_1)
        let latinBytes = try #require(CharacterEncoding.iso8859_1.encode(wire))
        #expect(latin.serialize() == latinBytes)
        #expect(try Parser().parse(Self.adt("", nte: "\u{20AC}5")).characterEncoding == .utf8)
    }

    @Test("A batch whose second message breaks its own MSH-18 is refused")
    func batchRefused() {
        let batch = Self.adt("", nte: "first") + Self.adt("ASCII", nte: "Caf\u{E9}")
        #expect(throws: ParseError.unsupportedCharacterEncoding(declared: "ASCII")) {
            try BatchParser().parse(batch)
        }
    }

    @Test("Bytes the declared character set cannot decode still throw", arguments: [
        [UInt8(0xE9)], [UInt8(0xC3), 0xA9],
    ])
    func bytesRefused(_ high: [UInt8]) {
        var bytes = Data(Self.adt("ASCII", nte: "Caf").utf8)
        bytes.removeLast()
        bytes.append(contentsOf: high + [0x0D])
        #expect(throws: ParseError.unsupportedCharacterEncoding(declared: "ASCII")) {
            try Parser().parse(bytes)
        }
    }

    /// An ADT built in code with PID-5 `Renée`, in `encoding`.
    static func built(_ encoding: CharacterEncoding) throws -> Message {
        var builder = MessageBuilder(version: .v2_5_1, characterEncoding: encoding)
        builder.msh(messageType: ("ADT", "A01"), messageControlID: "C1")
        builder.appendSegment(id: "PID", fields: [
            .scalar("1"), .scalar(""), .scalar(""), .scalar(""), .scalar("Ren\u{E9}e"),
        ])
        return try builder.build()
    }

    @Test("A built message holding text its character set cannot encode fails validation", arguments: [
        ValidationOptions.default, .strict, .lenient,
    ])
    func builtReported(_ options: ValidationOptions) throws {
        let issues = Validator(options: options).validate(try Self.built(.ascii)).issues
            .filter(Self.isCharacterSetIssue)
        #expect(issues.count == 1)
        #expect(issues.first?.code == .characterNotEncodable(declared: "ASCII"))
        #expect(issues.first?.severity == .error)
        #expect(issues.first?.location == IssueLocation(segmentID: "PID", segmentIndex: 1, fieldIndex: 5))
    }

    @Test("The same text in UTF-8 draws nothing, and the ASCII message is written as UTF-8")
    func builtFallback() throws {
        #expect(!Validator().validate(try Self.built(.utf8)).issues.contains(where: Self.isCharacterSetIssue))
        let bytes = try Self.built(.ascii).serialize()
        // The documented fallback: the whole message is written as UTF-8.
        #expect(String(decoding: bytes, as: UTF8.self).contains("PID|1||||Ren\u{E9}e"))
        #expect(!bytes.allSatisfy { $0 < 0x80 })
    }

    @Test("An MSH-18 of the HL7 null reads as UTF-8 on both parse paths (#17)",
          arguments: ["\"\"", "\"\"~ISO IR87"])
    func nullReadsAsUTF8(_ msh18: String) throws {
        let wire = Self.adt(msh18, nte: "Caf\u{E9}")
        #expect(try Parser().parse(wire).characterEncoding == .utf8)
        #expect(try Parser().parse(Data(wire.utf8)).characterEncoding == .utf8)
        #expect(try CharacterEncoding.detect(in: wire) == .utf8)
    }

    @Test("Clearing MSH-18, or setting it to the HL7 null, leaves the message UTF-8 (#17)")
    func editToNull() throws {
        var cleared = try Parser().parse(Self.adt("8859/1", nte: "Caf\u{E9}"))
        try cleared.clear(at: Path("MSH-18"))
        #expect(cleared.characterEncoding == .utf8)
        #expect(cleared["MSH-18"] == "")

        var nulled = try Parser().parse(Self.adt("8859/1", nte: "Caf\u{E9}"))
        try nulled.set("\"\"", at: Path("MSH-18"))
        #expect(nulled.characterEncoding == .utf8)
    }

    @Test("A null MSH-18 draws no issue at MSH-18 (#17)")
    func nullValidates() throws {
        let message = try Parser().parse(Self.adt("\"\"", nte: "Caf\u{E9}"))
        let atMSH18 = Validator().validate(message).issues.filter {
            $0.location.segmentID == "MSH" && $0.location.fieldIndex == 18
        }
        #expect(atMSH18.isEmpty)
    }
}
