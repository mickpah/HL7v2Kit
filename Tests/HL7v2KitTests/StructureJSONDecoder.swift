// StructureJSONDecoder.swift
// P8b-7: the env-gated corpus tests read extractor dumps through this
// decoder, which applies the codegen's acceptance rules
// (Sources/HL7v2KitCodegen/StructureCodegen.swift: StructureElementSchema,
// MessageStructureSchema, validateStructure, validateStructureElement,
// validateName), so a file the codegen would reject is rejected here too.
// The test target cannot import the codegen executable (Package.swift is
// fixed), so the rules are mirrored, with the codegen's error texts;
// StructureJSONDecoderTests feeds every structure-file case of
// scripts/check-structure-codegen.sh through it and expects the same
// verdict and text. A rule change in the codegen must be mirrored here.

import Foundation
@testable import HL7v2Kit

enum StructureJSONDecoder {
    struct Rejected: Error, CustomStringConvertible { let description: String }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private static func rejectUnknownKeys(_ decoder: any Decoder, _ allowed: Set<String>, _ what: String) throws {
        let unknown = Set(try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)).subtracting(allowed).sorted()
        guard unknown.isEmpty else { throw Rejected(description: "\(what): unknown key(s) \(unknown)") }
    }

    struct Element: Decodable {
        let segment: String?, group: String?, isChoice: Bool, choice: String?, nameSource: String?
        let min: Int, max: Int?
        let elements: [Element]?, alternatives: [Element]?

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case segment, group, choice, nameSource, min, max, elements, alternatives
        }

        init(from decoder: any Decoder) throws {
            try rejectUnknownKeys(decoder, Set(CodingKeys.allCases.map(\.rawValue)), "element")
            let c = try decoder.container(keyedBy: CodingKeys.self)
            segment = try c.decodeIfPresent(String.self, forKey: .segment)
            group = try c.decodeIfPresent(String.self, forKey: .group)
            isChoice = c.contains(.choice)
            choice = try isChoice && !c.decodeNil(forKey: .choice) ? c.decode(String.self, forKey: .choice) : nil
            nameSource = try c.decodeIfPresent(String.self, forKey: .nameSource)
            min = try c.decode(Int.self, forKey: .min)
            guard c.contains(.max) else { throw Rejected(description: "element: missing key \"max\"") }
            max = try c.decodeNil(forKey: .max) ? nil : c.decode(Int.self, forKey: .max)
            elements = try c.decodeIfPresent([Element].self, forKey: .elements)
            alternatives = try c.decodeIfPresent([Element].self, forKey: .alternatives)
        }

        var model: StructureElement {
            if let id = segment { return .segment(id, min: min, max: max) }
            if let name = group { return .group(name, min: min, max: max, elements: (elements ?? []).map(\.model)) }
            return .choice(choice, min: min, max: max, alternatives: (alternatives ?? []).map(\.model))
        }
    }

    struct File: Decodable {
        let structure: String, version: String, citation: String, triggers: [String], elements: [Element]

        private enum CodingKeys: String, CodingKey, CaseIterable { case structure, version, citation, triggers, elements }

        init(from decoder: any Decoder) throws {
            try rejectUnknownKeys(decoder, Set(CodingKeys.allCases.map(\.rawValue)), "structure")
            let c = try decoder.container(keyedBy: CodingKeys.self)
            structure = try c.decode(String.self, forKey: .structure)
            version = try c.decode(String.self, forKey: .version)
            citation = try c.decode(String.self, forKey: .citation)
            triggers = try c.decode([String].self, forKey: .triggers)
            elements = try c.decode([Element].self, forKey: .elements)
        }
    }

    static let nameSources = ["printed", "override", "v2xml", "v2xml-v2.4", "synthesised"]

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    /// Decode and check `data`, the file `id`.json under the `version`
    /// directory; returns the structure as the codegen would emit it.
    static func decode(_ data: Data, id: String, version: String) throws -> MessageStructure {
        let s = try JSONDecoder().decode(File.self, from: data)
        guard s.structure == id, s.version == version else { throw Rejected(description: "structure / version do not match the path") }
        guard matches(s.structure, "^[A-Z][A-Z0-9]{2}(_[A-Z0-9]{3})?$") else { throw Rejected(description: "bad structure ID \"\(s.structure)\"") }
        guard !s.citation.isEmpty else { throw Rejected(description: "empty citation") }
        let badTriggers = s.triggers.filter { !matches($0, "^[A-Z][A-Z0-9]{2}\\^([A-Z0-9]{3}|\\*)$") }
        guard !s.triggers.isEmpty, badTriggers.isEmpty else {
            throw Rejected(description: "triggers must be non-empty CODE^EVT or CODE^*; bad: \(badTriggers)")
        }
        guard s.elements.first?.segment == "MSH" else { throw Rejected(description: "a structure must start with MSH") }
        for element in s.elements { try check(element, version: s.version, citation: s.citation) }
        return MessageStructure(id: s.structure, version: s.version, triggers: s.triggers, citation: s.citation,
                                elements: s.elements.map(\.model))
    }

    private static func check(_ e: Element, version: String, citation: String) throws {
        guard [e.segment != nil, e.group != nil, e.isChoice].filter({ $0 }).count == 1 else {
            throw Rejected(description: "an element needs exactly one of \"segment\", \"group\" or \"choice\"")
        }
        guard e.min >= 0, e.max.map({ $0 >= Swift.max(1, e.min) }) ?? true else {
            throw Rejected(description: "bad occurrence bounds min \(e.min) max \(String(describing: e.max))")
        }
        if let name = e.group {
            try checkName(name, kind: "group", source: e.nameSource, version: version, citation: citation)
            guard let children = e.elements, !children.isEmpty, e.alternatives == nil else {
                throw Rejected(description: "group \(name) needs a non-empty \"elements\" and no \"alternatives\"")
            }
            for child in children { try check(child, version: version, citation: citation) }
        } else if e.isChoice {
            let what = e.choice.map { "choice \($0)" } ?? "unnamed choice"
            if let name = e.choice {
                try checkName(name, kind: "choice", source: e.nameSource, version: version, citation: citation)
            } else if e.nameSource != nil {
                throw Rejected(description: "an unnamed choice cannot have a nameSource")
            }
            guard let alternatives = e.alternatives, alternatives.count >= 2, e.elements == nil else {
                throw Rejected(description: "\(what) needs at least two \"alternatives\" and no \"elements\"")
            }
            for alternative in alternatives { try check(alternative, version: version, citation: citation) }
        } else if let id = e.segment {
            guard matches(id, "^[A-Z][A-Z0-9]{2}$") else { throw Rejected(description: "bad segment ID \"\(id)\"") }
            guard e.elements == nil, e.alternatives == nil, e.nameSource == nil else {
                throw Rejected(description: "segment \(id) cannot have elements, alternatives or a nameSource")
            }
        }
    }

    private static func checkName(_ name: String, kind: String, source: String?, version: String, citation: String) throws {
        guard matches(name, "^[A-Z][A-Z0-9_]*$") else { throw Rejected(description: "bad \(kind) name \"\(name)\"") }
        guard let source, nameSources.contains(source) else {
            throw Rejected(description: "\(kind) \(name) needs nameSource one of \(nameSources)")
        }
        guard !(source == "v2xml-v2.4" && !["2.3", "2.3.1"].contains(version)), !(source == "v2xml" && version == "2.3") else {
            throw Rejected(description: "\(kind) \(name): nameSource \(source) on v\(version); v2xml-v2.4 is for v2.3 and v2.3.1 only, and v2.3 has no v2xml bundle")
        }
        let marker: String? = switch source {
        case "override": "overrides.json"
        case "v2xml": version == "2.3.1" ? "HL7-xml 2.3.1/" : "HL7-xml v\(version)/"
        case "v2xml-v2.4": "HL7-xml v2.4/"
        case "synthesised": "synthesised"
        default: nil
        }
        if let marker, !citation.contains("\(name) (\(marker)") {
            throw Rejected(description: "\(kind) \(name) (nameSource \(source)) is not cited: the citation lacks \"\(name) (\(marker)\"")
        }
    }
}
