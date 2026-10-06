// StructureCodegen.swift
// ADR-019: decode Resources/structures/v<version>/<STRUCT>.json, check it
// against the ADR-019 schema (unknown keys are rejected), and emit
// Sources/HL7v2Kit/Structures/Generated/MessageStructureTable+v<X_Y_Z>.swift
// through the shared all-or-nothing writer. One constant per structure keeps
// each expression small for the type checker (the ADR-017 lesson).

import Foundation

/// Any JSON object key, for rejecting keys the schema does not define.
private struct AnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Throws when `decoder`'s object holds a key outside `allowed`.
func rejectUnknownKeys(_ decoder: any Decoder, allowed: Set<String>, in what: String) throws {
    let keys = Set(try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue))
    let unknown = keys.subtracting(allowed).sorted()
    guard unknown.isEmpty else {
        throw StructureSchemaError(description: "\(what): unknown key(s) \(unknown)")
    }
}

/// One element of a structure file: exactly one of `segment`, `group` or `choice`. A choice
/// (P8b-6) is `{"choice": "<name>" or null, "nameSource" (named only), "min", "max",
/// "alternatives": [...]}`; the `choice` key is present even when the print gives no name. An
/// open slot (S3-1) is `{"slot": "<printed name>" or null, "min", "max", "citation"}`; the
/// `slot` key is present even when the print gives no name, and `citation` (required, and
/// allowed on a slot only) says where the slot is printed and what makes it open. A keyed
/// choice (S4-1) is a choice with a `key`: `{"segment", "field", "component", "values":
/// {value: alternative group name}, "citation"}`.
struct StructureElementSchema: Decodable, Equatable {
    let segment: String?
    let group: String?
    /// True when the `choice` key is present (its value may be null).
    let isChoice: Bool
    /// The printed choice name, or nil for an unnamed choice.
    let choice: String?
    /// True when the `slot` key is present (its value may be null).
    let isSlot: Bool
    /// The printed slot name, or nil.
    let slot: String?
    /// A slot's citation; nil on every other element.
    let citation: String?
    /// One of `structureNameSources`; required on a group and a named choice (ADR-019 data model).
    let nameSource: String?
    let min: Int
    let max: Int?
    let elements: [StructureElementSchema]?
    let alternatives: [StructureElementSchema]?
    /// A keyed choice's key (S4-1); nil on every other element.
    let key: StructureChoiceKeySchema?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case segment, group, choice, slot, nameSource, min, max, elements, alternatives, citation, key
    }

    init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)), in: "element")
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
        // `max` is required: an integer, or null for unbounded.
        guard c.contains(.max) else { throw StructureSchemaError(description: "element: missing key \"max\"") }
        max = try c.decodeNil(forKey: .max) ? nil : c.decode(Int.self, forKey: .max)
        elements = try c.decodeIfPresent([StructureElementSchema].self, forKey: .elements)
        alternatives = try c.decodeIfPresent([StructureElementSchema].self, forKey: .alternatives)
        key = try c.decodeIfPresent(StructureChoiceKeySchema.self, forKey: .key)
    }
}

/// A keyed choice's key (S4-1): the field whose value selects the alternative, and the printed
/// map from each value to an alternative's group name, with where the print gives it.
struct StructureChoiceKeySchema: Decodable, Equatable {
    let segment: String
    let field: Int
    let component: Int
    let values: [String: String]
    let citation: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case segment, field, component, values, citation
    }

    init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)), in: "key")
        let c = try decoder.container(keyedBy: CodingKeys.self)
        segment = try c.decode(String.self, forKey: .segment)
        field = try c.decode(Int.self, forKey: .field)
        component = try c.decode(Int.self, forKey: .component)
        values = try c.decode([String: String].self, forKey: .values)
        citation = try c.decode(String.self, forKey: .citation)
    }
}

