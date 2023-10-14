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

### Typed composite data types

v0.1.0/v0.1.x typed-segment accessors return `Field?` for structured HL7 data types (XPN, CX, XAD, CE, CWE, EI, XCN, ...). v0.2 plans Swift struct wrappers for the most common composites — for example:

```swift
// Current:
let family = pid.patientName?.first?.components[0].stringValue

// Planned (v0.2-C1):
let family = pid.patientName?.first?.familyName
```

Both forms will likely coexist for at least one minor release. The Swift struct accessors are additions, not replacements. Tracked as v0.2-C1; will bump the line to `0.2.0` because the changes touch the codegen template and every typed-segment file regenerates.

### Component-level grammar in Validator

v0.1.0 / current `main` only check field-level rules in ``Validator``. v0.2 plans component-level cardinality (e.g. XPN's family-name component being non-empty when XPN-1 is populated). Tracked as v0.2-V2; depends on the typed composite work above.

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
