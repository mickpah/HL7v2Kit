# Sprint plan — close all coverage gaps on v2.3 / v2.3.1 / v2.4 / v2.5.1

**Created:** 2026-08-23. Scope: the **AU-priority tiers** of ROADMAP M5 — every HL7 version
**below v2.6**. v2.6 / v2.8.2 are out of scope here and enumerated in
`docs/design/deferred-coverage-backlog.md`.

**Goal:** v2.3, v2.3.1, v2.4 and v2.5.1 reach **full segment coverage at full per-version
field depth**, verified by presence *and* depth audits, with every conditional either shipped
as a predicate or recorded as a spec-cited limitation.

> **Release-label note (2026-08-27):** the per-sprint labels below (v1.10 → v1.15) are **cycle
> names**, planned before remediation R10 landed the breaking v2.0.0 capstone on `main`. The
> sprints themselves are unchanged, but their releases ship on the **2.x line** (Sprint 0 is the
> first coverage cycle after the `v2.0.0` cut). See ROADMAP → R and STATUS.

## Measured scope

**131 schema-instances / ~1,054 fields / 47 distinct segments**, across 10 chapters. Field
counts are max-field-index upper bounds (withdrawn/reserved positions included). Segment
discovery is caption-based, so counts are a floor.

| Chapter | Segments | Inst. | Fields |
|---|---|---|---|
| CH2 control / envelope | ADD BHS BTS DSC DSP EQL ERQ FHS FTS OVR SFT URD URS VTQ | 46 | ~265 |
| CH8 master files | CM0 CM1 CM2 PRA STF | 20 | ~231 |
| CH4 orders | BLG IPC ODS ODT RQ1 RQD | 21 | ~118 |
| CH14 app management | NCK NSC NST | 9 | ~118 |
| CH15 personnel | AFF CER EDU LAN ORG | 9 | ~90 |
| CH3 patient admin | IAM NPU PDA | 8 | ~66 |
| CH7 observations | FAC | 4 | ~48 |
| CH13 lab automation | EQP EQU INV SAC TCC TCD | 6 | ~94 |
| CH5 queries | QRI SPR | 4 | ~14 |
| CH6 financial | BLC RMI | 4 | ~10 |
| **Total** | **47** | **131** | **~1,054** |

Sprint sizing is calibrated on proven throughput: v1.7 = 24 instances, v1.9 = 48, v1.8 = 54,
each one cycle.

---

## Sprint 0 (v1.10) — defect + audit blind spot

**6 instances / ~94 fields.** Small, but it goes first because it is a **defect on the
AU-critical version** and because the tooling gap hid it.

1. **Fix the v2.4 lab-automation presence gap.** v1.4 authored `EQU/SAC/INV/TCC/TCD/EQP` as
   "v2.5+", but the **v2.4 CH13 PDF contains all six attribute tables** (captions verified
   2026-08-23). Author all six on v2.4 at that version's own depth.
2. **Add a presence predicate to `scripts/audit-schemas.py`.** The depth pass only inspects
   schemas that **exist**, so it is structurally blind to an absent segment — which is why
   this survived three consecutive "fully clean" audits. Extract-and-diff per version;
   report missing segments alongside depth findings.
3. Re-run the extended audit across all six versions and record the true baseline.

**Done when:** the presence audit reports zero unexplained gaps on v2.4 for already-modelled
segments, and the tool would have caught this class.

**Status: ✅ landed 2026-08-28 (items 1–3).** Predicate written first and run red: exactly
`PRESENCE v2.4 {EQP,EQU,INV,SAC,TCC,TCD}`, nothing else — the tool catches this class. Then
the six authored from the v2.4 CH13 tables (`--emit-schema` seed → PDF check → `--verify`
PASS ×6); INV is **18** on v2.4, SAC-6/TCC-3 `CM`/`O` (v2.5.1 `SPS`/`C`,`B`), SAC-27/43 `CE`,
INV-14 `O`, SAC-22 "Available Volume", SAC-43 "Special Handling Considerations" — all pinned.
True baseline: 590 schemas, depth 584 exact / 0 / 0, presence 0; never-authored by caption
v2.3 24, v2.3.1 27, v2.4 37, v2.5.1 41, v2.6 61, v2.8.2 73 = **263** (the 2026-08-23 count
above was a floor by 6). Suite 514 → 515. The v2.4 chapter sweep continues under this sprint
(NEXT_STEPS Sprint 0 §3).

