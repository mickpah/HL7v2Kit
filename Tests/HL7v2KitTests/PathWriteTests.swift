// PathWriteTests.swift
// P00 S3-1: path-addressed writes. Each case names the exact wire after the edit, so a
// test also proves nothing else moved.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Path-addressed write")
struct PathWriteTests {
    static let msh = "MSH|^~\\&|APP|FAC|||20260101||ADT^A01^ADT_A01|C1|P|2.5.1\r"
    static let pid = "PID|1||A1~B2^^^AU||DOE^JO"
    static let wire = msh + pid + "\rNTE|1||first\rNTE|2||second\r"

    /// The wire after `edit`, with `pid` in place of the PID line.
    static func expected(pid: String, nte1: String = "NTE|1||first", nte2: String = "NTE|2||second") -> String {
        msh + pid + "\r" + nte1 + "\r" + nte2 + "\r"
    }

    static func edited(_ edit: (inout Message) throws -> Void) throws -> String {
        var message = try Parser().parse(wire)
        try edit(&message)
        return String(decoding: message.serialize(), as: UTF8.self)
    }

    @Test("set writes the named node and nothing else", arguments: [
        ("PID-5", "ROE", "PID|1||A1~B2^^^AU||ROE"),
        ("PID-3", "Z9", "PID|1||Z9||DOE^JO"),
        ("PID-3~2", "Z9", "PID|1||A1~Z9||DOE^JO"),
        ("PID-3[2]", "Z9", "PID|1||A1~Z9||DOE^JO"),
        ("PID-3.4", "NSW", "PID|1||A1^^^NSW~B2^^^AU||DOE^JO"),
        ("PID-3~2.4", "NSW", "PID|1||A1~B2^^^NSW||DOE^JO"),
        ("PID-3~2.4.2", "1.2.36", "PID|1||A1~B2^^^AU&1.2.36||DOE^JO"),
        ("PID-5.2", "JOSEPHINE", "PID|1||A1~B2^^^AU||DOE^JOSEPHINE"),
        ("PID-5.1", "A^B", "PID|1||A1~B2^^^AU||A\\S\\B^JO"),
        ("PID-3~4", "D4", "PID|1||A1~B2^^^AU~~D4||DOE^JO"),
        ("PID-5~2.1", "SMITH", "PID|1||A1~B2^^^AU||DOE^JO~SMITH"),
        ("PID-8", "F", "PID|1||A1~B2^^^AU||DOE^JO|||F"),
        ("PID-3[1]", "Z9", "PID|1||Z9~B2^^^AU||DOE^JO"),
        ("PID-3~1", "Z9", "PID|1||Z9~B2^^^AU||DOE^JO"),
    ])
    func set(_ path: String, _ value: String, _ pid: String) throws {
        let result = try Self.edited { try $0.set(value, at: Path(path)) }
        #expect(result == Self.expected(pid: pid))
    }

    @Test("clear empties the named node and trims nothing", arguments: [
        ("PID-3", "PID|1||||DOE^JO"),
        ("PID-3~2", "PID|1||A1~||DOE^JO"),
        ("PID-5.2", "PID|1||A1~B2^^^AU||DOE^"),
        ("PID-5", "PID|1||A1~B2^^^AU||"),
        ("PID-3~1", "PID|1||~B2^^^AU||DOE^JO"),
    ])
    func clear(_ path: String, _ pid: String) throws {
        let result = try Self.edited { try $0.clear(at: Path(path)) }
        #expect(result == Self.expected(pid: pid))
    }

    @Test("insertRepetition inserts before the named repetition and pads past the end", arguments: [
        ("PID-3~1", "PID|1||X0~A1~B2^^^AU||DOE^JO"),
        ("PID-3[2]", "PID|1||A1~X0~B2^^^AU||DOE^JO"),
        ("PID-3~3", "PID|1||A1~B2^^^AU~X0||DOE^JO"),
        ("PID-3~5", "PID|1||A1~B2^^^AU~~~X0||DOE^JO"),
        ("PID-2~1", "PID|1|X0|A1~B2^^^AU||DOE^JO"),
        ("PID-9~2", "PID|1||A1~B2^^^AU||DOE^JO||||~X0"),
    ])
    func insert(_ path: String, _ pid: String) throws {
        let result = try Self.edited { try $0.insertRepetition("X0", at: Path(path)) }
        #expect(result == Self.expected(pid: pid))
    }

    @Test("A segment occurrence is addressed in either syntax")
    func segmentOccurrence() throws {
        let result = try Self.edited { try $0.set("changed", at: Path("NTE[2]-3")) }
        #expect(result == Self.expected(pid: Self.pid, nte2: "NTE|2||changed"))
    }

