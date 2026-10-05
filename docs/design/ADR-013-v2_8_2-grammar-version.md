# ADR-013 — HL7 v2.8.2 as a grammar version: first-class, deferred-case, or out-of-scope

**Status:** **Accepted 2026-07-09 — Option A (first-class v2.8.2, full grammar).** Project-owner selected Option A in-session: v2.8.2 becomes a first-class grammar version with the full 15-segment typed-segment set + conditional rules, authored from the on-disk v2.8.2 Final Standard PDFs. Sequenced immediately after v0.14 (v2.6), pre-v1.0 (cleanest moment to add the `Version` case). Multi-substage cycle on branch `v0.15-adr-013-v2.8.2`; substage plan under "Decision". Options B / C recorded below as the rejected alternatives. Directly mirrors ADR-012 (v2.6).

**Context:** v0.14 (ADR-012) added first-class v2.6 grammar, closing the *common-version* set {2.3, 2.3.1, 2.4, 2.5.1, 2.6} per `ROADMAP.md` **M1**. The full **HL7 v2.8.2** Final Standard — the latest published HL7 v2.x release (2019) — then landed author-local at `docs/standards/HL7_V2.8.2_PDF/` (17 chapters, PDF + WORD). This ADR is the "needs an ADR first" gate `NEXT_STEPS.md` flagged for the v2.8.2 track — the same gate ADR-012 was for v2.6.

### What "supporting a version" means here (unchanged from ADR-012)

Three capabilities are version-sensitive; the rest of the library is version-agnostic:

1. **`Version` enum case** — `public enum Version` (`Version.swift`) maps the MSH-12 wire string to a case. Currently: `v2_3`, `v2_3_1`, `v2_4`, `v2_5_1`, `v2_6`, `v2_8`.
2. **Grammar table** — `SegmentGrammarTable.vX` (codegen-emitted from `Resources/schemas/vX/*.json`) drives per-field validation. Present for v2.3 / v2.3.1 / v2.4 / v2.5.1 / v2.6; **absent** for v2.8 (`Validator.grammarTable(for:)` returns `[:]`).
3. **Typed segments / composites** — version-*agnostic*; generated once from the canonical v2.5.1 schema. A v2.8.2 wire already parses, round-trips, and hydrates typed accessors **regardless of this ADR** — only *validation* depends on a grammar table.

### The naming reconciliation (the one decision genuinely new vs ADR-012)

The enum already carries a grammar-less `case v2_8 = "2.8"` (added 2026-06-18, "indefinitely deferred"). **v2.8.2 is a distinct point release from v2.8**, and HL7 puts the full version ID in MSH-12 (table 0104): a v2.8.2 message carries `MSH-12 = "2.8.2"`, a v2.8 message carries `"2.8"`. So the two are distinct raw values with no collision:

