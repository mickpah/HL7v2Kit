# docs/design — record index

**Created:** 2026-08-27 (post-remediation consolidation). One line per record: what it is and
whether it is *living* (kept current), a *point-in-time record* (never rewritten; corrected only
by dated addenda/annotations, per the archive convention), or *closed*.

Reading order for a cold start: `STATUS.md` → `NEXT_STEPS.md` → this index → the record you need.

## Founding design

| Record | Status |
|---|---|
| `HL7v2Kit-Spec.md` | **Point-in-time** (v0.1, pre-implementation). Retained as-written with inline `> As-built` annotations at the spots that diverged (package tree, §4 API sketches, §8 dictionaries). Current API truth: `public-api-surface.md` + `Migration.md`. |

## ADRs (all point-in-time; corrections land as dated addenda)

| ADR | Decision | Current status |
|---|---|---|
| 001 — AST model | Field/Repetition/Component/Subcomponent hierarchy | Implemented, unchanged |
| 002 — error strategy | Enums with associated values, location-carrying | Implemented; addendum: `malformedField` (never raised) removed at 2.0 |
| 003 — Z-segment policy | Tolerant parse, validator-policy surfacing | Implemented, unchanged |
| 004 — codegen over macros | Generation instead of Swift macros | Implemented, unchanged (drift CI enforces) |
| 005 — dictionaries strategy | Path C: codegen-emitted grammar tables | Implemented; addendum: the placeholder `HL7v2KitDictionaries` target retired at 2.0 |
| 006 — portable core boundary | Foundation-free kernel files, marked | In force (header marker; one-shot script retired R6) |
| 007 — AU profile architecture | Swift-source profile, JSON codegen deferred | Implemented; v0.14 note (JSON files retired) + addendum: `ProfileLoader` folded into `Profile.load(for:)` (R4) |
| 008 — cross-segment DSL | Peer refs, fail-safe semantics | Implemented, semantics unchanged (referent parsing shares `Path` since R4 — see ADR-010 addendum) |
| 009 — componentValueSet extensions | Conditional value-sets, subcomponent reads | Implemented, unchanged |
| 010 — DSL extensions (peer-absent / quantification / content-gated) | + Ext 2 group cardinality, Ext 3 fieldref suffix | Implemented; addendum: Ext 2's empty schema-side encoding axis removed (R2), Ext 3 parsing routed through `Path` (R4) |
| 011 — composite inequality + value-conditional rules | 44.4.8 / 44.4.4 rule types | Implemented, unchanged |
| 012 — v2.6 grammar version | S1 control/notes scope | Implemented; segment coverage beyond S1 deferred (see backlog register) |
| 013 — v2.8.2 grammar version | Distinct from grammar-less `.v2_8` | Implemented, unchanged |
| 014 — API evolution policy | Additive-only 1.x; breaking waits for 2.0 | In force; addendum: the 2.0 lane was exercised at R10 (2026-08-27) — additive-only resumes for 2.x |
| 015 — segment-coverage extraction pipeline | pdftotext-based authoring/audit pipeline | In force (method doc: `segment-coverage-extraction.md`) |

## Conformance registers (point-in-time; guard-tested where noted)

| Record | Status |
|---|---|
| `permanent-limitations-register.md` | **In force** (M2 close-out; guard test keeps the conditional set honest) |
| `conditional-completeness-audit.md` | **In force** (M2 register) |
| `public-api-surface.md` | **Point-in-time** (v1.0 boundary inventory) + 2.0-boundary delta note; fresh inventory belongs to a v2.0 gate if one runs |
| `full-segment-audit.md` | Point-in-time audit record |
| Spec audits: `v2_5_1-` / `v2_3-v2_4-` / `v2_6-` / `v2_8_2-spec-audit.md` | Point-in-time, per-version conformance findings feeding the predicates/limitations |

## Coverage programme (living until their exit criteria)

| Record | Status |
|---|---|
| `segment-inventory.md` | The 188-segment work-list (M5) |
| `segment-coverage-extraction.md` | **Living** method doc — audit predicates, per-version naming rules, extractor quirks (+ R6 tokenizer note) |
| `au-coverage-sprint-plan.md` | **Active runway** — Sprint 0 §1–§3 ✅ (2026-08-28→09-02: presence predicate + 36 segments on every AU-priority version → 146 typed; per-batch status lines in the doc). §3 absorbed Sprints 1–4's authoring scope; next is the Sprint-5-style close-out, then v2.1.0 |
| `deferred-coverage-backlog.md` | **Open register** — the deferred v2.6/v2.8.2 scope, enumerated with re-measure commands |

## Remediation programme

| Record | Status |
|---|---|
| `remediation-plan.md` | **Closed** — R1–R10 all landed (2026-08-26/27) with per-stage status + evidence; register closed at the `v2.0.0` tag (2026-08-28) |

## Conventions

- Point-in-time records are never rewritten: corrections are dated addenda (ADRs), inline
  `> As-built` annotations (the Spec), or header delta notes (registers).
- Living docs carry their own update triggers (per-batch audits, per-stage status lines).
- Historical STATUS/NEXT_STEPS snapshots live in `docs/archive/`, not here.
