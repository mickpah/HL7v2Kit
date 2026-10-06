// AUSubtypeCorrespondenceTests.swift
// P12 S2-2 item 3: HL7au:00044.10.1.6 and 00044.11.1.6 (AU ADRM-2021.1
// Appendix 5, pp 456 and 457): "When the ED <subtype (ID)> component is
// valued with a HL7 2.4 defined <Subtype (ID)> (Table 0291) value, then the
// corresponding HL7 2.4 type of data (Table 0191) must be used in the <Type
// of data (ID)> component" (and the same sentence for RP). The rule already
// ships through `HL7CodeTables.subtypeToTypeMap`; these pins prove that no
// v2.4 Table 0291 value skips it and give RP its own fire/silent pair.

import Testing
@testable import HL7v2Kit

@Suite("AU ED/RP subtype to type of data (HL7au:00044.10.1.6, 00044.11.1.6)")
struct AUSubtypeCorrespondenceTests {
    @Test("Every v2.4 Table 0291 value is a key of the subtype map, so none skips")
    func everyTable0291ValueIsMapped() throws {
        let table = try #require(HL7TableRegistry.table("0291", version: .v2_4))
        #expect(table.codes.count == 15)
        for code in table.codes {
            #expect(HL7CodeTables.subtypeToTypeMap[code.lowercased()] != nil, "0291 \(code) is not mapped")
        }
    }

    private func rpFindings(_ value: String) throws -> [ValidationIssue] {
        let wire = "MSH|^~\\&|LAB|FAC|HOSP|FAC|20240101||ORU^R01^ORU_R01|MSG|P|2.4\r"
            + "OBX|1|RP|123^Attachment^LN||\(value)|||||F\r"
        let report = Validator(locale: .auLocalisation)
            .validate(try Parser(locale: .auLocalisation).parse(wire))
        return report.issues.filter {
            if case .profileConstraintViolation(let rule) = $0.code { return rule.hasPrefix("HL7au:00044.11.1.5/.6") }
            return false
        }
    }

    @Test("RP with a Table 0291 subtype and a type of data that does not correspond fires at OBX-5.3")
    func rpMismatchFires() throws {
        let tiff = try rpFindings("ptr^APP^AP^TIFF")
        #expect(tiff.count == 1, "got \(tiff.map(\.message))")
        #expect(tiff.first?.location == IssueLocation(segmentID: "OBX", segmentIndex: 1, fieldIndex: 5, componentIndex: 3))
        #expect(try rpFindings("ptr^APP^IM^PDF").count == 1)
    }

    @Test("RP with a corresponding type of data is silent")
    func rpMatchSilent() throws {
        #expect(try rpFindings("ptr^APP^IM^TIFF").isEmpty)
        #expect(try rpFindings("ptr^APP^AP^PDF").isEmpty)
    }
}
