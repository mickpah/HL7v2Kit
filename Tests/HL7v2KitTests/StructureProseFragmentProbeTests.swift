// StructureProseFragmentProbeTests.swift
// S5-2 (requirement 4 evidence): messages against the structures the print gives only in prose,
// transcribed by hand into overrides.json proseFragments (ADR-019 S5). MFN_M03 on v2.3 and
// v2.3.1: the "[other segments(s)]" after OM1 are the combination MFI-1 names (CH08 8.7.2).
// MFN_M08 to MFN_M11 on v2.3.1: the MFN^M03 syntax with that combination in place of the row.
// MFR_M01 on v2.3 to v2.6: the "{MFE [Z..]}" part is replaced by the fragment of the file MFI-1
// names (staff and practitioner, test/observation, CDM, LOC, clinical trials). Segment content
// is minimal; only structure issues are read.

import Testing
@testable import HL7v2Kit

@Suite("Prose-fragment structure probes")
struct StructureProseFragmentProbeTests {

    typealias Probe = StructureSlotProbeTests.Probe

    static let query = ["MSA|AA|1", "QRD|20240101|R|I|Q1|||1^RD|ALL|MFQ|LOC"]

    static let probes: [Probe] = [
        // v2.3 CH08 8.7.2 (p 8-21): one structure for M03 and M08 to M11, keyed by MFI-1.
        Probe(version: "2.3", msh9: "MFN^M08", structure: "MFN_M03",
              body: ["MFI|OMA|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM2|1", "OM4|1"], findings: [], note: "numeric"),
        Probe(version: "2.3", msh9: "MFN^M09", structure: "MFN_M03",
              body: ["MFI|OMB|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM2|1"],
              findings: ["unexpected OM2 at OM2[1]"], note: "numeric segment under the categorical key"),
        // v2.3.1 CH08 8.7.2 (p 8-20).
        Probe(version: "2.3.1", msh9: "MFN^M03^MFN_M03", structure: "MFN_M03",
              body: ["MFI|OMC|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM5|1", "OM4|1", "OM4|2"], findings: [], note: "battery"),
        Probe(version: "2.3.1", msh9: "MFN^M03^MFN_M03", structure: "MFN_M03",
              body: ["MFI|OMD|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM6|1"],
              findings: ["missing OM2 at the end"], note: "calculated observation without OM2"),
        Probe(version: "2.3.1", msh9: "MFN^M08^MFN_M08", structure: "MFN_M08",
              body: ["MFI|OMA|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM2|1", "OM3|1", "MFE|MAD|2||2", "OM1|2"],
              findings: [], note: "numeric, the second entry without detail"),
        Probe(version: "2.3.1", msh9: "MFN^M08^MFN_M08", structure: "MFN_M08",
              body: ["MFI|OMA|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM5|1"],
              findings: ["unexpected OM5 at OM5[1]"], note: "battery segment in the numeric file"),
        Probe(version: "2.3.1", msh9: "MFN^M09^MFN_M09", structure: "MFN_M09",
              body: ["MFI|OMB|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM3|1", "OM4|1", "OM4|2"], findings: [], note: "categorical"),
        Probe(version: "2.3.1", msh9: "MFN^M09^MFN_M09", structure: "MFN_M09",
              body: ["MFI|OMB|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM4|1"],
              findings: ["unexpected OM4 at OM4[1]"], note: "OM4 without OM3"),
        Probe(version: "2.3.1", msh9: "MFN^M10^MFN_M10", structure: "MFN_M10",
              body: ["MFI|OMC|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM5|1"], findings: [], note: "battery"),
        Probe(version: "2.3.1", msh9: "MFN^M10^MFN_M10", structure: "MFN_M10",
              body: ["MFI|OMC|1|UPD", "MFE|MAD|1||1", "OM5|1"],
              findings: ["missing OM1 at OM5[1]"], note: "no OM1"),
        Probe(version: "2.3.1", msh9: "MFN^M11^MFN_M11", structure: "MFN_M11",
              body: ["MFI|OMD|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM6|1", "OM2|1"], findings: [], note: "calculated"),
        Probe(version: "2.3.1", msh9: "MFN^M11^MFN_M11", structure: "MFN_M11",
              body: ["MFI|OMD|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM2|1"],
              findings: ["unexpected OM2 at OM2[1]"], note: "OM2 without OM6"),
        // v2.3 CH08 8.3.3 (p 8-5) with the fragments of 8.6.1, 8.8.1, 8.9.1 and 8.10.1.
        Probe(version: "2.3", msh9: "MFR^M05", structure: "MFR_M01",
              body: query + ["MFI|LOC|1|UPD", "MFE|MAD|1||1", "LOC|1", "LCH|1", "LDP|1", "LCC|1", "LDP|2"],
              findings: [], note: "location"),
        Probe(version: "2.3", msh9: "MFR^M05", structure: "MFR_M01",
              body: query + ["MFI|LOC|1|UPD", "MFE|MAD|1||1", "LOC|1", "LRL|1"],
              findings: ["missing LDP at the end"], note: "location without a department"),
        Probe(version: "2.3", msh9: "MFR^M02", structure: "MFR_M01",
              body: query + ["MFI|PRA|1|UPD", "MFE|MAD|1||1", "STF|1", "PRA|1", "MFE|MAD|2||2", "STF|2"],
              findings: [], note: "practitioner file"),
        Probe(version: "2.3", msh9: "MFR^M06", structure: "MFR_M01",
              body: query + ["MFI|CMA|1|UPD", "MFE|MAD|1||1", "CM0|1", "CM1|1", "CM2|1", "CM1|2"],
              findings: [], note: "clinical study with phases (case 1)"),
        Probe(version: "2.3", msh9: "MFR^M07", structure: "MFR_M01",
              body: query + ["MFI|CMB|1|UPD", "MFE|MAD|1||1", "CM0|1", "CM1|1"],
              findings: ["unexpected CM1 at CM1[1]"], note: "a phase in the study without phases (case 2)"),
        // v2.4 CH08 8.4.3 (p 8-11).
        Probe(version: "2.4", msh9: "MFR^M04^MFR_M01", structure: "MFR_M01",
              body: query + ["MFI|CDM|1|UPD", "MFE|MAD|1||1", "CDM|1", "PRC|1", "PRC|2"], findings: [], note: "charge master"),
        Probe(version: "2.4", msh9: "MFR^M03^MFR_M01", structure: "MFR_M01",
              body: query + ["MFI|OME|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM7|1", "OM7|2"],
              findings: ["unexpected OM7 at OM7[2]"], note: "a second OM7"),
        // v2.5.1 CH08 8.4.4 (p 8-8).
        Probe(version: "2.5.1", msh9: "MFR^M02^MFR_M01", structure: "MFR_M01",
              body: query + ["MFI|STF|1|UPD", "MFE|MAD|1||1", "STF|1", "PRA|1", "PRA|2", "ORG|1", "NTE|1"],
              findings: [], note: "staff file, PRA repeating as of v2.5"),
        Probe(version: "2.5.1", msh9: "MFR^M07^MFR_M01", structure: "MFR_M01",
              body: query + ["MFI|CMB|1|UPD", "MFE|MAD|1||1", "CM0|1", "CM1|1"],
              findings: ["unexpected CM1 at CM1[1]"], note: "a phase in the study without phases"),
        Probe(version: "2.5.1", msh9: "MFR^M08^MFR_M01", structure: "MFR_M01",
              body: query + ["MFI|OMA|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM2|1"], findings: [], note: "numeric"),
        // v2.6 CH08 8.4.4 (pp 8-7 to 8-8).
        Probe(version: "2.6", msh9: "MFR^M05^MFR_M01", structure: "MFR_M01",
              body: query + ["MFI|LOC|1|UPD", "MFE|MAD|1||1", "LOC|1", "LDP|1", "LCH|1", "LCC|1"], findings: [],
              note: "location"),
        Probe(version: "2.6", msh9: "MFR^M02^MFR_M01", structure: "MFR_M01",
              body: query + ["MFI|STF|1|UPD", "MFE|MAD|1||1", "PRA|1"],
              findings: ["unexpected PRA at PRA[1]", "missing STF at the end"], note: "staff entry without STF"),
    ]

