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

## v1.5 extractor hardening — the three v1.4 items (DONE)

The v1.4 batches (query/lab + master-file/care, 57 → 85 typed) surfaced extractor edge
cases affecting **datatype fidelity** on specific PDF layouts. They did not crash or
misfire validation (an empty/wrong `dataType` yields an untyped `Field?` accessor, and the
field still parses / round-trips), but they were a req-#2/#4 faithfulness gap. All three
are now fixed in `scripts/extract-segment-tables.swift`:

1. ✅ **Column assignment mis-binned right/left-leaning values.** `nearestColumnKey`
   assigned each run to the nearest header-label **centre**. Where a table's `DT` values sit
   well right of the label (v2.5.1 **CH12 GOL** — GOL-1 `Action Code` extracted empty `DT`
   instead of `ID`; GOL-4/5 dropped `EI`) or a hair left (v2.5.1 **CH04 BPO** — `CWE` just
   left of the `DT` label), the datatype was dropped/mis-assigned. **Fixed:** `columnKey(forStart:)`
   assigns by smallest distance between the run's **start** and each label's **start** —
   resolves GOL *and* BPO, golden NK1/PV1/IN1 still pass.
2. ✅ **Spurious rows from wrapped `LEN` digits.** Row detection now rejects `seq < 1` and
   any row with **both** an empty name and an empty `DT`. Root cause identified: these were
   never "non-field lines" in general — they are the **overflow digits of a wrapped `LEN`
   cell** landing left of the `DT` column (OM6's `10240` wraps, leaving a bare `0`; EQP's
   `65536` leaves a bare `6`; OM4/OM1 likewise). They both inflated field counts and
   collided on derived swiftNames (`field2`, `field3`).
3. ✅ **`deriveSwiftName`** drops lone `s` fragments left by a possessive apostrophe
   (`Contact Person's Name` → `contactPersonName`, not `contactPersonSName`).

### Rule: empty `dataType` is not automatically a defect

The audit's initial "63 empty-DT defects" were **mostly false positives**. An empty `DT` is
**spec-correct** when optionality is `W` (withdrawn) or `X` (reserved) — those HL7 fields
have no datatype by design. Every flagged v2.6/v2.8.2 RX\*/IN1/PV1/MRG/SCH/SAC/TCC/GOL/INV
field is `W`; OBX-20/21/22 are `X`.

> **Audit predicate:** an empty `dataType` is a defect only if `OPT ∉ {W, X}`.

### Rule: wholesale regeneration is unsafe — DT fixes must be surgical

Regenerating a whole segment (or a whitelist) to fix a datatype **loses hand-authored
work**: it drops the `condition` predicates on ORC/OBR/PID/DG1/OBX, reproduces any
still-mis-binned DTs (regen ≠ fix), and title-cases element names (a fidelity regression).
Fix the specific field in the schema JSON instead.

### Fixed in v1.5 (each verified against the spec PDF, not just the extractor)

| Segment | Was | Now | Spec citation |
|---|---|---|---|
| v2.5.1 OM1 | 49 fields | **47** | CH08 §8.8, last row 47 `Modality Of Imaging Measurement` |
| v2.5.1 OM4 | 17 fields | **14** | CH08 §8.8, last row 14 `Specimen Retention Time` |
| v2.5.1 OM6 | 3 fields | **2** | CH08 §8.8.13, `LEN 10240` wraps → phantom `0` row |
| v2.5.1 EQP | 6 fields | **5** | CH13 §13.4.12, `LEN 65536` wraps → phantom `6` row |
| v2.5.1 GOL | 1/4/5 empty DT | **ID / EI / EI** | CH12 GOL attribute table |
| v2.3.1 GOL | 1–20 empty DT | **filled** | CH2 §2.24 Figure 12-2 (matches v2.3 / v2.4) |
| RDT (all 6) | wrong segment / prose | **1 field, `Column Value`** | see below |

