# HL7v2Kit — Swift Package Specification

**Version:** 0.1 (Draft spec, pre-implementation)
**Last updated:** 27 May 2026
**Target release:** v0.1.0 of HL7v2Kit
**Status:** Founding design record (v0.1, written pre-implementation). Retained as-written; **as-built divergences are annotated inline** (`> As-built` notes) and governed by the ADR chain. For the current API surface read `public-api-surface.md` + `Migration.md` ("The 2.0 boundary"); for the design-doc map read `docs/design/README.md`.
**Parent project:** AU Core Workbench (see `AU-Core-Workbench-Planning.md`)

---

## 1. Purpose & positioning

HL7v2Kit is the foundational Swift package for parsing, building, and validating HL7 v2.x messages. It is the lowest layer of the AU Core Workbench stack and the first piece of community open-source output from the project.

**Three reasons it exists as a separate package:**

1. **Open-sourceable.** No proprietary mapping logic. Apache 2.0 licence. Becomes a credibility artefact and a content-marketing piece (announcement post, GitHub README, search results for "HL7 v2 Swift").
2. **Reusable.** Future SKUs (DICOM tool, Windows port, server-side validator) can consume it. Community users can build their own tools on top.
3. **Forces clean boundaries.** Pure parser/builder with no UI, no FHIR knowledge, no AU-specific assumptions. AU Core flavour lives in `FHIRAUCoreKit` and `MappingEngine`, not here.

**Three things it is not:**

- Not a FHIR library. No FHIR types, no FHIR knowledge.
- Not a message router or integration engine. No transport, no queueing, no persistence.
- Not opinionated about AU profiles at the API level. AU-specific *test fixtures* live in this repo, but AU-specific *types* (PIT messages, AU Patient identifier semantics) live in `FHIRAUCoreKit`.

**Non-goal:** HL7 v3 support. HL7 v3 saw negligible AU production adoption and is now effectively superseded by FHIR. Out of scope forever.

---

## 2. Scope locked from planning decisions

These three answers from the planning session determine the v0.1.0 API surface.

| Decision | Locked value | Impact on v0.1.0 |
|---|---|---|
| Parser scope | Parse + build (round-trip) | AST must be lossless. Builder API ships alongside parser. Round-trip property tests are mandatory. |
| Validation depth | Structural + segment grammar + Z-segment tolerance | Ships with v2.3.1 / 2.4 / 2.5.1 / 2.8 segment grammars. Unknown segments (Z-segments) parse as `UnknownSegment` without errors. |
| Acknowledgments (ADR-019, decision 9) | Build and validate the general acknowledgment; no protocol logic | `MessageBuilder.acknowledgment(to:code:messageControlID:dateTime:)` applies the MSA-2 echo and sender/receiver swap; the ACK structure is validated with the other message structures. Choosing whether and when to send accept or application acknowledgments from MSH-15/MSH-16 (v2.5.1 CH02 §2.9.2-2.9.3) is receiving-application behaviour and a non-goal. |
| Public API style | Both — paths for ad-hoc, typed for known segments | Two parallel access patterns: string-path subscripts and typed segment accessors. Tests verify they return identical values. |

---

## 3. Package layout

```
HL7v2Kit/
├── Package.swift
├── README.md
├── LICENSE                          Apache 2.0
├── CHANGELOG.md
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                   Test matrix: macOS 14/15/26, Linux ubuntu-latest
│   │   ├── release.yml              Tag push → GitHub release with notes
│   │   └── docs.yml                 DocC build + deploy to GitHub Pages
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.yml
│   │   └── feature_request.yml
│   └── PULL_REQUEST_TEMPLATE.md
├── Sources/
│   ├── HL7v2Kit/                    Main module (public API)
│   │   ├── Message.swift            Top-level Message type
│   │   ├── Segment/
│   │   │   ├── Segment.swift        Segment protocol + erased type
│   │   │   ├── Field.swift          Field, Component, Subcomponent
│   │   │   ├── UnknownSegment.swift Z-segment fallback
│   │   │   └── Generated/           Typed segment structs (PID, MSH, OBR, OBX, ...)
│   │   ├── Parser/
│   │   │   ├── Parser.swift         Public Parser API
│   │   │   ├── Lexer.swift          Token stream
│   │   │   ├── EncodingChars.swift  Delimiter detection
│   │   │   └── ParseError.swift     Public error type
│   │   ├── Builder/
│   │   │   ├── MessageBuilder.swift Public builder API
│   │   │   ├── Serializer.swift     AST → wire bytes
│   │   │   └── Escape.swift         v2 escape sequence handling
│   │   ├── Path/
│   │   │   ├── Path.swift           Path parser ("PID-5.1.2")
│   │   │   └── Subscript.swift      Message subscript implementations
│   │   ├── Validation/
│   │   │   ├── Validator.swift      Public Validator API
│   │   │   ├── Grammar.swift        Segment grammar model
│   │   │   ├── DataType.swift       v2 data types (ST, NM, TS, CX, XPN, ...)
│   │   │   └── Issue.swift          ValidationIssue, Severity
│   │   ├── Encoding/
│   │   │   ├── CharacterEncoding.swift  MSH-18 → String.Encoding
│   │   │   └── EscapeSequences.swift
│   │   └── Internal/                Anything not @public
│   ├── HL7v2KitDictionaries/        Static segment grammar data (v2.3.1, 2.4, 2.5.1, 2.8)
│   │   ├── Resources/
│   │   │   ├── v2_3_1.json
│   │   │   ├── v2_4.json
│   │   │   ├── v2_5_1.json
│   │   │   └── v2_8.json
│   │   └── Dictionaries.swift       Public accessor for the bundled JSON
│   └── HL7v2KitCodegen/             Build-time tool: HL7 schemas → typed Swift structs
│       └── main.swift               Executable target (not shipped in library)
├── Tests/
│   ├── HL7v2KitTests/
│   │   ├── ParsingTests.swift
│   │   ├── BuilderTests.swift
│   │   ├── RoundTripTests.swift     Property-based: parse → build → bytes identical
│   │   ├── PathTests.swift
│   │   ├── TypedAccessorTests.swift
│   │   ├── ValidationTests.swift
│   │   ├── ZSegmentTests.swift
│   │   ├── EncodingTests.swift
│   │   └── GoldenFileTests.swift    Snapshot tests against fixture corpus
│   ├── HL7v2KitDictionariesTests/
│   │   └── DictionaryLoadingTests.swift
│   └── Fixtures/
│       ├── adt/                     ADT_A01, A02, A04, A08, A11, A28
│       ├── orm/                     ORM_O01 (eRequesting)
│       ├── oru/                     ORU_R01 (pathology + radiology)
│       ├── ack/                     ACK
│       ├── au-pathology/            AU PIT-flavoured pathology samples
│       ├── au-radiology/            AU radiology RIS samples
│       ├── malformed/               Bad inputs for error tests
│       └── README.md                Provenance, licensing, anonymisation log per file
├── docs/
│   ├── DocC/
│   │   └── HL7v2Kit.docc/
│   │       ├── HL7v2Kit.md          Top-level landing page
│   │       ├── Articles/
│   │       │   ├── GettingStarted.md
│   │       │   ├── ParsingAMessage.md
│   │       │   ├── BuildingAMessage.md
│   │       │   ├── ValidationGuide.md
│   │       │   └── ZSegmentHandling.md
│   │       └── Resources/
│   └── design/
│       ├── architecture-decisions.md#adr-001-ast-model     Architecture Decision Records
│       ├── architecture-decisions.md#adr-002-error-strategy
│       └── architecture-decisions.md#adr-003-z-segment-policy
└── scripts/
    ├── anonymise-fixture.sh         Wrapper CLI (HL7v2KitAnonymise target): scrub PHI
    ├── regenerate-dictionaries.sh   Pull HL7 v2 schemas, regenerate JSON
    └── regenerate-typed-segments.sh Run codegen → Sources/HL7v2Kit/Segment/Generated/
```

