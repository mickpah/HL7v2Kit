# Migration

Per-release migration notes for HL7v2Kit consumers.

## Overview

HL7v2Kit is pre-1.0 (currently 0.1.0 development). Minor releases (0.x → 0.(x+1)) may make source-breaking changes, documented here. Patch releases (0.x.y → 0.x.(y+1)) are bug-fix-only with no API changes. Post-1.0, strict SemVer applies.

## From 0.0.x (none shipped) → 0.1.0

There is no prior released version. The first public release is 0.1.0.

## Toward 0.2.0 — already on `main`

The following changes have landed on `main` since the `v0.1.0` tag but have **not** been released under a `v0.2.0` tag yet. Consumers pinning to a commit (rather than a tag) will encounter them now; consumers using `from: "0.1.0"` see only v0.1.x patch versions and are unaffected until `v0.2.0` ships.

### Parser hardening (v0.2-P1 / P2 / P3)

Three byte-path strictness fixes for ``Parser/parse(_:)-(Data)``. None affects ``Parser/parse(_:)-(String)`` (the byte-path-only constraint was respected).

- **UTF-8 BOM prefix is explicitly stripped.** A leading `EF BB BF` is dropped before charset detection. On macOS, Foundation's `String(data:encoding:.utf8)` silently stripped this anyway; on Linux Swift it didn't, so the byte path used to behave differently across platforms. Now the strip happens in HL7v2Kit code and behaviour is portable. The serialiser never re-emits the BOM, so a round-trip canonicalises BOM-prefixed input. A BOM-only input throws ``ParseError/emptyInput`` after strip.
- **Embedded NUL bytes are rejected at parse time** with ``ParseError/truncatedMessage(atByte:)``. Real v2 wire never carries `0x00`; an embedded NUL is almost always transport truncation (a fixed-size buffer NUL-padded beyond the real message). Reported byte offset is into the post-BOM-strip payload. This change makes round-trip invariant 1 honest without a NUL carve-out: every accepted message is NUL-free.
- **``ParserOptions/rejectUnknownVersion`` (new flag).** When `true`, a non-empty MSH-12 value that doesn't map to a known ``Version`` throws ``ParseError/unsupportedVersion(found:)``. Default is `false` (silent fallback to `.v2_5_1`); ``ParserOptions/strict`` sets it `true`. Empty MSH-12 falls back regardless of the flag — emptiness is a Validator concern (MSH-12 has optionality `R`, not "must be a known version").

### Typed-segment coverage closure (v0.2-F1)

PID schema 30 → 39 fields; ORC schema 19 → 31 fields. Both segments are now spec-complete for v2.5.1. New accessors on ``PID``:

- `identityUnknownIndicator`, `identityReliabilityCode`, `lastUpdateDateTime`, `lastUpdateFacility`, `speciesCode`, `breedCode`, `strain`, `productionClassCode`, `tribalCitizenship`

New accessors on ``ORC``:

- `advancedBeneficiaryNoticeCode`, `orderingFacilityName`, `orderingFacilityAddress`, `orderingFacilityPhoneNumber`, `orderingProviderAddress`, `orderStatusModifier`, `advancedBeneficiaryNoticeOverrideReason`, `fillersExpectedAvailabilityDateTime`, `confidentialityCode`, `orderType`, `entererAuthorizationMode`, `parentUniversalServiceIdentifier`

Pure additions — existing accessor names and return types are unchanged. See <doc:TypedSegments>.

### Typed composite data types (v0.2-C1) — API-breaking

Typed-segment accessors for XPN-, CX-, and XAD-typed fields now return Swift struct views (`XPN?`, `CX?`, `XAD?`) instead of raw `Field?`. The new structs expose named accessors for the most common components:

```swift
// Before:
let family = pid.patientName?.first?.components[0].stringValue   // "Smith"
let mrn    = pid.patientIdentifierList?.first?.components.first?.stringValue
let street = pid.patientAddress?.first?.components[0].stringValue

// Now:
let family = pid.patientName?.familyName                          // "Smith"
let mrn    = pid.patientIdentifierList?.id
let street = pid.patientAddress?.streetAddress
```

**Migration path for v0.1.x callers.** Each composite struct exposes a public `field: Field` for raw access — so the v0.1.x pattern continues to work with one extra hop:

```swift
let family = pid.patientName?.field.first?.components[0].stringValue
```

Other composites (CE, CWE, EI, XCN, HD, MSG, PT, VID, XTN, PL, CNE, XON, EIP) still return `Field?` for now. Each can be promoted to a typed struct in a future stage without further breaking changes — the codegen recognises composite data-type codes via a whitelist.

**Multi-repetition access.** XPN/CX/XAD named accessors read from the **first** repetition. For multi-rep fields like PID-3 (patient identifier list) or PID-5 (legal name + maiden name), walk `.field.repetitions` and wrap each in an additional composite struct via the `init(repetition:)` convenience:

