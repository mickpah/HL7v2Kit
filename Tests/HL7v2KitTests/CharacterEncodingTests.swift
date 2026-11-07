// CharacterEncodingTests.swift
// MSH-18-driven character-set detection and round-trip in non-UTF-8 charsets.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Character encoding")
struct CharacterEncodingTests {

    // MARK: - Wire-string lookup

    @Test(#"UNICODE UTF-8 maps to .utf8"#)
    func lookupUTF8() {
        #expect(CharacterEncoding.from(mshField18: "UNICODE UTF-8") == .utf8)
    }

    @Test("ASCII maps to .ascii")
    func lookupASCII() {
        #expect(CharacterEncoding.from(mshField18: "ASCII") == .ascii)
        #expect(CharacterEncoding.from(mshField18: "US-ASCII") == .ascii)
    }

    @Test("8859/1 and its aliases map to .iso8859_1")
    func lookupLatin1() {
        #expect(CharacterEncoding.from(mshField18: "8859/1") == .iso8859_1)
        #expect(CharacterEncoding.from(mshField18: "ISO-8859-1") == .iso8859_1)
        #expect(CharacterEncoding.from(mshField18: "Latin-1") == .iso8859_1)
    }

    @Test("Empty / whitespace-only MSH-18 returns nil (caller defaults to UTF-8)")
    func lookupEmpty() {
        #expect(CharacterEncoding.from(mshField18: "") == nil)
        #expect(CharacterEncoding.from(mshField18: "   ") == nil)
    }

    @Test("Unknown MSH-18 returns nil so caller can throw")
    func lookupUnknown() {
        #expect(CharacterEncoding.from(mshField18: "EBCDIC") == nil)
        #expect(CharacterEncoding.from(mshField18: "GB18030") == nil)
    }

    // MARK: - CharacterEncoding.detect(in:)

    @Test("detect returns the declared MSH-18 charset")
    func detectReturnsDeclared() throws {
        let wire = "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1||||||8859/1\r"
        #expect(try CharacterEncoding.detect(in: wire) == .iso8859_1)
    }

    @Test("detect defaults to UTF-8 when MSH-18 is absent")
    func detectDefaultsUTF8() throws {
        let wire = "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r"
        #expect(try CharacterEncoding.detect(in: wire) == .utf8)
    }

    @Test("detect throws on unrecognised MSH-18")
    func detectThrowsOnUnknown() {
        let wire = "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1||||||EBCDIC\r"
        #expect(throws: ParseError.unsupportedCharacterEncoding(declared: "EBCDIC")) {
            try CharacterEncoding.detect(in: wire)
        }
    }

    // MARK: - Parser detection

    @Test("MSH without an 18th field defaults to .utf8")
    func defaultsToUTF8WhenMSH18Absent() throws {
        let wire = "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r"
        let message = try Parser().parse(wire)
        #expect(message.characterEncoding == .utf8)
    }

    @Test(#"MSH-18 = "8859/1" is detected"#)
    func detects8859_1() throws {
        let wire = "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1||||||8859/1\r"
        let message = try Parser().parse(wire)
        #expect(message.characterEncoding == .iso8859_1)
    }

    @Test("Unrecognised MSH-18 throws .unsupportedCharacterEncoding")
    func unrecognisedThrows() {
        let wire = "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1||||||EBCDIC\r"
        #expect(throws: ParseError.unsupportedCharacterEncoding(declared: "EBCDIC")) {
            try Parser().parse(wire)
        }
    }

    // MARK: - Round-trip with Latin-1 body bytes

    @Test("Latin-1 message with é (0xE9) round-trips byte-perfectly")
    func latin1RoundTripsBytePerfect() throws {
        // Build raw bytes directly: MSH-18 declares 8859/1, OBX-5 carries
        // the literal byte 0xE9 ("é" in Latin-1).
        let header = "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1||||||8859/1\r"
        let obxPrefix = "OBX|1|TX|MSG^TEXT||Caf"
        let obxSuffix = " au lait\r"
        var bytes = Data(header.utf8)
        bytes.append(Data(obxPrefix.utf8))
        bytes.append(0xE9)                          // 'é' in Latin-1, not in ASCII
        bytes.append(Data(obxSuffix.utf8))

        let message = try Parser().parse(bytes)
        #expect(message.characterEncoding == .iso8859_1)
        #expect(message["OBX-5"] == "Café au lait")

        let rebuilt = message.serialize()
        #expect(rebuilt == bytes)
    }

    @Test("UTF-8 multi-byte content survives the default-charset round-trip")
    func utf8RoundTripStillWorks() throws {
        let wire = "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r" +
                   "OBX|1|TX|MSG^TEXT||Café résumé naïve\r"
        let data = Data(wire.utf8)
        let message = try Parser().parse(data)
        #expect(message.characterEncoding == .utf8)
        #expect(message.serialize() == data)
    }