> **As-built (2026-08-27):** the tree above is the v0.1 sketch. `HL7v2KitDictionaries` (+ its
> test target) shipped only as a placeholder and was **retired at the 2.0 boundary** (ADR-005
> addendum; remediation R10) — grammar ships as codegen-emitted Swift tables inside `HL7v2Kit`.
> `regenerate-dictionaries.sh` was never written; the live scripts are
> `regenerate-typed-segments.sh`, `extract-segment-tables.swift`, `audit-schemas.py`,
> `anonymise-fixture.sh`, and `scan-fixtures-for-phi.sh`.

---

## 4. Public API surface — v0.1.0

> **As-built (2026-08-27):** the listings below are the v0.1 sketches; the shipped surface is
> inventoried in `public-api-surface.md` and the 2.0 deltas in `Migration.md` → "The 2.0
> boundary". Divergences to read past: `ParserOptions.preserveExcessFields` (shipped as a
> documented no-op) and the `.lenient` preset (as-built it equalled `.default`) were **removed
> at 2.0** — the as-built default `lineTerminator` is `.lenient`, not `.strict`;
> `ParseError.malformedField`, `BuilderError.invalidEncodingCharacters`/`.duplicateMSH`, and
> `MessageBuilder.append(unknown:)` shipped but were never exercised and were **removed at
> 2.0**; the as-built `IssueCode` is a non-raw-value open enum (ADR-014) whose cases diverged
> from this sketch (`unknownSegment` removed at 2.0 — no-grammar segments route to
> `.zSegmentPresent`); `Batch` shipped as `BatchFile` with grouped `batches`. Full story:
> `remediation-plan.md` (R10).

This is the contract. Adding to it post-1.0 is fine. Removing or changing semantics requires a major version bump (semver).

### 4.1 Top-level types

```swift
/// A parsed HL7 v2 message. Lossless: round-trips to wire bytes byte-for-byte
/// when the original was syntactically valid.
public struct Message: Sendable, Equatable {
    public let version: Version              // e.g. .v2_5_1
    public let encodingCharacters: EncodingCharacters
    public let segments: [Segment]

    /// String-path subscript (ad-hoc access).
    /// Examples: msg["MSH-9"], msg["PID-5.1"], msg["OBX[2]-5.1.1"]
    public subscript(path: String) -> String? { get }

    /// Strongly-typed path subscript (compile-time-checked construction).
    public subscript(path: Path) -> String? { get }

    /// Find the first segment of a given type.
    public func firstSegment<S: TypedSegment>(_ type: S.Type) -> S?

    /// Find all segments of a given type, in document order.
    public func allSegments<S: TypedSegment>(_ type: S.Type) -> [S]

    /// Serialise back to wire bytes using the original encoding characters.
    public func serialize() -> Data
}

public enum Version: String, Sendable, CaseIterable {
    case v2_3_1 = "2.3.1"
    case v2_4   = "2.4"
    case v2_5_1 = "2.5.1"
    case v2_8   = "2.8"
}

/// The five encoding characters from MSH-1 and MSH-2.
public struct EncodingCharacters: Sendable, Equatable {
    public let fieldSeparator: Character        // default "|"
    public let componentSeparator: Character    // default "^"
    public let repetitionSeparator: Character   // default "~"
    public let escapeCharacter: Character       // default "\\"
    public let subcomponentSeparator: Character // default "&"

    public static let `default` = EncodingCharacters(
        fieldSeparator: "|",
        componentSeparator: "^",
        repetitionSeparator: "~",
        escapeCharacter: "\\",
        subcomponentSeparator: "&"
    )
}
```

