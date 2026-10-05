# ADR-014 — Public API evolution policy for v1.0

**Status:** **Accepted 2026-07-09 — Option B (documented SemVer evolution policy; no literal `@frozen`).** Project-owner selected in-session to open the M3 (API-stabilisation) cycle. The v1.0 public surface is settled as an *evolving-but-SemVer-bounded* contract: enums are classified **open** (may gain cases in 1.x minors — consumers use `@unknown default`) or **stable** (domain-closed; not expected to grow). No `@frozen` is applied. Options A / C recorded below as rejected. This ADR is the gate for ROADMAP **M3** — the last engineering gate before a v1.0 candidate.

**Context:** M1 (version coverage) and M2 (conformance surface) are closed (v0.15 / v0.17). v1.0 freezes the public API (per `Migration.md`): after it ships, breaking changes wait for 2.0. Before tagging v1.0 we must decide **how the public surface is allowed to evolve within 1.x** — specifically for the enums that legitimately grow as the domain grows (new HL7 versions, new locales, new validation checks).

### The surface in question

16 public enums (`grep "public enum"`, non-generated). They split by whether the *domain* can add members:

- **Open — grow with the domain:**
  - `Version` (String, CaseIterable) — HL7 keeps publishing versions (v2.7, v2.9, …); req #1 commits us to adding them.
  - `HL7Locale` (String, CaseIterable) — new localisation profiles (post-1.0 UK / US / NZ per the ROADMAP post-1.0 sketch).
  - `IssueCode` (12 cases) — each new validation check adds a case (precedent: `.segmentCardinalityBelowMinimum`, v0.11).
  - `ParseError`, `PathError`, `BuilderError` — new failure modes may be surfaced.
- **Stable — closed by the domain:**
  - `FieldOptionality` (R/O/C/X/B/W) — the *complete* HL7 optionality-code set; HL7 defines no others.
  - `FieldRepeatability` (single/multiple), `IssueSeverity` (info/warning/error), `ZSegmentPolicy`, `LineTerminatorPolicy`, `CharacterEncoding`, `RequiredComponentSet.Semantics`, `Segment` (typed/unknown sum-type).

**Key fact:** the package ships as an **SPM source package** with no library-evolution mode (`Package.swift` enables only `StrictConcurrency` + `ExistentialAny`). Therefore **`@frozen` is inert** — it changes nothing at compile time for a source dependency, and only matters for ABI-stable binary frameworks. The real lever is the **SemVer contract + `@unknown default` guidance**, not the attribute.

## Options

### Option A — Freeze everything (`@frozen` all public enums; promise no additive cases in 1.x)
Maximum source stability: a consumer's exhaustive `switch` never breaks within 1.x.

- **Cost:** directly contradicts req #1 and the project trajectory. A new HL7 version or locale could then only ship in a **2.0** — absurd for a library whose whole purpose is broad, growing spec coverage. Also `@frozen` is inert here (no library evolution), so the "benefit" is only the SemVer *promise*, and that promise is one we would immediately want to break.
- **Verdict:** rejected — freezes the very axes designed to grow.

