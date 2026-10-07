# HL7 v2.7.1 schema audit — remediation P10 (ADR-015, ADR-018)

**Audit date:** 2026-10-02 to 2026-10-03 (remediation plan P10, tasks P10-0 to P10-8).
**Audited:** `Resources/tables/v2.7.1/`, `Resources/datatypes/v2.7.1/` and `Resources/schemas/v2.7.1/` (170 segments), each extracted from the v2.7.1 print and read against it.
**Reference:** HL7 v2.7.1, ANSI/HL7 Final Standard, July 2012. PDFs held locally in `docs/standards/HL7_V271_PDF/PDF/` (28 files; gitignored, not committed pending IP review). Text read with the ADR-015 extractors over the PDF text layer.
**Lens:** the project requirements 1 to 4 (feature-complete, integrator reference, honesty over completeness, no known-incorrect predicate). Every reading is defensible against the v2.7.1 text alone: no v2.6 or v2.8.2 reading was copied without checking the v2.7.1 page, and where v2.7.1 differs from both neighbours the v2.7.1 print wins.

## What was extracted, and from where

| Resource | Source in the v2.7.1 print | Shipped (P10-8 count) | Task, commit |
|---|---|---|---|
| Code tables | Appendix A (layout A), cross-checked against Chapter 2C's 318 table headings; 0916 from Chapter 2C | 535 tables (174 HL7, 361 user-defined), 5,155 entries, 4 pattern rows (0141, 0203), 144 tables with no values; 54 tables with a cited override | P10-1 `7d012f0`, `d478e3b` |
| Datatype component grammar | Chapter 2A (90 sections: 72 composites, 12 primitives, 6 withdrawn stubs CE, ELD, OSD, SPS, TQ, TS) | 72 composites, 469 components, 151 bound to a table, 72 printed `C` (23 conditions, 30 conformance conditions, 19 bare) | P10-2 `4003241` |
| Segment schemas | Each segment's defining attribute table, Chapters 2, 3, 4, 4A (P10-4a), 5 to 10 (P10-4b), 11 to 17 (P10-4c); ADD from CH02 p. 47 | 170 segments, 2,519 fields (47 + 70 + 53 segments; 778 + 1,050 + 691 fields) | P10-4a `30283ba`, P10-4b `4c11091`, P10-4c `41d354d`, `dae0c3d` |
| Conditional rules | Each `C` field's own definition | 177 printed `C`: 112 with a rule (107 conditions, 5 prohibition only: TQ2-7, PRT-6, PRT-7, SPM-13, RCP-4), 65 bare; plus CSR-8, MFI-6 and ROL-4 printed `R` and modelled `C` (180 `C` fields) | P10-5a `b2004b9`, P10-5b `9dcce3f` |
| Example messages | Every chapter's printed examples | 222 messages; every error line claimed by the spec-example registry (244 entries, 0 mismatched) | P10-7 `a25ee85` |
| Message structures | Each chapter's abstract message syntax (`CODE^EVT^STRUCT: title` captions), Table 0354 (CH02C 2.C.2.175) | 164 structures (20 exact-matched); 58 registered as not modelled; v2.7.1 complete | P8b-16 `71724ed`, `1647930`, `7cc10f6` |

Optionality across the 2,519 fields: O 1,815, R 305, C 180, B 55, W 77, blank 87. Chapter 2B's unnamed 40-field PID profile table, the CH07 OBX example tables and the second CH04A RXA table are profile or example prints and are not the base grammar; only each segment's first (defining) table is used.

Counts in this document were recomputed from the shipped resources at P10-8. The P10-0 measurement figures (a local task report, not in the repository) differ in places because they were taken from the raw print before the cited overrides, repairs and fixes below.

## Rulings

