# HL7 v2.8.2 schema audit — v0.15 (ADR-013)

**Audit date:** 2026-07-09 (v0.15 cycle, substages S1–S5).
**Audited:** `Resources/schemas/v2.8.2/*.json` (15 segments: MSH, MSA, ERR, EVN, NTE, PID, PD1, NK1, PV1, AL1, ORC, OBR, OBX, DG1, IN1).
**Reference:** HL7 v2.8.2, ANSI/HL7 Final Standard, September 2015 — the latest published HL7 v2.x release. PDFs referenced locally in `docs/standards/HL7_V2.8.2_PDF/PDF/` (not committed to-tree pending IP review). Attribute tables and field-definition prose extracted via PDFKit and verified field-by-field against the v2.6 baseline schemas.
**Lens:** the working notes project requirements — **feature-complete over AU-specific; integrator primary-reference tool**. v2.8.2 is a deliberate req-#1 reach to the latest standard; ADR-013 accepted first-class grammar (Option A). Sequel to ADR-012 (v2.6).

## Method note — the OBX "Example" trap (req #2)

CH07 contains **five** "Attribute Table – OBX" occurrences: the **base** segment definition (p51, caption `– Observation/Result`) and **four profile examples** (p153–155, captioned `Example - TIM/CHN/WAV/ANO Category`). The example tables mark most OBX fields `X` (not-supported) *for that profile* — those markings are **not** the base grammar. The base OBX table (p51) was used; OBX-6/7/9/10/12/13/14 are `O` there, not `X`. Any future re-audit must take the un-suffixed p51 table.

## Divergence classes (v2.8.2 vs v2.6)

v2.8.2 is **five point releases** past v2.6 (2.7 → 2.7.1 → 2.8 → 2.8.1 → 2.8.2), so the delta is larger and more varied than the v2.6-vs-v2.5.1 delta. No blanket rename this time; every field was checked against its own v2.8.2 attribute-table row + field-def header.

### 1. `IS → CWE` — coded-field promotion (the dominant wave)

Coded fields backed by HL7 tables were promoted `IS → CWE` field-by-field: ERR-9; EVN-4; PD1-1/2/5/6/7/8/16/19/20/21; PV1-2/4/10/12/13/14/15/16/18; DG1-6/17/25/26; IN1-15/20/21; OBX-8 (also renamed, see §5). PID-8/32 likewise.

### 2. `B → W` — withdrawals (the 2.7-era removals)

Fields previously kept `B` (backward-compat) were withdrawn (`W`) as of v2.7: MSA-3/5/6; ERR-1; EVN-1; PD1-4; PID-2/4/9/12/19/20/28; AL1-6; OBR-5/6/14/15/27; ORC-7. `W` is the `FieldOptionality.withdrawn` case added in v0.14 (ADR-012) — **no new model extension was needed** for v2.8.2. Withdrawn fields retain their historical (v2.6) `dataType` for positional/type continuity.

### 3. `O → B` — new backward-compat demotions

Fields still present but demoted to backward-compat: PID-13/14; PD1-12/13; PV1-9; ORC-10/11/12/17/18/19/21/22/23/24/31; OBR-10/16/28/32/33/34/35/50; OBX-15/16/18/23/24/25.

### 4. Conditionals restructured

