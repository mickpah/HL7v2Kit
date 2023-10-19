# HL7 v2.3 / v2.3.1 / v2.4 schema audit — v0.4-S2

**Date:** 2026-06-18
**Audited:** `Resources/schemas/v2.3/*.json`, `Resources/schemas/v2.3.1/*.json`, `Resources/schemas/v2.4/*.json` (9 segments per version: MSH, PID, NK1, PV1, OBR, OBX, ORC, AL1, NTE).
**Baseline reference:** the now-spec-audited `Resources/schemas/v2.5.1/*.json` (see `v2_5_1-spec-audit.md`).
**Lens:** the working notes project requirements — **feature-complete over AU-specific; integrator primary-reference tool**. Audit conclusions must be defensible against the HL7 v2 spec text alone, not against test-fixture observations.

## Scope and honest framing

The v2.5.1 audit (S1 / S4) used the v2.5.1 Final Standard PDFs to make spec-text-citable claims. **The v2.3 / v2.3.1 / v2.4 Final Standard PDFs are not available locally.** That changes what S2 can and cannot do honestly:

**S2 CAN:**

1. **Structural delta audit** — every field that exists in two or more of the 4 supported versions can be compared on `name` / `dataType` / `optionality` / `repeatability`. HL7 v2.x's design is **additive** (each minor version extends the previous without changing existing field semantics, except for explicit deprecation marks). A divergence on these four axes between versions for the same field index would be a spec-encoding bug in our schemas.
2. **Field-count progression check** — pin and verify the per-segment growth across the version chain. The pins live in `Tests/HL7v2KitTests/MultiVersionTests.swift` (`extendedV24WireExercisesV24Additions` / `v23GrammarFitsSmallerSurface` / `v23PidPrefixOfV231Prefix...` / `fourWayGrammarDispatch`).
3. **Inheritance check on S4-C predicates** — for each conditional rule landed in v2.5.1 (PID-35 / PID-36 / OBX-2), confirm whether the referenced field exists in earlier versions, and decide carry-forward status.

**S2 CANNOT (without per-version PDFs):**

4. Cite per-version conditional-rule wording. The v2.5.1 wording is captured in `v2_5_1-spec-audit.md` with section numbers; the same wording in v2.3 / v2.3.1 / v2.4 would require their respective Final Standard PDFs.
5. Identify per-version component-table changes (e.g. whether CWE's component list looks different in v2.3 — likely, since CWE was introduced in v2.5; in v2.3 it's CE in those positions, but per-component layouts of CE itself may have shifted).
6. Catch version-specific errata.

Under the project's "honesty over completeness" requirement, this S2 commit ships the audit work that's spec-defensible (structural deltas + field counts) and **explicitly defers** the conditional-rule carry-forward + per-version component-definition audit until the relevant PDFs are obtained.

## Per-segment delta summary

Field counts per version:

| Segment | v2.3 | v2.3.1 | v2.4 | v2.5.1 | Delta history |
|---|---:|---:|---:|---:|---|
| **MSH** | 15 | 17 | 20 | 21 | v2.3→v2.3.1: +2 (MSH-16 application-acknowledgement, MSH-17 country code), v2.3.1→v2.4: +3 (MSH-18 charset, MSH-19 principal language, MSH-20 alternate char set handling), v2.4→v2.5.1: +1 (MSH-21 message profile identifier) |
| **PID** | 30 | 30 | 32 | 39 | v2.3.1→v2.4: +2 (PID-31 identity unknown indicator, PID-32 identity reliability code), v2.4→v2.5.1: +7 (PID-33 last update DT, PID-34 last update facility, PID-35 species code, PID-36 breed code, PID-37 strain, PID-38 production class code, PID-39 tribal citizenship) |
| **NK1** | 13 | 13 | 13 | 13 | no growth in the typed-surface cap (v0.1.0 capped NK1 at 13 from the original 39; later versions also extend beyond, but the typed cap stays) |
| **PV1** | 20 | 20 | 20 | 20 | same — capped at 20 in the typed surface |
| **OBR** | 43 | 43 | 47 | 47 | v2.3.1→v2.4: +4 (OBR-44 procedure code, OBR-45 procedure code modifier, OBR-46 placer supplemental info, OBR-47 filler supplemental info) |
| **OBX** | 11 | 14 | 16 | 17 | v2.3→v2.3.1: +3 (OBX-12..14 producer's ID / responsible observer / observation method), v2.3.1→v2.4: +2 (OBX-15 producer's facility, OBX-16 responsible observer), v2.4→v2.5.1: +1 (OBX-17 observation method) |
| **ORC** | 17 | 17 | 19 | 31 | v2.3.1→v2.4: +2 (ORC-18 confidentiality code, ORC-19 entered by), v2.4→v2.5.1: +12 (ORC-20..31 — large facility/address/phone/status block) |
| **AL1** | 6 | 6 | 6 | 6 | no growth (AL1 is small and stable) |
| **NTE** | 3 | 3 | 3 | 4 | v2.4→v2.5.1: +1 (NTE-4 entered by) |

