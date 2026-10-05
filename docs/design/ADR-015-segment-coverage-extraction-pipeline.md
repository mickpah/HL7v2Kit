# ADR-015 — Segment-coverage extraction pipeline (the M5 prerequisite)

**Status:** **Accepted 2026-07-12 — `pdftotext -layout` (poppler) as the uniform per-version attribute-table extractor.** Scouting (this session) validated that poppler's layout-preserving text extraction recovers the segment attribute tables — every column (`SEQ / LEN / [C.LEN] / DT / OPT / RP/# / TBL# / ITEM# / ELEMENT NAME`) cleanly whitespace-aligned — on **all six supported versions'** PDFs, including the 1997 v2.3 set. This dissolves the "legacy `RP/#` columns resist extraction" blocker that `STATUS.md` / `NEXT_STEPS.md` / `[[v1-0-requires-all-version-feature-parity]]` recorded against the M5 program. The tool is a **dev-time codegen aid**, not a package runtime dependency — the "no runtime deps" rule (the working notes) is unaffected. Options B (PDFKit geometric reconstruction) / C (WORD-only) / D (manual, status quo) recorded below as rejected.

**Context:** ROADMAP **M5** (owner directive 2026-07-09, `[[v1-0-requires-all-version-feature-parity]]`) reframed "v1.0 complete" to mean **every HL7 segment modelled to full field depth on every supported version** (v2.3 / v2.3.1 / v2.4 / v2.5.1 / v2.6 / v2.8.2) — ~150 segments × 6 versions ≈ 900 schemas. That scale is only defensible (the working notes req #2 / #4 — the schemas must be a faithful machine-readable rendering of the spec, not a best-guess) if the per-field data (`DT`, `OPT`, `RP/#`, `TBL#`) is extracted **reliably**, not eyeballed 900 times. The prior curated segments (the 15 typed set; NK1/PV1/IN1 to canonical v2.5.1 depth in v0.19) were authored by reading the PDFs by hand via PDFKit — which **does not scale** and, worse, PDFKit's `.string` output mis-orders the very columns (`OPT` / `RP/#`) that matter most. This ADR is the "extraction-pipeline prerequisite" that `NEXT_STEPS.md` Step 1 flagged as the first M5 sub-task.

### The blocker, precisely characterised (why raw PDFKit failed)

PDFKit's `PDFPage.string` reads the attribute tables **column-major, not row-major**. Scouted on the v2.5.1 and v2.6 NK1 tables, it emits:

- the `ELEMENT NAME` column cleanly, in `SEQ` order ("Set ID - NK1", "Name", "Relationship", …);
- the `OPT`+`RP/#` markers as a *separate* bunched run ("O Y O Y O Y …");
- the `LEN` / `DT` / `ITEM#` numerics scrambled into a single blob ("9 00750 O 0311 00751 00752 …").

Re-aligning those runs back to rows is unreliable (not every field is `O Y`, so the run can't be zipped 1:1 to the names). A geometric reconstruction from `PDFPage.characterBounds(at:)` was also scouted — on the v2.5.1 CH03 PDF it **fragmented** (element names split vertically across y-clusters, numerics interleaved), so per-field recovery was not trustworthy either. This is the concrete form of the "columns interleave" note the status docs carried.

### The finding (why `pdftotext -layout` succeeds)

`pdftotext -layout` (poppler; already installed at `/opt/homebrew/bin/pdftotext`) preserves the *visual* column positions with runs of spaces, so each attribute-table row survives as one text line with the columns positionally intact. Scouted output, verbatim, v2.5.1 NK1:

```
SEQ        LEN    DT      OPT    R P/#     TBL#      ITEM#    ELEMENT NAME
  1         4     SI       R                         00190    Set ID - NK1
  2        250   XPN       O       Y                 00191    Name
  3        250    CE       O               0063      00192    Relationship
 …
 39         2     IS       O               0099      00146    VIP Indicator
```

`OPT` and `RP/#` are now **distinct, aligned columns** — exactly what was missing. Verified on the hardest cases:

| Version | PDF vintage | NK1 table extraction | Notes |
|---|---|---|---|
| v2.3 | 1997 (`CH3.pdf`) | yes — clean | caption "Figure 3-5. NK1 attributes"; `RP/#` present; shorter field list |
| v2.4 | 2000 (`CH03.PDF`) | yes — clean | "HL7 Attribute Table"; multi-line TBL# `0327/0328` wraps |
| v2.5.1 | 2007 (`V251_CH03.pdf`) | yes — clean | 39 fields — **matches the v0.19 canonical depth** (cross-check) |
| v2.6 | 2007 (`V26_CH03…pdf`) | yes — clean | same column set as v2.5.1 |
| v2.8.2 | 2019 (`V282_CH03…pdf`) | yes — clean | extra `C.LEN` column; shows `B` on NK1-5/6 — **cross-validates the hand-authored v2.8.2 divergences** |

The v2.8.2 WORD `.doc` sources also extract cleanly via a *second, independent* path — `textutil -convert txt` renders each attribute table row-major with `\x07` (BEL) as the cell delimiter and newline as the row delimiter — usable as a **cross-check** for v2.8.2 (the only version shipping WORD on disk; v2.7.1 ships a WORD zip but is not a supported `Version`). Two independent extractors agreeing on v2.8.2 is a useful correctness signal but not required for the pipeline.

### What "the extraction pipeline" is (and is not)

- **It is** a dev-time authoring aid: `pdftotext -layout <chapter>` → a parser that locates attribute tables by their header row, bins each row into columns, handles continuation lines (wrapped element names / multi-line `TBL#`), and emits a structured intermediate to *seed and cross-check* the hand-reviewed `Resources/schemas/<version>/<SEG>.json` schemas.
- **It is not** part of the shipped package, not a SwiftPM dependency, and not a runtime code path. `Package.swift.dependencies` stays empty (the working notes). The committed, human-reviewable artifacts remain what they are today: the schema JSON (source of truth) + the codegen-emitted Swift under `Generated/`. Poppler is a contributor tool, documented in the regenerate script's prerequisites, exactly as the Xcode toolchain already is.
- **Authoring discipline is unchanged (req #2 / #4):** the extractor *proposes*; a human *verifies against the spec text* and the schema carries its citation. Automated extraction removes the transcription-error and column-misread risk; it does not remove the spec-faithfulness review. A cross-check test continues to pin field counts + known divergences per segment/version.

## Options

### Option A — `pdftotext -layout` (poppler), uniform across all six versions **(chosen)**
One extractor, every version. Layout-preserving text → header-anchored column parse → structured intermediate → seed/verify schema JSON. v2.8.2 additionally cross-checked against the WORD `textutil` BEL path.

- **Effort:** one parser to build + validate (S2), reused for the whole M5 sweep. Column set varies mildly (v2.8.2 adds `C.LEN`; older sets differ in caption/spacing) → parse columns by header-detected x-positions, not fixed offsets.
- **Dependency:** poppler (Homebrew), dev-time only. Acceptable — not a package runtime dep; a golden-file test lets contributors without poppler still validate committed schemas.
- **req #1 / #2 alignment:** strongest — makes the 900-schema sweep tractable *and* trustworthy; the schemas become defensible against the spec tables directly.

### Option B — PDFKit geometric reconstruction (`characterBounds`)
Cluster glyphs into rows/columns from their bounding boxes. **Rejected:** scouted on v2.5.1 CH03 → fragmented (vertical name splits, interleaved numerics); would need per-PDF tuning and still be fragile on the 1997-vintage sets. Higher effort, lower reliability than A, and it fails hardest exactly where coverage is thinnest (oldest versions). Keeps zero external deps — the only point in its favour — but that's moot since the dep is dev-time.

### Option C — WORD `.doc` → `textutil` (BEL-delimited) as the primary path
Clean and row-major, but **rejected as primary:** only v2.8.2 ships WORD on disk (v2.7.1 in a zip, unsupported version); the five legacy versions are PDF-only. Cannot cover the sweep. **Retained as the v2.8.2 cross-check** under Option A.

### Option D — Continue manual PDFKit reading (status quo)
What produced the 15 curated segments. **Rejected:** does not scale to ~900 schemas, and PDFKit's column mis-ordering makes hand-transcription of `OPT`/`RP/#` error-prone at volume — a direct req #4 hazard ("no known-incorrect metadata ships"). Manual reading stays only as the final human spec-verification step over Option A's output, never as the extraction mechanism.

## Recommendation

**Option A.** It is the only option that makes M5 both *tractable* (one tool, 900 schemas) and *trustworthy* (req #2/#4 — clean per-field columns, human-verified, cross-checked). The dependency objection dissolves once it's clear the extractor is a dev-time aid, not shipped code. The v2.5.1 (39-field NK1 matching v0.19) and v2.8.2 (`B` on NK1-5/6 matching the hand-authored divergences) cross-checks give immediate confidence the extractor agrees with work already reviewed by hand.

## Decision

**Option A — `pdftotext -layout` as the uniform extractor, 2026-07-12.** M5 proceeds as additive v1.1+ cycles on branches off `main` (worktree per cycle); this ADR + the extractor tool + the segment inventory are the v1.1 opening cycle. Plan:

- **S1 — this ADR.** Record the decision + scouting evidence. (Branch `v1.1-adr-015-extraction`.)
- **S2 — build + validate the extractor.** A parser over `pdftotext -layout` output: detect attribute-table headers, bin rows into columns by header x-positions, fold continuation lines, emit a structured intermediate (segment → ordered fields with `SEQ/LEN/DT/OPT/RP/TBL#/ITEM#/name`). **Golden test:** run it on v2.5.1 CH03 NK1 and assert it reproduces the already-authored canonical schema (39 fields, per-field `DT`/`OPT`/`RP`) exactly — the extractor must agree with hand-reviewed truth before it's trusted on unseen segments.
- **S3 — segment inventory.** Enumerate every HL7 segment per version from the chapter attribute-table indexes → the M5 work-list (~150 × 6), with each segment's chapter/home and per-version presence. This is the runway the additive cycles draw from.
- **S4 — release** the v1.1.0 *foundation* cycle (extractor + inventory + ADR; **no schema/API change yet** — so the frozen public surface is untouched, ADR-014 additive-only holds trivially): `docs/design/segment-coverage-extraction.md` (the pipeline how-to + poppler prerequisite), CHANGELOG, STATUS/NEXT_STEPS/ROADMAP sync, merge, tag, push to `private`.

Subsequent v1.1+ cycles author schemas by chapter/segment-family off the inventory, extractor-seeded + human-verified, each with cross-check tests. **First segment target:** the known gap — NK1/PV1/IN1 per-version depth (v2.3/v2.3.1/v2.4/v2.6/v2.8.2), since the extractor is already proven on those exact tables. **API stays frozen (ADR-014) throughout; `main` untouched during each cycle.**

**Model-extension watch (req #3):** if a version's attribute table uses an optionality code, datatype, or repeatability form the schema/DSL can't express faithfully (as `FieldOptionality.withdrawn` was for `W` in v0.14), extend the model rather than mapping to a near-miss — and record it in the audit doc + CHANGELOG.

## Consequences

- **If A (chosen):** the M5 blocker is retired; the ~900-schema program becomes a mechanical-but-verified sweep rather than an open research problem. `STATUS.md` / `[[v1-0-requires-all-version-feature-parity]]` "legacy PDF extraction may be intractable" caveat is superseded — the extraction is a solved, tooled step. v1.1.0 ships the foundation (extractor + inventory) with zero API movement; coverage growth follows as additive minors. The first *public* push remains gated on M5 reaching full parity, not on this ADR.
- **Dependency footprint:** one new dev-time tool (poppler) documented in the regenerate prerequisites; `Package.swift` unchanged; a golden-file test insulates contributors who lack poppler from needing it to validate committed schemas.
- **Residual risks:** (a) a handful of unusually-formatted attribute tables may defeat header-anchored column binning — handled case-by-case, flagged by the cross-check test, never silently mis-parsed (fail-safe: the extractor emits a diagnostic, the human authors that segment by hand); (b) `RP/#` cardinality numbers (`Y` vs a max count) and multi-line `TBL#` need continuation-line handling in S2 — the reason S2 has an explicit golden test before the tool is trusted at scale.

## References

- `ROADMAP.md` **M5** — full HL7 segment coverage; the program this ADR unblocks.
- `[[v1-0-requires-all-version-feature-parity]]` (memory) — the owner directive + the "legacy PDF `RP/#` resists extraction" blocker this ADR retires.
- `docs/design/full-segment-audit.md` — the v0.19 canonical NK1/PV1/IN1 depth (39/52/53) that the extractor is golden-tested against.
- `docs/design/ADR-014-api-evolution-policy.md` — additive-only 1.x; M5 coverage adds, never removes.
- `docs/design/ADR-013-v2_8_2-grammar-version.md` — the v2.8.2 divergences (`B` on NK1-5/6 etc.) the extractor cross-validates.
- `scripts/regenerate-typed-segments.sh` — where the poppler prerequisite gets documented alongside the existing Xcode-toolchain note.
- `docs/standards/HL7_*_PDF/` — the author-local Final Standard PDFs (IP-review-gated; keep out of any public tree); the extractor reads these, the repo commits only derived schema JSON.
- the working notes — "no runtime dependencies" (unaffected — dev-time tool) + req #1/#2/#4 (the reliability bar this pipeline exists to meet).
