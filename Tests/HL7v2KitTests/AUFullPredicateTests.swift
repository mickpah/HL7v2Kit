// AUFullPredicateTests.swift
// P4-31 (ADR-021) — HL7au:00060.4 route C. ADRM-2021 Appendix 5 (p. 467):
// "HL7 message elements with a usage of C (conditional) must not be valued
// when the associated predicate is not satisfied." Enforced only on C
// fields whose schema marks the stored condition as the spec's full
// predicate (`conditionIsPredicate`), only when that condition is
// definitely false, never when it is unknown.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("AU HL7au:00060.4 route C: full-predicate C fields (P4-31)")
struct AUFullPredicateTests {

    // MARK: - Helpers

    private func issues00060_4(_ report: ValidationReport) -> [ValidationIssue] {
        report.issues.filter { issue in
            guard case .profileConstraintViolation(let rule) = issue.code else { return false }
            return rule.hasPrefix("HL7au:00060.4")
        }
    }

    private func validate(_ wire: String, locale: HL7Locale = .auLocalisation) throws -> ValidationReport {
        Validator(locale: locale).validate(try Parser(locale: locale).parse(wire))
    }

    private func pid(_ extra: [Int: String]) -> String {
        TestWires.segment("PID", [1: "1", 3: "123^^^HOSP^MR", 5: "DOE^JOHN"].merging(extra) { $1 })
    }

    private let obr = "OBR|1|PLACER1^HOSP^1.2.36.1^ISO|FILLER1^LAB^1.2.36.2^ISO|GLU^Glucose^L"

    private func wire(_ type: String, _ segments: String...) -> String {
        TestWires.msh(type, "2.4") + segments.map { $0 + "\r" }.joined()
    }

    private let breed = "L-80900^Weimaraner^SNM3"
    private let species = "L-80700^Canine, NOS^SNM3"

    // MARK: - The marking

    @Test("v2.4 OBX-2 is the one field marked as a full predicate (owner ruling G9)")
    func marking() {
        #expect(FullPredicateConditions.generated == ["2.4|OBX-2"])
        #expect(FullPredicateConditions.isMarked(version: "2.4", segmentID: "OBX", fieldIndex: 2))
        for (segment, field) in [("PID", 36), ("CTI", 2), ("PID", 35), ("OBR", 2), ("ORC", 2)] {
            #expect(!FullPredicateConditions.isMarked(version: "2.4", segmentID: segment, fieldIndex: field))
        }
        #expect(!FullPredicateConditions.isMarked(version: "2.5.1", segmentID: "OBX", fieldIndex: 2))
    }

    // MARK: - PID-36 and CTI-2: trigger-only, never fire (owner ruling G9)

    // PID-36 "must be valued if PID-37 - Strain is valued" (v2.4 §3.4.2.36)
    // is a parent required when its child is valued, the shape of PID-35;
    // the section's own example sends breed alone ("L-80900^Weimaraner^SNM3").

    @Test("Species plus breed without strain does not fire HL7au:00060.4 in ORU, ORM or REF")
    func pid36WithoutStrainDoesNotFire() throws {
        for type in ["ORU^R01", "ORM^O01", "REF^I12"] {
            let report = try validate(wire(type, pid([35: species, 36: breed]), obr))
            #expect(issues00060_4(report).isEmpty, "\(type): \(issues00060_4(report).map(\.message))")
            #expect(!report.issues.contains { $0.location.segmentID == "PID" && $0.location.fieldIndex == 36 })
        }
    }

    // CTI-2 "must be valued if CTI-3 ... is valued" (v2.4 §7.8.4.3): the
    // segment identifies "the clinical trial, phase and time point" (§7.8.4),
    // and a phase may be sent without a time point.

    @Test("A study phase without a time point does not fire HL7au:00060.4")
    func cti2WithoutTimePointDoesNotFire() throws {
        let report = try validate(wire("ORU^R01", pid([:]), obr, "CTI|STUDY1^SPONSOR|PH1^Phase 1^L"))
        #expect(issues00060_4(report).isEmpty)
        #expect(!report.issues.contains { $0.location.segmentID == "CTI" && $0.location.fieldIndex == 2 })
    }

    // MARK: - OBX-2 (must be valued if OBX-11 is not X)

