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

    struct Probe: Sendable, CustomTestStringConvertible {
        let msh9: String
        let structure: String
        let compliant: [String]
        let variant: [String]
        /// "missing SEG" or "unexpected SEG": the variant's finding.
        let finding: String
        var testDescription: String { msh9 }
    }

    // Each compliant body follows the print cited in the structure's JSON
    // (Resources/structures/v2.3/<ID>.json); the variant names what it breaks.
    static let probes: [Probe] = [
        // CH03 3.2.7 (p 3-8; '[{ROL]}' read through a cited syntax-cell erratum): PV1 is required
        // (exact-matched: DRG twice; the one finding is at the furthest position, PR1).
        Probe(msh9: "ADT^A07", structure: "ADT_A07", compliant: ["EVN|A07", "PID|1", "PV1|1", "PR1|1", "ROL|1", "ROL|2"],
              variant: ["EVN|A07", "PID|1", "PR1|1"], finding: "unexpected PR1"),
        // CH03 3.2.19 (p 3-17; '[{ROL}] Role' one space from its description): QRD is required.
        Probe(msh9: "ADR^A19", structure: "ADR_A19", compliant: ["MSA|AA|1", "QRD|1", "PID|1", "PV1|1", "PR1|1", "ROL|1"],
              variant: ["MSA|AA|1", "PID|1", "PV1|1"], finding: "missing QRD"),
        // CH07 7.6.2 (p 7-65; '{[[ORC] ... }]' read through a cited erratum): CSR follows the patient.
        Probe(msh9: "CSU^C10", structure: "CSU_C09", compliant: ["PID|1", "CSR|1", "CSP|1", "CSS|1", "ORC|RE", "RXA|1", "RXR|1"],
              variant: ["PID|1", "CSP|1", "CSS|1", "ORC|RE", "RXA|1", "RXR|1"], finding: "unexpected CSP"),
        // CH04 4.8.17 (p 4-106; caption erratum R0R read as ROR, R0R kept): an order needs RXO.
        Probe(msh9: "ROR^R0R", structure: "ROR_ROR", compliant: ["MSA|AA|1", "QRD|1", "ORC|RE", "RXO|1", "RXR|1"],
              variant: ["MSA|AA|1", "QRD|1", "ORC|RE", "RXR|1"], finding: "missing RXO"),
        // CH04 4.8.13 (p 4-92; eventsFromTitle O01 and O02): RXA is followed by RXR.
        Probe(msh9: "RAS^O01", structure: "RAS_O01", compliant: ["ORC|RE", "RXA|1", "RXR|1"],
              variant: ["ORC|RE", "RXA|1"], finding: "missing RXR"),
        // CH04 4.8.6 (p 4-73; 'RRE Pharmacy...' one space from the code): RXE needs its route.
        Probe(msh9: "RRE^O02", structure: "RRE_O02", compliant: ["MSA|AA|1", "PID|1", "ORC|OK", "RXE|1", "RXR|1"],
              variant: ["MSA|AA|1", "PID|1", "ORC|OK", "RXE|1"], finding: "missing RXR"),
        // CH04 4.8.19 (p 4-106; the page after the break set right): a dispense needs RXD.
        Probe(msh9: "RDR^RDR", structure: "RDR_RDR", compliant: ["MSA|AA|1", "QRD|1", "ORC|RE", "RXD|1", "RXR|1"],
              variant: ["MSA|AA|1", "QRD|1", "ORC|RE", "RXR|1"], finding: "unexpected RXR"),
        // CH08 8.3.1 (p 8-4; eventsFromTitle: M03 prints no MFK of its own): MFI is required.
        Probe(msh9: "MFK^M03", structure: "MFK_M01", compliant: ["MSA|AA|1", "ERR|1", "MFI|1", "MFA|1"],
              variant: ["MSA|AA|1", "MFA|1"], finding: "missing MFI"),
        // CH08 8.6.1 (p 8-12): the staff acknowledgment prints no ERR.
        Probe(msh9: "MFK^M02", structure: "MFK_M02", compliant: ["MSA|AA|1", "MFI|1", "MFA|1"],
              variant: ["MSA|AA|1", "ERR|1", "MFI|1"], finding: "unexpected ERR"),
        // CH08 8.3.3 (p 8-5; Table 0003 'varies'): QRD is required.
        Probe(msh9: "MFQ^M05", structure: "MFQ_M01", compliant: ["QRD|1", "QRF|1"],
              variant: ["QRF|1"], finding: "missing QRD"),
        // CH10 10.2 (p 10-13; events S01 to S11 from the section text): ARQ is required.
        Probe(msh9: "SRM^S05", structure: "SRM_S01", compliant: ["ARQ|1", "RGS|1", "AIL|1", "AIP|1"],
              variant: ["RGS|1", "AIL|1"], finding: "missing ARQ"),
        // CH10 10.3 (p 10-18; S26 from 10.3.14): RESOURCES orders AIL before AIP.
        Probe(msh9: "SIU^S26", structure: "SIU_S12", compliant: ["SCH|1", "RGS|1", "AIL|1", "AIP|1"],
              variant: ["SCH|1", "RGS|1", "AIP|1", "AIL|1"], finding: "unexpected AIL"),
        // CH11 11.3.1 (p 11-14): RPA prints PROCEDURE as required.
        Probe(msh9: "RPA^I09", structure: "RPA_I08", compliant: ["MSA|AA|1", "PRD|1", "PID|1", "PR1|1"],
              variant: ["MSA|AA|1", "PRD|1", "PID|1"], finding: "missing PR1"),
        // CH02 2.14.2 (p 2-69; '{   DSP   } Display Data'): DSP is required.
        Probe(msh9: "UDM^Q05", structure: "UDM_Q05", compliant: ["URD|1", "DSP|1", "DSP|2"],
              variant: ["URD|1"], finding: "missing DSP"),
        // CH02 2.20.2 (p 2-77; folded onto TBR^*, no event printed): RDF is required.
        Probe(msh9: "TBR", structure: "TBR", compliant: ["MSA|AA|1", "QAK|1|OK", "RDF|1", "RDT|1"],
              variant: ["MSA|AA|1", "QAK|1|OK", "RDT|1"], finding: "missing RDF"),
        // CH02 2.18.1 (p 2-75; 'QCK (B to A)', the direction tag with no caret): MSA is required.
        Probe(msh9: "QCK^Q02", structure: "QCK_Q02", compliant: ["MSA|AA|1", "QAK|1|OK"],
              variant: ["QAK|1|OK"], finding: "missing MSA"),
        // CH09 9.4.10 (p 9-8; '... & Content Chapter', one space before the column): OBX is required.
        Probe(msh9: "MDM^T10", structure: "MDM_T10", compliant: ["EVN|T10", "PID|1", "PV1|1", "TXA|1", "OBX|1"],
              variant: ["EVN|T10", "PID|1", "PV1|1", "TXA|1"], finding: "missing OBX"),
    ]

    @Test("v2.3 probes: compliant bodies are clean, each variant draws its finding", arguments: probes)
    func probe(_ p: Probe) throws {
        #expect(MessageStructureTable.structure(p.structure, version: .v2_3) != nil, "\(p.structure) is not modelled")
        let ok = try structureIssues(p.msh9, p.compliant)
        #expect(ok.isEmpty, "\(p.msh9): \(ok.map(\.message))")
        let bad = try structureIssues(p.msh9, p.variant)
        #expect(bad.contains { Self.describe($0.code) == p.finding && $0.severity == .error },
                "\(p.msh9): \(bad.map { Self.describe($0.code) })")
        #expect(bad.allSatisfy { "\($0.code)".contains(p.structure) }, "\(p.msh9): \(bad.map(\.message))")
    }

    // Fix round 2: prose that names a printed structure without ambiguity adds the trigger to it
    // (overrides.json referencedTriggers): CH07 7.19.1 W01 "ORU messages" (ORU_R01), CH06 6.3.4
    // and CH07 7.2.2.1 the Chapter 2 QRY (P04, R05; both QRY prints are MSH QRD [QRF] [DSC]),
    // CH07 7.2.2.1 R06 "the unsolicited message" (UDM_Q05).
    @Test("Cross-referenced v2.3 triggers are matched against the structure the prose names",
          arguments: [Probe(msh9: "ORU^W01", structure: "ORU_R01", compliant: ["PID|1", "OBR|1", "OBX|1|CD"],
                            variant: ["PID|1", "OBX|1|CD"], finding: "unexpected OBX"),
                      Probe(msh9: "QRY^P04", structure: "QRY_Q01", compliant: ["QRD|1"], variant: ["QRF|1"], finding: "missing QRD"),
                      Probe(msh9: "QRY^R05", structure: "QRY_Q01", compliant: ["QRD|1", "QRF|1"], variant: ["QRF|1"], finding: "missing QRD"),
                      Probe(msh9: "UDM^R06", structure: "UDM_Q05", compliant: ["URD|1", "DSP|1"], variant: ["URD|1"], finding: "missing DSP")])
    func referenced(_ p: Probe) throws {
        try probe(p)
        let s = try #require(MessageStructureTable.structure(p.structure, version: .v2_3))
        #expect(s.citation.contains("added by overrides.json referencedTriggers"))
    }

    @Test("At least twelve probes on v2.3 structures")
    func coverage() {
        #expect(Self.probes.count >= 12)
    }

    // Group names: through the HL7-xml 2.3.1 bundle first (nameSource v2xml-v2.3.1), the citation
    // naming the file and its generator; the synthesised ID and the events' source are flagged.
    @Test("v2.3 citations flag the synthesised ID, the events' source and the bundle derivation")
    func citations() throws {
        let adt = try #require(MessageStructureTable.structure("ADT_A04", version: .v2_3))
        #expect(adt.citation.contains("Structure ID ADT_A04 synthesised as CODE_EVT"))
        #expect(adt.citation.contains("read from the section title 3.2.4"))
        #expect(adt.citation.contains("(HL7-xml 2.3.1/"))
        let srm = try #require(MessageStructureTable.structure("SRM_S01", version: .v2_3))
        #expect(srm.citation.contains("from overrides.json eventsFromTitle"))
        #expect(srm.triggers.count == 11)
        let ror = try #require(MessageStructureTable.structure("ROR_ROR", version: .v2_3))
        #expect(ror.triggers == ["ROR^ROR", "ROR^R0R"])
    }

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
    // information, never an error. A99 is in no table; ZZZ^Z01 is locally defined; QRF^W02 (CH07
    // 7.19.2, p 7-113) names a QRF message no chapter prints. (QRY^P04, once here, is matched
    // against the Chapter 2 QRY since fix round 2: CH06 6.3.4 names it.)
    @Test("A trigger the v2.3 print does not cover is info, not an error", arguments: ["QRF^W02", "ADT^A99", "ZZZ^Z01"])
    func uncoveredTrigger(_ msh9: String) throws {
        let issues = try structureIssues(msh9, ["PID|1"])
        #expect(issues.count == 1 && issues.first?.severity == .info, "\(msh9): \(issues.map(\.message))")
        #expect(issues.first.map { if case .messageStructureNotModelled = $0.code { true } else { false } } == true)
    }

    // P8b-15: v2.3 complete. Rule 1's unknown-MSH-9.3 branch cannot fire (rule 3 ignores MSH-9.3);
    // a trigger printed under a registered structure is info with the register reason, never an error.
    @Test("v2.3 complete: registered triggers are info with their reason; a declared ID changes nothing",
          arguments: [("ORM^O01", "Order Detail Segment"), ("PPR^PC2", "OBR, etc"), ("SUR^P09", "ED"),
                      ("ERP", "ellipsis"), ("MFN^M08", "other segments"), ("MFR^M05", "prose-printed replacement fragments"),
                      ("QRF^W02", "no message type QRF"), ("QRY^R03", "ORU^R03"), ("DSR^R03", "MSA optional"),
                      ("DSR^R05", "the reference is ambiguous")])
    func registered(_ c: (String, String)) throws {
        #expect(MessageStructureTable.isComplete(.v2_3))
        for msh9 in [c.0, c.0 + (c.0.contains("^") ? "^ZZZ_Z99" : "^^ZZZ_Z99")] {
            let issues = try structureIssues(msh9, ["PID|1"])
            #expect(issues.count == 1 && issues.first?.severity == .info, "\(msh9): \(issues.map(\.message))")
            #expect(issues.first?.message.contains(c.1) == true, "\(msh9): \(issues.map(\.message))")
        }
    }
}
