// StructureVariantFixProbeTests.swift
// S6 fix wave (requirement 4 evidence): the print disagreements S6-1 left on the default print,
// each now a variant governing its own triggers (ADR-019 S6, overrides.json variantPrints). A
// message under the stricter print's trigger draws that print's finding; the same body under the
// default print's trigger does not; a bare trigger (no MSH-9.3) resolves to its print as well.
// Segment content is minimal; only structure issues are read.

import Testing
@testable import HL7v2Kit

@Suite("Per-trigger structure variant probes (fix wave)")
struct StructureVariantFixProbeTests {

    typealias Probe = StructureSlotProbeTests.Probe

    static let ackERR = ["MSA|AA|1", "ERR|1"]
    static let ackTwoERR = ["MSA|AA|1", "ERR|1", "ERR|2"]
    static let mfkERR = ["MSA|AA|1", "ERR|1", "MFI|LOC"]
    static let twoGT1 = ["QRD|1", "PRD|1", "PID|1", "GT1|1", "GT1|2"]
    static let rreNTE = ["MSA|AA|1", "ORC|NW", "RXE|1", "NTE|1", "TQ1|1", "RXR|1"]

    static let probes: [Probe] = [
        // v2.3 CH02 2.13.1 (p 2-68) and v2.3.1 2.13.1 (p 2-78): MSH MSA [ERR]; CH07 7.2.1 (ACK^R01,
        // v2.3 p 7-14, v2.3.1 p 7-16): MSH MSA.
        Probe(version: "2.3", msh9: "ACK^R01", structure: "ACK", body: ackERR,
              findings: ["unexpected ERR at ERR[1]"], note: "observation acknowledgment with ERR"),
        Probe(version: "2.3", msh9: "ACK^A01", structure: "ACK", body: ackERR,
              findings: [], note: "general acknowledgment with ERR"),
        Probe(version: "2.3.1", msh9: "ACK^R01", structure: "ACK", body: ackERR,
              findings: ["unexpected ERR at ERR[1]"], note: "observation acknowledgment with ERR"),
        Probe(version: "2.3.1", msh9: "ACK^A01", structure: "ACK", body: ackERR,
              findings: [], note: "general acknowledgment with ERR"),
        // v2.4 CH02 2.14.1 (p 2-97): [ERR]; CH07 7.3.1 (R01, p 7-19) and CH14 14.3.2 (N02, p 14-4): no ERR.
        Probe(version: "2.4", msh9: "ACK^R01^ACK", structure: "ACK", body: ackERR,
              findings: ["unexpected ERR at ERR[1]"], note: "observation acknowledgment with ERR"),
        Probe(version: "2.4", msh9: "ACK^N02", structure: "ACK", body: ackERR,
              findings: ["unexpected ERR at ERR[1]"], note: "bare network acknowledgment with ERR"),
        Probe(version: "2.4", msh9: "ACK^A01^ACK", structure: "ACK", body: ackERR,
              findings: [], note: "general acknowledgment with ERR"),
        // CH02 ACK^varies^ACK: [{ERR}]; CH05 5.4.4 to 5.4.7 (Q16, Q17, J01, J02): [ERR].
        Probe(version: "2.5.1", msh9: "ACK^Q16^ACK", structure: "ACK", body: ackTwoERR,
              findings: ["unexpected ERR at ERR[2]"], note: "subscription acknowledgment, two ERR"),
        Probe(version: "2.5.1", msh9: "ACK^J02", structure: "ACK", body: ackTwoERR,
              findings: ["unexpected ERR at ERR[2]"], note: "bare cancel query trigger, two ERR"),
        Probe(version: "2.5.1", msh9: "ACK^A01^ACK", structure: "ACK", body: ackTwoERR,
              findings: [], note: "general acknowledgment, two ERR"),
        Probe(version: "2.6", msh9: "ACK^Q17^ACK", structure: "ACK", body: ackTwoERR,
              findings: ["unexpected ERR at ERR[2]"], note: "previous events acknowledgment, two ERR"),
        Probe(version: "2.6", msh9: "ACK^A01^ACK", structure: "ACK", body: ackTwoERR,
              findings: [], note: "general acknowledgment, two ERR"),
        Probe(version: "2.7.1", msh9: "ACK^J01^ACK", structure: "ACK", body: ackTwoERR,
              findings: ["unexpected ERR at ERR[2]"], note: "cancel query acknowledgment, two ERR"),
        Probe(version: "2.7.1", msh9: "ACK^A01^ACK", structure: "ACK", body: ackTwoERR,
              findings: [], note: "general acknowledgment, two ERR"),
        Probe(version: "2.8.2", msh9: "ACK^Q16", structure: "ACK", body: ackTwoERR,
              findings: ["unexpected ERR at ERR[2]"], note: "bare subscription trigger, two ERR"),
        Probe(version: "2.8.2", msh9: "ACK^A01^ACK", structure: "ACK", body: ackTwoERR,
              findings: [], note: "general acknowledgment, two ERR"),
        // v2.6 CH03 3.3.18 (ACK^A18^ACK, p 3-21): no UAC; CH02 2.13.1 (p 42): [UAC].
        Probe(version: "2.6", msh9: "ACK^A18^ACK", structure: "ACK", body: ["UAC|1", "MSA|AA|1"],
              findings: ["unexpected UAC at UAC[1]"], note: "merge patient acknowledgment with UAC"),
        Probe(version: "2.6", msh9: "ACK^A17^ACK", structure: "ACK", body: ["UAC|1", "MSA|AA|1"],
              findings: [], note: "swap patients acknowledgment with UAC"),
        // MFK_M01: the general print [ERR]; M07 printed only without ERR; M01 to M06 (v2.3.1) and M02,
        // M04 to M06 (v2.4) printed both ways keep the looser general print (keptOnDefault).
        Probe(version: "2.3.1", msh9: "MFK^M07", structure: "MFK_M01", body: mfkERR,
              findings: ["unexpected ERR at ERR[1]"], note: "clinical trials acknowledgment with ERR"),
        Probe(version: "2.3.1", msh9: "MFK^M05", structure: "MFK_M01", body: mfkERR,
              findings: [], note: "location acknowledgment with ERR (printed both ways)"),
        Probe(version: "2.4", msh9: "MFK^M07^MFK_M01", structure: "MFK_M01", body: mfkERR,
              findings: ["unexpected ERR at ERR[1]"], note: "clinical trials acknowledgment with ERR"),
        Probe(version: "2.4", msh9: "MFK^M02^MFK_M01", structure: "MFK_M01", body: mfkERR,
              findings: [], note: "staff acknowledgment with ERR (printed both ways)"),
        Probe(version: "2.4", msh9: "MFK^M01^MFK_M01", structure: "MFK_M01", body: mfkERR,
              findings: [], note: "general master file acknowledgment with ERR"),
        // v2.4 CH03 3.3.12 (A12, p 3-20): [DG1]; 3.3.9 (A09, p 3-18), A10, A11: [{DG1}].
        Probe(version: "2.4", msh9: "ADT^A12^ADT_A09", structure: "ADT_A09",
              body: ["EVN|A12", "PID|1", "PV1|1", "DG1|1", "DG1|2"],
              findings: ["unexpected DG1 at DG1[2]"], note: "cancel patient arriving, two DG1"),
        Probe(version: "2.4", msh9: "ADT^A12", structure: "ADT_A09",
              body: ["EVN|A12", "PID|1", "PV1|1", "DG1|1", "DG1|2"],
              findings: ["unexpected DG1 at DG1[2]"], note: "bare trigger, two DG1"),
        Probe(version: "2.4", msh9: "ADT^A11^ADT_A09", structure: "ADT_A09",
              body: ["EVN|A11", "PID|1", "PV1|1", "DG1|1", "DG1|2"],
              findings: [], note: "cancel admit, two DG1"),
        // v2.5.1 CH03 3.3.31 (A31, pp 3-37 to 3-38): PROCEDURE PR1 {ROL}; 3.3.5 (A05): PR1 [{ROL}].
        Probe(version: "2.5.1", msh9: "ADT^A31^ADT_A05", structure: "ADT_A05",
              body: ["EVN|A31", "PID|1", "PV1|1", "PR1|1"],
              findings: ["missing ROL at the end"], note: "update person, procedure without ROL"),
        Probe(version: "2.5.1", msh9: "ADT^A05^ADT_A05", structure: "ADT_A05",
              body: ["EVN|A05", "PID|1", "PV1|1", "PR1|1"],
              findings: [], note: "pre-admit, procedure without ROL"),
        // v2.6 CH03 3.3.13 (A13, pp 3-16 to 3-17): no ARV after PD1; 3.3.1 (A01, p 3-4): [{ARV}] after PD1.
        Probe(version: "2.6", msh9: "ADT^A13^ADT_A01", structure: "ADT_A01",
              body: ["EVN|A13", "PID|1", "ARV|1", "NK1|1", "PV1|1"],
              // The A13 print's only ARV follows PV1 [PV2], so the matcher reads this ARV as that one.
              findings: ["missing PV1 at ARV[1]", "unexpected NK1 at NK1[1]", "unexpected PV1 at PV1[1]"],
              note: "cancel discharge, ARV before NK1"),
        Probe(version: "2.6", msh9: "ADT^A01^ADT_A01", structure: "ADT_A01",
              body: ["EVN|A01", "PID|1", "ARV|1", "NK1|1", "PV1|1"],
              findings: [], note: "admit, ARV before NK1"),
        // CH11 11.3.6 (I06): [GT1]; 11.3.5 (I05): [{GT1}].
        Probe(version: "2.4", msh9: "RQC^I06^RQC_I05", structure: "RQC_I05", body: twoGT1,
              findings: ["unexpected GT1 at GT1[2]"], note: "clinical information query, two guarantors"),
        Probe(version: "2.4", msh9: "RQC^I05^RQC_I05", structure: "RQC_I05", body: twoGT1,
              findings: [], note: "patient information query, two guarantors"),
        Probe(version: "2.5.1", msh9: "RQC^I06", structure: "RQC_I05", body: twoGT1,
              findings: ["unexpected GT1 at GT1[2]"], note: "bare trigger, two guarantors"),
        Probe(version: "2.5.1", msh9: "RQC^I05^RQC_I05", structure: "RQC_I05", body: twoGT1,
              findings: [], note: "patient information query, two guarantors"),
        Probe(version: "2.6", msh9: "RQC^I06^RQC_I05", structure: "RQC_I05", body: twoGT1,
              findings: ["unexpected GT1 at GT1[2]"], note: "clinical information query, two guarantors"),
        Probe(version: "2.6", msh9: "RQC^I05^RQC_I05", structure: "RQC_I05", body: twoGT1,
              findings: [], note: "patient information query, two guarantors"),
        // CH04 4.13.14 (O26): RXE with no NTE in ENCODING; 4.13.6 (O12): RXE [{NTE}].
        Probe(version: "2.5.1", msh9: "RRE^O26^RRE_O12", structure: "RRE_O12", body: rreNTE,
              findings: ["unexpected NTE at NTE[1]"], note: "refill authorisation response, NTE after RXE"),
        Probe(version: "2.5.1", msh9: "RRE^O12^RRE_O12", structure: "RRE_O12", body: rreNTE,
              findings: [], note: "encoded order response, NTE after RXE"),
        Probe(version: "2.6", msh9: "RRE^O26", structure: "RRE_O12", body: rreNTE,
              findings: ["unexpected NTE at NTE[1]"], note: "bare trigger, NTE after RXE"),
        Probe(version: "2.6", msh9: "RRE^O12^RRE_O12", structure: "RRE_O12", body: rreNTE,
              findings: [], note: "encoded order response, NTE after RXE"),
    ]

