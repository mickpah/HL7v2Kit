// StructureSlotTests.swift
// S3-1 (ADR-019 amendment 2026-10-06, "S3-1 open-slot element", and the
// controller ruling that made the slot nondeterministic): the open slot models
// the print's "Order Detail Segment OBR, etc." and `< OBR | etc. >`. A slot
// takes any segment except MSH, including one that could begin what follows
// it; a message draws a finding only when no parse accepts it. A structure
// holding a slot is exact-matched. The structures here are synthetic; the
// printed structures that carry a slot arrive with the extractor (S3-2, S3-3).

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Open-slot structure element")
struct StructureSlotTests {
    typealias Property = StructureMatcherPropertyTests

    static func seg(_ id: String, _ min: Int = 1, _ max: Int? = 1) -> StructureElement {
        .segment(id, min: min, max: max)
    }

    static let name = "Order Detail Segment"
    static let slot = StructureElement.slot(name, min: 1, max: nil, citation: "synthetic, after v2.3 CH04 4.2.1 p 4-4")

    /// MSH PID [ORC] slot [{NTE}] [DSC]
    static let plain: [StructureElement] = [seg("MSH"), seg("PID"), seg("ORC", 0, 1), slot, seg("NTE", 0, nil), seg("DSC", 0, 1)]

    /// MSH PID {ORDER: ORC slot [{NTE}]} BLG: a required segment after the slot's group.
    static let grouped: [StructureElement] = [
        seg("MSH"), seg("PID"),
        .group("ORDER", min: 1, max: nil, elements: [seg("ORC"), slot, seg("NTE", 0, nil)]),
        seg("BLG"),
    ]

    /// MSH PID [{ORC slot [{NTE}] [{DG1}] [{OBX}]}]: the v2.3 general order's shape.
    static let order: [StructureElement] = [
        seg("MSH"), seg("PID"),
        .group("ORDER", min: 0, max: nil, elements: [
            seg("ORC"), slot, seg("NTE", 0, nil), seg("DG1", 0, nil), seg("OBX", 0, nil),
        ]),
    ]

    /// MSH PID [optional slot] [{NTE}]: a slot that may be empty.
    static let optional: [StructureElement] = [
        seg("MSH"), seg("PID"), .slot(nil, min: 0, max: nil, citation: "synthetic"), seg("NTE", 0, nil),
    ]

    static func structure(_ elements: [StructureElement]) -> MessageStructure {
        MessageStructure(id: "ZZZ_Z01", version: "2.5.1", triggers: ["ZZZ^Z01"], citation: "synthetic slot", elements: elements)
    }

    static func match(_ elements: [StructureElement], _ ids: [String]) -> StructureMatch {
        ExactStructureMatcher(structure: structure(elements)).match(ids)
    }

    // MARK: - Model

    @Test("A structure with a slot fails the determinism lint and is exact-matched")
    func routedToExact() {
        let lint = StructureMatcher.lint(Self.plain)
        #expect(!lint.isDeterministic)
        #expect(lint.conflicts.contains { $0.path == [Self.name] })
        #expect(Self.structure(Self.plain).requiresExactMatch)
        #expect(CompiledStructureMatcher(Self.structure(Self.grouped)).isExact)
    }