**§3 batch A — CH15 personnel ✅ 2026-08-28.** `STF/PRA/ORG/AFF/LAN/EDU` on v2.4 **and**
v2.5.1 (structs come from the canonical version only, so the AU version alone would be grammar
without accessors), plus `STF/PRA` on v2.3/v2.3.1 — 16 schemas → 115 typed. This sets the
§3 rule: **a segment lands on every AU-priority version it exists in, in one batch**; the
presence predicate flags a split, and v2.6/v2.8.2 absences of modelled segments are its
*deferred* class (listed, not failed — `DEFERRED_VERSIONS` in `audit-schemas.py`). Sprint 2's
CH15 scope is therefore already done for these six.

**§3 batch B — CH04 orders ✅ 2026-08-28.** `BLG/ODS/ODT/RQ1/RQD` on all four AU-priority
versions (20 schemas, `--verify` PASS ×20) → 120 typed. Closes Sprint 3's CH04 line and the
`BLG` loose end. Divergences pinned (BLG depth/DT, RQ1-2 name drift). `CER` is v2.5+ — the Sprint 2 CH15 list above is wrong for
v2.4. Found and fixed on the way: the extractor's `1-n` run-on bound BHS's rows under `ADD` on
every version (`BHS` was invisible to the presence audit; Sprint 1's "no schemas exist for
FHS/BHS/BTS/FTS" was true, but the tool could not have said so). Two v2.4 EDU spec-text
defects normalised (`segment-coverage-extraction.md` → "Spec-text defects"). Suite 515 → 516.

---

## Sprint 1 (v1.11) — CH2 control / envelope

**46 instances / ~265 fields / 14 segments.** The largest chapter and the highest-value one.

**Lead with the batch envelope — `FHS/BHS/BTS/FTS`.** `BatchParser` and
`StreamingBatchParser` already *frame* these (v0.3-T2), but **no schemas exist for them**, so
they parse with no grammar, no typed accessors and no validation. Every batch consumer
touches them. This is a coherence gap between the parser and the schema layer, not just
missing coverage.

Then, in two passes for reviewability:
- **Continuation / control:** `ADD`, `DSC`, `OVR`, `SFT`, `DSP`.
- **Query-adjacent:** `EQL`, `ERQ`, `URD`, `URS`, `VTQ`.

**Watch for:** `ADD-1` is a **`1-n` variable-column** row like RDT-1 — the extractor cannot
parse it, so hand-author and whitelist it in the depth audit (see
`segment-coverage-extraction.md`). The query-adjacent set is v2.3-era and may be `B`/`W` in
v2.5.1 — take optionality from each version's own table.

---

## Sprint 2 (v1.12) — CH8 master files + CH15 personnel

**29 instances / ~321 fields / 10 segments.** Highest field count of any sprint; `STF` alone
is large.

- **CH8:** `STF`, `PRA`, `CM0`, `CM1`, `CM2`.
- **CH15:** `AFF`, `CER`, `EDU`, `LAN`, `ORG`.

Grouped because they are one domain — staff/practitioner master files. Note `STF`/`PRA`
migrate chapter between versions (CH8 in the v2.3 era, CH15 later), so **source each version
from the chapter that version actually puts it in**; the v1.5 RDT lesson (defined in CH2, not
CH05) applies directly.

**Watch for:** `CM0/CM1/CM2` are clinical-study master files and likely carry conditionals
tied to the CSR/CSP family already modelled in v1.8 — check whether predicates are expressible
before defaulting to the limitation register.

---

## Sprint 3 (v1.13) — CH4 orders + CH5 queries + CH6 financial

**29 instances / ~142 fields / 10 segments.** Field-light, so a good sprint to absorb the
`1-n`/legacy-layout awkwardness.

- **CH4:** `BLG`, `IPC`, `ODS`, `ODT`, `RQ1`, `RQD` — `BLG` is the financial segment
  deliberately excluded from v1.9 because it lives in CH04, not CH06.
- **CH5:** `QRI`, `SPR` — **`SPR` is the segment whose table was wrongly committed as RDT
  before v1.5-S1.** Authoring it properly closes that loop; verify against the real caption.
- **CH6:** `BLC`, `RMI`.

---

## Sprint 4 (v1.14) — CH3 + CH7 + CH14

**21 instances / ~232 fields / 7 segments.**

- **CH14 app management:** `NCK`, `NSC`, `NST` — absent from v2.3, present v2.3.1+.
- **CH3:** `IAM`, `NPU`, `PDA` — `IAM` (allergy) is AU-relevant for ADT traffic.
- **CH7:** `FAC`.

---

## Sprint 5 (v1.15) — closure and verification

No new segments. This sprint exists so "complete" is a measured claim, not an assumption.

1. **Full presence + depth audit** across v2.3 / v2.3.1 / v2.4 / v2.5.1 → expect **zero**
   gaps, zero suspects, with only documented whitelists (RDT, ADD).
2. **Conditional-completeness sweep** over every segment added in Sprints 0–4: each `C` field
   either ships a spec-cited predicate or joins
   `conditional-completeness-audit.md`. Apply the v1.8 lessons — a field's condition may be
   stated in a **different field's** entry, and version prose must be located by **stable
   ITEM number**, not heading shape.
3. **Cross-check pin tests** for every new segment, asserting per-version depth *and* the
   datatype/name divergences (the v1.6 lesson: uniform-looking schemas hide renames).
4. **Update the coverage claim** in `README.md`, `STATUS.md` and DocC: v2.3–v2.5.1 complete;
   **v2.6 / v2.8.2 explicitly partial** (req #2).
5. **Kick off M6** — the ADRM-2021 AU localisation audit over its v2.4 base, now unblocked
   because v2.4 is complete.

---

## Sequencing rationale

| Sprint | Instances | Fields | Why here |
|---|---|---|---|
| 0 | 6 | ~94 | Defect on the AU-critical version + the audit blind spot that hid it |
| 1 | 46 | ~265 | Batch envelope is a parser/schema coherence gap; largest chapter |
| 2 | 29 | ~321 | One coherent domain; heaviest field count |
| 3 | 29 | ~142 | Field-light; closes the `BLG` and `SPR` loose ends |
| 4 | 21 | ~232 | Remaining scattered chapters |
| 5 | 0 | — | Verification, conditionals, honest coverage claims, M6 unblock |

## Per-sprint definition of done

Every sprint follows the established cycle, and none is "done" until all of it holds:

1. Schemas authored from **that version's own attribute table** — `DT`, `OPT`, `RP` **and**
   `name`, never copied from the canonical version.
2. **Golden `--verify` passes** for every new schema instance.
3. `bash scripts/regenerate-typed-segments.sh` → **no codegen drift**.
4. Cross-check **pin test** covering depth + per-version divergence.
5. `python3 scripts/audit-schemas.py --depth` (with the Sprint-0 presence predicate) →
   **clean**.
6. Full suite **green**; commit with `git commit -F`; STATUS / NEXT_STEPS / CHANGELOG synced.

## Risks

- **v2.3.1 is a single mega-PDF.** Chapter attribution is unavailable there and extraction is
  slower; two v1.6 false negatives came from hyphenation in that file. Verify v2.3.1 findings
  by **item number**, not heading.
- **Legacy layouts.** v2.3-era tables have caused three separate extractor fixes (SEQ
  detection, `R/O/C` headers, singular `attribute` captions). Expect at least one more; treat
  a shallow extraction as a tool failure, never a depth answer.
- **`1-n` segments.** `ADD-1` needs hand-authoring plus an audit whitelist.
- **Chapter migration.** `STF`/`PRA` move between CH8 and CH15 across versions — sourcing
  from the wrong chapter is exactly how the pre-v1.5 RDT defect happened.
- **Estimates are upper bounds.** ~1,054 fields counts withdrawn/reserved positions, which
  are cheap to author. Real effort skews lower; segment counts skew higher (caption-based
  discovery is a floor).
