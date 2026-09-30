# HL7 v2.6 schema audit — v0.14 (ADR-012)

**Audit date:** 2026-07-09 (v0.14 cycle, substages S1–S5).
**Audited:** `Resources/schemas/v2.6/*.json` (15 segments: MSH, MSA, ERR, EVN, NTE, PID, PD1, NK1, PV1, AL1, ORC, OBR, OBX, DG1, IN1).
**Reference:** HL7 v2.6, ANSI/HL7 Final Standard, October 2007. PDFs referenced locally in `docs/standards/HL7_v26_PDF/` (not committed to-tree pending IP review). Attribute tables and field-definition prose were extracted via PDFKit and verified field-by-field against the v2.5.1 baseline schemas.
**Lens:** the working notes project requirements — **feature-complete over AU-specific; integrator primary-reference tool**. v2.6 is a mainstream version; ADR-012 accepted first-class grammar (Option A) rather than leave it recognised-but-unvalidated (Option B, rejected as a shipped end-state).

## Outcome summary

The v2.6 grammar table was authored by taking each segment's v2.5.1 schema as the baseline and applying only the divergences the v2.6 attribute tables actually show. Three systematic and two structural divergence classes were found and applied verbatim; no speculative rules were introduced.

### 1. TS → DTM (systematic)

Every timestamp field renamed from the `TS` composite to the `DTM` scalar across all segments. Applied to: MSH-7; EVN-2/3/4/5/6; PID-7/29/33; ORC-9/15/27; OBR-6/7/8/14/22/36; OBX-12/14; DG1-5/19; IN1-18. This is a blanket v2.6 rename and was applied to every TS field.

### 2. CE → CWE (field-by-field, NOT blanket)

v2.6 migrated most `CE` coded fields to `CWE`, but the migration is **field-by-field** — some coded fields went to `CNE` instead, and a few composites were already CWE in v2.5.1. Each field was checked against its own v2.6 field-definition header rather than mechanically renamed:

- **CE → CWE:** PID-10/15/16/17/22/26/27/28/35/36/38; PD1-11/15; NK1-3/7; AL1-2/3/4; ORC-16/17/18/20; OBR-4/12/31/38/39/40/43/46/47/50; OBX-3/6/15/17; DG1-3/23; IN1-2/17.
- **CE → CNE:** OBR-44 (Procedure Code), OBR-45 (Procedure Code Modifier). Verified against the v2.6 CH04 headers — these do **not** go to CWE.
- Already CWE/CNE in v2.5.1 (unchanged): ORC-25/26/28/29/31 (CWE), ORC-30 (CNE), PID-39 (CWE).

### 3. Field-count growth (new fields appended)

Segment field counts grew where v2.6 appended fields; the new fields were authored from their v2.6 field-definition prose:

| Segment | v2.5.1 | v2.6 | New fields |
|---------|--------|------|------------|
| MSH | 21 | 25 | MSH-22..25 |
| MSA | 6 | 8 | MSA-7/8 |
| NTE | 4 | 8 | NTE-5..8 |
| PD1 | 21 | 22 | PD1-22 (Advance Directive Last Verified Date) |
| OBR | 47 | 50 | OBR-48 (Medically Necessary Duplicate Procedure Reason), 49 (Result Handling), 50 (Parent Universal Service Identifier) |
| OBX | 17 | 25 | OBX-18..25 (Equipment Instance Identifier … Performing Organization Medical Director) |
| DG1 | 21 | 26 | DG1-22 (Parent Diagnosis), 23 (DRG CCL Value Code), 24 (DRG Grouping Usage), 25 (DRG Diagnosis Determination Status), 26 (POA Indicator) |

Segments held at the v2.5.1 curation depth where v2.6 added no fields in the modelled range: PID (39), NK1 (13), PV1 (20 — curated), AL1 (6), ORC (31).

### 4. Withdrawn fields — new `W` optionality (model extension, req #3)

