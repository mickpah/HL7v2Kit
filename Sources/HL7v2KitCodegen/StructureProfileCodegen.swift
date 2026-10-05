// StructureProfileCodegen.swift
// P8b-4 (ADR-019 "HL7au:00060.1", ruling G9): decode the constrained structures a
// localisation profile prints, Resources/structures/profiles/<profile>/<STRUCT>.json, and
// emit Sources/HL7v2Kit/Structures/Generated/MessageStructureTable+<PROFILE>.swift with
// `static let <profile>: [String: MessageStructure]` (au-adrm-2021: auADRM2021). A profile
// file is a structure file plus three required keys, accepted only here: `profile` (the
// directory name), `baseVersion` (the version whose structure it constrains, equal to
// `version`) and `rule` (the conformance point it enforces). The constrained structure must
// constrain a loaded base structure of the same ID, and print only triggers that base
// structure prints, so the Validator applies it only where the base structure resolves.

import Foundation

/// The Swift names for profile `name` (`au-adrm-2021`): the table constant (`auADRM2021`)
/// and the file suffix (`AUADRM2021`).
func profileSwiftNames(_ name: String) -> (constant: String, file: String) {
    let parts = name.split(separator: "-").map(String.init)
    let constant = (parts.first ?? "") + parts.dropFirst().map { $0.uppercased() }.joined()
    return (constant, parts.map { $0.uppercased() }.joined())
}

/// Check a decoded profile file against its directory and the base it constrains.
/// `overrideNames` holds the overrides.json `groupNames` entries as "version|structure|name": a
/// group or choice named through nameSource `override` must be one of the base structure's (P8b-18).
func validateProfileStructure(_ s: MessageStructureSchema, file: URL, profile: String,
                              base: [String: [String: MessageStructureSchema]],
                              overrideNames: Set<String>) throws {
    guard let tag = s.profile, let baseVersion = s.baseVersion, let rule = s.rule else {
        throw StructureSchemaError(description: "a profile structure needs \"profile\", \"baseVersion\" and \"rule\"")
    }
    guard tag == profile else {
        throw StructureSchemaError(description: "profile \"\(tag)\" does not match its directory \(profile)")
    }
    guard baseVersion == s.version else {
        throw StructureSchemaError(description: "baseVersion \(baseVersion) differs from version \(s.version)")
    }
    guard rule.range(of: "^[A-Za-z0-9]+:[0-9]+(\\.[0-9]+)*$", options: .regularExpression) != nil else {
        throw StructureSchemaError(description: "bad rule \"\(rule)\"")
    }
    try validateStructure(s, file: file, version: baseVersion)
    guard let constrained = base[baseVersion]?[s.structure] else {
        throw StructureSchemaError(description: "no base v\(baseVersion) structure \(s.structure) to constrain")
    }
    let extra = Set(s.triggers).subtracting(constrained.triggers).sorted()
    guard extra.isEmpty else {
        throw StructureSchemaError(description: "triggers \(extra) are not printed for the base v\(baseVersion) \(s.structure)")
    }
    try validateProfileOverrideNames(s.elements, version: baseVersion, structure: s.structure, overrideNames: overrideNames)
}

/// A name taken through nameSource `override` in a profile file is the base structure's: an
/// overrides.json groupNames entry of the same version and structure ID names it. A citation
/// that merely mentions "overrides.json" is not enough (P8b-18).
private func validateProfileOverrideNames(_ elements: [StructureElementSchema], version: String, structure: String,
                                          overrideNames: Set<String>) throws {
    for element in elements {
        if element.nameSource == "override", let name = element.group ?? element.choice,
           !overrideNames.contains("\(version)|\(structure)|\(name)") {
            let kind = element.group != nil ? "group" : "choice"
            throw StructureSchemaError(description: "\(kind) \(name) (nameSource override) names no overrides.json "
                + "groupNames entry of the base v\(version) \(structure)")
        }
        try validateProfileOverrideNames((element.elements ?? []) + (element.alternatives ?? []), version: version,
                                         structure: structure, overrideNames: overrideNames)
    }
}

/// The overrides.json `groupNames` entries as "version|structure|name"; an absent file or key
/// gives none.
func overrideGroupNames(in root: URL) throws -> Set<String> {
    let url = root.appendingPathComponent(structureOverridesFileName)
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    guard let entries = (object as? [String: Any])?["groupNames"] as? [[String: Any]] else { return [] }
    var out: Set<String> = []
    for entry in entries {
        guard let version = entry["version"] as? String, let structure = entry["structure"] as? String,
              let name = entry["name"] as? String else {
            throw StructureSchemaError(description: "\(url.path): a groupNames entry needs version, structure and name")
        }
        out.insert("\(version)|\(structure)|\(name)")
    }
    return out
}

/// Render one table per directory under `<root>/profiles` (absent: none). The directory
/// holds only profile directories named in lower case with hyphens (hidden entries aside).
func renderProfileStructureTables(from root: URL, to outputRoot: URL,
                                  base: [String: [String: MessageStructureSchema]]) throws -> [(file: URL, source: String)] {
    let fm = FileManager.default
    let profilesRoot = root.appendingPathComponent(structureProfilesDirectoryName)
    guard fm.fileExists(atPath: profilesRoot.path) else { return [] }
    var rendered: [(file: URL, source: String)] = []
    let overrideNames: Set<String>
    do {
        overrideNames = try overrideGroupNames(in: root)
    } catch {
        FileHandle.standardError.write(Data("HL7v2KitCodegen: \(error)\n".utf8))
        throw ExitCode.failure
    }
    let entries = try fm.contentsOfDirectory(at: profilesRoot, includingPropertiesForKeys: [.isDirectoryKey])
        .filter { !$0.lastPathComponent.hasPrefix(".") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    for dirURL in entries {
        let profile = dirURL.lastPathComponent
        let isDirectory = (try? dirURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        guard isDirectory, profile.range(of: "^[a-z][a-z0-9]*(-[a-z0-9]+)*$", options: .regularExpression) != nil else {
            FileHandle.standardError.write(Data("HL7v2KitCodegen: \(dirURL.path): unexpected entry; \(structureProfilesDirectoryName)/ holds only profile directories (lower case, hyphenated)\n".utf8))
            throw ExitCode.failure
        }
        let decoder = JSONDecoder()
        decoder.userInfo[structureProfileKeysAllowed] = true
        var structures: [MessageStructureSchema] = []
        let files = try fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for fileURL in files {
            do {
                let s = try decoder.decode(MessageStructureSchema.self, from: Data(contentsOf: fileURL))
                try validateProfileStructure(s, file: fileURL, profile: profile, base: base, overrideNames: overrideNames)
                structures.append(s)
            } catch {
                FileHandle.standardError.write(Data("HL7v2KitCodegen: \(fileURL.path): \(error)\n".utf8))
                throw ExitCode.failure
            }
        }
        let names = profileSwiftNames(profile)
        rendered.append((outputRoot.appendingPathComponent("MessageStructureTable+\(names.file).swift"),
                         renderStructureTable(versionSwiftName: names.constant,
                                              sourceDir: "\(structureProfilesDirectoryName)/\(profile)",
                                              structures: structures)))
        print("rendered \(names.constant) (\(structures.count) structure(s))")
    }
    return rendered
}
