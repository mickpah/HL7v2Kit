// StructureMatcherPropertyTests.swift
// ADR-019 guard that does not depend on the lint rule being right: for every
// structure that passes the determinism lint, the one-pass matcher reports
// no finding exactly when a backtracking reference recogniser (which tries
// every way to match) accepts the sequence.
//
// Sequences: for small alphabets (at most 4 IDs after MSH) every sequence
// MSH + w with |w| <= 8; for the pilot structures, seeded random derivations
// of the grammar (each optional element 0 or 1 times, each repeating one up
// to 3 times) of at most 16 segments, each with four single-edit mutations
// (delete, insert from the alphabet plus ZZ1 and ADD, duplicate, swap).

import Testing
@testable import HL7v2Kit

@Suite("Structure matcher reference property")
struct StructureMatcherPropertyTests {

    // MARK: - Reference recogniser

    /// Every end position reachable by matching `elements` from any of `starts`.
    private static func ends(_ elements: ArraySlice<StructureElement>, _ ids: [String], from starts: Set<Int>) -> Set<Int> {
        elements.reduce(starts) { ends(of: $1, ids, from: $0) }
    }

    private static func ends(of element: StructureElement, _ ids: [String], from starts: Set<Int>) -> Set<Int> {
        var result: Set<Int> = element.min == 0 ? starts : []
        var frontier = starts
        var count = 0
        while !frontier.isEmpty, element.max.map({ count < $0 }) ?? true, count <= ids.count {
            switch element {
            case .segment(let id, _, _):
                frontier = Set(frontier.filter { $0 < ids.count && ids[$0] == id }.map { $0 + 1 })
            case .group(_, _, _, let children):
                frontier = ends(children[...], ids, from: frontier)
            case .choice(_, _, _, let alternatives), .keyedChoice(_, _, _, _, let alternatives):
                // One occurrence takes exactly one alternative, any of them (a keyed
                // choice unresolved: no key value selects one, S4-1).
                let current = frontier
                frontier = alternatives.reduce(into: Set<Int>()) { $0.formUnion(ends(of: $1, ids, from: current)) }
            case .slot:
                // One segment per occurrence, any but MSH (S3-1 ruling): every
                // end is kept, so a segment that could follow the slot may
                // also stay in it.
                frontier = Set(frontier.filter { $0 < ids.count && ids[$0] != "MSH" }.map { $0 + 1 })
            }
            count += 1
            if count >= element.min { result.formUnion(frontier) }
        }
        return result
    }

    static func referenceAccepts(_ elements: [StructureElement], _ ids: [String]) -> Bool {
        let real = ids.filter { !StructureMatcher.isTransparent($0) }
        return ends(elements[...], real, from: [0]).contains(real.count)
    }

    // MARK: - Generators

    /// SplitMix64: a small seeded generator, so a failure reproduces.
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// The segments a derivation puts in a slot (S3-1): order detail segments
    /// the structure does not name (mutations bring in the structure's own).
    static func slotFillers(_ elements: [StructureElement]) -> [String] {
        let named = elements.reduce(into: Set<String>()) { $0.formUnion($1.segmentIDs) }
        return ["OBR", "RXO", "RXR", "ODS", "RQD"].filter { !named.contains($0) }
    }

    static func alphabet(_ elements: [StructureElement]) -> [String] {
        var ids: Set<String> = []
        var slot = false
        func walk(_ element: StructureElement) {
            switch element {
            case .segment(let id, _, _): ids.insert(id)
            case .group(_, _, _, let children): children.forEach(walk)
            case .choice(_, _, _, let alternatives), .keyedChoice(_, _, _, _, let alternatives): alternatives.forEach(walk)
            case .slot: slot = true
            }
        }
        elements.forEach(walk)
        if slot { ids.formUnion(slotFillers(elements).prefix(2)) }
        return ids.sorted()
    }

