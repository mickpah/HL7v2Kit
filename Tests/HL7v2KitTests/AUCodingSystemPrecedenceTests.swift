// AUCodingSystemPrecedenceTests.swift
// P12 S2-2 item 1: HL7au:000034.1 / 000034.2, coding-system precedence.
// AU ADRM-2021.1 Appendix 5, p 444: "if the system transmits both the
// public (e.g. LOINC) and local terminology, then the public (e.g. LOINC)
// code must appear in the identifier"; p 445: "the local terminology must
// be transmitted in the second CE triplet i.e. the alternate identifier".
// The local side is the one the ADRM prints, in its Table 0396 (p 144):
// "99ZZZ or L". The rule fires only on a local primary with a non-local
// Table 0396 alternate; two public systems are outside the point (the
// shipped rule's misfire, a requirement 4 defect).

import Testing
@testable import HL7v2Kit

@Suite("AU coding-system precedence (HL7au:000034.1/.2)")
struct AUCodingSystemPrecedenceTests {
    private func findings(_ obx: String) throws -> [ValidationIssue] {
        let wire = TestWires.oru(
            "OBR|1|P1^H|F1^L^1.2.36^ISO|GLU^Glucose^L||||||||||||||||||||LAB",
            obx
        )
        let report = Validator(locale: .auLocalisation)
            .validate(try Parser(locale: .auLocalisation).parse(wire))
        return report.issues.filter {
            if case .profileConstraintViolation(let rule) = $0.code { return rule.hasPrefix("HL7au:000034") }
            return false
        }
    }

    private func at(_ field: Int) -> IssueLocation {
        IssueLocation(segmentID: "OBX", segmentIndex: 1, fieldIndex: field, componentIndex: 3)
    }

    @Test("Two public systems (ICD-10 primary, SNOMED CT alternate) on OBX-3 are silent")
    func twoPublicSystemsOnIdentifierAreSilent() throws {
        let issues = try findings("OBX|1|NM|E11.9^Type 2 diabetes^I10^44054006^Type 2 diabetes^SCT||5.4|mmol/L^mmol/L^UCUM|||||F")
        #expect(issues.isEmpty, "two public systems are outside HL7au:000034; got \(issues.map(\.message))")
    }

    @Test("Two public systems on a coded OBX-5 are silent")
    func twoPublicSystemsOnCodedValueAreSilent() throws {
        let issues = try findings("OBX|1|CE|14749-6^Glucose^LN||E11.9^Type 2 diabetes^I10^44054006^Type 2 diabetes^SCT||||||F")
        #expect(issues.isEmpty, "two public systems are outside HL7au:000034; got \(issues.map(\.message))")
    }

    @Test("A local primary (L) with a SNOMED CT alternate on OBX-3 fires at OBX-3.3")
    func localPrimaryPublicAlternateFires() throws {
        let issues = try findings("OBX|1|NM|GLU4^Glucose^L^14749-6^Glucose^SCT||5.4|mmol/L^mmol/L^UCUM|||||F")
        #expect(issues.count == 1, "got \(issues.map(\.message))")
        #expect(issues.first?.location == at(3))
        if case .profileConstraintViolation(let rule)? = issues.first?.code {
            #expect(rule.hasPrefix("HL7au:000034.1/.2"))
        }
    }

    @Test("A 99zzz primary with a LOINC alternate fires")
    func ninetyNinePrimaryFires() throws {
        let issues = try findings("OBX|1|NM|GLU4^Glucose^99ABC^14749-6^Glucose^LN||5.4|mmol/L^mmol/L^UCUM|||||F")
        #expect(issues.count == 1, "got \(issues.map(\.message))")
        #expect(issues.first?.location == at(3))
    }

    @Test("A local primary with a PBS alternate fires (any non-local Table 0396 row)")
    func localPrimaryPBSAlternateFires() throws {
        let issues = try findings("OBX|1|NM|GLU4^Glucose^L^1234X^Item^PBS||5.4|mmol/L^mmol/L^UCUM|||||F")
        #expect(issues.count == 1, "got \(issues.map(\.message))")
    }

    @Test("A local primary with a SNOMED CT alternate on a coded OBX-5 fires at OBX-5.3")
    func localPrimaryOnCodedValueFires() throws {
        let issues = try findings("OBX|1|CE|14749-6^Glucose^LN||DM2^Diabetes^L^44054006^Type 2 diabetes^SCT||||||F")
        #expect(issues.count == 1, "got \(issues.map(\.message))")
        #expect(issues.first?.location == at(5))
        if case .profileConstraintViolation(let rule)? = issues.first?.code {
            #expect(rule.hasPrefix("HL7au:000034.1"))
        }
    }

    @Test("A local primary with a local alternate is silent")
    func twoLocalSystemsAreSilent() throws {
        #expect(try findings("OBX|1|NM|GLU4^Glucose^L^G4^Glucose^99LAB||5.4|mmol/L^mmol/L^UCUM|||||F").isEmpty)
        #expect(try findings("OBX|1|CE|14749-6^Glucose^LN||DM2^Diabetes^99LAB^D2^Diabetes^L||||||F").isEmpty)
    }

    @Test("A public primary with a local alternate is silent")
    func publicPrimaryLocalAlternateIsSilent() throws {
        #expect(try findings("OBX|1|NM|14749-6^Glucose^LN^GLU4^Glucose^L||5.4|mmol/L^mmol/L^UCUM|||||F").isEmpty)
    }

    @Test("A non-coded OBX-5 (XPN) is outside the point")
    func nonCodedValueIsOutsideThePoint() throws {
        #expect(try findings("OBX|1|XPN|14749-6^Glucose^LN||Citizen^Jane^L^^^AMT||||||F").isEmpty)
    }

    @Test("The AU locale carries the ADRM's Table 0396 (pp 142 to 145)")
    func auTable0396IsSeeded() throws {
        let table = try #require(HL7TableRegistry.table("0396", locale: .auLocalisation))
        #expect(table.codes.count == 27)
        for code in ["DCM", "I10", "ICD10AM", "LN", "SCT", "UCUM", "AUSPDI", "99ZZZ", "L", "AMT", "PBS", "FHIR-ResourceType"] {
            #expect(table.codes.contains(code), "missing \(code)")
        }
    }
}
