// AUIdentifierTypeTests.swift
// P12 S2-2 item 4: HL7au:00044.1.3 (AU ADRM-2021.1 Appendix 5 p 449): "CX
// <identifier type code (ID)> component must be valued with a valid value
// from HL7 Table 0203 - Identifier type (see page 301)." The same value set
// as HL7au:00044.7.4 on XCN-13 (p 455, "must be valued with a valid value
// from HL7 Table 203"). The ADRM's Table 0203 prints a pattern row, "NNxxx
// National Person Identifier where the xxx is the ISO table 3166
// 3-character (alphabetic) country code" (p 306), so a value of that family
// is a valid value and must stay silent on CX-5 and XCN-13 alike.

import Testing
@testable import HL7v2Kit

@Suite("AU identifier type code, Table 0203 (HL7au:00044.1.3, 00044.7.4)")
struct AUIdentifierTypeTests {
    private func findings(_ segments: String..., point: String) throws -> [ValidationIssue] {
        let wire = "MSH|^~\\&|LAB|FAC|GP|FAC|20240101||ORU^R01^ORU_R01|MSG|P|2.4\r"
            + segments.map { $0 + "\r" }.joined()
        let report = Validator(locale: .auLocalisation)
            .validate(try Parser(locale: .auLocalisation).parse(wire))
        return report.issues.filter {
            if case .profileConstraintViolation(let rule) = $0.code { return rule.hasPrefix(point) }
            return false
        }
    }

    @Test("A CX-5 value outside Table 0203 fires HL7au:00044.1.3 at PID-3.5")
    func cx5OutsideTableFires() throws {
        let issues = try findings("PID|1||12345678^^^AUSHIC^ZZ", point: "HL7au:00044.1.3")
        #expect(issues.count == 1, "got \(issues.map(\.message))")
        #expect(issues.first?.location == IssueLocation(segmentID: "PID", segmentIndex: 1, fieldIndex: 3, componentIndex: 5))
    }

    @Test("CX-5 values from Table 0203, including the NNxxx family, are silent")
    func cx5InTableSilent() throws {
        #expect(try findings("PID|1||12345678^^^AUSHIC^MC~55512^^^LAB^MR", point: "HL7au:00044.1.3").isEmpty)
        #expect(try findings("PID|1||12345678^^^AUSHIC^NNAUS", point: "HL7au:00044.1.3").isEmpty)
        #expect(try findings("PID|1||12345678^^^AUSHIC^UPIN", point: "HL7au:00044.1.3").isEmpty)
    }

    @Test("An over-long NN value is not of the NNxxx family and fires")
    func notTheNNFamilyFires() throws {
        #expect(try findings("PID|1||12345678^^^AUSHIC^NNAUST", point: "HL7au:00044.1.3").count == 1)
    }

    @Test("XCN-13 accepts the NNxxx family too (HL7au:00044.7.4)")
    func xcn13NNFamilySilent() throws {
        // OBR-16 Ordering Provider (XCN).
        let obr = TestWires.segment("OBR", [1: "1", 2: "P1^H", 3: "F1^L^1.2.36^ISO", 4: "GLU^Glucose^L",
                                            16: "12345^Citizen^Jane^^^^^^AUSHIC^L^^^NNAUS"])
        #expect(try findings("PID|1||12345678^^^AUSHIC^MC", obr, point: "HL7au:00044.7.4").isEmpty)
    }
}