/// One structure file. The profile keys (`profile`, `baseVersion`, `rule`; ADR-019 data
/// model) are accepted only when the decoder's `userInfo` carries
/// `structureProfileKeysAllowed`, which the codegen sets for files under the profiles
/// directory alone (P8b-4, ruling G9); in a version file they are unknown keys.
struct MessageStructureSchema: Decodable {
    let structure: String
    let version: String
    let citation: String
    let triggers: [String]
    let elements: [StructureElementSchema]
    let profile: String?
    let baseVersion: String?
    let rule: String?
    /// The structure of the same version whose syntax this one takes (S4-2); its elements
    /// must equal the target's.
    let aliasOf: String?
    /// The CH05 5.6.5 query error response rule of a query response (S4-3).
    let errorResponse: ErrorResponseSchema?
    /// `"prose"` when the syntax is a hand transcription of the print's prose (S5-1,
    /// `overrides.json` proseFragments); checked, never rendered.
    let syntaxSource: String?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case structure, version, citation, triggers, elements, profile, baseVersion, rule, aliasOf, errorResponse,
             syntaxSource
    }

    private static let profileKeys: Set<CodingKeys> = [.profile, .baseVersion, .rule]

    init(from decoder: any Decoder) throws {
        let profileFile = decoder.userInfo[structureProfileKeysAllowed] as? Bool == true
        let allowed = CodingKeys.allCases.filter { profileFile || !Self.profileKeys.contains($0) }
        try rejectUnknownKeys(decoder, allowed: Set(allowed.map(\.rawValue)), in: "structure")
        let c = try decoder.container(keyedBy: CodingKeys.self)
        structure = try c.decode(String.self, forKey: .structure)
        version = try c.decode(String.self, forKey: .version)
        citation = try c.decode(String.self, forKey: .citation)
        triggers = try c.decode([String].self, forKey: .triggers)
        elements = try c.decode([StructureElementSchema].self, forKey: .elements)
        profile = try c.decodeIfPresent(String.self, forKey: .profile)
        baseVersion = try c.decodeIfPresent(String.self, forKey: .baseVersion)
        rule = try c.decodeIfPresent(String.self, forKey: .rule)
        aliasOf = try c.decodeIfPresent(String.self, forKey: .aliasOf)
        errorResponse = try c.decodeIfPresent(ErrorResponseSchema.self, forKey: .errorResponse)
        syntaxSource = try c.decodeIfPresent(String.self, forKey: .syntaxSource)
    }
}

/// A structure's `errorResponse` (S4-3, CH05 5.6.5): the MSA-1 codes that make the message an
/// error response, the query defining segments the structure prints, the QAK-2 values that with
/// MSA-1 AA make it a no-data response (Situation 3), and the citation.
struct ErrorResponseSchema: Decodable, Equatable {
    // The codes are checked only by the extractor's override check, as distinct two-letter codes;
    // nothing reads them against Table 0008.
    let acknowledgmentCodes: [String]
    let querySegments: [String]
    let noDataQueryStatus: [String]
    let citation: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case acknowledgmentCodes, querySegments, noDataQueryStatus, citation
    }

    init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)), in: "errorResponse")
        let c = try decoder.container(keyedBy: CodingKeys.self)
        acknowledgmentCodes = try c.decode([String].self, forKey: .acknowledgmentCodes)
        querySegments = try c.decode([String].self, forKey: .querySegments)
        noDataQueryStatus = try c.decode([String].self, forKey: .noDataQueryStatus)
        citation = try c.decode(String.self, forKey: .citation)
    }
}

/// The query defining segments an `errorResponse` may name (S4-3).
let errorResponseQuerySegments: Set<String> = ["QRD", "QRF", "QPD", "ERQ"]

/// Check an `errorResponse` against its structure (S4-3): distinct two-letter MSA-1 codes, a
/// top-level MSA, distinct query defining segments the structure prints, and a citation.
func validateErrorResponse(_ rule: ErrorResponseSchema, elements: [StructureElementSchema]) throws {
    guard !rule.acknowledgmentCodes.isEmpty, Set(rule.acknowledgmentCodes).count == rule.acknowledgmentCodes.count,
          rule.acknowledgmentCodes.allSatisfy({ matches($0, "^[A-Z]{2}$") }) else {
        throw StructureSchemaError(description: "errorResponse: acknowledgmentCodes must be distinct two-letter codes")
    }
    guard Set(rule.noDataQueryStatus).count == rule.noDataQueryStatus.count,
          rule.noDataQueryStatus.allSatisfy({ matches($0, "^[A-Z]{2}$") }) else {
        throw StructureSchemaError(description: "errorResponse: noDataQueryStatus must be distinct two-letter values")
    }
    guard elements.contains(where: { $0.segment == "MSA" }) else {
        throw StructureSchemaError(description: "errorResponse: the structure has no top-level MSA")
    }
    let printed = elements.reduce(into: Set<String>()) { $0.formUnion(schemaSegmentIDs([$1])) }
    guard Set(rule.querySegments).count == rule.querySegments.count,
          rule.querySegments.allSatisfy({ errorResponseQuerySegments.contains($0) && printed.contains($0) }) else {
        throw StructureSchemaError(description: "errorResponse: querySegments must be distinct query defining segments the structure prints")
    }
    guard !rule.citation.isEmpty else { throw StructureSchemaError(description: "errorResponse: empty citation") }
}

