# ADR-007 — Locale-aware architecture: AU vs international as a first-class API mode

**Status:** **Accepted 2026-06-18.** Proposed and revised same day; project-owner approval received. Implementation scope = **S5-A only in v0.4** (recommended option), per the project-owner's "Accepted" reply to the ADR's recommendation section. S5-B/C/D iterate later as integrator conformance needs drive scope. **Scope correction 2026-06-18 (post-S5-B-1)**: removed framings that positioned HL7v2Kit's purpose as feeding a FHIR mapper. HL7v2Kit is a parsing/validation library; mapping (HL7 v2 → FHIR or any other target) lives in downstream consumers, not here. The locale mode is a conformance-validation feature for HL7 integrators.
**Context:** The AU localisation profile `HL7AUSD-STD-OO-ADRM-2021.1` is now available at `docs/standards/HL7_v24_PDF/`. The project memory codifies v2.4 as the recommended AU platform for integrator conformance validation work.

## Decision

**Locale is a first-class, public API mode on Parser and Validator.** Defaults to `.international` (base spec only). AU consumers set `.auLocalisation` to engage the AU ADRM-2021 narrowings.

```swift
public enum HL7Locale: Sendable, Hashable {
    case international                // base HL7 v2.x spec, no localisation
    case auLocalisation               // AU ADRM-2021 layered over v2.4 base
    // future: .ukSpine, .deBasisprofil, etc.
}
```

**Base HL7 v2.4 / v2.5.1 / v2.3.1 / v2.3 schemas remain spec-faithful.** AU narrowings live in a separate overlay set at `Resources/profiles/au-adrm-2021/`. The `HL7Locale` enum is the *public* API; the profile-overlay mechanism is the *implementation* underneath it.

Implications for callers:

- **Parser**: takes an optional `locale:` parameter. Default is `.international` (parses base-spec wire). When `.auLocalisation` is set, pre-adopted v2.5+ fields like PID-35..38 hydrate as typed accessors even on v2.4 wires.
- **Validator**: takes an optional `locale:` parameter (or surfaces it via `ValidationOptions.locale`). Locale governs whether AU narrowings apply on top of base-spec checks.
- **Downstream consumers** (whatever they do — display, persistence, FHIR mapping, ETL, audit, etc.) can read `message.locale` / `report.locale` to see which conformance set was applied. HL7v2Kit makes no claims about downstream behaviour; it just reports what it validated against.

## Why

Three forces converge on locale-as-mode rather than profile-as-overlay-toggle:

1. **the working notes project requirements.** Base schemas must stay spec-faithful. AU constraints cannot bake in. The overlay storage stays as proposed in the first ADR draft; only the public-API framing changes.
2. **Integrator conformance validation is the use case.** Integrators validating AU pathology / referral traffic need a clear way to ask the validator "check this against the AU ADRM-2021 profile, not just base HL7 v2". A buried `options.profile = X` toggle hides that intent; a top-level `locale:` parameter makes the validation conformance set visible at every call site.
3. **v1.0 stability window.** Pre-v1.0 is the window to land the right shape. Locale-as-mode is the right shape: it generalises to other localisations (UK Spine, DE Basisprofil) without API change. A `profile:` option that's "really an enum in practice" would need refactoring later.

## Public API shape (proposed)

```swift
// New value type. Default everywhere.
public enum HL7Locale: Sendable, Hashable {
    case international
    case auLocalisation
}

extension Parser {
    public init(options: ParserOptions = .default, locale: HL7Locale = .international)
}

extension Validator {
    public init(options: ValidationOptions = .default, locale: HL7Locale = .international)
}

extension ValidationOptions {
    // Alternative ergonomics — embed locale in options.
    public var locale: HL7Locale { get set }
}

public enum ValidationIssue.Code {
    // ... existing cases ...
    case profileConstraintViolation(localeRule: String)
}
```

The locale value is propagated into:

- `Message.locale` — the locale that was active when this message was parsed.
- `ValidationReport.locale` — the locale that was active when validation ran.

