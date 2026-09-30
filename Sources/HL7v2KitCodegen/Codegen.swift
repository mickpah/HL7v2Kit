// HL7v2KitCodegen — emits Swift TypedSegment structs from schema JSON.
//
// Usage:
//   swift run HL7v2KitCodegen [<schemasRoot>] [<outputRoot>]
//
// Defaults:
//   schemasRoot: ./Resources/schemas
//   outputRoot:  ./Sources/HL7v2Kit/Segment/Generated
//
// The schemas root contains version directories (e.g. v2.5.1/) each with one
// JSON file per segment (e.g. PID.json). Each file is rendered to
//   <outputRoot>/<VersionDir>/<SegmentID>.swift
// Existing files are overwritten — the generated tree is intended to be
// owned by this tool, not edited by hand.

import Foundation

struct FieldSchema: Decodable {
    let index: Int
    let swiftName: String
    let name: String
    let dataType: String
    let optionality: String
    let repeatability: String
    /// Optional predicate string controlling when a `.conditional` field
    /// becomes required. See `FieldGrammar.condition` for the grammar.
    /// v0.2-V1.
    let condition: String?
    /// Optional predicate string controlling when a field is PROHIBITED
    /// (populated while the predicate is true fires). See
    /// `FieldGrammar.prohibitedWhen`. M8-D.
    let prohibitedWhen: String?
    /// Severity for the prohibition (`"error"`, `"warning"`, `"info"`);
    /// absent means error. See `FieldGrammar.prohibitedSeverity`. P4.
    let prohibitedSeverity: String?
    /// Track B: presence means the spec's SEQ cell is `1-n` (the field
    /// position recurs across every `|`-separated column). The value is
    /// the plural accessor name emitted alongside the primary accessor.
    let variableColumns: String?
    /// The HL7 code table this coded field draws from (the spec's `TBL#`
    /// column, e.g. `"0074"`), or `nil` for uncoded fields. See
    /// `FieldGrammar.table`. M6-O6.
    let table: String?
    /// The printed LEN cell, verbatim ("250"; v2.7+ "2..2", "32=", "250#"). M25.
    let length: String?
    /// `true` when the field's own prose leaves its bound table open ("for suggested
    /// values", User-defined, or extensible). See `FieldGrammar.tableOpen`. P2-15.
    let tableOpen: Bool?
    /// The spec citation that justifies `tableOpen`, quoting the field's prose. Read by
    /// the schema audit, not emitted. P2-15.
    let tableOpenCitation: String?
    /// Further prohibitions beyond `prohibitedWhen`, each with its own severity and
    /// spec citation. See `FieldGrammar.additionalProhibitions`. P4-21.
    let additionalProhibitions: [ProhibitionSchema]?
}

/// One entry of a field's `additionalProhibitions` array. `when` uses the condition
/// grammar; `severity` is `error`, `warning` or `info`; `citation` quotes the spec text
/// (read by the schema audit and required here, not emitted). P4-21. `permitsNull: true`
/// exempts the HL7 null `""` (see `FieldProhibition.permitsNull`). P4-26.
struct ProhibitionSchema: Decodable {
    let when: String?
    let severity: String?
    let citation: String?
    let permitsNull: Bool?
}