**Version set (ADR-018 amendments, P10-6 `e241b2b`, `059c751`).** `Version.v2_7_1` (`"2.7.1"`) is modelled, with its own tables, datatype grammar and segment grammar. MSH-12 `2.7` is substituted by v2.7.1 (`Version.v2_7`, owner decision G11): there is no v2.7 text on disk, so it is validated against v2.7.1 with one `versionGrammarSubstituted(declared: .v2_7, validatedAs: .v2_7_1)` info issue at MSH-12, exactly as `2.8` is against v2.8.2. The v2.7 to v2.7.1 differences are unverified, and the info issue says so.

**Era placement (P10-6).** v2.7.1 sits with v2.8.2 on every era rule, each verified against the v2.7.1 print: LEN is a normative length beside C.LEN (CH02 2.5.3.2, 2.5.3.3, 2.5.5.0, 2.5.5.3); no 65536 or 99999 length symbols (CH02 2.5.5, pp. 10 to 12); the truncation marks `=` and `#` (CH02 2.5.5.2 p. 11, 2.5.5.3 p. 12); SI bounded to 0 to 9999 (CH02A 2.A.69, p. 80); SNM a primitive and TS withdrawn (CH02A 2.A.71, 2.A.78). The recipient rule "ignore ... components, subcomponents ... that are present but were not expected" is CH02 2.6.2 a (p. 18), which the extra-component messages cite since P10-8.

**Struct bases (ADR-020 amendment, P10-3 `95a7b51`, ruling D2).** A released struct's union base never changes. v2.7.1 would have become the earliest definer of IAR, PAC, PRT and SHP; their v2.8.2 bases are pinned in `Resources/struct-bases.json` (38 pins). No generated struct is based on v2.7.1; v2.7.1 contributes through the union surface only.

