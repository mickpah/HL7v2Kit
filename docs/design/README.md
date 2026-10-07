# docs/design — record index

**Created:** 2026-08-27 (post-remediation consolidation). One line per record: what it is and
whether it is *living* (kept current), a *point-in-time record* (never rewritten; corrected only
by dated addenda/annotations, per the archive convention), or *closed*.

Reading order for a cold start: `STATUS.md` → `NEXT_STEPS.md` → this index → the record you need.

A path under `planning/` in any record here names the local planning folder, which is not in the repository.

## Project requirements

The records below cite these as "project requirement #1" to "#4". They were first kept in the
maintainer's local working notes, which are not in the repository; this section is their public home.

1. **Feature-complete over AU-specific.** The package implements the full HL7 v2.x standard, not
   the subset Australian traffic uses. "AU traffic does not trigger this case" does not excuse a gap.
2. **Integrator primary-reference tool.** Schemas, predicates and composite metadata must be
   defensible against the HL7 v2 text alone, not against test fixtures or vendor practice.
3. **Honesty over completeness when the model cannot express something.** Extend the model so the
   standard is represented faithfully; where that is out of scope, register the gap as a known
   limitation that blocks spec-completeness.
4. **No predicate ships if it is known to be incorrect.** A condition, required-component rule or
   grammar rule that misfires in any spec-compliant scenario is a defect: fix it, remove it, or
   change the model so it can be expressed correctly.

## Founding design

| Record | Status |
|---|---|
| `HL7v2Kit-Spec.md` | **Point-in-time** (v0.1, pre-implementation). Retained as-written with inline `> As-built` annotations at the spots that diverged (package tree, §4 API sketches, §8 dictionaries). Current API truth: `public-api-surface.md` + `Migration.md`. |

## ADRs (all point-in-time; corrections land as dated addenda)

