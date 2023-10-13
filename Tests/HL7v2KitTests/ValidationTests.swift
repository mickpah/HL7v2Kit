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
}
