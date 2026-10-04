// StructureLintCorpusTests.swift
// P8b-3b measurement for the G1 decision: run every structure the extractor
// parses (`extract-message-structures.py --dump DIR`, choices included from
// P8b-6) through the ADR-019 determinism lint and the reference-recogniser
// property comparison, without committing any structure JSON. Reads
// STRUCTURE_LINT_CORPUS/v<ver>/<ID>.json and writes lint-<ver>.tsv into the
// directory STRUCTURE_LINT_OUT (default: the corpus directory), one row per
// structure: version, structure, lint result, shape class, recogniser
// agreement, DSC placement, exact-matcher agreement (P8b-12), the default
// guards' verdict (P8b-7). Skipped
// unless STRUCTURE_LINT_CORPUS is set. P8b-7: files are read through
// StructureJSONDecoder (the codegen's acceptance rules); a missing or empty
// version directory fails; each structure has a minimum sequence count.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Structure lint corpus", .enabled(if: ProcessInfo.processInfo.environment["STRUCTURE_LINT_CORPUS"] != nil,
                                         "Set STRUCTURE_LINT_CORPUS to an extractor --dump directory"))
struct StructureLintCorpusTests {
    private static func name(_ element: StructureElement) -> String { element.label }

    /// Where an overlap's FOLLOW comes from: a later sibling group or segment
    /// (up to the next non-nullable one), or the enclosing level (the element
    /// is trailing). The pre-v2.5 ORU shape is a segment against a sibling
    /// group: `OBR {[NTE]} {[OBX] {[NTE]}}`.
    static func shape(_ elements: [StructureElement], _ overlap: StructureLint.Overlap) -> String {
        var level = elements
        for group in overlap.path.dropLast() {
            guard let parent = level.first(where: { name($0) == group }), !parent.children.isEmpty else { return "other: path not found" }
            level = parent.children
        }
        let ids = Set(overlap.segmentIDs)
        let label = "\(overlap.path.last ?? "?") vs \(ids.sorted().joined(separator: ","))"
        for (i, element) in level.enumerated() where name(element) == overlap.path.last {
            let kind = element.children.isEmpty ? "segment" : "group"
            for sibling in level[(i + 1)...] {
                if !sibling.firstSet.isDisjoint(with: ids) {
                    if case .group(let g, _, _, _) = sibling {
                        return kind == "segment" ? "pre-v2.5-ORU: \(label) in sibling group \(g)"
                            : "other: group \(label) in sibling group \(g)"
                    }
                    return "other: \(kind) \(label) in a sibling segment"
                }
                if !sibling.isNullable { break }
            }
            return "other: trailing \(kind) \(label) via the enclosing follow"
        }
        return "other: \(label)"
    }

    /// DSC placement: "none", "last" (the last top-level element), or where it sits.
    static func dsc(_ elements: [StructureElement]) -> String {
        if case .segment("DSC", _, _)? = elements.last { return "last" }
        if elements.contains(where: { name($0) == "DSC" && $0.children.isEmpty }) { return "not-last-top-level" }
        func nested(_ list: [StructureElement]) -> Bool {
            list.contains { element in
                let children = element.children
                return children.contains { name($0) == "DSC" && $0.children.isEmpty } || nested(children)
            }
        }
        return nested(elements) ? "inside-group" : "none"
    }

    /// One run per version, in parallel; each writes `lint-<version>.tsv`.
    @Test("Lint and reference recogniser over every extracted structure",
          arguments: ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.7.1", "2.8.2"])
    func corpus(_ version: String) throws {
        let env = ProcessInfo.processInfo.environment
        let root = URL(fileURLWithPath: try #require(env["STRUCTURE_LINT_CORPUS"]))
        let dir = root.appendingPathComponent("v\(version)")
        // P8b-7: a missing or empty version directory fails; it is not a pass.
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".json") }.sorted()
        try #require(!files.isEmpty, "no structure JSON under \(dir.path)")
        var rows: [String] = []
        // P8b-7: the default-on guards (StructureGuardTests) on every dumped
        // structure, recorded per row and timed, so a version task sees what
        // the guards will say before it commits, and the guard cost per
        // structure at full scale.
        let grammarVersion = try #require(Version(rawValue: version))
        var guardTime = Duration.zero
        var guardFailures = 0
        for file in files {
            // The codegen's acceptance rules (StructureJSONDecoder, P8b-7).
            let id = String(file.dropLast(5))
            let decoded = try StructureJSONDecoder.decode(Data(contentsOf: dir.appendingPathComponent(file)), id: id, version: version)
            let elements = decoded.elements
            let lint = StructureMatcher.lint(elements)
            let result = lint.isDeterministic ? "pass" : "fail: " + lint.conflicts
                .map { "\($0.segmentIDs.joined(separator: ",")) at \($0.path.joined(separator: "/"))" }
                .joined(separator: "; ")
            let shapes = lint.isDeterministic ? "-" : Array(Set(lint.conflicts.map { Self.shape(elements, $0) })).sorted()
                .joined(separator: "; ")
            let sequences = StructureMatcherPropertyTests.sequences(elements)
            // P8b-7: a minimum per structure: the full enumeration for an
            // alphabet of at most four IDs, else at least 1,000 sequences.
            let letters = StructureMatcherPropertyTests.alphabet(elements).filter { $0 != "MSH" }
            let minimum = letters.count <= 4 ? StructureMatcherPropertyTests.exhaustive(letters, upTo: 8).count : 1_000
            #expect(sequences.count >= minimum, "\(version) \(id): \(sequences.count) sequences checked, minimum \(minimum)")
            let structure = decoded
            let matcher = StructureMatcher(structure: structure)
            let exact = ExactStructureMatcher(structure: structure)
            var disagree = 0, exactDisagree = 0
            for sequence in sequences {
                let accepted = StructureMatcherPropertyTests.referenceAccepts(elements, sequence)
                if matcher.match(sequence).findings.isEmpty != accepted { disagree += 1 }
                if exact.match(sequence).findings.isEmpty != accepted { exactDisagree += 1 }
            }
            // P8b-12: the exact matcher (the Validator's choice when the lint fails) must never disagree.
            #expect(exactDisagree == 0, "\(version) \(id): exact matcher disagrees on \(exactDisagree)")
            #expect(structure.requiresExactMatch == !lint.isDeterministic)
            var guarded: (problems: [String], sequences: Int) = ([], 0)
            guardTime += ContinuousClock().measure {
                guarded = StructureGuardTests.guardStructure(structure, version: grammarVersion, derivations: StructureGuardTests.defaultDerivations)
            }
            if !guarded.problems.isEmpty { guardFailures += 1 }
            rows.append([version, id, result, shapes, "\(sequences.count) checked, \(disagree) disagree",
                         Self.dsc(elements), "exact: \(exactDisagree) disagree",
                         guarded.problems.isEmpty ? "guards: ok" : "guards: " + guarded.problems.joined(separator: "; ")].joined(separator: "\t"))
            print("lint-progress \(version) \(id) \(rows.count)/\(files.count)")
        }
        print("structure-guard-corpus v\(version): \(files.count) structures, \(guardFailures) failing a guard, guards took \(guardTime)")
        let out = URL(fileURLWithPath: env["STRUCTURE_LINT_OUT"] ?? root.path).appendingPathComponent("lint-\(version).tsv")
        try (rows.joined(separator: "\n") + "\n").write(to: out, atomically: true, encoding: .utf8)
    }
}
