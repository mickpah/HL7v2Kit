// StructureKeyedChoiceTests.swift
// S4-1 (requirement 4 evidence): messages against the structures whose body a field value
// chooses (ADR-019 S4 amendment). MFN_M03 (v2.4 to v2.6): the "other segment(s)" after OM1
// are those of the MFN^M08 to MFN^M12 group that MFI-1 names (OMA to OME, CH08 8.8.3 to
// 8.8.7). ERP (v2.3) and ERP_R09 (v2.3.1 to v2.5.1): the rows after ERQ are the segments of the
// message ERQ-2 names, which the print does not enumerate, so they are an open slot. Both are
// matched exactly (the slot, and MFN_M03 without its key), so a defect before the open part is
// reported as the first unexpected segment with what was expected there. Segment content is
// minimal; only structure issues are read.

import Testing
@testable import HL7v2Kit

@Suite("Field-keyed choice probes")
struct StructureKeyedChoiceTests {

    typealias Probe = StructureSlotProbeTests.Probe

    static let probes: [Probe] = [
        // v2.5.1 CH08 8.8.2 (p 8-23) and 8.8.3 (p 8-24): MFI-1 = OMA selects MF_TEST_NUMERIC's
        // segments after OM1, [OM2] [OM3] [OM4].
        Probe(version: "2.5.1", msh9: "MFN^M03^MFN_M03", structure: "MFN_M03",
              body: ["MFI|OMA^Numeric^HL70175|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM2|1", "OM3|1", "OM4|1"],
              findings: [], note: "numeric observation"),
        Probe(version: "2.5.1", msh9: "MFN^M03^MFN_M03", structure: "MFN_M03",
              body: ["MFI|OMB|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM3|1", "OM4|1", "OM4|2",
                     "MFE|MAD|2||2", "OM1|2"],
              findings: [], note: "categorical observations, the second without detail"),
        Probe(version: "2.5.1", msh9: "MFN^M03^MFN_M03", structure: "MFN_M03",
              body: ["MFI|OMA|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM5|1"],
              findings: ["unexpected OM5 at OM5[1]"], note: "battery segment under the numeric key"),
        Probe(version: "2.5.1", msh9: "MFN^M03^MFN_M03", structure: "MFN_M03",
              body: ["MFI|OMD|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM6|1"],
              findings: ["missing OM2 at the end"], note: "calculated observation without OM2"),
        Probe(version: "2.5.1", msh9: "MFN^M03^MFN_M03", structure: "MFN_M03",
              body: ["MFE|MAD|1||1", "OM1|1", "OM2|1"],
              findings: ["unexpected MFE at MFE[1]"], note: "no MFI, so no key"),
        // v2.6 CH08 8.8.2 (p 8-20) and 8.8.4 to 8.8.7.
        Probe(version: "2.6", msh9: "MFN^M03^MFN_M03", structure: "MFN_M03",
              body: ["MFI|OMC|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM5|1", "OM4|1"],
              findings: [], note: "battery"),
        Probe(version: "2.6", msh9: "MFN^M03^MFN_M03", structure: "MFN_M03",
              body: ["MFI|OME|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM7|1", "OM7|2"],
              findings: ["unexpected OM7 at OM7[2]"], note: "a second OM7"),
        // v2.4 CH08 8.8.2 (pp 8-21 to 8-22): the combinations printed after the M03 syntax.
        Probe(version: "2.4", msh9: "MFN^M03^MFN_M03", structure: "MFN_M03",
              body: ["MFI|OMB|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM3|1"],
              findings: [], note: "categorical observation"),
        Probe(version: "2.4", msh9: "MFN^M03^MFN_M03", structure: "MFN_M03",
              body: ["MFI|OMB|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM2|1"],
              findings: ["unexpected OM2 at OM2[1]"], note: "numeric segment under the categorical key"),

        // ERP: the open slot after ERQ (v2.5.1 CH05 5.10.4.2, p 5-120).
        Probe(version: "2.5.1", msh9: "ERP^R09^ERP_R09", structure: "ERP_R09",
              body: ["MSA|AA|1", "QAK|1|OK", "ERQ|1|A04", "EVN|A04", "PID|1", "PV1|1"],
              findings: [], note: "an A04 body"),
        Probe(version: "2.5.1", msh9: "ERP^R09^ERP_R09", structure: "ERP_R09",
              body: ["MSA|AA|1", "QAK|1|NF", "ERQ|1|A04"], findings: [], note: "no data found"),
        Probe(version: "2.5.1", msh9: "ERP^R09^ERP_R09", structure: "ERP_R09",
              body: ["MSA|AA|1", "ERQ|1|A04", "PID|1"], findings: ["unexpected ERQ at ERQ[1]"], note: "no QAK"),
        Probe(version: "2.4", msh9: "ERP^R09^ERP_R09", structure: "ERP_R09",
              body: ["MSA|AA|1", "QAK|1|OK", "ERQ|1|A04", "EVN|A04", "PID|1"], findings: [], note: "an A04 body"),
        Probe(version: "2.4", msh9: "ERP^R09^ERP_R09", structure: "ERP_R09",
              body: ["QAK|1|OK", "ERQ|1|A04", "PID|1"], findings: ["unexpected QAK at QAK[1]"], note: "no MSA"),
        Probe(version: "2.3.1", msh9: "ERP^R09^ERP_R09", structure: "ERP_R09",
              body: ["MSA|AA|1", "QAK|1|OK", "ERQ|1|A04", "EVN|A04", "PID|1"], findings: [], note: "an A04 body"),
        Probe(version: "2.3.1", msh9: "ERP^R09^ERP_R09", structure: "ERP_R09",
              body: ["MSA|AA|1", "QAK|1|OK", "PID|1"], findings: ["unexpected PID at PID[1]"], note: "no ERQ"),
        Probe(version: "2.3", msh9: "ERP^R09", structure: "ERP",
              body: ["MSA|AA|1", "QAK|1|OK", "ERQ|1|A04", "EVN|A04", "PID|1"], findings: [], note: "an A04 body"),
        Probe(version: "2.3", msh9: "ERP^R09", structure: "ERP",
              body: ["MSA|AA|1", "QAK|1|OK", "ERQ|1|A04", "PID|1", "MSA|AA|2"], findings: [],
              note: "a second MSA is slot content"),
        Probe(version: "2.3", msh9: "ERP^R09", structure: "ERP",
              body: ["QAK|1|OK", "MSA|AA|1", "ERQ|1|A04"], findings: ["unexpected QAK at QAK[1]"],
              note: "QAK before MSA"),
    ]

