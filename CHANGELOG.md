# Changelog

All notable changes to HL7v2Kit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

> **State (2026-08-21):** v1.7, v1.8 and v1.9 are all **merged to `main` and untagged** —
> they fold into the next release. Typed-segment coverage is **109**, and
> `scripts/audit-schemas.py --depth` reports **integrity 0 findings across 584 schemas;
> depth 578 exact, 0 gaps, 0 suspects**. Tests **519** green, no codegen drift. `main` and
> the `v1.4.0` tag have **not been pushed** to `private`.

### R1 — Foundation-import purge + codegen template trims (remediation stage 1 of 10)

First executed stage of `docs/design/remediation-plan.md` (F1, F34, F35, F36; F26
dropped). ~270 net lines removed, behaviour byte-identical, zero API change.

- **F1:** the emitted `import Foundation` removed from all three codegen templates — none of
  the 116 generated files uses a Foundation symbol — and from the 18 hand-written
  `Composite/` files + `SegmentRegistry.swift` (19 files × 2 lines).
- **F36:** generated structs now declare `: TypedSegment` only; the protocol already refines
  `Sendable, Equatable, Hashable` (`Segment.swift:14`) and synthesis still fires — 109 decl
  lines shortened.
- **F34:** `renderGrammarTable` calls `versionDirName(_:)` instead of inlining its body.
  **F35:** dead `"GTS"` entry removed from `scalarDataTypes` (0 of 584 schemas use it).
  Both proven output-neutral: step-a regeneration was **byte-identical**.
- **F26 dropped per the plan's never-force rule:** `String(reflecting:)` escapes apostrophes
  (`Mother's` → `Mother\'s`), churning every possessive grammar-table name; the hand-rolled
  escaper stays, now with a comment recording why.
- Stage verification: step-b regenerate diff contained **only** the two intended line classes
  (116 import+blank removals; 109 decl rewrites); `swift test list` name-diff **empty**;
  suite **519/519 green**; build **warning-free** — the fresh full-module recompile surfaced
  one pre-existing `ExistentialAny` warning in `StreamingBatchParser.swift:142` (untouched
  since v0.3-S1), fixed in its own commit as `any Error`.

### R2 — dead `segmentCardinalityRules` schema axis removed (remediation stage 2 of 10)

F9 of `docs/design/remediation-plan.md`: the generator carried a full decode/render
axis for schema-side group-cardinality rules that **0 of 584** schema JSONs ever set
(ADR-010 Ext 2 authored the axis speculatively; an encoding axis with zero encoded rules is
plumbing, not spec surface — reinstate from git when a first universal rule is authored).

- Deleted `CardinalityRuleSchema`, the `SegmentSchema.segmentCardinalityRules` field, and the
  non-empty-rules branch of `renderGrammarTable` — 35 lines, all in `Codegen.swift`.
- The **runtime** `SegmentCardinalityRule` type and `Profile.cardinalityExtensions` are
  untouched — the AU profile's locale-scoped cardinality rules still ship through them.
- Verification: regenerated output **byte-identical** (`Generated/` diff empty); test-name
  diff **empty**; suite **519/519 green**; build warning-free.

### R3 — `CompositeView` protocol extraction + `AnyTypedSegment` cleanup (remediation stage 3 of 10)

F2 + F30 of `docs/design/remediation-plan.md`; net −217 lines, behaviour unchanged
under the CompositeTypeTests / ComponentGrammarTests / TypedSegmentTests pins.

- **F2:** the mechanics duplicated verbatim across all 16 composite structs — `componentValue(_:)`
  (md5-identical ×16), the `init(repetition:)` body, and the `Sendable, Equatable, Hashable`
  conformance list — hoisted into a new public `CompositeView` protocol + extension
  (`Composite/CompositeView.swift`). Each composite keeps its per-spec accessors, docs, `field`,
  `init(field:)`, and non-empty metadata. The 5 empty `requiredComponents = []` decls (CWE, EIP,
  HD, PL, XTN) now come from the protocol default; their stale docs went with them (HD's still
  described the `RequiredComponentSet` refactor as "explicitly avoided" — it shipped in v0.4-S4).
  `init(repetition:)` and the metadata statics remain publicly callable via the extension —
  additive under ADR-014.
- **F30:** `AnyTypedSegment.underlyingTypeName` deleted — private, stored, never read; `==` is
  unchanged because segmentID→type is a bijection via the generated registry.
- **F13 re-binned to R10:** tightening `RequiredComponentSet.init`'s `description: String? = nil`
  to a required `String` is a public signature change, prohibited in 1.x by ADR-014 — it now
  rides the v2.0.0 boundary with the other breaking removals.
- Verification: test-name diff **empty**; suite **519/519 green**; build warning-free.

### R4 — validator/locale shrinks, characterization-first (remediation stage 4 of 10)

F11 + F12 + F14 + F15 + F19 + F24; the first stage with red-first work. Two characterization
tests written and green against pre-refactor code BEFORE anything moved, both green after:

- **C1** (CrossSegmentDSLTests): the condition-DSL referent grammar rejects repetition
  (`PID-3~2`) and segment-index (`PID[N]-3`) forms fail-safe — on a wire whose plain `PID-3`
  IS populated, so a mis-resolving parser goes red.
- **C2** (LocaleAUProfileTests): one parameterized row per `.profileConstraintViolation` append
  site (7) pinning the EXACT message text, with the in-message citation cross-checked against
  the issue's own `localeRule` payload.

The refactors:

- **F11:** all 7 profile-issue constructions fold into `appendProfileIssue(citation:location:message:into:)`.
  Line-neutral (messages stay at call sites) — the win is drift-proofed severity/code/location
  plumbing, proven byte-identical by C2.
- **F14:** the Validator's second field-ref parser (`ParsedIndexSuffix`/`parseIndexSuffix`) is
  gone; both referent call sites parse via the shared `Path` parser through `parseDSLFieldRef`,
  which guards `segmentIndex == nil && repetition == nil`. Undocumented junk referents that
  accidentally resolved (`PID-+3`, 1-char IDs before the dash) now uniformly evaluate fail-safe
  false, aligning behaviour with the documented `SEG-f[.c[.s]]` grammar.
- **F12:** `ProfileLoader.swift` deleted; loading is `Profile.load(for:)` beside the type.
- **F15:** four hand-rolled nested-for population/needs-encoding scans → `contains(where:)`
  (`isRepetitionPopulated`, `isComponentPopulated`, `isFieldPopulated` now delegates,
  `EscapeSequences.needsEncoding`).
- **F19:** dead internal `Profile` members deleted: `isEmpty`, `none`, `baseVersion` (+ its
  init param and the AU factory argument).
- **F24:** the ORC group-boundary walk lives once as `Message.orcGroupRange(around:)`, shared
  by `associatedSegment` and the Validator's `.orcObxGroup` resolution — the two group
  definitions can no longer drift.
- Verification: suite **522 green** (519 + the 3 characterization test names — the exact
  enumerated addition, zero removals); build warning-free. Source net −54 lines, +81 test lines.

### M5 sweep — CH06 financial completion (v1.9)

Adds **FT1/PR1/ACC/UB1/UB2/DRG** (all six versions) and **ABS/GP1/GP2** (v2.4+) — 48 schema
instances, all passing the golden `--verify` gate. Typed count **100 → 109**. Closes out CH06
alongside GT1/IN1/IN2/IN3 from v1.2.

Where v1.8's batch had uniform depths across all versions, this one is the opposite: the
depths themselves carry the version signal, and they move a lot. `FT1` 25 → 26 (v2.3.1
errata) → 31 → **43** (v2.8.2); `PR1` 15 → 16 → 18 → 20 → 22 → **25**; `ACC` 6 → **13**; and
`DRG` nearly triples in v2.6, 11 → **33**. `UB1`/`UB2` are the counterexample — static at
23/17 on every version. `ABS`/`GP1`/`GP2` arrived in v2.4 and are absent from the two legacy
dialects.

**Two more conditional predicates ship rather than being documented.** `PR1-19` Procedure
Identifier and `PR1-20` Procedure Action Code both cite the Update Diagnosis/Procedures
trigger event — "required in all implementations employing … (P12) messages" and "required
for the … (P12) message. In all other events it is optional" — so both carry
`triggerEvent = P12` on v2.5.1 / v2.6 / v2.8.2 (they do not exist before v2.5; PR1 caps at
18 in v2.4). The permanent-limitation register is unchanged by this batch, and the guard test
needed no edit.

Note `BLG` is **not** part of this batch despite being a financial segment — it is defined in
CH04, not CH06, so it belongs to a later orders pass.

Audit after this batch: **integrity 0 findings across 584 schemas; depth 578 exact, 0 gaps,
0 suspects**. Tests: 518 → **519**.

### M5 sweep — CH07 completion: product experience + clinical trials (v1.8)

Adds **PES/PEO/PCR/PDC/PSH** (product experience) and **CSR/CSP/CSS/CTI** (clinical trials),
closing out CH07 alongside OBR/OBX/SPM. All nine exist on **every** supported version at
identical depth — 54 schema instances, all passing the golden `--verify` gate. Typed count
**91 → 100**.

Because the depths are uniform, every divergence here is in datatypes and element names —
precisely what a depth-only check misses: `TS → DTM` and `CE → CWE` in v2.6; `CTI-1` shortens
`Sponsor Study Identifier` → `Sponsor Study ID` after v2.3; `PEO-14` gains "Description" in
v2.6; and v2.3's `PDC-14/15` genuinely read `Date First/Last Marked`, corrected to `Marketed`
in v2.4 — a spec typo rendered faithfully (both the attribute table and the definition
heading agree).

### Added — six conditional predicates now ship instead of being documented

The clinical-trials family states its conditions explicitly, so these left the
permanent-limitation register rather than joining it (req #3/#4):

| Field | Predicate | Spec basis |
|---|---|---|
| CSR-9, CSR-10 | `triggerEvent = C01` | "required for the patient registration trigger event (C01)" |
| CSR-14, CSR-15, CSR-16 | `triggerEvent = C04` | "required for the off-study trigger event (C04)" |
| CTI-2 | `CTI-3 populated` | stated in **CTI-3's** definition, not CTI-2's |

Applied on all six versions (36 entries), each verified against that version's own
field-definition prose. Two lessons recorded: a field's condition is not always written in
its own entry, and version prose must be located by **stable ITEM number** — the v2.3-era
heading format omits the `SEG-N` prefix, so heading-shaped regexes silently miss it.
**CSP-4** is the batch's only remaining bare `C` (§7.8.2.4 states no trigger).

### Added — `scripts/audit-schemas.py`

The integrity + depth audit is now a committed contributor tool rather than an ad-hoc
script, since the working rules require running it after every batch. Shape-based predicates
(emptiness, length, character class, index continuity) plus the two-directional depth diff,
with RDT whitelisted and `docs/standards/` resolved from the primary worktree when run from a
cycle worktree. Dev-time only; `Package.swift.dependencies` stays empty.

Audit after this batch: **integrity 0 findings across 536 schemas; depth 530 exact, 0 gaps,
0 suspects** — the first fully clean sweep. Tests: 516 → **518**.

### M5 sweep — CH13 lab-automation completion (v1.7)

Sixth chapter closed out. Adds **ISD/NDS/CNS/ECD/ECR/SID** (CH13 clinical laboratory
automation) — full depth on every version they appear in. CH13 was introduced in **v2.4**, so
these six exist on v2.4 / v2.5.1 / v2.6 / v2.8.2 only; v2.3 and v2.3.1 have no CH13. Typed
count **85 → 91**; 24 new schema instances, all 24 passing the golden `--verify` gate.

Per-version divergence is captured rather than flattened: `CE → CWE` and `TS → DTM` in v2.6;
`ECR-3`/`ECD-5` widen `ST → TX` in v2.5.1; **ECD-4** Requested Completion Time goes
`O` (v2.4) → `B` (v2.5.1/v2.6) → **withdrawn with no datatype** (v2.8.2); and v2.6 renamed
`ISD-1` (dropping "(unique identifier)") and `SID-1` (closing up "Application / Method").

**The whole SID segment is conditional.** §13.4.11 marks all four fields `C` and states no
condition at all, so no DSL predicate is expressible — documented in
`conditional-completeness-audit.md` as the purest instance of that class (~132 positions).
The other five segments carry no `C` fields.

### Fixed — five more prose-bleed element names (v1.7)

A **name-length** audit predicate (`> 120` chars) found five instances of the v1.5-S2
prose-bleed class that the earlier *marker-word* regex had missed: `TQ2-10` (v2.5.1 / v2.6 /
v2.8.2 — up to 1069 characters of absorbed prose), `BPX-21` and `BTX-20` (v2.8.2). All three
segments were authored in v1.2 / v1.3, before the extractor's table-end and continuation
fixes, and had never been re-extracted. Corrected to `Special Service Request Relationship`,
`BP Dispensing Individual` and `BP Unique ID`, each confirmed against the CH04 tables.

Lesson recorded in `segment-coverage-extraction.md`: prefer a *shape* predicate (length,
character class) over an *enumerated content* predicate when auditing for corruption —
marker lists only find the corruption you already thought of.

Depth audit re-run across all six versions: **476 of 482** schemas match exactly, 0 suspects,
0 unlocated (the 6 remaining gaps are the known RDT `1-n` whitelist). Tests: 515 → **516**.

## [1.4.0] — 2026-08-20

M5 sweep — typed-segment coverage **57 → 85**, plus two correctness cycles that moved the
authored surface from *assumed* complete to *verified* against the spec. **452 of 458
committed schemas now match their own version's attribute table exactly** (the 6 exceptions
are RDT, a known `1-n` variable-column extractor limitation whose hand-authored schema is
correct). Additive throughout (ADR-014) — the frozen v1.0 API only grows. Tests: 513 → **515**.

