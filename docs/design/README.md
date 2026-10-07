# docs/design — record index

**Created:** 2026-08-27 (post-remediation consolidation). One line per record: what it is and
whether it is *living* (kept current), a *point-in-time record* (never rewritten; corrected only
by dated addenda/annotations, per the archive convention), or *closed*.

Reading order for a cold start: `STATUS.md` → `NEXT_STEPS.md` → this index → the record you need.

A record here that cites a local plan or review means the maintainer's planning notes, which are not in the repository.

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

## Architecture decisions

| Record | Status |
|---|---|
| `architecture-decisions.md` | **Living.** ADR-001 to ADR-021 in one document, each decision stated as it stands, with condensed **Amended** / **Superseded** notes naming the task tag. Each section keeps its number as a stable heading and anchor (`#adr-019-message-structure-grammar`). |
| `../archive/adr/` | **Archive.** The 21 original ADR files with their dated amendments, evidence and run logs, moved unchanged. A citation of a dated ADR amendment (for example "ADR-019 amendment 2026-10-06") resolves there. |

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

- Point-in-time records are never rewritten: corrections are dated addenda (the archived ADRs), inline
  `> As-built` annotations (the Spec), or header delta notes (registers).
- Living docs carry their own update triggers (per-batch audits, per-stage status lines).
- Historical STATUS/NEXT_STEPS snapshots live in `docs/archive/`, not here.