/// The `JSONDecoder.userInfo` key that admits the profile keys; see `MessageStructureSchema`.
let structureProfileKeysAllowed = CodingUserInfoKey(rawValue: "structureProfileKeysAllowed")!

struct StructureSchemaError: Error, CustomStringConvertible {
    let description: String
}

private func matches(_ value: String, _ pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) != nil
}

/// Accepted group `nameSource` values (ADR-019 decision 3, P8b-2b): printed by the chapter, an
/// `overrides.json` entry, the version's HL7 v2.xml bundle (v2.3.1's folder is `HL7-xml 2.3.1`,
/// P8b-14), the v2.3.1 bundle for v2.3 (P8b-15), the v2.4 bundle for v2.3 and as v2.3.1's
/// fallback, or synthesised as `<FIRSTSEG>_GROUP`.
let structureNameSources = ["printed", "override", "v2xml", "v2xml-v2.3.1", "v2xml-v2.4", "synthesised"]

/// The text a structure citation must contain to cite a group named from a non-printed source
/// (the extractor's `required_citation` is the same rule); nil for `printed`.
func requiredNameCitation(name: String, source: String, version: String) -> String? {
    let marker: String
    switch source {
    case "override": marker = "overrides.json"
    case "v2xml": marker = version == "2.3.1" ? "HL7-xml 2.3.1/" : "HL7-xml v\(version)/"   // the folder as on disk
    case "v2xml-v2.3.1": marker = "HL7-xml 2.3.1/"
    case "v2xml-v2.4": marker = "HL7-xml v2.4/"
    case "synthesised": marker = "synthesised"
    default: return nil
    }
    return "\(name) (\(marker)"
}

/// Reject any element the runtime model cannot represent faithfully. `version` and `citation`
/// are the file's: every non-printed group name must be cited.
/// The elements of one sequence (the structure's, or a group's). Two slots side by side are
/// rejected: nothing printed would tell where one ends and the other begins (S3-1).
func validateStructureSequence(_ elements: [StructureElementSchema], version: String, citation: String,
                               inChoice: Bool = false) throws {
    for (i, element) in elements.enumerated() {
        if element.isSlot, i > 0, elements[i - 1].isSlot {
            throw StructureSchemaError(description: "two adjacent slots")
        }
        try validateStructureElement(element, version: version, citation: citation, inChoice: inChoice)
    }
}