### 4.2 Segment hierarchy

```swift
/// Type-erased segment. Every segment in a Message is one of these.
public enum Segment: Sendable, Equatable {
    case typed(any TypedSegment)
    case unknown(UnknownSegment)

    /// 3-character segment identifier (MSH, PID, OBR, ZAU, ...).
    public var segmentID: String { get }

    /// Raw field access — works for both typed and unknown segments.
    public func field(_ index: Int) -> Field?
}

/// Marker protocol implemented by all code-generated segment structs.
public protocol TypedSegment: Sendable, Equatable {
    static var segmentID: String { get }
    var fields: [Field] { get }
}

/// Fallback for any segment not defined in the loaded grammar
/// (typically Z-segments like ZAU, ZPI, ZMH).
public struct UnknownSegment: Sendable, Equatable {
    public let segmentID: String
    public let fields: [Field]
}
```

### 4.3 Field model

The AST must be lossless. That means every layer of nesting that exists on the wire is represented as a distinct node, even if most fields only use one layer.

```swift
/// A field is a sequence of repetitions. Single-value fields have one repetition.
public struct Field: Sendable, Equatable {
    public let repetitions: [Repetition]

    /// Convenience: the first repetition (most fields are single-valued).
    public var first: Repetition? { repetitions.first }
}

/// One repetition of a field. Contains one or more components.
public struct Repetition: Sendable, Equatable {
    public let components: [Component]

    /// Convenience: returns the rendered value if this repetition is a single
    /// scalar (one component, one subcomponent, plain text).
    public var stringValue: String? { get }
}

public struct Component: Sendable, Equatable {
    public let subcomponents: [Subcomponent]

    public var stringValue: String? { get }
}

public struct Subcomponent: Sendable, Equatable {
    /// The unescaped string value. Escape sequences in the original wire
    /// bytes are decoded; serialisation re-encodes them.
    public let value: String
}
```

### 4.4 Path API

Path strings follow the standard HL7 v2 dotted notation:

```
SEG-F[.C[.S]][~R]
SEG[N]-F[.C[.S]][~R]
```

Examples:

| Path | Meaning |
|---|---|
| `MSH-9` | Field 9 of MSH (message type) |
| `MSH-9.1` | Component 1 of MSH-9 (message code) |
| `MSH-9.2` | Component 2 of MSH-9 (trigger event) |
| `PID-3` | Field 3 of PID (all repetitions) |
| `PID-3~1` | First repetition of PID-3 |
| `PID-3~2.4` | Component 4 of the second repetition of PID-3 |
| `PID-5.1.1` | Subcomponent 1 of component 1 of PID-5 |
| `OBX[2]-5` | Field 5 of the second OBX segment in the message |
| `ZAU-3` | Field 3 of the (Z-segment) ZAU |

```swift
/// A parsed, structurally-validated v2 path.
public struct Path: Sendable, Equatable, ExpressibleByStringLiteral {
    public let segmentID: String
    public let segmentIndex: Int?       // 1-based; nil = first occurrence
    public let field: Int               // 1-based field index
    public let repetition: Int?         // 1-based; nil = first repetition
    public let component: Int?          // 1-based; nil = whole field
    public let subcomponent: Int?       // 1-based; nil = whole component

    /// Throwing parser for runtime use.
    public init(_ string: String) throws

    /// Non-throwing parser used by ExpressibleByStringLiteral.
    /// Crashes on malformed literals at compile time / first use.
    public init(stringLiteral value: String)
}

public enum PathError: Error, Equatable, Sendable {
    case malformed(input: String, position: Int)
    case invalidSegmentID(String)
    case invalidIndex(String)
}
```

The subscript on `Message` returns `String?` — present and stringable, or absent. Callers needing structured access (repetitions, raw subcomponents) use `firstSegment(_:)` / typed accessors instead.

### 4.5 Typed segment structs (code-generated)

These are generated from the HL7 v2 schemas by `HL7v2KitCodegen`. Each segment ships as a struct with named fields:

```swift
/// Patient Identification segment (HL7 v2.5.1).
/// Generated; do not edit by hand. Regenerate via scripts/regenerate-typed-segments.sh
public struct PID: TypedSegment, Sendable, Equatable {
    public static let segmentID = "PID"
    public let fields: [Field]

    public var setID: String? { get }                       // PID-1
    public var patientIDExternal: Field? { get }            // PID-2  (deprecated in 2.5.1)
    public var patientIdentifierList: Field? { get }        // PID-3  (CX type, repeats)
    public var alternatePatientID: Field? { get }           // PID-4  (deprecated)
    public var patientName: Field? { get }                  // PID-5  (XPN, repeats)
    public var mothersMaidenName: Field? { get }            // PID-6
    public var dateTimeOfBirth: String? { get }             // PID-7  (TS)
    public var administrativeSex: String? { get }           // PID-8
    // ... and so on for all 40 PID fields
}
```

**Convention:** typed accessors return `Field?` when the field is structured (XPN, CX, XAD, etc.) so callers get the full AST. They return `String?` only for genuinely scalar fields (NM, ST, ID, DT, TS where the timestamp is taken as a single string).

**Why not return typed sub-structures (e.g. `XPN` for patient name)?** v0.1.0 keeps the field-typing simple. Returning structured Swift types for every v2 composite data type (XPN, CX, XAD, XTN, ED, CWE, ...) is a v0.2.0 feature — too much surface area to lock in before real-world use. Callers in v0.1.0 access components via `patientName?.first?.components[0]` or via paths.

