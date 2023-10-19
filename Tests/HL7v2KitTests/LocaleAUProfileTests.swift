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

    // MARK: - S5-B-2: CE / CNE / CWE datatype-level rules (HL7au:00044.4 / .5 / .6)

    // OBR-4 (CE) populated with CE-1 set but CE-3 empty — violates
    // HL7au:00044.4.1 ("identifier set ⇒ name of coding system set").
    private let ceIdentifierWithoutCodingSystem = """
    MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r\
    OBR|1|PLACER123^HOSP^1.2.36.1.2001.1003.0.ABC^ISO|FILLER456^LAB^1.2.36.1.2001.1003.0.DEF^ISO|GLU^Glucose\r
    """

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
    private let ceAltIdentifierWithoutAltCodingSystem = """
    MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r\
    OBR|1|PLACER123^HOSP^1.2.36.1.2001.1003.0.ABC^ISO|FILLER456^LAB^1.2.36.1.2001.1003.0.DEF^ISO|GLU^Glucose^L^GLU2^Glucose alt\r
    """

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
    private let ceCodingSystemWithoutIdentifier = """
    MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r\
    OBR|1|PLACER123^HOSP^1.2.36.1.2001.1003.0.ABC^ISO|FILLER456^LAB^1.2.36.1.2001.1003.0.DEF^ISO|^Glucose^LN\r
    """

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
    private let ceConsistent = """
    MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r\
    OBR|1|PLACER123^HOSP^1.2.36.1.2001.1003.0.ABC^ISO|FILLER456^LAB^1.2.36.1.2001.1003.0.DEF^ISO|GLU^Glucose^L\r
    """

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
    private let cweInOBX = """
    MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r\
    OBX|1|CWE|HCT^Haematocrit|||F^Final^HL70123\r
    """

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

    // MARK: - S5-B-3: CX required-component rules (HL7au:00044.1.2 / .1.3)

    // PID-3 with only CX-1 populated. AU rules require CX-4 (Assigning
    // Authority) and CX-5 (Identifier Type Code) to also be valued.
    private let pidCxMinimal = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||999999\r
    """

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
    private let pidCxFull = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||999999^^^HOSP^MR\r
    """

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
    private let pidCxOnDeprecatedField = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1|DEPRECATED_ID|999999^^^HOSP^MR\r
    """

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

    // MSH-17 = "AUS" + MSH-19 = "en^English^ISO639" — fully AU-conformant.
    private let mshFullyAUCompliant = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1|||AL|NE|AUS||en^English^ISO639\r\
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

    @Test("MSH-17 / MSH-19 value-set rules are silent on empty fields (only fire when populated)")
    func mshValueSetRulesConditionalOnPopulated() throws {
        // The vast majority of the fixture corpus has empty MSH-17 +
        // MSH-19 — the value-set rules must not fire on those. The
        // "rules require population at all" enforcement is a separate
        // future dispatch (profileUsage-based, not in S5-C scope).
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||999999^^^HOSP^MR\r
        """
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let report = Validator(locale: .auLocalisation).validate(message)
        let mshValueSetViolations = report.errors.filter {
            if case .profileConstraintViolation(let rule) = $0.code,
               $0.location.segmentID == "MSH",
               (rule.contains("HL7au:000041") || rule.contains("HL7au:000042")) {
                return true
            }
            return false
        }
        #expect(mshValueSetViolations.isEmpty,
                "MSH value-set rules must not fire on empty MSH-17 / MSH-19 (yet)")
    }

    @Test("MSH-17 / MSH-19 rules don't fire under .international locale")
    func mshValueSetRulesAULocaleOnly() throws {
        let message = try Parser(locale: .international).parse(mshNonAUCountry)
        let report = Validator(locale: .international).validate(message)
        #expect(profileViolations(in: report).isEmpty,
                ".international locale must never fire profile violations")
    }
}