    @Test("A refused edit throws its reason and leaves the message unchanged", arguments: [
        ("ZZZ-1", MessageEditError.segmentNotFound(segmentID: "ZZZ", occurrence: 1)),
        ("NTE[3]-1", MessageEditError.segmentNotFound(segmentID: "NTE", occurrence: 3)),
        ("MSH-1", MessageEditError.delimiterField(segmentID: "MSH", field: 1)),
        ("MSH-2", MessageEditError.delimiterField(segmentID: "MSH", field: 2)),
    ])
    func refused(_ path: String, _ error: MessageEditError) throws {
        var message = try Parser().parse(Self.wire)
        let before = message.serialize()
        #expect(throws: error) { try message.set("X", at: Path(path)) }
        #expect(message.serialize() == before)
    }

    @Test("Wildcards, a non-repetition insert and a malformed memberwise path are refused")
    func refusedPaths() throws {
        var message = try Parser().parse(Self.wire)
        let before = message.serialize()
        let all = try Path("PID-3[*]")
        #expect(throws: MessageEditError.wildcardPath(all)) { try message.set("X", at: all) }
        let every = try Path("NTE[*]-3")
        #expect(throws: MessageEditError.wildcardPath(every)) { try message.clear(at: every) }
        let field = try Path("PID-3")
        #expect(throws: MessageEditError.notARepetition(field)) { try message.insertRepetition("X", at: field) }
        let component = try Path("PID-3~2.1")
        #expect(throws: MessageEditError.notARepetition(component)) { try message.insertRepetition("X", at: component) }
        let zero = Path(segmentID: "PID", field: 0)
        #expect(throws: MessageEditError.invalidPath(zero)) { try message.set("X", at: zero) }
        let orphan = Path(segmentID: "PID", field: 3, subcomponent: 1)
        #expect(throws: MessageEditError.invalidPath(orphan)) { try message.set("X", at: orphan) }
        let huge = try Path("PID-10000")
        #expect(throws: MessageEditError.invalidPath(huge)) { try message.set("X", at: huge) }
        #expect(message.serialize() == before)
    }

    @Test("Typed access, the locale and the final terminator survive an edit")
    func editKeepsMessageShape() throws {
        var message = try Parser(locale: .auLocalisation).parse(String(Self.wire.dropLast()))
        try message.set("ROE", at: Path("PID-5"))
        #expect(message.firstSegment(PID.self)?.fields[5].stringValue == "ROE")
        #expect(message.locale == .auLocalisation)
        #expect(message.trailingSegmentTerminator == false)
        #expect(message.serialize().last != 0x0D)
    }

    @Test("A value holding escape characters reads back and cannot break the structure", arguments: [
        ("\\a|b\\", "\\E\\a\\F\\b\\E\\"),
        ("\\x\rZZZ|evil\\", "\\E\\x\\X0D\\ZZZ\\F\\evil\\E\\"),
        ("C:\\Users", "C:\\E\\Users"),
        // #13: a run the standard does not define is text.
        ("C:\\Users\\me", "C:\\E\\Users\\E\\me"),
    ])
    func escapeCharactersInValues(_ value: String, _ wire: String) throws {
        let result = try Self.edited { try $0.set(value, at: Path("NTE[1]-3")) }
        #expect(result == Self.expected(pid: Self.pid, nte1: "NTE|1||" + wire))
        let back = try Parser().parse(result)
        #expect(back.segments.count == 4)
        #expect(back["NTE[1]-3"] == value)
    }

    @Test("Editing MSH-12 re-reads the version, as the parser does")
    func editVersion() throws {
        var m = try Parser().parse(Self.wire)
        try m.set("2.3", at: Path("MSH-12"))
        #expect(m.version == .v2_3)
        try m.set("9.9", at: Path("MSH-12"))
        #expect(m.version == .v2_5_1)
    }

    @Test("Editing MSH-18 re-reads the character set; an unknown one is refused and changes nothing")
    func editCharacterSet() throws {
        let latin = "MSH|^~\\&|APP|FAC|||20260101||ADT^A01^ADT_A01|C1|P|2.5.1||||||8859/1\r"
            + "PID|1||||Ren\u{E9}e\r"
        var m = try Parser().parse(try #require(latin.data(using: .isoLatin1)))
        #expect(m.characterEncoding == .iso8859_1)
        try m.set("UNICODE UTF-8", at: Path("MSH-18"))
        #expect(m.characterEncoding == .utf8)
        let back = try Parser().parse(m.serialize())
        #expect(back["PID-5"] == "Ren\u{E9}e")
        let before = m.serialize()
        #expect(throws: MessageEditError.unsupportedCharacterEncoding(declared: "EBCDIC")) {
            try m.set("EBCDIC", at: Path("MSH-18"))
        }
        #expect(m.serialize() == before)
        #expect(m.characterEncoding == .utf8)
        try m.clear(at: Path("MSH-18"))
        #expect(m.characterEncoding == .utf8)
    }

