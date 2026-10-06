// StructureSlotProbeTests.swift
// S3-3 (requirement 4 evidence): messages against the structures that hold the open order
// detail slot (ADR-019 S3-1 and S3-3 amendments), on every version that prints one. Each
// conformant body follows the print cited in the structure's JSON; each defect lies outside the
// slot (a required segment missing before or after it, an unexpected segment before it, a
// second MSH), where the slot's openness still lets the validator speak. Segment content is
// minimal; only structure issues are read.

import Testing
@testable import HL7v2Kit

@Suite("Open-slot structure probes")
struct StructureSlotProbeTests {

    struct Probe: Sendable, CustomTestStringConvertible {
        let version: String
        let msh9: String
        let structure: String
        let body: [String]
        /// The structure findings, each "missing SEG at ID[n]" or "unexpected SEG at ID[n]"
        /// (the issue's location); empty for a conformant body.
        let findings: [String]
        let note: String
        var testDescription: String { "v\(version) \(msh9): \(note)" }
    }

    static let msh2 = "MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||ACK|MSG00002|P|2.3"

    static let probes: [Probe] = [
        // v2.3 CH04 4.2.1 (p 4-4): ORC [Order Detail Segment OBR, etc. [{NTE}] [{DG1}] [{OBX [{NTE}]}]].
        Probe(version: "2.3", msh9: "ORM^O01", structure: "ORM_O01",
              body: ["PID|1", "PV1|1", "ORC|NW", "OBR|1", "NTE|1", "DG1|1", "OBX|1", "NTE|2", "BLG|1"],
              findings: [], note: "general order, OBR detail"),
        // v2.3 CH04 4.8.1 (p 4-60): the pharmacy print under the same trigger fits the slot.
        Probe(version: "2.3", msh9: "ORM^O01", structure: "ORM_O01",
              body: ["PID|1", "ORC|NW", "RXO|1", "NTE|1", "RXR|1"], findings: [], note: "pharmacy detail"),
        // v2.3 CH04 4.6 (p 4-47): the dietary order, two order groups (ODS, then ODT).
        Probe(version: "2.3", msh9: "ORM^O01", structure: "ORM_O01",
              body: ["PID|1", "ORC|NW", "ODS|1", "OBX|1", "ORC|NW", "ODT|1"], findings: [], note: "dietary detail"),
        // The detail group is optional: a bare ORC is clean (the slot is min 1 inside it).
        Probe(version: "2.3", msh9: "ORM^O01", structure: "ORM_O01",
              body: ["PID|1", "ORC|NW"], findings: [], note: "bare ORC"),
        Probe(version: "2.3", msh9: "ORM^O01", structure: "ORM_O01",
              body: ["PID|1"], findings: ["missing ORC at PID[1]"], note: "no order"),
        Probe(version: "2.3", msh9: "ORM^O01", structure: "ORM_O01",
              body: ["AL1|1", "PID|1", "ORC|NW", "OBR|1"], findings: ["unexpected AL1 at AL1[1]"],
              note: "allergy before the patient"),
        Probe(version: "2.3", msh9: "ORM^O01", structure: "ORM_O01",
              body: ["PID|1", "ORC|NW", "OBR|1", msh2], findings: ["unexpected MSH at MSH[2]"],
              note: "second MSH after the slot"),
        // v2.3 CH04 4.2.2 (p 4-5): ORC [Order Detail Segment] OBR, etc. (min 0).
        Probe(version: "2.3", msh9: "ORR^O02", structure: "ORR_O02",
              body: ["MSA|AA|1", "PID|1", "ORC|OK", "RXO|1", "RXR|1"], findings: [], note: "pharmacy response"),
        Probe(version: "2.3", msh9: "ORR^O02", structure: "ORR_O02",
              body: ["ORC|OK", "OBR|1"], findings: ["unexpected ORC at ORC[1]"], note: "no MSA"),
        // v2.3 CH04 4.2.3 (p 4-6): QRD before the response.
        Probe(version: "2.3", msh9: "OSR^Q06", structure: "OSR_Q06",
              body: ["MSA|AA|1", "QRD|1", "ORC|OK", "OBR|1"], findings: [], note: "status response"),
        Probe(version: "2.3", msh9: "OSR^Q06", structure: "OSR_Q06",
              body: ["MSA|AA|1", "ORC|OK", "OBR|1"], findings: ["unexpected ORC at ORC[1]"], note: "no QRD"),
        // v2.3 CH12 12.2.2 (p 12-9): [{ORC [OBR, etc [{NTE}] [{VAR}] [{OBX [{NTE}] [{VAR}]}]]}].
        Probe(version: "2.3", msh9: "PPR^PC1", structure: "PPR_PC1",
              body: ["PID|1", "PRB|1", "ORC|NW", "OBR|1", "NTE|1", "VAR|1", "OBX|1"], findings: [],
              note: "CH12 order detail"),
        Probe(version: "2.3", msh9: "PPR^PC1", structure: "PPR_PC1",
              body: ["PID|1", "ORC|NW", "OBR|1"], findings: ["unexpected ORC at ORC[1]"], note: "no problem"),

        // v2.3.1 CH04 4.2.1 (p 4-3).
        Probe(version: "2.3.1", msh9: "ORM^O01^ORM_O01", structure: "ORM_O01",
              body: ["PID|1", "ORC|NW", "OBR|1", "NTE|1", "OBX|1"], findings: [], note: "general order, OBR detail"),
        Probe(version: "2.3.1", msh9: "ORM^O01^ORM_O01", structure: "ORM_O01",
              body: ["PID|1", "ORC|NW", "RXO|1", "NTE|1", "RXR|1"], findings: [], note: "pharmacy detail"),
        Probe(version: "2.3.1", msh9: "ORM^O01^ORM_O01", structure: "ORM_O01",
              body: ["PID|1", "ORC|NW"], findings: [], note: "bare ORC"),
        Probe(version: "2.3.1", msh9: "ORM^O01^ORM_O01", structure: "ORM_O01",
              body: ["PID|1", "NTE|1", "PD1|1", "ORC|NW", "OBR|1"], findings: ["unexpected PD1 at PD1[1]"],
              note: "PD1 after the patient notes"),
        // v2.3.1 CH12 12.3.1 (p 12-8).
        Probe(version: "2.3.1", msh9: "PPR^PC1^PPR_PC1", structure: "PPR_PC1",
              body: ["PID|1", "PRB|1", "ORC|NW", "OBR|1", "NTE|1", "VAR|1", "OBX|1"], findings: [],
              note: "CH12 order detail"),
        Probe(version: "2.3.1", msh9: "PPT^PCL^PPT_PCL", structure: "PPT_PCL",
              body: ["MSA|AA|1", "PID|1", "PTH|1", "GOL|1", "ORC|NW", "OBR|1"], findings: ["unexpected PID at PID[1]"],
              note: "no QRD"),

        // v2.4 CH12 12.3.2 (pp 12-10 to 12-11).
        Probe(version: "2.4", msh9: "PPR^PC1^PPR_PC1", structure: "PPR_PC1",
              body: ["PID|1", "PRB|1", "ORC|NW", "OBR|1", "NTE|1", "VAR|1", "OBX|1"], findings: [],
              note: "CH12 order detail"),
        Probe(version: "2.4", msh9: "PPR^PC1^PPR_PC1", structure: "PPR_PC1",
              body: ["PID|1", "PRB|1", "ORC|NW", "RXO|1", "RXR|1"], findings: [], note: "pharmacy detail"),
        Probe(version: "2.4", msh9: "PRR^PC5^PRR_PC5", structure: "PRR_PC5",
              body: ["MSA|AA|1", "PID|1", "PRB|1", "ORC|NW", "OBR|1"], findings: ["unexpected PID at PID[1]"],
              note: "no QRD"),
    ] + laterVersions + misprinted

