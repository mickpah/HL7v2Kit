// GroupSpanLiftTests.swift
// P8b-17 fix round 4: non-repeating groups are transparent for the anchor as
// well as for the peer. An anchor inside a non-repeating group is scoped at its
// nearest repeating enclosing group occurrence, so it sees what that occurrence
// holds, including its repeating child groups; a peer never comes from a
// repeating sibling of that occurrence.

import Testing
@testable import HL7v2Kit

@Suite("Group spans: an anchor in a non-repeating group is scoped at its repeating parent (P8b-17 fix round 4)")
struct GroupSpanLiftTests {
    /// DFT_P03 COMMON_ORDER { [ORC] ... [ORDER { OBR [{NTE}] }] [{OBSERVATION { OBX ... }}] }
    /// (v2.5.1 CH06 6.4.3): the OBR in the non-repeating ORDER is scoped at its
    /// COMMON_ORDER occurrence and finds that occurrence's OBSERVATION OBX. Through
    /// the Validator a DFT with an ORC and an OBR has no spans (the parses
    /// disagree), so this is shown on the one-pass parse.
    @Test("DFT_P03 and DFT_P11: the OBR finds the OBX of its own COMMON_ORDER, not another's",
          arguments: ["2.5.1 DFT_P03", "2.8.2 DFT_P03", "2.5.1 DFT_P11", "2.8.2 DFT_P11"])
    func dftOBRFindsOBX(_ key: String) throws {
        let parts = key.split(separator: " ").map(String.init)
        let structure = try #require(MessageStructureTable.structure(parts[1], version: GroupSpanPredicateTests.version(parts[0])))
        let ids = ["MSH", "EVN", "PID", "ORC", "OBR", "OBX", "ORC", "OBR", "OBX", "FT1"]
        let match = StructureMatcher(structure: structure).match(ids)
        #expect(match.findings.isEmpty, "\(key)")
        let index = GroupSpanIndex(spans: match.spans, elements: structure.elements, ids: ids)
        let first = index.context(around: 4, of: "OBR", for: "OBX").filter { ids[$0] == "OBX" }
        let second = index.context(around: 7, of: "OBR", for: "OBX").filter { ids[$0] == "OBX" }
        #expect(first == [5], "\(key) first OBR: \(first)")
        #expect(second == [8], "\(key) second OBR: \(second)")
    }

    /// v2.8.2 CCR_I16 CLINICAL_ORDER_DETAIL { CLINICAL_ORDER_OBJECT <OBR | ...>
    /// [{CLINICAL_ORDER_OBSERVATION { OBX ... }}] }: the OBR in the non-repeating
    /// object choice is scoped at its detail and finds that detail's OBX.
    static let ccr = ("CCR^I16^CCR_I16", ["RF1|1", "PRD|1", "ORC|NW|P1", "OBR|1|P1||X", "OBX|1",
                                         "OBR|2|P1||X", "OBX|2", "PID|1", "PV1|1"])

    @Test("v2.8.2 CCR_I16: each OBR finds the OBX of its own CLINICAL_ORDER_DETAIL")
    func ccrOBRFindsOBX() throws {
        let message = try GroupSpanScopeTests.scoped(Self.ccr.0, "2.8.2", Self.ccr.1)
        #expect(message.associatedIndex("OBX", fromIndex: 4) == 5)
        #expect(message.associatedIndex("OBX", fromIndex: 6) == 7)
    }

    /// v2.8.2 OPU_R25 ORDER { OBR ... [COMMON_ORDER { ORC ... }] ... [{RESULT { OBX ... }}] }
    /// (CH07 7.3.11): the ORC in the non-repeating COMMON_ORDER is scoped at its
    /// ORDER occurrence and finds that order's RESULT OBX.
    static let opu = ("OPU^R25^OPU_R25", ["PV1|1", "NK1|1", "SPM|1", "OBR|1|P1||X", "ORC|SC|P1", "OBX|1",
                                         "OBR|2|P2||X", "ORC|SC|P2", "OBX|2"])

    @Test("v2.8.2 OPU_R25: each COMMON_ORDER ORC finds its own order's RESULT OBX")
    func opuORCFindsOBX() throws {
        let message = try GroupSpanScopeTests.scoped(Self.opu.0, "2.8.2", Self.opu.1)
        #expect(message.associatedIndex("OBX", fromIndex: 5) == 6)
        #expect(message.associatedIndex("OBX", fromIndex: 8) == 9)
    }

    /// A custom rule on ORC or OBR gated by `OBX present` (a segment-presence
    /// atom, read through the peer lookup) fires once per anchor whose scope
    /// holds an OBX.
    @Test("A custom rule on ORC or OBR gated by `OBX present` is resolved and evaluated", arguments: ["CCR", "OPU"])
    func customRuleOverTheLookup(_ which: String) throws {
        let (msh9, body, anchor) = which == "CCR" ? (Self.ccr.0, Self.ccr.1, "OBR") : (Self.opu.0, Self.opu.1, "ORC")
        let rule = SegmentCardinalityRule(countedSegmentID: anchor, scope: .messageWide, minCount: 99,
                                          predicate: "", applicableWhen: "OBX present",
                                          specCitation: "test-only:lift")
        let profile = Profile(locale: .international, cardinalityExtensions: [anchor: [rule]])
        let message = try GroupSpanScopeTests.message(msh9, "2.8.2", body)
        let issues = Validator(locale: .international, testProfileOverride: profile).validate(message).issues
        let fired = issues.filter {
            if case .segmentCardinalityBelowMinimum(let id, 99, _, _) = $0.code { return id == anchor }
            return false
        }
        // messageWide dedupes by group head, so the rule reports once when any anchor's gate holds.
        #expect(fired.count == 1, "\(which): \(fired.map(\.message))")
    }

