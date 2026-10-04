// StructureLintCorpusTests.swift
// P8b-3b measurement for the G1 decision: run every structure the extractor
// parses (`extract-message-structures.py --dump DIR`, choices included from
// P8b-6) through the ADR-019 determinism lint and the reference-recogniser
// property comparison, without committing any structure JSON. Reads
// STRUCTURE_LINT_CORPUS/v<ver>/<ID>.json and writes lint-<ver>.tsv into the
// directory STRUCTURE_LINT_OUT (default: the corpus directory), one row per
// structure: version, structure, lint result, shape class, recogniser
// agreement, DSC placement, exact-matcher agreement (P8b-12). Skipped
// unless STRUCTURE_LINT_CORPUS is set.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Structure lint corpus", .enabled(if: ProcessInfo.processInfo.environment["STRUCTURE_LINT_CORPUS"] != nil,
                                         "Set STRUCTURE_LINT_CORPUS to an extractor --dump directory"))
struct StructureLintCorpusTests {
    enum DecodeError: Error { case shape(String) }

    /// The element tree of one extractor JSON file (the shape the codegen reads).
    static func elements(_ json: Any) throws -> [StructureElement] {
        guard let list = json as? [[String: Any]] else { throw DecodeError.shape("elements is not a list") }
        return try list.map { item in
            let min = item["min"] as? Int ?? 1
            let max = item["max"] as? Int
            if let id = item["segment"] as? String { return .segment(id, min: min, max: max) }
            if item.keys.contains("choice"), let alternatives = item["alternatives"] {
                return .choice(item["choice"] as? String, min: min, max: max, alternatives: try elements(alternatives))
            }
            guard let name = item["group"] as? String, let children = item["elements"] else {
                throw DecodeError.shape("neither segment nor group: \(item)")
            }
            return .group(name, min: min, max: max, elements: try elements(children))
        }
    }

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
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var rows: [String] = []
        for file in files.filter({ $0.hasSuffix(".json") }).sorted() {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent(file)))
            let json = try #require(object as? [String: Any])
            let id = try #require(json["structure"] as? String)
            let elements = try Self.elements(json["elements"] as Any)
            let lint = StructureMatcher.lint(elements)
            let result = lint.isDeterministic ? "pass" : "fail: " + lint.conflicts
                .map { "\($0.segmentIDs.joined(separator: ",")) at \($0.path.joined(separator: "/"))" }
                .joined(separator: "; ")
            let shapes = lint.isDeterministic ? "-" : Array(Set(lint.conflicts.map { Self.shape(elements, $0) })).sorted()
                .joined(separator: "; ")
            let sequences = StructureMatcherPropertyTests.sequences(elements)
            let structure = MessageStructure(id: id, version: version, triggers: [], citation: "corpus", elements: elements)
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
            rows.append([version, id, result, shapes, "\(sequences.count) checked, \(disagree) disagree",
                         Self.dsc(elements), "exact: \(exactDisagree) disagree"].joined(separator: "\t"))
            print("lint-progress \(version) \(id) \(rows.count)/\(files.count)")
        }
        let out = URL(fileURLWithPath: env["STRUCTURE_LINT_OUT"] ?? root.path).appendingPathComponent("lint-\(version).tsv")
        try (rows.joined(separator: "\n") + "\n").write(to: out, atomically: true, encoding: .utf8)
    }
}