**RDT was wrong in every version.** v2.3 / v2.3.1 held the **SPR segment's** four fields;
v2.4 / v2.5.1 / v2.6 / v2.8.2 held corrupted prose. Root cause: in v2.3 / v2.3.1 RDT is
defined in **Chapter 2** (§2.24.19, *Figure 2-26. RDT attributes*), **not** CH05 — the
extractor was pointed at the query chapter and bound the nearest table it found. Correct
RDT, confirmed in all six PDFs: a single field, SEQ `1-n`, `Column Value`, `OPT R`, `RP`
blank, ITEM 00703. The `DT` literal is per-version — v2.3 / v2.3.1 / v2.4 print `Variable`,
v2.5.1 / v2.6 / v2.8.2 print `varies` — tracked per-version exactly as `TS`→`DTM` and
`CE`→`CWE` already are.

> **Model limitation (req #3):** SEQ `1-n` means the field *position* recurs — RDT carries
> an unbounded number of `|`-separated columns. The schema model indexes fields, so only
> column 1 is described; columns 2..n are unvalidated (the validator iterates
> `grammar.fields`, so they are silently ignored, never spuriously flagged).
> `RP` stays `1` because the spec's `RP/#` cell **is blank** — marking it `*` would assert
> `~`-repeatability the spec does not grant. The other `1-n` segment is **ADD**-1
> (`Addendum Continuation Pointer`, ITEM 00066), not yet modelled.

## v1.5-S2 element-name fidelity (DONE)

A **fourth** defect class: on some tables the row scan ran past the table end and folded the
following prose into the final row's element `name`. Three distinct root causes, all fixed:

1. **Table-end heading undetectable when the chapter number carries a letter.**
   `isFieldDefinitionsHeading` required the leading token to be digits-and-dots only, but
   v2.8.2 splits the pharmacy chapter into 4 and **4A**, numbering sections
   `4A.4.3.0 RXC field definitions`. The table never ended, so the *entire*
   field-definitions section (hundreds to thousands of characters — component lists, table
   references, whole paragraphs) was appended to the last row's name. Hit v2.8.2 `RXA-29`,
   `RXC-11`, `RXD-35`, `RXE-45`, `RXG-33`, `RXO-36`, `RXR-6`. **Fixed:** the leading token
   now matches `^[0-9]+[A-Za-z]?(\.[0-9]+)+$`.
2. **Unbounded continuation folding.** Any non-row line was folded into the previous row's
   name. The explanatory note that sits between table and definitions on CH12 ("the business
   and/or application must assume responsibility for maintaining knowledge about data
   ownership…") therefore contaminated `PRB-25` (v2.3 / v2.3.1 / v2.4 / v2.5.1) and
   `PRB-28` / `GOL-22` (v2.6 / v2.8.2). **Fixed:** `isNameContinuation` accepts a fragment
   only if it is short (≤ 60 chars), carries no sentence punctuation, has no `^`/`|`/`<`
   component-example markers, and keeps the accumulated name under 120 chars.
3. **Long names truncated at the front.** Element names are *centred* under the
   `ELEMENT NAME` label, so a long one starts left of the label's offset and a fixed-offset
   slice cut its head off — `Administered Tag Identifier` → `ministered Tag Identifier`,
   `Pharmacy Phone Number` → `armacy Phone Number`, `Administration Site Modifier` →
   `inistration Site Modifier`. This was latent behind (1): fixing the table end exposed it.
   **Fixed:** `nameBoundary(runs:nameStart:)` anchors the name on the rightmost 4–5 digit
   numeric metadata run (ITEM #, or TBL # when the item number is blank) and takes what
   follows; it falls back to the header offset for rows with no numeric metadata. The same
   boundary now bounds metadata binning, so a left-shifted name no longer overwrites `ITEM`.

Also tightened: a row with an empty name is now rejected when its `DT` is **under 2
characters**, not merely empty. Every real HL7 datatype token is 2+ chars, so a
single-character DT is a wrapped-cell tail — v2.5.1 `OBX-5`'s `varies` wraps as `varie` +
`s`, and that orphan `s` was being parsed as an entire extra row (the same artifact produced
the bogus pre-v1.5 RDT field).

**Two false-positive classes confirmed as faithful, deliberately left alone:** the attribute
tables literally print `Set ID- TXA` (v2.3 / v2.3.1 / v2.4 / v2.6 / v2.8.2) and
`Sequence Number- Test/Observation Master File` (v2.4 OM2–OM6) — no space after the hyphen —
while the *field-definition headings* on the same pages print them with spaces. The schemas
follow the attribute table, which is the pipeline's authoritative source. Fidelity to a spec
typo is correct behaviour (req #2); 10 of the 24 originally-flagged names were this.

Blast radius of the 14 real corrections was the **grammar tables** (`FieldGrammar.name` →
validator message text) and the reference surface, *not* Swift identifiers — typed structs
generate from the canonical v2.5.1 schemas only.

## v1.6 per-version depth audit (DONE)

The S2 finding, resolved. Every committed schema's depth was diffed against **its own
version's** attribute table, by extracting every table in every chapter of all six versions
and comparing max field index.

**Method** (re-runnable; the audit script pattern is worth keeping):

1. `xcrun swiftc -O scripts/extract-segment-tables.swift -o /tmp/extractbin` — the
   `swift <file>` path recompiles per invocation and is far too slow for ~90 chapter scans.
2. For each version, run the binary over every chapter PDF with no segment filter; collect
   `segmentHint → max field index`, keeping the deepest table seen per segment.
3. Diff against the committed schemas in **both** directions, and treat them differently:
   - **GAP** (extractor deeper than schema) → candidate missing fields.
   - **SUSPECT** (extractor shallower) → an extraction problem to investigate, *never* a
     depth answer. A shallow extraction is the tool failing, not the spec.

**Result:** 436 of 458 schemas matched exactly on the first pass; **46 fields across 14
(version, segment) pairs had never been authored**, all on core segments:

| Version | Segment | Was | Now | Added |
|---|---|---|---|---|
| v2.3 | MSH | 15 | **19** | 16–19 (Application Ack Type, Country Code, Character Set, Principal Language) |
| v2.3 | OBX | 11 | **17** | 12–17 |
| v2.3 | ORC | 17 | **19** | 18–19 (Entering Device, Action By) |
| v2.3.1 | MSH | 17 | **20** | 18–20 |
| v2.3.1 | NTE | 3 | **4** | 4 (Comment Type) |
| v2.3.1 | OBR | 43 | **45** | 44–45 (Procedure Code, Procedure Code Modifier) |
| v2.3.1 | OBX | 14 | **17** | 15–17 |
| v2.3.1 | ORC | 17 | **24** | 18–24 |
| v2.4 | MSH | 20 | **21** | 21 (Conformance Statement ID) |
| v2.4 | NTE | 3 | **4** | 4 |
| v2.4 | OBX | 16 | **19** | 17–19 |
| v2.4 | ORC | 19 | **25** | 20–25 |
| v2.4 | PID | 32 | **38** | 33–38 |
| v2.5.1 | OBX | 24 | **25** | 25 (Performing Organization Medical Director) |

After the fills: **452 / 458 match exactly, 0 suspects, 0 unlocated.**

### Per-version element names must never be copied from the canonical schema

The fill work exposed a **naming** trap. Sourcing an added field's `name` from the canonical
v2.5.1 schema (for cross-version consistency) is **wrong** — HL7 renames fields between
versions, so the canonical name is often not that version's name:

| Field | v2.3 / v2.3.1 | v2.4 | v2.5.1 | v2.6 / v2.8.2 |
|---|---|---|---|---|
| OBX-12 | Date Last Obs Normal Values | Date Last Observation Normal Value | Effective Date of Reference Range **Values** | Effective Date of Reference Range |
| OBX-15 | Producer's ID | Producer's ID | Producer's **Reference** | Producer's ID |
| MSH-21 | — | **Conformance Statement ID** (ID) | Message Profile Identifier (EI) | Message Profile Identifier (EI) |

Note MSH-21: v2.5 renamed *and* retyped it without changing the field count, so a
depth-only audit would never have caught it.

This also surfaced **two pre-existing name defects in the canonical v2.5.1 OBX schema**:
OBX-12 was truncated (`…Reference Range`, missing `Values`) and OBX-15 carried the
neighbouring versions' `Producer's ID` instead of `Producer's Reference`.

> **Deviation recorded (ADR-014) — RESOLVED at 2.0 (remediation R10, 2026-08-27):** the two
> `swiftName`s were frozen public API through 1.x while their DocC text and grammar entries
> read the spec wording. The rename shipped at the 2.0 boundary: OBX-12 is now
> `effectiveDateOfReferenceRangeValues`, OBX-15 is `producersReference` (schema `swiftName` +
> regenerate; the Generated/ diff was exactly the two accessor declarations).

**Rule:** take `DT` / `OPT` / `RP` *and* `name` from the version's own attribute table.
Only reach for another version's schema when the extraction is visibly corrupted, and then
hand-verify against the PDF.

### v1.7 — a length predicate catches what marker-matching missed

The v1.5-S2 prose-bleed sweep detected corrupted element names by matching prose *marker
words* (`It is`, `would`, `knowledge`, …). That under-detects: the v1.7 batch's integrity
run added a plain **name-length** predicate (`len(name) > 120`) and immediately found **five
more instances of the same class** that the marker regex had walked straight past —
`TQ2-10` (v2.5.1 / v2.6 / v2.8.2, up to 1069 characters), `BPX-21` and `BTX-20` (v2.8.2).
All three segments were authored in v1.2 / v1.3, before the extractor's table-end and
continuation fixes landed, and were never re-extracted.

True names, confirmed against the CH04 tables: `Special Service Request Relationship`,
`BP Dispensing Individual`, `BP Unique ID`. Fixed in v1.7.

**Lesson:** prefer a *shape* predicate (length, character class) over an *enumerated
content* predicate (marker words) when auditing for corruption. Marker lists only find the
corruption you already thought of. The audit predicate set is now: phantom rows, empty
`dataType` with `OPT ∉ {W, X}`, duplicate field index, gaps in the index sequence,
prose-marker names, **name length > 120**, and depth-vs-spec in both directions.

### Known extractor limitation — `1-n` variable-column segments

The row parser requires the SEQ cell to be a bare integer, so a `1-n` SEQ row (RDT-1, ADD-1)
never parses. For RDT the scan then runs on and binds whatever table follows: in v2.3 /
v2.3.1 it returns the **SPR** segment's four fields (items 00696 / 00697 / 00704 / 00705 —
exactly the content wrongly committed as RDT before v1.5-S1), and in v2.4+ a query-example
column table. **RDT therefore shows as a permanent 6-row GAP in the depth audit and must be
whitelisted**; its schema is hand-authored and correct (one field, `Column Value`). Any
future `1-n` segment needs the same treatment.

> **Sprint 0 §3 fix (2026-08-28) — the run-on no longer crosses a caption.** The same
> mechanism hid a whole segment: v2.4/v2.5.1 CH02 reported `ADD` with **BHS's** 12 fields
> and no `BHS` at all, because the empty `ADD` scan took BHS's header as a "stray duplicate
> before first row". An empty-rowed table now ends when a header with a *different* caption
> appears (`extractTables`, the `rows.isEmpty && caption != segHint` branch). Harness: full
> caption diff on v2.4 and v2.5.1 = exactly `−ADD +BHS`; depth audit unchanged. A `1-n`
> table followed by a *caption-less* table (the v2.4+ query-example columns after RDT) can
> still bind it, so the RDT whitelist stays. `ADD` is now simply absent from the caption set
> — hand-authored like RDT on all four AU-priority versions (§3C) and whitelisted alongside it.

### Spec-text defects normalised in authored schemas

The attribute table is authoritative, but a handful of cells are typeset wrong in the PDF
itself. Each is normalised in the schema and listed here so `--verify` FAILs are explainable:

| Version | Field | PDF cell | Schema | Evidence |
|---|---|---|---|---|
| v2.4 | EDU-2 OPT | *(blank)* | `O` | v2.5.1 table `O`; no conditionality stated in the EDU-2 definition. `--verify` reports this one mismatch. |
| v2.4 | EDU-4 name | `…Program ParticipationDate Range` | `…Program Participation Date Range` | The field's own definition heading (15.4.2.4) is spaced. `--verify` does not compare names. |

Caption matching was also widened to accept the singular (`Figure 2-10. ERR attribute`) —
the plural-only pattern silently excluded v2.3 / v2.3.1 ERR from the audit's coverage.

### The original S2 finding (kept for the record — CLOSED in v1.6)

The hardened extractor's golden sweep surfaced a **fifth, unrelated class**: segments whose
schemas stop short of the spec's field count. Confirmed on **OBX**, a core segment:

| Version | Schema depth | Spec depth | Missing |
|---|---|---|---|
| v2.5.1 | 24 | **25** | OBX-25 `Performing Organization Medical Director` (XCN, O, ITEM 02285) |
| v2.3 | 11 | **17** | OBX-12 … OBX-17 (through `Observation Method`) |
| v2.3.1 | 14 | *unverified* | — |
| v2.4 | 16 | *unverified* | extraction breaks at field 4 on this layout — needs a manual read |
| v2.6 | 25 | 25 | ✅ |
| v2.8.2 | 30 | 30 | ✅ |

The v1.1 audit completed OBX 17 → 24 but stopped one field short of the v2.5.1 table, and
never covered the legacy versions. **This is a req-#1/#4 completeness gap, not a
faithfulness gap, and it is almost certainly not limited to OBX** — the same "canonical
depth pinned, per-version depth assumed" pattern applies across the 85 typed segments.

*Closed by the v1.6 audit above.*


**Performance note:** `swift <file>` recompiles the ~500-line script every invocation,
making full regeneration impractically slow. Compile once —
`xcrun swiftc -O scripts/extract-segment-tables.swift -o /tmp/extractbin` — and drive
regeneration from the binary (~20× faster; full canonical re-verify then takes minutes).

---

## R6 tokenizer note (2026-08-27)

The extractor's hand-rolled offset tokenizer `runs(in:)` was replaced with a Swift Regex
(`#/[^ ](?: [^ ]|[^ ])*/#`) in remediation stage R6. The swap exposed a latent fidelity defect:
the old scanner **never appended single spaces to run text** (despite its own comment), so
multi-word cells consumed as `run.text` were silently collapsed — v2.3 CH7's waveform
`NA or MA` datatype cell extracted as `NAorMA`. Element names were unaffected (they are
re-sliced from the raw line by offsets). Harness evidence: v2.5.1 CH03 full-chapter extraction
**byte-identical**; v2.3 CH7 differing in exactly that one now-PDF-verbatim row; the all-PDF
depth audit clean; zero committed schemas carried either form. Offsets are Character distances,
matching the old `Array(line)` indexing; the only other delta (a line ending in exactly one
trailing space no longer counts it in the final run's `end`) is unreachable in both consumers.

---

## Sprint 0 presence predicate (2026-08-28)

`scripts/audit-schemas.py --depth` was structurally blind to an **absent** segment: the depth
loop iterates the schemas that exist, so a segment the spec defines on a version we never
authored there produced no finding. That is how the v2.4 lab-automation gap
(`EQU/SAC/INV/TCC/TCD/EQP`, 94 fields) survived three "fully clean" audits after v1.4
authored them as "v2.5+".

The pass now also diffs each version's **extracted caption set** (the same
`extracted_depths` output the depth check already consumes) against
`Resources/schemas/<version>/`:

- **PRESENCE** — the segment has a schema on some *other* version but not this one. A
  defect; non-zero exit. Written red-first: before authoring it reported exactly the six v2.4
  segments and nothing else.
- **never-authored backlog** — no schema on any version. Reported as a per-version count
  (the live M5 remainder), not failed. Baseline 2026-08-28: v2.3 24, v2.3.1 27, v2.4 37,
  v2.5.1 41, v2.6 61, v2.8.2 73 = 263 instances (before the `1-n` fix below and the
  Z-segment exclusion; after §3A: 22 / 25 / 30 / 34 / 54 / 66 = 231).
- **deferred** (added §3A) — a modelled-elsewhere absence on an owner-deferred version
  (`DEFERRED_VERSIONS = {v2.6, v2.8.2}`, per `deferred-coverage-backlog.md`). Listed, not
  failed: the AU-first sequencing authors a segment on v2.3–v2.5.1 first, which the plain
  PRESENCE rule would report as defects. Z-segments are skipped outright (site-defined).

Predicate shape, per the house rule: a set difference over what the extractor already
produces — no caption list to maintain, so it catches segments nobody thought to enumerate.
Caveat carried from `segment-inventory.md`: caption-based discovery is a floor; a segment
defined only in prose or under a non-standard caption is invisible to both passes.