    static func derive(_ elements: [StructureElement], _ rng: inout Seeded) -> [String] {
        derive(elements, &rng, fillers: Array(slotFillers(elements).prefix(2)))
    }

    private static func derive(_ elements: [StructureElement], _ rng: inout Seeded, fillers: [String]) -> [String] {
        elements.flatMap { element -> [String] in
            // An optional element is present one time in four, so derivations
            // of the larger structures stay short.
            let low = element.min
            let high = element.max.map { Swift.min($0, 3) } ?? 3
            let count = low == 0 && Int.random(in: 0..<4, using: &rng) != 0
                ? 0 : Int.random(in: Swift.max(low, 1)...Swift.max(high, 1), using: &rng)
            return (0..<count).flatMap { _ -> [String] in
                switch element {
                case .segment(let id, _, _): return [id]
                case .group(_, _, _, let children): return derive(children, &rng, fillers: fillers)
                case .choice(_, _, _, let alternatives), .keyedChoice(_, _, _, _, let alternatives):
                    return derive([alternatives.randomElement(using: &rng)!], &rng, fillers: fillers)
                case .slot: return [fillers.randomElement(using: &rng)!]
                }
            }
        }
    }

    static func mutations(_ ids: [String], _ letters: [String], _ rng: inout Seeded) -> [[String]] {
        guard ids.count > 1 else { return [] }
        let at = Int.random(in: 1..<ids.count, using: &rng)
        var deleted = ids; deleted.remove(at: at)
        var inserted = ids; inserted.insert((letters + ["ZZ1", "ADD"]).randomElement(using: &rng)!, at: at)
        var duplicated = ids; duplicated.insert(ids[at], at: at)
        var swapped = ids; swapped.swapAt(at, at == ids.count - 1 ? at - 1 : at + 1)
        return [deleted, inserted, duplicated, swapped]
    }

    /// The length of the shortest derivation: every required element once.
    static func shortest(_ elements: [StructureElement]) -> Int {
        elements.reduce(0) { total, element in
            guard element.min > 0 else { return total }
            switch element {
            case .segment, .slot: return total + 1
            case .group(_, _, _, let children): return total + shortest(children)
            case .choice(_, _, _, let alternatives), .keyedChoice(_, _, _, _, let alternatives):
                return total + (alternatives.map { shortest([$0]) }.min() ?? 0)
            }
        }
    }

    /// Every MSH + w over `letters` with |w| <= `length`.
    static func exhaustive(_ letters: [String], upTo length: Int) -> [[String]] {
        var layer: [[String]] = [["MSH"]]
        var all = layer
        for _ in 0..<length {
            layer = layer.flatMap { prefix in letters.map { prefix + [$0] } }
            all += layer
        }
        return all
    }

    static func sequences(_ elements: [StructureElement]) -> [[String]] {
        let letters = alphabet(elements).filter { $0 != "MSH" }
        if letters.count <= 4 {
            return exhaustive(letters, upTo: 8)
        }
        var rng = Seeded(state: 2_5_1)
        var result: [[String]] = []
        // At most 16 segments, or the shortest derivation plus 8 when that is longer (a large
        // structure in the P8b-3b corpus run); a bounded number of attempts, so a structure
        // whose derivations are rarely short still ends. Neither bound binds on the pilots.
        let limit = Swift.max(16, shortest(elements) + 8)
        var attempts = 0
        while result.count < 6000, attempts < 200_000 {
            attempts += 1
            let valid = derive(elements, &rng)
            guard valid.count <= limit else { continue }
            result.append(valid)
            result += mutations(valid, letters, &rng)
        }
        return result
    }

    /// The sequences on which matcher and reference disagree.
    static func disagreements(_ elements: [StructureElement]) -> [[String]] {
        let matcher = StructureMatcher(structure: MessageStructure(id: "T", version: "2.5.1", triggers: [], citation: "test", elements: elements))
        return sequences(elements).filter { matcher.match($0).findings.isEmpty != referenceAccepts(elements, $0) }
    }

