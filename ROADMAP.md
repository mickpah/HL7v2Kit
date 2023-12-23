# HL7v2Kit — Roadmap

Longer-horizon version arc toward **v1.0**. Companion to the two live planning docs:

- **`STATUS.md`** — where the project is *right now* (read first).
- **`NEXT_STEPS.md`** — the *near-term* ordered task runway (the next cycle or two).
- **`ROADMAP.md`** (this file) — the *milestone arc*: themes and gates between today and v1.0, plus a post-1.0 sketch.

Two registers hang off M5 and carry the enumerated detail this file only summarises:

- **`docs/design/au-coverage-sprint-plan.md`** — the six-sprint plan (v1.10 → v1.15) closing every gap on v2.3 / v2.3.1 / v2.4 / v2.5.1.
- **`docs/design/deferred-coverage-backlog.md`** — the deferred v2.6 / v2.8.2 scope, counted and named.

This file is intentionally higher-altitude than NEXT_STEPS. It records *direction and gates*, not per-stage tasks. Update it at each release boundary and whenever a milestone's scope materially shifts.

| | |
|---|---|
| Last updated | 2026-08-23 |
| Current release | **`v1.4.0`** (tagged locally, not yet pushed). `main` also carries the **v1.7** (CH13), **v1.8** (CH07) and **v1.9** (CH06) batches, all untagged — **109 typed segments** at verified per-version depth. API frozen; **still provisional pending full-coverage parity** (see M5). |
| Next planned cycle | **v1.10 = Sprint 0** of the six-sprint AU coverage plan — the v2.4 lab-automation presence **defect** + an audit presence predicate. Gates the first public push. |
| v1.0 stability clock | **Frozen at v1.0.0** (public API = SemVer contract, ADR-014). Coverage growth is additive (new segments/versions add members). |
| Guiding requirements | the working notes project requirements #1–#4 (feature-complete over AU-specific; integrator primary-reference tool; honesty over completeness; no known-incorrect predicate ships). **Sequencing** is AU-first as of 2026-08-23 (M5); **completeness** is unchanged — see `docs/design/deferred-coverage-backlog.md`. |

---

## Where we are (v1.0.0)

**Shipped and solid:**

- **Parsing / serialisation** — lossless round-trip; BOM/NUL hardening; MLLP codec (ADR-006); batch + streaming (`AsyncThrowingStream`) parsers.
- **Base-version grammar** — v2.3 / v2.3.1 / v2.4 / v2.5.1 / v2.6 / **v2.8.2** all present as first-class versions (the grammar-less `.v2_8` case aside): per-version field grammar, typed segments (15 at v1.0.0; **109 as of v1.9, merged and untagged**), typed composites (16), and per-version conditional rules. v2.6 added first-class in v0.14 (ADR-012, `W` optionality); v2.8.2 in v0.15 (ADR-013). **Version coverage spans v2.3 → v2.8.2** (the full published-standard set); **segment coverage within those versions is partial** — 109 typed, 263 schema-instances outstanding, AU-priority tiers first (M5). See `docs/design/v2_6-spec-audit.md` + `v2_8_2-spec-audit.md`.
- **Validation DSL** — same-segment compound predicates (v0.4-S4); cross-segment / message-context / position atoms (ADR-008); segment-presence atoms + subcomponent-granular field-refs + group-scope cardinality (ADR-010).
- **Locale / AU profile** — `HL7Locale.{international, auLocalisation}`; ADRM-2021 overlays for HL7au:000003–000008, 000040–000042, and the machine-checkable 00044 CE/CNE/CWE narrowings (ADR-009 + ADR-011). Compiler-checked Swift is the single source of truth (JSON overlays retired v0.13.1).
- **Docs discipline** — ADR-001…015 all Accepted + implemented; four spec-audit docs (v2_3-v2_4, v2_5_1, v2_6, v2_8_2) + the conditional-completeness register (v0.16); slim STATUS/NEXT_STEPS with archive snapshots at each boundary.