Both are accessor-only. Mutating the message's locale post-parse would be unsound.

## Implementation: the profile-overlay mechanism (internal)

Internally, locale resolution maps to a profile-overlay loader:

- `.international` → no overlay loaded; base-spec behaviour as today.
- `.auLocalisation` → load `Resources/profiles/au-adrm-2021/*.json` overlay over base `v2.4` schemas (and over `v2.5.1` if the AU profile is later extended to a v2.5.1 base).

The overlay format is the same as the first ADR draft proposed:

```json
{
  "profileID": "au-adrm-2021",
  "baseVersion": "2.4",
  "segmentID": "PID",
  "fieldOverrides": [ /* ... */ ]
}
```

Internal `Profile` type still exists, but it's an implementation detail. Public consumers only see `HL7Locale`.

## What the AU profile constrains (surface-area survey)

From a survey of `HL7AUSD-STD-OO-ADRM-2021.1` (548 pages, 7 chapters + 9 appendices):

1. **Usage codes extended.** Base HL7 v2 uses `R / O / C / X / B`. AU profile adds `RE` (Required, can be empty) and `CE` (Conditional, may be empty), and supports the special `-` (no documentation) marker. The semantics differ enough that the schema's `optionality` field cannot collapse them — the overlay schema needs its own `usage` field.
2. **Optionality narrowing.** Many base-`O` fields become base-`R` or `RE` under AU. The profile cannot *loosen* what base spec requires (per the profile's own conformance rules), only tighten.
3. **Code-system constraints.** "Value Set" attribute restricts CWE / CE / IS / ID fields to AU-specific HL7 code tables.
4. **Pre-adoption of v2.5+ fields.** AU v2.4 profile uses PID-35..38 (species / breed / strain / production class) and other v2.5-or-later additions, despite base v2.4 capping PID at 32. This is `Note: Where … HL7 Version 2.6 standards are pre-adopted, the constrained or specified HL7 table is included below the data type table.`
5. **Required-component narrowing.** Composites (XAD, XCN, XPN, CWE, etc.) carry tighter required-component lists in the AU profile.
6. **Sub-message-type-specific constraints.** Some constraints fire only for specific event codes (e.g. ORU^R01 vs. REF^I12).

This goes well beyond what a v2.X JSON schema currently expresses.

## What downstream consumers can do with the locale

HL7v2Kit's scope is parsing and validation. Downstream consumers (display layers, persistence, ETL, audit, FHIR mappers, etc.) live outside this project. The locale-aware design surfaces enough information for any of them to make their own decisions without commitment from HL7v2Kit:

- **`message.locale`** — tells the consumer which conformance set the parser was configured with. Consumers can branch on it.
- **`report.locale`** — same for validation reports.
- **`ValidationIssue.code.profileConstraintViolation(localeRule:)`** — when AU profile checking is enabled, consumers can see exactly which AU rule fired and attribute the failure precisely.

Whether a consumer maps the validated message to FHIR, persists it to a database, displays it to a user, or anything else, is the consumer's concern. HL7v2Kit guarantees only what it parsed and validated, not how that's consumed.

## What the AU profile constrains (surface-area survey)

From a survey of `HL7AUSD-STD-OO-ADRM-2021.1` (548 pages, 7 chapters + 9 appendices):

1. **Usage codes extended.** Base HL7 v2 uses `R / O / C / X / B`. AU profile adds `RE` (Required, can be empty) and `CE` (Conditional, may be empty), and supports the special `-` (no documentation) marker. The semantics differ enough that the schema's `optionality` field cannot collapse them — the profile schema needs its own type.
2. **Optionality narrowing.** Many base-`O` fields become base-`R` or `RE` under AU. The profile cannot *loosen* what base spec requires (per the profile's own conformance rules), only tighten.
3. **Code-system constraints.** "Value Set" attribute restricts CWE / CE / IS / ID fields to AU-specific HL7 code tables.
4. **Pre-adoption of v2.5+ fields.** AU v2.4 profile uses PID-35..38 (species / breed / strain / production class) and other v2.5-or-later additions, despite base v2.4 capping PID at 32. This is `Note: Where … HL7 Version 2.6 standards are pre-adopted, the constrained or specified HL7 table is included below the data type table.`
5. **Required-component narrowing.** Composites (XAD, XCN, XPN, CWE, etc.) carry tighter required-component lists in the AU profile.
6. **Sub-message-type-specific constraints.** Some constraints fire only for specific event codes (e.g. ORU^R01 vs. REF^I12).

This goes well beyond what a v2.X JSON schema currently expresses.

## Schema layout

Proposed directory structure:

```
Resources/
  schemas/           # base HL7 v2 spec (unchanged)
    v2.3/
    v2.3.1/
    v2.4/
    v2.5.1/
  profiles/          # NEW
    au-adrm-2021/    # AU ADRM-2021 profile (over v2.4 base)
      PID.json       # only the deltas vs base v2.4 PID.json
      OBR.json
      OBX.json
      ORC.json
      ...
      profile.json   # profile metadata: base version, identifier, conformance statements
```

Each profile JSON carries only deltas (overlay semantics), not the full re-emission of the base schema. This keeps the AU profile reviewable per-field rather than as a full diff.

## Profile schema format (initial sketch)

```json
{
  "profileID": "au-adrm-2021",
  "baseVersion": "2.4",
  "segmentID": "PID",
  "fieldOverrides": [
    {
      "index": 3,
      "usage": "R",
      "valueSet": "HL7AU-0001",
      "requiredComponents": [
        {"index": 1, "name": "Identifier"},
        {"index": 4, "name": "Assigning Authority"},
        {"index": 5, "name": "Identifier Type Code"}
      ]
    },
    {
      "index": 35,
      "usage": "RE",
      "specSource": "AU-profile-extension",
      "note": "Pre-adopted from v2.5+"
    }
  ]
}
```

Notable additions vs. base schema:
- `usage` (string, extended set including `RE` / `CE`).
- `valueSet` (string, AU code table identifier).
- `requiredComponents` (overrides the base value when present; falls back to base when absent).
- `specSource` (when the profile pre-adopts a field outside the base spec).

## Validator integration

Add `Profile` value type + new `ValidationOptions.profile: Profile?` field. When non-nil:

1. Run base-spec validation as today.
2. For each field, check the profile's `fieldOverrides`. If `usage` says `R` or `RE`, additional emptiness checks fire. If `valueSet` says a specific code table, the field's first component is verified against that table.
3. Profile violations emit `ValidationIssue.code = .profileConstraintViolation` with the profile identifier in the message.

`Profile` itself is loaded by an explicit init (file URL or JSON data). The Validator does not auto-discover profiles in `Resources/profiles/` — opt-in only.

## Migration / version-stability impact

- **Base schemas**: no API impact. The `FieldGrammar` enum keeps its `R / O / C / X / B` set.
- **New `HL7Locale` enum**: additive public API. Initial values `.international` and `.auLocalisation`. Designed to extend cleanly (`.ukSpine`, `.deBasisprofil`, …) without breaking pre-v1.0 callers, since the enum is non-frozen.
- **New `locale:` parameter on `Parser.init` / `Validator.init` / `ValidationOptions`**: additive defaults to `.international`, so all existing call sites keep their current behaviour.
- **New `Message.locale` / `ValidationReport.locale` accessors**: additive.
- **Internal `Profile` value type**: implementation detail. Not exposed in public API.
- **New `ValidationIssue.code = .profileConstraintViolation(localeRule:)`**: additive enum case (pre-v1.0; allowed per Migration.md). The associated value carries the AU-rule identifier so consumers can attribute the failure.
- **Locale stability after v1.0**: once v1.0 ships, adding `case .ukSpine` is a non-breaking change (consumers must use `default:` or `@unknown default:` in switches). Renaming or removing existing cases would be breaking.

## Scope for v0.4 cycle

v0.4 was scoped at Option α with 7 stages. Adding AU profile work as a new stage v0.4-S5, **reframed under the locale architecture**:

- **v0.4-S5-A** (the API plumbing — landed first because it shapes everything downstream):
  - `HL7Locale` enum at top level.
  - `Parser.init(options:locale:)` overload + locale propagation onto `Message.locale`.
  - `Validator.init(options:locale:)` overload + `ValidationOptions.locale` + locale propagation onto `ValidationReport.locale`.
  - Internal `Profile` value type + ProfileLoader for `Resources/profiles/<id>/*.json`.
  - New `ValidationIssue.code = .profileConstraintViolation(localeRule:)`.
  - No AU constraints landed yet — but `.international` works (no-op overlay) and `.auLocalisation` loads an empty overlay (no-op too). Sets the API surface in stone for v1.0.

- **v0.4-S5-B** (overlay content — AU narrowings for the 9 currently-typed segments):
  - `Resources/profiles/au-adrm-2021/{MSH,PID,NK1,NTE,OBR,OBX,ORC,PV1,AL1}.json` with `fieldOverrides` for the optionality narrowings listed in the AU spec. Subset choices should prioritise the fields most central to AU pathology / referral conformance validation (EI completeness on order/result identifiers, CWE / CE code-system rules, HD identification rules).

- **v0.4-S5-C** (AU code-table validation):
  - CWE / CE value-set checks against AU-defined HL7 code tables (Appendix 4 in the ADRM PDF).

- **v0.4-S5-D** (AU pre-adopted fields):
  - PID-35..38 hydrated as typed accessors on v2.4 wires when `.auLocalisation` is set.

Alternatively, v0.4-S5 could be deferred entirely to v0.5, keeping the v0.4 cycle's existing scope intact. **Decision pending project owner.**

**Recommendation**: land **only S5-A in v0.4** (the API plumbing). It's small, locks in the public surface for v1.0, and lets integrators (and any downstream consumers) start working with the locale enum immediately. S5-B/C/D can land iteratively in v0.5 or later as integrator conformance needs drive requirements.

This recommendation respects the "no predicate ships without citation" rule — the actual AU narrowings (S5-B/C/D) need careful per-field spec extraction from the 548-page AU PDF, which is substantial work that benefits from being scoped against real integrator needs.

## Alternatives considered

### Alternative 1: Bake AU into base v2.4 schemas

Rejected. Violates "feature-complete over AU-specific" requirement; misleads non-AU integrators; makes the audit doc claims wrong.

### Alternative 2: Separate per-version directories per profile

E.g. `Resources/schemas/v2.4-au/`. Considered but rejected — the duplication is real (most PID fields are unchanged) and would drift over time. The overlay format compresses the profile to only the meaningful deltas.

### Alternative 3: Wait for v2.5.1 AU profile

If HL7 Australia eventually publishes a v2.5.1 ADRM profile, the same architecture applies — different base version, different `profileID`. No architectural change needed; the chosen layered design is profile-version-agnostic.

## Consequences

- Adopting this ADR commits to a new `Profile` public type and the `profiles/` resource layout. Both are additive and pre-v1.0, so cost is bounded.
- Future profiles (other countries, sub-specialty profiles) follow the same pattern.
- The `Validator.validate(_, options:)` surface stays simple — `options.profile = X` is the only new toggle consumers need to understand.

## Status

**Accepted 2026-06-18.** Project-owner approved the locale-as-mode framing and the recommended scope (S5-A only in v0.4).

Implementation landing as a single S5-A commit on `v0.4-segments`:
- `HL7Locale` public enum.
- `Parser.init(options:locale:)` overload + `Message.locale` propagation.
- `Validator.init(options:locale:)` overload + `ValidationOptions.locale` + `ValidationReport.locale` propagation.
- Internal `Profile` type + `ProfileLoader` scaffold.
- `ValidationIssue.code.profileConstraintViolation(localeRule:)`.
- Tests: locale round-trip through parse + validate; default behaviour unchanged; `.auLocalisation` loads empty overlay (no constraints fire yet).

S5-B/C/D (actual AU narrowings) land iteratively as integrator conformance needs drive scope. No constraints ship without spec citation per the "no predicate ships without citation" rule.

## Implementation status update (final, v0.5 cycle close, 2026-06-18)

S5-A: shipped in v0.4.0 (`d60d12e` on `main`).

All S5-B/C/D sub-substages landed on the v0.5-au-profile worktree (8 functional + 1 doc commit; ready for v0.5.0 tag):

- **S5-B-1** (`4bb5f67`): 5 field-level AU rules for OBR-2/3 + ORC-2/3/4 EI completeness (HL7au:000003 / 000004.1 / 000005 / 000006 / 000007). Validator dispatches `Profile.fieldOverrides.requiredComponents`.
- **Scope correction** (`a844c03`): removed framings that positioned HL7v2Kit's purpose as feeding a FHIR mapper. HL7v2Kit is a parsing/validation library; mapping happens in downstream consumers. Locale mode is an integrator-focused conformance-validation feature.
- **S5-B-1 polish** (`6128d06`): citations inlined into `FieldOverride.specCitation`; separate `AUADRM2021Citations` switch removed. 2 pin tests for repeating-field + multi-segment occurrence semantics.
- **S5-B-2** (`46a33ac`): `Profile.compositeOverrides: [CompositeOverride]` + `PairConditional` rules. 12 AU datatype-level rules across CE / CNE / CWE (HL7au:00044.4 / .5 / .6 series). Validator dispatches per-repetition pair-conditional checks.
- **S5-B-3** (`7b7f24d`): `CompositeOverride.requiredComponents: [ComponentRequirement]` track. 2 AU CX rules — CX-4 + CX-5 must be valued when CX populated (HL7au:00044.1.2/.1.3).
- **S5-C** (`910bdc8`): `FieldOverride.componentValueSets: [ComponentValueSet]` track. 4 AU rules — MSH-17 = "AUS" (HL7au:000041), MSH-19 = "en^English^ISO639" (HL7au:000042, 3 component checks).
- **S5-D** (`b08931b`): `Profile.grammarExtensions: [String: [FieldGrammar]]` track + `Validator.mergeGrammarExtension`. AU pre-adopts v2.5+ PID-35..38 onto v2.4 wires; conditional predicates from v0.4-S4-C now apply to v2.4 wires under `.auLocalisation`.
- **S5-D-2** (`292c86e`): profileUsage dispatch — `FieldOverride.profileUsage = .required` now fires `.profileConstraintViolation` on empty fields. MSH-17 + MSH-19 flagged `.required` under AU. Closes the S5-C "populated-then-must-match" scope gap.

**Final cumulative coverage**:

| Narrowing axis | Internal type | AU rules |
|---|---|---:|
| Field required-components | `FieldOverride.requiredComponents` | 5 |
| Field required-presence | `FieldOverride.profileUsage = .required` | 2 |
| Field per-component value-set | `FieldOverride.componentValueSets` | 4 |
| Composite required-components | `CompositeOverride.requiredComponents` | 2 |
| Composite pair-conditional | `CompositeOverride.pairRules` | 12 |
| Grammar extension | `Profile.grammarExtensions` | 4 fields with cond predicates |

**29 distinct AU conformance rules** firing under `.auLocalisation` (each with verbatim HL7au spec citation in `localeRule`). Covers MSH / OBR / ORC / PID directly; CE / CNE / CWE / CX every populated occurrence via datatype dispatch.

**Tests**: 360 (v0.4.0) → **390** across 23 → 24 suites green.

ADR moves from "Accepted" to "Implemented" with this status update. Post-v0.5 AU narrowings (HL7au:000001 / 000008 / 00044.\*.3-.4-.7-.8 / 000040 / 00044.2) are out of S5's scope and listed in NEXT_STEPS as v0.6+ candidates — each needs a different sub-rule type (cross-segment refs, value-set code-table store, semantic evaluator, runtime PKI).
