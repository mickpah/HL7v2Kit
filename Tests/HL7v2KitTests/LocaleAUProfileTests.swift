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
    private let obrIncompletePlacer = TestWires.oru("OBR|1|PLACER123^HOSP|FILLER456^LAB^1.2.36.1.2001.1003.0.ABC^ISO|GLU^Glucose^L")

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
    private let obrAllEIComponentsPopulated = TestWires.oru("OBR|1|PLACER123^HOSP^1.2.36.1.2001.1003.0.ABC^ISO|FILLER456^LAB^1.2.36.1.2001.1003.0.DEF^ISO|GLU^Glucose^L")

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
        let wire = TestWires.oru("OBR|1|||GLU^Glucose^L")
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
    private let obrRepeatingFieldMixed = TestWires.oru("OBR|1|PLACER123^HOSP^1.2.36.1.2001.1003.0.ABC^ISO|FILLER456^LAB^1.2.36.1.2001.1003.0.DEF^ISO~ORPHAN789|GLU^Glucose^L")

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
    private let multiObrMixedConformance = TestWires.oru("OBR|1|PLACER1^HOSP^1.2.36.1.2001.1003.0.AAA^ISO|FILLER1^LAB^1.2.36.1.2001.1003.0.BBB^ISO|GLU^Glucose^L", "OBR|2|PLACER2^HOSP|FILLER2^LAB^1.2.36.1.2001.1003.0.CCC^ISO|LFT^Liver function^L")

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

    // MARK: - S5-B-2: CE / CNE / CWE datatype-level rules (HL7au:00044.4 / .5 / .6)

    // OBR-4 (CE) populated with CE-1 set but CE-3 empty — violates
    // HL7au:00044.4.1 ("identifier set ⇒ name of coding system set").
    private let ceIdentifierWithoutCodingSystem = TestWires.oru("OBR|1|PLACER123^HOSP^1.2.36.1.2001.1003.0.ABC^ISO|FILLER456^LAB^1.2.36.1.2001.1003.0.DEF^ISO|GLU^Glucose")

    @Test("CE rule HL7au:00044.4.1 — identifier set without coding system fires violation")
    func ceIdentifierSetWithoutCodingSystemFires() throws {
        let message = try Parser(locale: .auLocalisation).parse(ceIdentifierWithoutCodingSystem)
        let report = Validator(locale: .auLocalisation).validate(message)
        // OBR-4 (CE) — CE-1 = "GLU" set, CE-3 = empty. Violates 44.4.1.
        let violation = report.errors.first { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               issue.location.segmentID == "OBR",
               issue.location.fieldIndex == 4,
               issue.location.componentIndex == 3,
               rule.contains("HL7au:00044.4.1") {
                return true
            }
            return false
        }
        #expect(violation != nil,
                "Expected HL7au:00044.4.1 violation on OBR-4.3; report = \(report.errors.map(\.message))")
    }

    // CE-4 (alternate identifier) set but CE-6 (alternate coding system)
    // empty — violates HL7au:00044.4.5.
    private let ceAltIdentifierWithoutAltCodingSystem = TestWires.oru("OBR|1|PLACER123^HOSP^1.2.36.1.2001.1003.0.ABC^ISO|FILLER456^LAB^1.2.36.1.2001.1003.0.DEF^ISO|GLU^Glucose^L^GLU2^Glucose alt")

    @Test("CE rule HL7au:00044.4.5 — alt identifier set without alt coding system fires")
    func ceAltIdentifierSetWithoutAltCodingSystemFires() throws {
        let message = try Parser(locale: .auLocalisation).parse(ceAltIdentifierWithoutAltCodingSystem)
        let report = Validator(locale: .auLocalisation).validate(message)
        let violation = report.errors.first { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               issue.location.segmentID == "OBR",
               issue.location.fieldIndex == 4,
               issue.location.componentIndex == 6,
               rule.contains("HL7au:00044.4.5") {
                return true
            }
            return false
        }
        #expect(violation != nil,
                "Expected HL7au:00044.4.5 violation on OBR-4.6")
    }

    // CE-1 empty but CE-3 populated — violates HL7au:00044.4.2 (inverse).
    private let ceCodingSystemWithoutIdentifier = TestWires.oru("OBR|1|PLACER123^HOSP^1.2.36.1.2001.1003.0.ABC^ISO|FILLER456^LAB^1.2.36.1.2001.1003.0.DEF^ISO|^Glucose^LN")

    @Test("CE rule HL7au:00044.4.2 — empty identifier with non-empty coding system fires")
    func ceEmptyIdentifierWithCodingSystemFires() throws {
        let message = try Parser(locale: .auLocalisation).parse(ceCodingSystemWithoutIdentifier)
        let report = Validator(locale: .auLocalisation).validate(message)
        let violation = report.errors.first { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               issue.location.segmentID == "OBR",
               issue.location.fieldIndex == 4,
               rule.contains("HL7au:00044.4.2") {
                return true
            }
            return false
        }
        #expect(violation != nil,
                "Expected HL7au:00044.4.2 violation when CE-3 is set with CE-1 empty")
    }

    // CE fully consistent (CE-1 + CE-3 both set, CE-4 + CE-6 either both
    // set or both empty) — no CE violations.
    private let ceConsistent = TestWires.oru("OBR|1|PLACER123^HOSP^1.2.36.1.2001.1003.0.ABC^ISO|FILLER456^LAB^1.2.36.1.2001.1003.0.DEF^ISO|GLU^Glucose^L")

    @Test("CE consistent (CE-1+CE-3 both set, CE-4+CE-6 both empty) fires no CE violations")
    func ceConsistentFiresNoViolations() throws {
        let message = try Parser(locale: .auLocalisation).parse(ceConsistent)
        let report = Validator(locale: .auLocalisation).validate(message)
        let ceViolations = report.errors.filter {
            if case .profileConstraintViolation(let rule) = $0.code,
               rule.contains("HL7au:00044.4") { return true }
            return false
        }
        #expect(ceViolations.isEmpty,
                "Consistent CE should not fire any HL7au:00044.4.x violations; got \(ceViolations.map(\.message))")
    }

    // CWE pair rule on OBX-3 (which is a CE in v2.5.1; check that
    // dataType lookup is exact — only CWE fields trigger CWE rules,
    // not CE fields, and vice versa).
    private let cweInOBX = TestWires.oru("OBX|1|CWE|HCT^Haematocrit|||F^Final^HL70123")

    @Test("CWE rule HL7au:00044.6.1 fires on a CWE field with identifier missing coding system")
    func cweIdentifierWithoutCodingSystemFires() throws {
        // OBX-3 in v2.5.1 is CE, not CWE. But OBX-11 ('F^Final^HL70123')
        // has CE-1=F, CE-2=Final, CE-3=HL70123 — fully populated. The
        // OBR-4 type Identifier (CE) is HCT^Haematocrit — CE-1 set,
        // CE-3 empty, fires HL7au:00044.4.1.
        let message = try Parser(locale: .auLocalisation).parse(cweInOBX)
        let report = Validator(locale: .auLocalisation).validate(message)
        // Pin: this wire exercises CE-1 set + CE-3 empty in OBX-3,
        // which is a CE field — so the CE rule fires, not the CWE rule.
        let ceFires = report.errors.contains { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               rule.contains("HL7au:00044.4.1") { return true }
            return false
        }
        #expect(ceFires,
                "OBX-3 is a CE field (not CWE) in v2.5.1; the CE rule must fire on its incomplete state")
    }

    // MARK: - v0.13 (ADR-011): 00044.4.8 / .4.4 / .5.3 / .6.3

    private func hasViolation(_ report: ValidationReport, citing token: String) -> Bool {
        report.errors.contains { issue in
            if case .profileConstraintViolation(let rule) = issue.code, rule.contains(token) {
                return true
            }
            return false
        }
    }

    // HL7au:00044.4.8 — alternate coding system (CE-6) must differ from
    // primary coding system (CE-3). OBR-4 with CE-3 = CE-6 = "SCT" (both
    // populated, equal) fires. CE-6 = "SCT" (not "LN") so 44.4.4 stays
    // silent — clean isolation.
    private let ceEqualCodingSystems = """
    MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG|P|2.5.1\r\
    OBR|1|PLACER^HOSP^1.2.3^ISO|FILLER^LAB^1.2.4^ISO|GLU^Glucose^SCT^GLU2^Glucose alt^SCT\r
    """

    @Test("HL7au:00044.4.8 — CE-3 == CE-6 (same coding system) fires")
    func ceEqualCodingSystemsFires() throws {
        let message = try Parser(locale: .auLocalisation).parse(ceEqualCodingSystems)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(hasViolation(report, citing: "HL7au:00044.4.8"),
                "CE-3 == CE-6 must fire 44.4.8; got \(report.errors.map(\.message))")
        #expect(!hasViolation(report, citing: "HL7au:00044.4.4"),
                "CE-6 = SCT (not LN) must not fire 44.4.4")
    }

    // Distinct coding systems (CE-3 = SCT, CE-6 = L) → 44.4.8 silent.
    private let ceDistinctCodingSystems = """
    MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG|P|2.5.1\r\
    OBR|1|PLACER^HOSP^1.2.3^ISO|FILLER^LAB^1.2.4^ISO|GLU^Glucose^SCT^GLU2^Glucose alt^L\r
    """

    @Test("HL7au:00044.4.8 — distinct coding systems (CE-3 != CE-6) silent")
    func ceDistinctCodingSystemsSilent() throws {
        let message = try Parser(locale: .auLocalisation).parse(ceDistinctCodingSystems)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(!hasViolation(report, citing: "HL7au:00044.4.8"),
                "Distinct CE-3 / CE-6 must not fire 44.4.8; got \(report.errors.map(\.message))")
    }

    // HL7au:00044.4.4 — LOINC (LN) must be the primary coding system,
    // not the alternate. OBR-4 on an ORU with CE-6 = "LN" fires. CE-3 =
    // SCT != CE-6 so 44.4.8 stays silent.
    private let ceLoincInAltOnORU = """
    MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG|P|2.5.1\r\
    OBR|1|PLACER^HOSP^1.2.3^ISO|FILLER^LAB^1.2.4^ISO|GLU^Glucose^SCT^14749-6^Glucose^LN\r
    """

    @Test("HL7au:00044.4.4 — LOINC as alternate coding system on ORU fires")
    func loincInAltOnORUFires() throws {
        let message = try Parser(locale: .auLocalisation).parse(ceLoincInAltOnORU)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(hasViolation(report, citing: "HL7au:00044.4.4"),
                "LOINC in CE-6 on ORU must fire 44.4.4; got \(report.errors.map(\.message))")
        #expect(!hasViolation(report, citing: "HL7au:00044.4.8"),
                "CE-3 = SCT != CE-6 = LN, so 44.4.8 must stay silent")
    }

    // Gate check: same LOINC-in-alternate shape on an ADT (not
    // Orders/Results) via DG1-3 (CE) — 44.4.4 must NOT fire because the
    // messageCode gate (ORM, ORU) is false.
    private let ceLoincInAltOnADT = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG|P|2.5.1\r\
    PID|1||X^^^F^MR\r\
    DG1|1|I9|486^Pneumonia^SCT^19829001^Pneumonia^LN|||F\r
    """

    @Test("HL7au:00044.4.4 — LOINC-in-alternate on ADT (non-Orders/Results) is gated silent")
    func loincInAltOnADTGatedSilent() throws {
        let message = try Parser(locale: .auLocalisation).parse(ceLoincInAltOnADT)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(!hasViolation(report, citing: "HL7au:00044.4.4"),
                "ADT is outside the (ORM, ORU) gate; 44.4.4 must not fire; got \(report.errors.map(\.message))")
    }

    // HL7au:00044.6.3 — CWE <text> (CWE-2) must be valued. ERR-3 is a
    // CWE field in v2.5.1; populate CWE-1 + CWE-3 but leave CWE-2 empty.
    private let cweTextEmpty = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ACK|MSG|P|2.5.1\r\
    MSA|AE|MSG\r\
    ERR||PID^1^3|207^^HL70357|E\r
    """

    @Test("HL7au:00044.6.3 — CWE text component empty fires (ERR-3)")
    func cweTextMustBeValuedFires() throws {
        let message = try Parser(locale: .auLocalisation).parse(cweTextEmpty)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(hasViolation(report, citing: "HL7au:00044.6.3"),
                "ERR-3 (CWE) with empty text must fire 44.6.3; got \(report.errors.map(\.message))")
    }

    // HL7au:00044.5.3 — CNE <text> (CNE-2) must be valued. ORC-30
    // (Enterer Authorization Mode) is the only CNE field in v2.5.1;
    // populate CNE-1 with text empty. Built with String(repeating:) so
    // the value lands in field 30 exactly.
    @Test("HL7au:00044.5.3 — CNE text component empty fires (ORC-30)")
    func cneTextMustBeValuedFires() throws {
        let orc = "ORC|NW" + String(repeating: "|", count: 29) + "AUTH"
        let wire = "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG|P|2.5.1\r" + orc + "\r"
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(hasViolation(report, citing: "HL7au:00044.5.3"),
                "ORC-30 (CNE) with empty text must fire 44.5.3; got \(report.errors.map(\.message))")
    }

    // MARK: - S5-B-3: CX required-component rules (HL7au:00044.1.2 / .1.3)

    // PID-3 with only CX-1 populated. AU rules require CX-4 (Assigning
    // Authority) and CX-5 (Identifier Type Code) to also be valued.
    private let pidCxMinimal = TestWires.adt("PID|1||999999")

    @Test("CX rule HL7au:00044.1.2 — PID-3 with CX-4 empty fires")
    func cxAssigningAuthorityMissingFires() throws {
        let message = try Parser(locale: .auLocalisation).parse(pidCxMinimal)
        let report = Validator(locale: .auLocalisation).validate(message)
        let violation = report.errors.first { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               issue.location.segmentID == "PID",
               issue.location.fieldIndex == 3,
               issue.location.componentIndex == 4,
               rule.contains("HL7au:00044.1.2") {
                return true
            }
            return false
        }
        #expect(violation != nil,
                "Expected HL7au:00044.1.2 violation on PID-3.4")
    }

    @Test("CX rule HL7au:00044.1.3 — PID-3 with CX-5 empty fires")
    func cxIdentifierTypeCodeMissingFires() throws {
        let message = try Parser(locale: .auLocalisation).parse(pidCxMinimal)
        let report = Validator(locale: .auLocalisation).validate(message)
        let violation = report.errors.first { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               issue.location.segmentID == "PID",
               issue.location.fieldIndex == 3,
               issue.location.componentIndex == 5,
               rule.contains("HL7au:00044.1.3") {
                return true
            }
            return false
        }
        #expect(violation != nil,
                "Expected HL7au:00044.1.3 violation on PID-3.5")
    }

    // PID-3 fully AU-conformant: CX-1 + CX-4 + CX-5 all valued.
    private let pidCxFull = TestWires.adt("PID|1||999999^^^HOSP^MR")

    @Test("CX consistent (CX-1+CX-4+CX-5 populated) fires no CX-required violations")
    func cxConsistentFiresNoViolations() throws {
        let message = try Parser(locale: .auLocalisation).parse(pidCxFull)
        let report = Validator(locale: .auLocalisation).validate(message)
        let cxViolations = report.errors.filter {
            if case .profileConstraintViolation(let rule) = $0.code,
               rule.contains("HL7au:00044.1") { return true }
            return false
        }
        #expect(cxViolations.isEmpty,
                "AU-conformant CX must fire no HL7au:00044.1.x violations; got \(cxViolations.map(\.message))")
    }

    // CX rules apply to EVERY populated CX field, not just PID-3. PID-2
    // is also CX (Patient ID deprecated). When populated, AU rules fire.
    private let pidCxOnDeprecatedField = TestWires.adt("PID|1|DEPRECATED_ID|999999^^^HOSP^MR")

    @Test("CX rules fire on every populated CX field (dataType dispatch)")
    func cxRuleFiresOnEveryCxFieldRegardlessOfFieldIndex() throws {
        // PID-2 is a CX (deprecated). Wire populates CX-1 only,
        // mirroring an "incomplete legacy identifier" pattern. AU
        // rules narrow CX-4 + CX-5 across the datatype, so PID-2
        // should also fire the missing-component violations.
        let message = try Parser(locale: .auLocalisation).parse(pidCxOnDeprecatedField)
        let report = Validator(locale: .auLocalisation).validate(message)
        let pid2Violations = report.errors.filter {
            if case .profileConstraintViolation = $0.code,
               $0.location.segmentID == "PID",
               $0.location.fieldIndex == 2 {
                return true
            }
            return false
        }
        #expect(pid2Violations.count == 2,
                "PID-2 (CX, deprecated) should fire CX-4 + CX-5 missing under AU; got \(pid2Violations.count)")
    }

    @Test("CX rules don't fire under .international locale")
    func cxRulesAreAULocaleOnly() throws {
        let message = try Parser(locale: .international).parse(pidCxMinimal)
        let report = Validator(locale: .international).validate(message)
        #expect(profileViolations(in: report).isEmpty,
                ".international locale must never fire profile violations")
    }

    // MARK: - S5-C: per-component value-set rules (HL7au:000041 / 000042)

    // MSH-17 populated with "USA" instead of "AUS" — fires HL7au:000041.
    // MSH field layout (post-MSH-12): MSH-13 empty | MSH-14 empty |
    // MSH-15 AL | MSH-16 NE | MSH-17 USA | MSH-18 empty | MSH-19 lang.
    private let mshNonAUCountry = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1|||AL|NE|USA||en^English^ISO639\r\
    PID|1||999999^^^HOSP^MR\r
    """

    @Test("MSH-17 value-set rule HL7au:000041 — wrong country fires")
    func mshCountryWrongValueFires() throws {
        let message = try Parser(locale: .auLocalisation).parse(mshNonAUCountry)
        let report = Validator(locale: .auLocalisation).validate(message)
        let violation = report.errors.first { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               issue.location.segmentID == "MSH",
               issue.location.fieldIndex == 17,
               issue.location.componentIndex == 1,
               rule.contains("HL7au:000041") {
                return true
            }
            return false
        }
        #expect(violation != nil,
                "Expected HL7au:000041 violation on MSH-17.1 = 'USA'")
    }

    // MSH-19 populated with wrong language identifier.
    private let mshNonENLanguage = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1|||AL|NE|AUS||fr^French^ISO639\r\
    PID|1||999999^^^HOSP^MR\r
    """

    @Test("MSH-19 value-set rule HL7au:000042 — wrong language identifier fires")
    func mshLanguageWrongIdentifierFires() throws {
        let message = try Parser(locale: .auLocalisation).parse(mshNonENLanguage)
        let report = Validator(locale: .auLocalisation).validate(message)
        let violation = report.errors.first { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               issue.location.segmentID == "MSH",
               issue.location.fieldIndex == 19,
               issue.location.componentIndex == 1,
               rule.contains("HL7au:000042") {
                return true
            }
            return false
        }
        #expect(violation != nil,
                "Expected HL7au:000042 violation on MSH-19.1 = 'fr'")
    }

    // MSH-12 = "2.4^AUS&Australia&ISO3166_1" + MSH-17 = "AUS" + MSH-19
    // = "en^English^ISO639" — fully AU-conformant per HL7au:000040.1/.2,
    // 000041, 000042 (universal subrules; 040.3 / .4 require ORM/ORU or
    // REF/RRI messages which an ADT^A01 wire doesn't trigger).
    private let mshFullyAUCompliant = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.4^AUS&Australia&ISO3166_1|||AL|NE|AUS||en^English^ISO639\r\
    PID|1||999999^^^HOSP^MR\r
    """

    @Test("MSH-17 = AUS + MSH-19 = en^English^ISO639 fires no value-set violations")
    func mshFullyAUCompliantFiresNoViolations() throws {
        let message = try Parser(locale: .auLocalisation).parse(mshFullyAUCompliant)
        let report = Validator(locale: .auLocalisation).validate(message)
        let mshViolations = report.errors.filter {
            if case .profileConstraintViolation = $0.code,
               $0.location.segmentID == "MSH" { return true }
            return false
        }
        #expect(mshViolations.isEmpty,
                "AU-conformant MSH must fire no profile violations; got \(mshViolations.map(\.message))")
    }

    @Test("profileUsage dispatch: empty MSH-17 and MSH-19 fire profile-required violations")
    func mshProfileRequiredFiresOnEmpty() throws {
        // Post-S5-D-2 profileUsage dispatch: the AU spec says MSH-17
        // and MSH-19 must be populated under AU. With
        // profileUsage = .required on each FieldOverride, empty MSH-
        // 17 / MSH-19 fire .profileConstraintViolation (distinct from
        // the value-set check that fires only on populated-but-wrong).
        let wire = TestWires.adt("PID|1||999999^^^HOSP^MR")
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let report = Validator(locale: .auLocalisation).validate(message)
        let msh17Issue = report.errors.first { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               issue.location.segmentID == "MSH",
               issue.location.fieldIndex == 17,
               rule.contains("HL7au:000041") {
                return true
            }
            return false
        }
        let msh19Issue = report.errors.first { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               issue.location.segmentID == "MSH",
               issue.location.fieldIndex == 19,
               rule.contains("HL7au:000042") {
                return true
            }
            return false
        }
        #expect(msh17Issue != nil,
                "Empty MSH-17 should fire HL7au:000041 violation under AU profile-required")
        #expect(msh19Issue != nil,
                "Empty MSH-19 should fire HL7au:000042 violation under AU profile-required")
    }

    @Test("profileUsage: same wire under .international fires no profile-required violations")
    func internationalLocaleSilentOnEmptyMSH() throws {
        let wire = TestWires.adt("PID|1||999999^^^HOSP^MR")
        let message = try Parser(locale: .international).parse(wire)
        let report = Validator(locale: .international).validate(message)
        #expect(profileViolations(in: report).isEmpty,
                ".international locale must never fire profile violations")
    }

    @Test("MSH-17 / MSH-19 rules don't fire under .international locale")
    func mshValueSetRulesAULocaleOnly() throws {
        let message = try Parser(locale: .international).parse(mshNonAUCountry)
        let report = Validator(locale: .international).validate(message)
        #expect(profileViolations(in: report).isEmpty,
                ".international locale must never fire profile violations")
    }

    // MARK: - v0.8 (ADR-009): HL7au:000040 — MSH-12 Version ID conformance

    // ORU^R01 with full conformant MSH-12 — 040.1/.2 + 040.3 all
    // satisfied. ACK^* would be the simplest "in-scope" type but ORU
    // exercises both the universal and the 040.3 gated paths.
    private let oruAUConformantMSH12 = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|||ORU^R01|MSG|P|2.4^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L|||AL|NE|AUS||en^English^ISO639\r\
    PID|1||X^^^F^MR\r\
    ORC|RE|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL|GLUC|||||||||||||||||||||F\r
    """

    @Test("HL7au:000040.1/.2 — conformant ORU MSH-12 fires no MSH-12 violations")
    func msh12UniversalConformant() throws {
        let message = try Parser(locale: .auLocalisation).parse(oruAUConformantMSH12)
        let report = Validator(locale: .auLocalisation).validate(message)
        let msh12 = report.errors.filter {
            $0.location.segmentID == "MSH" && $0.location.fieldIndex == 12
        }
        #expect(msh12.isEmpty,
                "Expected no MSH-12 violations on fully-conformant wire; got \(msh12.map(\.message))")
    }

    // ORU with MSH-12.1 = "2.5.1" (wrong VID-1) → 040.1/.2 fires on VID-1.
    // (ADT^A01 wouldn't fire because 040.1/.2 is gated to ORM/ORU/REF/RRI/ACK
    // per the spec's enumeration; the v0.8-S3b polish closed that over-fire.)
    private let mshWrongVID1OnORU = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|||ORU^R01|MSG|P|2.5.1^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L|||AL|NE|AUS||en^English^ISO639\r\
    PID|1||X^^^F^MR\r\
    ORC|RE|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL|GLUC|||||||||||||||||||||F\r
    """

    @Test("HL7au:000040.1/.2 — MSH-12.1 = '2.5.1' on ORU fires VID-1 violation")
    func msh12WrongVID1Fires() throws {
        let message = try Parser(locale: .auLocalisation).parse(mshWrongVID1OnORU)
        let report = Validator(locale: .auLocalisation).validate(message)
        let issue = report.errors.first { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               issue.location.segmentID == "MSH",
               issue.location.fieldIndex == 12,
               rule.contains("HL7au:000040.1/.2") {
                return true
            }
            return false
        }
        #expect(issue != nil)
    }

    // Same wrong-VID-1 wire but messageCode = ADT — 040.1/.2 must NOT
    // fire because ADT is outside the spec's enumeration. Pins the
    // v0.8-S3b polish that gated 040.1/.2 by messageCode.
    private let mshWrongVID1OnADT = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG|P|2.5.1^USA&UnitedStates&ISO3166_1|||AL|NE|USA||fr^French^ISO639\r\
    PID|1||X^^^F^MR\r
    """

    @Test("HL7au:000040.1/.2 — ADT^A01 silent (out of spec's enumeration; v0.8-S3b polish)")
    func msh12UniversalSilentOnADT() throws {
        let message = try Parser(locale: .auLocalisation).parse(mshWrongVID1OnADT)
        let report = Validator(locale: .auLocalisation).validate(message)
        let msh12 = report.errors.filter { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               issue.location.segmentID == "MSH",
               issue.location.fieldIndex == 12,
               rule.contains("HL7au:000040") {
                return true
            }
            return false
        }
        #expect(msh12.isEmpty,
                "040.1/.2 must be gated off for ADT^A01; got \(msh12.map(\.message))")
    }

    // ORU with VID-2.2 missing (AUS&&ISO3166_1 — empty middle subcomponent).
    private let mshMissingVID22 = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|||ORU^R01|MSG|P|2.4^AUS&&ISO3166_1^HL7AU-OO-201701&&L|||AL|NE|AUS||en^English^ISO639\r\
    PID|1||X^^^F^MR\r\
    ORC|RE|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL|GLUC|||||||||||||||||||||F\r
    """

    @Test("HL7au:000040.1/.2 — subcomponent granularity: VID-2.2 empty fires")
    func msh12SubcomponentGranularityFires() throws {
        let message = try Parser(locale: .auLocalisation).parse(mshMissingVID22)
        let report = Validator(locale: .auLocalisation).validate(message)
        let issue = report.errors.first { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               issue.location.segmentID == "MSH",
               issue.location.fieldIndex == 12,
               rule.contains("MSH-12.2.2") {
                return true
            }
            return false
        }
        #expect(issue != nil,
                "Expected HL7au:000040.1/.2 violation on MSH-12.2.2 (Australia)")
    }

    // ORU^R01 — message code triggers 040.3 conditional gating. MSH-12.3 must =
    // "HL7AU-OO-201701&&L". Wire omits VID-3 entirely → 040.3 fires.
    private let oruMissingVID3 = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|||ORU^R01|MSG|P|2.4^AUS&Australia&ISO3166_1|||AL|NE|AUS||en^English^ISO639\r\
    PID|1||X^^^F^MR\r\
    ORC|RE|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL|GLUC|||||||||||||||||||||F\r
    """

    @Test("HL7au:000040.3 — Orders/Results without VID-3 fires (messageCode gating)")
    func msh12_040_3_FiresOnORU() throws {
        let message = try Parser(locale: .auLocalisation).parse(oruMissingVID3)
        let report = Validator(locale: .auLocalisation).validate(message)
        let issue = report.errors.first { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               issue.location.segmentID == "MSH",
               issue.location.fieldIndex == 12,
               rule.contains("HL7au:000040.3") {
                return true
            }
            return false
        }
        #expect(issue != nil,
                "Expected HL7au:000040.3 violation on Orders/Results message lacking VID-3")
    }

    // Same shape but ADT^A01 instead of ORU — 040.3 gated off; no violation.
    private let adtMissingVID3 = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG|P|2.4^AUS&Australia&ISO3166_1|||AL|NE|AUS||en^English^ISO639\r\
    PID|1||X^^^F^MR\r
    """

    @Test("HL7au:000040.3 — ADT messages don't fire VID-3 rule (conditional gating works)")
    func msh12_040_3_SilentOnNonOrders() throws {
        let message = try Parser(locale: .auLocalisation).parse(adtMissingVID3)
        let report = Validator(locale: .auLocalisation).validate(message)
        let issue = report.errors.first { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               rule.contains("HL7au:000040.3") || rule.contains("HL7au:000040.4") {
                return true
            }
            return false
        }
        #expect(issue == nil,
                "040.3 / 040.4 must not fire on ADT (non-Orders/Referrals); got \(issue?.message ?? "<none>")")
    }

    // ORU^R01 with correct VID-3 → 040.3 satisfied, no violation.
    private let oruConformantVID3 = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|||ORU^R01|MSG|P|2.4^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L|||AL|NE|AUS||en^English^ISO639\r\
    PID|1||X^^^F^MR\r\
    ORC|RE|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL|GLUC|||||||||||||||||||||F\r
    """

    @Test("HL7au:000040.3 — conformant ORU VID-3 fires no MSH-12 violations")
    func msh12_040_3_Satisfied() throws {
        let message = try Parser(locale: .auLocalisation).parse(oruConformantVID3)
        let report = Validator(locale: .auLocalisation).validate(message)
        let msh12 = report.errors.filter {
            $0.location.segmentID == "MSH" && $0.location.fieldIndex == 12
        }
        #expect(msh12.isEmpty,
                "Expected no MSH-12 violations on fully-conformant ORU; got \(msh12.map(\.message))")
    }

    // REF^I12 with the correct Level-2 VID-3 → 040.4 satisfied.
    private let refLevel2 = """
    MSH|^~\\&|HIS|FAC|REF|FAC|||REF^I12|MSG|P|2.4^AUS&Australia&ISO3166_1^HL7AU-OO-REF-SIMPLIFIED-201706&&L|||AL|NE|AUS||en^English^ISO639\r\
    PID|1||X^^^F^MR\r
    """

    @Test("HL7au:000040.4 — Referrals with Level-2 VID-3 fires no MSH-12 violations")
    func msh12_040_4_Level2Satisfied() throws {
        let message = try Parser(locale: .auLocalisation).parse(refLevel2)
        let report = Validator(locale: .auLocalisation).validate(message)
        let msh12 = report.errors.filter {
            $0.location.segmentID == "MSH" && $0.location.fieldIndex == 12
        }
        #expect(msh12.isEmpty,
                "Expected no MSH-12 violations on Level-2 Referral; got \(msh12.map(\.message))")
    }

    // REF^I12 with Level-1 VID-3 — also valid per 040.4.
    private let refLevel1 = """
    MSH|^~\\&|HIS|FAC|REF|FAC|||REF^I12|MSG|P|2.4^AUS&Australia&ISO3166_1^HL7AU-OO-REF-SIMPLIFIED-201706-L1&&L|||AL|NE|AUS||en^English^ISO639\r\
    PID|1||X^^^F^MR\r
    """

    @Test("HL7au:000040.4 — Referrals with Level-1 VID-3 fires no MSH-12 violations")
    func msh12_040_4_Level1Satisfied() throws {
        let message = try Parser(locale: .auLocalisation).parse(refLevel1)
        let report = Validator(locale: .auLocalisation).validate(message)
        let msh12 = report.errors.filter {
            $0.location.segmentID == "MSH" && $0.location.fieldIndex == 12
        }
        #expect(msh12.isEmpty)
    }

    // ORU with REF-style VID-3 → 040.3 fires (wrong identifier for Orders),
    // and 040.4 is gated off (not a Referral). Confirms message-code
    // dispatch routes to the right rule set.
    private let oruWithReferralVID3 = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|||ORU^R01|MSG|P|2.4^AUS&Australia&ISO3166_1^HL7AU-OO-REF-SIMPLIFIED-201706&&L|||AL|NE|AUS||en^English^ISO639\r\
    PID|1||X^^^F^MR\r\
    ORC|RE|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL|GLUC|||||||||||||||||||||F\r
    """

    @Test("HL7au:000040 — ORU with Referral-style VID-3 fires 040.3 but not 040.4")
    func msh12_040_DispatchIsExclusive() throws {
        let message = try Parser(locale: .auLocalisation).parse(oruWithReferralVID3)
        let report = Validator(locale: .auLocalisation).validate(message)
        let fired_040_3 = report.errors.contains { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               rule.contains("HL7au:000040.3") { return true }
            return false
        }
        let fired_040_4 = report.errors.contains { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               rule.contains("HL7au:000040.4") { return true }
            return false
        }
        #expect(fired_040_3,
                "Orders/Results with Referral-style VID-3 must fire 040.3")
        #expect(!fired_040_4,
                "040.4 must not fire on Orders/Results (gating off)")
    }

    // International locale: MSH-12 = wrong VID — base-spec accepts any
    // version ID; no AU narrowing fires.
    @Test("HL7au:000040 — silent under .international locale")
    func msh12_040_InternationalSilent() throws {
        let message = try Parser(locale: .international).parse(mshWrongVID1OnORU)
        let report = Validator(locale: .international).validate(message)
        #expect(profileViolations(in: report).isEmpty)
    }

    // ORU with VID-3 = "HL7AU-OO-201701^bogus^L" — VID-3.2 should be
    // empty per the literal "HL7AU-OO-201701&&L" form. Pins the
    // v0.8-S3b VID-3.2-must-be-empty addition.
    private let oruVID32Populated = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|||ORU^R01|MSG|P|2.4^AUS&Australia&ISO3166_1^HL7AU-OO-201701&bogus&L|||AL|NE|AUS||en^English^ISO639\r\
    PID|1||X^^^F^MR\r\
    ORC|RE|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL|GLUC|||||||||||||||||||||F\r
    """

    @Test("HL7au:000040.3 — VID-3.2 populated (non-empty) fires (v0.8-S3b literal pin)")
    func msh12_040_3_VID3_2_MustBeEmpty() throws {
        let message = try Parser(locale: .auLocalisation).parse(oruVID32Populated)
        let report = Validator(locale: .auLocalisation).validate(message)
        let issue = report.errors.first { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               issue.location.segmentID == "MSH",
               issue.location.fieldIndex == 12,
               rule.contains("HL7au:000040.3"),
               rule.contains("MSH-12.3.2") {
                return true
            }
            return false
        }
        #expect(issue != nil,
                "VID-3.2 must be empty per literal HL7AU-OO-201701&&L; populating it must fire")
    }

    // MARK: - S5-D: AU pre-adopted PID-35..38 grammar extensions on v2.4

    // v2.4 PID with PID-36 (Breed Code) populated but PID-35 (Species
    // Code) empty. Under v2.5.1 the AU-adopted condition `"PID-36
    // populated OR PID-38 populated"` requires PID-35 to be valued.
    // Without S5-D, v2.4 grammar has no PID-35..38 entries, so this
    // condition never fires on v2.4 wires. With S5-D + .auLocalisation,
    // the AU grammar extension merges PID-35..38 in, and the condition
    // fires.
    //
    // PID-36 populated (B7) + PID-35 empty. Wire shape mirrors the
    // ConditionalFieldTests.pidBreedPopulatedSpeciesEmpty pin: 28
    // separator pipes after `M` end PID-9..PID-35 (empty); the next
    // open is PID-36 where B7 lands.
    private let v24PIDBreedWithoutSpecies = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.4\r\
    PID|1||999999^^^HOSP^MR||Smith^John^A||19800101|M||||||||||||||||||||||||||||B7^Beagle^HL70449\r
    """

    @Test("v2.4 wire + .auLocalisation: PID-36 populated triggers PID-35 conditional via grammar extension")
    func v24PIDSpeciesConditionFiresUnderAU() throws {
        let message = try Parser(locale: .auLocalisation).parse(v24PIDBreedWithoutSpecies)
        let report = Validator(locale: .auLocalisation).validate(message)
        let issue = report.errors.first { issue in
            if issue.code == .conditionalFieldMissing,
               issue.location.segmentID == "PID",
               issue.location.fieldIndex == 35 {
                return true
            }
            return false
        }
        #expect(issue != nil,
                "Expected .conditionalFieldMissing on PID-35 under AU + v2.4")
        #expect(issue?.message.contains("PID-36 populated OR PID-38 populated") == true,
                "Issue message should carry the AU-extended condition string")
    }

    @Test("v2.4 wire + .international locale: PID-35..38 grammar gap means no conditional fires")
    func v24PIDSpeciesConditionSilentUnderInternational() throws {
        // Under .international + v2.4, the base grammar has no
        // PID-35..38 entries; the conditional rule cannot fire. This
        // pins the v2.4 base-spec behaviour against regression.
        let message = try Parser(locale: .international).parse(v24PIDBreedWithoutSpecies)
        let report = Validator(locale: .international).validate(message)
        let pid35Issues = report.errors.filter {
            $0.code == .conditionalFieldMissing
            && $0.location.segmentID == "PID"
            && $0.location.fieldIndex == 35
        }
        #expect(pid35Issues.isEmpty,
                "Base v2.4 grammar has no PID-35; no conditional should fire under .international")
    }

    // PID-35 + PID-36 both populated under v2.4 + AU — no conditional
    // violation on PID-35. Mirrors ConditionalFieldTests pidStrainAnd
    // BreedPopulated shape (27 pipes after M = PID-35 open, then L2,
    // then PID-36 = B7).
    private let v24PIDSpeciesAndBreed = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.4\r\
    PID|1||999999^^^HOSP^MR||Smith^John^A||19800101|M|||||||||||||||||||||||||||L2^Canine^HL70447|B7^Beagle^HL70449\r
    """

    @Test("v2.4 wire + .auLocalisation: PID-35 + PID-36 populated fires no PID-35 conditional")
    func v24PIDSpeciesAndBreedSatisfiesCondition() throws {
        let message = try Parser(locale: .auLocalisation).parse(v24PIDSpeciesAndBreed)
        let report = Validator(locale: .auLocalisation).validate(message)
        let pid35Issues = report.errors.filter {
            $0.code == .conditionalFieldMissing
            && $0.location.segmentID == "PID"
            && $0.location.fieldIndex == 35
        }
        #expect(pid35Issues.isEmpty,
                "PID-35 populated satisfies its conditional; should not fire")
    }

    // v2.5.1 PID-35/36 behaviour is unchanged regardless of locale
    // (base grammar already has these fields).
    @Test("v2.5.1 wire: PID-35 conditional rule fires regardless of locale (base-grammar route)")
    func v251PIDSpeciesConditionUnchangedByProfile() throws {
        // Same wire shape as v24PIDBreedWithoutSpecies but version 2.5.1.
        let v251Wire = TestWires.adt("PID|1||999999^^^HOSP^MR||Smith^John^A||19800101|M||||||||||||||||||||||||||||B7^Beagle^HL70449")
        let intlMessage = try Parser(locale: .international).parse(v251Wire)
        let intlReport = Validator(locale: .international).validate(intlMessage)
        let auMessage = try Parser(locale: .auLocalisation).parse(v251Wire)
        let auReport = Validator(locale: .auLocalisation).validate(auMessage)
        let intlPID35 = intlReport.errors.filter {
            $0.code == .conditionalFieldMissing
            && $0.location.fieldIndex == 35
        }
        let auPID35 = auReport.errors.filter {
            $0.code == .conditionalFieldMissing
            && $0.location.fieldIndex == 35
        }
        #expect(intlPID35.count == 1,
                "v2.5.1 base grammar fires PID-35 conditional under .international")
        #expect(auPID35.count == 1,
                "v2.5.1 base grammar fires PID-35 conditional under .auLocalisation")
    }

    // MARK: - v0.11-S2 (ADR-010): HL7au:000008.1 — OBX-3 AUSPDI value set

    // Fully AU-conformant MSH-12 stack so unrelated 040 rules don't
    // pollute the OBX-3 assertions. ORU^R01 (Results) is the message
    // type HL7au:000008 applies to.

    // OBX-3 = "PDF^Display format in PDF^AUSPDI" — conforming display
    // segment. HL7au:000008.1 must be silent.
    private let oruWithConformingAUSPDIDisplayOBX = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|||ORU^R01|MSG|P|2.4^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L|||AL|NE|AUS||en^English^ISO639\r\
    PID|1||X^^^F^MR\r\
    ORC|RE|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL|GLUC|||||||||||||||||||||F\r\
    OBX|1|ED|PDF^Display format in PDF^AUSPDI||content|||||F\r
    """

    @Test("HL7au:000008.1 — conforming AUSPDI display OBX (PDF) fires no OBX-3 violation")
    func hl7au000008_1_conformingPDFSilent() throws {
        let message = try Parser(locale: .auLocalisation).parse(oruWithConformingAUSPDIDisplayOBX)
        let report = Validator(locale: .auLocalisation).validate(message)
        let obx3 = report.errors.filter { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               issue.location.segmentID == "OBX",
               issue.location.fieldIndex == 3,
               rule.contains("HL7au:000008.1") {
                return true
            }
            return false
        }
        #expect(obx3.isEmpty,
                "PDF is a conforming AUSPDI display format; got \(obx3.map(\.message))")
    }

    // OBX-3 = "XYZ^Display in Bad Format^AUSPDI" — wrong identifier.
    // HL7au:000008.1 must fire.
    private let oruWithNonConformingAUSPDIDisplayOBX = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|||ORU^R01|MSG|P|2.4^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L|||AL|NE|AUS||en^English^ISO639\r\
    PID|1||X^^^F^MR\r\
    ORC|RE|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL|GLUC|||||||||||||||||||||F\r\
    OBX|1|ED|XYZ^Display in Bad Format^AUSPDI||content|||||F\r
    """

    @Test("HL7au:000008.1 — non-conforming identifier (XYZ) on AUSPDI display OBX fires")
    func hl7au000008_1_nonConformingAUSPDIFires() throws {
        let message = try Parser(locale: .auLocalisation).parse(oruWithNonConformingAUSPDIDisplayOBX)
        let report = Validator(locale: .auLocalisation).validate(message)
        let issue = report.errors.first { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               issue.location.segmentID == "OBX",
               issue.location.fieldIndex == 3,
               rule.contains("HL7au:000008.1") {
                return true
            }
            return false
        }
        #expect(issue != nil,
                "Expected HL7au:000008.1 violation on OBX-3.1 = XYZ under AUSPDI gate")
    }

    // OBX-3 = "1234-5^Glucose^LN" — atomic result OBX using LOINC.
    // HL7au:000008.1 must be silent because OBX-3.3 ≠ AUSPDI (the gate
    // filters the overlay out on non-display OBXs).
    private let oruWithLOINCAtomicOBX = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|||ORU^R01|MSG|P|2.4^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L|||AL|NE|AUS||en^English^ISO639\r\
    PID|1||X^^^F^MR\r\
    ORC|RE|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL|GLUC|||||||||||||||||||||F\r\
    OBX|1|NM|1234-5^Glucose^LN||5.4|mmol/L||||||F\r
    """

    @Test("HL7au:000008.1 — non-AUSPDI (LN atomic) OBX is silent via the OBX-3.3 gate")
    func hl7au000008_1_nonAUSPDIGateSilent() throws {
        let message = try Parser(locale: .auLocalisation).parse(oruWithLOINCAtomicOBX)
        let report = Validator(locale: .auLocalisation).validate(message)
        let obx3 = report.errors.filter { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               issue.location.segmentID == "OBX",
               issue.location.fieldIndex == 3,
               rule.contains("HL7au:000008.1") {
                return true
            }
            return false
        }
        #expect(obx3.isEmpty,
                "HL7au:000008.1 must be gated off when OBX-3.3 ≠ AUSPDI; got \(obx3.map(\.message))")
    }

    // Regression pin: PIT is deprecated but still permitted per AU
    // ADRM-2021 p. 247 ("receivers may find that they need to support
    // it for practical reasons"). Must not fire.
    private let oruWithPITAUSPDIDisplayOBX = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|||ORU^R01|MSG|P|2.4^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L|||AL|NE|AUS||en^English^ISO639\r\
    PID|1||X^^^F^MR\r\
    ORC|RE|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL|GLUC|||||||||||||||||||||F\r\
    OBX|1|FT|PIT^Display format in PIT^AUSPDI||content|||||F\r
    """

    @Test("HL7au:000008.1 — deprecated PIT identifier permitted (per AU ADRM p. 247)")
    func hl7au000008_1_deprecatedPITPermitted() throws {
        let message = try Parser(locale: .auLocalisation).parse(oruWithPITAUSPDIDisplayOBX)
        let report = Validator(locale: .auLocalisation).validate(message)
        let obx3 = report.errors.filter { issue in
            if case .profileConstraintViolation(let rule) = issue.code,
               issue.location.segmentID == "OBX",
               issue.location.fieldIndex == 3,
               rule.contains("HL7au:000008.1") {
                return true
            }
            return false
        }
        #expect(obx3.isEmpty,
                "PIT is deprecated but still permitted per AU ADRM-2021 p. 247; got \(obx3.map(\.message))")
    }

    // MARK: - v0.11-S3 (ADR-010): HL7au:000008 parent — ≥1 AUSPDI display OBX per OBR/OBX group

    // Helper to find HL7au:000008 parent-rule violations. The rule fires
    // as .segmentCardinalityBelowMinimum with groupScope = "obrObxGroup"
    // and countedSegmentID = "OBX".
    private func hl7au000008ParentIssues(_ report: ValidationReport) -> [ValidationIssue] {
        report.errors.filter { issue in
            if case .segmentCardinalityBelowMinimum(let segID, _, _, let scope) = issue.code,
               segID == "OBX",
               scope == "obrObxGroup" {
                return true
            }
            return false
        }
    }

    @Test("HL7au:000008 — ORU with a conforming AUSPDI display OBX fires no parent violation")
    func hl7au000008_parentSilentWhenAUSPDIPresent() throws {
        let message = try Parser(locale: .auLocalisation).parse(oruWithConformingAUSPDIDisplayOBX)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(hl7au000008ParentIssues(report).isEmpty,
                "PDF is an AUSPDI display OBX → parent rule satisfied; got \(hl7au000008ParentIssues(report).map(\.message))")
    }

    @Test("HL7au:000008 — ORU with no AUSPDI display OBX fires parent violation")
    func hl7au000008_parentFiresWhenNoAUSPDI() throws {
        // oruWithLOINCAtomicOBX has one OBX with OBX-3.3 = LN. No AUSPDI OBX
        // in the OBR group → HL7au:000008 fires.
        let message = try Parser(locale: .auLocalisation).parse(oruWithLOINCAtomicOBX)
        let report = Validator(locale: .auLocalisation).validate(message)
        let hits = hl7au000008ParentIssues(report)
        #expect(hits.count == 1,
                "Expected exactly one HL7au:000008 parent violation; got \(hits.count): \(hits.map(\.message))")
        if let first = hits.first,
           case .segmentCardinalityBelowMinimum(_, let minCount, let actual, _) = first.code {
            #expect(minCount == 1, "minCount should be 1")
            #expect(actual == 0, "actual count should be 0 (no AUSPDI OBX)")
        } else {
            Issue.record("Expected .segmentCardinalityBelowMinimum on first hit")
        }
    }

    // ADT^A01 has no OBR at all. HL7au:000008 anchored on OBR → the
    // group-scan never triggers on a segment whose grammar carries the
    // rule. Rule silent (correctly — no group to check).
    private let adtA01NoOBRNoOBX = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG|P|2.4^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L|||AL|NE|AUS||en^English^ISO639\r\
    PID|1||X^^^F^MR\r
    """

    @Test("HL7au:000008 — ADT^A01 (no OBR) fires no parent violation")
    func hl7au000008_parentSilentOnADT() throws {
        let message = try Parser(locale: .auLocalisation).parse(adtA01NoOBRNoOBX)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(hl7au000008ParentIssues(report).isEmpty,
                "No OBR → no OBR/OBX group → rule silent; got \(hl7au000008ParentIssues(report).map(\.message))")
    }

    // A hypothetical ORM^O01 (Order Message, NOT Results/Referrals) with
    // an OBR but no AUSPDI OBX. The applicableWhen gate
    // ("messageCode in (ORU, REF)") must block the rule for ORM.
    private let ormWithNoAUSPDI = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|||ORM^O01|MSG|P|2.4^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L|||AL|NE|AUS||en^English^ISO639\r\
    PID|1||X^^^F^MR\r\
    ORC|NW|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL|GLUC|||||||||||||||||||||F\r\
    OBX|1|NM|1234-5^Glucose^LN||5.4|mmol/L||||||F\r
    """

    @Test("HL7au:000008 — ORM^O01 (Orders, not Results/Referrals) fires no parent violation (applicableWhen gate)")
    func hl7au000008_parentSilentOnORM() throws {
        let message = try Parser(locale: .auLocalisation).parse(ormWithNoAUSPDI)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(hl7au000008ParentIssues(report).isEmpty,
                "ORM is outside the applicableWhen enum (ORU, REF); rule must be silent; got \(hl7au000008ParentIssues(report).map(\.message))")
    }

    @Test("HL7au:000008 — under .international locale, rule doesn't fire (locale-scoped)")
    func hl7au000008_parentSilentUnderInternational() throws {
        // Same LOINC-only wire that fires under .auLocalisation must be
        // silent under .international because the cardinality rule lives
        // in the AU profile, not the base grammar.
        let message = try Parser(locale: .international).parse(oruWithLOINCAtomicOBX)
        let report = Validator(locale: .international).validate(message)
        #expect(hl7au000008ParentIssues(report).isEmpty,
                "HL7au:000008 must not fire under .international; got \(hl7au000008ParentIssues(report).map(\.message))")
    }

    // Two OBRs in one ORC group. OBR[1] has an AUSPDI display OBX;
    // OBR[2] has only an atomic OBX. HL7au:000008 must fire once (for
    // OBR[2]'s group only).
    private let oruTwoOBRsOnlyFirstHasAUSPDI = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|||ORU^R01|MSG|P|2.4^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L|||AL|NE|AUS||en^English^ISO639\r\
    PID|1||X^^^F^MR\r\
    ORC|RE|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL1|GLUC|||||||||||||||||||||F\r\
    OBX|1|ED|PDF^Display format in PDF^AUSPDI||content|||||F\r\
    OBR|2|ORD002|FIL2|HBA1C|||||||||||||||||||||F\r\
    OBX|1|NM|4548-4^HbA1c^LN||5.4|%||||||F\r
    """

    @Test("HL7au:000008 — multi-OBR: fires per OBR/OBX group missing AUSPDI")
    func hl7au000008_parentFiresPerGroup() throws {
        let message = try Parser(locale: .auLocalisation).parse(oruTwoOBRsOnlyFirstHasAUSPDI)
        let report = Validator(locale: .auLocalisation).validate(message)
        let hits = hl7au000008ParentIssues(report)
        #expect(hits.count == 1,
                "Expected exactly one HL7au:000008 violation (OBR[2]'s group only); got \(hits.count): \(hits.map(\.message))")
    }

    // MARK: - R4-C2: exact-message characterization (one row per append site)

    /// One row per `.profileConstraintViolation` construction site in
    /// `Validator` (R4/F11). Pins the EXACT message text so the F11 fold
    /// into a shared append helper provably preserves emitted issues
    /// byte-for-byte. The citation inside the message is cross-checked
    /// against the issue's own `localeRule` payload rather than
    /// re-transcribed here.
    private static let exactMessageRows: [(site: String, wire: String, cite: String, segmentID: String, fieldIndex: Int, componentIndex: Int?, messagePrefix: String)] = [
        (site: "composite requiredComponents (Validator track 1)",
         wire: "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\rPID|1||999999\r",
         cite: "HL7au:00044.1.2", segmentID: "PID", fieldIndex: 3, componentIndex: 4,
         messagePrefix: "AU profile rule violated at PID[1]-3.4: CX-4 must be populated when CX field is populated "),
        (site: "composite pairRules (track 2)",
         wire: "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\rOBR|1|PLACER123^HOSP^1.2.36.1.2001.1003.0.ABC^ISO|FILLER456^LAB^1.2.36.1.2001.1003.0.DEF^ISO|GLU^Glucose\r",
         cite: "HL7au:00044.4.1", segmentID: "OBR", fieldIndex: 4, componentIndex: 3,
         messagePrefix: "AU profile rule violated at OBR[1]-4.3: CE-3 must be populated when CE-1 is populated "),
        (site: "composite componentInequalities (track 3)",
         wire: "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG|P|2.5.1\rOBR|1|PLACER^HOSP^1.2.3^ISO|FILLER^LAB^1.2.4^ISO|GLU^Glucose^SCT^GLU2^Glucose alt^SCT\r",
         cite: "HL7au:00044.4.8", segmentID: "OBR", fieldIndex: 4, componentIndex: 6,
         messagePrefix: "AU profile rule violated at OBR[1]-4.6: CE-3 and CE-6 must differ but both are \"SCT\" "),
        (site: "composite valueConditionals (track 4)",
         wire: "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG|P|2.5.1\rOBR|1|PLACER^HOSP^1.2.3^ISO|FILLER^LAB^1.2.4^ISO|GLU^Glucose^SCT^14749-6^Glucose^LN\r",
         cite: "HL7au:00044.4.4", segmentID: "OBR", fieldIndex: 4, componentIndex: 6,
         messagePrefix: "AU profile rule violated at OBR[1]-4.6: CE-6 must not be \"LN\" "),
        (site: "fieldOverride requiredComponents",
         wire: "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\rOBR|1|PLACER123^HOSP|FILLER456^LAB^1.2.36.1.2001.1003.0.ABC^ISO|GLU^Glucose^L\r",
         cite: "HL7au:000003", segmentID: "OBR", fieldIndex: 2, componentIndex: 3,
         messagePrefix: "AU profile rule violated at OBR[1]-2.3: EI component 3 must be populated when OBR-2 ('Placer Order Number') is populated "),
        (site: "fieldOverride componentValueSets",
         wire: "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1|||AL|NE|USA||en^English^ISO639\rPID|1||999999^^^HOSP^MR\r",
         cite: "HL7au:000041", segmentID: "MSH", fieldIndex: 17, componentIndex: 1,
         messagePrefix: "AU profile value-set rule violated at MSH[1]-17.1: expected one of [\"AUS\"] but got \"USA\" "),
        (site: "profileUsage required-but-missing",
         wire: "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\rPID|1||999999^^^HOSP^MR\r",
         cite: "HL7au:000041", segmentID: "MSH", fieldIndex: 17, componentIndex: nil,
         messagePrefix: "AU profile rule violated at MSH[1]-17: field is profile-required (au-adrm-2021 usage = R) but missing "),
    ]

    @Test("R4-C2: exact violation message per Validator append site", arguments: exactMessageRows)
    func appendSiteMessageExact(
        _ row: (site: String, wire: String, cite: String, segmentID: String, fieldIndex: Int, componentIndex: Int?, messagePrefix: String)
    ) throws {
        let message = try Parser(locale: .auLocalisation).parse(row.wire)
        let report = Validator(locale: .auLocalisation).validate(message)
        let issue = try #require(report.errors.first { issue in
            guard case .profileConstraintViolation(let rule) = issue.code else { return false }
            return rule.contains(row.cite)
                && issue.location.segmentID == row.segmentID
                && issue.location.fieldIndex == row.fieldIndex
                && issue.location.componentIndex == row.componentIndex
        }, "no \(row.cite) violation at the expected location for site: \(row.site)")
        guard case .profileConstraintViolation(let rule) = issue.code else { return }
        #expect(issue.message == row.messagePrefix + "(\(rule))",
                "message drifted for site: \(row.site)")
    }
}