**Documented permanent limitations** (not defects — honesty per req #3/#4): the base-spec conditional-without-condition set (OBR-1/8/9/10/11/20/21/22/26/32, OBR-48, OBX-4/5/22, DG1-22) is the v0.16 M2 register (`docs/design/conditional-completeness-audit.md`); AU narrowings HL7au:00044.4.3 (CE text carve-out), 00044.4.7 (concept-match, needs terminology service), 00044.2 (PKI runtime), HL7au:000001 (receiver-runtime semantics).

---

## Milestones between here and v1.0

The four themes below are roughly independent and can interleave across cycles. Ordering within a theme is firm; ordering *between* themes is the project owner's call per cycle (see NEXT_STEPS for the next concrete pick).

### M1 — Version coverage completeness ✅ **(fully closed v0.15.0)**
*Goal: the base-spec surface an integrator expects is present, or its absence is a documented, defensible decision.*

- **Common-version set (v2.3 / v2.3.1 / v2.4 / v2.5.1 / v2.6)** — ✅ **DONE (v0.14, ADR-012).** See `docs/design/v2_6-spec-audit.md`.
- **v2.8.2 grammar table** — ✅ **DONE (v0.15, ADR-013).** `Version.v2_8_2` + 15 segments, all divergences (IS→CWE promotion, B→W withdrawals, O→B demotions, dropped/added conditionals, EI→EIP / ST→OG / ID→NM, field-count growth) verified against the v2.8.2 PDFs. The grammar-less `.v2_8` case retained (distinct MSH-12 raw value). No new `FieldOptionality` case needed. See `docs/design/v2_8_2-spec-audit.md`. **Coverage now spans v2.3 → v2.8.2 — the full published-standard set the reference targets.**
- **Curated-depth backlog (req #1 follow-on, not a v1.0 blocker):** 🔶 **Canonical done (v0.19).** NK1 / PV1 / IN1 extended to full HL7 field depth on the **canonical v2.5.1** (39 / 52 / 53) — the typed-segment structs now expose the full accessor surface (`docs/design/full-segment-audit.md`). **Remaining:** the per-version grammar tables (v2.3 / v2.3.1 / v2.4 / v2.6 / v2.8.2) stay at curated depth (13 / 20 / 25) pending a follow-on sweep (which fights the legacy-PDF `RP/#` extraction). (Supersedes the v0.12 IN1-optionality carry-over note.)

### M2 — Conformance-surface finalisation ✅ **(closed v0.17.0)**
*Goal: every "C-with-no-condition" / partial / deferred rule is either shipped or recorded as a permanent limitation with a spec-cited rationale — so the schemas are trustworthy as a reference per req #2.*

- **Conditional-without-condition sweep** — ✅ **DONE (v0.16).** All 69 `C`-without-`condition` instances (17 positions) audited: PD1-15 + ORC-26 shipped; 15 documented. Register: `docs/design/conditional-completeness-audit.md`; a guard test keeps it honest.
- **AU narrowings + terminology/PKI/history gaps** — ✅ **DONE (v0.17).** Consolidated into `docs/design/permanent-limitations-register.md` (00044.4.3 carve-out, 00044.4.7 concept-match, 00044.2 PKI, 00044.1.2/.1.3, HL7au:000001; cross-cutting terminology / PKI / cross-message-history classes). Each spec-cited and freeze-decided.
- **Decision recorded:** all current limitations are spec-honest and **acceptable to freeze** for v1.0 — none blocks it. The two registers are the authoritative M2 gate; shipping any documented limitation as an unconditional rule would misfire (req #4). The terminology-service / PKI integrations that would unlock the semantic rules are explicitly **post-1.0** (out of the ADR-006 portable core).

### M3 — API stabilisation ✅ **(closed v0.18.0)**
*Goal: freeze a public surface we're willing to support indefinitely.*

- **Evolution policy** — ✅ **ADR-014 (Accepted).** Documented SemVer evolution contract; **no `@frozen`** (inert for this source SPM package). Enums classified **open** (`Version`, `HL7Locale`, `IssueCode`, `ParseError`, `PathError`, `BuilderError` — may gain cases in 1.x minors; `@unknown default`) vs **stable** (domain-closed). 1.x is additive-only; removals/renames/signature changes wait for 2.0.
- **Public-surface audit** — ✅ **DONE (v0.18).** `docs/design/public-api-surface.md`: 74 public types enumerated (59 hand-written + 15 codegen'd), each confirmed intended/minimal, every enum classified. The 6 open enums carry an `@unknown default` DocC note.
- **Migration guarantees** — ✅ **DONE (v0.18).** `Migration.md` finalised into the v1.0 contract (additive-only rule, open/stable lists, v0.5.0→v0.17 additive-case history).
- **v1.0 is the API-freeze boundary** (per Migration.md): after it ships, remaining gaps become permanent. **M1 + M2 + M3 are now all closed** — the only remaining v1.0 gate is M4 (external IP review).

### M4 — Distribution & open-source readiness 🔶 **(IP review cleared; publish gated on M5)**
*Goal: the package is publishable and discoverable to the HL7 integrator community it's built for.*

- **IP review** — ✅ **CLEARED** (2026-07-09). The employment-contract gate passed; the *legal* blocker is gone.
- **Public push is now gated on M5** (full-coverage parity) per the owner's completeness bar — see M5. The `v1.0.0` tag stays on `private` until M5 is met. Remote target TBD (owner names host/repo).
- **Spec-PDF handling** — the `docs/standards/` Final Standard PDFs stay **out of the public tree** (author-local).
- **Distribution hygiene (remaining):** public CI workflow, SPM discoverability, DocC hosting, README badges.
- **Real-world fixture acquisition** — gated on the not-yet-written `scripts/anonymise-fixture.swift`. No PHI ever enters the repo (the working notes).

### M5 — Full HL7 segment coverage across all versions 🟠 **(AU-priority tier active; v2.6/v2.8.2 deferred — the public-push gate)**
*Goal (owner, 2026-07-09, req #1 strict): every HL7 segment modelled to full field depth on **every** supported version — not just the canonical v2.5.1 subset.*

- **Bar (measured, v1.1-S5):** **188 distinct segments** across the 6 versions; **~850 schema-instances** at full depth. Today: **109 typed segments**; **~79 unmodelled**. **Depth of the authored surface is verified, not assumed** (`scripts/audit-schemas.py --depth`, re-run every batch): 578 of 584 committed schemas match their own version's attribute table exactly, with 0 suspects; the 6 exceptions are RDT, a known `1-n` extractor limitation whose hand-authored schema is correct.
- **✅ Prerequisite — extraction pipeline (DONE, v1.1, ADR-015).** `pdftotext -layout` (poppler) recovers every attribute-table column cleanly on all 6 versions; the legacy-`RP/#` blocker is retired. Dev-time tool only (no new package dep). Its golden `--verify` caught **11 canonical v2.5.1 defects** (fixed) + **2 incomplete segments** (OBR 47→50, OBX 17→24, completed) — validating both the tool and the M5 premise. See `docs/design/segment-coverage-extraction.md`.
- **✅ Segment inventory (DONE, v1.1, S5).** `docs/design/segment-inventory.md` — the 188-segment work-list + proposed sweep order.
- **⬅ Sweep (ongoing):** additive cycles (ADR-014 §open — add, never remove; API frozen), extractor-seeded (`--emit-schema`) + human-verified, by chapter/family.
  - ✅ **v1.2:** NK1/PV1/IN1 per-version full depth (closes the immediate gap) + 14 new typed segments (PV2/MRG/DB1/GT1/IN2/IN3 + TQ1/TQ2/RXO/RXR/RXC/RXE/RXD/RXG) full-depth on all versions → **29 typed segments**. Also an extractor legacy-CH4 reliability fix.
  - ✅ **v1.3:** 28 new segments — SPM/ROL + CH10 scheduling + blood-product/RXA, then master-files (MFI/MFE/MFA + OM1–OM7) + referral (RF1/AUT/PRD/CTD) → **57 typed segments**. Also an extractor legacy-`R/O/C`-header reliability fix.
  - ✅ **v1.4.0 (shipped):** query (CH05) + lab-automation (CH13) + master-file-locations/patient-care/med-records (CH08/CH12/CH09) → **85 typed segments**. Surfaced the extractor DT-accuracy issue that v1.5 then fixed.
  - ✅ **v1.5 (in v1.4.0):** extractor hardening + fidelity. Datatype-column assignment, row robustness, element-name prose bleed (lettered-chapter table ends, unbounded continuation folding, front-truncated centred names). RDT rebuilt in all 6 versions — v2.3/v2.3.1 had held the *SPR* segment's fields, RDT being defined in CH2 §2.24.19 there rather than CH05.
  - ✅ **v1.6 (in v1.4.0):** per-version depth audit — **46 never-authored fields** filled across 14 (version, segment) pairs, all on core segments (v2.3/v2.3.1/v2.4 MSH/PID/ORC/OBR/OBX/NTE + v2.5.1 OBX-25). Established that per-version element **names** and datatypes must come from each version's own table, never the canonical schema.
  - ✅ **v1.7 (merged, untagged):** CH13 clinical-lab-automation completion — ISD/NDS/CNS/ECD/ECR/SID, v2.4+ only (v2.3 / v2.3.1 have no CH13) → **91 typed segments**. Whole-SID conditionality documented (§13.4.11 marks all four fields `C` with no stated condition). Five further prose-bleed element names fixed, found by adding a name-**length** audit predicate that v1.5's marker-word regex had missed.
  - ✅ **v1.8 (merged, untagged):** CH07 completion — the product-experience family (PES/PEO/PCR/PDC/PSH) and the clinical-trials family (CSR/CSP/CSS/CTI), all nine present on **all six versions at identical depth** → **100 typed segments**. Because the depths are uniform, every divergence was in datatypes and element names. **Six conditional predicates shipped rather than documented** (CSR-9/10 → `triggerEvent = C01`; CSR-14/15/16 → `triggerEvent = C04`; CTI-2 → `CTI-3 populated`), leaving CSP-4 as the batch's only bare `C`. First fully clean audit of the programme.
  - ✅ **v1.9 (merged, untagged):** CH06 financial completion — FT1/PR1/ACC/UB1/UB2/DRG (all six versions) + ABS/GP1/GP2 (v2.4+) → **109 typed segments**. The mirror image of v1.8: here the **depths** carry the version signal and move sharply (FT1 25→43, PR1 15→25, ACC 6→13, DRG 11→**33** at v2.6), while UB1/UB2 stay static at 23/17. `PR1-19`/`PR1-20` shipped `triggerEvent = P12`, making this the **first batch to add no bare `C` at all** — the limitation register and its guard test were untouched. `BLG` is excluded: it is a financial segment but lives in CH04.
  - **v1.10+ (next):** the **~79 unmodelled segments** by chapter/family (CH16 eClaims IVC/PMT/ADJ/PYE/IPC (v2.6+), CH15 personnel STF/PRA/ORG/AFF/LAN/EDU/CER, CH17 materials, **`BLG` in CH04**, the long tail), re-running `scripts/audit-schemas.py --depth` each batch.

  **Method note (earned the hard way in v1.5/v1.6, reconfirmed in v1.7):** six prior sweep cycles authored depths that looked complete and were not — 46 missing fields on the most-used segments in the standard. Coverage counted in *segments* hides gaps counted in *fields*. v1.7 then showed the same for *fidelity*: a name-**length** predicate found five corrupted element names that a marker-word regex had walked past. So — audit with **shape** predicates rather than enumerated content lists, and run them every batch. Both audits are cheap once the extractor is compiled, and they are now a committed tool (`scripts/audit-schemas.py`) rather than an ad-hoc script.

  **v1.8 added two reading lessons.** A field's condition may be stated in a **different field's** entry — CTI-2's requirement is written in CTI-3's definition, which is the only reason it shipped a predicate instead of joining the limitation register. And version prose must be located by **stable ITEM number**, never by heading shape: the v2.3-era chapters number definitions `7.8.1.9 <Name> (TS) 01043` with no `SEG-N` prefix, so a `CSR-9`-shaped regex returns nothing — which reads as "no condition stated" when the condition is right there. Both mean the honest answer to "is this conditionality expressible?" is often **yes**, and finding out takes reading the neighbours.
- **This is what "v1.0 complete" now means, and it gates the first public push.**

#### ⚠️ Re-prioritisation (owner, 2026-08-23): AU-relevant versions first

The sweep is **re-sequenced**, not reduced. Remaining coverage was measured at **263
schema-instances / ~2,431 fields** and split by Australian relevance:

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

### M6 — Australian localisation completeness 🟠 **(new, 2026-08-23 — promoted by the re-prioritisation)**
*Goal: the AU localisation surface is complete and spec-cited against ADRM-2021 over its v2.4
base, so AU integrators can trust the profile as a faithful rendering of the localisation.*

- **Base version is v2.4** — ADRM-2021 localises HL7 v2.4; the profile model already records
  this (`Profile.swift` → `baseVersion`). M6 work is therefore coupled to the Tier-1 v2.4
  coverage above: a localisation narrowing cannot be expressed on a segment that is not yet
  modelled on v2.4.
- **Shipped so far:** HL7au:000003–000008, 000040–000042, and the machine-checkable 00044
  CE/CNE/CWE narrowings (ADR-009 + ADR-011), locale-gated via
  `HL7Locale.auLocalisation`.
- **Known-open AU items** (already in `docs/design/permanent-limitations-register.md`):
  00044.4.3 CE text carve-out; 00044.4.7 concept-match (needs a terminology service);
  00044.2 PKI runtime; HL7au:000001 receiver-runtime semantics. These stay limitations —
  they need capability outside the ADR-006 portable core, not more schema work.
- **Next concrete step:** audit ADRM-2021 for narrowings that are expressible in the current
  DSL but not yet shipped, the same way v1.8 found six shippable predicates hiding in CH07
  prose. Until that audit runs, the AU surface is "as complete as v0.17 left it", which is
  not the same as complete.

---

## v1.0 definition — reframed (owner, 2026-07-09)

> **v1.0 = frozen public API + spec-honest conformance surface + full HL7 segment coverage at complete depth across every supported version (v2.3–v2.8.2).**

Gate status:
1. ✅ M3 API stabilisation (v0.18, ADR-014).
2. ✅ M2 conformance surface (v0.16 + v0.17 registers).
3. ✅ M1 *version-set* coverage — the six versions are modelled (v0.14 / v0.15) **for the 15-segment set**.
4. ✅ M4 IP review cleared (legal gate).
5. 🔴 **M5 full-coverage parity** — every segment × every version at full depth. **NOT met.** This is now the completeness bar and the public-push gate.

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
