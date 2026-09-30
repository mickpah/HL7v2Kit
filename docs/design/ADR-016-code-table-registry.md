# ADR-016 — Code-table registry (closes M6-O6)

**Status:** **Accepted 2026-09-20 — per-version table JSON generated into a Swift registry; closed-set enforcement for `ID` fields only; a locale axis for a localisation's own rendering of a table.**

**Context:** The M6 audit (`m6-adrm-2021-localisation-audit.md`, M6-O6) found that HL7 code tables were not modelled at all: schemas dropped the spec's `TBL#` column, and the only tables in the package were four hand-seeded AU value sets. Project requirements #1 and #2 ask for the full spec surface as a faithful, machine-readable rendering; requirement #4 forbids any rule known to misfire on spec-compliant input. A code-table registry has to serve both: complete enough to be a reference, and conservative enough that a membership check never rejects a value the spec allows.

Three facts about the source shaped the design:

- **A field can bind more than one table.** The TBL# cell of some composite-typed fields prints several numbers (`NK1-11` 0327/0328, `OBR-15` 0070/0163/0369, `LCH-5` 0136/0262/0263).
- **A printed table is not always a closed set.** HL7-defined tables can carry a bare `...` row (the list continues, or the values are external: v2.6 0153 "See NUBC codes"), an open-ended range (`2 ...` in 0359 / 0418), local-extension rows (0396 `99zzz or L`), or rows that denote an absent field rather than a value (0207 "Not present").
- **A localisation may widen a base table.** AU ADRM-2021 back-ports `UNICODE UTF-8` from v2.6 into its v2.4 Table 0211 (p. 55 footnote).

## Options

1. **Hand-curated Swift tables**, grown as rules need them (the M6-B-4 seed). Cheap, but never complete and never auditable against the spec.
2. **One merged table set across versions.** Smaller, but wrong: tables change between versions (0211 gains four Unicode rows in v2.5; 0125 gains `CWE` in v2.6), so a merged set either rejects or admits values the message's own version does not.
3. **Per-version JSON extracted from each version's own PDF, generated into Swift**, with an audited override file for extraction defects. Larger, but each table is citable to one printed page and re-extractable.

## Recommendation

Option 3. It is the only one defensible against the spec text alone, and it reuses the ADR-015 discipline: extract with a tool, audit the result, and treat every extraction defect as the tool failing.

## Decision

- **Table contents:** `Resources/tables/v<version>/NNNN.json` (kind `HL7` / `User`, name, `permitsLocalExtensions`, citation, entries with descriptions), emitted by `scripts/extract-code-tables.swift` from Appendix A (v2.3 to v2.6) or Chapter 2C (v2.8.2). Codegen renders `HL7TableRegistry+v<X_Y_Z>.swift`; `HL7TableRegistry.table(_:version:)` is the lookup. 2,565 table files across the six versions.
- **Corrections are never hand edits to the JSON.** They go in `Resources/tables/overrides.json`, version-scoped, each citing the text lines it was read against, and the table is re-extracted. Structural rules live in the extractor (a bare `...` row is dropped; the mis-decoded quotes of the v2.5.1 text layer are restored).
- **Field bindings are two keys with two jobs.** `tables` (a list, any datatype) is the verified record of the spec's TBL# cell. `table` (one string, `ID` / `IS` fields only) is the enforced link codegen reads into `FieldGrammar.table`, derived from `tables` where a field binds exactly one table. The integrity audit fails if a field's `table` is not among its `tables`.
- **The closed-set rule.** `valueNotInTable` fires only when the field's datatype is `ID` **and** `HL7Table.isClosed`: kind `HL7`, no local extensions, at least one entry. `IS` fields and user-defined tables are linked and never enforced. Empty and HL7-null values are never checked.
- **Fail-safe on openness.** An HL7-defined table that printed `...` beside other rows is left open unless `overrides.json` closes it explicitly (v2.6 0365 / 0366 / 0367, whose `...` is the null row). Table 0203 is opened on v2.4 to v2.8.2 because every CX.5 / XCN.13 / PPN.13 / XON.7 definition cites it "for suggested values" (P2-7, V282-C02, owner gate G5).
- **Pattern rows.** A printed row that names a family of codes (0203 `NNxxx`, v2.3.1 to v2.8.2) is declared in `overrides.json` as `patterns: [{code, regex}]`; the extractor moves it out of `entries` into the table JSON's `patterns`, and `HL7Table.contains` accepts a full match (P2-6, V282-C01).
- **Locale axis.** `Resources/tables/locale/<locale-id>/` holds a localisation's own rendering of a table; `HL7TableRegistry.table(_:locale:)`. The Validator consults it only after the message's own version table has rejected a value, so a locale can widen the check and can never reject what the version prints. Narrowing a value set is a profile rule, not a table.
- **Local extension is caller-declared, tables stay closed by default (P2-13, owner gate G5).** HL7 v2.5.1+ permits a table to be extended with locally defined values (CH02 2.5.3.6; v2.8.2 CH02C 2.C.1.2), but that permission is never inferred from the wire: a table stays closed unless the caller declares the codes it has added, per table number, via `ValidationOptions.localTableExtensions`. The Validator consults it after the version and locale checks, at both field and component level, so it widens the same way a locale rendering does and never narrows. Table 0203 stays open per P2-7 regardless of this setting.
- **Audit.** `scripts/audit-schemas.py --tables` checks shape, suspect codes (with a cited allowlist for genuine printed oddities), kind mismatches and schema links; `--tables --depth` re-extracts and reports drift.

## Consequences

- `valueNotInTable` is live on 1,073 `ID` fields across six versions. A message that carried an out-of-table value in such a field used to pass and now reports an error; `ValidationOptions.checkCodeTables = false` (and the `lenient` preset) suppress it.
- Generated Swift must keep each expression small. A version's grammar emitted as one dictionary literal took 16 minutes to type-check once fields carried a string for the optional `table`; codegen now emits one constant per segment.
- **Deferred (registered, not shipped):** table links on composite components (`CX.5` 0203, `XCN.13`, `CE.3` 0396 and the like) — `tables` records only field-level bindings, and component tables are printed in the datatype chapter, which the extractor does not read yet. Multi-table field bindings are recorded in `tables` but not enforced. The VMR implementation table and OBX-4 sub-ID tree validation are the first planned consumers beyond field membership.
- 14 advisory `KINDMISMATCH` findings remain by design: the spec itself binds some `ID` fields to user-defined tables; they are never enforced.
- Print-versus-prose binding conflicts are resolved in `scripts/table-repairs.json` with a citation (TQ1-12, CON-18, SID-4, RCP-7, SAC-28; P2-8, P2-9).

## References

- `docs/design/m6-adrm-2021-localisation-audit.md` — M6-O6, the originating finding.
- ADR-014 (API evolution: all of this is additive), ADR-015 (the extraction discipline reused here).
- `scripts/extract-code-tables.swift`, `scripts/backfill-schema-tables.py`, `scripts/table-repairs.json`, `Resources/tables/overrides.json`.
- AU ADRM-2021.1 pp. 54-55 (Table 0211), pp. 301-310 (Tables 0203 / 0363).
