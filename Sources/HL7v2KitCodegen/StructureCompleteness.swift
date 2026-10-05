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
/// modelled, the citation for that claim, and the structures registered as
/// not modelled (P8b-9).
struct StructureCompletenessEntry: Decodable {
    let complete: Bool
    let citation: String
    let notModelled: [NotModelledEntry]

    private enum CodingKeys: String, CodingKey, CaseIterable { case complete, citation, notModelled }

    init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)), in: "completeness entry")
        let c = try decoder.container(keyedBy: CodingKeys.self)
        complete = try c.decode(Bool.self, forKey: .complete)
        citation = try c.decode(String.self, forKey: .citation)
        notModelled = try c.decodeIfPresent([NotModelledEntry].self, forKey: .notModelled) ?? []
    }
}

/// A structure the version prints, or its Table 0354 lists, that is not
/// modelled (an unexpandable placeholder, a non-segment row, no printed
/// syntax), with the triggers its captions print and the register reason
/// (P8b-9). A message naming it is reported as not modelled, never as a
/// mismatch, even on a complete version.
struct NotModelledEntry: Decodable {
    let structure: String
    let triggers: [String]
    let reason: String

    private enum CodingKeys: String, CodingKey, CaseIterable { case structure, triggers, reason }

    init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)), in: "notModelled entry")
        let c = try decoder.container(keyedBy: CodingKeys.self)
        structure = try c.decode(String.self, forKey: .structure)
        triggers = try c.decode([String].self, forKey: .triggers)
        reason = try c.decode(String.self, forKey: .reason)
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
/// - A notModelled entry has a structure ID, triggers of the form CODE^EVT,
///   a one-line reason, is listed once and is not a loaded structure. The ID
///   has the CODE_EVT form, or is a Table 0354 misprint the version prints
///   literally (`misprints`: the `printed` ID of a cited overrides.json
///   table-0354 erratum, such as v2.3.1 SIIU_S12), registered so that a
///   message copying it is not a mismatch (P8b-final, F-I1).
func validateCompleteness(_ data: StructureCompleteness, modelledVersions: Set<String>,
                          structureCounts: [String: Int], structureIDs: [String: Set<String>] = [:],
                          misprints: [String: Set<String>] = [:]) throws {
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
        var seen: Set<String> = []
        for gap in entry.notModelled {
            let label = "version \(version) notModelled \(gap.structure)"
            guard gap.structure.range(of: "^[A-Z][A-Z0-9]{2}(_[A-Z0-9]{3})?$", options: .regularExpression) != nil
                    || misprints[version]?.contains(gap.structure) == true else {
                throw StructureSchemaError(description: "\(label): bad structure ID")
            }
            let bad = gap.triggers.filter { $0.range(of: "^[A-Z][A-Z0-9]{2}\\^([A-Z0-9]{3}|\\*)$", options: .regularExpression) == nil }
            guard bad.isEmpty else {
                throw StructureSchemaError(description: "\(label): triggers must be CODE^EVT or CODE^*; bad: \(bad)")
            }
            guard !gap.reason.trimmingCharacters(in: .whitespaces).isEmpty, !gap.reason.contains(where: \.isNewline) else {
                throw StructureSchemaError(description: "\(label): the reason must be one non-empty line")
            }
            guard seen.insert(gap.structure).inserted else {
                throw StructureSchemaError(description: "\(label): listed twice")
            }
            guard !(structureIDs[version] ?? []).contains(gap.structure) else {
                throw StructureSchemaError(description: "\(label): it is a loaded structure")
            }
        }
    }
}

/// Every trigger printed under two or more structures of one version (the
/// loaded ones and the registered notModelled ones) must be declared in
/// overrides.json `sharedTriggers` for that version, naming at least those
/// structures (ADR-019 lookup rule 2: without MSH-9.3 such a trigger is
/// ambiguous, and the Validator says so). `declared` maps version to trigger
/// to the declared structure IDs.
func validateSharedTriggers(owners: [String: [String: Set<String>]], declared: [String: [String: Set<String>]]) throws {
    for (version, byTrigger) in owners.sorted(by: { versionPrecedes($0.key, $1.key) }) {
        for (trigger, ids) in byTrigger.sorted(by: { $0.key < $1.key }) where ids.count > 1 {
            guard let names = declared[version]?[trigger], ids.isSubset(of: names) else {
                throw StructureSchemaError(description: "version \(version): trigger \(trigger) is printed under \(ids.sorted()) "
                    + "but overrides.json sharedTriggers does not declare it with those structures")
            }
        }
    }
}

/// The overrides.json `sharedTriggers` entries as version to trigger to
/// structure IDs; an absent file or key declares none.
func declaredSharedTriggers(in root: URL) throws -> [String: [String: Set<String>]] {
    let url = root.appendingPathComponent(structureOverridesFileName)
    guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    guard let entries = (object as? [String: Any])?["sharedTriggers"] as? [[String: Any]] else { return [:] }
    var out: [String: [String: Set<String>]] = [:]
    for entry in entries {
        guard let version = entry["version"] as? String, let trigger = entry["trigger"] as? String,
              let ids = entry["structures"] as? [String] else {
            throw StructureSchemaError(description: "\(url.path): a sharedTriggers entry needs version, trigger and structures")
        }
        out[version, default: [:]][trigger] = Set(ids)
    }
    return out
}

/// The structure IDs a version's Table 0354 prints misprinted, as version to
/// IDs: the `printed` value of each overrides.json `errata` entry with
/// `where` "table-0354" whose printed text is a structure ID (it holds an
/// underscore; an event erratum's printed text does not). An absent file or
/// key gives none.
func misprintedTableIDs(in root: URL) throws -> [String: Set<String>] {
    let url = root.appendingPathComponent(structureOverridesFileName)
    guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    guard let entries = (object as? [String: Any])?["errata"] as? [[String: Any]] else { return [:] }
    var out: [String: Set<String>] = [:]
    for entry in entries where entry["where"] as? String == "table-0354" {
        if let version = entry["version"] as? String, let printed = entry["printed"] as? String, printed.contains("_") {
            out[version, default: []].insert(printed)
        }
    }
    return out
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
    let gapCases = versions.compactMap { version -> String? in
        guard let gaps = data.versions[version]?.notModelled, !gaps.isEmpty else { return nil }
        let rows = gaps.sorted { $0.structure < $1.structure }.map { gap -> String in
            let triggers = gap.triggers.map(escapeStringLiteral).joined(separator: ", ")
            return "                \(escapeStringLiteral(gap.structure)): NotModelledStructure(\n"
                + "                    triggers: [\(triggers)],\n"
                + "                    reason: \(escapeStringLiteral(gap.reason))),"
        }.joined(separator: "\n")
        return "        case .\(versionDirName(version)):\n            return [\n\(rows)\n            ]"
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

        /// The grammar versions whose every printed structure is modelled
        /// or registered as not modelled.
        static let completeVersions: Set<Version> = [\(complete.joined(separator: ", "))]

        /// The structures `version`'s grammar version prints, or its Table
        /// 0354 lists, that are registered as not modelled (register section
        /// E), keyed by ID.
        static func generatedNotModelled(for version: Version) -> [String: NotModelledStructure] {
            switch version.grammarVersion {
    \(gapCases.isEmpty ? "" : gapCases + "\n")        default: return [:]
            }
        }
    }

    """
}