- **Decision:** add **`case v2_8_2 = "2.8.2"`** (placed after `v2_6`, before `v2_8`, to keep the enum in ascending version order). **Keep `.v2_8 = "2.8"` as-is** (grammar-less). They coexist cleanly — no rename, no fold.
- **Rationale for keeping `.v2_8`:** removing it would be a source-breaking enum change for no benefit, and a bare `"2.8"` wire (rare) should still parse to a recognised case rather than falling to unknown. `.v2_8` stays a grammar-less recognised case (same status as before); only `.v2_8_2` gets a grammar table this cycle.
- **`.v2_8` grammar (future):** if a `"2.8"` wire ever needs validation, the closest-published-grammar question (reuse v2.8.2's table for `.v2_8`? author a separate v2.8 table?) is deferred — out of scope for this cycle, recorded here so it isn't lost.

### Why v2.8.2 divergence work is heavier than v2.6 was (req #2 warning)

v2.8.2 is **five point releases** beyond v2.6 (2.7 → 2.7.1 → 2.8 → 2.8.1 → 2.8.2). Expect materially more divergence than the v2.6-vs-v2.5.1 delta:

- **More datatype migrations** — the CE→CWE/CNE and TS→DTM waves largely completed by v2.6, but further coded-field and composite retypings are likely; verify every field per its own v2.8.2 attribute-table header (never carry a v2.6 datatype unverified).
- **Larger segments / more new fields** — segment field counts have kept growing (e.g. OBX, PID, ORC gained fields across 2.7–2.8.x); expect new trailing fields on most segments.
- **More withdrawn (`W`) fields** — v0.14 added `FieldOptionality.withdrawn`; v2.8.2 will likely use `W` more widely (and may surface optionality codes not yet modelled — if so, extend the model per req #3, exactly as `W` was added in v0.14).
- **Chapter restructure** — v2.8.2 splits Ch2 into CH02 (Control) / CH02A (DataTypes) / CH02B (Conformance) / CH02C (CodeTables), and Orders into CH04 / CH04A. Segment homes are otherwise stable: MSH/MSA/ERR/NTE (CH02), EVN/PID/PD1/NK1/PV1/AL1 (CH03), ORC/OBR (CH04), OBX (CH07), DG1/IN1 (CH06).

The typed-segment canonical version stays v2.5.1 (typed structs are version-agnostic); this cycle authors a grammar table only.

## Options

### Option A — First-class v2.8.2 (full grammar)
Add `case v2_8_2 = "2.8.2"`; author `Resources/schemas/v2.8.2/*.json` for the full 15-segment set with v2.8.2 field shapes + conditional rules; emit `SegmentGrammar+v2_8_2.swift`; wire `grammarTable(for:)`. A v2.8.2 wire gets full per-field + conditional validation, same as v2.5.1 / v2.6.

- **Effort:** comparable to v0.14 but likely larger per-segment (more fields, more divergences). Multi-substage cycle mirroring ADR-012.
- **API impact:** additive `Version` case (precedented by v2_6 / v2_8); `allCases` count changes. Non-`@frozen` enum → source-compatible additive change. Possibly one additive `FieldOptionality` case if v2.8.2 uses an optionality code beyond R/O/C/X/B/W. No other public surface moves.
- **req #1 alignment:** strongest — extends coverage to the **latest published standard**, the clearest statement that the library is a full-spec integrator reference and not an AU-only tool.

### Option B — Deferred case (enum only, grammar later)
Add `case v2_8_2 = "2.8.2"` **only** — no grammar table (mirrors the current `.v2_8`). A v2.8.2 wire parses, round-trips, hydrates typed accessors; validation runs zero field-level checks.

- **Risk:** same false-implication as ADR-012 Option B — a recognised-but-unvalidated case reads as "supported" when it isn't. Acceptable only as an *interim within* an Option-A cycle (case lands in S1, grammar fills across S2–S5), never as the shipped end-state.

### Option C — Out of scope (status quo)
Do nothing. `MSH-12 = "2.8.2"` falls back to `.v2_5_1` (default) or throws `.unsupportedVersion` under `rejectUnknownVersion` / `strict`.

- **req #1 tension:** leaves the newest standard unmodelled in a tool marketed as a full-spec reference — the sharpest form of the req-#1 gap, since v2.8.2 is where "latest and complete" is judged.

## Recommendation

**Option A, this cycle (v0.15), pre-v1.0.** Reasoning mirrors ADR-012 and is *stronger* here:

1. **req #1 tie-breaker.** v2.8.2 is the latest published HL7 v2.x standard; a full-spec reference that stops at v2.6 invites exactly the "we didn't need it" critique req #1 rejects. The owner supplying the full PDF + WORD set is a direct signal it is in the target audience's scope.
2. **The machinery is proven twice** — the v0.6/v0.12 T-back-ports and the v0.14 v2.6 cycle established (and stress-tested, incl. the `W` model extension) the schema-authoring → codegen → cross-check-test pattern. v2.8.2 is bigger, not novel.
3. **Do it pre-1.0.** Adding the `Version` case (and any new `FieldOptionality` case) is a clean additive change now; after the v1.0 freeze it is a heavier lift.
4. **Reject B as an end-state; C is now the weakest option** — unlike v2.6 (which the AU parent never needs, making C at least defensible), leaving the *latest* standard unmodelled is hard to defend for an integrator reference.

## Decision

**Option A — first-class v2.8.2 (full grammar), 2026-07-09.** Multi-substage v0.15 cycle on `v0.15-adr-013-v2.8.2`. Substage plan (mirrors ADR-012 / the v0.14 discipline: per-segment attribute-table extraction from the v2.8.2 PDFs via PDFKit, preserving every v2.8.2-vs-v2.6 divergence verbatim; each schema carries a citation; cross-check tests pin field counts + divergences):

- **S1 — control + notes + `Version` wiring:** MSH, MSA, ERR, EVN, NTE (v2.8.2 CH02 / CH03). Add `case v2_8_2 = "2.8.2"` to `Version` (keep `.v2_8`); wire `grammarTable(for:)`; extend the regenerate path so `SegmentGrammar+v2_8_2.swift` emits.
- **S2 — patient admin:** PID, PD1, NK1, PV1, AL1 (CH03).
- **S3 — orders + observations:** ORC, OBR, OBX (CH04 / CH04A / CH07).
- **S4 — financial:** DG1, IN1 (CH06).
- **S5 — conditional-rule pass:** propagate the cross-segment / message-context / specimen / XOR conditions to v2.8.2 where the v2.8.2 spec text matches; extend `MultiVersionTests` (version detected, grammar dispatched, field counts, divergences, any new withdrawn/optionality handling, a clean-message no-spurious-error regression).
- **S6 — release** as v0.15.0 (`docs/design/v2_8_2-spec-audit.md`, CHANGELOG, STATUS/NEXT_STEPS archive + slim, ROADMAP M1 track closure, merge, tag, push, remove worktree).

Each substage is its own commit at green tests. The `Version` case lands in S1 so a v2.8.2 wire is recognised from the first substage (validation fills in as segments are authored — an in-cycle Option-B interim, resolved to full grammar by S5). **Leave `main` untouched during the cycle** (avoids the v0.11 pointer-commit merge friction).

**Model-extension watch (req #3):** if v2.8.2 uses a field-level construct the model can't express faithfully (a new optionality code, a new datatype class, a conditional form the DSL can't state), extend the model rather than mapping it to a near-miss — exactly as `FieldOptionality.withdrawn` was added in v0.14. Record any such extension in the audit doc + CHANGELOG.

## Consequences

- **If A (chosen):** `ROADMAP.md` M1 fully closes — coverage spans v2.3 → v2.8.2, the complete published-standard set the reference targets. v1.0's `Version` surface settles at six live grammar tables + the grammar-less `.v2_8` placeholder. `FieldOptionality` may gain one more case (kept open per M3 until M1 closes).
- **If B:** M1 stays open (grammar owed); false-implication risk documented in `Version` DocC + Migration.md.
- **If C:** M1 declared complete-by-decision at the common set; v2.8.2 recorded as "recognised-or-not, grammar out of scope, revisit on demand." Weakest for a full-spec reference.

## References

- `docs/design/ADR-012-v2_6-grammar-version.md` — the immediately-preceding, structurally-identical decision (v2.6); this ADR is its sequel for the latest standard.
- `Sources/HL7v2Kit/Version.swift` — the `Version` enum (non-`@frozen`, `CaseIterable`; `v2_6` live, `v2_8` grammar-less; `v2_8_2` to be added).
- `Sources/HL7v2Kit/Validation/Validator.swift` — `grammarTable(for:)` returns `[:]` for grammar-less versions.
- `Sources/HL7v2Kit/Validation/SegmentGrammar.swift` — `FieldOptionality` (R/O/C/X/B/W); the `.withdrawn` precedent for a req-#3 model extension.
- `docs/design/v2_6-spec-audit.md` — the v0.14 audit doc this cycle's `v2_8_2-spec-audit.md` mirrors.
- `docs/standards/HL7_V2.8.2_PDF/PDF/V282_*.pdf` — the author-local Final Standard source (IP-review-gated; keep out of any public tree).
- `ROADMAP.md` M1 (version coverage) + M3 (API freeze) — the milestones this decision sits between.
- the working notes req #1 (feature-complete over AU-specific) vs memory `project_au_baseline` (AU version priority) — v2.8.2 is the clearest req-#1-over-AU-baseline case yet.

## Addendum (2026, ADR-018)

The deferred `.v2_8` grammar question above is decided by ADR-018: a `2.8` message is validated against the v2.8.2 grammar, and the Validator reports the substitution (`IssueCode.versionGrammarSubstituted`, info). `.v2_8` keeps its public case and still owns no tables in the public registries.

---

**Addendum (P9, ADR-020):** point 3's "typed segments / composites are version-agnostic,
generated once from the canonical v2.5.1 schema" is superseded. The structs keep the v2.5.1
base and add the other supported versions' surface (fields, names, `As<T>` views), and composite views
cover every component through v2.8.2 (CWE and CNE 22, XAD 23, XCN 25).
