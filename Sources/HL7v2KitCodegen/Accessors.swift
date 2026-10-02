// Accessors.swift
// Typed-accessor emission for generated segment structs: the singular
// accessor, its deprecated aliases (P6-9), the `…All` every-repetition
// accessor (P9-4, V251-C11) and the Track B `1-n` column plural.

import Foundation

/// How an HL7 data type surfaces as a typed accessor.
enum AccessorKind: Equatable {
    case scalar
    case view(String)
    case raw
}

func accessorKind(_ dataType: String) -> AccessorKind {
    if scalarDataTypes.contains(dataType) { return .scalar }
    if compositeDataTypes.contains(dataType) { return .view(dataType) }
    return .raw
}

/// Return types and bodies of the singular and `…All` accessors for field `index`.
struct AccessorShape {
    let type: String
    let body: String
    let allType: String
    let allBody: String
    let docTail: String
}

func accessorShape(_ dataType: String, index: Int) -> AccessorShape {
    switch accessorKind(dataType) {
    case .scalar:
        return AccessorShape(type: "String?", body: "field(\(index))?.stringValue",
                             allType: "[String?]", allBody: "repetitions(\(index)).map(\\.stringValue)",
                             docTail: "")
    case .view(let t):
        return AccessorShape(type: "\(t)?", body: "field(\(index)).map(\(t).init(field:))",
                             allType: "[\(t)]", allBody: "repetitions(\(index)).map(\(t).init(field:))",
                             docTail: " Returns the typed ``\(t)`` view; use `.field` for raw access.")
    case .raw:
        return AccessorShape(type: "Field?", body: "field(\(index))",
                             allType: "[Field]", allBody: "repetitions(\(index))",
                             docTail: "")
    }
}

/// A field repeats when its schema repeatability is `*` or a bound of 2 or more
/// (the same rule `FieldGrammar.repeatability` is generated from).
func fieldRepeats(_ field: FieldSchema) -> Bool {
    field.repeatability != "1"
}

/// Emit the accessors for one field.
/// - name: accessor name; defaults to the schema `swiftName`.
/// - notes: extra DocC sentences (P9-5 version notes).
/// - single: emit the singular accessor (and its deprecated aliases).
/// - all: emit `<name>All`; defaults to "the field repeats".
/// - plural: emit the Track B `1-n` column accessor.
func swiftAccessor(for field: FieldSchema, segmentID: String, name: String? = nil,
                   notes: [String] = [], single: Bool = true, all: Bool? = nil,
                   plural: Bool = true) -> String {
    let accessorName = name ?? field.swiftName
    let shape = accessorShape(field.dataType, index: field.index)
    let repeats = fieldRepeats(field)
    var summary = "\(segmentID)-\(field.index): \(field.name). HL7 data type `\(field.dataType)`.\(shape.docTail)"
    if repeats {
        summary += " Repeating field: this accessor reads the first repetition; `\(accessorName)All` returns every repetition."
    }
    var blocks: [String] = []
    if single {
        blocks.append(([summary] + notes).map { "    /// \($0)" }.joined(separator: "\n") + "\n" + [
            "    public var \(escapedIdentifier(accessorName)): \(shape.type) {",
            "        \(shape.body)",
            "    }",
        ].joined(separator: "\n") + deprecatedAliases(for: field, segmentID: segmentID, returnType: shape.type))
    }
    if all ?? repeats {
        let allDoc = [
            "\(segmentID)-\(field.index): every repetition of \(field.name), in wire order. Passes",
            "``TypedSegment/repetitions(_:)`` through unchanged, so the count matches the wire and",
            "the validator: empty when the field is absent; one entry when it is present but empty;",
            "`A~~B` gives three entries, the middle one empty; an HL7 null (`\"\"`) gives one entry",
            "holding the literal `\"\"`.",
        ]
        blocks.append((allDoc + (single ? [] : notes)).map { "    /// \($0)" }.joined(separator: "\n") + "\n" + [
            "    public var \(escapedIdentifier(accessorName + "All")): \(shape.allType) {",
            "        \(shape.allBody)",
            "    }",
        ].joined(separator: "\n"))
    }
    if plural, let columns = field.variableColumns {
        blocks.append([
            "    /// \(segmentID)-\(field.index)..n: every `\(field.name)` column. The spec's SEQ is `1-n`:",
            "    /// the field position recurs, so this returns each `|`-separated column from",
            "    /// position \(field.index) upward in wire order (empty columns included). Not",
            "    /// `~`-repetition — each element is one column.",
            "    public var \(escapedIdentifier(columns)): [Field] {",
            "        fields.count > \(field.index) ? Array(fields[\(field.index)...]) : []",
            "    }",
        ].joined(separator: "\n"))
    }
    return blocks.joined(separator: "\n\n")
}

/// Members every `TypedSegment` already has; a generated name must not shadow one.
let typedSegmentMembers: Set<String> = ["fields", "segmentID", "field", "repetitions", "cast"]

/// A generated `<name>All` must not collide with any other accessor in the
/// struct: a schema `swiftName`, a deprecated alias, a Track B plural or a
/// `TypedSegment` member. Codegen fails loudly rather than renaming.
func checkAllNames(_ schema: SegmentSchema) throws {
    let names = typedSegmentMembers
        .union(schema.fields.map(\.swiftName))
        .union(schema.fields.compactMap(\.variableColumns))
        .union(schema.fields.flatMap { $0.deprecatedSwiftNames ?? [] })
    for field in schema.fields where fieldRepeats(field) && names.contains(field.swiftName + "All") {
        FileHandle.standardError.write(Data(
            "HL7v2KitCodegen: \(schema.segmentID)-\(field.index): `\(field.swiftName)All` collides with an existing accessor\n".utf8))
        throw ExitCode.failure
    }
}
