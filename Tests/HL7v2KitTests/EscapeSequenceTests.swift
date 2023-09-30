// EscapeSequenceTests.swift
// Decode/encode pair for HL7 v2 subcomponent escape sequences, plus a
// round-trip property check on a message that exercises them.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Escape sequences")
struct EscapeSequenceTests {

    private let enc = EncodingCharacters.default

    // MARK: - Atomic standard escapes

    @Test(#"Decodes \F\ to the field separator"#)
    func decodeFieldSeparator() {
        #expect(EscapeSequences.decode(#"a\F\b"#, encoding: enc) == "a|b")
    }

    @Test(#"Decodes \S\ to the component separator"#)
    func decodeComponentSeparator() {
        #expect(EscapeSequences.decode(#"a\S\b"#, encoding: enc) == "a^b")
    }

    @Test(#"Decodes \T\ to the subcomponent separator"#)
    func decodeSubcomponentSeparator() {
        #expect(EscapeSequences.decode(#"a\T\b"#, encoding: enc) == "a&b")
    }

    @Test(#"Decodes \R\ to the repetition separator"#)
    func decodeRepetitionSeparator() {
        #expect(EscapeSequences.decode(#"a\R\b"#, encoding: enc) == "a~b")
    }

    @Test(#"Decodes \E\ to the escape character"#)
    func decodeEscapeCharacter() {
        #expect(EscapeSequences.decode(#"a\E\b"#, encoding: enc) == #"a\b"#)
    }

    // MARK: - Hex and passthrough

    @Test(#"Decodes \X0D\ to a CR byte"#)
    func decodeSingleHexByte() {
        #expect(EscapeSequences.decode(#"a\X0D\b"#, encoding: enc) == "a\rb")
    }

    @Test(#"Decodes \X0D0A\ to CR LF"#)
    func decodeMultiHexBytes() {
        #expect(EscapeSequences.decode(#"\X0D0A\"#, encoding: enc) == "\r\n")
    }

    @Test(#"\Z…\ passes through verbatim"#)
    func decodeZPassthrough() {
        #expect(EscapeSequences.decode(#"a\Z123\b"#, encoding: enc) == #"a\Z123\b"#)
    }

    @Test("No escape characters present is a no-op")
    func decodeNoOp() {
        #expect(EscapeSequences.decode("plain text", encoding: enc) == "plain text")
    }

    // MARK: - Encode

    @Test("Encodes the field separator")
    func encodeFieldSeparator() {
        #expect(EscapeSequences.encode("a|b", encoding: enc) == #"a\F\b"#)
    }

    @Test("Encodes the component separator")
    func encodeComponentSeparator() {
        #expect(EscapeSequences.encode("a^b", encoding: enc) == #"a\S\b"#)
    }

    @Test("Encodes a literal backslash as the escape escape")
    func encodeEscapeCharacter() {
        #expect(EscapeSequences.encode(#"a\b"#, encoding: enc) == #"a\E\b"#)
    }

    @Test("Encodes a CR character as a hex escape")
    func encodeControlCharacter() {
        #expect(EscapeSequences.encode("a\rb", encoding: enc) == #"a\X0D\b"#)
    }

    @Test(#"Leaves a pre-formed \Z…\ sequence untouched"#)
    func encodeZPassthrough() {
        #expect(EscapeSequences.encode(#"a\Z123\b"#, encoding: enc) == #"a\Z123\b"#)
    }

    // MARK: - Inverse properties

    @Test("decode(encode(x)) == x for plain decoded values")
    func encodeThenDecodeIsIdentity() {
        let cases = [
            "plain",
            "Smith & Co",
            "100|200",
            "A^B^C",
            "rep1~rep2",
            #"back\slash"#,
            "mixed | ^ & ~ \\ all at once",
        ]
        for value in cases {
            let encoded = EscapeSequences.encode(value, encoding: enc)
            let decoded = EscapeSequences.decode(encoded, encoding: enc)
            #expect(decoded == value, "round-trip lost data for \(value)")
        }
    }

    @Test("encode(decode(y)) == y for canonical encoded wire forms")
    func decodeThenEncodeIsIdentityForCanonicalForms() {
        let cases = [
            #"\F\"#, #"\S\"#, #"\T\"#, #"\R\"#, #"\E\"#,
            #"\X0D\"#, #"\X0D0A\"#,
            #"a\F\b\S\c"#,
            #"prefix\Z123\suffix"#,
        ]
        for wire in cases {
            let decoded = EscapeSequences.decode(wire, encoding: enc)
            let reEncoded = EscapeSequences.encode(decoded, encoding: enc)
            #expect(reEncoded == wire, "round-trip lost canonical form: \(wire)")
        }
    }

    // MARK: - Full message round-trip exercising escapes

    @Test("OBX-5 containing a literal ^ round-trips byte-perfectly")
    func obx5WithComponentSeparatorRoundTrips() throws {
        let wire = """
        MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r\
        OBX|1|TX|MSG^TEXT||Hello \\S\\ World\r
        """
        let message = try Parser().parse(wire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == wire)

        // The decoded OBX-5 should hold the literal '^', not the wire escape.
        #expect(message["OBX-5"] == "Hello ^ World")
    }
}