    private func obx(type: String, status: String) -> String {
        "OBX|1|\(type)|GLU^Glucose^L||\(type.isEmpty || type == "\"\"" ? "" : "5.2")|mmol/L|||||\(status)"
    }

    @Test("OBX-2 valued while OBX-11 = X fires; under F, empty or null it is silent")
    func obx2() throws {
        for type in ["ORU^R01", "ORM^O01", "REF^I12"] {
            let fires = issues00060_4(try validate(wire(type, pid([:]), obr, obx(type: "NM", status: "X"))))
            #expect(fires.map(\.location.fieldIndex) == [2], "\(type)")
            #expect(fires.first?.severity == .error)
            #expect(fires.first?.location.segmentID == "OBX")
        }
        #expect(issues00060_4(try validate(wire("ORU^R01", pid([:]), obr, obx(type: "NM", status: "F")))).isEmpty)
        #expect(issues00060_4(try validate(wire("ORU^R01", pid([:]), obr, obx(type: "", status: "X")))).isEmpty)
        #expect(issues00060_4(try validate(wire("ORU^R01", pid([:]), obr, obx(type: "\"\"", status: "X")))).isEmpty)
        #expect(issues00060_4(try validate(wire("ORU^R01", pid([:]), obr, obx(type: "NM", status: "X")),
                                       locale: .international)).isEmpty)
        #expect(issues00060_4(try validate(wire("ADT^A08", "EVN|A08|20260930120000", pid([:]),
                                               obx(type: "NM", status: "X")))).isEmpty)
    }

    @Test("OBX-2 under OBX-11 = O is reported once, by the base null rule, not by 00060.4")
    func obx2DynamicSpecificationReportedOnce() throws {
        let report = try validate(wire("ORM^O01", pid([:]), "ORC|NW|PLACER1^HOSP^1.2.36.1^ISO", obr,
                                       obx(type: "NM", status: "O")))
        #expect(issues00060_4(report).isEmpty)
        #expect(report.issues.filter { $0.code == .conditionalFieldProhibited
            && $0.location.segmentID == "OBX" && $0.location.fieldIndex == 2 }.count == 1)
    }

    // MARK: - Unknown never fires; no double report (test profile)

    /// A copy of the AU rule that also marks extra (version|SEG-n) keys, so
    /// the three-state handling can be pinned on stored conditions that
    /// reference a peer segment.
    private func testValidator(marking extra: Set<String>,
                               overrides: [FieldOverride] = []) throws -> Validator {
        let rule = try #require(Profile.auADRM2021.fullPredicateRule)
        let profile = Profile(
            locale: .auLocalisation,
            fieldOverrides: overrides,
            fullPredicateRule: FullPredicateRule(
                scope: rule.scope, severity: rule.severity, specCitation: rule.specCitation,
                marked: FullPredicateConditions.generated.union(extra)))
        return Validator(locale: .auLocalisation, testProfileOverride: profile)
    }

    @Test("An unknown condition never fires: OBR-29 'ORC-1 = CH AND ORC-8 empty' in an ORU with no ORC")
    func unknownNeverFires() throws {
        let validator = try testValidator(marking: ["2.4|OBR-29"])
        let obr29 = obr + "|||||||||||||||||||||||||PARENT1&HOSP&1.2.36.1&ISO"
        let noORC = try Parser(locale: .auLocalisation).parse(wire("ORU^R01", pid([:]), obr29))
        #expect(issues00060_4(validator.validate(noORC)).isEmpty)
        // The same OBR-29 with an ORC whose ORC-1 is not CH: definitely false, fires.
        let withORC = try Parser(locale: .auLocalisation)
            .parse(wire("ORU^R01", pid([:]), "ORC|RE|PLACER1^HOSP^1.2.36.1^ISO", obr29))
        #expect(issues00060_4(validator.validate(withORC)).map(\.location.fieldIndex) == [29])
    }

    @Test("A field an AU profile prohibition already reports is not reported again")
    func noDoubleReportWithProfileProhibition() throws {
        let override = FieldOverride(
            segmentID: "OBR", fieldIndex: 29,
            prohibitions: [ProfileFieldProhibition(condition: "messageCode = ORU", severity: .error,
                                                   specCitation: "TEST — OBR-29 prohibited in ORU")],
            specCitation: "TEST")
        let validator = try testValidator(marking: ["2.4|OBR-29"], overrides: [override])
        let message = try Parser(locale: .auLocalisation).parse(wire(
            "ORU^R01", pid([:]), "ORC|RE|PLACER1^HOSP^1.2.36.1^ISO",
            obr + "|||||||||||||||||||||||||PARENT1&HOSP&1.2.36.1&ISO"))
        let report = validator.validate(message)
        #expect(issues00060_4(report).isEmpty)
        #expect(report.issues.contains {
            if case .profileConstraintViolation(let rule) = $0.code { return rule.hasPrefix("TEST") }
            return false
        })
    }

    @Test("A field a base prohibition already reports is not reported again (PRA-1 outside MFN)")
    func noDoubleReportWithBaseProhibition() throws {
        let validator = try testValidator(marking: ["2.4|PRA-1"])
        let message = try Parser(locale: .auLocalisation).parse(wire(
            "ORU^R01", pid([:]), obr, "PRA|PRACT1^^^HOSP"))
        let report = validator.validate(message)
        #expect(issues00060_4(report).isEmpty)
        #expect(report.issues.contains { $0.code == .conditionalFieldProhibited
            && $0.location.segmentID == "PRA" && $0.location.fieldIndex == 1 })
    }
}
