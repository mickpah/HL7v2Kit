// StructureVariantProbeTests.swift
// S6-1 (requirement 4 evidence): two normative prints of one structure ID that differ by
// trigger are each checked under their own triggers (ADR-019 S6, overrides.json variantPrints).
// A message under the stricter print's trigger draws that print's finding; the same body under
// the other print's trigger does not; a bare trigger (no MSH-9.3) resolves to its print as well.
// Segment content is minimal; only structure issues are read.

import Testing
@testable import HL7v2Kit

@Suite("Per-trigger structure variant probes")
struct StructureVariantProbeTests {

    typealias Probe = StructureSlotProbeTests.Probe

    static let twoUAC = ["UAC|1", "UAC|2", "MSA|AA|1"]
    static let merge = ["EVN|A30", "PID|1", "ARV|1", "MRG|1"]
    static let rdeNoOBX = ["ORC|NW", "RXE|1", "TQ1|1", "RXR|1", "NTE|1"]
    static let k21Head = ["MSA|AA|1", "QAK|1|OK", "QPD|1"]

    static let probes: [Probe] = [
        // v2.6 CH02 2.13.1 (p 42) ACK^varies^ACK prints [UAC]; CH10 10.4 (p 10-17) ACK^S12-S24, S26 [{UAC}].
        Probe(version: "2.6", msh9: "ACK^A01^ACK", structure: "ACK", body: twoUAC,
              findings: ["unexpected UAC at UAC[2]"], note: "general acknowledgment, two UAC"),
        Probe(version: "2.6", msh9: "ACK^A01", structure: "ACK", body: twoUAC,
              findings: ["unexpected UAC at UAC[2]"], note: "bare trigger, two UAC"),
        Probe(version: "2.6", msh9: "ACK^S12^ACK", structure: "ACK", body: twoUAC,
              findings: [], note: "scheduling acknowledgment, two UAC"),
        Probe(version: "2.6", msh9: "ACK^S26", structure: "ACK", body: twoUAC,
              findings: [], note: "bare scheduling trigger, two UAC"),
        // v2.7.1 CH02 2.13.1 (p 46) and CH10 10.4 (p 18); v2.8.2 CH02 2.13.1 (p 47) and CH10 10.4 (p 20).
        Probe(version: "2.7.1", msh9: "ACK^A01^ACK", structure: "ACK", body: twoUAC,
              findings: ["unexpected UAC at UAC[2]"], note: "general acknowledgment, two UAC"),
        Probe(version: "2.7.1", msh9: "ACK^S27^ACK", structure: "ACK", body: twoUAC,
              findings: [], note: "scheduling acknowledgment, two UAC"),
        Probe(version: "2.8.2", msh9: "ACK^R01^ACK", structure: "ACK", body: twoUAC,
              findings: ["unexpected UAC at UAC[2]"], note: "general acknowledgment, two UAC"),
        Probe(version: "2.8.2", msh9: "ACK^S13^ACK", structure: "ACK", body: twoUAC,
              findings: [], note: "scheduling acknowledgment, two UAC"),
        // v2.6 CH03 3.3.30 (A30, p 3-30; A35, A48, A49 likewise): no ARV; 3.3.34 (A34, p 3-33): [{ARV}].
        Probe(version: "2.6", msh9: "ADT^A30^ADT_A30", structure: "ADT_A30", body: merge,
              findings: ["unexpected ARV at ARV[1]"], note: "merge person information with ARV"),
        Probe(version: "2.6", msh9: "ADT^A49", structure: "ADT_A30", body: merge,
              findings: ["unexpected ARV at ARV[1]"], note: "bare trigger with ARV"),
        Probe(version: "2.6", msh9: "ADT^A34^ADT_A30", structure: "ADT_A30", body: merge,
              findings: [], note: "merge patient identifier with ARV"),
        // v2.6 CH03 3.3.43 (A43, p 3-39): no ARV; 3.3.44 (A44, p 3-40): [{ARV}].
        Probe(version: "2.6", msh9: "ADT^A43^ADT_A43", structure: "ADT_A43", body: merge,
              findings: ["unexpected ARV at ARV[1]"], note: "move patient information with ARV"),
        Probe(version: "2.6", msh9: "ADT^A44^ADT_A43", structure: "ADT_A43", body: merge,
              findings: [], note: "move account information with ARV"),
        // v2.6 CH08 8.4.1 (M01, p 8-5) and 8.8.2 (M03): no UAC; 8.4.2 (M13, p 8-6) and twelve others: [UAC].
        Probe(version: "2.6", msh9: "MFK^M01^MFK_M01", structure: "MFK_M01", body: ["UAC|1", "MSA|AA|1", "MFI|LOC"],
              findings: ["unexpected UAC at UAC[1]"], note: "master file acknowledgment with UAC"),
        Probe(version: "2.6", msh9: "MFK^M03", structure: "MFK_M01", body: ["UAC|1", "MSA|AA|1", "MFI|OMA"],
              findings: ["unexpected UAC at UAC[1]"], note: "bare test/observation trigger with UAC"),
        Probe(version: "2.6", msh9: "MFK^M13^MFK_M01", structure: "MFK_M01", body: ["UAC|1", "MSA|AA|1", "MFI|LOC"],
              findings: [], note: "general master file acknowledgment with UAC"),
        // v2.6 CH12 12.2.5 (PC4, p 12-12): MSH QRD [QRF]; 12.2.7 (PC9, p 12-14): [{SFT}] [UAC] after MSH.
        Probe(version: "2.6", msh9: "QRY^PC4^QRY_PC4", structure: "QRY_PC4", body: ["SFT|1", "QRD|1"],
              findings: ["unexpected SFT at SFT[1]"], note: "problem query with SFT"),
        Probe(version: "2.6", msh9: "QRY^PC9^QRY_PC4", structure: "QRY_PC4", body: ["SFT|1", "QRD|1"],
              findings: [], note: "goal query with SFT"),
        // v2.5.1 CH04 4.13.5 (O11, pp 4-115 to 4-116) and v2.6 4.13.5 (pp 4-88 to 4-89): OBX required in
        // OBSERVATION, so an NTE after RXR has no place; 4.13.13 (O25): [OBX].
        Probe(version: "2.5.1", msh9: "RDE^O11^RDE_O11", structure: "RDE_O11", body: rdeNoOBX,
              findings: ["unexpected NTE at NTE[1]"], note: "pharmacy encoded order, observation of NTE alone"),
        Probe(version: "2.5.1", msh9: "RDE^O25^RDE_O11", structure: "RDE_O11", body: rdeNoOBX,
              findings: [], note: "refill authorisation, observation of NTE alone"),
        Probe(version: "2.6", msh9: "RDE^O11", structure: "RDE_O11", body: rdeNoOBX,
              findings: ["unexpected NTE at NTE[1]"], note: "bare trigger, observation of NTE alone"),
        Probe(version: "2.6", msh9: "RDE^O25^RDE_O11", structure: "RDE_O11", body: rdeNoOBX,
              findings: [], note: "refill authorisation, observation of NTE alone"),
        // v2.5.1 CH03 3.3.56 (K21, p 3-59): one QUERY_RESPONSE, QRI required; 3.3.57 (K22, p 3-61): repeating, [QRI].
        Probe(version: "2.5.1", msh9: "RSP^K21^RSP_K21", structure: "RSP_K21",
              body: k21Head + ["PID|1", "QRI|1", "PID|2", "QRI|2"],
              findings: ["unexpected PID at PID[2]", "unexpected QRI at QRI[2]"], note: "demographics response, two persons"),
        Probe(version: "2.5.1", msh9: "RSP^K21^RSP_K21", structure: "RSP_K21", body: k21Head + ["PID|1"],
              findings: ["missing QRI at the end"], note: "demographics response without QRI"),
        Probe(version: "2.5.1", msh9: "RSP^K22^RSP_K21", structure: "RSP_K21",
              body: k21Head + ["PID|1", "QRI|1", "PID|2"], findings: [], note: "candidates response, two persons"),
        // v2.6 CH03 3.3.56 (K21, pp 3-48 to 3-49): one QUERY_RESPONSE with [{ARV}], QRI required;
        // 3.3.57 (K22, p 3-50): repeating, [QRI], no ARV.
        Probe(version: "2.6", msh9: "RSP^K21^RSP_K21", structure: "RSP_K21",
              body: k21Head + ["PID|1", "QRI|1", "PID|2", "QRI|2"],
              findings: ["unexpected PID at PID[2]", "unexpected QRI at QRI[2]"], note: "demographics response, two persons"),
        Probe(version: "2.6", msh9: "RSP^K21^RSP_K21", structure: "RSP_K21",
              body: k21Head + ["PID|1", "ARV|1", "QRI|1"], findings: [], note: "demographics response with ARV"),
        Probe(version: "2.6", msh9: "RSP^K22^RSP_K21", structure: "RSP_K21",
              body: k21Head + ["PID|1", "ARV|1"], findings: ["unexpected ARV at ARV[1]"],
              note: "candidates response with ARV"),
        Probe(version: "2.6", msh9: "RSP^K22^RSP_K21", structure: "RSP_K21",
              body: k21Head + ["PID|1", "PID|2", "QRI|2"], findings: [], note: "candidates response, two persons"),
        // v2.7.1 CH11 11.3.6 (I06, pp 14 to 15): [GT1]; 11.3.5 (I05, p 13): [{GT1}].
        Probe(version: "2.7.1", msh9: "RQC^I06^RQC_I05", structure: "RQC_I05",
              body: ["QRD|1", "PRD|1", "PID|1", "GT1|1", "GT1|2"],
              findings: ["unexpected GT1 at GT1[2]"], note: "clinical information query, two guarantors"),
        Probe(version: "2.7.1", msh9: "RQC^I05^RQC_I05", structure: "RQC_I05",
              body: ["QRD|1", "PRD|1", "PID|1", "GT1|1", "GT1|2"],
              findings: [], note: "patient information query, two guarantors"),
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
}