    @Test("Padding a bare BHS writes its delimiter fields from the encoding characters")
    func bareSeparatorSegment() throws {
        var m = try Parser().parse(Self.msh + "BHS\rPID|1\r")
        try m.set("X", at: Path("BHS-3"))
        #expect(String(decoding: m.serialize(), as: UTF8.self) == Self.msh + "BHS|^~\\&|X\rPID|1\r")
    }

    @Test("An edited MSH stays typed and an edited Z-segment stays unknown")
    func hydrationAfterEdit() throws {
        var m = try Parser().parse(Self.wire + "ZAU|1|A\r")
        try m.set("C2", at: Path("MSH-10"))
        try m.set("B", at: Path("ZAU-2"))
        #expect(m.firstSegment(MSH.self)?.fields[10].stringValue == "C2")
        #expect(m.segments.contains { segment in
            if case .unknown(let unknown) = segment { return unknown.segmentID == "ZAU" && unknown.fields[2].stringValue == "B" }
            return false
        })
    }

    @Test("Over the corpus, writing any populated leaf reads back and moves no other leaf")
    func corpusWriteReadBack() throws {
        for url in try FixtureCorpus.validFixtureURLs() {
            let name = url.lastPathComponent
            let message = try Parser().parse(Data(contentsOf: url))
            let entries = message.populatedPaths()
            for (offset, entry) in entries.enumerated() {
                var copy = message
                if ["MSH", "BHS", "FHS"].contains(entry.path.segmentID), entry.path.field <= 2 {
                    #expect(throws: MessageEditError.delimiterField(segmentID: entry.path.segmentID, field: entry.path.field)) {
                        try copy.set("EDITED", at: entry.path)
                    }
                    continue
                }
                let p = entry.path
                if p.segmentID == "MSH", p.segmentIndex == 1, p.field == 18, p.repetition == 1,
                   p.component == 1, p.subcomponent == 1 {
                    #expect(throws: MessageEditError.unsupportedCharacterEncoding(declared: "EDITED")) {
                        try copy.set("EDITED", at: entry.path)
                    }
                    continue
                }
                try copy.set("EDITED", at: entry.path)
                var expected = entries
                expected[offset] = PathValue(path: entry.path, value: "EDITED")
                if copy.populatedPaths() != expected {
                    Issue.record("\(name): writing \(entry.path) moved another leaf")
                }
                let reparsed = try Parser().parse(copy.serialize())
                if reparsed.populatedPaths() != expected {
                    Issue.record("\(name): writing \(entry.path) does not survive a re-parse")
                }
            }
        }
    }

    @Test("A repeated or structured MSH-18 is refused, as the parser would reject it")
    func structuredCharacterSet() throws {
        var m = try Parser().parse(Self.wire)
        try m.set("UNICODE UTF-8", at: Path("MSH-18"))
        let before = m.serialize()
        #expect(throws: MessageEditError.unsupportedCharacterEncoding(declared: "UNICODE UTF-8~8859/1")) {
            try m.insertRepetition("8859/1", at: Path("MSH-18~2"))
        }
        #expect(throws: MessageEditError.unsupportedCharacterEncoding(declared: "UNICODE UTF-8^X")) {
            try m.set("X", at: Path("MSH-18.2"))
        }
        #expect(m.serialize() == before)
        #expect(try Parser().parse(m.serialize()).characterEncoding == .utf8)
    }

    @Test("A character the character set cannot encode is refused, so untouched values are not re-encoded")
    func unencodableCharacter() throws {
        let latin = "MSH|^~\\&|APP|FAC|||20260101||ADT^A01^ADT_A01|C1|P|2.5.1||||||8859/1\r"
            + "PID|1||||Ren\u{E9}e\rNTE|1||Zo\u{EB}\r"
        var m = try Parser().parse(try #require(latin.data(using: .isoLatin1)))
        let before = m.serialize()
        #expect(throws: MessageEditError.characterNotEncodable(.iso8859_1)) {
            try m.set("\u{674E}", at: Path("PID-11"))
        }
        #expect(throws: MessageEditError.characterNotEncodable(.ascii)) {
            try m.set("ASCII", at: Path("MSH-18"))
        }
        #expect(m.serialize() == before)
        #expect(m.characterEncoding == .iso8859_1)
        try m.set("Zo\u{EB} 2", at: Path("NTE-3"))
        let back = try Parser().parse(m.serialize())
        #expect(back["PID-5"] == "Ren\u{E9}e")
        #expect(back["NTE-3"] == "Zo\u{EB} 2")
    }

    @Test("An existing node above index 9,999 stays writable; only padding past it is refused")
    func capLimitsPaddingOnly() throws {
        let many = (1...10_001).map { "OBX|\($0)|NM|X||v" }.joined(separator: "\r")
        var m = try Parser().parse(Self.msh + many + "\r")
        try m.set("w", at: Path("OBX[10001]-5"))
        #expect(m["OBX[10001]-5"] == "w")
        let deep = try Path("OBX[1]-5~10000")
        #expect(throws: MessageEditError.invalidPath(deep)) { try m.set("x", at: deep) }
    }
}
