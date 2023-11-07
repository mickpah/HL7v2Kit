# ADR-012 — HL7 v2.6 as a grammar version: first-class, deferred-case, or out-of-scope

**Status:** **Accepted 2026-07-04 — Option A (first-class v2.6, full grammar).** Project-owner selected Option A: v2.6 becomes a first-class grammar version with the full 15-segment typed-segment set + conditional rules, authored from the on-disk v2.6 Final Standard PDFs. Sequenced pre-v1.0 (cleanest moment to add the `Version` case). Multi-substage cycle on branch `v0.14-adr-012-v2.6`; substage plan under "Decision". Options B / C recorded below as the rejected alternatives.

**Context:** v0.11–v0.13 closed the ADR-010 DSL cluster, the T-track per-version grammar gap (v2.3 / v2.3.1), and the machine-checkable AU 00044 narrowings. Per `ROADMAP.md`, **M1 (version-coverage completeness)** now has one common HL7 version not modelled: **v2.6** (2007). Its Final Standard PDFs are author-local at `docs/standards/HL7_v26_PDF/` (16 chapters). This ADR is the "needs an ADR first" gate `NEXT_STEPS.md` flagged for the v2.6 track.

### What "supporting a version" means here

Three capabilities are version-sensitive; the rest of the library is version-agnostic:

1. **`Version` enum case** — `public enum Version` (`Version.swift`) maps the MSH-12 wire string to a case. Currently: `v2_3`, `v2_3_1`, `v2_4`, `v2_5_1`, `v2_8`.
2. **Grammar table** — `SegmentGrammarTable.vX` (codegen-emitted from `Resources/schemas/vX/*.json`) drives per-field validation. Present for v2.3 / v2.3.1 / v2.4 / v2.5.1; **absent** for v2.8 (`Validator.grammarTable(for:)` returns `[:]`).
3. **Typed segments / composites** — version-*agnostic*; generated once from the canonical v2.5.1 schema. A v2.6 wire already parses, round-trips, and hydrates typed accessors **regardless of this ADR** — only *validation* depends on a grammar table.

**Precedent — `v2_8` is already a grammar-less enum case.** v2.8 was added to the enum (so MSH-12 = "2.8" parses to `.v2_8` rather than an unknown) but "indefinitely deferred" for grammar (project decision 2026-06-18: not in common use). So the "enum case without a grammar table" shape already exists and is sanctioned.

### The tension

- **the working notes req #1** ("feature-complete over AU-specific … the full HL7 v2.x spec … primary audience is HL7 integrators using it as a reference tool — they validate the full spec surface, including the parts AU consumers don't exercise") argues **for** v2.6: it is a real, common version an integrator-reference tool is expected to validate. v2.6 is materially more common in real-world traffic than v2.8.
- **AU-baseline priority** (memory `project_au_baseline`): v2.5.1 + v2.4 lead, v2.3/v2.3.1 lower, v2.8 deferred. **v2.6 is not in the AU priority set at all** — no AU consumer needs it.
- **v1.0 clock** (Migration.md): the public API — including `Version` — is meant to stabilise. Adding a `Version` case is cleanest **before** v1.0; doing it after the freeze is a heavier lift.

## Options

### Option A — First-class v2.6 (full grammar)
Add `case v2_6 = "2.6"`; author `Resources/schemas/v2.6/*.json` for the full typed-segment set (15 segments) with v2.6 field shapes + conditional rules; emit `SegmentGrammar+v2_6.swift`; wire `grammarTable(for:)`. A v2.6 wire gets full per-field + conditional validation, same as v2.4 / v2.5.1.

- **Effort:** Largest single remaining coverage item. ~15 segments × per-version field shapes, extracted from the v2.6 PDFs, preserving v2.6-vs-v2.5.1 divergences verbatim (same discipline as the v0.12 T-back-port, but ~2.5× the segment count and a full conditional-rule pass). Realistically a multi-substage cycle (S1 Ch2/3 control+admin, S2 Ch4/7 orders+observations, S3 remaining, S4 conditionals, S5 release).
- **API impact:** additive `Version` case (precedented by v2_8); `allCases` count changes. Non-`@frozen` enum → source-compatible additive change. No other public surface moves.
- **req #1 alignment:** strongest — completes the common-version set {2.3, 2.3.1, 2.4, 2.5.1, 2.6}.

### Option B — Deferred case (enum only, grammar later)
Add `case v2_6 = "2.6"` **only** — no grammar table (mirrors v2.8). A v2.6 wire parses, round-trips, and hydrates typed accessors; validation runs zero field-level checks (grammar table empty), i.e. it neither wrongly rejects nor validates.

- **Effort:** trivial (one enum case + a test).
- **Risk:** *implies* support that isn't there. An integrator seeing `.v2_6` recognised but getting no validation may mistake silence for conformance. Arguably **worse than honest** "unsupported" unless clearly documented. The v2.8 case has the same property but v2.8 is explicitly deferred/rare; v2.6 being common makes the false-implication sharper.
- **Use:** a placeholder that unblocks "recognised, not unknown" and lets typed-access work, with grammar authored in a later cycle.