### 4.6 Parser API

```swift
public struct Parser: Sendable {
    public init(options: ParserOptions = .default)

    /// Parse a single message from raw bytes. Encoding is detected from
    /// MSH-18, defaulting to UTF-8 if absent or unrecognised.
    public func parse(_ data: Data) throws -> Message

    /// Parse a single message from a string (assumes already-decoded text).
    public func parse(_ string: String) throws -> Message

    /// Parse a batch file (FHS/BHS framed) into individual messages.
    public func parseBatch(_ data: Data) throws -> Batch

    /// Stream-parse a sequence of MLLP-framed messages.
    /// Provided as a convenience; HL7v2Kit does NOT do network I/O.
    public func parseMLLPStream<S: AsyncSequence>(
        _ bytes: S
    ) -> AsyncThrowingStream<Message, Error>
        where S.Element == UInt8
}

public struct ParserOptions: Sendable {
    /// If true, segments not in the loaded grammar parse as UnknownSegment.
    /// If false, they raise ParseError.unknownSegment.
    /// Default: true (Z-segment tolerance).
    public var allowUnknownSegments: Bool

    /// HL7 version to use for typed segment hydration. If nil, version is
    /// read from MSH-12.
    public var versionOverride: Version?

    /// If true, segment field counts beyond what the grammar defines are
    /// preserved as anonymous fields. Default: true (forward compatibility).
    public var preserveExcessFields: Bool

    /// Whitespace tolerance at segment boundaries.
    /// Default: .strict (one \r between segments).
    public var lineTerminator: LineTerminatorPolicy

    public static let `default`: ParserOptions
    public static let lenient: ParserOptions   // Z-segments OK, accepts \r\n and \n
    public static let strict: ParserOptions    // grammar-perfect, no leniency
}

public enum LineTerminatorPolicy: Sendable, Equatable {
    case strict          // \r only (per HL7 standard)
    case lenient         // any of \r, \n, \r\n accepted
}

public enum ParseError: Error, Equatable, Sendable, CustomStringConvertible {
    case emptyInput
    case missingMSH
    case invalidMSH(reason: String)
    case unsupportedVersion(found: String)
    case unknownSegment(id: String, position: Int)
    case malformedField(segment: String, fieldIndex: Int, reason: String)
    case unsupportedCharacterEncoding(declared: String)
    case truncatedMessage(atByte: Int)

    public var description: String { get }   // Human-readable, includes byte offset
}

public struct Batch: Sendable, Equatable {
    public let fileHeader: Segment?    // FHS, optional
    public let batchHeader: Segment?   // BHS, optional
    public let messages: [Message]
    public let batchTrailer: Segment?  // BTS
    public let fileTrailer: Segment?   // FTS
}
```

### 4.7 Builder API

```swift
public struct MessageBuilder: Sendable {
    public init(
        version: Version,
        encodingCharacters: EncodingCharacters = .default
    )

    /// Append a typed segment.
    public mutating func append<S: TypedSegment>(_ segment: S)

    /// Append from a Z-segment or otherwise unknown segment.
    public mutating func append(unknown: UnknownSegment)

    /// Append from raw field data.
    public mutating func appendSegment(id: String, fields: [Field])

    /// Build the final Message. Throws if required segments (MSH) are missing.
    public func build() throws -> Message
}

/// Fluent helpers for constructing common segments without touching the AST.
public extension MessageBuilder {
    @discardableResult
    mutating func msh(
        messageType: (code: String, triggerEvent: String),
        sendingApplication: String? = nil,
        sendingFacility: String? = nil,
        receivingApplication: String? = nil,
        receivingFacility: String? = nil,
        messageControlID: String,
        processingID: String = "P"
    ) -> Self
}

public enum BuilderError: Error, Equatable, Sendable {
    case missingMSH
    case invalidEncodingCharacters
    case duplicateMSH
}
```

### 4.8 Validator API

```swift
public struct Validator: Sendable {
    public init(options: ValidationOptions = .default)

    /// Validate a parsed Message against the loaded grammar.
    /// Returns all issues — does not throw on validation failure.
    public func validate(_ message: Message) -> ValidationReport
}

public struct ValidationOptions: Sendable {
    /// Version of the v2 grammar to validate against. If nil, taken from MSH-12.
    public var versionOverride: Version?

    /// How to treat unknown segments (Z-segments).
    public var zSegmentPolicy: ZSegmentPolicy

    /// Validate v2 data types (TS, NM, DT, etc.).
    public var validateDataTypes: Bool

    /// Validate required field cardinalities per segment grammar.
    public var validateCardinality: Bool

    /// Maximum issues to collect before stopping (perf guard).
    public var maxIssues: Int

    public static let `default`: ValidationOptions
    public static let strict: ValidationOptions    // every check on, maxIssues = .max
}

public enum ZSegmentPolicy: Sendable, Equatable {
    case ignore              // skip entirely
    case warnPresence        // emit a .info issue per Z-segment found
    case structural          // check field structural integrity only, no grammar
}

public struct ValidationReport: Sendable, Equatable {
    public let issues: [ValidationIssue]
    public var isValid: Bool { !issues.contains { $0.severity == .error } }
    public var hasWarnings: Bool { issues.contains { $0.severity == .warning } }
}

public struct ValidationIssue: Sendable, Equatable {
    public let severity: Severity
    public let location: Location
    public let code: IssueCode
    public let message: String
}

public enum Severity: Sendable, Equatable {
    case info
    case warning
    case error
}

public struct Location: Sendable, Equatable {
    public let segmentID: String
    public let segmentIndex: Int       // 1-based position in message
    public let field: Int?
    public let component: Int?
    public let subcomponent: Int?

    public var pathString: String { get }   // "PID[1]-5.1.2"
}

public enum IssueCode: String, Sendable, CaseIterable {
    case requiredFieldMissing
    case fieldCardinalityExceeded
    case unknownSegment
    case invalidDataType
    case invalidTimestamp
    case unrecognizedCodedValue        // info-level — table lookups are deferred
    case excessFieldsPresent           // forward-compat fields beyond grammar
    case malformedEscapeSequence
}
```

