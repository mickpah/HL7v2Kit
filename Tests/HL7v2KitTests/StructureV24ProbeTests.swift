// StructureV24ProbeTests.swift
// P8b-13 (requirement 4 evidence): hand-built v2.4 messages, one compliant with the
// chapter print and one variant that breaks it. Under messageStructureSeverity = .error
// the compliant message draws no structure issue and the variant draws the expected
// finding. v2.4 prints no group names: every group is named from the HL7 v2.xml v2.4
// bundle, a cited overrides.json entry, or synthesised. Segment content is minimal;
// only structure issues are read.

import Testing
@testable import HL7v2Kit

@Suite("v2.4 structure probes")
struct StructureV24ProbeTests {

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
    // (Resources/structures/v2.4/<ID>.json); the variant names what it breaks.
    static let probes: [Probe] = [
        // CH07 7.3.1: an OBX belongs to an ORDER_OBSERVATION, which OBR opens.
        Probe(structure: "ORU_R01", msh9: "ORU^R01^ORU_R01",
              compliant: ["PID|1", "OBR|1", "OBX|1", "OBX|2"],
              variant: ["PID|1", "OBX|1"], finding: "unexpected OBX"),
        // CH04 4.4.1: ORDER_DETAIL is a choice of one order detail segment (OBR, RQD, RQ1,
        // RXO, ODS or ODT); a second detail segment after the first is not allowed.
        Probe(structure: "ORM_O01", msh9: "ORM^O01^ORM_O01",
              compliant: ["PID|1", "ORC|NW", "RXO|1", "NTE|1"],
              variant: ["PID|1", "ORC|NW", "RXO|1", "OBR|1"], finding: "unexpected OBR"),
        // CH03 3.3.1 (V24-A01): PV1 is required.
        Probe(structure: "ADT_A01", msh9: "ADT^A01^ADT_A01",
              compliant: ["EVN|A01", "PID|1", "PV1|1"],
              variant: ["EVN|A01", "PID|1"], finding: "missing PV1"),
        // CH05 5.10.5 original-mode query: QRD is required (v2.4 defines QRD and QRF).
        Probe(structure: "QRY_A19", msh9: "QRY^A19^QRY_A19",
              compliant: ["QRD|1", "QRF|1"],
              variant: ["QRF|1"], finding: "missing QRD"),
        // CH04 4.4.7: RESPONSE opens with PID; the group names come from HL7-xml
        // v2.4/ORL_O22.xsd by member set (cited overrides; the bundle nests them under PATIENT).
        Probe(structure: "ORL_O22", msh9: "ORL^O22^ORL_O22",
              compliant: ["MSA|AA|1", "PID|1", "SAC|1", "ORC|OK", "OBR|1"],
              variant: ["MSA|AA|1", "SAC|1"], finding: "unexpected SAC"),
        // CH04 4.10.11: ADMINISTRATION (the v2.5.1 bundle's name, a cited override) is
        // {RXA} RXR; RXR is required.
        Probe(structure: "RAS_O17", msh9: "RAS^O17^RAS_O17",
              compliant: ["ORC|RE", "RXA|1", "RXR|1"],
              variant: ["ORC|RE", "RXA|1"], finding: "missing RXR"),
        // CH10 10.4: RESOURCES orders LOCATION_RESOURCE (AIL) before PERSONNEL_RESOURCE (AIP).
        Probe(structure: "SIU_S12", msh9: "SIU^S12^SIU_S12",
              compliant: ["SCH|1", "RGS|1", "AIL|1", "AIP|1"],
              variant: ["SCH|1", "RGS|1", "AIP|1", "AIL|1"], finding: "unexpected AIL"),
        // CH10 10.5 SQR^S25 prints PERSONNEL_RESOURCE (AIP) before LOCATION_RESOURCE (AIL),
        // the reverse of SIU_S12; names borrowed from the v2.5.1 bundle (no v2.4 xsd).
        Probe(structure: "SQR_S25", msh9: "SQR^S25^SQR_S25",
              compliant: ["MSA|AA|1", "QAK|1|OK", "SCH|1", "RGS|1", "AIP|1", "AIL|1"],
              variant: ["MSA|AA|1", "QAK|1|OK", "SCH|1", "RGS|1", "AIL|1", "AIP|1"], finding: "unexpected AIP"),
        // CH08 8.7.1: each MF_STAFF is MFE then STF.
        Probe(structure: "MFN_M02", msh9: "MFN^M02^MFN_M02",
              compliant: ["MFI|1", "MFE|MAD", "STF|1"],
              variant: ["MFI|1", "MFE|MAD"], finding: "missing STF"),
        // CH06 6.4.3 (footnote marks read off the brackets): FINANCIAL (FT1) is required.
        Probe(structure: "DFT_P03", msh9: "DFT^P03^DFT_P03",
              compliant: ["EVN|P03", "PID|1", "FT1|1", "DG1|1", "IN1|1"],
              variant: ["EVN|P03", "PID|1"], finding: "missing FT1"),
        // CH06 6.4.1: PID is required before VISIT.
        Probe(structure: "BAR_P01", msh9: "BAR^P01^BAR_P01",
              compliant: ["EVN|P01", "PID|1", "PV1|1"],
              variant: ["EVN|P01", "PV1|1"], finding: "unexpected PV1"),
        // CH07 7.3.2 (read through the '[PV2]]' erratum): ORDER_OBSERVATION needs OBR.
        Probe(structure: "OUL_R21", msh9: "OUL^R21^OUL_R21",
              compliant: ["PID|1", "PV1|1", "PV2|1", "OBR|1", "OBX|1"],
              variant: ["PID|1", "PV1|1", "OBX|1"], finding: "unexpected OBX"),
        // CH03 3.3.56: QAK is required before QPD.
        Probe(structure: "RSP_K21", msh9: "RSP^K21^RSP_K21",
              compliant: ["MSA|AA|1", "QAK|1|OK", "QPD|Q21", "PID|1"],
              variant: ["MSA|AA|1", "QPD|Q21", "PID|1"], finding: "missing QAK"),
        // CH11 11.3.5: PROVIDER is required (exact-matched: the finding is the PID where PRD
        // should be); the bundle's group 'c' is named OBSERVATION (a cited override from the v2.5.1 bundle).
        Probe(structure: "RCI_I05", msh9: "RCI^I05^RCI_I05",
              compliant: ["MSA|AA|1", "QRD|1", "PRD|RP", "PID|1", "OBR|1", "OBX|1"],
              variant: ["MSA|AA|1", "QRD|1", "PID|1"], finding: "unexpected PID"),
        // CH04 4.17.6: ORDER is [ORC] RXA [RXR]; RXA is required (names from the v2.5.1 bundle).
        Probe(structure: "VXU_V04", msh9: "VXU^V04^VXU_V04",
              compliant: ["PID|1", "ORC|RE", "RXA|1", "OBX|1"],
              variant: ["PID|1", "ORC|RE", "OBX|1"], finding: "missing RXA"),
        // CH04 4.4.6 (the last ']' read as '}', a cited erratum): ORDER_GENERAL repeats, each
        // with a required ORDER opened by ORC.
        Probe(structure: "OML_O21", msh9: "OML^O21^OML_O21",
              compliant: ["PID|1", "ORC|NW", "OBR|1", "ORC|NW", "OBR|2"],
              variant: ["PID|1", "OBR|1"], finding: "unexpected OBR"),
    ]