/// One element. `inChoice` is true anywhere inside a choice, where a slot is rejected: the print
/// never puts one there, and `< OBR | etc. >` is itself the slot (OBR one of its fillers).
func validateStructureElement(_ element: StructureElementSchema, version: String, citation: String,
                              inChoice: Bool = false) throws {
    let kinds = [element.segment != nil, element.group != nil, element.isChoice, element.isSlot].filter { $0 }.count
    guard kinds == 1 else {
        throw StructureSchemaError(description: "an element needs exactly one of \"segment\", \"group\", \"choice\" or \"slot\"")
    }
    guard element.min >= 0, element.max.map({ $0 >= Swift.max(1, element.min) }) ?? true else {
        throw StructureSchemaError(description: "bad occurrence bounds min \(element.min) max \(String(describing: element.max))")
    }
    guard element.isSlot || element.citation == nil else {
        throw StructureSchemaError(description: "only a slot has a \"citation\"")
    }
    guard element.isChoice || element.key == nil else {
        throw StructureSchemaError(description: "only a choice has a \"key\"")
    }
    if let name = element.group {
        try validateName(name, kind: "group", source: element.nameSource, version: version, citation: citation)
        guard let children = element.elements, !children.isEmpty, element.alternatives == nil else {
            throw StructureSchemaError(description: "group \(name) needs a non-empty \"elements\" and no \"alternatives\"")
        }
        try validateStructureSequence(children, version: version, citation: citation, inChoice: inChoice)
    } else if element.isSlot {
        guard !inChoice else { throw StructureSchemaError(description: "a slot cannot be inside a choice") }
        guard let cited = element.citation, !cited.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw StructureSchemaError(description: "a slot needs a non-empty \"citation\"")
        }
        // A name shaped like a segment ID would read as one in a finding.
        if let name = element.slot, name.trimmingCharacters(in: .whitespaces).isEmpty || matches(name, "^[A-Z][A-Z0-9]{2}$") {
            throw StructureSchemaError(description: "bad slot name \"\(name)\"")
        }
        guard element.elements == nil, element.alternatives == nil, element.nameSource == nil else {
            throw StructureSchemaError(description: "a slot cannot have elements, alternatives or a nameSource")
        }
    } else if element.isChoice {
        let what = element.choice.map { "choice \($0)" } ?? "unnamed choice"
        if let name = element.choice {
            try validateName(name, kind: "choice", source: element.nameSource, version: version, citation: citation)
        } else if element.nameSource != nil {
            throw StructureSchemaError(description: "an unnamed choice cannot have a nameSource")
        }
        guard let alternatives = element.alternatives, alternatives.count >= 2, element.elements == nil else {
            throw StructureSchemaError(description: "\(what) needs at least two \"alternatives\" and no \"elements\"")
        }
        for alternative in alternatives {
            try validateStructureElement(alternative, version: version, citation: citation, inChoice: true)
        }
        if let key = element.key {
            try validateChoiceKey(key, alternatives: alternatives, what: what)
        }
    } else if let id = element.segment {
        guard matches(id, "^[A-Z][A-Z0-9]{2}$") else {
            throw StructureSchemaError(description: "bad segment ID \"\(id)\"")
        }
        guard element.elements == nil, element.alternatives == nil, element.nameSource == nil else {
            throw StructureSchemaError(description: "segment \(id) cannot have elements, alternatives or a nameSource")
        }
    }
}

/// A keyed choice (S4-1): every alternative a named group occurring once, the names distinct;
/// the key a segment ID, field and component; every value maps to an alternative and every
/// alternative is selected by some value; a non-empty citation.
func validateChoiceKey(_ key: StructureChoiceKeySchema, alternatives: [StructureElementSchema], what: String) throws {
    let names = alternatives.compactMap(\.group)
    guard names.count == alternatives.count, Set(names).count == names.count,
          alternatives.allSatisfy({ $0.min == 1 && $0.max == 1 }) else {
        throw StructureSchemaError(description: "keyed \(what): every alternative must be a group occurring once, with a distinct name")
    }
    guard matches(key.segment, "^[A-Z][A-Z0-9]{2}$"), key.field >= 1, key.component >= 1 else {
        throw StructureSchemaError(description: "keyed \(what): bad key \(key.segment)-\(key.field).\(key.component)")
    }
    guard !key.values.isEmpty, key.values.keys.allSatisfy({ !$0.isEmpty }) else {
        throw StructureSchemaError(description: "keyed \(what): the key needs non-empty values")
    }
    let unknown = Set(key.values.values).subtracting(names)
    guard unknown.isEmpty else {
        throw StructureSchemaError(description: "keyed \(what): values map to no alternative: \(unknown.sorted())")
    }
    let unselected = Set(names).subtracting(key.values.values)
    guard unselected.isEmpty else {
        throw StructureSchemaError(description: "keyed \(what): no value selects \(unselected.sorted())")
    }
    guard !key.citation.trimmingCharacters(in: .whitespaces).isEmpty else {
        throw StructureSchemaError(description: "keyed \(what): the key needs a non-empty \"citation\"")
    }
}