    // The eleven prints read through cited syntax-cell errata (overrides.json, S3-3): v2.3 CH12
    // 12.2.1 PGL '[{VAR}]}', 12.2.3 PPP and 12.2.8 PPV '[{NTE]}', 12.2.10 PTR '{NTE}]', 12.2.12 PPT
    // a pathway group never closed; v2.3.1 12.2.x and v2.4 12.3.x PGL, PPV and PTR likewise. Each
    // probe pins the reading: the observation NTE optional, the order inside the problem (PPP,
    // PTR) or the goal (PGL, PPV, PPT), the pathway closed at the end (PPT).
    static let misprinted: [Probe] = [
        Probe(version: "2.3", msh9: "PGL^PC6", structure: "PGL_PC6",
              body: ["PID|1", "GOL|1", "ORC|NW", "OBR|1", "OBX|1", "NTE|1", "VAR|1", "OBX|2"], findings: [],
              note: "order observations with variance"),
        Probe(version: "2.3", msh9: "PGL^PC6", structure: "PGL_PC6",
              body: ["PID|1", "ORC|NW", "OBR|1"], findings: ["unexpected ORC at ORC[1]"], note: "no goal"),
        Probe(version: "2.3", msh9: "PPP^PCB", structure: "PPP_PCB",
              body: ["PID|1", "PTH|1", "PRB|1", "GOL|1", "ORC|NW", "OBR|1", "NTE|1", "VAR|1"], findings: [],
              note: "order under the problem"),
        Probe(version: "2.3", msh9: "PPP^PCB", structure: "PPP_PCB",
              body: ["PID|1", "PTH|1", "ORC|NW", "OBR|1"], findings: ["unexpected ORC at ORC[1]"],
              note: "order with no problem"),
        Probe(version: "2.3", msh9: "PPV^PCA", structure: "PPV_PCA",
              body: ["MSA|AA|1", "QRD|1", "PID|1", "GOL|1", "ORC|NW", "OBR|1", "NTE|1"], findings: [],
              note: "goal response with an order"),
        Probe(version: "2.3", msh9: "PPV^PCA", structure: "PPV_PCA",
              body: ["MSA|AA|1", "PID|1", "GOL|1"], findings: ["unexpected PID at PID[1]"], note: "no QRD"),
        Probe(version: "2.3", msh9: "PTR^PCF", structure: "PTR_PCF",
              body: ["MSA|AA|1", "QRD|1", "PID|1", "PTH|1", "PRB|1", "OBX|1", "ORC|NW", "OBR|1"], findings: [],
              note: "problem observation without notes"),
        Probe(version: "2.3", msh9: "PTR^PCF", structure: "PTR_PCF",
              body: ["MSA|AA|1", "QRD|1", "PID|1", "PTH|1", "ORC|NW"], findings: ["unexpected ORC at ORC[1]"],
              note: "order with no problem"),
        Probe(version: "2.3", msh9: "PPT^PCL", structure: "PPT_PCL",
              body: ["MSA|AA|1", "QRD|1", "PID|1", "PTH|1", "GOL|1", "PRB|1", "ORC|NW", "OBR|1", "PTH|2", "PID|2", "PTH|3"],
              findings: [], note: "two pathways, two patients"),
        Probe(version: "2.3", msh9: "PPT^PCL", structure: "PPT_PCL",
              body: ["MSA|AA|1", "QRD|1", "PID|1", "GOL|1"], findings: ["unexpected GOL at GOL[1]"],
              note: "goal with no pathway"),
    ] + ["2.3.1", "2.4"].flatMap { v in [
        Probe(version: v, msh9: "PGL^PC6^PGL_PC6", structure: "PGL_PC6",
              body: ["PID|1", "GOL|1", "ORC|NW", "RXO|1", "OBX|1", "VAR|1", "OBX|2"], findings: [],
              note: "order observations with variance"),
        Probe(version: v, msh9: "PPV^PCA^PPV_PCA", structure: "PPV_PCA",
              body: ["MSA|AA|1", "QRD|1", "PID|1", "GOL|1", "ORC|NW", "OBR|1", "NTE|1"], findings: [],
              note: "goal response with an order"),
        Probe(version: v, msh9: "PTR^PCF^PTR_PCF", structure: "PTR_PCF",
              body: ["MSA|AA|1", "QRD|1", "PID|1", "PTH|1", "PRB|1", "OBX|1", "ORC|NW", "OBR|1"], findings: [],
              note: "problem observation without notes"),
        Probe(version: v, msh9: "PTR^PCF^PTR_PCF", structure: "PTR_PCF",
              body: ["MSA|AA|1", "QRD|1", "PID|1", "PTH|1", "ORC|NW", "OBR|1"], findings: ["unexpected ORC at ORC[1]"],
              note: "order with no problem"),
    ] }

