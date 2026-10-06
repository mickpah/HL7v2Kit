// StructureV271ProbeTests.swift
// P8b-16 (requirement 4 evidence): hand-built v2.7.1 messages for structures not
// probed for v2.5.1, v2.6 or v2.8.2, one compliant with the chapter print and one
// variant that breaks it. Under messageStructureSeverity = .error the compliant
// message draws no structure issue and the variant draws the expected finding.
// Segment content is minimal; only structure issues are read.

import Testing
@testable import HL7v2Kit

@Suite("v2.7.1 structure probes")
struct StructureV271ProbeTests {

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
    // (Resources/structures/v2.7.1/<ID>.json); the variant names what it breaks.
    static let probes: [Probe] = [
        // CH11 11.7.2: RESOURCE_OBJECT is a named choice of AIS, AIG, AIL or AIP that opens
        // RESOURCE_DETAIL; an OBX straight after RGS has no resource to belong to.
        // PATIENT_VISITS (PV1) is required at the end, as in every CC* probe here.
        Probe(structure: "CCI_I22", msh9: "CCI^I22^CCI_I22",
              compliant: ["MSA|AA|1", "PID|1", "SCH|1", "RGS|1", "AIG|1", "OBX|1", "PV1|1"],
              variant: ["MSA|AA|1", "PID|1", "SCH|1", "RGS|1", "OBX|1", "PV1|1"], finding: "unexpected OBX"),
        // CH11 11.6.2 (RESOURCE_DETAIL read through the 'RESOURCED_DETAIL end' erratum):
        // {RF1} is required before PROVIDER_CONTACT.
        Probe(structure: "CCR_I16", msh9: "CCR^I16^CCR_I16",
              compliant: ["RF1|1", "PRD|RP", "PID|1", "PV1|1"],
              variant: ["PRD|RP", "PID|1", "PV1|1"], finding: "missing RF1"),
        // CH11 11.6.6: RF1 is required and opens the message body.
        Probe(structure: "CCU_I20", msh9: "CCU^I20^CCU_I20",
              compliant: ["RF1|1", "PID|1", "SCH|1", "RGS|1", "AIL|1", "OBX|1", "PV1|1"],
              variant: ["PID|1", "SCH|1", "PV1|1"], finding: "missing RF1"),
        // CH07 7.17.1 (the caption-cell header row and the wrapped group marks, P8b-16):
        // SHIPMENT requires {PRT} after SHP.
        Probe(structure: "OSM_R26", msh9: "OSM^R26^OSM_R26",
              compliant: ["SHP|1", "PRT|1", "PAC|1", "SPM|1", "PV1|1", "PID|1"],
              variant: ["SHP|1", "PAC|1", "SPM|1"], finding: "unexpected PAC"),
        // CH04 4.4.16: {PRT} is required before the ORDER group.
        Probe(structure: "OPL_O37", msh9: "OPL^O37^OPL_O37",
              compliant: ["PRT|1", "NK1|1", "SPM|1", "ORC|NW", "OBR|1"],
              variant: ["NK1|1", "SPM|1", "ORC|NW", "OBR|1"], finding: "unexpected NK1"),
        // CH16 16.3.10: '< ... >' with no '|' named AUTHORIZATION_REQUEST is a named
        // required group (P8b-6 ruling; the CH16 text never says "one of"); IVC opens it.
        Probe(structure: "EHC_E20", msh9: "EHC^E20^EHC_E20",
              compliant: ["IVC|1", "CTD|1", "PID|1", "IN1|1", "PSL|1"],
              variant: ["CTD|1", "PID|1", "IN1|1", "PSL|1"], finding: "missing IVC"),
        // CH16 16.3.13: QUERY_ACK is a no-bar named required group; QAK opens it.
        Probe(structure: "RSP_E22", msh9: "RSP^E22^RSP_E22",
              compliant: ["MSA|AA|1", "QAK|1|OK", "QPD|E22"],
              variant: ["MSA|AA|1", "QPD|E22"], finding: "missing QAK"),
        // CH10 10.3: RESOURCES orders LOCATION_RESOURCE (AIL) before PERSONNEL_RESOURCE
        // (AIP), so an AIL after an AIP is out of order (the CH10 examples print AIP first).
        Probe(structure: "SRM_S01", msh9: "SRM^S01^SRM_S01",
              compliant: ["ARQ|1", "PID|1", "RGS|1", "AIL|1", "AIP|1"],
              variant: ["ARQ|1", "PID|1", "RGS|1", "AIP|1", "AIL|1"], finding: "unexpected AIL"),
        // CH08 8.12.2: each MATERIAL_ITEM_RECORD is MFE then ITM.
        Probe(structure: "MFN_M16", msh9: "MFN^M16^MFN_M16",
              compliant: ["MFI|1", "MFE|MAD", "ITM|1"],
              variant: ["MFI|1", "MFE|MAD"], finding: "missing ITM"),
        // CH17 17.5.1: {SLT} is the body; an MSA (the CH17 example's acknowledgment) is not.
        Probe(structure: "SLR_S28", msh9: "SLR^S28^SLR_S28",
              compliant: ["SLT|1"],
              variant: ["MSA|AA|1"], finding: "unexpected MSA"),
        // CH07 7.6.1 (CRM^C01, p 91): each PATIENT carries a required CSR after the visit.
        Probe(structure: "CRM_C01", msh9: "CRM^C01^CRM_C01",
              compliant: ["PID|1", "PV1|1", "CSR|1"],
              variant: ["PID|1", "PV1|1"], finding: "missing CSR"),
        // CH07 7.10.1 (PEX^P07, pp 108 to 110): each PEX_OBSERVATION needs a PEX_CAUSE opened by PCR.
        Probe(structure: "PEX_P07", msh9: "PEX^P07^PEX_P07",
              compliant: ["EVN|P07", "PID|1", "PES|1", "PEO|1", "PCR|1"],
              variant: ["EVN|P07", "PID|1", "PES|1", "PEO|1"], finding: "missing PCR"),
        // CH11 11.3.4 (RPI^I04, a declared shared trigger with RPI_I01 through Table 0354):
        // PROVIDER is required after MSA.
        Probe(structure: "RPI_I04", msh9: "RPI^I04^RPI_I04",
              compliant: ["MSA|AA|1", "PRD|RP", "PID|1"],
              variant: ["MSA|AA|1", "PID|1"], finding: "missing PRD"),
    ]

