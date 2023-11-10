# Permanent-limitations register — v0.17 (ROADMAP M2 close-out)

**Compiled:** 2026-07-09 (v0.17 cycle, ROADMAP M2 close-out).
**Purpose:** the single authoritative list of conformance rules HL7v2Kit **cannot** machine-check from the wire, with the reason and the v1.0 freeze decision for each. This closes ROADMAP **M2** — the conformance surface is now, in full, either *shipped* (validated) or *documented here as a permanent limitation with a spec-cited rationale* (req #2 / #3 / #4).

**Scope note:** these are **not defects**. Every entry falls into the fail-safe path (v0.2-V1: an absent/unresolvable predicate evaluates `false`, so the field is treated as optional and never wrongly flagged). A permanent limitation means "the spec states a constraint that no on-the-wire signal lets us decide" — not "we skipped it".

## A. Base-spec conditional-without-condition set

Fully audited in v0.16 — see **`docs/design/conditional-completeness-audit.md`** for the per-field rationale and the guard test. 17 positions: 2 shipped (PD1-15, ORC-26), 15 permanent limitations (OBR-1/8/9/10/11/20/21/22/26/32, OBR-48, OBX-4/5/22, DG1-22). Not repeated here.

**Freeze decision:** acceptable to freeze. Each is discourse-level, data-nature-dependent, peer-comparison, or descriptive-without-cited-MUST; none is wire-decidable. A guard test keeps the set honest across future edits.

## B. AU-localisation (ADRM 2021) narrowings

The machine-checkable HL7au:00044.* CE/CNE/CWE narrowings shipped in v0.13 (ADR-011). The following AU rules are **not** machine-checkable from the wire:

| Rule | What it requires | Why it can't ship | Freeze decision |
|------|------------------|-------------------|-----------------|
| **HL7au:00044.4.3** (CE `<text>`) | CE-2 text must be valued | The spec carries an explicit "*in some locations user display is not intended and the text may be blank*" carve-out. An unconditional required-CE-2 rule would over-fire on the blank-allowed locations, and those locations are not wire-signalled. Shipping it would violate req #4 ("no predicate ships if known-incorrect"). | **Permanent** unless a future spec revision adds a wire signal for the blank-allowed locations. |
| **HL7au:00044.4.7** (CE concept-match) | CE identifier and alternate identifier must reflect the *same concept* | Requires a terminology service to compare concepts across code systems; not derivable from the wire. Out of the portable-core boundary (ADR-006). | **Permanent** (a terminology-service hook would be a post-1.0, out-of-core module). |
| **HL7au:00044.5.7 / 00044.6.7** (CNE/CWE concept-match) | as .4.7, for CNE/CWE | Marked **"Removed"** in ADRM r2 — not applicable. | **N/A** (withdrawn by the profile). |
| **HL7au:00044.2** (HD / NASH PKI) | HD identifiers validate against NASH PKI | Runtime/PKI-dependent — needs an external certificate service at validation time, not a wire property. | **Permanent-until-runtime-integration** (post-1.0, out-of-core). |
| **HL7au:00044.1.2 / .1.3** (NASH sub-points / value-set membership) | NASH-specific formats / value-set membership | Runtime/PKI-dependent or require value-set dispatch against externally-maintained tables. | **Deferred**; re-audit if a value-set-dispatch mechanism lands. |
| **HL7au:000001** (Order addressing / MSH-6 Receiving Facility) | 4 sub-rules on order addressing | Each sub-rule is either **receiver-runtime semantics** (what the receiver must *do*, not what the message must *contain*), **soft "should" guidance** (not a MUST), or points to the PKI-deferred 00044.2. None is a wire-checkable MUST. | **Permanent** (runtime/soft-guidance, not a schema constraint). |

## C. Terminology / external-state limitations (cross-cutting)

- **Code-system-aware value checks** — any rule of the form "value X must belong to code system Y" or "concept A ≡ concept B" needs a terminology service; the validator checks structure and (where the profile enumerates them) literal value sets, not semantic equivalence. This bounds the AU 00044.4.4 LOINC-placement rule (shipped v0.13 as a **partial** necessary condition) and 00044.4.7 above.
- **PKI / certificate validation** — NASH and similar require live certificate infrastructure; out of the portable-core boundary (ADR-006).
- **Cross-message / patient-history state** — rules like OBR-48 "duplicate procedure" need history beyond the current message.

**Freeze decision (B + C):** all acceptable to freeze for v1.0. They are honest, spec-cited gaps, not defects; each would require an out-of-core runtime integration (terminology service, PKI) that is explicitly **post-1.0** (see ROADMAP "Post-1.0 sketch"). Shipping any as an unconditional rule would misfire, violating req #4.

## What is NOT a limitation (recorded to prevent re-litigation)

- **NUL / BOM handling** — embedded NUL is *rejected* at parse (v0.2-P2); BOM is stripped. These are design decisions with no carve-out, not limitations.
- **`.v2_8` grammar-less case** — a deliberate scope decision (ADR-013), not an undocumented gap: `2.8` is rare and distinct from the fully-modelled `2.8.2`.
- **Curated NK1 / PV1 / IN1 depth** — a req-#1 feature-completeness *backlog* item (extend the field sets), not a conformance limitation of the modelled fields.

## Outcome — M2 closed

With A (v0.16) and B/C (this register) documented and freeze-decided, **ROADMAP M2 (conformance-surface finalisation) is closed**: every conformance rule is either validated or listed here with a spec-cited reason and an explicit v1.0 freeze decision. The remaining v1.0 gate is **M3** (API stabilisation).
