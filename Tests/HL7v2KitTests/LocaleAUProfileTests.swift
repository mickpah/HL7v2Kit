// LocaleAUProfileTests.swift
// v0.5-S5-B-1 — direct coverage of the AU ADRM-2021 EI-completeness
// rules for OBR-2 / OBR-3 / ORC-2 / ORC-3 / ORC-4.
//
// Each rule asserts that when the field is populated, the EI's four
// components (Entity ID, Namespace ID, Universal ID, Universal ID
// Type) must all be populated. The rule fires only under
// .auLocalisation; under .international the same wire passes silently.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("AU ADRM-2021 profile field-override dispatch (v0.5-S5-B-1)")
struct LocaleAUProfileTests {

    // MARK: - Helpers

    /// Returns the .profileConstraintViolation issues only (filters
    /// out base-spec errors that may also be present in the report).
    private func profileViolations(in report: ValidationReport) -> [ValidationIssue] {
        report.errors.filter {
            if case .profileConstraintViolation = $0.code { return true }
            return false
        }
    }

    /// True if the report contains a profile violation matching the
    /// given (segmentID, fieldIndex, componentIndex) location.
    private func hasViolation(
        _ report: ValidationReport,
        segmentID: String,
        fieldIndex: Int,
        componentIndex: Int
    ) -> Bool {
        report.errors.contains { issue in
            if case .profileConstraintViolation = issue.code,
               issue.location.segmentID == segmentID,
               issue.location.fieldIndex == fieldIndex,
               issue.location.componentIndex == componentIndex {
                return true
            }
            return false
        }
    }

    // MARK: - OBR-2 / OBR-3 EI completeness (HL7au:000003, 000004.1)

    // OBR with OBR-2 = PLACER123^HOSP (2 of 4 EI components populated).
    // AU rule must fire on EI-3 (Universal ID) + EI-4 (Universal ID Type).
    private let obrIncompletePlacer = """
    MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r\
    OBR|1|PLACER123^HOSP|FILLER456^LAB^1.2.36.1.2001.1003.0.ABC^ISO|GLU^Glucose^L\r
    """

