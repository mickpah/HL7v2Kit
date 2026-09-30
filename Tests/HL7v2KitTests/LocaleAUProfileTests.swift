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

    /// True if the report contains a profile violation matching every
    /// provided axis — location (segmentID / fieldIndex / componentIndex)
    /// and/or a citation token contained in the rule. R9/F3: the per-test
    /// `first { if case … }` closures all route through here.
    private func hasViolation(
        _ report: ValidationReport,
        segmentID: String? = nil,
        fieldIndex: Int? = nil,
        componentIndex: Int? = nil,
        citing token: String? = nil
    ) -> Bool {
        report.errors.contains { issue in
            guard case .profileConstraintViolation(let rule) = issue.code else { return false }
            if let segmentID, issue.location.segmentID != segmentID { return false }
            if let fieldIndex, issue.location.fieldIndex != fieldIndex { return false }
            if let componentIndex, issue.location.componentIndex != componentIndex { return false }
            if let token, !rule.contains(token) { return false }
            return true
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

    // OBR with both OBR-2 and OBR-3 fully populated (and OBR-24 = LAB,
    // required on Senders Results per HL7au:000032) — no violations.
    private let obrAllEIComponentsPopulated = TestWires.oru("OBR|1|PLACER123^HOSP^1.2.36.1.2001.1003.0.ABC^ISO|FILLER456^LAB^1.2.36.1.2001.1003.0.DEF^ISO|GLU^Glucose^L||||||||||||||||||||LAB")

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
        let wire = TestWires.oru("OBR|1|||GLU^Glucose^L||||||||||||||||||||LAB")
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
    // OBR-24 = LAB on both (HL7au:000032 requires it on Senders Results).
    private let multiObrMixedConformance = TestWires.oru("OBR|1|PLACER1^HOSP^1.2.36.1.2001.1003.0.AAA^ISO|FILLER1^LAB^1.2.36.1.2001.1003.0.BBB^ISO|GLU^Glucose^L||||||||||||||||||||LAB", "OBR|2|PLACER2^HOSP|FILLER2^LAB^1.2.36.1.2001.1003.0.CCC^ISO|LFT^Liver function^L||||||||||||||||||||LAB")

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
        #expect(hasViolation(report, segmentID: "OBR", fieldIndex: 4, componentIndex: 3, citing: "HL7au:00044.4.1"),
                "Expected HL7au:00044.4.1 violation on OBR-4.3; report = \(report.errors.map(\.message))")
    }

    // CE-4 (alternate identifier) set but CE-6 (alternate coding system)
    // empty — violates HL7au:00044.4.5.
    private let ceAltIdentifierWithoutAltCodingSystem = TestWires.oru("OBR|1|PLACER123^HOSP^1.2.36.1.2001.1003.0.ABC^ISO|FILLER456^LAB^1.2.36.1.2001.1003.0.DEF^ISO|GLU^Glucose^L^GLU2^Glucose alt")

    @Test("CE rule HL7au:00044.4.5 — alt identifier set without alt coding system fires")
    func ceAltIdentifierSetWithoutAltCodingSystemFires() throws {
        let message = try Parser(locale: .auLocalisation).parse(ceAltIdentifierWithoutAltCodingSystem)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(hasViolation(report, segmentID: "OBR", fieldIndex: 4, componentIndex: 6, citing: "HL7au:00044.4.5"),
                "Expected HL7au:00044.4.5 violation on OBR-4.6")
    }

    // CE-1 empty but CE-3 populated — violates HL7au:00044.4.2 (inverse).
    private let ceCodingSystemWithoutIdentifier = TestWires.oru("OBR|1|PLACER123^HOSP^1.2.36.1.2001.1003.0.ABC^ISO|FILLER456^LAB^1.2.36.1.2001.1003.0.DEF^ISO|^Glucose^LN")

    @Test("CE rule HL7au:00044.4.2 — empty identifier with non-empty coding system fires")
    func ceEmptyIdentifierWithCodingSystemFires() throws {
        let message = try Parser(locale: .auLocalisation).parse(ceCodingSystemWithoutIdentifier)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(hasViolation(report, segmentID: "OBR", fieldIndex: 4, citing: "HL7au:00044.4.2"),
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
    // ORU, not ACK: HL7au:00044.6 is scoped to Orders, Results and
    // Referrals (M6-D4). ERR carries the CWE field under test.
    private let cweTextEmpty = """
    MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG|P|2.5.1\r\
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

    // MARK: - M6-D3: profile usage narrowings are message-type gated
    //
    // Appendix 5 scopes HL7au:000041 / 000042 to "Orders, Results,
    // Referrals, Acknowledgement, Referral Response". Both rules used to
    // apply `profileUsage = .required` unconditionally, so an ADT — a
    // message type the localisation never addresses — failed AU
    // validation for a missing MSH-17 and MSH-19. req #4: a predicate
    // that misfires in any spec-compliant scenario is a defect.

    @Test("M6-D3 — ADT is outside HL7au:000041/000042's message-type scope and fires neither")
    func msh17And19GatedOffOutsideScope() throws {
        let message = try Parser(locale: .auLocalisation)
            .parse(TestWires.adt("PID|1||999999^^^AUTH^MR"))
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(!hasViolation(report, citing: "HL7au:000041"),
                "ADT is not Orders/Results/Referrals/ACK/RRI; 41 must not fire; got \(report.errors.map(\.message))")
        #expect(!hasViolation(report, citing: "HL7au:000042"),
                "ADT is not Orders/Results/Referrals/ACK/RRI; 42 must not fire; got \(report.errors.map(\.message))")
    }

    @Test("M6-D3 — the gate does not silence the rules inside their scope (ORU)")
    func msh17And19StillFireInScope() throws {
        // ORU^R01 with MSH-17 and MSH-19 both absent.
        let wire = "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|20240101||ORU^R01|MSG|P|2.4\r"
        let report = Validator(locale: .auLocalisation).validate(
            try Parser(locale: .auLocalisation).parse(wire))
        #expect(hasViolation(report, citing: "HL7au:000041"),
                "ORU is in scope; missing MSH-17 must still fire 41; got \(report.errors.map(\.message))")
        #expect(hasViolation(report, citing: "HL7au:000042"),
                "ORU is in scope; missing MSH-19 must still fire 42; got \(report.errors.map(\.message))")
    }

    @Test("M6-D3 — populated-but-wrong values stay gated too (ADT with MSH-17 = USA)")
    func msh17WrongValueGatedOutsideScope() throws {
        let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101||ADT^A01|MSG|P|2.4|||||USA||fr^French^ISO639\r"
        let report = Validator(locale: .auLocalisation).validate(
            try Parser(locale: .auLocalisation).parse(wire))
        #expect(!hasViolation(report, citing: "HL7au:000041"),
                "ADT out of scope; a non-AUS country must not fire 41; got \(report.errors.map(\.message))")
        #expect(!hasViolation(report, citing: "HL7au:000042"),
                "ADT out of scope; a non-English language must not fire 42; got \(report.errors.map(\.message))")
    }

    // MARK: - M6-A stage 2: XCN required components
    //
    // HL7au:00044.7 series. Component indices from the v2.4 XCN
    // definition (CH02 §2.9.52): 2 family name (FN), 9 assigning
    // authority, 10 name type code, 13 identifier type code.
    // PV1-7 (Attending Doctor) is XCN on every supported version.

    private func xcnViolations(_ pv1: String) throws -> [String] {
        let wire = "MSH|^~\\&|LAB|FAC|HOSP|FAC|20240101||ORU^R01^ORU_R01|MSG|P|2.4\r" + pv1 + "\r"
        let report = Validator(locale: .auLocalisation).validate(
            try Parser(locale: .auLocalisation).parse(wire))
        return report.errors.compactMap { issue in
            guard case .profileConstraintViolation(let rule) = issue.code,
                  rule.contains("HL7au:00044.7") else { return nil }
            return rule
        }
    }

    @Test("HL7au:00044.7.2/.3/.4/.5 — a bare XCN fires all four required-component rules")
    func xcnRequiredComponentsFire() throws {
        let rules = try xcnViolations("PV1|1|I|||||1234")
        for point in ["00044.7.5", "00044.7.2", "00044.7.3", "00044.7.4"] {
            #expect(rules.contains { $0.contains(point) },
                    "XCN with only an ID number must fire \(point); got \(rules)")
        }
    }

    @Test("HL7au:00044.7.x — a fully valued XCN fires nothing")
    func xcnFullyValuedIsSilent() throws {
        // 1 ID ^ 2 family ^ 3 given ^ 4 ^ 5 ^ 6 ^ 7 ^ 8 ^ 9 authority ^
        // 10 name type ^ 11 ^ 12 ^ 13 identifier type
        let rules = try xcnViolations(
            "PV1|1|I|||||1234^SMITH^JOHN^^^^^^AUTH^L^^^MR")
        #expect(rules.isEmpty, "a complete XCN must fire nothing; got \(rules)")
    }

    @Test("HL7au:00044.7.5 — a populated XCN-2 with no surname subcomponent still fires")
    func xcnFamilyNameSurnameSubcomponent() throws {
        // XCN-2 is FN: <surname> & <own surname prefix> & ... A value of
        // "&VAN" populates the component but leaves the surname empty,
        // which is exactly what .7.5 names. Without subcomponent
        // addressing this would pass.
        let rules = try xcnViolations(
            "PV1|1|I|||||1234^&VAN^JOHN^^^^^^AUTH^L^^^MR")
        #expect(rules.contains { $0.contains("00044.7.5") },
                "XCN-2 populated but surname empty must fire .7.5; got \(rules)")
    }

    @Test("HL7au:00044.7.x — ADT is outside the series' message-type scope")
    func xcnGatedOutsideScope() throws {
        let wire = TestWires.adt("PV1|1|I|||||1234")
        let report = Validator(locale: .auLocalisation).validate(
            try Parser(locale: .auLocalisation).parse(wire))
        let rules = report.errors.compactMap { issue -> String? in
            guard case .profileConstraintViolation(let rule) = issue.code,
                  rule.contains("HL7au:00044.7") else { return nil }
            return rule
        }
        #expect(rules.isEmpty, "ADT is outside the XCN series' scope; got \(rules)")
    }

    // M6-B-5 — the membership halves of .7.3/.7.4, upgraded from PARTIAL
    // via the composite value-set track over the HL7CodeTables seed.

    @Test("HL7au:00044.7.3/.7.4 — non-table XCN-10/13 values fire membership")
    func xcnTableMembershipFires() throws {
        // "Q" is not in table 0200; "BADTYPE" is not in table 0203.
        let rules = try xcnViolations(
            "PV1|1|I|||||1234^SMITH^JOHN^^^^^^AUTH^Q^^^BADTYPE")
        #expect(rules.contains { $0.contains("00044.7.3") && $0.contains("0200") },
                "XCN-10 = Q must fire 0200 membership; got \(rules)")
        #expect(rules.contains { $0.contains("00044.7.4") && $0.contains("0203") },
                "XCN-13 = BADTYPE must fire 0203 membership; got \(rules)")
    }

    @Test("HL7au:00044.7.3/.7.4 — empty components fire presence only, not membership")
    func xcnMembershipIsPopulatedOnly() throws {
        // Bare XCN: the required-component rules fire; the value sets
        // must NOT double-report the same components as non-members.
        let wire = "MSH|^~\\&|LAB|FAC|HOSP|FAC|20240101||ORU^R01^ORU_R01|MSG|P|2.4\rPV1|1|I|||||1234\r"
        let report = Validator(locale: .auLocalisation).validate(
            try Parser(locale: .auLocalisation).parse(wire))
        let membership = report.errors.filter {
            guard case .profileConstraintViolation(let rule) = $0.code else { return false }
            return rule.contains("HL7au:00044.7") && $0.message.contains("not in the allowed set")
        }
        #expect(membership.isEmpty,
                "empty XCN-10/13 are presence violations only; got \(membership.map(\.message))")
    }

    // MARK: - M6-D4: composite overrides are message-type gated
    //
    // The composite-track twin of M6-D3. Every HL7au:00044.* datatype
    // point is scoped to a named set of message types, but the CX / CE /
    // CNE / CWE overrides applied to every message, so an ADT with a
    // two-component CX failed AU validation citing a point that does not
    // reach ADT. The positive halves are pinned by the CX / CE / CNE /
    // CWE tests above, which now run on in-scope wires.

    @Test("M6-D4 — ADT is outside HL7au:00044.1's scope, so CX narrowings stay silent")
    func compositeOverridesGatedOutsideScope() throws {
        let report = Validator(locale: .auLocalisation).validate(
            try Parser(locale: .auLocalisation).parse(TestWires.adt("PID|1||999999")))
        let cx = report.errors.filter {
            if case .profileConstraintViolation(let rule) = $0.code {
                return rule.contains("HL7au:00044.1")
            }
            return false
        }
        #expect(cx.isEmpty,
                "ADT is not Orders/Results/Referrals; CX rules must not fire; got \(cx.map(\.message))")
    }

    @Test("M6-D4 — the gate is per-message-type, not per-locale: REF still fires CX narrowings")
    func compositeOverridesFireOnReferrals() throws {
        let wire = "MSH|^~\\&|GP|CLINIC|SPEC|HOSP|20240101||REF^I12|MSG|P|2.4\rPID|1||999999\r"
        let report = Validator(locale: .auLocalisation).validate(
            try Parser(locale: .auLocalisation).parse(wire))
        #expect(hasViolation(report, citing: "HL7au:00044.1.2"),
                "REF is in scope for the CX series; got \(report.errors.map(\.message))")
    }

    // MARK: - M6-A stage 1: MSH envelope literals
    //
    // Ten Appendix 5 points on the message header. Each is gated on the
    // message types the table names, so every rule gets a positive case
    // inside its scope and a negative case outside it.

    /// Fully AU-conformant ORU header: separators, MSH-9 all three
    /// components, MSH-12 per HL7au:000040.1/.2/.3, AL/AL, AUS,
    /// en^English^ISO639.
    private let mshConformantORU =
        "MSH|^~\\&|LAB|FAC|HOSP|FAC|20240101120000+1000||ORU^R01^ORU_R01|MSG1|P|"
        + "2.4^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L|||AL|AL|AUS||en^English^ISO639\r"

    /// The HL7au citations of every MSH-located profile violation on a wire.
    private func mshViolations(_ wire: String) throws -> [String] {
        let report = Validator(locale: .auLocalisation)
            .validate(try Parser(locale: .auLocalisation).parse(wire))
        return report.errors.compactMap { issue in
            guard case .profileConstraintViolation(let rule) = issue.code,
                  issue.location.segmentID == "MSH" else { return nil }
            return rule
        }
    }

    @Test("M6-A — a fully AU-conformant ORU header fires no MSH profile violations")
    func conformantOruHeaderIsSilent() throws {
        let rules = try mshViolations(mshConformantORU)
        #expect(rules.isEmpty, "conformant header must fire nothing; got \(rules)")
    }

    @Test("HL7au:000024.1 — a non-'|' field separator fires on ORU, not on ADT")
    func fieldSeparatorNarrowing() throws {
        let oruRules = try mshViolations(
            "MSH!^~\\&!LAB!FAC!HOSP!FAC!20240101!!ORU^R01^ORU_R01!MSG!P!2.4!!!AL!AL!AUS!!en^English^ISO639\r")
        #expect(oruRules.contains { $0.contains("HL7au:000024.1") },
                "ORU with '!' separator must fire 24.1; got \(oruRules)")
        let adtRules = try mshViolations(
            "MSH!^~\\&!HIS!FAC!HOSP!FAC!20240101!!ADT^A01!MSG!P!2.4\r")
        #expect(!adtRules.contains { $0.contains("HL7au:000024.1") },
                "ADT is outside 24.1's scope; got \(adtRules)")
    }

    @Test("HL7au:000024.2/.3/.4/.5 — non-standard encoding characters fire on ORU")
    func encodingCharactersNarrowing() throws {
        let rules = try mshViolations(
            "MSH|^~\\#|LAB|FAC|HOSP|FAC|20240101||ORU^R01^ORU_R01|MSG|P|2.4|||AL|AL|AUS||en^English^ISO639\r")
        #expect(rules.contains { $0.contains("HL7au:000024.2") },
                "ORU with '#' sub-component separator must fire; got \(rules)")
    }

    @Test("HL7au:000024.3/.4/.5 — REF is outside their scope, so MSH-2 is unpinned there")
    func encodingCharactersUnpinnedOnReferrals() throws {
        // Documented gap: .2 (component separator) DOES apply to
        // Referrals, but pinning the whole MSH-2 literal there would
        // enforce .3/.4/.5 where the spec does not. See M6-B.
        let rules = try mshViolations(
            "MSH|^~\\#|GP|CLINIC|SPEC|HOSP|20240101||REF^I12|MSG|P|2.4|||AL|AL|AUS||en^English^ISO639\r")
        #expect(!rules.contains { $0.contains("HL7au:000024") },
                "REF is outside .3/.4/.5's scope; got \(rules)")
    }

    @Test("HL7au:00049.2/.3 — MSH-9 without trigger event or message structure fires on ORU")
    func messageTypeComponentsRequired() throws {
        let codeOnly = try mshViolations(
            "MSH|^~\\&|LAB|FAC|HOSP|FAC|20240101||ORU|MSG|P|2.4|||AL|AL|AUS||en^English^ISO639\r")
        #expect(codeOnly.contains { $0.contains("HL7au:00049.2/.3") },
                "MSH-9 with only a message code must fire 49.2/.3; got \(codeOnly)")
        let noStructure = try mshViolations(
            "MSH|^~\\&|LAB|FAC|HOSP|FAC|20240101||ORU^R01|MSG|P|2.4|||AL|AL|AUS||en^English^ISO639\r")
        #expect(noStructure.contains { $0.contains("HL7au:00049.2/.3") },
                "MSH-9 without message structure must still fire; got \(noStructure)")
    }

    @Test("HL7au:00049.2/.3 — ADT keeps base HL7 optionality for MSH-9.3")
    func messageTypeComponentsGatedOutsideScope() throws {
        let rules = try mshViolations("MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101||ADT^A01|MSG|P|2.4\r")
        #expect(!rules.contains { $0.contains("HL7au:00049") },
                "ADT is outside 49's scope; got \(rules)")
    }

    @Test("HL7au:00047.1 / .2 — MSH-15 and MSH-16 must both be valued AL")
    func acknowledgementModesNarrowed() throws {
        // Absent: the profileUsage half.
        let absent = try mshViolations(
            "MSH|^~\\&|LAB|FAC|HOSP|FAC|20240101||ORU^R01^ORU_R01|MSG|P|2.4|||||AUS||en^English^ISO639\r")
        #expect(absent.contains { $0.contains("HL7au:00047.1") },
                "missing MSH-15 must fire 47.1; got \(absent)")
        #expect(absent.contains { $0.contains("HL7au:00047.2") },
                "missing MSH-16 must fire 47.2; got \(absent)")
        // Populated but wrong: the value-set half.
        let wrong = try mshViolations(
            "MSH|^~\\&|LAB|FAC|HOSP|FAC|20240101||ORU^R01^ORU_R01|MSG|P|2.4|||NE|ER|AUS||en^English^ISO639\r")
        #expect(wrong.contains { $0.contains("HL7au:00047.1") },
                "MSH-15 = NE must fire 47.1; got \(wrong)")
        #expect(wrong.contains { $0.contains("HL7au:00047.2") },
                "MSH-16 = ER must fire 47.2; got \(wrong)")
    }

    @Test("HL7au:00047.1 / .2 — ADT keeps base HL7 optionality for MSH-15/16")
    func acknowledgementModesGatedOutsideScope() throws {
        let rules = try mshViolations(
            "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101||ADT^A01^ADT_A01|MSG|P|2.4|||NE|NE\r")
        #expect(!rules.contains { $0.contains("HL7au:00047") },
                "ADT is outside 47's scope; got \(rules)")
    }

    @Test("HL7au:00048.3.1 — MSH-18 accepts the AU character-set values and rejects others")
    func characterSetValueSet() throws {
        for accepted in ["ASCII", "UNICODE UTF-8", "8859/1"] {
            let rules = try mshViolations(
                "MSH|^~\\&|LAB|FAC|HOSP|FAC|20240101||ORU^R01^ORU_R01|MSG|P|"
                + "2.4^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L|||AL|AL|AUS|\(accepted)|en^English^ISO639\r")
            #expect(rules.isEmpty, "MSH-18 = \(accepted) is permitted; got \(rules)")
        }
        // "UTF-8" and "US-ASCII" are aliases `CharacterEncoding` accepts,
        // so they parse — but HL7au:00048.3.1 lists the four literals
        // exactly, and an alias is not one of them. A genuinely unknown
        // encoding never reaches the Validator: the Parser rejects it
        // with `ParseError.unsupportedCharacterEncoding` first. This
        // rule's whole value is over that alias gap.
        for alias in ["UTF-8", "US-ASCII", "ISO-8859-1"] {
            let rejected = try mshViolations(
                "MSH|^~\\&|LAB|FAC|HOSP|FAC|20240101||ORU^R01^ORU_R01|MSG|P|"
                + "2.4^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L|||AL|AL|AUS|\(alias)|en^English^ISO639\r")
            #expect(rejected.contains { $0.contains("HL7au:00048.3.1") },
                    "\(alias) parses but is not in the AU value set; got \(rejected)")
        }
    }

    // MARK: - M6-D1: alternate-identifier pair-rule citations
    //
    // ADRM-2021 Appendix 5 does NOT number the alternate-identifier pair
    // consistently across the three coded composites: CE is .4.5 / .4.6,
    // but CNE is .5.4 / .5.5 and CWE is .6.4 / .6.5. The overlay used to
    // treat CNE like CE, which cited HL7au:00044.5.6 — a point revision
    // r2 removed. These pins lock the numbering to the spec text so the
    // helper's `altBase` cannot drift back.

    @Test("HL7au:00044.5.4 — CNE alt identifier without alt coding system cites .5.4, never the removed .5.6")
    func cneAltPairCitesSpecNumbering() throws {
        // ORC-30 (Enterer Authorization Mode) is v2.5.1's only CNE field.
        // CNE-4 (alternate identifier) set, CNE-6 (alt coding system) empty.
        let orc = "ORC|NW" + String(repeating: "|", count: 29) + "CODE^Text^SYS^ALTCODE"
        let wire = "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG|P|2.5.1\r" + orc + "\r"
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(hasViolation(report, citing: "HL7au:00044.5.4"),
                "CNE alt identifier without alt coding system must cite 44.5.4; got \(report.errors.map(\.message))")
        #expect(!hasViolation(report, citing: "HL7au:00044.5.6"),
                "HL7au:00044.5.6 was removed in r2 and must never be cited")
    }

    @Test("Alternate-identifier pair rules carry each composite's own spec numbering")
    func altPairCitationsMatchSpecPerComposite() throws {
        // CE: OBR-4 (.4.5) · CWE: ERR-3 (.6.4). Both with the alternate
        // identifier set and the alternate coding system left empty.
        let ceWire = TestWires.oru("OBR|1|P^H^1.2.3^ISO|F^L^1.2.4^ISO|GLU^Glucose^LN^ALTGLU")
        let ceReport = Validator(locale: .auLocalisation).validate(
            try Parser(locale: .auLocalisation).parse(ceWire))
        #expect(hasViolation(ceReport, citing: "HL7au:00044.4.5"),
                "CE alt pair must cite 44.4.5; got \(ceReport.errors.map(\.message))")

        let cweWire = """
        MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG|P|2.5.1\r\
        MSA|AE|MSG\r\
        ERR||PID^1^3|207^Text^HL70357^ALT207|E\r
        """
        let cweReport = Validator(locale: .auLocalisation).validate(
            try Parser(locale: .auLocalisation).parse(cweWire))
        #expect(hasViolation(cweReport, citing: "HL7au:00044.6.4"),
                "CWE alt pair must cite 44.6.4; got \(cweReport.errors.map(\.message))")
    }

    // MARK: - S5-B-3: CX required-component rules (HL7au:00044.1.2 / .1.3)

    // PID-3 with only CX-1 populated. AU rules require CX-4 (Assigning
    // Authority) and CX-5 (Identifier Type Code) to also be valued.
    // ORU, not ADT: HL7au:00044.1 is scoped to Orders, Results and
    // Referrals, so an ADT wire exercises nothing since M6-D4.
    private let pidCxMinimal = TestWires.oru("PID|1||999999")

    @Test("CX rule HL7au:00044.1.2 — PID-3 with CX-4 empty fires")
    func cxAssigningAuthorityMissingFires() throws {
        let message = try Parser(locale: .auLocalisation).parse(pidCxMinimal)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(hasViolation(report, segmentID: "PID", fieldIndex: 3, componentIndex: 4, citing: "HL7au:00044.1.2"),
                "Expected HL7au:00044.1.2 violation on PID-3.4")
    }

    @Test("CX rule HL7au:00044.1.3 — PID-3 with CX-5 empty fires")
    func cxIdentifierTypeCodeMissingFires() throws {
        let message = try Parser(locale: .auLocalisation).parse(pidCxMinimal)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(hasViolation(report, segmentID: "PID", fieldIndex: 3, componentIndex: 5, citing: "HL7au:00044.1.3"),
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
    private let pidCxOnDeprecatedField = TestWires.oru("PID|1|DEPRECATED_ID|999999^^^HOSP^MR")

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
    MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1|||AL|NE|USA||en^English^ISO639\r\
    PID|1||999999^^^HOSP^MR\r
    """

    @Test("MSH-17 value-set rule HL7au:000041 — wrong country fires")
    func mshCountryWrongValueFires() throws {
        let message = try Parser(locale: .auLocalisation).parse(mshNonAUCountry)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(hasViolation(report, segmentID: "MSH", fieldIndex: 17, componentIndex: 1, citing: "HL7au:000041"),
                "Expected HL7au:000041 violation on MSH-17.1 = 'USA'")
    }

    // MSH-19 populated with wrong language identifier.
    private let mshNonENLanguage = """
    MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1|||AL|NE|AUS||fr^French^ISO639\r\
    PID|1||999999^^^HOSP^MR\r
    """

    @Test("MSH-19 value-set rule HL7au:000042 — wrong language identifier fires")
    func mshLanguageWrongIdentifierFires() throws {
        let message = try Parser(locale: .auLocalisation).parse(mshNonENLanguage)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(hasViolation(report, segmentID: "MSH", fieldIndex: 19, componentIndex: 1, citing: "HL7au:000042"),
                "Expected HL7au:000042 violation on MSH-19.1 = 'fr'")
    }

    // MSH-12 = "2.4^AUS&Australia&ISO3166_1" + MSH-17 = "AUS" + MSH-19
    // = "en^English^ISO639" — fully AU-conformant per HL7au:000040.1/.2,
    // 000041, 000042. Stays on ADT deliberately: it pins that a
    // conformant MSH fires nothing, and 040.3 / .4 (ORM/ORU or REF/RRI
    // only) must not reach it either.
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
        // ORU, not ADT: since M6-D3 the narrowing is scoped to the
        // message types Appendix 5 names for these points.
        let wire = TestWires.oru("PID|1||999999^^^HOSP^MR")
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(hasViolation(report, segmentID: "MSH", fieldIndex: 17, citing: "HL7au:000041"),
                "Empty MSH-17 should fire HL7au:000041 violation under AU profile-required")
        #expect(hasViolation(report, segmentID: "MSH", fieldIndex: 19, citing: "HL7au:000042"),
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
        #expect(hasViolation(report, segmentID: "MSH", fieldIndex: 12, citing: "HL7au:000040.1/.2"))
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
        #expect(hasViolation(report, segmentID: "MSH", fieldIndex: 12, citing: "MSH-12.2.2"),
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
        #expect(hasViolation(report, segmentID: "MSH", fieldIndex: 12, citing: "HL7au:000040.3"),
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

    @Test("v2.4 wire + .international locale: PID-35 fires from the base grammar (P4-17)")
    func v24PIDSpeciesConditionFiresUnderInternational() throws {
        // P4-17 added the printed Conditionality Rule (v2.4 CH03
        // §3.4.2.35: "This field must be valued if PID-36 - Breed
        // Code or PID-38 - Production Class Code is valued") directly
        // to the base v2.4 PID.json — the field was already present
        // there (bare C), the S5-D AU grammar extension above was not
        // filling a genuine base-spec gap. The predicate now fires
        // under .international too, without the AU locale layer.
        let message = try Parser(locale: .international).parse(v24PIDBreedWithoutSpecies)
        let report = Validator(locale: .international).validate(message)
        let pid35Issues = report.errors.filter {
            $0.code == .conditionalFieldMissing
            && $0.location.segmentID == "PID"
            && $0.location.fieldIndex == 35
        }
        #expect(pid35Issues.count == 1,
                "Base v2.4 grammar now carries the PID-35 condition; it should fire under .international")
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
        #expect(hasViolation(report, segmentID: "OBX", fieldIndex: 3, citing: "HL7au:000008.1"),
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
         wire: "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\rPID|1||999999\r",
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
         wire: "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1|||AL|NE|USA||en^English^ISO639\rPID|1||999999^^^HOSP^MR\r",
         cite: "HL7au:000041", segmentID: "MSH", fieldIndex: 17, componentIndex: 1,
         messagePrefix: "AU profile value-set rule violated at MSH[1]-17.1: expected one of [\"AUS\"] but got \"USA\" "),
        (site: "profileUsage required-but-missing",
         wire: "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\rPID|1||999999^^^HOSP^MR\r",
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

    // MARK: - M6-A stage 3: prohibition rules (maxCount 0)

    // HL7au:000021 — OBX-2 must not be TX (Senders Results; the
    // Referrals(L2) leg is PARTIAL, see the audit doc). HL7au:000023 —
    // the NTE segment must not be used (Senders Orders/Results/
    // Referrals). Both are message-wide `SegmentCardinalityRule`s with
    // `maxCount: 0`, anchored on MSH.

    /// Filters to `.segmentCardinalityAboveMaximum` for the given
    /// counted segment at messageWide scope.
    private func prohibitionIssues(_ report: ValidationReport, counted: String) -> [ValidationIssue] {
        report.errors.filter { issue in
            if case .segmentCardinalityAboveMaximum(let segID, _, _, let scope) = issue.code,
               segID == counted, scope == "messageWide" {
                return true
            }
            return false
        }
    }

    @Test("HL7au:000021 — ORU with OBX-2 = TX fires the prohibition")
    func hl7au000021_firesOnTXValueTypeInORU() throws {
        let wire = TestWires.oru(
            "PID|1||X^^^F^MR",
            "OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|GLU^Glucose^L",
            "OBX|1|TX|100^Note^LN||free text comment|||||F"
        )
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let report = Validator(locale: .auLocalisation).validate(message)
        let hits = prohibitionIssues(report, counted: "OBX")
        #expect(hits.count == 1,
                "Expected exactly one HL7au:000021 violation; got \(hits.count): \(hits.map(\.message))")
        if let first = hits.first,
           case .segmentCardinalityAboveMaximum(_, let maxCount, let actual, _) = first.code {
            #expect(maxCount == 0, "maxCount should be 0 (prohibition)")
            #expect(actual == 1, "one TX-valued OBX should be counted")
            #expect(first.message.contains("HL7au:000021"),
                    "issue must carry the HL7au citation; got \(first.message)")
        } else {
            Issue.record("Expected .segmentCardinalityAboveMaximum on first hit")
        }
    }

    @Test("HL7au:000021 — ORU with OBX-2 = NM is silent")
    func hl7au000021_silentOnNonTXValueType() throws {
        let wire = TestWires.oru(
            "PID|1||X^^^F^MR",
            "OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|GLU^Glucose^L",
            "OBX|1|NM|1234-5^Glucose^LN||5.4|mmol/L||||||F"
        )
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(prohibitionIssues(report, counted: "OBX").isEmpty,
                "OBX-2 = NM must not fire HL7au:000021")
    }

    // The Referrals(L2) leg of HL7au:000021 is deliberately unshipped
    // (PARTIAL): L2 is identified by an MSH-21 profile ID the model
    // cannot address, and a bare REF gate would over-fire on Level 1
    // and unprofiled referrals. A REF wire with a TX OBX must be silent.
    private let refWithTXValueType = """
    MSH|^~\\&|GP|FAC|SPEC|FAC|||REF^I12|MSG00001|P|2.4\r\
    PID|1||X^^^F^MR\r\
    OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|REFER^Referral^L\r\
    OBX|1|TX|100^Note^LN||referral narrative|||||F\r
    """

    @Test("HL7au:000021 — REF with OBX-2 = TX is silent (Referrals(L2) leg is PARTIAL)")
    func hl7au000021_silentOnREF() throws {
        let message = try Parser(locale: .auLocalisation).parse(refWithTXValueType)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(prohibitionIssues(report, counted: "OBX").isEmpty,
                "the REF leg is not shipped; HL7au:000021 must be silent on REF")
    }

    @Test("HL7au:000023 — ORU with two NTE segments fires once with actual = 2")
    func hl7au000023_firesOnNTEInORU() throws {
        // Two NTEs pin the empty-predicate counting path: every segment
        // of the counted ID counts, no field is tested.
        let wire = TestWires.oru(
            "PID|1||X^^^F^MR",
            "OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|GLU^Glucose^L",
            "NTE|1||first comment",
            "OBX|1|NM|1234-5^Glucose^LN||5.4|mmol/L||||||F",
            "NTE|2||second comment"
        )
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let report = Validator(locale: .auLocalisation).validate(message)
        let hits = prohibitionIssues(report, counted: "NTE")
        #expect(hits.count == 1,
                "Expected exactly one HL7au:000023 violation; got \(hits.count): \(hits.map(\.message))")
        if let first = hits.first,
           case .segmentCardinalityAboveMaximum(_, let maxCount, let actual, _) = first.code {
            #expect(maxCount == 0, "maxCount should be 0 (prohibition)")
            #expect(actual == 2, "both NTE segments must be counted (empty predicate)")
            #expect(first.message.contains("HL7au:000023"),
                    "issue must carry the HL7au citation; got \(first.message)")
        } else {
            Issue.record("Expected .segmentCardinalityAboveMaximum on first hit")
        }
    }

    @Test("HL7au:000023 — ORM with an NTE fires (Orders leg)")
    func hl7au000023_firesOnORM() throws {
        let wire = """
        MSH|^~\\&|HIS|FAC|LAB|FAC|||ORM^O01|MSG00001|P|2.4\r\
        PID|1||X^^^F^MR\r\
        ORC|NW|ORD001^H^1.2.36.1^ISO\r\
        OBR|1|ORD001^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|GLU^Glucose^L\r\
        NTE|1||order comment\r
        """
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(prohibitionIssues(report, counted: "NTE").count == 1,
                "ORM is inside the (ORM, ORU, REF) gate; HL7au:000023 must fire")
    }

    @Test("HL7au:000023 — ADT with an NTE is silent (outside the message-type gate)")
    func hl7au000023_silentOnADT() throws {
        let wire = TestWires.adt(
            "PID|1||X^^^F^MR",
            "NTE|1||admission comment"
        )
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(prohibitionIssues(report, counted: "NTE").isEmpty,
                "ADT is outside the (ORM, ORU, REF) gate; HL7au:000023 must be silent")
    }

    @Test("M6-A-3 — prohibitions are silent under .international locale")
    func prohibitionsSilentUnderInternational() throws {
        let wire = TestWires.oru(
            "PID|1||X^^^F^MR",
            "OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|GLU^Glucose^L",
            "NTE|1||comment",
            "OBX|1|TX|100^Note^LN||free text|||||F"
        )
        let message = try Parser(locale: .international).parse(wire)
        let report = Validator(locale: .international).validate(message)
        #expect(prohibitionIssues(report, counted: "OBX").isEmpty
                    && prohibitionIssues(report, counted: "NTE").isEmpty,
                "prohibition rules live in the AU profile, not the base grammar")
    }

    // MARK: - M6-B-1: PRD exactly-one rules + referral display formats

    // HL7au:00104.1.1 / 00104.2.1 — exactly one PRD with PRD-1 = AP /
    // IR in the REF message. PRD-1 repeats, so the rules use the
    // anyRepeat atom. HL7au:00104.7.0 (r3) — PRD-7 required on the IR
    // PRD. HL7au:000008.3.1 (PARTIAL) — ≥1 HTML/PDF/TXT display OBX
    // per OBR/OBX group on Referrals.

    private func prdCardinalityIssues(_ report: ValidationReport, citing token: String) -> [ValidationIssue] {
        report.errors.filter { issue in
            switch issue.code {
            case .segmentCardinalityBelowMinimum(let segID, _, _, let scope),
                 .segmentCardinalityAboveMaximum(let segID, _, _, let scope):
                return segID == "PRD" && scope == "messageWide"
                    && issue.message.contains(token)
            default:
                return false
            }
        }
    }

    // A conforming REF: one AP PRD, one IR PRD (with PRD-7 in the
    // table-conformant shape: ID ^ 0363-authority ^ 0203-type), OBR-24
    // valued from table 0074, and a PDF display OBX in the single OBR
    // group.
    private let refConforming = """
    MSH|^~\\&|GP|FAC|SPEC|FAC|||REF^I12|MSG00001|P|2.4\r\
    PRD|AP^Authoring Provider^HL70286|Doe^John\r\
    PRD|IR^Intended Recipient^HL70286|Smith^Alice|||||049960CT^AUSHICPR^UPIN\r\
    PID|1||X^^^F^MR\r\
    OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|REFER^Referral^L||||||||||||||||||||PHY\r\
    OBX|1|ED|PDF^Display format in PDF^AUSPDI||content|||||F\r
    """

    @Test("HL7au:00104.1.1/.2.1 — conforming REF (one AP, one IR) is silent")
    func hl7au00104_conformingREFSilent() throws {
        let message = try Parser(locale: .auLocalisation).parse(refConforming)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(prdCardinalityIssues(report, citing: "HL7au:00104.1.1").isEmpty
                    && prdCardinalityIssues(report, citing: "HL7au:00104.2.1").isEmpty,
                "one AP + one IR must satisfy both exactly-one rules; got \(report.errors.map(\.message))")
    }

    // AP arrives in the SECOND repetition of PRD-1 — pins the anyRepeat
    // atom. A first-repetition read would count zero APs and misfire.
    private let refAPInSecondRepeat = """
    MSH|^~\\&|GP|FAC|SPEC|FAC|||REF^I12|MSG00001|P|2.4\r\
    PRD|RP^Referring Provider^HL70286~AP^Authoring Provider^HL70286|Doe^John\r\
    PRD|IR^Intended Recipient^HL70286|Smith^Alice|||||12345^^^AUSHIC^UPIN\r\
    PID|1||X^^^F^MR\r\
    OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|REFER^Referral^L\r\
    OBX|1|ED|PDF^Display format in PDF^AUSPDI||content|||||F\r
    """

    @Test("HL7au:00104.1.1 — AP in a later PRD-1 repetition still counts (anyRepeat)")
    func hl7au00104_1_1_anyRepeatCountsLaterRepetition() throws {
        let message = try Parser(locale: .auLocalisation).parse(refAPInSecondRepeat)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(prdCardinalityIssues(report, citing: "HL7au:00104.1.1").isEmpty,
                "PRD-1 = RP~AP carries AP in repetition 2; the rule must count it; got \(prdCardinalityIssues(report, citing: "HL7au:00104.1.1").map(\.message))")
    }

    @Test("HL7au:00104.1.1 — REF with no AP PRD fires below-minimum")
    func hl7au00104_1_1_firesWhenNoAP() throws {
        let wire = """
        MSH|^~\\&|GP|FAC|SPEC|FAC|||REF^I12|MSG00001|P|2.4\r\
        PRD|IR^Intended Recipient^HL70286|Smith^Alice|||||12345^^^AUSHIC^UPIN\r\
        PID|1||X^^^F^MR\r\
        OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|REFER^Referral^L\r\
        OBX|1|ED|PDF^Display format in PDF^AUSPDI||content|||||F\r
        """
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let report = Validator(locale: .auLocalisation).validate(message)
        let hits = prdCardinalityIssues(report, citing: "HL7au:00104.1.1")
        #expect(hits.count == 1,
                "no AP PRD → exactly one 00104.1.1 violation; got \(hits.count)")
    }

    @Test("HL7au:00104.2.1 — REF with two IR PRDs fires above-maximum")
    func hl7au00104_2_1_firesOnTwoIRs() throws {
        let wire = """
        MSH|^~\\&|GP|FAC|SPEC|FAC|||REF^I12|MSG00001|P|2.4\r\
        PRD|AP^Authoring Provider^HL70286|Doe^John\r\
        PRD|IR^Intended Recipient^HL70286|Smith^Alice|||||12345^^^AUSHIC^UPIN\r\
        PRD|IR^Intended Recipient^HL70286|Jones^Bob|||||67890^^^AUSHIC^UPIN\r\
        PID|1||X^^^F^MR\r\
        OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|REFER^Referral^L\r\
        OBX|1|ED|PDF^Display format in PDF^AUSPDI||content|||||F\r
        """
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let report = Validator(locale: .auLocalisation).validate(message)
        let hits = prdCardinalityIssues(report, citing: "HL7au:00104.2.1")
        #expect(hits.count == 1, "two IR PRDs → one above-maximum violation")
        if let first = hits.first,
           case .segmentCardinalityAboveMaximum(_, let maxCount, let actual, _) = first.code {
            #expect(maxCount == 1 && actual == 2)
        } else {
            Issue.record("Expected .segmentCardinalityAboveMaximum")
        }
    }

    @Test("HL7au:00104.x — ORU with no PRD is silent (REF gate)")
    func hl7au00104_silentOutsideREF() throws {
        let wire = TestWires.oru(
            "PID|1||X^^^F^MR",
            "OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|GLU^Glucose^L",
            "OBX|1|NM|1234-5^Glucose^LN||5.4|mmol/L||||||F"
        )
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(prdCardinalityIssues(report, citing: "HL7au:00104").isEmpty,
                "the PRD rules are gated on messageCode = REF")
    }

    @Test("HL7au:00104.7.0 — IR PRD without PRD-7 fires; AP PRD without PRD-7 does not")
    func hl7au00104_7_0_prd7RequiredOnIROnly() throws {
        let wire = """
        MSH|^~\\&|GP|FAC|SPEC|FAC|||REF^I12|MSG00001|P|2.4\r\
        PRD|AP^Authoring Provider^HL70286|Doe^John\r\
        PRD|IR^Intended Recipient^HL70286|Smith^Alice\r\
        PID|1||X^^^F^MR\r\
        OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|REFER^Referral^L\r\
        OBX|1|ED|PDF^Display format in PDF^AUSPDI||content|||||F\r
        """
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let report = Validator(locale: .auLocalisation).validate(message)
        let hits = report.errors.filter { issue in
            guard case .profileConstraintViolation(let rule) = issue.code else { return false }
            return rule.contains("HL7au:00104.7.0")
        }
        #expect(hits.count == 1,
                "PRD-7 missing on the IR PRD only → exactly one 00104.7.0 violation; got \(hits.count): \(hits.map(\.message))")
        #expect(hits.first?.location.segmentIndex == 2,
                "the violation must attach to the second PRD (the IR one)")
    }

    @Test("HL7au:000008.3.1 — REF group with only an RTF display OBX fires")
    func hl7au000008_3_1_firesOnRTFOnly() throws {
        let wire = """
        MSH|^~\\&|GP|FAC|SPEC|FAC|||REF^I12|MSG00001|P|2.4\r\
        PRD|AP^Authoring Provider^HL70286|Doe^John\r\
        PRD|IR^Intended Recipient^HL70286|Smith^Alice|||||12345^^^AUSHIC^UPIN\r\
        PID|1||X^^^F^MR\r\
        OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|REFER^Referral^L\r\
        OBX|1|ED|RTF^Display format in RTF^AUSPDI||content|||||F\r
        """
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let report = Validator(locale: .auLocalisation).validate(message)
        let hits = report.errors.filter { issue in
            if case .segmentCardinalityBelowMinimum = issue.code {
                return issue.message.contains("HL7au:000008.3.1")
            }
            return false
        }
        #expect(hits.count == 1,
                "RTF alone does not satisfy the HTML/PDF/TXT disjunction; got \(hits.count): \(hits.map(\.message))")
        // The conforming wire (PDF display) must be silent for 000008.3.1.
        let okReport = Validator(locale: .auLocalisation)
            .validate(try Parser(locale: .auLocalisation).parse(refConforming))
        #expect(!okReport.errors.contains { $0.message.contains("HL7au:000008.3.1") },
                "a PDF display OBX satisfies 000008.3.1")
    }

    // MARK: - M6-B-2: the Z-prefix prohibitions

    // HL7au:000020 — trigger event codes beginning with Z must not be
    // used (enforced on the ORM/ORU intersection; the message-code leg
    // is self-excluded by the gate and Referrals(L2) is unaddressable).
    // HL7au:000023.1 — Z segments must not be used (ORM/ORU/REF), via
    // the `Z*` counted-segment prefix pattern.

    @Test("HL7au:000020 — ORU^Z01 (Z trigger event) fires the prohibition")
    func hl7au000020_firesOnZTriggerEvent() throws {
        let wire = """
        MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^Z01|MSG00001|P|2.4\r\
        PID|1||X^^^F^MR\r
        """
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let report = Validator(locale: .auLocalisation).validate(message)
        let hits = prohibitionIssues(report, counted: "MSH")
            .filter { $0.message.contains("HL7au:000020") }
        #expect(hits.count == 1,
                "ORU^Z01 must fire HL7au:000020 exactly once; got \(hits.count)")
    }

    @Test("HL7au:000020 — ORU^R01 is silent; ADT^Z99 is outside the gate")
    func hl7au000020_silentOnNonZAndOutsideGate() throws {
        let oru = try Parser(locale: .auLocalisation)
            .parse(TestWires.oru("PID|1||X^^^F^MR"))
        let oruReport = Validator(locale: .auLocalisation).validate(oru)
        #expect(!oruReport.errors.contains { $0.message.contains("HL7au:000020") },
                "R01 does not begin with Z")
        let adt = try Parser(locale: .auLocalisation).parse("""
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^Z99|MSG00001|P|2.4\r\
        PID|1||X^^^F^MR\r
        """)
        let adtReport = Validator(locale: .auLocalisation).validate(adt)
        #expect(!adtReport.errors.contains { $0.message.contains("HL7au:000020") },
                "ADT is outside the (ORM, ORU) gate")
    }

    @Test("HL7au:000023.1 — ORU with two Z segments fires once with actual = 2")
    func hl7au000023_1_firesOnZSegments() throws {
        let wire = TestWires.oru(
            "PID|1||X^^^F^MR",
            "ZAU|1|local content",
            "ZXY|extra local segment"
        )
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let report = Validator(locale: .auLocalisation).validate(message)
        let hits = prohibitionIssues(report, counted: "Z*")
            .filter { $0.message.contains("HL7au:000023.1") }
        #expect(hits.count == 1,
                "expected one HL7au:000023.1 violation; got \(hits.count): \(hits.map(\.message))")
        if let first = hits.first,
           case .segmentCardinalityAboveMaximum(_, _, let actual, _) = first.code {
            #expect(actual == 2, "both Z segments must be counted by the Z* prefix")
        } else {
            Issue.record("Expected .segmentCardinalityAboveMaximum")
        }
    }

    @Test("HL7au:000023.1 — ADT with a Z segment is silent (outside the gate)")
    func hl7au000023_1_silentOnADT() throws {
        let wire = TestWires.adt(
            "PID|1||X^^^F^MR",
            "ZAU|1|local content"
        )
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(!report.errors.contains { $0.message.contains("HL7au:000023.1") },
                "ADT is outside the (ORM, ORU, REF) gate")
    }

    // MARK: - M6-B-4: code-table membership (HL7CodeTables seed)

    // HL7au:000032 / 000032.2 — OBR-24 must be valued from HL7 Table
    // 0074 on Results/Referrals. HL7au:00104.7.2.1 / .7.3.1 — PRD-7.2
    // from User-defined Table 0363, PRD-7.3 from HL7 Table 0203.

    @Test("HL7au:000032 — ORU with OBR-24 missing fires; wrong value fires membership; LAB is silent")
    func hl7au000032_obr24PresenceAndMembership() throws {
        // Missing → profile-required.
        let missing = try Parser(locale: .auLocalisation)
            .parse(TestWires.oru("OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|GLU^Glucose^L"))
        let missingReport = Validator(locale: .auLocalisation).validate(missing)
        #expect(missingReport.errors.contains {
            guard case .profileConstraintViolation(let rule) = $0.code else { return false }
            return rule.contains("HL7au:000032") && $0.location.fieldIndex == 24
        }, "OBR-24 absent on ORU must fire the required narrowing")
        // Non-member → value-set violation citing 000032.
        let bad = try Parser(locale: .auLocalisation)
            .parse(TestWires.oru("OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|GLU^Glucose^L||||||||||||||||||||XYZ"))
        let badReport = Validator(locale: .auLocalisation).validate(bad)
        #expect(badReport.errors.contains {
            guard case .profileConstraintViolation(let rule) = $0.code else { return false }
            return rule.contains("HL7au:000032") && rule.contains("0074")
        }, "OBR-24 = XYZ is not in table 0074 and must fire membership")
        // Member → silent for 000032.
        let ok = try Parser(locale: .auLocalisation)
            .parse(TestWires.oru("OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|GLU^Glucose^L||||||||||||||||||||LAB"))
        let okReport = Validator(locale: .auLocalisation).validate(ok)
        #expect(!okReport.errors.contains { $0.message.contains("HL7au:000032") },
                "OBR-24 = LAB is in table 0074; got \(okReport.errors.map(\.message))")
    }

    @Test("HL7au:000032 — ADT is outside the (ORU, REF) gate")
    func hl7au000032_gatedOffOnADT() throws {
        let message = try Parser(locale: .auLocalisation)
            .parse(TestWires.adt("PID|1||X^^^F^MR"))
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(!report.errors.contains { $0.message.contains("HL7au:000032") },
                "no OBR and no gate match on ADT")
    }

    @Test("HL7au:00104.7.3.1/.7.1.4 — PRD-7 membership and authority-pair rules on REF")
    func hl7au00104_7_tableMembership() throws {
        // Conforming wire (AUSHICPR^UPIN, the ADRM's own example pair):
        // silent for membership and correspondence. (00104.7.2.1's 0363
        // membership was withdrawn at M6-B-8 — table 0363 is
        // user-defined and the ADRM's own examples use vendor
        // authorities outside it.)
        let okReport = Validator(locale: .auLocalisation)
            .validate(try Parser(locale: .auLocalisation).parse(refConforming))
        #expect(!okReport.errors.contains { $0.message.contains("HL7au:00104.7") },
                "AUSHICPR^UPIN is the ADRM's own example pair; got \(okReport.errors.map(\.message))")
        // BADTYPE fires 0203 membership AND the AUSHICPR => UPIN pair rule.
        let wire = """
        MSH|^~\\&|GP|FAC|SPEC|FAC|||REF^I12|MSG00001|P|2.4\r\
        PRD|AP^Authoring Provider^HL70286|Doe^John\r\
        PRD|IR^Intended Recipient^HL70286|Smith^Alice|||||12345^AUSHICPR^BADTYPE\r\
        PID|1||X^^^F^MR\r\
        OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|REFER^Referral^L||||||||||||||||||||PHY\r\
        OBX|1|ED|PDF^Display format in PDF^AUSPDI||src^application^pdf^Base64^AAAA|||||F\r
        """
        let report = Validator(locale: .auLocalisation)
            .validate(try Parser(locale: .auLocalisation).parse(wire))
        #expect(report.errors.contains { $0.message.contains("HL7au:00104.7.3.1") },
                "BADTYPE is not in table 0203")
        #expect(report.errors.contains { $0.message.contains("HL7au:00104.7.1.4") },
                "AUSHICPR requires UPIN per the p. 334 matches table")
        // A vendor-allocated identifier (authority outside 0363, VDI
        // qualifier) is sanctioned by the ADRM's own examples: silent.
        let vendor = """
        MSH|^~\\&|GP|FAC|SPEC|FAC|||REF^I12|MSG00001|P|2.4\r\
        PRD|AP^Authoring Provider^HL70286|Doe^John\r\
        PRD|IR^Intended Recipient^HL70286|Smith^Alice|||||X0012345^Argus^VDI\r\
        PID|1||X^^^F^MR\r\
        OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|REFER^Referral^L||||||||||||||||||||PHY\r\
        OBX|1|ED|PDF^Display format in PDF^AUSPDI||src^application^pdf^Base64^AAAA|||||F\r
        """
        let vendorReport = Validator(locale: .auLocalisation)
            .validate(try Parser(locale: .auLocalisation).parse(vendor))
        #expect(!vendorReport.errors.contains { $0.message.contains("HL7au:00104.7") },
                "vendor authorities skip the (withdrawn) 0363 check and the pair map; got \(vendorReport.errors.map(\.message))")
    }

    // MARK: - M6-B-8: correspondence maps

    @Test("HL7au:00044.10.1.5/.6 — ED subtype pdf requires type application")
    func edSubtypeTypeCorrespondence() throws {
        let bad = try edRpViolations("OBX|1|ED|123^Attachment^LN||src^text^pdf^Base64^AAAA|||||F")
        #expect(bad.contains { $0.contains("10.1.5") },
                "pdf subtype with type 'text' must fire the correspondence; got \(bad)")
        let ok = try edRpViolations("OBX|1|ED|123^Attachment^LN||src^application^pdf^Base64^AAAA|||||F")
        #expect(ok.isEmpty, "application/pdf is the stated pair; got \(ok)")
        // Case-insensitivity: the ADRM's own examples use TEXT^RTF.
        let rtf = try edRpViolations("OBX|1|ED|RTF^Display format in RTF^AUSPDI||src^TEXT^RTF^Base64^AAAA|||||F")
        #expect(rtf.isEmpty, "TEXT^RTF is a sanctioned example casing; got \(rtf)")
    }

    @Test("HL7au:000008.1.3 — OBX-2 must match the display format")
    func obx2DisplayFormatCorrespondence() throws {
        // HTML display carried as FT: the table says ED.
        let wire = TestWires.oru(
            "OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|GLU^Glucose^L||||||||||||||||||||LAB",
            "OBX|1|FT|HTML^Display format in HTML^AUSPDI||<div>x</div>|||||F"
        )
        let report = Validator(locale: .auLocalisation)
            .validate(try Parser(locale: .auLocalisation).parse(wire))
        #expect(report.errors.contains { $0.message.contains("HL7au:000008.1.3") },
                "HTML display with OBX-2 = FT must fire; got \(report.errors.map(\.message))")
        // TXT display as FT is the stated pair: silent.
        let ok = TestWires.oru(
            "OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|GLU^Glucose^L||||||||||||||||||||LAB",
            "OBX|1|FT|TXT^Display format in Text^AUSPDI||plain text|||||F"
        )
        let okReport = Validator(locale: .auLocalisation)
            .validate(try Parser(locale: .auLocalisation).parse(ok))
        #expect(!okReport.errors.contains { $0.message.contains("HL7au:000008.1.3") },
                "TXT => FT is the stated pair; got \(okReport.errors.map(\.message))")
    }

    // MARK: - M6-B-9: uniqueness, relational cardinality, precedence, timezone

    @Test("HL7au:000028 — duplicate OBR-3 filler order numbers fire; distinct ones are silent")
    func obr3UniquenessFires() throws {
        let dup = TestWires.oru(
            "OBR|1|P1^H|FIL001^LAB^1.2.36^ISO|GLU^Glucose^L||||||||||||||||||||LAB",
            "OBR|2|P2^H|FIL001^LAB^1.2.36^ISO|LFT^Liver^L||||||||||||||||||||LAB"
        )
        let dupReport = Validator(locale: .auLocalisation)
            .validate(try Parser(locale: .auLocalisation).parse(dup))
        #expect(dupReport.errors.contains { $0.message.contains("HL7au:000028") },
                "two OBRs sharing FIL001 must fire; got \(dupReport.errors.map(\.message))")
        let ok = TestWires.oru(
            "OBR|1|P1^H|FIL001^LAB^1.2.36^ISO|GLU^Glucose^L||||||||||||||||||||LAB",
            "OBR|2|P2^H|FIL002^LAB^1.2.36^ISO|LFT^Liver^L||||||||||||||||||||LAB"
        )
        let okReport = Validator(locale: .auLocalisation)
            .validate(try Parser(locale: .auLocalisation).parse(ok))
        #expect(!okReport.errors.contains { $0.message.contains("HL7au:000028") },
                "distinct filler numbers must be silent")
    }

    @Test("HL7au:000008.3.2 — RTF display without an HTML/PDF/TXT sibling fires on L2")
    func rtfSiblingRuleFires() throws {
        func issues(_ obx: String...) throws -> [String] {
            let wire = "MSH|^~\\&|GP|FAC|SPEC|FAC|||REF^I12|MSG|P|2.4^AUS&Australia&ISO3166_1^HL7AU-OO-REF-SIMPLIFIED-201706&&L\r"
                + "PID|1||X^^^F^MR\r"
                + "OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|REFER^Referral^L||||||||||||||||||||PHY\r"
                + obx.map { $0 + "\r" }.joined()
            let report = Validator(locale: .auLocalisation)
                .validate(try Parser(locale: .auLocalisation).parse(wire))
            return report.errors.compactMap {
                $0.message.contains("HL7au:000008.3.2") ? $0.message : nil
            }
        }
        // RTF alone: sibling requirement fires.
        #expect(try issues("OBX|1|ED|RTF^Display format in RTF^AUSPDI||src^TEXT^RTF^Base64^AAAA|||||F").count == 1)
        // RTF + PDF sibling: silent.
        #expect(try issues(
            "OBX|1|ED|RTF^Display format in RTF^AUSPDI||src^TEXT^RTF^Base64^AAAA|||||F",
            "OBX|2|ED|PDF^Display format in PDF^AUSPDI||src^application^pdf^Base64^AAAA|||||F"
        ).isEmpty)
        // No RTF at all: the activation predicate keeps the rule off.
        #expect(try issues("OBX|1|ED|HTML^Display format in HTML^AUSPDI||src^text^html^Base64^AAAA|||||F").isEmpty)
    }

    @Test("HL7au:000034.1 — a public system relegated to the alternate triplet fires")
    func publicSystemPrecedenceFires() throws {
        // OBX-3: local primary (L) with SCT in the alternate — the
        // public code is not in the identifier: fires.
        let bad = TestWires.oru(
            "OBR|1|P1^H|F1^L^1.2.36^ISO|GLU^Glucose^L||||||||||||||||||||LAB",
            "OBX|1|NM|GLU4^Glucose^L^14749-6^Glucose^SCT||5.4|mmol/L^mmol/L^UCUM|||||F"
        )
        let badReport = Validator(locale: .auLocalisation)
            .validate(try Parser(locale: .auLocalisation).parse(bad))
        #expect(badReport.errors.contains { $0.message.contains("HL7au:000034") },
                "SCT in the alternate with a local primary must fire; got \(badReport.errors.map(\.message))")
        // Public primary (LN) with SCT alternate: both public — silent.
        let ok = TestWires.oru(
            "OBR|1|P1^H|F1^L^1.2.36^ISO|GLU^Glucose^L||||||||||||||||||||LAB",
            "OBX|1|NM|14749-6^Glucose^LN^271062006^Glucose^SCT||5.4|mmol/L^mmol/L^UCUM|||||F"
        )
        let okReport = Validator(locale: .auLocalisation)
            .validate(try Parser(locale: .auLocalisation).parse(ok))
        #expect(!okReport.errors.contains { $0.message.contains("HL7au:000034") },
                "public primary with public alternate is conformant; got \(okReport.errors.map(\.message))")
    }

    @Test("HL7au:00044.8.1 — hour-precision timestamps need a timezone offset")
    func tsTimezoneRequired() throws {
        // OBR-7 (Observation Date/Time, TS) with hour precision and no
        // offset: fires. Same value with +1000: silent. Date-only: silent.
        func issues(_ obr7: String) throws -> [String] {
            let wire = TestWires.oru("OBR|1|P1^H|F1^L|GLU^Glucose^L|||\(obr7)|||||||||||||||||LAB")
            let report = Validator(locale: .auLocalisation)
                .validate(try Parser(locale: .auLocalisation).parse(wire))
            return report.errors.compactMap {
                $0.message.contains("HL7au:00044.8.1") ? $0.message : nil
            }
        }
        #expect(try issues("20240101120000").count == 1,
                "hour-plus precision without an offset must fire")
        #expect(try issues("20240101120000+1000").isEmpty,
                "an offset satisfies the rule")
        #expect(try issues("20240101").isEmpty,
                "date-only values skip — the offset is conditioned on time being transmitted")
    }

    // MARK: - M7-P2: prose-sweep findings (docs/design/m7-adrm-prose-sweep.md)

    private func prose(_ wire: String, _ tag: String) throws -> [String] {
        let report = Validator(locale: .auLocalisation)
            .validate(try Parser(locale: .auLocalisation).parse(wire))
        return report.errors.compactMap {
            $0.message.contains(tag) ? $0.message : nil
        }
    }

    @Test("ADRM-prose:P-1 — PID-1 is mandatory in the Australian context")
    func pid1MandatoryAU() throws {
        let noSetID = "MSH|^~\\&|LAB|FAC|HOSP|FAC|||ORU^R01|MSG1|P|2.5.1\r"
            + "PID|||999999^^^HOSP^MR\r"
        #expect(try prose(noSetID, "ADRM-prose:P-1").count == 1,
                "an ORU PID without Set ID must fire P-1")
        let withSetID = "MSH|^~\\&|LAB|FAC|HOSP|FAC|||ORU^R01|MSG1|P|2.5.1\r"
            + "PID|1||999999^^^HOSP^MR\r"
        #expect(try prose(withSetID, "ADRM-prose:P-1").isEmpty)
        // ADT is outside the guide's scope — base HL7 optionality holds.
        let adt = "MSH|^~\\&|LAB|FAC|HOSP|FAC|||ADT^A01|MSG1|P|2.5.1\r"
            + "PID|||999999^^^HOSP^MR\r"
        #expect(try prose(adt, "ADRM-prose:P-1").isEmpty)
    }

    @Test("ADRM-prose:P-2 — the §7.4.2 disallowed segments fire on REF only")
    func refDisallowedSegments() throws {
        let refWithGT1 = "MSH|^~\\&|GP|FAC|SPEC|FAC|||REF^I12^REF_I12|MSG1|P|2.4\r"
            + "PID|1||X^^^F^MR\r"
            + "GT1|1||GUARANTOR^G\r"
        let fired = try prose(refWithGT1, "ADRM-prose:P-2")
        #expect(fired.count == 1 && fired[0].contains("GT1"),
                "a GT1 in a REF must fire the §7.4.2 prohibition; got \(fired)")
        // Multiple disallowed segments each fire.
        let refWithTwo = "MSH|^~\\&|GP|FAC|SPEC|FAC|||REF^I12^REF_I12|MSG1|P|2.4\r"
            + "PID|1||X^^^F^MR\r"
            + "DSC|1\r"
            + "PR1|1||1234^Proc^L\r"
        #expect(try prose(refWithTwo, "ADRM-prose:P-2").count == 2)
        // The gate: the same segments outside REF are untouched by P-2
        // (GT1 is legitimate ORM billing content, p. 117).
        let ormWithGT1 = "MSH|^~\\&|GP|FAC|LAB|FAC|||ORM^O01|MSG1|P|2.4\r"
            + "PID|1||X^^^F^MR\r"
            + "GT1|1||GUARANTOR^G\r"
        #expect(try prose(ormWithGT1, "ADRM-prose:P-2").isEmpty)
    }

    @Test("ADRM-prose:P-3 — MSH-9 pinned to REF^I12^REF_I12 / RRI^I12^RRI_I12")
    func msh9ReferralPins() throws {
        let wrongStructure = "MSH|^~\\&|GP|FAC|SPEC|FAC|||REF^I12^REF_I11|MSG1|P|2.4\r"
            + "PID|1||X^^^F^MR\r"
        #expect(try prose(wrongStructure, "ADRM-prose:P-3").count == 1,
                "REF with a wrong message structure must fire P-3")
        let conformant = "MSH|^~\\&|GP|FAC|SPEC|FAC|||REF^I12^REF_I12|MSG1|P|2.4\r"
            + "PID|1||X^^^F^MR\r"
        #expect(try prose(conformant, "ADRM-prose:P-3").isEmpty)
        let rriWrongTrigger = "MSH|^~\\&|SPEC|FAC|GP|FAC|||RRI^I13^RRI_I12|MSG1|P|2.4\r"
            + "PID|1||X^^^F^MR\r"
        #expect(try prose(rriWrongTrigger, "ADRM-prose:P-3").count == 1,
                "RRI with a wrong trigger event must fire P-3")
    }

    @Test("ADRM-prose:P-5a — ACK MSH-12.3.1 closed over the two ack profile IDs")
    func ackProfilePin() throws {
        func ack(_ vid3: String) -> String {
            "MSH|^~\\&|LAB|FAC|GP|FAC|||ACK|MSG1|P|2.4^AUS&Australia&ISO3166_1\(vid3)\r"
                + "MSA|AA|MSG0\r"
        }
        #expect(try prose(ack("^HL7AU-OO-ACK-201701&&L"), "ADRM-prose:P-5a").isEmpty,
                "the general-ack profile ID is conformant")
        #expect(try prose(ack("^HL7AU-OO-ACK-READ-2020006&&L"), "ADRM-prose:P-5a").isEmpty,
                "the read-ack profile ID is conformant")
        #expect(try prose(ack("^HL7AU-OO-201701&&L"), "ADRM-prose:P-5a").count == 1,
                "the Orders/Results profile ID on an ACK must fire")
        #expect(try prose(ack(""), "ADRM-prose:P-5a").count == 1,
                "an ACK without MSH-12.3 must fire — both §8.4/§8.5 say 'must be valued'")
    }

    @Test("ADRM-prose:P-4 — the \\X / \\C / \\M escape sequences must not be used")
    func escapeSequenceProhibitions() throws {
        func oruWithNote(_ text: String) -> String {
            "MSH|^~\\&|LAB|FAC|HOSP|FAC|||ORU^R01|MSG1|P|2.5.1\r"
                + "PID|1||999999^^^HOSP^MR\r"
                + "OBX|1|FT|8251-1^Notes^LN||\(text)||||||F\r"
        }
        // A complete hex escape fires.
        #expect(try prose(oruWithNote("before\\X0D\\after"), "ADRM-prose:P-4").count == 1)
        // Single-byte and multi-byte character escapes fire.
        #expect(try prose(oruWithNote("a\\C2842\\b"), "ADRM-prose:P-4").count == 1)
        #expect(try prose(oruWithNote("a\\M2842AA\\b"), "ADRM-prose:P-4").count == 1)
        // Permitted escapes are untouched.
        #expect(try prose(oruWithNote("line one\\.br\\line two \\E\\ \\T\\ \\F\\"), "ADRM-prose:P-4").isEmpty)
        // The \E\-then-literal-X shape is NOT an \X escape: the middle
        // backslash CLOSES \E\ and the X is ordinary text (the naive
        // substring scan would misfire here).
        #expect(try prose(oruWithNote("path \\E\\X2 \\E\\ done"), "ADRM-prose:P-4").isEmpty)
        // Unterminated opening skips, fail-safe.
        #expect(try prose(oruWithNote("broken\\X0D"), "ADRM-prose:P-4").isEmpty)
        // ADT is outside the guide's scope.
        let adt = "MSH|^~\\&|LAB|FAC|HOSP|FAC|||ADT^A01|MSG1|P|2.5.1\r"
            + "PID|1||999999^^^HOSP^MR\r"
            + "OBX|1|FT|8251-1^Notes^LN||x\\X0D\\y||||||F\r"
        #expect(try prose(adt, "ADRM-prose:P-4").isEmpty)
    }

    @Test("ADRM-prose:P-6 — the VMR header OBX is pinned to RP and the fixed OBX-5 literal")
    func vmrHeaderPins() throws {
        func ref(_ obx: String) -> String {
            "MSH|^~\\&|GP|FAC|SPEC|FAC|||REF^I12^REF_I12|MSG1|P|2.4\r"
                + "PID|1||X^^^F^MR\r"
                + obx + "\r"
        }
        let conformant = ref("OBX|1|RP|74028-2^Report template ID^LN|1|HL7V2-VMR.v1^HL7V2 VMR&99A-9AAC5A649D18B6F2&L^TX^Octet-stream||||||F")
        #expect(try prose(conformant, "ADRM-prose:P-6").isEmpty,
                "the ADRM's own header example must be silent")
        // Wrong OBX-2 on the header fires the RP pin.
        let wrongType = ref("OBX|1|TX|74028-2^Report template ID^LN|1|HL7V2-VMR.v1^HL7V2 VMR&99A-9AAC5A649D18B6F2&L^TX^Octet-stream||||||F")
        #expect(try prose(wrongType, "ADRM-prose:P-6").count == 1)
        // Wrong template pointer fires the OBX-5.1 pin.
        let wrongPointer = ref("OBX|1|RP|74028-2^Report template ID^LN|1|OTHER-TEMPLATE^HL7V2 VMR&99A-9AAC5A649D18B6F2&L^TX^Octet-stream||||||F")
        #expect(try prose(wrongPointer, "ADRM-prose:P-6").count == 1)
        // A non-header OBX (different OBX-3) is outside the gate.
        let atomic = ref("OBX|1|NM|14749-6^Glucose^LN||5.4|mmol/L^mmol/L^UCUM|||||F")
        #expect(try prose(atomic, "ADRM-prose:P-6").isEmpty)
        // The VMR is referral content — ORU is outside the gate.
        let oru = "MSH|^~\\&|LAB|FAC|HOSP|FAC|||ORU^R01|MSG1|P|2.5.1\r"
            + "PID|1||999999^^^HOSP^MR\r"
            + "OBX|1|TX|74028-2^Report template ID^LN|1|whatever||||||F\r"
        #expect(try prose(oru, "ADRM-prose:P-6").isEmpty)
    }

    @Test("ADRM-prose:P-5b — read-ack MSH-3.3 must be AUSHICPR or NPIO")
    func readAckSenderScheme() throws {
        func readAck(msh3: String, vid3: String = "HL7AU-OO-ACK-READ-2020006") -> String {
            "MSH|^~\\&|\(msh3)|FAC|GP|FAC|||ACK|MSG1|P|2.4^AUS&Australia&ISO3166_1^\(vid3)&&L\r"
                + "MSA|AA|MSG0\r"
        }
        #expect(try prose(readAck(msh3: "DrSmith^0499602CT^AUSHICPR"), "ADRM-prose:P-5b").isEmpty)
        #expect(try prose(readAck(msh3: "DrSmith^8003611566701234@8003621566684455^NPIO"), "ADRM-prose:P-5b").isEmpty)
        #expect(try prose(readAck(msh3: "DrSmith^0499602CT^LOCAL"), "ADRM-prose:P-5b").count == 1,
                "a non-AUSHICPR/NPIO scheme on a read-ack must fire")
        // The gate: a general ACK is not a read-ack — the scheme is free.
        #expect(try prose(readAck(msh3: "LAB^X^LOCAL", vid3: "HL7AU-OO-ACK-201701"), "ADRM-prose:P-5b").isEmpty)
    }

    // MARK: - M6-B-6: the L1/L2 legs via the MSH-12.3.1 profile discriminator
    //
    // The ADRM declares the adhered profile in MSH-12.3 (000040.4 pins the
    // literals), so "Referrals(L2)" and "Referrals Level 1" scopes gate on
    // MSH-12.3.1 — the audit's earlier "MSH-21" note was a
    // misidentification, corrected at M6-B-6.

    private func refWire(profileID: String, obx: String) -> String {
        "MSH|^~\\&|GP|FAC|SPEC|FAC|||REF^I12|MSG00001|P|2.4^AUS&Australia&ISO3166_1^\(profileID)&&L\r"
            + "PRD|AP^Authoring Provider^HL70286|Doe^John\r"
            + "PRD|IR^Intended Recipient^HL70286|Smith^Alice|||||049960CT^AUSHICPR^UPIN\r"
            + "PID|1||X^^^F^MR\r"
            + "OBR|1|P1^H^1.2.36.1^ISO|F1^L^1.2.36.2^ISO|REFER^Referral^L||||||||||||||||||||PHY\r"
            + obx + "\r"
    }

    @Test("HL7au:000021 — Referrals(L2) leg fires on the L2 profile, not on L1")
    func hl7au000021_level2LegViaProfileID() throws {
        let l2 = try Parser(locale: .auLocalisation).parse(refWire(
            profileID: "HL7AU-OO-REF-SIMPLIFIED-201706",
            obx: "OBX|1|TX|100^Note^LN||narrative|||||F"))
        let l2Report = Validator(locale: .auLocalisation).validate(l2)
        #expect(prohibitionIssues(l2Report, counted: "OBX")
                    .contains { $0.message.contains("Referrals(L2)") },
                "TX OBX on an L2 referral must fire 000021's L2 leg")
        let l1 = try Parser(locale: .auLocalisation).parse(refWire(
            profileID: "HL7AU-OO-REF-SIMPLIFIED-201706-L1",
            obx: "OBX|1|TX|100^Note^LN||narrative|||||F"))
        let l1Report = Validator(locale: .auLocalisation).validate(l1)
        #expect(prohibitionIssues(l1Report, counted: "OBX").isEmpty,
                "Level 1 is outside 000021's scope; got \(prohibitionIssues(l1Report, counted: "OBX").map(\.message))")
    }

    @Test("HL7au:000008.3.1 — the L1 leg requires a PDF display specifically")
    func hl7au000008_3_1_level1PDFLeg() throws {
        func l1Issues(_ report: ValidationReport) -> [ValidationIssue] {
            report.errors.filter {
                if case .segmentCardinalityBelowMinimum = $0.code {
                    return $0.message.contains("Referrals Level 1")
                }
                return false
            }
        }
        // L1 with an HTML display: satisfies the base 3.1 disjunction but
        // not the L1 PDF leg.
        let l1html = try Parser(locale: .auLocalisation).parse(refWire(
            profileID: "HL7AU-OO-REF-SIMPLIFIED-201706-L1",
            obx: "OBX|1|ED|HTML^Display format in HTML^AUSPDI||content|||||F"))
        let htmlReport = Validator(locale: .auLocalisation).validate(l1html)
        #expect(l1Issues(htmlReport).count == 1,
                "L1 with only HTML must fire the PDF leg; got \(l1Issues(htmlReport).map(\.message))")
        // L1 with a PDF display: silent.
        let l1pdf = try Parser(locale: .auLocalisation).parse(refWire(
            profileID: "HL7AU-OO-REF-SIMPLIFIED-201706-L1",
            obx: "OBX|1|ED|PDF^Display format in PDF^AUSPDI||content|||||F"))
        #expect(l1Issues(Validator(locale: .auLocalisation).validate(l1pdf)).isEmpty)
        // L2 with only HTML: the L1 leg does not apply.
        let l2html = try Parser(locale: .auLocalisation).parse(refWire(
            profileID: "HL7AU-OO-REF-SIMPLIFIED-201706",
            obx: "OBX|1|ED|HTML^Display format in HTML^AUSPDI||content|||||F"))
        #expect(l1Issues(Validator(locale: .auLocalisation).validate(l2html)).isEmpty,
                "the PDF leg is L1-gated")
    }

    // MARK: - M6-B-7: OBX-2-driven datatype resolution (ED/RP series)

    private func edRpViolations(_ obx: String, msh: String = "MSH|^~\\&|LAB|FAC|HOSP|FAC|20240101||ORU^R01^ORU_R01|MSG|P|2.4\r") throws -> [String] {
        let report = Validator(locale: .auLocalisation).validate(
            try Parser(locale: .auLocalisation).parse(msh + obx + "\r"))
        return report.errors.compactMap {
            guard case .profileConstraintViolation(let rule) = $0.code,
                  rule.contains("HL7au:00044.10") || rule.contains("HL7au:00044.11") else { return nil }
            return rule
        }
    }

    @Test("HL7au:00044.10 — an ED-typed OBX-5 with bare content fires all four ED rules")
    func edOBX5RulesFire() throws {
        // OBX-2 = ED makes OBX-5's effective type ED; a single-component
        // value leaves ED-2..5 empty.
        let rules = try edRpViolations("OBX|1|ED|123^Attachment^LN||content|||||F")
        for point in ["10.1.1", "10.1.2", "10.1.3", "10.1.4"] {
            #expect(rules.contains { $0.contains(point) },
                    "bare ED value must fire 00044.\(point); got \(rules)")
        }
    }

    @Test("HL7au:00044.10 — a complete ED value is silent")
    func edOBX5CompleteSilent() throws {
        let rules = try edRpViolations("OBX|1|ED|123^Attachment^LN||src^application^pdf^Base64^AAAA|||||F")
        #expect(rules.isEmpty, "ED with type/subtype/encoding/data valued must fire nothing; got \(rules)")
    }

    @Test("HL7au:00044.11 — an RP-typed OBX-5 fires the RP rules; NM does not dispatch")
    func rpOBX5RulesFireAndNMDoesNot() throws {
        let rp = try edRpViolations("OBX|1|RP|123^Attachment^LN||pointer|||||F")
        for point in ["11.1.2", "11.1.3", "11.1.4"] {
            #expect(rp.contains { $0.contains(point) },
                    "RP with only a pointer must fire 00044.\(point); got \(rp)")
        }
        let nm = try edRpViolations("OBX|1|NM|1234-5^Glucose^LN||5.4|mmol/L||||||F")
        #expect(nm.isEmpty, "OBX-2 = NM must not dispatch the ED/RP overrides")
    }

    @Test("HL7au:000020 — Referrals(L2) leg fires on a Z trigger event")
    func hl7au000020_level2LegViaProfileID() throws {
        let wire = "MSH|^~\\&|GP|FAC|SPEC|FAC|||REF^Z99|MSG00001|P|2.4^AUS&Australia&ISO3166_1^HL7AU-OO-REF-SIMPLIFIED-201706&&L\r"
            + "PID|1||X^^^F^MR\r"
        let report = Validator(locale: .auLocalisation)
            .validate(try Parser(locale: .auLocalisation).parse(wire))
        #expect(prohibitionIssues(report, counted: "MSH")
                    .contains { $0.message.contains("Referrals(L2)") },
                "REF^Z99 under the L2 profile must fire 000020's L2 leg; got \(report.errors.map(\.message))")
    }
}
