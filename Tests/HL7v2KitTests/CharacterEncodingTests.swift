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
}
