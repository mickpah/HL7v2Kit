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

## Addendum 2026-09-21 — M11: nested composites and OBX-5

Two items from the deferred list shipped, both as extensions of the rule above rather than new machinery:

- **Nested composites.** When a component is not itself an enforceable `ID` but its datatype has a grammar on the message's version, its subcomponents are checked against that grammar. HL7 v2 has no level below the subcomponent, so one descent is the whole depth. The HD in `CX.4` makes `CX.4.3` a checked universal ID type (0301); `IssueLocation` gained `subcomponentIndex`, and the path reads `PID[1]-3.4.3`. 46 nested sites on v2.5.1, 28 on v2.6, 27 on v2.8.2; `HD.3` accounts for most.
- **OBX-5.** The datatype OBX-2 declares is resolved once (`effectiveDataType`, shared with the AU composite overrides) and the component check runs under it. A primitive or absent OBX-2 has no grammar and nothing fires.
- **A defect this exposed in v3.4.0:** Table 0301 prints the three local-scheme codes in one row, `L,M,N`. As a single code the closed table rejected a valid `HD.3` of `L`, `M` or `N`. Split by cited override; the audit now treats a comma in a code as suspect.

**Still deferred after M11:** component grammar for v2.3 to v2.4 (prose only); TBL# cells naming several tables; component optionality and length, recorded and not enforced.

## Addendum 2026-09-21 — M13: v2.3, v2.3.1 and v2.4 from prose

Option 3 was deferred above for want of a standard of evidence. M13 sets one and meets it.

- **Structure comes from headings, not free text.** Each composite has a numbered section and each component a numbered subsection ("2.9.12.5 Identifier type code (ID)"): index, name and datatype are read from that heading. A trailing subsection with no datatype code is a note ("Usage notes:") and is dropped. 105 datatype files, 575 components, marked `"source": "prose"`; `optionalityCode` is `""` because the prose prints none.
- **A table binding must pass three tests:** the subsection names exactly one table; that number is in the version's own registry; and when the prose states the table's name, it matches the registry's name for that number. Anything else stays unbound.
- **The name test is not theoretical.** v2.3 sec 2.8.31.4 binds QSC.4 to "HL7 table 0102 - Relation conjunction"; v2.3's 0102 is Delayed Acknowledgment Type, a closed table that would have rejected AND and OR. It also caught v2.3 XCN.8 / PPN.8 ("0207 - CN ID source"; 0207 is Processing mode), JCC.2 ("0329 - job class"; 0329 is Quantity method) and v2.3.1 DLN.2 (0333 printed for two different tables).
- **Measured:** every surviving binding that has a v2.5.1 counterpart equals v2.5.1's printed component table: 28, 48 and 70 on the three versions, zero conflicts. 39 mentions were rejected.
- **Multi-table field cells** (NK1-11 `0327/0328`) are the successive coded components of the field's composite (JCC.1, JCC.2), so the component grammar is what gives them meaning; no separate mechanism is needed.
- **AU consequence, found by sweeping before enabling:** with v2.4 checked, the AU locale needed the ADRM's own renderings of two more tables. Table 0301 (p. 161) adds AUSHICPR, AUSHIC, AUSDVA, AUSNATA and AUSLSPN as daggered Australian extensions, and `QML^2184^AUSNATA` in MSH-4 is everyday AU traffic. Table 0125 (p. 237) adds CNE, CWE, DR and EI as OBX-2 value types — and that one was a live false error under the AU locale since v3.3.0, because OBX-2 has been enforced at field level since then.

**Still deferred after M13:** component length; TBL# cells that name several tables on a component with no grammar to resolve them.

## Addendum 2026-09-21 — M14: required components from the grammar

The grammar made an audit possible that was not before: the Validator's hand-written required-component lists against the optionality each version prints. Eight of eleven flat lists contradicted v2.5.1's own table (`XAD.1`, `XPN.1`, `XCN.1`, `XON.1`, `CE.1`, `EI.1`, `PT.1`, `VID.1` are all printed `O`), while citing the very sections that print it. They predate any extracted data (v0.2 to v0.3).

- **Decision:** the required components of a composite are exactly those its version's component table prints `R`. The hand-written lists are no longer read by the Validator; the public constants now hold the v2.5.1 print and are informational.
- **Consequence in both directions.** False errors disappear (an address with no street line). Spec requirements the old lists waived are now enforced, the visible one being `MSH-9.3`: all three `MSG` components are `R` from v2.5, and the old list's comment that the structure is "often left empty" is the consumer-profile reasoning requirement #1 rules out. The project's own synthetic corpus was non-conformant on it (48 fixtures) and was corrected from Table 0354.
- **Not enforced, stated:** `C` components (no predicate is printed for them), `RE` (by definition never a missing value), and everything on v2.3 to v2.4, whose prose prints no optionality. The either-or sets (`HD`, `CWE`, `EIP`, `PL`, `XTN`) are hand-written from prose and were not part of this audit; they remain as they were.

## Addendum 2026-09-21 — M15: the either-or rules, held to the spec's examples

Tables could not audit these five rules, so the spec's own prose and examples did. Three reject an example the spec prints, and one can never fire:

| Rule | Verdict | Evidence (v2.5.1) |
|---|---|---|
| `XTN`: 1 OR 4 OR 12 | **removed — misfire** | sec 2.A.89 example `^ORN^FX^^^734^6777777`; the delimited form is the recommended one as of v2.3 |
| `PL`: 1 OR 4 | **removed — misfire** | sec 2.A.53: "for a patient treated at home, only the person location type is valued" |
| `CWE`: 1 OR 9 | **removed — misfire** | sec 2.A.13 usage b) "Uncoded: Text is valued, the identifier has no value", `^Wesnerian^SNM3^^^^3.4` |
| `EIP`: 1 OR 2 | **removed — vacuous** | two components; a populated field always satisfied it |
| `HD`: 1 OR (2 AND 3) | **kept** | sec 2.A.33: "either as a local identifier ... or ... a UID (<universal ID> and <universal ID type> both valued)" |

Registered at the time, **shipped in M16**: the same HD section says components 2 and 3 "must either both be valued (both non-null), or both be not valued", a sentence all six versions print. A partially populated group now fails the rule. M16's must-pass test over every HD example the section prints also caught a false error live since v3.5.0: the table prints `Random`, the example `RANDOM`; the example's spelling is now in Table 0301 by cited override.

## References

- ADR-015 (extraction discipline), ADR-016 (the registry, the closed-set rule, the locale axis), ADR-014 (additive API).
- `scripts/extract-datatype-components.py`, `Resources/datatypes/`, `Sources/HL7v2Kit/DataTypes/`.
- HL7 v2.5.1 / v2.6 / v2.8.2 Chapter 2A, "HL7 Component Table" figures.