    // MARK: - Repeated MSH-18 (#15)

    static func header(_ msh18: String) -> String {
        "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1||||||\(msh18)\r"
    }

    @Test("The first repetition of MSH-18 names the character set (v2.5.1 section 2.15.9.18)", arguments: [
        ("8859/1~ISO IR87", CharacterEncoding.iso8859_1),
        ("UNICODE UTF-8~UNICODE UTF-8", .utf8),
        ("ASCII~8859/1", .ascii),
        // An empty first repetition takes the empty-field default, UTF-8 (ruling; the
        // print reads it as ASCII).
        ("~ISO IR87", .utf8),
    ])
    func firstRepetitionNamesCharset(_ row: (msh18: String, expected: CharacterEncoding)) throws {
        #expect(try CharacterEncoding.detect(in: Self.header(row.msh18)) == row.expected)
        #expect(try Parser().parse(Self.header(row.msh18)).characterEncoding == row.expected)
    }

    @Test("An unknown first repetition throws, naming that repetition")
    func unknownFirstRepetitionThrows() {
        #expect(throws: ParseError.unsupportedCharacterEncoding(declared: "EBCDIC")) {
            try Parser().parse(Self.header("EBCDIC~ASCII"))
        }
    }

    @Test("A repeated MSH-18 round-trips byte for byte")
    func repeatedRoundTrips() throws {
        var bytes = Data(Self.header("8859/1~ISO IR87").utf8)
        bytes.append(Data("OBX|1|TX|MSG^TEXT||Caf".utf8))
        bytes.append(0xE9)
        bytes.append(Data("\r".utf8))
        let message = try Parser().parse(bytes)
        #expect(message.characterEncoding == .iso8859_1)
        #expect(message["OBX-5"] == "Caf\u{E9}")
        #expect(message.serialize() == bytes)
    }

    @Test("from(mshField18:) maps one value, so a repeated value is nil")
    func fromMapsOneValue() {
        #expect(CharacterEncoding.from(mshField18: "8859/1~ISO IR87") == nil)
    }

    @Test("A custom repetition separator ends the first repetition of MSH-18")
    func customRepetitionSeparator() throws {
        let raw = "MSH|^#\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1||||||8859/1#ISO IR87\r"
        #expect(try CharacterEncoding.detect(in: raw) == .iso8859_1)
    }

    @Test("MSH-18 is found when segments end in CRLF, and MSH ends at MSH-18 (#15)")
    func crlfMSHEndingAtMSH18() throws {
        let text = "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1||||||8859/1\r\nPID|1\r\n"
        #expect(try CharacterEncoding.detect(in: text) == .iso8859_1)
        var bytes = Data(text.utf8)
        bytes.append(contentsOf: Data("OBX|1|TX|MSG^TEXT||Caf".utf8))
        bytes.append(0xE9)
        bytes.append(contentsOf: Data("\r\n".utf8))
        #expect(try Parser().parse(bytes).characterEncoding == .iso8859_1)
    }

    @Test("A Latin-1 batch with CRLF line ends and FHS and BHS ahead of the MSH parses (#15)")
    func crlfBatch() throws {
        var bytes = Data("FHS|^~\\&\r\nBHS|^~\\&\r\nMSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1||||||8859/1\r\nOBX|1|TX|MSG^TEXT||Caf".utf8)
        bytes.append(0xE9)
        bytes.append(contentsOf: Data("\r\nBTS|1\r\nFTS|1\r\n".utf8))
        let message = try #require(try BatchParser().parse(bytes).batches.first?.messages.first)
        #expect(message.characterEncoding == .iso8859_1)
        #expect(message["OBX-5"] == "Caf\u{E9}")
    }

    // swift-corelibs-foundation 6.0 on Linux answers nil for any ISO Latin 1 text or bytes holding
    // a CR, which is every HL7 message; `decode(_:)` and `encode(_:)` do the conversion by hand.
    @Test("ISO 8859-1 text and bytes convert with a CR in them, on every toolchain")
    func latin1ConvertsByHand() {
        let bytes = Data([0x61, 0x0D, 0xE9, 0x0D])
        #expect(CharacterEncoding.iso8859_1.decode(bytes) == "a\r\u{E9}\r")
        #expect(CharacterEncoding.iso8859_1.encode("a\r\u{E9}\r") == bytes)
        #expect(CharacterEncoding.iso8859_1.decode(Data("MSH|a\rPID|b\r".utf8)) == "MSH|a\rPID|b\r")
        #expect(CharacterEncoding.iso8859_1.encode("\u{20AC}") == nil)
        #expect(CharacterEncoding.utf8.decode(Data([0x61, 0xC3, 0xA9])) == "a\u{E9}")
        let every = CharacterEncoding.iso8859_1.decode(Data((0...255).map { UInt8($0) }))
        #expect(every?.unicodeScalars.map(\.value) == Array(0...255))
    }
}
