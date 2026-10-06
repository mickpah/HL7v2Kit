// LocaleAUMaximumTests.swift
// S6-3 (owner decision 1, ruled 2026-10-06; ADR-019 decision 7 as amended in S6): under
// `.auLocalisation`, a segment beyond a maximum the ADRM-2021 narrows below the base v2.4
// structure's draws one information issue per occurrence, naming the ADRM print and the
// maximum. REF^I12 (ADRM-2021 section 7.2.1, pp 324 to 325) prints `[IN1]` where the base
// repeats the insurance group, and PV1 and `[PV2]` once where the base (v2.4 CH11 pp 11-16 to
// 11-17) prints `[ PV1 [PV2] ]` twice. The base accepts these occurrences, so before S6 nothing
// was reported (decision 7 dropped the profile's beyond-maximum findings).

import Testing
@testable import HL7v2Kit

@Suite("AU HL7au:00060.1: segments beyond the ADRM's narrowed maxima (S6-3)")
struct LocaleAUMaximumTests {

    private func issues(_ body: [String], locale: HL7Locale = .auLocalisation,
                        severity: IssueSeverity? = .warning) throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = severity
        let wire = TestWires.msh("REF^I12^REF_I12", "2.4") + body.map { $0 + "\r" }.joined()
        return Validator(options: options, locale: locale).validate(try Parser(locale: locale).parse(wire)).issues
    }

    /// The beyond-maximum information issues, each as "SEG[n]".
    private func beyond(_ issues: [ValidationIssue]) -> [String] {
        issues.filter { "\($0.code)".hasPrefix("profileMaximumExceeded") }
            .map { "\($0.location.segmentID)[\($0.location.segmentIndex)]" }
    }

    /// Every structure finding, base or profile, at any severity but information.
    private func findings(_ issues: [ValidationIssue]) -> [ValidationIssue] {
        issues.filter {
            switch $0.code {
            case .messageStructureSegmentMissing, .messageStructureSegmentUnexpected, .messageStructureMismatch,
                 .profileConstraintViolation(localeRule: "HL7au:00060.1"): return true
            default: return false
            }
        }
    }

    static let head = ["RF1|A", "PRD|RP", "PID|1"]

    @Test("A second visit (PV1, PV2) on REF^I12 draws one information issue per occurrence")
    func secondVisit() throws {
        let all = try issues(Self.head + ["PV1|1", "PV2|1", "PV1|2", "PV2|2"])
        #expect(findings(all).isEmpty, "\(findings(all).map(\.message))")
        #expect(beyond(all) == ["PV1[2]", "PV2[2]"], "\(all.map(\.message))")
        let info = all.filter { "\($0.code)".hasPrefix("profileMaximumExceeded") }
        #expect(info.allSatisfy { $0.severity == .info })
        let first = try #require(info.first)
        #expect("\(first.code)".contains("HL7au:00060.1"))
        #expect(first.message.contains("PV1 at most once here") && first.message.contains("pp 324 to 325"), "\(first.message)")
    }

    @Test("A second IN1 on REF^I12 draws one information issue")
    func secondInsurance() throws {
        let all = try issues(Self.head + ["IN1|1", "IN1|2", "PV1|1"])
        #expect(findings(all).isEmpty, "\(findings(all).map(\.message))")
        #expect(beyond(all) == ["IN1[2]"], "\(all.map(\.message))")
    }

    @Test("The issue stays information whatever the structure severity", arguments: [IssueSeverity.error, .warning, .info])
    func severity(_ severity: IssueSeverity) throws {
        let info = try issues(Self.head + ["PV1|1", "PV1|2"], severity: severity)
            .filter { "\($0.code)".hasPrefix("profileMaximumExceeded") }
        #expect(info.count == 1 && info.allSatisfy { $0.severity == .info })
    }

    @Test("Nothing under the international locale, nothing with the structure check off, nothing within the maxima")
    func silence() throws {
        #expect(beyond(try issues(Self.head + ["PV1|1", "PV1|2"], locale: .international)).isEmpty)
        #expect(beyond(try issues(Self.head + ["PV1|1", "PV1|2"], severity: nil)).isEmpty)
        #expect(beyond(try issues(Self.head + ["IN1|1", "PV1|1", "PV2|1"])).isEmpty)
    }

    @Test("The message names the profile's maximum, or says the occurrence is more than the profile allows")
    func maximumWording() {
        #expect(Validator.beyondMaximumClause(segmentID: "PV1", maximum: 1, structure: "the REF_I12 structure")
            == "the REF_I12 structure allows PV1 at most once here, and this occurrence is beyond it")
        #expect(Validator.beyondMaximumClause(segmentID: "IN1", maximum: 3, structure: "the REF_I12 structure")
            == "the REF_I12 structure allows IN1 at most 3 times here, and this occurrence is beyond it")
        #expect(Validator.beyondMaximumClause(segmentID: "PV1", maximum: nil, structure: "the REF_I12 structure")
            == "PV1 occurs here more times than the REF_I12 structure allows")
    }
}
