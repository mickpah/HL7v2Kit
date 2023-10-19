// LocaleTests.swift
// v0.4-S5-A: locale plumbing through Parser → Message and
// Validator → ValidationReport. The AU profile overrides themselves
// land in S5-B and later; this suite pins the public-API surface
// (HL7Locale enum cases, default values, locale propagation) so v1.0
// stability has a regression backstop.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("HL7Locale public API (v0.4-S5-A)")
struct LocaleTests {

    private let minimalAdt = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r\
    PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M\r
    """

    // MARK: - Enum surface

    @Test("HL7Locale.allCases lists both supported locales")
    func allCasesEnumerated() {
        let cases = HL7Locale.allCases
        #expect(cases.contains(.international))
        #expect(cases.contains(.auLocalisation))
    }

    @Test("HL7Locale raw values are stable wire strings")
    func rawValuesStable() {
        #expect(HL7Locale.international.rawValue == "international")
        #expect(HL7Locale.auLocalisation.rawValue == "au-adrm-2021")
    }

    // MARK: - Parser locale propagation

    @Test("Parser default locale is .international")
    func parserDefaultLocaleIsInternational() throws {
        let parser = Parser()
        #expect(parser.locale == .international)
        let message = try parser.parse(minimalAdt)
        #expect(message.locale == .international)
    }

    @Test("Parser with .auLocalisation propagates locale onto Message")
    func parserAuLocalePropagates() throws {
        let parser = Parser(locale: .auLocalisation)
        #expect(parser.locale == .auLocalisation)
        let message = try parser.parse(minimalAdt)
        #expect(message.locale == .auLocalisation)
    }

    @Test("Parser locale survives parse(_:Data) byte-path")
    func parserAuLocaleSurvivesBytePath() throws {
        let bytes = Data(minimalAdt.utf8)
        let parser = Parser(locale: .auLocalisation)
        let message = try parser.parse(bytes)
        #expect(message.locale == .auLocalisation)
    }

    // MARK: - Validator locale propagation

    @Test("Validator default locale is .international")
    func validatorDefaultLocaleIsInternational() throws {
        let validator = Validator()
        #expect(validator.locale == .international)
        let message = try Parser().parse(minimalAdt)
        let report = validator.validate(message)
        #expect(report.locale == .international)
    }

    @Test("Validator with .auLocalisation propagates locale onto ValidationReport")
    func validatorAuLocalePropagates() throws {
        let validator = Validator(locale: .auLocalisation)
        #expect(validator.locale == .auLocalisation)
        let message = try Parser().parse(minimalAdt)
        let report = validator.validate(message)
        #expect(report.locale == .auLocalisation)
    }

    // MARK: - Default behaviour preserved (no AU constraints fire yet)

    @Test("AU locale: no OBR/ORC profileConstraintViolation issues fire on a PID-only message")
    func auLocaleEmitsNoOBROrORCViolationsOnPIDOnlyMessage() throws {
        // The S5-B-1 AU rules fire only on OBR-2/3 and ORC-2/3/4. A
        // PID-only ADT carries no OBR or ORC, so those rules don't
        // apply. (MSH rules will fire under profileUsage dispatch
        // because minimalAdt leaves MSH-17 / MSH-19 empty — that's
        // covered separately in LocaleAUProfileTests.)
        let message = try Parser(locale: .auLocalisation).parse(minimalAdt)
        let report = Validator(locale: .auLocalisation).validate(message)
        let obrOrOrcViolations = report.issues.filter {
            if case .profileConstraintViolation = $0.code,
               ($0.location.segmentID == "OBR" || $0.location.segmentID == "ORC") {
                return true
            }
            return false
        }
        #expect(obrOrOrcViolations.isEmpty,
                "ADT with only PID should fire no OBR/ORC profile violations")
    }

    @Test("AU locale errors are a superset of international errors on the fixture corpus")
    func auLocaleAddsButDoesNotRemoveBaseSpecErrors() throws {
        // Post-S5-B, AU locale fires .profileConstraintViolation on
        // OBR/ORC EI-incomplete fixtures (which is most of the corpus,
        // since base-spec-only fixtures populate only 1-2 EI components).
        // The invariant we pin here: AU errors == intl errors + AU-
        // specific profile-violation errors. AU never REMOVES a base-
        // spec error.
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
            let intlMessage = try Parser(locale: .international).parse(bytes)
            let intlReport = Validator(locale: .international).validate(intlMessage)
            let auMessage = try Parser(locale: .auLocalisation).parse(bytes)
            let auReport = Validator(locale: .auLocalisation).validate(auMessage)
            let intlNonProfileErrors = intlReport.errors.filter {
                if case .profileConstraintViolation = $0.code { return false }
                return true
            }
            let auNonProfileErrors = auReport.errors.filter {
                if case .profileConstraintViolation = $0.code { return false }
                return true
            }
            #expect(intlNonProfileErrors.count == auNonProfileErrors.count,
                    "\(url.lastPathComponent): AU locale must not introduce or remove base-spec (non-profile) errors")
            #expect(auReport.errors.count >= intlReport.errors.count,
                    "\(url.lastPathComponent): AU locale must never remove an error")
        }
    }

    // MARK: - ValidationIssue.code surface

    @Test("IssueCode.profileConstraintViolation case is constructible with localeRule")
    func profileConstraintViolationCaseExists() {
        let issue = ValidationIssue(
            severity: .error,
            code: .profileConstraintViolation(localeRule: "au-adrm-2021:PID-3.4 R"),
            location: IssueLocation(segmentID: "PID", segmentIndex: 1, fieldIndex: 3),
            message: "test"
        )
        if case .profileConstraintViolation(let rule) = issue.code {
            #expect(rule == "au-adrm-2021:PID-3.4 R")
        } else {
            Issue.record("Expected .profileConstraintViolation case")
        }
    }
}
