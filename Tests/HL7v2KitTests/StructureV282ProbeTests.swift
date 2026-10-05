// StructureV282ProbeTests.swift
// P8b-11 (requirement 4 evidence): hand-built v2.8.2 messages for structures not
// probed for v2.5.1 or v2.6, one compliant with the chapter print and one variant
// that breaks it. Under messageStructureSeverity = .error the compliant message
// draws no structure issue and the variant draws the expected finding. Segment
// content is minimal; only structure issues are read.

import Testing
@testable import HL7v2Kit

@Suite("v2.8.2 structure probes")
struct StructureV282ProbeTests {

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
    // (Resources/structures/v2.8.2/<ID>.json); the variant names what it breaks.
    static let probes: [Probe] = [
        // CH11 11.6.1: RESOURCE_OBJECT is a named choice of AIS, AIG, AIL or AIP; an
        // OBX straight after RGS has no resource to belong to. PATIENT_VISITS is required.
        Probe(structure: "CCM_I21", msh9: "CCM^I21^CCM_I21",
              compliant: ["PID|1", "SCH|1", "RGS|1", "AIL|1", "OBX|1", "AIP|1", "PV1|1"],
              variant: ["PID|1", "SCH|1", "RGS|1", "OBX|1", "PV1|1"], finding: "unexpected OBX"),
        // CH16 16.3.1: '< ... >' with no '|' named INVOICE_INFORMATION_SUBMIT is a named
        // required group (P8b-6 ruling; the CH16 text says nothing of "one of"); IVC opens it.
        Probe(structure: "EHC_E01", msh9: "EHC^E01^EHC_E01",
              compliant: ["IVC|1", "PYE|1", "PSS|1", "PSG|1", "PSL|1"],
              variant: ["PSS|1", "PSG|1", "PSL|1"], finding: "missing IVC"),
        // CH04 4.4.9.1 (ORL^O34, patient required): RESPONSE opens with PID.
        Probe(structure: "ORL_O34", msh9: "ORL^O34^ORL_O34",
              compliant: ["MSA|AA|1", "PID|1", "SPM|1", "ORC|OK", "OBR|1"],
              variant: ["MSA|AA|1", "SPM|1", "ORC|OK"], finding: "unexpected SPM"),
        // CH04 4.4.9.2 (ORL^O34 too, patient optional; the shared-trigger pair of ORL_O34):
        // SPECIMEN is required in RESPONSE.
        Probe(structure: "ORL_O42", msh9: "ORL^O34^ORL_O42",
              compliant: ["MSA|AA|1", "SPM|1", "ORC|OK", "OBR|1"],
              variant: ["MSA|AA|1", "PID|1", "ORC|OK"], finding: "missing SPM"),
        // CH04 4.4.11.1 (the caption title wraps before the Segments row): each SPECIMEN
        // needs a SPECIMEN_CONTAINER (SAC) before its orders.
        Probe(structure: "ORL_O36", msh9: "ORL^O36^ORL_O36",
              compliant: ["MSA|AA|1", "PID|1", "SPM|1", "SAC|1", "ORC|OK"],
              variant: ["MSA|AA|1", "PID|1", "SPM|1", "ORC|OK"], finding: "missing SAC"),
        // CH03 3.2.44 (A44 and A47; ADT_A30, which carried the merges up to v2.6, is a
        // Table 0354 row marked Deprecated): MRG is required in PATIENT.
        Probe(structure: "ADT_A44", msh9: "ADT^A47^ADT_A44",
              compliant: ["EVN|A47", "PID|1", "ARV|1", "MRG|1", "PID|2", "MRG|2"],
              variant: ["EVN|A47", "PID|1", "ARV|1"], finding: "missing MRG"),
        // CH17 17.6.5 (SCN^S37, with the hyphenated group-mark erratum): the named required
        // group opens with SDD.
        Probe(structure: "SDR_S32", msh9: "SCN^S37^SDR_S32",
              compliant: ["SDD|1", "SCD|1", "SCD|2"],
              variant: ["SCD|1"], finding: "missing SDD"),
        // CH04A 4A.3.20 (the table ends before the 'QPD Input Parameter Specification'
        // prose): RXD needs at least one RXR.
        Probe(structure: "RSP_K31", msh9: "RSP^K31^RSP_K31",
              compliant: ["MSA|AA|1", "QAK|1", "QPD|Q31", "RCP|I", "ORC|OK", "RXD|1", "RXR|1"],
              variant: ["MSA|AA|1", "QAK|1", "QPD|Q31", "RCP|I", "ORC|OK", "RXD|1"], finding: "missing RXR"),
        // CH04 4.16.6 (a 'Segments Descriptions' header): QPD then RCP, both required.
        Probe(structure: "QBP_O33", msh9: "QBP^Q33^QBP_O33",
              compliant: ["QPD|Q33", "RCP|I"],
              variant: ["QPD|Q33"], finding: "missing RCP"),
        // CH05 5.4.3: QAK is required between MSA and QPD.
        Probe(structure: "RDY_K15", msh9: "RDY^K15^RDY_K15",
              compliant: ["MSA|AA|1", "QAK|1", "QPD|Q15", "DSP|1", "DSP|2"],
              variant: ["MSA|AA|1", "QPD|Q15", "DSP|1"], finding: "missing QAK"),
        // CH05 5.4.2: ROW_DEFINITION opens with RDF; an RDT alone does not open it.
        Probe(structure: "RTB_K13", msh9: "RTB^K13^RTB_K13",
              compliant: ["MSA|AA|1", "QAK|1", "QPD|Q13", "RDF|1", "RDT|1", "RDT|2"],
              variant: ["MSA|AA|1", "QAK|1", "QPD|Q13", "RDT|1"], finding: "unexpected RDT"),
        // CH07 7.3.4 (ORA^R33, captioned 'ORA^R33^ORA_R33 :' with a space): MSA required.
        Probe(structure: "ORA_R33", msh9: "ORA^R33^ORA_R33",
              compliant: ["MSA|AA|1", "ORC|OK"],
              variant: ["ORC|OK"], finding: "missing MSA"),
        // CH07 7.3.4 (ORU^R30, no longer running on into ACK^R30): ORC is required.
        Probe(structure: "ORU_R30", msh9: "ORU^R30^ORU_R30",
              compliant: ["PID|1", "ORC|NW", "OBR|1", "OBX|1"],
              variant: ["PID|1", "OBR|1", "OBX|1"], finding: "missing ORC"),
        // CH16 16.3.9: PAYMENT_REMITTANCE_HEADER_INFO is a named required group opening
        // with PMT. EHC_E15 fails the lint, so the exact matcher reports one finding.
        Probe(structure: "EHC_E15", msh9: "EHC^E15^EHC_E15",
              compliant: ["PMT|1", "PYE|1", "IPR|1", "IVC|1", "PSS|1", "PSG|1", "PSL|1", "ADJ|1"],
              variant: ["PYE|1", "IPR|1"], finding: "unexpected PYE"),
    ]

