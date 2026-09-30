// AUIdentifierComponentTests.swift
// HL7au:00044.1.1 (CX-1), 00044.3.1 (EI-1) and 00044.7.1 (XCN-1) on AU
// traffic at every grammar version (P3 fix wave, group 1).
//
// ADRM 2021 Appendix 5, all three Senders / Orders, Results, Referrals:
//   00044.1.1 "CX <ID (ST)> component must be specified ..."
//   00044.3.1 "The EI Entity identifier component must be valued ..."
//   00044.7.1 "XCN <ID (ST)> component must be specified ..."
// v2.4 CX, EI and XCN carry no component optionality, and EI.1 and XCN.1 are
// O (or C) on every modelled version, so none of these was enforced by the
// base model on AU VID-form traffic. CX.1 is R from v2.5.1, so 00044.1.1
// yields to that base check there.

import Testing
@testable import HL7v2Kit

@Suite("AU identifier components")
struct AUIdentifierComponentTests {

    static let au24 = "2.4^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L"
    static let au251 = "2.5.1^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L"

    /// Synthetic ORU^R01 with the given PID-3, OBR-3 and OBR-16.
    func oru(msh12: String, messageCode: String = "ORU^R01^ORU_R01",
             pid3: String, obr3: String, obr16: String) throws -> ValidationReport {
        let wire = [
            "MSH|^~\\&|LAB|FAC|GP|FAC|20240301120000+1000||\(messageCode)|MSG1|P|\(msh12)",
            "PID|1||\(pid3)||Smith^John||19800101|M",
            "OBR|1||\(obr3)|1234^Test^LN|||20240301120000+1000|||||||||\(obr16)",
        ].joined(separator: "\r") + "\r"
        return Validator(locale: .auLocalisation).validate(try Parser(locale: .auLocalisation).parse(wire))
    }

    static let goodCX = "123456^^^HOSP&1.2.36.1&ISO^MR"
    static let goodEI = "R1^LAB^1.2.36.1^ISO"
    static let goodXCN = "0123456A^Smith^Jane^^^^^^AUSHICPR^L^^^UPIN"

    func hits(_ report: ValidationReport, _ point: String) -> [ValidationIssue] {
        report.issues.filter {
            if case .profileConstraintViolation(let rule) = $0.code { return rule.hasPrefix(point + " ") }
            return false
        }
    }

    func baseMissing(_ report: ValidationReport, segment: String, field: Int) -> [ValidationIssue] {
        report.issues.filter {
            $0.code == .requiredComponentMissing
                && $0.location.segmentID == segment && $0.location.fieldIndex == field
        }
    }

    // MARK: - HL7au:00044.1.1 (CX-1)