/// The name rules shared by groups and named choices: the pattern, an accepted `nameSource`, the
/// v2.3/v2.3.1 bundle rule, and a citation for every name the print does not give.
private func validateName(_ name: String, kind: String, source: String?, version: String, citation: String) throws {
    guard matches(name, "^[A-Z][A-Z0-9_]*$") else {
        throw StructureSchemaError(description: "bad \(kind) name \"\(name)\"")
    }
    guard let source, structureNameSources.contains(source) else {
        throw StructureSchemaError(description: "\(kind) \(name) needs nameSource one of \(structureNameSources)")
    }
    // v2.3 has no bundle and v2.3.1 falls back to v2.4 (P8b-14): only their names come through
    // v2.4, only v2.3's through the v2.3.1 bundle (P8b-15), and v2.3 has no v2xml.
    guard !(source == "v2xml-v2.4" && !["2.3", "2.3.1"].contains(version)), !(source == "v2xml-v2.3.1" && version != "2.3"),
          !(source == "v2xml" && version == "2.3") else {
        throw StructureSchemaError(description: "\(kind) \(name): nameSource \(source) on v\(version); v2xml-v2.4 is for v2.3 and v2.3.1 only, v2xml-v2.3.1 for v2.3 only, and v2.3 has no v2xml bundle")
    }
    if let needed = requiredNameCitation(name: name, source: source, version: version),
       !citation.contains(needed) {
        throw StructureSchemaError(description: "\(kind) \(name) (nameSource \(source)) is not cited: the citation lacks \"\(needed)\"")
    }
}

/// Check one decoded file against its path and the top-level schema rules.
func validateStructure(_ s: MessageStructureSchema, file: URL, version: String) throws {
    guard s.structure == file.deletingPathExtension().lastPathComponent, s.version == version else {
        throw StructureSchemaError(description: "structure / version do not match the path")
    }
    guard matches(s.structure, "^[A-Z][A-Z0-9]{2}(_[A-Z0-9]{3})?$") else {
        throw StructureSchemaError(description: "bad structure ID \"\(s.structure)\"")
    }
    guard !s.citation.isEmpty else { throw StructureSchemaError(description: "empty citation") }
    let badTriggers = s.triggers.filter { !matches($0, "^[A-Z][A-Z0-9]{2}\\^([A-Z0-9]{3}|\\*)$") }
    guard !s.triggers.isEmpty, badTriggers.isEmpty else {
        throw StructureSchemaError(description: "triggers must be non-empty CODE^EVT or CODE^*; bad: \(badTriggers)")
    }
    guard s.elements.first?.segment == "MSH" else {
        throw StructureSchemaError(description: "a structure must start with MSH")
    }
    try validateStructureSequence(s.elements, version: s.version, citation: s.citation)
    let keySegments = keyedChoiceKeys(s.elements).map(\.segment)
    let named = s.elements.reduce(into: Set<String>()) { $0.formUnion(schemaSegmentIDs([$1])) }
    if let missing = keySegments.first(where: { !named.contains($0) }) {
        throw StructureSchemaError(description: "a keyed choice's key segment \(missing) is not in the structure")
    }
    if let rule = s.errorResponse { try validateErrorResponse(rule, elements: s.elements) }
    if let source = s.syntaxSource {
        // S5-1 (ADR-019 S5): a transcription says so, and its citation names the cited entry.
        guard source == "prose" else { throw StructureSchemaError(description: "syntaxSource must be \"prose\"") }
        guard s.citation.contains("overrides.json proseFragments") else {
            throw StructureSchemaError(description: "syntaxSource prose needs a citation naming \"overrides.json proseFragments\"")
        }
    }
}

/// The aliases of one version (S4-2): each names another structure of the same version that is
/// not itself an alias, and carries exactly its elements (the extractor copies them; a target
/// re-extracted without its alias fails here, never ships stale).
func validateAliases(_ structures: [MessageStructureSchema]) throws {
    let byID = Dictionary(uniqueKeysWithValues: structures.map { ($0.structure, $0) })
    for s in structures {
        guard let target = s.aliasOf else { continue }
        guard target != s.structure, let original = byID[target] else {
            throw StructureSchemaError(description: "\(s.structure): aliasOf \(target) is not another structure of v\(s.version)")
        }
        guard original.aliasOf == nil else {
            throw StructureSchemaError(description: "\(s.structure): aliasOf \(target), which is itself an alias")
        }
        guard original.elements == s.elements else {
            throw StructureSchemaError(description: "\(s.structure): its elements differ from those of \(target), which it aliases")
        }
    }
}

