// ExactStructureMatcherTests.swift
// P8b-12 (G15): the exact matcher for structures that fail the determinism
// lint. The oracle is the reference recogniser of the property test
// (`StructureMatcherPropertyTests.referenceAccepts`): on every synthetic
// shape, the exact matcher accepts exactly the sequences it accepts.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Exact structure matcher")
struct ExactStructureMatcherTests {
    private static func matcher(_ elements: [StructureElement]) -> ExactStructureMatcher {
        ExactStructureMatcher(structure: MessageStructure(id: "T", version: "2.5.1", triggers: [], citation: "test", elements: elements))
    }

    private static func ids(_ text: String) -> [String] { text.split(separator: " ").map(String.init) }

    /// The sequences on which the exact matcher and the reference disagree.
    static func disagreements(_ elements: [StructureElement], _ sequences: [[String]]) -> [[String]] {
        let exact = matcher(elements)
        return sequences.filter { exact.match($0).findings.isEmpty != StructureMatcherPropertyTests.referenceAccepts(elements, $0) }
    }

    @Test("Every synthetic shape, lint-failing ones first: exact matcher and reference agree on every sequence",
          arguments: StructureShapes.all.map(\.name))
    func syntheticShapes(_ name: String) throws {
        let elements = try #require(StructureShapes.all.first { $0.name == name }).elements
        // Exhaustive: every MSH + w with |w| <= 12 over two letters, 9 over three, 8 over four.
        let letters = StructureMatcherPropertyTests.alphabet(elements).filter { $0 != "MSH" }
        let length = [1: 14, 2: 12, 3: 9, 4: 8][letters.count]
        let sequences = try #require(length.map { StructureMatcherPropertyTests.exhaustive(letters, upTo: $0) })
        #expect(sequences.count > 8000, "\(name): \(sequences.count) sequences")
        #expect(Self.disagreements(elements, sequences).prefix(3).map { $0.joined(separator: " ") } == [], "\(name)")
    }

    @Test("Pilot structures: the exact matcher also agrees with the reference (and so with the one-pass matcher)")
    func pilots() throws {
        for id in ["ACK", "ADT_A01", "ORU_R01"] {
            let elements = try #require(MessageStructureTable.structure(id, version: .v2_5_1)).elements
            let sequences = StructureMatcherPropertyTests.sequences(elements)
            #expect(Self.disagreements(elements, sequences).prefix(3).map { $0.joined(separator: " ") } == [], "\(id)")
        }
    }

    @Test("The lint-failing shapes are the ones the one-pass matcher cannot be trusted on")
    func lintFailingShapes() {
        let failing = StructureShapes.all.filter { !StructureMatcher.lint($0.elements).isDeterministic }.map(\.name)
        #expect(failing.contains("preV25") && failing.contains("counterExample")
                && failing.contains("overlappingChoice") && failing.contains("optionalAlternatives")
                && failing.contains("choiceThenSibling"), "\(failing)")
    }

    @Test("Pre-v2.5 ORU shape: accepts the interleaved notes; rejects OBX before OBR at index 1")
    func preV25() {
        let exact = Self.matcher(StructureShapes.preV25)
        #expect(exact.match(Self.ids("MSH OBR NTE OBX NTE")).findings.isEmpty)
        #expect(exact.match(Self.ids("MSH OBR NTE NTE OBX NTE OBX OBX NTE")).findings.isEmpty)
        #expect(exact.match(Self.ids("MSH OBX")).findings == [StructureFinding(kind: .unexpected, segmentID: "OBX", group: nil, index: 1)])
        #expect(exact.match(Self.ids("MSH")).findings == [StructureFinding(kind: .missing, segmentID: "OBR", group: nil, index: 1)])
        #expect(exact.match(Self.ids("MSH OBR NTE OBX NTE")).spans.isEmpty)
    }

    @Test("Counter-example {G: X {Q: X Y}}: two instances accepted; a short tail is missing Y in Q")
    func counterExample() {
        let exact = Self.matcher(StructureShapes.counterExample)
        #expect(exact.match(Self.ids("MSH X X Y X X Y")).findings.isEmpty)
        #expect(exact.match(Self.ids("MSH X X")).findings == [StructureFinding(kind: .missing, segmentID: "Y", group: "Q", index: 3)])
        #expect(exact.match(Self.ids("MSH X Y")).findings == [StructureFinding(kind: .unexpected, segmentID: "Y", group: nil, index: 2)])
    }

    @Test("Missing at the end names the first segment of the shortest completion")
    func missingAtEnd() {
        // [A] C: after MSH the shortest completion is C, not the optional A.
        let exact = Self.matcher([.segment("MSH", min: 1, max: 1), .segment("A", min: 0, max: 1), .segment("C", min: 1, max: 1)])
        #expect(exact.match(["MSH"]).findings == [StructureFinding(kind: .missing, segmentID: "C", group: nil, index: 1)])
    }

    @Test("Z-segments, ADD and the caller's transparent IDs are skipped; indices stay message indices")
    func transparency() {
        let exact = Self.matcher(StructureShapes.preV25)
        #expect(exact.match(Self.ids("MSH ZZ1 OBR ADD NTE QQQ OBX ZZ2"), transparent: ["QQQ"]).findings.isEmpty)
        #expect(exact.match(Self.ids("MSH ZZ1 OBX")).findings == [StructureFinding(kind: .unexpected, segmentID: "OBX", group: nil, index: 2)])
        #expect(exact.match(Self.ids("MSH ZZ1")).findings == [StructureFinding(kind: .missing, segmentID: "OBR", group: nil, index: 2)])
    }

    @Test("Choices: one alternative per occurrence; overlapping and optional alternatives are matched exactly")
    func choices() {
        let overlapping = Self.matcher(StructureShapes.overlappingChoice)
        #expect(overlapping.match(Self.ids("MSH A C")).findings.isEmpty)
        #expect(overlapping.match(Self.ids("MSH A B C")).findings.isEmpty)
        #expect(!overlapping.match(Self.ids("MSH A B A C")).findings.isEmpty)
        let optional = Self.matcher(StructureShapes.optionalAlternatives)
        #expect(optional.match(Self.ids("MSH C")).findings.isEmpty)
        #expect(optional.match(Self.ids("MSH A B B A C")).findings.isEmpty)
    }

    @Test("A 2,000-segment message is matched in well under a second, accepted or rejected")
    func longMessage() {
        let exact = Self.matcher(StructureShapes.preV25)
        let body = (0..<999).flatMap { _ in ["OBX", "NTE"] }
        let good = ["MSH", "OBR"] + body
        let bad = good + ["OBR"]
        #expect(good.count == 2000)
        let clock = ContinuousClock()
        var accepted = false
        var rejected: [StructureFinding] = []
        let elapsed = clock.measure {
            accepted = exact.match(good).findings.isEmpty
            rejected = exact.match(bad).findings
        }
        #expect(accepted)
        #expect(rejected == [StructureFinding(kind: .unexpected, segmentID: "OBR", group: nil, index: 2000)])
        #expect(elapsed < .seconds(1), "\(elapsed)")
    }

    @Test("The compiled automaton's state count is bounded by the structure, not the message")
    func memoBound() {
        let exact = Self.matcher(StructureShapes.preV25)
        #expect(exact.stateCount > 0 && exact.stateCount <= 64, "\(exact.stateCount)")
    }
}
