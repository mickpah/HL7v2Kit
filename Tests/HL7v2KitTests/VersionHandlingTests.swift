// VersionHandlingTests.swift
// How the declared MSH-12 version selects the grammar, and how the Validator
// reports what it could not validate (ADR-018).

import Testing
@testable import HL7v2Kit

@Suite("Version handling")
struct VersionHandlingTests {

    /// Synthetic ADT^A01. `extra` segments are appended after PV1.
    func adt(version: String, pid3: String = "123456^^^HOSP^MR", extra: [String] = []) -> String {
        (["MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01^ADT_A01|MSG00001|P|\(version)",
          "EVN||20240301120000",
          "PID|1||\(pid3)||Smith^John||19800101|M",
          "PV1|1|I"] + extra).joined(separator: "\r") + "\r"
    }

    func codes(_ report: ValidationReport, segment: String) -> [ValidationIssue] {
        report.issues.filter { $0.location.segmentID == segment }
    }

    // MARK: - P3-2: non-Z segments without a grammar entry

    @Test("A non-Z segment the version does not define is a warning, never a Z-segment")
    func nonZSegmentWithoutGrammar() throws {
        // PRT is first defined in v2.7; Resources/schemas/v2.3/ has no PRT.json.
        let message = try Parser().parse(adt(version: "2.3", extra: ["PRT|1|AD"]))
        for options in [ValidationOptions.default, .strict] {
            let prt = codes(Validator(options: options).validate(message), segment: "PRT")
            #expect(!prt.contains { $0.code == .zSegmentPresent })
            let hit = try #require(prt.first { $0.code == .segmentNotInVersionGrammar })
            #expect(hit.severity == .warning)
            #expect(hit.location == IssueLocation(segmentID: "PRT", segmentIndex: 1))
            #expect(hit.message.contains("2.3"))
        }
    }

    @Test("A Z-segment still follows zSegmentPolicy")
    func zSegmentStillFollowsPolicy() throws {
        let message = try Parser().parse(adt(version: "2.3", extra: ["ZAU|1|x"]))
        let strict = codes(Validator(options: .strict).validate(message), segment: "ZAU")
        #expect(strict.map(\.code) == [.zSegmentPresent])
        #expect(strict.first?.severity == .error)
        #expect(codes(Validator().validate(message), segment: "ZAU").isEmpty)
    }
}