/// Every keyed choice's key in `elements`, at any depth.
func keyedChoiceKeys(_ elements: [StructureElementSchema]) -> [StructureChoiceKeySchema] {
    elements.flatMap { e in (e.key.map { [$0] } ?? []) + keyedChoiceKeys((e.elements ?? []) + (e.alternatives ?? [])) }
}

func renderStructureElement(_ element: StructureElementSchema, indent: String) -> String {
    let max = element.max.map(String.init) ?? "nil"
    if let id = element.segment {
        return "\(indent).segment(\(escapeStringLiteral(id)), min: \(element.min), max: \(max)),"
    }
    if element.isSlot {
        let name = element.slot.map(escapeStringLiteral) ?? "nil"
        return "\(indent).slot(\(name), min: \(element.min), max: \(max), citation: \(escapeStringLiteral(element.citation ?? ""))),"
    }
    if element.isChoice, let key = element.key {
        let name = element.choice.map(escapeStringLiteral) ?? "nil"
        let values = key.values.keys.sorted()
            .map { "\(escapeStringLiteral($0)): \(escapeStringLiteral(key.values[$0] ?? ""))" }.joined(separator: ", ")
        var lines = ["\(indent).keyedChoice(\(name), min: \(element.min), max: \(max), key: StructureChoiceKey(",
                     "\(indent)    segmentID: \(escapeStringLiteral(key.segment)), field: \(key.field), component: \(key.component),",
                     "\(indent)    alternatives: [\(values)],",
                     "\(indent)    citation: \(escapeStringLiteral(key.citation))), alternatives: ["]
        lines += (element.alternatives ?? []).map { renderStructureElement($0, indent: indent + "    ") }
        lines.append("\(indent)]),")
        return lines.joined(separator: "\n")
    }
    if element.isChoice {
        let name = element.choice.map(escapeStringLiteral) ?? "nil"
        var lines = ["\(indent).choice(\(name), min: \(element.min), max: \(max), alternatives: ["]
        lines += (element.alternatives ?? []).map { renderStructureElement($0, indent: indent + "    ") }
        lines.append("\(indent)]),")
        return lines.joined(separator: "\n")
    }
    var lines = ["\(indent).group(\(escapeStringLiteral(element.group ?? "")), min: \(element.min), max: \(max), elements: ["]
    lines += (element.elements ?? []).map { renderStructureElement($0, indent: indent + "    ") }
    lines.append("\(indent)]),")
    return lines.joined(separator: "\n")
}

func renderStructureTable(versionSwiftName: String, sourceDir: String, structures: [MessageStructureSchema]) -> String {
    let sorted = structures.sorted { $0.structure < $1.structure }
    let keys = sorted.map { "        \"\($0.structure)\": \(versionSwiftName)_\($0.structure)," }.joined(separator: "\n")
    let constants = sorted.map { s -> String in
        let triggers = s.triggers.map(escapeStringLiteral).joined(separator: ", ")
        var lines = [
            "    private static let \(versionSwiftName)_\(s.structure): MessageStructure = MessageStructure(",
            "        id: \(escapeStringLiteral(s.structure)),",
            "        version: \(escapeStringLiteral(s.version)),",
            "        triggers: [\(triggers)],",
            "        citation: \(escapeStringLiteral(s.citation)),",
        ]
        // P8b-4: a profile structure carries its profile, base version and rule.
        if let profile = s.profile, let baseVersion = s.baseVersion, let rule = s.rule {
            lines += [
                "        profile: \(escapeStringLiteral(profile)),",
                "        baseVersion: \(escapeStringLiteral(baseVersion)),",
                "        rule: \(escapeStringLiteral(rule)),",
            ]
        }
        lines += [
            // P8b-12: the determinism lint, run here so the Validator never lints a message.
            "        requiresExactMatch: \(!structureIsDeterministic(s.elements)),",
        ]
        // S4-2: an alias names its target; its elements are the target's (checked equal).
        if let target = s.aliasOf { lines.append("        aliasOf: \(escapeStringLiteral(target)),") }
        // S4-3: a query response carries its CH05 5.6.5 error response rule.
        if let rule = s.errorResponse {
            lines += [
                "        errorResponse: StructureErrorResponse(",
                "            acknowledgmentCodes: [\(rule.acknowledgmentCodes.map(escapeStringLiteral).joined(separator: ", "))],",
                "            querySegments: [\(rule.querySegments.map(escapeStringLiteral).joined(separator: ", "))],",
                "            noDataQueryStatus: [\(rule.noDataQueryStatus.map(escapeStringLiteral).joined(separator: ", "))],",
                "            citation: \(escapeStringLiteral(rule.citation))),",
            ]
        }
        lines += [
            "        elements: [",
        ]
        lines += s.elements.map { renderStructureElement($0, indent: "            ") }
        lines += ["        ]", "    )"]
        return lines.joined(separator: "\n")
    }.joined(separator: "\n\n")
    return """
    \(generatedHeader)
    // Source: Resources/structures/\(sourceDir)/*.json
    // Regenerate via scripts/regenerate-typed-segments.sh

    extension MessageStructureTable {
        static let \(versionSwiftName): [String: MessageStructure] = [
    \(keys)
        ]

    \(constants)
    }

    """
}