    @Test("HL7au:00044.1.1 fires at CX-1 on AU v2.4 traffic")
    func cx1FiresOnV24() throws {
        let report = try oru(msh12: Self.au24, pid3: "^^^HOSP&1.2.36.1&ISO^MR",
                             obr3: Self.goodEI, obr16: Self.goodXCN)
        let found = hits(report, "HL7au:00044.1.1")
        #expect(found.count == 1)
        #expect(found.first?.location == IssueLocation(segmentID: "PID", segmentIndex: 1,
                                                       fieldIndex: 3, componentIndex: 1))
    }

    @Test("HL7au:00044.1.1 is silent when CX-1 is valued")
    func cx1SilentWhenValued() throws {
        let report = try oru(msh12: Self.au24, pid3: Self.goodCX, obr3: Self.goodEI, obr16: Self.goodXCN)
        #expect(hits(report, "HL7au:00044.1.1").isEmpty)
    }

    @Test("HL7au:00044.1.1 yields to the v2.5.1 base CX.1 check: one finding, not two")
    func cx1ReportedOnceOnV251() throws {
        let report = try oru(msh12: Self.au251, pid3: "^^^HOSP&1.2.36.1&ISO^MR",
                             obr3: Self.goodEI, obr16: Self.goodXCN)
        #expect(hits(report, "HL7au:00044.1.1").isEmpty)
        #expect(baseMissing(report, segment: "PID", field: 3).map(\.location.componentIndex) == [1])
    }

    // MARK: - HL7au:00044.3.1 (EI-1)

    @Test("HL7au:00044.3.1 fires at EI-1 on AU traffic", arguments: [au24, au251])
    func ei1Fires(_ msh12: String) throws {
        let report = try oru(msh12: msh12, pid3: Self.goodCX, obr3: "^LAB^1.2.36.1^ISO", obr16: Self.goodXCN)
        let found = hits(report, "HL7au:00044.3.1")
        #expect(found.count == 1)
        #expect(found.first?.location == IssueLocation(segmentID: "OBR", segmentIndex: 1,
                                                       fieldIndex: 3, componentIndex: 1))
    }

    @Test("HL7au:00044.3.1 is silent when EI-1 is valued")
    func ei1SilentWhenValued() throws {
        let report = try oru(msh12: Self.au24, pid3: Self.goodCX, obr3: Self.goodEI, obr16: Self.goodXCN)
        #expect(hits(report, "HL7au:00044.3.1").isEmpty)
    }

    // MARK: - HL7au:00044.7.1 (XCN-1)

    @Test("HL7au:00044.7.1 fires at XCN-1 on AU traffic", arguments: [au24, au251])
    func xcn1Fires(_ msh12: String) throws {
        let report = try oru(msh12: msh12, pid3: Self.goodCX, obr3: Self.goodEI,
                             obr16: "^Smith^Jane^^^^^^AUSHICPR^L^^^UPIN")
        let found = hits(report, "HL7au:00044.7.1")
        #expect(found.count == 1)
        #expect(found.first?.location == IssueLocation(segmentID: "OBR", segmentIndex: 1,
                                                       fieldIndex: 16, componentIndex: 1))
    }

    @Test("HL7au:00044.7.1 is silent when XCN-1 is valued")
    func xcn1SilentWhenValued() throws {
        let report = try oru(msh12: Self.au24, pid3: Self.goodCX, obr3: Self.goodEI, obr16: Self.goodXCN)
        #expect(hits(report, "HL7au:00044.7.1").isEmpty)
    }

    @Test("v2.8.2: an XCN with XCN.1 and XCN.2 both empty reports each missing component under both of its rules")
    func xcn1AndXcn2EmptyOnV282() throws {
        // XCN.1's absence is reported twice: HL7au:00044.7.1 and the base v2.8.2 condition
        // "XCN.1 is required if XCN.2 is not populated". The empty family name is reported
        // separately, by XCN.2's own condition ("required if XCN.1 is not populated") and by
        // HL7au:00044.7.5. All four are violated, so all four are reported by design.
        let report = try oru(msh12: "2.8.2^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L",
                             pid3: Self.goodCX, obr3: Self.goodEI,
                             obr16: "^^Jane^^^^^^AUSHICPR^L^^^UPIN")
        let atXCN = report.issues.filter { $0.location.segmentID == "OBR" && $0.location.fieldIndex == 16 }
        let found = Set(atXCN.map { issue -> String in
            let rule: String
            if case .profileConstraintViolation(let r) = issue.code {
                rule = String(r.prefix { $0 != " " })
            } else {
                rule = "\(issue.code)"
            }
            return "\(rule)@\(issue.location.componentIndex ?? 0).\(issue.location.subcomponentIndex ?? 0)"
        })
        // The fifth issue is unrelated to the XCN: OBR-16 is B (deprecated) on v2.8.2, so a
        // populated OBR-16 also carries the fieldNotSupported warning.
        #expect(found == [
            "HL7au:00044.7.1@1.0",
            "conditionalComponentMissing@1.0",
            "conditionalComponentMissing@2.0",
            "HL7au:00044.7.5@2.0",
            "fieldNotSupported@0.0",
        ])
        #expect(atXCN.count == 5)
    }

    // MARK: - Scope gate

    @Test("The three points keep their Orders/Results/Referrals scope: silent on ADT")
    func outOfScopeMessageIsSilent() throws {
        let report = try oru(msh12: Self.au24, messageCode: "ADT^A08^ADT_A01",
                             pid3: "^^^HOSP&1.2.36.1&ISO^MR", obr3: "^LAB^1.2.36.1^ISO",
                             obr16: "^Smith^Jane^^^^^^AUSHICPR^L^^^UPIN")
        for point in ["HL7au:00044.1.1", "HL7au:00044.3.1", "HL7au:00044.7.1"] {
            #expect(hits(report, point).isEmpty)
        }
    }
}
