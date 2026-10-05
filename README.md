# HL7v2Kit

A native Swift package for **parsing, building, and validating** HL7 v2.x healthcare messages.

**Status:** `v1.0.0` — first stable release. The public API is frozen under SemVer (additive-only in `1.x`); see [CHANGELOG.md](CHANGELOG.md), [ROADMAP.md](ROADMAP.md), and the versioning contract in [`Migration.md`](Sources/HL7v2Kit/HL7v2Kit.docc/Migration.md).

## Why use this

- **Round-trip safe.** Parse a v2 message, modify it, serialise it — the bytes match (including escape sequences and the original character set).
- **Spec-faithful validation.** Per-version field grammar for v2.3 → v2.8.2, a conditional-field DSL, cross-segment / message-context rules, group-scope cardinality (AU profile rules), and component-level checks. Message-level structure (segment order and groups per trigger event) is checked on all seven versions, as warnings by default (`ValidationOptions.messageStructureSeverity`); the residue is registered. Conformance gaps that can't be checked from the wire are documented, not silently skipped.
- **Australian-aware.** An `HL7Locale.auLocalisation` profile layers the ADRM-2021 (`HL7au`) narrowings on top of the base spec; AU Z-segments (ZAU, ZPI, …) round-trip without false negatives.
- **Two APIs, one AST.** String paths (`msg["PID-5.1"]`) for ad-hoc work, typed accessors (`msg.firstSegment(PID.self)?.patientName`) for known segments.
- **Zero runtime dependencies.** Pure Swift 6 + Foundation, strict concurrency on. Apache 2.0.

## Quickstart

```swift
import HL7v2Kit

let wire = Data(/* ... v2 bytes ... */)
let message = try Parser().parse(wire)

// Ad-hoc path access — works for any field.
let patientFamilyName = message["PID-5.1"]

// Typed accessors — for the segments HL7v2Kit ships dictionaries for.
let pid = message.firstSegment(PID.self)
let dob = pid?.dateTimeOfBirth                      // "19800101"
let name = pid?.patientName                          // XPN? (typed composite view)
let familyName = name?.familyName                    // "Smith"

// Validate against the message's declared version (MSH-12) + optional locale.
let report = Validator().validate(message)           // international rules
for issue in report.errors {
    print(issue.severity, issue.code, issue.location.pathDescription)
}
let auReport = Validator(locale: .auLocalisation).validate(message)

// Round-trip — serialised bytes equal the input.
let rebuilt = message.serialize()
assert(rebuilt == wire)
```

## Supported HL7 v2 versions

Per-version segment and field grammar + validation for **v2.3, v2.3.1, v2.4, v2.5.1, v2.6, v2.7.1 and v2.8.2** (the version is read from `MSH-12`; the AST itself is version-agnostic). A bare `2.8` or `2.7` wire has no text of its own and is validated against v2.8.2 or v2.7.1, with an info issue saying so; other versions fall back to v2.5.1 with a warning (see [ADR-018](docs/design/ADR-018-supported-version-set.md)). Segment coverage: **every version has zero missing segments** — all 188 segments the seven specs define are modelled on every version that defines them (the deferred backlog of [`docs/design/deferred-coverage-backlog.md`](docs/design/deferred-coverage-backlog.md) closed 2026-09-16). Every authored schema is verified against its own version's attribute table (depth, presence *and* per-field datatype) by `scripts/audit-schemas.py`. **Message structures:** segment order, segment groups and the segments each trigger event requires are checked against every structure the seven versions print (1,107 modelled, extracted from each version's own print and cited), as warnings in `ValidationOptions.default`, errors in `.strict` and off in `.lenient` (`messageStructureSeverity`). Structures the print gives no checkable syntax for (templates, placeholders, prose-only fragments, Table 0354 rows nothing prints) report one info issue with their reason (240 registered); the residue is registered in [`permanent-limitations-register.md` section E](docs/design/permanent-limitations-register.md) (ADR-019). Conditions that read a peer segment in the same group (ORC-2/3, OBR-2/3 and the group-scope cardinality rules) are scoped by the matched structure's own groups on a conformant message, falling back to the ORC walk otherwise. Under `.auLocalisation`, a v2.4 ORU^R01, ORM^O01, REF^I12, RRI^I12 or OSR^Q06 is also matched against the ADRM-2021 profile structure, which reports the segments it requires (HL7au:00060.1, partial) and governs the base findings.

## Typed segments & composites

**188 code-generated typed segment structs** — the ADT/ORU core (`MSH`, `PID`, `OBX`, `OBR`, …) through orders/pharmacy, scheduling, financial, master files, personnel, clinical trials, lab automation, queries, eClaims, materials management, and the batch envelopes (`BHS`/`FHS`/`BTS`/`FTS`) — generated from the canonical v2.5.1 schemas (`Resources/schemas/`), falling back to a segment's earliest defining version where v2.5.1 never defines it, and version-agnostic at runtime. Composite-typed fields return typed struct views with named accessors instead of raw `Field?`:

| Composite | Example accessors |
|---|---|
| `XPN` | `patientName?.familyName`, `.givenName` |
| `CX` | `patientIdentifierList?.id`, `.identifierTypeCode` |
| `XAD` | `patientAddress?.streetAddress` |
| `HD` / `MSG` / `PT` / `VID` / `EI` / `XCN` / `XON` / `PL` / `CNE` / `CWE` / `CE` / `EIP` / `XTN` | named component accessors |

Segment IDs without a typed struct (Z-segments, less-common segments) come back as `UnknownSegment` and stay fully accessible via path strings. See [`public-api-surface.md`](docs/design/public-api-surface.md) for the full public surface.

## Also included

- **MLLP codec** — a portable framing/unframing kernel (`MLLP`, `MLLPUnframer`).
- **Batch + streaming parsers** — `BatchParser` and `StreamingBatchParser` (`AsyncThrowingStream`) for large batch files.
- **Message builder** — `MessageBuilder` for programmatic construction.

## Installation

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/<your-org>/HL7v2Kit.git", from: "1.0.0")
```

Then add `"HL7v2Kit"` to your target's `dependencies`.

## Supported platforms

| Platform | Minimum |
|---|---|
| macOS | 12 |
| iOS | 15 |
| tvOS | 15 |
| watchOS | 8 |
| visionOS | 1 |
| Linux | No Apple-only dependencies — expected to work on Swift 6.0+ (not yet in CI) |

## Adding a typed segment

Typed segment structs are code-generated from JSON schemas:

1. Hand-curate `Resources/schemas/<version>/<SegmentID>.json` (copy an existing schema, e.g. `PID.json`, for the format).
2. Run `bash scripts/regenerate-typed-segments.sh` to emit the typed struct(s) and the per-version grammar tables.
3. Register hydration: add a `case <X>.segmentID: …` to `Sources/HL7v2Kit/Segment/SegmentRegistry.swift`.
4. Add a cross-check test in `Tests/HL7v2KitTests/TypedSegmentTests.swift` — path access and typed accessor must agree.

The codegen-drift CI job fails any commit that edits a schema without committing the regenerated output. Never hand-edit files under `Sources/HL7v2Kit/Segment/Generated/`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). **No PHI ever enters the repository** — all fixtures must be PHI-free synthetic data. (Real-world-derived fixtures must go through `scripts/anonymise-fixture.sh` and still pass the CI PHI scan.)

## Licence

Apache 2.0 — see [LICENSE](LICENSE).
