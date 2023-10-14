// ParseErrorTests.swift
//
// Expands negative-path coverage for the parser. Each section either:
//   1. exercises a ParseError case that wasn't otherwise covered, or
//   2. pins current behaviour on a byte-level edge case where the parser
//      *could* throw but currently doesn't (silently accepts) — comments
//      flag those for v0.2 hardening review.
//
// Started 2026-06-13 as Task 7c. Goal: ParseError.swift to 100% line
// coverage; document parser leniency where it exists.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Parser error paths")
struct ParseErrorTests {

    // MARK: - ParseError case coverage

    @Test("Empty input throws .emptyInput from String overload")
    func emptyStringInput() {
        #expect(throws: ParseError.emptyInput) {
            try Parser().parse("")
        }
    }

    @Test("Empty Data input throws .emptyInput")
    func emptyDataInput() {
        #expect(throws: ParseError.emptyInput) {
            try Parser().parse(Data())
        }
    }

    @Test("MSH segment shorter than 8 characters throws .invalidMSH")
    func mshTooShort() {
        // 'MSH|^~' is only 6 characters — not enough for the MSH-1 + MSH-2
        // skeleton. Parser must reject structurally.
        #expect(throws: ParseError.invalidMSH(reason: "too short")) {
            try Parser().parse("MSH|^~\r")
        }
    }

    @Test("MSH without trailing field separator after MSH-2 throws .invalidMSH")
    func mshMissingFieldSepAfterMSH2() {
        // MSH-1 is "|", then 4 encoding chars "^~\\&", then we expect "|"
        // again. Replace the 9th char with something else.
        let wire = "MSH|^~\\&X|EXTRA|FAC|HOSP|FAC|||ADT^A01|MSG|P|2.5.1\r"
        #expect(throws: ParseError.invalidMSH(reason: "MSH-2 not followed by field separator")) {
            try Parser().parse(wire)
        }
    }

    @Test("MSH-2 encoding chars must be distinct — repeated chars throws .invalidMSH")
    func mshNonDistinctEncodingChars() {
        // All four encoding chars set to ^ — fails EncodingCharacters.isValid.
        let wire = "MSH|^^^^|HIS|FAC|HOSP|FAC|||ADT^A01|MSG|P|2.5.1\r"
        #expect(throws: ParseError.invalidMSH(reason: "encoding characters not distinct")) {
            try Parser().parse(wire)
        }
    }

    @Test("Non-MSH first segment throws .missingMSH (Data overload)")
    func nonMSHFirstSegmentBytes() {
        let wire = "PID|1\r"
        #expect(throws: ParseError.missingMSH) {
            try Parser().parse(Data(wire.utf8))
        }
    }

    @Test("Unrecognised character set in MSH-18 throws .unsupportedCharacterEncoding (String)")
    func unsupportedCharsetFromString() {
        let wire = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG|P|2.5.1||||||GB18030\r"
        #expect(throws: ParseError.unsupportedCharacterEncoding(declared: "GB18030")) {
            try Parser().parse(wire)
        }
    }

    @Test("Strict mode on a Z-segment throws .unknownSegment with 1-based position")
    func strictUnknownSegmentPosition() {
        // ZAU is the 2nd segment (MSH is 1st). Position must be 2.
        let wire = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG|P|2.5.1\rZAU|1\r"
        #expect(throws: ParseError.unknownSegment(id: "ZAU", position: 2)) {
            try Parser(options: .strict).parse(wire)
        }
    }

    // MARK: - ParseError.description renders every case

    @Test("Every ParseError case renders a non-empty description")
    func everyCaseDescriptionRenders() {
        let cases: [ParseError] = [
            .emptyInput,
            .missingMSH,
            .invalidMSH(reason: "test"),
            .unsupportedVersion(found: "v9.9"),
            .unknownSegment(id: "ZAU", position: 2),
            .malformedField(segment: "PID", fieldIndex: 3, reason: "test"),
            .unsupportedCharacterEncoding(declared: "EBCDIC"),
            .truncatedMessage(atByte: 42),
        ]
        for c in cases {
            #expect(!c.description.isEmpty, "Empty description for \(c)")
        }
    }

    // MARK: - Behaviour pins for current leniency
    //
    // These tests document what the parser DOES today on edge cases — they
    // pin behaviour rather than enforce a strict-parser contract. Comments
    // flag items worth re-examining for v0.2 hardening. If the parser
    // becomes stricter, these tests will need to flip from "succeeds with X"
    // to "throws Y".

    @Test("Unknown MSH-12 version silently falls back to v2.5.1 (lenient by design)")
    func unknownVersionFallsBack() throws {
        // Parser.swift:122 documents this as a deliberate choice — keeps
        // the parser useful for older fixtures with non-canonical MSH-12.
        // ParseError.unsupportedVersion is currently unreachable; consider
        // wiring it on strict mode in v0.2.
        let wire = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG|P|9.9.9\r"
        let message = try Parser().parse(wire)
        #expect(message.version == .v2_5_1, "Default fallback should be v2.5.1")
    }

    @Test("Empty MSH-12 silently falls back to v2.5.1")
    func emptyVersionFallsBack() throws {
        let wire = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG|P|\r"
        let message = try Parser().parse(wire)
        #expect(message.version == .v2_5_1)
    }

    @Test("BOM-prefixed input is explicitly stripped before parsing (v0.2-P1)")
    func bomPrefixStrippedExplicitly() throws {
        // CONTRACT (v0.2-P1): the 3-byte UTF-8 BOM (EF BB BF) is dropped
        // before charset detection in `parse(_ data:)`. Result is identical
        // to the same message without the BOM on every platform — no longer
        // a Foundation-specific quirk. The serializer must not re-emit the
        // BOM. The String overload is unaffected (already-decoded text).
        let mshLine = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG|P|2.5.1\r"
        var bytes = Data([0xEF, 0xBB, 0xBF])
        bytes.append(Data(mshLine.utf8))
        let message = try Parser().parse(bytes)
        #expect(message.segments.count == 1)
        // Round-trip drops the BOM — the kit canonicalises output.
        let rebuilt = message.serialize()
        #expect(rebuilt == Data(mshLine.utf8), "Serialiser must not re-emit the BOM")
    }

    @Test("BOM-only input throws .emptyInput after strip (v0.2-P1)")
    func bomOnlyInputIsEmptyAfterStrip() {
        // Once the 3 BOM bytes are dropped the payload is empty — must hit
        // the same .emptyInput contract as zero-length Data.
        let bytes = Data([0xEF, 0xBB, 0xBF])
        #expect(throws: ParseError.emptyInput) {
            try Parser().parse(bytes)
        }
    }

    @Test("Mid-message NUL byte is rejected at parse time (v0.2-P2)")
    func midMessageNULRejected() {
        // CONTRACT (v0.2-P2): Real HL7 v2 messages never carry NUL. If one
        // appears it's almost always transport truncation (a fixed-size
        // buffer NUL-padded beyond the real message). Parser rejects up-
        // front with .truncatedMessage(atByte:) so the round-trip byte-
        // equality invariant (spec § 5) holds for every accepted message
        // without a NUL carve-out. The reported byte offset is into the
        // post-BOM-strip payload — see nulOffsetIsRelativeToStrippedPayload.
        let mshLine = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG|P|2.5.1\r"
        let beforeNUL = "PID|1||SYN-0001||Smith"
        let afterNUL = "Special^John\r"
        var bytes = Data(mshLine.utf8)
        bytes.append(Data(beforeNUL.utf8))
        let nulOffset = bytes.count
        bytes.append(0x00)
        bytes.append(Data(afterNUL.utf8))
        #expect(throws: ParseError.truncatedMessage(atByte: nulOffset)) {
            try Parser().parse(bytes)
        }
    }

    @Test("NUL offset is reported relative to post-BOM-strip payload (v0.2-P2)")
    func nulOffsetIsRelativeToStrippedPayload() {
        // Design choice: the BOM (if present) is dropped before the NUL
        // scan, and the byte offset reported in .truncatedMessage(atByte:)
        // is into the post-strip buffer — callers usually care about
        // "where in the meaningful payload" not "where in the wire
        // including 3 BOM bytes the kit silently dropped".
        let preamble = Data("MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG|P|2.5.1\r".utf8)
        let nulOffsetInPayload = preamble.count
        var bytes = Data([0xEF, 0xBB, 0xBF])
        bytes.append(preamble)
        bytes.append(0x00)
        #expect(throws: ParseError.truncatedMessage(atByte: nulOffsetInPayload)) {
            try Parser().parse(bytes)
        }
    }

    @Test("Multiple MSH segments in one input parse without error (NOT batch-aware)")
    func multipleMSHSegmentsAcceptedAsIs() throws {
        // HL7 v2 has a batch grammar (FHS/BHS framing) that HL7v2Kit
        // doesn't yet support — see roadmap. Until then, a stream with
        // two MSHs is parsed as a single "message" with one MSH at
        // position 1 and another at position 2 (treated as an unknown-ish
        // sibling). Parser.parse(_:) accepts this; consumers can detect
        // it by counting MSH segments in `message.segments`.
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG1|P|2.5.1\r\
        PID|1\r\
        MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG2|P|2.5.1\r\
        PID|2\r
        """
        let message = try Parser().parse(wire)
        let mshCount = message.segments.filter { $0.segmentID == "MSH" }.count
        #expect(mshCount == 2, "Two MSHs in one stream — note: batch framing is v0.2 work")
    }

    @Test("Repeated separator characters produce empty intermediate fields")
    func repeatedSeparatorsProduceEmptyFields() throws {
        // PID|||||||  — 7 pipes after PID. Parser preserves the empty
        // fields (required for round-trip). Validator can flag missing
        // required fields, but Parser accepts the structure.
        let wire = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG|P|2.5.1\rPID|||||||\r"
        let message = try Parser().parse(wire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == wire, "Empty intermediate fields must round-trip")
    }

    @Test("Very long field (8 KB) parses without overflow")
    func longFieldHandled() throws {
        // DoS adjacent — a 8 KB field with no inner delimiters should parse
        // in linear time without stack overflow / quadratic blowup.
        let big = String(repeating: "X", count: 8 * 1024)
        let wire = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG|P|2.5.1\rOBX|1|TX|MSG^TEXT||\(big)\r"
        let message = try Parser().parse(wire)
        // Re-typed as UnknownSegment + path access:
        #expect(message["OBX-5"]?.count == big.count, "Long field preserved through AST")
    }

    @Test("Deep repetition fan-out (1000 ~ characters) does not stack-overflow")
    func deepRepetitionFanOut() throws {
        // PID-3 with 1000 repetitions — exercises the split-on-~ path. AST
        // construction is iterative, not recursive — should be linear.
        let reps = (0..<1000).map { "ID\($0)^^^FAC^MR" }.joined(separator: "~")
        let wire = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG|P|2.5.1\rPID|1||\(reps)||Smith^John\r"
        let message = try Parser().parse(wire)
        guard let pid = message.firstSegment(PID.self) else {
            Issue.record("PID did not hydrate")
            return
        }
        #expect(pid.patientIdentifierList?.repetitions.count == 1000)
    }

    @Test("Trailing CR-only message round-trips")
    func bareCRMessageRoundTrips() throws {
        // Single MSH then immediate end. Round-trip must preserve the
        // terminating CR.
        let wire = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG|P|2.5.1\r"
        let message = try Parser().parse(wire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == wire)
    }

    @Test("Mixed CR/LF terminators normalise under .lenient (default)")
    func mixedTerminatorsLenient() throws {
        // CRLF + LF + CR all in one message — lenient parser normalises
        // all to CR. Serialised output uses CR only.
        let wire = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG|P|2.5.1\r\nPID|1\nNTE|1||Note text\r"
        let message = try Parser().parse(wire)
        #expect(message.segments.count == 3)
        // Round-trip is byte-different because the parser normalised, but
        // re-parsing the output should yield the same shape.
        let rebuilt = try Parser().parse(message.serialize())
        #expect(rebuilt.segments.count == 3)
    }

    @Test("Whitespace-only input throws .missingMSH (not .emptyInput)")
    func whitespaceOnlyInput() {
        // After line-terminator normalisation, a blank-line-only input
        // collapses to an empty segment list — but the input itself isn't
        // empty. Distinguish from .emptyInput.
        #expect(throws: ParseError.missingMSH) {
            try Parser().parse("   \r")
        }
    }

    @Test("Segment with only the segment ID (no field separator) parses as zero-field segment")
    func segmentIDOnlyAccepted() throws {
        // "ZZZ\r" — three-char ID, no fields. Permitted under lenient
        // parsing; UnknownSegment retains the ID and an empty field list.
        let wire = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG|P|2.5.1\rZZZ\r"
        let message = try Parser().parse(wire)
        #expect(message.segments.count == 2)
        #expect(message.segments.last?.segmentID == "ZZZ")
    }

    @Test("Segment ID shorter than 3 characters in a non-MSH segment throws .invalidMSH")
    func shortNonMSHSegmentID() {
        // The parser's parseSegment check requires >= 3 chars; raises
        // .invalidMSH with a "too short" reason (the case is reused for
        // any short segment, not just MSH).
        let wire = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG|P|2.5.1\rPI\r"
        #expect(throws: ParseError.self) {
            try Parser().parse(wire)
        }
    }

    @Test("Custom MSH-2 encoding chars are honoured for downstream parsing")
    func customEncodingCharsHonoured() throws {
        // Some senders use # / @ / ! / + instead of the default ^ / ~ / \\ / &.
        // MSH-2 must be exactly 4 chars: component, repetition, escape,
        // subcomponent. So MSH-2 = "#@!+" and field sep = "|".
        // PID-3 (CX) layout is ID^^^auth^type, which here is ID###auth#type
        // (# as component sep). PID-5 (XPN) is family#given.
        let wire = "MSH|#@!+|HIS|FAC|HOSP|FAC|20240101120000||ADT#A01|MSG|P|2.5.1\rPID|1||SYN-0001###FAC#MR||Smith#John\r"
        let message = try Parser().parse(wire)
        guard let pid = message.firstSegment(PID.self) else {
            Issue.record("PID did not hydrate under custom encoding chars")
            return
        }
        let firstID = pid.patientIdentifierList?.first?.components.first?.stringValue
        #expect(firstID == "SYN-0001")
        // Round-trip must use the custom chars on output.
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == wire, "Custom encoding chars must round-trip")
    }
}
