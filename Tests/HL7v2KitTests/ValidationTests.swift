// ValidationTests.swift
// Validator behaviour: required-field check, cardinality check, Z-segment
// policies, deprecated-field warnings, and the contract that validation is
// non-fatal (always returns a report, never throws).

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Validator")
struct ValidationTests {

    // MARK: - Required-field check

    @Test("A valid PID-bearing message has an empty report")
    func wellFormedMessageIsValid() throws {
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M\r
        """
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        #expect(report.isValid)
        #expect(report.errors.isEmpty)
    }

    @Test("Missing required PID-3 produces a .requiredFieldMissing error")
    func missingRequiredField() throws {
        // PID-3 (Patient Identifier List) is `R`. Omitting it should error.
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1\r
        """
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        #expect(!report.isValid)
        let issue = try #require(report.errors.first { $0.code == .requiredFieldMissing && $0.location.fieldIndex == 3 })
        #expect(issue.location.segmentID == "PID")
        #expect(issue.location.segmentIndex == 1)
        #expect(issue.severity == .error)
    }

    @Test("checkRequiredFields=false suppresses the required-field error")
    func canDisableRequiredFieldCheck() throws {
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1\r
        """
        let message = try Parser().parse(wire)
        let options = ValidationOptions(checkRequiredFields: false)
        let report = Validator(options: options).validate(message)
        // No required-field error since the check is off. AL1/etc not present
        // so no other errors expected either.
        #expect(report.errors.isEmpty)
    }

    // MARK: - Z-segment policy

    @Test(".ignore (default) does not report Z-segment presence")
    func defaultIgnoresZSegments() throws {
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||123456^^^HOSP^MR||Smith^John^A\r\
        ZAU|1|something\r
        """
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        #expect(!report.issues.contains(where: { $0.code == .zSegmentPresent }))
    }

    @Test(".warnPresence yields a .info issue per Z-segment")
    func warnPresenceFlagsZSegments() throws {
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||123456^^^HOSP^MR||Smith^John^A\r\
        ZAU|1|something\r
        """
        let message = try Parser().parse(wire)
        let options = ValidationOptions(zSegmentPolicy: .warnPresence)
        let report = Validator(options: options).validate(message)
        let info = try #require(report.infos.first { $0.code == .zSegmentPresent })
        #expect(info.location.segmentID == "ZAU")
        #expect(info.severity == .info)
        // Z-segment info shouldn't make the report invalid.
        #expect(report.isValid)
    }

    @Test(".reject yields an .error issue per Z-segment and report becomes invalid")
    func rejectFlagsZSegmentsAsErrors() throws {
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||123456^^^HOSP^MR||Smith^John^A\r\
        ZAU|1|something\r
        """
        let message = try Parser().parse(wire)
        let options = ValidationOptions(zSegmentPolicy: .reject)
        let report = Validator(options: options).validate(message)
        let error = try #require(report.errors.first { $0.code == .zSegmentPresent })
        #expect(error.location.segmentID == "ZAU")
        #expect(!report.isValid)
    }

    // MARK: - Cardinality

