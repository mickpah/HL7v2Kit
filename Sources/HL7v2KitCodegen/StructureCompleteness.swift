// StructureCompleteness.swift
// P8b-1 (ADR-019 lookup rule 1, rollout step 4): decode
// Resources/structures/completeness.json and render the generated
// version-to-table switch and completeness set,
// Sources/HL7v2Kit/Structures/Generated/MessageStructureTable+Versions.swift.

import Foundation

/// The file name of the completeness data under the structures root. It does
/// not start with `v`, so it can never be read as a version directory
/// (pre-flight B5).
let structureCompletenessFileName = "completeness.json"

/// The extractor's override file (scripts/extract-message-structures.py,
/// P8b-2a) under the structures root. The codegen skips it.
let structureOverridesFileName = "overrides.json"

/// The AU profile structures directory under the structures root (ruling G9).
/// The codegen skips it.
let structureProfilesDirectoryName = "profiles"

/// One version's entry: whether every structure the version prints is
/// modelled, and the citation for that claim.
struct StructureCompletenessEntry: Decodable {
    let complete: Bool
    let citation: String

    private enum CodingKeys: String, CodingKey, CaseIterable { case complete, citation }

    init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)), in: "completeness entry")
        let c = try decoder.container(keyedBy: CodingKeys.self)
        complete = try c.decode(Bool.self, forKey: .complete)
        citation = try c.decode(String.self, forKey: .citation)
    }
}

/// The whole completeness file: `{ "versions": { "<version>": entry } }`.
struct StructureCompleteness: Decodable {
    let versions: [String: StructureCompletenessEntry]

    private enum CodingKeys: String, CodingKey, CaseIterable { case versions }

    init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)), in: "completeness file")
        versions = try decoder.container(keyedBy: CodingKeys.self).decode([String: StructureCompletenessEntry].self, forKey: .versions)
    }
}

/// Check the completeness data against the modelled versions (the schema
/// version directories) and the structure directories present.
/// - Every modelled version is listed, and nothing else is.
/// - Every structure directory's version is listed.
/// - Every citation is one non-empty line.
/// - A version marked complete has at least one structure.
func validateCompleteness(_ data: StructureCompleteness, modelledVersions: Set<String>,
                          structureCounts: [String: Int]) throws {
    let listed = Set(data.versions.keys)
    let missing = modelledVersions.subtracting(listed).sorted()
    let extra = listed.subtracting(modelledVersions).sorted()
    guard missing.isEmpty, extra.isEmpty else {
        throw StructureSchemaError(description: "versions must equal the modelled set \(modelledVersions.sorted(by: versionPrecedes)); "
            + "missing \(missing), not modelled \(extra)")
    }
    let unlisted = Set(structureCounts.keys).subtracting(listed).sorted()
    guard unlisted.isEmpty else {
        throw StructureSchemaError(description: "structure directories for unlisted versions \(unlisted)")
    }
    for (version, entry) in data.versions.sorted(by: { versionPrecedes($0.key, $1.key) }) {
        guard !entry.citation.trimmingCharacters(in: .whitespaces).isEmpty,
              !entry.citation.contains(where: \.isNewline) else {
            throw StructureSchemaError(description: "version \(version): the citation must be one non-empty line")
        }
        guard !entry.complete || (structureCounts[version] ?? 0) > 0 else {
            throw StructureSchemaError(description: "version \(version) is marked complete but has no structures")
        }
    }
}

/// Numeric version order: 2.3 < 2.3.1 < 2.4 < ... < 2.8.2.
func versionPrecedes(_ a: String, _ b: String) -> Bool {
    let x = a.split(separator: ".").map { Int($0) ?? 0 }
    let y = b.split(separator: ".").map { Int($0) ?? 0 }
    return x.lexicographicallyPrecedes(y)
}

/// Render the version switch and the completeness set. Every listed version
/// gets an explicit case; a substituted version (`Version.v2_8`) is resolved
/// through `grammarVersion` before the switch, so its table is never
/// duplicated.
func renderStructureVersions(_ data: StructureCompleteness, structureCounts: [String: Int]) -> String {
    let versions = data.versions.keys.sorted(by: versionPrecedes)
    let width = versions.map { versionDirName($0).count }.max() ?? 0
    let cases = versions.map { version -> String in
        let name = versionDirName(version)
        let pad = String(repeating: " ", count: width - name.count)
        let table = (structureCounts[version] ?? 0) > 0 ? name : "[:]"
        return "        case .\(name):\(pad) return \(table)"
    }.joined(separator: "\n")
    let complete = versions.filter { data.versions[$0]?.complete == true }.map { ".\(versionDirName($0))" }
    let citations = versions.map { version -> String in
        let entry = data.versions[version]
        let state = entry?.complete == true ? "complete" : "incomplete"
        return "    //   \(version) (\(state)): \(entry?.citation ?? "")"
    }.joined(separator: "\n")
    return """
    \(generatedHeader)
    // Source: Resources/structures/\(structureCompletenessFileName) and the v<version> directories
    // Regenerate via scripts/regenerate-typed-segments.sh

    extension MessageStructureTable {
        // Completeness per grammar version (ADR-019 lookup rule 1):
    \(citations)

        /// Every modelled structure of `version`'s grammar version, keyed by
        /// ID. A version with no structures modelled returns an empty table.
        static func generatedStructures(for version: Version) -> [String: MessageStructure] {
            switch version.grammarVersion {
    \(cases)
            // Only a grammar version missing from completeness.json reaches
            // here, and the codegen rejects that: not modelled.
            default: return [:]
            }
        }

        /// The grammar versions whose every printed structure is modelled.
        static let completeVersions: Set<Version> = [\(complete.joined(separator: ", "))]
    }

    """
}