    @Test("OBR-2 with 2-of-4 EI components fires AU profile violation on missing components")
    func obr2IncompleteEIFires() throws {
        let message = try Parser(locale: .auLocalisation).parse(obrIncompletePlacer)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(hasViolation(report, segmentID: "OBR", fieldIndex: 2, componentIndex: 3))
        #expect(hasViolation(report, segmentID: "OBR", fieldIndex: 2, componentIndex: 4))
        // OBR-3 in this wire has all 4 components — no violations there.
        let obr3Violations = report.errors.filter {
            if case .profileConstraintViolation = $0.code,
               $0.location.segmentID == "OBR", $0.location.fieldIndex == 3 {
                return true
            }
            return false
        }
        #expect(obr3Violations.isEmpty,
                "OBR-3 is fully populated; should fire no AU violations")
    }

    @Test("Same wire under .international locale fires no profile violations")
    func obr2IncompleteEIInternationalLocalePasses() throws {
        let message = try Parser(locale: .international).parse(obrIncompletePlacer)
        let report = Validator(locale: .international).validate(message)
        #expect(profileViolations(in: report).isEmpty,
                ".international locale must never fire profile violations")
    }

    // OBR with both OBR-2 and OBR-3 fully populated — no violations.
    private let obrAllEIComponentsPopulated = """
    MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r\
    OBR|1|PLACER123^HOSP^1.2.36.1.2001.1003.0.ABC^ISO|FILLER456^LAB^1.2.36.1.2001.1003.0.DEF^ISO|GLU^Glucose^L\r
    """

    @Test("OBR-2 + OBR-3 fully populated (4 of 4 EI components) fires no violations")
    func obrAllEIComponentsPass() throws {
        let message = try Parser(locale: .auLocalisation).parse(obrAllEIComponentsPopulated)
        let report = Validator(locale: .auLocalisation).validate(message)
        let obrViolations = report.errors.filter {
            if case .profileConstraintViolation = $0.code,
               $0.location.segmentID == "OBR" { return true }
            return false
        }
        #expect(obrViolations.isEmpty,
                "Fully-populated EI fields must not trigger AU violations")
    }

    @Test("Empty OBR-2 + OBR-3 fires no AU violations (rule is conditional on field populated)")
    func obrEmptyFieldNoAUViolation() throws {
        let wire = """
        MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r\
        OBR|1|||GLU^Glucose^L\r
        """
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let report = Validator(locale: .auLocalisation).validate(message)
        let obrViolations = report.errors.filter {
            if case .profileConstraintViolation = $0.code,
               $0.location.segmentID == "OBR" { return true }
            return false
        }
        #expect(obrViolations.isEmpty,
                "AU rules fire conditionally only when the field is populated")
    }

    // MARK: - ORC-2 / ORC-3 / ORC-4 EI completeness (HL7au:000005, 000006, 000007)

    // ORC with all three EI fields incomplete (only 1 component each).
    private let orcAllEIIncomplete = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|||ORM^O01|MSG00001|P|2.5.1\r\
    ORC|NW|PLACER123|FILLER456|GRP789\r
    """

    @Test("ORC-2 / ORC-3 / ORC-4 incomplete EI fire AU violations on each missing component")
    func orcIncompleteEIFiresOnAllThreeFields() throws {
        let message = try Parser(locale: .auLocalisation).parse(orcAllEIIncomplete)
        let report = Validator(locale: .auLocalisation).validate(message)
        for fieldIndex in [2, 3, 4] {
            // Each field has only EI-1 populated; EI-2 / EI-3 / EI-4 must
            // all fire.
            #expect(hasViolation(report, segmentID: "ORC", fieldIndex: fieldIndex, componentIndex: 2),
                    "ORC-\(fieldIndex).2 should fire AU violation")
            #expect(hasViolation(report, segmentID: "ORC", fieldIndex: fieldIndex, componentIndex: 3),
                    "ORC-\(fieldIndex).3 should fire AU violation")
            #expect(hasViolation(report, segmentID: "ORC", fieldIndex: fieldIndex, componentIndex: 4),
                    "ORC-\(fieldIndex).4 should fire AU violation")
        }
    }

    @Test("ORC violation issue carries the HL7au spec citation in localeRule")
    func orcViolationCarriesSpecCitation() throws {
        let message = try Parser(locale: .auLocalisation).parse(orcAllEIIncomplete)
        let report = Validator(locale: .auLocalisation).validate(message)
        // Find any ORC-2 violation.
        let orc2 = try #require(report.errors.first { issue in
            if case .profileConstraintViolation = issue.code,
               issue.location.segmentID == "ORC",
               issue.location.fieldIndex == 2 {
                return true
            }
            return false
        })
        guard case .profileConstraintViolation(let rule) = orc2.code else {
            Issue.record("Expected .profileConstraintViolation")
            return
        }
        #expect(rule.contains("HL7au:000005"),
                "ORC-2 rule should cite HL7au:000005, got \(rule)")
        // Find ORC-3 violation — should cite HL7au:000006.
        let orc3 = try #require(report.errors.first { issue in
            if case .profileConstraintViolation = issue.code,
               issue.location.segmentID == "ORC",
               issue.location.fieldIndex == 3 {
                return true
            }
            return false
        })
        if case .profileConstraintViolation(let rule) = orc3.code {
            #expect(rule.contains("HL7au:000004.1") || rule.contains("HL7au:000006"),
                    "ORC-3 rule should cite the spec, got \(rule)")
        }
    }

    // MARK: - Cross-locale invariants

    @Test(".international locale never fires AU rules on AU-incomplete OBR/ORC wires")
    func internationalLocaleNeverFiresAURules() throws {
        for wire in [obrIncompletePlacer, orcAllEIIncomplete] {
            let message = try Parser(locale: .international).parse(wire)
            let report = Validator(locale: .international).validate(message)
            #expect(profileViolations(in: report).isEmpty,
                    ".international locale must never fire profile violations")
        }
    }

    @Test("Validator with .auLocalisation propagates locale onto the report")
    func reportCarriesAULocale() throws {
        let message = try Parser(locale: .auLocalisation).parse(obrIncompletePlacer)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(report.locale == .auLocalisation)
    }

    // MARK: - Polish pass: repeating-field + multi-segment pins

    // OBR-3 with two repetitions: first complete (4-of-4 EI), second
    // incomplete (1-of-4 EI). AU rule must fire on the incomplete rep
    // only — the complete rep passes silently. Repetitions are
    // separated by `~`.
    private let obrRepeatingFieldMixed = """
    MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r\
    OBR|1|PLACER123^HOSP^1.2.36.1.2001.1003.0.ABC^ISO|FILLER456^LAB^1.2.36.1.2001.1003.0.DEF^ISO~ORPHAN789|GLU^Glucose^L\r
    """

    @Test("Repeating field: AU rule fires per repetition, not just the first")
    func auRuleFiresPerRepetition() throws {
        let message = try Parser(locale: .auLocalisation).parse(obrRepeatingFieldMixed)
        let report = Validator(locale: .auLocalisation).validate(message)
        // OBR-3 has 2 repetitions: rep 1 is complete (no violations);
        // rep 2 has only EI-1 set (violations on EI-2, EI-3, EI-4).
        let obr3Violations = report.errors.filter {
            if case .profileConstraintViolation = $0.code,
               $0.location.segmentID == "OBR", $0.location.fieldIndex == 3 {
                return true
            }
            return false
        }
        // Three violations expected from the incomplete second repetition.
        #expect(obr3Violations.count == 3,
                "Each missing component in the incomplete repetition must fire; got \(obr3Violations.count)")
    }

    // Two OBR segments in one message: OBR[1] valid, OBR[2] invalid.
    // The AU rule must fire on OBR[2] only, with the correct
    // segmentIndex on the location.
    private let multiObrMixedConformance = """
    MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r\
    OBR|1|PLACER1^HOSP^1.2.36.1.2001.1003.0.AAA^ISO|FILLER1^LAB^1.2.36.1.2001.1003.0.BBB^ISO|GLU^Glucose^L\r\
    OBR|2|PLACER2^HOSP|FILLER2^LAB^1.2.36.1.2001.1003.0.CCC^ISO|LFT^Liver function^L\r
    """

    @Test("Multi-segment mixed conformance: AU rule fires on second OBR only")
    func auRuleFiresOnCorrectSegmentOccurrence() throws {
        let message = try Parser(locale: .auLocalisation).parse(multiObrMixedConformance)
        let report = Validator(locale: .auLocalisation).validate(message)
        let obrViolations = report.errors.filter {
            if case .profileConstraintViolation = $0.code,
               $0.location.segmentID == "OBR" { return true }
            return false
        }
        // Second OBR's OBR-2 is incomplete (2 of 4 EI components) and
        // fires on EI-3 + EI-4. First OBR is complete; fires zero.
        #expect(obrViolations.count == 2,
                "Expected 2 violations on OBR[2]-2 (EI-3 + EI-4); got \(obrViolations.count)")
        for issue in obrViolations {
            #expect(issue.location.segmentIndex == 2,
                    "All violations must be on segmentIndex 2 (the second OBR)")
            #expect(issue.location.fieldIndex == 2,
                    "All violations must be on OBR-2 (the incomplete field)")
        }
    }
}
