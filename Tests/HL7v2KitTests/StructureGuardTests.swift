// StructureGuardTests.swift
// P8b-7: the guards every committed structure must pass, run by default over
// every structure of every generated version table (never a hard-coded list),
// so a version task that commits a bad structure fails the suite. Per
// structure:
//   1. the generated `requiresExactMatch` flag equals a fresh library lint
//      (the codegen's lint is a port; this is its drift guard);
//   2. the matcher the Validator selects by that flag (one-pass when false,
//      exact when true) agrees with the backtracking reference recogniser on
//      a seeded, bounded set of derived and mutated sequences, and the set is
//      not vacuous (both accepted and rejected sequences occur);
//   3. the first element is a required, non-repeating MSH, and every segment
//      ID is in the version's segment grammar, or is ADD;
//   4. DSC, if present anywhere, is the last top-level element (the fragment
//      rule in Validator+MessageStructure assumes it).
// Budget (2): 40 derivations per structure, each with four single-edit
// mutations (200 sequences); a structure whose alphabet after MSH has at most
// two IDs is enumerated exhaustively to length 6 instead. STRUCTURE_PROPERTY_FULL
// runs 2,000 derivations per structure.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Structure guards over every committed structure")
struct StructureGuardTests {
    typealias Property = StructureMatcherPropertyTests

    /// Each grammar version once (v2.7 and v2.8 read the v2.7.1 and v2.8.2 tables).
    static let grammarVersions: [Version] = Version.allCases.filter { $0.grammarVersion == $0 }

    static let defaultDerivations = 40

    /// `derivations` seeded derivations of the grammar, each followed by its
    /// four mutations. Derivations start bounded at 16 segments (or the
    /// shortest derivation plus 8); the bound grows by 8 after every 100
    /// rejected attempts, so the budget is always met.
    static func sequences(_ elements: [StructureElement], derivations: Int) -> (sequences: [[String]], derived: Int) {
        let letters = Property.alphabet(elements).filter { $0 != "MSH" }
        if letters.count <= 2 { return (Property.exhaustive(letters, upTo: 6), 0) }
        var rng = Property.Seeded(state: 0x8B7)
        var limit = Swift.max(16, Property.shortest(elements) + 8)
        var result: [[String]] = []
        var derived = 0, misses = 0
        while derived < derivations {
            let valid = Property.derive(elements, &rng)
            guard valid.count <= limit else {
                misses += 1
                if misses % 100 == 0 { limit += 8 }
                continue
            }
            derived += 1
            result.append(valid)
            result += Property.mutations(valid, letters, &rng)
        }
        return (result, derived)
    }

    /// The matcher the Validator uses for `structure`, as a predicate: true
    /// when the sequence is accepted (no finding).
    static func selectedAccepts(_ structure: MessageStructure) -> ([String]) -> Bool {
        if structure.requiresExactMatch {
            let exact = ExactStructureMatcher(structure: structure)
            return { exact.match($0).findings.isEmpty }
        }
        let onePass = StructureMatcher(structure: structure)
        return { onePass.match($0).findings.isEmpty }
    }

    /// Every committed structure as "<version> <ID>", one test case each, so
    /// the cases run in parallel and a failure names its structure.
    static let keys: [String] = grammarVersions.flatMap { version in
        MessageStructureTable.structures(for: version).keys.sorted().map { "\(version.rawValue) \($0)" }
    }

    static func structure(_ key: String) -> (Version, MessageStructure)? {
        let parts = key.split(separator: " ").map(String.init)
        guard parts.count == 2, let version = Version(rawValue: parts[0]),
              let structure = MessageStructureTable.structures(for: version)[parts[1]] else { return nil }
        return (version, structure)
    }

