# Segment-coverage extraction pipeline (ADR-015)

The dev-time tooling that makes the **M5** full-segment-coverage program (ROADMAP M5,
`[[v1-0-requires-all-version-feature-parity]]`) tractable *and* trustworthy. Reads the
author-local HL7 Final-Standard PDFs and recovers each segment's attribute table as
structured per-field data, to **seed and cross-check** the hand-reviewed
`Resources/schemas/<version>/<SEG>.json`.

> **Not shipped.** This is a contributor tool. `Package.swift.dependencies` stays empty;
> the package has no runtime dependency on any of the below. The committed, reviewable
> artifacts remain the schema JSON (source of truth) + the codegen-emitted Swift.

## Prerequisites

- **poppler** — `pdftotext` (`brew install poppler`; already present at
  `/opt/homebrew/bin/pdftotext`). The layout-preserving extractor. See ADR-015 for why
  this beats PDFKit (`.string` reads the tables column-major; `characterBounds`
  fragments on the 1997-vintage PDFs).
- **Xcode Swift toolchain** — the tool is a Swift script run via `xcrun swift`.
- The **author-local Final-Standard PDFs** under `docs/standards/…` (IP-review-gated;
  never committed). Absent PDFs make the tool a no-op, never an error.

## The tool

`scripts/extract-segment-tables.swift`

```bash
# Dump every attribute table in a chapter as structured JSON:
xcrun swift scripts/extract-segment-tables.swift <chapter.pdf>

# One segment only:
xcrun swift scripts/extract-segment-tables.swift <chapter.pdf> NK1

# Golden/verify mode — compare the extracted DT/OPT/RP + field count against a
# committed canonical schema. PASS/FAIL, exit 0/1. SKIPs cleanly if the PDF is absent.
xcrun swift scripts/extract-segment-tables.swift --verify <chapter.pdf> NK1 \
    Resources/schemas/v2.5.1/NK1.json
```

How it works: `pdftotext -layout` → locate each `HL7 Attribute Table` header → bin every
row into columns by nearest header-center (robust to values being centered under, not
left-aligned to, their header) → fold continuation lines (wrapped element names,
multi-line `TBL#`) → survive page breaks (skip footers / running heads / form-feeds and
re-read the repeated header, whose column spacing differs per page) → stop at the
`N.N.N field definitions` section. `RP/#` maps to repeatability (`Y` or a max-count →
`*`, blank → `1`); a `(B)`/`(B) X` optionality reduces to `B`.

