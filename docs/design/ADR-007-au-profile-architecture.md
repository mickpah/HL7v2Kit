# ADR-007 — AU profile architecture (layered, not baked-in)

**Status:** Proposed, 2026-06-18.
**Context:** The AU localisation profile `HL7AUSD-STD-OO-ADRM-2021.1` (Australian Diagnostics and Referral Messaging — Localisation of HL7 Version 2.4) is now available at `docs/standards/HL7_v24_PDF/HL7AUSD-STD-OO-ADRM-2021.1 - Australian Diagnostics and Referral Messaging - Localisation of HL7 Version 2.4.pdf`. The project memory codifies v2.4 as the recommended AU platform.

## Decision

**The AU profile lives in a separate, layered constraint set. Base HL7 v2.4 (and v2.3 / v2.3.1 / v2.5.1) schemas remain spec-faithful — no AU-specific narrowing is baked in.**

The Validator gains a new `Profile?` parameter on `ValidationOptions`. When a profile is loaded, validation runs base-spec checks first, then layers the profile's narrowing constraints on top. Profile violations carry a distinct `ValidationIssue.code` (`.profileConstraintViolation`) so consumers can distinguish base-spec failures from profile failures.

## Why

The the working notes project requirements rule directly here:

> 1. **Feature-complete over AU-specific.** HL7v2Kit must accurately implement the full HL7 v2.x spec, not just the subset used by Australian clinical traffic.
> 2. **Integrator primary-reference tool.** Schema fields, validator predicates, and composite metadata must be defensible against the HL7 v2 spec text alone — not against AU vendor behaviour.

Baking AU narrowing into the base schemas would mean: (a) the schema no longer reflects the HL7 v2 spec text — it reflects HL7 v2 spec + AU constraints; (b) non-AU integrators reading the schema would mistake AU rules for base-spec rules; (c) the audit doc claims (e.g. "PID-3 is `R` per v2.4 §3.4.2.3") become false when AU constrains the same field tighter and the schema only carries the AU version.

The layered architecture preserves both axes:

- **Base layer**: spec-faithful, audit-citable against HL7 v2.4 / v2.5.1 Final Standard PDFs.
- **AU profile layer**: spec-faithful, audit-citable against the AU ADRM-2021 PDF.
- **Validator**: configurable. Default is base-only (everyone gets it). AU consumers opt in by loading the profile.

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
- **New `Profile` value type**: additive public API. Initial scope is the AU profile; profile loading mechanics generalise to other profiles later.
- **New `ValidationOptions.profile`**: additive.
- **New `ValidationIssue.code = .profileConstraintViolation`**: additive enum case (pre-v1.0; allowed per Migration.md).

## Scope for v0.4 cycle

v0.4 was scoped at Option α with 7 stages. Adding AU profile work pushes into a new stage v0.4-S5:

- **v0.4-S5-A**: Profile value type + ProfileLoader + ValidationOptions extension + ValidationIssue case. No actual AU constraints landed yet.
- **v0.4-S5-B**: AU profile schema for the 9 currently-typed segments (MSH / PID / NK1 / NTE / OBR / OBX / ORC / PV1 / AL1) — `fieldOverrides` for the optionality narrowings the AU spec lists.
- **v0.4-S5-C**: AU code-table validation (CWE / CE value-set checks).
- **v0.4-S5-D**: AU pre-adopted fields (PID-35..38 in v2.4 profile) — exercises the `specSource: "AU-profile-extension"` path.

Alternatively, v0.4-S5 could be deferred entirely to v0.5, keeping the v0.4 cycle's existing scope intact. **Decision pending project owner.**

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
1. Whether to add v0.4-S5 to this cycle, or defer to v0.5.
2. The scope of S5-B (all 9 typed segments, or start with PID / OBR / OBX only since the AU profile is pathology-focused).
3. Whether to migrate the project memory `project_au_baseline.md` to note that AU baseline is now formally documented and the profile is in-tree.

If approved, ADR moves to **Accepted** and S5 lands per substages above.
