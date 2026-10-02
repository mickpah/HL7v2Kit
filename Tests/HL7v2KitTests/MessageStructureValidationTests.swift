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

    @Test("An unmodelled structure is an info issue, never a silent pass")
    func notModelledStructure() throws {
        let issues = try structureIssues(Self.wire("SIU^S12^SIU_S12", []))
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "SIU_S12")])
        #expect(issues.first?.severity == .info)
        #expect(issues.first?.location.pathDescription == "MSH[1]-9")
    }

    @Test("An unmodelled two-component MSH-9 reports the trigger")
    func notModelledTrigger() throws {
        #expect(try structureIssues(Self.wire("SIU^S12", [])).map(\.code) == [.messageStructureNotModelled(structure: "SIU^S12")])
    }

    // ADR-019 lookup rule 1: an MSH-9.3 ID outside the loaded structures is
    // not modelled while the version is incomplete (a mismatch only once the
    // version is complete), even when the trigger resolves elsewhere.
    @Test("ADT^A04^ADT_A04 on the incomplete v2.5.1 pilot: not modelled, naming the printed ADT_A01, no body match")
    func a04DeclaredWrongly() throws {
        let issues = try structureIssues(Self.wire("ADT^A04^ADT_A04", [Self.pid]))
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "ADT_A04")])
        #expect(issues.first?.severity == .info)
        #expect(issues.first?.message.contains("prints ADT^A04 under ADT_A01") == true)
    }

    @Test("An MSH-9.3 differing from a modelled ID only by case or whitespace: still info, named as such, no body match",
          arguments: ["ADT_A01 ", "adt_a01"])
    func nearMissStructureID(declared: String) throws {
        let issues = try structureIssues(Self.wire("ADT^A01^\(declared)", [Self.pid]))
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: declared)])
        #expect(issues.first?.severity == .info)
        #expect(issues.first?.message.contains("differs from the modelled structure ID ADT_A01 only by case or whitespace") == true,
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

    @Test("A valid ADT^A02^ADT_A02 gets the not-modelled info issue only, never a mismatch")
    func a02UnderA02() throws {
        let issues = try structureIssues(Self.wire("ADT^A02^ADT_A02", [Self.evn, Self.pid, Self.pv1]), severity: .warning)
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "ADT_A02")])
        #expect(issues.first?.severity == .info)
    }

    // MARK: - Version rule

    @Test("A recognised version with no structure data (v2.4) is an info issue")
    func notModelledVersion() throws {
        let issues = try structureIssues(Self.wire("ADT^A01^ADT_A01", version: "2.4", [Self.evn, Self.pid, Self.pv1]))
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "ADT_A01")])
        #expect(issues.first?.severity == .info)
    }

    @Test("An unresolved MSH-12 is not matched, only the info issue", arguments: ["2.7", "2.9"])
    func unresolvedVersion(_ version: String) throws {
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

    @Test("A structure that fails the determinism lint is reported as not modelled, never matched")
    func lintFailureNotMatched() throws {
        let elements: [StructureElement] = [
            .segment("MSH", min: 1, max: 1),
            .group("G", min: 1, max: nil, elements: [
                .segment("NTE", min: 1, max: 1),
                .group("Q", min: 0, max: nil, elements: [.segment("NTE", min: 1, max: 1), .segment("OBX", min: 1, max: 1)]),
            ]),
        ]
        #expect(!StructureMatcher.lint(elements).isDeterministic)
        let structure = MessageStructure(id: "ZZZ_Z01", version: "2.5.1", triggers: ["ZZZ^Z01"], citation: "synthetic", elements: elements)
        let message = try Parser().parse(Self.wire("ZZZ^Z01^ZZZ_Z01", ["NTE|1", "NTE|2", "OBX|1", "NTE|3", "NTE|4", "OBX|2"]))
        let issues = Validator().matchStructure(structure, message: message, severity: .error)
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "ZZZ_Z01")])
    }
}