    // The routing above makes this unreachable; the one-pass matcher must still stop
    // rather than ignore a slot in a release build, where an assertion is compiled out.
    @Test("The one-pass matcher refuses a slot structure in every build")
    func onePassRefusesSlot() async {
        await #expect(processExitsWith: .failure) {
            _ = StructureMatcher(structure: StructureSlotTests.structure(StructureSlotTests.plain))
        }
    }

    @Test("A slot has no children and no segment IDs; the structure's IDs exclude it")
    func walkers() {
        #expect(Self.slot.children.isEmpty)
        #expect(Self.slot.segmentIDs.isEmpty)
        #expect(Self.slot.min == 1 && Self.slot.max == nil)
        let ids = Self.plain.reduce(into: Set<String>()) { $0.formUnion($1.segmentIDs) }
        #expect(ids == ["MSH", "PID", "ORC", "NTE", "DSC"])
        let group = Self.grouped[2]
        #expect(group.children.count == 3)
        #expect(group.segmentIDs == ["ORC", "NTE"])
    }

    // MARK: - Matching

    @Test("Any run of segments but MSH fills the slot without a finding")
    func anyFiller() {
        let fillers = ["OBR", "RXO", "RXR", "PID", "ORC", "NTE", "DSC", "BLG", "OBX", "ZL1", "ADD"]
        var rng = Property.Seeded(state: 0x5_31)
        for _ in 0..<500 {
            let run = (0..<Int.random(in: 1...6, using: &rng)).map { _ in fillers.randomElement(using: &rng)! }
            // A run of Z-segments and ADD alone leaves the required slot empty.
            guard run.contains(where: { !StructureMatcher.isTransparent($0) }) else { continue }
            let tail = [[], ["NTE"], ["NTE", "NTE", "DSC"], ["DSC"]].randomElement(using: &rng)!
            let ids = ["MSH", "PID"] + run + tail
            #expect(Self.match(Self.plain, ids).findings.isEmpty, "\(ids)")
            let grouped = ["MSH", "PID", "ORC"] + run + ["BLG"]
            #expect(Self.match(Self.grouped, grouped).findings.isEmpty, "\(grouped)")
        }
    }

    @Test("Ruling (c): the v2.3 pharmacy order detail RXO NTE RXR is clean")
    func pharmacy() {
        #expect(Self.match(Self.order, ["MSH", "PID", "ORC", "RXO", "NTE", "RXR"]).findings.isEmpty)
        #expect(Self.match(Self.order, ["MSH", "PID", "ORC", "RXO", "NTE", "RXR", "RXC", "NTE", "OBX", "NTE", "ORC", "OBR"])
            .findings.isEmpty)
    }

    @Test("Ruling (a): a required segment after the slot is still enforced")
    func requiredAfterSlot() {
        #expect(Self.match(Self.grouped, ["MSH", "PID", "ORC", "OBR", "NTE"]).findings
            == [StructureFinding(kind: .missing, segmentID: "BLG", group: nil, index: 5)])
        // A segment that could follow the slot inside the run, the required one at the end.
        #expect(Self.match(Self.grouped, ["MSH", "PID", "ORC", "OBR", "NTE", "PID", "BLG"]).findings.isEmpty)
    }

    @Test("Ruling (b): a misplaced optional segment after the slot is read as slot content")
    func optionalAbsorbed() {
        #expect(Self.match(Self.plain, ["MSH", "PID", "OBR", "NTE", "OBR"]).findings.isEmpty)
        #expect(Self.match(Self.plain, ["MSH", "PID", "OBR", "DSC", "NTE"]).findings.isEmpty)
    }

    @Test("Ruling (d): a defect before the slot is still found")
    func beforeSlot() {
        let missingPID = Self.match(Self.plain, ["MSH", "OBR"])
        #expect(missingPID.findings == [StructureFinding(kind: .unexpected, segmentID: "OBR", group: nil, index: 1)])
        #expect(missingPID.expectedHere == ["PID"])
        #expect(Self.match(Self.grouped, ["MSH", "PID", "OBR", "BLG"]).findings
            == [StructureFinding(kind: .unexpected, segmentID: "OBR", group: nil, index: 2)])
    }

    @Test("An empty required slot is missing, named by its printed name")
    func emptySlot() {
        #expect(Self.match(Self.plain, ["MSH", "PID"]).findings
            == [StructureFinding(kind: .missing, segmentID: Self.name, group: nil, index: 2)])
        #expect(Self.match(Self.grouped, ["MSH", "PID", "ORC"]).findings
            == [StructureFinding(kind: .missing, segmentID: Self.name, group: "ORDER", index: 3)])
        // An optional slot may be empty.
        #expect(Self.match(Self.optional, ["MSH", "PID", "NTE"]).findings.isEmpty)
        #expect(Self.match(Self.optional, ["MSH", "PID"]).findings.isEmpty)
    }

    @Test("Ruling (e): the expected-here text names the slot and the segments after it")
    func expectedHere() {
        let before = Self.match(Self.plain, ["MSH", "PID", "MSH"])
        #expect(before.findings == [StructureFinding(kind: .unexpected, segmentID: "MSH", group: nil, index: 2)])
        #expect(before.expectedHere == ["ORC", Self.name])
        let inside = Self.match(Self.plain, ["MSH", "PID", "OBR", "MSH"])
        #expect(inside.findings == [StructureFinding(kind: .unexpected, segmentID: "MSH", group: nil, index: 3)])
        #expect(inside.expectedHere == [Self.name, "NTE", "DSC"])
        #expect(inside.endExpectedHere)
        #expect(Validator.expectedText(inside) == "; expected here: \(Self.name), NTE, DSC or the end of the message")
    }

    @Test("A second MSH after an order's slot content is unexpected (ORC OBR MSH)")
    func secondMSHAfterOrder() {
        let result = Self.match(Self.order, ["MSH", "PID", "ORC", "OBR", "MSH"])
        #expect(result.findings.map(\.kind) == [.unexpected])
        #expect(result.findings.map(\.segmentID) == ["MSH"])
        #expect(result.findings.map(\.index) == [4])
        #expect(result.expectedHere.contains(Self.name))
    }

    @Test("Z-segments and ADD never fill the slot: a slot holding only them is empty")
    func transparentOnlySlot() {
        #expect(Self.match(Self.plain, ["MSH", "PID", "ZL1", "ADD"]).findings
            == [StructureFinding(kind: .missing, segmentID: Self.name, group: nil, index: 4)])
        #expect(Self.match(Self.plain, ["MSH", "PID", "ZL1", "OBR", "ADD"]).findings.isEmpty)
    }

    @Test("Group spans cover the slot's segments; ambiguous parses withhold them")
    func spans() {
        let one = Self.match(Self.grouped, ["MSH", "PID", "ORC", "OBR", "RXO", "NTE", "BLG"])
        #expect(one.findings.isEmpty)
        #expect(one.spans.map(\.path) == [["ORDER"]])
        #expect(one.spans.map(\.indices) == [2...5])
        // The second ORC may open a second ORDER or be slot content: the parses
        // disagree on the groups, so no spans are given.
        let two = Self.match(Self.grouped, ["MSH", "PID", "ORC", "OBR", "ORC", "OBR", "BLG"])
        #expect(two.findings.isEmpty)
        #expect(two.spansWithheld)
        #expect(two.spans.isEmpty)
    }

    // MARK: - Cross-checks

    @Test("The exact matcher agrees with the reference recogniser on slot structures")
    func reference() {
        let shapes = [("plain", Self.plain), ("grouped", Self.grouped), ("order", Self.order), ("optional", Self.optional)]
        for (label, elements) in shapes {
            let matcher = ExactStructureMatcher(structure: Self.structure(elements))
            let sequences = Property.sequences(elements)
            let wrong = sequences.filter { matcher.match($0).findings.isEmpty != Property.referenceAccepts(elements, $0) }
            let accepted = sequences.filter { Property.referenceAccepts(elements, $0) }.count
            #expect(wrong.isEmpty, "\(label): \(wrong.count) disagreements, e.g. \(wrong.prefix(2))")
            #expect(accepted > 0 && accepted < sequences.count, "\(label): vacuous")
        }
    }

    @Test("The reference recogniser lets a slot take any segment but MSH")
    func referenceSanity() {
        #expect(Property.referenceAccepts(Self.plain, ["MSH", "PID", "OBR", "PID", "ORC", "NTE", "DSC"]))
        #expect(Property.referenceAccepts(Self.plain, ["MSH", "PID", "OBR", "NTE", "OBR"]))
        #expect(!Property.referenceAccepts(Self.plain, ["MSH", "PID"]))
        #expect(!Property.referenceAccepts(Self.plain, ["MSH", "PID", "MSH"]))
        #expect(!Property.referenceAccepts(Self.grouped, ["MSH", "PID", "ORC", "BLG"]))
        #expect(Property.referenceAccepts(Self.order, ["MSH", "PID", "ORC", "RXO", "NTE", "RXR"]))
    }

    @Test("The structure guards pass on slot structures")
    func guards() {
        for elements in [Self.plain, Self.grouped, Self.order, Self.optional] {
            let result = StructureGuardTests.guardStructure(Self.structure(elements), version: .v2_5_1, derivations: 40)
            #expect(result.problems == [])
        }
    }

    // MARK: - Validator end to end

    private func issues(_ elements: [StructureElement], _ body: [String]) throws -> [IssueCode] {
        let message = try Parser().parse(MessageStructureValidationTests.wire("ZZZ^Z01^ZZZ_Z01", body))
        let validator = Validator()
        let table = ["ZZZ_Z01": Self.structure(elements)]
        let resolved = validator.resolveStructure(message, severity: .error, structures: table)
        let structure = try #require(resolved.structure)
        return validator.matchStructure(structure, message: message, severity: .error).map(\.code)
    }

    @Test("Validator: order detail segments in the slot draw no structure finding")
    func validatorClean() throws {
        let pid = MessageStructureValidationTests.pid
        #expect(try issues(Self.plain, [pid, "ORC|NW", "OBR|1", "RXO|1", "NTE|1"]).isEmpty)
        #expect(try issues(Self.order, [pid, "ORC|NW", "RXO|1", "NTE|1", "RXR|1"]).isEmpty)
    }

    @Test("Validator: an empty required slot draws messageStructureSegmentMissing naming the slot")
    func validatorMissing() throws {
        #expect(try issues(Self.plain, [MessageStructureValidationTests.pid])
            == [.messageStructureSegmentMissing(structure: "ZZZ_Z01", segmentID: Self.name, group: nil)])
    }

    @Test("Validator: a required segment after the slot draws messageStructureSegmentMissing")
    func validatorRequiredAfter() throws {
        #expect(try issues(Self.grouped, [MessageStructureValidationTests.pid, "ORC|NW", "OBR|1", "NTE|1"])
            == [.messageStructureSegmentMissing(structure: "ZZZ_Z01", segmentID: "BLG", group: nil)])
    }
}
