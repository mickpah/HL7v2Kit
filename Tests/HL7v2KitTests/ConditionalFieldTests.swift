// ConditionalFieldTests.swift
// Conditional-field evaluation in the Validator. The DSL is documented on
// `FieldGrammar.condition` (same-segment predicates only; compound AND / OR
// + in / not in added in v0.4-S4 substage B).
//
// Schema-driven predicates exercised here (v0.4-S4 substage C):
//   PID-35: "PID-36 populated OR PID-38 populated"  — §3.4.2.35
//   PID-36: "PID-37 populated"                       — §3.4.2.36
//   OBX-2:  "OBX-11 != X"                            — §7.4.2.2
//
// Wire fixtures use a sparse PID prefix (PID-1/3/5/7/8 populated, then a
// run of pipes to position the field under test). The "Pre-condition"
// path-access checks pin that the wire actually populates the intended
// field — a counting bug there would masquerade as a validator bug.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Validator — conditional fields")
struct ConditionalFieldTests {

    // MARK: - PID-36 schema-driven condition ("PID-37 populated")

    // PID-37 (Strain) populated, PID-36 (Breed Code) empty. Pipe count
    // after `M`: 29 pipes places `DeKalb` at PID-37 with PID-35/36 both
    // empty. The condition fires on PID-36.
    private let pidStrainPopulatedBreedEmpty = TestWires.adt("PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M|||||||||||||||||||||||||||||DeKalb")