/// Fail the run with `message` on stderr.
private func structureFailure(_ path: String, _ message: Any) -> ExitCode {
    FileHandle.standardError.write(Data("HL7v2KitCodegen: \(path): \(message)\n".utf8))
    return .failure
}

/// Emit one `MessageStructureTable` extension per `v<version>` directory and
/// the version switch with the completeness set (P8b-1). The input root is
/// required: without it the generated tables would go stale unseen. The root
/// may hold only `completeness.json`, the extractor's `overrides.json`, a
/// `profiles` directory (G9) and `v<digits and dots>` directories (hidden
/// entries aside); anything else fails the run (pre-flight B5).
/// `modelledVersions` is the schema version set, which completeness.json
/// must list exactly. Everything is rendered before anything is written.
/// `grammar` maps each modelled version to the segment IDs its schemas define.
/// A segment some version lists in overrides.json withdrawnSegments may stand in
/// a structure only where the structure's version defines it or lists it, cited
/// (S2-2: the relaxation of guard 3 never leaks to an uncited version; guard 3
/// in full is StructureGuardTests' and the extractor's).
func emitStructureTables(from root: URL, to outputRoot: URL, modelledVersions: Set<String>,
                         grammar: [String: Set<String>]) throws {
    let fm = FileManager.default
    guard fm.fileExists(atPath: root.path) else {
        FileHandle.standardError.write(Data("HL7v2KitCodegen: \(root.path) is missing; it is required (ADR-019 message structures)\n".utf8))
        throw ExitCode.failure
    }
    var dirs: [URL] = []
    for entry in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
        let name = entry.lastPathComponent
        let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        // The extractor's overrides.json (P8b-2a) is read by other tools; the profiles
        // directory (G9) is rendered after the versions, against the base it constrains (P8b-4).
        let skipped = name.hasPrefix(".")
            || (!isDirectory && [structureCompletenessFileName, structureOverridesFileName].contains(name))
            || (isDirectory && name == structureProfilesDirectoryName)
        if skipped { continue }
        guard isDirectory, matches(name, "^v[0-9]+(\\.[0-9]+)*$") else {
            throw structureFailure(entry.path, "unexpected entry; Resources/structures holds only \(structureCompletenessFileName), "
                                   + "\(structureOverridesFileName), \(structureProfilesDirectoryName)/ and v<version> directories")
        }
        dirs.append(entry)
    }
    dirs.sort { $0.lastPathComponent < $1.lastPathComponent }
    let withdrawn: [String: [String: WithdrawnSegmentEntry]]
    do {
        withdrawn = try withdrawnSegments(in: root, grammar: grammar)
    } catch {
        throw structureFailure(root.appendingPathComponent(structureOverridesFileName).path, error)
    }
    let withdrawnIDs = Set(withdrawn.values.flatMap(\.keys))
    var rendered: [(file: URL, source: String)] = []
    var structureCounts: [String: Int] = [:]
    var structureIDs: [String: Set<String>] = [:]
    var owners: [String: [String: Set<String>]] = [:]
    var loaded: [String: [String: MessageStructureSchema]] = [:]
    for dirURL in dirs {
        let version = String(dirURL.lastPathComponent.dropFirst())
        var structures: [MessageStructureSchema] = []
        let files = try fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for fileURL in files {
            do {
                let s = try JSONDecoder().decode(MessageStructureSchema.self, from: Data(contentsOf: fileURL))
                try validateStructure(s, file: fileURL, version: version)
                let uncited = schemaSegmentIDs(s.elements).intersection(withdrawnIDs)
                    .subtracting(grammar[version] ?? []).subtracting((withdrawn[version] ?? [:]).keys)
                guard uncited.isEmpty else {
                    throw StructureSchemaError(description: "withdrawn segments \(uncited.sorted()) that v\(version) "
                        + "neither defines nor lists in overrides.json withdrawnSegments")
                }
                structures.append(s)
            } catch {
                FileHandle.standardError.write(Data("HL7v2KitCodegen: \(fileURL.path): \(error)\n".utf8))
                throw ExitCode.failure
            }
        }
        do {
            try validateAliases(structures)
        } catch {
            FileHandle.standardError.write(Data("HL7v2KitCodegen: \(dirURL.path): \(error)\n".utf8))
            throw ExitCode.failure
        }
        let swiftName = versionDirName(version)
        let outFile = outputRoot.appendingPathComponent("MessageStructureTable+\(swiftName).swift")
        rendered.append((outFile, renderStructureTable(versionSwiftName: swiftName, sourceDir: dirURL.lastPathComponent,
                                                       structures: structures)))
        print("rendered \(swiftName) (\(structures.count) structure(s))")
        structureCounts[version] = structures.count
        structureIDs[version] = Set(structures.map(\.structure))
        loaded[version] = Dictionary(uniqueKeysWithValues: structures.map { ($0.structure, $0) })
        for s in structures {
            for trigger in s.triggers { owners[version, default: [:]][trigger, default: []].insert(s.structure) }
        }
    }
    let completenessURL = root.appendingPathComponent(structureCompletenessFileName)
    let completeness: StructureCompleteness
    do {
        completeness = try JSONDecoder().decode(StructureCompleteness.self, from: Data(contentsOf: completenessURL))
        try validateCompleteness(completeness, modelledVersions: modelledVersions, structureCounts: structureCounts,
                                 structureIDs: structureIDs, misprints: try misprintedTableIDs(in: root))
    } catch {
        throw structureFailure(completenessURL.path, error)
    }
    // P8b-final (F-I1): a printed pair names a loaded structure that does not print the trigger.
    for (version, entry) in completeness.versions {
        for pair in entry.printedPairs where owners[version]?[pair.trigger]?.contains(pair.structure) == true {
            throw structureFailure(completenessURL.path, StructureSchemaError(
                description: "version \(version) printedPairs \(pair.trigger) \(pair.structure): the structure prints that trigger"))
        }
    }
    // ADR-019 lookup rule 2 (P8b-9): a trigger under two structures, loaded or registered as
    // not modelled, is accepted only as a declared shared trigger.
    for (version, entry) in completeness.versions {
        for gap in entry.notModelled {
            for trigger in gap.triggers { owners[version, default: [:]][trigger, default: []].insert(gap.structure) }
        }
    }
    do {
        try validateSharedTriggers(owners: owners, declared: try declaredSharedTriggers(in: root))
    } catch {
        throw structureFailure(root.appendingPathComponent(structureOverridesFileName).path, error)
    }
    rendered += try renderProfileStructureTables(from: root, to: outputRoot, base: loaded)
    rendered.append((outputRoot.appendingPathComponent("MessageStructureTable+Versions.swift"),
                     renderStructureVersions(completeness, structureCounts: structureCounts, withdrawn: withdrawn)))
    try writeGeneratedDirectory(rendered, into: outputRoot)
}

/// Every segment ID named in `elements`, through groups and choices.
func schemaSegmentIDs(_ elements: [StructureElementSchema]) -> Set<String> {
    elements.reduce(into: Set<String>()) { ids, element in
        if let id = element.segment { ids.insert(id) }
        ids.formUnion(schemaSegmentIDs((element.elements ?? []) + (element.alternatives ?? [])))
    }
}