v2.6 is the **first modelled version to use the `W` (withdrawn) optionality code** in its attribute tables: DG1-2/4 and the DRG/outlier block DG1-7..14 were withdrawn and removed from the standard (the DRG detail moved to the new DRG segment). A withdrawn field's sequence slot is retained but carries no meaning.

`W` is semantically distinct from `B` (deprecated but retained for backward compatibility). Mapping `W → B` would have been a **known-incorrect representation** (the working notes req #4). Per req #3, the model was extended: `FieldOptionality.withdrawn = "W"`, codegen maps `"W" → .withdrawn`, and `Validator.checkDeprecation` warns (`.fieldNotSupported`) when a withdrawn field is populated — the same warn-on-populated family as `B`/`X`. This is an **additive** public-API change (a new case on the non-`@frozen` `FieldOptionality`), landed pre-v1.0.

Withdrawn fields keep their historical (v2.5.1) `dataType` string in the schema for positional/type continuity, with optionality `W`.

### 5. IN1 25-field scope (carried limitation, not a regression)

The v2.6 IN1 schema mirrors the **25-field curation** established for the v2.5.1 / v2.4 / v2.3 IN1 schemas (the shared typed-segment surface), not the full ~53-field v2.6 IN1. This is a **carried scope limitation** consistent across every version, not a v2.6-specific gap. Extending IN1 to its full field set across all versions is a separate feature-completeness backlog item (req #1), out of scope for the v2.6 grammar-parity cycle.

## Conditional-rule pass (S5)

The cross-segment / message-context / specimen / XOR conditions were carried into v2.6 verbatim from v2.5.1: ORC-2 (`OBR-2 empty`), ORC-3 (`OBR-3 empty`), ORC-8 (`ORC-1 = CH AND OBR absent OR ORC-1 = CH AND OBR-29 empty`); OBR-2 (`ORC-2 empty`), OBR-3 (`ORC-3 empty`), OBR-7 (`messageCode = ORU OR SPM present OR OBR-15 populated`), OBR-14 (`SPM present OR OBR-15 populated`), OBR-25 (`messageCode = ORU`), OBR-29 (`ORC-1 = CH AND ORC absent OR ORC-1 = CH AND ORC-8 empty`); OBX-2 (`OBX-11 != X`); PID-35 (`PID-36 populated OR PID-38 populated`), PID-36 (`PID-37 populated`); DG1-20/21 (`triggerEvent = P12`). The v2.6 spec text for these **structural** conditions is unchanged from v2.5.1 (they concern message structure, not the datatype/field-count divergences above), so carrying them verbatim is spec-faithful. A `v26CleanORUHasNoErrors` regression pins that a well-formed v2.6 ORU^R01 — every ORU-required conditional satisfied, no XOR/specimen misfire — validates with zero errors.

**P1-1 correction:** OBR-7 is now `messageCode = ORU` and OBR-14 is `B` with no condition (CH04 row 14, §4.5.3.14). The carried `SPM present` / `OBR-15 populated` legs misfired on conformant orders (V26-C01, X-C05).

**P1-2:** "report message" is `messageCode in (ORU, ORF, OUL, OPU)`: CH07 §7.3.1-§7.3.10 (adds OPU R25).

### Known limitation (documented, not shipped — req #3/#4)

- **OBX-22 Mood Code** is marked conditional (`C`) in the v2.6 OBX attribute table, but the field-definition prose does not state an extractable predicate. It is recorded as a conditional-without-condition (the same honest state as any `C` field with no `condition` — it falls through as effectively optional and never fires) rather than inventing a predicate that could misfire.

## Regression coverage

`MultiVersionTests` pins, per substage: version detection (`v26VersionDetected`); segment dispatch / no-unknown-segment (`v26S1SegmentsRecognised`); grammar-table field counts + divergences for every substage (S1 control/notes, S2a admin, S2b PID, S3a ORC, S3b OBR/OBX, S4 DG1/IN1); the PID-35 species conditional firing; the populated-withdrawn-field warning (`v26WithdrawnFieldWarns`); and the clean-ORU conditional pass (`v26CleanORUHasNoErrors`).