| ADR | Decision | Current status |
|---|---|---|
| 001 — AST model | Field/Repetition/Component/Subcomponent hierarchy | Implemented, unchanged |
| 002 — error strategy | Enums with associated values, location-carrying | Implemented; addendum: `malformedField` (never raised) removed at 2.0 |
| 003 — Z-segment policy | Tolerant parse, validator-policy surfacing | Implemented; ADR-018 amendment: only `Z`-prefixed IDs enter the Z-segment branch; other IDs with no grammar entry are `segmentNotInVersionGrammar` (warning) |
| 004 — codegen over macros | Generation instead of Swift macros | Implemented, unchanged (drift CI enforces) |
| 005 — dictionaries strategy | Path C: codegen-emitted grammar tables | Implemented; addendum: the placeholder `HL7v2KitDictionaries` target retired at 2.0 |
| 006 — portable core boundary | Foundation-free kernel files, marked | In force (header marker; one-shot script retired R6) |
| 007 — AU profile architecture | Swift-source profile, JSON codegen deferred | Implemented; v0.14 note (JSON files retired) + addendum: `ProfileLoader` folded into `Profile.load(for:)` (R4) |
| 008 — cross-segment DSL | Peer refs, fail-safe semantics | Implemented, semantics unchanged (referent parsing shares `Path` since R4 — see ADR-010 addendum) |
| 009 — componentValueSet extensions | Conditional value-sets, subcomponent reads | Implemented, unchanged |
| 010 — DSL extensions (peer-absent / quantification / content-gated) | + Ext 2 group cardinality, Ext 3 fieldref suffix | Implemented; addendum: Ext 2's empty schema-side encoding axis removed (R2), Ext 3 parsing routed through `Path` (R4) |
| 011 — composite inequality + value-conditional rules | 44.4.8 / 44.4.4 rule types | Implemented, unchanged |
| 012 — v2.6 grammar version | S1 control/notes scope | Implemented; segment coverage beyond S1 deferred at the time, completed in M5 (v3.1.0; backlog register closed) |
| 013 — v2.8.2 grammar version | `.v2_8_2` distinct from `.v2_8` | Implemented; addendum (ADR-018): a `.v2_8` message is validated against the v2.8.2 grammar (the public registries stay version-literal) |
| 014 — API evolution policy | Additive-only 1.x; breaking waits for 2.0 | In force; addendum: the 2.0 lane was exercised at R10 (2026-08-27) — additive-only resumes for 2.x |
| 015 — segment-coverage extraction pipeline | pdftotext-based authoring/audit pipeline | In force (method doc: `segment-coverage-extraction.md`) |
| 016 — code-table registry | per-version generated HL7 tables, closed-set enforcement for ID fields, locale axis | In force |
| 017 — datatype component grammar | per-version component tables (printed on v2.5.1 and later; read from the prose on v2.3 to v2.4, M13 addendum), code-table check on ID components | In force |
| 018 — supported version set | Seven modelled versions (v2.7.1 added by the P10-6 amendment); `2.8` validated as v2.8.2 and `2.7` as v2.7.1 (info); VID.1 names the version; any populated MSH-12 with no resolvable version warns (throws under `rejectUnknownVersion`); excluded versions in the permanent-limitations register §F | In force (P3; amended P10-6) |
| 019 — message structures | Abstract message syntax per version: hybrid source (extracted prints plus cited overrides), greedy matcher with a determinism lint, HL7 v2.xml group names; `messageStructureSeverity` | In force (gate G2; P8 pilot, P8b rollout complete on all seven versions; dated amendments, exact matcher for lint-failing structures under G15); residual rows in the permanent-limitations register section E |
| 020 — composite views and version-union accessors | Composite views generated to full spec depth on every version; typed segment accessors over the union of versions | In force (gate G3, Option B; P10-3 amendment: a released struct's union base never changes); residual in register section H |
| 021 — full-predicate conditions | Three-state condition evaluator (Kleene AND/OR; two-state = "true"); per-field `conditionIsPredicate` marking; AU HL7au:00060.4 route C on definitely-false marked conditions | In force (P4-31); 00060.4 SHIPPED (owner rulings G6, G9): OBX-2 the one marked field, the other 51 candidates carry no derivable prohibition |

## Conformance registers (point-in-time; guard-tested where noted)

| Record | Status |
|---|---|
| `permanent-limitations-register.md` | **In force** (M2 close-out; guard test keeps the conditional set honest) |
| `conditional-completeness-audit.md` | **In force** (M2 register) |
| `public-api-surface.md` | **Point-in-time** (v1.0 boundary inventory) + 2.0-boundary delta note; fresh inventory belongs to a v2.0 gate if one runs |
| `full-segment-audit.md` | Point-in-time audit record |
| Spec audits: `v2_5_1-` / `v2_3-v2_4-` / `v2_6-` / `v2_7_1-` / `v2_8_2-spec-audit.md` | Point-in-time, per-version conformance findings feeding the predicates/limitations |

## Coverage programme (living until their exit criteria)

| Record | Status |
|---|---|
| `segment-inventory.md` | The 188-segment work-list (M5) |
| `segment-coverage-extraction.md` | **Living** method doc — audit predicates, per-version naming rules, extractor quirks (+ R6 tokenizer note) |
| `au-coverage-sprint-plan.md` | **Active runway** — Sprint 0 §1–§3 done (2026-08-28→09-02: presence predicate + 36 segments on every AU-priority version → 146 typed; per-batch status lines in the doc). §3 absorbed Sprints 1–4's authoring scope; next is the Sprint-5-style close-out, then v2.1.0 |
| `deferred-coverage-backlog.md` | **Open register** — the deferred v2.6/v2.8.2 scope, enumerated with re-measure commands |
| `m6-adrm-2021-localisation-audit.md` | **Active runway (M6)** — findings from the ADRM-2021 Appendix 5 diff: 1 defect (M6-D1), 31 shippable points (M6-A), 23 needing a model extension (M6-B) |
| `m6-adrm-2021-conformance-register.md` | **Generated** by `scripts/extract-adrm-conformance.py` — every ADRM-2021 conformance point classified against the shipped overlay. Do not hand-edit; regenerate |
| `p12-adrm-partial-points-audit.md` | **Audit (P12 S2-1, 2026-10-07)** — the 18 PARTIAL and 8 REGISTERED ADRM points re-read against the capabilities shipped since M6-B; verdict per point and the proposed S2-2 order |

## Remediation programme

| Record | Status |
|---|---|
| `remediation-plan.md` | **Closed** — R1–R10 all landed (2026-08-26/27) with per-stage status + evidence; register closed at the `v2.0.0` tag (2026-08-28) |

## Conventions

- Point-in-time records are never rewritten: corrections are dated addenda (ADRs), inline
  `> As-built` annotations (the Spec), or header delta notes (registers).
- Living docs carry their own update triggers (per-batch audits, per-stage status lines).
- Historical STATUS/NEXT_STEPS snapshots live in `docs/archive/`, not here.
