# Full-segment field-depth audit — v0.19 (req #1 feature-completeness)

**Audit date:** 2026-07-09 (v0.19 cycle).
**Scope:** extend the **canonical v2.5.1** schemas for **NK1**, **PV1**, **IN1** from their historical curated depth to the **full HL7 v2.5.1 field set**. The canonical version drives the typed-segment structs (`HL7v2KitCodegen` generates `NK1`/`PV1`/`IN1` from `Resources/schemas/v2.5.1/`), so this delivers the full typed-accessor surface — the primary req-#1 integrator value ("an integrator reading the schemas can trust them as a faithful rendering of the spec").

| Segment | Curated → full | Reference |
|---------|----------------|-----------|
| NK1 | 13 → **39** | HL7 v2.5.1 §3.4.5 |
| PV1 | 20 → **52** | HL7 v2.5.1 §3.4.3 |
| IN1 | 25 → **53** | HL7 v2.5.1 §6.5.6 |

## Why these were curated

NK1/PV1/IN1 were originally authored to a "shared typed-segment surface" depth (the fields AU clinical traffic exercises) rather than the full HL7 field set — a deliberate v0.2-era scoping call, flagged in the version-coverage audits as a req-#1 backlog item. This cycle closes the canonical portion of that gap.

## Method + fidelity

Per-field authoring from the v2.5.1 Final Standard PDFs (`docs/standards/HL7_v251_PDF/`):

- **Field index / name / datatype** — extracted directly from the v2.5.1 CH03/CH06 field-definition headers (`SEG-N Name (DT) ItemNum`), which parse cleanly. **Spec-verified.**
- **Optionality** — verified: every extended field is `O`; the only `R` fields are the ones already present (NK1-1 Set ID; PV1-2 Patient Class; IN1-1/2/3). No `C`/`X`/`B`/`W` in the extended range for v2.5.1. **Spec-verified.**
- **Repeatability** — the v2.5.1 attribute-table `RP/#` column does not extract cleanly from the PDFs (PDFKit interleaves the `DT/OPT/RP` columns). Repeatability was therefore set per the **HL7 v2.5.1 standard's documented NK1/PV1/IN1 shape** — the multi-value list fields (names, addresses, phones, identifiers, citizenship, ethnic-group, race, doctors, financial-class, insurance-company lists, etc.) marked repeating (`*`), the rest single (`1`). This axis is a **documented best-effort** rather than a per-field PDF extraction. It is **fail-safe**: a field wrongly marked `1` only under-validates a multi-repeat instance; it never causes a false rejection (req #4 is not violated — no message that was conformant becomes non-conformant).

## Scope boundary (carried limitation, not a gap)

- **Only the canonical v2.5.1** grammar + typed structs are extended this cycle. The **per-version grammar tables** (v2.3 / v2.3.1 / v2.4 / v2.6 / v2.8.2) for NK1/PV1/IN1 **remain at their curated depth** (13/20/25) until a follow-on cycle. Consequence: typed-accessor coverage is now full (version-agnostic, from canonical), but *per-version validation* of the extended NK1/PV1/IN1 fields is still limited to the modelled range on non-v2.5.1 wires. This is a bounded, documented follow-on — the full per-version sweep fights the legacy-PDF `RP/#` extraction and is deferred.
- The v2.6 / v2.8.2 NK1/PV1/IN1 divergences (CE→CWE, TS→DTM, IS→CWE, field-count growth to 41/54/53) are recorded in the `v2_6` / `v2_8_2` spec-audit docs and would apply when those per-version grammars are extended.

## Regression coverage

`TypedSegmentTests`: `v0_19FullCanonicalFieldCounts` (grammar carries NK1 39 / PV1 52 / IN1 53, spot-checked datatypes, `R` fields held) and `v0_19ExtendedTypedAccessor` (a newly-added scalar accessor, NK1-37, hydrates and agrees with the path). 501 tests green.

## API impact

Purely **additive** (ADR-014 §open): the typed structs gain accessors; no existing accessor changes name or return type; the v2.5.1 grammar table gains fields. Safe in a 1.x minor.