    /// The same atom as a counting predicate shows each anchor resolved on its
    /// own: a messageWide rule counts the anchors whose `OBX present` holds. With
    /// both orders' OBX every anchor counts (2); without the second order's OBX
    /// only the first does (1); the ORC back-walk would still find the first
    /// order's OBX for the second OBR and count 2. OPU_R25 requires each ORDER's
    /// RESULT group, so it has the full case only.
    @Test("A custom rule on ORC or OBR counting `OBX present` resolves each anchor in its own scope",
          arguments: [("CCR", true), ("CCR", false), ("OPU", true)])
    func customRuleCountsEachAnchor(_ which: String, _ secondHasOBX: Bool) throws {
        let (msh9, full, anchor) = which == "CCR" ? (Self.ccr.0, Self.ccr.1, "OBR") : (Self.opu.0, Self.opu.1, "ORC")
        let body = secondHasOBX ? full : full.filter { $0 != "OBX|2" }
        let rule = SegmentCardinalityRule(countedSegmentID: anchor, scope: .messageWide, minCount: 99,
                                          predicate: "OBX present", specCitation: "test-only:lift")
        let profile = Profile(locale: .international, cardinalityExtensions: [anchor: [rule]])
        let message = try GroupSpanScopeTests.scoped(msh9, "2.8.2", body)
        let issues = Validator(locale: .international, testProfileOverride: profile).validate(message).issues
        let counted = issues.compactMap { issue -> Int? in
            if case .segmentCardinalityBelowMinimum(anchor, 99, let actual, _) = issue.code { return actual }
            return nil
        }
        #expect(counted == [secondHasOBX ? 2 : 1], "\(which): \(counted)")
    }

    /// REF_I12 (v2.4 CH11 11.5.1) and RCI_I05 (v2.5.1 CH11) print the provider
    /// group { PRD [{CTD}] } and the OBSERVATION { OBR ... } group as repeating
    /// siblings: a provider is not tied to an observation request, so a PRD has
    /// no OBR.
    @Test("REF_I12 and RCI_I05: a PRD has no OBR", arguments: ["2.4 REF^I12^REF_I12", "2.5.1 RCI^I05^RCI_I05"])
    func prdHasNoOBR(_ key: String) throws {
        let parts = key.split(separator: " ").map(String.init)
        let body = parts[1].hasPrefix("REF") ? ["PRD|1", "PID|1", "OBR|1|P1||X"]
            : ["MSA|AA|1", "QRD|20240101|R|I|Q1|||1^RD|ALL|OS|", "PRD|1", "PID|1", "OBR|1|P1||X"]
        let message = try GroupSpanScopeTests.scoped(parts[1], parts[0], body)
        let ids = message.segments.map(\.segmentID)
        let prd = try #require(ids.firstIndex(of: "PRD"))
        #expect(message.associatedIndex("OBR", fromIndex: prd) == nil, "\(key)")
    }

    /// Transparency applies to the boundary too. v2.4 OML_O21 ORDER_GENERAL {
    /// [CONTAINER_1 { SAC [{OBX}] }] {ORDER { ORC [OBSERVATION_REQUEST { OBR ...
    /// [{OBSERVATION { OBX ... }}] }] }} } (CH04 4.4.6) and v2.5.1 OML_O33 SPECIMEN
    /// { SPM [{OBX}] {ORDER { ORC [OBSERVATION_REQUEST { OBR ... }] }} } (CH04 4.4.8):
    /// the repeating ORDER claims the OBR of its non-repeating OBSERVATION_REQUEST
    /// for OBX anchors, so the container's or the specimen's OBX, scoped at the
    /// enclosing occurrence, does not take an order's OBR.
    @Test("A container or specimen OBX does not take an order's OBR through a transparent request group",
          arguments: ["2.4 OML^O21^OML_O21 SAC|1;OBX|1;ORC|NW|P1;OBR|1|P1||X",
                      "2.5.1 OML^O33^OML_O33 SPM|1;OBX|1;ORC|NW|P1;OBR|1|P1||X"])
    func containerOBXHasNoOBR(_ spec: String) throws {
        let parts = spec.split(separator: " ").map(String.init)
        let message = try GroupSpanScopeTests.scoped(parts[1], parts[0], parts[2].split(separator: ";").map(String.init))
        let ids = message.segments.map(\.segmentID)
        let obx = try #require(ids.firstIndex(of: "OBX"))
        #expect(message.associatedIndex("OBR", fromIndex: obx) == nil, "v\(parts[0])")
    }
}

