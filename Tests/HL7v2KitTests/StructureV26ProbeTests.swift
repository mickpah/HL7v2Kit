// StructureV26ProbeTests.swift
// P8b-10 (requirement 4 evidence): hand-built v2.6 messages for structures not
// probed for v2.5.1, one compliant with the chapter print and one variant that
// breaks it. Under messageStructureSeverity = .error the compliant message
// draws no structure issue and the variant draws the expected finding. Segment
// content is minimal; only structure issues are read.

import Testing
@testable import HL7v2Kit

@Suite("v2.6 structure probes")
struct StructureV26ProbeTests {

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
    // (Resources/structures/v2.6/<ID>.json); the variant names what it breaks.
    static let probes: [Probe] = [
        // CH16 16.3 (EHC^E02): INVOICE_INFORMATION is a bracketless named group, so
        // required; IVC opens it.
        Probe(structure: "EHC_E02", msh9: "EHC^E02^EHC_E02",
              compliant: ["UAC|1", "UAC|2", "IVC|1", "PYE|1", "NTE|1", "PSS|1", "PSG|1", "PSL|1"],
              variant: ["PYE|1", "PSS|1"], finding: "missing IVC"),
        // CH16 16.3 (EHC^E12, with the syntax-cell erratum '[ { CTD } ]'): at least one
        // REQUEST group, OBR required in it.
        Probe(structure: "EHC_E12", msh9: "EHC^E12^EHC_E12",
              compliant: ["RFI|1", "CTD|1", "CTD|2", "IVC|1", "PSS|1", "PSG|1", "CTD|3", "OBR|1", "OBX|1"],
              variant: ["RFI|1", "IVC|1", "PSS|1", "PSG|1", "CTD|1"], finding: "missing OBR"),
        // CH17 17.5.4: '< SDD [{SCD}] >' with a name and no '|' is a named required group.
        Probe(structure: "SDR_S31", msh9: "SDR^S31^SDR_S31",
              compliant: ["SDD|1", "SCD|1", "SCD|2"],
              variant: ["SCD|1"], finding: "missing SDD"),
        // CH04 4.4.3: the order detail is a choice of one segment (OBR, RQD, RQ1, RXO, ODS, ODT).
        Probe(structure: "OSR_Q06", msh9: "OSR^Q06^OSR_Q06",
              compliant: ["MSA|AA|1", "QRD|1", "PID|1", "ORC|NW", "RQD|1", "NTE|1"],
              variant: ["MSA|AA|1", "QRD|1", "PID|1", "ORC|NW", "OBR|1", "RXO|1"], finding: "unexpected RXO"),
        // CH03 3.3.60: ARV after PID and again after the optional PV1/PV2; EVN required.
        // The two ARVs fail the lint, so the exact matcher reports one finding (PID, where
        // EVN was due).
        Probe(structure: "ADT_A60", msh9: "ADT^A60^ADT_A60",
              compliant: ["EVN|A60", "PID|1", "ARV|1", "PV1|1", "PV2|1", "ARV|2", "IAM|1"],
              variant: ["PID|1", "ARV|1", "IAM|1"], finding: "unexpected PID"),
        // CH12 12.2.7 (the looser PC9 print, primaryPrints): SFT and UAC accepted on a
        // PC4 query; QRD required.
        Probe(structure: "QRY_PC4", msh9: "QRY^PC4^QRY_PC4",
              compliant: ["SFT|1", "UAC|1", "QRD|1", "QRF|1"],
              variant: ["SFT|1", "QRF|1"], finding: "missing QRD"),
        // CH08 8.4.2 (the looser M13 print, primaryPrints): UAC accepted on MFK^M01; MFI required.
        Probe(structure: "MFK_M01", msh9: "MFK^M01^MFK_M01",
              compliant: ["UAC|1", "MSA|AA|1", "MFI|1", "MFA|1"],
              variant: ["MSA|AA|1", "MFA|1"], finding: "missing MFI"),
        // CH04 4.20.5 (with the syntax-cell erratum closing PATIENT and RESPONSE): PID opens PATIENT.
        Probe(structure: "BRP_O30", msh9: "BRP^O30^BRP_O30",
              compliant: ["MSA|AA|1", "UAC|1", "PID|1", "ORC|OK", "TQ1|1", "BPO|1", "BPX|1"],
              variant: ["MSA|AA|1", "ORC|OK", "BPX|1"], finding: "unexpected ORC"),
        // CH03 3.3.44 (the looser A44 print, primaryPrints): ARV accepted on A43; MRG required.
        Probe(structure: "ADT_A43", msh9: "ADT^A43^ADT_A43",
              compliant: ["EVN|A43", "PID|1", "PD1|1", "ARV|1", "MRG|1", "PID|2", "MRG|2"],
              variant: ["EVN|A43", "PID|1", "ARV|1"], finding: "missing MRG"),
        // CH16 16.3 (QBP^E03): QUERY_INFORMATION (QPD RCP) is a required named group.
        Probe(structure: "QBP_E03", msh9: "QBP^E03^QBP_E03",
              compliant: ["QPD|E03", "RCP|I"],
              variant: ["QPD|E03"], finding: "missing RCP"),
        // CH15 15.3.1: STF is required after EVN.
        Probe(structure: "PMU_B01", msh9: "PMU^B01^PMU_B01",
              compliant: ["EVN|B01", "STF|1", "PRA|1", "ORG|1", "EDU|1"],
              variant: ["EVN|B01", "PRA|1"], finding: "missing STF"),
        // CH11 11.3.3 (RQI^I03, with the group-mark erratum): GUARANTOR_INSURANCE needs an IN1.
        Probe(structure: "RQI_I01", msh9: "RQI^I03^RQI_I01",
              compliant: ["PRD|1", "CTD|1", "PID|1", "NK1|1", "GT1|1", "IN1|1", "IN2|1", "NTE|1"],
              variant: ["PRD|1", "PID|1", "GT1|1", "NTE|1"], finding: "missing IN1"),
        // CH08 8.10.1: each MF_QUERY has MFE then CDM.
        Probe(structure: "MFR_M04", msh9: "MFR^M04^MFR_M04",
              compliant: ["MSA|AA|1", "QRD|1", "MFI|1", "MFE|MAD", "CDM|1", "PRC|1"],
              variant: ["MSA|AA|1", "QRD|1", "MFI|1", "MFE|MAD", "PRC|1"], finding: "missing CDM"),
        // CH03 3.3.34 (the looser A34 print, primaryPrints): ARV accepted; MRG required.
        Probe(structure: "ADT_A30", msh9: "ADT^A34^ADT_A30",
              compliant: ["EVN|A34", "PID|1", "PD1|1", "ARV|1", "MRG|1"],
              variant: ["EVN|A34", "PID|1", "PD1|1"], finding: "missing MRG"),
    ]

