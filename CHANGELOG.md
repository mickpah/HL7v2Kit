# Changelog

All notable changes to HL7v2Kit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added — v0.5-S5-D: AU pre-adopted PID-35..38 grammar extensions on v2.4

Substage for the AU profile's pre-adoption of v2.5+ PID fields onto v2.4 wires. Closes the documented gap: under base v2.4 grammar (PID capped at 32), the Validator never iterated PID-33..38, so the v2.5.1-style conditional predicates added in v0.4-S4-C didn't apply to v2.4 wires. With S5-D + `.auLocalisation`, the AU profile extends the v2.4 PID grammar so those rules fire.

- **`Profile` model extension**:
  - `Profile.grammarExtensions: [String: [FieldGrammar]]` — segment ID to appended/replacing field-grammar entries. New track alongside `fieldOverrides`, `compositeOverrides`.
  - `Profile.init` re-ordered to `(locale, baseVersion, fieldOverrides, grammarExtensions, compositeOverrides)` so the segment-level overrides cluster naturally.

- **AU grammar extension shipped**:
  - **`"PID"`** → 4 `FieldGrammar` entries mirroring the v2.5.1 PID-35..38 schema:
    - PID-35 Species Code (CE, C, condition: `"PID-36 populated OR PID-38 populated"`).
    - PID-36 Breed Code (CE, C, condition: `"PID-37 populated"`).
    - PID-37 Strain (ST, O).
    - PID-38 Production Class Code (CE, O).

- **`Validator.mergeGrammarExtension`** (new): merges a profile's grammar extension into a base segment grammar. Existing indices REPLACE; new indices APPEND. The Validator now resolves grammar via the merged result when a profile is loaded.

- **Behaviour gain**: a v2.4 wire that populates PID-36 (Breed Code) without PID-35 (Species Code) under `.auLocalisation` now correctly fires `.conditionalFieldMissing` on PID-35 — matching what would happen on a v2.5.1 wire. Under `.international`, the same v2.4 wire fires nothing (base v2.4 grammar has no PID-35), preserving the documented base-spec behaviour.

- **Tests added (Tests/HL7v2KitTests/LocaleAUProfileTests.swift)**: 4 new tests:
  - v2.4 + AU: PID-36 populated triggers PID-35 conditional missing.
  - v2.4 + .international: same wire silently ignores PID-35 (base v2.4 has no PID-35).
  - v2.4 + AU: PID-35 + PID-36 both populated satisfies the conditional.
  - v2.5.1 wire: PID-35 conditional fires regardless of locale (base-grammar route is unaffected by profile).

385 → 389 tests across 24 suites green. Fixture corpus pin held (no fixtures populate v2.4 PID-35..38).

**Cumulative v0.5**: AU profile now provides 4 narrowing axes — field-level (S5-B-1), composite required (S5-B-3), composite pair-conditional (S5-B-2), per-component value-set (S5-C), grammar extension (S5-D) — across 5 segments (MSH / OBR / ORC / PID via dispatch + AU grammar reach into PID-35..38 on v2.4).

### Added — v0.5-S5-C: AU ADRM-2021 per-component value-set rules (MSH-17 / MSH-19)

First substage of the AU profile value-set track. Extends `FieldOverride` with a `componentValueSets` track parallel to `requiredComponents` (S5-B-1 / -3), then ships the AU "country must be AUS" + "language must be en/English/ISO639" rules.

- **`Profile` model extension**:
  - `FieldOverride.componentValueSets: [ComponentValueSet]` — new sub-rule track. Each entry restricts a specific 1-based component to a fixed list of allowed literal values via exact-string comparison.
  - `ComponentValueSet` struct (component index + `allowedValues: [String]` + `specCitation: String?`).
  - `FieldOverride.init` made explicit (Swift's synthesized memberwise init can't carry defaults for the new field while preserving back-compat).

- **AU rules added**:
  - **`HL7au:000041 (r2)`** — MSH-17 country code must be `"AUS"`.
  - **`HL7au:000042`** — MSH-19 must be valued as `"en^English^ISO639"` (three component value-sets: CE-1 = en, CE-2 = English, CE-3 = ISO639).

- **`Validator.checkProfileFieldOverrides`** extended to dispatch the new track alongside the existing `requiredComponents`. Same `.profileConstraintViolation(localeRule:)` plumbing; spec citation per rule.

- **`Resources/profiles/au-adrm-2021/MSH.json`** — new overlay file with both rules + verbatim spec citations + an `_notes` block documenting the populated-then-must-match scope and the future `profileUsage`-based dispatch.

- **Scope note (documented in source comments)**: S5-C rules fire only when the field is populated. The AU spec actually says MSH-17 and MSH-19 must always be populated under `.auLocalisation`. The "field must be populated under AU" enforcement is a separate future track — likely via `profileUsage` dispatch — and is not in S5-C-1 scope.

- **Tests added (Tests/HL7v2KitTests/LocaleAUProfileTests.swift)**: 5 new tests covering MSH-17 wrong country fires; MSH-19 wrong language identifier fires; fully AU-conformant MSH passes; empty MSH-17 / MSH-19 fires nothing (scope pin for populated-then-must-match); `.international` locale silent. 380 → 385 tests across 24 suites green.

**Fixture corpus pin held**: existing fixtures leave MSH-17 / MSH-19 empty, so the S5-C rules don't fire on them. The corpus continues to pass under both locales.

**Cumulative v0.5**: 23 AU rules now firing under `.auLocalisation` (5 field-level EI from S5-B-1, 12 datatype-level pair rules across CE/CNE/CWE from S5-B-2, 2 CX completeness rules from S5-B-3, 4 MSH value-set rules from S5-C — counting each MSH-19 component check separately).

### Added — v0.5-S5-B-3: AU ADRM-2021 CX required-component rules (HL7au:00044.1.2 / .1.3)

Third substage of the AU profile constraint overlays. Extends `CompositeOverride` with a `requiredComponents` track parallel to the `pairRules` from S5-B-2, then ships the AU CX completeness rules.

- **`Profile` model extension**:
  - `CompositeOverride.requiredComponents: [ComponentRequirement]` — new sub-rule track. Each requirement says "when a field of this dataType is populated, this component must be populated".
  - `ComponentRequirement` — internal struct (1-based component index + `specCitation`). Citation-per-rule keeps attribution clean.
  - Existing `pairRules` track unchanged; both tracks dispatch together inside `checkProfileCompositeOverrides`.

- **AU rules added**:
  - **CX `HL7au:00044.1.2 (r2)`** — CX-4 Assigning Authority must be valued when CX is populated.
  - **CX `HL7au:00044.1.3`** — CX-5 Identifier Type Code must be valued when CX is populated.
  - Skipped (with reasons documented in source comments):
    - `HL7au:00044.1.1` (CX-1 must be specified) — redundant with base spec, which already requires CX-1 via `CX.requiredComponents`.
    - `HL7au:00044.1.2` NASH sub-points and `HL7au:00044.1.3` value-set membership — runtime/PKI-dependent or value-set-dispatch work, deferred.

- **`Validator.checkProfileCompositeOverrides`** extended to dispatch the new `requiredComponents` track before the existing `pairRules` track. Same `.profileConstraintViolation(localeRule:)` plumbing; citation per rule.

- **`Resources/profiles/au-adrm-2021/datatypes.json`** — CX entry added with both AU rules + an `_skipped` documentation block listing the rules deliberately omitted with their reasons. Source-of-truth for the Swift Profile content.

- **Tests added (Tests/HL7v2KitTests/LocaleAUProfileTests.swift)**: 5 new tests — PID-3 with CX-4 missing fires `HL7au:00044.1.2`, PID-3 with CX-5 missing fires `HL7au:00044.1.3`, AU-conformant CX fires nothing, CX rules apply to every populated CX field (PID-2 deprecated still triggers under `.auLocalisation`), `.international` locale never fires AU rules. 375 → 380 tests across 24 suites green.

The fixture corpus continues to pass under both locales — existing fixtures coincidentally populate CX-4 (assigning authority) and CX-5 (identifier type code) when PID-3 is populated, so they're AU-conformant on these two new rules.

**Cumulative**: v0.5 has now landed 19 AU rules under `.auLocalisation` (5 field-level EI from S5-B-1, 12 datatype-level pair rules across CE/CNE/CWE from S5-B-2, 2 CX completeness rules from S5-B-3).

### Added — v0.5-S5-B-2: AU ADRM-2021 datatype-level pair rules (CE / CNE / CWE)

Second substage of the AU profile constraint overlays. Extends the Profile model from per-field overrides (S5-B-1) to also carry per-HL7-datatype overrides, then ships 12 AU pair-conditional rules.

- **`Profile` model extension**:
  - New `compositeOverrides: [CompositeOverride]` track alongside the existing `fieldOverrides: [FieldOverride]`.
  - New `CompositeOverride` (dataType code + `pairRules: [PairConditional]`).
  - New `PairConditional` (ifComponent / condition / thenComponent / requirement / specCitation).
  - New `PairCondition` enum (`.populated` / `.empty`).
  - New `PairRequirement` enum (`.mustBePopulated` / `.mustBeEmpty`).
  - All types internal — public surface unchanged.

- **AU rules added** (12 total, from Appendix 5 of HL7AUSD-STD-OO-ADRM-2021.1):
  - **CE** (`HL7au:00044.4.{1,2,5,6}`): identifier ⇔ name of coding system, alt identifier ⇔ alt name of coding system.
  - **CNE** (`HL7au:00044.5.{1,2,5,6}`): same shape on CNE composites.
  - **CWE** (`HL7au:00044.6.{1,2,4,5}`): same shape; spec numbers alt rules as `.4` / `.5` rather than `.5` / `.6`.
  - Skipped (deferred): `*.3` (CE-2 text must-be-valued — carries a "may be blank" carve-out that violates "no predicate ships if known-incorrect"), `*.4` LOINC-first / `*.7` concept-match / `*.8` distinct-alt-coding-system (value-set / semantic rules deferred to S5-C).

- **`Validator.checkProfileCompositeOverrides`** (new): for each populated field, looks up the override by `fieldGrammar.dataType`. For each pair rule, checks the condition on `ifComponent`; if triggered, requires the `thenComponent` to satisfy the requirement; fires `.profileConstraintViolation(localeRule: <HL7au-id>)` on failure. Dispatches per repetition.

- **`Resources/profiles/au-adrm-2021/datatypes.json`** — new overlay file documenting the 12 pair rules with verbatim spec citations. Source-of-truth for the Swift Profile content.

- **Tests added (Tests/HL7v2KitTests/LocaleAUProfileTests.swift)**: 5 new tests covering CE identifier-without-coding-system, alt-identifier-without-alt-coding-system, empty-identifier-with-coding-system (inverse), fully-consistent CE (no false positives), and a dataType-dispatch sanity check that CE fields (not CWE) fire CE rules. 370 → 375 tests across 24 suites green.

**Fixture corpus pin held**: all 51+3 fixtures still pass under both `.international` and `.auLocalisation` — they happen to be CE-consistent (every CE-1 is paired with a CE-3; every empty CE-1 has empty CE-3). The additive-errors invariant in `LocaleTests.auLocaleAddsButDoesNotRemoveBaseSpecErrors` continues to pass.

### Added — v0.5-S5-B-1: AU ADRM-2021 EI-completeness rules

First substage of the AU profile constraint overlays. The `.auLocalisation` locale was a no-op overlay in v0.4-S5-A; v0.5-S5-B-1 ships the first 5 concrete AU rules:

- **`Resources/profiles/au-adrm-2021/{OBR,ORC}.json`** — overlay JSONs documenting the rules with spec citations:
  - `OBR-2` (Placer Order Number EI): all 4 components required when populated. HL7au:000003 (r2).
  - `OBR-3` (Filler Order Number EI): all 4 components required when populated. HL7au:000004.1 (r3).
  - `ORC-2` (Placer Order Number EI): all 4 components required when populated. HL7au:000005 (r2).
  - `ORC-3` (Filler Order Number EI): all 4 components required when populated. HL7au:000006 (r3).
  - `ORC-4` (Placer Group Number EI): all 4 components required when populated. HL7au:000007 (r2).
- **`Sources/HL7v2Kit/Locale/Profile+au_adrm_2021.swift`** (new) — hand-curated runtime Profile mirroring the JSON overlays. Codegen support for profile overlays is deferred until more profiles need this pattern.
- **`Validator`** extended to dispatch `Profile.fieldOverrides`. When `.auLocalisation` is set AND a field has an override AND is populated, the override's `requiredComponents` rule fires `.profileConstraintViolation(localeRule: <HL7au-identifier>)` for each missing component.
- **`ProfileLoader.load(for: .auLocalisation)`** now returns `Profile.auADRM2021` instead of the empty S5-A scaffold.

Behavioural change for `.auLocalisation` consumers: AU-incomplete OBR/ORC EI fields now fire `.profileConstraintViolation`. `.international` locale is unchanged.

Tests added: 9 new tests in `LocaleAUProfileTests.swift` covering each rule's positive / negative / cross-locale behaviour, plus 1 spec-citation pin. `LocaleTests.swift`'s fixture-corpus pin renamed from "AU locale doesn't introduce new errors" to "AU locale errors are a superset of international errors" and re-implemented with the additive-errors invariant (AU may ADD errors, never REMOVES one). 360 → 368 tests across 23 → 24 suites green.

Spec citation: HL7AUSD-STD-OO-ADRM-2021.1 Appendix 5 Conformance Statements (Normative). Author-local PDFs at `docs/standards/HL7_v24_PDF/`.

## [0.4.0] — 2026-06-18