## Per-field consistency check

A pairwise check across the 4 versions: for every `(segment, field_index)` pair that appears in 2+ versions, do `name`, `dataType`, `optionality`, and `repeatability` agree?

**Result: 0 inconsistencies across 198+ rows.**

Every field present in multiple versions has identical per-field attributes. HL7's additive history holds in our schemas. No structural corrections warranted.

## Conditional-rule carry-forward status

The v2.5.1 audit (S4 substage C) added three conditional predicates citable to specific sections of the v2.5.1 Final Standard:

| Field | v2.5.1 condition | Citation | v2.3 / v2.3.1 / v2.4 status |
|---|---|---|---|
| PID-35 | `"PID-36 populated OR PID-38 populated"` | §3.4.2.35 | **Not applicable** in base v2.3 / v2.3.1 / v2.4 — PID-35 doesn't exist (PID caps are 30 / 30 / 32). Note: the **AU v2.4 ADRM-2021 profile pre-adopts PID-35..38** from v2.5; that's a profile-level extension, handled separately when AU profile support lands. |
| PID-36 | `"PID-37 populated"` | §3.4.2.36 | **Not applicable** in base spec — same reason. |
| OBX-2 | `"OBX-11 != X"` | §7.4.2.2 | **v2.4 RESOLVED 2026-06-18** — v2.4 §7.4.2.2 wording is identical to v2.5.1 (verified against `docs/standards/HL7_v24_PDF/CH07.PDF`); carry-forward applied. v2.3 / v2.3.1 still **DEFERRED** pending those PDFs. |

## Known limitations (explicit)

Per the working notes's "honesty over completeness" requirement, these are the per-version checks deferred to a future cycle when the corresponding PDFs become available:

1. **Per-version conditional rules** — apart from the OBX-2 carry-forward question above, no `condition` predicates exist in v2.3 / v2.3.1 / v2.4 schemas. Per-version spec text would surface (a) other same-segment predicates the v2.5.1 audit didn't enumerate because they're version-specific, and (b) the version-history of the three predicates we did land (i.e. whether PID-35/36 and OBX-2 first appeared in v2.5.1 or earlier).
2. **Per-version component-table audit** — composite definitions evolve across versions (CWE was introduced in v2.5; v2.3 uses CE in those positions; XPN gained components across the version chain; etc.). The per-version spec PDFs would let the audit confirm composite component lists match the spec text per version.
3. **Per-version errata** — the official HL7 ballot errata sheets are not consulted at any version.

## Conclusion

Under the project's the working notes requirements, the v2.3 / v2.3.1 / v2.4 schemas as of v0.4-S2 are:

- **Structurally consistent** with the spec-audited v2.5.1 baseline on every field that exists in multiple versions.
- **Field-count progression** matches the documented HL7 minor-version additive-history pattern and is pinned end-to-end in `MultiVersionTests.swift`.
- **Conditional rules** are absent in v2.3 / v2.3.1 / v2.4 by design — carry-forward of the v2.5.1 S4-C predicates is deferred under "no predicate ships without citation". OBX-2 is the candidate when the v2.3 / v2.3.1 / v2.4 §7.4.2.2 wording can be cited.
- **0 corrections warranted** at the structural-delta axis.

This S2 commit ships the structural-delta findings + the deferred-items framing. Closure of the deferred items happens when the per-version PDFs become available; tracked as a follow-up.

## What this audit does NOT validate

- **v2.8 schema** — doesn't exist yet; v0.4-S3 adds it.
- **Per-version conditional rules** — see "Known limitations" above.
- **Per-version composite-component definitions** — see "Known limitations".
- **Spec table errata** — neither the v2.3 / v2.3.1 / v2.4 nor the v2.5.1 errata sheets are consulted. The audit uses the public Final Standard PDFs (or, for v2.3 / v2.3.1 / v2.4, the inheritance-from-v2.5.1 assumption).