    private func structureIssues(_ msh9: String, _ body: [String]) throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let wire = (["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||\(msh9)|MSG00001|P|2.6"] + body).joined(separator: "\r")
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

    @Test("A compliant message draws no structure issue; the variant draws the finding", arguments: probes)
    func probe(_ p: Probe) throws {
        #expect(MessageStructureTable.structure(p.structure, version: .v2_6) != nil, "\(p.structure) is not modelled")
        let ok = try structureIssues(p.msh9, p.compliant)
        #expect(ok.isEmpty, "\(p.structure): \(ok.map(\.message))")
        let bad = try structureIssues(p.msh9, p.variant)
        #expect(bad.contains { Self.describe($0.code) == p.finding && $0.severity == .error },
                "\(p.structure): \(bad.map { Self.describe($0.code) })")
    }

    // P8b-18: registrations classed by the print. CH08 gives the staff MFR body only in prose
    // (8.7.1, pp 8-18 to 8-19) and MFN^M03's other segments by reference to MFN^M08 to M12, each
    // keyed by MFI-1 (blocking). Table 0354 gives W01 its own ID while the CH07 examples send
    // ORU^W01^ORU_R01 (permanent; the reason says both).
    @Test("Registered v2.6 structures are info with the reason the print supports",
          arguments: [("MFR^M02^MFR_M01", "prose-printed replacement fragments"),
                      ("MFN^M03^MFN_M03", "keyed by MFI-1"),
                      ("ORU^W01^ORU_W01", "ORU^W01^ORU_R01"), ("QRF^W02^QRF_W02", "7.15.2")])
    func registeredByThePrint(_ c: (String, String)) throws {
        let issues = try structureIssues(c.0, ["MSA|AA|1", "QRD|1"])
        #expect(issues.count == 1 && issues.first?.severity == .info, "\(c.0): \(issues.map(\.message))")
        #expect(issues.first?.message.contains(c.1) == true, "\(c.0): \(issues.map(\.message))")
    }

    @Test("At least twelve probes, none a pilot structure nor one probed for v2.5.1")
    func coverage() {
        #expect(Self.probes.count >= 12)
        let v251: Set<String> = ["ADT_A03", "ADT_A05", "ORM_O01", "OMG_O19", "RDE_O11", "RAS_O17", "SIU_S12", "MFN_M02",
                                 "DFT_P03", "BAR_P01", "OUL_R22", "MDM_T02", "QBP_Q21", "VXU_V04"]
        #expect(Set(Self.probes.map(\.structure)).isDisjoint(with: v251.union(["ACK", "ADT_A01", "ORU_R01"])))
    }
}
