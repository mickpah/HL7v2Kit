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
        let isSlot: Bool, slot: String?, citation: String?
        let min: Int, max: Int?
        let elements: [Element]?, alternatives: [Element]?
        let key: Key?

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case segment, group, choice, slot, nameSource, min, max, elements, alternatives, citation, key
        }

        init(from decoder: any Decoder) throws {
            try rejectUnknownKeys(decoder, Set(CodingKeys.allCases.map(\.rawValue)), "element")
            let c = try decoder.container(keyedBy: CodingKeys.self)
            segment = try c.decodeIfPresent(String.self, forKey: .segment)
            group = try c.decodeIfPresent(String.self, forKey: .group)
            isChoice = c.contains(.choice)
            choice = try isChoice && !c.decodeNil(forKey: .choice) ? c.decode(String.self, forKey: .choice) : nil
            isSlot = c.contains(.slot)
            slot = try isSlot && !c.decodeNil(forKey: .slot) ? c.decode(String.self, forKey: .slot) : nil
            citation = try c.decodeIfPresent(String.self, forKey: .citation)
            nameSource = try c.decodeIfPresent(String.self, forKey: .nameSource)
            min = try c.decode(Int.self, forKey: .min)
            guard c.contains(.max) else { throw Rejected(description: "element: missing key \"max\"") }
            max = try c.decodeNil(forKey: .max) ? nil : c.decode(Int.self, forKey: .max)
            elements = try c.decodeIfPresent([Element].self, forKey: .elements)
            alternatives = try c.decodeIfPresent([Element].self, forKey: .alternatives)
            key = try c.decodeIfPresent(Key.self, forKey: .key)
        }

        var model: StructureElement {
            if let id = segment { return .segment(id, min: min, max: max) }
            if let name = group { return .group(name, min: min, max: max, elements: (elements ?? []).map(\.model)) }
            if isSlot { return .slot(slot, min: min, max: max, citation: citation ?? "") }
            if let key {
                return .keyedChoice(choice, min: min, max: max,
                                    key: StructureChoiceKey(segmentID: key.segment, field: key.field, component: key.component,
                                                            alternatives: key.values, citation: key.citation),
                                    alternatives: (alternatives ?? []).map(\.model))
            }
            return .choice(choice, min: min, max: max, alternatives: (alternatives ?? []).map(\.model))
        }
    }

    /// A keyed choice's key (S4-1), as the codegen's StructureChoiceKeySchema.
    struct Key: Decodable {
        let segment: String, field: Int, component: Int, values: [String: String], citation: String

        private enum CodingKeys: String, CodingKey, CaseIterable { case segment, field, component, values, citation }

        init(from decoder: any Decoder) throws {
            try rejectUnknownKeys(decoder, Set(CodingKeys.allCases.map(\.rawValue)), "key")
            let c = try decoder.container(keyedBy: CodingKeys.self)
            segment = try c.decode(String.self, forKey: .segment)
            field = try c.decode(Int.self, forKey: .field)
            component = try c.decode(Int.self, forKey: .component)
            values = try c.decode([String: String].self, forKey: .values)
            citation = try c.decode(String.self, forKey: .citation)
        }
    }

    /// One structure file. `aliasOf` (S4-2) is checked against its target by the codegen's
    /// directory walk (validateAliases), which this per-file decoder does not mirror.
    struct File: Decodable {
        let structure: String, version: String, citation: String, triggers: [String], elements: [Element]
        let aliasOf: String?
        let errorResponse: ErrorResponse?

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case structure, version, citation, triggers, elements, aliasOf, errorResponse
        }

        init(from decoder: any Decoder) throws {
            try rejectUnknownKeys(decoder, Set(CodingKeys.allCases.map(\.rawValue)), "structure")
            let c = try decoder.container(keyedBy: CodingKeys.self)
            structure = try c.decode(String.self, forKey: .structure)
            version = try c.decode(String.self, forKey: .version)
            citation = try c.decode(String.self, forKey: .citation)
            triggers = try c.decode([String].self, forKey: .triggers)
            elements = try c.decode([Element].self, forKey: .elements)
            aliasOf = try c.decodeIfPresent(String.self, forKey: .aliasOf)
            errorResponse = try c.decodeIfPresent(ErrorResponse.self, forKey: .errorResponse)
        }
    }

    /// A query response's CH05 5.6.5 rule (S4-3).
    struct ErrorResponse: Decodable {
        let acknowledgmentCodes: [String], querySegments: [String], citation: String

        private enum CodingKeys: String, CodingKey, CaseIterable { case acknowledgmentCodes, querySegments, citation }

        init(from decoder: any Decoder) throws {
            try rejectUnknownKeys(decoder, Set(CodingKeys.allCases.map(\.rawValue)), "errorResponse")
            let c = try decoder.container(keyedBy: CodingKeys.self)
            acknowledgmentCodes = try c.decode([String].self, forKey: .acknowledgmentCodes)
            querySegments = try c.decode([String].self, forKey: .querySegments)
            citation = try c.decode(String.self, forKey: .citation)
        }

        var model: StructureErrorResponse {
            StructureErrorResponse(acknowledgmentCodes: acknowledgmentCodes, querySegments: querySegments, citation: citation)
        }
    }

    static let nameSources = ["printed", "override", "v2xml", "v2xml-v2.3.1", "v2xml-v2.4", "synthesised"]

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
        try checkSequence(s.elements, version: s.version, citation: s.citation)
        func keys(_ list: [Element]) -> [Key] {
            list.flatMap { e in (e.key.map { [$0] } ?? []) + keys((e.elements ?? []) + (e.alternatives ?? [])) }
        }
        func ids(_ list: [Element]) -> Set<String> {
            list.reduce(into: Set<String>()) { $0.formUnion($1.segment.map { [$0] } ?? ids(($1.elements ?? []) + ($1.alternatives ?? []))) }
        }
        if let missing = keys(s.elements).map(\.segment).first(where: { !ids(s.elements).contains($0) }) {
            throw Rejected(description: "a keyed choice's key segment \(missing) is not in the structure")
        }
        return MessageStructure(id: s.structure, version: s.version, triggers: s.triggers, citation: s.citation,
                                aliasOf: s.aliasOf, errorResponse: s.errorResponse?.model,
                                elements: s.elements.map(\.model))
    }

    /// One sequence's elements; two slots side by side are rejected (S3-1).
    private static func checkSequence(_ list: [Element], version: String, citation: String, inChoice: Bool = false) throws {
        for (i, e) in list.enumerated() {
            if e.isSlot, i > 0, list[i - 1].isSlot { throw Rejected(description: "two adjacent slots") }
            try check(e, version: version, citation: citation, inChoice: inChoice)
        }
    }

    private static func check(_ e: Element, version: String, citation: String, inChoice: Bool) throws {
        guard [e.segment != nil, e.group != nil, e.isChoice, e.isSlot].filter({ $0 }).count == 1 else {
            throw Rejected(description: "an element needs exactly one of \"segment\", \"group\", \"choice\" or \"slot\"")
        }
        guard e.min >= 0, e.max.map({ $0 >= Swift.max(1, e.min) }) ?? true else {
            throw Rejected(description: "bad occurrence bounds min \(e.min) max \(String(describing: e.max))")
        }
        guard e.isSlot || e.citation == nil else { throw Rejected(description: "only a slot has a \"citation\"") }
        guard e.isChoice || e.key == nil else { throw Rejected(description: "only a choice has a \"key\"") }
        if let name = e.group {
            try checkName(name, kind: "group", source: e.nameSource, version: version, citation: citation)
            guard let children = e.elements, !children.isEmpty, e.alternatives == nil else {
                throw Rejected(description: "group \(name) needs a non-empty \"elements\" and no \"alternatives\"")
            }
            try checkSequence(children, version: version, citation: citation, inChoice: inChoice)
        } else if e.isSlot {
            guard !inChoice else { throw Rejected(description: "a slot cannot be inside a choice") }
            guard let cited = e.citation, !cited.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw Rejected(description: "a slot needs a non-empty \"citation\"")
            }
            if let name = e.slot, name.trimmingCharacters(in: .whitespaces).isEmpty || matches(name, "^[A-Z][A-Z0-9]{2}$") {
                throw Rejected(description: "bad slot name \"\(name)\"")
            }
            guard e.elements == nil, e.alternatives == nil, e.nameSource == nil else {
                throw Rejected(description: "a slot cannot have elements, alternatives or a nameSource")
            }
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
            for alternative in alternatives { try check(alternative, version: version, citation: citation, inChoice: true) }
            if let key = e.key { try checkKey(key, alternatives: alternatives, what: what) }
        } else if let id = e.segment {
            guard matches(id, "^[A-Z][A-Z0-9]{2}$") else { throw Rejected(description: "bad segment ID \"\(id)\"") }
            guard e.elements == nil, e.alternatives == nil, e.nameSource == nil else {
                throw Rejected(description: "segment \(id) cannot have elements, alternatives or a nameSource")
            }
        }
    }

    /// The codegen's validateChoiceKey (S4-1).
    private static func checkKey(_ key: Key, alternatives: [Element], what: String) throws {
        let names = alternatives.compactMap(\.group)
        guard names.count == alternatives.count, Set(names).count == names.count,
              alternatives.allSatisfy({ $0.min == 1 && $0.max == 1 }) else {
            throw Rejected(description: "keyed \(what): every alternative must be a group occurring once, with a distinct name")
        }
        guard matches(key.segment, "^[A-Z][A-Z0-9]{2}$"), key.field >= 1, key.component >= 1 else {
            throw Rejected(description: "keyed \(what): bad key \(key.segment)-\(key.field).\(key.component)")
        }
        guard !key.values.isEmpty, key.values.keys.allSatisfy({ !$0.isEmpty }) else {
            throw Rejected(description: "keyed \(what): the key needs non-empty values")
        }
        let unknown = Set(key.values.values).subtracting(names)
        guard unknown.isEmpty else { throw Rejected(description: "keyed \(what): values map to no alternative: \(unknown.sorted())") }
        let unselected = Set(names).subtracting(key.values.values)
        guard unselected.isEmpty else { throw Rejected(description: "keyed \(what): no value selects \(unselected.sorted())") }
        guard !key.citation.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw Rejected(description: "keyed \(what): the key needs a non-empty \"citation\"")
        }
    }

    private static func checkName(_ name: String, kind: String, source: String?, version: String, citation: String) throws {
        guard matches(name, "^[A-Z][A-Z0-9_]*$") else { throw Rejected(description: "bad \(kind) name \"\(name)\"") }
        guard let source, nameSources.contains(source) else {
            throw Rejected(description: "\(kind) \(name) needs nameSource one of \(nameSources)")
        }
        guard !(source == "v2xml-v2.4" && !["2.3", "2.3.1"].contains(version)), !(source == "v2xml-v2.3.1" && version != "2.3"),
              !(source == "v2xml" && version == "2.3") else {
            throw Rejected(description: "\(kind) \(name): nameSource \(source) on v\(version); v2xml-v2.4 is for v2.3 and v2.3.1 only, v2xml-v2.3.1 for v2.3 only, and v2.3 has no v2xml bundle")
        }
        let marker: String? = switch source {
        case "override": "overrides.json"
        case "v2xml": version == "2.3.1" ? "HL7-xml 2.3.1/" : "HL7-xml v\(version)/"
        case "v2xml-v2.3.1": "HL7-xml 2.3.1/"
        case "v2xml-v2.4": "HL7-xml v2.4/"
        case "synthesised": "synthesised"
        default: nil
        }
        if let marker, !citation.contains("\(name) (\(marker)") {
            throw Rejected(description: "\(kind) \(name) (nameSource \(source)) is not cited: the citation lacks \"\(name) (\(marker)\"")
        }
    }
}
