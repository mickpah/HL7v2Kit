# Migration

Versioning contract and per-release migration notes for HL7v2Kit consumers.

## Overview

HL7v2Kit is approaching **v1.0** (currently `v0.17.0`). The public API surface has been stable since **v0.5.0** (the v1.0 stability-clock anchor); changes since then have been **additive only** (new enum cases, new segments/versions, new validation checks). The remaining pre-1.0 work is the external distribution gate (ROADMAP M4 — IP review), not API churn.

- **Pre-1.0** (`0.x`): minor releases (`0.x → 0.(x+1)`) *may* make source-breaking changes, each called out in `CHANGELOG.md`. In practice none has since v0.5.0.
- **Post-1.0** (`1.x`): strict SemVer under the evolution policy below (ADR-014). Additive-only in minors; breaking changes wait for `2.0`.

## The v1.0 API evolution contract (ADR-014)

Once `v1.0.0` ships, the public surface is frozen under an **additive-only** rule for the `1.x` line:

**Allowed in a `1.x` minor:** new public types, methods, overloads, and conformances; new cases on the **open** enums below; new typed segments / grammar versions (these add members, never remove).

**Never in `1.x` (waits for `2.0`):** removing or renaming any public symbol; changing a method signature or an enum raw value; tightening access; removing a `Sendable` / `Equatable` / `Hashable` conformance.

### Open enums — may gain cases in a minor; switch with `@unknown default`

``Version``, ``HL7Locale``, ``IssueCode``, ``ParseError``, ``PathError``, ``BuilderError``.

These grow as the domain grows (new HL7 versions, localisation profiles, validation checks, failure modes). Each carries a DocC `- Note:` at its declaration. Consumer code that switches over them **must** include `@unknown default`:

```swift
switch message.version {
case .v2_5_1: …
case .v2_8_2: …
@unknown default: …   // required — new versions ship in minor releases
}
```

### Stable enums — closed by their domain

``FieldOptionality`` (R/O/C/X/B/W — HL7's complete optionality-code set), ``FieldRepeatability``, ``IssueSeverity``, `ZSegmentPolicy`, `LineTerminatorPolicy`, ``CharacterEncoding``, `RequiredComponentSet.Semantics`, and ``Segment`` (a closed typed/unknown sum-type). No growth is anticipated; the additive-only rule still governs if a domain ever surprises us.

> `@frozen` is **not** applied to any public enum. HL7v2Kit ships as an SPM *source* package (no library-evolution mode), so `@frozen` would be inert; the contract above is the SemVer promise, not a compiler attribute. See `docs/design/ADR-014-api-evolution-policy.md` and the surface inventory in `docs/design/public-api-surface.md`.

## API evolution since v0.5.0 (the stability anchor)

All additive — no source break for a consumer who follows the `@unknown default` guidance:

| Release | Additive change |
|---------|-----------------|
| v0.11.0 | `IssueCode.segmentCardinalityBelowMinimum` (ADR-010 group-scope cardinality) |
| v0.12.0 | v2.3 / v2.3.1 T-track grammar (no API surface change — schemas only) |
| v0.13.0 | AU composite-override narrowings (internal; reuses `.profileConstraintViolation`) |
| v0.14.0 | `Version.v2_6`; `FieldOptionality.withdrawn` (`W`) |
| v0.15.0 | `Version.v2_8_2` |
| v0.16.0 | Two shipped conditional predicates (schema metadata; no API surface change) |
| v0.17.0 | Conformance-limitations register (docs only) |

## Historical: 0.1.0 → 0.5.0

The early minors (0.2–0.5) included source-breaking refactors while the surface settled: typed-composite accessors moving from raw `Field?` to struct views (`XPN`/`CX`/`XAD`), component-level and conditional-field validation, the MLLP codec, and the `HL7Locale` API. These predate the v0.5.0 stability anchor; consumers starting at v0.5.0+ are unaffected. Full detail is in `CHANGELOG.md` and the `docs/archive/` snapshots.

## v1.0 gates

Per `ROADMAP.md`, v1.0 ships when:

1. **M3 API stabilisation** — ✅ this cycle (ADR-014 + the public-API-surface inventory + this contract).
2. **M2 conformance surface finalised** — ✅ (v0.16 conditional register + v0.17 permanent-limitations register).
3. **M1 version coverage** — ✅ (v2.3 → v2.8.2).
4. **M4 public push** — external IP review (the only remaining gate). v1.0 may be tagged on the private repo with M1–M3 satisfied and the public push tracked as a follow-on.

## See Also

- `docs/design/ADR-014-api-evolution-policy.md` — the evolution policy this contract implements
- `docs/design/public-api-surface.md` — the full v1.0 public-symbol inventory
- `CHANGELOG.md` (repository root) — per-release detail
- ``Version`` · ``IssueCode`` · ``HL7Locale``