Two shipped accessors keep names that now differ from their corrected element names —
`effectiveDateOfReferenceRange` (OBX-12) and `producersID` (OBX-15). Frozen public API;
rename at 2.0.

### Per-version field-depth audit (v1.6)

Correctness-only, additive. Every committed schema's depth was diffed against **its own
version's** attribute table — all tables in all chapters of all six versions extracted, then
compared by max field index in both directions.

**436 of 458 schemas matched on the first pass. 46 fields across 14 (version, segment) pairs
had never been authored**, all on core segments:

| Version | Segment | Was | Now |
|---|---|---|---|
| v2.3 | MSH / OBX / ORC | 15 / 11 / 17 | **19 / 17 / 19** |
| v2.3.1 | MSH / NTE / OBR / OBX / ORC | 17 / 3 / 43 / 14 / 17 | **20 / 4 / 45 / 17 / 24** |
| v2.4 | MSH / NTE / OBX / ORC / PID | 20 / 3 / 16 / 19 / 32 | **21 / 4 / 19 / 25 / 38** |
| v2.5.1 | OBX | 24 | **25** |

v2.5.1 OBX-25 (`Performing Organization Medical Director`) adds a typed accessor; the rest
deepen per-version grammar tables. All additive (ADR-014). After the fills: **452/458 exact,
0 suspects, 0 unlocated.** New pin test guards the fills and the naming rules below.

**Per-version element names must never be copied from the canonical schema.** HL7 renames
fields between versions, so the canonical name is often not that version's name:

| Field | v2.3 / v2.3.1 | v2.4 | v2.5.1 | v2.6 / v2.8.2 |
|---|---|---|---|---|
| OBX-12 | Date Last Obs Normal Values | Date Last Observation Normal Value | Effective Date of Reference Range **Values** | Effective Date of Reference Range |
| OBX-15 | Producer's ID | Producer's ID | Producer's **Reference** | Producer's ID |
| MSH-21 | — | **Conformance Statement ID** (`ID`) | Message Profile Identifier (`EI`) | Message Profile Identifier (`EI`) |

MSH-21 was renamed *and* retyped in v2.5 without changing the field count — a depth-only
audit could never have caught it.