    // v2.5.1 to v2.8.2 CH12 print the detail as the choice < OBR | etc. > (the slot); a detail
    // the choice does not list (RXO) is accepted.
    static let laterVersions: [Probe] = ["2.5.1", "2.6", "2.7.1", "2.8.2"].flatMap { v in [
        Probe(version: v, msh9: "PGL^PC6^PGL_PC6", structure: "PGL_PC6",
              body: ["PID|1", "GOL|1", "ORC|NW", "RXO|1", "RXR|1"], findings: [], note: "detail not listed"),
        Probe(version: v, msh9: "PPR^PC1^PPR_PC1", structure: "PPR_PC1",
              body: ["PID|1", "PRB|1", "ORC|NW", "OBR|1", "NTE|1", "VAR|1", "OBX|1"], findings: [],
              note: "CH12 order detail"),
        Probe(version: v, msh9: "PGL^PC6^PGL_PC6", structure: "PGL_PC6",
              body: ["PID|1", "ORC|NW", "OBR|1"], findings: ["unexpected ORC at ORC[1]"], note: "no goal"),
        Probe(version: v, msh9: "PGL^PC6^PGL_PC6", structure: "PGL_PC6",
              body: ["PID|1", "NTE|1", "GOL|1", "ORC|NW", "OBR|1"], findings: ["unexpected NTE at NTE[1]"],
              note: "note before the goal"),
        Probe(version: v, msh9: "PGL^PC6^PGL_PC6", structure: "PGL_PC6",
              body: ["PID|1", "GOL|1", "ORC|NW", "OBR|1", msh2], findings: ["unexpected MSH at MSH[2]"],
              note: "second MSH after the slot"),
    ] }

