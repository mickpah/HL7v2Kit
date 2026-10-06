// StructureSlotTests.swift
// S3-1 (ADR-019 amendment 2026-10-06, "S3-1 open-slot element"): the open
// slot models the print's "Order Detail Segment OBR, etc." and `< OBR | etc. >`.
// A slot takes any run of segments whose IDs are not in its FOLLOW set (the
// segments that can come next); MSH never fills it. A structure holding a
// slot is exact-matched. The structures here are synthetic; the printed
// structures that carry a slot arrive with the extractor (S3-2, S3-3).

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

    /// MSH PID [ORC] slot [{NTE}] [DSC]: the slot's FOLLOW set is {NTE, DSC}.
    static let plain: [StructureElement] = [seg("MSH"), seg("PID"), seg("ORC", 0, 1), slot, seg("NTE", 0, nil), seg("DSC", 0, 1)]

    /// MSH PID {ORDER: ORC slot [{NTE}]} BLG: FOLLOW is {NTE, ORC, BLG}.
    static let grouped: [StructureElement] = [
        seg("MSH"), seg("PID"),
        .group("ORDER", min: 1, max: nil, elements: [seg("ORC"), slot, seg("NTE", 0, nil)]),
        seg("BLG"),
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

    @Test("Any run of segments outside the FOLLOW set fills the slot without a finding")
    func anyFiller() {
        let fillers = ["OBR", "RXO", "RXR", "PID", "ORC", "PV1", "OBX", "ZL1", "ADD"]
        var rng = Property.Seeded(state: 0x5_31)
        for _ in 0..<500 {
            let run = (0..<Int.random(in: 1...6, using: &rng)).map { _ in fillers.randomElement(using: &rng)! }
            // A run of Z-segments and ADD alone leaves the required slot empty.
            guard run.contains(where: { !StructureMatcher.isTransparent($0) }) else { continue }
            let tail = [[], ["NTE"], ["NTE", "NTE", "DSC"], ["DSC"]].randomElement(using: &rng)!
            let ids = ["MSH", "PID"] + run + tail
            #expect(Self.match(Self.plain, ids).findings.isEmpty, "\(ids)")
            // In the grouped structure ORC re-enters ORDER and BLG ends it.
            let inner = run.filter { $0 != "ORC" && $0 != "BLG" }
            if inner.contains(where: { !StructureMatcher.isTransparent($0) }) {
                let grouped = ["MSH", "PID", "ORC"] + inner + tail.filter { $0 == "NTE" } + ["BLG"]
                #expect(Self.match(Self.grouped, grouped).findings.isEmpty, "\(grouped)")
            }
        }
    }

    @Test("A FOLLOW-set segment ends the slot, and what the print gives after it is still checked")
    func afterSlot() {
        // The NTE ends the slot; an order detail segment after it has no place.
        #expect(Self.match(Self.plain, ["MSH", "PID", "OBR", "NTE", "OBR"]).findings
            == [StructureFinding(kind: .unexpected, segmentID: "OBR", group: nil, index: 4)])
        // DSC is last.
        #expect(Self.match(Self.plain, ["MSH", "PID", "OBR", "DSC", "NTE"]).findings
            == [StructureFinding(kind: .unexpected, segmentID: "NTE", group: nil, index: 4)])
        // A required segment after the slot's group is still required.
        #expect(Self.match(Self.grouped, ["MSH", "PID", "ORC", "OBR", "NTE"]).findings
            == [StructureFinding(kind: .missing, segmentID: "BLG", group: nil, index: 5)])
        #expect(Self.match(Self.grouped, ["MSH", "PID", "ORC", "OBR", "NTE", "PID", "BLG"]).findings
            == [StructureFinding(kind: .unexpected, segmentID: "PID", group: nil, index: 5)])
    }

    @Test("A defect before the slot is still found")
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
        // ORC is outside the plain slot's FOLLOW set, so there it can fill the slot;
        // in the grouped structure ORC re-enters ORDER, so it cannot.
        #expect(Self.match(Self.plain, ["MSH", "PID", "ORC"]).findings.isEmpty)
        #expect(Self.match(Self.grouped, ["MSH", "PID", "ORC"]).findings
            == [StructureFinding(kind: .missing, segmentID: Self.name, group: "ORDER", index: 3)])
        let early = Self.match(Self.plain, ["MSH", "PID", "NTE"])
        #expect(early.findings == [StructureFinding(kind: .unexpected, segmentID: "NTE", group: nil, index: 2)])
        #expect(early.expectedHere == ["ORC", Self.name])
        #expect(!early.endExpectedHere)
        let inGroup = Self.match(Self.grouped, ["MSH", "PID", "ORC", "NTE"])
        #expect(inGroup.findings == [StructureFinding(kind: .unexpected, segmentID: "NTE", group: nil, index: 3)])
        #expect(inGroup.expectedHere == [Self.name])
        // An optional slot may be empty.
        #expect(Self.match(Self.optional, ["MSH", "PID", "NTE"]).findings.isEmpty)
        #expect(Self.match(Self.optional, ["MSH", "PID"]).findings.isEmpty)
    }

    @Test("Group spans cover the slot's segments; the slot itself has no span")
    func spans() {
        let ids = ["MSH", "PID", "ORC", "OBR", "RXO", "NTE", "ORC", "OBR", "BLG"]
        let match = Self.match(Self.grouped, ids)
        #expect(match.findings.isEmpty)
        #expect(!match.spansWithheld)
        #expect(match.spans.map(\.path) == [["ORDER"], ["ORDER"]])
        #expect(match.spans.map(\.indices) == [2...5, 6...7])
    }

    // MARK: - Cross-checks

    @Test("The exact matcher agrees with the reference recogniser on slot structures")
    func reference() {
        for (label, elements) in [("plain", Self.plain), ("grouped", Self.grouped), ("optional", Self.optional)] {
            let matcher = ExactStructureMatcher(structure: Self.structure(elements))
            let sequences = Property.sequences(elements)
            let wrong = sequences.filter { matcher.match($0).findings.isEmpty != Property.referenceAccepts(elements, $0) }
            let accepted = sequences.filter { Property.referenceAccepts(elements, $0) }.count
            #expect(wrong.isEmpty, "\(label): \(wrong.count) disagreements, e.g. \(wrong.prefix(2))")
            #expect(accepted > 0 && accepted < sequences.count, "\(label): vacuous")
        }
    }

    @Test("The reference recogniser fills a slot by the FOLLOW-set rule")
    func referenceSanity() {
        #expect(Property.referenceAccepts(Self.plain, ["MSH", "PID", "OBR", "PID", "ORC", "NTE", "DSC"]))
        #expect(!Property.referenceAccepts(Self.plain, ["MSH", "PID", "OBR", "NTE", "OBR"]))
        #expect(!Property.referenceAccepts(Self.plain, ["MSH", "PID"]))
        #expect(!Property.referenceAccepts(Self.grouped, ["MSH", "PID", "ORC", "BLG"]))
        #expect(!Property.referenceAccepts(Self.plain, ["MSH", "PID", "MSH"]))
        #expect(Property.referenceAccepts(Self.grouped, ["MSH", "PID", "ORC", "OBR", "ORC", "RXO", "BLG"]))
    }

    @Test("The structure guards pass on slot structures")
    func guards() {
        for elements in [Self.plain, Self.grouped, Self.optional] {
            let result = StructureGuardTests.guardStructure(Self.structure(elements), version: .v2_5_1, derivations: 40)
            #expect(result.problems == [])
        }
    }

    // MARK: - Validator end to end

    private func issues(_ body: [String]) throws -> [IssueCode] {
        let message = try Parser().parse(MessageStructureValidationTests.wire("ZZZ^Z01^ZZZ_Z01", body))
        let validator = Validator()
        let table = ["ZZZ_Z01": Self.structure(Self.plain)]
        let resolved = validator.resolveStructure(message, severity: .error, structures: table)
        let structure = try #require(resolved.structure)
        return validator.matchStructure(structure, message: message, severity: .error).map(\.code)
    }

    @Test("Validator: order detail segments in the slot draw no structure finding")
    func validatorClean() throws {
        #expect(try issues([MessageStructureValidationTests.pid, "ORC|NW", "OBR|1", "RXO|1", "NTE|1"]).isEmpty)
    }

    @Test("Validator: an empty required slot draws messageStructureSegmentMissing naming the slot")
    func validatorMissing() throws {
        #expect(try issues([MessageStructureValidationTests.pid])
            == [.messageStructureSegmentMissing(structure: "ZZZ_Z01", segmentID: Self.name, group: nil)])
    }

    @Test("Validator: the expected-here text names the slot")
    func validatorExpected() throws {
        let message = try Parser().parse(MessageStructureValidationTests.wire("ZZZ^Z01^ZZZ_Z01",
                                                                             [MessageStructureValidationTests.pid, "NTE|1"]))
        let found = Validator().matchStructure(Self.structure(Self.plain), message: message, severity: .error)
        #expect(found.map(\.code) == [.messageStructureSegmentUnexpected(structure: "ZZZ_Z01", segmentID: "NTE")])
        #expect(found.first?.message.contains("expected here: ORC or \(Self.name)") == true)
    }
}