### Option B — Documented SemVer evolution policy (no `@frozen`) — **chosen**
Classify each enum open vs stable. In 1.x, the only allowed changes are **additive** (new cases on open enums; new types/methods) — never removals, renames, or signature changes. Consumers switching over **open** enums must include `@unknown default` (documented in each enum's DocC + `Migration.md`). Removals/renames wait for 2.0.

- **Benefit:** honest and future-proof — HL7 evolution ships in 1.x minors without a major bump; consumers who follow the `@unknown default` guidance never break. Matches req #1.
- **Cost:** consumers must write `@unknown default` on open-enum switches (standard Swift practice for evolving library enums). Documented, not surprising.

### Option C — Hybrid `@frozen` (freeze the stable enums, leave open ones un-frozen)
Apply `@frozen` to the domain-closed enums; leave the open ones un-frozen.

- **Cost:** `@frozen` is inert without library evolution, so this adds attributes that do nothing today, imply an ABI-stability posture the package doesn't have, and would *forbid* a future additive case on a "stable" enum if the domain ever surprises us (e.g. HL7 adds an optionality code — unlikely but not impossible). All cost, no benefit.
- **Verdict:** rejected — inert complexity; the SemVer policy (B) already documents which enums are stable without over-committing.

## Decision

**Option B.** The v1.0 API evolution contract:

1. **No `@frozen`** anywhere — inert for a source SPM package; revisit only if HL7v2Kit ever ships as an ABI-stable binary framework (would be its own ADR).
2. **Open enums** — `Version`, `HL7Locale`, `IssueCode`, `ParseError`, `PathError`, `BuilderError` — **may gain cases in any 1.x minor.** Their DocC carries: *"This enum may gain cases in a minor release; switch with `@unknown default`."*
3. **Stable enums** — `FieldOptionality`, `FieldRepeatability`, `IssueSeverity`, `ZSegmentPolicy`, `LineTerminatorPolicy`, `CharacterEncoding`, `RequiredComponentSet.Semantics`, `Segment` — closed by the domain; no additive cases anticipated, but the same SemVer rule applies (additive-only in 1.x) if the domain ever surprises us.
4. **1.x rule:** additive only — new cases (open enums), new public types/methods/overloads. **Never** in 1.x: removing/renaming a symbol, changing a signature, changing a raw value, tightening access. Those wait for 2.0.
5. **`Sendable` / `Equatable` / `Hashable` conformances** on public types are part of the frozen contract — not removed in 1.x.

## M3 substage plan (v0.18 cycle, this branch)

- **S1 — ADR-014** (this doc): decide the policy. Done.
- **S2 — Public-surface audit:** enumerate every `public` symbol; confirm each is intended, minimal, DocC-commented; classify each open/stable; produce `docs/design/public-api-surface.md` (the v1.0 inventory). Add the `@unknown default` DocC note to each open enum.
- **S3 — `Migration.md` finalisation:** rewrite the stale (0.2.0-era) guide into the v1.0 contract — the additive-only rule, the open/stable enum lists, the 0.11→0.17 additive-case history, and what 2.0 would be free to change.
- **S4 — v1.0-definition ratification + release:** tick the ROADMAP v1.0 definition item 1 (M3); note the only remaining gate is M4 (external IP review); release v0.18.0.

Each substage its own commit at green tests; `main` untouched until the S4 merge.

## Consequences

- **v1.0 becomes tag-able on the engineering axis** once S2–S4 land: M1 + M2 + M3 all closed, only M4 (external IP review) outstanding. The ROADMAP already allows a private-repo v1.0 tag with M4 tracked as a follow-on.
- The contract is **honest**: it promises stability where we can keep it (no removals/renames/signature changes in 1.x) and openness where the domain demands it (new versions/locales/checks), rather than a freeze we would immediately break.
- Consumers get a clear, standard obligation (`@unknown default` on open-enum switches) documented at the point of use.

## References

- `Sources/HL7v2Kit/HL7v2Kit.docc/Migration.md` — the v1.0 stability clock (anchored v0.5.0); to be finalised in S3 as the contract.
- `docs/design/conditional-completeness-audit.md` + `permanent-limitations-register.md` — the M2 conformance registers (v1.0 gate, closed).
- `ROADMAP.md` M3 (this cycle) + M4 (distribution / IP review) + the candidate v1.0 definition.
- the working notes req #1 (feature-complete, will keep adding versions) — the reason `Version` must stay open.
- Swift library-evolution / `@frozen` semantics — inert without `-enable-library-evolution`, which this package does not set.

---

**Addendum (2026-08-27, R10):** the "waits for 2.0" lane was exercised for the first time.
The v2.0.0 boundary carries the remediation removals — dead public surface with
zero call sites; see `Migration.md` → "The 2.0 boundary" for the enumerated list and
`docs/design/remediation-plan.md` → "v2.0.0 removal register" for the evidence —
plus the two v1.6-deferred OBX swiftName corrections and the `RequiredComponentSet`
required-description tightening. The additive-only contract resumes for the 2.x line
from v2.0.0.

**Addendum (2026-09-15, M6-D5 override):** the project owner directed an override of the
2.x additive-only contract to remediate M6-D5 immediately: OBX-5's declared datatype was
`ST` in all six schemas where every version's attribute table gives the variable datatype
(`*` on v2.3/v2.3.1/v2.4, `varies` on v2.5.1+), so `OBX.observationValue` silently
flattened structured payloads to `String?`. The fix (accessor now `Field?`) is breaking;
the next release is therefore a **major** (`v3.0.0`). This is a spec-fidelity defect fix
under the working notes req #4, not a policy change — the additive-only contract is otherwise
unchanged and resumes for the 3.x line from v3.0.0. See `Migration.md` → "The 3.0
boundary".
