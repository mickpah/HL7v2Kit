// StructureV29ProbeTests.swift
// v2.9-T6 (requirement 4 evidence): hand-built v2.9 messages, one compliant with the chapter print
// and one variant that breaks it, per structure family. Under messageStructureSeverity = .error the
// compliant message draws no structure issue and the variant draws the expected finding. Bodies are
// minimal and synthetic, and only structure issues are read. No probe sends ARV: its place on v2.9 is
// the CTO letter's rather than the print's, and ARVPlacementTests holds that.

import Testing
@testable import HL7v2Kit

@Suite("v2.9 structure probes")
struct StructureV29ProbeTests {

    struct Probe: Sendable, CustomTestStringConvertible {
        let structure: String
        let msh9: String
        let compliant: [String]
        let variant: [String]
        /// "missing SEG" or "unexpected SEG": the variant's finding (for a structure
        /// flagged requiresExactMatch, the one finding at the furthest position).
        let finding: String
        var testDescription: String { "\(structure) \(msh9)" }
    }

    // Each compliant body follows the print cited in the structure's JSON
    // (Resources/structures/v2.9/<ID>.json); the variant names what it breaks.
    static let probes: [Probe] = [
        // CH03 3.3.1: EVN is required.
        Probe(structure: "ADT_A01", msh9: "ADT^A01^ADT_A01",
              compliant: ["EVN|A01", "PID|1", "PV1|1|I"],
              variant: ["PID|1", "PV1|1|I"], finding: "missing EVN"),
        // CH03 3.3.15 p 38 prints '{{ PRT }}' after PV2, read as [{ PRT }] by a cited erratum: PRT is optional.
        Probe(structure: "ADT_A15", msh9: "ADT^A15^ADT_A15",
              compliant: ["EVN|A15", "PID|1", "PV1|1|I"],
              variant: ["EVN|A15", "PID|1", "PV1|1|I", "PV1|2|I"], finding: "unexpected PV1"),
        // CH11 11.6.1 p 26: PARTICIPATION_CLINICAL_HISTORY_OBJECT is a choice of ROL, PRT or PRD; the print
        // leaves the bar off the ROL row. PATIENT_VISITS is required.
        Probe(structure: "CCM_I21", msh9: "CCM^I21^CCM_I21",
              compliant: ["PID|1", "ORC|1", "ROL|1", "PV1|1"],
              variant: ["PID|1", "ORC|1", "ROL|1"], finding: "missing PV1"),
        Probe(structure: "CCM_I21", msh9: "CCM^I21^CCM_I21",
              compliant: ["PID|1", "ORC|1", "PRT|1", "PV1|1"],
              variant: ["PID|1", "ORC|1", "PRT|1"], finding: "missing PV1"),
        Probe(structure: "CCM_I21", msh9: "CCM^I21^CCM_I21",
              compliant: ["PID|1", "ORC|1", "PRD|1", "PV1|1"],
              variant: ["PID|1", "ORC|1", "PRD|1"], finding: "missing PV1"),
        // CH04 4.16.10 p 167: the row closing DONOR_OBSERVATIONS prints 'begin'; the group ends there,
        // so an OBX after the donor's NTE belongs to nothing.
        Probe(structure: "DRG_O43", msh9: "DRG^O43^DRG_O43",
              compliant: ["PID|1", "OBX|1", "PRT|1", "OBX|2", "NTE|1", "AL1|1", "PV1|1", "PRT|2", "NTE|2"],
              variant: ["PID|1", "OBX|1", "NTE|1", "OBX|2"], finding: "unexpected OBX"),
        // CH04 4.16.12 p 169: the DONOR group (mark printed 'Donor') is optional, DONATION_ORDER required.
        Probe(structure: "DEO_O45", msh9: "DEO^O45^DEO_O45",
              compliant: ["PID|1", "OBX|1", "NTE|1", "PV1|1", "OBR|1", "NTE|2", "OBX|2", "NTE|3"],
              variant: ["PID|1", "OBX|1"], finding: "missing OBR"),
        Probe(structure: "DEO_O45", msh9: "DEO^O45^DEO_O45",
              compliant: ["OBR|1"],
              variant: ["OBR|1", "PV1|1"], finding: "unexpected PV1"),
        // CH06 6.4.8 pp 16 to 18: footnote marks beside '[ DRG ] 8' and over the wrapped 'DG1' are not
        // notation. DIAGNOSIS repeats; DRG does not; FINANCIAL is required.
        Probe(structure: "DFT_P11", msh9: "DFT^P11^DFT_P11",
              compliant: ["EVN|P11", "PID|1", "DG1|1", "DG1|2", "DRG|1", "GT1|1", "GT1|2", "IN1|1", "FT1|1", "DG1|3", "DRG|2", "GT1|3", "IN1|2"],
              variant: ["EVN|P11", "PID|1", "DRG|1", "DRG|2", "FT1|1"], finding: "unexpected DRG"),
        // CH06 6.4.3 p 9: '[ { GT1 } ] 4', the mark a space from the bracket.
        Probe(structure: "DFT_P03", msh9: "DFT^P03^DFT_P03",
              compliant: ["EVN|P03", "PID|1", "FT1|1", "DG1|1", "GT1|1", "GT1|2", "IN1|1"],
              variant: ["EVN|P03", "PID|1", "FT1|1", "GT1|1", "DG1|1"], finding: "unexpected DG1"),
        // New in v2.9. CH04 4.4.7.2 p 18: the patient is optional, MSA is not.
        Probe(structure: "ORL_O53", msh9: "ORL^O53^ORL_O53",
              compliant: ["MSA|AA|1", "ORC|OK", "OBR|1", "SPM|1", "SAC|1"],
              variant: ["PID|1", "ORC|OK"], finding: "missing MSA"),
        // CH04 4.4.20 p 49: an order carries its document: OBX then TXA.
        Probe(structure: "OMQ_O57", msh9: "OMQ^O57^OMQ_O57",
              compliant: ["ORC|NW", "OBX|1", "TXA|1"],
              variant: ["ORC|NW", "OBX|1"], finding: "missing TXA"),
        // CH04 4.4.21 p 52: TXA is required in ORDER.
        Probe(structure: "ORX_O58", msh9: "ORX^O58^ORX_O58",
              compliant: ["MSA|AA|1", "PID|1", "ORC|OK", "TXA|1"],
              variant: ["MSA|AA|1", "PID|1", "ORC|OK"], finding: "missing TXA"),
        // CH04 4.4.18 p 47: ORDER_STATUS is required; the patient is not.
        Probe(structure: "OSU_O51", msh9: "OSU^O51^OSU_O51",
              compliant: ["ORC|SC", "PRT|1"],
              variant: ["PID|1"], finding: "missing ORC"),
    ]

