// StructureV231ProbeTests.swift
// P8b-14 (requirement 4 evidence): v2.3.1 messages against the structures extracted
// from the v2.3.1 print. v2.3.1 captions mostly print CODE^EVT alone; the structure ID
// comes from the version's own Table 0354 (Chapter 2, section 2.24.1.9, pp 2-103 to
// 2-106), read through cited errata where the table misprints a row. Group names come
// from the HL7-xml 2.3.1 bundle first, then the v2.4 bundle. Segment content is
// minimal; only structure issues are read.

import Testing
@testable import HL7v2Kit

@Suite("v2.3.1 structure probes")
struct StructureV231ProbeTests {

    struct Resolution: Sendable, CustomTestStringConvertible {
        let msh9: String
        let structure: String
        let compliant: [String]
        let variant: [String]
        /// "missing SEG" or "unexpected SEG": the variant's finding.
        let finding: String
        var testDescription: String { msh9 }
    }

    // V231-A03: each trigger resolves, with or without MSH-9.3, to the structure Table 0354
    // gives it, and the body is matched against the print.
    static let resolutions: [Resolution] = [
        // CH02 2.13.1 (p 2-78): the general acknowledgment, folded onto ACK^* (no Table 0354 row).
        Resolution(msh9: "ACK^A01", structure: "ACK", compliant: ["MSA|AA|1"], variant: ["ERR|1"], finding: "missing MSA"),
        Resolution(msh9: "ACK^A01^ACK", structure: "ACK", compliant: ["MSA|AA|1", "ERR|1"], variant: ["ERR|1"], finding: "missing MSA"),
        // CH03 3.2.1 (p 3-2): PV1 is required.
        Resolution(msh9: "ADT^A01", structure: "ADT_A01", compliant: ["EVN|A01", "PID|1", "PV1|1"],
                   variant: ["EVN|A01", "PID|1"], finding: "missing PV1"),
        Resolution(msh9: "ADT^A01^ADT_A01", structure: "ADT_A01", compliant: ["EVN|A01", "PID|1", "PV1|1"],
                   variant: ["EVN|A01", "PID|1"], finding: "missing PV1"),
        // CH04 4.7 (p 4-53): ORM^O01 is printed under five structures; MSH-9.3 names the stock
        // requisition, whose order detail is RQD.
        Resolution(msh9: "ORM^O01^OMS_O01", structure: "OMS_O01", compliant: ["PID|1", "ORC|NW", "RQD|1"],
                   variant: ["PID|1", "RQD|1"], finding: "unexpected RQD"),
        // CH07 7.2.1: an OBX belongs to an ORDER_OBSERVATION, which OBR opens.
        Resolution(msh9: "ORU^R01", structure: "ORU_R01", compliant: ["PID|1", "OBR|1", "OBX|1"],
                   variant: ["PID|1", "OBX|1"], finding: "unexpected OBX"),
        Resolution(msh9: "ORU^R01^ORU_R01", structure: "ORU_R01", compliant: ["PID|1", "OBR|1", "OBX|1"],
                   variant: ["PID|1", "OBX|1"], finding: "unexpected OBX"),
        // CH07 ORF^R04: Table 0354 maps R02 and R04 to ORF_R02; QRD is required.
        Resolution(msh9: "ORF^R04", structure: "ORF_R02", compliant: ["MSA|AA|1", "QRD|1", "OBR|1"],
                   variant: ["MSA|AA|1", "OBR|1"], finding: "unexpected OBR"),
        Resolution(msh9: "ORF^R04^ORF_R02", structure: "ORF_R02", compliant: ["MSA|AA|1", "QRD|1", "OBR|1"],
                   variant: ["MSA|AA|1", "OBR|1"], finding: "unexpected OBR"),
    ]

    private func structureIssues(_ msh9: String, _ body: [String]) throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let wire = (["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||\(msh9)|MSG00001|P|2.3.1"] + body).joined(separator: "\r")
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

    @Test("v2.3.1 triggers resolve through Table 0354 and are matched (V231-A03)", arguments: resolutions)
    func resolves(_ r: Resolution) throws {
        #expect(MessageStructureTable.structure(r.structure, version: .v2_3_1) != nil, "\(r.structure) is not modelled")
        let ok = try structureIssues(r.msh9, r.compliant)
        #expect(ok.isEmpty, "\(r.msh9): \(ok.map(\.message))")
        let bad = try structureIssues(r.msh9, r.variant)
        #expect(bad.contains { Self.describe($0.code) == r.finding && $0.severity == .error },
                "\(r.msh9): \(bad.map { Self.describe($0.code) })")
        #expect(bad.allSatisfy { "\($0.code)".contains(r.structure) }, "\(r.msh9): \(bad.map(\.message))")
    }

    // CH04 4.2.1 (p 4-3) prints the general order's detail as "Order Detail Segment OBR,
    // etc.", which use note b and section 4.7 leave open between one segment and a
    // combination (ruling G6): ORM_O01 is registered, so MSH-9.3 ORM_O01 is info with
    // the register reason, and ORM^O01 alone is ambiguous (five structures).
    @Test("ORM^O01: ORM_O01 is registered (info); without MSH-9.3 the trigger is ambiguous")
    func generalOrder() throws {
        let declared = try structureIssues("ORM^O01^ORM_O01", ["PID|1", "ORC|NW", "OBR|1"])
        #expect(declared.map(\.code) == [.messageStructureNotModelled(structure: "ORM_O01")], "\(declared.map(\.message))")
        #expect(declared.first?.severity == .info && declared.first?.message.contains("Order Detail Segment") == true,
                "\(declared.map(\.message))")
        let bare = try structureIssues("ORM^O01", ["PID|1", "ORC|NW", "OBR|1"])
        #expect(bare.count == 1 && bare.first?.severity == .info && bare.first?.message.contains("ambiguous") == true,
                "\(bare.map(\.message))")
    }

    // Table 0354 (p 2-103) lists A28 and A31 under ADT_A01 and ADT_A28; CH03 3.2.28 and
    // 3.2.31 print them with ADT_A01's syntax (declared shared triggers). MSH-9.3 picks one.
    @Test("ADT^A28 and ADT^A31: matched with MSH-9.3 against either structure; ambiguous without it",
          arguments: ["ADT^A28", "ADT^A31"])
    func sharedPersonTriggers(_ trigger: String) throws {
        for sid in ["ADT_A01", "ADT_A28"] {
            #expect(try structureIssues("\(trigger)^\(sid)", ["EVN|A28", "PID|1", "PV1|1"]).isEmpty, "\(trigger)^\(sid)")
            #expect(try structureIssues("\(trigger)^\(sid)", ["EVN|A28", "PID|1"]).map { Self.describe($0.code) } == ["missing PV1"])
        }
        let bare = try structureIssues(trigger, ["EVN|A28", "PID|1", "PV1|1"])
        #expect(bare.count == 1 && bare.first?.message.contains("ambiguous") == true, "\(bare.map(\.message))")
    }

    // Captions Table 0354 places under no structure (overrides.json unresolvedCaptions):
    // MFN^M04 (CH08 8.9.1, p 8-60; no MFN_M04 row) and the master files query MFQ (no
    // MFQ row) are not modelled: info, never a false finding.
    @Test("Triggers with no Table 0354 structure are info", arguments: ["MFN^M04", "MFQ^M01"])
    func noStructureID(_ msh9: String) throws {
        let issues = try structureIssues(msh9, ["MFI|1"])
        #expect(issues.count == 1 && issues.first?.severity == .info, "\(issues.map(\.message))")
    }
}
