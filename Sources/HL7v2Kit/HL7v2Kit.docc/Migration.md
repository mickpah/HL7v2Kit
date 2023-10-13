# Migration

Per-release migration notes for HL7v2Kit consumers.

## Overview

HL7v2Kit is pre-1.0 (currently 0.1.0 development). Minor releases (0.x → 0.(x+1)) may make source-breaking changes, documented here. Patch releases (0.x.y → 0.x.(y+1)) are bug-fix-only with no API changes. Post-1.0, strict SemVer applies.

## From 0.0.x (none shipped) → 0.1.0

There is no prior released version. The first public release is 0.1.0.

## Anticipated changes in 0.2.0

The following items are tracked for the v0.2 release. None has shipped yet; this section is informational so consumers can plan ahead.

### Typed composite data types

v0.1.0 typed-segment accessors return `Field?` for structured HL7 data types (XPN, CX, XAD, CE, CWE, EI, XCN, ...). v0.2 may introduce Swift struct wrappers for the most common composites — for example:

```swift
// v0.1.0:
let family = pid.patientName?.first?.components[0].stringValue

// Speculative v0.2:
let family = pid.patientName?.first?.family
```

Both forms would coexist for at least one minor release. The Swift struct accessors would be additions, not replacements.

### Conditional-field evaluation

v0.1.0 treats `optionality=C` (conditional) the same as `optionality=O` for the required-field check. v0.2 may introduce a small condition-evaluation language sufficient for the standard's "required if PV1-2 = 'I'" patterns. The introduction would be additive — currently-valid messages will continue to validate; previously-suppressed conditional errors may now surface.

### Component-level grammar

v0.1.0 only checks field-level rules in ``Validator``. v0.2 may add component-level cardinality (e.g. XPN's family-name component being non-empty when XPN-1 is populated).

### Runtime-loadable dictionaries

v0.1.0 bakes grammar into a compile-time Swift literal (`SegmentGrammarTable.v2_5_1`). v0.2 may revisit the original `HL7v2KitDictionaries` runtime-loadable plan if there's evidence of consumer need (e.g. dynamic version selection). See `ADR-005`.

## Long-term: pre-1.0 → 1.0.0

The v1.0.0 release is gated on:

- 10+ external GitHub stars
- at least 1 external production user
- 3 months of post-0.1.0 stability with no API breaks

It targets month 9–12 of the AU Core Workbench parent project. Until then, expect minor releases to potentially break source compatibility, with each break called out in `CHANGELOG.md`.

## See Also

- `CHANGELOG.md` (repository root)
- ``Version``
