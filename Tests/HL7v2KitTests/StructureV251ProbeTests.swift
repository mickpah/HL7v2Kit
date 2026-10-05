// StructureV251ProbeTests.swift
// P8b-9 (requirement 4 evidence): hand-built v2.5.1 messages for structures the
// pilots did not cover, one compliant with the chapter print and one variant
// that breaks it. Under messageStructureSeverity = .error the compliant message
// draws no structure issue above info and the variant draws the expected
// finding. Segment content is minimal; only structure issues are read.

import Testing
@testable import HL7v2Kit

@Suite("v2.5.1 structure probes")
struct StructureV251ProbeTests {

    struct Probe: Sendable, CustomTestStringConvertible {
        let structure: String
        let msh9: String
        let compliant: [String]
        let variant: [String]
        /// "missing SEG" or "unexpected SEG": the variant's finding (for a structure
        /// flagged requiresExactMatch, the one finding at the furthest position).
        let finding: String
        var testDescription: String { structure }
    }

    // Each compliant body follows the print cited in the structure's JSON
    // (Resources/structures/v2.5.1/<ID>.json); the variant names what it breaks.
    static let probes: [Probe] = [
        // CH03 3.3.3: PV1 is required; PROCEDURE and INSURANCE groups optional.
        Probe(structure: "ADT_A03", msh9: "ADT^A03^ADT_A03",
              compliant: ["EVN|A03", "PID|1", "PV1|1", "PR1|1", "ROL|1", "IN1|1", "IN2|1"],
              variant: ["EVN|A03", "PID|1", "PR1|1"], finding: "missing PV1"),
        // CH03 3.3.5, printed for A28: OBX before AL1 and DG1.
        Probe(structure: "ADT_A05", msh9: "ADT^A28^ADT_A05",
              compliant: ["EVN|A28", "PID|1", "PV1|1", "OBX|1", "AL1|1", "DG1|1", "GT1|1", "IN1|1"],
              variant: ["EVN|A28", "PID|1", "PV1|1", "AL1|1", "OBX|1"], finding: "unexpected OBX"),
        // CH04 4.4.1: ORDER_DETAIL is a choice of one order detail segment.
        Probe(structure: "ORM_O01", msh9: "ORM^O01^ORM_O01",
              compliant: ["PID|1", "PV1|1", "ORC|NW", "RXO|1", "NTE|1", "ORC|NW", "OBR|1", "OBX|1", "NTE|1"],
              variant: ["PID|1", "ORC|NW", "OBR|1", "RXO|1"], finding: "unexpected RXO"),
        // CH04 4.4.4: OBR is required in each ORDER. OMG_O19 fails the lint, so the exact
        // matcher reports one finding, at the furthest segment any parse reached (NTE).
        Probe(structure: "OMG_O19", msh9: "OMG^O19^OMG_O19",
              compliant: ["PID|1", "PV1|1", "ORC|NW", "TQ1|1", "OBR|1", "NTE|1", "SPM|1"],
              variant: ["PID|1", "ORC|NW", "TQ1|1", "NTE|1"], finding: "unexpected NTE"),
        // CH04 4.13.5: TIMING_ENCODED (TQ1) is required after RXE.
        Probe(structure: "RDE_O11", msh9: "RDE^O11^RDE_O11",
              compliant: ["PID|1", "ORC|NW", "RXE|1", "TQ1|1", "RXR|1"],
              variant: ["PID|1", "ORC|NW", "RXE|1", "RXR|1"], finding: "missing TQ1"),
        // CH04 4.13.11: each ADMINISTRATION has RXA then one RXR.
        Probe(structure: "RAS_O17", msh9: "RAS^O17^RAS_O17",
              compliant: ["PID|1", "ORC|RE", "RXA|0|1", "RXR|1"],
              variant: ["PID|1", "ORC|RE", "RXA|0|1"], finding: "missing RXR"),
        // CH10 10.4: RESOURCES prints SERVICE, GENERAL_RESOURCE, LOCATION_RESOURCE,
        // PERSONNEL_RESOURCE in that order (five CH10 examples print AIP before AIL:
        // one SIU, four SRM/SRR).
        Probe(structure: "SIU_S12", msh9: "SIU^S13^SIU_S12",
              compliant: ["SCH|1", "TQ1|1", "PID|1", "RGS|1", "AIS|1", "AIL|1", "AIP|1"],
              variant: ["SCH|1", "PID|1", "RGS|1", "AIP|1", "AIL|1"], finding: "unexpected AIL"),
        // CH08 8.7.1: each MF_STAFF has MFE then STF.
        Probe(structure: "MFN_M02", msh9: "MFN^M02^MFN_M02",
              compliant: ["MFI|STF", "MFE|MAD", "STF|1", "PRA|1", "MFE|MAD", "STF|2"],
              variant: ["MFI|STF", "MFE|MAD", "PRA|1"], finding: "missing STF"),
        // CH06 6.4.3: at least one FINANCIAL group (FT1); exact matcher, one finding (DG1).
        Probe(structure: "DFT_P03", msh9: "DFT^P03^DFT_P03",
              compliant: ["EVN|P03", "PID|1", "PV1|1", "FT1|1", "PR1|1", "DG1|1"],
              variant: ["EVN|P03", "PID|1", "PV1|1", "DG1|1"], finding: "unexpected DG1"),
        // CH06 6.4.1: EVN is required; exact matcher, one finding (PID, where EVN was due).
        Probe(structure: "BAR_P01", msh9: "BAR^P01^BAR_P01",
              compliant: ["EVN|P01", "PID|1", "PV1|1", "DG1|1", "GT1|1", "IN1|1"],
              variant: ["PID|1", "PV1|1"], finding: "unexpected PID"),
        // CH07 7.3.7: each SPECIMEN starts with SPM.
        Probe(structure: "OUL_R22", msh9: "OUL^R22^OUL_R22",
              compliant: ["PID|1", "SPM|1", "OBR|1", "ORC|SC", "OBX|1", "NTE|1"],
              variant: ["PID|1", "OBR|1", "OBX|1"], finding: "missing SPM"),
        // CH09 9.5.2 (with the group-close erratum): OBX is required after TXA.
        Probe(structure: "MDM_T02", msh9: "MDM^T02^MDM_T02",
              compliant: ["EVN|T02", "PID|1", "PV1|1", "ORC|NW", "OBR|1", "TXA|1", "OBX|1", "NTE|1"],
              variant: ["EVN|T02", "PID|1", "PV1|1", "TXA|1"], finding: "missing OBX"),
        // CH03 3.3.56 (QBP_Q21, printed for Q22): QPD then RCP.
        Probe(structure: "QBP_Q21", msh9: "QBP^Q22^QBP_Q21",
              compliant: ["QPD|Q22", "RCP|I"],
              variant: ["QPD|Q22"], finding: "missing RCP"),
        // CH04 4.17.6: each ORDER has ORC then RXA.
        Probe(structure: "VXU_V04", msh9: "VXU^V04^VXU_V04",
              compliant: ["PID|1", "NK1|1", "ORC|RE", "RXA|0|1", "RXR|1", "OBX|1"],
              variant: ["PID|1", "ORC|RE", "RXR|1"], finding: "missing RXA"),
    ]

