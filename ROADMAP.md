# HL7v2Kit — Roadmap

Longer-horizon version arc toward **v1.0**. Companion to the two live planning docs:

- **`STATUS.md`** — where the project is *right now* (read first).
- **`NEXT_STEPS.md`** — the *near-term* ordered task runway (the next cycle or two).
- **`ROADMAP.md`** (this file) — the *milestone arc*: themes and gates between today and v1.0, plus a post-1.0 sketch.

Three registers hang off the milestones and carry the enumerated detail this file only summarises:

- **`docs/design/au-coverage-sprint-plan.md`** — the six-sprint plan (v1.10 → v1.15) closing every gap on v2.3 / v2.3.1 / v2.4 / v2.5.1 (hangs off **M5**).
- **`docs/design/deferred-coverage-backlog.md`** — the deferred v2.6 / v2.8.2 scope, counted and named (hangs off **M5**).
- **`docs/design/remediation-plan.md`** — the 36-finding over-engineering register + R1–R10 TDD stages (hangs off **R**, the parallel track; R10 = the v2.0.0 boundary).

This file is intentionally higher-altitude than NEXT_STEPS. It records *direction and gates*, not per-stage tasks. Update it at each release boundary and whenever a milestone's scope materially shifts.

| | |
|---|---|
| Last updated | 2026-09-22 (M24 merged, unreleased; `v3.7.2` tagged earlier) |
| Current release | **`v3.7.2`** (2026-09-22) — docs only (M23), on top of `v3.7.1`: repeatability audited per version (M22), on top of `v3.7.0`: `requiredComponentSeverity` and the name audit (M20, M21), on top of `v3.6.5`: optionality audited per version, 30 fields corrected (M19), on top of `v3.6.4`: OBX-2 waveform value types fixed and the spec's example messages run through the Validator (M18), on top of `v3.6.3`: the spec's printed datatype examples as a standing audit, `NA.1` and Table 0528 `AHS` fixed (M17), on top of `v3.6.2`: HD's universal ID and type valued together and the spec's `RANDOM` example fixed (M16), on top of `v3.6.1`: three either-or component rules that rejected the spec's own examples removed (M15), on top of `v3.6.0`: required components now follow each version's printed component table (M14), on top of `v3.5.0`: code-table checks at field, component and subcomponent level on all six versions (the registry of `v3.3.0`, the component grammar of `v3.4.0`, extended to nested composites, OBX-5 and the prose-defined v2.3 to v2.4); the AU VMR sub-ID tree; AU locale renderings of Tables 0074 / 0125 / 0200 / 0203 / 0211 / 0301 / 0363. Additive under ADR-014. **188 typed segments, 853 schemas, six versions**; AU profile 104/104 accounted (66 shipped / 13 partial / 15 base / 10 registered), plus ADRM-prose rules P-1 to P-10. The public push has not happened. |
| Next planned cycle | **None scheduled.** Remaining gaps: `C` components and LEN. |
| Stability clock | The 1.x additive-only contract (ADR-014) **closed at R10** — the first exercise of the "waits for 2.0" lane — and **`v2.0.0` shipped it (2026-08-28)**. Additive-only is **in force again for the 2.x line** (see the ADR-014 addendum + `Migration.md` → "The 2.0 boundary"). |
| Guiding requirements | the working notes project requirements #1–#4 (feature-complete over AU-specific; integrator primary-reference tool; honesty over completeness; no known-incorrect predicate ships). **Sequencing** is AU-first as of 2026-08-23 (M5); **completeness** is unchanged — see `docs/design/deferred-coverage-backlog.md`. |

---

## Where we are (`v3.7.2`)

**Shipped and solid:**

- **Parsing / serialisation** — lossless round-trip; BOM/NUL hardening; MLLP codec (ADR-006); batch + streaming (`AsyncThrowingStream`) parsers.
- **Base-version grammar** — v2.3 / v2.3.1 / v2.4 / v2.5.1 / v2.6 / **v2.8.2** all present as first-class versions (the grammar-less `.v2_8` case aside): per-version field grammar, typed segments (15 at v1.0.0; **188 as of `v3.2.0`** — every segment the six specs define), typed composites (16), and per-version conditional rules. v2.6 added first-class in v0.14 (ADR-012, `W` optionality); v2.8.2 in v0.15 (ADR-013). **Version coverage spans v2.3 → v2.8.2** (the full published-standard set); **segment coverage within those versions is partial** — 109 typed, 263 schema-instances outstanding, AU-priority tiers first (M5). See `docs/design/v2_6-spec-audit.md` + `v2_8_2-spec-audit.md`.
- **Validation DSL** — same-segment compound predicates (v0.4-S4); cross-segment / message-context / position atoms (ADR-008); segment-presence atoms + subcomponent-granular field-refs + group-scope cardinality (ADR-010).
- **Locale / AU profile** — `HL7Locale.{international, auLocalisation}`; ADRM-2021 overlays for HL7au:000003–000008, 000040–000042, and the machine-checkable 00044 CE/CNE/CWE narrowings (ADR-009 + ADR-011). Compiler-checked Swift is the single source of truth (JSON overlays retired v0.13.1).
- **Docs discipline** — ADR-001…015 all Accepted + implemented; four spec-audit docs (v2_3-v2_4, v2_5_1, v2_6, v2_8_2) + the conditional-completeness register (v0.16); slim STATUS/NEXT_STEPS with archive snapshots at each boundary.

