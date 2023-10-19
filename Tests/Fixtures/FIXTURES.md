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
| `adt_a01_minimal.hl7` | ADT^A01 (admit) | MSH + PID + PV1 — smallest valid admit message | N/A — synthetic from scratch |
| `adt_a01_with_nk1.hl7` | ADT^A01 (admit) | MSH + PID + NK1 + PV1 — admit with next-of-kin contact | N/A — synthetic from scratch |
| `orm_o01_lab_order.hl7` | ORM^O01 (order) | MSH + PID + ORC + OBR — lab order for glucose | N/A — synthetic from scratch |
| `oru_r01_chemistry.hl7` | ORU^R01 (result) | MSH + PID + OBR + 3 × OBX — chemistry panel results | N/A — synthetic from scratch |
| `oru_r01_with_z_segment.hl7` | ORU^R01 + Z-segments | MSH + PID + ZAU + OBR + OBX + ZPI — AU-style Z-segment overlay | N/A — synthetic; Z-segments are facility-specific dummy data |
| `edge_empty_fields.hl7` | Edge case | Empty fields + `\F\` `\S\` `\T\` escape sequences in NTE-3 | N/A — synthetic |
| `malformed_missing_msh.hl7` | Malformed | Starts with PID instead of MSH — parser must throw `.missingMSH` | N/A — synthetic |
| `malformed_invalid_encoding_chars.hl7` | Malformed | MSH-2 = `^^^^` (encoding chars not distinct) — parser must throw `.invalidMSH` | N/A — synthetic |
| `adt_a01_with_allergies.hl7` | ADT^A01 (admit) | MSH + PID + PV1 + 2 × AL1 — admit with drug allergies | N/A — synthetic from scratch |
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
| `msh_with_z_only.hl7` | MSH + Z-segment | Heartbeat-style: MSH + ZTX only (no PID) | N/A — synthetic from scratch |
| `malformed_msh_too_short.hl7` | Malformed | MSH segment truncated to `MSH\|^~` — parser must throw `.invalidMSH("too short")` | N/A — synthetic |
| `malformed_msh_no_field_sep_after_enc.hl7` | Malformed | Char after MSH-2 encoding chars isn't `\|` — `.invalidMSH("MSH-2 not followed by field separator")` | N/A — synthetic |
| `malformed_unsupported_charset.hl7` | Malformed | MSH-18 = `GB18030` (unsupported) — `.unsupportedCharacterEncoding` | N/A — synthetic |
| `malformed_empty.hl7` | Malformed | Zero-byte file — `.emptyInput` | N/A — synthetic |
| `edge_unicode_diacritics.hl7` | Edge | UTF-8 names with diacritics (García, José, Søren, Müller) | N/A — synthetic |
| `edge_repeating_pid3_identifiers.hl7` | Edge | PID-3 with 3 repetitions (MR + MC + NH) via `~` | N/A — synthetic |
| `edge_long_address.hl7` | Edge | Very long PID-11 address components | N/A — synthetic |
| `edge_escape_sequences_in_name.hl7` | Edge | `\F\`, `\H\`, `\N\`, `\X0D\` escape sequences in PID-5 and NTE | N/A — synthetic |
| `edge_many_nte.hl7` | Edge | ORU with 4 trailing NTE segments after OBX | N/A — synthetic |
| `edge_minimal_pid_phone_only.hl7` | Edge | Sparsely populated PID — name + phone only | N/A — synthetic |
| `edge_obx_repeating_values.hl7` | Edge | OBX-5 + OBX-8 with `~` repetitions (3-sample BP series) | N/A — synthetic |
| `adt_a01_v23.hl7` | Multi-version (v2.3) | v2.3 ADT^A01 admit — exercises the v2.3 grammar table (MSH cap at 15) | N/A — synthetic from scratch (v0.3-Z2) |
| `orm_o01_v231.hl7` | Multi-version (v2.3.1) | v2.3.1 ORM^O01 order — exercises the v2.3.1 grammar table (PID cap at 30, ORC cap at 17) | N/A — synthetic from scratch (v0.3-Z2) |
| `oru_r01_v24.hl7` | Multi-version (v2.4) | v2.4 ORU^R01 result — populates PID-31/32 (identityUnknownIndicator / identityReliabilityCode, the v2.4 additions); MSH-18 charset declared | N/A — synthetic from scratch (v0.3-Z2) |

### Batch fixtures (`Batches/` subdirectory)

These fixtures use the HL7 v2 batch grammar (FHS / BHS / BTS / FTS framing markers). The auto-discovering `FixtureRoundTripTests` harness only enumerates the top-level `Tests/Fixtures/` directory, so files under `Batches/` are intentionally skipped by `Parser.parse(_:)`-based round-trip tests — they would be ambiguous (FHS isn't a valid first segment for `Parser`). Instead, `BatchFixtureTests.swift` enumerates `Batches/` and exercises each file through `BatchParser` + `StreamingBatchParser`.

| File | Category | Purpose | Anonymisation log |
|---|---|---|---|
| `Batches/batch_bhs_minimal.hl7` | Batch (BHS-only) | BHS + 1 MSH + BTS — smallest valid batch wrapper | N/A — synthetic from scratch (v0.3-Z2) |
| `Batches/batch_file_full.hl7` | Batch (fully wrapped) | FHS + BHS + 2 MSH + BTS + FTS — exercises all four framing markers in one file | N/A — synthetic from scratch (v0.3-Z2) |
| `Batches/batch_multi_groups.hl7` | Batch (multi-group) | FHS + 2 BHS/BTS pairs + FTS — one ADT batch followed by one ORU batch | N/A — synthetic from scratch (v0.3-Z2) |

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
