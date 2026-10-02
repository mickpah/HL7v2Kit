// CompositeViews.swift
// P9-3 (V251-C11, V282-C10, ADR-020): emit `<T>+Components.swift` for each
// composite view. Accessor names come from the hand-curated
// Resources/composites/composite-views.json; component names, types and
// per-version presence come from Resources/datatypes/v*/<T>.json.
//
// Treatment of the awkward cases:
// - Withdrawn components (`W` in some version) still get an accessor. An
//   earlier version defines them and a wire can carry them; the DocC names
//   the versions that withdraw the component.
// - Components printed without a data type (an empty `dataType`, as in a
//   withdrawn row) take the type from the newest version that prints one; if
//   no version prints one, the DocC says so.
// - Open arrays (MA, NA) have no fixed component indices, so they are not
//   composite views and get no named accessors. Only the types in
//   `compositeDataTypes` are emitted.

import Foundation

/// One view's curated names: the accessors already hand-written on the struct
/// (frozen API) and the ones this generator emits. Keys are component indices.
struct CompositeViewSpec: Decodable {
    let handWritten: [String: String]
    let generated: [String: String]
}

/// Members every `CompositeView` already has; a generated name must not shadow one.
let compositeReservedNames: Set<String> = [
    "field", "component", "viewed", "requiredComponents", "requiredComponentSet",
    "componentAccessorNames", "componentValue", "hashValue",
]

func compositeFailure(_ type: String, _ message: String) -> ExitCode {
    FileHandle.standardError.write(Data("HL7v2KitCodegen: composite \(type): \(message)\n".utf8))
    return .failure
}

/// The `/// ...` DocC lines for generated component `index` of `type`.
/// `firstSubcomponents` maps a version to each composite datatype it defines
/// that has no view (DR, TS, ...) and the name of that datatype's component 1.
func compositeComponentDoc(type: String, index: Int,
                           definitions: [(version: String, component: ComponentSchema)],
                           firstSubcomponents: [String: [String: String]] = [:]) -> [String] {
    let newest = definitions[definitions.count - 1].component
    let typed = definitions.last { !($0.component.dataType ?? "").isEmpty }
    let dataType = typed?.component.dataType ?? ""
    let versions = { (rows: [(version: String, component: ComponentSchema)]) in
        rows.map { "v" + $0.version }.joined(separator: ", ")
    }
    var doc = ["\(type)-\(index): \(newest.name)\(dataType.isEmpty ? "" : " (`\(dataType)`)"). "
        + "Defined in \(versions(definitions)). "
        + "On a message of another version this returns whatever \(type)-\(index) holds on the wire."]
    // Earlier printed names and data types that differ from the current ones,
    // each with the versions that print it. Case-only differences are not news.
    func variants(_ value: (ComponentSchema) -> String, current: String) -> [(value: String, versions: String)] {
        var order: [String] = []
        var seen: [String: [String]] = [:]
        for row in definitions where row.component.optionality != "W" {
            let v = value(row.component)
            guard !v.isEmpty, v.lowercased() != current.lowercased() else { continue }
            let key = v.lowercased()
            if seen[key] == nil { order.append(v) }
            seen[key, default: []].append("v" + row.version)
        }
        return order.map { ($0, seen[$0.lowercased()]!.joined(separator: ", ")) }
    }
    let otherNames = variants({ $0.name }, current: newest.name)
    if !otherNames.isEmpty {
        doc.append("Printed as \(otherNames.map { "\"\($0.value)\" (\($0.versions))" }.joined(separator: "; ")).")
    }
    let otherTypes = variants({ $0.dataType ?? "" }, current: dataType)
    if !otherTypes.isEmpty {
        doc.append("Typed \(otherTypes.map { "`\($0.value)` in \($0.versions)" }.joined(separator: "; ")).")
    }
    let untyped = definitions.filter { ($0.component.dataType ?? "").isEmpty && $0.component.optionality != "W" }
    if dataType.isEmpty {
        doc.append("No supported version prints a data type for it.")
    } else if !untyped.isEmpty, let typed {
        doc.append("\(versions(untyped)) print\(untyped.count == 1 ? "s" : "") no data type; "
            + "`\(dataType)` is from v\(typed.version).")
    }
    let withdrawn = definitions.filter { $0.component.optionality == "W" }
    if !withdrawn.isEmpty {
        doc.append("Withdrawn (`W`) in \(versions(withdrawn)); the accessor still reads it, "
            + "because earlier versions define it and a wire can carry it.")
    }
    let backward = definitions.filter { $0.component.optionality == "B" }
    if !backward.isEmpty {
        doc.append("Retained for backward compatibility (`B`) in \(versions(backward)).")
    }
    doc.append("Reads the first repetition and returns the component's first subcomponent: "
        + "`nil` when the component is absent, empty when it is present but empty.")
    if compositeDataTypes.contains(dataType) {
        doc.append("For the typed view use `component(\(index), as: \(dataType).self)`.")
    }
    // A component typed as a composite with no view returns only that
    // composite's first subcomponent; say so, and how to reach the rest.
    var nonView: [String] = []
    var nonViewVersions: [String: [String]] = [:]
    var nonViewFirst: [String: String] = [:]
    for row in definitions where row.component.optionality != "W" {
        guard let t = row.component.dataType, !compositeDataTypes.contains(t),
              let first = firstSubcomponents[row.version]?[t] else { continue }
        if nonViewVersions[t] == nil { nonView.append(t) }
        nonViewFirst[t] = first   // rows run oldest to newest: keep the newest name
        nonViewVersions[t, default: []].append("v" + row.version)
    }
    for t in nonView {
        doc.append("`\(t)` (\(nonViewVersions[t]!.joined(separator: ", "))) is a composite with no view: "
            + "this accessor returns only \(t).1, \(nonViewFirst[t]!). Read the other subcomponents "
            + "through ``field``: `field.repetitions.first?.components[\(index - 1)].subcomponents[1]` "
            + "is \(t).2.")
    }
    return doc
}

