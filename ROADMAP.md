# HL7v2Kit — Roadmap

Longer-horizon version arc toward **v1.0**. Companion to the two live planning docs:

- **`STATUS.md`** — where the project is *right now* (read first).
- **`NEXT_STEPS.md`** — the *near-term* ordered task runway (the next cycle or two).
- **`ROADMAP.md`** (this file) — the *milestone arc*: themes and gates between today and v1.0, plus a post-1.0 sketch.

This file is intentionally higher-altitude than NEXT_STEPS. It records *direction and gates*, not per-stage tasks. Update it at each release boundary and whenever a milestone's scope materially shifts.

| | |
|---|---|
| Last updated | 2026-07-09 |
| Current release | **`v0.19.0`** (req-#1: canonical NK1/PV1/IN1 full depth) on `main`, pushed to private bare repo |
| Next planned cycle | **v1.0 candidate** — M1 + M2 + M3 all closed; only M4 (external IP review) remains. v1.0 is tag-able on the private repo at the owner's call. (Optional pre-1.0: per-version NK1/PV1/IN1 depth follow-on.) |
| v1.0 stability clock | Anchored at **v0.5.0** (public API surface). See `Sources/HL7v2Kit/HL7v2Kit.docc/Migration.md`. |
| Guiding requirements | the working notes project requirements #1–#4 (feature-complete over AU-specific; integrator primary-reference tool; honesty over completeness; no known-incorrect predicate ships). |

---

## Where we are (v0.18.0)

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

### M4 — Distribution & open-source readiness
*Goal: the package is publishable and discoverable to the HL7 integrator community it's built for.*

- **First public push** — **gated on the employment-contract IP review** (project-owner parallel-track item). Until cleared, tags live only on the private bare repo.
- **Spec-PDF IP review** — the `docs/standards/` Final Standard PDFs are author-local; decide handling before any public push (likely: keep out of the public tree).
- **Distribution hygiene** — README quickstart (exists), LICENSE (Apache 2.0, set), CI on the public remote, SPM discoverability, DocC hosting.
- **Real-world fixture acquisition** — pipeline is designed but gated on (a) IP review and (b) the not-yet-written `scripts/anonymise-fixture.swift`. No PHI ever enters the repo (the working notes). Synthetic corpus (51 + 3 batch) covers current tests.

---

## Candidate v1.0 definition (draft — for project-owner ratification)

> **v1.0 = frozen public API + spec-honest conformance surface across v2.3–v2.6 (+ v2.8.2 per the M1 track), with all gaps either closed or documented as permanent limitations, published to a public remote.**

Concretely, v1.0 ships when:
1. ✅ M3 API audit complete and `Migration.md` finalised (v0.18, ADR-014).
2. ✅ M2 conformance surface finalised — no undocumented gaps (v0.16 conditional register + v0.17 permanent-limitations register).
3. ✅ M1 version coverage complete — v2.3 → v2.8.2 (v0.14 / v0.15).
4. M4 public push unblocked (IP review) — *or* an explicit decision to tag v1.0 privately and push later.

**Items 1–3 (all engineering-controllable) are DONE.** Only item 4 — the external IP-review gate — remains. Per the standing decision, **v1.0 can now be tagged on the private repo** with the public push tracked as a follow-on whenever the owner chooses. There is no remaining engineering blocker to a v1.0 candidate.

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