    @Test("Slot structures: conformant bodies are clean, defects outside the slot are found", arguments: probes)
    func probe(_ p: Probe) throws {
        let version = try #require(Version(rawValue: p.version))
        let structure = try #require(MessageStructureTable.structure(p.structure, version: version),
                                     "\(p.structure) is not modelled on v\(p.version)")
        #expect(structure.requiresExactMatch)
        let issues = try Self.structureIssues(p.msh9, p.version, p.body)
        #expect(issues.map(Self.describe) == p.findings, "\(p.testDescription): \(issues.map(\.message))")
        #expect(issues.allSatisfy { $0.severity == .error && "\($0.code)".contains(p.structure) },
                "\(p.testDescription): \(issues.map(\.message))")
    }

    @Test("Every version that prints the open order detail has a conformant and a defect probe")
    func coverage() {
        for v in ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.7.1", "2.8.2"] {
            let mine = Self.probes.filter { $0.version == v }
            #expect(mine.contains { $0.findings.isEmpty } && mine.contains { !$0.findings.isEmpty }, "v\(v)")
        }
    }

    static func structureIssues(_ msh9: String, _ version: String, _ body: [String]) throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let wire = (["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||\(msh9)|MSG00001|P|\(version)"] + body)
            .joined(separator: "\r")
        return Validator(options: options).validate(try Parser().parse(wire)).issues.filter {
            switch $0.code {
            case .messageStructureSegmentMissing, .messageStructureSegmentUnexpected,
                 .messageStructureMismatch, .messageStructureNotModelled: true
            default: false
            }
        }
    }

    static func describe(_ issue: ValidationIssue) -> String {
        let at = "at \(issue.location.segmentID)[\(issue.location.segmentIndex)]"
        switch issue.code {
        case .messageStructureSegmentMissing(_, let segment, _): return "missing \(segment) \(at)"
        case .messageStructureSegmentUnexpected(_, let segment): return "unexpected \(segment) \(at)"
        default: return "\(issue.code)"
        }
    }
}