    @Test("Keyed and ERQ-2 bodies: conformant bodies are clean, defects are found", arguments: probes)
    func probe(_ p: Probe) throws {
        let version = try #require(Version(rawValue: p.version))
        #expect(MessageStructureTable.structure(p.structure, version: version) != nil,
                "\(p.structure) is not modelled on v\(p.version)")
        let issues = try StructureSlotProbeTests.structureIssues(p.msh9, p.version, p.body)
        #expect(issues.map(Self.describe) == p.findings, "\(p.testDescription): \(issues.map(\.message))")
        #expect(issues.allSatisfy { $0.severity == .error && "\($0.code)".contains(p.structure) },
                "\(p.testDescription): \(issues.map(\.message))")
    }

    @Test("An MFI-1 value the print does not map is information naming the key and the value",
          arguments: ["2.4", "2.5.1", "2.6"])
    func unknownKey(_ version: String) throws {
        let issues = try StructureSlotProbeTests.structureIssues(
            "MFN^M03^MFN_M03", version, ["MFI|ZZZ^Local^L|1|UPD", "MFE|MAD|1||1", "OM1|1", "ZOM|1"])
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "MFN_M03")], "\(issues.map(\.message))")
        #expect(issues.allSatisfy { $0.severity == .info && $0.message.contains("MFI-1") && $0.message.contains("ZZZ") },
                "\(issues.map(\.message))")
    }

    @Test("Two MFI segments: the first one's key selects the alternative, the second is reported")
    func twoKeySegments() throws {
        // OMA selects MF_TEST_NUMERIC ([OM2] after OM1); were the second MFI's OMB read, OM2
        // would be out of place in MF_TEST_CATEGORICAL.
        let issues = try StructureSlotProbeTests.structureIssues(
            "MFN^M03^MFN_M03", "2.5.1", ["MFI|OMA|1|UPD", "MFI|OMB|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM2|1"])
        #expect(issues.map(Self.describe) == ["unexpected MFI at MFI[2]"], "\(issues.map(\.message))")
    }

    @Test("An empty MFI-1 leaves the plain choice; the required-field rule reports MFI-1")
    func emptyKey() throws {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let wire = ["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||MFN^M03^MFN_M03|MSG00001|P|2.5.1",
                    "MFI||1|UPD", "MFE|MAD|1||1", "OM1|1", "OM3|1"].joined(separator: "\r")
        let issues = Validator(options: options).validate(try Parser().parse(wire)).issues
        let structure = issues.filter { "\($0.code)".hasPrefix("messageStructure") }
        #expect(structure.isEmpty, "a body some alternative accepts: \(structure.map(\.message))")
        #expect(issues.contains { $0.code == .requiredFieldMissing && $0.location.pathDescription.hasPrefix("MFI[1]-1") },
                "\(issues.map { "\($0.code) \($0.location.pathDescription)" })")
    }

    @Test("Group spans follow the selected alternative")
    func spans() throws {
        let wire = (["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||MFN^M03^MFN_M03|MSG00001|P|2.5.1",
                     "MFI|OMB|1|UPD", "MFE|MAD|1||1", "OM1|1", "OM3|1", "OM4|1"]).joined(separator: "\r")
        let outcome = Validator().groupSpanOutcome(for: try Parser().parse(wire))
        let spans = try #require(outcome.spans, "\(outcome.cause ?? "")")
        #expect(spans.spans.map(\.description) == ["MF_TEST 2...5", "MF_TEST/MF_TEST_CATEGORICAL 4...5",
                                                   "MF_TEST/MF_TEST_CATEGORICAL/MF_TEST_CAT_DETAIL 4...5"],
                "\(spans.spans)")
        let unknown = wire.replacingOccurrences(of: "MFI|OMB", with: "MFI|ZZZ")
        let none = Validator().groupSpanOutcome(for: try Parser().parse(unknown))
        #expect(none.spans == nil)
        #expect(none.cause?.contains("ZZZ") == true, "\(none.cause ?? "")")
    }

    @Test("A keyed choice is deterministic by its key; each resolution is linted as it is")
    func lintAndResolution() throws {
        let m03 = try #require(MessageStructureTable.structure("MFN_M03", version: .v2_5_1))
        #expect(m03.hasKeyedChoice)
        #expect(!m03.requiresExactMatch, "the key, not the first segment, selects the alternative")
        for (value, group) in [("OMA", "MF_TEST_NUMERIC"), ("OMB", "MF_TEST_CATEGORICAL"), ("OMC", "MF_TEST_BATTERIES"),
                               ("OMD", "MF_TEST_CALCULATED"), ("OME", "MF_OBS_ATTRIBUTES")] {
            guard case .resolved(let resolved) = m03.resolvingKeyedChoices({ _ in value }) else {
                Issue.record("\(value) does not resolve"); continue
            }
            #expect(!resolved.hasKeyedChoice && resolved.keySelection == "MFI-1=\(value)")
            #expect(resolved.elements[3].children[2].groupName == group, "\(value)")
            #expect(resolved.requiresExactMatch == !StructureMatcher.lint(resolved.elements).isDeterministic)
        }
        // No key value: the plain choice of every alternative, which the choice rule sends to the
        // exact matcher (the alternatives overlap and may be empty).
        guard case .resolved(let open) = m03.resolvingKeyedChoices({ _ in nil }) else {
            Issue.record("no value does not resolve"); return
        }
        #expect(!open.hasKeyedChoice && open.requiresExactMatch)
        #expect(m03.resolvingKeyedChoices({ _ in "ZZZ" }) == .unmapped(key: try #require(Self.key(m03)), value: "ZZZ"))
    }

    static func key(_ structure: MessageStructure) -> StructureChoiceKey? {
        func find(_ elements: [StructureElement]) -> StructureChoiceKey? {
            for element in elements {
                if case .keyedChoice(_, _, _, let key, _) = element { return key }
                if let key = find(element.children) { return key }
            }
            return nil
        }
        return find(structure.elements)
    }

    static func describe(_ issue: ValidationIssue) -> String {
        if case .messageStructureSegmentMissing(_, let segment, _) = issue.code,
           issue.message.contains("at the end of the message") {
            return "missing \(segment) at the end"
        }
        return StructureSlotProbeTests.describe(issue)
    }
}
