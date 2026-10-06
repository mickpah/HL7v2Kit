// StructureMatcherCorpusTests.swift
// P8-4 measurement (project requirement 4): run the structure matcher over
// every spec example (SPEC_EXAMPLE_MESSAGES, optional) and every parseable
// fixture whose v2.5.1 structure is a modelled pilot structure, and write one
// line per finding to STRUCTURE_MATCH_OUT for classification. It calls the
// matcher directly; production use is through the Validator when
// ValidationOptions.messageStructureSeverity is set (P8-5). Skipped unless
// STRUCTURE_MATCH_OUT is set.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Structure matcher corpus", .enabled(if: ProcessInfo.processInfo.environment["STRUCTURE_MATCH_OUT"] != nil,
                                            "Set STRUCTURE_MATCH_OUT to the findings path"))
struct StructureMatcherCorpusTests {
    struct Example: Decodable { let source: String; let index: Int; let segments: [String]; let mshVersionElided: Bool }

    /// One message to match. `chapter` is the version of the chapters that
    /// print an example (`v2.5.1`); nil for a fixture.
    struct Wire { let name: String; let text: String; let chapter: String?; let elided: Bool }

    /// In scope for the v2.5.1 pilot: MSH-12 reads 2.5.1 on the wire, or the
    /// print elides or omits MSH-12 and the example is printed in the v2.5.1
    /// chapters.
    private func isV251(_ message: Message, _ wire: Wire) -> Bool {
        let reading = message["MSH-12.1"] ?? ""
        if let chapter = wire.chapter, wire.elided || reading.isEmpty { return chapter == "v2.5.1" }
        return reading == "2.5.1"
    }

    /// MSH-9.3 when it names a modelled structure, else the structure whose
    /// caption lines print MSH-9.1^9.2.
    private func resolve(_ message: Message) -> MessageStructure? {
        if let id = message.messageStructure, !id.isEmpty {
            return MessageStructureTable.structure(id, version: .v2_5_1)
        }
        // An unprinted trigger (`ACK` alone) still resolves through `ACK^*`.
        guard let code = message.messageCode else { return nil }
        return MessageStructureTable.structures(messageCode: code, triggerEvent: message.triggerEvent ?? "", version: .v2_5_1).first
    }

    @Test("Corpus: every finding on the spec examples and fixtures that resolve to a pilot structure")
    func corpus() throws {
        let env = ProcessInfo.processInfo.environment
        var wires: [Wire] = []
        if let path = env["SPEC_EXAMPLE_MESSAGES"] {
            let examples = try JSONDecoder().decode([Example].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            wires += examples.map {
                Wire(name: "\($0.source)#\($0.index)", text: $0.segments.joined(separator: "\r") + "\r", chapter: String($0.source.prefix { $0 != "/" }),
                     elided: $0.mshVersionElided)
            }
        }
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures")
        let files = (FileManager.default.enumerator(atPath: dir.path)?.allObjects as? [String] ?? [])
            .filter { $0.hasSuffix(".hl7") }.sorted()
        for file in files {
            let text = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
            wires.append(Wire(name: file, text: text.replacingOccurrences(of: "\n", with: "\r"), chapter: nil, elided: false))
        }
        var lines: [String] = []
        var matched = (examples: 0, fixtures: 0)
        for wire in wires {
            let name = wire.name
            guard let message = try? Parser().parse(wire.text), isV251(message, wire),
                  let structure = resolve(message) else { continue }
            let ids = message.segments.map(\.segmentID)
            let fragment = !(message["MSH-14"] ?? "").isEmpty
                || (ids.last == "DSC" && structure.elements.last != .segment("DSC", min: 0, max: 1))
            if fragment {
                lines.append("\(name)\t\(structure.id)\tFRAGMENT")
                continue
            }
            if wire.chapter != nil { matched.examples += 1 } else { matched.fixtures += 1 }
            let grammar = Validator.grammarTable(for: .v2_5_1)
            let outside = Set(ids.filter { grammar[$0] == nil })
            // S3-3 (ruling 3): an exact-matched structure (a slot structure among them) is
            // matched as the Validator matches it; the one-pass matcher never compiles one.
            let result = structure.requiresExactMatch
                ? ExactStructureMatcher(structure: structure).match(ids, transparent: outside)
                : StructureMatcher(structure: structure).match(ids, transparent: outside)
            if result.findings.isEmpty { lines.append("\(name)\t\(structure.id)\tconforms") }
            for finding in result.findings {
                lines.append("\(name)\t\(structure.id)\t\(finding.kind)\t\(finding.segmentID)\t\(finding.group ?? "-")\t\(finding.index)")
            }
        }
        lines.insert("# matched \(matched.examples) spec examples and \(matched.fixtures) fixtures", at: 0)
        let out = try #require(env["STRUCTURE_MATCH_OUT"])
        try lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
    }
}
