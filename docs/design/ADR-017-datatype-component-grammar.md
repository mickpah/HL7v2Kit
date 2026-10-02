# ADR-017 — Datatype component grammar and component-level code tables

**Status:** **Accepted 2026-09-20 — per-version datatype component tables extracted into `Resources/datatypes/`, generated into `DataTypeGrammarTable`; `valueNotInTable` extended to `ID` components on closed tables.**

**Context:** ADR-016 shipped the code-table registry and enforced it at FIELD level only, registering component-level bindings as deferred. The bindings integrators ask about most live on components, not fields: the name type in `XPN.7` (0200), the telecommunication codes in `XTN.2` / `XTN.3`, the address type in `XAD.7`. The package had no per-version model of a datatype's components at all: the eighteen typed composite views are hand-written against v2.5.1 and carry no table metadata. Requirements #1 and #2 ask for the spec's own rendering; requirement #4 forbids a rule known to misfire.

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
- **Rule:** for a populated field whose datatype has a grammar on the message's version, each populated `ID` component bound to exactly one table must carry one of that table's codes when the table `isClosed`. The error is `valueNotInTable(table:)` located at the component — the name type in `XPN.7`, Table 0200 (`PID[1]-5.7`). All ADR-016 guards carry over: `IS` and user-defined or open tables never enforced, empty and HL7-null never checked, the locale rendering consulted before raising.
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

## Addendum 2026-09-21 — M17: the printed examples as a standing audit

Checking a rule against an example the spec prints had found a false error every time it was tried by hand (XTN, PL, CWE, HD). M17 makes it systematic: `audit-schemas.py --examples` extracts every pipe-delimited composite example from each version's datatype chapter and applies the component rules to it. 352 example repetitions; it found two more self-contradictions (`NA.1` printed `R` beside a prose sentence and an example that leave it empty; Table 0528 printing `HS` beside an RPT example that uses `AHS`), both resolved in favour of the example by cited override. Three rejections are registered as the example's fault rather than the rule's, each with its reason in `EXPECTED_EXAMPLE_REJECTIONS`.

**Limit of the audit, stated:** it re-implements the two component rules in Python over the extracted data, which is where every misfire so far has originated; it does not drive the Swift Validator. The Swift tests cover the rule logic; this covers the data.

## Addendum 2026-09-21 — M18: example messages, and where examples stop being evidence

M18 ran the 616 complete example messages of the domain chapters through the Swift Validator. It found one real defect: Table 0125 omits `NA`, `MA` and `CD` on v2.3 to v2.6 although Chapter 7's normative text directs them into OBX-2 (v2.8.2 corrects the table).

It also marked the limit of "the spec's examples are must-pass". That held for the datatype chapters, where an example illustrates the datatype being defined and the surrounding prose is normative. It does not hold for printed messages: half declare a version other than the chapter printing them, many are truncated or misaligned, and they omit required fields by the hundred. **The rule adopted: normative text (tables and prose) decides; an example can overturn a table only when normative prose agrees with it** (`NA.1`), or when the rule's data is plainly a spelling or extraction artefact (`RANDOM`, `AHS`). `MSH-9.3` is the test case: the MSG table prints `R`, the MSH-9 prose is silent, 35 of 68 v2.5.1 examples omit it — the table stands.

## Addendum 2026-09-22 — M26: conditional components

The last registered gap. The component tables print `C` with no predicate; the prose sometimes states one. Every `C` component's definition on v2.5.1, v2.6 and v2.8.2 was read (118 slots). The conditions fall into four groups, and each was measured against the spec's own example messages before anything shipped.

- **Sibling-presence conditions the examples honour** (36 rules): modelled on `ComponentGrammar.condition` in a five-token predicate language, cited sentence by sentence in `Resources/datatypes/conditions.json`. Zero violations across every version-consistent printed message and every datatype-chapter example.
- **The "as of v2.7" family** (32 rules, same shape): violated by 62 to 100 percent of the specification's own v2.7+ example values. This is the case the M18 rule did not anticipate: normative prose against not one stray example but the corpus. **Decision: authored, cited and registered, not applied.** Shipping them would make the Validator reject the standard's own messages, which fails requirement #4 in spirit even though each sentence is normative. An advisory severity tier would be the way to ship them; that is a modelling decision for a later cycle.
- **Conditions the model cannot express:** on the coding system in use (CWE.7 and kin), on the repetition count (XAD.7), and CNE.20, whose sentence contradicts its own summary.
- **`C` with no stated condition:** left as printed.

