# Test fixture corpus

Every fixture in this directory must be **synthetic** v2 data with no real PHI.
The `scripts/anonymise-fixture.sh` script (Task 7a, 2026-06-13) is the only
gate by which a real-world-derived fixture could enter the corpus, and even
then the output must be scanned via `scripts/scan-fixtures-for-phi.sh` before
commit.

Status v0.1.0: 48-fixture synthetic corpus complete (7a starter set +
7b expansion). Spec § 9.2 fixture target met.

Status v0.3-Z2 (2026-06-17): grew the corpus to **51 top-level fixtures
+ 3 batch fixtures** under `Batches/`. New material targets the surfaces
introduced in v0.3: multi-version grammar tables (v2.3 / v2.3.1 / v2.4
wires) and the batch parser (FHS / BHS / BTS / FTS framing).

## Adding a fixture

See `docs/design/HL7v2Kit-Spec.md` §10 for the anonymisation policy.

1. Synthetic fixtures written from scratch are always acceptable. Anything
   real-world-derived must go through `scripts/anonymise-fixture.sh` (the
   `HL7v2KitAnonymise` target) — the only approved path — and the output
   must still pass `scripts/scan-fixtures-for-phi.sh` before commit.
2. Add a row to the provenance table below (source, purpose, anonymisation log).
3. Add a corresponding test in `Tests/HL7v2KitTests/` (directory-scanning
   suites pick up round-trip/fuzz coverage automatically; purpose-specific
   assertions need their own test).
4. A valid-corpus fixture (any name not starting `malformed_`) must conform
   to its declared message structure wherever that structure is modelled:
   `FixtureStructureConformanceTests` checks every one with the ADR-019
   structure check at `.error`. A fixture whose purpose is a structural
   defect goes in that test's `deliberatelyNonConformant` list with its
   reason, and its row below says it is structurally non-conformant by design.

## Line endings

All `.hl7` files use **CR (`\r`)** as the segment terminator — matching real
v2 wire format. Some editors display this as a single long line. To browse:

```bash
xxd Tests/Fixtures/adt_a01_minimal.hl7 | head
```

Or convert to `\r\n` for viewing:

```bash
tr '\r' '\n' < Tests/Fixtures/adt_a01_minimal.hl7
```

## Provenance

All fixtures below were hand-written from scratch for the v0.1.0 starter
set. Synthetic identifiers use the `SYN-NNNN` prefix; synthetic facilities
use the `SYNTH_` prefix; synthetic providers use `DR########` (AHPRA-shaped
but transparently fake). No real-world data sources.