func renderCompositeComponents(type: String, spec: CompositeViewSpec, grammars: [DataTypeSchema],
                                firstSubcomponents: [String: [String: String]] = [:]) throws -> String {
    let ordered = grammars.sorted { versionLess($0.version, $1.version) }
    let defined = Set(ordered.flatMap { $0.components.map(\.index) })

    var names: [Int: String] = [:]
    var generated: [Int] = []
    for (source, map) in [("handWritten", spec.handWritten), ("generated", spec.generated)] {
        for (key, name) in map {
            guard let index = Int(key) else { throw compositeFailure(type, "\(source) key \"\(key)\" is not an index") }
            guard names[index] == nil else { throw compositeFailure(type, "component \(index) is named twice") }
            names[index] = name
            if source == "generated" { generated.append(index) }
        }
    }
    let unnamed = defined.subtracting(names.keys).sorted()
    guard unnamed.isEmpty else { throw compositeFailure(type, "components \(unnamed) have no curated accessor name") }
    let undefined = Set(names.keys).subtracting(defined).sorted()
    guard undefined.isEmpty else { throw compositeFailure(type, "components \(undefined) are not defined in any version") }
    let duplicates = Dictionary(grouping: names.values, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
    guard duplicates.isEmpty else { throw compositeFailure(type, "accessor names \(duplicates) are used twice") }
    let reserved = names.values.filter { swiftKeywords.contains($0) || compositeReservedNames.contains($0) }.sorted()
    guard reserved.isEmpty else { throw compositeFailure(type, "accessor names \(reserved) are reserved") }
    // P6-9 name rules: lowerCamelCase, at most 70 characters.
    let malformed = names.values.filter {
        $0.count > 70 || $0.range(of: "^[a-z][A-Za-z0-9]*_?$", options: .regularExpression) == nil
    }.sorted()
    guard malformed.isEmpty else { throw compositeFailure(type, "accessor names \(malformed) are not lowerCamelCase within 70 characters") }

    var accessors: [String] = []
    for index in generated.sorted() {
        let definitions: [(version: String, component: ComponentSchema)] = ordered.compactMap { grammar in
            grammar.components.first { $0.index == index }.map { (grammar.version, $0) }
        }
        let doc = compositeComponentDoc(type: type, index: index, definitions: definitions,
                                        firstSubcomponents: firstSubcomponents)
        accessors.append([
            doc.map { "    /// \($0)" }.joined(separator: "\n    ///\n"),
            "    public var \(names[index]!): String? {",
            "        componentValue(\(index))",
            "    }",
        ].joined(separator: "\n"))
    }

    let entries = names.keys.sorted().map { "\($0): \"\(names[$0]!)\"" }
    let rows = stride(from: 0, to: entries.count, by: 4).map {
        "        " + entries[$0..<min($0 + 4, entries.count)].joined(separator: ", ") + ","
    }
    let lines: [String] = [
        "// Auto-generated by HL7v2KitCodegen. Do not edit by hand.",
        "// Sources: Resources/composites/composite-views.json (accessor names) and",
        "// Resources/datatypes/v*/\(type).json (component tables). ADR-020.",
        "// Regenerate via scripts/regenerate-typed-segments.sh",
        "",
        "extension \(type) {",
        "    /// Accessor name for every component index any supported version defines,",
        "    /// hand-written and generated alike. `CompositeComponentTests` reads it.",
        "    static let componentAccessorNames: [Int: String] = [",
    ] + rows + [
        "    ]",
        accessors.isEmpty ? "" : "\n" + accessors.joined(separator: "\n\n"),
        "}",
        "",
    ]
    return lines.joined(separator: "\n")
}

/// Render every view first and write only when all of them succeed, so a
/// failure on one view leaves the generated tree untouched.
func emitCompositeViews(specFile: URL, outputRoot: URL, dataTypesByVersion: [String: [DataTypeSchema]]) throws {
    guard FileManager.default.fileExists(atPath: specFile.path) else {
        throw compositeFailure("*", "\(specFile.path) is missing; it is required (the curated accessor names)")
    }
    let specs: [String: CompositeViewSpec]
    do {
        specs = try JSONDecoder().decode([String: CompositeViewSpec].self, from: Data(contentsOf: specFile))
    } catch {
        throw compositeFailure("*", "\(specFile.path): malformed view map: \(error)")
    }
    let unlisted = compositeDataTypes.subtracting(specs.keys).sorted()
    guard unlisted.isEmpty else { throw compositeFailure("*", "views \(unlisted) are missing from \(specFile.lastPathComponent)") }
    // Per version: each composite datatype with no view, and its component 1 name.
    var firstSubcomponents: [String: [String: String]] = [:]
    for (version, types) in dataTypesByVersion {
        for t in types where !compositeDataTypes.contains(t.dataType) {
            if let first = t.components.first(where: { $0.index == 1 }) {
                firstSubcomponents[version, default: [:]][t.dataType] = first.name
            }
        }
    }
    var rendered: [(file: URL, source: String)] = []
    for (type, spec) in specs.sorted(by: { $0.key < $1.key }) {
        guard compositeDataTypes.contains(type) else { throw compositeFailure(type, "is not a composite view type") }
        let grammars = dataTypesByVersion.values.compactMap { types in types.first { $0.dataType == type } }
        guard !grammars.isEmpty else { throw compositeFailure(type, "no Resources/datatypes version defines it") }
        let source = try renderCompositeComponents(type: type, spec: spec, grammars: grammars,
                                                   firstSubcomponents: firstSubcomponents)
        rendered.append((outputRoot.appendingPathComponent("\(type)+Components.swift"), source))
    }
    try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
    for (outFile, source) in rendered {
        try Data(source.utf8).write(to: outFile)
        print("emitted \(outFile.path)")
    }
}