## Addendum 2026-09-22 — M27: the v2.7 rules as an opt-in tier

The 32 rules M26 registered now ship on `ComponentGrammar.conformanceCondition`, evaluated only when `ValidationOptions.conformanceConditionSeverity` is set. The default stays silent for the reason M26 gave: the specification's own v2.7+ examples violate them in 62 to 100 percent of values. The predicates are correct renderings of normative sentences, so an integrator checking strict v2.7+ conformance can ask for them; nobody gets them unasked. No further registered gap remains on the component grammar except the conditions the model cannot express (coding system in use, repetition count, CNE.20).

## Addendum 2026-09-22 — M28: `repeated`

XAD.7's sentence ("required if there are multiple occurrences of XAD in a field") was registered by M26 as a repetition-count condition the language could not carry. One token carries it: `repeated`, true when the field has more than one populated repetition, evaluated by the Swift and Python evaluators alike. The single v2.7+ example with two address repetitions is mis-delimited and does not count against the sentence; the judgement is recorded in the rule's citation. What the model still cannot express: CWE.7 and kin (a version ID when .3 names anything but an HL7-type `HL7nnnn` table: a value-pattern term plus a table-type lookup, and the spec's own v2.7+ examples supply .7 in 1 of the 13 values that would require it, so it could only ever join the opt-in tier; measured 2026-09-22 and left registered), and CNE.20, whose sentence contradicts its own summary.

## Addendum 2026-10 — P5: the printed Components line, TQ, arrays and field-local composites

M13 took structure from numbered headings only. Reviews V23-C04/C05, V231-C06/C07 and V24-C05 showed what that misses. P5 adds the printed "Components:" / "Format:" line as a second source that ranks below the headings. It never binds a table.

- **Completion.** A subsection that prints no datatype gives way to the line when the line prints one: v2.3 sec 2.8.3.4 "Alternate components" is one heading over CE.4-6, and v2.3.1 sec 2.8.8.9 "Original text" prints no `(ST)`. A component that the line names past the last subsection comes from the line. CE now has 6 components on v2.3 and v2.3.1, and CNE has 9 on v2.3.1. The same rule corrected DLN.1 (ST) on all three versions and v2.3 ED.2 (ID, table 0191) and SN.1. A line shorter than the typed subsections is not trusted (v2.3 PPN, XCN, XTN).
- **Line-only composites** (`"source": "prose-line"`): CD, CF and TS, which have no numbered subsections on any of the three versions. TS prints `YYYY[...]^<degree of precision>` with no datatype codes, so both components carry `""`.
- **TQ** comes from CH4 (v2.3 / v2.3.1 sec 4.4, v2.4 sec 4.3), numbered like any CH2 composite: 10, 12 and 12 components.
- **MA and NA have no grammar, by design.** Before v2.5 each prints an open list (`<value1> ^ <value2> ^ ...`, `...~`) whose components are all NM. No fixed component list exists to state. The NM lexical rule is P6's primitive-lexical work. This is not a gap in the grammar.
- **Field-local composites** (`Resources/datatypes/v<X>/fields/<SEG>-<N>.json`, `"source": "prose-field"`, `DataTypeGrammarTable.grammar(segment:field:version:)`). Each pre-v2.5 field heading that prints `CM` (or v2.3's `PTS` / `SVC`) is followed by a Components line, and `scripts/extract-field-components.py` reads it: 45 fields on v2.3, 41 on v2.3.1 and 43 on v2.4. A table binds only to a coded component (IS, ID, CE / CNE / CWE), under the three M13 tests, from a chunk that opens "The <ordinal> component" (a word, or a number: v2.4 OBR-15.7 "The 7th component", Table 0369), a bullet that opens with the component's name, or, when the field has exactly one coded component, any other sentence that names exactly one table (v2.4 PV1-37.1, Table 0113). A sentence naming two or more tables never binds. Bound components: 13 on v2.3, 19 on v2.3.1 and 26 on v2.4. A field printed twice keeps the copy that extends the other (v2.4 OBR-15: CH04 prints seven components, CH07 six; CH13 sec 13.4.3.6 cites "the 7th component").
- **Not emitted, stated:** v2.3 QRD-11 prints `(CM)` in its heading and `ST` in its attribute table; the table wins, so the field stays `ST`.
- **Enforced (P5-6).** Every composite-aware check resolves a field's grammar through one point, `Validator.fieldGrammar(segment:field:dataType:version:)`: a primitive stays primitive, else the field-local grammar where the field prints one, else `Validator.componentGrammar(_:version:)`. The width check (P6-15), the primitive-component and component code-table checks (P6-14), the format check (P6-7) and the conditional and required component checks all call it; no check reads `grammar(segment:field:version:)` directly. A component one level down still resolves by its datatype, so a field-local `TS` (IN3-20.3) is format-checked as the primitive it is on v2.3 to v2.4. Code tables bind only where the table is closed (an HL7 table with no local extensions): IS bindings and the open MSH-9 tables (0076, 0003, 0354 on v2.3.1 / v2.4) stay unenforced. A top-level `CE` component bound to a closed HL7 table (OBR-15.1 0070, OBR-15.4 0163, ERR-1.4 0357, SAC-6 / TCC-3) is checked on its identifier only when CE.3 is empty or names that table as `HL7nnnn` (v2.3 / v2.3.1 2.8.3.3, v2.4 2.9.3.3); any other coding system is silent, which is how OBR-15's "Veterinary medicine may choose the tables supported for the components of this field" (v2.4 7.4.1.15) is honoured. The lookup resolves `Version.grammarVersion`, so `2.8` reads the (empty) v2.8.2 table.
- **Misprinted `&` (P5-6).** v2.3.1 and v2.4 PRA-7 print `<privilege (CE)> & <privilege class (CE)> ^ <expiration date (DT)> ^ ...`, then a "Subcomponents for privilege class:" line, and the v2.4 CH15 example carries `ADMIT&&ADT^MED&&L2^19941231`. The extractor reads an `&` as `^` when every piece after it has its own "Subcomponents for <name>:" line (a piece with subcomponents is a component), so PRA-7 has five components there.

**Still deferred after P5 (blocks spec-completeness, requirement 3):** OM2-6 "Reference (normal) range for ordinal and continuous observations" on v2.3 and v2.3.1 (sec 8.7.4.6) and v2.4 (CH08 sec 8.8.4.6). The spec prints its structure as a narrative repetition list (`<ref. (normal) range1>^<sex1>^<age range1>^...~`) with a nested `Components: <low value (NM)> & <high value (NM)>`, and no field-level Components line. It has no component grammar; the `fieldLocalCoverage` test pins it as registered.

Also deferred, and blocking spec-completeness: 15 table mentions in CM field definitions that no rule above can attribute to one component, 7 on v2.3, 4 on v2.3.1 and 4 on v2.4. They are IN2-28 (0145, 0146) and IN2-29 (0147, 0193) on all three versions, where one sentence names two tables over two IS components; v2.3 MSH-9 (0076 and 0003), whose sec 2.24.1.9 names both tables in one sentence ("first ... table 0076 ...; second is ... table 0003"); and v2.3 IN3-11.1, which names 0149 "Day type" where the v2.3 registry prints "Days Type". `python3 scripts/extract-field-components.py <version> --report` lists every one with its reason. The permanent-limitations register carries both deferrals as rows (addendum to section D).

## References

- ADR-015 (extraction discipline), ADR-016 (the registry, the closed-set rule, the locale axis), ADR-014 (additive API).
- `scripts/extract-datatype-components.py`, `Resources/datatypes/`, `Sources/HL7v2Kit/DataTypes/`.
- HL7 v2.5.1 / v2.6 / v2.8.2 Chapter 2A, "HL7 Component Table" figures.
