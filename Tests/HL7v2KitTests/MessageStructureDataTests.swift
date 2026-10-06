// MessageStructureDataTests.swift
// ADR-019 data model: every Resources/structures/v<ver>/<STRUCT>.json keeps the
// schema the ADR describes (no unknown keys, `nameSource` on every group), and
// the generated MessageStructureTable equals the JSON, structure for structure.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Message structure data")
struct MessageStructureDataTests {

    private static let topKeys: Set<String> = ["structure", "version", "citation", "triggers", "elements"]
    private static let segmentKeys: Set<String> = ["segment", "min", "max"]
    private static let groupKeys: Set<String> = ["group", "nameSource", "min", "max", "elements"]
    private static let choiceKeys: Set<String> = ["choice", "min", "max", "alternatives"]

    private static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HL7v2KitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("Resources/structures")
    }

    /// Every structure file, as (version directory, file URL).
    private func files() throws -> [(version: String, url: URL)] {
        let fm = FileManager.default
        return try fm.contentsOfDirectory(atPath: Self.root.path)
            .filter { $0.hasPrefix("v") }.sorted()
            .flatMap { dir in
                try fm.contentsOfDirectory(atPath: Self.root.appendingPathComponent(dir).path)
                    .filter { $0.hasSuffix(".json") }.sorted()
                    .map { (String(dir.dropFirst()), Self.root.appendingPathComponent(dir).appendingPathComponent($0)) }
            }
    }

    /// The element a JSON object describes, recording every schema breach.
    private func element(_ object: [String: Any], at path: String) -> StructureElement? {
        let min = object["min"] as? Int
        let max = object["max"] is NSNull ? nil : object["max"] as? Int
        #expect(min != nil && min! >= 0, "\(path): min")
        #expect(object["max"] is NSNull || (max ?? 0) >= Swift.max(1, min ?? 0), "\(path): max")
        if let id = object["segment"] as? String {
            #expect(Set(object.keys).isSubset(of: Self.segmentKeys), "\(path): keys \(object.keys.sorted())")
            #expect(id.range(of: "^[A-Z][A-Z0-9]{2}$", options: .regularExpression) != nil, "\(path): segment \(id)")
            return .segment(id, min: min ?? 0, max: max)
        }
        // S3-1/S3-3: the open order-detail slot, named or null, always cited, never ID-shaped.
        if object.keys.contains("slot") {
            let name = object["slot"] as? String
            let citation = object["citation"] as? String ?? ""
            #expect(Set(object.keys) == ["slot", "min", "max", "citation"], "\(path): keys \(object.keys.sorted())")
            #expect(object["slot"] is NSNull || name.map { $0.range(of: "^[A-Z][A-Z0-9]{2}$", options: .regularExpression) == nil } == true,
                    "\(path): slot name")
            #expect(!citation.isEmpty, "\(path): slot citation")
            return .slot(name, min: min ?? 0, max: max, citation: citation)
        }
        // P8b-6: a choice, named (with a nameSource) or unnamed (null, no nameSource).
        if object.keys.contains("choice"), let alternatives = object["alternatives"] as? [[String: Any]] {
            let name = object["choice"] as? String
            #expect(Set(object.keys) == Self.choiceKeys.union(name == nil ? [] : ["nameSource"]), "\(path): keys \(object.keys.sorted())")
            #expect(alternatives.count >= 2, "\(path): alternatives")
            let options = alternatives.enumerated().compactMap { element($1, at: "\(path)/<\($0)>") }
            return .choice(name, min: min ?? 0, max: max, alternatives: options)
        }
        guard let name = object["group"] as? String, let children = object["elements"] as? [[String: Any]] else {
            Issue.record("\(path): neither a segment nor a group with elements")
            return nil
        }
        #expect(Set(object.keys) == Self.groupKeys, "\(path): keys \(object.keys.sorted())")
        // ADR-019 decision 3 as amended by P8b-2b and P8b-15: the six accepted name sources.
        #expect(["printed", "override", "v2xml", "v2xml-v2.3.1", "v2xml-v2.4", "synthesised"].contains(object["nameSource"] as? String ?? ""),
                "\(path): nameSource")
        #expect(name.range(of: "^[A-Z][A-Z0-9_]*$", options: .regularExpression) != nil, "\(path): group \(name)")
        #expect(!children.isEmpty, "\(path): empty group")
        let elements = children.enumerated().compactMap { element($1, at: "\(path)/\(name)[\($0)]") }
        return .group(name, min: min ?? 0, max: max, elements: elements)
    }

    @Test("Every structure file keeps the ADR-019 schema and equals its generated entry")
    func filesMatchTable() throws {
        let all = try files()
        #expect(!all.isEmpty)
        var seen: [Version: Set<String>] = [:]
        for (versionName, url) in all {
            let id = url.deletingPathExtension().lastPathComponent
            let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            #expect(Set(object.keys) == Self.topKeys, "\(id): keys \(object.keys.sorted())")
            #expect(object["structure"] as? String == id)
            #expect(object["version"] as? String == versionName)
            let triggers = object["triggers"] as? [String] ?? []
            #expect(!triggers.isEmpty, "\(id): triggers")
            for trigger in triggers {
                #expect(trigger.range(of: "^[A-Z][A-Z0-9]{2}\\^([A-Z0-9]{3}|\\*)$", options: .regularExpression) != nil,
                        "\(id): trigger \(trigger)")
            }
            let raw = object["elements"] as? [[String: Any]] ?? []
            let elements = raw.enumerated().compactMap { element($1, at: "\(id)[\($0)]") }
            #expect(elements.first == .segment("MSH", min: 1, max: 1), "\(id): starts with MSH")
            let version = try #require(Version(rawValue: versionName))
            let generated = try #require(MessageStructureTable.structures(for: version)[id], "\(id) is not generated")
            #expect(generated == MessageStructure(id: id, version: versionName, triggers: triggers,
                                                  citation: object["citation"] as? String ?? "", elements: elements))
            #expect(!generated.citation.isEmpty)
            seen[version, default: []].insert(id)
        }
        // A wire version that shares a grammar (2.8 reads as 2.8.2, ADR-018) serves its files.
        for version in Version.allCases {
            #expect(Set(MessageStructureTable.structures(for: version).keys) == seen[version.grammarVersion] ?? [],
                    "\(version.rawValue): generated structures without a file")
        }
    }
}