    private func structureIssues(_ msh9: String, _ body: [String], version: String = "2.7.1") throws -> [ValidationIssue] {
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

    @Test("A compliant message draws no structure issue; the variant draws the finding", arguments: probes)
    func probe(_ p: Probe) throws {
        #expect(MessageStructureTable.structure(p.structure, version: .v2_7_1) != nil, "\(p.structure) is not modelled")
        let ok = try structureIssues(p.msh9, p.compliant)
        #expect(ok.isEmpty, "\(p.structure): \(ok.map(\.message))")
        let bad = try structureIssues(p.msh9, p.variant)
        #expect(bad.contains { Self.describe($0.code) == p.finding && $0.severity == .error },
                "\(p.structure): \(bad.map { Self.describe($0.code) })")
    }

    // CH07 7.3.1: the SPECIMEN group's observations are SPECIMEN_OBSERVATION (the cited
    // group-mark erratum for 'SPECIMEN OBSERVATION'), where the HL7 v2.xml bundle says
    // PATIENT_OBSERVATION; an OBX after SPM belongs to it.
    @Test("v2.7.1 ORU_R01 reads SPECIMEN_OBSERVATION inside SPECIMEN")
    func oruR01SpecimenObservation() throws {
        let structure = try #require(MessageStructureTable.structure("ORU_R01", version: .v2_7_1))
        func groups(_ elements: [StructureElement]) -> [String] {
            elements.flatMap { $0.children.isEmpty ? [] : [$0.label] + groups($0.children) }
        }
        #expect(groups(structure.elements).contains("SPECIMEN_OBSERVATION"))
        let compliant = ["PID|1", "OBR|1", "OBX|1", "SPM|1", "OBX|2", "OBX|3"]
        #expect(try structureIssues("ORU^R01^ORU_R01", compliant).isEmpty)
        let issues = try structureIssues("ORU^R01^ORU_R01", ["PID|1", "SPM|1", "OBR|1"])
        #expect(!issues.isEmpty, "an SPM before any OBR has no ORDER_OBSERVATION to belong to")
    }

    // ADR-018: a 2.7 wire message is checked against the v2.7.1 structures.
    @Test("A 2.7 wire SRM^S01 is checked against the v2.7.1 print")
    func wire27() throws {
        #expect(try structureIssues("SRM^S01^SRM_S01", ["ARQ|1", "PID|1", "RGS|1", "AIL|1", "AIP|1"], version: "2.7").isEmpty)
        let issues = try structureIssues("SRM^S01^SRM_S01", ["PID|1", "RGS|1"], version: "2.7")
        #expect(issues.map { Self.describe($0.code) } == ["missing ARQ"], "\(issues.map(\.message))")
    }

    // The structures printing QRD and QRF (QRY_PC4, RCI_I05, RQC_I05, RCL_I06) and URD and
    // URS (UDM_Q05) are modelled since S2-2: WithdrawnSegmentTests probes them.

    @Test("At least twelve probes, none a pilot structure nor one probed for v2.5.1, v2.6 or v2.8.2")
    func coverage() {
        #expect(Self.probes.count >= 12)
        let earlier: Set<String> = ["ADT_A03", "ADT_A05", "ORM_O01", "OMG_O19", "RDE_O11", "RAS_O17", "SIU_S12", "MFN_M02",
                                    "DFT_P03", "BAR_P01", "OUL_R22", "MDM_T02", "QBP_Q21", "VXU_V04",
                                    "EHC_E02", "EHC_E12", "SDR_S31", "OSR_Q06", "ADT_A60", "QRY_PC4", "MFK_M01", "BRP_O30",
                                    "ADT_A43", "QBP_E03", "PMU_B01", "RQI_I01", "MFR_M04", "ADT_A30",
                                    "CCM_I21", "EHC_E01", "ORL_O34", "ORL_O42", "ORL_O36", "ADT_A44", "SDR_S32", "QBP_O33",
                                    "RSP_K31", "RTB_K13", "RDY_K15", "ORA_R33", "ORU_R30", "EHC_E15", "QBP_Q11"]
        #expect(Set(Self.probes.map(\.structure)).isDisjoint(with: earlier.union(["ACK", "ADT_A01", "ORU_R01"])))
    }
}