    @Test("Single-cardinality field with multiple repetitions errors")
    func cardinalityExceededOnSingleField() throws {
        // PID-7 (DOB, TS) has repeatability=1. Force two ~-separated reps.
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||123456^^^HOSP^MR||Smith^John^A||19800101~19850101|M\r
        """
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        let issue = try #require(report.errors.first { $0.code == .cardinalityExceeded && $0.location.fieldIndex == 7 })
        #expect(issue.severity == .error)
    }

    @Test("Multi-cardinality field accepts repetitions without complaint")
    func multipleCardinalityAllowsRepetitions() throws {
        // PID-3 (Identifier List, CX) has repeatability=*. Two reps should
        // not trigger a cardinality issue.
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||123456^^^HOSP^MR~789012^^^GOV^IHI||Smith^John^A\r
        """
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        #expect(!report.issues.contains(where: {
            $0.code == .cardinalityExceeded && $0.location.fieldIndex == 3
        }))
    }

    // MARK: - Deprecated-field warning

    @Test("Populated B-optionality (deprecated) field emits a .warning")
    func deprecatedFieldEmitsWarning() throws {
        // PID-2 (Patient ID, deprecated B) — populating it should warn.
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1|OLDID|123456^^^HOSP^MR||Smith^John^A\r
        """
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        let warning = try #require(report.warnings.first { $0.code == .fieldNotSupported && $0.location.fieldIndex == 2 })
        #expect(warning.severity == .warning)
        // A deprecated-field warning alone shouldn't invalidate the message.
        #expect(report.isValid)
    }

    @Test("warnDeprecatedFields=false suppresses deprecation warnings")
    func canDisableDeprecationWarnings() throws {
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1|OLDID|123456^^^HOSP^MR||Smith^John^A\r
        """
        let message = try Parser().parse(wire)
        let options = ValidationOptions(warnDeprecatedFields: false)
        let report = Validator(options: options).validate(message)
        #expect(report.warnings.isEmpty)
    }

    // MARK: - Report shape

    @Test("Validation is non-fatal — empty input is not a thing it sees")
    func validatorNeverThrows() throws {
        // The validator only runs on a parsed Message — so emptiness etc
        // are the parser's problem. This test pins the no-throw contract.
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01|MSG00001|P|2.5.1\r
        """
        let message = try Parser().parse(wire)
        // Smoke test — Validator.validate(_:) is not `throws`. If it were,
        // this call site wouldn't compile without `try`.
        let report = Validator().validate(message)
        _ = report.isValid
    }

    @Test("IssueLocation.pathDescription renders correctly")
    func locationPathDescription() {
        let segLocation = IssueLocation(segmentID: "PID", segmentIndex: 1)
        #expect(segLocation.pathDescription == "PID[1]")

        let fieldLocation = IssueLocation(segmentID: "PID", segmentIndex: 2, fieldIndex: 5)
        #expect(fieldLocation.pathDescription == "PID[2]-5")
    }

    // MARK: - M8-B1: base ORC/OBR paired-field equality (items 00216/00217)

    private func pairMismatches(_ wire: String) throws -> [ValidationIssue] {
        let report = Validator().validate(try Parser().parse(wire))
        return report.errors.filter {
            if case .pairedFieldMismatch = $0.code { return true }
            return false
        }
    }

    @Test("ORC-2/OBR-2 carrying different values in one group fires item 00216")
    func orcObrPlacerMismatchFires() throws {
        let wire = "MSH|^~\\&|HIS|FAC|LAB|FAC|||ORM^O01|MSG1|P|2.5.1\r"
            + "PID|1||999999^^^HOSP^MR\r"
            + "ORC|NW|PLACER-A^HOSP|FIL-1^LAB\r"
            + "OBR|1|PLACER-B^HOSP|FIL-1^LAB|GLU^Glucose^L\r"
        let fired = try pairMismatches(wire)
        #expect(fired.count == 1, "got \(fired.map(\.message))")
        #expect(fired.first?.code == .pairedFieldMismatch(item: "00216"))
        #expect(fired.first?.location.pathDescription == "OBR[1]-2")
    }

    @Test("ORC-3/OBR-3 mismatch fires item 00217; matching pairs are silent")
    func orcObrFillerMismatchFires() throws {
        let mismatch = "MSH|^~\\&|HIS|FAC|LAB|FAC|||ORM^O01|MSG1|P|2.5.1\r"
            + "PID|1||999999^^^HOSP^MR\r"
            + "ORC|NW|PL-1^HOSP|FIL-A^LAB\r"
            + "OBR|1|PL-1^HOSP|FIL-B^LAB|GLU^Glucose^L\r"
        let fired = try pairMismatches(mismatch)
        #expect(fired.count == 1)
        #expect(fired.first?.code == .pairedFieldMismatch(item: "00217"))
        let matching = "MSH|^~\\&|HIS|FAC|LAB|FAC|||ORM^O01|MSG1|P|2.5.1\r"
            + "PID|1||999999^^^HOSP^MR\r"
            + "ORC|NW|PL-1^HOSP|FIL-1^LAB\r"
            + "OBR|1|PL-1^HOSP|FIL-1^LAB|GLU^Glucose^L\r"
        #expect(try pairMismatches(matching).isEmpty)
    }

    @Test("An empty side skips — equality only applies when both are valued")
    func orcObrPairEmptySideSkips() throws {
        // The spec's own upward-compatibility pattern: the value lives
        // in the OBR and the ORC omits it (or vice versa).
        let orcOnly = "MSH|^~\\&|HIS|FAC|LAB|FAC|||ORM^O01|MSG1|P|2.5.1\r"
            + "PID|1||999999^^^HOSP^MR\r"
            + "ORC|NW|PL-1^HOSP\r"
            + "OBR|1||FIL-1^LAB|GLU^Glucose^L\r"
        #expect(try pairMismatches(orcOnly).isEmpty)
    }

    @Test("Per-group evaluation: a mismatch in the second ORC group fires once, at OBR[2]")
    func orcObrPairPerGroup() throws {
        let wire = "MSH|^~\\&|HIS|FAC|LAB|FAC|||ORM^O01|MSG1|P|2.5.1\r"
            + "PID|1||999999^^^HOSP^MR\r"
            + "ORC|NW|PL-1^HOSP|FIL-1^LAB\r"
            + "OBR|1|PL-1^HOSP|FIL-1^LAB|GLU^Glucose^L\r"
            + "ORC|NW|PL-2^HOSP|FIL-2^LAB\r"
            + "OBR|2|PL-2X^HOSP|FIL-2^LAB|LFT^Liver^L\r"
        let fired = try pairMismatches(wire)
        #expect(fired.count == 1)
        #expect(fired.first?.location.pathDescription == "OBR[2]-2")
    }

    @Test("The pair rule is base-spec: it fires under the international locale")
    func orcObrPairIsBaseSpec() throws {
        // No profile is loaded for .international — this rule still runs.
        let wire = "MSH|^~\\&|HIS|FAC|LAB|FAC|||ORM^O01|MSG1|P|2.5.1\r"
            + "ORC|NW|PL-A^HOSP\r"
            + "OBR|1|PL-B^HOSP||GLU^Glucose^L\r"
        let report = Validator(locale: .international)
            .validate(try Parser(locale: .international).parse(wire))
        #expect(report.errors.contains { $0.code == .pairedFieldMismatch(item: "00216") })
    }

    @Test("ORC-12/OBR-16 (Ordering Provider, item 00226) — repetition-aware equality")
    func orcObrOrderingProviderPair() throws {
        // Same provider list on both sides: silent.
        func wire(orc12: String, obr16: String) -> String {
            "MSH|^~\\&|HIS|FAC|LAB|FAC|||ORM^O01|MSG1|P|2.5.1\r"
                + "ORC|NW|PL-1^HOSP|FIL-1^LAB|||||||||\(orc12)\r"
                + "OBR|1|PL-1^HOSP|FIL-1^LAB|GLU^Glucose^L||||||||||||\(obr16)\r"
        }
        let same = wire(orc12: "1234^SMITH^JOHN~5678^JONES^ANN", obr16: "1234^SMITH^JOHN~5678^JONES^ANN")
        #expect(try pairMismatches(same).isEmpty)
        // A repetition differing only on the second repeat fires.
        let differs = wire(orc12: "1234^SMITH^JOHN~5678^JONES^ANN", obr16: "1234^SMITH^JOHN~9999^OTHER^X")
        let fired = try pairMismatches(differs)
        #expect(fired.count == 1)
        #expect(fired.first?.code == .pairedFieldMismatch(item: "00226"))
        #expect(fired.first?.location.pathDescription == "OBR[1]-16")
        // Trailing empty components are the same value.
        let normalised = wire(orc12: "1234^SMITH^JOHN^^", obr16: "1234^SMITH^JOHN")
        #expect(try pairMismatches(normalised).isEmpty)
    }

    // MARK: - M8-C: BatchValidator

    private let batchORU = "MSH|^~\\&|LAB|FAC|GP|FAC|||ORU^R01|M-ORU|P|2.5.1\r"
        + "PID|1||1^^^H^MR\r"
    private let batchREF = "MSH|^~\\&|GP|FAC|SPEC|FAC|||REF^I12^REF_I12|M-REF|P|2.4\r"
        + "PID|1||X^^^F^MR\r"

    @Test("ADRM-prose:P-7 — only one Batch is supported per file in Australia")
    func auSingleBatchPerFile() throws {
        let twoBatches = "FHS|^~\\&|APP\r"
            + "BHS|^~\\&|APP\r" + batchORU + "BTS|1\r"
            + "BHS|^~\\&|APP\r" + batchORU + "BTS|1\r"
            + "FTS|1\r"
        let file = try BatchParser().parse(twoBatches)
        let auReport = BatchValidator(locale: .auLocalisation).validate(file)
        #expect(auReport.batchIssues.contains { $0.message.contains("ADRM-prose:P-7") },
                "two BHS-headed batches must fire; got \(auReport.batchIssues.map(\.message))")
        // The rule is AU-scoped: the international locale is silent.
        let intReport = BatchValidator(locale: .international).validate(file)
        #expect(intReport.batchIssues.isEmpty)
        #expect(intReport.messageReports.count == 2)
    }

    @Test("HL7au:000022.3 — a referral batch must contain no more than one message")
    func auReferralBatchSize() throws {
        func file(_ messages: [String]) throws -> BatchFile {
            try BatchParser().parse(
                "BHS|^~\\&|APP\r" + messages.joined() + "BTS|\(messages.count)\r"
            )
        }
        // REF alongside another message: fires.
        let mixed = BatchValidator(locale: .auLocalisation)
            .validate(try file([batchREF, batchORU]))
        #expect(mixed.batchIssues.contains { $0.message.contains("HL7au:000022.3") },
                "got \(mixed.batchIssues.map(\.message))")
        // A single REF: silent.
        let single = BatchValidator(locale: .auLocalisation)
            .validate(try file([batchREF]))
        #expect(single.batchIssues.isEmpty)
        // Multiple non-referral messages: "a batch can contain any
        // number of messages" (p. 19) — silent.
        let results = BatchValidator(locale: .auLocalisation)
            .validate(try file([batchORU, batchORU, batchORU]))
        #expect(results.batchIssues.isEmpty)
        #expect(results.messageReports.count == 3)
    }

    @Test("HL7au:000022.1 — batched messages get the per-message AL acknowledgement rules")
    func auBatchedMessagesGetAckRules() throws {
        // The batched ORU has no MSH-15/16 — under AU the per-message
        // validation inside BatchValidator must fire HL7au:00047.1/.2.
        let file = try BatchParser().parse("BHS|^~\\&|APP\r" + batchORU + "BTS|1\r")
        let report = BatchValidator(locale: .auLocalisation).validate(file)
        #expect(report.messageReports.count == 1)
        let ackViolations = report.messageReports[0].errors.filter {
            $0.message.contains("HL7au:00047")
        }
        #expect(ackViolations.count == 2,
                "missing MSH-15 and MSH-16 must both fire inside the batch; got \(ackViolations.map(\.message))")
        #expect(!report.isValid)
    }

    @Test("Parent pair — ORC-8/OBR-29 through v2.6; ORC-8/OBR-54 on v2.8.2")
    func orcObrParentPairMovesAcrossVersions() throws {
        // v2.5.1: parent lives at OBR-29 (both sides EIP).
        let v251 = "MSH|^~\\&|HIS|FAC|LAB|FAC|||ORM^O01|MSG1|P|2.5.1\r"
            + "ORC|CH|PL-1^HOSP|FIL-1^LAB|||||PARENT-A&HOSP^FILP&LAB\r"
            + "OBR|1|PL-1^HOSP|FIL-1^LAB|GLU^Glucose^L|||||||||||||||||||||||||PARENT-B&HOSP^FILP&LAB\r"
        let firedOld = try pairMismatches(v251)
        #expect(firedOld.count == 1, "got \(firedOld.map(\.message))")
        #expect(firedOld.first?.code == .pairedFieldMismatch(item: "00222"))
        #expect(firedOld.first?.location.pathDescription == "OBR[1]-29")
        // v2.8.2: OBR-29 is a DIFFERENT element (00261) — a differing
        // OBR-29 must NOT fire; the pair reads OBR-54 instead.
        let v282Obr29 = "MSH|^~\\&|HIS|FAC|LAB|FAC|||OML^O21|MSG1|P|2.8.2\r"
            + "ORC|CH|PL-1^HOSP|FIL-1^LAB|||||PARENT-A&HOSP^FILP&LAB\r"
            + "OBR|1|PL-1^HOSP|FIL-1^LAB|GLU^Glucose^L|||||||||||||||||||||||||PARENT-B&HOSP^FILP&LAB\r"
        #expect(try pairMismatches(v282Obr29).isEmpty,
                "OBR-29 is not the v2.8.2 parent peer")
        // v2.8.2 with a mismatching OBR-54 fires.
        let obr54Tail = String(repeating: "|", count: 50)
        let v282Obr54 = "MSH|^~\\&|HIS|FAC|LAB|FAC|||OML^O21|MSG1|P|2.8.2\r"
            + "ORC|CH|PL-1^HOSP|FIL-1^LAB|||||PARENT-A&HOSP^FILP&LAB\r"
            + "OBR|1|PL-1^HOSP|FIL-1^LAB|GLU^Glucose^L\(obr54Tail)PARENT-B&HOSP^FILP&LAB\r"
        let fired282 = try pairMismatches(v282Obr54)
        #expect(fired282.count == 1, "got \(fired282.map(\.message))")
        #expect(fired282.first?.location.pathDescription == "OBR[1]-54")
    }
}
