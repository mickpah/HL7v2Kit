// AUFieldLengthTests.swift
// P12 S3-2 item 1 (defect D1 of S3-1): the AU ADRM-2021 attribute tables print
// LEN variations from v2.4, and under the AU locale the field-length check reads
// the ADRM's LEN in place of the v2.4 one. Each row below is a LEN cell of an
// ADRM attribute table that differs from the v2.4 grammar, with its page:
// MSH-12 p 37 ("Australian variation to HL7 V2.4 with the length changed from 60
// to 250 characters.", p 38), OBR-2/3 p 207 ("The field length of OBR-2 and OBR-3
// of 250 characters for Australian usage is a variance to the HL7 V 2.4 field
// length of 22 characters.", p 209), RF1-6/11 pp 326-327, and the others listed.
// Under the international locale the v2.4 LEN still applies.

import Testing
@testable import HL7v2Kit

@Suite("AU ADRM field-length variations replace the v2.4 LEN under the AU locale")
struct AUFieldLengthTests {
    /// One ADRM length variation: the field, the v2.4 LEN and the ADRM LEN.
    struct Variation: Sendable, CustomStringConvertible {
        let segment: String
        let field: Int
        let v24: Int
        let adrm: Int
        var description: String { "\(segment)-\(field) v2.4 \(v24) ADRM \(adrm)" }
    }

    static let variations: [Variation] = [
        Variation(segment: "MSH", field: 10, v24: 20, adrm: 199),
        Variation(segment: "MSH", field: 12, v24: 60, adrm: 250),
        Variation(segment: "PV1", field: 10, v24: 3, adrm: 10),
        Variation(segment: "PV1", field: 21, v24: 2, adrm: 13),
        Variation(segment: "AL1", field: 1, v24: 250, adrm: 4),
        Variation(segment: "AL1", field: 5, v24: 15, adrm: 250),
        Variation(segment: "OBR", field: 2, v24: 22, adrm: 250),
        Variation(segment: "OBR", field: 3, v24: 22, adrm: 250),
        Variation(segment: "OBR", field: 9, v24: 20, adrm: 250),
        Variation(segment: "OBX", field: 18, v24: 22, adrm: 250),
        Variation(segment: "ORC", field: 2, v24: 22, adrm: 250),
        Variation(segment: "ORC", field: 3, v24: 22, adrm: 250),
        Variation(segment: "ORC", field: 4, v24: 22, adrm: 250),
        Variation(segment: "RF1", field: 6, v24: 30, adrm: 250),
        Variation(segment: "RF1", field: 11, v24: 30, adrm: 250),
    ]

    /// A v2.4 message carrying `value` in `segment`-`field`.
    private func wire(_ variation: Variation, _ value: String) -> String {
        var msh: [Int: String] = [3: "LAB", 4: "FAC", 5: "GP", 6: "FAC", 7: "20240101",
                                  9: "ORU^R01^ORU_R01", 10: "MSG", 11: "P", 12: "2.4"]
        var wire = ""
        if variation.segment == "MSH" {
            msh[variation.field] = value
        } else {
            var fields: [Int: String] = [1: "1"]
            fields[variation.field] = value
            wire = TestWires.segment(variation.segment, fields) + "\r"
        }
        var header = "MSH|^~\\&"
        for index in 3...12 { header += "|" + (msh[index] ?? "") }
        return header + "\r" + wire
    }

    private func lengthFindings(_ wire: String, locale: HL7Locale, _ variation: Variation) throws -> [ValidationIssue] {
        let message = try Parser(locale: locale).parse(wire)
        return Validator(options: .strict, locale: locale).validate(message).issues.filter {
            guard case .fieldLengthOutOfRange = $0.code else { return false }
            return $0.location.segmentID == variation.segment && $0.location.fieldIndex == variation.field
        }
    }

    private func value(_ length: Int) -> String { String(repeating: "1", count: length) }

    @Test("At the ADRM LEN the field is clean under the AU locale", arguments: variations)
    func adrmLengthClean(_ variation: Variation) throws {
        #expect(try lengthFindings(wire(variation, value(variation.adrm)), locale: .auLocalisation, variation).isEmpty)
    }

    @Test("One past the ADRM LEN warns under the AU locale, citing the ADRM LEN", arguments: variations)
    func pastADRMLengthWarns(_ variation: Variation) throws {
        let found = try lengthFindings(wire(variation, value(variation.adrm + 1)), locale: .auLocalisation, variation)
        #expect(found.count == 1)
        #expect(found.first?.severity == .warning)
        #expect(found.first?.code == .fieldLengthOutOfRange(length: "\(variation.adrm)", actual: variation.adrm + 1))
        #expect(found.first?.message.contains("AU ADRM-2021") == true)
    }

    @Test("The v2.4 LEN still applies under the international locale", arguments: variations)
    func internationalKeepsV24(_ variation: Variation) throws {
        let past = try lengthFindings(wire(variation, value(variation.v24 + 1)), locale: .international, variation)
        #expect(past.map(\.code) == [.fieldLengthOutOfRange(length: "\(variation.v24)", actual: variation.v24 + 1)])
        #expect(try lengthFindings(wire(variation, value(variation.v24)), locale: .international, variation).isEmpty)
    }

    @Test("A 61-character MSH-12 (the Level 2 declaration) is clean under AU and a v2.4 warning internationally")
    func levelTwoVersionID() throws {
        let vid = "2.4^AUS&Australia&ISO3166_1^HL7AU-OO-REF-SIMPLIFIED-201706&&L"
        #expect(vid.count == 61)
        let msh12 = Variation(segment: "MSH", field: 12, v24: 60, adrm: 250)
        #expect(try lengthFindings(wire(msh12, vid), locale: .auLocalisation, msh12).isEmpty)
        let international = try lengthFindings(wire(msh12, vid), locale: .international, msh12)
        #expect(international.map(\.code) == [.fieldLengthOutOfRange(length: "60", actual: 61)])
        #expect(international.first?.severity == .warning)
    }

    @Test("A message declaring 2.5.1 gets the ADRM MSH-12 length under AU and the v2.5.1 length (60) internationally")
    func declaredV251VersionID() throws {
        let msh12 = Variation(segment: "MSH", field: 12, v24: 60, adrm: 250)
        func vid(_ length: Int) -> String { "2.5.1^" + String(repeating: "X", count: length - 6) }
        func wire251(_ length: Int) -> String { wire(msh12, vid(length)) }
        #expect(try lengthFindings(wire251(61), locale: .auLocalisation, msh12).isEmpty)
        let past = try lengthFindings(wire251(251), locale: .auLocalisation, msh12)
        #expect(past.map(\.code) == [.fieldLengthOutOfRange(length: "250", actual: 251)])
        #expect(past.first?.message.contains("AU ADRM-2021") == true)
        let international = try lengthFindings(wire251(61), locale: .international, msh12)
        #expect(international.map(\.code) == [.fieldLengthOutOfRange(length: "60", actual: 61)])
    }

    @Test("Each AU profile field override is unique per segment and field, so a length cannot shadow another rule")
    func overrideKeysUnique() throws {
        let profile = try #require(Profile.load(for: .auLocalisation))
        let keys = profile.fieldOverrides.map { "\($0.segmentID)-\($0.fieldIndex)" }
        #expect(Set(keys).count == keys.count)
    }
}
