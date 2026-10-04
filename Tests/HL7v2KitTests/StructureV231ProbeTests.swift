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

    // Each compliant body follows the print cited in the structure's JSON
    // (Resources/structures/v2.3.1/<ID>.json); the variant names what it breaks.
    static let probes: [Resolution] = [
        // CH08 8.3.1 (p 8-3, read as MFK_M01 through overrides.json captionStructures): the
        // general acknowledgment allows ERR; MFI is required.
        Resolution(msh9: "MFK^M04^MFK_M01", structure: "MFK_M01", compliant: ["MSA|AA|1", "ERR|1", "MFI|1", "MFA|1"],
                   variant: ["MSA|AA|1", "MFA|1"], finding: "missing MFI"),
        // CH08 8.10.1 Case 2 (p 8-67, the MFN^M06 caption read as M07, a cited erratum): no CM1.
        Resolution(msh9: "MFN^M07^MFN_M07", structure: "MFN_M07", compliant: ["MFI|1", "MFE|MAD", "CM0|1", "CM2|1"],
                   variant: ["MFI|1", "MFE|MAD", "CM0|1", "CM1|1"], finding: "unexpected CM1"),
        // CH08 8.10.1 Case 1 (p 8-67): CM2 belongs to a phase (CM1).
        Resolution(msh9: "MFN^M06^MFN_M06", structure: "MFN_M06", compliant: ["MFI|1", "MFE|MAD", "CM0|1", "CM1|1", "CM2|1"],
                   variant: ["MFI|1", "MFE|MAD", "CM0|1", "CM2|1"], finding: "unexpected CM2"),
        // CH08 8.8.1 (p 8-47, the "MFN ^M05" caption): each location has a department (LDP).
        Resolution(msh9: "MFN^M05^MFN_M05", structure: "MFN_M05", compliant: ["MFI|1", "MFE|MAD", "LOC|1", "LDP|1"],
                   variant: ["MFI|1", "MFE|MAD", "LOC|1"], finding: "missing LDP"),
        // CH02 2.20.2 (p 2-86; Table 0354 TBR_R09 read as TBR_R08): RDF is required.
        Resolution(msh9: "TBR^R08^TBR_R08", structure: "TBR_R08", compliant: ["MSA|AA|1", "QAK|1|OK", "RDF|1", "RDT|1"],
                   variant: ["MSA|AA|1", "QAK|1|OK", "RDT|1"], finding: "missing RDF"),
        // CH04 4.8.6 (p 4-70; Table 0354 RRE_O01 read as RRE_O02): RXE needs its route.
        Resolution(msh9: "RRE^O02", structure: "RRE_O02", compliant: ["MSA|AA|1", "PID|1", "ORC|OK", "RXE|1", "RXR|1"],
                   variant: ["MSA|AA|1", "PID|1", "ORC|OK", "RXE|1"], finding: "missing RXR"),
        // CH04 4.8.6 (p 4-69): RXE is required in each order.
        Resolution(msh9: "RDE^O01^RDE_O01", structure: "RDE_O01", compliant: ["PID|1", "ORC|NW", "RXE|1", "RXR|1"],
                   variant: ["PID|1", "ORC|NW", "RXR|1"], finding: "missing RXE"),
        // CH04 4.6 (p 4-46): the diet group prints {OBX [{NTE}]}, required.
        Resolution(msh9: "ORM^O01^OMD_O01", structure: "OMD_O01", compliant: ["ORC|NW", "ODS|1", "OBX|1"],
                   variant: ["ORC|NW", "ODS|1"], finding: "missing OBX"),
        // CH11 11.2.7 (p 11-11; Table 0354 PIN_107 read as PIN_I07): PROVIDER is required.
        Resolution(msh9: "PIN^I07^PIN_I07", structure: "PIN_I07", compliant: ["PRD|1", "PID|1", "IN1|1"],
                   variant: ["PID|1", "IN1|1"], finding: "missing PRD"),
        // CH03 3.2.19 (p 3-14; Table 0354 ARD_A19 read as ADR_A19): QRD is required.
        Resolution(msh9: "ADR^A19^ADR_A19", structure: "ADR_A19", compliant: ["MSA|AA|1", "QRD|1", "PID|1", "PV1|1"],
                   variant: ["MSA|AA|1", "PID|1", "PV1|1"], finding: "missing QRD"),
        // CH03 3.2.36 (p 3-24; Table 0354 '136' read as A36): the ADT_A30 merge requires MRG.
        Resolution(msh9: "ADT^A36", structure: "ADT_A30", compliant: ["EVN|A36", "PID|1", "MRG|1"],
                   variant: ["EVN|A36", "PID|1"], finding: "missing MRG"),
        // CH10 10.3 (p 10-16): RESOURCES orders LOCATION_RESOURCE (AIL) before PERSONNEL_RESOURCE (AIP).
        Resolution(msh9: "SIU^S13^SIU_S12", structure: "SIU_S12", compliant: ["SCH|1", "RGS|1", "AIL|1", "AIP|1"],
                   variant: ["SCH|1", "RGS|1", "AIP|1", "AIL|1"], finding: "unexpected AIL"),
        // CH11 11.4.1 (p 11-14): PROVIDER is required before PID (exact-matched).
        Resolution(msh9: "REF^I12^REF_I12", structure: "REF_I12", compliant: ["PRD|1", "PID|1", "PV1|1", "PV1|2"],
                   variant: ["PID|1"], finding: "unexpected PID"),
        // CH04 4.17 VXU: an ORDER needs RXA.
        Resolution(msh9: "VXU^V04^VXU_V04", structure: "VXU_V04", compliant: ["PID|1", "ORC|RE", "RXA|1"],
                   variant: ["PID|1", "ORC|RE", "OBX|1"], finding: "missing RXA"),
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

    @Test("v2.3.1 triggers resolve through Table 0354 and are matched (V231-A03)", arguments: resolutions + probes)
    func resolves(_ r: Resolution) throws {
        #expect(MessageStructureTable.structure(r.structure, version: .v2_3_1) != nil, "\(r.structure) is not modelled")
        let ok = try structureIssues(r.msh9, r.compliant)
        #expect(ok.isEmpty, "\(r.msh9): \(ok.map(\.message))")
        let bad = try structureIssues(r.msh9, r.variant)
        #expect(bad.contains { Self.describe($0.code) == r.finding && $0.severity == .error },
                "\(r.msh9): \(bad.map { Self.describe($0.code) })")
        #expect(bad.allSatisfy { "\($0.code)".contains(r.structure) }, "\(r.msh9): \(bad.map(\.message))")
    }

    private static func groups(_ elements: [StructureElement]) -> [String] {
        elements.flatMap { $0.children.isEmpty ? [] : [$0.label] + groups($0.children) }
    }

    // Group names: ORU_R01's from the HL7-xml 2.3.1 bundle (an encoder-generated file, cited
    // with its generator); RAS_O01's ENCODING through the v2.4 bundle, the v2.3.1 bundle's
    // ENCODING being refused without a cited override (P8b-14 ruling).
    @Test("v2.3.1 group names: the v2.3.1 bundle first, cited with its generator; ENCODING through v2.4")
    func groupNames() throws {
        let oru = try #require(MessageStructureTable.structure("ORU_R01", version: .v2_3_1))
        #expect(Self.groups(oru.elements) == ["PATIENT_RESULT", "PATIENT", "VISIT", "ORDER_OBSERVATION", "OBSERVATION"])
        #expect(oru.citation.contains("PATIENT_RESULT (HL7-xml 2.3.1/ORU_R01.xsd, ORU_R01.PATIENT_RESULT.CONTENT, generator urn:com.sun:encoder-hl7-1.0)"))
        let ras = try #require(MessageStructureTable.structure("RAS_O01", version: .v2_3_1))
        #expect(Self.groups(ras.elements).contains("ENCODING"))
        #expect(ras.citation.contains("ENCODING (HL7-xml v2.4/RAS_O17.xsd"))
        #expect(ras.citation.contains("refused without a cited override"))
    }

    @Test("At least twelve probes on v2.3.1 structures beyond the resolution cases")
    func coverage() {
        #expect(Self.probes.count >= 12)
        #expect(Set(Self.probes.map(\.structure)).count == Self.probes.count)
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