v0.4 cycle release. Three tracks landed: **spec accuracy** (v2.5.1 + v2.4 schemas spec-text-audited; conditional predicates with citations; compound DSL; composite OR-rule enforcement via `RequiredComponentSet`), **localisation API** (`HL7Locale` first-class enum locked for v1.0 stability per ADR-007 Accepted), and **typed segments** (15 typed segments — added EVN, MSA, ERR, PD1, DG1, IN1). 322 → 360 tests across 22 → 23 suites. **API-affecting** — purely additive: new `HL7Locale` enum, new `locale:` parameter on `Parser.init` / `Validator.init`, new `Message.locale` / `ValidationReport.locale` accessors, new `IssueCode.profileConstraintViolation(localeRule:)` case, new typed-segment surface for the 6 additions. No public-API breakage from v0.3.0. The 3-month no-API-break v1.0 stability clock restarts from this tag per Migration.md.

### Added — v0.4-T3: IN1 (Insurance) typed segment — closes segments track

- **`Resources/schemas/v2.5.1/IN1.json`** — 25 fields (billing-essentials subset of the full 53-field v2.5.1 segment). Covers set ID (R), insurance plan ID (CE, R), insurance company ID (CX, R, repeats), company name (XON) + address (XAD) + contact (XPN) + phone (XTN), group number + name + employer ID/name, plan effective + expiration dates, authorization info (AUI), plan type, insured name (XPN) + relationship + DOB + address, assignment + coordination of benefits, COB priority, notice-of-admission flag + date, report-of-eligibility flag.
- **Codegen output**: `Sources/HL7v2Kit/Segment/Generated/IN1.swift` + `SegmentRegistry+Generated.swift` extension + `SegmentGrammar+v2_5_1.swift` row. 15 typed segments total (was 14).
- **T3 capstone test**: existing fixture `adt_a01_with_insurance.hl7` (which previously exercised IN1 as UnknownSegment) now auto-hydrates IN1 typed and round-trips byte-perfectly. **No fixture changes needed** — the wire was already spec-conformant.
- 7 new tests in `TypedSegmentTests.swift`. 353 → 360 tests across 23 suites green.

### Added — v0.4-T2: PD1 + DG1 typed segments

- **`Resources/schemas/v2.5.1/PD1.json`** — 21 fields (full v2.5.1 surface) covering living dependency/arrangement, primary facility (XON), primary care provider (XCN, B-deprecated), student/handicap/living-will/organ-donor indicators, separate bill, duplicate patient (CX), publicity code (CE), protection indicator + effective date, place of worship (XON), advance directive code (CE), immunization registry status, publicity-code effective date, military branch/rank/status.
- **`Resources/schemas/v2.5.1/DG1.json`** — 21 fields (full v2.5.1 surface) covering set ID (R), diagnosis coding method (B-deprecated), diagnosis code (CE), date/time, diagnosis type (R), legacy MDC/DRG/outlier fields (B-deprecated), priority, diagnosing clinician (XCN repeats), classification, confidential indicator, attestation date, diagnosis identifier (C) + diagnosis action code (C). The two C-fields carry no `condition` predicate — both are "required for P12 update messages" which is a message-context rule the same-segment DSL cannot express; deferred per the no-predicate-without-citation rule.
- 9 new tests in `TypedSegmentTests.swift` covering scalar + composite accessors + round-trip equality. 344 → 353 tests green.

### Added — v0.4-T1: EVN + MSA + ERR typed segments

- **`Resources/schemas/v2.5.1/EVN.json`** — 7 fields (event type code B, recorded date/time R, planned event date, event reason code, operator ID XCN repeats, event occurred, event facility HD).
- **`Resources/schemas/v2.5.1/MSA.json`** — 6 fields (ack code R, message control ID R, text message B, expected sequence number, delayed acknowledgment type X (withdrawn v2.5), error condition B).
- **`Resources/schemas/v2.5.1/ERR.json`** — 12 fields covering the v2.5+ redesign (ELD ERR-1 B for backward compat, ERL ERR-2 location, CWE ERR-3 R hl7 error code, ID ERR-4 R severity, + 8 informational fields).
- **Codegen**: 12 typed segments total after T1 (was 9). All four `SegmentGrammar+v2_X.swift` tables refreshed.
- **Fixture correction**: `Tests/Fixtures/ack_application_error.hl7` updated to v2.5.1-conformant ERR layout. The pre-T1 fixture used the v2.4-style single ERR-1 ELD (`ERR|PID^1^3^1|||101^...`) but was labeled MSH-12 = 2.5.1. While ERR was UnknownSegment the validator couldn't see the mismatch; once ERR became typed under v2.5.1 grammar, missing ERR-3 (R) + ERR-4 (R) surfaced. Updated to `ERR||PID^1^3^1|101^Invalid patient ID format^HL70357|E`. FIXTURES.md row annotated.
- 12 new tests in `TypedSegmentTests.swift` covering EVN/MSA/ERR scalar + composite accessors, round-trip equality, and ACK fixture auto-pickup regression pins. 322 → 344 tests green.

### Added — v0.4-S5-A: `HL7Locale` public API + Profile/ProfileLoader scaffold

- **`HL7Locale` public enum** (Sources/HL7v2Kit/Locale/HL7Locale.swift): `.international` (default, base spec only) / `.auLocalisation` (HL7AUSD-STD-OO-ADRM-2021 over base v2.4). Sendable, CaseIterable, raw-value-backed. **Locale-as-mode is a first-class public API**, not a buried profile toggle — per ADR-007 Accepted.
- **`Parser.init(options:locale:)`** overload + `Parser.locale` accessor.
- **`Validator.init(options:locale:)`** overload + `Validator.locale` accessor.
- **`Message.locale`** property + `Message.init(...locale:)` parameter.
- **`ValidationReport.locale`** property + `ValidationReport.init(...locale:)`.
- **`IssueCode.profileConstraintViolation(localeRule:)`** additive enum case carrying the AU-rule identifier for attribution (pre-v1.0 allowed per Migration.md).
- Internal scaffold (consumers never see these): `Profile` value type with `FieldOverride` + `ProfileUsage`; `ProfileLoader` returns `nil` for `.international` and an empty Profile for `.auLocalisation`. JSON-backed loader + AU narrowings ship in S5-B/C/D.
- **Behavioural change: NONE.** `.auLocalisation` loads an empty overlay; no `profileConstraintViolation` issues fire in S5-A. Fixture corpus has identical issue counts under both locales (pinned by `auLocaleNoRegressionsOnFixtureCorpus`).
- **Downstream-consumer surface**: callers can read `message.locale` / `report.locale` to see which conformance set was applied. HL7v2Kit makes no claims about downstream behaviour; the locale is a conformance-validation feature for HL7 integrators. (Scope correction 2026-06-18: the initial v0.4-S5-A entry framed this as "FHIR AU Core mapper unblocking", which overstated HL7v2Kit's purpose. Mapping happens in downstream consumers, not here.)
- 10 new tests in `LocaleTests.swift`. 318 → 332 tests across 22 → 23 suites green.
- **ADR-007** (`docs/design/ADR-007-au-profile-architecture.md`): Accepted 2026-06-18. Locale-aware architecture; base schemas stay spec-faithful; AU constraints live in separate `Resources/profiles/au-adrm-2021/` overlay (ships in S5-B).

### Added — v0.4-S2-reopen: v2.4 OBX-2 carry-forward (S2 deferred item closed for v2.4)

- **Trigger**: v2.4 Final Standard PDFs added at `docs/standards/HL7_v24_PDF/` (author-local, not committed pending IP review), including the AU ADRM-2021 localisation profile.
- **Schema correction**: `Resources/schemas/v2.4/OBX.json` — OBX-2 gains `condition: "OBX-11 != X"` per v2.4 §7.4.2.2. Wording is verbatim-identical to v2.5.1 §7.4.2.2; carry-forward is spec-citable.
- **Audit doc updated**: `docs/design/v2_3-v2_4-spec-audit.md` OBX-2 row now marks v2.4 RESOLVED with the v2.4 spec citation. v2.3 / v2.3.1 still deferred (no PDFs).

### Changed — Housekeeping: `add-kernel-headers.sh` moved to `scripts/`

- The one-shot kernel-header utility moved from repo-root to `scripts/`. Its `KERNEL_FILES` list extended to include the new `Sources/HL7v2Kit/Locale/HL7Locale.swift` so future re-runs cover the v0.4-S5-A additions.

### Added — v0.4-S2: structural delta audit of v2.3 / v2.3.1 / v2.4 schemas

- **`docs/design/v2_3-v2_4-spec-audit.md`** — new audit doc covering all 9 segments × 3 earlier HL7 v2 versions as structural deltas against the spec-audited v2.5.1 baseline.
- **0 corrections warranted on the structural-delta axis.** Per-field consistency check across 4 versions: every field present in 2+ versions has identical `name` / `dataType` / `optionality` / `repeatability`.
- **Field-count progression** captured for all 9 segments: MSH 15→17→20→21; PID 30→30→32→39; OBR 43→43→47→47; OBX 11→14→16→17; ORC 17→17→19→31; NTE 3→3→3→4. NK1 / PV1 / AL1 stable at their typed-surface caps. End-to-end pinned in `MultiVersionTests.swift`.
- **Conditional-rule carry-forward**: PID-35 / PID-36 from S4-C don't apply below v2.5 (fields don't exist). OBX-2 carry-forward is plausible but **deferred** — the v2.3 / v2.3.1 / v2.4 Final Standard PDFs aren't locally available, so the per-version §7.4.2.2 text can't be cited.
- **Known limitations documented honestly** under the the working notes "honesty over completeness" requirement: per-version conditional rules, per-version composite-component definitions, and per-version errata are deferred to a future cycle when the relevant PDFs become available.
- No schema mutations; no source / test changes. 322/322 tests across 22 suites green (unchanged).

### Added — v0.4-S4 substage C: spec-text-driven schema corrections (PID-35 / PID-36 / OBX-2)

- **Schema corrections under `Resources/schemas/v2.5.1/`**, each citable to the v2.5.1 Final Standard (ANSI/HL7 April 2007). The author's local copy of the spec PDFs (not committed pending IP review) was used; the audit doc lists section numbers for each citation:
  - **`PID.json`**: PID-35 (Species Code) gains `condition: "PID-36 populated OR PID-38 populated"` per §3.4.2.35. PID-36 (Breed Code) `condition` corrected from the backwards `"PID-35 populated"` to the spec-accurate `"PID-37 populated"` per §3.4.2.36. The pre-S4 predicate was on the wrong field and fired in the wrong direction; the original S1 audit's "non-human species" narrative was speculation, not a spec citation.
  - **`OBX.json`**: OBX-2 (Value Type) gains `condition: "OBX-11 != X"` per §7.4.2.2. Uses the new compound-DSL `!= <value>` operator.
- **Audit doc rewrite** (`docs/design/v2_5_1-spec-audit.md`):
  - **Gap 1 (PID conditional rules) RESOLVED** with spec citations.
  - **Gap 2 PARTIALLY RESOLVED**: OBX-2 closed; the 12 other fields (ORC-2 / ORC-3 / ORC-8 / OBR-1 / 7 / 8 / 10 / 14 / 22 / 25 / 26 / 32 / OBX-4) carry **cross-segment** rules (ORC-2 ↔ OBR-2 XOR per §4.5.1.2) or **message-context** rules (OBR-25 "when in a report message" per §4.5.3.25) that the same-segment compound DSL cannot express. Documented as known limitations requiring cross-segment DSL extension — candidate for post-v0.4 cycle. The S1 audit's "ORC-2 required when ORC-1 in (NW/CA/...)" claim was a speculative reconstruction and has been retracted in the audit doc.
  - **Gap 3 (composite OR-rules) RESOLVED** with the spec-text caveat that the OR-rule choices for CWE / XTN / HD / PL / EIP are interpretive (community-convention) rather than directly cited — the v2.5.1 component tables list all components as `O`. Documented so integrators don't mistake them for literal spec assertions.
- **Tests**: `Tests/HL7v2KitTests/ConditionalFieldTests.swift` rewritten around the corrected predicates. 11 tests cover: PID-37→PID-36 trigger + satisfaction, PID-36→PID-35 trigger + satisfaction, PID-38→PID-35 OR-branch trigger, OBX-11≠X→OBX-2 trigger + satisfaction, OBX-2-populated short-circuit, OBX-11=X no-trigger, plus the fixture-corpus regression pin (none of the 48 valid fixtures populate the veterinary fields or trigger the OBX-2 path). 318 → 322 tests across 22 suites green.
- **Spec PDFs** (Final Standard, April 2007) referenced locally during the audit; **not committed** pending IP review. The audit doc captures the specific section numbers and pull-quoted text so the conclusions remain reproducible without requiring the PDFs in-tree.

### Added — v0.4-S4 substages A + B: composite OR-rule enforcement + compound-predicate DSL

