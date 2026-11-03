import Testing
import Foundation
@testable import HL7v2Kit

// `Character ==` compares by canonical equivalence, so `é` as U+00E9 equals `é` as `e` U+0301, and
// U+212A equals `K`. On the wire those are different bytes: only the delimiter's own spelling is a
// delimiter, or a value holding the other one would be split and written back changed.
@Suite("A delimiter matches only its own spelling")
struct DelimiterSpellingTests {
    static let composed = "\u{E9}"
    static let decomposed = "e\u{301}"

    static func message(separator: String = "|", encoding: String = #"^~\&"#, body: String) -> String {
        ["MSH", encoding, "APP", "FAC", "", "", "20260101", "", "ADT", "C1", "P", "2.5.1"]
            .joined(separator: separator) + "\r" + body + "\r"
    }

    static let fieldSeparatorTwins: [(separator: String, twin: String)] = [
        (decomposed, composed), (composed, decomposed),
        (";", "\u{37E}"), ("`", "\u{1FEF}"), ("K", "\u{212A}"),
    ]

    @Test("A value holding the other spelling of the field separator stays one value",
          arguments: fieldSeparatorTwins)
    func fieldSeparator(_ row: (separator: String, twin: String)) throws {
        let value = "\(row.twin)A\(row.twin)B"
        let wire = Self.message(separator: row.separator,
                                body: ["PID", "1", value].joined(separator: row.separator))
        for message in [try Parser().parse(wire), try Parser().parse(Data(wire.utf8))] {
            #expect(message["PID-2"] == value)
            #expect(message.serialize() == Data(wire.utf8))
        }
    }

    @Test("A value holding the other spelling of an encoding character stays one value",
          arguments: ["e\u{301}~\\&", "^e\u{301}\\&", "^~e\u{301}&", "^~\\e\u{301}"])
    func encodingCharacter(_ encoding: String) throws {
        let value = "a\(Self.composed)b\(Self.composed)c"
        let wire = Self.message(encoding: encoding, body: "PID|1|\(value)")
        let message = try Parser().parse(wire)
        #expect(message["PID-2"] == value)
        #expect(message.serialize() == Data(wire.utf8))
        #expect(!Validator().validate(message).issues.contains { $0.code == .escapeSequenceUndefined })
    }

    @Test("The delimiter's own spelling still delimits and still escapes")
    func ownSpelling() throws {
        let separator = Self.decomposed
        let wire = Self.message(encoding: "^~\(separator)&", body: "PID|1|a\(separator)F\(separator)b")
        let message = try Parser().parse(wire)
        #expect(message["PID-2"] == "a|b")
        #expect(message.serialize() == Data(wire.utf8))

        let split = try Parser().parse(Self.message(separator: separator,
                                                    body: "PID\(separator)1\(separator)x\(separator)y"))
        #expect(split["PID-2"] == "x")
        #expect(split["PID-3"] == "y")
    }

    @Test("A written value holding the other spelling is copied; one holding the delimiter is escaped")
    func written() throws {
        let separator = Self.decomposed
        let wire = Self.message(separator: separator, body: "PID\(separator)1\(separator)x")
        var message = try Parser().parse(wire)
        try message.set(Self.composed, at: Path("PID-2"))
        #expect(message.serialize() == Data(Self.message(
            separator: separator, body: "PID\(separator)1\(separator)\(Self.composed)").utf8))
        try message.set(separator, at: Path("PID-2"))
        #expect(message.serialize() == Data(Self.message(
            separator: separator, body: #"PID\#(separator)1\#(separator)\F\"#).utf8))
    }

    @Test("Length counts the other spelling of the escape character as a character")
    func encodedLength() {
        let encoding = EncodingCharacters(fieldSeparator: "|", componentSeparator: "^", repetitionSeparator: "~",
                                          escapeCharacter: Character(Self.decomposed), subcomponentSeparator: "&")
        #expect(Validator.encodedLength(Subcomponent("a\(Self.composed)b", wire: nil), encoding: encoding) == 3)
    }

    @Test("An AU escape prohibition does not read the other spelling of the escape character as one")
    func prohibitedEscape() throws {
        func findings(_ text: String) throws -> [ValidationIssue] {
            let wire = "MSH|^~\(Self.decomposed)&|LAB|FAC|HOSP|FAC|||ORU^R01|MSG1|P|2.5.1\r"
                + "OBX|1|FT|8251-1^Notes^LN||\(text)||||||F\r"
            return Validator(locale: .auLocalisation).validate(try Parser(locale: .auLocalisation).parse(wire))
                .errors.filter { $0.message.contains("ADRM-prose:P-4") }
        }
        #expect(try findings("\(Self.composed)X41\(Self.composed)").isEmpty)
        #expect(try !findings("\(Self.decomposed)X41\(Self.decomposed)").isEmpty)
    }

    @Test("The header lines read their separator by its spelling")
    func headerLines() throws {
        let separator = Self.decomposed
        let twin = Self.composed
        // A later line whose fourth character is the other spelling is an ordinary line.
        let later = Self.message(separator: separator, body: "MSH\(twin)1")
        let laterMessage = try Parser().parse(later)
        #expect(laterMessage.segments.map(\.segmentID) == ["MSH", "MSH\(twin)1"])
        #expect(laterMessage.serialize() == Data(later.utf8))

        // MSH-2 must be followed by the separator as MSH-1 spells it.
        #expect(throws: ParseError.invalidMSH(reason: "MSH-2 not followed by field separator")) {
            try Parser().parse("MSH\(separator)^~\\&\(twin)APP\r")
        }
        #expect(Parser.headerDelimiters("BHS\(separator)^~\\&\(separator)APP")?.fieldSeparator
            == Character(separator))
        #expect(Parser.headerDelimiters("BHS\(separator)^~\\&\(twin)APP") == nil)
    }

    @Test("Two spellings of one character are still not distinct delimiters")
    func distinctness() throws {
        let separator = Self.decomposed
        let twin = Self.composed
        #expect(throws: ParseError.invalidMSH(reason: "encoding characters not distinct")) {
            try Parser().parse("MSH\(separator)\(twin)~\\&\(separator)APP\r")
        }
        // A truncation character that is the field separator under another spelling.
        #expect(throws: ParseError.invalidMSH(reason: "encoding characters not distinct")) {
            try Parser().parse("MSH\(separator)^~\\&\(twin)\(separator)APP\r")
        }
        #expect(Parser.headerDelimiters("BHS\(separator)^~\\&\(twin)\(separator)APP") == nil)
    }

    @Test("BatchParser reads the separator in force by its spelling")
    func batchTrailer() throws {
        let separator = Self.decomposed
        let header = Self.message(separator: separator, body: "").dropLast()
        let wire = header + "BTS\(Self.composed)1\rBTS\(separator)1\r"
        let file = try BatchParser().parse(String(wire))
        #expect(file.batches.map(\.trailer) == ["BTS\(separator)1"])
        #expect(file.allMessages.first?.segments.map(\.segmentID) == ["MSH", "BTS\(Self.composed)1"])
    }

    @Test("MSH-18 is found past a value holding the other spelling of the separator")
    func characterSetProbe() throws {
        let separator = Self.decomposed
        let parts = ["MSH", #"^~\&"#, "A\(Self.composed)B"] + Array(repeating: "", count: 14) + ["8859/1"]
        let declared = try CharacterEncoding.detect(in: parts.joined(separator: separator) + "\r")
        #expect(declared == .iso8859_1)
    }
}