    @Test("Transcribed structures: conformant bodies are clean, defects are found", arguments: probes)
    func probe(_ p: Probe) throws {
        let version = try #require(Version(rawValue: p.version))
        #expect(MessageStructureTable.structure(p.structure, version: version) != nil,
                "\(p.structure) is not modelled on v\(p.version)")
        let issues = try StructureSlotProbeTests.structureIssues(p.msh9, p.version, p.body)
        #expect(issues.map(StructureKeyedChoiceTests.describe) == p.findings, "\(p.testDescription): \(issues.map(\.message))")
        #expect(issues.allSatisfy { $0.severity == .error && "\($0.code)".contains(p.structure) },
                "\(p.testDescription): \(issues.map(\.message))")
    }

    @Test("A file the print gives no fragment for is information naming MFI-1 and the value",
          arguments: [("2.3", "MFR^M01", "ZZZ"), ("2.4", "MFR^M01^MFR_M01", "ZZZ"), ("2.5.1", "MFR^M13^MFR_M01", "CLN"),
                      ("2.6", "MFR^M08^MFR_M01", "OMA")])
    func unmappedFile(_ version: String, _ msh9: String, _ file: String) throws {
        let issues = try StructureSlotProbeTests.structureIssues(
            msh9, version, Self.query + ["MFI|\(file)|1|UPD", "MFE|MAD|1||1", "ZL7|1"])
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "MFR_M01")], "\(issues.map(\.message))")
        #expect(issues.allSatisfy { $0.severity == .info && $0.message.contains("MFI-1") && $0.message.contains(file) },
                "\(issues.map(\.message))")
    }

    @Test("Each transcription is marked as such in its citation and resolves by every printed key value")
    func citationsAndResolution() throws {
        let cases: [(Version, String, [String])] = [
            (.v2_3, "MFN_M03", ["OMA", "OMB", "OMC", "OMD"]), (.v2_3_1, "MFN_M03", ["OMA", "OMB", "OMC", "OMD"]),
            (.v2_3_1, "MFN_M08", []), (.v2_3_1, "MFN_M09", []), (.v2_3_1, "MFN_M10", []), (.v2_3_1, "MFN_M11", []),
            (.v2_3, "MFR_M01", ["CDM", "CMA", "CMB", "LOC", "OMA", "OMB", "OMC", "OMD", "PRA", "STF"]),
            (.v2_4, "MFR_M01", ["CDM", "CMA", "CMB", "LOC", "OMA", "OMB", "OMC", "OMD", "OME", "PRA", "STF"]),
            (.v2_5_1, "MFR_M01", ["CDM", "CMA", "CMB", "LOC", "OMA", "OMB", "OMC", "OMD", "OME", "PRA", "STF"]),
            (.v2_6, "MFR_M01", ["CDM", "CMA", "CMB", "LOC", "PRA", "STF"]),
        ]
        for (version, id, values) in cases {
            let s = try #require(MessageStructureTable.structure(id, version: version), "\(id) v\(version.rawValue)")
            #expect(s.citation.contains("overrides.json proseFragments"), "\(id) v\(version.rawValue)")
            #expect(s.hasKeyedChoice == !values.isEmpty, "\(id) v\(version.rawValue)")
            guard let key = StructureKeyedChoiceTests.key(s) else { continue }
            #expect(key.fieldName == "MFI-1" && key.alternatives.keys.sorted() == values, "\(id) v\(version.rawValue)")
            for value in values {
                guard case .resolved(let resolved) = s.resolvingKeyedChoices({ _ in value }) else {
                    Issue.record("\(id) v\(version.rawValue): \(value) does not resolve"); continue
                }
                #expect(resolved.requiresExactMatch == !StructureMatcher.lint(resolved.elements).isDeterministic)
            }
        }
    }
}
