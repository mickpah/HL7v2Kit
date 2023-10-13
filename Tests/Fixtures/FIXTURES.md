# Test fixture corpus

Every fixture in this directory must be **synthetic** v2 data with no real PHI.
The `scripts/anonymise-fixture.sh` script (Task 7a, 2026-06-13) is the only
gate by which a real-world-derived fixture could enter the corpus, and even
then the output must be scanned via `scripts/scan-fixtures-for-phi.sh` before
commit.

Status v0.1.0: synthetic starter set (7a); the full 48-fixture corpus per
spec § 9.2 is 7b work.

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
