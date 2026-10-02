# Deferred coverage backlog — v2.6 / v2.8.2 segment surface

**Created:** 2026-08-23, at the owner's re-prioritisation of the M5 sweep toward
Australian-relevant versions and localisation.

This register records coverage work that is **deliberately deferred, not abandoned**. It
exists so the deferral stays visible and quantified: an integrator reading the schemas can
see exactly which versions are complete, which are partial, and by how much.

> **This document supersedes nothing on its own.** It is the counterpart to the
> re-prioritisation recorded in `ROADMAP.md` → M5. Read that first for the decision and its
> rationale; read this for the enumerated scope.

## Why this register exists (the requirement it sits against)

`the working notes` project requirement **#1** states: *feature-complete over AU-specific — "AU
traffic doesn't trigger this case" is **not** a valid defence for a known feature gap.*
Requirement **#2** frames the package as an integrator primary-reference tool, defensible
against the spec text alone.

The 2026-08-23 re-prioritisation **narrows the near-term runway** to the versions Australian
implementations actually use. It does **not** retract requirements #1/#2 as the end state.
The distinction that keeps this honest:

- **Sequencing** — which gaps get closed first — is now AU-driven.
- **Completeness** — whether they get closed at all — is unchanged. Everything below remains
  in scope for the full-coverage bar, and remains a **blocking** item for any claim that
  HL7v2Kit is spec-complete across v2.3 → v2.8.2.

What would be a requirement-#1 violation, and is explicitly **not** what we are doing:
silently shipping v2.6 / v2.8.2 as if they were complete. The per-version coverage state is
published in `STATUS.md` and enumerated here.

## Measured scope (2026-08-23)

Method: extract every attribute table from every chapter PDF of each version, diff the
segment set against `Resources/schemas/<version>/`. Field counts are the **max field index**
per table, so they are upper bounds on authoring effort (withdrawn/reserved positions
included). Segment discovery is caption-based, so these are a **floor** — a segment defined
only in prose could be missed.

| Tier | Versions | Unmodelled instances | Est. fields | Status |
|---|---|---|---|---|
| **AU-priority** | v2.3, v2.3.1, v2.4, v2.5.1 | **131** | ~1,054 | Active runway |
| **Deferred** | v2.6, v2.8.2 | **132** | ~1,377 | This register |
| | | **263** | **~2,431** | |

Per deferred version:

| Version | Unmodelled segments | Est. fields | AU relevance |
|---|---|---|---|
| v2.6 | 60 | ~593 | Not used in AU clinical traffic |
| v2.8.2 | 72 | ~784 | Not used in AU clinical traffic |

Note the deferral moves **slightly over half the remaining field surface** (~1,377 of
~2,431) out of the near-term runway, while leaving the AU-relevant half (~1,054 fields
across 131 schema-instances) active.

## The deferred set

**38 segments required *only* by v2.6 / v2.8.2** — no AU-priority version defines them, so
they are the cleanest deferral:

```
ADJ ARV BUI CDO DMI DON DPS IAR ILT IPR ITM IVC IVT MCP OMC PAC PCE PKG PM1 PMT
PRT PSG PSL PSS PYE REL RFI RXV SCD SCP SDD SGH SGT SHP SLT STZ UAC VND
```

These are largely the v2.6+ additions: eClaims (`IVC/PMT/ADJ/PYE/IPR`), materials management
and shipping (`ITM/PAC/PKG/SHP/VND/SDD/SCD`), the participation/`PRT` family, and the
specimen/donation extensions (`DON/BUI/SCP/SGH/SGT`).

**The remaining 94 deferred instances** are AU-priority segments that additionally need
authoring on v2.6 / v2.8.2. Those follow naturally when each AU batch is done — author the
segment on its AU versions now, add the v2.6 / v2.8.2 instances when the deferred tier is
picked up.

## Also deferred: the `.v2_8` grammar table

`Version.v2_8` (distinct from `v2_8.2`) remains grammar-less — a pre-existing, separately
documented decision (ADR-013). It is unaffected by this re-prioritisation and stays deferred
on its own rationale: the `2.8` MSH-12 raw value is rare in the field.

## Also deferred: abstract message syntax (all versions)

Message structures (segment order, segment groups, required segments per trigger event,
and the MSH-9.3 event-to-structure mapping) are modelled only for the P8 pilot: v2.5.1
ADT_A01, ORU_R01 and ACK, checked when `ValidationOptions.messageStructureSeverity` is set
(off by default; P8-3 to P8-7, 2026-10-02). Every other structure and version is not
modelled. This is a different axis from the segment surface above: every segment can be
modelled and a message can still be structurally invalid. It is registered as blocking
spec-completeness in `permanent-limitations-register.md` section E, designed in ADR-019
(accepted 2026-10-02 under gate G2), piloted by `planning/remediation/P8-message-structures.md`
and rolled out per version by `planning/remediation/P8b-message-structure-rollout.md` (to be
scoped by P8-9).

## Exit criteria — when this register closes

1. The AU-priority tier reaches full per-version depth (v2.3 / v2.3.1 / v2.4 / v2.5.1).
2. The AU localisation surface is complete against ADRM-2021 (`ROADMAP.md` → M6).
3. Then the deferred tier is swept chapter-by-chapter using the same discipline — extractor
   seed, per-version verification against that version's **own** attribute table, golden
   `--verify`, cross-check pin, `scripts/audit-schemas.py --depth`.

Until (3) completes, **v2.6 and v2.8.2 must be described as partial** wherever coverage is
stated: `README.md`, `STATUS.md`, DocC, and any public-facing claim. Requirement #2 makes
that non-negotiable — an integrator must not be able to mistake partial for complete.

## Re-measuring this register

```bash
xcrun swiftc -O scripts/extract-segment-tables.swift -o /tmp/extractbin   # /tmp is cleaned
python3 scripts/audit-schemas.py --depth                                   # depth of what exists
```

The depth audit only checks schemas that **exist**, so it cannot see an absent segment. The
presence gap this register enumerates needs the extract-and-diff described under *Measured
scope* — see the v1.10 runway item for folding a presence predicate into
`scripts/audit-schemas.py` so this becomes a one-command check.