```swift
let identifiers = pid.patientIdentifierList?.field.repetitions.map { CX(repetition: $0) }
identifiers?.forEach { print("\($0.id ?? "") (\($0.identifierTypeCode ?? ""))") }
```

### Component-level grammar in Validator (v0.2-V2)

`Validator` now enforces required sub-components on populated composite-typed fields. Each typed composite carries its own `static let requiredComponents: [RequiredComponent]`:

| Composite | Required component |
|---|---|
| ``XPN`` | XPN-1 Family Name |
| ``CX`` | CX-1 ID Number |
| ``XAD`` | XAD-1 Street Address |

When a composite is populated but a required component is empty, the validator emits ``IssueCode/requiredComponentMissing`` with a component-level path:

```swift
// PID-5 (XPN) = ^John^A — family name component empty
let report = Validator().validate(message)
// .errors contains an .requiredComponentMissing issue at PID[1]-5.1
```

``IssueLocation`` gains a `componentIndex: Int?` for component-level issues. ``IssueLocation/pathDescription`` renders as `"PID[1]-5.1"` when the component index is set, alongside the existing `"PID[1]-3"` (field-level) and `"ZAU[1]"` (segment-level) shapes.

New toggle: ``ValidationOptions/checkComponentGrammar`` (default `true`; ``ValidationOptions/lenient`` disables it; ``ValidationOptions/strict`` keeps it on).

**Behaviour change for consumers.** Senders that populate a composite without the required first component now produce a `.requiredComponentMissing` error where v0.1.x produced none. The 48 gold-corpus fixtures all populate the required components and remain unaffected (pinned by `ComponentGrammarTests.fixtureCorpusNoComponentErrors`). Composites HL7v2Kit hasn't typed yet (CE / CWE / EI / XCN / ...) skip silently — promotion is incremental.

### Conditional-field evaluation in Validator (v0.2-V1)

v0.1.0 treated `optionality=C` (conditional) the same as `optionality=O`. ``Validator`` now evaluates `.conditional` fields against an optional predicate carried on ``FieldGrammar/condition``:

```swift
// PID-36 (Breed Code) ships with: condition = "PID-35 populated"
// → "if a species code is declared, a breed code is required"
let report = Validator().validate(messageWithSpeciesNoBreed)
// .errors contains an ``IssueCode/conditionalFieldMissing`` at PID[1]-36
```

The DSL is kept small: `<segment-id>-<index> <predicate>` where `<predicate>` ∈ `populated`, `empty`, `= <value>`, `!= <value>`. Same-segment references only; cross-segment or malformed predicates fail safe (no-trigger), so a schema typo can never make a previously-accepted message non-conformant. C fields without a `condition` continue to behave as `.optional`.

New toggle: ``ValidationOptions/checkConditionalFields`` (default `true`; ``ValidationOptions/lenient`` disables it). See <doc:Validation>.

**Behaviour change for consumers.** Messages that include PID-35 (species code) but not PID-36 (breed code) will now produce a `.conditionalFieldMissing` error where v0.1.0 produced none. The 48 gold-corpus fixtures all use human patients (PID-35 empty) and remain unaffected.

## Still pending for 0.2.0

The items below are tracked for v0.2 but have **not** landed on `main` yet. This section stays informational so consumers can plan ahead.

### More composite data types

v0.2-C1 shipped XPN / CX / XAD. The other v2.5.1 composites (CE, CWE, EI, XCN, HD, MSG, PT, VID, XTN, PL, CNE, XON, EIP) still return `Field?` and can be promoted incrementally without further breaking changes. Each promotion is additive: the codegen template already recognises a composite-type whitelist, and any new struct just needs to follow the XPN/CX/XAD pattern (wraps `Field`, exposes named accessors, `Sendable + Equatable + Hashable`).

### Performance budget tests

Nightly latency assertions per spec § 9.5. Adds a new test target gated on an environment variable so the default test run stays fast. Tracked as v0.2-X1.

### Runtime-loadable dictionaries

v0.1.0 / current `main` bake grammar into a compile-time Swift literal (`SegmentGrammarTable.v2_5_1`). v0.2 may revisit the original `HL7v2KitDictionaries` runtime-loadable plan if there's evidence of consumer need (e.g. dynamic version selection). See `ADR-005`.

## Long-term: pre-1.0 → 1.0.0

The v1.0.0 release is gated on:

- 10+ external GitHub stars
- at least 1 external production user
- 3 months of post-0.1.0 stability with no API breaks

It targets month 9–12 of the AU Core Workbench parent project. Until then, expect minor releases to potentially break source compatibility, with each break called out in `CHANGELOG.md`.

## See Also

- `CHANGELOG.md` (repository root)
- ``Version``