    private func structureIssues(_ msh9: String, _ body: [String]) throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let wire = (["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||\(msh9)|MSG00001|P|2.5.1"] + body).joined(separator: "\r")
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

    @Test("A compliant message draws no structure issue above info; the variant draws the finding", arguments: probes)
    func probe(_ p: Probe) throws {
        #expect(MessageStructureTable.structure(p.structure, version: .v2_5_1) != nil, "\(p.structure) is not modelled")
        let ok = try structureIssues(p.msh9, p.compliant)
        #expect(ok.filter { $0.severity != .info }.isEmpty, "\(p.structure): \(ok.map(\.message))")
        #expect(ok.isEmpty, "\(p.structure): \(ok.map(\.message))")
        let bad = try structureIssues(p.msh9, p.variant)
        #expect(bad.contains { Self.describe($0.code) == p.finding && $0.severity == .error },
                "\(p.structure): \(bad.map { Self.describe($0.code) })")
    }

    // P8b-18: registrations classed by the print. CH08 gives the staff MFR body only in prose
    // (8.7.1, pp 8-20 to 8-21) and MFN^M03's other segments by reference to MFN^M08 to M12, each
    // keyed by MFI-1 (blocking); CH06 6.4.4 refers P04 to the Chapter 5 QRY/DSR, but Table 0354
    // gives QRY_P04 an ID of its own (blocking, no alias) and the DSR prints differ (permanent).
    // Table 0354 IDs that a chapter caption contradicts, or that only Appendix A lists, say so.
    @Test("Registered v2.5.1 structures are info with the reason the print supports",
          arguments: [("MFR^M02^MFR_M01", "prose-printed replacement fragments"),
                      ("MFN^M03^MFN_M03", "keyed by MFI-1"),
                      ("QRY^P04^QRY_P04", "no structure alias"), ("DSR^P04^DSR_P04", "which mode P04 uses"),
                      ("ORU^R31^ORU_R31", "ORU^R31^ORU_R30"), ("QRY^T12^QRY_T12", "QRY^T12^QRY"),
                      ("RSP^K22^RSP_K22", "RSP^K22^RSP_K21"), ("RDE^O01^RDE_O01", "Appendix A")])
    func registeredByThePrint(_ c: (String, String)) throws {
        let issues = try structureIssues(c.0, ["MSA|AA|1", "QRD|1"])
        #expect(issues.count == 1 && issues.first?.severity == .info, "\(c.0): \(issues.map(\.message))")
        #expect(issues.first?.message.contains(c.1) == true, "\(c.0): \(issues.map(\.message))")
    }

    @Test("At least twelve probes, none a pilot structure")
    func coverage() {
        #expect(Self.probes.count >= 12)
        #expect(Set(Self.probes.map(\.structure)).isDisjoint(with: ["ACK", "ADT_A01", "ORU_R01"]))
    }
}
