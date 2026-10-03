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

/// One element of a structure file: exactly one of `segment` or `group`.
struct StructureElementSchema: Decodable {
    let segment: String?
    let group: String?
    /// `printed` or `override`; required on a group (ADR-019 data model).
    let nameSource: String?
    let min: Int
    let max: Int?
    let elements: [StructureElementSchema]?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case segment, group, nameSource, min, max, elements
    }

    init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)), in: "element")
        let c = try decoder.container(keyedBy: CodingKeys.self)
        segment = try c.decodeIfPresent(String.self, forKey: .segment)
        group = try c.decodeIfPresent(String.self, forKey: .group)
        nameSource = try c.decodeIfPresent(String.self, forKey: .nameSource)
        min = try c.decode(Int.self, forKey: .min)
        // `max` is required: an integer, or null for unbounded.
        guard c.contains(.max) else { throw StructureSchemaError(description: "element: missing key \"max\"") }
        max = try c.decodeNil(forKey: .max) ? nil : c.decode(Int.self, forKey: .max)
        elements = try c.decodeIfPresent([StructureElementSchema].self, forKey: .elements)
    }
}

/// One structure file.
struct MessageStructureSchema: Decodable {
    let structure: String
    let version: String
    let citation: String
    let triggers: [String]
    let elements: [StructureElementSchema]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case structure, version, citation, triggers, elements
    }

    init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)), in: "structure")
        let c = try decoder.container(keyedBy: CodingKeys.self)
        structure = try c.decode(String.self, forKey: .structure)
        version = try c.decode(String.self, forKey: .version)
        citation = try c.decode(String.self, forKey: .citation)
        triggers = try c.decode([String].self, forKey: .triggers)
        elements = try c.decode([StructureElementSchema].self, forKey: .elements)
    }
}

struct StructureSchemaError: Error, CustomStringConvertible {
    let description: String
}

private func matches(_ value: String, _ pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) != nil
}

/// Reject any element the runtime model cannot represent faithfully.
func validateStructureElement(_ element: StructureElementSchema) throws {
    let isSegment = element.segment != nil
    let isGroup = element.group != nil
    guard isSegment != isGroup else {
        throw StructureSchemaError(description: "an element needs exactly one of \"segment\" or \"group\"")
    }
    guard element.min >= 0, element.max.map({ $0 >= Swift.max(1, element.min) }) ?? true else {
        throw StructureSchemaError(description: "bad occurrence bounds min \(element.min) max \(String(describing: element.max))")
    }
    if let name = element.group {
        guard matches(name, "^[A-Z][A-Z0-9_]*$") else {
            throw StructureSchemaError(description: "bad group name \"\(name)\"")
        }
        guard let source = element.nameSource, ["printed", "override"].contains(source) else {
            throw StructureSchemaError(description: "group \(name) needs nameSource \"printed\" or \"override\"")
        }
        guard let children = element.elements, !children.isEmpty else {
            throw StructureSchemaError(description: "group \(name) has no elements")
        }
        for child in children { try validateStructureElement(child) }
    } else if let id = element.segment {
        guard matches(id, "^[A-Z][A-Z0-9]{2}$") else {
            throw StructureSchemaError(description: "bad segment ID \"\(id)\"")
        }
        guard element.elements == nil, element.nameSource == nil else {
            throw StructureSchemaError(description: "segment \(id) cannot have elements or a nameSource")
        }
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
    for element in s.elements { try validateStructureElement(element) }
}

func renderStructureElement(_ element: StructureElementSchema, indent: String) -> String {
    let max = element.max.map(String.init) ?? "nil"
    if let id = element.segment {
        return "\(indent).segment(\(escapeStringLiteral(id)), min: \(element.min), max: \(max)),"
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
func emitStructureTables(from root: URL, to outputRoot: URL, modelledVersions: Set<String>) throws {
    let fm = FileManager.default
    guard fm.fileExists(atPath: root.path) else {
        FileHandle.standardError.write(Data("HL7v2KitCodegen: \(root.path) is missing; it is required (ADR-019 message structures)\n".utf8))
        throw ExitCode.failure
    }
    var dirs: [URL] = []
    for entry in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
        let name = entry.lastPathComponent
        let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        // The extractor's overrides.json (P8b-2a) and the AU profiles directory (G9) are read
        // by other tools, not by the codegen.
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
    var rendered: [(file: URL, source: String)] = []
    var structureCounts: [String: Int] = [:]
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
                structures.append(s)
            } catch {
                FileHandle.standardError.write(Data("HL7v2KitCodegen: \(fileURL.path): \(error)\n".utf8))
                throw ExitCode.failure
            }
        }
        let swiftName = versionDirName(version)
        let outFile = outputRoot.appendingPathComponent("MessageStructureTable+\(swiftName).swift")
        rendered.append((outFile, renderStructureTable(versionSwiftName: swiftName, sourceDir: dirURL.lastPathComponent,
                                                       structures: structures)))
        print("rendered \(swiftName) (\(structures.count) structure(s))")
        structureCounts[version] = structures.count
    }
    let completenessURL = root.appendingPathComponent(structureCompletenessFileName)
    let completeness: StructureCompleteness
    do {
        completeness = try JSONDecoder().decode(StructureCompleteness.self, from: Data(contentsOf: completenessURL))
        try validateCompleteness(completeness, modelledVersions: modelledVersions, structureCounts: structureCounts)
    } catch {
        throw structureFailure(completenessURL.path, error)
    }
    rendered.append((outputRoot.appendingPathComponent("MessageStructureTable+Versions.swift"),
                     renderStructureVersions(completeness, structureCounts: structureCounts)))
    try writeGeneratedDirectory(rendered, into: outputRoot)
}
