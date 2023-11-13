# HL7v2Kit — Roadmap

Longer-horizon version arc toward **v1.0**. Companion to the two live planning docs:

- **`STATUS.md`** — where the project is *right now* (read first).
- **`NEXT_STEPS.md`** — the *near-term* ordered task runway (the next cycle or two).
- **`ROADMAP.md`** (this file) — the *milestone arc*: themes and gates between today and v1.0, plus a post-1.0 sketch.

This file is intentionally higher-altitude than NEXT_STEPS. It records *direction and gates*, not per-stage tasks. Update it at each release boundary and whenever a milestone's scope materially shifts.

| | |
|---|---|
| Last updated | 2026-07-13 |
| Current release | **`v1.2.0`** (on `private`); **v1.3 committed on worktree** (57 typed segments), awaiting merge/tag. API frozen; **still provisional pending full-coverage parity** (see M5). |
| Next planned cycle | **M5 sweep continues (v1.4+)** — the ~131 unmodelled segments by chapter/family off the inventory. Gates the first public push. |
| v1.0 stability clock | **Frozen at v1.0.0** (public API = SemVer contract, ADR-014). Coverage growth is additive (new segments/versions add members). |
| Guiding requirements | the working notes project requirements #1–#4 (feature-complete over AU-specific; integrator primary-reference tool; honesty over completeness; no known-incorrect predicate ships). |

---

## Where we are (v1.0.0)

**Shipped and solid:**

- **Parsing / serialisation** — lossless round-trip; BOM/NUL hardening; MLLP codec (ADR-006); batch + streaming (`AsyncThrowingStream`) parsers.
- **Base-version grammar** — v2.3 / v2.3.1 / v2.4 / v2.5.1 / v2.6 / **v2.8.2** fully covered (the grammar-less `.v2_8` case aside): per-version field grammar, typed segments (15), typed composites (16), and per-version conditional rules. v2.6 added first-class in v0.14 (ADR-012, `W` optionality); v2.8.2 in v0.15 (ADR-013). **Coverage spans v2.3 → v2.8.2, the full published-standard set.** See `docs/design/v2_6-spec-audit.md` + `v2_8_2-spec-audit.md`.
- **Validation DSL** — same-segment compound predicates (v0.4-S4); cross-segment / message-context / position atoms (ADR-008); segment-presence atoms + subcomponent-granular field-refs + group-scope cardinality (ADR-010).
- **Locale / AU profile** — `HL7Locale.{international, auLocalisation}`; ADRM-2021 overlays for HL7au:000003–000008, 000040–000042, and the machine-checkable 00044 CE/CNE/CWE narrowings (ADR-009 + ADR-011). Compiler-checked Swift is the single source of truth (JSON overlays retired v0.13.1).
- **Docs discipline** — ADR-001…013 all Accepted + implemented; four spec-audit docs (v2_3-v2_4, v2_5_1, v2_6, v2_8_2) + the conditional-completeness register (v0.16); slim STATUS/NEXT_STEPS with archive snapshots at each boundary.

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

### M5 — Full HL7 segment coverage across all versions 🟠 **(foundation done v1.1; sweep ongoing — the public-push gate)**
*Goal (owner, 2026-07-09, req #1 strict): every HL7 segment modelled to full field depth on **every** supported version — not just the canonical v2.5.1 subset.*

- **Bar (measured, v1.1-S5):** **188 distinct segments** across the 6 versions; **~850 schema-instances** at full depth. Today: **57 typed segments** (canonical v2.5.1 full + defect-clean; NK1/PV1/IN1 full-depth on all 6 versions + 42 new segments across v1.2/v1.3; **~131 segments unmodelled**).
- **✅ Prerequisite — extraction pipeline (DONE, v1.1, ADR-015).** `pdftotext -layout` (poppler) recovers every attribute-table column cleanly on all 6 versions; the legacy-`RP/#` blocker is retired. Dev-time tool only (no new package dep). Its golden `--verify` caught **11 canonical v2.5.1 defects** (fixed) + **2 incomplete segments** (OBR 47→50, OBX 17→24, completed) — validating both the tool and the M5 premise. See `docs/design/segment-coverage-extraction.md`.
- **✅ Segment inventory (DONE, v1.1, S5).** `docs/design/segment-inventory.md` — the 188-segment work-list + proposed sweep order.
- **⬅ Sweep (ongoing):** additive cycles (ADR-014 §open — add, never remove; API frozen), extractor-seeded (`--emit-schema`) + human-verified, by chapter/family.
  - ✅ **v1.2:** NK1/PV1/IN1 per-version full depth (closes the immediate gap) + 14 new typed segments (PV2/MRG/DB1/GT1/IN2/IN3 + TQ1/TQ2/RXO/RXR/RXC/RXE/RXD/RXG) full-depth on all versions → **29 typed segments**. Also an extractor legacy-CH4 reliability fix.
  - ✅ **v1.3:** 28 new segments — SPM/ROL + CH10 scheduling + blood-product/RXA, then master-files (MFI/MFE/MFA + OM1–OM7) + referral (RF1/AUT/PRD/CTD) → **57 typed segments**. Also an extractor legacy-`R/O/C`-header reliability fix.
  - **v1.4+ (next):** the ~131 unmodelled segments by chapter/family.
- **This is what "v1.0 complete" now means, and it gates the first public push.**

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