| File | Category | Purpose | Anonymisation log |
|---|---|---|---|
| `adt_a01_minimal.hl7` | ADT^A01 (admit) | MSH + EVN + PID + PV1 — smallest valid admit message (EVN added 2026-10-03, P8b-5) | N/A — synthetic from scratch |
| `adt_a01_with_nk1.hl7` | ADT^A01 (admit) | MSH + EVN + PID + NK1 + PV1 — admit with next-of-kin contact (EVN added 2026-10-03, P8b-5) | N/A — synthetic from scratch |
| `orm_o01_lab_order.hl7` | ORM^O01 (order) | MSH + PID + ORC + OBR — lab order for glucose | N/A — synthetic from scratch |
| `oru_r01_chemistry.hl7` | ORU^R01 (result) | MSH + PID + OBR + 3 × OBX — chemistry panel results | N/A — synthetic from scratch |
| `oru_r01_with_z_segment.hl7` | ORU^R01 + Z-segments | MSH + PID + ZAU + OBR + OBX + ZPI — AU-style Z-segment overlay | N/A — synthetic; Z-segments are facility-specific dummy data |
| `edge_empty_fields.hl7` | Edge case | Empty fields + `\F\` `\S\` `\T\` escape sequences in a free-text narrative (OBX-5, FT; moved from a top-level NTE-3 that ADT_A01 does not define, and EVN added, 2026-10-03, P8b-5) | N/A — synthetic |
| `malformed_missing_msh.hl7` | Malformed | Starts with PID instead of MSH — parser must throw `.missingMSH` | N/A — synthetic |
| `malformed_invalid_encoding_chars.hl7` | Malformed | MSH-2 = `^^^^` (encoding chars not distinct) — parser must throw `.invalidMSH` | N/A — synthetic |
| `adt_a01_with_allergies.hl7` | ADT^A01 (admit) | MSH + EVN + PID + PV1 + 2 × AL1 — admit with drug allergies (EVN added 2026-10-03, P8b-5) | N/A — synthetic from scratch |
| `adt_a01_with_insurance.hl7` | ADT^A01 (admit) | MSH + EVN + PID + PV1 + IN1 — admit with insurance details | N/A — synthetic from scratch |
| `adt_a01_emergency.hl7` | ADT^A01 (admit) | MSH + EVN + PID + PV1 — emergency-class admission | N/A — synthetic from scratch |
| `adt_a04_register_clinic.hl7` | ADT^A04 (register) | MSH + EVN + PID + PV1 — outpatient clinic registration | N/A — synthetic from scratch |
| `adt_a04_register_with_nk1.hl7` | ADT^A04 (register) | MSH + EVN + PID + NK1 + PV1 — register with next-of-kin | N/A — synthetic from scratch |
| `adt_a04_register_paediatric.hl7` | ADT^A04 (register) | MSH + EVN + PID + PD1 + NK1 + PV1 — paediatric register with mother NK1 | N/A — synthetic from scratch |
| `adt_a08_update_address.hl7` | ADT^A08 (update) | MSH + EVN + PID + PV1 — patient demographic update (address) | N/A — synthetic from scratch |
| `adt_a08_update_demographics.hl7` | ADT^A08 (update) | MSH + EVN + PID + PV1 — patient demographic update (marital status) | N/A — synthetic from scratch |
| `adt_a08_update_with_allergies.hl7` | ADT^A08 (update) | MSH + EVN + PID + PV1 + 2 × AL1 — update adding allergies | N/A — synthetic from scratch |
| `orm_o01_radiology_xray.hl7` | ORM^O01 (order) | Chest X-ray order to RIS | N/A — synthetic from scratch |
| `orm_o01_microbiology.hl7` | ORM^O01 (order) | MCS (microscopy/culture/sensitivity) order | N/A — synthetic from scratch |
| `orm_o01_haematology.hl7` | ORM^O01 (order) | FBC (full blood count) order | N/A — synthetic from scratch |
| `orm_o01_cancel.hl7` | ORM^O01 (cancel) | LFT order cancellation (ORC-1=CA) | N/A — synthetic from scratch |
| `orm_o01_with_diagnosis.hl7` | ORM^O01 (order) | HbA1c order with DG1 diabetes diagnosis | N/A — synthetic from scratch |
| `oru_r01_haematology.hl7` | ORU^R01 (result) | FBC results (4 × OBX: HGB/WCC/PLT/HCT) | N/A — synthetic from scratch |
| `oru_r01_lipid_panel.hl7` | ORU^R01 (result) | Lipid panel with mixed N/H abnormal flags | N/A — synthetic from scratch |
| `oru_r01_thyroid_function.hl7` | ORU^R01 (result) | TFT results (TSH/FT4/FT3) | N/A — synthetic from scratch |
| `oru_r01_microbiology.hl7` | ORU^R01 (result) | MCS results — organism + sensitivity + TX comment | N/A — synthetic from scratch |
| `oru_r01_xray_chest.hl7` | ORU^R01 (radiology) | Chest X-ray narrative report (TX) | N/A — synthetic from scratch |
| `oru_r01_ct_scan.hl7` | ORU^R01 (radiology) | CT abdomen/pelvis report + impression | N/A — synthetic from scratch |
| `oru_r01_ultrasound.hl7` | ORU^R01 (radiology) | Pelvic ultrasound report + impression | N/A — synthetic from scratch |
| `oru_r01_mri_brain.hl7` | ORU^R01 (radiology) | MRI brain report + impression | N/A — synthetic from scratch |
| `oru_r01_multi_obr.hl7` | ORU^R01 (result) | Two OBR batteries (EUC + LFT) under one PID | N/A — synthetic from scratch |
| `ack_application_accept.hl7` | ACK | MSH + MSA (AA — application accept) | N/A — synthetic from scratch |
| `ack_application_error.hl7` | ACK | MSH + MSA (AE) + ERR — invalid patient ID format. ERR layout updated 2026-06-18 (v0.4-T1) to v2.5.1-conformant form (ERR-2 location + ERR-3 CWE code + ERR-4 severity), replacing the pre-T1 v2.4-style single ERR-1 ELD that was hidden when ERR was UnknownSegment. | N/A — synthetic from scratch |
| `adt_a01_with_zau_zin.hl7` | ADT^A01 + Z-segments | ZAU (Medicare) + ZIN (insurance) interleaved before PV1 | N/A — synthetic; Z-segments are AU facility-specific dummy |
| `orm_o01_z_billing.hl7` | ORM^O01 + Z-segment | ZBL (MBS bulk-bill) appended after OBR | N/A — synthetic; ZBL is dummy |
| `oru_r01_z_lab_overlay.hl7` | ORU^R01 + Z-segments | ZLB (NATA accreditation) before OBR + ZRE (reflex) after OBX | N/A — synthetic; Z-segments dummy |
| `msh_with_z_only.hl7` | MSH + Z-segment | Heartbeat-style: MSH + ZTX only (no PID). Structurally non-conformant by design (ADR-019): it declares ADT^A01^ADT_A01 but carries none of EVN, PID and PV1, because the point is a message with nothing but MSH and one Z-segment; listed in `FixtureStructureConformanceTests.deliberatelyNonConformant` (2026-10-03, P8b-5) | N/A — synthetic from scratch |
| `malformed_msh_too_short.hl7` | Malformed | MSH segment truncated to `MSH\|^~` — parser must throw `.invalidMSH("too short")` | N/A — synthetic |
| `malformed_msh_no_field_sep_after_enc.hl7` | Malformed | Char after MSH-2 encoding chars isn't `\|` — `.invalidMSH("MSH-2 not followed by field separator")` | N/A — synthetic |
| `malformed_unsupported_charset.hl7` | Malformed | MSH-18 = `GB18030` (unsupported) — `.unsupportedCharacterEncoding` | N/A — synthetic |
| `malformed_empty.hl7` | Malformed | Zero-byte file — `.emptyInput` | N/A — synthetic |
| `edge_unicode_diacritics.hl7` | Edge | UTF-8 names with diacritics (García, José, Søren, Müller); EVN added 2026-10-03 (P8b-5) | N/A — synthetic |
| `edge_repeating_pid3_identifiers.hl7` | Edge | PID-3 with 3 repetitions (MR + MC + NH) via `~`; EVN added 2026-10-03 (P8b-5) | N/A — synthetic |
| `edge_long_address.hl7` | Edge | Very long PID-11 address components; EVN added 2026-10-03 (P8b-5) | N/A — synthetic |
| `edge_escape_sequences_in_name.hl7` | Edge | `\F\`, `\H\`, `\N\`, `\X0D\` escape sequences in PID-5 and a free-text narrative (OBX-5, FT; moved from a top-level NTE that ADT_A01 does not define, and EVN added, 2026-10-03, P8b-5) | N/A — synthetic |
| `edge_many_nte.hl7` | Edge | ORU with 4 trailing NTE segments after OBX | N/A — synthetic |
| `edge_minimal_pid_phone_only.hl7` | Edge | Sparsely populated PID — name + phone only; EVN and a minimal PV1 (PV1-2 `O`) added 2026-10-03 (P8b-5) so the message carries ADT_A01's required segments | N/A — synthetic |
| `edge_obx_repeating_values.hl7` | Edge | OBX-5 + OBX-8 with `~` repetitions (3-sample BP series) | N/A — synthetic |
| `adt_a01_v23.hl7` | Multi-version (v2.3) | v2.3 ADT^A01 admit — exercises the v2.3 grammar table (MSH-1..19 per v2.3 CH2 Figure 2-8); EVN added in P8b-15 (v2.3 Chapter 3 section 3.2.1, p 3-3, prints EVN as required), EVN-1 left empty as v2.3 marks it B | N/A — synthetic from scratch (v0.3-Z2) |
| `orm_o01_v231.hl7` | Multi-version (v2.3.1) | v2.3.1 ORM^O01 order — exercises the v2.3.1 grammar table (PID 30 fields, ORC 24 fields) | N/A — synthetic from scratch (v0.3-Z2) |
| `oru_r01_v24.hl7` | Multi-version (v2.4) | v2.4 ORU^R01 result — its trailing PID values `N|US` sit at PID-35/36 (Species Code / Breed Code), not at PID-31/32 (identityUnknownIndicator / identityReliabilityCode) as this row first said; corrected 2026-10-01 (P4-31 review), fixture bytes unchanged; MSH-18 declares `ASCII` (base v2.4 Table 0211 has no `UNICODE UTF-8`, which is the AU ADRM-2021 back-port; the file is pure ASCII) | N/A — synthetic from scratch (v0.3-Z2) |
| `oru_r01_v23.hl7` | Multi-version (v2.3) | v2.3 ORU^R01 without ORC: OBR-2/3 carry the order numbers; OBX-2, OBR-25 and ORC-absent OBR-2/3 fire/silent pairs in `VersionFixtureTests`; validates with no issues under `.strict` | N/A — synthetic from scratch (P7-6); licence Apache 2.0, as the package |
| `orf_r04_v23.hl7` | Multi-version (v2.3) | v2.3 ORF^R04 query response: MSA, QRD (QRD-4 within its printed LEN 10), QRF, PID, OBR, OBX; validates with no issues under `.strict` | N/A — synthetic from scratch (P7-6); licence Apache 2.0, as the package |
| `ack_a01_v23.hl7` | Multi-version (v2.3) | v2.3 ACK^A01 general acknowledgement, MSA-1 `AA`; validates with no issues under `.strict` | N/A — synthetic from scratch (P7-6); licence Apache 2.0, as the package |
| `oru_r01_v231.hl7` | Multi-version (v2.3.1) | v2.3.1 ORU^R01 with ORC `RE`, order numbers within the printed EI LEN 22; OBX-2 and OBR-25 pairs; validates with no issues under `.strict` | N/A — synthetic from scratch (P7-6); licence Apache 2.0, as the package |
| `adt_a01_v231.hl7` | Multi-version (v2.3.1) | v2.3.1 ADT^A01 admit: EVN (EVN-1 empty, B in v2.3.1), PID with address, PV1; validates with no issues under `.strict` | N/A — synthetic from scratch (P7-6); licence Apache 2.0, as the package |
| `ack_a01_v231.hl7` | Multi-version (v2.3.1) | v2.3.1 ACK^A01 with MSA-1 `AE` and an ERR-1 locating PID-3 (code 101, table 0357); validates with no issues under `.strict` | N/A — synthetic from scratch (P7-6); licence Apache 2.0, as the package |
| `oru_r01_v26.hl7` | Multi-version (v2.6) | v2.6 ORU^R01 with ORC `RE`, three-component MSH-9; OBX-2, OBR-7 and OBR-25 pairs; validates with no issues under `.strict` | N/A — synthetic from scratch (P7-7); licence Apache 2.0, as the package |
| `adt_a01_v26.hl7` | Multi-version (v2.6) | v2.6 ADT^A01 with DG1; DG1-20 trigger-gate pair (silent on A01, fires on P12); validates with no issues under `.strict` | N/A — synthetic from scratch (P7-7); licence Apache 2.0, as the package |
| `oru_r01_v271.hl7` | Multi-version (v2.7.1) | v2.7.1 ORU^R01 with ORC, OBR, PRT (person participation), TQ1, OBX and SPM; OBX-2, OBR-7, OBR-25 and PRT one-of / PRT-7 prohibition pairs; validates with no issues under `.strict` | N/A — synthetic from scratch (P7-7); licence Apache 2.0, as the package |
| `adt_a01_v271.hl7` | Multi-version (v2.7.1) | v2.7.1 ADT^A01 with DG1 (EVN-1 empty, W from v2.7); DG1-20 trigger-gate pair; validates with no issues under `.strict` | N/A — synthetic from scratch (P7-7); licence Apache 2.0, as the package |
| `adt_a01_v282.hl7` | Multi-version (v2.8.2) | v2.8.2 ADT^A01 with PID-40 XTN (XTN.1 empty, withdrawn); fictional-range phone number (02) 5550 1234; validates with no issues under `.strict` | N/A — synthetic from scratch (P7-7); licence Apache 2.0, as the package |
| `oru_r01_v282.hl7` | Multi-version (v2.8.2) | v2.8.2 ORU^R01 with PRT, TQ1, SPM and OBX-26..30 populated together; PRT one-of / PRT-7 prohibition pairs; validates with no issues under `.strict` | N/A — synthetic from scratch (P7-7); licence Apache 2.0, as the package |
| `oml_o21_v282.hl7` | Multi-version (v2.8.2) | v2.8.2 OML^O21 lab order (ORC `NW`) with TQ1 and SPM; pins the registered OBR-7 request-leg gap; validates with no issues under `.strict` | N/A — synthetic from scratch (P7-7); licence Apache 2.0, as the package |
| `au_oru_r01_pathology.hl7` | AU ADRM-2021 (v2.4) | ORU^R01 pathology result: NASH-shaped HD and EI addressing, LOINC-coded NM OBX with UCUM units, an HTML display OBX (AUSPDI) last in its group; `AUFixtureTests` | N/A — synthetic, written from scratch (P12 S3-1); HPI-O digits all zero-filled (`0000000000001001`), not a real identifier; licence Apache 2.0, as the package |
| `au_oru_r01_pathology_pdf.hl7` | AU ADRM-2021 (v2.4) | ORU^R01 pathology result as `au_oru_r01_pathology.hl7`, with the ADRM's PDF display form (`PDF^Display format in PDF^AUSPDI`, OBX-5 `^application^pdf^Base64^...`, pp 248-249) last in its group; the base64 content decodes to the two lines `%PDF-1.4` and `%Synthetic`, not a document. Validated by `AUFixtureTests` only: under the international locale it draws the v2.4 Table 0191 and 0291 findings by design, so `FixtureRoundTripTests` round-trips it but does not validate it | N/A — synthetic, written from scratch (P12 S3-2); HPI-O digits all zero-filled, not a real identifier; licence Apache 2.0, as the package |
| `au_oru_r01_radiology.hl7` | AU ADRM-2021 (v2.4) | ORU^R01 radiology report with a TXT (FT) display OBX; OBR-24 `RAD`; `AUFixtureTests` | N/A — synthetic, written from scratch (P12 S3-1); licence Apache 2.0, as the package |
| `au_orm_o01.hl7` | AU ADRM-2021 (v2.4) | ORM^O01 new order (ORC `NW`) addressed by MSH-6; `AUFixtureTests` | N/A — synthetic, written from scratch (P12 S3-1); licence Apache 2.0, as the package |
| `au_osr_q06.hl7` | AU ADRM-2021 (v2.4) | OSR^Q06 order status response (QRD, ORC `SR`, OBR); `AUFixtureTests` | N/A — synthetic, written from scratch (P12 S3-1); licence Apache 2.0, as the package |
| `au_orr_o02.hl7` | AU ADRM-2021 (v2.4) | ORR^O02 order acknowledgement (ORC `OK`) with PID; `AUFixtureTests` | N/A — synthetic, written from scratch (P12 S3-1); licence Apache 2.0, as the package |
| `au_ref_i12.hl7` | AU ADRM-2021 (v2.4) | REF^I12 in the Chapter 7 structure (DG1, AL1, two OBR/OBX groups) declaring no Appendix 8 profile, so it draws HL7au:000040.4 by construction; `AUFixtureTests` | N/A — synthetic, written from scratch (P12 S3-1); PRD-7 provider numbers `SYN-PRV-nnnn`, not real; licence Apache 2.0, as the package |
| `au_ref_i12_simplified.hl7` | AU ADRM-2021 (v2.4) | REF^I12 declaring the Appendix 8 simplified profile, Level 2 (MSH-12.3 `HL7AU-OO-REF-SIMPLIFIED-201706`); PRD `AP` and `IR`, one OBR group with an HTML display OBX; `AUFixtureTests` | N/A — synthetic, written from scratch (P12 S3-1); licence Apache 2.0, as the package |
| `au_rri_i12.hl7` | AU ADRM-2021 (v2.4) | RRI^I12 referral response echoing the simplified referral's RF1, PRD and PID; `AUFixtureTests` | N/A — synthetic, written from scratch (P12 S3-1); licence Apache 2.0, as the package |

### Batch fixtures (`Batches/` subdirectory)

These fixtures use the HL7 v2 batch grammar (FHS / BHS / BTS / FTS framing markers). The auto-discovering `FixtureRoundTripTests` harness only enumerates the top-level `Tests/Fixtures/` directory, so files under `Batches/` are intentionally skipped by `Parser.parse(_:)`-based round-trip tests — they would be ambiguous (FHS isn't a valid first segment for `Parser`). Instead, `BatchFixtureTests.swift` enumerates `Batches/` and exercises each file through `BatchParser` + `StreamingBatchParser`.

| File | Category | Purpose | Anonymisation log |
|---|---|---|---|
| `Batches/batch_bhs_minimal.hl7` | Batch (BHS-only) | BHS + 1 MSH + BTS — smallest valid batch wrapper | N/A — synthetic from scratch (v0.3-Z2) |
| `Batches/batch_file_full.hl7` | Batch (fully wrapped) | FHS + BHS + 2 MSH + BTS + FTS — exercises all four framing markers in one file | N/A — synthetic from scratch (v0.3-Z2) |
| `Batches/batch_multi_groups.hl7` | Batch (multi-group) | FHS + 2 BHS/BTS pairs + FTS — one ADT batch followed by one ORU batch | N/A — synthetic from scratch (v0.3-Z2) |
| `Batches/au_batch_oru_r01.hl7` | Batch (AU ADRM-2021) | FHS + BHS + the two AU ORU^R01 fixtures (pathology, radiology) + BTS + FTS; clean through `BatchValidator` under the AU locale, FHS separator fire pair; `AUFixtureTests` | N/A — synthetic, written from scratch (P12 S3-1); licence Apache 2.0, as the package |

### API-surface snapshots (`APISurface/` subdirectory)

Not messages: no fixture harness reads them, and they hold no patient data. `SegmentReleasedSurfaceTests` reads the released file by path and checks that each released declaration is still there; `AccessorSurfaceSnapshotTests` checks the `-unreleased` files for equality with HEAD.

| File | Category | Purpose | Anonymisation log |
|---|---|---|---|
| `APISurface/segment-structs-v3.13.0.txt` | API snapshot | Every `public` declaration in v3.13.0's `Sources/HL7v2Kit/Segment/Generated/` (`git show v3.13.0:<path>`), as `File\|signature` with the body and initial value removed (P9-4). v3.13.0 had no `@available` lines, so the deprecation attributes on the later aliases (P6-9) are pinned in `SegmentReleasedSurfaceTests` itself | N/A — no PHI; source declarations only |
| `APISurface/segment-accessors-unreleased.txt` | API snapshot | Every `public var` in the generated segment structs at HEAD (3602), as `File\|name\|type\|field index`. `AccessorSurfaceSnapshotTests` tests it for equality, so any rename, retype, drop, addition or re-index fails. Regenerate deliberately with `API_SURFACE_SNAPSHOT_WRITE=1 xcrun swift test --filter AccessorSurfaceSnapshotTests` and review the diff; promoted to the release snapshot at tag time | N/A — no PHI; source declarations only |
| `APISurface/composite-accessors-unreleased.txt` | API snapshot | Every `public var` in `Sources/HL7v2Kit/Composite/` (hand-written views and generated `+Components` extensions) at HEAD (181), as `File\|name\|type\|component index`. Same equality test, regeneration and promotion as the segment file | N/A — no PHI; source declarations only |

## Corrections log

- **2026-10-03 — nine v2.5.1 ADT fixtures made structurally valid against ADT_A01; one marked non-conformant by design** (P8b-5, G14). The message-structure check (ADR-019) at `.error` found 15 findings on 10 fixtures. Nine lacked EVN (`adt_a01_minimal`, `adt_a01_with_allergies`, `adt_a01_with_nk1`, `edge_empty_fields`, `edge_escape_sequences_in_name`, `edge_long_address`, `edge_minimal_pid_phone_only`, `edge_repeating_pid3_identifiers`, `edge_unicode_diacritics`): each gains `EVN||<MSH-7>` after MSH (EVN-1 is B in v2.5.1, so it is left empty; EVN-2 repeats the synthetic MSH-7 timestamp). `edge_empty_fields` and `edge_escape_sequences_in_name` carried a top-level NTE that ADT_A01 does not define: the narrative, escape sequences unchanged, moves to an `OBX|1|FT|SYN-NOTE^Narrative note^L||...||||||F` in ADT_A01's OBX position. `edge_minimal_pid_phone_only` lacked PV1 and gains a minimal one (PV1-1 `1`, PV1-2 `O`). `msh_with_z_only` keeps its MSH + ZTX shape and is listed in `FixtureStructureConformanceTests.deliberatelyNonConformant`. All content remains synthetic; the PHI scan passes. The default validation digest is unchanged; with the structure check on, only the 12 corrected findings disappear.
- **2026-09-21 — `MSH-9` completed in 48 v2.5.1 fixtures (49 MSH segments, batches included)** (M14). v2.5 onward prints all three `MSG` components as required; the fixtures carried `ADT^A01`-style values with no message structure, and the two ACK fixtures a bare `ACK`. Structures taken from v2.5.1 Table 0354 (`ADT_A01` for A01 / A04 / A08, `ORM_O01`, `ORU_R01`, `ACK^A01^ACK`). The v2.3, v2.3.1 and v2.4 fixtures are unchanged: those versions print no component optionality. Synthetic data; no PHI implications.
- **2026-09-20 — ordering provider moved from OBR-17 to OBR-16 in 13 synthetic fixtures** (`oru_r01_*`, `edge_many_nte`, `edge_obx_repeating_values`). Each carried a provider value such as `DR12121212^Foster^Taylor` (an XCN) in OBR-17, Order Callback Phone Number (XTN), with OBR-16 empty: an off-by-one from when the fixtures were written. The component-level code-table check (M10-C) exposed it, because XTN.2 and XTN.3 are coded. Synthetic data; no PHI implications.
- **2026-09-20 — `oru_r01_v24.hl7` MSH-18 changed from `UNICODE UTF-8` to `ASCII`** (A5): base v2.4 Table 0211 does not print the UTF-8 value.

## Anonymise tool semantics

The `anonymise-fixture.sh` script is deterministic but **one-shot**:

- **Deterministic:** same input file → byte-identical output. The per-file salt is derived from MSH-10, so two runs on the same input produce the same output.
- **One-shot:** running anonymise on an already-anonymised file produces *different* output. The DOB scrubber shifts the input date by `±(salt mod 60 / 2)` days; the second pass shifts again from the already-shifted date. All other fields (names, addresses, phones, IDs, facilities) are idempotent — only DOB drifts on repeated passes.

The expected workflow is one anonymise pass per real-world input, then commit. If you accidentally re-anonymise, revert to the input and try again.

## Adding a fixture

If you have a real-world v2 message you want to add to the corpus:

1. Run it through `bash scripts/anonymise-fixture.sh <input>.hl7 anonymised.hl7`. The script applies spec § 10's scrubbing rules deterministically (per-file salt derived from MSH-10).
2. Manually diff the output to confirm no real names / addresses / IDs survived.
3. Run `bash scripts/scan-fixtures-for-phi.sh` to confirm no AU-identifier patterns leak.
4. Add the file under `Tests/Fixtures/` with a `\r` line terminator.
5. Add a row to the provenance table above documenting source, licence, and what the anonymisation step actually changed.
6. If the fixture should round-trip cleanly, no test code change is needed — the harness in `Tests/HL7v2KitTests/FixtureRoundTripTests.swift` auto-discovers `*.hl7` files.
7. If the fixture is **expected to fail parsing** (malformed corpus), add its filename to the `malformed_` prefix convention and the harness's expected-failure list.

## Adding a synthetic fixture (no PHI gate needed)

Files generated from scratch don't need the anonymise step. Skip directly to
step 4 above (commit + provenance row, mark "synthetic from scratch" in the
anonymisation log column).