### 4.9 Errors — design notes

- All public errors are enums with associated values. No `Error`-wrapping or string-only errors.
- All public errors conform to `Equatable` and `Sendable`. Tests assert on specific cases.
- `ParseError` is fatal (input cannot be parsed). `ValidationIssue` is non-fatal (the AST is good, but content fails the grammar). This distinction is load-bearing.
- All errors carry enough context to identify the byte offset or field position. "Parse failed" with no location is not acceptable.

---

## 5. Round-trip guarantee

The single most important property test:

```swift
@Test
func roundTripPreservesBytes_realWorldFixtures() throws {
    for url in Fixtures.allValid() {
        let original = try Data(contentsOf: url)
        let parsed = try Parser().parse(original)
        let rebuilt = parsed.serialize()
        #expect(rebuilt == original,
                "Round-trip changed bytes for \(url.lastPathComponent)")
    }
}
```

This must pass for every fixture in the corpus that the parser accepts. If a fixture round-trips imperfectly, either:

1. The fixture is genuinely malformed → move it to `Fixtures/malformed/`.
2. The AST is lossy → fix the AST, not the test.

Acceptable deviations from byte-perfect round-trip in v0.1.0 (documented exceptions):

- **Trailing whitespace** within a segment is preserved (load-bearing for some AU senders).
- **Empty trailing fields.** A message ending with `|||\r` after PID-39 round-trips identically; the parser does NOT collapse trailing empty fields.
- **Whitespace inside fields** is preserved exactly.
- **Encoding character roundtrip.** If MSH-2 contains the standard `^~\&`, the builder writes exactly `^~\&`, not a normalised form.

Non-acceptable deviations (must round-trip exactly):

