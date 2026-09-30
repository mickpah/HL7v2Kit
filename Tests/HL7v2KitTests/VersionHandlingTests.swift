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

    // MARK: - P3-3: 2.8 validated against the v2.8.2 grammar

    static let substitution = IssueCode.versionGrammarSubstituted(declared: .v2_8, validatedAs: .v2_8_2)

    @Test("Every version is its own grammar version except 2.8, which is v2.8.2")
    func grammarVersionMapping() {
        for version in Version.allCases where version != .v2_8 {
            #expect(version.grammarVersion == version)
        }
        #expect(Version.v2_8.grammarVersion == .v2_8_2)
    }

    @Test("A 2.8 message reports the v2.8.2 substitution once, as info at MSH-12")
    func substitutionIsAnnounced() throws {
        let message = try Parser().parse(adt(version: "2.8"))
        #expect(message.version == .v2_8)
        let hits = Validator().validate(message).issues.filter { $0.code == Self.substitution }
        #expect(hits.count == 1)
        let hit = try #require(hits.first)
        #expect(hit.severity == .info)
        #expect(hit.location == IssueLocation(segmentID: "MSH", segmentIndex: 1, fieldIndex: 12))
        #expect(hit.message.contains("2.8.2"))
    }

    @Test("2.8 and 2.8.2 draw the same findings apart from the substitution note")
    func sameFindingsAsV282() throws {
        // OBR-24 "XX" is outside closed Table 0074 (Diagnostic Service Section ID; table
        // 0203 is open since P2-7 (gate G5), so it cannot demonstrate this), so the grammar
        // demonstrably runs.
        let obr = "OBR|1|A|B|C^D||||||||||||||||||||XX"
        let wire282 = adt(version: "2.8.2", extra: [obr])
        let wire28 = adt(version: "2.8", extra: [obr])
        let expected = Validator().validate(try Parser().parse(wire282)).issues
        let actual = Validator().validate(try Parser().parse(wire28)).issues
            .filter { $0.code != Self.substitution }
        #expect(expected.contains { $0.code == .valueNotInTable(table: "0074") })
        #expect(actual == expected)
    }

    @Test("Under .strict a 2.8 message has no Z-segment issue on MSH, EVN, PID or PV1")
    func strictNoZSegmentsOn28() throws {
        let report = Validator(options: .strict).validate(try Parser().parse(adt(version: "2.8")))
        #expect(!report.issues.contains { $0.code == .zSegmentPresent })
        #expect(report.issues.filter { $0.code == Self.substitution }.count == 1)
    }

    // MARK: - P3-4: MSH-12 is a VID; the version is VID.1

    @Test("MSH-12 in VID form takes the version from VID.1", arguments: [
        (wire: "2.4^AUS&Australia&ISO3166_1", expected: Version.v2_4),
        (wire: "2.4^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L", expected: Version.v2_4),
        (wire: "2.3.1^AUS", expected: Version.v2_3_1),
        (wire: "2.8.2^^HL7AU", expected: Version.v2_8_2),
        (wire: " 2.6 ^AUS", expected: Version.v2_6),
    ])
    func vidFormResolvesVersion(_ testCase: (wire: String, expected: Version)) throws {
        #expect(try Parser().parse(adt(version: testCase.wire)).version == testCase.expected)
    }

    @Test("Strict parsing rejects an unknown VID.1 and names VID.1 only")
    func strictRejectsUnknownVID1() {
        #expect(throws: ParseError.unsupportedVersion(found: "9.9.9")) {
            try Parser(options: .strict).parse(adt(version: "9.9.9^AUS"))
        }
    }

    @Test("An empty VID.1 still falls back to v2.5.1")
    func emptyVID1FallsBack() throws {
        #expect(try Parser().parse(adt(version: "^AUS")).version == .v2_5_1)
    }

    // AU v2.4 traffic now meets the v2.4 grammar, not v2.5.1. v2.4 types
    // MSH-9 as CM with no component optionality, and "the second component
    // is not required on response or acknowledgment messages" (HL7 v2.4
    // Chapter 2, 2.16.9.9). v2.5.1 types it as MSG with MSG.2 and MSG.3
    // required. The AU profile's own MSG.2/MSG.3 rule (HL7au:00049.2/.3,
    // ORM/ORU/REF only) must still fire.
    static let auMSH12 = "2.4^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L"

    func baseMSH9ComponentIssues(_ report: ValidationReport) -> [ValidationIssue] {
        report.issues.filter {
            $0.code == .requiredComponentMissing
                && $0.location.segmentID == "MSH" && $0.location.fieldIndex == 9
        }
    }

    @Test("AU ORU at 2.4^AUS... applies v2.4 MSH-9 grammar and keeps HL7au:00049.2/.3")
    func auORUUsesV24Grammar() throws {
        let wire = "MSH|^~\\&|LAB|FAC|GP|FAC|||ORU^R01|MSG1|P|\(Self.auMSH12)\r"
        let message = try Parser(locale: .auLocalisation).parse(wire)
        #expect(message.version == .v2_4)
        let report = Validator(locale: .auLocalisation).validate(message)
        #expect(baseMSH9ComponentIssues(report).isEmpty)
        #expect(report.issues.contains {
            if case .profileConstraintViolation(let rule) = $0.code { return rule.hasPrefix("HL7au:00049.2/.3") }
            return false
        })
    }

    @Test("AU ACK at 2.4^AUS... is not required to value MSH-9.2 or MSH-9.3 under v2.4")
    func auACKUsesV24Grammar() throws {
        let wire = "MSH|^~\\&|LAB|FAC|GP|FAC|||ACK|MSG1|P|\(Self.auMSH12)\rMSA|AA|MSG0\r"
        let message = try Parser(locale: .auLocalisation).parse(wire)
        #expect(message.version == .v2_4)
        #expect(baseMSH9ComponentIssues(Validator(locale: .auLocalisation).validate(message)).isEmpty)
    }

    // MARK: - P3-4 fix round 1: strict whitespace MSH-12, HL7au:00049.1

    @Test("Strict parsing treats a whitespace-only MSH-12 as empty and falls back to v2.5.1")
    func strictWhitespaceMSH12FallsBack() throws {
        #expect(try Parser(options: .strict).parse(adt(version: "  ")).version == .v2_5_1)
    }

    func msh91Violations(_ report: ValidationReport) -> [ValidationIssue] {
        report.issues.filter {
            if case .profileConstraintViolation(let rule) = $0.code { return rule.hasPrefix("HL7au:00049.1") }
            return false
        }
    }

    func auORU(msh9: String, msh12: String) throws -> ValidationReport {
        let wire = "MSH|^~\\&|LAB|FAC|GP|FAC|||\(msh9)|MSG1|P|\(msh12)\r"
        return Validator(locale: .auLocalisation).validate(try Parser(locale: .auLocalisation).parse(wire))
    }

    @Test("HL7au:00049.1 fires at MSH-9.1 on AU v2.4 traffic with no message code")
    func au000491FiresOnV24() throws {
        let report = try auORU(msh9: "^R01^ORU_R01", msh12: Self.auMSH12)
        let hits = msh91Violations(report)
        #expect(hits.count == 1)
        #expect(hits.first?.location.segmentID == "MSH")
        #expect(hits.first?.location.fieldIndex == 9)
        #expect(hits.first?.location.componentIndex == 1)
    }

    @Test("HL7au:00049.1 is silent when MSH-9.1 is valued")
    func au000491SilentWhenValued() throws {
        #expect(msh91Violations(try auORU(msh9: "ORU^R01^ORU_R01", msh12: Self.auMSH12)).isEmpty)
    }

    @Test("HL7au:00049.1 yields to the v2.5.1 base MSG.1 check: one finding, not two")
    func au000491DoesNotDoubleFireOnV251() throws {
        let report = try auORU(msh9: "^R01^ORU_R01", msh12: "2.5.1^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L")
        #expect(msh91Violations(report).isEmpty)
        #expect(baseMSH9ComponentIssues(report).map(\.location.componentIndex) == [1])
    }

    // MARK: - P3-5: unrecognised versions

    static func isVersionNotRecognised(_ issue: ValidationIssue) -> Bool {
        if case .versionNotRecognised = issue.code { return true } else { return false }
    }

    @Test("An MSH-12 version HL7v2Kit does not model yields one warning naming the fallback",
          arguments: ["2.1", "2.2", "2.5", "2.7", "2.7.1", "2.8.1", "2.9"])
    func unrecognisedVersionWarns(_ wireVersion: String) throws {
        let message = try Parser().parse(adt(version: wireVersion))
        #expect(message.version == .v2_5_1)
        let hits = Validator().validate(message).issues.filter(Self.isVersionNotRecognised)
        #expect(hits.count == 1)
        let hit = try #require(hits.first)
        #expect(hit.code == .versionNotRecognised(wireValue: wireVersion))
        #expect(hit.severity == .warning)
        #expect(hit.location == IssueLocation(segmentID: "MSH", segmentIndex: 1, fieldIndex: 12))
        #expect(hit.message.contains("2.5.1"))
    }

    @Test("The warning names VID.1, not the whole VID")
    func unrecognisedVID1Only() throws {
        let report = Validator().validate(try Parser().parse(adt(version: "2.8.1^AUS")))
        #expect(report.issues.filter(Self.isVersionNotRecognised).map(\.code)
                == [.versionNotRecognised(wireValue: "2.8.1")])
    }

    @Test("A recognised version never raises versionNotRecognised", arguments: Version.allCases)
    func recognisedVersionQuiet(_ version: Version) throws {
        let report = Validator().validate(try Parser().parse(adt(version: version.rawValue)))
        #expect(report.issues.filter(Self.isVersionNotRecognised).isEmpty)
    }

    @Test("With a version override the warning names the grammar actually applied")
    func overrideNamedInWarning() throws {
        let message = try Parser(options: ParserOptions(versionOverride: .v2_6)).parse(adt(version: "2.7.1"))
        let hit = try #require(Validator().validate(message).issues.first(where: Self.isVersionNotRecognised))
        #expect(hit.message.contains("v2.6"))
    }

    @Test("An empty MSH-12 is the required-field check's business, not this warning")
    func emptyMSH12NotReportedHere() throws {
        let report = Validator().validate(try Parser().parse(adt(version: "")))
        #expect(report.issues.filter(Self.isVersionNotRecognised).isEmpty)
    }

    // MARK: - P3-5 carry-in: yieldsToBase only defers when the base check runs

    @Test("Under .lenient, HL7au:00049.1 still fires on v2.5.1 because checkComponentGrammar is off")
    func au000491FiresUnderLenientWhenBaseCheckIsOff() throws {
        let wire = "MSH|^~\\&|LAB|FAC|GP|FAC|||^R01^ORU_R01|MSG1|P|2.5.1^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L\r"
        let message = try Parser(locale: .auLocalisation).parse(wire)
        let report = Validator(options: .lenient, locale: .auLocalisation).validate(message)
        // v2.5.1 already requires MSG.1, but that base check is `checkComponentGrammar`-gated
        // and `.lenient` turns it off, so it never runs here.
        #expect(baseMSH9ComponentIssues(report).isEmpty)
        // The AU profile rule must not yield to a base check that isn't running, or the
        // empty MSH-9.1 would go entirely unreported (P3-5 carry-in 5).
        #expect(msh91Violations(report).count == 1)
    }
}