    // MARK: - Properties

    @Test("The reference recogniser accepts the reviewer's two-instance sequence")
    func referenceSanity() {
        #expect(Self.referenceAccepts(StructureShapes.counterExample, ["MSH", "X", "X", "Y", "X", "X", "Y"]))
        #expect(!Self.referenceAccepts(StructureShapes.counterExample, ["MSH", "X", "X"]))
        #expect(Self.referenceAccepts(StructureShapes.allOptionalGroup, ["MSH", "ADD", "X", "N", "X", "X", "ZZ1"]))
    }

    @Test("Pilot structures: matcher and reference agree on every generated sequence")
    func pilots() throws {
        for id in ["ACK", "ADT_A01", "ORU_R01"] {
            let structure = try #require(MessageStructureTable.structure(id, version: .v2_5_1))
            #expect(StructureMatcher.lint(structure.elements).isDeterministic)
            #expect(Self.disagreements(structure.elements).prefix(3).map { $0.joined(separator: " ") } == [], "\(id)")
        }
    }

    @Test("Pilot sequences are not vacuous: the reference accepts some and rejects some")
    func pilotsNotVacuous() throws {
        for id in ["ADT_A01", "ORU_R01"] {
            let structure = try #require(MessageStructureTable.structure(id, version: .v2_5_1))
            let accepted = Self.sequences(structure.elements).map { Self.referenceAccepts(structure.elements, $0) }
            #expect(accepted.contains(true), "\(id): no accepted sequence")
            #expect(accepted.contains(false), "\(id): no rejected sequence")
        }
    }

    @Test("Synthetic shapes that pass the lint: matcher and reference agree on every sequence", arguments: StructureShapes.all.map(\.name))
    func synthetic(_ name: String) throws {
        let elements = try #require(StructureShapes.all.first { $0.name == name }).elements
        guard StructureMatcher.lint(elements).isDeterministic else { return }
        #expect(Self.disagreements(elements).prefix(3).map { $0.joined(separator: " ") } == [], "\(name)")
    }

    @Test("Choice shapes: the lint passes exactly on the three expected; their sequences are not vacuous")
    func choiceShapes() {
        let passing = StructureShapes.choices.filter { StructureMatcher.lint($0.elements).isDeterministic }.map(\.name)
        #expect(passing == ["simpleChoice", "repeatingChoice", "namedChoice"])
        for (name, elements) in StructureShapes.choices where passing.contains(name) {
            let accepted = Self.sequences(elements).map { Self.referenceAccepts(elements, $0) }
            #expect(accepted.contains(true) && accepted.contains(false), "\(name)")
        }
        #expect(Self.referenceAccepts(StructureShapes.simpleChoice, ["MSH", "B", "C"]))
        #expect(!Self.referenceAccepts(StructureShapes.simpleChoice, ["MSH", "A", "B", "C"]))
        #expect(Self.referenceAccepts(StructureShapes.namedChoice, ["MSH", "B", "N", "A", "N", "N", "C"]))
    }

    @Test("Ruling 3 shapes agree with the reference whether or not the lint passes")
    func rulingThreeShapes() {
        #expect(Self.disagreements(StructureShapes.allOptionalGroup).isEmpty)
        #expect(Self.disagreements(StructureShapes.nullablePrefix).isEmpty)
        #expect(Self.disagreements(StructureShapes.preV25).isEmpty)
    }

    @Test("The counter-example disagrees with the reference, so the lint must reject it")
    func counterExampleDisagrees() {
        let bad = Self.disagreements(StructureShapes.counterExample).map { $0.joined(separator: " ") }
        #expect(bad.contains("MSH X X Y X X Y"))
        #expect(!StructureMatcher.lint(StructureShapes.counterExample).isDeterministic)
    }
}