    private static func structureIssues(_ msh9: String, _ body: [String] = []) throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let wire = (["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||\(msh9)|MSG00001|P|2.9"] + body).joined(separator: "\r")
        return Validator(options: options).validate(try Parser().parse(wire)).issues.filter(\.code.isMessageStructure)
    }

    private static func describe(_ code: IssueCode) -> String {
        switch code {
        case .messageStructureSegmentMissing(_, let segment, _): "missing \(segment)"
        case .messageStructureSegmentUnexpected(_, let segment): "unexpected \(segment)"
        default: "\(code)"
        }
    }

    @Test("A compliant message draws no structure issue; the variant draws the finding", arguments: probes)
    func probe(_ p: Probe) throws {
        #expect(MessageStructureTable.structure(p.structure, version: .v2_9) != nil, "\(p.structure) is not modelled")
        let ok = try Self.structureIssues(p.msh9, p.compliant)
        #expect(ok.isEmpty, "\(p.testDescription): \(ok.map(\.message))")
        let bad = try Self.structureIssues(p.msh9, p.variant)
        #expect(bad.contains { Self.describe($0.code) == p.finding && $0.severity == .error },
                "\(p.testDescription): \(bad.map { Self.describe($0.code) })")
    }

    // Per-trigger prints (ADR-019 S6): each body is legal under one trigger and not under the other.
    @Test("A variant print governs its own trigger, and the default print the others",
          arguments: [
            // CH03 3.3.13 p 32 prints [{ OH3 }]; 3.3.1 p 5 prints [ OH3 ].
            ("ADT^A13^ADT_A01", "ADT^A01^ADT_A01", ["EVN|A13", "PID|1", "OH3|1", "OH3|2", "PV1|1|I"], "unexpected OH3"),
            // CH03 3.3.28 p 55 prints [{ NK1 }] in NEXT_OF_KIN; 3.3.5 p 15 prints NK1 required.
            ("ADT^A28^ADT_A05", "ADT^A05^ADT_A05", ["EVN|A28", "PID|1", "PRT|1", "OH2|1", "PV1|1|I"], "unexpected OH2"),
            // CH07 7.3.12 p 34 prints [{PRT}] in OBSERVATION_PARTICIPATION; 7.3.1 p 10 prints PRT required, so
            // there DEV can only open the DEVICE group that follows the order, and TQ1 cannot follow it.
            ("ORU^R40^ORU_R01", "ORU^R01^ORU_R01", ["OBR|1", "DEV|1", "TQ1|1"], "unexpected TQ1"),
          ] as [(String, String, [String], String)])
    func variantEachWay(_ c: (variant: String, other: String, body: [String], finding: String)) throws {
        let under = try Self.structureIssues(c.variant, c.body)
        #expect(under.isEmpty, "\(c.variant): \(under.map(\.message))")
        let other = try Self.structureIssues(c.other, c.body)
        #expect(other.map { Self.describe($0.code) } == [c.finding], "\(c.other): \(other.map(\.message))")
    }

    @Test("A body legal under both prints is clean under both",
          arguments: [("ADT^A13^ADT_A01", ["EVN|A13", "PID|1", "OH3|1", "PV1|1|I"]),
                      ("ADT^A01^ADT_A01", ["EVN|A01", "PID|1", "OH3|1", "PV1|1|I"]),
                      ("ADT^A28^ADT_A05", ["EVN|A28", "PID|1", "NK1|1", "PV1|1|I"]),
                      ("ADT^A05^ADT_A05", ["EVN|A05", "PID|1", "NK1|1", "PV1|1|I"]),
                      ("ORU^R40^ORU_R01", ["OBR|1", "PRT|1", "DEV|1", "TQ1|1"]),
                      ("ORU^R01^ORU_R01", ["OBR|1", "PRT|1", "DEV|1", "TQ1|1"])] as [(String, [String])])
    func variantShared(_ c: (msh9: String, body: [String])) throws {
        let issues = try Self.structureIssues(c.msh9, c.body)
        #expect(issues.isEmpty, "\(c.msh9): \(issues.map(\.message))")
    }

    // What the print gives but no syntax: each is information naming the structure, never a mismatch.
    @Test("A printed ID with no syntax is information, whatever the trigger",
          arguments: [
            // CH02C p 272: new SET rows, Status N, naming no event, so any event is reported the same way.
            ("SET^S38^SET_S38", "SET_S38"), ("SET^S39^SET_S38", "SET_S38"), ("SET^S52^SET_S52", "SET_S52"),
            // CH02C p 268: the row misprints INR_U14 as INV_U14.
            ("INV^U14^INV_U14", "INV_U14"), ("INR^U14^INV_U14", "INV_U14"),
            // CH02C p 271, CH05 5.2.6 p 12: withdrawn, and no chapter prints it.
            ("RDR^RDR^RDR_RDR", "RDR_RDR"), ("RDR^RDR", "RDR^RDR"), ("UDM^Q05^UDM_Q05", "UDM_Q05"),
            // Acknowledgment Choreography cells: CH03 p 97, CH04A p 25, CH16 p 27, CH03 p 65, CH10 p 15.
            ("RSP^K24^RSP_K24", "RSP_K24"), ("RRE^O26^RRE_O26", "RRE_O26"), ("RSP^E22^RSP_E03", "RSP_E03"),
            ("ADT^A37^ACK", "ACK"), ("ACK^S01^SRR_S01", "SRR_S01"), ("ACK^S11^SRR_S01", "SRR_S01"),
            // CH05 5.4 (pp 38, 39, 41): 'may specify a unique trigger event value in its Query Profile'.
            ("QBP^Q11^QBP_Q11", "QBP_Q11"), ("QBP^Q31^QBP_Q11", "QBP_Q11"), ("QBP^Q61^QBP_Q11", "QBP_Q11"), ("QBP^Q11", "QBP^Q11"),
            ("QBP^Q15^QBP_Q15", "QBP_Q15"), ("QBP^Q41^QBP_Q15", "QBP_Q15"),
            ("RSP^K11^RSP_K11", "RSP_K11"), ("RSP^K61^RSP_K11", "RSP_K11"),
            ("QBP^Q13^QBP_Q13", "QBP_Q13"), ("QBP^Q40^QBP_Q13", "QBP_Q13"),
          ] as [(String, String)])
    func registered(_ c: (msh9: String, structure: String)) throws {
        let issues = try Self.structureIssues(c.msh9)
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: c.structure)], "\(c.msh9): \(issues.map(\.message))")
        #expect(issues.first?.severity == .info, "\(c.msh9)")
    }

    // CH05 5.4.5 gives QVR no varying event ('Event Q17'), so its list stays closed.
    @Test("QVR_Q17 keeps its one printed trigger")
    func qvrClosed() throws {
        #expect(try Self.structureIssues("QVR^Q17^QVR_Q17").map(\.code) == [.messageStructureNotModelled(structure: "QVR_Q17")])
        let other = try Self.structureIssues("QVR^Q61^QVR_Q17")
        #expect(other.map(\.code) == [.messageStructureMismatch(declared: "QVR_Q17", trigger: "QVR^Q61")], "\(other.map(\.message))")
    }
}
