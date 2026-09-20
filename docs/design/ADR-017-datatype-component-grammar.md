# ADR-017 — Datatype component grammar and component-level code tables

**Status:** **Accepted 2026-09-20 — per-version datatype component tables extracted into `Resources/datatypes/`, generated into `DataTypeGrammarTable`; `valueNotInTable` extended to `ID` components on closed tables.**

**Context:** ADR-016 shipped the code-table registry and enforced it at FIELD level only, registering component-level bindings as deferred. The bindings integrators ask about most live on components, not fields: the identifier type in `CX.5` (0203), the name type in `XPN.7` (0200), the telecommunication codes in `XTN.2` / `XTN.3`, the address type in `XAD.7`. The package had no per-version model of a datatype's components at all: the eighteen typed composite views are hand-written against v2.5.1 and carry no table metadata. Requirements #1 and #2 ask for the spec's own rendering; requirement #4 forbids a rule known to misfire.

Two facts about the source:

- **Only v2.5.1, v2.6 and v2.8.2 print component tables** ("HL7 Component Table - CX", Chapter 2A), each row giving SEQ, LEN, DT, OPT, TBL# and the component name. v2.3, v2.3.1 and v2.4 define components in prose ("Components: <a> ^ <b>") with tables named in running text.
- **The component tables are regular**, unlike the segment attribute tables: one caption, one header, one row per component. A small dedicated reader is safer than bending the ADR-015 segment extractor, whose heuristics are tuned to a different layout and guarded by a clean depth audit.

## Options

1. **Hang table metadata on the hand-written composite views.** Eighteen types, one version. Not per version, not complete (the spec prints about 80 datatypes), and not auditable.
2. **Extract component tables per version and generate a grammar**, mirroring ADR-015 / ADR-016: extractor as the only author, JSON as the record, generated Swift as the runtime.
3. **Parse the prose of v2.3 to v2.4 as well.** Would cover every version, at the cost of a prose parser whose output could not be shape-audited the way a table can.

## Recommendation

Option 2 for the three versions that print tables. Option 3 is registered as deferred rather than attempted: a component binding recovered from prose could not be held to the same standard of evidence.

## Decision

- **Data:** `Resources/datatypes/v<version>/<DT>.json` (code, name, components with index, name, datatype, printed optionality, bound table numbers), written only by `scripts/extract-datatype-components.py`. 227 datatype files, 1,323 components, 437 with a table binding. Primitive datatypes print no rows and have no file.
- **Extractor rules, each read against the print:** a component name can start under the TBL# header, so a TBL# cell is recognised by content (v2.5.1 AD); a withdrawn component prints SEQ, `W` and a name but no datatype (v2.6 XTN.1); a row can be printed without its SEQ number (v2.5.1 MA row 1); v2.6 LA2 prints table numbers without the leading zero; text at the left margin that is not a row ends the table, so trailing prose cannot run into the last component's name.
- **Runtime:** `DataTypeGrammarTable.grammar(_:version:)` returns a `DataTypeGrammar` of `ComponentGrammar` entries. Codegen emits one constant per datatype (the ADR-016 lesson on expression size). `optionalityCode` is the printed code verbatim, because `RE` (v2.8.2 XPN.1) has no `FieldOptionality` equivalent.
- **Rule:** for a populated field whose datatype has a grammar on the message's version, each populated `ID` component bound to exactly one table must carry one of that table's codes when the table `isClosed`. The error is `valueNotInTable(table:)` located at the component (`PID[1]-3.5`). All ADR-016 guards carry over: `IS` and user-defined or open tables never enforced, empty and HL7-null never checked, the locale rendering consulted before raising.
- **Audit:** `scripts/audit-schemas.py --datatypes` (shape, table resolution; re-extraction drift with `--depth`). `9999`, the v2.7+ "no table assigned" sentinel, is accepted as printed and never resolved.
- **Table 0354 (Message structure) is open on every version.** Vetting the rule showed that each version's chapters use 15 to 25 structures its printed table omits (v2.5.1 Chapter 15 defines `RSP^K25^RSP_K25`). MSG.3 is therefore linked and never enforced.

## Consequences

- About 50 components per version are enforced. On its first run the rule found a real defect in 13 synthetic fixtures: the ordering provider sat in OBR-17 (callback phone) instead of OBR-16.
- Vetting the enforced tables found four ADR-016 registry defects, fixed in the same cycle: v2.8.2 tables with non-standard column headers had extracted empty; v2.5.1 Appendix A drops `OR` from 0210; a mis-decoded no-break space corrupted three v2.6 0550 codes; and 0354 as above.
- **Deferred, registered:** component grammar for v2.3, v2.3.1 and v2.4 (prose only); descent into nested composites (the HD inside `CX.4`, so `HD.3` is enforced only where HD is the field's own datatype); OBX-5, whose datatype varies with OBX-2; fields or components whose TBL# cell names several tables; component optionality and length, which the grammar records and nothing enforces yet.
- The hand-written composite views are unchanged. They remain the typed accessors; the grammar is the per-version metadata beside them.

## References

- ADR-015 (extraction discipline), ADR-016 (the registry, the closed-set rule, the locale axis), ADR-014 (additive API).
- `scripts/extract-datatype-components.py`, `Resources/datatypes/`, `Sources/HL7v2Kit/DataTypes/`.
- HL7 v2.5.1 / v2.6 / v2.8.2 Chapter 2A, "HL7 Component Table" figures.