    /// Runs guards 1 to 4 on one structure; returns each guard it breaks and
    /// the number of sequences checked.
    static func guardStructure(_ structure: MessageStructure, version: Version, derivations: Int) -> (problems: [String], sequences: Int) {
        var problems: [String] = []
        func check(_ ok: Bool, _ text: @autoclosure () -> String) { if !ok { problems.append(text()) } }
        let grammar = Set(Validator.grammarTable(for: version).keys).union(["ADD"])
        let name = "v\(version.rawValue) \(structure.id)"
        let elements = structure.elements
        let all = elements.reduce(into: Set<String>()) { $0.formUnion($1.segmentIDs) }

        // 1. The generated flag equals the library lint.
        check(structure.requiresExactMatch == !StructureMatcher.lint(elements).isDeterministic, "\(name): flag differs from the lint")

        // 2. The selected matcher agrees with the reference; not vacuous.
        let (sequences, derived) = Self.sequences(elements, derivations: derivations)
        let accepts = selectedAccepts(structure)
        var accepted = 0
        var wrong: [String] = []
        for sequence in sequences {
            let reference = Property.referenceAccepts(elements, sequence)
            if reference { accepted += 1 }
            if accepts(sequence) != reference { wrong.append(sequence.joined(separator: " ")) }
        }
        let kind = structure.requiresExactMatch ? "exact" : "one-pass"
        check(wrong.isEmpty, "\(name): the \(kind) matcher disagrees with the reference on \(wrong.count), e.g. \(wrong.prefix(2))")
        check(derived == 0 || derived == derivations, "\(name): \(derived) derivations")
        if all.count > 1 {
            check(accepted > 0 && accepted < sequences.count, "\(name): vacuous, \(accepted) of \(sequences.count) accepted")
        }

        // 3. MSH first; every segment in the version grammar, or ADD.
        check(elements.first == .segment("MSH", min: 1, max: 1), "\(name): the first element is not a required MSH")
        let outside = all.subtracting(grammar)
        check(outside.isEmpty, "\(name): segments outside the v\(version.rawValue) grammar: \(outside.sorted())")

        // 4. DSC, if present, is the last top-level element and nowhere else.
        if all.contains("DSC") {
            var last = false
            if case .segment("DSC", _, _)? = elements.last { last = true }
            let elsewhere = elements.dropLast().contains { $0.segmentIDs.contains("DSC") }
            check(last && !elsewhere, "\(name): DSC is not only the last top-level element")
        }
        return (problems, sequences.count)
    }

    @Test("Every committed structure passes the guards (default budget)", arguments: keys)
    func guards(_ key: String) throws {
        let (version, structure) = try #require(Self.structure(key))
        let clock = ContinuousClock()
        var result: (problems: [String], sequences: Int) = ([], 0)
        let elapsed = clock.measure { result = Self.guardStructure(structure, version: version, derivations: Self.defaultDerivations) }
        #expect(result.problems == [])
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        print("structure-guard \(key): \(result.sequences) sequences, " + String(format: "%.1f ms", ms))
        // The budget is the sequence count, not wall time: a time ceiling
        // misfires under the parallel suite's contention. 200 sequences cost
        // about 6 to 60 ms per structure alone in a debug build (P8b-7).
        // At most 200 sampled, or 127 exhaustive (two IDs, length 6).
        #expect(result.sequences <= Self.defaultDerivations * 5, "\(key): \(result.sequences) sequences")
    }

    @Test("Every committed structure passes the guards (full budget)",
          .enabled(if: ProcessInfo.processInfo.environment["STRUCTURE_PROPERTY_FULL"] != nil,
                   "Set STRUCTURE_PROPERTY_FULL for 2,000 derivations per structure"),
          arguments: keys)
    func fullGuards(_ key: String) throws {
        let (version, structure) = try #require(Self.structure(key))
        let result = Self.guardStructure(structure, version: version, derivations: 2_000)
        #expect(result.problems == [])
        print("structure-guard-full \(key): \(result.sequences) sequences")
    }

    /// The guards a structure built to break them reports.
    private static func problems(_ elements: [StructureElement], exact: Bool? = nil) -> [String] {
        let structure = MessageStructure(id: "BAD_X01", version: "2.5.1", triggers: ["BAD^X01"], citation: "synthetic",
                                         requiresExactMatch: exact, elements: elements)
        return guardStructure(structure, version: .v2_5_1, derivations: 10).problems
    }

    @Test("Each guard rejects a structure built to break it")
    func guardsBite() {
        let seg = { (id: String, min: Int, max: Int?) in StructureElement.segment(id, min: min, max: max) }
        let pid = [seg("MSH", 1, 1), seg("PID", 1, 1), seg("NTE", 0, nil)]
        // 1 and 2: a lint-failing shape flagged for the one-pass matcher.
        let flagged = Self.problems(StructureShapes.counterExample, exact: false).joined(separator: "\n")
        #expect(flagged.contains("flag differs from the lint"))
        #expect(flagged.contains("one-pass matcher disagrees"))
        // 3: MSH not first; a segment outside the v2.5.1 grammar.
        #expect(Self.problems([seg("PID", 1, 1), seg("MSH", 1, 1), seg("NTE", 0, nil)]).contains { $0.contains("not a required MSH") })
        #expect(Self.problems(pid + [seg("QQQ", 0, 1)]).contains { $0.contains("outside the v2.5.1 grammar") })
        // 4: DSC before the end, and inside a group.
        #expect(Self.problems([seg("MSH", 1, 1), seg("DSC", 0, 1), seg("PID", 1, 1)]).contains { $0.contains("DSC is not only") })
        #expect(Self.problems(pid + [.group("G", min: 0, max: 1, elements: [seg("OBX", 1, 1), seg("DSC", 0, 1)])]).contains { $0.contains("DSC is not only") })
        // A clean structure records nothing.
        #expect(Self.problems(pid + [seg("DSC", 0, 1)]) == [])
    }

    @Test("Every grammar version is guarded, and the tables are not empty")
    func notEmpty() {
        #expect(Self.grammarVersions.count == 7)
        #expect(!Self.keys.isEmpty)
    }
}