    @Test("PID-37 populated + PID-36 empty → .conditionalFieldMissing on PID-36")
    func breedCodeConditionFiresWhenStrainPopulated() throws {
        let message = try Parser().parse(pidStrainPopulatedBreedEmpty)
        #expect(message["PID-37"] == "DeKalb", "Wire mis-counted: DeKalb should land at PID-37")
        let report = Validator().validate(message)
        let issue = try #require(report.errors.first {
            $0.code == .conditionalFieldMissing && $0.location.fieldIndex == 36
        })
        #expect(issue.location.segmentID == "PID")
        #expect(issue.severity == .error)
        #expect(issue.message.contains("PID-37 populated"))
    }

    // PID-37 populated AND PID-36 populated — condition triggers but the
    // dependent field is present, no error.
    private let pidStrainAndBreedPopulated = TestWires.adt("PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M|||||||||||||||||||||||||||L2^Canine^HL70447|B7^Beagle^HL70449|DeKalb")

    @Test("PID-35/36/37 all populated → no conditional error")
    func breedCodeConditionSatisfiedWhenBothPopulated() throws {
        let message = try Parser().parse(pidStrainAndBreedPopulated)
        let report = Validator().validate(message)
        #expect(!report.errors.contains { $0.code == .conditionalFieldMissing })
    }

    // MARK: - PID-35 schema-driven condition ("PID-36 populated OR PID-38 populated")

    // PID-36 populated, PID-35 empty → PID-35 conditional fires. Pipe
    // count: 28 pipes after `M` places `B7^Beagle^HL70449` at PID-36 with
    // PID-35 empty.
    private let pidBreedPopulatedSpeciesEmpty = TestWires.adt("PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M||||||||||||||||||||||||||||B7^Beagle^HL70449")

    @Test("PID-36 populated + PID-35 empty → .conditionalFieldMissing on PID-35")
    func speciesCodeConditionFiresWhenBreedPopulated() throws {
        let message = try Parser().parse(pidBreedPopulatedSpeciesEmpty)
        #expect(message["PID-36.1"] == "B7", "Wire mis-counted: B7 should land at PID-36.1")
        let report = Validator().validate(message)
        let issue = try #require(report.errors.first {
            $0.code == .conditionalFieldMissing && $0.location.fieldIndex == 35
        })
        #expect(issue.location.segmentID == "PID")
        #expect(issue.message.contains("PID-36 populated OR PID-38 populated"))
    }

    // PID-38 populated, PID-35 empty → PID-35 conditional fires via the
    // OR clause. Pipe count: 30 pipes after `M`.
    private let pidProductionPopulatedSpeciesEmpty = TestWires.adt("PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M||||||||||||||||||||||||||||||DA^Dairy^L")

    @Test("PID-38 populated + PID-35 empty → .conditionalFieldMissing on PID-35 (OR branch)")
    func speciesCodeConditionFiresWhenProductionClassPopulated() throws {
        let message = try Parser().parse(pidProductionPopulatedSpeciesEmpty)
        #expect(message["PID-38.1"] == "DA", "Wire mis-counted: DA should land at PID-38.1")
        let report = Validator().validate(message)
        let issue = try #require(report.errors.first {
            $0.code == .conditionalFieldMissing && $0.location.fieldIndex == 35
        })
        #expect(issue.message.contains("PID-36 populated OR PID-38 populated"))
    }

    // MARK: - Backward-compatibility & toggles

    // PID with NO species/breed/strain/production-class fields (the typical
    // human-patient shape). No conditional should fire. This pins backward
    // compatibility for the gold-fixture corpus.
    private let pidPlainHumanPatient = TestWires.adt("PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M")

    @Test("PID-35..PID-38 all empty → no conditional error")
    func noVeterinaryFieldsNoConditionalError() throws {
        let message = try Parser().parse(pidPlainHumanPatient)
        let report = Validator().validate(message)
        #expect(!report.errors.contains { $0.code == .conditionalFieldMissing })
    }

    @Test("checkConditionalFields=false suppresses the conditional-field error")
    func toggleSuppressesConditionalCheck() throws {
        let message = try Parser().parse(pidStrainPopulatedBreedEmpty)
        let options = ValidationOptions(checkConditionalFields: false)
        let report = Validator(options: options).validate(message)
        #expect(!report.errors.contains { $0.code == .conditionalFieldMissing })
    }

    @Test(".lenient preset disables conditional checks")
    func lenientPresetDisablesConditional() throws {
        let message = try Parser().parse(pidStrainPopulatedBreedEmpty)
        let report = Validator(options: .lenient).validate(message)
        #expect(!report.errors.contains { $0.code == .conditionalFieldMissing })
    }

    // MARK: - OBX-2 schema-driven condition ("OBX-11 != X")

    // OBX-11 populated with a non-X result status, OBX-2 empty → fires.
    // The OBR scaffolding is the minimum required to put a single OBX
    // under a parsed message.
    private let obxResultStatusNonXValueTypeEmpty = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r\
    PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M\r\
    OBR|1|||GLU^Glucose\r\
    OBX|1||GLU^Glucose|1|95||||||F\r
    """

    @Test("OBX-11 != X + OBX-2 empty → .conditionalFieldMissing on OBX-2")
    func obxValueTypeConditionFiresWhenResultStatusNotX() throws {
        let message = try Parser().parse(obxResultStatusNonXValueTypeEmpty)
        #expect(message["OBX-11"] == "F", "Wire mis-counted: F should land at OBX-11")
        let report = Validator().validate(message)
        let issue = try #require(report.errors.first {
            $0.code == .conditionalFieldMissing
            && $0.location.segmentID == "OBX"
            && $0.location.fieldIndex == 2
        })
        #expect(issue.message.contains("OBX-11 != X"))
    }

    // OBX-11 = X (no results, order cancelled) → predicate evaluates
    // false, OBX-2 empty is acceptable.
    private let obxResultStatusXValueTypeEmpty = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r\
    PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M\r\
    OBR|1|||GLU^Glucose\r\
    OBX|1||GLU^Glucose|1|||||||X\r
    """

    @Test("OBX-11 == X + OBX-2 empty → no conditional error on OBX-2")
    func obxValueTypeConditionSilentWhenResultStatusIsX() throws {
        let message = try Parser().parse(obxResultStatusXValueTypeEmpty)
        #expect(message["OBX-11"] == "X", "Wire mis-counted: X should land at OBX-11")
        let report = Validator().validate(message)
        let obx2Errors = report.errors.filter {
            $0.code == .conditionalFieldMissing
            && $0.location.segmentID == "OBX"
            && $0.location.fieldIndex == 2
        }
        #expect(obx2Errors.isEmpty)
    }

    // OBX-2 populated → no conditional regardless of OBX-11.
    private let obxValueTypePopulated = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|2.5.1\r\
    PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M\r\
    OBR|1|||GLU^Glucose\r\
    OBX|1|NM|GLU^Glucose|1|95||||||F\r
    """

    @Test("OBX-2 populated → no conditional error on OBX-2")
    func obxValueTypeConditionSatisfiedWhenPopulated() throws {
        let message = try Parser().parse(obxValueTypePopulated)
        let report = Validator().validate(message)
        let obx2Errors = report.errors.filter {
            $0.code == .conditionalFieldMissing
            && $0.location.segmentID == "OBX"
            && $0.location.fieldIndex == 2
        }
        #expect(obx2Errors.isEmpty)
    }

    // MARK: - Fixture corpus regression pin

    // MARK: - v0.7-S3: schema-driven cross-segment / message-context conditions

    // ORC + OBR with both placer-order fields empty triggers the XOR
    // rule on both sides (ADR-008 §"Three rules expressed in the new DSL").
    private let oruBothPlacersEmpty = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|20260619120000||ORU^R01^ORU_R01|MSG|P|2.5.1\r\
    PID|1||X^^^F^MR||Doe^Jane||19800101|F\r\
    ORC|RE|||GROUP001|CM\r\
    OBR|1||FIL001|GLUC^Glucose|||||||||||||||||||||F\r
    """

    @Test("ORC-2 / OBR-2 XOR fires on both sides when both placer fields empty")
    func placerOrderXORFiresOnBothSides() throws {
        let message = try Parser().parse(oruBothPlacersEmpty)
        let report = Validator().validate(message)
        let xorIssues = report.errors.filter {
            $0.code == .conditionalFieldMissing && $0.location.fieldIndex == 2
        }
        // Expect one issue per side: ORC-2 and OBR-2.
        #expect(xorIssues.contains { $0.location.segmentID == "ORC" })
        #expect(xorIssues.contains { $0.location.segmentID == "OBR" })
    }

    private let oruORCCarriesPlacer = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|20260619120000||ORU^R01^ORU_R01|MSG|P|2.5.1\r\
    PID|1||X^^^F^MR||Doe^Jane||19800101|F\r\
    ORC|RE|ORD001||GROUP001|CM\r\
    OBR|1||FIL001|GLUC^Glucose|||||||||||||||||||||F\r
    """

    @Test("ORC-2 / OBR-2 XOR satisfied when ORC carries the placer order")
    func placerOrderXORSatisfiedFromORCSide() throws {
        let message = try Parser().parse(oruORCCarriesPlacer)
        let report = Validator().validate(message)
        let xorIssues = report.errors.filter {
            $0.code == .conditionalFieldMissing && $0.location.fieldIndex == 2
        }
        #expect(xorIssues.isEmpty)
    }

    // OBR-25 (Result Status) required on ORU; ADT^A01 with no OBR-25
    // must NOT fire the conditional because messageCode = ORU is false.
    private let adtA01NoOBR = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20260619120000||ADT^A01|MSG|P|2.5.1\r\
    PID|1||X^^^F^MR||Smith^John||19800101|M\r
    """

    @Test("OBR-25 conditional doesn't fire on non-ORU messages")
    func obr25SilentOnADT() throws {
        let message = try Parser().parse(adtA01NoOBR)
        let report = Validator().validate(message)
        let obr25Issues = report.errors.filter {
            $0.location.segmentID == "OBR" && $0.location.fieldIndex == 25
        }
        #expect(obr25Issues.isEmpty)
    }

    // Parent-child ORC pair: first ORC carries ORC-1 = PA (parent),
    // second carries ORC-1 = CH (child). The child's ORC-8 is empty
    // → conditional must fire on ORC[2]-8 because ORC-1 = CH (the
    // current ORC IS a child order). v0.9 audit corrected the
    // predicate from `previousSegment(ORC).ORC-1 = PA` to the
    // same-segment `ORC-1 = CH` per v2.4 CH04 §4.5.1.1 (p. 4-26).
    private let parentChildORCChildMissingParentRef = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|20260619120000||ORU^R01^ORU_R01|MSG|P|2.5.1\r\
    PID|1||X^^^F^MR||Doe^Jane||19800101|F\r\
    ORC|PA|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL001|GLUC|||||||||||||||||||||F\r\
    ORC|CH|ORD002||GROUP|CM\r\
    OBR|2|ORD002|FIL002|HBA1C|||||||||||||||||||||F\r
    """

    @Test("ORC-8 conditional fires on child ORC (ORC-1 = CH)")
    func orc8ConditionalFiresOnChild() throws {
        let message = try Parser().parse(parentChildORCChildMissingParentRef)
        let report = Validator().validate(message)
        let orc8Issues = report.errors.filter {
            $0.code == .conditionalFieldMissing &&
            $0.location.segmentID == "ORC" &&
            $0.location.fieldIndex == 8
        }
        // ORC[1] has ORC-1 = PA (parent) — predicate false, no fire.
        // ORC[2] has ORC-1 = CH (child) — predicate true, ORC-8 empty,
        // fire on ORC[2]-8.
        #expect(orc8Issues.count == 1)
        #expect(orc8Issues.first?.location.segmentIndex == 2)
    }

    // v0.9 audit pin: a standalone CH order with no preceding parent
    // ORC must still fire — the prior predicate `previousSegment(ORC)
    // .ORC-1 = PA` would have under-fired here. This is the regression
    // guard for the the working notes req #4 defect fix.
    private let standaloneChildORC = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|20260619120000||ORU^R01^ORU_R01|MSG|P|2.5.1\r\
    PID|1||X^^^F^MR||Doe^Jane||19800101|F\r\
    ORC|CH|ORD002||GROUP|CM\r\
    OBR|1|ORD002|FIL002|HBA1C|||||||||||||||||||||F\r
    """

    @Test("ORC-8 fires on standalone CH order with no preceding parent ORC")
    func orc8ConditionalFiresOnStandaloneChild() throws {
        let message = try Parser().parse(standaloneChildORC)
        let report = Validator().validate(message)
        let orc8Issues = report.errors.filter {
            $0.code == .conditionalFieldMissing &&
            $0.location.segmentID == "ORC" &&
            $0.location.fieldIndex == 8
        }
        #expect(orc8Issues.count == 1,
                "Standalone CH order must fire ORC-8 conditional under corrected predicate")
    }

    // Parent ORC (ORC-1 = PA) with no ORC-8 must NOT fire — the rule
    // scopes to child orders, not parents.
    private let standaloneParentORC = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|20260619120000||ORU^R01^ORU_R01|MSG|P|2.5.1\r\
    PID|1||X^^^F^MR||Doe^Jane||19800101|F\r\
    ORC|PA|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL001|GLUC|||||||||||||||||||||F\r
    """

    @Test("ORC-8 silent on standalone PA order (predicate scoped to CH)")
    func orc8ConditionalSilentOnParent() throws {
        let message = try Parser().parse(standaloneParentORC)
        let report = Validator().validate(message)
        let orc8Issues = report.errors.filter {
            $0.location.segmentID == "ORC" && $0.location.fieldIndex == 8
        }
        #expect(orc8Issues.isEmpty,
                "PA orders don't require ORC-8 per v2.4 §4.5.1.1; got \(orc8Issues.map(\.message))")
    }

    // v0.9 audit pin: OBR-29 carries the same "required when the
    // order is a child" rule as ORC-8 per v2.4 §4.5.3.29 (p. 4-54).
    // The predicate `ORC-1 = CH` resolves cross-segment via
    // associatedSegment(ORC) when evaluated in OBR context.

    @Test("OBR-29 conditional fires on OBR whose associated ORC is a child")
    func obr29ConditionalFiresOnChildAssociatedORC() throws {
        // Same parent+child wire as orc8ConditionalFiresOnChild. The
        // child group's OBR (OBR[2]) has OBR-29 empty AND its
        // associated ORC carries ORC-1 = CH → OBR-29 fires.
        let message = try Parser().parse(parentChildORCChildMissingParentRef)
        let report = Validator().validate(message)
        let obr29Issues = report.errors.filter {
            $0.code == .conditionalFieldMissing &&
            $0.location.segmentID == "OBR" &&
            $0.location.fieldIndex == 29
        }
        #expect(obr29Issues.count == 1)
        #expect(obr29Issues.first?.location.segmentIndex == 2)
    }

    // v0.10 audit: OBR-7 §4.5.3.7 first sentence — "When the OBR is
    // transmitted as part of a report message, the field must be
    // filled in." Same message-context predicate as OBR-25. The
    // §4.5.3.7 second sentence (specimen sent with request) is NOT
    // captured by the current DSL — would need a specimen-presence
    // atom. Documented in v2_3-v2_4-spec-audit.md as a known gap.

    private let oruWithEmptyOBR7 = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|||ORU^R01|MSG|P|2.5.1\r\
    PID|1||X^^^F^MR\r\
    ORC|RE|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL|GLUC|||||||||||||||||||||F\r
    """

    // ORC-3 / OBR-3 filler-order XOR per v2.4 §4.5.1.3 / §4.5.3.3:
    // "ORC-3-filler order number is the same as OBR-3-filler order
    // number. If the filler order number is not present in the ORC,
    // it must be present in the associated OBR." Exact mirror of the
    // ORC-2/OBR-2 placer-order XOR shipped in v0.7-S4.

    private let oruBothFillersEmpty = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|||ORU^R01^ORU_R01|MSG|P|2.5.1\r\
    PID|1||X^^^F^MR\r\
    ORC|RE|ORD001||GROUP|CM\r\
    OBR|1|ORD001||GLUC|||20260619000000||||||||||||||||||||F\r
    """

    // DG1-20 / DG1-21 per v2.5.1 §6.5.2.20 / §6.5.2.21: "This field
    // is required in all implementations employing Update Diagnosis/
    // Procedures (P12) messages." Trigger: messageCode + triggerEvent
    // pair "ADT^P12". The v0.7 message-context atom resolves
    // MSH-9.2 directly.

    private let adtP12WithEmptyDG1 = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^P12|MSG|P|2.5.1\r\
    PID|1||X^^^F^MR\r\
    DG1|1||\r
    """

    @Test("DG1-20 / DG1-21 fire on ADT^P12 with empty DG1 (v0.10 audit)")
    func dg1ConditionalsFireOnP12() throws {
        let message = try Parser().parse(adtP12WithEmptyDG1)
        let report = Validator().validate(message)
        let dg1Issues = report.errors.filter {
            $0.code == .conditionalFieldMissing &&
            $0.location.segmentID == "DG1" &&
            ($0.location.fieldIndex == 20 || $0.location.fieldIndex == 21)
        }
        #expect(dg1Issues.contains { $0.location.fieldIndex == 20 })
        #expect(dg1Issues.contains { $0.location.fieldIndex == 21 })
    }

    private let adtA01WithEmptyDG1 = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG|P|2.5.1\r\
    PID|1||X^^^F^MR\r\
    DG1|1||\r
    """

    @Test("DG1-20 / DG1-21 silent on non-P12 messages")
    func dg1ConditionalsSilentOnNonP12() throws {
        let message = try Parser().parse(adtA01WithEmptyDG1)
        let report = Validator().validate(message)
        let dg1Issues = report.errors.filter {
            $0.code == .conditionalFieldMissing &&
            $0.location.segmentID == "DG1" &&
            ($0.location.fieldIndex == 20 || $0.location.fieldIndex == 21)
        }
        #expect(dg1Issues.isEmpty)
    }

    @Test("ORC-3 / OBR-3 XOR fires on both sides when both filler orders empty")
    func fillerOrderXORFiresOnBothSides() throws {
        let message = try Parser().parse(oruBothFillersEmpty)
        let report = Validator().validate(message)
        let xorIssues = report.errors.filter {
            $0.code == .conditionalFieldMissing && $0.location.fieldIndex == 3
        }
        #expect(xorIssues.contains { $0.location.segmentID == "ORC" })
        #expect(xorIssues.contains { $0.location.segmentID == "OBR" })
    }

    private let oruOBRCarriesFiller = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|||ORU^R01^ORU_R01|MSG|P|2.5.1\r\
    PID|1||X^^^F^MR\r\
    ORC|RE|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL001|GLUC|||20260619000000||||||||||||||||||||F\r
    """

    @Test("ORC-3 / OBR-3 XOR satisfied when OBR carries the filler order")
    func fillerOrderXORSatisfiedFromOBRSide() throws {
        let message = try Parser().parse(oruOBRCarriesFiller)
        let report = Validator().validate(message)
        let xorIssues = report.errors.filter {
            $0.code == .conditionalFieldMissing && $0.location.fieldIndex == 3
        }
        #expect(xorIssues.isEmpty)
    }

    @Test("OBR-7 conditional fires on ORU message with empty OBR-7")
    func obr7ConditionalFiresOnORU() throws {
        let message = try Parser().parse(oruWithEmptyOBR7)
        let report = Validator().validate(message)
        let obr7Issues = report.errors.filter {
            $0.code == .conditionalFieldMissing &&
            $0.location.segmentID == "OBR" &&
            $0.location.fieldIndex == 7
        }
        #expect(obr7Issues.count == 1)
    }

    private let adtWithEmptyOBR = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG|P|2.5.1\r\
    PID|1||X^^^F^MR\r
    """

    @Test("OBR-7 silent when no OBR present (e.g. ADT message)")
    func obr7ConditionalSilentWhenNoOBR() throws {
        // ADT^A01 has no OBR segment at all → the conditional check
        // never runs on OBR-7. Negative pin to confirm.
        let message = try Parser().parse(adtWithEmptyOBR)
        let report = Validator().validate(message)
        let obr7Issues = report.errors.filter {
            $0.location.segmentID == "OBR" && $0.location.fieldIndex == 7
        }
        #expect(obr7Issues.isEmpty)
    }

    @Test("OBR-29 silent on OBR whose associated ORC is not a child")
    func obr29ConditionalSilentOnNonChildAssociatedORC() throws {
        // Parent-only wire (ORC-1 = PA). OBR-29 empty but the
        // associated ORC carries PA, not CH → predicate false → no fire.
        let message = try Parser().parse(standaloneParentORC)
        let report = Validator().validate(message)
        let obr29Issues = report.errors.filter {
            $0.location.segmentID == "OBR" && $0.location.fieldIndex == 29
        }
        #expect(obr29Issues.isEmpty,
                "OBR-29 must not fire on PA orders; got \(obr29Issues.map(\.message))")
    }

    // v0.11-S1 XOR softening pins (ADR-010, v2.4 CH04 §4.5.1.8): the
    // parent identifier may be carried in EITHER ORC-8 OR OBR-29 — a
    // child order that populates one side must not fire the "required"
    // rule on the other. The prior v0.9 `ORC-1 = CH` predicate over-fired
    // in both directions; the DNF-encoded XOR
    // `ORC-1 = CH AND OBR absent OR ORC-1 = CH AND OBR-29 empty` (and
    // symmetric on OBR-29) closes both over-fires.

    // OBR carries the parent identifier; ORC-8 empty. Softening case A.
    private let childOrderOBRCarriesParent = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|20260619120000||ORU^R01^ORU_R01|MSG|P|2.5.1\r\
    PID|1||X^^^F^MR||Doe^Jane||19800101|F\r\
    ORC|CH|ORD002||GROUP|CM\r\
    OBR|1|ORD002|FIL002|HBA1C|||||||||||||||||||||F||||PLACER_ORD001\r
    """

    @Test("XOR softening: ORC-8 silent when OBR-29 carries the parent")
    func orc8SilentUnderXORSofteningWhenOBRCarriesParent() throws {
        let message = try Parser().parse(childOrderOBRCarriesParent)
        let report = Validator().validate(message)
        let orc8Issues = report.errors.filter {
            $0.code == .conditionalFieldMissing &&
            $0.location.segmentID == "ORC" &&
            $0.location.fieldIndex == 8
        }
        #expect(orc8Issues.isEmpty,
                "ORC-8 must not fire when peer OBR-29 carries the parent; got \(orc8Issues.map(\.message))")
    }

    // ORC carries the parent identifier; OBR-29 empty. Softening case B.
    private let childOrderORCCarriesParent = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|20260619120000||ORU^R01^ORU_R01|MSG|P|2.5.1\r\
    PID|1||X^^^F^MR||Doe^Jane||19800101|F\r\
    ORC|CH|ORD002||GROUP|CM|||PLACER_ORD001\r\
    OBR|1|ORD002|FIL002|HBA1C|||||||||||||||||||||F\r
    """

    @Test("XOR softening: OBR-29 silent when ORC-8 carries the parent")
    func obr29SilentUnderXORSofteningWhenORCCarriesParent() throws {
        let message = try Parser().parse(childOrderORCCarriesParent)
        let report = Validator().validate(message)
        let obr29Issues = report.errors.filter {
            $0.code == .conditionalFieldMissing &&
            $0.location.segmentID == "OBR" &&
            $0.location.fieldIndex == 29
        }
        #expect(obr29Issues.isEmpty,
                "OBR-29 must not fire when peer ORC-8 carries the parent; got \(obr29Issues.map(\.message))")
    }

    @Test("Fixture corpus produces no unexpected conditional errors")
    func fixtureCorpusNoConditionalErrors() throws {
        // None of the synthetic fixtures populate PID-36/37/38 or the
        // veterinary fields, and OBX segments either populate OBX-2 or
        // use OBX-11 = X — so the schema-driven conditional rules must
        // not flip any valid fixture from valid → invalid.
        let urls = try FixtureCorpus.validFixtureURLs()
        #expect(!urls.isEmpty, "Should find at least one valid fixture")
        for url in urls {
            let bytes = try Data(contentsOf: url)
            guard let message = try? Parser().parse(bytes) else { continue }
            let report = Validator().validate(message)
            let conditionalIssues = report.errors.filter { $0.code == .conditionalFieldMissing }
            #expect(conditionalIssues.isEmpty,
                    "\(url.lastPathComponent) unexpectedly hit a conditional check: \(conditionalIssues.map(\.message))")
        }
    }

    // MARK: - v0.11-S4 (ADR-010): OBR specimen-presence cluster

    // Helper: filter OBR-N conditional-field-missing issues.
    private func obrConditionalHits(_ report: ValidationReport, fieldIndex: Int) -> [ValidationIssue] {
        report.errors.filter {
            $0.code == .conditionalFieldMissing
                && $0.location.segmentID == "OBR"
                && $0.location.fieldIndex == fieldIndex
        }
    }

    // OBR-15 populated (specimen source indicated) but OBR-14 empty.
    // v2.4 §4.5.3.14 "This field must contain a value when the order is
    // accompanied by a specimen..." → fires. Field positions counted
    // via pipe-split index: OBR-7 at index 7 (20240401080000), OBR-15
    // at index 15 (BLOOD^Blood^HL70070).
    private let ormWithSpecimenSourceMissingReceivedDT = """
    MSH|^~\\&|SENDER|FAC|LAB|FAC|||ORM^O01|MSG|P|2.4\r\
    PID|1||X^^^F^MR\r\
    ORC|NW|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL|GLUC|||20240401080000||||||||BLOOD^Blood^HL70070\r
    """

    @Test("v0.11-S4: OBR-14 fires when OBR-15 populated but OBR-14 empty (v2.4)")
    func obr14FiresWhenOBR15PopulatedAndOBR14Empty_v24() throws {
        let message = try Parser().parse(ormWithSpecimenSourceMissingReceivedDT)
        let report = Validator().validate(message)
        let hits = obrConditionalHits(report, fieldIndex: 14)
        #expect(hits.count == 1,
                "Expected exactly one OBR-14 violation; got \(hits.count): \(hits.map(\.message))")
    }

    // OBR-14 populated + OBR-15 populated → guard bypasses (field populated),
    // no fire. Pipe-split positions: f7=20240401080000, f14=20240401075000,
    // f15=BLOOD^Blood^HL70070.
    private let ormWithSpecimenSourceAndReceivedDT = """
    MSH|^~\\&|SENDER|FAC|LAB|FAC|||ORM^O01|MSG|P|2.4\r\
    PID|1||X^^^F^MR\r\
    ORC|NW|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL|GLUC|||20240401080000||||||20240401075000|BLOOD^Blood^HL70070\r
    """

    @Test("v0.11-S4: OBR-14 silent when both OBR-14 and OBR-15 populated (v2.4)")
    func obr14SilentWhenOBR14Populated_v24() throws {
        let message = try Parser().parse(ormWithSpecimenSourceAndReceivedDT)
        let report = Validator().validate(message)
        let hits = obrConditionalHits(report, fieldIndex: 14)
        #expect(hits.isEmpty,
                "OBR-14 populated → conditional guard bypasses; got \(hits.map(\.message))")
    }

    // Neither SPM nor OBR-15 populated → predicate false, no fire even
    // when OBR-14 empty. Represents an ORM without a specimen (e.g.
    // imaging order request).
    private let ormWithoutSpecimen = """
    MSH|^~\\&|SENDER|FAC|RAD|FAC|||ORM^O01|MSG|P|2.4\r\
    PID|1||X^^^F^MR\r\
    ORC|NW|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL|CXR^Chest X-ray^L|||20240401080000|||||L\r
    """

    @Test("v0.11-S4: OBR-14 silent when neither OBR-15 nor SPM present (v2.4)")
    func obr14SilentWhenNoSpecimenIndicator_v24() throws {
        let message = try Parser().parse(ormWithoutSpecimen)
        let report = Validator().validate(message)
        let hits = obrConditionalHits(report, fieldIndex: 14)
        #expect(hits.isEmpty,
                "No specimen indicator → OBR-14 must not fire; got \(hits.map(\.message))")
    }

    // v2.5.1: SPM segment present, OBR-15 empty, OBR-14 empty.
    // Predicate `SPM present OR OBR-15 populated` → true via SPM →
    // OBR-14 fires.
    private let oruWithSPMSegmentMissingReceivedDT = """
    MSH|^~\\&|SENDER|FAC|LAB|FAC|||ORU^R01|MSG|P|2.5.1\r\
    PID|1||X^^^F^MR\r\
    ORC|RE|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL|GLUC|||||||||||||||||||||F\r\
    SPM|1|ORD001&&FIL|BLOOD^Blood^HL70487\r\
    OBX|1|NM|1234-5^Glucose^LN||5.2|mmol/L||||||F\r
    """

    @Test("v0.11-S4: OBR-14 fires when SPM segment present (v2.5.1 detector)")
    func obr14FiresWhenSPMPresent_v251() throws {
        let message = try Parser().parse(oruWithSPMSegmentMissingReceivedDT)
        let report = Validator().validate(message)
        let hits = obrConditionalHits(report, fieldIndex: 14)
        #expect(hits.count == 1,
                "SPM present → OBR-14 must fire; got \(hits.count): \(hits.map(\.message))")
    }

    // OBR-7 second trigger: non-ORU message with OBR-15 populated but
    // OBR-7 empty. v0.10 shipped `messageCode = ORU` alone; S4 extends
    // to also fire on `OBR-15 populated`. Message type ORM (order),
    // specimen indicated via OBR-15 → OBR-7 must fire. Pipe-split
    // positions: f7=empty, f14=20240401075000, f15=BLOOD^Blood^HL70070.
    // (OBR-14 is also populated so its rule doesn't ALSO fire, keeping
    // this test focused on OBR-7.)
    private let ormWithSpecimenMissingObservationDT = """
    MSH|^~\\&|SENDER|FAC|LAB|FAC|||ORM^O01|MSG|P|2.4\r\
    PID|1||X^^^F^MR\r\
    ORC|NW|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL|GLUC||||||||||20240401075000|BLOOD^Blood^HL70070\r
    """

    @Test("v0.11-S4: OBR-7 fires on ORM with OBR-15 populated (specimen-sent trigger)")
    func obr7FiresUnderSecondTrigger() throws {
        let message = try Parser().parse(ormWithSpecimenMissingObservationDT)
        let report = Validator().validate(message)
        let hits = obrConditionalHits(report, fieldIndex: 7)
        #expect(hits.count == 1,
                "ORM with OBR-15 populated → OBR-7 must fire via v0.11-S4 trigger; got \(hits.count): \(hits.map(\.message))")
    }

    // MARK: - v0.11-S4b (ADR-010): v2.3 / v2.3.1 per-version mirror

    // v2.3 wire (MSH-12 = 2.3). OBR-15 populated, OBR-14 empty →
    // OBR-14 condition "OBR-15 populated" fires. Mirrors the v2.4 pin;
    // v2.3 §4.5.1.14 verbatim-identical to v2.4 §4.5.3.14.
    private let ormV23SpecimenSourceMissingReceivedDT = """
    MSH|^~\\&|SENDER|FAC|LAB|FAC|||ORM^O01|MSG|P|2.3\r\
    PID|1||X^^^F^MR\r\
    ORC|NW|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL|GLUC|||20240401080000||||||||BLOOD^Blood^HL70070\r
    """

    @Test("v0.11-S4b: OBR-14 fires on v2.3 when OBR-15 populated")
    func obr14FiresOnV23() throws {
        let message = try Parser().parse(ormV23SpecimenSourceMissingReceivedDT)
        let report = Validator().validate(message)
        let hits = obrConditionalHits(report, fieldIndex: 14)
        #expect(hits.count == 1,
                "v2.3 OBR-14 must fire when OBR-15 populated; got \(hits.count): \(hits.map(\.message))")
    }

    // v2.3.1 child-order wire: ORC-1 = CH, both ORC-8 and OBR-29 empty
    // → XOR softening fires on BOTH (neither peer carries the parent).
    // Mirrors the v2.4/v2.5.1 both-empty case.
    private let oruV231ChildBothParentsEmpty = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|||ORU^R01|MSG|P|2.3.1\r\
    PID|1||X^^^F^MR\r\
    ORC|CH|ORD002||GROUP|CM\r\
    OBR|1|ORD002|FIL002|HBA1C|||||||||||||||||||||F\r
    """

    @Test("v0.11-S4b: ORC-8 + OBR-29 XOR softening fires on v2.3.1 child with both empty")
    func orc8Obr29FireOnV231ChildBothEmpty() throws {
        let message = try Parser().parse(oruV231ChildBothParentsEmpty)
        let report = Validator().validate(message)
        let orc8 = report.errors.filter {
            $0.code == .conditionalFieldMissing
                && $0.location.segmentID == "ORC" && $0.location.fieldIndex == 8
        }
        let obr29 = obrConditionalHits(report, fieldIndex: 29)
        #expect(orc8.count == 1, "v2.3.1 ORC-8 must fire on child with both parents empty; got \(orc8.map(\.message))")
        #expect(obr29.count == 1, "v2.3.1 OBR-29 must fire on child with both parents empty; got \(obr29.map(\.message))")
    }

    // v2.3.1 child-order wire where OBR-29 carries the parent (ORC-8
    // empty) → XOR softening: ORC-8 must stay silent.
    private let oruV231ChildOBRCarriesParent = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|||ORU^R01|MSG|P|2.3.1\r\
    PID|1||X^^^F^MR\r\
    ORC|CH|ORD002||GROUP|CM\r\
    OBR|1|ORD002|FIL002|HBA1C|||||||||||||||||||||F||||PLACER_ORD001\r
    """

    @Test("v0.11-S4b: ORC-8 silent on v2.3.1 child when OBR-29 carries the parent")
    func orc8SilentOnV231WhenOBRCarriesParent() throws {
        let message = try Parser().parse(oruV231ChildOBRCarriesParent)
        let report = Validator().validate(message)
        let orc8 = report.errors.filter {
            $0.code == .conditionalFieldMissing
                && $0.location.segmentID == "ORC" && $0.location.fieldIndex == 8
        }
        #expect(orc8.isEmpty,
                "v2.3.1 ORC-8 must not fire when OBR-29 carries the parent; got \(orc8.map(\.message))")
    }
}
