// StructureV23ProbeTests.swift
// P8b-15 (requirement 4 evidence): v2.3 messages against the structures extracted from
// the v2.3 print. v2.3 prints the message code alone over each syntax table, the events
// in the section title, no structure ID and no Table 0354, and its MSH-9 (CM) has two
// components; structure IDs are synthesised CODE_EVT (ADR-019 lookup rule 3: a v2.3
// message resolves from MSH-9.1^9.2 only). Segment content is minimal; only structure
// issues are read.

import Testing
@testable import HL7v2Kit

@Suite("v2.3 structure probes")
struct StructureV23ProbeTests {

    private func structureIssues(_ msh9: String, _ body: [String]) throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let wire = (["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||\(msh9)|MSG00001|P|2.3"] + body).joined(separator: "\r")
        return Validator(options: options).validate(try Parser().parse(wire)).issues.filter { Self.isStructure($0.code) }
    }

    private static func isStructure(_ code: IssueCode) -> Bool {
        switch code {
        case .messageStructureSegmentMissing, .messageStructureSegmentUnexpected,
             .messageStructureMismatch, .messageStructureNotModelled: true
        default: false
        }
    }

    private static func describe(_ code: IssueCode) -> String {
        switch code {
        case .messageStructureSegmentMissing(_, let segment, _): "missing \(segment)"
        case .messageStructureSegmentUnexpected(_, let segment): "unexpected \(segment)"
        default: "\(code)"
        }
    }

    // V23-A03. CH03 3.2.1 (p 3-3): ADT^A01 prints EVN and PV1 as required segments.
    @Test("ADT^A01 without EVN and PV1 raises two missing-segment findings (V23-A03)")
    func admitWithoutEventAndVisit() throws {
        #expect(try structureIssues("ADT^A01", ["EVN|A01", "PID|1", "PV1|1"]).isEmpty)
        let issues = try structureIssues("ADT^A01", ["PID|1"])
        #expect(issues.map { Self.describe($0.code) } == ["missing EVN", "missing PV1"], "\(issues.map(\.message))")
        #expect(issues.allSatisfy { $0.severity == .error && "\($0.code)".contains("ADT_A01") })
    }

    // V23-A03. CH02 2.13.1 (p 2-68): the general acknowledgment, MSH MSA [ERR], for every trigger.
    @Test("ACK without MSA raises one missing-segment finding (V23-A03)", arguments: ["ACK^A01", "ACK^R01", "ACK"])
    func acknowledgmentWithoutMSA(_ msh9: String) throws {
        #expect(try structureIssues(msh9, ["MSA|AA|MSG00001"]).isEmpty, "\(msh9)")
        let issues = try structureIssues(msh9, [])
        #expect(issues.map { Self.describe($0.code) } == ["missing MSA"], "\(msh9): \(issues.map(\.message))")
        #expect(issues.first?.severity == .error)
    }

    // ADR-019 lookup rule 3 (carry-in P8-6(b)): v2.3 defines no MSH-9.3 (CH02 2.24.1.9, MSH-9
    // is CM <message type>^<trigger event>), so a populated third component is ignored for
    // resolution: never a mismatch, never not-modelled, whatever it names.
    @Test("Lookup rule 3: a v2.3 message resolves from MSH-9.1^9.2 only; a third component is ignored",
          arguments: ["ADT^A01^ADT_A01", "ADT^A01^ADT_A04", "ADT^A01^ZZZ_Z99", "ADT^A01^ACK"])
    func ruleThree(_ msh9: String) throws {
        #expect(try structureIssues(msh9, ["EVN|A01", "PID|1", "PV1|1"]).isEmpty, "\(msh9)")
        let issues = try structureIssues(msh9, ["EVN|A01", "PID|1"])
        #expect(issues.map { Self.describe($0.code) } == ["missing PV1"], "\(msh9): \(issues.map(\.message))")
    }

    // A trigger the v2.3 print covers resolves to its own print; one it does not cover gets
    // information, never an error. Table 0003 (CH02 p 2-91) lists P04 (QRY/DSP) and CH06 6.3.4
    // (p 6-3) refers it to "the QRY/DSP transaction, as defined in Chapter 2" in prose, but no
    // syntax table is printed for P04; A99 is in no table; ZZZ^Z01 is locally defined.
    @Test("A trigger the v2.3 print does not cover is info, not an error", arguments: ["QRY^P04", "ADT^A99", "ZZZ^Z01"])
    func uncoveredTrigger(_ msh9: String) throws {
        let issues = try structureIssues(msh9, ["PID|1"])
        #expect(issues.count == 1 && issues.first?.severity == .info, "\(msh9): \(issues.map(\.message))")
        #expect(issues.first.map { if case .messageStructureNotModelled = $0.code { true } else { false } } == true)
    }
}