- Field count (no implicit truncation).
- Escape sequences (`\F\`, `\S\`, `\T\`, `\R\`, `\E\`, `\X..\`, `\Z..\`).
- Repetition order.
- Z-segment content.

---

## 6. Z-segment tolerance — the AU angle

AU senders frequently include custom Z-segments:

| Common AU Z-segments | Where seen |
|---|---|
| ZAU | Generic AU extension; varied semantics by sender |
| ZPI / ZPD | Patient supplementary data |
| ZMH | Medicare-related fields |
| ZBR | Billing reference (some pathology labs) |
| ZRX | Prescription supplementary (community pharmacy) |
| ZOR / ZBE / ZIN | Various lab and imaging extensions |

**v0.1.0 behaviour:**

- Default: parsed as `UnknownSegment`. Fields are split by the encoding characters but not validated against any grammar.
- `ValidationOptions.zSegmentPolicy = .warnPresence` emits an `.info` issue per Z-segment so consumers can audit usage.
- A future `HL7v2KitAUExtensions` package (v0.x) ships AU-specific Z-segment grammars contributed by the community. Not part of v0.1.0.

**What the library does not do:** guess at Z-segment semantics. There is no "AU Z-segment auto-recognition" magic. Every Z-segment is an `UnknownSegment` until a consumer maps it explicitly.

---

## 7. Code generation strategy

Typed segment structs are code-generated, not handwritten. Reasoning:

- HL7 v2.5.1 has ~140 segments and ~1,100 fields. Hand-maintaining the typed accessors is a maintenance trap.
- HL7 publishes the v2 schemas as well-formed XML (and the HL7 v2-to-FHIR project also exposes them as JSON).
- Codegen lets us add v2.7 / v2.9 in the future by adding an input file, not by writing Swift.

### 7.1 Codegen pipeline

1. **Input:** HL7 v2 schema XML / JSON per version, checked into the repo at `Resources/schemas/`.
2. **Tool:** `HL7v2KitCodegen` executable target. Invoked by `scripts/regenerate-typed-segments.sh`.
3. **Output:** `Sources/HL7v2Kit/Segment/Generated/<Version>/<SegmentID>.swift`.
4. **CI guard:** a GitHub Actions job runs codegen on every PR and fails if the generated files would change. This forces contributors to regenerate when schemas update.

### 7.2 Why not use Swift macros?

Swift Macros could theoretically generate segment structs at compile time from the schema. Rejected because:

- Compile-time macro evaluation is slow at this scale (140 segments × 4 versions).
- Macros obscure the generated code from contributors browsing the source.
- The generated files in source control double as documentation.

Hand-written code generator (`HL7v2KitCodegen`) is simpler and the right call for v0.1.0.

---

## 8. Dictionaries module

> **As-built (2026-08-27):** superseded by **ADR-005 Path C** — the grammar ships as
> codegen-emitted Swift tables (`SegmentGrammar+vX_Y_Z.swift`) inside the `HL7v2Kit` target;
> the JSON schemas live at repo-root `Resources/schemas/` as the **codegen input**, not a
> runtime resource. The placeholder `HL7v2KitDictionaries` target this section proposes was
> retired at the 2.0 boundary (remediation R10). The JSON format sketch below survives as the
> schema-authoring format.

`HL7v2KitDictionaries` is a separate target that ships the static segment grammar as JSON resources. Two reasons it's separate:

1. **Resource isolation.** Swift Package Manager resource bundling is target-scoped. Keeping JSON in its own target avoids polluting the main module's bundle.
2. **Optional consumption.** Future consumers wanting only the parser/AST can depend on `HL7v2Kit` directly; consumers needing validation pull in `HL7v2KitDictionaries`.

JSON format (sketch):

```json
{
  "version": "2.5.1",
  "segments": {
    "PID": {
      "description": "Patient Identification",
      "fields": [
        {
          "index": 1,
          "name": "Set ID - PID",
          "dataType": "SI",
          "optionality": "O",
          "repeatability": "1",
          "length": 4
        },
        {
          "index": 3,
          "name": "Patient Identifier List",
          "dataType": "CX",
          "optionality": "R",
          "repeatability": "*",
          "length": 250
        }
      ]
    }
  },
  "dataTypes": {
    "CX": {
      "components": [
        { "index": 1, "name": "ID Number", "dataType": "ST" },
        { "index": 2, "name": "Check Digit", "dataType": "ST" }
      ]
    }
  }
}
```

---

## 9. Testing strategy

### 9.1 Test taxonomy

| Tier | Framework | Examples | Run when |
|---|---|---|---|
| Unit | Swift Testing | Each parser branch, escape sequence handling, single-segment parses | Every PR |
| Property | Swift Testing + custom generators | Round-trip, idempotence | Every PR |
| Golden file | Swift Testing | Snapshot of typed accessor output for known fixtures | Every PR |
| Fuzz | Swift Testing + corpus replay | Random byte mutations against valid fixtures | Nightly CI |
| Performance | Swift Testing benchmarks | 1,000-message batch parse < 5s on M-series | Nightly CI |

### 9.2 Test fixture corpus

This is the single most valuable artefact in the package — more valuable than the code. Real-world v2 fixtures that round-trip correctly are the reason consumers will trust the library.

**Sourcing rules:**

- Every fixture is documented in `Tests/Fixtures/README.md` with:
  - Original source (synthetic, donated by a vendor, public sample data, etc.)
  - Licence (CC-BY-4.0 / Apache 2.0 / public domain)
  - Anonymisation log (what was scrubbed, by what rule)
  - Sender context (vendor, AU jurisdiction, message type)
- No fixture contains real PHI. Period. The `scripts/anonymise-fixture.sh` tool enforces this — see §10.
- Synthetic AU pathology fixtures generated from the AU Core test data published by HL7 Australia are the safest starting point.
- Donated fixtures require a written waiver from the donor confirming the data is non-PHI synthetic / test data.

**Target fixture count for v0.1.0:**

| Category | Count | Notes |
|---|---|---|
| ADT_A01 (admit) | 5 | Mix of AU hospital senders |
| ADT_A04 (register) | 3 | |
| ADT_A08 (update) | 3 | |
| ORM_O01 (eRequesting) | 5 | AU eRequesting-flavoured |
| ORU_R01 (pathology) | 8 | Includes PIT-style and Sonic, ACL, Healius, QML formats |
| ORU_R01 (radiology) | 5 | RIS-style with embedded images deferred |
| ACK | 2 | |
| Z-segment heavy | 5 | Real-world AU senders |
| Malformed (parse should fail) | 6 | Catch regressions in error paths |
| Edge cases | 6 | Empty fields, max field counts, escape soup |
| **Total** | **48** | Minimum for v0.1.0 |

### 9.3 Round-trip property test

Already shown in §5. The single highest-priority test.

### 9.4 Path / typed accessor cross-check

For every fixture, every documented path returns the same string the typed accessor returns:

```swift
@Test
func pathAndTypedAccessor_returnIdenticalValues() throws {
    for url in Fixtures.allValid() {
        let msg = try Parser().parse(Data(contentsOf: url))
        if let pid = msg.firstSegment(PID.self) {
            #expect(msg["PID-1"] == pid.setID)
            #expect(msg["PID-3"] == pid.patientIdentifierList?.first?.stringValue)
            #expect(msg["PID-5.1"] == pid.patientName?.first?.components[0].stringValue)
            // ...
        }
    }
}
```

### 9.5 Performance budget (nightly)

| Operation | Budget on Apple Silicon M1+ |
|---|---|
| Parse 1 message (1KB) | < 1ms (warm) |
| Parse 1,000 messages (avg 1KB each) | < 5s |
| Round-trip 1,000 messages | < 10s |
| Validate 1 message (default options) | < 2ms |
| Validate 1,000 messages | < 10s |

Performance regressions of >20% on these numbers fail the nightly build.

---

## 10. Anonymisation tool (`scripts/anonymise-fixture.sh`)

Mandatory companion script. Refuses to add any fixture to the test corpus that hasn't been processed through it.

**Scrubbing rules:**

- All identifiers in `PID-3` replaced with synthetic values matching the original type structure (IHI 16-digit format preserved, Medicare 11-digit format preserved, etc.).
- All name components (`PID-5`, `PID-6`, `PID-9`, `NK1-2`, `IN1-16`) replaced from a fixed synthetic name list (deterministically, so the same input name produces the same output name in the same fixture).
- Dates of birth shifted by a per-file random offset, preserving day-of-week and approximate age.
- All addresses replaced with synthetic AU addresses (real AU suburb + postcode, fake street).
- All phone numbers replaced (61-2-1234-5678 patterns kept structurally valid).
- All free-text fields (OBX-5 narrative, NTE-3) replaced with `[REDACTED]` unless explicitly whitelisted (e.g., synthetic clinical findings from public test datasets).
- Healthcare provider names and IDs replaced.
- All MSH-3 / MSH-4 / MSH-5 / MSH-6 sender/receiver identifiers replaced with synthetic facility names.

**CI enforcement:**

- A GitHub Actions check scans all `.hl7` files in `Tests/Fixtures/` against a regex blacklist (real-looking 10-digit Medicare numbers in the IHI position, etc.). Build fails on hits.
- Quarterly manual audit by the maintainer.

This is non-negotiable. A single PHI leak in a public open-source repo would end the side project and trigger OAIC reporting.

---

## 11. Documentation plan

### 11.1 README.md

Structure (in this order):

1. One-sentence pitch ("A native Swift package for parsing, building, and validating HL7 v2 messages.")
2. Three-line "why use this" — round-trip safe, AU-aware Z-segment handling, both path and typed APIs.
3. Quickstart code block — parse → access → validate → serialize, all in 10 lines.
4. Installation (SPM `package` snippet).
5. Supported platforms and Swift version table.
6. Link to full DocC.
7. Status badge (CI passing, Swift versions, platforms).
8. Roadmap (high-level).
9. Contributing pointer.
10. Licence (Apache 2.0).

### 11.2 DocC catalogue

Articles to write:

- `GettingStarted.md` — 5-minute tutorial.
- `ParsingAMessage.md` — full parser usage including options.
- `BuildingAMessage.md` — builder API, fluent helpers.
- `PathSyntax.md` — full path grammar reference.
- `TypedAccessors.md` — when to use which API.
- `ValidationGuide.md` — interpreting issues, choosing options.
- `ZSegmentHandling.md` — AU-specific guidance.
- `EncodingAndEscaping.md` — character encoding pitfalls (MSH-18, escape sequences, Unicode).

DocC publishes automatically to GitHub Pages on every `main` push.

### 11.3 ADRs (Architecture Decision Records)

Lightweight markdown files under `docs/design/`. Each ADR records a single decision with context, options considered, decision, and consequences. Initial set:

- **ADR-001:** AST model — lossless field hierarchy with explicit Repetition/Component/Subcomponent.
- **ADR-002:** Error strategy — split ParseError (fatal) vs ValidationIssue (non-fatal).
- **ADR-003:** Z-segment policy — default to UnknownSegment, never guess semantics.
- **ADR-004:** Typed segments by code generation, not macros.
- **ADR-005:** Dictionaries as a separate target.

ADRs are append-only. Superseded ADRs link forward to the replacement.

---

## 12. Versioning, release & support

### 12.1 Semver policy

- **Pre-1.0 (0.x.y):** patch releases (0.1.0 → 0.1.1) are bug-fix-only; minor releases (0.1.0 → 0.2.0) may break source compatibility, documented in CHANGELOG.
- **1.0.0:** declared when at least 10 external GitHub stars + 1 external production user + 3 months of post-0.1.0 stability with no API breaks. Targets month 9 to 12 of the AU Core Workbench project.
- **Post-1.0:** strict semver. Breaking changes are major; additions are minor; bug fixes are patch.

### 12.2 Release process

1. Update `CHANGELOG.md` (Keep-a-Changelog format).
2. Tag the commit `vX.Y.Z`.
3. Push tag — GitHub Actions publishes the release with changelog excerpt as release notes.
4. DocC site regenerates and deploys.
5. Tweet / LinkedIn / newsletter mention.

No publishing to a package registry — Swift Package Manager consumes directly from GitHub tags.

### 12.3 Branching

- `main` is always green.
- Feature work happens on `feature/<short-name>` branches (or git worktrees per the founder's preferred workflow).
- No long-lived `develop` branch. Trunk-based development.
- Release branches (`release/0.1.x`) created only when supporting multiple major versions in parallel becomes necessary (not before 1.0).

### 12.4 Support policy

- Pre-1.0: best-effort. No SLA.
- 1.0+: latest minor version receives bug fixes for 12 months from release.
- Security issues at all versions: triage within 14 days; patch within 30 days.

---

## 13. Package.swift

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HL7v2Kit",
    platforms: [
        .macOS(.v12),    // Note: BELOW the app's deployment target.
        .iOS(.v15),      // The package is reusable on iOS even if AUCW isn't.
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "HL7v2Kit", targets: ["HL7v2Kit"]),
        .library(name: "HL7v2KitDictionaries", targets: ["HL7v2KitDictionaries"]),
    ],
    dependencies: [
        // No runtime dependencies. Intentional.
        // Test-only dependencies allowed below.
    ],
    targets: [
        .target(
            name: "HL7v2Kit",
            dependencies: ["HL7v2KitDictionaries"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
        .target(
            name: "HL7v2KitDictionaries",
            resources: [
                .process("Resources"),
            ]
        ),
        .executableTarget(
            name: "HL7v2KitCodegen",
            dependencies: ["HL7v2KitDictionaries"]
        ),
        .testTarget(
            name: "HL7v2KitTests",
            dependencies: ["HL7v2Kit"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
        .testTarget(
            name: "HL7v2KitDictionariesTests",
            dependencies: ["HL7v2KitDictionaries"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
```

**Design notes on Package.swift:**

- **No runtime dependencies.** A foundational library should not pull in transitive deps. Stays Apache 2.0 clean and easy to audit.
- **Deployment target lower than the app.** AU Core Workbench targets macOS 14+, but HL7v2Kit targets macOS 12+ so the package is reusable for other consumers (server-side validators, older macOS apps, iOS apps). The app simply uses newer-platform features in its own code, not in HL7v2Kit.
- **Strict Concurrency on.** All public types are Sendable. Caught early, not retrofitted.
- **Swift 6 language mode.** Concurrency-safe by default. New AU Core Workbench project — no legacy to drag along.

---

## 14. CI matrix (`.github/workflows/ci.yml`)

```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request: { branches: [main] }

jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        os: [macos-14, macos-15]
        swift: ["6.0", "6.1"]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v5
      - uses: swift-actions/setup-swift@v3
        with: { swift-version: ${{ matrix.swift }} }
      - run: swift build -v
      - run: swift test -v

  lint:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v5
      - run: swiftlint --strict

  fixture-safety:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - run: ./scripts/scan-fixtures-for-phi.sh   # regex check; fails build on hit

  codegen-drift:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v5
      - run: ./scripts/regenerate-typed-segments.sh
      - run: |
          if [[ -n "$(git status --porcelain Sources/HL7v2Kit/Segment/Generated)" ]]; then
            echo "Generated files are stale. Run regenerate-typed-segments.sh and commit."
            exit 1
          fi
```

---

## 15. v0.1.0 release acceptance criteria

These are the binary "ship or don't ship" gates. All must be green.

- All 48 fixtures parse successfully.
- All 48 valid fixtures round-trip byte-perfectly.
- Codegen passes — no drift between schemas and generated Swift.
- Documentation: README complete, DocC builds, all 8 articles published.
- All public types and methods have DocC comments.
- CI matrix all green on macOS 14 + 15, Swift 6.0 + 6.1.
- Zero compiler warnings under strict concurrency.
- 80%+ line coverage on `Sources/HL7v2Kit/`.
- Test fixture corpus passes the PHI-scan check.
- Apache 2.0 LICENSE in repo.
- `CHANGELOG.md` entry written.
- Announcement post drafted (publishes alongside the GitHub release).

---

## 16. v0.2.0+ roadmap (not for this release)

Captured here so consumers know what's coming but won't ship with v0.1.0:

- **Typed v2 data types.** XPN, XAD, CX, XTN, ED, CWE, FT, etc. as Swift structs with named components.
- **HL7v2KitAUExtensions companion package.** Community-contributed AU Z-segment grammars (ZAU, ZPI, ZMH, ZBR).
- **MLLP server primitives.** Bytestream → message stream with frame validation. Direct-build only.
- **Streaming parser** for very large batch files (memory-bounded).
- **Linux support** validated in CI (technically works in 0.1.0 since no Apple-only dependencies, but not actively tested).
- **HL7 v2.7 and v2.9 grammars.**
- **Performance optimisation** — SIMD field tokenisation for >100MB batch files.

---

## 17. Implementation order (sprint plan)

This maps to weeks 3 to 6 of the AU Core Workbench MVP plan. Each sprint is a week. Each sprint ends with passing tests and a green CI build before starting the next.

### Sprint 1 (week 3) — bootstrap + lexer

- Package skeleton, Package.swift, CI green with zero tests.
- README placeholder, LICENSE, CONTRIBUTING.
- Lexer producing segment/field/component/subcomponent tokens.
- 10 parse-only tests on synthetic fixtures.
- `EncodingCharacters` parsed from MSH-1, MSH-2.

### Sprint 2 (week 4) — AST + parser

- Field/Repetition/Component/Subcomponent types.
- `Parser.parse(_ data: Data) throws -> Message`.
- `UnknownSegment` for Z-segments.
- `Message["PID-5.1"]` path subscript.
- 20 parsing tests, mix of synthetic and 5 AU pathology fixtures.

### Sprint 3 (week 5) — builder + round-trip

- `MessageBuilder`, fluent `msh(...)` helper.
- `Message.serialize() -> Data`.
- Round-trip property tests on all loaded fixtures.
- All 48 fixtures sourced, anonymised, documented in Tests/Fixtures/README.md.
- PHI-scan CI job.

### Sprint 4 (week 6) — typed segments + validation + docs

- `HL7v2KitCodegen` executable; generated segment structs for v2.5.1 PID, MSH, OBR, OBX, NK1, PV1, AL1, NTE, ORC.
- (Other versions and segments code-generated; not all hand-verified in v0.1.0.)
- `Validator` with structural + cardinality + Z-segment policy checks.
- DocC catalogue with all 8 articles.
- v0.1.0 release tagged, announcement post drafted.

---

## 18. Open questions for v0.1.0

These are deferred to implementation but flagged here:

1. **`PID-5` — return `[Field]` or `Field` with repetitions?** Currently spec'd as `Field?` with `repetitions` inside. Confirm at first PID typed-accessor implementation.
2. **Date/timestamp parsing.** v0.1.0 returns TS fields as `String?`. Should we offer an opt-in `Date` parser via an extension? Probably yes, gated by a `parseTimestamps: Bool` option on `ParserOptions`. Defer the decision to sprint 4.
3. **Batch file parsing.** Included in the API surface above (FHS/BHS). Do real AU senders use batch framing, or just MLLP-streamed single messages? Survey 3 fixture donors before implementing in sprint 3.
4. **Character encoding fallback.** If MSH-18 is empty, default to UTF-8 (modern AU senders) or ISO-8859-1 (legacy)? Recommend UTF-8 with a warning issue on parse. Confirm at sprint 2.
5. **Error message localisation.** v0.1.0 ships English-only. Should error message strings be `String` (current spec) or `LocalizedStringKey`? Recommend String — error messages are for developers reading logs, not end users. Lock in.

---

## 19. Change log

| Version | Date | Changes |
|---|---|---|
| 0.1 (spec) | 2026-05-27 | Initial spec from chat-based design session. Scope locked from three planning answers (parse+build, structural+grammar+Z-tolerance, dual API). Sprint plan aligned to AU Core Workbench MVP weeks 3 to 6. |

---

*End of HL7v2Kit specification.*
