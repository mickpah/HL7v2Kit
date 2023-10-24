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
    private let pidStrainPopulatedBreedEmpty = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M|||||||||||||||||||||||||||||DeKalb\r
    """

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
    private let pidStrainAndBreedPopulated = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M|||||||||||||||||||||||||||L2^Canine^HL70447|B7^Beagle^HL70449|DeKalb\r
    """

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
    private let pidBreedPopulatedSpeciesEmpty = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M||||||||||||||||||||||||||||B7^Beagle^HL70449\r
    """

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
    private let pidProductionPopulatedSpeciesEmpty = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M||||||||||||||||||||||||||||||DA^Dairy^L\r
    """

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
    private let pidPlainHumanPatient = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M\r
    """

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
    // → conditional must fire on ORC[2]-8 because previousSegment(ORC)
    // .ORC-1 = PA.
    private let parentChildORCChildMissingParentRef = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|20260619120000||ORU^R01^ORU_R01|MSG|P|2.5.1\r\
    PID|1||X^^^F^MR||Doe^Jane||19800101|F\r\
    ORC|PA|ORD001||GROUP|CM\r\
    OBR|1|ORD001|FIL001|GLUC|||||||||||||||||||||F\r\
    ORC|CH|ORD002||GROUP|CM\r\
    OBR|2|ORD002|FIL002|HBA1C|||||||||||||||||||||F\r
    """

    @Test("ORC-8 conditional fires on child ORC when previous ORC carries PA")
    func orc8ConditionalFiresOnChild() throws {
        let message = try Parser().parse(parentChildORCChildMissingParentRef)
        let report = Validator().validate(message)
        let orc8Issues = report.errors.filter {
            $0.code == .conditionalFieldMissing &&
            $0.location.segmentID == "ORC" &&
            $0.location.fieldIndex == 8
        }
        // ORC[1] is the parent (its previous ORC doesn't exist, so the
        // condition fails safe) — silent. ORC[2] is the child (its
        // previous ORC carries PA) — fires.
        #expect(orc8Issues.count == 1)
        #expect(orc8Issues.first?.location.segmentIndex == 2)
    }

    @Test("Fixture corpus produces no unexpected conditional errors")
    func fixtureCorpusNoConditionalErrors() throws {
        // None of the synthetic fixtures populate PID-36/37/38 or the
        // veterinary fields, and OBX segments either populate OBX-2 or
        // use OBX-11 = X — so the schema-driven conditional rules must
        // not flip any valid fixture from valid → invalid.
        let fixturesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let fm = FileManager.default
        let urls = try fm.contentsOfDirectory(at: fixturesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "hl7" }
            .filter { !$0.lastPathComponent.hasPrefix("malformed_") }
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
}