- **`Sources/HL7v2Kit/Composite/RequiredComponentSet.swift`** (new). Value type with two semantics cases: `.atLeastOneOf` and `.allOfGroupOrAtLeastOne(group:)`. Closes audit Gap 3: composites with OR-rule conformance (CWE / XTN / HD / PL / EIP) now enforce their spec rule via `requiredComponentSet`, instead of skipping silently. The Validator's `checkComponents` dispatches both the flat `requiredComponents` check (v0.2-V2) and the new OR-rule check (v0.4-S4) per repetition.
- **CWE composite behavioural change**: `requiredComponents` was `[(1, "Identifier")]`, which false-positive'd on legitimate CWE-9-only payloads. Now `requiredComponents = []`; `requiredComponentSet = atLeastOneOf(CWE-1, CWE-9)`. Migration: callers that scanned `CWE.requiredComponents` for `(1, "Identifier")` should switch to `CWE.requiredComponentSet`. Pre-v1.0 API change.
- **Compound-predicate DSL** in `Validator.conditionTriggers`. Grammar extends from single-atom (`<segment>-<index> <op>`) to `<atom> (AND <atom>)* (OR <atom>)*` plus `in (<values>)` / `not in (<values>)` set-membership operators. Recursive-descent evaluator; AND binds tighter than OR. `not in` requires referent to be populated (fail-safe rule for ambiguous empty referents). Schema strings continue to be the public format — no `FieldGrammar` API break.
- **Audit doc updated**: Gap 3 marked RESOLVED at commit `0959be6`; Gaps 1 + 2 marked INFRASTRUCTURE LANDED, SCHEMA-LEVEL CLOSURE PENDING (substage C blocked on spec-text citations for ORC-2's value set etc.).
- Test count: 316 → 318 across 22 suites green (2 new positive pins; 1 existing pin renamed + assertion updated). All 51 top-level + 3 batch fixtures still round-trip byte-perfect.

### Added — HL7 v2.5.1 schema audit document (v0.4-S1)

- **`docs/design/v2_5_1-spec-audit.md`** — new design doc capturing the v0.4-S1 audit of all 9 v2.5.1 schemas against the public HL7 v2.5.1 spec, **re-framed under the the working notes project requirements** (feature-complete over AU-specific; integrator primary-reference tool).
- **Per-field attributes (name / dataType / optionality / repeatability) — 0 corrections warranted** across 198 rows. The schemas faithfully render the spec on those four axes.
- **3 spec-completeness defects identified** — not deferrable under the project requirements; each must be closed before v1.0 freezes the API:
  1. **PID-36 `condition: "PID-35 populated"` is over-broad** — fires false-positive on spec-compliant `PID-35 = L1^Human` (human patient with species explicitly declared, PID-36 legitimately empty).
  2. **12+ `C` fields without predicates** — ORC-2 / ORC-3 / ORC-8 / OBR-1 / 7 / 8 / 10 / 14 / 22 / 25 / 26 / 32 / OBX-2 / 4 all carry compound `AND` / `OR` spec conditions the v0.2-V1 single-predicate DSL cannot express. Validator currently provides no enforcement.
  3. **Five composite OR-rules silently unenforced** — CWE-1 OR CWE-9; XTN-1 OR XTN-4 OR XTN-12; HD-1 OR HD-2&3; PL-1 OR PL-4; EIP-1 OR EIP-2. Validator's `requiredComponents` dispatch returns empty for each.
- **No schema mutations in S1.** The defect fixes require model extensions (compound predicates in the conditional-field DSL; `RequiredComponentSet` for composite OR-rules). Both are scheduled for **v0.4-S4** — a new stage inserted between S1 and S2 per the cycle re-scope. S4 extends the model; the schema-level corrections land in S4's commit alongside the model change. S2 and S3 then absorb the richer model.
- **v0.4 cycle scope updated** from Option A (6 stages) to Option α (7 stages) — see NEXT_STEPS.md for the new S4 task entry and the updated stage order on the spec branch (S1 → S4 → S2 → S3).
- **Note on framing history**: an earlier S1 framing deferred these as "AU traffic doesn't trigger them" known limitations. That framing was rejected by the project owner under the integrator-reference-tool requirement and replaced with the current "defect, not deferrable" classification. The the working notes update at commit `909142b` codifies the requirement going forward.
- **No source / generated / test changes** in S1. `SegmentGrammar+v2_5_1.swift` codegen output is byte-identical pre- and post-audit. 316/316 tests across 22 suites green (unchanged).

## [0.3.0] — 2026-06-17

v0.3 cycle release. Covers four parallel-track surface expansions and a post-cycle layout refactor: all 16 v2.5.1 typed-segment-surface composites promoted to Swift struct views; `Validator` dispatches four HL7 v2 versions (v2.3 / v2.3.1 / v2.4 / v2.5.1); MLLP framing + structural batch parser + streaming batch parser ship the full TCP-to-Messages pipeline; byte-level fuzz harness across every parser surface; fixture corpus grew 48 → 51 + 3 batch fixtures. **API-affecting** — 16 typed-segment accessor return types went `Field?` → `<Composite>?` across the cycle. Migration path preserved via the public `.field` escape hatch on each composite struct (per the v0.2-C1 pattern). The 3-month no-API-break v1.0 stability clock continues from this tag per Migration.md.

### Added — Fixture corpus growth past 48 (v0.3-Z2)

- **`Tests/Fixtures/` corpus grew 48 → 51 top-level + 3 batch fixtures**. New material targets the surfaces v0.3 introduced — earlier fixtures were all v2.5.1 single-message wires.
- **Multi-version fixtures** (top-level, picked up automatically by `FixtureRoundTripTests` since `Parser.parse(_:)` handles all four supported versions):
  - `adt_a01_v23.hl7` — minimal v2.3 admit; exercises the v2.3 grammar table (MSH cap at 15)
  - `orm_o01_v231.hl7` — v2.3.1 order; exercises the v2.3.1 grammar table (PID cap at 30, ORC cap at 17)
  - `oru_r01_v24.hl7` — v2.4 result; populates PID-31 / PID-32 (`identityUnknownIndicator` / `identityReliabilityCode`, the v2.4 additions); MSH-18 charset declared
- **Batch fixtures** (new `Tests/Fixtures/Batches/` subdirectory — `FixtureRoundTripTests` enumerates only the top-level dir, so these are intentionally invisible to the `Parser`-based round-trip harness):
  - `Batches/batch_bhs_minimal.hl7` — BHS + 1 MSH + BTS, smallest valid batch wrapper
  - `Batches/batch_file_full.hl7` — FHS + BHS + 2 MSH + BTS + FTS, exercises all four framing markers
  - `Batches/batch_multi_groups.hl7` — FHS + 2 BHS/BTS pairs + FTS (one ADT batch + one ORU batch)
- **New `Tests/HL7v2KitTests/BatchFixtureTests.swift`** enumerates `Batches/` and exercises every fixture through `BatchParser` + `StreamingBatchParser`. 5 tests cover: every-file-parses smoke check / each fixture's structural assertions / parity between `BatchParser` and `StreamingBatchParser` message counts.
- **`Tests/Fixtures/FIXTURES.md`** updated with provenance rows for all 6 new fixtures + a v0.3-Z2 status block above the table.
- **Fuzz coverage automatically grows**: `FuzzTests.swift`'s `seedFixtures()` loader pulls the 3 new top-level fixtures into the cross-product. Per-cycle mutation count: 47 × 7 × 100 × 5 ≈ 165k → **50 × 7 × 100 × 5 ≈ 175k** mutated payloads (Batches/ subdir is correctly skipped by the top-level enumeration). Fuzz suite still passes under `RUN_FUZZ_TESTS=1` (~5.8s).
- 5 new tests in `BatchFixtureTests.swift` (auto-discover-and-parse, three per-fixture structural checks, BatchParser/StreamingBatchParser parity). 311 → 316 tests across 21 → 22 suites on default `swift test`.

### Changed — `Generated/v2_5_1/` subdirectory flattened to `Generated/` (folder-layout consistency)

- **Typed-segment struct files moved up one level**: the 9 generated `<SegmentID>.swift` files (PID / MSH / NK1 / NTE / OBR / OBX / ORC / PV1 / AL1) now live directly at `Sources/HL7v2Kit/Segment/Generated/`, alongside the per-version `SegmentGrammar+vX_Y_Z.swift` tables and `SegmentRegistry+Generated.swift`. The misleading `v2_5_1/` subdirectory has been deleted.
- **Why.** The struct surface is **shared** across every supported HL7 v2 version (v2.3 / v2.3.1 / v2.4 / v2.5.1) — accessors for fields that don't exist at an older version return `nil` per the Optional contract. Placing the structs under `Generated/v2_5_1/` implied sibling `Generated/v2_3_1/`, `Generated/v2_4/`, etc. that by design will never exist. The new layout makes the folder hierarchy honest: structs are version-agnostic; grammar tables are per-version.
- **Mechanism.** Single edit in `Sources/HL7v2KitCodegen/Codegen.swift`: the canonical-version output path is now `outputRoot/<SegmentID>.swift` instead of `outputRoot/<versionDirName(canonicalVersion)>/<SegmentID>.swift`. The codegen-drift CI job already pins reproducibility — the regenerated layout is byte-identical across re-runs.
- **API-compatible**. Swift module structure is unchanged — `import HL7v2Kit` still surfaces `PID` / `MSH` / etc. at the top level. No callsite edits required.
- **Path references**: `Sources/HL7v2KitCodegen/Codegen.swift` `canonicalVersion` doc comment and `Sources/HL7v2Kit/HL7v2Kit.docc/TypedSegments.md` Overview updated to point at the new location. Historical CHANGELOG entries for v0.3-G1 and historical NEXT_STEPS task lines reference the old path and are intentionally left as-is — they describe what was true when they landed.

### Added — Fuzz testing harness (v0.3-Z1)

- **`Tests/HL7v2KitTests/FuzzTests.swift`** — byte-level fuzz harness covering all four parser surfaces: `Parser.parse(_ data:)`, `BatchParser.parse(_ data:)`, `StreamingBatchParser.feed/finish`, and `MLLPUnframer.feed(_:)` (plus a `MLLPUnframer → Parser` round-trip composition). For each surface, the harness iterates over the cross-product `gold-corpus fixtures × mutators × iterations` and asserts the only acceptable failure mode is a thrown `ParseError`. Any other behaviour (non-`ParseError` throw, force-unwrap trap, slice out-of-bounds, infinite loop) fails the test.
- **Mutators**: 7 small targeted perturbations — `bitFlip`, `byteReplace`, `byteInsert`, `byteDelete`, `truncate`, `delimiterCorrupt` (corrupts one of `|^~\&\r`), `nulInject`. Designed to surface bounds-checking bugs, not to model real-world corruption.
- **Seeded PRNG**: small Xorshift64\* generator with a fixed seed (`0xC0FFEE`) drives all mutations, so every fuzz failure is reproducible — the failing test records the (fixture × mutator × iteration) tuple and a replay against the same seed reproduces the case.
- **Skipped by default** like `PerformanceTests`. Run with `RUN_FUZZ_TESTS=1 xcrun swift test --filter FuzzTests`. Default `swift test` count goes 306 → 311 with the 5 fuzz tests marked `➜ skipped: "Set RUN_FUZZ_TESTS=1 to run the fuzz suite"`.
- **Coverage at landing time**: 47 fixtures × 7 mutators × 100 iterations × 5 surfaces ≈ 165,000 mutated payloads exercised in ~5.4 s on the dev machine. All five tests pass — no crashes, no unexpected error types — across the full grid. Validates the byte-level robustness of every parser-side surface added through v0.3.

### Added — Streaming batch parser (v0.3-S1)

- **`StreamingBatchParser`** — incremental, memory-bounded variant of `BatchParser`. Consumes byte chunks of arbitrary size via `feed(_ bytes: Data) throws -> [Message]` and emits each completed `Message` as soon as the next MSH (or batch marker, or EOF) closes the current run. Designed for very-large historical-extract files that don't fit comfortably in memory. New `Sources/HL7v2Kit/Parser/StreamingBatchParser.swift`.
- **API surface**: value-type `feed(_:) throws -> [Message]` + `finish() throws -> [Message]` core for direct chunked-I/O use; plus `static StreamingBatchParser.messages(from: AsyncSequence<UInt8>) -> AsyncThrowingStream<Message, Error>` wrapper for callers using `FileHandle.AsyncBytes` or network read loops. The async wrapper buffers in 4 KB chunks before delegating to the core. `hasPending: Bool` observer is exposed for half-frame timeout detection (true when the parser has a partial segment or an open MSH run).
- **Scope note** (documented on the struct doc): streaming mode flattens batch markers — FHS / FTS / BHS / BTS lines are recognised (so they correctly close any open message) but their wire strings are NOT preserved. Callers needing the file / batch structure should use the non-streaming `BatchParser`. Streaming mode also assumes UTF-8 input (MSH-18 charset detection requires buffering the whole first message, which defeats the streaming property).
- **NUL rejection** mirrors `Parser.parse(_ data:)` — a `0x00` byte in the stream throws `ParseError.truncatedMessage(atByte:)` with the byte offset, both in the synchronous and `AsyncStream` paths.
- 11 new tests in `Tests/HL7v2KitTests/StreamingBatchParserTests.swift` cover: whole-input feed-then-finish / marker flattening (FHS+BHS+BTS+FTS consumed, not preserved) / byte-at-a-time feed produces identical output / random-sized chunk feed identical / incremental emission (first message surfaces before `finish()` once the second MSH boundary appears) / unterminated trailing segment flushed by `finish()` / `hasPending` lifecycle / NUL byte rejection / 100-message batch streamed in 1 KB chunks doesn't accumulate state / AsyncStream wrapper yields in order / AsyncStream wrapper throws on NUL. 295 → 306 tests across 19 → 20 suites.
- **Closes the v0.3-transport track.** T1 (MLLP) + T2 (BatchParser) + S1 (StreamingBatchParser) now cover the full transport-and-batch surface.

### Added — FHS / BHS batch parser (v0.3-T2)

- **`BatchParser`** — new structural parser for HL7 v2 batch / file grammar. Recognises the four framing markers (`FHS` file header, `FTS` file trailer, `BHS` batch header, `BTS` batch trailer) and groups the MSH-starting message runs between them. Each message run is dispatched to `Parser(options:).parse(_:)` so encoding detection, composite parsing, escape decoding, and typed-segment hydration behave identically to the bare-message path. New `Sources/HL7v2Kit/Parser/BatchParser.swift`.
- **`BatchFile`** + **`BatchGroup`** — new public value types modelling the result. `BatchFile.fileHeader` / `fileTrailer` carry the FHS / FTS wire strings (or `nil` if absent); `BatchFile.batches: [BatchGroup]` carries one entry per `BHS` / `BTS` pair (or a single header-less group for bare multi-MSH input). `BatchGroup.header` / `trailer` mirror the same pattern. Convenience `BatchFile.allMessages` flattens the messages across groups in document order.
- **API forms**. `BatchParser.parse(_ data: Data) throws -> BatchFile` mirrors `Parser.parse(_ data:)` semantics (BOM stripping, NUL rejection, MSH-18 charset detection). `BatchParser.parse(_ raw: String) throws -> BatchFile` is the already-decoded counterpart. Both accept lenient line terminators (`\r`, `\n`, `\r\n` all normalise to `\r` before segmentation).
- **The v0.1.0 `multipleMSHSegmentsAcceptedAsIs` pin is preserved**. `Parser.parse(_:)` on a bare multi-MSH stream still returns one `Message` with multiple MSH segments — the v0.3-T2 `BatchParser` is the opt-in alternative for callers that explicitly want each MSH-starting run split. New test `parserMultiMSHBehaviourUnchanged` pins the contract.
- 11 new tests in `Tests/HL7v2KitTests/BatchParserTests.swift` cover: bare multi-MSH splits / single-message no-framing / batch-only framing (BHS+msgs+BTS) / fully-wrapped (FHS+BHS+...+BTS+FTS) / multi-batch file (two BHS/BTS pairs in one FHS/FTS) / empty batch (BHS immediately followed by BTS) / per-message delegation to the full Parser pipeline (typed composite accessors work) / `parse(Data:)` BOM strip + NUL rejection / lenient line terminators (LF parses identically to CR) / empty-input throws / regression pin for the v0.1.0 Parser contract. 284 → 295 tests across 18 → 19 suites.

### Added — MLLP framing (v0.3-T1)

- **`MLLP.frame(_:)`** — wraps an HL7 message body in the standard Minimum Lower Layer Protocol envelope (`0x0B <body> 0x1C 0x0D`). Callers stream the result directly to a TCP socket; body bytes are opaque (no escape processing at the MLLP layer).
- **`MLLPUnframer`** — stateful unframer that consumes incremental TCP byte chunks via `feed(_:)` and emits complete frame bodies as their trailing `0x1C 0x0D` arrives. Handles realistic TCP boundary cases: half-frames across multiple receives, multiple frames in one receive, byte-at-a-time delivery, garbage prefix before the first start byte (silently dropped — common receiver-resilience pattern), and mid-frame restart (a fresh `0x0B` re-syncs the buffer). Exposes `isMidFrame: Bool` for application-layer half-frame-timeout detection.
- **`MLLP`** namespace exports `startByte` (`0x0B`), `endBodyByte` (`0x1C`), `endFrameByte` (`0x0D`) for callers that need to inspect or hand-construct frames at the byte level.
- **Portable-kernel placement**. New `Sources/HL7v2Kit/Transport/MLLPCodec.swift` carries the PORTABLE KERNEL header per ADR-006 — `Data` only at API edges, `[UInt8]` for the inner buffer, no Foundation dependencies beyond the type itself. Future Rust/Go port translates this file directly.
- 12 new tests in `Tests/HL7v2KitTests/MLLPCodecTests.swift` cover framing (single + empty body + body preserved), unframing happy path (one frame / two concatenated / empty body), partial-frame streaming (half-and-half / three-way split / one-byte-at-a-time), resync (garbage prefix dropped / mid-frame restart), round-trip preservation, and end-to-end `frame() → unframe() → Parser.parse()` integration. 272 → 284 tests across 17 → 18 suites.

### Added — HL7 v2.3 grammar table + `Version.v2_3` case (v0.3-G3)

- **`Version.v2_3 = "2.3"`** — new enum case for the oldest HL7 v2 dialect HL7v2Kit supports. `Version` enum cases now cover `.v2_3` / `.v2_3_1` / `.v2_4` / `.v2_5_1` / `.v2_8`; messages with `MSH-12 = "2.3"` previously fell through `Version(rawValue:)` to nil and the parser's silent v2.5.1 fallback. Now they parse with the correct `.version == .v2_3` and route to the v2.3 grammar table.
- **`SegmentGrammarTable.v2_3`** — codegen-emitted Swift literal table baked from new `Resources/schemas/v2.3/*.json` schemas. `Validator.grammarTable(for:)` extended: `case .v2_3 → SegmentGrammarTable.v2_3`. Four distinct grammar tables (v2.3 / v2.3.1 / v2.4 / v2.5.1) now dispatched.
- **`Resources/schemas/v2.3/*.json`** — 9 hand-curated schemas pruned from the v2.5.1 sources to the v2.3-era field caps: MSH 21 → 15 (no MSH-16 application-acknowledgement, MSH-17 country code, MSH-18 charset and beyond), OBX 17 → 11 (v2.3 had the early observation slots only; OBX-12..17 are v2.3.1+ / v2.4+ / v2.5+ additions). PID / ORC / OBR / NK1 / PV1 / NTE / AL1 unchanged from the v2.3.1 caps (already at or below the v2.3 surface).
- 6 new tests in `Tests/HL7v2KitTests/MultiVersionTests.swift`: v2.3 version detection / round-trip / dispatch / grammar table populated with v2.3 caps / four-way grammar dispatch confirming MSH grows monotonically 15 → 17 → 20 → 21 across v2.3 → v2.3.1 → v2.4 → v2.5.1 / typed accessors for v2.4+ fields return nil on a v2.3 wire. 266 → 272 tests across 17 suites.
- This commit closes the v0.3-multiversion track. Three new grammar tables landed total (v2.3 / v2.3.1 / v2.4); v2.5.1 unchanged.

### Added — HL7 v2.4 grammar table (v0.3-G2)

- **`SegmentGrammarTable.v2_4`** — codegen-emitted Swift literal table baked from new `Resources/schemas/v2.4/*.json` schemas; sits between v2.3.1 and v2.5.1 in field-count granularity. `Validator.grammarTable(for:)` extended: `case .v2_4 → SegmentGrammarTable.v2_4`. Only `.v2_8` remains at the empty-table fallback until v0.3 ships a future v2.8 stage.
- **`Resources/schemas/v2.4/*.json`** — 9 hand-curated schemas pruned from the v2.5.1 sources with the field caps that match the v2.4 spec surface: MSH 21 → 20 (no MSH-21 `messageProfileIdentifier`), PID 39 → 32 (adds PID-31 `identityUnknownIndicator` + PID-32 `identityReliabilityCode` over v2.3.1's 30; cuts the v2.5 species/breed/strain/tribal-citizenship tail), ORC 31 → 19 (adds ORC-18 `entererAuthorizationMode`-ish slot + ORC-19 `actionBy` over v2.3.1's 17; cuts the v2.5 ordering-facility cluster), OBX 17 → 16 (adds OBX-15 `producerIdentifier` + OBX-16 `responsibleObserver` over v2.3.1's 14; cuts OBX-17 `observationMethod` which is v2.5), OBR 43 → 47 (v2.4 already at the v2.5.1 surface for OBR — keep the full 47). NK1 / PV1 / NTE / AL1 unchanged from the v2.3.1 caps (already at or below the v2.4 surface).
- 6 new tests in `Tests/HL7v2KitTests/MultiVersionTests.swift`: v2.4 version detection / round-trip / validator routes to v2.4 grammar / table populated with v2.4 caps / typed accessors expose the v2.4 additions (PID-31/32) while v2.5-only fields stay nil / three-way cross-check confirms PID grows monotonically 30 → 32 → 39 across v2.3.1 → v2.4 → v2.5.1. 260 → 266 tests across 17 suites.

### Added — HL7 v2.3.1 grammar table (v0.3-G1)

- **Validator now dispatches grammar by message version.** Messages with `MSH-12 = "2.3.1"` validate against the new `SegmentGrammarTable.v2_3_1` table; v2.5.1 messages keep validating against the existing `SegmentGrammarTable.v2_5_1` table. The dispatch lives in `Validator.grammarTable(for:)` as a per-version switch. v2.4 / v2.8 fall back to an empty table (no grammar errors emitted) until v0.3-G2 / G3 land.
- **`Resources/schemas/v2.3.1/*.json`** — hand-curated JSON schemas for all 9 spec § 17 segments, pruned from the v2.5.1 schemas to the v2.3.1-era field counts: MSH 21 → 17 (no MSH-18 charset / MSH-19 principalLanguageOfMessage / MSH-20 altCharsetHandlingScheme / MSH-21 messageProfileIdentifier), PID 39 → 30 (no v2.4 identity flags or v2.5 species/breed/tribal-citizenship), ORC 31 → 17 (no v2.4 advancedBeneficiaryNoticeCode or v2.5 ordering-facility / confidentiality cluster), OBR 47 → 43 (no v2.4 results-handling extensions), OBX 17 → 14 (no v2.4 producerIdentifier / responsibleObserver / observationMethod). NK1 / PV1 / NTE / AL1 keep their existing field caps (already at or below the v2.3.1 surface).
- **`SegmentGrammarTable.v2_3_1`** — codegen-emitted Swift literal table baked from the v2.3.1 schemas, parallel to the existing v2.5.1 table. Total ~150 grammar entries across 9 segments. Reproducible across runs; CI codegen-drift job pins the output.
- **Mechanism**. `Sources/HL7v2KitCodegen/Codegen.swift` now declares `let canonicalVersion = "2.5.1"` and treats only the canonical version's schemas as the source of typed-struct emission — the v2.3.1 schemas contribute only to the grammar table. The shared typed `struct PID` / `struct ORC` / ... lives under `Generated/v2_5_1/` and represents the union surface; accessors for v2.4+ / v2.5+ fields on a v2.3.1 wire simply return `nil` (the normal Optional contract for an absent field). No per-version Swift namespace required; no API change for callers.
- 7 new tests in `Tests/HL7v2KitTests/MultiVersionTests.swift` cover: v2.3.1 wire parses with `.version == .v2_3_1`; v2.3.1 wire round-trips byte-perfectly; path and typed accessors agree on a v2.3.1 wire; validation runs against the v2.3.1 grammar table (not v2.5.1); the v2.3.1 grammar table is populated for all 9 segments with the right field counts; v2.5.1-only typed accessors return nil on a v2.3.1 wire; v2.5.1 messages still route to the v2.5.1 grammar table (regression pin). 253 → 260 tests across 16 → 17 suites.

### Changed — API-BREAKING (typed composites, v0.3-C4)

- **Typed-segment accessors for HD-, MSG-, PT-, VID-, PL-, CNE-, XON- and EIP-typed fields now return Swift struct views** instead of `Field?`. With v0.3-C4 closing out the composite-promotion track, **every populated typed-segment accessor on the 9 spec § 17 segments now returns either a `String?` (scalar) or a typed composite struct** — there are no remaining `Field?` accessors for structured HL7 datatypes on the v2.5.1 typed-segment surface. New structs live under `Sources/HL7v2Kit/Composite/` following the v0.2-C1 / v0.3-C2 / v0.3-C3 template.
  - `HD` — `namespaceID`, `universalID`, `universalIDType`. All 3 spec components exposed.
  - `MSG` — `messageCode`, `triggerEvent`, `messageStructure`. All 3 spec components exposed.
  - `PT` — `processingID`, `processingMode`. All 2 spec components exposed.
  - `VID` — `versionID`, `internationalizationCode` (first subcomponent of the nested CE), `internationalVersionID` (first subcomponent of the nested CE). All 3 spec slots exposed.
  - `PL` — `pointOfCare`, `room`, `bed`, `facility` (first subcomponent of the nested HD). The first 4 of 12 PL components — the AU clinical traffic common case. PL-5..12 remain accessible via `.field`.
  - `CNE` — `identifier`, `text`, `nameOfCodingSystem`, `altIdentifier`, `altText`, `nameOfAltCodingSystem`. All 6 spec components exposed (same shape as CE).
  - `XON` — `organizationName`, `organizationNameTypeCode`, `identifierTypeCode`, `organizationIdentifier`. The 4 commonly-populated XON components; XON-3 (deprecated), XON-4/5 (check digit / scheme), XON-6 (assigning authority, nested HD), XON-8 (assigning facility, nested HD), and XON-9 remain accessible via `.field`.
  - `EIP` — `placerAssignedIdentifier`, `fillerAssignedIdentifier`. Each accessor returns the first subcomponent of the nested EI (EI-1 entityIdentifier); for the full nested EI structure, drill into `.field.first?.components[N]`.
- **Required-component metadata**:
  - `MSG.requiredComponents = [(1, "Message Code")]`, `PT.requiredComponents = [(1, "Processing ID")]`, `VID.requiredComponents = [(1, "Version ID")]`, `CNE.requiredComponents = [(1, "Identifier")]`, `XON.requiredComponents = [(1, "Organization Name")]` — empty primary slot on a populated field fires `.requiredComponentMissing`.
  - `HD.requiredComponents = []`, `PL.requiredComponents = []`, `EIP.requiredComponents = []` — empty by design. HD's "HD-1 OR (HD-2 AND HD-3)", PL's "PL-1 OR PL-4", and EIP's "either slot populated" are the same disjunctive OR-rule shape v0.3-C2 / v0.3-C3 documented for CWE / XTN — modelling these is a future `RequiredComponentSet` refactor that v0.3-C4 explicitly avoids. Each empty `requiredComponents` choice is pinned by a dedicated `…SkipsSilentlyWithNoRequiredComponents` test so the choice can't silently flip later.
- **Affected typed-segment accessors** (any field with `dataType ∈ {HD, MSG, PT, VID, PL, CNE, XON, EIP}` across the 9 spec § 17 segments):
  - **HD**: `MSH.sendingApplication` / `sendingFacility` / `receivingApplication` / `receivingFacility`; `PID.lastUpdateFacility`. 5 accessors.
  - **MSG**: `MSH.messageType`. 1 accessor.
  - **PT**: `MSH.processingID`. 1 accessor.
  - **VID**: `MSH.versionID`. 1 accessor.
  - **PL**: `PV1.assignedPatientLocation` / `priorPatientLocation` / `temporaryLocation`; `ORC.enterersLocation`. 4 accessors.
  - **CNE**: `ORC.entererAuthorizationMode`. 1 accessor.
  - **XON**: `NK1.organizationName`; `ORC.orderingFacilityName`. 2 accessors.
  - **EIP**: `ORC.parent`; `OBR.parent`. 2 accessors.
- **Migration path** preserved via the public `field: Field` escape hatch — the same v0.1.x → v0.3.x pattern documented for the earlier composite promotions. `pid.lastUpdateFacility?.first?.components[0].stringValue` becomes either `pid.lastUpdateFacility?.field.first?.components[0].stringValue` (one extra hop) or the named accessor `pid.lastUpdateFacility?.namespaceID`.
- **Mechanism**. `Codegen.compositeDataTypes` whitelist extended to `["XPN", "CX", "XAD", "CE", "CWE", "EI", "XCN", "XTN", "HD", "MSG", "PT", "VID", "PL", "CNE", "XON", "EIP"]` — one-line edit. `Validator.requiredComponents(forCompositeCode:)` switch gains the 8 new cases.
- **Behavioural change on V2 component-grammar check**: messages with a populated MSG / PT / VID / CNE / XON field that lacks the required primary component now fire `.requiredComponentMissing` — previously skipped because these composites were untyped. Gold-corpus fixtures all populate the required component properly and remain unaffected; pinned by `ComponentGrammarTests.fixtureCorpusNoComponentErrors`. HD / PL / EIP remain silent because their `requiredComponents` is empty by design.
- **Test landscape**. `Validator`'s `untypedCompositesSkippedSilently` test rebased onto a new `hdSkipsSilentlyWithEmptyRequiredComponents` — the contract it was pinning (untyped composites skip silently) is now vacuous because every typed-segment composite is typed; the rebased test pins the related contract that HD's *deliberately empty* `requiredComponents` doesn't false-positive on legitimate HD-2-only fields. 11 existing test sites across `TypedSegmentTests.swift` migrated from `.first?.components[N].stringValue` to typed named accessors. 16 new tests in `CompositeTypeTests.swift` cover every named accessor on each of the 8 new composites + cross-check against path API + round-trip preservation. 7 new V2 tests in `ComponentGrammarTests.swift`: 5 positive enforcement tests (MSG / PT / VID / CNE / XON empty-primary fires) + 2 negative pins (PL / EIP empty-required-components skips silently). 230 → 253 tests across 16 suites.

### Changed — API-BREAKING (typed composites, v0.3-C3)

- **Typed-segment accessors for EI-, XCN- and XTN-typed fields now return Swift struct views** (`EI?` / `XCN?` / `XTN?`) instead of `Field?`. New structs live under `Sources/HL7v2Kit/Composite/` following the v0.2-C1 / v0.3-C2 template (value-type view over `Field`; `Sendable + Equatable + Hashable`; `init(field:)` + `init(repetition:)`; named accessors via a private `componentValue(_:)` helper; `static let requiredComponents` for V2 enforcement).
  - `EI` — `entityIdentifier`, `namespaceID`, `universalID`, `universalIDType`. All 4 spec components exposed.
  - `XCN` — `idNumber`, `familyName`, `givenName`, `middleName`, `suffix`, `prefix_`. The first 6 of XCN's 23 spec components — covers the common ID-plus-name-parts case. XCN-7..23 (degree, source table, assigning authority, name type code, identifier check digit, check digit scheme, identifier type code, assigning facility, name representation code, name context, name validity range, name assembly order, effective date, expiration date, professional suffix, assigning jurisdiction, assigning agency or department) remain accessible via `.field`.
  - `XTN` — `telephoneNumber` (XTN-1 deprecated free-form), `telecommunicationUseCode`, `telecommunicationEquipmentType`, `emailAddress`, `countryCode`, `areaCityCode`, `localNumber`, `unformattedTelephoneNumber` (XTN-12 modern primary). Covers the common phone / email / fax case; XTN-8..11 (extension, any text, extension prefix, speed dial code) and XTN-13/14 remain accessible via `.field`.
- **Required-component metadata**:
  - `EI.requiredComponents = [(1, "Entity Identifier")]` — empty EI-1 on a populated EI fires `.requiredComponentMissing`.
  - `XCN.requiredComponents = [(1, "ID Number")]` — empty XCN-1 on a populated XCN fires `.requiredComponentMissing`.
  - `XTN.requiredComponents = []` — empty by design. XTN-1 is deprecated and XTN-12 is the modern primary, but neither is strictly required; the "at least one of XTN-1 / XTN-4 / XTN-12" pattern is the same OR-rule shape v0.3-C2 documented for CWE. Modelling disjunctive required-component sets is a future RequiredComponentSet refactor that v0.3-C3 explicitly avoids.
- **Affected typed-segment accessors** (any field with `dataType ∈ {EI, XCN, XTN}` across the 9 spec § 17 segments):
  - **EI**: `MSH.messageProfileIdentifier`; `ORC.placerOrderNumber` / `fillerOrderNumber` / `placerGroupNumber`; `OBR.placerOrderNumber` / `fillerOrderNumber`. 6 accessors total.
  - **XCN**: `ORC.enteredBy` / `verifiedBy` / `orderingProvider` / `actionBy`; `OBR.collectorIdentifier` / `orderingProvider` / `resultCopiesTo`; `OBX.responsibleObserver`; `PV1.attendingDoctor` / `referringDoctor` / `consultingDoctor` / `admittingDoctor`. 12 accessors total.
  - **XTN**: `PID.phoneNumberHome` / `phoneNumberBusiness`; `NK1.phoneNumber` / `businessPhoneNumber`; `ORC.callBackPhoneNumber` / `orderingFacilityPhoneNumber`; `OBR.orderCallbackPhoneNumber`. 7 accessors total.
- **Migration path** preserved via the public `field: Field` escape hatch — v0.1.x / v0.2.x callers can rewrite `orc.orderingProvider?.first?.components[1].stringValue` as either `orc.orderingProvider?.field.first?.components[1].stringValue` (one extra hop) or migrate to the named accessor `orc.orderingProvider?.familyName`. Cross-check invariant holds for both: `orc.orderingProvider?.idNumber == message["ORC-12.1"]`.
- **Mechanism**. `Codegen.compositeDataTypes` whitelist extended to `["XPN", "CX", "XAD", "CE", "CWE", "EI", "XCN", "XTN"]` — one-line edit. `Validator.requiredComponents(forCompositeCode:)` switch gains EI/XCN/XTN cases.
- **Round-trip preserved**. Composite structs are value-type *views* over `Field`, not owners — the segment still holds the bytes. All 48 gold-corpus fixtures round-trip byte-identical; `CompositeTypeTests.compositeRoundTripsByteIdentical` covers EI/XCN/XTN wires too.
- **Behavioural change on V2 component-grammar check**: messages with an EI field populated as `^HOSP^ISO` (EI-1 empty) now fire `.requiredComponentMissing` at the appropriate field path — previously skipped because EI was untyped. Same for XCN with empty XCN-1. Gold-corpus fixtures all populate EI-1 / XCN-1 properly and remain unaffected; pinned by `ComponentGrammarTests.fixtureCorpusNoComponentErrors`.
- 9 new tests in `Tests/HL7v2KitTests/CompositeTypeTests.swift` cover every named accessor on each composite + the `.field` migration path (EI) + multi-repetition access (XCN consulting doctors, XTN home + mobile) + cross-check against path API + round-trip preservation. 3 new V2 tests in `ComponentGrammarTests.swift` (`eiFiresComponentMissingOnEmptyEntityIdentifier`, `xcnFiresComponentMissingOnEmptyIdNumber`, `xtnSkipsSilentlyWithNoRequiredComponents` — the last pins XTN's deliberately-empty `requiredComponents` list as the design choice). 11 existing test sites across `TypedSegmentTests.swift` migrated to the new named accessors. 218 → 230 tests across 16 suites.

### Changed — API-BREAKING (typed composites, v0.3-C2)

- **Typed-segment accessors for CE- and CWE-typed fields now return Swift struct views** (`CE?` / `CWE?`) instead of `Field?`. New structs live under `Sources/HL7v2Kit/Composite/` and expose named accessors for every component the spec defines:
  - `CE` — `identifier`, `text`, `nameOfCodingSystem`, `altIdentifier`, `altText`, `nameOfAltCodingSystem`
  - `CWE` — `identifier`, `text`, `nameOfCodingSystem`, `altIdentifier`, `altText`, `nameOfAltCodingSystem`, `codingSystemVersionID`, `altCodingSystemVersionID`, `originalText`
- **Required-component metadata** for both: CE-1 / CWE-1 (Identifier). `Validator.checkComponentGrammar` now fires `.requiredComponentMissing` on CE/CWE fields populated with an empty CE-1 / CWE-1 (e.g. `PID|...||^WhiteTextOnly` on PID-10). CWE's `"CE-1 OR CE-9"` OR-semantics from the v2.5.1 spec is simplified to "CE-1 required only" — documented as a known divergence; the conditional-field DSL doesn't yet support disjunctive component conditions.
- **Affected typed-segment accessors** (any field with `dataType ∈ {CE, CWE}` across the 9 spec § 17 segments):
  - **CE**: `MSH.principalLanguageOfMessage`; `AL1.allergenTypeCode` / `allergenCodeMnemonicDescription` / `allergySeverityCode`; `NK1.relationship` / `administrativeSex`; `OBR.universalServiceIdentifier` / many; `OBX.observationIdentifier` / `units` / many; `ORC.orderControlCodeReason` / `enteringOrganization` / `enteringDevice` / `advancedBeneficiaryNoticeCode`; `PID.race` / `primaryLanguage` / `maritalStatus` / `religion` / `ethnicGroup` / `citizenship` / `veteransMilitaryStatus` / `nationality` / `speciesCode` / `breedCode` / `productionClassCode`.
  - **CWE**: `PID.tribalCitizenship`; `ORC.orderStatusModifier` / `advancedBeneficiaryNoticeOverrideReason` / `confidentialityCode` / `orderType` / `parentUniversalServiceIdentifier`.
- **Migration path** preserved via the public `field: Field` escape hatch — v0.1.x callers can rewrite `pid.race?.first?.components[0].stringValue` as either `pid.race?.field.first?.components[0].stringValue` (one extra hop) or migrate to the named accessor `pid.race?.identifier`. Cross-check invariant holds for both: `pid.race?.identifier == message["PID-10.1"]`.
- **Mechanism**. `Codegen.compositeDataTypes` whitelist extended to `["XPN", "CX", "XAD", "CE", "CWE"]` — one-line edit. `Validator.requiredComponents(forCompositeCode:)` switch gains CE/CWE cases.
- **Round-trip preserved**. Composite structs are value-type *views* over `Field`, not owners — the segment still holds the bytes. All 48 gold-corpus fixtures round-trip byte-identical; `CompositeTypeTests.compositeRoundTripsByteIdentical` covers CE/CWE wires too.
- **Behavioural change on V2 component-grammar check**: messages with PID-10 (race) populated as `^WhiteTextOnly` (CE-1 empty) now fire `.requiredComponentMissing` at `PID[1]-10.1` — previously skipped because CE was untyped. Gold-corpus fixtures all populate CE-1 properly and remain unaffected; pinned by the updated `ComponentGrammarTests.fixtureCorpusNoComponentErrors`.
- 8 new tests in `Tests/HL7v2KitTests/CompositeTypeTests.swift` cover every named accessor on each composite + the `.field` migration path + multi-repetition access (PID-10 race) + cross-check against path API + round-trip preservation. 2 new V2 tests in `ComponentGrammarTests.swift` (`ceFiresComponentMissingOnEmptyIdentifier`, `cweFiresComponentMissingOnEmptyIdentifier`); the old "CE / CWE / EI skipped silently" test refactored to use the still-untyped HD (PID-34 lastUpdateFacility). 21 existing test sites across `TypedSegmentTests.swift` migrated to the new named accessors. 210 → 218 tests across 16 suites.

## [0.2.0] — 2026-06-15

### Added (infrastructure)

- **Top-level `HL7v2Kit.xcworkspace/`** at the repo root. Open with `open HL7v2Kit.xcworkspace` instead of `Package.swift` directly. Single `<FileRef>` to the package today; scales to multi-repo when `FHIRAUCoreKit` and `AUCoreWorkbench` land by adding more `<FileRef>` entries. The auto-generated `.swiftpm/xcode/package.xcworkspace` stays gitignored.
- **Four v0.2 git worktrees** under `~/Developer/HL7v2Kit-worktrees/` for parallel-branch development, all branched off `main` at `69060e4`:
  - `v0.2-parser-hardening` — P1 BOM → P2 NUL → P3 unsupportedVersion (serial; all touch `Parser.swift`) **— landed & merged 2026-06-14; worktree dropped**
  - `v0.2-composites` — C1 typed composite data types → V2 component-level validation
  - `v0.2-fringe-fields` — F1 PID/ORC fringe-field expansion → V1 conditional-field evaluation
  - `v0.2-perf-tests` — X1 performance budget tests
  - Documented merge order: parser-hardening → fringe-fields → composites → perf-tests.
- **`NEXT_STEPS.md` reorganised** around the v0.2 cycle: new "Workspaces and worktrees" section, each task names its worktree + position in the serial chain, full v0.1.0 task history preserved under "Historical: v0.1.0 runway".
- **`the working notes` "Project at a glance"** surfaces the workspace + worktree setup so future sessions discover them without re-derivation.

### Fixed (parser hardening)

- **v0.2-P1 — UTF-8 BOM prefix is now explicitly stripped** in `Parser.parse(_ data:)` before charset detection. Previously this depended on Foundation's `String(data:encoding:.utf8)` silently dropping the BOM, which Linux Swift does not do — so the byte path behaved differently across platforms. Now the 3-byte `EF BB BF` prefix is detected and dropped in HL7v2Kit code; behaviour is identical on macOS and Linux. The String overload (`parse(_ raw:)`) is unaffected because it operates on already-decoded text. The serializer never re-emits the BOM, so a round-trip canonicalises the output. A BOM-only input still throws `.emptyInput` (the empty-after-strip case is checked explicitly). DocC on `parse(_ data:)` documents the contract. Pin in `ParseErrorTests.swift` renamed `bomPrefixSilentlyAccepted` → `bomPrefixStrippedExplicitly` and asserts the round-trip canonicalisation; new `bomOnlyInputIsEmptyAfterStrip` pins the empty-after-strip edge. 159 → 160 tests.
- **v0.2-P2 — Embedded NUL bytes are now rejected at parse time** with `ParseError.truncatedMessage(atByte:)`. Real HL7 v2 wire never carries NUL; an embedded `0x00` is almost always transport truncation (a fixed-size buffer NUL-padded beyond the real message). Rejecting up-front keeps the round-trip byte-equality invariant (spec §5) honest — every accepted message is NUL-free, no carve-out required. The reported byte offset is into the **post-BOM-strip payload**, not the original wire (so a NUL at byte 100 of a BOM-prefixed input reports as 100, not 103). Pin in `ParseErrorTests.swift` renamed `midMessageNULLossy` → `midMessageNULRejected` (was "round-trip is lossy"; now asserts the throw). New `nulOffsetIsRelativeToStrippedPayload` pins the post-strip-offset design choice. 160 → 161 tests.
- **v0.2-P3 — `.unsupportedVersion` now fires on `Parser(options: .strict)`** when MSH-12 carries a non-empty value the `Version` enum doesn't recognise. Default + lenient preserve the existing silent v2.5.1 fallback (intentional — keeps the parser useful for older fixtures with non-canonical MSH-12). Empty MSH-12 always falls back regardless of the strict flag (that's a Validator concern; MSH-12 is required, not "must map to a known version"). Mechanism: new `ParserOptions.rejectUnknownVersion: Bool` flag (default `false`); `.strict` sets it `true`. `.strict` is now a superset of `.default`'s checks (rejects unknown segments + unknown versions). Pin in `ParseErrorTests.swift`: `unknownVersionFallsBack` → `unknownVersionFallsBackOnDefault` (still passes; default unchanged); new `unknownVersionThrowsOnStrict` and `emptyMSH12FallsBackEvenOnStrict` pin the strict throw and the empty-MSH-12-still-falls-back design choice. 161 → 163 tests.

### Added (schema coverage)

- **v0.2-F1 — PID and ORC are now spec-complete for v2.5.1.** PID extended from 30 → 39 fields: `identityUnknownIndicator` (ID), `identityReliabilityCode` (IS, repeating), `lastUpdateDateTime` (TS), `lastUpdateFacility` (HD), `speciesCode` / `breedCode` / `productionClassCode` (CE), `strain` (ST), `tribalCitizenship` (CWE, repeating). ORC extended from 19 → 31 fields: `advancedBeneficiaryNoticeCode` (CE), `orderingFacilityName` (XON, repeating), `orderingFacilityAddress` / `orderingProviderAddress` (XAD, repeating), `orderingFacilityPhoneNumber` (XTN, repeating), `orderStatusModifier` (CWE), `advancedBeneficiaryNoticeOverrideReason` (CWE), `fillersExpectedAvailabilityDateTime` (TS), `confidentialityCode` / `orderType` / `parentUniversalServiceIdentifier` (CWE), `entererAuthorizationMode` (CNE). Schema-only change: typed-segment files regenerate via `bash scripts/regenerate-typed-segments.sh`; codegen output is reproducible.
- 14 new cross-check tests in `TypedSegmentTests.swift`: 7 for PID-31..39 (scalar accessors + CE/HD/CWE composites + round-trip), 7 for ORC-20..31 (scalar TS + CE/CWE/XON/XAD/CNE composites + round-trip). Both fringe wires include the standard field-map comment per the multi-field-fixture convention. All 48 fixture round-trips still byte-perfect.
- Generated file sizes: `PID.swift` 145 → 210 lines, `ORC.swift` 90 → 170 lines — both under the soft 300-line cap, no per-field-group split required.

### Added (validator)

- **v0.2-V1 — Conditional-field evaluation in `Validator`.** `.conditional` (HL7 optionality `C`) fields can now carry a predicate that controls when they become required. New `FieldGrammar.condition: String?` carries the predicate; new `ValidationOptions.checkConditionalFields: Bool` (default `true`; `.lenient` preset sets `false`) gates evaluation; `Validator` emits the already-reserved `IssueCode.conditionalFieldMissing` when a predicate evaluates to true on an empty field.
- **DSL grammar** (kept deliberately small): `<segment-id>-<index> <predicate>` where `<predicate>` ∈ `"populated"`, `"empty"`, `"= <value>"`, `"!= <value>"`. Same-segment references only in v0.2; cross-segment references and malformed predicates fail safe (treated as no-trigger so a schema typo never makes a previously-accepted message non-conformant). `populated`/`empty` use the any-subcomponent-non-empty check; `=`/`!=` compare against the first-subcomponent-of-first-component-of-first-repetition "scalar view" of the field.
- **First real condition shipped:** `PID-36` (Breed Code) carries `"PID-35 populated"` — "if a species code is declared, a breed code is required" — the natural veterinary-HL7 interpretation. All 48 gold-corpus fixtures are unaffected because none populate PID-35 (all human patients); pinned by `ConditionalFieldTests.fixtureCorpusNoConditionalErrors`.
- **C fields without a condition** (e.g. `ORC-2`/`ORC-3`/`ORC-8`/`PID-35` itself) continue to behave as `.optional` — backward compatible. Conditions can be added to those JSON entries in future stages without code changes.
- **Codegen extended:** `FieldSchema.condition: String?` (optional Decodable) feeds the new `condition:` argument in the emitted `FieldGrammar(...)` table entries. `FieldGrammar.init`'s `condition: String? = nil` default keeps hand-rolled construction compatible.
- 6 new tests in `Tests/HL7v2KitTests/ConditionalFieldTests.swift`: condition triggers with field empty → error, condition triggers with field populated → no error, condition doesn't trigger → no error, `checkConditionalFields=false` suppresses, `.lenient` preset suppresses, full-corpus regression pin. 173 → 179 tests across 12 → 13 suites.

Tests: 159 (v0.1.0 tag) → 205 (default `swift test`); 210 with `RUN_PERF_TESTS=1`. Per-stage net: 4 from parser-hardening (P1+P2+P3) + 14 from F1 + 6 from V1 + 11 from C1 + 11 from V2 + 5 from X1 (skipped by default) = 51 net; 46 active by default. All 48 fixture round-trips still byte-perfect.

### Added — performance budget tests (v0.2-X1)

- **New `Tests/HL7v2KitTests/PerformanceTests.swift`** carrying 5 nightly latency assertions per spec § 9.5 (Apple Silicon M1+ budgets):
  - Parse 1 message (~600 bytes) under 1ms warm
  - Parse 1,000 messages under 5s
  - Round-trip 1,000 messages under 10s
  - Validate 1 message (default options) under 2ms warm
  - Validate 1,000 messages under 10s
- **Skipped by default.** The suite gates on `ProcessInfo.processInfo.environment["RUN_PERF_TESTS"] == nil` via the `@Suite(.disabled(if:))` trait, so the everyday `swift test` run stays fast. To run the perf suite: `RUN_PERF_TESTS=1 xcrun swift test`. Output marks the skipped tests with `➜ ... skipped: "Set RUN_PERF_TESTS=1 to run the perf suite"`.
- **Timing uses `Date()` differences** for portability with macOS 12+ (Foundation's `ContinuousClock` is macOS 13+). Precision is ~µs — plenty for ms/s budgets.
- Representative ~600-byte ADT^A01 wire (synthesised from the `adt_a01_minimal.hl7` gold-corpus fixture) carries the composite types most AU clinical traffic populates (CX/XPN/CE/XAD/XTN on PID; PL/XCN on PV1) so the budget covers a realistic critical path. Warm-up loops (100 iterations) precede the single-iteration measurements.
- Measured on the dev machine at landing time: parse-warm ≈ 41ms suite time; 1000-parse 0.176s; 1000-round-trip 0.233s; validate-warm 35ms suite time; 1000-validate 0.056s. All comfortably under budget; spec also reserves a 20% regression threshold above these numbers.
- 5 new tests in the disabled-by-default suite. Default `swift test` count: 205 → 210 (5 skipped, not 5 net additions).

### Added — component-level grammar in Validator (v0.2-V2)

- **`Validator` now enforces required sub-components on populated composite-typed fields.** Each typed composite (XPN / CX / XAD) carries a `static let requiredComponents: [RequiredComponent]` listing its mandatory sub-components per HL7 v2.5.1: XPN-1 Family Name, CX-1 ID Number, XAD-1 Street Address. When a composite is populated but a required component is empty, the validator emits `IssueCode.requiredComponentMissing` with a component-level location.
- **New `RequiredComponent` value type** (`Sources/HL7v2Kit/Composite/RequiredComponent.swift`) — `Sendable + Equatable + Hashable` shape `{ index: Int, name: String }`.
- **`IssueLocation` gains `componentIndex: Int?`** (defaulted to nil for backward compatibility). `pathDescription` now renders as `"PID[1]-5.1"` when the component index is set, alongside the existing `"PID[1]-3"` (field-level) and `"ZAU[1]"` (segment-level) shapes.
- **New `ValidationOptions.checkComponentGrammar: Bool`** toggle (default `true`; `.strict` keeps it on; `.lenient` disables it).
- **Composites without typed metadata** (CE / CWE / EI / XCN / HD / MSG / PT / VID / XTN / PL / CNE / XON / EIP) skip silently — they can be promoted incrementally by adding a `static let requiredComponents` and extending `Validator.requiredComponents(forCompositeCode:)`.
- **Backward-compatible additive change** — no migration burden on v0.1.x callers beyond the C1 breaking change. All 48 gold-corpus fixtures still produce a non-error report; the regression pin lives in `ComponentGrammarTests.fixtureCorpusNoComponentErrors`.
- 11 new tests in `Tests/HL7v2KitTests/ComponentGrammarTests.swift` cover: XPN/CX/XAD missing-component error paths (3); positive-path no-error case (1); empty-field-hits-required-field-not-component edge (1); CX multi-repetition independent checking (1); toggle suppression (1); `.lenient` preset suppression (1); `.strict` preset enforcement (1); untyped-composite skip (1); 48-fixture regression pin (1). 194 → 205 tests across 14 → 15 suites.

### Changed — API-BREAKING (typed composites, v0.2-C1)

- **Typed-segment accessors for XPN-, CX-, and XAD-typed fields now return Swift struct views** (`XPN?` / `CX?` / `XAD?`) instead of `Field?`. New structs live under `Sources/HL7v2Kit/Composite/` and expose named accessors for the most common components:
  - `XPN` — `familyName`, `givenName`, `middleName`, `suffix`, `prefix`, `nameTypeCode`
  - `CX` — `id`, `checkDigit`, `checkDigitScheme`, `assigningAuthorityNamespace`, `identifierTypeCode`, `assigningFacilityNamespace`
  - `XAD` — `streetAddress`, `otherDesignation`, `city`, `state`, `zip`, `country`, `addressType`
- **Affected accessors** (any field with `dataType ∈ {XPN, CX, XAD}`): `pid.patientName`, `pid.mothersMaidenName`, `pid.patientAlias` (XPN); `pid.patientIdentifierList`, `pid.alternatePatientID`, `pid.patientAccountNumber`, `pid.mothersIdentifier`, `pv1.visitNumber` (CX); `pid.patientAddress`, `nk1.address`, `orc.orderingFacilityAddress`, `orc.orderingProviderAddress` (XAD); `nk1.name` (XPN). Other composites (CE, CWE, EI, XCN, HD, MSG, PT, VID, XTN, PL, CNE, XON, EIP) still return `Field?` — they can be promoted incrementally without further breaking changes.
- **Migration path.** Each composite struct exposes a public `field: Field` for raw access — the v0.1.x `pid.patientName?.first?.components[0].stringValue` pattern still works as `pid.patientName?.field.first?.components[0].stringValue` (one extra hop). Or migrate to the named accessor: `pid.patientName?.familyName`. The cross-check invariant holds for both: `pid.patientName?.familyName == message["PID-5.1"]`.
- **Multi-repetition access.** Named accessors read from the FIRST repetition. For multi-rep fields (PID-3 patient identifier list, PID-5 name with maiden, ORC-22 facility address, …), walk `.field.repetitions` and wrap each in a new composite struct via the new `init(repetition:)` convenience.
- **Mechanism.** `Codegen.swift` recognises the composite data-type whitelist (`["XPN", "CX", "XAD"]`); when a field's `dataType` matches, the emitted accessor wraps the underlying `field(N)` call via `<Composite>.init(field:)`. Adding more composites to the whitelist is a one-line change; promoting another composite is purely additive.
- **Round-trip preserved.** Composite structs are value-type *views* over `Field`, not owners — the segment still holds the bytes. All 48 gold-corpus fixtures round-trip byte-identical; `CompositeTypeTests.compositeRoundTripsByteIdentical` pins this.
- 11 new tests in `Tests/HL7v2KitTests/CompositeTypeTests.swift` cover every named accessor on each composite + the `.field` migration path + multi-repetition access + cross-check against the path API + round-trip preservation. 13 existing tests across `TypedSegmentTests.swift`, `FixtureRoundTripTests.swift`, `ParseErrorTests.swift`, `ReadmeQuickstartTests.swift`, and `README.md` migrated to the new typed accessors. 183 → 194 tests across 13 → 14 suites.

### Changed (docs)

- **DocC catalogue brought up to date with the v0.2 work merged on `main`**:
  - `Migration.md` — "Anticipated changes in 0.2.0" rewritten into two sections: "Toward 0.2.0 — already on `main`" (P1/P2/P3 + F1 + V1, what consumers see if they pin to a commit instead of the `v0.1.0` tag) and "Still pending for 0.2.0" (C1 typed composites, V2 component grammar, X1 perf budget, runtime dictionaries).
  - `TypedSegments.md` — `PID` / `ORC` field counts updated from "30 of 39" / "19 of 31" to "all 39" / "all 31" with a note pointing at F1.
  - `Validation.md` — new "Conditional-field check" bullet under the active-checks list; new "Conditional-field DSL" section documenting the predicate grammar (`populated` / `empty` / `= <value>` / `!= <value>`), same-segment-only scope, and fail-safe semantics; presets updated to mention the new `checkConditionalFields` toggle (default `true`; `.lenient` disables); "What the validator does not check" trimmed (conditional fields removed; cross-segment predicates added as a known limit).
  - `AddingASegment.md` — schema-field list extended with the optional `condition` field (only meaningful for `optionality=C`); "Limits" updated — conditional `C` is no longer treated as `O`; typed-composite and component-level-grammar limits link to `Migration.md` for the v0.2 status.
  - `RoundTripGuarantee.md` — "Inputs the parser rejected" bullet expanded to call out NUL byte rejection (`ParseError.truncatedMessage(atByte:)`) and BOM strip (round-trip is canonicalisation, not byte-equality, for BOM-prefixed input). Both link back to `Migration.md`.
  - `GettingStarted.md` / `CharacterEncoding.md` / `EscapeSequences.md` / landing page — spot-checked, no edits needed.
- No source / test / API changes; tests still 183/183 in 13 suites.

## [0.1.0] — 2026-06-13

### Added

- **Code-generated typed segment structs** for HL7 v2.5.1: `MSH`, `PID` (first 12 of 40 fields), `NTE`, `AL1`.
  - `HL7v2KitCodegen` executable target reads per-segment JSON schemas from `Resources/schemas/<version>/` and emits Swift `TypedSegment` structs under `Sources/HL7v2Kit/Segment/Generated/`.
  - `SegmentRegistry.hydrate(_:)` switches segment IDs to typed factories; `Parser` calls it after structural parsing.
  - `scripts/regenerate-typed-segments.sh` regenerates the output tree.
  - Codegen output is reproducible (byte-identical across runs); CI codegen-drift job in `.github/workflows/ci.yml` catches schema edits that forget to regenerate.
- **MSH-18 character-set detection.** `Parser.parse(_ data:)` probes MSH-18 via an ISO-8859-1 1:1 decode, looks up the declared charset, and re-decodes the bytes. `Parser.parse(_ raw:)` does the same probe on the already-decoded string. Supports `UNICODE UTF-8` (default), `ASCII`, `8859/1` and the common aliases for each.
- **HL7 escape-sequence codec.** `\F\` `\S\` `\T\` `\R\` `\E\` `\X..\` decode/encode at the subcomponent leaf. `\Z..\` and unknown sequences pass through verbatim. `Subcomponent.value` stores decoded text; the serializer canonicalises on output. Hex runs coalesce (`\X0D0A\` not `\X0D\\X0A\`).
- `CharacterEncoding` public enum (Foundation edge) mapping MSH-18 wire strings to `String.Encoding`.
- `Message.characterEncoding: CharacterEncoding` property — populated by the parser, used by the serializer to emit bytes in the originating charset.
- `MessageBuilder` accepts an optional `characterEncoding` parameter (defaults to `.utf8`).
- 41 new tests: 17 `EscapeSequenceTests`, 11 `CharacterEncodingTests`, 13 `TypedSegmentTests` (path vs typed-accessor cross-check on MSH/PID/NTE/AL1, hydration check, byte-perfect round-trip through typed segments, Z-segment regression).

### Changed

- **Removed the explicit `swift-testing` SwiftPM dependency.** Swift Testing ships with the Swift 6 toolchain; the explicit dep was triggering a `@Suite` deprecation warning. The package now has zero external dependencies.
- `Parser` version-detection (MSH-12) reads via the unified `Segment.fields` accessor rather than pattern-matching `case .unknown(let msh)` — required once MSH starts hydrating as `.typed`. Encoding-agnostic and survives future typed-segment additions.
- `Parser` previously always emitted `.unknown(UnknownSegment)`; it now consults `SegmentRegistry.hydrate(_:)` to wrap recognised segment IDs as `.typed`. Z-segment tolerance is preserved (unknown IDs still fall through to `.unknown`).
- **MSH-18 probe-and-lookup logic factored into `CharacterEncoding.detect(in:)`** *(R3)*. `Parser.parse(_ data:)` and `Parser.parse(_ raw:)` now share the same one-line invocation; the private `probeMSH18` helper has moved off `Parser` since it's pure structural lookup.
- **`MessageBuilder.appendSegment(id:fields:)` contract clarified** *(R1)*: `fields` is treated as 1-indexed; the builder always prepends the index-0 placeholder. The dead-code condition (`fs.count == fields.count` was a tautology) has been removed. Behaviour is unchanged; the DocC now states the contract explicitly.
- **`Parser.parse(_ raw:)` DocC updated** *(R2)* to call out that MSH-18 is still consulted on the String-input path, with the same strict-on-unrecognised policy as `parse(_ data:)`.

### Added (R6 — ParserOptions audit)

- **`ParseError.unknownSegment(id: String, position: Int)`** — new error case. Spec § 4.6 had it declared but the implementation lacked the case. Position is 1-based (MSH is position 1).
- **`Parser(options: .strict).parse(...)`** now actually rejects unrecognised segments with `.unknownSegment`. Previously the `.strict` `allowUnknownSegments: false` option was silently equivalent to `.default` because the parser never consulted the flag. Now it checks after `SegmentRegistry.hydrate(_:)` returns and throws if the result is `.unknown`.
- **`ParserOptions.preserveExcessFields`** DocC updated to honestly mark it deferred to v0.2: v0.1.x has no per-segment field-count dictionary to check against, so excess fields are always preserved regardless of the flag. The flag stays on the API so consumers don't break when the dictionary-driven behaviour lands.
- 3 new tests in `ParsingTests.swift`: strict mode rejects ZAU with `.unknownSegment(id: "ZAU", position: 2)`; default options still allow ZAU (Z-segment tolerance regression); strict mode still accepts a registered PID.

### Added (Task 7c — parser error-path coverage)

- New `Tests/HL7v2KitTests/ParseErrorTests.swift` with **23 negative-path tests** covering: every `ParseError` case (including the previously-dead `.unsupportedVersion`, `.malformedField`, `.truncatedMessage` via the `everyCaseDescriptionRenders` reflection test), MSH structural edges (too-short MSH, missing field-separator after MSH-2, non-distinct encoding chars, segment-ID-only segments), byte-level edges (BOM prefix, embedded NUL, custom encoding characters), DoS-adjacent stress (8 KB single field, 1000-way repetition fan-out), mixed line terminators under `.lenient`, multiple MSH segments (batch-shaped input), and behaviour pins for current parser leniency (unknown MSH-12 falls back to v2.5.1, whitespace-only input throws `.missingMSH` not `.emptyInput`).
- Two findings flagged in test comments as v0.2 hardening candidates: (1) BOM prefix is silently stripped by Foundation on macOS (portability gap on Linux/Windows); (2) embedded NUL bytes are NOT preserved through round-trip — current behaviour is lossy. Both pinned by the test suite so they'll be caught if either silently changes.
- Coverage moves: `ParseError.swift` from **84.62% → 100.00% line** (every enum case description exercised); `Parser.swift` from **93.72% → 97.10% line / 84.72% → 91.67% region**. Overall `Sources/HL7v2Kit/` from **93.06% → 94.36% line / 86.60% → 88.60% region**.
- 136 → 159 tests across 12 suites.

### Added (Task 7a — anonymise tool + starter fixture corpus)

- **`HL7v2KitAnonymise` executable target** (`Sources/HL7v2KitAnonymise/Anonymise.swift`) implementing the spec § 10 scrubbing rules: PID-3 identifier replacement (format-preserved for digit-only IDs, otherwise `SYN-NNNN` prefix), XPN name lists, DOB shift by `±(salt mod 60 / 2)` days, AU synthetic addresses (8 real suburbs × 5 fake street names), AU-shaped phone numbers (`61-2-XXXX-XXXX`), MSH-3/4/5/6 facility names (8-entry pool), XCN provider lists (PV1 attending/referring/consulting/admitting + OBR collector/ordering/principal interpreter), OBX-5 narrative redaction (`TX` / `FT` / `ST` / `ED` value types → `[REDACTED]`), NTE-3 redaction. **Deterministic** — per-file salt derived from MSH-10 via djb2 hash; same input → byte-identical output. **One-shot** — re-anonymising an already-scrubbed file shifts the DOB again (documented in `Tests/Fixtures/FIXTURES.md`).
- **`scripts/anonymise-fixture.sh`** wrapper invoking the executable via `xcrun swift run`, matching the existing `regenerate-typed-segments.sh` pattern.
- **8 starter fixtures** under `Tests/Fixtures/`: `adt_a01_minimal.hl7`, `adt_a01_with_nk1.hl7`, `orm_o01_lab_order.hl7`, `oru_r01_chemistry.hl7`, `oru_r01_with_z_segment.hl7`, `edge_empty_fields.hl7`, `malformed_missing_msh.hl7`, `malformed_invalid_encoding_chars.hl7`. All hand-written synthetic with `\r` line terminators (real v2 wire format). Documented in `Tests/Fixtures/FIXTURES.md`.
- **`Tests/HL7v2KitTests/FixtureRoundTripTests.swift`** — auto-discovers `*.hl7` files in the bundled Fixtures resource and applies four invariants:
  - Every non-malformed fixture round-trips byte-perfectly (spec § 9.3).
  - Every non-malformed fixture validates without errors.
  - Every `malformed_` fixture throws a `ParseError`.
  - Path access and typed accessor cross-check on PID-1 / PID-3 / PID-5 / PID-7 / PID-8 (spec § 9.4).
- Adding fixture #9..#48 is now a pure drop-in operation — no test code change required.

### Added (Task 8c — release polish prep)

- New `Tests/HL7v2KitTests/ReadmeQuickstartTests.swift` — a `@Test` that mirrors the README's Quickstart code block and asserts each documented expected value. Drift in the README example (renamed methods, changed return types, stale `//` comments) breaks the test at PR time before any user encounters a stale example.
- README updated for accuracy: "Typed segments currently shipped" lists all 9 v2.5.1 segments with field-coverage counts (was stale at 4 segments / "PID 12 of 40"); "Adding a typed segment" workflow corrected from 4 steps to 3 (no manual `SegmentRegistry.swift` edit — the registry is itself codegen-emitted post-R5).
- Line-coverage benchmark on `Sources/HL7v2Kit/` (excluding `Generated/`, `HL7v2KitCodegen/`, `HL7v2KitDictionaries/`, and tests):
  - **Region:** 86.60% (433 of 500 covered)
  - **Function:** 92.81% (142 of 153 covered)
  - **Line:** 93.06% (1072 of 1152 covered)
  - Exceeds spec § 15's 80% line-coverage gate. Lowest-covered files: `Validation/SegmentGrammar.swift` 54.55% (value-type initialisers exercised at codegen-table compile time rather than via direct test), `Message.swift` 75.00% (some typed-segment iteration paths), `ParseError.swift` 84.62% (some error cases like `.truncatedMessage`, `.malformedField` not exercised by tests because no malformed-byte fixture triggers them yet — Task 7).

### Added (Task 8b — DocC catalogue)

- New `Sources/HL7v2Kit/HL7v2Kit.docc/` catalogue with the landing page and 8 articles per spec § 11.2:
  - `HL7v2Kit.md` — module landing page with Topics index linking to articles and public type catalogue.
  - `GettingStarted.md` — install → parse → read → serialise → validate in one short page.
  - `RoundTripGuarantee.md` — what byte equality covers and what it doesn't.
  - `TypedSegments.md` — typed-segment access pattern; `String?` vs `Field?` rule; multi-occurrence iteration; cross-check guarantee.
  - `Validation.md` — `Validator.validate` returns a `ValidationReport`; the three presets; filtering by severity / code / segment; current check coverage and v0.2 gaps.
  - `EscapeSequences.md` — the `\F\` / `\S\` / `\T\` / `\R\` / `\E\` / `\X..\` / `\Z..\` grammar; hex coalescing; round-trip canonical-form property.
  - `CharacterEncoding.md` — MSH-18 detection via ISO-8859-1 probe; supported charsets; Latin-1 round-trip example.
  - `AddingASegment.md` — three-step contributor workflow (schema, regen, cross-check test); CI drift safety net; v0.1.0 limits.
  - `Migration.md` — pre-1.0 SemVer policy; anticipated v0.2 changes (typed composite data types, conditional-field evaluation, component-level grammar, possible runtime-loadable dictionaries).

### Added (Task 8a — ADR catalogue)

- `docs/design/ADR-001-ast-model.md` — explicit Field/Repetition/Component/Subcomponent hierarchy + round-trip rationale.
- `docs/design/ADR-002-error-strategy.md` — `ParseError` (fatal, throws) vs `ValidationReport` (non-fatal, returned) split.
- `docs/design/ADR-003-z-segment-policy.md` — three-layer Z-segment control (parser default `UnknownSegment`, strict opt-in, validator policy `.ignore`/`.warnPresence`/`.reject`).
- `docs/design/ADR-004-codegen-over-macros.md` — rationale for explicit codegen executable + committed output over Swift Macros or build-time preprocessing.
- `docs/design/ADR-005-dictionaries-strategy.md` — original "Dictionaries as separate target" intent + the v0.1.0 revision to Path C (codegen-emitted Swift literal grammar table), with the spec § 8 direction held open for v0.2+.

### Added (Task 5 — Validator)

- **`Validator` per spec § 4.8.** Public surface: `Validator(options:)` + `validate(_ message:) -> ValidationReport`. **Non-fatal** (returns a report, never throws — ADR-002 invariant). Built on Path C — the validator reads a codegen-emitted `SegmentGrammarTable.v2_5_1` static table; no runtime JSON parsing, no separate `HL7v2KitDictionaries` runtime resource needed for v0.1.0.
- **`ValidationOptions`** with three presets: `.default` (grammar checks on, Z-segments silently tolerated), `.strict` (Z-segments rejected as errors), `.lenient` (only structural required-field check). Knobs: `zSegmentPolicy` (`.ignore` / `.warnPresence` / `.reject`), `checkRequiredFields`, `checkCardinality`, `warnDeprecatedFields`.
- **`ValidationReport`** (`issues`, `isValid` — false iff any `.error`-severity issue — plus `errors` / `warnings` / `infos` filters) and **`ValidationIssue`** (`severity`, `code`, `location`, `message`).
- **`IssueSeverity`** (`.info` / `.warning` / `.error`), **`IssueLocation`** (segment ID + 1-based segment occurrence + optional 1-based field index; renders as `"PID[1]-3"`), and **`IssueCode`** (`.requiredFieldMissing`, `.conditionalFieldMissing` (reserved), `.fieldNotSupported`, `.cardinalityExceeded`, `.zSegmentPresent`, `.unknownSegment`).
- **Public grammar types**: `SegmentGrammar`, `FieldGrammar`, `FieldOptionality` (R/O/C/X/B from HL7 wire codes), `FieldRepeatability` (.single/.multiple). `SegmentGrammarTable` is the codegen-emitted lookup `[String: SegmentGrammar]` keyed by segment ID.
- **Codegen extension**: `HL7v2KitCodegen` now also emits `Sources/HL7v2Kit/Segment/Generated/SegmentGrammar+v2_5_1.swift` containing the static `SegmentGrammarTable.v2_5_1` table. Per-version files allow future v2.3.1 / v2.4 / v2.8 tables to slot in without touching v2.5.1's output. Sorted by segment ID and field index for deterministic output.
- **Three operational checks**:
  - **Required-field check**: fields with optionality `R` that are unpopulated emit `.requiredFieldMissing` errors.
  - **Cardinality check**: single-cardinality fields (`repeatability=1`) carrying multiple `~`-separated repetitions emit `.cardinalityExceeded` errors.
  - **Deprecated-field warning**: populated `B` (deprecated) or `X` (not supported) fields emit `.fieldNotSupported` warnings (non-blocking).
- **Z-segment policy**: `.ignore` (no issue), `.warnPresence` (`.info` per segment, still valid), `.reject` (`.error` per segment, report invalid).
- 12 new tests in new `Tests/HL7v2KitTests/ValidationTests.swift`: well-formed-is-valid, missing-required-PID-3, checkRequiredFields toggle, all three Z-segment policies, cardinality on PID-7 single-field with two reps, multi-cardinality on PID-3 doesn't trigger, deprecated PID-2 warning, warnDeprecatedFields toggle, non-throw contract, IssueLocation path-description rendering. Suite total to 131.
- **Codegen accessor template uses `field(N)`** *(R4)* instead of the inline `fields.indices.contains(N) ? fields[N] : nil`. `TypedSegment` gains a `field(_ index: Int) -> Field?` default-impl that mirrors `Segment.field(_:)`'s bounds policy — single source of truth for "what does an out-of-range typed accessor return". Generated files visually halve in size.
- **`SegmentRegistry+Generated.swift` is now codegen-emitted** *(R5)*. The hand-written `SegmentRegistry.swift` shrank from a 4-case switch (and growing per Task 4c segment) to a 13-line entry point that calls `hydrateGenerated`. Adding a new segment is now a 2-step workflow: drop the JSON schema, run `regenerate-typed-segments.sh`. The codegen-drift CI job catches missed regenerations. ORC v2.5.1 lands as the canary segment proving end-to-end auto-registration.

### Added (R-β)

- `ORC` typed segment for HL7 v2.5.1 (one field — Order Control). Added as the R5 canary; extended to 19 fields in Task 4c-1.
- `TypedSegment.field(_:)` default-impl extension.

### Added (Task 4c-1)

- `OBX` typed segment for HL7 v2.5.1 (full 17 fields covering Set ID, Value Type, Observation Identifier, Observation Value, Units, References Range, Abnormal Flags, Probability, Nature of Abnormal Test, Observation Result Status, Effective Date of Reference Range, User Defined Access Checks, Date/Time of the Observation, Producer's ID, Responsible Observer, Observation Method).
- `ORC` typed segment extended from 1 to 19 fields (Order Control through Action By — covers the commonly-used Common Order fields including Placer/Filler Order Numbers, Order Status, Date/Time of Transaction, Ordering Provider).
- 14 new cross-check tests in `TypedSegmentTests.swift` (5 for extended ORC + 9 for OBX including round-trip), bringing the suite total to 84.

### Added (Task 4c-2)

- `OBR` typed segment for HL7 v2.5.1 (full 47 fields — the largest segment in the v0.1.0 set). Covers placer/filler order numbers (EI), universal service identifier (CE), specimen/observation timestamps, collector and ordering provider XCN composites, specimen action code, placer/filler text fields, result status, parent ordering, transport metadata, procedure codes, supplemental service information.
- 13 new cross-check tests in `TypedSegmentTests.swift`: 12 OBR-specific (hydration, SI/EI/CE/XCN/TS/ID coverage by field cluster, byte-perfect round-trip) plus 1 full-message integration test parsing an ORU^R01 result message with MSH + PID + OBR + OBX and asserting byte-perfect round-trip. Suite total to 97.

### Added (Task 4c-3)

- `PID` typed segment extended from 12 → 30 fields. New coverage: phone numbers (home/business XTN), primary language (CE), marital status (CE), religion (CE), patient account number (CX), SSN + driver's license (deprecated), mother's identifier (CX), ethnic group (CE), birth place (ST), multiple birth indicator (ID), birth order (NM), citizenship (CE), veterans military status (CE), nationality (CE, deprecated), patient death date/indicator (TS + ID).
- `NK1` typed segment for HL7 v2.5.1 (13 commonly-used fields). Covers Set ID, name (XPN), relationship (CE), address (XAD), home + business phone (XTN), contact role (CE), start/end dates (DT), job title (ST), job code/class (JCC), employee number (CX), organization name (XON).
- `PV1` typed segment for HL7 v2.5.1 (20 commonly-used fields). Covers Set ID, patient class (IS), assigned + temporary + prior patient locations (PL), admission type (IS), preadmit number (CX), attending/referring/consulting/admitting doctors (XCN), hospital service (IS), preadmit/readmit/admit indicators (IS), ambulatory status (IS), VIP indicator (IS), patient type (IS), visit number (CX), financial class (FC).
- 19 new cross-check tests in `TypedSegmentTests.swift`: 6 extended-PID (XTN home phone, CE language/marital/religion triplet, CX account, ST birth place, TS+ID death fields, byte-perfect round-trip), 5 NK1 (hydration, scalars, name+relationship composites, phone composites, round-trip), 7 PV1 (hydration, class+admit type scalars, PL location composite, XCN attending doctor, IS admin scalars, CX visit number, round-trip), and 1 ADT^A01 integration (MSH + PID + PV1 + NK1 in one message with byte-perfect round-trip). Suite total to 116.

### Added (initial scaffold — pre-Task-2)

- Initial scaffold: `Package.swift`, module structure, base types.
- `Version` enum for HL7 v2.3.1, 2.4, 2.5.1, 2.8.
- `EncodingCharacters` struct (default `|^~\&`).
- `Field` / `Repetition` / `Component` / `Subcomponent` AST nodes.
- `Segment` enum with `.typed` / `.unknown` cases and `UnknownSegment` fallback.
- `Message` top-level type with byte-level `serialize()`.
- `Path` parser supporting `SEG[N]-F[.C[.S]][~R]` syntax.
- `Parser` skeleton with single-message parsing and structural Z-segment tolerance.
- `MessageBuilder` for round-trip construction.
- Round-trip property test scaffolding.

### Added (Task 7b — fixture corpus scale-out)

- **Fixture corpus expanded 8 → 48** (spec § 9.2 target met for v0.1.0). All synthetic from scratch.
  - **ADT (12 total):** 3 × A01 (minimal, with NK1, allergies, insurance, emergency) + 3 × A04 (clinic, NK1, paediatric with PD1) + 3 × A08 (address update, demographics update, allergies-add).
  - **ORM (5 total):** lab order baseline + radiology X-ray, microbiology, haematology, cancel (ORC-1=CA), order with DG1 diagnosis.
  - **ORU pathology (6 total):** chemistry, haematology FBC, lipid panel, TFT, microbiology MCS, multi-OBR (EUC + LFT batteries under one PID).
  - **ORU radiology (4 total):** chest X-ray, CT abdomen/pelvis, pelvic ultrasound, MRI brain — each with TX narrative + ST impression.
  - **ACK (2 total):** application-accept (AA) and application-error (AE + ERR).
  - **Z-segment heavy (5 total):** original `oru_r01_with_z_segment` + ZAU/ZIN overlay in ADT, ZBL billing in ORM, ZLB/ZRE in ORU, ZTX heartbeat (MSH + Z only).
  - **Malformed (6 total):** missing MSH + non-distinct encoding chars + MSH too short + MSH no field-sep after MSH-2 + unsupported MSH-18 charset + empty file. Each triggers a distinct `ParseError` case.
  - **Edge (8 total):** original `edge_empty_fields` + Unicode diacritics, repeating PID-3 identifiers, very-long address, escape sequences in PID-5 and NTE, many trailing NTEs, sparsely-populated PID, OBX with `~`-repeating values.
- All valid fixtures: round-trip byte-perfectly, produce non-error `ValidationReport`, and pass the PID typed-accessor vs path-string cross-check. All malformed fixtures throw `ParseError`. `FixtureRoundTripTests` auto-discovers — no test code change required.

### Deferred to v0.2 (or later)

- **Full PID 30 → 39 and ORC 19 → 31.** Fringe coverage: PID-31..39 are species / breed / strain / tribal-citizenship; ORC-20..31 are confidentiality / charge metadata. v0.1.0 covers the commonly-populated fields per the 2026-06-13 decisions-log entry.
- **Typed composite data types** (`XPN` / `CX` / `XAD` as Swift structs with named accessors). v0.1.0 returns `Field?` for composites; callers reach into `.components[i].stringValue`. Spec § 4.5 last paragraph.
- **Conditional-field evaluation.** v0.1.0 treats `optionality=C` as equivalent to `O` for the required-field check. Per `ValidationIssue.IssueCode.conditionalFieldMissing` (reserved).
- **Component-level grammar in `Validator`.** v0.1.0 only checks field-level rules; e.g. XPN's family-name component being non-empty when XPN-1 is populated is not checked.
- **Performance budget tests** (spec § 9.5). Nightly latency assertions not in the v0.1.0 acceptance gate.
- **Three parser-hardening candidates** from Task 7c (all pinned by `ParseErrorTests.swift`, none blocks v0.1.0):
  - BOM prefix portability — silently stripped by Foundation on macOS but Linux Swift may differ.
  - Embedded NUL bytes — currently lossy through round-trip; consider `.truncatedMessage(atByte:)` at parse time.
  - `ParseError.unsupportedVersion` is reachable code but never thrown — unknown MSH-12 silently falls back to v2.5.1. Wire on `.strict` mode.
- **`HL7v2KitDictionaries` runtime JSON.** Path C (ADR-005 revised) supersedes the original spec § 8 plan for v0.1.0; placeholder.json stays. Revisit in v0.2 if dynamic version selection becomes a real consumer need.

[Unreleased]: https://github.com/<your-org>/HL7v2Kit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/<your-org>/HL7v2Kit/releases/tag/v0.1.0