**Code tables (P10-1).**
- Appendix A is the source. It prints "no suggested values" rows with a Unicode ellipsis (U+2026) in the code column; the extractor reads it as the bare "..." row, which removed 141 bogus entries.
- The Appendix A versus Chapter 2C cross-check found 13 code-set and 13 kind differences, each decided by a cited override. Examples: 0492 keeps the printed `??` row (both prints carry it; the Chapter 2C miss was the extractor's ".." table-of-contents filter, fixed); 0125 gains `CD` (CH07 7.15.4, p. 141) and drops `ID`, which OBX-2's own text rules out; 0104 gains `2.7.1` and stays open.
- 0070 is printed in Chapter 2C only, as withdrawn in v2.7, and is not created; 0048 is printed nowhere in v2.7.1 and is recorded as absent; 0916 is created from Chapter 2C.
- Against v2.6: v2.7.1 has 10 tables v2.6 lacks (0904 to 0910, 0912, 0913, 0916) and lacks 12 of v2.6's (0048, 0070, 0106 to 0109, 0156 to 0158, 0348, 0349, 0524). Against v2.8.2: it lacks 30 of v2.8.2's tables and has none v2.8.2 lacks.

**Datatypes (P10-2).** Against v2.8.2: LA1 and LA2 are present (retained for backward compatibility), OG is absent, PRL.2 is ST, and XON.4 and XON.5 are printed `O`. The 23 conditions and 30 conformance conditions are those of v2.8.2, each re-cited to the identical v2.7.1 sentence; the conformance tier is opt-in (`conformanceConditionSeverity`). XTN.4 encodes "required if, and only allowed if, XTN.7 or XTN.12 are not populated" as `7 empty AND 12 empty`, the reading v2.8.2 ships; it fires only where both readings require the component, and the prohibition half is not modelled. NA is an open-ended array: the table prints four values and an ellipsis (2.A.45), so it is never width-checked.

**Segments (P10-4a to P10-4c).**
- Segment set: v2.7.1 adds IAR, PAC, PRT and SHP to v2.6's 170 and lacks QRD, QRF, URD and URS; it lacks ten of v2.8.2's (BUI, CDO, DON, DPS, MCP, OMC, PM1, RXV, SGH, SGT) and has none v2.8.2 lacks.
- Field counts: 152 segments have v2.8.2's count; 18 have fewer (ACC, AUT, BTX, IN1, IN3, ITM, OBX, OM1, OM4, ORC, PKG, PRT, RF1, RXA, RXC, RXD, RXG, TCC). Every difference from v2.8.2 within a segment was read on the v2.7.1 page and kept as printed.
- Withdrawn fields: a `W` field carries exactly the data type its attribute table prints. v2.7.1 prints the DT cell blank for 76 of its 77 `W` fields; only UB1-1 keeps a type (SI, CH06 6.5.10). `audit-schemas.py` holds v2.7.1 to the rule.
- Blank OPT: 87 fields in 11 segments print no OPT code (NST 14, NSC 8, SCD 37, SCP 8, SDD 7, SLT 5, STZ 4, PKG-4, RCP-7, ACC-12, STF-41), each region cited in `UNREADABLE_WHITELIST`; read as optional (register §A addendum P6-12).
- Table openness: 14 fields carry `tableOpen` with a v2.7.1 quote (0136: DG1-24, IVC-13, PSG-4, PSL-47, RFI-3; 0167: RXD-11; 0185: CTD-6, PRD-6, PRD-14; 0206: ARV-2, IAM-6; 0371: OM4-7, SAC-27; 0532: PSL-21), matching v2.6 and v2.8.2.
- Table repairs (`table-repairs.json`): OBX-5 binds no table (9999 appears only in the ANO example table); OBX-8 binds 0078, which the defining attribute table omits (no TBL#) but Chapter 2C 2.C.2.15 ("Where used: OBX-8") and the CH07 category tables print. 0078 is user-defined and OBX-8 is CWE, so no closed-table check can fire.
- RDT is modelled as on v2.6 and v2.8.2 (CH05 5.5.8, p. 48: SEQ 1-n, varies, R).

**Conditional fields (P10-5a, P10-5b).** Every printed `C` was read against its own v2.7.1 definition and compared with v2.8.2's; quotes and reasons are in `conditional-completeness-audit.md` ("v2.7.1 (P10-5a)" and "v2.7.1 (P10-5b)"). Readings that differ from v2.8.2:
- ORC-2/3 and OBR-2/3 take the v2.6 forms: v2.7.1 prints no Send Number exception (CH04 4.5.1.2-3, pp. 34-35; 4.5.3.2-3, pp. 55-56). The `messageCode not in (OUL, OPU, OPL)` gates and the ORC-absent `messageCode in (ORU, ORF)` leg are kept (ruling C5; register §D); the OBR-2/3 ORC-absent clause has no `OBR-3 empty` guard because the v2.7.1 text says the placer number "must be present" (CH04 4.5.3.2, p. 55).
- OBR-7 and OBR-25 take the v2.8.2 report set (QRY and ORF withdrawn as of v2.7, CH07 7.2.3).
- PRT-5/8/9/10 have no PRT-22 leg (CH07 7.3.4.5); PID-35 and PID-36 take v2.6's "Conditionality Rule" sentences (CH03 3.4.2.35-36); AIS-10, AIG-14, AIL-12 and AIP-12 keep v2.8.2's filler set (CH10 10.5.3 withdraws SQM/SQR as of v2.7).
- CSR-8, MFI-6 and ROL-4 are printed `R` and modelled `C` with an optionality citation (P4-30); RXA-4 stays `R` (owner ruling G8).
- EQU-3 (`messageCode = ESU`, CH13 13.4.1.3), RCP-4 (prohibited, warning, when RCP-1 is not `D`, CH05 5.5.6.4) and ROL-1 (required in the Chapter 12 and Chapter 15 messages, CH15 15.4.7.1) are v2.7.1's own readings of sentences that v2.6 and v2.8.2 printed but left bare. The same rules were then applied to every version printing the same sentence (P10-5b intake `8fbd4aa`; P10-7 intake `94c9780`).
- No position carries `conditionIsPredicate`: it marks only complete predicates (ADR-021), which no v2.7.1 rule needed.

**Example messages (P10-7).** The 222 v2.7.1 examples and every example declaring MSH-12 `2.7` run through the validator. Every error line (249 on the 2.7 and 2.7.1 examples at P10-7) is claimed by a registry entry cited to the v2.7.1 print: 248 example defects and one substitution effect, no misfire. The v2.7.1 text layer encodes a printed hyphen as U+2010; the example extractor maps it to "-" (94 false format warnings removed; self-check added).

## Differences from v2.6 and v2.8.2 (summary)

| Area | v2.7.1 against v2.6 | v2.7.1 against v2.8.2 |
|---|---|---|
| Segments | +IAR, PAC, PRT, SHP; −QRD, QRF, URD, URS (170 each) | −10 segments (180 against 170) |
| Fields | 2,519 against 2,465 | 2,519 against 2,717; 18 segments shorter |
| Withdrawn fields | 77 against 22 | 77 against 81; UB1-1 the only typed `W` on both |
| Code tables | +10, −12 (535 against 537) | −30 (535 against 565) |
| Datatypes | component tables for all 72 composites | +LA1, LA2; −OG; PRL.2, XON.4, XON.5 differ |
| Order numbers | same placer-or-filler forms | no Send Number exception |

## Message structures (P8b-16)

The extractor reads 414 v2.7.1 captions: 39 excluded as examples, query profiles or templates
(ruling G7; the CH08 8.4.3 exclusion is scoped to its MFN^M14^MFN_Znn caption, and the CH05
5.9.1.1 RDR restatement is excluded as on the other versions), 182 structure IDs, 169 read and
13 unreadable (G6 placeholders and templates). 164 are committed under
`Resources/structures/v2.7.1/` and v2.7.1 is `complete: true`; with the 58 registered in
`completeness.json` they account for all 222 Table 0354 v2.7.1 rows. A 2.7 message is checked
against them through `Version.grammarVersion`.

Rulings applied (progress ledger): primary print, and the looser print where two normative
prints disagree (ACK from CH10 10.4; RQC_I05's 11.3.5 recorded); no-bar `< ... >` groups as
named required groups (eleven CH16 structures and SDR_S31/SDR_S32; the CH16 text never says
"one of"); Z message types and triggers on a complete version; Table 0354 triggers merged into
each structure (ADT_A39, MFK_M01, RPI_I01; RPI^I04 a declared shared trigger); the CH04A
4A.3.20 "Query Trigger (= MSH-9)" line adds QBP^Q31 to the registered QBP_Q11. Two reader fixes
(a header row repeating the caption, CH07 7.17.1; a group mark whose name wraps) and 13 cited
print errata (register §E v2.7.1 addendum).

Not modelled, with reasons in `completeness.json`: PGL_PC6, PPR_PC1, PPP_PCB, PPG_PCG, PRR_PC5,
PPV_PCA, PTR_PCF and PPT_PCL (CH12 `< OBR | Hxx etc. >`, G6); QBP_Q11, RSP_K11, QBP_Q13, QBP_Q15
and QVR_Q17 (CH05 query templates, G6); RDR_RDR (no normative print); UDM_Q05 (URD and URS) and
QRY_PC4, RCI_I05, RCL_I06 and RQC_I05 (QRD and QRF, withdrawn as of v2.7), segments v2.7.1 does
not define (Blocking, a model limit, since P8b-final F-I2); and 39 Table 0354 rows marked
Deprecated with no printed syntax. P8b-final (ruling F-I1) folds ORU^W01 onto ORU_R01 (CH07
7.14.1) and records the CH03 3.3.63 query profile's `RSP^K32^RSP_K25` as a printed pair, so
neither is a mismatch.

Requirement 4 evidence: with the structure check off the validation digest is byte-identical;
with it on, 146 example messages change: 68 now match cleanly, 32 stay info with a new reason,
46 are example defects cited to the print (ACK trailing space, CH13 bare-code MSH-9.3, CH10 AIP
before AIL, query events Table 0003 does not define, ADT^A44 under ADT_A43, MFK^M13^MFK_M13,
acknowledgment bodies labelled MFN^M16 and SLR^S28), and none is a misfire. 13 probes in
`StructureV271ProbeTests` cover structures not probed on any other version.

## Known limitations (registered, not shipped — req #3 / #4)

- **Bare conditionals:** 65 field positions (register §A; per-position quotes in the conditional-completeness audit) and 19 component positions (register §D addendum, P10-2). Each is fail-safe (read as optional).
- **TXA-22** component co-presence ("both must be valued as non-null"), a field-local composite rule (register §D addendum, v2.5.1 to v2.8.2).
- **ROL-4** "same values as the correlated field" sentence (register §A, P4-30 addendum).
- **Blank OPT** on 87 fields (register §A, P6-12 addendum).
- **Withdrawn fields** are untyped as printed; a populated one raises only the withdrawn-field warning (register §C).
- **ORC/OBR group heuristics** and the OUL/OPU/OPL gates (register §D).
- **Message structures** are not modelled on v2.7.1 (or `2.7`); each message raises `messageStructureNotModelled` (info) when the opt-in check is on (register §E; rollout plan P8b).
- **`2.7` substitution** is unverified without the v2.7 text (register §F, ADR-018).

## Defects found in shipped data and fixed along the way

Reading v2.7.1 against its neighbours exposed defects in versions already shipped. Each was fixed from that version's own print, with a self-check or test:

| Defect | Version | Fix | Commit |
|---|---|---|---|
| Tables 0359 and 0418 stored the ellipsis row as a code and were closed; 0544 closed although cited "for suggested values"; wrapped prose stored as codes (0088, 0343, 0396); Chapter 2C ".." filter dropped rows (0093, 0466, 0141) | v2.8.2 | Corrected tables; ellipsis read in both layouts; dotted-leader filter only | `d478e3b`, `bd8d26a` |
| Table 0141 range rows (`E1 ... E9`, `O1 ... O9`, `W1 ... W4`) stored as literal codes or missing | v2.3.1 to v2.8.2 | Pattern rows matching exactly the codes they name | `bd8d26a` |
| MFA-5 and MFE-4 read "Varie", OBX-5 "varie" (wrapped DT cell) | v2.5.1 | Extractor completes the wrapped cell; schemas already said Varies | `7dfe7ce` |
| Table 0131 bound on CTD-1 and NK1-7 but absent | v2.4 | Created empty, user-defined (CH03 3.4.5.7) | `f3aec80` |
| NA typed on SAC-11 and SAC-14 with no grammar | v2.4 | Four printed values from CH07 7.14.1.1, open-ended | `84cf7e0` |
| 30 withdrawn fields carried a type the print leaves blank | v2.8.2 | Untyped as printed; UB1-1 keeps SI | `ed0d2bb` |
| ITM schema stopped at ITM-6 (table cut at a page-foot footnote) | v2.6 | ITM-7 to ITM-29 added; `itemNaturalAccountCodeAsCWE` | `bae0622` |
| 11 withdrawn fields carried a type the print leaves blank | v2.6 | Untyped as printed; v2.5.1 MSA-5 kept as the one registered exception (released accessor) | `a4f34f5` |
| Prose bleeding into the last row's element name; page-foot footnote read as a row | all versions | Segment-table extractor fixes with self-check cases | `30283ba`, `41d354d` |
| EQU-3, RCP-4, ROL-1 left bare against their own text | v2.4 to v2.8.2 | Rules applied where the same sentence is printed | `8fbd4aa`, `94c9780` |
| Extra-component messages cited "v2.5.1 and v2.8.2 section 2.6.2 a" on every version | all versions | Message cites the validating version's own section | `1aff1a9` |

## Regression coverage

`V271GrammarTests` (16 tests) pins the inventory, the Unicode ellipsis, the openness and kind readings, the 14 previously truncated composite tables, the segment set against v2.6 and v2.8.2, the per-chapter field counts, hand-read fields and the withdrawn-field rule. The conditional-rule tests pin the v2.7.1 conditioned set and the bare-C guard; `VersionHandlingTests.versionMatrix` pins `2.7.1` (modelled) and `2.7` (substituted); `StructBasePinTests` pins the struct bases; the spec-example registry claims every v2.7.1 example error line.
