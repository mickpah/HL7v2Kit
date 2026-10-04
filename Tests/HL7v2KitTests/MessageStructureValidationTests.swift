// MessageStructureValidationTests.swift
// ADR-019: the abstract-message-syntax check inside Validator.validate(_:),
// opt-in through ValidationOptions.messageStructureSeverity.

import Testing
import Foundation
@testable import HL7v2Kit

private extension IssueCode {
    var isMessageStructure: Bool {
        switch self {
        case .messageStructureSegmentMissing, .messageStructureSegmentUnexpected,
             .messageStructureMismatch, .messageStructureNotModelled:
            return true
        default:
            return false
        }
    }
}

@Suite("Message structure validation")
struct MessageStructureValidationTests {

    static let evn = "EVN|A01|20240101120000"
    static let pid = "PID|1||123456^^^HOSP^MR||Smith^John"
    static let pv1 = "PV1|1|I"

    static func wire(_ msh9: String, version: String = "2.5.1", msh14: String? = nil, _ body: [String]) -> String {
        let tail = msh14.map { "||\($0)" } ?? ""
        return (["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||\(msh9)|MSG00001|P|\(version)\(tail)"] + body)
            .joined(separator: "\r")
    }

    private func structureIssues(_ wire: String, severity: IssueSeverity? = .error,
                                 parser: Parser = Parser()) throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = severity
        return Validator(options: options).validate(try parser.parse(wire)).issues.filter(\.code.isMessageStructure)
    }

    private func fixtureIssues(_ name: String) throws -> [ValidationIssue] {
        let url = FixtureCorpus.fixturesDirectory().appendingPathComponent(name)
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let report = Validator(options: options).validate(try Parser().parse(Data(contentsOf: url)))
        return report.issues.filter(\.code.isMessageStructure)
    }

    // MARK: - Gating and presets

    @Test("Off by default: an ADT_A01 with no EVN raises no structure issue")
    func offByDefault() throws {
        let message = try Parser().parse(Self.wire("ADT^A01^ADT_A01", [Self.pid, Self.pv1]))
        #expect(Validator().validate(message).issues.filter(\.code.isMessageStructure).isEmpty)
    }

    @Test("All three presets leave the check off")
    func presetsOff() {
        #expect(ValidationOptions.default.messageStructureSeverity == nil)
        #expect(ValidationOptions.strict.messageStructureSeverity == nil)
        #expect(ValidationOptions.lenient.messageStructureSeverity == nil)
    }

    @Test("The configured severity is used")
    func severityFollowsOption() throws {
        let issues = try structureIssues(Self.wire("ADT^A01^ADT_A01", [Self.pid, Self.pv1]), severity: .warning)
        #expect(issues.map(\.severity) == [.warning])
    }

    // MARK: - ADT_A01

    @Test("A complete ADT_A01 raises nothing")
    func adtComplete() throws {
        #expect(try structureIssues(Self.wire("ADT^A01^ADT_A01", [Self.evn, Self.pid, Self.pv1])).isEmpty)
    }

    @Test("Missing EVN: one error at the segment it was expected before")
    func adtMissingEVN() throws {
        let issues = try structureIssues(Self.wire("ADT^A01^ADT_A01", [Self.pid, Self.pv1]))
        #expect(issues.map(\.code) == [.messageStructureSegmentMissing(structure: "ADT_A01", segmentID: "EVN", group: nil)])
        #expect(issues.first?.location.pathDescription == "PID[1]")
        #expect(issues.first?.severity == .error)
    }

    @Test("Missing PV1 at the end is anchored on the last segment")
    func adtMissingPV1() throws {
        let issues = try structureIssues(Self.wire("ADT^A01^ADT_A01", [Self.evn, Self.pid]))
        #expect(issues.map(\.code) == [.messageStructureSegmentMissing(structure: "ADT_A01", segmentID: "PV1", group: nil)])
        #expect(issues.first?.location.pathDescription == "PID[1]")
    }

    @Test("A second PID is unexpected and located at PID[2]")
    func adtSecondPID() throws {
        let issues = try structureIssues(Self.wire("ADT^A01^ADT_A01", [Self.evn, Self.pid, Self.pid, Self.pv1]))
        #expect(issues.map(\.code) == [.messageStructureSegmentUnexpected(structure: "ADT_A01", segmentID: "PID")])
        #expect(issues.first?.location.pathDescription == "PID[2]")
    }

    // MARK: - Transparent segments and locations

    @Test("Z-segments are left to the Z-segment policy, wherever they sit")
    func zSegmentsIgnored() throws {
        #expect(try structureIssues(Self.wire("ADT^A01^ADT_A01", [Self.evn, "ZAU|1", Self.pid, Self.pv1, "ZIN|x"])).isEmpty)
    }

    @Test("ADD continuations are skipped")
    func addIgnored() throws {
        #expect(try structureIssues(Self.wire("ADT^A01^ADT_A01", [Self.evn, Self.pid, "ADD|more", Self.pv1])).isEmpty)
    }

    @Test("Locations count the skipped Z and ADD segments")
    func locationsAfterSkippedSegments() throws {
        let missing = try structureIssues(Self.wire("ADT^A01^ADT_A01", ["ZAU|1", "ADD|x", Self.pid, Self.pv1]))
        #expect(missing.map(\.code) == [.messageStructureSegmentMissing(structure: "ADT_A01", segmentID: "EVN", group: nil)])
        #expect(missing.first?.location.pathDescription == "PID[1]")
        let extra = try structureIssues(Self.wire("ADT^A01^ADT_A01", [Self.evn, Self.pid, "ZAU|1", Self.pid, Self.pv1]))
        #expect(extra.map(\.location.pathDescription) == ["PID[2]"])
    }

    @Test("Missing at the end points at the last segment, a trailing Z-segment included")
    func missingAtEndAfterZ() throws {
        let issues = try structureIssues(Self.wire("ADT^A01^ADT_A01", [Self.evn, Self.pid, "ZIN|x"]))
        #expect(issues.map(\.code) == [.messageStructureSegmentMissing(structure: "ADT_A01", segmentID: "PV1", group: nil)])
        #expect(issues.first?.location.pathDescription == "ZIN[1]")
    }

    @Test("A segment the version grammar lacks is reported once, by segmentNotInVersionGrammar")
    func notInGrammarNotReportedTwice() throws {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let message = try Parser().parse(Self.wire("ADT^A01^ADT_A01", [Self.evn, "QQQ|1", Self.pid, Self.pv1]))
        let issues = Validator(options: options).validate(message).issues
        #expect(issues.filter(\.code.isMessageStructure).isEmpty)
        #expect(issues.filter { $0.code == .segmentNotInVersionGrammar }.count == 1)
    }

    // MARK: - ORU_R01 and ACK

    @Test("ORU_R01 fixture oru_r01_chemistry.hl7 conforms")
    func oruFixture() throws {
        #expect(try fixtureIssues("oru_r01_chemistry.hl7").isEmpty)
    }

    @Test("ORU_R01 with ORC but no OBR: OBR missing in ORDER_OBSERVATION, at OBX[1]")
    func oruMissingOBR() throws {
        let issues = try structureIssues(Self.wire("ORU^R01^ORU_R01", [Self.pid, "ORC|NW", "OBX|1|NM|GLU^Glucose||5.4"]))
        #expect(issues.map(\.code) == [.messageStructureSegmentMissing(structure: "ORU_R01", segmentID: "OBR", group: "ORDER_OBSERVATION")])
        #expect(issues.first?.location.pathDescription == "OBX[1]")
    }

    @Test("ACK with no MSA: MSA missing, anchored on MSH")
    func ackMissingMSA() throws {
        let issues = try structureIssues(Self.wire("ACK^A01^ACK", []))
        #expect(issues.map(\.code) == [.messageStructureSegmentMissing(structure: "ACK", segmentID: "MSA", group: nil)])
        #expect(issues.first?.location.pathDescription == "MSH[1]")
    }

    @Test("ACK fixture ack_application_accept.hl7 conforms")
    func ackFixture() throws {
        #expect(try fixtureIssues("ack_application_accept.hl7").isEmpty)
    }

    // MARK: - Resolution

    @Test("Two-component MSH-9 resolves through the trigger (ADT^A01 -> ADT_A01)")
    func resolvesFromTrigger() throws {
        let issues = try structureIssues(Self.wire("ADT^A01", [Self.pid, Self.pv1]))
        #expect(issues.map(\.code) == [.messageStructureSegmentMissing(structure: "ADT_A01", segmentID: "EVN", group: nil)])
    }

    @Test("MSH-9.3 naming a structure the trigger does not map to: the mismatch alone, no body match")
    func declaredForAnotherTrigger() throws {
        let issues = try structureIssues(Self.wire("ADT^A02^ADT_A01", [Self.pid]), severity: .warning)
        #expect(issues.map(\.code) == [.messageStructureMismatch(declared: "ADT_A01", trigger: "ADT^A02")])
        #expect(issues.first?.location.pathDescription == "MSH[1]-9.3")
        #expect(issues.first?.severity == .warning)
    }

    // P8b-9: PGL_PC6 is registered as not modelled (a G6 placeholder, CH12 12.3.1).
    @Test("An unmodelled structure is an info issue, never a silent pass")
    func notModelledStructure() throws {
        let issues = try structureIssues(Self.wire("PGL^PC6^PGL_PC6", []))
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "PGL_PC6")])
        #expect(issues.first?.severity == .info)
        #expect(issues.first?.location.pathDescription == "MSH[1]-9")
        #expect(issues.first?.message.contains("4.2.2.4") == true)
    }

    @Test("An unmodelled two-component MSH-9 reports the trigger")
    func notModelledTrigger() throws {
        #expect(try structureIssues(Self.wire("PGL^PC6", [])).map(\.code) == [.messageStructureNotModelled(structure: "PGL^PC6")])
    }

    // ADR-019 lookup rule 1: v2.5.1 is complete (P8b-9), so an MSH-9.3 ID that
    // is neither loaded nor registered as not modelled is a mismatch, with no
    // body match; on an incomplete version it stays info (synthetic tests below).
    @Test("ADT^A04^ADT_A04 on the complete v2.5.1: the mismatch alone, no body match (rule 1)")
    func a04DeclaredWrongly() throws {
        let issues = try structureIssues(Self.wire("ADT^A04^ADT_A04", [Self.pid]))
        #expect(issues.map(\.code) == [.messageStructureMismatch(declared: "ADT_A04", trigger: "ADT^A04")])
        #expect(issues.first?.severity == .error)
        #expect(issues.first?.message.contains("whose structures are all modelled") == true)
        // Unchanged by the flip: ADT^A01 and ORU^R01 resolve and match as before.
        #expect(try structureIssues(Self.wire("ADT^A01^ADT_A01", [Self.evn, Self.pid, Self.pv1])).isEmpty)
        #expect(try structureIssues(Self.wire("ADT^A04", [Self.evn, Self.pid, Self.pv1])).isEmpty)
        #expect(try structureIssues(Self.wire("ORU^R01^ORU_R01", [Self.pid, "OBR|1", "OBX|1"])).isEmpty)
    }

    // P8b-9: v2.5.1 is complete, so the near miss is a mismatch that names the loaded ID.
    @Test("An MSH-9.3 differing from a modelled ID only by case or whitespace: a mismatch on the complete v2.5.1, named as such",
          arguments: ["ADT_A01 ", "adt_a01"])
    func nearMissStructureID(declared: String) throws {
        let issues = try structureIssues(Self.wire("ADT^A01^\(declared)", [Self.pid]))
        #expect(issues.map(\.code) == [.messageStructureMismatch(declared: declared, trigger: "ADT^A01")])
        #expect(issues.first?.severity == .error)
        #expect(issues.first?.message.contains("it differs from ADT_A01 only by case or whitespace") == true,
                "\(issues.map(\.message))")
    }

    @Test("A two-component ACK resolves through ACK^* whatever the event")
    func ackTwoComponents() throws {
        #expect(try structureIssues(Self.wire("ACK^R01", ["MSA|AA|MSG00001"])).isEmpty)
        #expect(try structureIssues(Self.wire("ACK^R01^ACK", [])).map(\.code)
            == [.messageStructureSegmentMissing(structure: "ACK", segmentID: "MSA", group: nil)])
    }

    static func synthetic(_ id: String) -> MessageStructure {
        MessageStructure(id: id, version: "2.5.1", triggers: ["ZZZ^Z01"], citation: "synthetic",
                         elements: [.segment("MSH", min: 1, max: 1), .segment("PID", min: 1, max: 1)])
    }

    @Test("A trigger printed under two loaded structures is ambiguous: not modelled, naming both (B6)")
    func ambiguousTrigger() throws {
        let table = ["ZZZ_Z01": Self.synthetic("ZZZ_Z01"), "ZZZ_Z02": Self.synthetic("ZZZ_Z02")]
        let message = try Parser().parse(Self.wire("ZZZ^Z01", [Self.pid]))
        let resolved = Validator().resolveStructure(message, severity: .error, structures: table)
        #expect(resolved.structure == nil)
        #expect(resolved.issues.map(\.code) == [.messageStructureNotModelled(structure: "ZZZ^Z01")])
        #expect(resolved.issues.first?.message.contains("ambiguous") == true)
        #expect(resolved.issues.first?.message.contains("ZZZ_Z01 and ZZZ_Z02") == true)
        #expect(resolved.issues.first?.message.contains("no v2.5.1 abstract message syntax") == false)

        let declared = try Parser().parse(Self.wire("ZZZ^Z01^ZZZ_Z02", [Self.pid]))
        let named = Validator().resolveStructure(declared, severity: .error, structures: table)
        #expect(named.structure?.id == "ZZZ_Z02")
        #expect(named.issues.isEmpty)
    }

    // P8b-9: a declared shared trigger (overrides.json sharedTriggers) whose other
    // structure is registered as not modelled (v2.5.1 MFR^M04 under MFR_M01 and MFR_M04).
    @Test("A trigger shared with a registered not-modelled structure is ambiguous without MSH-9.3 (rule 2)")
    func ambiguousWithRegisteredGap() throws {
        let table = ["ZZZ_Z01": Self.synthetic("ZZZ_Z01")]
        let gaps = ["ZZZ_Z00": NotModelledStructure(triggers: ["ZZZ^Z00", "ZZZ^Z01"], reason: "a template (synthetic)")]
        let message = try Parser().parse(Self.wire("ZZZ^Z01", [Self.pid]))
        let resolved = Validator().resolveStructure(message, severity: .error, structures: table, complete: [.v2_5_1], gaps: gaps)
        #expect(resolved.structure == nil)
        #expect(resolved.issues.map(\.code) == [.messageStructureNotModelled(structure: "ZZZ^Z01")])
        #expect(resolved.issues.first?.severity == .info)
        #expect(resolved.issues.first?.message.contains("ambiguous, printed under ZZZ_Z00 and ZZZ_Z01") == true,
                "\(resolved.issues.map(\.message))")

        let declared = try Parser().parse(Self.wire("ZZZ^Z01^ZZZ_Z01", [Self.pid]))
        let named = Validator().resolveStructure(declared, severity: .error, structures: table, complete: [.v2_5_1], gaps: gaps)
        #expect(named.structure?.id == "ZZZ_Z01")
        #expect(named.issues.isEmpty)
    }

    @Test("A registered not-modelled structure is info on a complete version, a mismatch only for a trigger it does not print")
    func registeredGapOnCompleteVersion() throws {
        let table = ["ZZZ_Z01": Self.synthetic("ZZZ_Z01")]
        let gaps = ["ZZZ_Z00": NotModelledStructure(triggers: ["ZZZ^Z00"], reason: "a template (synthetic)"),
                    "ZZZ_Z09": NotModelledStructure(triggers: [], reason: "Table 0354 only (synthetic)")]
        func resolve(_ msh9: String) throws -> [ValidationIssue] {
            let message = try Parser().parse(Self.wire(msh9, [Self.pid]))
            return Validator().resolveStructure(message, severity: .error, structures: table, complete: [.v2_5_1], gaps: gaps).issues
        }
        let byID = try resolve("ZZZ^Z00^ZZZ_Z00")
        #expect(byID.map(\.code) == [.messageStructureNotModelled(structure: "ZZZ_Z00")])
        #expect(byID.first?.severity == .info)
        #expect(byID.first?.message.contains("a template (synthetic)") == true)
        let byTrigger = try resolve("ZZZ^Z00")
        #expect(byTrigger.map(\.code) == [.messageStructureNotModelled(structure: "ZZZ^Z00")])
        #expect(byTrigger.first?.message.contains("under ZZZ_Z00, which is not modelled: a template (synthetic)") == true)
        let tableOnly = try resolve("ZZZ^Z01^ZZZ_Z09")
        #expect(tableOnly.map(\.code) == [.messageStructureNotModelled(structure: "ZZZ_Z09")])
        let wrongEvent = try resolve("ZZZ^Z01^ZZZ_Z00")
        #expect(wrongEvent.map(\.code) == [.messageStructureMismatch(declared: "ZZZ_Z00", trigger: "ZZZ^Z01")])
        #expect(wrongEvent.first?.severity == .error)
    }

    // P8b-1: lookup rule 1's complete-version branch, proven on a synthetic
    // complete version (no version is complete yet).
    @Test("Rule 1: an MSH-9.3 naming no loaded structure is a mismatch on a complete version, info otherwise")
    func unknownIDOnCompleteVersion() throws {
        let table = ["ZZZ_Z01": Self.synthetic("ZZZ_Z01")]
        let message = try Parser().parse(Self.wire("ZZZ^Z01^ZZZ_Z99", [Self.pid]))
        let complete = Validator().resolveStructure(message, severity: .error, structures: table, complete: [.v2_5_1])
        #expect(complete.structure == nil)
        #expect(complete.issues.map(\.code) == [.messageStructureMismatch(declared: "ZZZ_Z99", trigger: "ZZZ^Z01")])
        #expect(complete.issues.first?.severity == .error)

        let incomplete = Validator().resolveStructure(message, severity: .error, structures: table, complete: [])
        #expect(incomplete.issues.map(\.code) == [.messageStructureNotModelled(structure: "ZZZ_Z99")])
        #expect(incomplete.issues.first?.severity == .info)

        let otherComplete = Validator().resolveStructure(message, severity: .error, structures: table, complete: [.v2_6])
        #expect(otherComplete.issues.map(\.code) == [.messageStructureNotModelled(structure: "ZZZ_Z99")])
    }

    @Test("Rule 1 on a complete version: an ID differing only by case is a mismatch, naming the modelled ID")
    func nearMissOnCompleteVersion() throws {
        let table = ["ZZZ_Z01": Self.synthetic("ZZZ_Z01")]
        let message = try Parser().parse(Self.wire("ZZZ^Z01^zzz_z01", [Self.pid]))
        let resolved = Validator().resolveStructure(message, severity: .warning, structures: table, complete: [.v2_5_1])
        #expect(resolved.issues.map(\.code) == [.messageStructureMismatch(declared: "zzz_z01", trigger: "ZZZ^Z01")])
        #expect(resolved.issues.first?.severity == .warning)
        #expect(resolved.issues.first?.message.contains("ZZZ_Z01") == true, "\(resolved.issues.map(\.message))")
    }

    @Test("A 2.8 message on a complete v2.8.2 uses rule 1 (pre-flight C3)")
    func substitutedVersionUsesRuleOne() throws {
        let table = ["ZZZ_Z01": Self.synthetic("ZZZ_Z01")]
        let message = try Parser().parse(Self.wire("ZZZ^Z01^ZZZ_Z99", version: "2.8", [Self.pid]))
        #expect(message.version.grammarVersion == .v2_8_2)
        let resolved = Validator().resolveStructure(message, severity: .error, structures: table, complete: [.v2_8_2])
        #expect(resolved.issues.map(\.code) == [.messageStructureMismatch(declared: "ZZZ_Z99", trigger: "ZZZ^Z01")])
        let known = try Parser().parse(Self.wire("ZZZ^Z01^ZZZ_Z01", version: "2.8", [Self.pid]))
        #expect(Validator().resolveStructure(known, severity: .error, structures: table, complete: [.v2_8_2]).structure?.id == "ZZZ_Z01")
    }

    @Test("Default: v2.5.1 is complete (P8b-9), so an unknown MSH-9.3 on v2.5.1 is a mismatch")
    func defaultCompletenessUnchanged() throws {
        let issues = try structureIssues(Self.wire("ADT^A01^ADT_Z99", [Self.evn, Self.pid, Self.pv1]))
        #expect(issues.map(\.code) == [.messageStructureMismatch(declared: "ADT_Z99", trigger: "ADT^A01")])
    }

    @Test("ADT^A02^ADT_A01 contradicts v2.5.1 (ADT_A01 is printed for A01, A04, A08, A13 only)")
    func a02UnderA01() throws {
        let issues = try structureIssues(Self.wire("ADT^A02^ADT_A01", [Self.evn, Self.pid, Self.pv1]))
        #expect(issues.map(\.code) == [.messageStructureMismatch(declared: "ADT_A01", trigger: "ADT^A02")])
    }

    @Test("ADT^A08^ADT_A01 agrees with the print")
    func a08UnderA01() throws {
        #expect(try structureIssues(Self.wire("ADT^A08^ADT_A01", [Self.evn, Self.pid, Self.pv1])).isEmpty)
    }

    @Test("MSH-9 of just ACK resolves to the ACK structure (event varies)")
    func ackCodeOnly() throws {
        #expect(try structureIssues(Self.wire("ACK", ["MSA|AA|MSG00001"])).isEmpty)
    }

    @Test("ADT^A01^ACK: ACK^* accepts only message code ACK, so the mismatch alone")
    func ackStructureUnderADT() throws {
        let issues = try structureIssues(Self.wire("ADT^A01^ACK", [Self.evn, Self.pid, Self.pv1]), severity: .warning)
        #expect(issues.map(\.code) == [.messageStructureMismatch(declared: "ACK", trigger: "ADT^A01")])
        #expect(issues.first?.severity == .warning)
    }

    // P8b-9: ADT_A02 is modelled from CH03 3.3.2.
    @Test("A valid ADT^A02^ADT_A02 gets no structure issue")
    func a02UnderA02() throws {
        #expect(try structureIssues(Self.wire("ADT^A02^ADT_A02", [Self.evn, Self.pid, Self.pv1]), severity: .warning).isEmpty)
    }

    // MARK: - Version rule

    @Test("A recognised version with no structure data (v2.4) is an info issue")
    func notModelledVersion() throws {
        let issues = try structureIssues(Self.wire("ADT^A01^ADT_A01", version: "2.4", [Self.evn, Self.pid, Self.pv1]))
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "ADT_A01")])
        #expect(issues.first?.severity == .info)
    }

    @Test("An unresolved MSH-12 is not matched, only the info issue", arguments: ["2.8.1", "2.9"])
    func unresolvedVersion(_ version: String) throws {
        let issues = try structureIssues(Self.wire("ADT^A01^ADT_A01", version: version, [Self.pid]))
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "ADT_A01")])
        #expect(issues.first?.severity == .info)
    }

    @Test("v2.7.1 has no modelled message structures: 2.7.1 and 2.7 get only the info issue",
          arguments: ["2.7.1", "2.7"])
    func v271StructuresNotModelled(_ version: String) throws {
        let issues = try structureIssues(Self.wire("ADT^A01^ADT_A01", version: version, [Self.pid]))
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "ADT_A01")])
        #expect(issues.first?.severity == .info)
    }

    @Test("An empty MSH-12 is not matched, only the info issue")
    func emptyVersion() throws {
        let issues = try structureIssues(Self.wire("ADT^A01^ADT_A01", version: "", [Self.pid]))
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "ADT_A01")])
    }

    @Test("A message whose version differs from the wire reading (versionOverride) is not matched")
    func overriddenVersion() throws {
        let parser = Parser(options: ParserOptions(versionOverride: .v2_5_1))
        let issues = try structureIssues(Self.wire("ADT^A01^ADT_A01", version: "2.4", [Self.pid]), parser: parser)
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "ADT_A01")])
    }

    // MARK: - Fragments

    @Test("A populated MSH-14 marks a fragment: info issue, no body match")
    func continuationFragment() throws {
        let issues = try structureIssues(Self.wire("ADT^A01^ADT_A01", msh14: "CONT0001", [Self.pid]))
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "ADT_A01")])
        #expect(issues.first?.severity == .info)
    }

    @Test("A last DSC the structure does not define marks a fragment")
    func dscFragment() throws {
        let issues = try structureIssues(Self.wire("ADT^A01^ADT_A01", [Self.evn, Self.pid, "DSC|CONT0001"]))
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "ADT_A01")])
        let empty = try structureIssues(Self.wire("ADT^A01^ADT_A01", [Self.evn, Self.pid, Self.pv1, "DSC"]))
        #expect(empty.map(\.code) == [.messageStructureNotModelled(structure: "ADT_A01")])
    }

    @Test("ORU first fragment (PID then DSC with a continuation pointer): the info issue only")
    func oruFirstFragment() throws {
        let issues = try structureIssues(Self.wire("ORU^R01^ORU_R01", [Self.pid, "DSC|CP001|F"]))
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "ORU_R01")])
        #expect(issues.first?.severity == .info)
    }

    @Test("A complete ORU ending in a DSC with an empty DSC-1 is matched as usual")
    func dscEmptyPointerMatched() throws {
        let body = [Self.pid, "OBR|1||F1|GLU^Glucose", "OBX|1|NM|GLU^Glucose||5.4", "DSC"]
        #expect(try structureIssues(Self.wire("ORU^R01^ORU_R01", body)).isEmpty)
        let missing = try structureIssues(Self.wire("ORU^R01^ORU_R01", [Self.pid, "DSC||F"]))
        #expect(missing.map(\.code) == [.messageStructureSegmentMissing(structure: "ORU_R01", segmentID: "OBR", group: "ORDER_OBSERVATION")])
    }

    @Test("A complete ORU ending in a DSC with a continuation pointer is not matched (the info issue only)")
    func dscPointerOnCompleteMessage() throws {
        let body = [Self.pid, "OBR|1||F1|GLU^Glucose", "OBX|1|NM|GLU^Glucose||5.4", "DSC|CP001", "ZIN|x"]
        #expect(try structureIssues(Self.wire("ORU^R01^ORU_R01", body)).map(\.code) == [.messageStructureNotModelled(structure: "ORU_R01")])
    }

    @Test("An empty MSH-9 gets a clear info issue")
    func emptyMSH9() throws {
        let issues = try structureIssues(Self.wire("", [Self.pid]))
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "")])
        #expect(issues.first?.message.contains("MSH-9 is empty") == true)
        #expect(issues.first?.message.contains("for :") == false)
    }

    // MARK: - Lint

    /// `MSH {G: NTE [{Q: NTE OBX}]}`: fails the lint (Q's NTE against G's re-entry).
    private static let lintFailing: [StructureElement] = [
        .segment("MSH", min: 1, max: 1),
        .group("G", min: 1, max: nil, elements: [
            .segment("NTE", min: 1, max: 1),
            .group("Q", min: 0, max: nil, elements: [.segment("NTE", min: 1, max: 1), .segment("OBX", min: 1, max: 1)]),
        ]),
    ]

    @Test("A structure that fails the determinism lint is matched exactly, not reported as not modelled (P8b-12)")
    func lintFailureMatchedExactly() throws {
        #expect(!StructureMatcher.lint(Self.lintFailing).isDeterministic)
        let structure = MessageStructure(id: "ZZZ_Z01", version: "2.5.1", triggers: ["ZZZ^Z01"], citation: "synthetic", elements: Self.lintFailing)
        #expect(structure.requiresExactMatch)
        let good = try Parser().parse(Self.wire("ZZZ^Z01^ZZZ_Z01", ["NTE|1", "NTE|2", "OBX|1", "NTE|3", "NTE|4", "OBX|2"]))
        #expect(Validator().matchStructure(structure, message: good, severity: .error).isEmpty)
        let bad = try Parser().parse(Self.wire("ZZZ^Z01^ZZZ_Z01", ["NTE|1", "OBX|1"]))
        let issues = Validator().matchStructure(structure, message: bad, severity: .error)
        #expect(issues.map(\.code) == [.messageStructureSegmentUnexpected(structure: "ZZZ_Z01", segmentID: "OBX")])
        #expect(issues.first?.location == IssueLocation(segmentID: "OBX", segmentIndex: 1))
        let empty = try Parser().parse(Self.wire("ZZZ^Z01^ZZZ_Z01", []))
        #expect(Validator().matchStructure(structure, message: empty, severity: .error).map(\.code)
                == [.messageStructureSegmentMissing(structure: "ZZZ_Z01", segmentID: "NTE", group: "G")])
    }

    @Test("The Validator selects the matcher by the structure's flag and never lints a message")
    func selectionByFlag() throws {
        // The same lint-failing structure with the flag forced off goes through the one-pass
        // matcher, which rejects the valid message: the flag, not a per-message lint, decides.
        let forced = MessageStructure(id: "ZZZ_Z01", version: "2.5.1", triggers: ["ZZZ^Z01"], citation: "synthetic",
                                      requiresExactMatch: false, elements: Self.lintFailing)
        let good = try Parser().parse(Self.wire("ZZZ^Z01^ZZZ_Z01", ["NTE|1", "NTE|2", "OBX|1", "NTE|3", "NTE|4", "OBX|2"]))
        let issues = Validator().matchStructure(forced, message: good, severity: .error)
        #expect(!issues.isEmpty)
        #expect(!issues.contains { if case .messageStructureNotModelled = $0.code { return true } else { return false } })
    }
}