    @Test("Each print governs its own triggers", arguments: probes)
    func probe(_ p: Probe) throws {
        let version = try #require(Version(rawValue: p.version))
        #expect(MessageStructureTable.structure(p.structure, version: version) != nil,
                "\(p.structure) is not modelled on v\(p.version)")
        let issues = try StructureSlotProbeTests.structureIssues(p.msh9, p.version, p.body)
        #expect(issues.map(StructureKeyedChoiceTests.describe) == p.findings, "\(p.testDescription): \(issues.map(\.message))")
        #expect(issues.allSatisfy { $0.severity == .error && "\($0.code)".contains(p.structure) },
                "\(p.testDescription): \(issues.map(\.message))")
    }

    /// The group names of an element list, depth first.
    static func groupNames(_ elements: [StructureElement]) -> [String] {
        elements.flatMap { element -> [String] in
            if case let .group(name, _, _, children) = element { return [name] + groupNames(children) }
            return []
        }
    }

    @Test("RDE^O25 takes its own print's group name (v2.7.1 and v2.8.2 4A.3.13: COMPONENTS)")
    func rdeGroupName() throws {
        for version in [Version.v2_7_1, .v2_8_2] {
            let rde = try #require(MessageStructureTable.structure("RDE_O11", version: version))
            #expect(Self.groupNames(rde.elements).contains("COMPONENT"), "v\(version.rawValue)")
            let o25 = try #require(rde.variant(messageCode: "RDE", triggerEvent: "O25"), "v\(version.rawValue)")
            #expect(Self.groupNames(o25.elements).contains("COMPONENTS"), "v\(version.rawValue)")
            #expect(!Self.groupNames(o25.elements).contains("COMPONENT"), "v\(version.rawValue)")
            #expect(rde.variant(messageCode: "RDE", triggerEvent: "O11") == nil, "v\(version.rawValue)")
        }
    }
}