- **`C → O` (condition dropped):** the v2.6 veterinary species/breed conditionals are gone — **PID-35** (renamed "Taxonomic Classification Code") is a self-contained `O`, **PID-36** is `B`. The parent-order XOR conditionals also dropped: **ORC-8** and **OBR-29** are now plain `O`. Several v2.6 `C` order fields relaxed to `O` (OBR-1/8/9/11).
- **`O → C` (new conditionals, no extractable predicate):** PD1-15 (Advance Directive Code), ORC-26 (ABN Override Reason), OBR-48 (Medically Necessary Duplicate Procedure Reason), DG1-22 (Parent Diagnosis). All recorded `C` **without** a `condition` — they fall through as optional and never fire, the same honest convention as OBX-22 Mood Code (which stays `C`). Documented rather than inventing a predicate (req #4).

### 5. Datatype / naming changes beyond IS→CWE

- **`EI → EIP`:** ORC-4 (Placer Group Number).
- **`ST → OG`:** OBX-4 (Observation Sub-ID) — `OG` (Observation Grouper) is a v2.8.x composite; also `O → C`.
- **`ID → NM`:** DG1-15 (Diagnosis Priority) — reverts to the v2.3-era type.
- **`ST → CWE`:** OBR-13 (Relevant Clinical Information).
- **Renames:** OBX-8 "Abnormal Flags" (IS) → "Interpretation Codes" (CWE); PID-35 "Species Code" → "Taxonomic Classification Code"; IN1-2 "Insurance Plan ID" → "Health Plan ID".

### 6. Field-count growth (new fields appended, authored from v2.8.2 prose)

| Segment | v2.6 | v2.8.2 | New fields |
|---------|------|--------|------------|
| PID | 39 | 40 | PID-40 Patient Telecommunication Information (XTN) |
| ORC | 31 | 34 | 32 ABN Date (DT), 33 Alternate Placer Order Number (CX), 34 Order Workflow Profile (EI) |
| OBR | 50 | 54 | 51 Observation Group ID (EI), 52 Parent Observation Group ID (EI), 53 Alternate Placer Order Number (CX), 54 Parent Order (EIP) |
| OBX | 25 | 30 | 26 Patient Results Release Category (ID), 27 Root Cause (CWE), 28 Local Process Control (CWE), 29 Observation Type (ID), 30 Observation Sub-Type (ID) |

Segments held at v2.6 counts (no new fields in the modelled range): MSH (25, byte-identical to v2.6), MSA (8), ERR (12), EVN (7), NTE (8, identical), PD1 (22), AL1 (6), DG1 (26). NK1 (13) and PV1 (20) mirror the v2.6 **curated** depth (full v2.8.2 NK1/PV1 are 41/54); IN1 (25) mirrors the shared curated depth (full v2.8.2 IN1 is 53). These curations are consistent across all versions — a documented req-#1 feature-completeness backlog item, not a v2.8.2 regression.

## Conditional-rule pass (S5)

Conditions carried verbatim where the v2.8.2 OPT column still shows `C` and the spec text matches: ORC-2 (`OBR-2 empty`), ORC-3 (`OBR-3 empty`); OBR-2 (`ORC-2 empty`), OBR-3 (`ORC-3 empty`), OBR-25 (`messageCode = ORU` — "required whenever OBR in a report message"); OBX-2 (`OBX-11 != X`); DG1-20/21 (`triggerEvent = P12`). **OBR-7** finalised as `messageCode = ORU OR SPM present` — the v2.6 "OBR-15 populated" clause is moot because OBR-15 is withdrawn in v2.8.2. The v2.6 XOR/parent conditions (ORC-8, OBR-29) are **dropped** because those fields are now plain `O`. `v282CleanORUHasNoErrors` pins that a well-formed v2.8.2 ORU^R01 validates with zero errors.

**P1-1:** OBR-7 is now `messageCode = ORU` (the `SPM present` leg misfired on orders; SPM may describe a virtual specimen, CH07 SPM intro). X-C06 checked: OBR-14 and OBR-15 are `W` (CH04 §4.5.3.14, §4.5.3.15) and no v2.8.2 condition references OBR-15.

### Known limitations (documented, not shipped — req #3/#4)

- **PD1-15, ORC-26, OBR-48, DG1-22, OBX-22** — `C` in the v2.8.2 tables with no extractable predicate; recorded conditional-without-condition (never fire).
- **NK1 / PV1 / IN1** — curated to the shared typed-segment depth (13 / 20 / 25); the full v2.8.2 field sets (41 / 54 / 53) are unmodelled — a cross-version req-#1 backlog item.

## Public-API / model impact

Additive only: `Version.v2_8_2 = "2.8.2"` (the grammar-less `.v2_8 = "2.8"` is retained — distinct MSH-12 raw value). **No new `FieldOptionality` case** — `.withdrawn` (v0.14) covers every `W`. v1.0 clock continues from v0.5.0.

## Regression coverage

`MultiVersionTests` pins, per substage: version detection incl. `.v2_8`/`.v2_8_2` coexistence; S1–S4 grammar-table field counts + divergences (withdrawn sets, IS→CWE / O→B waves, EI→EIP, ST→OG, ID→NM, renames, new fields, carried conditions); S1 dispatch no-unknown-segment; and the S5 clean-ORU no-spurious-error regression.
