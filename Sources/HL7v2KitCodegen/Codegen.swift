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
    /// Track B: presence means the spec's SEQ cell is `1-n` (the field
    /// position recurs across every `|`-separated column). The value is
    /// the plural accessor name emitted alongside the primary accessor.
    let variableColumns: String?
}

struct SegmentSchema: Decodable {
    let segmentID: String
    let version: String
    let description: String
    let fields: [FieldSchema]
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
            return "            FieldGrammar(index: \(field.index), name: \(escapeStringLiteral(field.name)), dataType: \(escapeStringLiteral(field.dataType)), optionality: .\(optionalityCase(field.optionality)), repeatability: \(repeatability), condition: \(condition), prohibitedWhen: \(prohibitedWhen), variableColumns: \(variableColumns)),"
        }.joined(separator: "\n")
        return """
                "\(schema.segmentID)": SegmentGrammar(
                    segmentID: "\(schema.segmentID)",
                    version: "\(schema.version)",
                    fields: [
        \(fields)
                    ]
                ),
        """
    }.joined(separator: "\n")

    return """
    // Auto-generated by HL7v2KitCodegen. Do not edit by hand.
    // Validator looks segments up here at runtime — no JSON parsing needed.
    // To extend a segment's grammar, edit its JSON schema under
    // Resources/schemas/ and run scripts/regenerate-typed-segments.sh.

    extension SegmentGrammarTable {
        public static let \(versionSwiftName): [String: SegmentGrammar] = [
    \(entries)
        ]
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

        print("HL7v2KitCodegen: \(emitted) segment(s) emitted under \(outputRoot.path)")
    }
}

enum ExitCode: Error { case failure }