### Option C — Out of scope (status quo)
Do nothing. MSH-12 = "2.6" falls back to `.v2_5_1` (default) or throws `.unsupportedVersion` under `rejectUnknownVersion` / `strict`. Revisit only on concrete integrator demand.

- **Effort:** none.
- **req #1 tension:** leaves a known, common version unmodelled in a tool that markets itself as a full-spec reference.

## Recommendation

**Option A, sequenced *before* v1.0 — but only if the owner judges v2.6 to be in the target integrator audience's real traffic.** Reasoning:

1. **req #1 is the tie-breaker.** The project's stated purpose is a full-spec integrator reference, explicitly broader than the AU baseline. v2.6 is a mainstream version; leaving it unmodelled is the kind of "AU traffic doesn't need it" rationalisation req #1 warns against.
2. **The machinery is proven.** The v0.6 and v0.12 T-back-ports established the per-version schema-authoring + codegen + cross-check-test pattern. v2.6 is bigger but not novel.
3. **Do it pre-1.0.** Adding the `Version` case is a clean additive change now; after the v1.0 freeze it becomes a bigger decision. If v2.6 is ever going to be first-class, before v1.0 is the cheap moment.
4. **Reject Option B as a shipped end-state** — a recognised-but-unvalidated common version misleads. B is acceptable only as an *interim* within an Option-A cycle (land the enum case in S1, grammar across S2–S4), never as the final state.

If the owner judges v2.6 **not** in the audience's traffic (a legitimate call — the AU parent project never needs it), **Option C** is the honest choice: keep it unmodelled and record the decision, exactly as v2.8 is recorded. Do **not** pick B as a permanent resting point.

## Decision

**Option A — first-class v2.6 (full grammar), 2026-07-04.** Multi-substage v0.14 cycle on `v0.14-adr-012-v2.6`. Substage plan (mirrors the v0.12 T-back-port discipline: per-segment attribute-table extraction from the v2.6 PDFs, preserving every v2.6-vs-v2.5.1 divergence verbatim; each schema carries a citation; cross-check tests pin field counts + divergences):

- **S1 — control + notes:** MSH, MSA, ERR, EVN, NTE (v2.6 CH02 / CH03 headers). Add `case v2_6 = "2.6"` to `Version`; wire `grammarTable(for:)`; extend the regenerate path so `SegmentGrammar+v2_6.swift` emits.
- **S2 — patient admin:** PID, PD1, NK1, PV1, AL1 (CH03).
- **S3 — orders + observations:** ORC, OBR, OBX (CH04 / CH07).
- **S4 — financial:** DG1, IN1 (CH06).
- **S5 — conditional-rule pass:** propagate the cross-segment / message-context / specimen / XOR conditions to v2.6 where the v2.6 spec text matches (mirror of the v0.11-S4b + v0.12 work); MultiVersionTests extended for v2.6 (version detected, grammar dispatched, field counts, divergences).
- **S6 — release** as v0.14.0 (audit-doc note, CHANGELOG, STATUS/NEXT_STEPS, ROADMAP M1 closure, merge, tag, push).

Each substage is its own commit at green tests. The `Version` case lands in S1 so a v2.6 wire is recognised from the first substage (validation fills in as segments are authored — an in-cycle instance of the Option-B interim, resolved to full grammar by S5).

## Consequences

- **If A:** `ROADMAP.md` M1 closes with the common-version set complete; v1.0's `Version` surface is settled. A multi-cycle effort precedes other M-track work (or interleaves).
- **If B:** minimal now, but M1 stays open (grammar still owed) and the false-implication risk must be documented in `Version` DocC + Migration.md.
- **If C:** M1 is declared complete-by-decision at {2.3, 2.3.1, 2.4, 2.5.1}; v2.6 + v2.8 are both "recognised-or-not, grammar out of scope, revisit on demand." Cleanest for a v1.0 that scopes itself to the AU-relevant + adjacent versions.

## References

- `Sources/HL7v2Kit/Version.swift` — the `Version` enum (non-`@frozen`, `CaseIterable`, v2_8 grammar-less precedent).
- `Sources/HL7v2Kit/Validation/Validator.swift` — `grammarTable(for:)` returns `[:]` for grammar-less versions.
- `docs/design/ADR-004-codegen-over-macros.md` — the schema-JSON → generated-grammar pipeline v2.6 would use.
- `docs/archive/*v0.6*` + CHANGELOG `[0.12.0]` — the T-back-port precedent for per-version schema authoring.
- `ROADMAP.md` M1 (version coverage) + M3 (API freeze) — the milestones this decision sits between.
- the working notes req #1 (feature-complete over AU-specific) vs memory `project_au_baseline` (AU version priority) — the two poles of the tension.
- Migration.md — v1.0 stability clock; `Version` listed under the stabilising surface.