/// Render a field's `additionalProhibitions` as the trailing initialiser argument, or `""`
/// when the key is absent so the field keeps a released initialiser. Fails codegen on a
/// malformed rule: a blank or one-token `when`, an unknown severity, a missing citation.
func renderAdditionalProhibitions(_ rules: [ProhibitionSchema]?, context: String) -> String {
    guard let rules else { return "" }
    precondition(!rules.isEmpty, "\(context): additionalProhibitions is empty; omit the key instead")
    let items = rules.enumerated().map { offset, rule -> String in
        let label = "\(context) additionalProhibitions[\(offset)]"
        let when = rule.when ?? ""
        // Plain spaces only, none leading or trailing, at least two tokens. Same rule as
        // `when_is_well_formed` in scripts/audit-schemas.py.
        let otherWhitespace = when.unicodeScalars.contains {
            $0 != " " && CharacterSet.whitespacesAndNewlines.contains($0)
        }
        precondition(!otherWhitespace && !when.hasPrefix(" ") && !when.hasSuffix(" ")
                        && when.split(separator: " ", omittingEmptySubsequences: true).count >= 2,
                     "\(label): when must be a condition '<referent> <predicate>', got '\(when)'")
        let severity = rule.severity ?? ""
        precondition(["error", "warning", "info"].contains(severity),
                     "\(label): severity must be error, warning or info, got '\(severity)'")
        precondition(!(rule.citation ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
                     "\(label): citation is missing")
        let permitsNull = rule.permitsNull == true ? ", permitsNull: true" : ""
        return "FieldProhibition(condition: \(escapeStringLiteral(when)), severity: .\(severity)\(permitsNull))"
    }
    return ", additionalProhibitions: [\(items.joined(separator: ", "))]"
}

struct SegmentSchema: Decodable {
    let segmentID: String
    let version: String
    let description: String
    let fields: [FieldSchema]
}

/// One printed value row of an HL7 code table (M6-O6).
struct TableEntrySchema: Decodable {
    let code: String
    let description: String
}

/// One HL7 code table as printed by one spec version. Hand-curated under
/// `Resources/tables/v<version>/<NNNN>.json`.
struct TableSchema: Decodable {
    let table: String
    let version: String
    let name: String
    let kind: String                      // "HL7" | "User"
    let permitsLocalExtensions: Bool?
    let citation: String?
    let entries: [TableEntrySchema]
    let patterns: [TablePatternSchema]?
}

/// One pattern row of a table (`"patterns"` in the table JSON): a printed
/// row that names a family of codes, e.g. 0203 `NNxxx`.
struct TablePatternSchema: Decodable {
    let code: String
    let description: String
    let regex: String
}

/// HL7 data type codes whose values are scalar enough that the typed
/// accessor returns `String?` (the flattened first-subcomponent value).
let scalarDataTypes: Set<String> = [
    "SI", "ID", "IS", "ST", "NM", "DT", "TM", "TS", "FT", "TX", "DTM",
]

/// HL7 composite data types for which HL7v2Kit ships a Swift struct view.
/// Accessors return `<Composite>?` instead of `Field?` — callers reach
/// into the named accessors on the struct, with `.field` available for
/// unexposed components and additional repetitions.
///
/// v0.2-C1 shipped XPN / CX / XAD. v0.3-C2 added CE / CWE. v0.3-C3
/// added EI / XCN / XTN. v0.3-C4 closes out the v2.5.1 typed-segment
/// composite landscape with HD / MSG / PT / VID / PL / CNE / XON /
/// EIP — every dataType that appears across the 9 spec § 17 segments
/// is now a typed struct.
let compositeDataTypes: Set<String> = [
    "XPN", "CX", "XAD", "CE", "CWE", "EI", "XCN", "XTN",
    "HD", "MSG", "PT", "VID", "PL", "CNE", "XON", "EIP",
]

/// The HL7 version whose schemas drive typed-segment-struct emission.
/// Other versions (v2.3 / v2.3.1 / v2.4 added in v0.3-G1..G3) contribute
/// only to their per-version `SegmentGrammar+vX_Y_Z.swift` tables; the
/// typed `struct PID` / `struct ORC` / ... shared across all callers
/// lives at the `Generated/` root (one file per segment, version-agnostic
/// names) and represents the union surface. Field accessors that don't
/// exist on an older wire simply return nil — that's the normal Optional
/// contract for an absent field.
let canonicalVersion = "2.5.1"

/// Swift keywords that can't be bare identifiers — a schema field whose derived
/// swiftName collides (e.g. IN3-8 "Operator" → `operator`) is emitted backtick-escaped.
let swiftKeywords: Set<String> = [
    "operator", "class", "struct", "enum", "protocol", "extension", "func", "var", "let",
    "if", "else", "switch", "case", "default", "for", "while", "repeat", "do", "return",
    "break", "continue", "guard", "defer", "in", "where", "as", "is", "try", "throw",
    "throws", "rethrows", "init", "deinit", "self", "super", "nil", "true", "false",
    "import", "typealias", "associatedtype", "public", "private", "internal", "fileprivate",
    "static", "final", "lazy", "weak", "unowned", "some", "any", "inout", "subscript",
]

func escapedIdentifier(_ s: String) -> String {
    swiftKeywords.contains(s) ? "`\(s)`" : s
}

func swiftAccessor(for field: FieldSchema, segmentID: String) -> String {
    let returnType: String
    let body: String
    let docTail: String
    if scalarDataTypes.contains(field.dataType) {
        returnType = "String?"
        body = "field(\(field.index))?.stringValue"
        docTail = ""
    } else if compositeDataTypes.contains(field.dataType) {
        returnType = "\(field.dataType)?"
        body = "field(\(field.index)).map(\(field.dataType).init(field:))"
        docTail = " Returns the typed ``\(field.dataType)`` view; use `.field` for raw access."
    } else {
        returnType = "Field?"
        body = "field(\(field.index))"
        docTail = ""
    }
    let primary = """
        /// \(segmentID)-\(field.index): \(field.name). HL7 data type `\(field.dataType)`.\(docTail)
        public var \(escapedIdentifier(field.swiftName)): \(returnType) {
            \(body)
        }
    """
    guard let plural = field.variableColumns else { return primary }
    return primary + """


        /// \(segmentID)-\(field.index)..n: every `\(field.name)` column. The spec's SEQ is `1-n`:
        /// the field position recurs, so this returns each `|`-separated column from
        /// position \(field.index) upward in wire order (empty columns included). Not
        /// `~`-repetition — each element is one column.
        public var \(escapedIdentifier(plural)): [Field] {
            fields.count > \(field.index) ? Array(fields[\(field.index)...]) : []
        }
    """
}

func render(_ schema: SegmentSchema) -> String {
    let accessors = schema.fields
        .map { swiftAccessor(for: $0, segmentID: schema.segmentID) }
        .joined(separator: "\n\n")

    return """
    // Auto-generated by HL7v2KitCodegen. Do not edit by hand.
    // Source schema: Resources/schemas/v\(schema.version)/\(schema.segmentID).json
    // Regenerate via scripts/regenerate-typed-segments.sh

    /// \(schema.description) segment (HL7 v\(schema.version)).
    public struct \(schema.segmentID): TypedSegment {
        public static let segmentID = "\(schema.segmentID)"
        public let fields: [Field]

        public init(fields: [Field]) {
            self.fields = fields
        }

    \(accessors)
    }

    """
}

func versionDirName(_ version: String) -> String {
    // v2.5.1 → v2_5_1 (legal Swift identifier piece)
    "v" + version.replacingOccurrences(of: ".", with: "_")
}

/// Emit the codegen-side `SegmentRegistry` extension. Cases are sorted
/// alphabetically by segment ID so the output is deterministic.
func renderRegistry(segmentIDs: [String]) -> String {
    let cases = segmentIDs.sorted().map { id in
        "        case \(id).segmentID: return .typed(AnyTypedSegment(\(id)(fields: unknown.fields)))"
    }.joined(separator: "\n")

    return """
    // Auto-generated by HL7v2KitCodegen. Do not edit by hand.
    // This extension is the source of truth for typed-segment hydration.
    // To register a new segment, add its JSON schema under Resources/schemas/
    // and run scripts/regenerate-typed-segments.sh.

    extension SegmentRegistry {
        /// Hydrate `unknown` into a `.typed` segment if its ID matches a
        /// schema-emitted typed struct. Returns nil for unrecognised IDs so
        /// the caller can fall back to `.unknown` (Z-segment tolerance).
        static func hydrateGenerated(_ unknown: UnknownSegment) -> Segment? {
            switch unknown.segmentID {
    \(cases)
            default:
                return nil
            }
        }
    }

    """
}

/// Emit the validator's per-version `SegmentGrammar` table. The validator
/// reads from this table at runtime — no JSON parsing, no extra bundle.
/// Schemas are sorted by segment ID and fields by ascending `index` so the
/// output is deterministic.
func renderGrammarTable(version: String, schemas: [SegmentSchema]) -> String {
    let versionSwiftName = versionDirName(version)
    let entries = schemas.sorted(by: { $0.segmentID < $1.segmentID }).map { schema in
        let fields = schema.fields.sorted(by: { $0.index < $1.index }).map { field in
            let repeatability = field.repeatability == "*" ? ".multiple" : ".single"
            let condition = field.condition.map { escapeStringLiteral($0) } ?? "nil"
            let prohibitedWhen = field.prohibitedWhen.map { escapeStringLiteral($0) } ?? "nil"
            let variableColumns = field.variableColumns != nil ? "true" : "false"
            let table = field.table.map { escapeStringLiteral($0) } ?? "nil"
            let length = field.length.map { escapeStringLiteral($0) } ?? "nil"
            // Emitted only when set, so unmarked fields keep the released initialiser.
            let tableOpen = field.tableOpen == true ? ", tableOpen: true" : ""
            let prohibitedSeverity: String = {
                guard let raw = field.prohibitedSeverity else { return "" }
                precondition(field.prohibitedWhen != nil,
                             "\(schema.segmentID)-\(field.index): prohibitedSeverity is set without prohibitedWhen")
                precondition(["error", "warning", "info"].contains(raw),
                             "\(schema.segmentID)-\(field.index): prohibitedSeverity must be error, warning or info, got \(raw)")
                return ", prohibitedSeverity: .\(raw)"
            }()
            let additionalProhibitions = renderAdditionalProhibitions(
                field.additionalProhibitions, context: "\(schema.segmentID)-\(field.index)")
            return "            FieldGrammar(index: \(field.index), name: \(escapeStringLiteral(field.name)), dataType: \(escapeStringLiteral(field.dataType)), optionality: .\(optionalityCase(field.optionality)), repeatability: \(repeatability), condition: \(condition), prohibitedWhen: \(prohibitedWhen), variableColumns: \(variableColumns), table: \(table), length: \(length)\(tableOpen)\(prohibitedSeverity)\(additionalProhibitions)),"
        }.joined(separator: "\n")
        // One typed constant per segment. The whole version used to be a single dictionary
        // literal, which the type checker solves as ONE expression: once fields carried a
        // String literal for the optional `table` (A5), a version's file went from 13 s to
        // 16 min to type-check. A per-segment constant bounds every expression to one segment.
        return """
            private static let \(versionSwiftName)_\(schema.segmentID): SegmentGrammar = SegmentGrammar(
                segmentID: "\(schema.segmentID)",
                version: "\(schema.version)",
                fields: [
        \(fields)
                ]
            )
        """
    }.joined(separator: "\n\n")
    let keys = schemas.sorted(by: { $0.segmentID < $1.segmentID })
        .map { "        \"\($0.segmentID)\": \(versionSwiftName)_\($0.segmentID)," }
        .joined(separator: "\n")

    return """
    // Auto-generated by HL7v2KitCodegen. Do not edit by hand.
    // Validator looks segments up here at runtime — no JSON parsing needed.
    // To extend a segment's grammar, edit its JSON schema under
    // Resources/schemas/ and run scripts/regenerate-typed-segments.sh.

    extension SegmentGrammarTable {
        public static let \(versionSwiftName): [String: SegmentGrammar] = [
    \(keys)
        ]

    \(entries)
    }

    """
}

struct ComponentSchema: Decodable {
    let index: Int
    let name: String
    let dataType: String?
    let optionality: String
    let length: String?
    /// M26: a cited predicate over sibling components, on components printed C.
    let condition: String?
    /// M27: the same, for the "as of v2.7" rules checked only on opt-in.
    let conformanceCondition: String?
    let tables: [String]?
}

struct DataTypeSchema: Decodable {
    let dataType: String
    let version: String
    let name: String
    let components: [ComponentSchema]
}

/// Emit `DataTypeGrammarTable+v<X_Y_Z>.swift` (M10-B). One typed constant per
/// datatype: a single dictionary literal for a whole version is one expression
/// to the type checker, and the grammar tables showed what that costs.
func renderDataTypeTable(versionSwiftName: String, sourceDir: String, types: [DataTypeSchema]) -> String {
    let sorted = types.sorted { $0.dataType < $1.dataType }
    let constants = sorted.map { t -> String in
        let components = t.components.sorted { $0.index < $1.index }.map { c -> String in
            let tables = (c.tables ?? []).map { escapeStringLiteral($0) }.joined(separator: ", ")
            let length = c.length.map { escapeStringLiteral($0) } ?? "nil"
            let condition = c.condition.map { escapeStringLiteral($0) } ?? "nil"
            let conformance = c.conformanceCondition.map { escapeStringLiteral($0) } ?? "nil"
            return "            ComponentGrammar(index: \(c.index), name: \(escapeStringLiteral(c.name)), dataType: \(escapeStringLiteral(c.dataType ?? "")), optionalityCode: \(escapeStringLiteral(c.optionality)), tables: [\(tables)], length: \(length), condition: \(condition), conformanceCondition: \(conformance)),"
        }.joined(separator: "\n")
        return """
            private static let \(versionSwiftName)_\(t.dataType): DataTypeGrammar = DataTypeGrammar(
                dataType: "\(t.dataType)",
                version: "\(t.version)",
                name: \(escapeStringLiteral(t.name)),
                components: [
        \(components)
                ]
            )
        """
    }.joined(separator: "\n\n")
    let keys = sorted.map { "        \"\($0.dataType)\": \(versionSwiftName)_\($0.dataType)," }.joined(separator: "\n")
    return """
    // Auto-generated by HL7v2KitCodegen. Do not edit by hand.
    // Source: Resources/datatypes/\(sourceDir)/*.json
    // Regenerate via scripts/regenerate-typed-segments.sh

    extension DataTypeGrammarTable {
        static let \(versionSwiftName): [String: DataTypeGrammar] = [
    \(keys)
        ]

    \(constants)
    }

    """
}

struct VMRRowSchema: Decodable {
    let path: String
    let name: String
    let obx2: String
    let min: Int
    let max: Int?
    let kind: String
}

struct VMRTableSchema: Decodable {
    let profile: String
    let citation: String
    let root: String
    let elements: [VMRRowSchema]
}

/// Emit `VMRImplementationTable+<profile>.swift` (M12-B). An array of 89 small
/// initialiser calls with no optional-literal arguments type-checks quickly; `max` is
/// written as an explicit `Int?` expression for that reason.
func renderVMRTable(_ table: VMRTableSchema) -> String {
    let name = table.profile.replacingOccurrences(of: "-", with: "_")
    let rows = table.elements.map { e -> String in
        let max = e.max.map { "Optional(\($0))" } ?? "Int?.none"
        return "        VMRElement(path: \(escapeStringLiteral(e.path)), name: \(escapeStringLiteral(e.name)), obx2: \(escapeStringLiteral(e.obx2)), min: \(e.min), max: \(max), kind: \(escapeStringLiteral(e.kind))),"
    }.joined(separator: "\n")
    return """
    // Auto-generated by HL7v2KitCodegen. Do not edit by hand.
    // Source: Resources/profiles/\(table.profile)/vmr-table.json
    // \(table.citation)
    // Regenerate via scripts/regenerate-typed-segments.sh

    extension VMRImplementationTable {
        static let \(name): [VMRElement] = [
    \(rows)
        ]
    }

    """
}

/// Map a table JSON's `kind` string to its `HL7Table.Kind` Swift case.
///
/// Unknown values fail the build rather than defaulting. `.hl7` with rows
/// and no local extensions is exactly the combination that makes
/// `HL7Table.isClosed` true, so a miscoded user-defined table (`"user"`,
/// `"USER"`, a typo) would silently ship as an enforceable closed set.
/// `context` names the offending file or table in the diagnostic.
func tableKindCase(_ kind: String, context: String) throws -> String {
    switch kind {
    case "HL7":  return ".hl7"
    case "User": return ".userDefined"
    default:
        FileHandle.standardError.write(Data(
            "HL7v2KitCodegen: \(context): unknown table kind \"\(kind)\" — expected \"HL7\" or \"User\"\n".utf8))
        throw ExitCode.failure
    }
}

/// Emit one version's `HL7TableRegistry` dictionary. One `static let`
/// per table with an explicit element type keeps type-checking linear
/// on the large versions. Tables are sorted by number so the output is
/// deterministic; a version with no curated tables emits `[:]`.
func renderTableRegistry(versionSwiftName: String, sourceDir: String, tables: [TableSchema]) throws -> String {
    let sorted = tables.sorted { $0.table < $1.table }
    let header = """
    // Auto-generated by HL7v2KitCodegen. Do not edit by hand.
    // Source: Resources/tables/\(sourceDir)/*.json
    // Regenerate via scripts/regenerate-typed-segments.sh

    """

    guard !sorted.isEmpty else {
        return header + """

        extension HL7TableRegistry {
            public static let \(versionSwiftName): [String: HL7Table] = [:]
        }

        """
    }

    let constants = try sorted.map { t -> String in
        let kind = try tableKindCase(t.kind, context: "table \(t.table) (v\(t.version))")
        let entries = t.entries.map {
            "            HL7Table.Entry(code: \(escapeStringLiteral($0.code)), description: \(escapeStringLiteral($0.description))),"
        }.joined(separator: "\n")
        for p in t.patterns ?? [] {
            _ = try NSRegularExpression(pattern: p.regex)   // fail the codegen on a malformed pattern
            guard p.regex.hasPrefix("^"), p.regex.hasSuffix("$") else {
                FileHandle.standardError.write(Data(
                    "HL7v2KitCodegen: table \(t.table) (v\(t.version)): pattern \"\(p.code)\" regex \"\(p.regex)\" is not anchored — expected \"^...$\"\n".utf8))
                throw ExitCode.failure
            }
        }
        let patternLines = (t.patterns ?? []).map {
            "            HL7Table.CodePattern(code: \(escapeStringLiteral($0.code)), description: \(escapeStringLiteral($0.description)), regex: \(escapeStringLiteral($0.regex))),"
        }
        let patternsArgument = patternLines.isEmpty ? "" :
            ",\n        patterns: [\n" + patternLines.joined(separator: "\n") + "\n        ] as [HL7Table.CodePattern]"
        return """
            static let t\(t.table)_\(versionSwiftName) = HL7Table(
                number: "\(t.table)",
                name: \(escapeStringLiteral(t.name)),
                kind: \(kind),
                permitsLocalExtensions: \(t.permitsLocalExtensions ?? false),
                entries: [
        \(entries)
                ] as [HL7Table.Entry]\(patternsArgument)
            )
        """
    }.joined(separator: "\n\n")
    let keys = sorted.map { "        \"\($0.table)\": t\($0.table)_\(versionSwiftName)," }.joined(separator: "\n")

    return header + """

    extension HL7TableRegistry {
        public static let \(versionSwiftName): [String: HL7Table] = [
    \(keys)
        ]

    \(constants)
    }

    """
}

/// Map a single-letter HL7 optionality code to a Swift enum case name.
func optionalityCase(_ code: String) -> String {
    switch code {
    case "R": return "required"
    case "O": return "optional"
    case "C": return "conditional"
    case "X": return "notSupported"
    case "B": return "backwardCompat"
    case "W": return "withdrawn"
    default:  return "optional"   // Default to permissive on unknown codes.
    }
}

/// Render a Swift string literal that round-trips the input value safely
/// (handles backslash and quote characters). Deliberately hand-rolled:
/// `String(reflecting:)` additionally escapes apostrophes (`\'`), which
/// would churn every grammar-table line containing a possessive name.
func escapeStringLiteral(_ s: String) -> String {
    let escaped = s
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}

@main
struct Codegen {
    static func main() throws {
        let args = CommandLine.arguments
        let cwd = FileManager.default.currentDirectoryPath
        let schemasRoot = URL(fileURLWithPath: args.count > 1 ? args[1] : "\(cwd)/Resources/schemas")
        let outputRoot = URL(fileURLWithPath: args.count > 2 ? args[2] : "\(cwd)/Sources/HL7v2Kit/Segment/Generated")
        let tablesRoot = URL(fileURLWithPath: args.count > 3 ? args[3] : "\(cwd)/Resources/tables")
        let tablesOutputRoot = URL(fileURLWithPath: args.count > 4 ? args[4] : "\(cwd)/Sources/HL7v2Kit/Tables/Generated")

        let fm = FileManager.default

        let versionDirs = try fm.contentsOfDirectory(at: schemasRoot, includingPropertiesForKeys: nil)
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false }

        guard !versionDirs.isEmpty else {
            FileHandle.standardError.write(Data("HL7v2KitCodegen: no version directories under \(schemasRoot.path)\n".utf8))
            throw ExitCode.failure
        }

        var emitted = 0
        var emittedSegmentIDs: Set<String> = []
        var schemasByVersion: [String: [SegmentSchema]] = [:]
        for versionURL in versionDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let version = versionURL.lastPathComponent.replacingOccurrences(of: "v", with: "", options: [.anchored])
            let segmentFiles = try fm.contentsOfDirectory(at: versionURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })

            let isCanonical = (version == canonicalVersion)
            // Canonical-version structs emit at the Generated/ root rather
            // than under a per-version subdirectory. The struct surface is
            // shared across every supported HL7 v2 version (typed-segment
            // accessors return Optional, so fields not present on an older
            // wire surface as nil) — placing the file under v2_5_1/ would
            // misleadingly imply sibling v2_3_1/, v2_4/ etc. that never
            // exist. Per-version SegmentGrammar+vX_Y_Z.swift files DO live
            // at the Generated/ root and reflect the per-version field
            // sets. See Codegen.swift `canonicalVersion` documentation.
            if isCanonical {
                try fm.createDirectory(at: outputRoot, withIntermediateDirectories: true)
            }

            for schemaURL in segmentFiles {
                let data = try Data(contentsOf: schemaURL)
                let schema = try JSONDecoder().decode(SegmentSchema.self, from: data)
                schemasByVersion[version, default: []].append(schema)
                guard isCanonical else { continue }
                let source = render(schema)
                let outFile = outputRoot.appendingPathComponent("\(schema.segmentID).swift")
                try Data(source.utf8).write(to: outFile)
                print("emitted \(outFile.path)")
                emitted += 1
                emittedSegmentIDs.insert(schema.segmentID)
            }
        }

        // Fallback pass (v3-C5): a segment with no canonical v2.5.1 schema
        // — the v2.6/v2.8.2-only surface — emits its shared struct from
        // the EARLIEST version that defines it. This extends the
        // union-surface doctrine rather than replacing it: canonical
        // stays authoritative wherever it defines a segment; where it
        // never does, the earliest definer is that segment's de-facto
        // canonical. (Pre-v2.6 versions cannot reach this path — the
        // presence audit guarantees every pre-v2.6 segment also exists
        // on canonical.)
        for (_, schemas) in schemasByVersion.sorted(by: { $0.key < $1.key }) {
            for schema in schemas where !emittedSegmentIDs.contains(schema.segmentID) {
                let source = render(schema)
                let outFile = outputRoot.appendingPathComponent("\(schema.segmentID).swift")
                try Data(source.utf8).write(to: outFile)
                print("emitted \(outFile.path)")
                emitted += 1
                emittedSegmentIDs.insert(schema.segmentID)
            }
        }

        // Emit the cross-version SegmentRegistry extension.
        try fm.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        let registrySource = renderRegistry(segmentIDs: Array(emittedSegmentIDs))
        let registryFile = outputRoot.appendingPathComponent("SegmentRegistry+Generated.swift")
        try Data(registrySource.utf8).write(to: registryFile)
        print("emitted \(registryFile.path)")

        // Emit the per-version SegmentGrammar table consumed by Validator.
        for (version, schemas) in schemasByVersion.sorted(by: { $0.key < $1.key }) {
            let grammarSource = renderGrammarTable(version: version, schemas: schemas)
            let grammarFile = outputRoot.appendingPathComponent("SegmentGrammar+\(versionDirName(version)).swift")
            try Data(grammarSource.utf8).write(to: grammarFile)
            print("emitted \(grammarFile.path)")
        }

        // Emit the per-version HL7 code-table registry (M6-O6). Version
        // directories are the ones whose name starts with "v"; anything
        // else under Resources/tables (the locale axis, stray files) is
        // not a spec version and is skipped.
        if fm.fileExists(atPath: tablesRoot.path) {
            let tableVersionDirs = try fm.contentsOfDirectory(at: tablesRoot, includingPropertiesForKeys: nil)
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false }
                .filter { $0.lastPathComponent.hasPrefix("v") }
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            // The locale axis (A6): Resources/tables/locale/<locale-id>/ holds a locale's own
            // printed rendering of a table, keyed by the HL7Locale raw value. Each file's
            // "version" carries that id, so the same misfiled-table guard applies.
            let localeRoot = tablesRoot.appendingPathComponent("locale")
            let tableLocaleDirs = fm.fileExists(atPath: localeRoot.path)
                ? try fm.contentsOfDirectory(at: localeRoot, includingPropertiesForKeys: nil)
                    .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false }
                    .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                : []

            try fm.createDirectory(at: tablesOutputRoot, withIntermediateDirectories: true)
            for versionURL in tableVersionDirs + tableLocaleDirs {
                let isLocale = versionURL.deletingLastPathComponent().lastPathComponent == "locale"
                let version = isLocale
                    ? versionURL.lastPathComponent
                    : versionURL.lastPathComponent.replacingOccurrences(of: "v", with: "", options: [.anchored])
                let tableFiles = try fm.contentsOfDirectory(at: versionURL, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "json" }
                    .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                var tables: [TableSchema] = []
                for tableURL in tableFiles {
                    let data = try Data(contentsOf: tableURL)
                    let table: TableSchema
                    do {
                        table = try JSONDecoder().decode(TableSchema.self, from: data)
                    } catch {
                        FileHandle.standardError.write(Data(
                            "HL7v2KitCodegen: \(tableURL.path): malformed table JSON — \(error)\n".utf8))
                        throw ExitCode.failure
                    }
                    // A table that disagrees with where it sits would be
                    // emitted under the wrong number or version silently.
                    _ = try tableKindCase(table.kind, context: tableURL.path)
                    let expectedNumber = tableURL.deletingPathExtension().lastPathComponent
                    guard table.table == expectedNumber else {
                        FileHandle.standardError.write(Data(
                            "HL7v2KitCodegen: \(tableURL.path): table number \"\(table.table)\" does not match the filename \"\(expectedNumber)\"\n".utf8))
                        throw ExitCode.failure
                    }
                    guard table.version == version else {
                        FileHandle.standardError.write(Data(
                            "HL7v2KitCodegen: \(tableURL.path): version \"\(table.version)\" does not match its directory \"\(versionURL.lastPathComponent)\"\n".utf8))
                        throw ExitCode.failure
                    }
                    tables.append(table)
                }
                let versionSwiftName = isLocale
                    ? version.replacingOccurrences(of: "-", with: "_")
                    : versionDirName(version)
                let source = try renderTableRegistry(
                    versionSwiftName: versionSwiftName,
                    sourceDir: isLocale ? "locale/\(version)" : versionURL.lastPathComponent,
                    tables: tables)
                let outFile = tablesOutputRoot.appendingPathComponent("HL7TableRegistry+\(versionSwiftName).swift")
                try Data(source.utf8).write(to: outFile)
                print("emitted \(outFile.path) (\(tables.count) table(s))")
            }
        } else {
            print("HL7v2KitCodegen: no tables root at \(tablesRoot.path) — skipping table registry")
        }

        // M12-B: locale profile artefacts (the AU VMR implementation table).
        let profilesRoot = URL(fileURLWithPath: args.count > 7 ? args[7] : "\(cwd)/Resources/profiles")
        let profilesOutputRoot = URL(fileURLWithPath: args.count > 8 ? args[8] : "\(cwd)/Sources/HL7v2Kit/Locale/Generated")
        if fm.fileExists(atPath: profilesRoot.path) {
            try fm.createDirectory(at: profilesOutputRoot, withIntermediateDirectories: true)
            for dirURL in try fm.contentsOfDirectory(at: profilesRoot, includingPropertiesForKeys: nil)
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let fileURL = dirURL.appendingPathComponent("vmr-table.json")
                guard fm.fileExists(atPath: fileURL.path) else { continue }
                let table: VMRTableSchema
                do {
                    table = try JSONDecoder().decode(VMRTableSchema.self, from: Data(contentsOf: fileURL))
                } catch {
                    FileHandle.standardError.write(Data(
                        "HL7v2KitCodegen: \(fileURL.path): malformed VMR table JSON — \(error)\n".utf8))
                    throw ExitCode.failure
                }
                guard table.profile == dirURL.lastPathComponent else {
                    FileHandle.standardError.write(Data(
                        "HL7v2KitCodegen: \(fileURL.path): profile \"\(table.profile)\" does not match its directory\n".utf8))
                    throw ExitCode.failure
                }
                let outFile = profilesOutputRoot.appendingPathComponent(
                    "VMRImplementationTable+\(table.profile.replacingOccurrences(of: "-", with: "_")).swift")
                try Data(renderVMRTable(table).utf8).write(to: outFile)
                print("emitted \(outFile.path) (\(table.elements.count) row(s))")
            }
        }

        // M10-B: datatype component tables.
        let dataTypesRoot = URL(fileURLWithPath: args.count > 5 ? args[5] : "\(cwd)/Resources/datatypes")
        let dataTypesOutputRoot = URL(fileURLWithPath: args.count > 6 ? args[6] : "\(cwd)/Sources/HL7v2Kit/DataTypes/Generated")
        if fm.fileExists(atPath: dataTypesRoot.path) {
            try fm.createDirectory(at: dataTypesOutputRoot, withIntermediateDirectories: true)
            let dirs = try fm.contentsOfDirectory(at: dataTypesRoot, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("v") }
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            for dirURL in dirs {
                let version = dirURL.lastPathComponent.replacingOccurrences(of: "v", with: "", options: [.anchored])
                var types: [DataTypeSchema] = []
                for fileURL in try fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
                    .filter({ $0.pathExtension == "json" }) {
                    let type: DataTypeSchema
                    do {
                        type = try JSONDecoder().decode(DataTypeSchema.self, from: Data(contentsOf: fileURL))
                    } catch {
                        FileHandle.standardError.write(Data(
                            "HL7v2KitCodegen: \(fileURL.path): malformed datatype JSON — \(error)\n".utf8))
                        throw ExitCode.failure
                    }
                    guard type.dataType == fileURL.deletingPathExtension().lastPathComponent, type.version == version else {
                        FileHandle.standardError.write(Data(
                            "HL7v2KitCodegen: \(fileURL.path): dataType / version do not match the path\n".utf8))
                        throw ExitCode.failure
                    }
                    types.append(type)
                }
                let swiftName = versionDirName(version)
                let outFile = dataTypesOutputRoot.appendingPathComponent("DataTypeGrammarTable+\(swiftName).swift")
                try Data(renderDataTypeTable(versionSwiftName: swiftName, sourceDir: dirURL.lastPathComponent, types: types).utf8)
                    .write(to: outFile)
                print("emitted \(outFile.path) (\(types.count) datatype(s))")
            }
        }

        print("HL7v2KitCodegen: \(emitted) segment(s) emitted under \(outputRoot.path)")
    }
}

enum ExitCode: Error { case failure }