**Documented permanent limitations** (not defects — honesty per req #3/#4): the base-spec conditional-without-condition set (OBR-1/8/9/10/11/20/21/22/26/32, OBR-48, OBX-4/5/22, DG1-22) is the v0.16 M2 register (`docs/design/conditional-completeness-audit.md`); AU narrowings HL7au:00044.4.3 (CE text carve-out), 00044.4.7 (concept-match, needs terminology service), 00044.2 (PKI runtime), HL7au:000001 (receiver-runtime semantics).

---

## Milestones between here and v1.0

The four themes below are roughly independent and can interleave across cycles. Ordering within a theme is firm; ordering *between* themes is the project owner's call per cycle (see NEXT_STEPS for the next concrete pick).

### M1 — Version coverage completeness **(fully closed v0.15.0)**
*Goal: the base-spec surface an integrator expects is present, or its absence is a documented, defensible decision.*

- **Common-version set (v2.3 / v2.3.1 / v2.4 / v2.5.1 / v2.6)** — **DONE (v0.14, ADR-012).** See `docs/design/v2_6-spec-audit.md`.
- **v2.8.2 grammar table** — **DONE (v0.15, ADR-013).** `Version.v2_8_2` + 15 segments, all divergences (IS→CWE promotion, B→W withdrawals, O→B demotions, dropped/added conditionals, EI→EIP / ST→OG / ID→NM, field-count growth) verified against the v2.8.2 PDFs. The grammar-less `.v2_8` case retained (distinct MSH-12 raw value). No new `FieldOptionality` case needed. See `docs/design/v2_8_2-spec-audit.md`. **Coverage now spans v2.3 → v2.8.2 — the full published-standard set the reference targets.**
- **Curated-depth backlog (req #1 follow-on, not a v1.0 blocker):** **Canonical done (v0.19).** NK1 / PV1 / IN1 extended to full HL7 field depth on the **canonical v2.5.1** (39 / 52 / 53) — the typed-segment structs now expose the full accessor surface (`docs/design/full-segment-audit.md`). **Remaining:** the per-version grammar tables (v2.3 / v2.3.1 / v2.4 / v2.6 / v2.8.2) stay at curated depth (13 / 20 / 25) pending a follow-on sweep (which fights the legacy-PDF `RP/#` extraction). (Supersedes the v0.12 IN1-optionality carry-over note.)

### M2 — Conformance-surface finalisation **(closed v0.17.0)**
*Goal: every "C-with-no-condition" / partial / deferred rule is either shipped or recorded as a permanent limitation with a spec-cited rationale — so the schemas are trustworthy as a reference per req #2.*

- **Conditional-without-condition sweep** — **DONE (v0.16).** All 69 `C`-without-`condition` instances (17 positions) audited: PD1-15 + ORC-26 shipped; 15 documented. Register: `docs/design/conditional-completeness-audit.md`; a guard test keeps it honest.
- **AU narrowings + terminology/PKI/history gaps** — **DONE (v0.17).** Consolidated into `docs/design/permanent-limitations-register.md` (00044.4.3 carve-out, 00044.4.7 concept-match, 00044.2 PKI, 00044.1.2/.1.3, HL7au:000001; cross-cutting terminology / PKI / cross-message-history classes). Each spec-cited and freeze-decided.
- **Decision recorded:** all current limitations are spec-honest and **acceptable to freeze** for v1.0 — none blocks it. The two registers are the authoritative M2 gate; shipping any documented limitation as an unconditional rule would misfire (req #4). The terminology-service / PKI integrations that would unlock the semantic rules are explicitly **post-1.0** (out of the ADR-006 portable core).

### M3 — API stabilisation **(closed v0.18.0)**
*Goal: freeze a public surface we're willing to support indefinitely.*

- **Evolution policy** — **ADR-014 (Accepted).** Documented SemVer evolution contract; **no `@frozen`** (inert for this source SPM package). Enums classified **open** (`Version`, `HL7Locale`, `IssueCode`, `ParseError`, `PathError`, `BuilderError` — may gain cases in 1.x minors; `@unknown default`) vs **stable** (domain-closed). 1.x is additive-only; removals/renames/signature changes wait for 2.0.
- **Public-surface audit** — **DONE (v0.18).** `docs/design/public-api-surface.md`: 74 public types enumerated (59 hand-written + 15 codegen'd), each confirmed intended/minimal, every enum classified. The 6 open enums carry an `@unknown default` DocC note.
- **Migration guarantees** — **DONE (v0.18).** `Migration.md` finalised into the v1.0 contract (additive-only rule, open/stable lists, v0.5.0→v0.17 additive-case history).
- **v1.0 is the API-freeze boundary** (per Migration.md): after it ships, remaining gaps become permanent. **M1 + M2 + M3 are now all closed** — the only remaining v1.0 gate is M4 (external IP review).

### M4 — Distribution & open-source readiness **(all gates met; awaiting the owner's push)**
*Goal: the package is publishable and discoverable to the HL7 integrator community it's built for.*

- **IP review** — **CLEARED** (2026-07-09). The employment-contract gate passed; the *legal* blocker is gone.
- **The M5 gate is RELEASED** (M5 closed 2026-09-16) — every stated gate on the first public push is now met. What remains is the owner's action: name the remote, push. Remote target TBD (owner names host/repo).
- **Spec-PDF handling** — the `docs/standards/` Final Standard PDFs stay **out of the public tree** (author-local).
- **Distribution hygiene (remaining):** public CI workflow, SPM discoverability, DocC hosting, README badges.
- **Real-world fixture acquisition** — pipeline ready (`scripts/anonymise-fixture.sh` + the `HL7v2KitAnonymise` target); gated on the owner supplying source material (the IP review is cleared). No PHI ever enters the repo (the working notes).

### M5 — Full HL7 segment coverage across all versions **CLOSED (2026-09-16, owner-confirmed)**
*Goal (owner, 2026-07-09, req #1 strict): every HL7 segment modelled to full field depth on **every** supported version — not just the canonical v2.5.1 subset.*

- **Close-out:** the bar is met and measured — **188 typed segments, 853 schemas, zero
  never-authored and zero deferred instances on all six versions**; depth, presence and
  per-field dataType verified by `scripts/audit-schemas.py --depth` (all predicates zero).
  The v3 coverage cycles (2026-09-16) finished the v2.5-only quartet, the deferred
  v2.6/v2.8.2 batches A–C, and the never-authored backlog, with a codegen
  earliest-defining-version fallback for the 38 v2.6/v2.8.2-only segments. Formally
  confirmed closed by the owner 2026-09-16; released as **`v3.1.0`**. The public-push
  gate M5 held is released — the push itself remains the owner's action.
  *(The section below is the historical sweep narrative.)*

- **Bar (measured, v1.1-S5):** **188 distinct segments** across the 6 versions; **~850 schema-instances** at full depth. Today (post-Sprint 0 §3, 2026-09-02): **146 typed segments**; **never-authored: 0 on v2.3/v2.3.1/v2.4**, 4 on v2.5.1 (the v2.5-only set), 28/42 on the deferred v2.6/v2.8.2. **Depth *and presence* of the authored surface are verified, not assumed** (`scripts/audit-schemas.py --depth`, re-run every batch): 706 of 717 committed schemas match their own version's attribute table exactly, 0 suspects, presence 0 (whitelist: RDT + ADD `1-n`; v2.3.1/NSC).
- **Prerequisite — extraction pipeline (DONE, v1.1, ADR-015).** `pdftotext -layout` (poppler) recovers every attribute-table column cleanly on all 6 versions; the legacy-`RP/#` blocker is retired. Dev-time tool only (no new package dep). Its golden `--verify` caught **11 canonical v2.5.1 defects** (fixed) + **2 incomplete segments** (OBR 47→50, OBX 17→24, completed) — validating both the tool and the M5 premise. See `docs/design/segment-coverage-extraction.md`.
- **Segment inventory (DONE, v1.1, S5).** `docs/design/segment-inventory.md` — the 188-segment work-list + proposed sweep order.
- **Sweep (ongoing):** additive cycles (ADR-014 §open — add, never remove; API frozen), extractor-seeded (`--emit-schema`) + human-verified, by chapter/family.
  - **v1.2:** NK1/PV1/IN1 per-version full depth (closes the immediate gap) + 14 new typed segments (PV2/MRG/DB1/GT1/IN2/IN3 + TQ1/TQ2/RXO/RXR/RXC/RXE/RXD/RXG) full-depth on all versions → **29 typed segments**. Also an extractor legacy-CH4 reliability fix.
  - **v1.3:** 28 new segments — SPM/ROL + CH10 scheduling + blood-product/RXA, then master-files (MFI/MFE/MFA + OM1–OM7) + referral (RF1/AUT/PRD/CTD) → **57 typed segments**. Also an extractor legacy-`R/O/C`-header reliability fix.
  - **v1.4.0 (shipped):** query (CH05) + lab-automation (CH13) + master-file-locations/patient-care/med-records (CH08/CH12/CH09) → **85 typed segments**. Surfaced the extractor DT-accuracy issue that v1.5 then fixed.
  - **v1.5 (in v1.4.0):** extractor hardening + fidelity. Datatype-column assignment, row robustness, element-name prose bleed (lettered-chapter table ends, unbounded continuation folding, front-truncated centred names). RDT rebuilt in all 6 versions — v2.3/v2.3.1 had held the *SPR* segment's fields, RDT being defined in CH2 §2.24.19 there rather than CH05.
  - **v1.6 (in v1.4.0):** per-version depth audit — **46 never-authored fields** filled across 14 (version, segment) pairs, all on core segments (v2.3/v2.3.1/v2.4 MSH/PID/ORC/OBR/OBX/NTE + v2.5.1 OBX-25). Established that per-version element **names** and datatypes must come from each version's own table, never the canonical schema.
  - **v1.7 (merged, untagged):** CH13 clinical-lab-automation completion — ISD/NDS/CNS/ECD/ECR/SID, v2.4+ only (v2.3 / v2.3.1 have no CH13) → **91 typed segments**. Whole-SID conditionality documented (§13.4.11 marks all four fields `C` with no stated condition). Five further prose-bleed element names fixed, found by adding a name-**length** audit predicate that v1.5's marker-word regex had missed.
  - **v1.8 (merged, untagged):** CH07 completion — the product-experience family (PES/PEO/PCR/PDC/PSH) and the clinical-trials family (CSR/CSP/CSS/CTI), all nine present on **all six versions at identical depth** → **100 typed segments**. Because the depths are uniform, every divergence was in datatypes and element names. **Six conditional predicates shipped rather than documented** (CSR-9/10 → `triggerEvent = C01`; CSR-14/15/16 → `triggerEvent = C04`; CTI-2 → `CTI-3 populated`), leaving CSP-4 as the batch's only bare `C`. First fully clean audit of the programme.
  - **v1.9 (merged, untagged):** CH06 financial completion — FT1/PR1/ACC/UB1/UB2/DRG (all six versions) + ABS/GP1/GP2 (v2.4+) → **109 typed segments**. The mirror image of v1.8: here the **depths** carry the version signal and move sharply (FT1 25→43, PR1 15→25, ACC 6→13, DRG 11→**33** at v2.6), while UB1/UB2 stay static at 23/17. `PR1-19`/`PR1-20` shipped `triggerEvent = P12`, making this the **first batch to add no bare `C` at all** — the limitation register and its guard test were untouched. `BLG` is excluded: it is a financial segment but lives in CH04.
  - **v1.10+ (next):** the **~79 unmodelled segments** by chapter/family (CH16 eClaims IVC/PMT/ADJ/PYE/IPC (v2.6+), CH15 personnel STF/PRA/ORG/AFF/LAN/EDU/CER, CH17 materials, **`BLG` in CH04**, the long tail), re-running `scripts/audit-schemas.py --depth` each batch.

  **Method note (earned the hard way in v1.5/v1.6, reconfirmed in v1.7):** six prior sweep cycles authored depths that looked complete and were not — 46 missing fields on the most-used segments in the standard. Coverage counted in *segments* hides gaps counted in *fields*. v1.7 then showed the same for *fidelity*: a name-**length** predicate found five corrupted element names that a marker-word regex had walked past. So — audit with **shape** predicates rather than enumerated content lists, and run them every batch. Both audits are cheap once the extractor is compiled, and they are now a committed tool (`scripts/audit-schemas.py`) rather than an ad-hoc script.

  **v1.8 added two reading lessons.** A field's condition may be stated in a **different field's** entry — CTI-2's requirement is written in CTI-3's definition, which is the only reason it shipped a predicate instead of joining the limitation register. And version prose must be located by **stable ITEM number**, never by heading shape: the v2.3-era chapters number definitions `7.8.1.9 <Name> (TS) 01043` with no `SEG-N` prefix, so a `CSR-9`-shaped regex returns nothing — which reads as "no condition stated" when the condition is right there. Both mean the honest answer to "is this conditionality expressible?" is often **yes**, and finding out takes reading the neighbours.
- **This is what "v1.0 complete" now means, and it gates the first public push.**

#### Re-prioritisation (owner, 2026-08-23): AU-relevant versions first

The sweep is **re-sequenced**, not reduced. Remaining coverage was measured at **263
schema-instances / ~2,431 fields** and split by Australian relevance (Sprint 0 §3 — 2026-09-02 —
has since authored the entire AU-priority half; what remains is the v2.5-only quartet and the
deferred tier below):

| Tier | Versions | Remaining | Est. fields | Rationale |
|---|---|---|---|---|
| **1 — AU-critical** | **v2.4** | 42 instances | ~353 | The **ADRM-2021 localisation base** (`Profile.swift`: "AU ADRM-2021 is over v2.4"). Where the AU profile actually applies. |
| **2 — AU legacy, in-field** | **v2.3.1**, **v2.3** | 26 + 23 | ~224 + ~156 | AS 4700.x pathology/referral messaging; still live in AU deployments. |
| **3 — structurally required** | **v2.5.1** | 40 instances | ~321 | Not deferrable regardless of AU use: the **typed structs generate from canonical v2.5.1**, so it is load-bearing for the public API. |
| **Deferred** | v2.6, v2.8.2 | 132 instances | ~1,377 | Not used in AU clinical traffic. Enumerated in `docs/design/deferred-coverage-backlog.md`. |

**Execution plan for Tiers 1–3:** `docs/design/au-coverage-sprint-plan.md` — the 131
AU-priority instances broken into **six sprints, v1.10 → v1.15**, sized against proven
throughput (v1.7 = 24 instances, v1.9 = 48, v1.8 = 54, each one cycle):

| Sprint | Cycle | Inst. | Fields | Content |
|---|---|---|---|---|
| 0 | v1.10 | 6 | ~94 | v2.4 lab-automation presence **defect** + audit presence predicate |
| 1 | v1.11 | 46 | ~265 | CH2 control / envelope — leads on `FHS/BHS/BTS/FTS` |
| 2 | v1.12 | 29 | ~321 | CH8 master files + CH15 personnel |
| 3 | v1.13 | 29 | ~142 | CH4 orders + CH5 queries + CH6 financial |
| 4 | v1.14 | 21 | ~232 | CH3 + CH7 + CH14 |
| 5 | v1.15 | — | — | Closure: audits, conditionals, honest coverage claims, M6 unblock |

Two things set that order, and both are gaps the segment counts alone did not show:

- **Sprint 0 leads on a defect, not new work.** v2.4 is missing six already-modelled
  lab-automation segments, and `scripts/audit-schemas.py` could not see it — the depth pass
  only inspects schemas that **exist**, so an absent segment is invisible to it.
  *(2026-08-28: both fixed — the six authored, and the audit now runs a presence predicate.)*
- **Sprint 1 leads on the batch envelope.** `BatchParser` / `StreamingBatchParser` already
  *frame* `FHS/BHS/BTS/FTS` (v0.3-T2), but **no schemas exist** for them — they parse with no
  grammar, no typed accessors and no validation. That is a coherence gap between the parser
  and schema layers, and every batch consumer touches it.

Sprint 5 is deliberately empty of new segments: it is what makes "v2.3–v2.5.1 complete" a
**measured** claim rather than an assumption, and it is where the coverage statements in
README / STATUS / DocC get corrected to say v2.6 / v2.8.2 are partial.

**The tension this creates, stated plainly.** the working notes requirement #1 says
feature-completeness beats AU-specificity, and "AU traffic doesn't trigger this case" is not
a valid defence for a known gap. This decision does **not** retract that as the end state —
it changes **sequencing only**. Two guards keep the two compatible:

1. **The deferred scope is enumerated, not vague** — 132 instances, ~1,377 fields, 38
   segments named. A deferral you can count is a deferral you can finish.
2. **v2.6 / v2.8.2 must be described as *partial* everywhere coverage is claimed** (README,
   STATUS, DocC, any public statement). Requirement #2 makes that non-negotiable: an
   integrator must never mistake partial for complete.

If the intent ever hardens into "v2.6/v2.8.2 are out of scope permanently", that is a
different decision — it would need requirement #1 amended and the public-push gate redefined,
because it changes what the package *is*. This is not that.

### M6 — Australian localisation completeness **CLOSED (2026-09-16)**
*Goal: the AU localisation surface is complete and spec-cited against ADRM-2021 over its v2.4
base, so AU integrators can trust the profile as a faithful rendering of the localisation.*

- **Outcome:** Appendix 5 extracted into a re-runnable register (302 rows / 263 conformance
  points; one misparsed row repaired and shipped); at close, 74 of the 104 message-decidable
  rows accounted for. **The M6-B capability run (B-4..9, same date) then finished the job:
  ALL 104 rows accounted for — 65 shipped, 12 partial (unenforced half stated per row),
  15 base-model, 12 registered with citations; EXTEND 0, CANDIDATE 0.** Capabilities
  landed: `HL7CodeTables`, composite value sets, the MSH-12.3.1 L1/L2 profile gate,
  OBX-2-driven datatype resolution (M6-O7), correspondence maps, field uniqueness,
  relational cardinality, public-system precedence, TS timezone presence.
  `permanent-limitations-register.md` §D is drained.
- **Four defects found and fixed** (D1 citations, D3/D4 message-type gates, D5 the breaking
  OBX-5 datatype fix under the owner-directed ADR-014 override → next release is `v3.0.0`),
  plus the M6-O5 dataType audit predicate (13 further schema defects fixed) and five DSL
  extensions (maxCount, anyRepeat, startsWith, `Z*` counted prefix, `subcomponent`).
- **Standing caveat:** Appendix 5 is explicitly not exhaustive — the ADRM chapter-body
  prose sweep is separate, later work, and AU coverage is always cited as the measured
  number. Full narrative: `docs/design/m6-adrm-2021-localisation-audit.md` +
  `docs/archive/STATUS-2026-09-16-m6-closed.md`.

### M7 — ADRM prose sweep **CLOSED (2026-09-16; released in `v3.2.0`)**
*Goal: audit the ADRM text Appendix 5 explicitly does not cover — chapter-body prose and
the normative appendices — so no prose-only narrowing is invisible to the profile.*

- **Outcome:** the chapter bodies (319 normative hits → 263 candidates) and normative
  appendices 8–10 (63 candidates) fully swept and hand-triaged
  (`docs/design/m7-adrm-prose-sweep.md`; re-runnable via `scripts/sweep-adrm-prose.py`).
  **Seven prose-only narrowings shipped** as `ADRM-prose:P-1..P-7` rules (PID-1 required;
  the §7.4.2 REF disallowed segments; MSH-9 REF/RRI pins; the \X/\C/\M escape
  prohibitions via the new `EscapeProhibition` track; the ACK MSH-12.3.1 closed set;
  read-ack MSH-3.3 scheme; the VMR header OBX pins; single-batch-per-file landed with
  M8's `BatchValidator`). Every non-shippable finding registered with its reason.

### M8 — Base-spec consistency + batch scope **CLOSED (2026-09-17; released in `v3.2.0`)**
*Goal: the base-spec cross-segment rules and batch-envelope scope the message-scoped
Validator could not carry.*

- **Outcome:** the ORC/OBR paired-field equality family (items 00216/00217/00226/00222,
  incl. the v2.8.2 OBR-54 parent split; the TQ pair deliberately not shipped — advisory
  and withdrawn); the public `BatchValidator`/`BatchValidationReport` (upgrading the AU
  batch points: `000022.3` SHIPPED, `000022.1` PARTIAL — **final AU register 66/13/15/10,
  104/104, EXTEND 0**); and the numeric-`>` / `prohibitedWhen` conditional classes
  (PAC-2, PRT-6/7 — the bare-C guard set shrank by three). New `IssueCode` cases:
  `pairedFieldMismatch(item:)`, `conditionalFieldProhibited`.

### M9 — General per-version code-table registry **CLOSED (2026-09-20; ADR-016; released in `v3.3.0`)**
*Goal: every HL7 table the spec binds to a field is bound in the schema, available as per-version data with descriptions, and consumable by the validator — defensible against the spec text alone (req #2). Closes M6-O6.*

- **Outcome:** 2,565 per-version tables with descriptions, extracted from each version's own Appendix A / Chapter 2C and generated into `HL7TableRegistry`; schema keys `tables` (4,290 verified bindings) and `table` (1,893 enforced links); `valueNotInTable` on 1,073 `ID` fields over closed HL7-defined tables, never on IS or user-defined tables; a locale table axis carrying the five AU ADRM-2021 tables, which can widen a base table (0211 `UNICODE UTF-8`) and never narrows it. The same cycle landed **Track B**, the `variableColumns` model for the 1-n segments RDT / ADD.
- **Honesty points (req #3/#4):** a table that printed `...` beside other rows stays open unless explicitly closed; rows that denote an absent field are not codes; corrections are version-scoped, cited overrides, never hand edits. Two registered spec typos (v2.3 DB1-2 TBL# 0033 for 0334; v2.3 Appendix A Table 0207 in lowercase).
- **Deferred, registered:** table links on composite components and multi-table field bindings.

### M10 — Code tables on composite components **CLOSED (2026-09-20; ADR-017; released in `v3.4.0`)**
*Goal: the table bindings integrators ask about most live on components (`CX.5`, `XPN.7`, `XTN.2`), not fields. Model each version's datatype components and enforce their closed tables, under the same honesty rules as the field check.*

- **Outcome:** `Resources/datatypes/` (227 datatype files, 1,323 components) from the Chapter 2A component tables of v2.5.1 / v2.6 / v2.8.2; `DataTypeGrammarTable` generated from it; `valueNotInTable` on populated `ID` components over closed tables, located at the component. About 50 components per version.
- **Honesty points (req #3/#4):** Table 0354 opened on every version after measuring 15 to 25 chapter-used structures its table omits; four v3.3.0 registry defects found and fixed while vetting; `RE` kept as the printed optionality code instead of being mapped lossily.
- **M11 (2026-09-21, released in `v3.5.0`):** nested composites (`CX.4.3`, `IssueLocation.subcomponentIndex`) and OBX-5 under its OBX-2 datatype. **Still deferred:** v2.3 to v2.4 (prose-only component definitions) and multi-table cells.

### M12 — AU HL7v2 VMR sub-ID tree **CLOSED (2026-09-21; released in `v3.5.0`)**
*Goal: the one ADRM normative appendix whose rules the DSL could not carry: a template whose elements are OBX segments addressed by a dotted-decimal OBX-4 path.*

- **Outcome:** the 89-row implementation table of ADRM-2021 Appendix 9 as extracted, audited data; a `SubIDTreeRule` model track (req #3: extend the model); rules ADRM-prose P-8, P-9 and P-10, scoped per OBR group and rooted at whatever the header declares.
- **Honesty points (req #4):** the appendix's own examples are the must-pass test; the table's OBX-2 and OBX-3 columns are registered and not enforced because that example contradicts them; OCCURRENCES is registered because the appendix never says which repeats the VMR forbids.

### M13 — Component grammar for v2.3, v2.3.1 and v2.4 **CLOSED (2026-09-21; released in `v3.5.0`)**
*Goal: Australian traffic is v2.4, and the component check never fired for it, because those versions print no component tables.*

- **Outcome:** the component grammar of the three older versions recovered from their numbered prose subsections under a three-test evidence rule (one table named, present in the registry, stated name matching); 105 datatype files, 168 bound components, zero conflicts with v2.5.1's printed tables. The component check now runs on all six versions.
- **Honesty points (req #4):** the name test caught real v2.3 misprints that would have become wrong rules; a sweep of every closed table enforced on v2.4 against the ADRM's own print found two AU widenings (Tables 0125 and 0301), one of them a false error live since `v3.3.0`.

### M14 — Required components from the printed grammar **CLOSED (2026-09-21; released in `v3.6.0`)**
*Goal: use the component grammar to audit, then replace, the Validator's hand-written required-component lists.*

- **Outcome:** eight of eleven hand-written lists contradicted the v2.5.1 tables they cited; required components are now exactly those the message's own version prints `R`. False errors removed (`XAD.1`, `XPN.1`, ...); waived requirements enforced (`MSH-9.3` from v2.5; `CX.5`, `PT.1`, `VID.1`, `XTN.3` on v2.8.2). 48 fixtures corrected.
- **Honesty points:** the old `MSG` list waived the message structure as "often left empty" — the reasoning req #1 rules out; v2.3 to v2.4 get no component requirements because their prose prints none.

### M15 — The either-or component rules, held to the spec's examples **CLOSED (2026-09-21; released in `v3.6.1`)**
*Goal: finish the M14 audit for the five rules no table could check.*

- **Outcome:** `XTN`, `PL` and `CWE` rules removed — each rejected an example the spec prints; `EIP` removed as vacuous; `HD` kept, supported by the prose. The spec's examples are now must-pass tests.

### M16 — HD both-or-neither; the spec's HD examples as tests **CLOSED (2026-09-21; released in `v3.6.2`)**

- **Outcome:** the HD rule all six versions print ("must either both be valued ... or both be not valued") is enforced; and testing every HD example the section prints caught a false error live since `v3.5.0` (`Random` in the table, `RANDOM` in the example).

### M17 — The spec's printed examples as a standing audit **CLOSED (2026-09-21; released in `v3.6.3`)**

- **Outcome:** `audit-schemas.py --examples` checks all 352 composite examples of the six datatype chapters against the component rules, with three cited exceptions. Two more spec self-contradictions fixed (`NA.1`, Table 0528 `AHS`).

### M18 — The spec's example messages through the Validator **CLOSED (2026-09-21; released in `v3.6.4`)**

- **Outcome:** 616 printed messages validated end to end (gated suite, spec text kept out of the repository); Table 0125's missing waveform value types `NA` / `MA` / `CD` restored on v2.3 to v2.6; the rule for when an example may overturn a table written into ADR-017.

### M19 — Optionality audited per version **CLOSED (2026-09-21; released in `v3.6.5`)**

- **Outcome:** an `optionality` predicate in the depth audit; 30 of ~13,000 fields carried a later version's OPT (a false error on v2.3 `MSH-7`, 21 false deprecation warnings, seven too-lenient v2.6 fields), all corrected from their own version's table.

### M20 — Names audited per version **CLOSED (2026-09-22; released in `v3.7.0`)**

- **Outcome:** a `name` predicate in the depth audit; 110 left-truncated and 22 empty names (pharmacy segments), v2.3-era names copied from v2.5.1, and a missing v2.8.2 `ITM-33` all corrected from the print; three extractor layouts fixed.

### M21 — Required-component severity option **CLOSED (2026-09-22; released in `v3.7.0`)**

- **Outcome:** `ValidationOptions.requiredComponentSeverity`; the `MSH-9.3` question closed without special-casing a field. Additive API.

### M22 — Repeatability audited per version **CLOSED (2026-09-22; released in `v3.7.1`)**

- **Outcome:** an RP predicate in the depth audit; 19 fields corrected (14 false cardinality errors removed, five checks added); the extractor reads a Y under the TBL# header as the RP cell.

### M23 — Example-message required-field triage **CLOSED (2026-09-22; released in `v3.7.2`, docs only)**

- **Outcome:** all 106 required-field findings on version-consistent example messages traced to example damage; the report is fully triaged and the triage tool records the conclusion.

### M24 — v2.3 chapter-only tables; prose mentions closed **CLOSED (2026-09-22; merged, unreleased)**

- **Outcome:** Tables 0298 / 0299 / 0301 / 0336 added to the v2.3 registry from the chapters that print them (the only such gap on any version); `HD.3` checked on v2.3; all 39 rejected prose mentions read and found unbindable.

### R — Over-engineering remediation **(CLOSED 2026-08-28 — R1–R10 all landed; register closed at the `v2.0.0` tag)**

> **R10 landed the breaking capstone on `main` (owner-scheduled 2026-08-27) and `v2.0.0`
> shipped it (2026-08-28)**, folding the untagged v1.7–v1.9 merges + the R-track. The M5/M6
> sprint releases below (labelled v1.10–v1.15 when planned) ship as **v2.x** releases; the
> sprint-plan labels are cycle names, not tags. Delivered: ~1,300 net lines removed, two real
> defects found-and-fixed (batch MSH-18 detection; extractor cell-collapsing), C1–C3
> characterization tests, shared test infra, the dead-API removals + OBX-12/15 renames at 2.0.
*Goal: retire the ~1,400 lines of audited complexity debt — dead code, duplicated mechanics,
hand-rolled stdlib — without touching a line of spec surface.*

- **Source:** a four-agent over-engineering audit (2026-08-26) produced **36 verified findings**
  (0 spec surface; every claim grep-verified same day), staged as **R1–R10** with per-stage
  TDD protocols, pinning tests, and done-when criteria in
  `docs/design/remediation-plan.md`.
- **Not a gate.** R1–R9 are non-breaking, 1.x-safe, and sized one-stage-one-commit; they
  interleave with the M5/M6 sprints opportunistically (no overlap with schema/sprint files).
  M5 remains the sole public-push gate.
- **R10 is the v2.0.0 boundary** (owner decision, 2026-08-26): six dead public symbols ship
  their removal *as* the 2.0 release — SemVer-honest and costless pre-publication. The owner
  scheduled 2.0 ahead of the sprints (2026-08-27). The ADR-014-deferred renames
  (`effectiveDateOfReferenceRange` / `producersID`, OBX-12/OBX-15) ride the same boundary.
- **Characterization tests first** (C1–C3): the DSL-rejects-`[N]`/`~N` guard, exact validator
  messages across the 7 profile-issue sites, and BatchParser MSH-18 Latin-1 — real coverage
  gaps closed *before* the refactors they protect.

---

## v1.0 definition — reframed (owner, 2026-07-09)

> **v1.0 = frozen public API + spec-honest conformance surface + full HL7 segment coverage at complete depth across every supported version (v2.3–v2.8.2).**

Gate status:
1. M3 API stabilisation (v0.18, ADR-014).
2. M2 conformance surface (v0.16 + v0.17 registers).
3. M1 *version-set* coverage — the six versions are modelled (v0.14 / v0.15) **for the 15-segment set**.
4. M4 IP review cleared (legal gate).
5. **M5 full-coverage parity** — every segment × every version at full depth. **NOT met.** This is now the completeness bar and the public-push gate.

**`v1.0.0` is tagged on `private`** as the API-freeze marker. It is **provisional** until M5 is met — the first public push waits on full-coverage parity. Coverage growth ships as additive v1.1+.

---

## Post-1.0 sketch (not committed)

- **Second localisation profile** (UK / US / NZ) — would justify the deferred JSON-driven profile codegen (ADR-004 principle; ADR-007 v0.14 note). The composite-override + cardinality + DSL machinery is already locale-agnostic.
- **Terminology-service hook** — an optional, injected resolver would unlock the currently-unshippable semantic rules (44.4.7 concept-match, LOINC well-formedness beyond placement). Out of the portable-core boundary (ADR-006) — likely a separate module.
- **Performance track** — perf/fuzz suites are gated (`RUN_PERF_TESTS` / `RUN_FUZZ_TESTS`); promote to a measured baseline if large-batch throughput becomes a consumer concern.
- **AU Core Workbench** — the downstream macOS app (separate repo) is the primary consumer; its needs may surface new validation or ergonomics requirements.

---

## How this maps to the cycle cadence

- Each **minor** (`v0.X.0`) = one themed cycle (an ADR + its implementation, or a coherent coverage/audit sweep). Branch `v0.X-<slug>` → tag `v0.X.0`.
- **Patch** (`v0.X.1`) reserved for maintenance / hotfixes (e.g. v0.13.1 JSON retirement).
- **v1.0.0** = the API-freeze release once M1–M4 gates are satisfied (or M4 explicitly deferred).

*End of ROADMAP.md.*
