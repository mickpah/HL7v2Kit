# ADR-007 — Locale-aware architecture: AU vs international as a first-class API mode

**Status:** Proposed, 2026-06-18. Revised the same day after project-owner guidance that HL7v2Kit is a building block for a HL7 v2 → FHIR AU Core mapper, and the AU/international toggle is a competitive-advantage API surface.
**Context:** The AU localisation profile `HL7AUSD-STD-OO-ADRM-2021.1` is now available at `docs/standards/HL7_v24_PDF/`. The project memory codifies (a) v2.4 as the recommended AU platform, and (b) HL7v2Kit's downstream role as the substrate for a FHIR AU Core mapping layer.

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

Implications for downstream callers:

- **Parser**: takes an optional `locale:` parameter. Default is `.international` (parses base-spec wire). When `.auLocalisation` is set, pre-adopted v2.5+ fields like PID-35..38 hydrate as typed accessors even on v2.4 wires.
- **Validator**: takes an optional `locale:` parameter (or surfaces it via `ValidationOptions.locale`). Locale governs whether AU narrowings apply.
- **FHIR mapping layer (downstream)**: can query the locale to know what guarantees the parser/validator made. AU-locale output carries promises (e.g. CX-4 assigning authority namespace will be populated for AU identifiers) that international-locale output does not. The mapper can rely on those promises without re-verifying.

## Why

Three forces converge on locale-as-mode rather than profile-as-overlay-toggle:

1. **the working notes project requirements.** Base schemas must stay spec-faithful. AU constraints cannot bake in. The overlay storage stays as proposed in the first ADR draft; only the public-API framing changes.
2. **Downstream FHIR mapper consumer.** When HL7v2Kit feeds a FHIR AU Core mapper, the mapper's contract is "I take HL7 v2 messages and produce AU Core FHIR resources." The mapper depends on AU constraints holding (specific identifier types, code systems, populated fields). Exposing the locale as a buried `options.profile = X` toggle hides the contract; exposing it as a top-level mode makes the contract part of the API conversation.
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

## FHIR AU Core mapping integration (downstream-consumer-aware)

The FHIR mapping layer is HL7v2Kit's primary downstream consumer per the project memory. Locale-aware design helps it concretely:

- **Identifier mapping**: `CX-4 Assigning Authority` is `O` in base HL7 v2 but `R` (or `RE`) in AU. AU-locale parse + validate guarantees the mapper can rely on the namespace being present for FHIR `Identifier.system` resolution. International-locale parse makes no such promise — the mapper falls back to heuristics.
- **Code system mapping**: AU profile constrains `OBX-3 Observation Identifier` to specific code systems (LOINC, AU pathology codes). AU-locale validation rejects out-of-system codes before the mapper sees them; international-locale validation accepts any code, and the mapper does the system-detection work.
- **Pre-adopted v2.5+ fields**: AU-locale parse on a v2.4 wire surfaces PID-35..38 as typed accessors; the mapper can map them to FHIR `Patient` extensions for species/breed. International-locale parse leaves them as `UnknownField` requiring manual extraction.
- **Profile compliance reporting**: `ValidationReport.locale == .auLocalisation` is a signal the mapper can include in the FHIR `MessageHeader` provenance.

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
  - `Resources/profiles/au-adrm-2021/{MSH,PID,NK1,NTE,OBR,OBX,ORC,PV1,AL1}.json` with `fieldOverrides` for the optionality narrowings listed in the AU spec. Subset choices should prioritise the fields the FHIR mapper needs first (CX-4, CX-5, HD-2, OBR-4 universal service identifier, OBX-3 observation identifier).

- **v0.4-S5-C** (AU code-table validation):
  - CWE / CE value-set checks against AU-defined HL7 code tables (Appendix 4 in the ADRM PDF).

- **v0.4-S5-D** (AU pre-adopted fields):
  - PID-35..38 hydrated as typed accessors on v2.4 wires when `.auLocalisation` is set.

Alternatively, v0.4-S5 could be deferred entirely to v0.5, keeping the v0.4 cycle's existing scope intact. **Decision pending project owner.**

**Recommendation**: land **only S5-A in v0.4** (the API plumbing). It's small, locks in the public surface for v1.0, and unblocks the FHIR mapper consumer immediately (mapper can already check `message.locale` and adjust behaviour). S5-B/C/D can land iteratively in v0.5 or later as the FHIR mapper consumer drives requirements.

This recommendation respects the "no predicate ships without citation" rule — the actual AU narrowings (S5-B/C/D) need careful per-field spec extraction from the 548-page AU PDF, which is substantial work that benefits from being scoped against real consumer needs.

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

**Proposed.** Awaiting project-owner decision on:
1. Adopt the locale-as-mode framing (replaces buried-profile-toggle framing from the initial ADR draft).
2. Land **S5-A only in v0.4** (recommended — API plumbing locks in v1.0 surface, downstream FHIR mapper unblocked), or land the full S5-A/B/C/D in v0.4, or defer entirely to v0.5.
3. The scope of S5-B if it does land in v0.4 (all 9 typed segments, or start with PID / OBR / OBX only — pathology-focused given AU ADRM is a diagnostics/referral profile).

If approved, ADR moves to **Accepted** and the agreed substages land per the cycle plan. The locale enum + Profile-overlay internals + ValidationIssue.code extension all land together in S5-A as one commit so the public-API surface is committed atomically.