**Fixed: two pre-existing name defects in the canonical v2.5.1 OBX schema** — OBX-12 was
truncated (missing `Values`) and OBX-15 carried the neighbouring versions' `Producer's ID`.
Their `swiftName`s are deliberately unchanged: `effectiveDateOfReferenceRange` and
`producersID` are shipped public API, frozen until 2.0 (ADR-014). The accessors keep their
names while their DocC text and grammar entries now read the spec's wording.

**Extractor:** caption matching widened to accept the singular (`Figure 2-10. ERR
attribute`), which had silently excluded v2.3 / v2.3.1 ERR from audit coverage. Documented
limitation: a `1-n` variable-column SEQ row (RDT-1, ADD-1) cannot be parsed, so RDT shows as
a permanent 6-row gap and must be whitelisted — its hand-authored schema is correct.

Tests: 514 → **515** green.

### Element-name fidelity (v1.5-S2)

Correctness-only. Fixes the element-name prose-bleed class — three distinct root causes in
the extractor, plus 14 surgical name corrections, each verified against the version's own
attribute table.

**Extractor:**

- **Table-end detection now accepts a lettered chapter number.** v2.8.2 splits the pharmacy
  chapter into 4 and **4A** and numbers sections `4A.4.3.0 RXC field definitions`; the
  digits-and-dots-only test missed those, so the table never ended and the entire
  field-definitions section was folded into the last row's element name.
- **Continuation folding is bounded** — a fragment is accepted as a wrapped name only if it
  is short, free of sentence punctuation and component-example markers, and keeps the name
  under 120 chars. Previously the explanatory note between a CH12 table and its definitions
  contaminated the last row.
- **Names are no longer truncated at the front.** Element names are *centred* under the
  `ELEMENT NAME` label, so long ones start left of the label offset and a fixed-offset slice
  cut their heads off (`Administered Tag Identifier` → `ministered Tag Identifier`). The
  boundary is now anchored on the rightmost 4–5 digit metadata run (ITEM #, or TBL # when
  the item number is blank), and the same boundary bounds metadata binning.
- **Empty-name rows are rejected when `DT` is under 2 characters**, not merely empty — every
  real HL7 datatype token is 2+ chars, so a 1-char DT is a wrapped-cell tail. v2.5.1
  `OBX-5`'s `varies` wraps as `varie` + `s`, and the orphan `s` was parsed as an extra row.

**Names corrected (14):** v2.8.2 `RXA-29` `Administered Tag Identifier`, `RXC-11` /
`RXG-33` `Dispense Units`, `RXD-35` `Dispense Tag Identifier`, `RXE-45` / `RXO-36`
`Pharmacy Phone Number`, `RXR-6` `Administration Site Modifier`; `PRB-25`
`Security/Sensitivity` (v2.3 / v2.3.1 / v2.4 / v2.5.1); `PRB-28` and v2.8.2 `GOL-22`
`Mood Code` (v2.6 / v2.8.2).

**Left alone as faithful (10):** the attribute tables literally print `Set ID- TXA` (v2.3 /
v2.3.1 / v2.4 / v2.6 / v2.8.2) and `Sequence Number- Test/Observation Master File` (v2.4
OM2–OM6) with no space after the hyphen, while the field-definition headings on the same
pages print them with spaces. The schemas follow the attribute table; rendering a spec typo
faithfully is correct (req #2).

Blast radius of the corrections is the grammar tables (`FieldGrammar.name` → validator
message text) and the reference surface, not Swift identifiers — typed structs generate from
the canonical v2.5.1 schemas only. Golden `--verify` sweep: 18/20 canonical segments pass
clean (OBR-32 is the documented intentional conditional upgrade; OBX surfaced the depth gap
noted above). Tests: **514** green.

### Extractor hardening + schema datatype fidelity (v1.5-S1)

Correctness-only. Fixes all three extractor items found during the v1.4 sweep and every
datatype defect the follow-up audit confirmed, each verified against the spec PDF rather
than against the extractor's own output.

**Extractor** (`scripts/extract-segment-tables.swift`, dev-time tool — not shipped):
column assignment now keys on nearest label **start** rather than run **centre** (fixes
values sitting right of the `DT` label, e.g. CH12 GOL, and a hair left, e.g. CH04 BPO);
rows with `seq < 1`, or with both an empty name and an empty `DT`, are rejected;
`deriveSwiftName` drops lone `s` fragments from possessives.

**Schema corrections:**

- **Phantom rows removed** — root-caused to **wrapped `LEN` digits** landing left of the
  `DT` column (OM6's `10240` leaves a bare `0`; EQP's `65536` leaves a bare `6`), not
  generic junk lines. Corrected depths: **OM1 49 → 47**, **OM4 17 → 14**, **OM6 3 → 2**,
  **EQP 6 → 5**. Depth pins updated.
- **GOL** — v2.5.1 fields 1/4/5 gain `ID`/`EI`/`EI`; **v2.3.1 fields 1–20** filled (were
  all empty; matches v2.3 / v2.4 per Figure 12-2).
- **RDT — corrected in all six versions.** v2.3 / v2.3.1 held the **SPR** segment's four
  fields; v2.4 / v2.5.1 / v2.6 / v2.8.2 held corrupted prose. Root cause: in v2.3 / v2.3.1
  RDT is defined in **Chapter 2 §2.24.19**, not CH05. Correct in every version: one field,
  `Column Value`, `OPT R`, ITEM 00703 — DT literal per-version (`Variable` for v2.3 / v2.3.1 /
  v2.4, `varies` for v2.5.1 / v2.6 / v2.8.2, tracked per-version as `TS`→`DTM` already is).
  `RP` stays `1`: the spec's `RP/#` cell is blank, so `*` would assert `~`-repeatability the
  spec does not grant. RDT's `1-n` unbounded-column semantic is recorded as a model
  limitation (req #3). RDT's typed accessor changes shape, which is ADR-014-clean only
  because v1.4 has not been released.

**Two audit rules recorded** in `segment-coverage-extraction.md`: an empty `dataType` is a
defect only when `OPT ∉ {W, X}` (`W`/`X` fields have no datatype by design — this made most
of the originally-flagged empty-DT set false positives); and wholesale/whitelist
regeneration is unsafe (it drops hand-authored `condition` predicates, reproduces
mis-binned datatypes, and title-cases element names), so datatype fixes must be surgical.

Tests: **514** green. The RDT pin now asserts field identity, not just count — the previous
count-only pin passed against an extractor-garbage field.

### M5 sweep — 14 new segments (master-file locations + patient-care + med-records)

Sixth sweep batch. Adds **LOC/LCH/LRL/LDP/LCC/CDM/PRC/IIM** (CH08 master files), **GOL/PRB/PTH/VAR** (CH12 patient care), **TXA/CON** (CH09 med records) — full-depth on every version they appear in. Typed count **71 → 85**. IIM moved CH08→CH17 across versions (sourced accordingly); CON is v2.6+. 13 conditional fields documented + guarded (~128 total). Tests: 514.

### M5 sweep — 14 new segments (query + lab-automation)

Fifth sweep batch. Adds **QPD/QRD/QRF/QAK/QID/RCP/RDF/RDT** (CH05 query) and
**EQU/SAC/INV/TCC/TCD/EQP** (CH13 lab automation) — each full-depth on every version it
appears in. Typed-segment count **57 → 71**. v2.3 query segments sourced from CH2 (v2.3
CH5 is an empty placeholder); QPD/QID/RCP are v2.4+; lab-automation is v2.5+. 6 new
conditional fields documented + guarded. Additive (ADR-014). Tests: 514.

## [1.3.0] — 2026-07-13

M5 sweep — typed-segment coverage **29 → 57** (two batches). Additive / correctness only;
the frozen v1.0 API grows but never breaks (ADR-014). Tests: 510 → **513**.

### M5 sweep — 14 new segments (master-files + referral)

Fourth sweep batch. Adds **MFI/MFE/MFA + OM1–OM7** (CH08 master files) and
**RF1/AUT/PRD/CTD** (CH11 referral) — each full-depth on every version it appears in.
Typed-segment count **43 → 57**. OM7 is v2.4+; v2.8.2 notably expands OM1 (47→59), RF1
(12→25), AUT (10→29). Extractor-seeded + golden-`--verify`ed; additive (ADR-014). 5 new
conditional fields (MFE-2/MFA-2/OM7-16/OM7-18/AUT-6) documented + guarded. Tests: 513.

### M5 sweep — 14 new segments (scheduling / blood-product / specimen / role)

Third sweep cycle. Adds **SPM** (CH07), **ROL** (CH15), the CH10 scheduling family
(**SCH/RGS/AIS/AIG/AIL/AIP/APR/ARQ**), and blood-product **BPO/BPX/BTX** + **RXA** (CH04).
Typed-segment count **29 → 43**, each full-depth on every version it appears in.
Extractor-seeded + golden-`--verify`ed; additive API growth only (ADR-014). Tests: 512.

- **RXA** resolves to the base "Pharmacy/Treatment Administration" table (26 fields), not
  the "Segment Uses in Vaccine Messages" profile table that follows it — pinned by test.
- **Extractor reliability fix:** `detectHeader` now accepts the legacy `R/O/C`
  optionality-column header. v2.3 CH10 uses it, so the whole scheduling chapter had been
  silently skipped; all v2.3 scheduling grammar is now present. Golden v2.5.1 unaffected.
- **Conditional-completeness:** 55 new conditional-without-trigger fields
  (scheduling/blood-product/specimen/role) bulk-documented + added to the v2.8.2 guard set
  (fail-safe; ~104 documented total).

## [1.2.0] — 2026-07-13

M5 sweep — typed-segment coverage **15 → 29**, all at full per-version depth. Additive /
correctness only; the frozen v1.0 API grows but never breaks (ADR-014). Tests: 504 → **510**.

### M5 sweep — 8 new order/pharmacy/timing segments + extractor reliability fix

Third cycle of the M5 sweep. Adds **TQ1, TQ2, RXO, RXR, RXC, RXE, RXD, RXG** (CH04/CH04A)
as typed segments — the typed-segment count goes **21 → 29** — each full-depth on every
version it appears in. Tests: 507 → **510**.

- **Canonical v2.5.1 depths:** TQ1 14, TQ2 10, RXO 28, RXR 6, RXC 9, RXE 44, RXD 33, RXG 26.
  Per-version depths grow monotonically (RXE 30→45, RXO 22→36); TQ1/TQ2 are v2.5+.
- **Extractor reliability fix:** SEQ detection now uses the first token before the DT
  column, not a fixed header-offset slice — recovering legacy v2.3 CH4 tables (RXO/RXC/RXG)
  that the old slice silently dropped, and correcting v2.3 RXR 6→4. Golden `--verify`
  unaffected. A general fix for all legacy-chapter sweeps.
- **Conditional-completeness:** these are HL7's most conditional-heavy segments — 31 new
  C-without-expressible-trigger fields, bulk-documented in the register + the v2.8.2 guard
  set (fail-safe, never shipped as rules; req #4).

### M5 sweep — 6 new typed segments (PV2, MRG, DB1, GT1, IN2, IN3)

Second cycle of the M5 sweep. Adds **PV2, MRG, DB1** (CH03) and **GT1, IN2, IN3** (CH06)
as first-class typed segments — the typed-segment count goes **15 → 21**. Each is modelled
at full field depth on every version it appears in (36 schemas: canonical v2.5.1 + 30
per-version), extractor-seeded and golden-`--verify`ed. Auto-registered via the generated
`SegmentRegistry`; additive API growth only (ADR-014). Tests: 505 → **507**.

- **Canonical v2.5.1 depths:** PV2 49, MRG 7, DB1 8, GT1 57, IN2 72, IN3 25. Per-version
  depths vary (e.g. PV2 37→50, GT1 55→57, IN3 25→27).
- **Codegen:** now backtick-escapes Swift-keyword swiftNames (IN3-8 "Operator" →
  `` `operator` ``) — general safety; grammar-table names stay faithful.
- **Conditional-completeness:** PV2-1/45/47 are conditional-without-expressible-trigger —
  added to the register + the v2.8.2 guard-test set (documented, fail-safe).
- **Tooling:** the extractor gains a reusable `--emit-schema` seed generator.

### M5 sweep — per-version NK1/PV1/IN1 full depth

First segment-coverage cycle of the M5 sweep. Extends **NK1 / PV1 / IN1** from the
curated caps (13 / 20 / 25) to **full per-version field depth** on every non-canonical
version — closing the immediate coverage gap. Extractor-seeded (ADR-015 `--emit-schema`)
and verified: all 15 schemas pass the golden `--verify` (DT/OPT/RP + counts). Additive,
grammar-table-only — typed structs generate from canonical v2.5.1 (unchanged); the frozen
v1.0 API is untouched (ADR-014). Tests: 504 → **505**.

- **Full per-version depths** (field counts grow across the standard):
  - v2.3 / v2.3.1 / v2.4 — NK1 **37**, PV1 **52**, IN1 **49**
  - v2.6 — NK1 **39**, PV1 **52**, IN1 **53**
  - v2.8.2 — NK1 **41**, PV1 **54**, IN1 **55**
- **Version divergences captured verbatim:** v2.3-era coded fields stay `IS` (pre CE→CWE);
  v2.6 CE→CWE + TS→DTM wave; v2.8.2 full CWE promotion, new NK1-40/41 telecommunication-info
  fields, and `B`-demotion of the legacy phone fields.
- **Tooling:** the extractor gains a reusable `--emit-schema` mode (swiftNames mapped from a
  reference schema) + element-name glyph normalization; `MultiVersionTests` depth pins
  updated + a new v1.2 divergence pin.

## [1.1.0] — 2026-07-12

### M5 foundation — extraction pipeline, canonical corrections, segment inventory (ADR-015)

The opening of ROADMAP **M5** (full HL7 segment coverage across all versions — the gate on
the first public push). **Additive / correctness only; the frozen v1.0 public API grows but
never breaks** (ADR-014). Tests: 501 → **504** across 26 suites.

**Added — the extraction pipeline (ADR-015).** `scripts/extract-segment-tables.swift` parses
segment attribute tables from the Final-Standard PDFs via `pdftotext -layout`, recovering every
column (`SEQ/LEN/DT/OPT/RP/#/TBL#/ITEM#/NAME`) cleanly across **all six versions** (v2.3→v2.8.2).
This retires the "legacy `RP/#` columns don't extract cleanly" blocker that v0.19 documented and
that M5 was gated on. Dev-time tool only — **`Package.swift` has no new dependency**. See
`docs/design/segment-coverage-extraction.md` (+ its `--verify` golden gate).

**Fixed — 11 canonical v2.5.1 metadata defects** surfaced by the pipeline's golden audit
(concentrated in the `OPT`/`RP/#` columns the prior PDFKit hand-authoring mis-read):

- Optionality: **PV1-9 / PV1-40 / PV1-52** and **IN1-38 / IN1-40 / IN1-41** were `O`, spec is `B`
  (backward-compatibility); **MSA-5** was `X`/`ST`, spec is `W` (withdrawn).
- Repeatability: **NK1-26**, **PID-38**, **PV1-45** are repeatable (`RP/# = Y`/max) — were single;
  **PV1-50** is single — was over-marked repeatable.

**Added — completed two incomplete canonical segments** (real v2.5.1 fields never authored;
additive typed accessors):

- **OBR** 47 → **50** — 48 Medically Necessary Duplicate Procedure Reason (CWE, C), 49 Result
  Handling (IS, O), 50 Parent Universal Service Identifier (CWE, O).
- **OBX** 17 → **24** — 18 Equipment Instance Identifier (EI), 19 Date/Time of the Analysis (TS),
  20/21/22 Reserved for harmonization with V2.6 (X), 23 Performing Organization Name (XON),
  24 Performing Organization Address (XAD).

**Added — segment inventory** (`docs/design/segment-inventory.md`): the M5 work-list — 188
distinct segments across the six versions (per-version 106→180), ~850 schema-instances for
full-depth coverage vs. 15 typed today. Plus ADR-015 and 3 new cross-check pin tests.

## [1.0.0] — 2026-07-09

> **Note (post-tag, 2026-07-09):** the owner reframed the v1.0 completeness bar to require **full HL7 segment coverage across all versions** (ROADMAP M5). `v1.0.0` stays the API-freeze tag but is **provisional on `private`**; the first public push is gated on M5.

**API-freeze release.** The public API is frozen under the ADR-014 evolution contract; from here, `1.x` releases are additive-only (new enum cases on the open enums, new types/methods) — removals, renames, and signature changes wait for `2.0`. Milestone status at tag time:

- **M1 — Version coverage:** full per-version field grammar + validation for **v2.3, v2.3.1, v2.4, v2.5.1, v2.6, v2.8.2** (the complete published-standard set an integrator reference targets). A bare `2.8` wire is recognised but grammar-less (ADR-013).
- **M2 — Conformance surface:** every rule is either validated or documented as a spec-cited permanent limitation with a v1.0 freeze decision — the conditional-completeness register (`docs/design/conditional-completeness-audit.md`) + the permanent-limitations register (`docs/design/permanent-limitations-register.md`).
- **M3 — API stabilisation:** ADR-014 evolution policy, the public-surface inventory (`docs/design/public-api-surface.md`), and the finalised versioning contract (`Migration.md`).
- **M4 — Distribution:** the external IP review has **cleared** — the first public push is unblocked.

No source change vs `v0.19.0`; v1.0.0 is the stability-commitment tag. The v1.0 public surface: `Parser` / `BatchParser` / `StreamingBatchParser`, `MessageBuilder`, path + typed-accessor APIs, 15 typed segments + 16 typed composites, `Validator` (+ `HL7Locale.auLocalisation`), and the MLLP codec. Tests: 501 across 26 suites.

### Capability summary (shipped across 0.1 → 0.19, frozen at 1.0)

- Lossless parse ↔ serialise round-trip; BOM/NUL hardening; character-set detection (UTF-8 / ASCII / ISO-8859-1).
- Validation DSL: same-segment compound predicates, cross-segment / message-context / segment-presence atoms, subcomponent-granular field-refs, group-scope cardinality, component-level required-component checks.
- AU ADRM-2021 profile (HL7au:000003–000008, 000040–000042, machine-checkable 00044.* CE/CNE/CWE narrowings).
- `FieldOptionality` R/O/C/X/B/W; codegen'd typed segments + composites; zero runtime dependencies.

## [0.19.0] — 2026-07-09

req-#1 feature-completeness — extend the canonical v2.5.1 NK1 / PV1 / IN1 schemas to their full HL7 field set. Since the canonical version drives the typed-segment structs, this delivers the full typed-accessor surface for these three segments. **Additive only** (ADR-014 §open): typed structs gain accessors; no existing accessor changes; the v2.5.1 grammar table gains fields. Tests: 499 → 501 across 26 suites.

### Added — full canonical field depth for NK1 / PV1 / IN1

- **NK1** 13 → **39** fields (HL7 v2.5.1 §3.4.5) — Marital Status … VIP Indicator.
- **PV1** 20 → **52** fields (§3.4.3) — Charge Price Indicator … Other Healthcare Provider.
- **IN1** 25 → **53** fields (§6.5.6) — Report of Eligibility Date … VIP Indicator (incl. IN1-28 Pre-Admit Cert).

Field index / name / datatype and optionality are spec-verified (all extended fields `O`; only NK1-1 / PV1-2 / IN1-1/2/3 are `R`). Repeatability follows the HL7 v2.5.1 standard shape — the attribute-table `RP/#` column doesn't extract cleanly, so it's a documented, fail-safe best-effort (see `docs/design/full-segment-audit.md`).

### Scope (documented follow-on, not a gap)

**Canonical v2.5.1 only.** The per-version grammar tables (v2.3 / v2.3.1 / v2.4 / v2.6 / v2.8.2) for NK1/PV1/IN1 stay at curated depth (13/20/25) pending a follow-on cycle — typed-accessor coverage is now full (version-agnostic), but per-version *validation* of the extended fields on non-v2.5.1 wires is still limited to the modelled range.

### Added — regression pins

`TypedSegmentTests` (+2): full-canonical field counts + datatypes + held `R` fields; a new scalar typed accessor (NK1-37) hydrates and agrees with the path.

## [0.18.0] — 2026-07-09

ROADMAP M3 (API stabilisation) — the last v1.0 engineering gate. Settles the public API evolution policy, audits the full public surface, and finalises the migration contract. **No behaviour change; the only code change is added DocC notes.** Tests unchanged at 499 across 26 suites. **With M3 closed, M1 + M2 + M3 are all done — v1.0 is tag-able on the private repo (only M4 external IP review remains).**

### Added — ADR-014 public API evolution policy

Documented SemVer evolution contract; **no `@frozen`** (inert for this SPM *source* package with no library-evolution mode). Public enums classified **open** (`Version`, `HL7Locale`, `IssueCode`, `ParseError`, `PathError`, `BuilderError` — may gain cases in a 1.x minor; consumers switch with `@unknown default`) vs **stable** (`FieldOptionality`, `FieldRepeatability`, `IssueSeverity`, `ZSegmentPolicy`, `LineTerminatorPolicy`, `CharacterEncoding`, `RequiredComponentSet.Semantics`, `Segment` — domain-closed). 1.x is additive-only; removals / renames / signature changes wait for 2.0.

### Added — `docs/design/public-api-surface.md`

The v1.0 public-symbol inventory: 74 public types (59 hand-written + 15 codegen'd typed segments), each confirmed intended / minimal / documented, every enum classified open/stable. No accidentally-`public` internals.

### Changed — open-enum DocC + finalised `Migration.md`

The six open enums each gained a `- Note:` telling consumers to switch with `@unknown default` (`ParseError` / `PathError` / `BuilderError` also gained a type-level summary comment). `Migration.md` rewritten from its stale 0.2.0-era content into the v1.0 versioning contract (additive-only rule, open/stable lists, the v0.5.0→v0.17 additive-case history, v1.0 gates).

## [0.17.0] — 2026-07-09

ROADMAP M2 close-out. Consolidates the AU-narrowing and terminology/PKI/history permanent limitations into a single authoritative register and formally closes M2 (conformance-surface finalisation). **Documentation only — no code or API change.** Tests unchanged at 499 across 26 suites.

### Added — `docs/design/permanent-limitations-register.md`

The authoritative list of conformance rules HL7v2Kit cannot machine-check from the wire, each spec-cited and freeze-decided for v1.0: the AU narrowings (HL7au:00044.4.3 CE-text carve-out, 00044.4.7 concept-match, 00044.2 NASH PKI, 00044.1.2/.1.3, HL7au:000001 order addressing) and the cross-cutting terminology / PKI / cross-message-history classes. References the v0.16 conditional-completeness register for the base-spec conditional set. Records what is explicitly **not** a limitation (NUL/BOM handling, grammar-less `.v2_8`, curated NK1/PV1/IN1 depth) to prevent re-litigation.

### Closed — ROADMAP M2

With the v0.16 conditional register (base-spec `C`-without-`condition`) and this register (AU + terminology/PKI/history), every conformance rule is now either validated or documented as a spec-cited permanent limitation with an explicit v1.0 freeze decision. **Decision recorded: all current limitations are acceptable to freeze — none blocks v1.0.** The remaining v1.0 engineering gate is **M3** (API stabilisation).

## [0.16.0] — 2026-07-09

ROADMAP M2 conditional-completeness cycle. Audited every grammar field marked `C` (conditional) that carried no `condition` predicate — 69 instances across 17 distinct segment-index positions — and either shipped a spec-citable predicate or recorded it as a documented permanent limitation. **No public-API change** (both shipped predicates reuse the existing v0.4-S4 same-segment DSL; the condition strings are internal schema metadata). v1.0 stability clock continues from v0.5.0. Tests: 495 → 499 across 26 suites.

### Added — `docs/design/conditional-completeness-audit.md` (M2 register)

The authoritative conditional-completeness register: per-position verdict (ship / permanent limitation) with spec citations. This is the M2 gate for v1.0 — the conditional surface is now either shipped or explicitly, spec-citably documented.

### Fixed — two v2.8.2 conditions the v0.15 authoring left as bare `C`

A spec predicate existed for these but was not extracted during v0.15 (fail-safe, so no misfire — but incomplete per req #4):

- **PD1-15 Advance Directive Code** — `PD1-22 populated` (exact; v2.8.2 §3.3.11.15 "required when PD1-22 - Advance Directive Last Verified Date is valued").
- **ORC-26 Advanced Beneficiary Notice Override Reason** — `ORC-20 in (3, 4)` (v2.8.2 §4.5.1.26; HL7 Table 0339 not-signed codes). **Partial** — external code systems may encode "not signed" with other values (documented, same honesty pattern as HL7au:00044.4.4); a sound necessary condition that cannot misfire on HL7-standard traffic.

### Documented — 15 permanent limitations (req #3/#4)

OBR-1/8/9/10/11/20/21/22/26/32, OBR-48, OBX-4/5/22, DG1-22 carry `C` in their attribute tables but no wire-detectable required-when trigger (discourse-level, data-nature-dependent, peer-comparison, or descriptive-without-cited-MUST). Each stays fail-safe (treated as optional) and never misfires. See the register for per-field rationale.

### Added — regression pins

`MultiVersionTests` (+4): PD1-15 fires (PD1-22 populated + PD1-15 empty); ORC-26 fires (ORC-20=3) and does NOT fire (ORC-20=1, a signed value); a guard asserts the v2.8.2 permanent-limitation set stays `C`-without-`condition` (catches any future accidental bare-`C` field).

## [0.15.0] — 2026-07-09

ADR-013 first-class v2.8.2 grammar cycle. Adds `Version.v2_8_2` and a full v2.8.2 grammar table (15 segments) — coverage now spans v2.3 → v2.8.2, the latest published HL7 v2.x standard (ROADMAP M1 track). **Additive public-API change** (`Version.v2_8_2 = "2.8.2"`; the grammar-less `.v2_8 = "2.8"` is retained — distinct MSH-12 raw value, no fold). **No new `FieldOptionality` case** — `.withdrawn` (v0.14) covers every v2.8.2 `W`. v1.0 stability clock continues from v0.5.0. Tests: 488 → 495 across 26 suites.

### Added — `Version.v2_8_2` + 15 v2.8.2 segment schemas

`case v2_8_2 = "2.8.2"` (after `v2_6`, before `v2_8`); `grammarTable(for:)` wired; `SegmentGrammar+v2_8_2.swift` emits. Segments authored under `Resources/schemas/v2.8.2/` from the v2.8.2 Final Standard PDFs (CH02/03/04/06/07), preserving every v2.8.2-vs-v2.6 divergence verbatim: MSH/MSA/ERR/EVN/NTE (S1); PID/PD1/NK1/PV1/AL1 (S2); ORC/OBR/OBX (S3); DG1/IN1 (S4). Divergence classes (see `docs/design/v2_8_2-spec-audit.md`):

- **`IS → CWE`** — the dominant coded-field promotion wave (ERR-9, EVN-4, PD1/PV1/DG1/IN1 coded fields, PID-8/32, OBX-8).
- **`B → W`** — 2.7-era withdrawals (MSA-3/5/6, ERR-1, EVN-1, PD1-4, PID-2/4/9/12/19/20/28, AL1-6, OBR-5/6/14/15/27, ORC-7).
- **`O → B`** — new backward-compat demotions across ORC/OBR/OBX/PID/PD1/PV1.
- **Conditionals restructured** — v2.6 vet conditionals dropped (PID-35 `C→O` renamed "Taxonomic Classification Code", PID-36 `C→B`); parent-order XOR dropped (ORC-8, OBR-29 `C→O`); new predicate-less `C` fields recorded conditional-without-condition (PD1-15, ORC-26, OBR-48, DG1-22).
- **Other datatype/name changes** — `EI→EIP` (ORC-4), `ST→OG` (OBX-4), `ID→NM` (DG1-15), `ST→CWE` (OBR-13); renames (OBX-8 "Interpretation Codes", IN1-2 "Health Plan ID").
- **Field-count growth** — PID 39→40, ORC 31→34, OBR 50→54, OBX 25→30; new fields authored from v2.8.2 prose.

### Method note

The OBX base attribute table (CH07 p51) was used, **not** the four `Example - <cat> Category` profile tables (p153–155) whose `X` markings are example-specific — a trap flagged in the audit doc.

### Known limitations (documented, not shipped — req #3/#4)

- **PD1-15 / ORC-26 / OBR-48 / DG1-22 / OBX-22** — `C` with no extractable predicate; recorded conditional-without-condition (never fire).
- **NK1 / PV1 / IN1** — curated to the shared typed-segment depth (13 / 20 / 25); full v2.8.2 sets (41 / 54 / 53) unmodelled — a cross-version req-#1 backlog item.

### Added — regression pins

`MultiVersionTests` (+7): version detection incl. `.v2_8`/`.v2_8_2` coexistence; S1–S4 grammar-table field counts + divergences; S1 dispatch no-unknown-segment; and `v282CleanORUHasNoErrors` (well-formed v2.8.2 ORU^R01 → zero errors).

## [0.14.0] — 2026-07-09

ADR-012 first-class v2.6 grammar cycle. Adds `Version.v2_6` and a full v2.6 grammar table (15 segments), closing the last common-version coverage gap (ROADMAP M1). Before this, a `2.6` wire fell back to `.v2_5_1` or threw `.unsupportedVersion`; it now dispatches to per-field v2.6 validation. **Additive public-API change** (`Version.v2_6` — precedented by `v2_8`; and `FieldOptionality.withdrawn` — a new case on the non-`@frozen` optionality enum); v1.0 stability clock continues from v0.5.0. Tests: 482 → 488 across 26 suites.

### Added — `Version.v2_6` + 15 v2.6 segment schemas

`case v2_6 = "2.6"` (between `v2_5_1` and `v2_8`); `grammarTable(for:)` wired; the regenerate path emits `SegmentGrammar+v2_6.swift`. Segments authored under `Resources/schemas/v2.6/`, each from the v2.6 Final Standard PDFs (CH02/03/04/06/07), preserving every v2.6-vs-v2.5.1 divergence verbatim: MSH, MSA, ERR, EVN, NTE (S1); PID, PD1, NK1, PV1, AL1 (S2); ORC, OBR, OBX (S3); DG1, IN1 (S4). Divergence classes (see `docs/design/v2_6-spec-audit.md`):

- **TS → DTM** — systematic across every timestamp field.
- **CE → CWE** — field-by-field (verified per header, not blanket); OBR-44/45 went to **CNE**, not CWE.
- **Field-count growth** — MSH 21→25, MSA 6→8, NTE 4→8, PD1 21→22, OBR 47→50, OBX 17→25, DG1 21→26; new fields authored from v2.6 prose.
- **Structural conditions** carried verbatim (unchanged in v2.6 spec text): ORC-2/3/8, OBR-2/3/7/14/25/29, OBX-2, PID-35/36, DG1-20/21.

### Added — `FieldOptionality.withdrawn` (`W`) model extension (req #3)

v2.6 is the first modelled version to use the `W` (withdrawn) OPT code — DG1-2/4 and the DRG/outlier block DG1-7..14 were withdrawn (DRG detail moved to the new DRG segment). `W` is distinct from `B` (retained for compatibility); mapping `W → B` would misrepresent the spec (req #4). Added `FieldOptionality.withdrawn = "W"`; codegen maps `"W" → .withdrawn`; `Validator.checkDeprecation` warns (`.fieldNotSupported`) on a populated withdrawn field — same warn-on-populated family as `B`/`X`.

### Known limitations (documented, not shipped — req #3/#4)

- **OBX-22 Mood Code** is `C` in the v2.6 attribute table but the prose gives no extractable predicate; recorded as a conditional-without-condition (falls through as optional, never fires) rather than inventing a rule that could misfire.
- **IN1** mirrors the shared 25-field curation across all versions (not the full ~53-field v2.6 IN1) — a carried scope limitation, not a v2.6 regression.

### Added — regression pins

`MultiVersionTests` (+6): grammar-table field counts + divergences per substage (S1–S4), the populated-withdrawn-field warning (`v26WithdrawnFieldWarns`), and a well-formed v2.6 ORU^R01 that validates with zero errors (`v26CleanORUHasNoErrors`) — end-to-end proof the carried conditions don't over-fire.

## [0.13.1] — 2026-07-04

### Changed — retired orphaned AU profile JSON overlays (maintenance)

Deleted `Resources/profiles/au-adrm-2021/{MSH,OBR,ORC,datatypes}.json`. These files were authored partially in v0.5–v0.8 as the "editable spec source" ADR-007 envisioned, but `ProfileLoader` always returned the hand-curated `Profile.auADRM2021` Swift and never read the JSON — so they were dead code that had drifted stale (missing the v0.8 MSH-12, v0.11 `cardinalityExtensions`, and v0.13 `componentInequalities` / `valueConditionals` rules). Removing them eliminates the "hand-synced JSON↔Swift drift risk" flagged in the runway by deleting the unused second representation; the compiler-checked Swift is now the acknowledged single source of truth. A JSON-driven codegen path (ADR-004 principle) is deferred until a second localisation profile makes shared tooling worthwhile. Comments in `Profile+au_adrm_2021.swift` / `ProfileLoader.swift` corrected; ADR-007 carries a v0.14 status note. **No behaviour or API change**; 475 / 475 tests unchanged.

## [0.13.0] — 2026-07-04

ADR-011 composite-override extension cycle. Adds two internal rule axes to `CompositeOverride` and ships four previously-deferred HL7au:00044.* CE/CNE/CWE datatype conformance points. **No public-API change** (composite-override types are internal per ADR-007; both new rules reuse `.profileConstraintViolation`, no new `ValidationIssue.Kind` case); v1.0 stability clock continues from v0.5.0. Tests: 469 → 475 across 26 suites. Single functional commit + release commit.

### Added — composite-override model extensions (ADR-011)

- **`ComponentInequality`** `{ componentA, componentB, specCitation }` — "two named components must carry different values when both populated." Fires `.profileConstraintViolation` on equal values; no-op when either is empty.
- **`ComponentValueConditional`** `{ component, deniedValues, condition?, specCitation }` — "component must not carry a denied value," with an optional v0.7-DSL message-context gate (reuses the ADR-009 `conditionTriggers` entry point). No-op on empty component or gate-false.
- `CompositeOverride` gains `componentInequalities` + `valueConditionals` (defaulted empty). `Validator.checkProfileCompositeOverrides` gains two inner loops (Track 3 / Track 4).

### Added — HL7au:00044 CE/CNE/CWE conformance points

- **44.4.8** (CE) — alternate coding system (CE-6) must differ from primary (CE-3). `ComponentInequality(3, 6)`.
- **44.4.4** (CE, Orders/Results) — LOINC (LN) must be the primary coding system, not the alternate. `ComponentValueConditional(6, ["LN"], "messageCode in (ORM, ORU)")`. Shipped as a machine-checkable *necessary condition* ("LN must not appear in CE-6"), not the full placement rule — flagged partial (same honesty pattern as v0.10 OBR-7).
- **44.5.3** (CNE) / **44.6.3** (CWE) — `<text>` component (CNE-2 / CWE-2) must be valued. `requiredComponents: [2]` (existing model, no carve-out unlike CE-2).

### Known limitations (documented, not shipped — req #3/#4)

- **44.4.3** (CE `<text>`) — carries an explicit "in some locations user display is not intended and the text may be blank" carve-out; not wire-detectable, an unconditional rule would over-fire. Permanent limitation unless a wire signal for the blank-allowed locations emerges.
- **44.4.7** (CE concept-match) — "identifier and alternate identifier must reflect the same concept" requires a terminology service; not machine-checkable from the wire. Permanent limitation.
- **44.5.7 / 44.6.7** (CNE/CWE concept-match) — marked "Removed" in ADRM r2; not applicable.

### Regression pins

Six in `LocaleAUProfileTests`: 44.4.8 fires (equal CE-3/CE-6) + silent (distinct); 44.4.4 fires (LOINC in CE-6 on ORU) + gated-silent (LOINC in CE-6 on ADT); 44.6.3 (ERR-3 CWE empty text); 44.5.3 (ORC-30 CNE empty text).

## [0.12.0] — 2026-07-03

v2.3 / v2.3.1 T-track grammar back-port. Authors the six T-track segments (EVN / MSA / ERR / PD1 / DG1 / IN1) into the v2.3 and v2.3.1 grammar tables, mirroring the v0.6 v2.4 back-port. Before this, a v2.3 / v2.3.1 wire carrying any of these segments hit the "unknown segment" (Z-segment) path — now they dispatch to per-version field-level validation. Closes the T-track per-version coverage gap documented in `docs/design/v2_3-v2_4-spec-audit.md`. **No public-API change** vs v0.11.0 (typed-segment structs are version-agnostic and already existed); v1.0 stability clock continues from v0.5.0. Tests: 466 → 469 across 26 suites.

### Added — 12 new per-version schemas

Six segments × two versions authored under `Resources/schemas/v2.3/` and `Resources/schemas/v2.3.1/`, each from the version's own spec PDF (v2.3 CH2/CH3/CH6; v2.3.1 combined Final Standard). Per-version field shapes preserved verbatim:

- **EVN** — 6 fields on v2.3 / v2.3.1 (no EVN-7 Event Facility; that arrived in v2.4).
- **MSA** — 6 fields; identical to v2.4.
- **ERR** — single `CM` field (Error Code and Location); identical to v2.4.
- **PD1** — 12 fields on v2.3 / v2.3.1 (v2.4 expanded to 21).
- **DG1** — 19 fields. Divergences: DG1-2 (Coding Method) is `R` on v2.3 / v2.3.1 (v2.4 downgraded to `B`); DG1-15 (Diagnosis Priority) is `NM` on v2.3, revised to `ID` on v2.3.1 (matching v2.4).
- **IN1** — 25-field curation (shared typed-segment surface). Divergences: IN1-14 (Authorization Information) is `CM` on v2.3 / v2.3.1 (v2.4 retyped to `AUI`); IN1-17 (Insured's Relationship To Patient) is `IS` on v2.3, revised to `CE` on v2.3.1 (matching v2.4). Field optionality follows the v2.4 curation (R on IN1-1/2/3) — the v2.3 CH6 OPT column resisted clean PDF extraction; types + field count are exact. Documented in the audit doc.

### Added — regression pins

`MultiVersionTests`: `v23BackportedSegmentsRecognised` + `v231BackportedSegmentsRecognised` (segments dispatch to the version grammar, no unknown-segment), `v23DG1RequiredFieldsFire` (DG1-1/2/6 required-field misses fire; proves the v2.3-specific DG1-2 = R is enforced). Extended `grammarTablePopulated` (v2.3.1) + `v23GrammarTablePopulated` (v2.3) with the 6 new segment counts + the DG1-15 / IN1-17 errata-delta type assertions.

## [0.11.0] — 2026-07-03

ADR-010 DSL-extension cycle. Ships three new predicate/grammar primitives (segment-presence atoms, group-scope cardinality rules, subcomponent-granular field-refs) and applies them to close a cluster of previously-deferred spec rules across all four base versions plus the AU profile: §4.5.1.8 ORC-8/OBR-29 XOR softening, OBR-7/-14 specimen-presence triggers, and HL7au:000008 + .1 (Display Segments). **One new public `ValidationIssue.Kind` case** (`.segmentCardinalityBelowMinimum`, additive on a non-`@frozen` enum — minor bump); no other public-API change; v1.0 stability clock continues from v0.5.0. Tests: 446 (v0.10.0) → 466 across 26 suites. Six functional commits: `13e616a` (S1) → `3d11590` (S2) → `4088a75` (S3) → `cca9aa8` (S4) → `2f4796c` (S4b) plus the ADR-010 accept `2396bd2`.

### Added — ADR-010 Accepted (2026-07-02)

`docs/design/ADR-010-dsl-extensions-peer-absent-quantification-content-gated.md` Accepted. Opens the v0.11 cycle. Three narrowly-scoped extensions to the ADR-008 / ADR-009 machinery, each additive and internal:

- **Segment-presence atoms** (`<segmentID> present` / `absent`) — unlocks §4.5.1.8 XOR softening and the OBR-7 / .9 / .10 / .11 / .14 specimen-presence cluster. Reuses ADR-008 group-boundary resolution.
- **Group-scope cardinality rules on `SegmentGrammar`** — new axis alongside min/max occurrence bounds, carrying a v0.7-DSL atom predicate. Sole initial consumer: HL7au:000008 parent ("≥1 OBX per OBR/OBX group with `OBX-3.3 = AUSPDI`"). Adds `.segmentCardinalityBelowMinimum` case to `ValidationIssue.Kind`.
- **Subcomponent-granular field-refs in DSL atoms** (`<segmentID>-<int>[.<int>[.<int>]]`) — unlocks HL7au:000008.1 as an ADR-009-style overlay with `condition: "OBX-3.3 = AUSPDI"`. Reuses `ComponentValueSet.condition` dispatch unchanged.

Substage plan: S1 segment-presence + XOR softening → S2 subcomponent field-refs + HL7au:000008.1 → S3 cardinality axis + HL7au:000008 parent → S4 specimen-presence cluster → S5 release as v0.11.0.

Accepted as drafted (single ADR spanning all three extensions); split-off of Extension 2 into a follow-up ADR-011 remains an available option if S3 turns out too large in practice.

### Added — v0.11-S1: segment-presence atoms + §4.5.1.8 XOR softening (2026-07-03)

First implementation stage of ADR-010 lands on branch `v0.11-adr-010`. Extends the v0.7-S2 predicate DSL with the ADR-010 Extension 1 segment-presence atom (`<segmentID> present` / `<segmentID> absent`) and applies it to soften the v2.4 CH04 §4.5.1.8 ORC-8 / OBR-29 XOR — the child-order parent may be carried in either peer without over-firing.

- `Validator.evaluateSegmentPresenceAtom` dispatches the new atom shape before the general referent/predicate split. Segment-ID filter: 3-char ASCII alphanumeric uppercase (matches DG1, IN1, PV1 alongside ORC, OBR, etc.).
- `Message.segmentExists(_ id: String, inGroupOf index: Int) -> Bool` — thin wrapper over ADR-008 `associatedSegment(_:fromIndex:)`. Same ORC/OBR-group boundary semantics; degenerate-group fallback for non-ORC/OBR callers.
- ORC-8 / OBR-29 conditions in `Resources/schemas/{v2.4,v2.5.1}/{ORC,OBR}.json` rewritten as DNF-encoded XOR softening. Parser has no paren support, so `A AND (B OR C)` is encoded as `A AND B OR A AND C` (equivalent under AND-tighter-than-OR precedence). DocC on `conditionTriggers` updated with the DNF constraint.
- Regression pins in `ConditionalFieldTests`: `orc8SilentUnderXORSofteningWhenOBRCarriesParent`, `obr29SilentUnderXORSofteningWhenORCCarriesParent`. All v0.9 pins (both-empty case fires; parent-only case silent) remain green.
- **Known limitation**: v2.3 / v2.3.1 ORC-8 / OBR-29 still carry the unsoftened `"ORC-1 = CH"` predicate — softening those needs PDFKit spec-text confirmation that v2.3 / v2.3.1 CH04 carry the equivalent §4.5.1.8 XOR trigger; queued for S5 release-prep audit.

Tests: 446 → 448 across 26 suites.

### Added — v0.11-S2: subcomponent-granular DSL field-refs + HL7au:000008.1 overlay (2026-07-03)

Second implementation stage of ADR-010 lands on branch `v0.11-adr-010`. Extends the v0.7-S2 predicate DSL with the ADR-010 Extension 3 subcomponent-granular field-ref production (`<segmentID>-<int>[.<int>[.<int>]]`) so atom LHSes can read a specific composite slot. First (initial) consumer: HL7au:000008.1 — the AU display-segment identifier value set gated on `OBX-3.3 = AUSPDI`.

- `Validator.parseIndexSuffix` factored out; `resolveFieldRef` / `readFieldRef` extended to accept the new tail. `readField` widened with optional `componentIndex` / `subcomponentIndex` (nil → v0.4-S4 first-of-first-of behaviour; set → specified slot). `populated` / `empty` still evaluate the whole field.
- AU profile `Profile+au_adrm_2021.swift` gains a `FieldOverride` on OBX-3 with `component: 1`, `condition: "OBX-3.3 = AUSPDI"`, `allowedValues: ["HTML","PDF","RTF","TXT","PIT"]`. Reuses the ADR-009 `ComponentValueSet.condition` dispatch unchanged. Spec text extracted via PDFKit from AU ADRM-2021 pp. 247 + 420–421.
- **ADR-010 amended** in the same commit with a post-hoc clarification: the ADR §"Rules expressed…" section originally wrote `component: 3` for the HL7au:000008.1 overlay, but component 3 IS the AUSPDI gate itself. The value-set check is on component 1 (Identifier) per HL7au:000008.1 verbatim. Implementation ships with `component: 1`.
- Four new regression pins in `LocaleAUProfileTests`: `hl7au000008_1_conformingPDFSilent`, `hl7au000008_1_nonConformingAUSPDIFires`, `hl7au000008_1_nonAUSPDIGateSilent` (verifies the gate blocks non-display OBXs), `hl7au000008_1_deprecatedPITPermitted` (deprecated per AU ADRM p. 247 but still supported).
- DSL grammar DocC on `conditionTriggers` updated with the extended `<fieldref>` production.

Tests: 448 → 452 across 26 suites.

### Added — v0.11-S3: group-scope cardinality axis + HL7au:000008 parent (2026-07-03)

Third implementation stage of ADR-010 lands on branch `v0.11-adr-010`. New grammar axis for group-scope cardinality rules (Extension 2), plus a parallel `Profile.cardinalityExtensions` axis so locale-scoped rules can layer on the base grammar without over-firing outside their locale. First consumer: HL7au:000008 parent — "The message must contain at least one OBX display segment per OBR/OBX group" (AU ADRM-2021 p. 420).

**New internal types**:
- `GroupScope` enum: `.orcObxGroup`, `.obrObxGroup`, `.messageWide`.
- `SegmentCardinalityRule`: `{countedSegmentID, scope, minCount, predicate, applicableWhen?, specCitation?}`. Two S3-clarification fields beyond the ADR-010 Decision text — `countedSegmentID` (avoids parsing the predicate to reconstruct the target segment ID for the fired issue) and `applicableWhen` (v0.7-DSL message-context gate, mirrors ADR-009 `ComponentValueSet.condition`).

**Model additions**:
- `SegmentGrammar` gains `segmentCardinalityRules: [SegmentCardinalityRule]` (empty by default; axis is ready for future universal rules that ship in the base schema JSON).
- `Profile` gains `cardinalityExtensions: [String: [SegmentCardinalityRule]]` — parallel to `grammarExtensions`. Locale-scoped rules layer here; the base-grammar axis remains reserved for spec-universal rules.

**Public API**:
- New `ValidationIssue.Kind.segmentCardinalityBelowMinimum(segmentID:minCount:actual:groupScope:)` case. Additive on a non-`@frozen` enum; minor bump per the pattern established at v0.4-S4 / v0.7 / v0.8. All other public API is unchanged.

**Codegen**:
- `HL7v2KitCodegen.CardinalityRuleSchema` decodes the optional `segmentCardinalityRules` JSON key and emits the internal `SegmentGrammar` init that carries the rules array. Silent-safe: no shipping schema uses the key yet, so generated output is byte-identical to v0.11-S2. Codegen-drift CI stays clean.

**Validator**:
- `mergeGrammarExtension` extended to merge `Profile.cardinalityExtensions` into the effective `SegmentGrammar.segmentCardinalityRules`.
- `Validator.validate` gains a `checkCardinalityRules` call after each `checkSegment`. Group resolution via a new private `resolveGroup(scope:anchorIndex:message:)` helper (three scopes implemented). Dedupe via a `Set<String>` keyed by `(scope, groupHeadIndex, countedSegmentID, predicate, minCount)` so a rule attached to a head segment fires exactly once per distinct group.
- Candidate iteration filters to segments matching `countedSegmentID`. Without this filter, a predicate like `OBX-3.3 = AUSPDI` evaluated against a non-OBX candidate would resolve via ADR-008 `associatedSegment` (ORC-scoped) and could false-positive-match an OBX in a different sub-group. Discovered during multi-OBR regression test.

**AU profile — HL7au:000008 shipped** as a `SegmentCardinalityRule` on OBR grammar via `Profile.cardinalityExtensions`. `countedSegmentID: "OBX", scope: .obrObxGroup, minCount: 1, predicate: "OBX-3.3 = AUSPDI", applicableWhen: "messageCode in (ORU, REF)"`. Fires only under `.auLocalisation` on Results / Referrals messages when a resolved OBR/OBX sub-group contains no OBX with `OBX-3.3 = AUSPDI`.

**Tests**:
- `LocaleTests.auLocaleAddsButDoesNotRemoveBaseSpecErrors` updated: `.segmentCardinalityBelowMinimum` classified as locale-attributable (mirrors `.profileConstraintViolation`) so the AU-vs-international fixture parity check treats the new violations correctly.
- Six new regression pins in `LocaleAUProfileTests`: silent-with-AUSPDI, fires-without-AUSPDI, silent-on-ADT-with-no-OBR, silent-on-ORM (applicableWhen gate), silent-under-`.international` (locale gate), fires-per-group on multi-OBR wire.

**ADR-010 amended** with an S3-implementation clarification block:
1. Locale-scoped cardinality rules require the parallel `Profile.cardinalityExtensions` axis in addition to `SegmentGrammar.segmentCardinalityRules` (ADR text only mentioned the base axis).
2. `SegmentCardinalityRule` gains `countedSegmentID` (required) and `applicableWhen` (optional) fields — both additive to what the Decision section specified.

Tests: 452 → 458 across 26 suites.

### Added — v0.11-S4: OBR specimen-presence cluster (2026-07-03)

Fourth implementation stage of ADR-010 lands on branch `v0.11-adr-010`. Uses the v0.11-S1 `<segmentID> present` atom (`SPM present` on v2.5.1) plus the existing `<fieldref> populated` atom (`OBR-15 populated`) to encode "specimen sent with request" triggers on OBR-7 and OBR-14 per v2.4 CH04 §4.5.3.7 / .14.

**Schema updates**:
- **v2.5.1 OBR-7**: `"messageCode = ORU"` → `"messageCode = ORU OR SPM present OR OBR-15 populated"`. Adds the specimen-sent-with-request second trigger from §4.5.3.7.
- **v2.4 OBR-7**: `"messageCode = ORU"` → `"messageCode = ORU OR OBR-15 populated"`. SPM segment doesn't exist in v2.4; OBR-15 (specimen source) is the specimen indicator.
- **v2.5.1 OBR-14**: new condition `"SPM present OR OBR-15 populated"` per §4.5.3.14 "must contain a value when the order is accompanied by a specimen".
- **v2.4 OBR-14**: new condition `"OBR-15 populated"` per §4.5.3.14 with SPM-absent fallback.

**Scope trim per the working notes req #4**:
- ADR-010 §"Rules expressed…" named "OBR-7 second trigger + OBR-9 / OBR-10 / OBR-11 / OBR-14" as the specimen-presence targets. PDFKit extraction of v2.4 CH04 pp. 46-48 confirmed only OBR-7 (§4.5.3.7) and OBR-14 (§4.5.3.14) carry crisp "must be filled in when X" conditional-required triggers.
- OBR-9 §4.5.3.9 ("results-only field except when the placer has drawn the specimen"), OBR-10 §4.5.3.10 ("will identify..."), OBR-11 §4.5.3.11 ("identifies the action...") are descriptive statements without MUST language. Not shipped per req #4 ("no predicate ships if known-incorrect"). Re-audit if a future spec revision adds MUST language.
- ADR-010 amended with a "Clarification 2026-07-03 (during S4 implementation)" block documenting the trim.

**Fixture-corpus side-fix**:
- Discovered a systematic field-shift error across 13 ORU fixtures: a timestamp was consistently placed at OBR-15 (specimen source, deprecated in v2.5.1) instead of OBR-14 (specimen received DT). Mechanical sed fix `s/L\|\|\|\([0-9]\{14\}\)\|\|/L||\1|||/g` corrected all 13.
- Bonus fix: cleared the pre-existing "OBR-15 (deprecated B) but populated" warnings that had been surfacing on those fixtures since v0.2.

**Regression pins** (five new tests in `ConditionalFieldTests`):
- `obr14FiresWhenOBR15PopulatedAndOBR14Empty_v24` — v2.4 §4.5.3.14 canonical trigger.
- `obr14SilentWhenOBR14Populated_v24` — guard bypasses on populated field.
- `obr14SilentWhenNoSpecimenIndicator_v24` — no OBR-15 (imaging OBR case) → predicate false.
- `obr14FiresWhenSPMPresent_v251` — v2.5.1 SPM-segment detection (uses S1 `SPM present` atom).
- `obr7FiresUnderSecondTrigger` — ORM with OBR-15 populated fires OBR-7 via the second trigger.

**Known limitations carried into S5**:
- v2.3 / v2.3.1 OBR-7 / OBR-14 do not carry S4 predicates — v2.3 CH04 audit is an S5 candidate.
- v2.3 / v2.3.1 ORC-8 / OBR-29 still carry the unsoftened `"ORC-1 = CH"` from v0.10 (documented per S1).

Tests: 458 → 463 across 26 suites.

### Added — v0.11-S4b: per-version mirror to v2.3 / v2.3.1 (2026-07-03)

Closes the per-version coverage gap for the S1 XOR softening and S4 specimen-presence conditions by mirroring them into the v2.3 and v2.3.1 OBR / ORC schemas, after PDFKit-confirming the equivalent spec text in v2.3 CH4.

- **v2.3 + v2.3.1 ORC-8 / OBR-29**: `"ORC-1 = CH"` → DNF XOR softening (same predicate strings as v2.4/v2.5.1). Basis: v2.3 §4.3.1.8 child-order-transmitted trigger (verbatim like v2.4 §4.5.1.1) + OBR-29 defined "identical to ORC-8-parent" + the general XOR parenthetical "This rule is the same for other identical fields in the ORC and OBR" (v2.3 CH4, placer/filler order-number rules). v2.3 has no parent-specific §4.5.1.8 sentence like v2.4, so the softening rests on the identical-fields generalization — documented in the audit doc.
- **v2.3 + v2.3.1 OBR-7**: `"messageCode = ORU"` → `"messageCode = ORU OR OBR-15 populated"` (SPM absent in v2.3/v2.3.1, same fallback as v2.4). Basis: v2.3 §4.5.1.7.
- **v2.3 + v2.3.1 OBR-14**: new condition `"OBR-15 populated"`. Basis: v2.3 §4.5.1.14 — *verbatim identical* to v2.4 §4.5.3.14 ("must contain a value when the order is accompanied by a specimen").
- Three regression pins: `obr14FiresOnV23`, `orc8Obr29FireOnV231ChildBothEmpty`, `orc8SilentOnV231WhenOBRCarriesParent`.

Tests: 463 → 466 across 26 suites.

## [0.10.0] — 2026-06-25

Per-version cross-segment / message-context coverage closure + AU narrowing audit. **Eight functional commits** since v0.9.0, all under the "correct defects as found" feedback rule (`feedback_correct_defects_as_found.md`). PDFKit-extracted spec text for v2.3, v2.3.1, and v2.5.1 CH06 to close the v0.4-S2 "per-version conditional rules pending PDFs" gap for every spec-extractable trigger. Two AU narrowings (HL7au:000001, HL7au:000008) audited and explicitly marked unshippable until a future ADR-010 introduces peer-absent / segment-quantification / content-gated DSL primitives. **No public-API change** vs v0.9.0; v1.0 stability clock continues from v0.5.0. Tests: 439 (v0.9.0) → 446 across 26 suites.

### Added — OBR-7 partial + audit of OBR-14 / OBR-22 / OBR-32

`0810bda` ships `"messageCode = ORU"` on OBR-7 in v2.5.1 + v2.4 per §4.5.3.7 first trigger (report message). Second trigger (specimen sent with request) deferred — needs specimen-presence DSL atom. OBR-14 / OBR-22 / OBR-32 explicitly audited as having no extractable spec MUST trigger.

### Added — ORC-3 / OBR-3 filler-order XOR

`1f7448e` ships the symmetric XOR per §4.5.1.3 (exact mirror of the v0.7-S4 ORC-2 / OBR-2 placer rule).

### Added — Per-version coverage closure to v2.3 + v2.3.1

`5148421` propagates all 5 cross-segment / message-context rules (ORC-2/OBR-2 XOR, ORC-3/OBR-3 XOR, ORC-8/OBR-29 child-order, OBR-7 report-message, OBR-25 report-message) to v2.3 + v2.3.1 schemas. PDFKit-extracted both v2.3.1 Hl7V231.pdf and v2.3 CH4.pdf; confirmed verbatim-equivalent spec text. **16 new condition strings**.

`f98ea6a` propagates OBX-2 result-status condition `"OBX-11 != X"` to v2.3 + v2.3.1 OBX.json. §7.3.2.2 wording confirmed verbatim across all 4 versions.

### Added — DG1-20 / DG1-21 Update-Diagnosis trigger

`c25e208` ships `"triggerEvent = P12"` on both fields in v2.5.1 per §6.5.2.20 / §6.5.2.21. Uses the v0.7 message-context atom.

### Audited / not shippable

- `87dc447` HL7au:000001 (Order addressing / MSH-6 Receiving facility) audited; all 4 subrules either runtime semantics, soft "should" guidance, or pointing to PKI-deferred HL7au:00044.2.
- `14377cc` HL7au:000008 (Display Segments) audited; cluster needs new DSL primitives (segment-presence-quantification, content-gated overlays). Re-audit after ADR-010 lands.

Combined audit findings reveal a pattern: multiple deferred rules (§4.5.1.8 XOR softening, OBR-7/9/10/11/14 specimen-presence, HL7au:000008) all point to the same architectural extension — a future ADR-010 covering peer-absent atom + segment-quantification atom + content-gated overlay dispatch.

### Carried over from v0.9.0 onto the v0.10.0 line

- `cc14e89` ORC-8 predicate corrected (`previousSegment(ORC).ORC-1 = PA` → `"ORC-1 = CH"`) per the working notes req #4.
- `f750e56` OBR-29 silently-missing condition filled (`"ORC-1 = CH"`).

These were tagged into v0.9.0; included here for cycle continuity.

## [0.9.0] — 2026-06-25

Docs + defect-fix release. Closes the v0.7-S4 deferred work by back-filling verbatim v2.4 CH04 § citations for the four cross-segment / message-context rules into `docs/design/v2_3-v2_4-spec-audit.md`, using the PDFKit-based spec-extraction recipe (memory file `reference_pdf_extraction.md`) that cleared the prior "no pdftotext" gate. The audit pass surfaced two the working notes req #4 defects — both corrected in the same session per the new `feedback_correct_defects_as_found` working rule. **No public-API change** vs v0.8.0; v1.0 stability clock continues from v0.5.0. Tests: 435 (v0.8.0) → 439 across 26 suites.

### Added — v2.4 spec-audit § citation back-fill

`docs/design/v2_3-v2_4-spec-audit.md` Conditional-rule carry-forward table extended with rows citing v2.4 CH04 verbatim for each v0.7 cross-segment rule:

- **ORC-2 §4.5.1.2** (p. 4-34) — XOR with OBR-2; wording identical to v2.5.1.
- **OBR-2 §4.5.3.2** — symmetric XOR partner.
- **OBR-25 §4.5.3.25** (p. 4-52) — report-message guard; wording identical to v2.5.1.
- **ORC-8 §4.5.1.1 + §4.5.1.8** (pp. 4-26 / 4-37) — child-order trigger + XOR softening.
- **OBR-29 §4.5.3.29** (p. 4-54) — identical-to-ORC-8 trigger.

PDFKit-based extraction recipe captured as `reference_pdf_extraction.md` memory; clears the previously-deferred "no pdftotext" gate that blocked spec-audit work.

### Fixed — ORC-8 predicate (the working notes req #4 defect)

The v0.7-S4 mirror shipped `previousSegment(ORC).ORC-1 = PA` as the ORC-8 conditional. The v2.4 CH04 audit surfaced that the spec §4.5.1.1 trigger is keyed on "current ORC carries ORC-1 = CH", not on "preceding ORC carried PA". The prior predicate under-fired on standalone CH orders and CH orders whose parent was sent in a prior message — silent false negatives on spec-compliant scenarios.

Corrected to `"ORC-1 = CH"` (same-segment v0.4-S4 DSL atom; no architectural change) on both `Resources/schemas/v2.5.1/ORC.json` and `Resources/schemas/v2.4/ORC.json`. Tests: existing `orc8ConditionalFiresOnChild` updated; new `orc8ConditionalFiresOnStandaloneChild` (regression guard for the prior false-negative) + `orc8ConditionalSilentOnParent` (negative pin) added. 2 new tests.

### Fixed — OBR-29 silently-missing condition (same defect class)

OBR-29 was conditional in both v2.5.1 and v2.4 schemas but had no `"condition"` string at all — the field's §4.5.3.29 "It is required when the order is a child" trigger silently never fired. Added `"condition": "ORC-1 = CH"`; the v0.7 cross-segment field-ref semantic resolves `ORC-1` via `Message.associatedSegment(ORC, fromIndex: OBR_index)` when evaluated in OBR context.

Tests: new `obr29ConditionalFiresOnChildAssociatedORC` + `obr29ConditionalSilentOnNonChildAssociatedORC` pins. 2 new tests.

Known limitation documented: the §4.5.1.8 XOR softening (parent in ORC OR OBR satisfies both) is not yet enforced — would require a DSL primitive distinguishing "peer absent" from "peer empty" (current cross-segment ref fails safe to false on both). The shipped ORC-8 / OBR-29 conditions err on the over-fire side relative to the XOR softening but match the §4.5.1.1 / §4.5.3.29 child-order triggers exactly.

### Added — Process improvement

New feedback memory `feedback_correct_defects_as_found.md`: when an audit surfaces a the working notes req #4 defect with clear spec text and a mechanical fix path, fix it in the same session rather than queuing as a future candidate. This release sequence (audit → 2 defect corrections → same-session ship) exercises the rule.

### Known follow-ups (deferred to v0.10+)

Same-class audit found **78 conditional fields across all schemas** carrying `"optionality": "C"` with no `"condition"` string. The 4 we corrected in v0.9 are a subset; the remaining 74 silent never-fires require multi-session audit work (v2.3 / v2.3.1 PDF extraction + cross-segment / message-context DSL extensions for some). Scoping options in `NEXT_STEPS.md` "Conditional-without-condition audit" track.

## [0.8.0] — 2026-06-25

Ships the first AU profile narrowing that exercises subcomponent-granular value pinning and message-type-dispatched conditional gating, per **ADR-009** (Accepted 2026-06-25). The AU `ComponentValueSet` model gains two optional fields (`subcomponent: Int?` + `condition: String?`); the Validator reuses the v0.7 (ADR-008) `conditionTriggers` evaluator as the gating engine — no new parser, no new dispatch surface. Closes HL7au:000040 (MSH-12 Version ID Field Conformance Points) subrules .1, .2, .3, .4 verbatim against the AU ADRM-2021 spec pp. 445–446. 040.5 is receiver runtime behaviour, explicitly out of scope. **No public-API change** vs v0.7.0; v1.0 stability clock continues from v0.5.0. Tests: 423 (v0.7.0) → 435 across 26 suites.

Workflow improvement: macOS PDFKit-based spec-text extraction (`xcrun swift /tmp/extract.swift`) cleared the previously-deferred "no pdftotext" gate that was blocking spec-audit § citation work. Memory file `reference_pdf_extraction.md` documents the recipe for future sessions.

### Added — v0.8-S1: ComponentValueSet model extensions

`ComponentValueSet` gains two optional fields, both defaulting to `nil` (full backwards-compatibility with v0.5–v0.7 overrides):

- **`subcomponent: Int?`** — When nil, reads the named component's FIRST subcomponent (v0.5-S5-C behaviour). When set, reads that named subcomponent. Required by HL7au:000040.1/.2 so MSH-12.2.1 = "AUS", MSH-12.2.2 = "Australia", MSH-12.2.3 = "ISO3166_1" can all be pinned independently.
- **`condition: String?`** — When nil, the check always applies on populated fields. When set, the check is gated through the v0.7 `conditionTriggers` evaluator — if the predicate is false the value-set is skipped. Required by HL7au:000040.3/.4 to apply different VID-3 values per message-code class without duplicating the FieldOverride entry.

Explicit memberwise init with `nil` defaults for both new fields + `specCitation` lets every existing call site continue to compile via labeled arguments.

### Added — v0.8-S2: Validator dispatch wiring

`Validator.checkProfileFieldOverrides` plumbs `segment: Segment`, `segmentArrayIndex: Int` (0-based, matching the v0.7 evaluator convention), and `message: Message` so it can:

1. Evaluate per-ComponentValueSet `condition` via `conditionTriggers` before applying the value-set check. Unresolvable predicates fail safe per ADR-008 ("malformed schema must never make a previously-accepted message non-conformant").
2. Resolve the value-set's actual scalar by subcomponent when set, rather than defaulting to the first subcomponent.

Helper rename: `componentScalarValue(in:componentIndex:)` → `valueSetScalarValue(in:component:subcomponent:)`. The validator's legacy `segmentIndex: Int` parameter (which historically meant "1-based per-segment-ID occurrence") was renamed to `occurrence: Int` to unify naming with the v0.7 convention where `segmentIndex` is the 0-based array index.

### Added — v0.8-S3: HL7au:000040 MSH-12 Version ID conformance rules

Nine ComponentValueSet entries on the MSH-12 FieldOverride in `Profile+au_adrm_2021.swift` (mirrored verbatim in `Resources/profiles/au-adrm-2021/MSH.json` per ADR-007's hand-curated sync):

- **040.1/.2** (Senders Orders/Results/Referrals/ACK/RRI): MSH-12.1 = "2.4"; MSH-12.2.1 = "AUS"; MSH-12.2.2 = "Australia"; MSH-12.2.3 = "ISO3166_1".
- **040.3** (Senders Orders/Results, gated on `messageCode in (ORM, ORU)`): MSH-12.3.1 = "HL7AU-OO-201701"; MSH-12.3.3 = "L".
- **040.4** (Senders Referrals/RRI, gated on `messageCode in (REF, RRI)`): MSH-12.3.1 ∈ {"HL7AU-OO-REF-SIMPLIFIED-201706", "HL7AU-OO-REF-SIMPLIFIED-201706-L1"}; MSH-12.3.3 = "L".

Fixture audit folded into S3: one inline AU-locale test wire (`mshFullyAUCompliant`) needed MSH-12 updated from "2.5.1" to the AU-conformant form; the broader `Tests/Fixtures/` corpus is `.international` and unaffected. 10 new validator-level pins cover positive/negative/gating/dispatch-exclusivity across all four subrules.

### Added — v0.8-S3b: Polish — gating + literal-pin completeness

Post-review polish on the v0.8-S3 rules:

- **Gated 040.1/.2 by messageCode**: added `condition: "messageCode in (ORM, ORU, REF, RRI, ACK)"` to the four universal ComponentValueSet entries. The spec enumerates these five message-type categories; the prior universal-fire was a known misfire on out-of-scope message types (e.g. ADT^A01 with non-AU MSH-12 was spec-compliant under v2.5.1 but triggered the AU rule).
- **VID-3.2 literal-empty pin**: the spec literal `"HL7AU-OO-201701&&L"` (and `"...-201706&&L"`) carries an empty middle subcomponent. Two new ComponentValueSet entries pin `MSH-12.3.2 = [""]` on both 040.3 and 040.4 gated paths, closing the permissive over-acceptance gap.

Test changes: 4 ADT-based wires flipped to ORU/REF to keep the rule-firing tests valid under stricter gating. New `msh12UniversalSilentOnADT` pins the gating fix; new `msh12_040_3_VID3_2_MustBeEmpty` pins the literal-empty fix. JSON↔Swift sync maintained.

## [0.7.0] — 2026-06-24

Closes the three documented out-of-scope conditional rules from `docs/design/v2_5_1-spec-audit.md` §93–121 by extending the v0.4-S4 condition DSL per **ADR-008** (Accepted 2026-06-19). The DSL gains three new predicate categories — cross-segment field refs, message-context atoms (`messageCode` / `triggerEvent` / `messageStructure`), and bounded position atoms (`previousSegment(<ID>).<fieldref>`, `associatedSegment(<ID>).<fieldref>`) — evaluated against the full `Message` rather than a single `Segment`. Schema JSON surface unchanged; `"condition"` strings carry the new productions. **No public-API breakage** vs v0.6.0 — pure internal grammar enrichment behind the locked `HL7Locale` enum + `ValidationIssue` surfaces. Tests: 390 (v0.6.0) → 423 across 24 → 26 suites. The 3-month no-API-break v1.0 stability clock continues from v0.5.0.

### Added — v0.7-S1: Message helpers + Validator signature widening

Internal plumbing layer. `Message` gains five helpers: `messageCode` / `triggerEvent` / `messageStructure` (read MSH-9.1 / .2 / .3), `associatedSegment(_:fromIndex:)` (ORC-delimited group resolution), `previousSegment(_:beforeIndex:)` (nearest preceding segment of named ID). `Validator.checkConditional` signature widens to `(segment, segmentIndex, currentSegmentID, message)`; the segment index is plumbed through `validate()` → `checkSegment` → `conditionTriggers` → OR/AND/atom evaluators. Atom body unchanged in S1 (behaviour identical to v0.6.0). 12 new pins in `MessageCrossSegmentTests`. Test count 390 → 402.

### Added — v0.7-S2: predicate parser productions

Three new productions in the recursive-descent evaluator at `Validator.swift`:
- **Cross-segment field refs** — `<otherSegmentID>-<n>` resolves via `Message.associatedSegment`, replacing v0.6.0's silent `return false` guard.
- **Message-context atoms** — `messageCode`, `triggerEvent`, `messageStructure` evaluate against MSH-9.
- **Position atoms** — `previousSegment(<ID>).<fieldref>` and `associatedSegment(<ID>).<fieldref>`.

Atom evaluator refactored into a clean dispatch (`resolveReferent` → `applyPredicate`) with a `ResolvedReferent` value type. Fail-safe semantics tightened per ADR-008: an unresolvable peer / position returns `nil` from the resolver, atom evaluates `false` (vs the prior "treat absence as empty" behaviour, which would spuriously trigger `<peer>-<n> empty`). `Validator.conditionTriggers` raised from `private` to internal for test access via `@testable`; no public-API surface change. 16 new pins in `CrossSegmentDSLTests` (positive / negative / fail-safe per production + 1 compound + 1 v0.4-S4 regression). Test count 402 → 418.

### Added — v0.7-S3: v2.5.1 schema additions + fixture re-audit

Four conditions added to `Resources/schemas/v2.5.1/`:
- ORC-2 (Placer Order Number) → `"OBR-2 empty"` (§4.5.1.2 XOR).
- ORC-8 (Parent) → `"previousSegment(ORC).ORC-1 = PA"` (§4.5.3.29 parent-child).
- OBR-2 (Placer Order Number) → `"ORC-2 empty"` (symmetric XOR partner).
- OBR-25 (Result Status) → `"messageCode = ORU"` (§4.5.3.25 report-message guard).

Fixture corpus re-audit (same shape as v0.5-S5-D-2 when profileUsage first fired): 14 ORU^R01 fixtures previously omitted OBR-25 — every one gained `F` (Final results) appended to OBR, all still round-trip byte-perfectly. `oru_r01_with_z_segment.hl7` had a shorter OBR (ended at field 16 instead of 17 like its peers); fix uses 9 separators+F instead of 8. 4 new validator-level integration pins in `ConditionalFieldTests` (XOR fires both sides, XOR satisfied, OBR-25 silent on ADT, ORC-8 fires on child / silent on parent). Test count 418 → 422.

### Added — v0.7-S4: v2.4 mirror

Same four conditions mirrored onto `Resources/schemas/v2.4/{ORC,OBR}.json`. The involved fields exist in v2.4 with identical shapes (verified pre-edit). `oru_r01_v24.hl7` fixture audited: OBR-25 = F appended (OBR previously ended at field 4). 1 new validator-level pin in `MultiVersionTests` exercising all three productions through the v2.4 grammar dispatch. Test count 422 → 423.

Caveat: full verbatim v2.4 § citation extraction is deferred (pdftotext unavailable on dev box; the v2_3-v2_4-spec-audit.md doesn't yet include CH04 chapter audit detail). The conditions propagate from the v2.5.1 audit, which captures HL7's stable ordering semantics that v2.4 inherits identically. A future audit pass will add verbatim citations to `v2_3-v2_4-spec-audit.md`.

## [0.6.0] — 2026-06-19

v0.6 cycle opener. Closes the per-version T-track grammar gap from v0.4's audit: v2.4 wires using EVN / MSA / ERR / PD1 / DG1 / IN1 now get per-field validation against the actual v2.4 spec shape, not "unknown segment". Per the project's "feature-complete over AU-specific" + "integrator primary-reference tool" requirements, every v2.4-vs-v2.5.1 divergence (ERR collapse to 1 field, DG1 truncation at 19, MSA-5 retype) is preserved verbatim from the v2.4 spec PDFs (chs 2, 3, 6) rather than transposed from v2.5.1. **No public-API breakage** vs v0.5.0 — pure grammar-table enrichment. Tests: 390 (v0.5.0) → 390 across 24 suites. The 3-month no-API-break v1.0 stability clock continues from v0.5.0.

### Added — v0.6-T-back-port: v2.4 grammar for the T-track segments

Closes the per-version coverage gap documented in `docs/design/v2_3-v2_4-spec-audit.md`: the six T-track segments (EVN, MSA, ERR, PD1, DG1, IN1) previously only had v2.5.1 grammar tables. v2.4 wires using these segments fell through to "unknown segment" rather than getting per-field validation.

- **6 new v2.4 schemas** authored under `Resources/schemas/v2.4/`:
  - `EVN.json` — 7 fields, EVN-2 (Recorded Date/Time) is R. Identical shape to v2.5.1.
  - `MSA.json` — 6 fields. v2.4 difference vs v2.5.1: MSA-5 (Delayed Acknowledgment Type) is `ID, B` in v2.4 vs `ST, X` in v2.5.1.
  - `ERR.json` — **1 field only** (ERR-1 CM Error Code and Location). v2.5+ redesigned ERR to 12 fields; v2.4 had only the CM composite.
  - `PD1.json` — 21 fields. Identical to v2.5.1.
  - `DG1.json` — **19 fields** (no DG1-20 Diagnosis Identifier or DG1-21 Diagnosis Action Code — those were added in v2.5+).
  - `IN1.json` — 25 fields (billing-essentials subset). Identical to v2.5.1.

- **Codegen** picks up automatically: the per-version `SegmentGrammarTable.v2_4` now publishes all 15 segments (was 9). Typed segment structs are version-agnostic and unchanged.

- **MultiVersionTests** pin updated to cover the new 6: EVN=7, MSA=6, ERR=1, PD1=21, DG1=19, IN1=25.

- Tests: 390 → 390 across 24 suites green. No new tests required — the existing grammar-table pin assertions caught all back-port shape decisions.

- All field counts and optionalities authored from the v2.4 spec PDFs (chapters 2, 3, 6) — not transposed from v2.5.1. Per the project's "feature-complete over AU-specific" + "integrator primary-reference tool" requirements, every divergence from v2.5.1 (ERR collapse, DG1 truncation, MSA-5 `(B) → X` retype) is preserved verbatim from the source spec text.

## [0.5.0] — 2026-06-18

v0.5 cycle release. AU profile constraint overlay substrate now substantively complete for the same-segment / same-datatype subset of HL7 Australia's ADRM-2021 conformance profile. **29 AU conformance rules** firing under `.auLocalisation` across 6 narrowing axes (field required-components, field required-presence, field per-component value-set, composite required-components, composite pair-conditional, grammar extension). All cited verbatim to HL7au identifiers via `.profileConstraintViolation(localeRule:)`. Base-spec behaviour under `.international` is unchanged. The additive-errors invariant (`auLocaleAddsButDoesNotRemoveBaseSpecErrors`) is enforced as a fixture-corpus pin. **No public-API breakage** vs v0.4.0 — all v0.5 work is internal overlay enrichment behind the locked `HL7Locale` enum + `ValidationIssue.code.profileConstraintViolation(localeRule:)` surfaces. Tests: 360 (v0.4.0) → 390 across 23 → 24 suites. The 3-month no-API-break v1.0 stability clock restarts from this tag per Migration.md.

### Added — v0.5-S5-D-2: profileUsage dispatch (closes "must be populated under AU" gap)

Closes the documented S5-C scope gap: under `.auLocalisation`, MSH-17 (`HL7au:000041`) and MSH-19 (`HL7au:000042`) must be populated — not just match a value-set when populated. The S5-C check fired only on populated-but-wrong values; this substage adds presence enforcement via `FieldOverride.profileUsage`.

- **`Validator.checkProfileFieldUsage`** (new): for every field in the segment grammar, when a profile is loaded and the matching `FieldOverride` declares `profileUsage = .required` and the field is empty, emit `.profileConstraintViolation(localeRule:)` with the override's spec citation. `.requiredEmpty` (RE) treated as informational (no fire on empty per the spec's RE semantic); `.notUsed` (X) handled by the existing base `checkDeprecation`; other usage codes don't drive a presence rule.
- **AU profile updated**: MSH-17 and MSH-19 FieldOverrides now carry `profileUsage = .required`. JSON overlay file (`Resources/profiles/au-adrm-2021/MSH.json`) and Swift mirror in sync.
- **Tests updated**:
  - `LocaleTests.auLocaleEmitsNoProfileViolationsOnPIDOnlyMessage` renamed and refocused — now pins "no OBR/ORC AU rules fire on PID-only wire" (filters out MSH violations which now legitimately fire under profileUsage).
  - `LocaleAUProfileTests.mshValueSetRulesConditionalOnPopulated` (the S5-C scope-limit pin) replaced with `mshProfileRequiredFiresOnEmpty` + `internationalLocaleSilentOnEmptyMSH`. New invariant: empty MSH-17 / MSH-19 now fire `profileConstraintViolation` per the profileUsage track.

- 389 → 390 tests across 24 suites green.

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