**Authoring discipline is unchanged (the working notes req #2 / #4):** the tool *proposes*; a
human *verifies against the spec text* and the schema carries its citation. Automation
removes transcription and column-misread error; it does not remove the review.

## Validation — the golden gate

The tool's trustworthiness was established by running `--verify` against the already
hand-reviewed canonical v2.5.1 schemas. On the clean tables it reproduced `DT` / `OPT` /
`RP` / field-count **exactly** (e.g. NK1 = 39, matching the v0.19 canonical). Where it
disagreed, **the tool was right** in every case that resolved to a real error — it
surfaced defects the pre-pipeline hand-authoring (from PDFKit's column-jumbled output)
had introduced. That is the strongest possible validation, and it is the reason M5 needs
this pipeline rather than more hand-reading.

Re-run the full gate any time with the loop in the commit for `v1.1-S2`.

## Findings — canonical v2.5.1 golden audit (15 typed segments)

Running `--verify` across all 15 typed segments' canonical v2.5.1 schemas
(2026-07-12). **7 pass clean:** MSH, ERR, NTE, EVN, PD1, AL1, DG1. The other 8 surfaced
three distinct classes (only A + B are defects):

### A. Confirmed field-metadata defects (extractor authoritative; simple tables, unambiguous PDF)

| Field | Element | Spec (PDF) | v0.19/earlier schema | Error |
|---|---|---|---|---|
| MSA-5 | Delayed Acknowledgment Type | OPT `W`, DT blank | OPT `X`, DT `ST` | withdrawn field mis-modelled as X/ST |
| NK1-26 | Mother's Maiden Name | RP `Y` | `1` | repeatable missed |
| PID-38 | Production Class Code | RP `2` | `1` | repeatable (max 2) missed |
| PV1-9 | Consulting Doctor | OPT `B` | `O` | B flattened to O |
| PV1-40 | Bed Status | OPT `B` | `O` | B→O |
| PV1-45 | Discharge Date/Time | RP `Y` | `1` | repeatable missed |
| PV1-50 | Alternate Visit ID | RP blank | `*` | over-marked repeatable |
| PV1-52 | Other Healthcare Provider | OPT `B` | `O` | B→O |
| IN1-38 | Policy Limit - Amount | OPT `B` | `O` | B→O |
| IN1-40 | Room Rate - Semi-Private | OPT `B` | `O` | B→O |
| IN1-41 | Room Rate - Private | OPT `B` | `O` | B→O |

Root cause: PV1/IN1/NK1 were authored in v0.19 (and OBX/OBR/MSA earlier) by reading the
PDFs via PDFKit, whose column-major output interleaves exactly the `OPT` and `RP/#`
columns — the columns in error here. This is the failure mode ADR-015 exists to end.

### B. Incomplete schemas (real spec fields never authored)

| Segment | Schema depth | Spec depth | Missing |
|---|---|---|---|
| OBR | 47 | 50 | 48 Medically Necessary Duplicate Procedure Reason (CWE, C); 49 Result Handling (IS, O); 50 Parent Universal Service Identifier (CWE, O) |
| OBX | 17 | 24 | 18 Equipment Instance Identifier (EI, O, Y); 19 Date/Time of the Analysis (TS, O); 20/21/22 Reserved for harmonization with V2.6; 23 Performing Organization Name (XON, O); 24 Performing Organization Address (XAD, O) |

### C. Deliberate conditional (`C`) modelling — NOT defects

The verify tool also flags every field where the schema's `OPT` differs from the raw
attribute-table letter. For the OBR/ORC conditional set this divergence is **intentional
and spec-cited** — the schema upgrades the raw `O`/`B` to `C` per the §4.5 conditional
rules (v0.11 XOR softening + v0.16 conditional-completeness), already recorded in
`conditional-completeness-audit.md`:

- **ORC-8** (raw `O` → schema `C`, §4.5.1.8 Parent XOR).
- **OBR-1 / 8 / 9 / 10 / 11 / 14 / 20 / 21 / 22 / 26 / 29 / 32** (raw `O`/`B` → schema `C`).

These need **no change**; they are the reason the tool is an *aid*, not an auto-writer —
a human distinguishes "intentional conditional upgrade" from "transcription defect".
(`ORC-26` — raw `C` vs schema `O` — is the one remaining item to reconcile individually
against §4.5 during the correction cycle.)

## Correction runway (next M5 cycles)

The Class-A + Class-B findings are req-#4 defects/gaps in the **canonical v2.5.1** surface
that underpins the typed segments. They should be corrected as an additive/fix cycle
(schema edits → `regenerate-typed-segments.sh` → cross-check tests → the new
OBX/OBR accessors are additive, ADR-014-clean; the OPT/RP fixes are validation-behaviour
corrections). Then the sweep extends per-version and to the ~135 unmodelled segments off
the S3 inventory. Every step runs the golden gate above.

## Known extraction limitations + v1.5 hardening backlog (found during the v1.4 sweep)

The v1.4 batches (query/lab + master-file/care, 57 → 85 typed) surfaced extractor edge
cases that affect **datatype fidelity** on specific PDF layouts. They do not crash or
misfire validation (an empty/wrong `dataType` yields an untyped `Field?` accessor, and the
field still parses / round-trips), but they are a req-#2/#4 faithfulness gap. **A dedicated
v1.5 "extractor hardening" cycle is planned** to fix all three items below, then regenerate
+ re-verify **every** segment across all versions from a clean extractor.

1. **Column assignment mis-bins right/left-leaning values.** `nearestColumnKey` assigns
   each run to the nearest header-label **centre**. Where a table's `DT` values sit well to
   the right of the label (v2.5.1 **CH12 GOL** — GOL-1 `Action Code` extracts empty `DT`
   instead of `ID`; GOL-4/5 drop `EI`) or a hair left (v2.5.1 **CH04 BPO** — `CWE` just left
   of the `DT` label), the datatype is dropped/mis-assigned. **Fix (validated in a v1.4
   spike, then reverted for stability):** assign by smallest distance between the run's
   **start** and each label's **start** — resolved GOL *and* BPO and kept golden NK1/PV1/IN1
   passing. A full re-verify will enumerate all affected segments (GOL, OM1/OM4, other
   wide-column CH08/CH12 tables).
2. **Spurious `index:0` rows on some tables.** OM4 (CH08) parses three non-field lines as
   rows (`index:0`, empty name/DT) — they collide on derived swiftName `field3` (breaks
   codegen) and mask three real trailing fields. Row detection must reject `seq < 1` and
   empty-name/empty-DT rows, and diagnose why the real SEQ tokens weren't read.
3. **`deriveSwiftName` must guarantee global uniqueness** (the `field3` collision) and drop
   possessive `'s` fragments (v1.2 saw `contactPersonSTelecom…`).

**Performance note:** `swift <file>` recompiles the ~500-line script every invocation,
making full regeneration impractically slow. Compile once —
`xcrun swiftc -O scripts/extract-segment-tables.swift -o /tmp/extractbin` — and drive
regeneration from the binary (~20× faster; full canonical re-verify then takes minutes).