    private func structureIssues(_ msh9: String, _ body: [String], version: String = "2.4") throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let wire = (["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||\(msh9)|MSG00001|P|\(version)"] + body).joined(separator: "\r")
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

    private static func groups(_ elements: [StructureElement]) -> [String] {
        elements.flatMap { $0.children.isEmpty ? [] : [$0.label] + groups($0.children) }
    }

    @Test("A compliant message draws no structure issue; the variant draws the finding", arguments: probes)
    func probe(_ p: Probe) throws {
        #expect(MessageStructureTable.structure(p.structure, version: .v2_4) != nil, "\(p.structure) is not modelled")
        let ok = try structureIssues(p.msh9, p.compliant)
        #expect(ok.isEmpty, "\(p.structure): \(ok.map(\.message))")
        let bad = try structureIssues(p.msh9, p.variant)
        #expect(bad.contains { Self.describe($0.code) == p.finding && $0.severity == .error },
                "\(p.structure): \(bad.map { Self.describe($0.code) })")
    }

    // The group names v2.4 does not print: ORL_O22's from the v2.4 bundle by member set
    // (cited overrides), DFT_P03's per-FT1 insurance group synthesised (no bundle names it).
    @Test("v2.4 group names: ORL_O22 from its bundle by member set; DFT_P03's per-FT1 insurance synthesised")
    func groupNames() throws {
        let orl = try #require(MessageStructureTable.structure("ORL_O22", version: .v2_4))
        #expect(Self.groups(orl.elements) == ["RESPONSE", "GENERAL_ORDER", "CONTAINER", "ORDER", "OBSERVATION_REQUEST"])
        let dft = try #require(MessageStructureTable.structure("DFT_P03", version: .v2_4))
        #expect(Self.groups(dft.elements).contains("IN1_GROUP"))
        #expect(Self.groups(dft.elements).contains("FINANCIAL_PROCEDURE"))
    }

    // CH05 5.10.4.2 prints ERP^R09 with ellipsis rows standing for another message's
    // segments (ruling G6): registered as not modelled on v2.4 and v2.5.1 (a corpus misfire
    // fixed in P8b-13), so an event replay response is info, never a false finding.
    @Test("ERP^R09 is registered (info) on v2.4 and v2.5.1", arguments: ["2.4", "2.5.1"])
    func eventReplayResponse(_ version: String) throws {
        let issues = try structureIssues("ERP^R09^ERP_R09", ["MSA|AA|1", "QAK|1|OK", "ERQ|1", "EVN|A01", "PID|1"], version: version)
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "ERP_R09")], "\(issues.map(\.message))")
        #expect(issues.first?.severity == .info && issues.first?.message.contains("ellipsis") == true, "\(issues.map(\.message))")
    }

    @Test("At least twelve probes on v2.4 structures")
    func coverage() {
        #expect(Self.probes.count >= 12)
        #expect(Set(Self.probes.map(\.structure)).count == Self.probes.count)
    }
}