    private func structureIssues(_ msh9: String, _ body: [String]) throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let wire = (["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||\(msh9)|MSG00001|P|2.8.2"] + body).joined(separator: "\r")
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
        #expect(MessageStructureTable.structure(p.structure, version: .v2_8_2) != nil, "\(p.structure) is not modelled")
        let ok = try structureIssues(p.msh9, p.compliant)
        #expect(ok.isEmpty, "\(p.structure): \(ok.map(\.message))")
        let bad = try structureIssues(p.msh9, p.variant)
        #expect(bad.contains { Self.describe($0.code) == p.finding && $0.severity == .error },
                "\(p.structure): \(bad.map { Self.describe($0.code) })")
    }

    // CH07 7.3.1: the ORU_R01 rows end at the 'ACK^R01^ACK : Observation Message' caption
    // (P8b-11 reader fix), so the structure is the print's (ORDER_DOCUMENT inside
    // COMMON_ORDER), and an MSA after the observations is unexpected, not part of ORU_R01.
    @Test("v2.8.2 ORU_R01 ends where its acknowledgment is captioned")
    func oruR01AfterRunOnFix() throws {
        let structure = try #require(MessageStructureTable.structure("ORU_R01", version: .v2_8_2))
        #expect(structure.elements.filter { $0.label == "MSH" }.count == 1)
        let compliant = ["PID|1", "ORC|RE", "OBX|1", "TXA|1", "OBR|1", "OBX|2", "SPM|1", "OBX|3"]
        #expect(try structureIssues("ORU^R01^ORU_R01", compliant).isEmpty)
        let issues = try structureIssues("ORU^R01^ORU_R01", ["PID|1", "OBR|1", "OBX|1", "MSA|AA|1"])
        #expect(issues.map { Self.describe($0.code) } == ["unexpected MSA"], "\(issues.map(\.message))")
    }

    // Deprecated-adjacent: ADT_A30 is a Table 0354 v2.8.2 row marked Deprecated, so a
    // message declaring it is info with that reason, while ADT_A44 is matched.
    @Test("A Table 0354 row marked Deprecated is info; its successor print is matched")
    func deprecatedRow() throws {
        let issues = try structureIssues("ADT^A34^ADT_A30", ["EVN|A34", "PID|1", "MRG|1"])
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "ADT_A30")])
        #expect(issues.first?.severity == .info && issues.first?.message.contains("marks it Deprecated") == true,
                "\(issues.map(\.message))")
    }

    // CH04A 4A.3.20 declares 'Query Trigger (= MSH-9): QBP^Q31^QBP_Q11' (Table 0003 Q31):
    // the registered template's triggers include it, so it is info, never a mismatch.
    @Test("QBP^Q31^QBP_Q11, declared by the CH04A query profile, is info on v2.8.2")
    func queryProfileTrigger() throws {
        let issues = try structureIssues("QBP^Q31^QBP_Q11", ["QPD|Q31", "RCP|I"])
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "QBP_Q11")], "\(issues.map(\.message))")
        #expect(issues.first?.severity == .info)
    }

    @Test("At least twelve probes, none a pilot structure nor one probed for v2.5.1 or v2.6")
    func coverage() {
        #expect(Self.probes.count >= 12)
        let earlier: Set<String> = ["ADT_A03", "ADT_A05", "ORM_O01", "OMG_O19", "RDE_O11", "RAS_O17", "SIU_S12", "MFN_M02",
                                    "DFT_P03", "BAR_P01", "OUL_R22", "MDM_T02", "QBP_Q21", "VXU_V04",
                                    "EHC_E02", "EHC_E12", "SDR_S31", "OSR_Q06", "ADT_A60", "QRY_PC4", "MFK_M01", "BRP_O30",
                                    "ADT_A43", "QBP_E03", "PMU_B01", "RQI_I01", "MFR_M04", "ADT_A30"]
        #expect(Set(Self.probes.map(\.structure)).isDisjoint(with: earlier.union(["ACK", "ADT_A01", "ORU_R01"])))
    }
}
