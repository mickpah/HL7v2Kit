# Changelog

All notable changes to HL7v2Kit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added — P7-2: the conditional-completeness register is pinned to the grammar

- **Every bare `C` must be named in the register (V251-C12).** `BareConditionalGuardTests`
  already pinned each version's set of `C` fields with no predicate (v2.3 to v2.7.1; v2.8.2
  in `MultiVersionTests`), but a field could join a set with a literal update alone. A new
  test reads `docs/design/conditional-completeness-audit.md` and fails when a bare `C` on any
  of the seven versions is not named there. The two slots V251-C12 found unregistered,
  TXA-21 (v2.3 to v2.6, registered in P4-15) and OBR-48 on v2.5.1 (scope added in the P1
  fix round), are named today.
- **v2.4 ROL-1 is required in the Patient Care messages (P10-7 intake).** v2.4 CH12
  section 12.4.3.1 (p. 24): "This field is required when used in Patient Care messages. The
  field is optional when used in ADT and Finance messages." ROL-1 was bare on v2.4 because
  the sentence differs from v2.5.1's; it now carries `messageCode in (PGL, PPG, PPP, PPR,
  PPT, PPV, PRR, PTR)`, the eight CH12 messages, each of which carries ROL. ADT, Finance,
  CH13 and PMU messages are unaffected on v2.4. `RoleConditionTests` covers both sides.

### Fixed — P8b-final: findings of the whole-branch review of the message-structure rollout

- **An exact-matched structure names what it expected (F-I3).** A structure that fails the
  determinism lint reports its one finding at the furthest segment any parse reached, so a
  required segment absent mid-message was reported only as the next segment unexpected
  ("PID has no place in BAR_P01 at this point", EVN never named). The text now adds the
  segments the structure accepts there: "; expected here: SFT or EVN" (each ID once, in
  structure order, at most eight then "and N more", "or the end of the message" when a parse
  is complete there). Code, severity, location and the number of findings are unchanged. In
  the three validation digests 4 lines change (default and strict), each this clause only.
- **A structure ID the version's print gives is never a mismatch (F-I1 a, b; reverses the
  P8b-14 ruling, owner to confirm).** v2.3.1 prints structure IDs only in Table 0354, and ten of
  its rows are misprinted: TBR_R09, RRE_O01, MFD_P09, PIN_107, RPI_I0I, RQI_I0I, ARD_A19,
  SIIU_S12, RROR_ROR and ORM__O01 were mismatches (error under `.strict`) for a message that
  copied them; they are now registered as not modelled, so `TBR^R08^TBR_R09` or
  `TBR^R09^TBR_R09` is information naming TBR_R08, not structure-checked. The corrected IDs and
  the bare triggers keep matching. v2.4's CH02 listing of Table 0354 (2.17.3, pp 2-138 to 2-141)
  prints ten rows Appendix A lacks or prints differently (QRY_Q26 to QRY_Q30, whose CH04
  captions read QRY^Q26^QRY_Q01 and so on; RPI_I0I, RQI_I0I, ORN_008, TBR_R09, RDE_O01), and
  v2.5.1's listings disagree on BRP_030 and RSP_Q11: registered likewise. PPG^PCC is registered
  with PPG_PCG on v2.5.1, v2.6 and v2.8.2, as on v2.3.1, v2.4 and v2.7.1 (every Table 0354 lists
  PCC under it). The codegen accepts a registered ID that is not of the CODE_EVT form only as the
  printed ID of a cited table-0354 erratum. Registered: v2.3.1 38, v2.4 34, v2.5.1 32.
- **Deprecated Table 0354 rows carry their events (M4).** The v2.7.1 and v2.8.2 registrations of
  rows the printed table marks Deprecated (39 and 47) had no triggers, so a bare `ORM^O01` got
  the generic reason; the 76 whose row lists events now carry them (`ORM^O01`), written and
  checked by `scripts/extract-message-structures.py` (`--write` / `--check`) from Table 0354, so a
  bare trigger gets the Deprecated reason. No trigger is shared with a modelled structure
  except `ORU^W01` on v2.7.1 and v2.8.2 (next item).
- **`ORU^W01` is an ORU_R01 trigger on v2.3.1 to v2.8.2 (F-I1 c).** Each version's CH07 W01
  section says the waveform trigger "identifies ORU messages" (v2.3.1 7.19.1 p 7-117, v2.4 7.15.1
  p 7-117, v2.5.1 7.15.1 p 7-130, v2.6 7.15.1 p 7-110, v2.7.1 7.14.1 p 140, v2.8.2 7.15.1 p 153)
  and v2.6 to v2.8.2's examples send `ORU^W01^ORU_R01`, which was a mismatch. W01 is now folded
  onto ORU_R01 through `referencedTriggers`, as on v2.3: `ORU^W01^ORU_R01` is matched against
  ORU_R01; `ORU^W01^ORU_W01` (Table 0354's ID, no printed syntax) stays information; a bare
  `ORU^W01` resolves to ORU_R01 on v2.3.1 to v2.6 and is ambiguous (information) on v2.7.1 and
  v2.8.2, where the Deprecated ORU_W01 row carries W01 (declared in `sharedTriggers`). The
  extractor's shared-trigger check now counts registered structures' triggers, as the codegen
  guard does.
- **Every printed (trigger, structure ID) pair swept (F-I1 d).** A sweep validated one message
  per pair that any printed Table 0354 listing (CH02 / CH02C and Appendix A), caption or query
  profile trigger row gives, on every version (4,747 messages; a table row's events tried under
  every code a caption prints for them). Printed pairs still reported as mismatches: v2.4 CH02
  2.14.2 (p 2-97) prints the delayed acknowledgment as `MCF^varies^ACK`, so `MCF^A01^ACK` was
  reported; the general ACK fold now also takes `MCF^*` from that caption (extractor
  `fold_triggers`, cited in the structure). The v2.8.2 CH04 4.16.6 and 4.16.8 query profiles
  print QBP_Q33, RSP_K33, QBP_Q34 and RSP_K34 where the captions give QBP_O33 and so on: now
  registered (v2.8.2: 62 registered). The v2.7.1 CH03 3.3.63 and v2.8.2 CH03 3.2.63 profiles
  print `RSP^K32^RSP_K25`, whose ID is modelled for RSP^K25: a new completeness.json
  `printedPairs` list (codegen-checked: the structure is loaded and does not print the trigger)
  makes such a pair information. The six rows left are Table 0354 event misprints that are not
  trigger events (v2.3.1 `136`, `1II`; v2.4 and v2.5.1 `007`, `022`), whose corrected events
  match.
- **The rule stated where a consumer reads it (F-I1 e, M7).** Migration.md ("The
  message-structure check is on by default") and ADR-019 (amendment 2026-10-05) state that a
  printed structure ID is never a mismatch and what a consumer gets in each case: matched,
  information (registered, or a `printedPairs` entry), or a mismatch only for an ID printed for
  other triggers or nowhere. The register's v2.4 Table 0354 and close-out paragraphs, the spec
  audits and Validation.md say so too; earlier CHANGELOG entries that call the v2.3.1 misprints
  mismatches are annotated.
- **Documents and comments (M1, M2, M3, M5, M6, M8, M9).** `ADT^A47^ADT_A30` and
  `ADT^A49^ADT_A30` on v2.7.1 and v2.8.2 draw information, not a mismatch (ADT_A30 is registered
  with no triggers there): the register close-out, STATUS.md and NEXT_STEPS.md say so (M1). The
  resolver's comment says Table 0354 is not consulted at runtime, its rows being merged by the
  extractor (M2). The `MessageStructureTable` DocC says what a lookup miss does and does not mean
  (M3). The 00060.1 text says every profile `unexpected` finding is dropped, not only
  beyond-maximum ones (M5). The `messageStructureSegmentMissing` DocC says v2.3 to v2.4 group
  names and v2.3 structure IDs are not the print's, and corrects "off by default" (M6). The
  register's performance row records the two resolutions and base matches per `validate` (M8).
  Validation.md and Migration.md state that one unrelated structure finding switches the OUL /
  OPU / OPL order-number predicates off, with no issue saying so (M9). No API change.
- **The Permanent / Blocking line drawn by its definition (F-I2).** v2.7.1 QRY_PC4, RCI_I05,
  RQC_I05, RCL_I06 and UDM_Q05 and v2.8.2 UDM_Q05 print their full syntax and are registered only
  because it names QRD, QRF, URD or URS, which the version's grammar does not define: a model
  limit, now **Blocking**, each reason naming what would close it (segment grammars for the
  withdrawn segments, or a rule that passes over them and checks the rest). v2.8.2 QBP_Q13's
  reason no longer says "no normative print": CH05 5.4.2 refers to 5.3.1.2, an example query
  profile whose grammar (query Z99) has a query-specific PID and disagrees with 5.4.2's own
  segment list, so it stays Permanent as a template ID. Outcomes unchanged (information).

### Fixed — P8b-18: message-structure rollout close-out

- **Rollout complete.** Every structure the seven versions print is modelled or registered with
  its reason: v2.3 147 / 22, v2.3.1 100 / 28, v2.4 148 / 24, v2.5.1 173 / 30, v2.6 190 / 20,
  v2.7.1 164 / 58, v2.8.2 185 / 58 (1,107 modelled, 240 registered; 266 after P8b-final), plus five ADRM-2021 profile
  structures on v2.4. Register section E opens with the state at close-out: what a consumer gets
  per version, and why every version still has Blocking rows (master-file prose fragments on v2.3
  to v2.6, a structure alias for QRY_P04 on v2.4 and v2.5.1, per-trigger structures on v2.5.1 to
  v2.8.2, fragment reassembly and version provenance everywhere). ADR-019 gains the close-out
  amendment and its status line.
- **Group scoping (P8b-17) imprecisions registered, not fixed:** a container or specimen OBX
  beside repeating orders takes the first order's ORC and OBR, and that order's ORC and OBR take
  it (v2.4 ORL_O22; v2.5.1 and v2.6 ORL_O34, ORL_O36; v2.6 OPR_O38); v2.4 OML_O21 OBR to OBX;
  v2.7.1 and v2.8.2 ORU_R30 message-level OBR to OBX; v2.8.2 `.obrObxGroup` on ORU_R01; the
  worst-case lookup cost. No shipped condition reads these lookups. The termination comment in
  `GroupScoping.swift` states the real call graph.
- **HL7au:00060.1 wording:** a required segment the profile still expects when segments follow
  the last one it matched (RQD or RQ1 for an ORM^O01 order detail, or a Z-segment) now reads
  "requires OBR in group ORDER after ORC[1]", naming the last matched segment, not "at the end of
  the message": the segments after it are transparent to the profile match, so OBR may stand
  anywhere after ORC[1]. Code, severity and location (the last segment) are unchanged
  (Migration.md row). The fix rounds tried "in place of RQD[1]" (the first passed-over segment,
  not necessarily the one replaced) and "no later than <last segment>" (false: OBR appended
  after the last segment satisfies the profile). The OSR^Q06 register row names every unflagged case against ADRM p 281
  (RQD, RQ1, RXO, ODS or ODT in place of OBR, and an OBX after any of them); the conformance
  register is regenerated. The unused `profiles:` test seam of `matchProfileStructure` is removed.
- **v2.4 group names:** ADR-019 states why the 35 `groupNames` overrides stand in place of
  extractor borrowing, and what each cites.
- **v2.4 Table 0354 listings:** CH02 (p 2-139) lists QRY_P04 and QRY_Q26 to QRY_Q30, which
  Appendix A and `Resources/tables/v2.4/0354.json` do not; registered for P7 (table JSON unchanged).
- **Tests (1538 to 1541):** v2.8.2 COMMON_ORDER cases in the long-message growth test;
  `customRuleCountsEachAnchor`; the real v2.4 REF_I12 same-name PATIENT_VISIT siblings; the
  v2.3.1 literal misprints PIN_107, RPI_I0I, RQI_I0I and ARD_A19 as mismatches (information since
  P8b-final, ruling F-I1). Validation digests
  (default, strict, structure off) byte-identical to 9c81e6eb.

### Changed — P8b-18: the message-structure check is on in `.default` and `.strict`

- **Default output changes (owner decision G2 (b), ADR-019 "Later preset change"):**
  `ValidationOptions.messageStructureSeverity` is `.warning` in `.default` (and for a memberwise
  `ValidationOptions()`), `.error` in `.strict`, and `nil` in `.lenient`. On the spec's printed
  examples and the fixtures the default digest gains 4,284 lines: 3,428 info issues (no structure
  applied, with the reason) and 856 warnings on 167 messages, each a genuine example or fixture
  defect (`p8b-18-classes.tsv`); `.strict` gains the same lines at error; `.lenient` is unchanged.
  Migration.md has the row and a section. The preset pins changed (MessageStructureValidationTests,
  SignatureCompatibilityTests); five tests whose subject is another rule now set the structure
  findings aside, and two acknowledgment-builder tests expect the info issue.
- **Performance:** the AU REF^I12 re-match (P8b-4a) passes over every segment the base
  structure names nowhere in one pass; structure resolution reads a trigger index built once per
  version (resolve 106 us to 14 us); group scoping reads each segment's innermost group occurrence
  from an index built once per message instead of a linear search per lookup, and the exact
  matcher's span computation computes each state's reach once (both behaviour-preserving: the
  three validation digests are byte-identical). `PerformanceStructureTests` (gated by
  `RUN_PERF_TESTS`; release build, best of three, Apple Silicon) measures:
  - **The spec 9.5 budget** (two rows, both for a 1 KB message, default options): a 1,002-byte
    v2.5.1 ADT^A01 validates in 0.52 ms with the check at `.warning` (budget 2 ms) and 1,000 of
    them in 0.54 s (budget 10 s). The 2 ms row is met in a release build only: in a debug build
    the message takes about 2.5 ms, and took 2.35 ms with the check off at 542f5cd, before the
    rollout.
  - **Derived scaling checks, not spec budgets** (9.5 prints no budget for a long message; the
    limit is the 1 KB row scaled by size, 2 ms per KB): a 5,002-segment ORU^R01 of 150,084 bytes
    (limit 293 ms) validates in 227 ms on v2.5.1 and 269 ms on v2.8.2 at `.warning` (1.55 and
    1.83 ms per KB; one release run of `PerformanceStructureTests`, `RUN_PERF_TESTS=1 swift test -c
    release`, at 1e3d8f26 on 2026-10-05, P8b-final carry-forward). The AU REF^I12 with 200 to 800 ADRM-added segments (3,125 to 12,327 bytes)
    takes 7.9 to 40.3 ms, 2.59 to 3.35 ms per KB, over its derived limit (6.1 to 24.1 ms); it was
    over it before the rollout too (6.9 to 36.8 ms at 542f5cd), so the rollout added 1.0 to 3.5 ms;
    a profile puts the time in the AU profile's field-level checks (register section E, close-out
    addendum). The three cases are wrapped in `withKnownIssue`, citing that row.
- The validation digest keeps a preset's own severity unless `VALIDATION_DIGEST_STRUCTURE_SEVERITY`
  is set (`off` forces it off) and accepts `VALIDATION_DIGEST_PRESET=lenient`.

### Fixed — P8b-18: registered structures and triggers classed by the print on every version

Every structure and trigger registered as not modelled now says one true thing in one of three
classes: the print names an already printed structure (modelled through `referencedTriggers`),
the print gives the segments only in prose fragments (blocking: the extractor does not read
them), or the print gives neither (permanent, the reason quoting what it does give). No segment,
group, cardinality or choice of a modelled structure changes.

- v2.3: DSR^P04 (the response of CH06 6.3.4's "QRY/DSP transaction"; CH02 prints DSR twice with
  MSA required and optional, mode not stated) and ORU^R03 (Table 0003 gives R03 to QRY/DSR; one
  CH07 7.4.5.3 example sends ORU^R03) are registered with their reason: 22 registered.
- v2.3.1: QRY^P04 is matched against QRY_Q01 (CH06 6.3.4, p 6-4, "the QRY/DSR transaction, as
  defined in Chapter 2"; both Chapter 2 QRY prints are MSH QRD [QRF] [DSC]), as on v2.3, with
  MSH-9.3 empty or QRY_Q01; DSR^P04 is registered (the two DSR prints differ on MSA): 28
  registered. MCF, folded in P8b-15, is named among the printed IDs Table 0354 lacks.
- v2.4: MFR_M01 and MFN_M03 are blocking, not templates: CH08 gives the MFR body per master file
  in prose ("the part ... {MFE [Z..]} is replaced by", 8.7.1 p 8-19, 8.8.2 p 8-21, 8.9.1 p 8-58,
  8.10.1 p 8-72, 8.11.1 p 8-81) and keys MFN^M03's other segments by MFI-1 (8.8.2), which the
  extractor does not read. QRY_P04 is blocking: CH06 6.4.4 refers P04 to the Chapter 5 QRY, whose
  two prints agree, but the caption QRY^P04^QRY_P04 gives it an ID of its own and the model has no
  structure alias. DSR_P04 stays permanent (the two Chapter 5 DSR prints differ on MSA). 24
  registered, unchanged.
- v2.5.1: MFR_M01 and MFN_M03 are blocking, not templates: CH08 gives the staff MFR body only in
  prose (8.7.1, pp 8-20 to 8-21), the M03 and M08 to M12 bodies by reference (8.8.2, p 8-22),
  and MFN^M03's other segments as the MFN^M08 to M12 groups, each keyed by MFI-1. QRY_P04 is
  blocking as on v2.4 (Table 0354 gives it an ID of its own). The Table 0354 reasons now cite the
  right page and say what the print gives instead: ORU_R31 and ORU_R32 (Appendix A listing only;
  the chapter prints ORU^R31^ORU_R30 and ORU^R32^ORU_R30), QRY_T12 (CH09 prints QRY^T12^QRY),
  RSP_K22 (CH03 prints RSP^K22^RSP_K21), RDE_O01 and RRA_O02 (Appendix A only), MFD_MFA (named in
  CH08 8.4, no syntax). 30 registered, unchanged.
- v2.6: MFR_M01 and MFN_M03 are blocking, not templates, as on v2.5.1 (the staff MFR body in
  prose, 8.7.1, pp 8-18 to 8-19; MFN^M03's other segments as the MFI-1-keyed MFN^M08 to M12
  groups). ORU_W01's reason now says the CH07 7.17 examples send ORU^W01^ORU_R01 against Table
  0354's ORU_W01; QRF_W02's cites CH07 7.15.2. On v2.5.1 the waveform examples are cited as
  7.17, not 7.16. 20 registered, unchanged.
- v2.7.1 and v2.8.2: every registration read and unchanged (Table 0354 rows marked Deprecated,
  templates, CH12 placeholders, prints of segments the version does not define).
- Register statuses agree for equivalent prints. SUR_P09's `ED` row is permanent on every version
  (it was blocking on v2.5.1 and v2.6; v2.5.1 CH07 7.11.2 prints the row on p 7-102, and the
  section's deprecation note on p 7-101 calls it "an invalid ED segment"). A structure registered only for an open slot, whose other segments are printed,
  is blocking on every version (fix round 1 reversed the first pass, which had made them
  permanent): the CH12 `OBR, etc.` order detail on v2.3 to v2.8.2 (52 registrations), the
  general order detail of ORM_O01, ORR_O02 and OSR_Q06 on v2.3 and v2.3.1. CH04 4.2.2.4 (v2.5.1 p 4-5; 4.1.2.4 on v2.3 and v2.3.1) says "Examples are
  OBR and RXO. Future ancillary-specific segments may be defined": the slot is open, and an
  open-slot structure element would let the validator check everything printed around it but not
  what fills it. The 58 reasons say so; the register, NEXT_STEPS and STATUS list the element as
  a follow-up for the owner. ERP on v2.3 to v2.5.1 is blocking too, but not on an open slot: ERQ-2
  (Event Identifier) "dictate[s] the format of the response message", and the ERP returns the
  segments of the message that event defines (v2.5.1 CH05 5.10.5.2.3, p 5-124), so modelling it
  needs a structure keyed by a field value, as MFN_M03 needs one keyed by MFI-1.
- Counts, modelled and registered: v2.3 147 and 22, v2.3.1 100 and 28, v2.4 148 and 24, v2.5.1
  173 and 30, v2.6 190 and 20, v2.7.1 164 and 58, v2.8.2 185 and 58; the P8b-9 and P8b-10
  entries below note their later counts.

### Fixed — P8b-18: Table 0354 provenance on every version; citation and guard minors

- **Provenance (citations only):** every structure whose ID the extractor reads from Table 0354
  now says so with the table's page, on every version that prints the table, as v2.3.1 has since
  P8b-14: 24 on v2.4 (the two-part captions), 12 on v2.5.1 and 6 on v2.6 (QRY_Q02, QCK_Q02 and
  the other captions that print no ID). v2.7.1 and v2.8.2 print every structure's own ID, so none
  is added there. No segment, group, cardinality, choice or trigger changes.
- **Page citations:** v2.3 2.18.1 and 2.18.2 are on p 2-75 (not 2-74), Table 0076 on pp 2-89 to
  2-90 (not 2-88 to 2-89); the v2.3 ORU^W01 reference also cites 7.14 (p 7-104); the spec audit
  counts ten printed v2.3.1 IDs with no Table 0354 row (with MCF); a test comment gives v2.5.1
  QRY^Q02 its page, 5-116.
- **Extractor guards:** a `referencedTriggers` trigger must carry the structure's message code
  and enters the shared-trigger check; a `captionStructures` entry is looked up as a Table 0354
  row before its row's message code is compared; a direction caption (`CODE^EVT (A to B)`) must be
  a column header ending in "Chapter", so running prose of that form is no caption.
- **Codegen guard:** a profile group named through nameSource `override` must be a name an
  overrides.json `groupNames` entry gives the base structure, not merely cite "overrides.json".

### Changed — P8b-17: structure group spans scope the group-dependent predicates

- Default output changes on purpose (ADR-019 decision 5): on every complete version a message
  whose structure matches cleanly has its ORC/OBR peers, segment-presence atoms, ORC/OBR pair
  equality and group-scope cardinality rules scoped by the matched group instances, whatever
  `messageStructureSeverity` is. One principle decides the scope: a group that occurs at most
  once per occurrence of its parent is transparent for the anchor, the peer and the group scope
  alike (the v2.8.2 COMMON_ORDER's ORC serves the whole order; an OBR in DFT `[ORDER]` is
  scoped at its COMMON_ORDER, so it finds that order's OBSERVATION OBX); only a repeating nested
  group that claims its own segments, such as ORDER_PRIOR, is a boundary; a peer never comes
  from a repeating sibling group
  (v2.8.2 CSU_C09: the pharmacy ORC has no OBR) or a nested pairing group (the prior results
  of OML_O21, OML_O33, OML_O35 and OMQ_O42). Otherwise the ORC walk is used as before.
- The P4-7 and P10-5a `messageCode not in (...)` gates are removed: from ORC-2, ORC-3, ORC-8,
  OBR-2, OBR-3 and OBR-29 on v2.5.1 and v2.6, and from ORC-2, ORC-3, OBR-2 and OBR-3 on v2.7.1
  and v2.8.2 (the only fields gated there): OUL^R21 to R24, OPU^R25 and
  OPL^O37 messages are now checked inside their own groups. An OUL, OPU or OPL message with no
  spans (a structure deviation, disagreeing parses) keeps the gate's outcome on those fields
  (register, Addendum to §D).
- The exact matcher reports group spans when every accepting parse puts every segment in the
  same group occurrences, and withholds them when parses disagree. Its verdict and finding are
  unchanged.
- The spec-example and fixture digest is unchanged in outcome: 152 issue lines per digest
  (default, structure check at warning, `.strict`) change only in the quoted condition text.
  `ValidationDigestTests` gains `VALIDATION_DIGEST_PRESET=strict`.

### Added — P8b-15: HL7 v2.3 message structures complete; lookup rule 3

- With `messageStructureSeverity` set, every v2.3 message structure is now checked: 147
  structures extracted from the v2.3 chapter prints (10 matched exactly), and v2.3 is marked
  complete, so every supported version is. `ADT^A01` on v2.3 with no EVN or PV1 now draws two
  missing-segment findings where it drew one info issue.
- ADR-019 lookup rule 3: v2.3 defines no MSH-9.3, so a message whose MSH-12 reads as 2.3 is
  resolved from MSH-9.1^9.2 only and a populated third component is ignored (never a mismatch).
  A trigger the v2.3 print covers resolves to its own print; one it does not (an event printed
  under no syntax table, a Z event) is info, never an error.
- v2.3 prints the message code alone over each table, the events in the section title, no
  structure ID and no Table 0354. Structure IDs are synthesised `CODE_EVT` from the code and the
  first event of the title (`ADT_A04`, `SRM_S01`), or the code alone for the general
  acknowledgment and the four messages printed with no event (MCF, EDR, TBR, ERP); every v2.3
  citation says so and names where each event came from. v2.3 no longer reads v2.3.1's Table
  0354 or its errata. 39 captions whose section title names no event take their events from a
  cited `overrides.json` `eventsFromTitle` entry (section text or Table 0003).
- Group names, which v2.3 never prints: 235 derived through the HL7 v2.xml 2.3.1 bundle (new
  `nameSource` `v2xml-v2.3.1`), 7 through the v2.4 bundle, 3 synthesised.
- 22 v2.3 structures are registered as not modelled, each with its reason (register section E):
  the general order's `Order Detail Segment` placeholder (ORM_O01, ORR_O02, OSR_Q06; the four
  specialised ORM and ORR prints of CH04 share the trigger and cannot be told apart from
  MSH-9.1^9.2), eight CH12 `[OBR, etc.` structures, MFN_M01's `[Z..]`, ERP's ellipsis rows,
  SUR_P09's ED row, MFR_M01's `[Z..]` and MFN_M03's `[other segments(s)]`, whose segments the master file sections give per file in prose fragments the extractor does not read (a capability gap that blocks spec-completeness; only M01's `[Z..]` cannot be enumerated), and 6 triggers v2.3 defines only in Table 0003 or prose
  with no unambiguous printed structure (QRF^W02, QRY^R03, DSR^R03, DSR^R05; DSR^P04 and ORU^R03
  since P8b-18), whose info now gives the reason. The four triggers whose prose names a printed structure are added to it through overrides.json `referencedTriggers` and matched (ORU^W01 to ORU_R01, CH07 7.19.1 and 7.14; QRY^P04 and QRY^R05 to QRY_Q01, CH06 6.3.4 and CH07 7.2.2.1; UDM^R06 to UDM_Q05, 7.2.2.1). The v2.3.1 MFN_M03 reason, and the status of v2.3.1's
  MFN_M03, MFN_M08 to M11 and MFR rows, are corrected the same way (blocking, not permanent).
- v2.3.1 MCF (CH02 2.13.2) is now modelled through a `triggerFolds` entry onto `MCF^*`, as on v2.3:
  v2.3.1 has 100 structures.
- Errata, each cited to the v2.3 print: CH04 4.8.17's `R0R` read as `ROR` (Table 0076), the
  printed event R0R kept; crossed brackets in ADT^A07 (`[{ROL]}`), ADT^A31 (`{[ROL}]`) and CSU
  (`{[ ... }]`), whose two nested readings mean the same; CH02 2.11.1's WRQ/WRP notation example
  excluded.
- The extractor reads v2.3's other caption forms (`QRY (A to B)`, a code one space from its
  title or with no Chapter column) and rows whose syntax cell sits one space from its
  description or on a page set right of the caption. No v2.3.1, v2.4, v2.5.1, v2.6, v2.7.1 or
  v2.8.2 structure or report row changes.
- The `adt_a01_v23.hl7` fixture gains the EVN segment the v2.3 print requires.

### Added — P8b-14: HL7 v2.3.1 message structures complete

- With `messageStructureSeverity` set, every v2.3.1 message structure is now checked: 99
  structures extracted from the v2.3.1 print (10 matched exactly), and v2.3.1 is marked
  complete. An MSH-9.3 that names no v2.3.1 structure (`ADT^A04^ADT_A04`, or the misprinted
  Table 0354 ID `PIN_107`) is now `messageStructureMismatch` on v2.3.1 instead of info (for
  `PIN_107` and the other literally printed misprints, information again since P8b-final).
- Most v2.3.1 captions print `CODE^EVT` only; the structure ID comes from Table 0354 v2.3.1,
  read through cited errata for its misprinted rows (ARD_A19, PIN_107, RPI_I0I, RQI_I0I,
  TBR_R09, RRE_O01, MFD_P09 and the events 136 and 1II; PPG_PCG gains PCG and keeps PCC). Each
  structure whose ID came from the table says so in its citation, naming any erratum. Where the table lists an
  event under two structures (ADT^A28, ADT^A31) the triggers are declared shared; where its
  one row of a message code omits the caption's events (MFK, PPP) a cited declaration names
  the row; captions it places under no structure (MFN^M04, MFQ, MFR and the master file
  templates) are declared and not modelled. CH08 8.10.1's second clinical-trials print, captioned
  MFN^M06 and MFK^M06, is read as M07 (Table 0003).
- Group names: 247 from the HL7 v2.xml 2.3.1 bundle (each citation names the file's generator,
  since the bundle mixes two), 6 through the v2.4 bundle (the 2.3.1 bundle's CHOICE name is not
  taken without a cited override), none synthesised.
- 28 v2.3.1 structures are registered as not modelled (27 until P8b-18 added DSR_P04), each with its reason (register section
  E): the general order's `Order Detail Segment` placeholder (ORM_O01, ORR_O02, OSR_Q06), eight
  CH12 `[OBR, etc.` structures, ERP_R09, MFN_M03, SUR_P09 and 13 Table 0354 rows no print
  carries. Every Table 0354 v2.3.1 row is modelled or registered.
- The structure extractor reads `CODE ^EVT` (one space before the caret, CH08 8.8.1), treats
  notation in the description column inside an open group as a placeholder (OSR^Q06), and on a
  version with its own Table 0354 fails a full read on any caption the table cannot resolve
  unless a cited override settles it. No v2.4, v2.5.1, v2.6, v2.7.1 or v2.8.2 structure changes.
- The literally printed misprinted Table 0354 IDs (`TBR^R09^TBR_R09`, `RRE^O01^RRE_O01`,
  `MFD^P09^MFD_P09`, `PIN^I07^PIN_107`) are `messageStructureMismatch` on v2.3.1 (P8b-14 fix
  round 1, controller ruling); register section E gives the evidence. Reversed by P8b-final
  (ruling F-I1): they are registered and report information.

### Fixed — P8b-4a: AU profile structures govern base structure findings; RRI_I12

- Under the AU locale with `messageStructureSeverity` set, a v2.4 message that conforms to the
  ADRM-2021 print no longer draws base v2.4 structure findings the ADRM structure contradicts:
  a base finding is dropped where the ADRM structure accepts the message at that point (a segment
  it places there, such as PD1 in REF^I12, p 324, or ERR in RRI^I12, p 325; a segment it makes
  optional, such as PRD and PID in RRI^I12). Every other base finding is kept. Where the base is
  matched exactly (v2.4 REF_I12, RRI_I12 and ORU_R01, which report their first divergence only)
  and that finding is a dropped `unexpected`, the base is matched again with that segment passed
  over, until a finding is kept or none is left, so a later divergence is still reported. Narrowed
  maxima (REF^I12 `[IN1]`, PV1 and PV2) stay unreported: the base allows the repetition and the
  ADRM's beyond-maximum finding is not reported (decision 7). The international locale and
  triggers with no ADRM structure are unchanged (ADR-019 decision 7, amended).
- The order status response (OSR^Q06, p 281, caption erratum `OSQ^Q06^OSQ_Q06`) is the fifth ADRM
  structure: its `[{OBX}]` is accepted under the AU locale. Its order detail keeps the base v2.4
  choice, as the print says only "OBR Order Detail" and does not settle whether the p 280
  narrowing applies, so RQD or RQ1 there is not flagged.
- RRI^I12 is the fourth ADRM structure (p 325, `MSH MSA [ERR] [ RF1 {PRD} PID ]`): a missing MSA
  is reported as `profileConstraintViolation(localeRule: "HL7au:00060.1")`.
- The ORM^O01 order detail is narrowed to OBR, RXO, ODS and ODT (p 280: OBR is replaced only for
  medication and diet orders), so RQD or RQ1 in its place is an HL7au:00060.1 finding; the
  glossary citation moves to p 279.
- Register and self-check corrections: the RRI print is quoted with its brackets, "PID optional"
  on the order status response is no longer listed as a relaxation (base v2.4 OSR_Q06 has it), the
  conformance register row names the narrowed maxima and the base-finding rule, and
  `check-structure-codegen.sh` covers `baseVersion` and `rule` in a version file (71 cases).

### Added — P8b-4: HL7au:00060.1 required segments through the ADRM-2021 structures

- Under the AU locale with `messageStructureSeverity` set, a v2.4 ORU^R01, ORM^O01 or REF^I12
  is also matched against the structure the ADRM-2021 prints for it (pp 205, 279, 324), and a
  segment that structure requires and the message lacks is reported as
  `profileConstraintViolation(localeRule: "HL7au:00060.1")` at that severity: PID in each
  ORU^R01 result, PV1 beside PD1, NK1 or PV2, an order detail segment in each ORM^O01 order,
  RF1 and PV1 in REF^I12. A base segment the ADRM removed is not a finding (ADR-019 decision 7),
  and a segment the base check already reports missing is not reported twice. Default output is
  unchanged.
- The structures are hand-authored with page citations in
  `Resources/structures/profiles/au-adrm-2021/`; the codegen accepts the `profile`,
  `baseVersion` and `rule` keys only there and checks each structure against the base v2.4
  structure it constrains.
- HL7au:00060.1 moves from BASE to PARTIAL in the conformance register: RRI^I12, the Appendix 8
  simplified REF structure, the ORR^O02 print and the prose-only PV1 mandate are registered
  (register section E).

### Added — P8b-13: HL7 v2.4 message structures complete

- With `messageStructureSeverity` set, every v2.4 message structure is now checked: 148
  structures extracted from the chapter prints (18 matched exactly), and v2.4 is marked
  complete. An MSH-9.3 that names no v2.4 structure (`ADT^A04^ADT_A04`) is now
  `messageStructureMismatch` on v2.4 instead of info; `ADT^A01^ADT_A01` without PV1 is a
  missing segment.
- v2.4 prints no group names: 298 are named from the HL7 v2.xml v2.4 bundle, 35 by cited
  overrides (the v2.5.1 bundle's names for the seven structures the v2.4 bundle lacks, ORL_O22,
  RAS_O17, DFT_P03 and RCI_I05, whose bundle group is named `c`), and one is synthesised.
- 24 v2.4 structures are registered as not modelled, each with its reason (register section
  E): eight CH12 `[OBR, etc.` structures, five CH05 query templates, three CH08 master file
  templates, ERP_R09, SUR_P09, QRY_P04 and DSR_P04 ('see Chapter 5') and four Table 0354 rows
  with no print (ORU_W01, QRF_W02, RRA_O02, RRE_O02). Every Table 0354 v2.4 row is modelled or registered.
  (P8b-18 classes MFR_M01, MFN_M03 and QRY_P04 as blocking, not templates or permanent.)
- Shared triggers MFN^M02 to M06, RPI^I04 and RSP^K24 are ambiguous without MSH-9.3.

### Fixed — P8b-13: QRY_Q02 and QCK_Q02 on v2.4, v2.5.1 and v2.6

- QRY_Q02 and QCK_Q02 were registered as not modelled ("no chapter prints its syntax") on
  v2.4, v2.5.1 and v2.6, but CH05 5.10.3.1 prints both (v2.4 p 5-112, v2.5.1 p 5-116, v2.6
  p 96) as "QRY^Q02 (A to B)" and "QCK^Q02 (B to A)". The structure extractor now reads a
  `CODE^EVT` caption followed by a one-space direction tag. Both structures are modelled on the
  three versions: a QRY^Q02 without QRD is now a missing segment, and a QCK^Q02 without MSA
  likewise. Counts: v2.4 148 modelled, 24 registered; v2.5.1 173 and 30; v2.6 190 and 20.

### Fixed — P8b-13: ERP_R09 on v2.5.1

- v2.5.1 ERP_R09 was extracted as `MSH MSA [ERR] QAK ERQ [DSC]`, dropping the ellipsis rows
  CH05 5.10.4.2 prints for the replayed message's segments, so a compliant event replay response
  drew false findings. It is now registered as not modelled (info) on v2.4 and v2.5.1.
- The structure extractor drops footnote marks fused to brackets, reads a bracket-only cell in
  the description column as syntax, ends a table at a `CODE^EVT` row, treats an ellipsis row as
  a placeholder, accepts an `occurrence` on a syntax-cell erratum, and requires a cited override
  for a bundle group name no group name can hold; four v2.4 print errata are cited.

### Added — P8b-16: HL7 v2.7.1 message structures complete

- With `messageStructureSeverity` set, every v2.7.1 message structure is now checked: 164
  structures extracted from the chapter prints (20 matched exactly), and v2.7.1 is marked
  complete; a 2.7 message is checked against them (`Version.v2_7` reads through the v2.7.1
  grammar). An MSH-9.3 that names no v2.7.1 structure (`ADT^A04^ADT_A04`) is now
  `messageStructureMismatch` on v2.7.1 and 2.7 instead of info.
- 58 v2.7.1 structures are registered as not modelled, each with its reason (register section
  E): eight CH12 `< OBR | Hxx etc. >` structures, five CH05 query templates, RDR_RDR (no
  normative print), UDM_Q05 (URD and URS) and QRY_PC4, RCI_I05, RCL_I06 and RQC_I05 (QRD and
  QRF, withdrawn as of v2.7), whose segments v2.7.1 does not define, and the 39 Table 0354 rows
  marked Deprecated. Every Table 0354 v2.7.1 row is modelled or registered.
- ACK takes its looser print (CH10's `[{UAC}]`); RPI^I04 is a declared shared trigger (Table
  0354 maps it to RPI_I01 as well as the printed RPI_I04).
- The structure extractor reads a header row that repeats the caption in place of "Segments"
  (v2.7.1 CH07 OSM^R26) and a group mark whose name wraps onto the begin/end line; 13 v2.7.1
  print errata are cited, and the CH08 8.4.3 exclusion is scoped to its template caption.
- Tests pin that RPI^I04 (v2.5.1, v2.6, v2.7.1, v2.8.2) and v2.5.1 ADT^A12 are ambiguous
  without MSH-9.3 and resolve cleanly with it.

### Added — P8b-11: HL7 v2.8.2 message structures complete

- With `messageStructureSeverity` set, every v2.8.2 message structure is now checked: 185
  structures extracted from the chapter prints (32 matched exactly), and v2.8.2 is marked
  complete; a 2.8 message is checked against them (`Version.v2_8` reads through the v2.8.2
  grammar). An MSH-9.3 that names no v2.8.2 structure (`ADT^A04^ADT_A04`) is now
  `messageStructureMismatch` on v2.8.2 and 2.8 instead of info.
- 58 v2.8.2 structures are registered as not modelled, each with its reason (register section
  E): four CH12 `< OBR | Hxx etc. >` structures, four CH05 query templates, UDM_Q05 (its URD
  and URS are not defined in v2.8.2), QBP_Q13 (its CH05 5.4.2 reference gives only a query
  profile's grammar, P8b-final), RDR_RDR (no normative print) and the 47
  Table 0354 rows marked Deprecated. Every Table 0354 v2.8.2 row is modelled or registered.
- ACK takes its looser print (CH10's `[{UAC}]`); ORL^O22, O34, O36 and O40 are declared
  shared triggers (each printed for a patient-required and a patient-optional structure);
  QBP^Q31, which the CH04A query profile declares, is a registered QBP_Q11 trigger.
- A structure now accepts every trigger Table 0354 of its version maps to it, as well as the
  triggers its captions print: v2.8.2 `MFK^M03^MFK_M01` (M03 withdrawn in CH08 8.8.2, still
  mapped by the table) is matched instead of a mismatch. RPI^I04 (v2.5.1, v2.6, v2.8.2) and
  ADT^A12 (v2.5.1) become declared shared triggers, ambiguous without MSH-9.3.
- v2.6 RSP_K21 is now modelled as the union of its two incomparable prints (a new cited
  `unionPrints` override: aligned by name, the lesser minimum and greater maximum, an element
  in one print only optional).
- The structure extractor reads the v2.7.1 and v2.8.2 layouts more fully: a caption with a
  space before its colon (`ACK^R01^ACK :`, so ORU_R01 and ORU_R30 no longer run on into the
  acknowledgment), a caption title wrapped before the Segments row, a `Segments Descriptions`
  header, prose after a table that opens with a segment ID, and indented section headings
  (captions now cite their own section).

### Added — P8b-10: HL7 v2.6 message structures complete

- With `messageStructureSeverity` set, every v2.6 message structure is now checked: 187
  structures extracted from the chapter prints (23 matched exactly), and v2.6 is marked
  complete. An MSH-9.3 that names no v2.6 structure (`ADT^A04^ADT_A04`) is now
  `messageStructureMismatch` on v2.6 instead of info.
- 23 v2.6 structures are registered as not modelled (20 since P8b-11 and the P8b-13 fix round; 190 modelled), each with its reason (register section
  E): eight CH12 `< OBR | etc. >` structures, eight query and master-file templates, SUR_P09,
  RSP_K21 (its K21 and K22 prints are incomparable) and five Table 0354 rows with no printed
  syntax.
- Looser prints committed for ACK (CH10's `[{UAC}]`), ADT_A30, ADT_A43, MFK_M01, QRY_PC4 and
  RDE_O11; v2.6 MFR^M04 to M07 are declared shared triggers.
- On a complete version a locally defined message (a Z message type, trigger or structure ID
  whose trigger the version prints under no structure) is not modelled, never a mismatch.
- `MFK^M14^MFK_M01` is now read on v2.5.1 and v2.6 (the CH08 8.4.3 exclusion is scoped to the
  `MFN_Znn` template caption).
- The structure extractor reads bracketless named groups and no-bar named `< ... >` groups as
  required groups, supports a cited `syntax-cell` erratum and caption-scoped exclusions, and
  reads a table whose MSH row sits left of its caption.

### Added — P8b-9: HL7 v2.5.1 message structures complete

- With `messageStructureSeverity` set, every v2.5.1 message structure is now checked: 172
  structures extracted from the chapter prints (21 matched exactly), and v2.5.1 is marked
  complete. An MSH-9.3 that names no v2.5.1 structure (`ADT^A04^ADT_A04`) is now
  `messageStructureMismatch` on v2.5.1 instead of info.
- 31 v2.5.1 structures are registered as not modelled (30 since the P8b-13 fix round; 173 modelled), each with its reason (register section
  E): eight CH12 structures whose order detail is the unenumerated `< OBR | etc. >`, eight
  query and master-file templates, SUR_P09 (a non-segment `ED` row) and 14 Table 0354 rows with
  no printed syntax. A message naming one draws
  `messageStructureNotModelled` (info) with the reason, never a mismatch.
- A structure ID printed twice with different syntax takes the looser print, cited to both
  (`primaryPrints` override): RSP_K21 from its K22 print (repeating QUERY_RESPONSE, QRI optional)
  and RDE_O11 from its O25 print (OBX optional in OBSERVATION); the stricter prints are not
  checked (register section E).
- A trigger printed under two structures (v2.5.1 MFR^M04 to M07) is reported as ambiguous when
  MSH-9.3 is empty; the codegen accepts such a trigger only when it is declared.
- The structure extractor reads wrapped captions, comma-and-space event lists and indented
  page-break repeats, never reads a query/response grid row as a caption, and supports a
  cited `group-close` erratum (v2.5.1 MDM_T02).

### Added — P8b-7: guards over every committed structure; compiled-matcher cache

- A default-on test checks every committed structure of every version: the generated
  exact-match flag equals a fresh lint; the matcher the flag selects agrees with the
  reference recogniser on 200 seeded derived and mutated sequences, with both accepted and
  rejected ones; MSH is the first, required element; every segment is in the version's
  segment grammar or is ADD; DSC, if present, is only the last top-level element.
  `STRUCTURE_PROPERTY_FULL` runs it at 2,000 derivations per structure. A structure added by
  a version task that breaks any of these fails the suite.
- The Validator compiles each structure's matcher once and reuses it for every message
  (internal `StructureMatcherCache`, keyed by version and structure ID); the one-pass matcher
  now computes its FIRST sets once per structure instead of while matching. 1,000 messages
  against one lint-failing structure compile one automaton. No public API change; the
  validation digest is byte-identical with the option off and at `.warning`.
- The env-gated corpus tests read extractor dumps with the codegen's acceptance rules (a test
  feeds them every structure-file case of `scripts/check-structure-codegen.sh`), fail on a
  missing or empty version directory, require a minimum sequence count per structure, and
  record the default guards' verdict per structure.
- ADR-019 amendment (P8b-7).

### Changed — P8b-12: exact matching for structures that fail the determinism lint

- With `ValidationOptions.messageStructureSeverity` set, a structure that fails the ADR-019
  determinism lint is now matched exactly instead of raising `messageStructureNotModelled`
  (owner decision G15). It reports at most one finding, at the furthest segment any parse
  reached (`messageStructureSegmentUnexpected` there, or `messageStructureSegmentMissing` at
  the end of the message naming the first segment of the shortest completion), and no group
  spans. No committed structure fails the lint today, so output is unchanged (validation
  digest byte-identical with the option off and at `.warning`).
- The codegen lints every structure it emits and renders an internal `requiresExactMatch`
  flag into the generated table; the Validator no longer lints a message. A test re-lints
  every generated structure against the flag, and `scripts/check-structure-codegen.sh` gains
  eight flag cases. No public API change.
- Internal `ExactStructureMatcher`: memoised matching over (element path, position) on an
  automaton compiled from the structure; memory bounded by the structure's state count,
  time linear in the message length. Proved against the reference recogniser on every
  synthetic shape (exhaustive) and, env-gated, on the 44 real structures the P8b-3b run
  found the one-pass matcher wrong on (0 disagreements over 132,000 sequences).
- ADR-019 amendment (ceiling 1 replaced), register section E, Validation.md and the
  `messageStructureNotModelled` DocC updated.

### Added — P8b-6: the choice element in the structure model, matcher and lint

- `StructureElement.choice(_:min:max:alternatives:)`: the print's `< A | B >` (from v2.4),
  named from v2.7.1 on, unnamed (`nil`) before. Each occurrence takes exactly one
  alternative. A new case of an open enum (ADR-014): a `switch` outside the package needs
  `@unknown default`.
- `StructureElement.children` (a group's elements, a choice's alternatives, none for a
  segment) and `StructureElement.segmentIDs` (every segment ID at any depth): a walker that
  recurses through them never skips the segments inside a choice. Pinned in
  `SignatureCompatibilityTests`.
- Model: FIRST of a choice is the union of its alternatives' FIRST sets; a choice is
  nullable when its minimum is 0 or any alternative is nullable; its head segment is the
  first alternative's.
- Matcher: a choice occurrence takes the alternative whose FIRST set holds the current
  segment. A named choice opens a group span per occurrence; an unnamed one opens none. A
  required choice with no alternative present is missing its first alternative's head; a
  second alternative past the choice's maximum exceeds it.
- Lint: two alternatives whose FIRST sets overlap are a conflict, and so is a nullable
  alternative (the one-pass matcher does not decide how an empty occurrence was taken);
  otherwise a choice is checked against its FOLLOW like any element, and each alternative
  against the choice's follow set and, when the choice repeats, its re-entry.
- Codegen: the JSON keys `choice` (a name, or `null`), `nameSource` (named choices only),
  `min`, `max` and `alternatives` (at least two); 14 new self-check cases.
- No committed structure uses a choice, so the generated tables and every default output
  are unchanged.

### Changed — P8b-6: the extractor reads choices

- `scripts/extract-message-structures.py` reads `< A | B >` inline, one alternative per row,
  token per row, and named (`--- NAME begin` on the `<` row, v2.7.1 on); `ChoiceNotation` no
  longer skips a structure. A choice of placeholder alternatives (`< OBR | etc. >`, v2.5.1
  CH12) and `...` rows are skipped as `placeholder (G6)`; the summary line counts them and the
  parsed structures that carry a choice.
- `scripts/read-v2xml-bundles.py`: a printed choice is compared with the bundle's choice group
  (`CHOICE` when unnamed); a choice against a sequence is a `bundle-differs` row.
- An alternative of several elements (CH02's "choice of segment groups") is an unnamed group,
  named by the usual rule; a `< >` with no `|` (v2.8.2 CH16 `< QPD RCP >`) is skipped pending a
  ruling: the print reads as a sequence, the HL7 v2.xml bundle as a choice of each member.
- Seven new extractor self-checks (the four layouts, choices of segment groups, malformed
  choices, the bundle cross-check).
- v2.5.1: 166 structures parse (163 before); ORM_O01, ORR_O02 and OSR_Q06 carry a choice and
  pass the lint; the three pilots still reproduce byte for byte. v2.8.2: five structures parse
  with named choices and pass the lint; eleven print a `< >` with no `|`.

### Changed — P8b-3b: CH02B guard, triggerFolds stale guard, ACK on v2.3 and v2.3.1, v2.7.1 ORU_R01

- A Conformance-chapter (CH02B, sections 2.B.x) print is never a structure's primary print; a
  structure printed only there is an error (exclude it, ruling G7). The v2.7.1 and v2.8.2 CH02B
  section 2.B.8 `ADT^A01^ADT_A01` profile examples are printed in the caret form, which those
  versions' caption reader does not take, so they are not read and need no exclusion (an
  exclusion would be stale); the guard covers them should the reader widen.
- A `triggerFolds` entry that matches no caption is an error on a full read, and one whose
  primary matches no normative print is an error there too.
- v2.3 and v2.3.1: cited `triggerFolds` entries fold every ACK caption into structure `ACK`
  (`ACK^*`) through CH02 section 2.13.1, which prints the general acknowledgment under the code
  alone; Table 0354 has no ACK row. ACK now parses on both (76 and 71 captions).
- v2.7.1 `ORU_R01`: a cited group-mark erratum reads the printed `SPECIMEN OBSERVATION` marks
  as `SPECIMEN_OBSERVATION` (the v2.8.2 print's and bundle's name); the structure parses. The
  v2.7.1 bundle names that group `PATIENT_OBSERVATION` and is reported as `bundle-differs`.
- Two new extractor self-checks (39 in all). No structure JSON added; the pilots reproduce.

### Added — P8b-3b: per-version lint and recogniser run

- `extract-message-structures.py --dump DIR` writes every parsed structure of every version
  to `DIR/v<ver>/` (refused under `Resources/`), so the lint can run without committing JSON.
- `StructureLintCorpusTests` (env-gated by `STRUCTURE_LINT_CORPUS`, like the matcher corpus
  test) decodes each dumped structure, runs the ADR-019 determinism lint, classes each
  failure's shape, compares the one-pass matcher with the backtracking reference recogniser on
  the property test's bounded sequences, and records DSC placement; one TSV per version.
- The property test's sequence generator bounds a derivation at 16 segments or the shortest
  derivation plus 8, whichever is longer, and stops after 200,000 attempts, so the largest
  printed structures finish; neither bound binds on the pilots.
- The extractor reports an empty print, or rows that run on into the next table (a second
  top-level MSH), as unreadable instead of a parsed structure (17 such structures across
  v2.4 to v2.8.2; self-check 40).

### Changed — P8b-3a: the structure extractor reads every version

- `scripts/extract-message-structures.py` reads all seven versions' caption forms (v2.3 code
  alone with the event in the section title; v2.3.1 `CODE^EVT` through Table 0354; v2.4 to v2.6
  `CODE^EVT^STRUCT`; v2.7.1 and v2.8.2 `CODE^EVT^STRUCT: title`), event ranges, page-break
  repeats, and footnote furniture inside syntax tables.
- Primary-print rule: the defining caption's print is primary; other prints of the structure
  are compared (`duplicate-differs`). 107 cited exclusions (ruling G7: profile examples, query
  grammars, Z-events); 93 cited errata (group-mark typos, Table 0354 rows, one caption);
  `sharedTriggers` declared for v2.3.1 `ORM^O01`, `ORR^O02` and v2.8.2 `ORL^O22/O34/O36/O40`;
  `triggerFolds` for ACK on v2.4 to v2.8.2. Stale exclusions and errata are errors.
- `--report` writes per-version rows (parsed, skipped by reason, duplicates, Table 0354
  reconciliation both ways, shared triggers, bundle-differs). No structure JSON added.

### Added — P8b-2b: v2.xml bundle reader and group-name resolution

- `scripts/read-v2xml-bundles.py` (imported by the structure extractor) reads the HL7 v2.xml
  schema bundles under the gitignored `docs/XML-schemas` (v2.4, v2.5.1, v2.6, v2.7.1, v2.8.2):
  per `<STRUCTURE>.xsd`, the sequence and choice content, element refs with
  minOccurs/maxOccurs, and the `STRUCT.GROUP.CONTENT` group names. No bundle file or text is
  committed (ruling D4).
- An unnamed printed group takes the bundle group with the same parent path, first segment and
  member segment set, never a position (`nameSource: v2xml`). v2.3 and v2.3.1 have no bundle:
  their names are derived through the v2.4 bundle on first segment and member set within the
  same structure ID, or across the v2.4 structures of the same message code where the ID
  differs only by trigger, citing both IDs (`v2xml-v2.4`, ruling D2). Otherwise an
  `overrides.json` entry (`override`), else `<FIRSTSEG>_GROUP` numbered on a clash
  (`synthesised`), each a `no-bundle-name` report row. An override that a bundle name shadows is
  an error.
- Every non-printed name is cited in the structure citation (`NAME (HL7-xml v2.5.1/ORU_R01.xsd,
  ORU_R01.VISIT.CONTENT)`); the extractor and `StructureCodegen` accept the five `nameSource`
  values and reject a non-printed name the citation does not cite, `v2xml-v2.4` outside v2.3 and
  v2.3.1, and `v2xml` on them (`scripts/check-structure-codegen.sh`, six new cases).
- Report-only cross-check (ruling D3): `bundle-differs` rows where the bundle's member lists or
  bounds disagree with the print, and for an unreadable bundle schema (v2.5.1 `ORL_O34.xsd`
  nests `SPECIMEN` inside itself). Per-version name line: v2.4 162 v2xml, 6 synthesised, 14
  bundle-differs; v2.5.1 8 v2xml, 3 bundle-differs; v2.6 7 v2xml, 6 bundle-differs.
- `scripts/check-audit-schemas.py`: the bundle map joins the version-map agreement check, with
  the explicit derived-through-v2.4 exception for 2.3 and 2.3.1.

### Changed — P8b-2b: the ORU_R01 pilot names come from the v2.5.1 bundle

- The five `overrides.json` groupNames for v2.5.1 ORU_R01 are gone; VISIT, ORDER_OBSERVATION,
  TIMING_QTY, OBSERVATION and SPECIMEN are `nameSource: v2xml`, cited to
  `HL7-xml v2.5.1/ORU_R01.xsd`. Only `nameSource` and the citation text changed; the structure
  data and the generated table (citation only) are otherwise identical. Without a bundle the
  extractor no longer skips a structure with an unnamed group: it synthesises the name and
  reports the miss.

### Added — P8b-2a: message-structure extractor core; overrides.json; the pilot golden

- `scripts/extract-message-structures.py` reads the abstract message syntax tables printed
  under each `CODE^EVENT^STRUCTURE` caption (the v2.4 to v2.6 caption form; the other eras are
  named in `ERAS_PENDING` for P8b-3) and writes `Resources/structures/v<ver>/*.json` in the
  pilot's exact layout (ADR-019 Option C step 1). `--check` compares with the committed files,
  `--write` is idempotent, `--report` writes a per-structure TSV, and every run prints captions
  found, structures parsed and structures skipped by reason (choice, unnamed group,
  unreadable). Nesting comes from bracket balance; a structure printing choice notation is
  reported and skipped until P8b-6. It reproduces the three v2.5.1 pilot files byte for byte
  (v2.5.1: 401 captions, 2 excluded, 173 structures, 141 parsed, 32 skipped).
- `Resources/structures/overrides.json`: the five ORU_R01 group names the v2.5.1 print leaves
  unnamed (VISIT, ORDER_OBSERVATION, TIMING_QTY, OBSERVATION, SPECIMEN), each cited; the
  pilots' citation notes; the ACK trigger fold (`ACK^*`, CH02 section 2.14.1); and one
  exclusion (v2.5.1 CH05 section 5.7.3.1, a conformance-statement example that prints
  ORU^R01, ruling G7).
- `scripts/check-extract-message-structures.py` (CI, fixture-safety job): golden checks on
  print excerpts for ACK, ADT_A01 and ORU_R01, plus synthetic cases (nested and
  optional-repeating groups, `{[X]}`, `[PV2]]`, a page break inside a table, a wrapped
  caption, nested printed names, an unnamed group, a skipped choice, an excluded section,
  override validation).
- The codegen accepts `overrides.json` and a `profiles/` directory under
  `Resources/structures` (4 new cases in `scripts/check-structure-codegen.sh`, now 22);
  `check-audit-schemas.py` adds the extractor's version map.

### Fixed — P8b-2a: ORU_R01 pilot citation pages

- The golden found the v2.5.1 ORU_R01 citation gave pp 7-12 to 7-13; the table is printed on
  pp 7-13 to 7-14 (the section heading is on p 7-12). Corrected to the caption-to-last-row
  rule the other pilots already follow. Structure data and validation output are unchanged.

### Changed — P8b-1: generated structure version switch, completeness flag and codegen self-check

- The version-to-table switch for message structures is generated from
  `Resources/structures/completeness.json` into
  `Sources/HL7v2Kit/Structures/Generated/MessageStructureTable+Versions.swift`, together with
  the set of complete versions (ADR-019). All seven grammar versions are listed and none is
  complete; `2.7` and `2.8` read the v2.7.1 and v2.8.2 entries through `grammarVersion`.
- Lookup rule 1's complete-version branch is implemented: once a version is complete, an
  MSH-9.3 naming no structure of that version is a `messageStructureMismatch` rather than
  `messageStructureNotModelled`. No version is complete, so output is unchanged; the
  validation digest is byte-identical with the structure check off and at `.warning`.
- `scripts/check-structure-codegen.sh` (CI, codegen-drift job) proves the codegen rejects
  bad structure and completeness input (17 cases) and that a clean run reproduces the
  committed generated files; `check-audit-schemas.py` asserts the completeness file names
  every modelled version.
- A valid-corpus fixture that fails to parse now fails `FixtureStructureConformanceTests`
  instead of being skipped. Public API unchanged.

### Fixed — P8b-5: synthetic fixtures conform to their message structures

- Nine v2.5.1 ADT fixtures were not valid against ADT_A01 (v2.5.1 Chapter 3, section 3.3.1),
  which the message-structure check (ADR-019) reported at `.error` as 12 of 15 corpus findings.
  All nine gain an `EVN` after MSH (EVN-1, B in v2.5.1, left empty; EVN-2 repeats MSH-7);
  `edge_empty_fields` and `edge_escape_sequences_in_name` move their top-level NTE narrative,
  escape sequences unchanged, into an `OBX` (FT), which ADT_A01 defines; and
  `edge_minimal_pid_phone_only` gains a minimal PV1. `msh_with_z_only` (MSH plus one
  Z-segment) is structurally non-conformant by design and is marked as such. Every fixture
  stays synthetic and the PHI scan passes. The default validation digest is byte-identical;
  with the structure check on, only the 12 corrected findings disappear.
- New always-on `FixtureStructureConformanceTests`: every parseable valid-corpus fixture is
  validated with `messageStructureSeverity = .error` and must raise no structure finding
  (`messageStructureNotModelled` aside), except the fixtures listed in its
  `deliberatelyNonConformant` set, which must still raise one. The env-gated
  `StructureMatcherCorpusTests` stays as the measurement tool for the spec examples.
- `.gitignore` gains `docs/XML-schemas` (no trailing slash, so a worktree symlink is ignored
  too): the HL7 v2.xml bundles are licensed content and are never committed.

### Changed — P10-8: the recipient-rule citation names the message's own version

- `extraComponentsInPrimitiveField` and `extraComponentsInCompositeField` messages cited
  "v2.5.1 and v2.8.2 section 2.6.2 a" whatever version validated the message. They now cite
  the grammar version's own section for the rule "ignore segments, fields, components,
  subcomponents, and extra repetitions of a field that are present but were not expected":
  v2.3 and v2.3.1 section 2.10 and v2.4 section 2.11 (receiving rule a), v2.5.1, v2.6, v2.7.1
  and v2.8.2 section 2.6.2 a (a `2.7` message cites v2.7.1). Only the message text changes:
  codes, severities and locations are unchanged.

### Documentation — P10-8: v2.7.1 close-out

- `docs/design/v2_7_1-spec-audit.md`: what was extracted, the counts, every ruling and the
  shipped-data defects fixed along the way. ADR-018: the original lines describing 2.7 and
  2.7.1 as absent or scheduled are marked superseded, and a current version table follows the
  amendments. ADR-020: outcome note (no struct base moved). Limitations register sections A,
  C and E name v2.7.1. Conditional-completeness audit: the v2.7.1 totals are broken down and
  two stale intake headings reworded. `FieldLengthRule` cites the v2.7.1 truncation marks
  (CH02 2.5.5.2 p. 11, 2.5.5.3 p. 12). The open-ended NA array (v2.4 and v2.7.1) is pinned by
  a test.

### Changed — P10-7: RCP-4 and ROL-1 rules on the versions that print v2.7.1's text

- RCP-4 is prohibited (warning) when RCP-1 is not `D` on v2.4, v2.5.1, v2.6 and v2.8.2, as on
  v2.7.1: each prints "This field is only valued when RCP-1-Query priority contains the value
  D (Deferred)" (CH05; v2.3 and v2.3.1 define no RCP). Default output gains four warnings on
  the spec examples: the v2.4 and v2.5.1 CH03 QBP^Q23/Q24 examples print "RCP||I|SEC|0614",
  one field to the right.
- ROL-1 is required in the Patient Care and Personnel Management messages on v2.5.1, v2.6 and
  v2.8.2, as on v2.7.1 (CH15 15.4.7.1); v2.8.2 leaves out PRR, PPV, PTR and PPT, removed as of
  v2.8. v2.4 prints a different sentence and stays bare; v2.3 and v2.3.1 print ROL-1 `R`. No
  spec example changes.

### Added — P10-7: v2.7.1 spec examples in the harness

- The 222 v2.7.1 example messages run through the validator; every error line on a v2.7.1
  example, and on every example declaring MSH-12 `2.7`, is claimed by a registry entry cited
  to the v2.7.1 print (244 entries, 0 mismatched). Each is an example defect or the declared
  substitution; none is a misfire.
- The ORC-8 / OBR-54 pair check is pinned end to end for a literal MSH-12 `2.7` and `2.8`.

### Fixed — P10-7: the v2.7.1 text layer's printed hyphen

- The v2.7.1 PDFs encode a printed hyphen as U+2010, so extracted example values such as
  time-zone offsets carried a non-ASCII character and raised 94 false format warnings.
  `extract-example-messages.py` maps U+2010 to "-", with a self-check. Extraction only; the
  shipped resources are unchanged.

### Changed — P10-6: MSH-12 `2.7` validated against v2.7.1 (owner decision G11)

- `Version.v2_7` (`"2.7"`), additive. A message whose MSH-12 declares `2.7` no longer
  raises `versionNotRecognised` against the v2.5.1 fallback, and `ParserOptions.strict`
  accepts it: it is validated against the v2.7.1 grammar, code tables and datatype grammar
  with one `versionGrammarSubstituted(declared: .v2_7, validatedAs: .v2_7_1)` info issue at
  MSH-12, exactly as `2.8` is validated against v2.8.2 (ADR-018 amendment). The registries
  stay version-literal: `.v2_7` owns no tables or grammar.
- The ORC/OBR paired-field version sets are read through `grammarVersion`. This is a tidy-up
  with no change in output: `validate(_:)` already re-declares the message under its grammar
  version before any version-keyed check, so a `2.8` message already got the ORC-8 / OBR-54
  parent-order check of v2.8.2, and a `2.7` message gets v2.7.1's. (Corrected in P10-8: this
  entry first said the check had read the declared version and that `2.8` output changed;
  P10-7 found otherwise and pins the behaviour end to end.)

### Added — P10-6: `Version.v2_7_1`, HL7 v2.7.1 validated against its own grammar

- `Version.v2_7_1` (`"2.7.1"`), additive on the open enum (ADR-014). Every per-version
  dispatch reaches the v2.7.1 resources: `HL7TableRegistry.tables(for:)`,
  `DataTypeGrammarTable.grammars(for:)` and `fieldGrammars(for:)` (empty: v2.7.1 prints a
  component table for every composite), and the Validator's segment grammar table.
- v2.7.1 sits with v2.8.2 on every era rule, each verified against the v2.7.1 print: LEN is
  a normative length beside C.LEN (CH02 2.5.3.2, 2.5.3.3, 2.5.5.0, 2.5.5.3); no 65536 or
  99999 length symbols (CH02 2.5.5); SI bounded to 0 to 9999 (CH02A 2.A.69); SNM a primitive
  and TS withdrawn (CH02A 2.A.71, 2.A.78).
- The ORC-8 / OBR-54 parent-order pair applies on v2.7.1 (CH04 4.5.3.54; 4.5.1.8 prints
  "OBR-??", resolved by 4.5.3.54).

### Changed — P10-6: default output for messages that declare 2.7.1

- A message whose MSH-12 declares `2.7.1` no longer falls back to v2.5.1 with
  `versionNotRecognised`, and `ParserOptions.strict` no longer throws `unsupportedVersion`
  for it. It is validated against the v2.7.1 grammar. None of the spec example messages
  declares `2.7.1`, so the validation digest is unchanged.

### Changed — P10-5b intake: EQU-3 required in the ESU message on v2.4 to v2.8.2

- CH13 13.4.1.3 prints "The Equipment State is required in the ESU message and is optional
  otherwise" on v2.4, v2.5.1, v2.6 and v2.8.2 as on v2.7.1; all four now carry
  `messageCode = ESU` (v2.3 and v2.3.1 define no EQU). Every printed ESU example values
  EQU-3, so no spec example output changes.

### Added — P10-5a, P10-5b: v2.7.1 conditional fields

- Every one of the 177 fields v2.7.1 prints `C` was read against its own v2.7.1 definition:
  112 carry a rule (107 a `condition`, 5 a prohibition only) and 65 stay bare, each with its
  quote and reason in `docs/design/conditional-completeness-audit.md`. CSR-8, MFI-6 and
  ROL-4 are printed `R` and modelled `C` with an optionality citation (P4-30).
- Readings that differ from v2.8.2, each from the v2.7.1 text: ORC-2/3 and OBR-2/3 take the
  v2.6 forms (no Send Number exception); PRT-5/8/9/10 have no PRT-22 leg; PID-35 and PID-36
  take v2.6's "Conditionality Rule" sentences; RCP-4, ROL-1 and EQU-3 get rules v2.6 and
  v2.8.2 then left bare (applied there in later intakes). The `messageCode not in (OUL ...)`
  ORC/OBR gates are kept (register section D).
- No output changed at the time: v2.7.1 was not dispatched until P10-6.

### Fixed — P10-4d: v2.4 NA datatype

- v2.4 types SAC-11 and SAC-14 NA but shipped no NA grammar. CH02 2.9.27 defers to CH07
  7.14.1.1, which prints "<value1> ^ <value2> ^ <value3> ^ <value4> ^ ...";
  `Resources/datatypes/v2.4/NA.json` holds the four printed values, untyped as printed. NA is
  an open-ended array on every version (the print ends in an ellipsis), so the four entries
  are not a maximum and NA is never width-checked. No output changes.

### Fixed — P10-4d: v2.4 table 0131

- v2.4 binds User-defined Table 0131 (Contact Role) on NK1-7 and CTD-1, and CH03 3.4.5.7
  prints it with the single row "No suggested values", but Appendix A omits it. It is now
  created, empty and user-defined (v2.4: 409 tables). No output changes.

### Fixed — P10-4d: v2.5.1 MFA-5, MFE-4 and OBX-5 "Varies"

- The segment-table extractor read a data-type cell that wraps its last letters onto the
  next line as "Varie" (v2.5.1 CH08 8.5.2 and 8.5.3) and "varie" (OBX-5). It now completes the
  cell from the wrapped fragment. The schemas already recorded `Varies`, so only the
  extractor and a now-unneeded audit whitelist entry change.

### Fixed — P10-4d: v2.6 withdrawn fields carry the printed data type; the v2.5.1 MSA-5 exception

- Eleven v2.6 withdrawn (W) fields carried a data type the v2.6 attribute tables leave blank
  (DG1-2, DG1-4, DG1-7 to DG1-14, MSA-5). They are now untyped, as printed. A populated one
  raises only the withdrawn-field warning; on the spec examples validated as v2.6, 8
  `extraComponentsInPrimitiveField` issues on MSA-5 no longer fire. No accessor changes.
- v2.5.1 MSA-5 keeps its ID type as the one registered exception: the print's DT cell is
  blank, but the released `MSA.delayedAcknowledgmentType` is typed from it (ADR-014).
  Every version from v2.5.1 up is now held to the rule by `audit-schemas.py`.

### Fixed — P10-4d: v2.6 ITM fields 7 to 29

- The v2.6 ITM schema stopped at ITM-6: the segment-table extractor ended the table at a
  page-foot footnote (fixed in P10-4c). ITM-7 to ITM-29 are added from the v2.6 CH17
  section 17.4.2 attribute table (pp. 9 to 10), so v2.6 validates them.
- Added `ITM.itemNaturalAccountCodeAsCWE`: v2.6 prints ITM-19 IS, so the unreleased
  `itemNaturalAccountCode` is now `String?` and the v2.7.1 / v2.8.2 CWE reading has its
  own accessor. The released v3.13.0 surface is unchanged.

### Fixed — P10-4d: v2.8.2 withdrawn fields carry the printed data type

- 30 v2.8.2 withdrawn (W) fields carried a data type the v2.8.2 attribute tables leave blank
  (AL1-6, DG1-2/4/7 to 14, ERR-1, EVN-1, MSA-3/5/6, OBR-5/6/14/15/27, ORC-7, PD1-4,
  PID-2/4/9/12/19/20/28). They are now untyped, as printed; only UB1-1 keeps a type (SI,
  CH06 section 6.5.10, p. 124). A populated one raises only the withdrawn-field warning;
  on the v2.8.2 spec examples 64 type-keyed issues on PID-2, PID-4 and MSA-5 no longer fire.
  `audit-schemas.py` now holds v2.8.2 to the rule as well as v2.7.1.

### Added — P10-4a to P10-4c: v2.7.1 segment schemas

- `Resources/schemas/v2.7.1`: 170 segments and 2,519 fields from Chapters 2 to 17, each
  segment from its defining attribute table, cross-checked by an independent parse and read
  on the page wherever it differs from v2.8.2. v2.7.1 adds IAR, PAC, PRT and SHP to v2.6's
  set and lacks QRD, QRF, URD and URS; it lacks ten v2.8.2 segments and has none v2.8.2
  lacks.
- Withdrawn (`W`) fields carry exactly the data type their attribute table prints: of
  v2.7.1's 77, only UB1-1 is typed (SI). Blank OPT cells (87 fields) and table openness
  (14 fields) are cited from the v2.7.1 print.
- Extractor fixes, each with a self-check, that also apply to every version: prose bleeding
  into the last row's element name, and a page-foot footnote inside a table read as a row
  (it gave v2.7.1 ITM a phantom field and had cut the v2.6 ITM table short).
- `audit-schemas.py` checks that every field's data type exists on its version. Generated
  DocC version lists name v2.7.1; no accessor is added, removed or retyped.

### Added — P10-2: v2.7.1 datatype component grammar

- `Resources/datatypes/v2.7.1`: 72 composites, 469 components, 151 bound to a table, 72
  printed `C` (23 conditions and 30 conformance conditions re-cited to the identical v2.7.1
  sentences; 19 bare, registered in section D). Against v2.8.2: LA1 and LA2 added, OG
  absent, PRL.2 ST, XON.4 and XON.5 printed `O`.
- The datatype and example extractors treat v2.7.1's second page-footer line as furniture,
  which had truncated 14 composite tables.

### Fixed — P10-1 fix round: shipped v2.8.2 and v2.6 table data

- v2.8.2 Tables 0359 (Diagnosis Priority) and 0418 (Procedure Priority) stored the printed
  ellipsis row (U+2026) as a code and were closed. They now hold 0, 1 and 2 and are open:
  Chapter 6 DG1-15 and PR1-14 say "Values 2-99 convey ranked secondary" diagnoses or
  procedures. The extractor reads the Unicode ellipsis as the bare "..." row in both layouts.
- v2.8.2 Table 0544 (Container Condition) is open, as Chapter 7 SPM-28, SHP-9 and PAC-6
  cite it "for suggested values"; the wrapped fragment `temperature` is no longer a code and
  six descriptions are restored as printed.
- v2.8.2 wrapped prose stored as codes is dropped: `contractors.` (Tables 0088, 0343) and
  `codes` (Table 0396).
- The Chapter 2C layout skipped every line containing ".." as a table-of-contents line,
  losing rows that print "..."; only a dotted leader is skipped now. v2.8.2 Tables 0093 and
  0466 regain their ellipsis row and are open; Table 0141 regains its range rows.
- Table 0141 (Military Rank/Grade) range rows `E1 ... E9`, `O1 ... O9` (`O1 ... O10` on
  v2.3.1 and v2.4) and `W1 ... W4` were literal codes on v2.3.1 to v2.6 and missing on v2.8.2.
  They are now pattern rows matching exactly the codes they name, on every version that prints
  them.
- See Migration.md for the visible `HL7TableRegistry` changes; validation output is unchanged.

### Added — P10-1: v2.7.1 code tables

- `Resources/tables/v2.7.1`: 535 tables (174 HL7, 361 user-defined), 5,155 entries and four
  pattern rows (0141, 0203), 144 tables with no values; Appendix A is the source, plus
  Chapter 2C's 0916. 54 tables carry a cited override: the Appendix A versus Chapter 2C
  cross-check (13 code-set and 13 kind differences), the readings every version carries,
  and the openness of ellipsis and no-value tables; 0070 and 0048 are recorded as absent.
  Readings of 0492, 0125 and 0104 were settled in the review round.
- `extract-code-tables.swift` reads Appendix A's Unicode ellipsis row (U+2026) as the bare
  "..." row, which removed 141 bogus entries, with a self-check; the six existing versions
  re-extract unchanged. Self-check guards: every per-version source map names every modelled
  version, and a bare U+2026 code is flagged.

### Changed — P10-3: a released struct's union base never changes (ADR-020 amendment)

- The codegen takes a segment struct's base schema from `Resources/struct-bases.json` where
  the segment is listed there, and only otherwise from canonical v2.5.1 or the earliest
  definer (`StructBase.swift`). The list pins the 38 structs released in v3.13.0 on a base
  other than v2.5.1 (24 on v2.6, 14 on v2.8.2, including IAR, PAC, PRT and SHP), so adding
  v2.7.1 or any other earlier version cannot rename or retype a released accessor. A pin to
  a version that does not define the segment fails the run.
- `StructBasePinTests` (3 tests) fails when a generated struct's base differs from its pin
  or from v2.5.1, when a pin names no struct, or when a v3.13.0 struct is no longer
  generated: a new segment's non-v2.5.1 base is added to the list in the commit that
  introduces it. `scripts/check-struct-base-pin.py` (CI, codegen-drift job) runs the codegen
  on a scratch schema copy with a synthetic earlier PRT and shows its base and released
  declarations do not move.
- Regeneration output is unchanged; `docs/design/public-api-surface.md` states the
  guarantee.

### Changed — P8 final review: internal structure initialiser; wording and doc corrections

- `MessageStructure.init(id:version:triggers:citation:elements:)` is internal (unreleased
  API, so no compatibility break): there is no public matcher to hand a consumer-built
  structure to, and the AU overlay will add fields. The DocC of `triggers` gives the
  `"CODE^EVENT"` / `"CODE^*"` format, `version` is the printed version string, and
  `StructureElement` says a later release adds cases.
- An MSH-9.3 that differs from a modelled structure ID only by case or surrounding
  whitespace (`ADT_A01 `, `adt_a01`) is still `messageStructureNotModelled` (info, no body
  match), and its message now says so. Default output unchanged.
- Docs: README feature line, Migration.md open-enum list (`StructureElement`), ADR-019
  (internal initialiser; where the pilot differs: no overrides.json or JSON Schema file,
  lookup rule 3 not implemented, lint run per message uncached), ACK syntax citations per
  version (UAC from v2.6), the MSH-18 echo in the DocC and register rows, and a
  `Validation.md` note that batch input goes through `BatchParser` and `BatchValidator`.

### Documentation — P8-8: message-structure pilot close-out

- Permanent-limitations register section E: each row restated for what is true after
  the pilot (three v2.5.1 structures modelled, every other structure and version not
  modelled; fragments; version provenance; lint-failing structures reported as not
  modelled); still blocking, "pilot shipped PARTIAL".
- ADR-019: "pilot shipped" addendum with measured test counts; decision 9 amended for
  the MSH-18 echo; rollout step 4 records that `isComplete` switches lookup rule 1's
  unknown-ID case from not-modelled to mismatch.
- DocC `Validation.md`: a "Message structures" section; the "does not check" bullet now
  reads "partial". `Migration.md`: every P8 public member listed.
- `public-api-surface.md`: a fresh inventory, 263 public types (75 hand-written, 188
  generated segment structs), every type listed; 11 types the old tally missed and the
  `ParseError` case count (7, not 8) corrected.
- `MessageBuilder.acknowledgment` DocC: an empty original MSH-9.2 gives `ACK^^ACK`
  (pinned by a new test); MSH-18 is a builder rule; on v2.3 and v2.3.1 echoing the
  event is permitted, not mandated. `MessageStructure.accepts` pinned by function type.

### Added — P8-7: general acknowledgment builder (ADR-019 decision 9)

- `AcknowledgmentCode` (HL7 Table 0008, six cases, open enum),
  `MessageBuilder.acknowledgment(to:code:messageControlID:dateTime:)` and
  `BuilderError.acknowledgedMessageControlIDMissing`. Builds MSH and MSA in the
  original's version: MSA-2 copies the MSH-10 field, MSH-3/4 and MSH-5/6 swap, MSH-9 is
  `ACK^<event>^ACK` (`ACK^<event>` on v2.3), MSH-11, MSH-12 and a populated MSH-18 are
  echoed. No protocol logic (MSH-15/16, enhanced mode, sequence numbers): the caller
  chooses the code and adds SFT, UAC or ERR. Additive; default output unchanged.

### Added — P8-6: MSH-9 resolution cases and event-to-structure consistency

- An MSH-9.3 naming a modelled structure not printed for MSH-9.1^9.2 raises
  `messageStructureMismatch` alone, with no body match. An MSH-9.3 naming an unmodelled
  structure (`ADT^A04^ADT_A04` on v2.5.1) is `messageStructureNotModelled` until a
  version is complete; a trigger printed under two structures is not resolved and the
  info issue names both.

### Added — P8-5: message-structure validation, opt-in (ADR-019)

- `ValidationOptions.messageStructureSeverity` (`IssueSeverity?`, `nil` in every preset;
  not an init parameter) and four `IssueCode` cases:
  `messageStructureSegmentMissing(structure:segmentID:group:)`,
  `messageStructureSegmentUnexpected(structure:segmentID:)`,
  `messageStructureMismatch(declared:trigger:)` and
  `messageStructureNotModelled(structure:)` (always `.info`). The structure comes from
  MSH-9.3, or MSH-9.1^9.2 through the caption-line triggers; it applies only when MSH-12
  reads as the version validated. Z-segments, ADD and segments the version's grammar does
  not define are skipped. A fragment (MSH-14 populated, or a trailing DSC with a
  continuation pointer or where the structure defines none) is not structure-checked.
  Default output unchanged.

### Added — P8-4: structure matcher and determinism lint

- Greedy recursive-descent matcher (internal) reporting missing, unexpected and
  over-maximum segments, and the determinism lint every modelled structure must pass;
  a structure that fails it is reported as not modelled. A reference recogniser property
  test checks that the matcher and a full recogniser agree on the pilot structures and on
  every synthetic shape that passes the lint.

### Added — P8-3: message structure model, codegen and the v2.5.1 pilot

- `MessageStructure`, `StructureElement` (open enum) and `MessageStructureTable`,
  generated into `Sources/HL7v2Kit/Structures/Generated/` from `Resources/structures/`.
  Three structures: v2.5.1 `ADT_A01` (A01, A04, A08, A13), `ORU_R01` and `ACK`. The
  codegen-drift CI job covers the new generated directory.

### Documentation — P8-1 and P8-2: abstract message syntax registered; ADR-019

- P8-1: permanent-limitations register section E registers message structures,
  event-to-structure consistency and acknowledgment construction as blocking
  spec-completeness; README and DocC state the gap.
- P8-2: ADR-019 (message structure grammar) accepted under owner gate G2: hybrid source
  of truth, greedy matcher with determinism lint, ADD skipped on every version, fragments
  not structure-checked, the version rule, and a mismatch reported alone.

### Fixed — P5 final review: TQ.6 priority repeat on v2.3/v2.3.1; v2.3 QRD-11

- v2.3 and v2.3.1 section 4.4.6 let TQ.6 Priority repeat with the repeat
  delimiter (`1^Q6H^^200001011200^^S~A^^^S`), which the parser reads as a
  field repetition. On those versions a single-repeat `TQ` field (ORC-7,
  RXE-1, RXG-3, GOL-15, QRF-9, URS-9) no longer raises `cardinalityExceeded`
  for repetitions 2 to n, and no component, format, length or table check
  runs on them; repetition 1 is validated as usual. v2.4 (section 4.3.6)
  uses a space and is unchanged. A genuinely wrong second repetition there
  now goes unreported: a known limit, recorded in the limitations register.
- v2.3 QRD-11 is typed `CM`, as its section 2.24.4.11 heading and Components
  line print (`<first data code value (ST)> ^ <last data code value (ST)>`),
  not `ST` as its attribute table prints; a cited `DATATYPE_WHITELIST` entry
  records the disagreement. `A^Z` no longer raises
  `extraComponentsInPrimitiveField`; a third component raises
  `extraComponentsInCompositeField`. v2.3 now has 46 field-local grammars.

### Changed — P5-1 to P5-3: more issues may fire by default

- No API change, but default output changes, and more errors may fire:
  `valueNotInTable(table: "0472")` on v2.4 TQ.9, `valueNotInTable(table:
  "0191")` on v2.3 ED.2, `CD` and `CF` width-checked, and `TQ` checked
  against its CH4 component grammar. The width warning on a six-component
  v2.3/v2.3.1 `CE` is gone. See Migration.md.

### Fixed — P5-9: v2.3.1 datatype names without table-of-contents residue

- `DataTypeGrammar.name` for every v2.3.1 composite datatype carried leftover
  padding and a page number from `scripts/extract-datatype-prose.py` picking
  up the table-of-contents entry instead of the body heading (`"address
  2-12"`, `"timing quantity      2-52"`, 39 names in all). v2.3.1's contents
  entries print no dot leaders, so the extractor's furniture filter — which
  drops v2.3 and v2.4's dot-leadered contents lines — missed them, and the
  extractor kept the first heading match it saw rather than the last.
- Fixed at the source: the extractor now keeps the LAST match of the datatype
  heading pattern, the body heading that is actually followed by the
  datatype's definition text, discarding any earlier contents-line match
  (the same rule `extract_tq` already applied to Chapter 4's TQ numbering).
  v2.3 and v2.4 print no such duplicate match, so the fix is a no-op there.
- `audit-schemas.py --datatypes` now also rejects a datatype `name` ending in
  what looks like a page reference (`\d+-\d+$`) or containing a run of three
  or more spaces, on every version.
- Added `scripts/check-extract-datatype-prose.py` (wired into the CI
  `fixture-safety` job alongside `check-extract-example-messages.py`),
  covering the name-capture fix, `parse_components_line`, `reconcile`'s
  WARN-and-keep path, and `extract-field-components.py`'s
  `promote_misprinted_ampersands`.
- No component, datatype or table binding changed; only the 39 `name`
  strings. Confirmed by diffing every re-extracted v2.3.1 file, by a clean
  re-extraction of v2.3 and v2.4, and by a before/after diff of
  `Validator().validate(_:).issues` (all severities) over the 1233 spec
  example messages and the fixture corpus: identical.

### Fixed — P5-7: OBR-15 and OBR-32 to OBR-35 typed `CM`, not the v2.5-era names

- v2.3, v2.3.1 and v2.4 OBR-15 and OBR-32 to OBR-35 were reported as the
  v2.5-era `SPS` / `NDL` composites. Those structures differ from what the
  field actually prints (OBR-15.2 additives `TX` vs `SPS.2` `CWE`; OBR-32.1
  `CN` vs `NDL.1` `CNN`), so the typed name was misleading even though the
  field-local grammar (P5-5/P5-6) already supplied the right components. The
  schemas now print `CM`, as the attribute table does; components come only
  from the field-local grammar. (V24-C08)
- `audit-schemas.py`'s `CM` carve-out is now an enumerated set,
  `CM_REFINEMENTS` (`MSG`, `MOC`, `PRL`, `EIP`): only those four pre-v2.5
  `CM` fields may be typed with their v2.5-era name, because only their
  structure is identical to it. Every other `CM` field stays `CM`. Guarded
  by `check_cm_refinements` in `scripts/check-audit-schemas.py`.

### Fixed — P5-6: CE components checked only under an explicit HL7nnnn coding system; width-check dedupe

- Every composite-aware check (width, primitive-component, component
  code-table, value-format, conditional and required components) now
  resolves a field's grammar through one point,
  `Validator.fieldGrammar(segment:field:dataType:version:)`: a primitive
  stays primitive, else the field-local grammar (P5-5) where the field
  prints one, else the datatype-level grammar. This closes the
  component-table half of V231-C03, V23-C06 and V24-C06: a closed HL7 table
  bound to a field-local `CE`/`CWE` component (OBR-15.1 0070, OBR-15.4 0163,
  ERR-1.4 0357, SAC-6, TCC-3, IN3-20.2 0136, BLG-1.1 0100, PRA-5.3 0337) is
  now enforced, where it was silent.
- A `CE` component's closed-table check only fires when the component's own
  coding-system subcomponent (CE.3, or CE.6 for the alternate triplet
  CE.4-6, "defined analogously") explicitly names the table as `HL7nnnn`
  (case-insensitive; v2.3/v2.3.1 section 2.8.3.3, v2.4 section 2.9.3.3). An
  empty CE.3 is silent — the spec's own ERR-1 example sends `X3L` with none
  and calls it "the locally-established code" — and so is any other coding
  system, which is how OBR-15's veterinary-table allowance (v2.4 section
  7.4.1.15) is honoured. The same rule now also reaches the existing
  v2.5.1 ELD.4 (0357) type-level binding.
- v2.3.1 and v2.4 PRA-7 now has five components: the extractor reads a
  misprinted `&` as `^` when every later piece has its own "Subcomponents
  for <name>:" line.
- IS bindings and the open MSH-9 tables (0076, 0003, 0354 on v2.3.1/v2.4)
  stay unenforced.

### Added — P9: complete composite views and later-version typed accessors (ADR-020)

- `CompositeView.component(_:as:)` views a sub-composite (for example CX-4 as `HD`);
  `CompositeView.viewed(as:)` views the same field as another composite (for example
  a v2.5.1-typed `CE` as the `CWE` that v2.6+ prints); `TypedSegment.repetitions(_:)`
  returns each repetition of a field as its own `Field`. Additive (ADR-014).
- **V251-C11, V282-C10: composite views reach full spec depth.**
  - Every component that any supported version defines now has a named accessor on CX (12), XPN (15), XAD (23), XCN (25), XTN (18), PL (11), CWE (22), CNE (22) and XON (10). CE, EI, EIP, HD, MSG, PT and VID were already complete.
  - The new accessors are generated from the datatype component tables and a curated name map (`Resources/composites/composite-views.json`) into `Sources/HL7v2Kit/Composite/Generated/`. Codegen fails if any component is unnamed.
  - Withdrawn components keep an accessor (earlier versions define them); a component printed without a data type takes the type from the newest version that prints one; open arrays (MA, NA) are not composite views.
  - Hand-written accessors are unchanged, checked against v3.13.0 by `CompositeReleasedSurfaceTests`. The "commonly-populated" rationale is removed.
- **V251-C11: repeating fields.** Every repeating field (`*` or a bound, 536 in all) on the
  generated segment structs gains `<name>All`, which returns every repetition in wire order:
  - `[<View>]` for composite views;
  - `[String?]` for scalars;
  - `[Field]` for other types.

  For example, `PID.patientIdentifierListAll: [CX]`. Each passes `TypedSegment.repetitions(_:)`
  through unchanged: empty when the field is absent, one entry when it is present but empty,
  three for `A~~B`, and one entry holding `""` for an HL7 null. The singular accessor's DocC
  now says the field repeats. Codegen fails on an `…All` name that collides with another
  accessor. The v3.13.0 segment-struct surface is checked by `SegmentReleasedSurfaceTests`.
  Additive.
- **V282-C10: version-union typed accessors.** Generated segment structs keep their
  v2.5.1 base (or the earliest defining version) and add what the other supported
  versions define (510 accessors, one per element and Swift type):
  - fields past the base maximum, and positions the base reserves that a later version
    defines, with their later name and type (222; for example PID-40, ORC-32..34,
    OBR-51..54, OBX-26..30, and `OBX.observationSite` where v2.5.1 reserves OBX-20);
  - a later name for a base position only when its Swift type differs from the base
    accessor's (9; for example `OBX.interpretationCodes: CWE?` for v2.8.2 OBX-8, renamed
    from Abnormal Flags). A same-type rename is a DocC note on the base accessor;
  - `<name>As<T>` where any version prints a scalar or raw field as a composite (186;
    for example `CON.languageTranslatedToAsCWE`, and `MFA.primaryKeyValueMfaAsCE` for
    v2.3 to v2.4);
  - `<name>All` wherever any supported version repeats the element (93 more, 629 in
    all: 16 base fields that repeat only in another version, 45 later element names, 32
    `As<T>` views; for example `MRG.priorAlternateVisitIdAll`).

  DocC names the versions each accessor applies to and says that on another version's
  message it returns whatever the position holds. A kept rename says "Same element as
  ..., renamed in ..." and the base accessor points back to it; every printed name is
  listed with the accessor whose type matches that version. Composite-to-composite
  retypes (CE to CWE) point at `viewed(as:)`; 48 view accessors note the version that
  prints a scalar there. A reserved position's DocC says "No data type: reserved
  position in v2.5.1". The v3-C5 fallback pass is folded into the union pass. ADR-020
  records the rules. No existing accessor changes name or type. Additive.
- **Schema fix: v2.5.1 MFA-5 and MFE-4 data type `Varies`.** The schemas stored `Varie`,
  the attribute table's truncated cell; the field headings (CH08 8.5.2.4, 8.5.3.5) print
  `Varies`, as v2.6 and v2.8.2 store it.
- **P9 close-out (documentation).** The `TypedSegment` and `CWE` DocC state the version
  shape; the TypedSegments article gains compiled examples for the new accessors;
  Migration.md, the public-API inventory and register section H (now closed, with three
  registered residuals) describe what shipped; ADR-013 carries an addendum. A generated
  accessor that was renamed no longer states the rename twice in its DocC.
- **P9 final review: wire behaviour, names and a full surface snapshot.** Accessors are not
  version-gated: the `TypedSegment` and `CWE` DocC, Migration.md and the TypedSegments
  article now say an accessor returns `nil` only when its position is absent and otherwise
  reads what the wire holds, and generated composite DocC says so beside "Defined in". Four
  unreleased later-version names drop a stranded possessive "S" (`IN2.patientRelationshipToInsured`,
  `NK1.contactPersonTelecommunicationInformation`, `OM1.replacementProducerServiceTestObservationId`,
  `ROL.personLocation`), as do nine v2.3 to v2.4 schema rows whose names reach no accessor;
  `audit-schemas.py` now rejects a stranded "S" on any name neither released at v3.13.0 nor
  canonical-inherited. `AccessorSurfaceSnapshotTests` pins every segment and composite
  accessor (name, type, index) for equality against `Tests/Fixtures/APISurface/*-unreleased.txt`.
- **P9 final review: generator fixes.** Segment and composite codegen render every file
  before writing any, and delete a file in its output directory that the run did not
  produce. Rename notes ignore a "(deprecated)" suffix and merge versions that print the
  same name (OBR-15); a case-only difference is not a rename (IN1-17). A retype note names an existing accessor of that type before
  `viewed(as:)` (`PID.speciesCode` on v2.6: `taxonomicClassificationCode`). The redundant
  `checkAllNames` pass is gone; the union pass's name claims cover it.

### Added — P5-5: field-local component grammar for pre-v2.5 `CM` fields

- `DataTypeGrammarTable.grammar(segment:field:version:)` (additive): the
  component grammar a pre-v2.5 field defines for itself on its own printed
  Components line, read by `scripts/extract-field-components.py` into
  `Resources/datatypes/v<X>/fields/<SEG>-<N>.json`. 45 fields on v2.3, 41 on
  v2.3.1, 43 on v2.4. A table binds only to a coded component (IS, ID,
  CE/CNE/CWE), under the existing three-test evidence rule, reaching
  13/19/26 bound components across the three versions; 15 field mentions
  (IN2-28, IN2-29, v2.3 MSH-9, v2.3 IN3-11.1) stay unbound because the prose
  names two tables in one sentence or misprints the table number, and are
  recorded in the limitations register.
- The component code-table check now runs on these fields (the width check
  and the others are wired in by P5-6).

### Added — P5-2/P5-3: CD, CF, TS and TQ component grammar

- v2.3, v2.3.1 and v2.4 `CD` (6 components), `CF` (6) and `TS` (2) now have
  a component grammar, read from each datatype's printed Components /
  Format line when it has no numbered prose subsections
  (`"source": "prose-line"`); `CD` and `CF` are now width-checked and
  `CF.2`/`CF.5` follow the FT line-marker rule.
- v2.3, v2.3.1 and v2.4 `TQ` now has a component grammar (10/12/12
  components), read from the CH4 quantity/timing definition (v2.3/v2.3.1
  section 4.4, v2.4 section 4.3) rather than CH02; v2.4 TQ.9 is bound to
  Table 0472.
- `Validator.componentGrammar(_:version:)`: the single resolution point a
  composite check calls for a type with no field-local grammar. It keeps
  `TS` a primitive before consulting the table, so giving `TS` a component
  grammar does not regress the P6-7 format check, the P6-14
  primitive-component limit or the P6-15 width check.
  `checkComponentCodeTables`, `checkConditionalComponents` and
  `requiredComponents` all route through it.

### Fixed — P5-1: pre-v2.5 composites corrected from the printed Components line

- `extract-datatype-prose.py` now also reads the printed "Components:"
  line: a numbered subsection that prints no datatype yields to it, and a
  component the line names past the last numbered subsection comes from it.
- v2.3 and v2.3.1 `CE` now has six components (was three); v2.3.1 `CNE` now
  has nine (was eight). (V23-C04, V231-C07)
- Side effects, each printed by the line: `DLN.1` is `ST` on v2.3 to v2.4
  (was unset); v2.3 `ED.2` is `ID` bound to Table 0191 (was unset); v2.3
  `SN.1` is the comparator component.

### Added — P6-15: extra components on composite fields

- New `IssueCode.extraComponentsInCompositeField` (additive; the enum is open
  per ADR-014). A composite field repetition carrying a populated component
  beyond its datatype's component table on the message's version (an XPN with
  a 15th component on v2.5.1) is reported at the field. A composite component
  carrying a populated subcomponent beyond its own datatype's table (a sixth
  FN subcomponent in XPN.1, a fourth HD subcomponent in CX.4) is reported at
  that component. Before, neither was reported anywhere.
- Severity follows `ValidationOptions.extraComponentsSeverity` (`.warning` by
  default, off under `.lenient`). A recipient ignores components "present but
  were not expected" (v2.5.1 and v2.8.2 section 2.6.2 a), and "New components
  may be added at the end of a data type" (v2.5.1 section 2.8.1, v2.8.2
  section 2.8.1 h), so a value shaped by a later version may carry them.
- Silent: trailing empty components and subcomponents, escaped `\S\` / `\T\`,
  a datatype the version prints no component table for (CM on v2.3 to v2.4,
  OBX-5 `varies` with no OBX-2), and the open-ended arrays NA (its tables end
  in an ellipsis; v2.5.1 section 2.A.45 example
  `125^34^-22^-234^569^442^-212^6`) and MA ("channels within a sample are
  separated by component delimiters", v2.5.1 section 2.A.40; the v2.6 and
  v2.8.2 tables end in an ellipsis). OBX-5 takes the datatype OBX-2 names.
  Primitive fields and components keep `extraComponentsInPrimitiveField`.
- The length check is unchanged for composites: it still measures the whole
  occurrence.
- Fixtures: no new warnings. Spec examples: no change to the error report
  (149 registry entries, 0 mismatched). 43 new warnings, all print defects
  (field shifts, a TQ-shaped RXA-3, an XCN in a CE field, a four-component QIP)
  or print elisions (`...` inside ORC-9); five also depend on version
  substitution (MSH-12 elided, validated as v2.5.1).

### Changed — P6-11: OR-rule issue messages name the failing sub-rule

- The OR-rule issue message (`RequiredComponentSet`, used today only by `HD`) named every
  OR alternative even when a grouped pair was the actual failure — misleading when, for
  example, HD-1 is valued and only one of the HD-2/HD-3 pair is valued: the pair rule fired,
  not the OR, yet the message read as if HD-1 were missing too. `RequiredComponentSet.violationMessage(populatedIndices:compositeCode:)`
  now names the partially-populated group's "both or neither" rule directly in that case,
  and falls back to the OR alternatives (unchanged wording) when nothing in the field
  satisfies either side. Issue codes, severities and locations are unaffected — message text
  only, and `ValidationIssue.message` carries no stability guarantee (ADR-014).

### Fixed — P6-14: extra components on every primitive; component-level table check

- `extraComponentsInPrimitiveField` covered `ID` and `IS` fields only. It now
  covers every primitive field of the message's version, from each version's
  datatype sections: DT, FT, ID, IS, NM, SI, ST, TM, TN, TS and TX on v2.3 to
  v2.4 (section 2.8 / 2.9); DT, DTM, FT, GTS, ID, IS, NM, SI, ST, TM and TX on
  v2.5.1 and v2.6 (section 2.A); the same plus SNM on v2.8.2. Content after
  the first value of an NM, SI, DT, TM, DTM or TS field (for example `12^abc`)
  is now reported; the P6-7 limitations-register sentence is removed.
- A primitive component of a composite carrying a subcomponent after its value
  (CX.1 `12&3`) is reported with the same code, located at the component.
- Spec-allowed shapes stay silent: the TS degree-of-precision component on
  v2.3 to v2.4 ("...[+/-ZZZZ]^<degree of precision>"), FT line markers ("The
  component separator that marks each line", v2.5.1 section 2.7.6), one
  observation ID suffix in OBX-3.1, OBX-3.4 and v2.8.2 OBX-3.10 ("71020&IMP",
  "This same combining rule applies to other coding systems", v2.5.1 section
  7.2.3), the QIP.2 value list ("<value1 & value2 &...>", v2.5.1 section
  2.A.59.2), and escaped `\S\` / `\T\`. TX and GTS are checked: TX lines are separated by
  the repetition separator, and GTS "follows the formatting rules for a ST
  field" (v2.5.1 section 2.A.32). FT line markers are field-level only: an FT
  component (CF.2, CF.5; CF.11 on v2.8.2) admits one subcomponent.
- The component-level table check skipped an `ID` component with
  subcomponents (`Component.stringValue` is nil there). It now checks the first
  subcomponent and locates the issue at subcomponent 1 when more follow. It
  also looks up the grammar by `Version.grammarVersion` directly; a `2.8`
  message already ran these checks, because `validate(_:)` declares the
  grammar version first.
- Spec examples: no change to the error report (149 registry entries, 0
  mismatched). The new warnings are print defects (field shifts, composite
  shapes in primitive fields, unescaped delimiters). One class was a misfire
  and is fixed: 253 OBX-3.1 suffix warnings (`73916&IMP`) are now silent.

### Added — P6-7: primitive lexical rules

- `IssueCode.valueFormatInvalid(dataType:)` (additive; open enum per ADR-014)
  and `ValidationOptions.valueFormatSeverity: IssueSeverity?` (default
  `.warning`, owner gate G4; `.warning` in `.strict`; `nil` in `.lenient`).
  NM, SI, DT, TM, DTM and TS are checked against their printed formats on
  every version, including composite components one level of subcomponents
  down and OBX-5 by its OBX-2 type; a primitive field is read as its first
  value. (V251-C10)
- Rules (v2.5.1 and v2.8.2 section 2.A; v2.3 to v2.4 section 2.8 / 2.9): NM is
  an optional sign, digits and an optional decimal point; SI a non-negative
  integer in NM form, bounded 0 to 9999 from v2.5.1 where the section prints
  the bound (`Version.boundsSequenceID`); DT `YYYY[MM[DD]]` naming a calendar
  date; TM `HH[MM[SS[.S[S[S[S]]]]]][+/-ZZZZ]`; DTM and TS
  `YYYY[MM[DD[HH[MM[SS[.S[S[S[S]]]]]]]]][+/-ZZZZ]`. The pre-v2.5 TS format
  line prints `HHMM`, but the same section's prose has `YYYYMMDDHH` specify a
  precision of hour, so the hour alone is accepted on every version.

### Changed — P6-7

- Messages carrying a malformed primitive value (for example an NM of `<5`,
  or a DT of `1980-01-01`) now raise a `valueFormatInvalid` warning. Set
  `valueFormatSeverity = .error` to fail validation on it, or `nil` for the
  previous behaviour.
- Fixture `adt_a04_register_paediatric.hl7`: PD1-3 carried `L` in XON.3 (ID
  number, NM); corrected to `Family Health^L` (XON.1 name, XON.2 type code).

### Fixed — P6-13: table check covers multi-component values in primitive fields

- The field-level code-table check skipped any `ID` field repetition with more
  than one component or subcomponent (`Repetition.stringValue` is nil there),
  so TQ2-10 `RR2^SYS` was never checked against Table 0506. It now reads the
  first component, the value a recipient reads: a recipient ignores
  components "present but ... not expected" (v2.5.1 and v2.8.2 section
  2.6.2 a). A miss on that first component is located at component 1
  (`TQ2[1]-10.1`). Local table extensions and locale renderings apply as
  before; `IS` fields and open tables are still never enforced.
- New `IssueCode.extraComponentsInPrimitiveField` (additive; open enum per
  ADR-014) reports an `ID` or `IS` field repetition with content after its
  first value. The component separator separates components "of data fields
  where allowed" (section 2.5.4) and a sender escapes it in data as `\S\`
  (§2.7.1); an escaped separator is one value and stays silent.
  Severity follows the new `ValidationOptions.extraComponentsSeverity:
  IssueSeverity?` (default `.warning`, owner gate G4; `nil` in `.lenient`).
- Length: while that check is at least as severe as the length severity that
  applies (`normativeLengthSeverity` from v2.7, `fieldLengthSeverity` before;
  error > warning > info), an `ID` / `IS` field's length is the length of its
  first value, so with the defaults v2.8.2 ECD-3 `Y^YES` raises one
  extra-component warning instead of a length warning for the same cause.
  When the length rule is more binding (say `normativeLengthSeverity =
  .error`), or the check is off, the whole occurrence is measured as before.
- Under version substitution (an unrecognised MSH-12 such as 2.7, validated
  against the v2.5.1 grammar, ADR-018) a value a later version allows, such as
  a CWE in a field that is `IS` in v2.5.1, may raise the extra-component or
  length warning. This is by design and pinned by a test.
- Spec examples: 60 new `valueNotInTable` errors, all example defects, now
  registered (`_P6_13_ENTRIES`, 149 registry entries, 0 mismatched): 51
  AIL-2 / AIP-2 (the omitted Segment Action Code shift), 6 MSH-16 (a spaced
  `QPD |` segment ID), 1 MSA-5 (MSA and QAK printed on one line), 1 v2.3.1
  OBR-30 (field shift) and 1 v2.8.2 TCC-9 (` Y^YES`). 165 new
  extra-component warnings, all code^text pairs or shifted fields in the
  prints.

### Fixed — P6-6 fix 1: G10 length corrections, escape measurement, very-large-number symbols

- Owner ruling G10: 18 pre-v2.7 LEN cells shorter than values their own spec
  defines as valid are corrected in the schema, each with a cited
  `LENGTH_WHITELIST` entry: v2.3 MSH-18 6 to 10 (Table 0211 `JIS X 0202`);
  OBX-2 2 to 3 on v2.3, v2.4 and v2.5.1 and OM3-7 2 to 3 on v2.4 and v2.5.1
  (Table 0125); MSH-9 7 to 15 on v2.3.1 and 13 to 15 on v2.4 (three
  message-type components, 3 + 3 + 7 plus two separators); PEO-25 1 to 2 on
  every pre-v2.7 version (Table 0243 `NA`); TXA-3 2 to 11 on v2.3.1 (Table 0191
  `Application`) and 2 to 9 on v2.4, v2.5.1 and v2.6 (`multipart`); v2.6
  PSL-21 2 to 4 (Table 0532 `ASKU`). The P6-2 assertion on v2.3 OBX-2 moves
  from 2 to 3.
- New guard (`FieldLengthSpecConflictTests`): every pre-v2.7 ID or IS field
  bound to an HL7 table, and every closed-coded composite field, admits its
  longest valid value.
- Escape sequences count the characters between their escape delimiters
  (`\F\` 1, `\.br\` 3, `\X0D0A\` 5), per v2.8.2 section 2.7; the pre-v2.7
  texts are silent, so the rule applies to every version. Previously an escape
  counted as the one character it decodes to.
- The v2.4 to v2.6 LEN symbols 65536 (very large number) and 99999 (variable)
  are no longer read as maxima (v2.5.1 section 2.5.3.2 b, c).
- `ValidationOptions.strict` DocC states the length severities stay `.warning`.

### Added — P6-6: field length validation

- `IssueCode.fieldLengthOutOfRange(length:actual:)` (additive; open enum per
  ADR-014). `length` is the printed cell; `actual` is the repetition's
  length with component and subcomponent separators counted.
- `ValidationOptions.fieldLengthSeverity: IssueSeverity?` (default
  `.warning`; `nil` in `.lenient`): the pre-v2.7 maximum length (v2.3 to
  v2.6), which the spec lets a site agreement change (v2.5.1 section
  2.5.3.2). Not an init parameter.
- `ValidationOptions.normativeLengthSeverity: IssueSeverity?` (default
  `.warning`; `nil` in `.lenient`): v2.7+ normative lengths (`m..n`, `m..`,
  `x,y,z`) on primitive-typed fields, which conformant messages SHALL meet
  (v2.8.2 section 2.5.5.0). Not an init parameter. (V231-C15)
- Internal `PrintedLength` reads every stored LEN / C.LEN shape (n, nK, `*`,
  m..n, m.., x,y,z, n=, n#), mirroring the audit's `LENGTH_TOKEN`; a
  schema-wide test pins every stored length as well formed for its era.
  Conformance lengths (`n=`, `n#`, a bare v2.7+ integer) are never enforced
  (section 2.5.5.3); a range printed on a composite field is not enforced
  (section 2.5.5.0). Registered in the permanent-limitations register,
  section C.

### Changed — P6-6

- Validation results change: an over-length field now produces a
  `fieldLengthOutOfRange` warning on every version. Errors and `isValid` are
  unchanged by default (owner gate G4, warning first). Set both severities to
  `nil` for the previous behaviour, or `normativeLengthSeverity = .error` to
  make v2.7+ normative lengths binding.
- Test wire corrected: `OrderConditionTests` carried `RR2^SYS` in TQ2-10 (ID,
  LEN 1; v2.8.2 `1..1`, Table 0506). It now carries `S`.
- Wording: "OCR-glued" is now "extraction-glued" in `audit-schemas.py` and
  the P6-2 entry below (the PDFs are vector text, not scanned).

### Changed — P6-12: blank OPT prints stored verbatim

- 146 fields whose attribute table prints OPT blank now store `""`, not
  `O` (143) or `X` (v2.5.1 OBX-20 to 22, 3). The spec defines no blank
  code (v2.6 section 2.5.3.4); the validator reads a blank as optional, as
  it read `O`, so only v2.5.1 OBX-20 to 22 change behaviour: a populated
  reserved field is no longer flagged as not supported. Recorded as a
  known limitation (limitations register, addendum to section A).
- This settles the P6-10 intake row for v2.3 AIG-2 ("no optionality
  value"): Figure 10-7 prints the cell blank, and the blank is correct.
- The audit compares each cited blank against the stored value, keys every
  unreadable-region citation by its reason (a region cited for blanks no
  longer hides a malformed print or a missing row), and `--write-lengths`
  never removes a length on a blank read. LENGTH_TOKEN rejects a minimum
  of 0 and accepts the section 2.5.5.0 list form `x,y,z`.

### Fixed — P6-12: audits report unreadable prints; printed lengths read

- The schema audit's optionality (M19), repeatability (M22) and length (M25)
  passes no longer skip a slot they cannot read. A slot with no extracted
  row, a blank cell that is not itself a print, or a cell outside the
  column's printed shapes is reported as unreadable, unless a cited
  `UNREADABLE_WHITELIST` entry names it (23 regions: blank OPT cells in
  NST, NSC, SCD, SCP, SDD, SLT, STZ and others, v2.5.1 OBX-20 to 22, v2.8.2
  BUI-12 RP 'R', v2.8.2 TQ2-6 LEN '2..'). A TBL# number bled into RP/# is
  now unreadable instead of `*`.
- A blank LEN is compared as a print where the spec makes it one: v2.8.2
  (LEN and C.LEN are printed "if applicable", sections 2.5.3.2 and 2.5.5.4)
  and withdrawn fields. M25 now compares 2,048 v2.8.2 slots it used to
  skip.
- The segment-table extractor reads a right-aligned LEN cell that sat
  nearer the DT header, the v2.8.2 `C_LEN` header, and a bare OPT code set
  right of its header (v2.6 BLC). It emits C.LEN separately as `clen`.
- Lengths corrected from the print: v2.6 STF-4, 5, 7, 21, 23 to 26, 29, 31,
  32, 35 and GOL-1 (previously absent), v2.6 UAC-1 705 (was `7 05`), v2.6
  OBX-5 `*` (was 24; footnote 1 makes it variable), v2.5.1 OBX-6 250 (was
  6), v2.8.2 OBX-2 2..3 (was 2..2), v2.8.2 DG1-15 2= (previously absent).
- `--write-lengths` now changes only the listed fields; it used to strip
  every other field's length in the same schema.

### Added — P6-4: bounded repetition counts

- `FieldGrammar.maxRepetitions: Int?` (additive, via a separate `init`
  overload; the released initialisers are unchanged). It carries the RP/#
  column's printed bound (`Y/3` before v2.5, `3` from v2.5; v2.3.1 §2.6.5,
  v2.5.1 §2.5.3.5), and `cardinalityExceeded` now fires, as a warning, when a
  field carries more repetitions than that bound. The single-cardinality
  check keeps its error severity and message. (V23-C08, V24-C07)
- Schema `"repeatability"` accepts a decimal bound (`"3"`) besides `"1"` and
  `"*"`; `FieldRepeatability(wireValue:)` maps it to `.multiple`. The
  extractor keeps the printed bound, and `audit-schemas.py --depth
  --write-repeatability` writes it; M22 compares bounds, and `integrity()`
  rejects any other token. Codegen emits `maxRepetitions:` only for a bounded
  field, so every other generated line is unchanged.
- 221 bounded fields across the six versions (v2.3 35, v2.3.1 31, v2.4 35,
  v2.5.1 34, v2.6 43, v2.8.2 43), for example v2.3 MSH-18 `Y/3`, v2.4 OBR-17
  `Y/2`, v2.6 PID-38 `2`, UB2-13 `Y/23`.
- A printed range keeps its maximum as the bound: v2.6 and v2.8.2 CH16
  PYE-4 `0-5`, PYE-5/-6 `0-4`, PSL-8/-19 `0-5`, PSL-17/-18/-20 `0-20` and
  ADJ-5 `0-5`. The minimum is not modelled; every printed minimum is 0, which
  adds nothing beyond the field's optionality, and the extractor reports any
  minimum above 0 as a known limitation.
- The extractor no longer reads a stray cell as a repeat: a LEN bled into the
  RP/# column (v2.8.2 CH07 OBX-4/-13 `20=`) and an OPT or DT code (`R`, `O`,
  `CE`) map to `1`; `Y` plus a footnote digit (v2.3 `Y3`, v2.3.1 `Y4`, OBX-5)
  maps to `*`. `extract-segment-tables.swift --self-check-rp` pins the mapping.
- M22 compares a slot against the defining table's RP/# cell, as M19 and M21
  do, not the union of every chapter's print, so a constrained copy can no
  longer hide a bound.
- `FieldGrammar`'s initialiser traps on a non-nil `maxRepetitions` with
  `.single` or a value below 2.
- OBX-8 on v2.3, v2.3.1 and v2.4 is bounded at 5 by hand: the base OBX table
  prints `Y/5` (v2.3 CH7, v2.4 CH07), and the constrained OBX copies that
  print a blank RP/# are message profiles, not the segment definition.
- ADJ-7 on v2.6 and v2.8.2 prints RP/# `1` and is now single-cardinality
  (the old extractor read any digit as a repeat).
- v2.6 OBX-5 stays unbounded: the CH07 table prints `Y` under a superscript
  footnote marker `2`, which the extractor reads as a bound. Whitelisted in
  M22 with the citation.

### Fixed — P6-5: PCR repeatability (v2.3.1)

- v2.3.1 PCR-9, 11, 13, 15, 17, 19 and 20 are single-cardinality, as printed
  (Figure 7-22, p. 7-96). The TBL# numbers that the column shift put in the
  RP column had been read as repeats. PCR-12/21/22/23 carry their printed
  bounds (3/6/6/3). `table-repairs.json` entries now take an optional
  `repeatability`, which M22 compares against. (V231-C05)

### Added — P6-3: ADD on v2.6 and v2.8.2

- The ADD (Addendum) segment is modelled on v2.6 and v2.8.2 (CH02 §2.14.1,
  SEQ `1-n`), so it now validates instead of taking the Z-segment path.
  Typed accessors are generated as on the other versions. (V282-C04)
- `audit-schemas.py --depth` checks a `DEPTH_WHITELIST` segment's presence
  from its attribute-table caption, so a missing ADD, RDT or NSC is reported.

### Fixed — P6-2: OBX, OBR and NSC lengths (v2.3, v2.3.1)

- v2.3.1 OBX-2 LEN is 3 and OBX-16 is 80, and v2.3 OBX-16 is 80: the values
  printed in the base Figure 7-5, not the waveform category tables
  (Figures 7-26/7-27). (V231-C14)
- v2.3.1 NSC carries the Appendix C Figure C-3 lengths (4, then 30 for
  NSC-2..9). (V231-C16)
- Pre-flight ruling d4 (P7-1 length intake, OBR/OBX rows): v2.3.1 OBR-16 is
  120 and v2.3 OBR-2/OBR-3 are both 75 — the values each segment's defining
  Chapter 4 (Order Entry) attribute table prints, not Chapter 7's stale
  reproduction. v2.3 OBX-1 is 10 and OBX-3 is 590, per Figure 7-5.
- v2.3 and v2.3.1 OBX-5 keeps its variable-length `*`: each version's own
  footnote on the field ("The length of the observation value field is
  variable, depending upon value type") overrides the LEN column's printed
  numeric cap (65536, extraction-glued to its footnote marker). Recorded as a cited
  `LENGTH_WHITELIST` entry in `scripts/audit-schemas.py`.

### Fixed — P6-9: swiftName prose bleed and truncation

- The schema extractor let definition prose bleed into `swiftName` and cut other
  names short. A sweep of all 853 schemas corrected 145 slots from the printed
  element name. Prose bleed: TQ2-10 on v2.5.1 (873 characters), v2.6 (847) and
  v2.8.2 (806); QPD-2 on v2.4, v2.5.1, v2.6 and v2.8.2, which had absorbed the
  next row's "User Parameters (in successive fields)"; and v2.8.2 BPX-21 (421),
  BTX-20 (400) and ITM-16 (94). Truncated heads and `fieldN` placeholders: v2.3
  QRF (6), v2.3.1 RXE (24), v2.4 LOC (7) and RXE (26), and v2.8.2 RXA (13,
  including RXA-2 "nistrationSubIdCounter"), RXC (3), RXD (12), RXE (16), RXG
  (9) and RXO (18). v2.8.2 OM1-56 drops the stray possessive "S", as the
  extractor's current naming rule does. Non-canonical slots take the canonical
  v2.5.1 name where the element is unchanged, as the rest of each segment does.
- Fix round: 31 more slots now carry the canonical name, which brings the sweep to
  176. Of these, 27 were truncated heads that dropped whole leading words, so they
  passed the anchor rule ("minimum" for v2.3.1 RXE-3 "Give Amount - Minimum"):
  v2.3 QRF-1/3/9, v2.3.1 RXE-3/4/6/9/22/26, v2.4 LOC-3/4 and RXE-3/4/22/26/31,
  and v2.8.2 RXA-3/4, RXD-29, RXE-14/17/18/34, RXG-24 and RXO-6/15/26. The other 4
  were possessive-S variants of the canonical name: TQ1-14 and TXA-23 on v2.6 and
  v2.8.2. The convention is now explicit (`AddingASegment.md`). A non-canonical slot
  whose element name matches the canonical v2.5.1 element takes the canonical
  swiftName, possessive "S" included. Any other slot takes the extractor's derived
  name.
- The typed accessors change on two segments: `TQ2.specialServiceRequestRelationship`
  and `QPD.queryTag` (see Deprecated). Only the v2.5.1 schemas (and the earliest
  definer of a segment v2.5.1 lacks) emit typed structs, so no other slot was
  public.
- The element names of v2.8.2 ITM-16 and RQ1-7 also carried prose; they are now
  the printed "Approving Regulatory Agency" and "Substitute Allowed"
  (`FieldGrammar.name` on the v2.8.2 grammar).
- v2.8.2 RXA-2's length "4=" was checked against the print and is correct: the
  attribute table leaves LEN blank and prints C.LEN "4=", which the schema records
  under the extractor's LEN-else-C.LEN rule (as RXA-1 does). Unchanged.
- New audit guard: `scripts/audit-schemas.py` now fails any swiftName that is not a
  lowerCamelCase identifier, is over 70 characters, does not start a word of its
  element name, carries three or more words absent from it, or repeats within a
  segment, or that departs from the canonical name for the same element. It also
  checks element names: at most 11 words, and no run of more than 5 lowercase
  words (the corpus maximum is 10 and 4). Self-checks `check_swift_name`,
  `check_swift_name_uniqueness` and `check_element_name` are in
  `scripts/check-audit-schemas.py`.

### Fixed — P6-1: RF1-18 datatype (v2.8.2)

- v2.8.2 RF1-18 Remaining Benefit Amount is typed `MO`, not the attribute-table
  misprint `M0`, so the MO component grammar now applies. Registered in
  `segment-coverage-extraction.md` and `DATATYPE_WHITELIST`. (V282-C11)

### Deprecated — P6-9: two prose-bled accessor names

- `TQ2.specialServiceRequestRelationshipRequestsUsingTheParentChild...` (the
  873-character v3.13.0 name), renamed `TQ2.specialServiceRequestRelationship`.
- `QPD.queryTagUserParametersInSuccessiveFields`, renamed `QPD.queryTag`.
- Both old names stay as `@available(*, deprecated, renamed:)` aliases that
  forward to the new accessors (ADR-014). Codegen emits them from a new optional
  schema key, `deprecatedSwiftNames`, which the audit validates.

### Added — P4-32: AU OBR-29 "not used" (owner decision G7)

- Under `.auLocalisation`, OBR-29 (Parent) should not be valued on ORM, ORU
  and REF. ADRM-2021 §4.4.1.29 (p. 229) reads "Not used in Australian
  messages. Use observation Sub-ID in OBX-4 to link results" — the
  identical sentence as OBR-26 (item 00261 here, item 00259 on OBR-26).
  Reported as a warning
  `.profileConstraintViolation("ADRM-prose:P-13 ...")`; the HL7 null `""`
  is exempt. Same mechanism and scope as P-11 (OBR-26, P4-27).
- P4-27 withheld this rule (NEEDS_CONTEXT) because the base v2.4 condition
  on OBR-29 (`ORC-1 = CH AND ORC-8 empty`) makes the field conditionally
  required for a child order sent without ORC-8, mirroring ADRM §5.4.1.8
  (p. 295, unchanged from base v2.4 §4.5.1.8): "ORC-8-parent is the same
  as OBR-29-parent. If the parent is not present in the ORC, it must be
  present in the associated OBR." Owner decision G7 (2026-10-01) resolves
  the conflict in favour of shipping anyway: on a v2.3–v2.6 child order
  sent without ORC-8, the AU warning and the base conditionally-required
  check now both fire on the same field — an accepted double-bind, not a
  defect in either rule.
- Not double-reported against HL7au:00060.4 (P4-31): the generated
  full-predicate set marks only `2.4|OBX-2`, so `checkFullPredicateConditional`
  never visits OBR-29.
- No Appendix 5 HL7au conformance-point ID exists for OBR-29 (checked
  directly against the Appendix 5 text region); `docs/design/
  m7-adrm-prose-sweep.md` and the permanent-limitations register's
  HL7au:00060.4 addendum are updated instead, `scripts/
  extract-adrm-conformance.py` was not re-run because there is nothing
  for it to pick up.

### Changed — P4-31: three-state condition evaluator (ADR-021)

- The condition evaluator's core now answers true, false or unknown (a peer that does not resolve, an atom that does not parse, a quantifier over an empty domain, a predicate that cannot judge its referent), combining atoms with Kleene AND and OR. Internal; no public API change.
- No behaviour change: `conditionTriggers` is exactly "the condition is true". The full suite, a digest of every issue on the extracted spec examples and the test fixtures under both locales, and the spec-example registry check (138 entries, 0 mismatched) are unchanged.

### Added — P4-31: HL7au:00060.4 route C, full-predicate enforcement (ADR-021)

- Schema keys `conditionIsPredicate` and `predicateCitation`: a field may mark its stored condition as the spec's complete C predicate (required when true, must not be sent when false). Codegen emits the marked set into an internal lookup; `FieldGrammar` and the public API are unchanged. `scripts/audit-schemas.py` requires the citation, a printed C and a condition, with a self-check case.
- AU profile: in ORM, ORU and REF, a marked C field valued (other than with the HL7 null) while its condition is definitely false reports `.profileConstraintViolation("HL7au:00060.4 ...")`, error. Unknown never fires; a field a base or AU prohibition already reports is not reported twice. Marked on v2.4: OBX-2 only (valued while OBX-11 = X; ADRM §4.17.2 Scenario 5 confirms). PID-36 and CTI-2 are parents required when their child is valued and stay unmarked (owner ruling G9).
- Every C field in the v2.4 ORM^O01, ORU^R01 and REF^I12 segments classified with quotes (`docs/design/conditional-completeness-audit.md`): 1 full predicate, 31 trigger-only, 8 with no prohibition derivable from the text, 12 with no prohibition derivable from the message (owner ruling G9). HL7au:00060.4 moves from PARTIAL to SHIPPED with that scope (ADRM conformance register: 74 shipped, 17 partial).

### Added — P4: expressible conditions

- `FieldGrammar.prohibitedSeverity` (default `.error`) and the schema key `prohibitedSeverity`, so SHOULD-level and "not applicable" prohibitions surface as warnings. A separate `init` overload; the released initialisers are unchanged (ADR-014).
- Condition DSL: `noRepeat(<fieldref>) <op>` (no repetition satisfies the predicate) and `nextSegmentID(<ID>|...)` (next segment ID after skipped IDs). ADR-010 amendment.
- Predicates moved out of the permanent-limitations register, each with a spec citation in `docs/design/conditional-completeness-audit.md` ("Shipped in P4"): PV2-1, PV2-45, PV2-47; TXA-3, 5, 7, 13, 22; TQ1-12, TQ2-3/4/5/6/10; SCH-1/2/27, ARQ-25; AIS/AIG/AIL/AIP start, offset units, allow substitution and filler status; MFE-2, MFA-2, LRL-5/6, OM7-16/18; BPX-5/6/8/9/10, BTX-2..7; v2.8.2 OBR-22 and PRT-14; v2.6 PD1-15 and ORC-26.
- Conditional prohibitions: RXR-6, ORC-25, OBX-12, PYE-3..6 (errors); TQ2-7, STF-1, PRA-1, PRA-12, SPM-13, BPX/BTX "not applicable" (warnings).

### Fixed — P4: expressible conditions

- v2.8.2 PRT-7 prohibition keyed to PRT-5 as printed (§7.4.4.7); it fired on person participations without an organisation.
- OBR-2/3 and ORC-2/3 accept a filler id alone ("either a placer or a filler id"), with the Send Number exception, on all six versions.

### Changed — P4: expressible conditions

- Validation is stricter wherever a predicate above now fires: messages that omit a field the cited sentence requires gain an error or warning. v2.6 PD1-15, DG1-22 and ORC-26, plus v2.5.1 ORC-26 (`ORC-20 in (3, 4)`), move from `O` to the printed `C`; v2.6 OBR-48 was already `C` and is untouched by P4.
- `docs/design/permanent-limitations-register.md` section A and the conditional-completeness audit are rewritten: the bare-C set is now frozen position by position, with guard tests on all six versions (`BareConditionalGuardTests` for v2.3, v2.3.1, v2.4, v2.5.1, v2.6; `MultiVersionTests.v282M2PermanentLimitationsGuard` for v2.8.2).

### Fixed — P4-16: AU profile PID-35..38 grammar extension removed as redundant

- The S5-D `Profile+au_adrm_2021.swift` `grammarExtensions["PID"]` override (fields 35..38) is gone. P4-17 confirmed base v2.4 `PID.json` has carried all four fields since before P4-17; the override duplicated 35/36/37 exactly, and its field-38 `repeatability: .single` had silently diverged from the base/v2.5.1/v2.6 `*` (RP 2) with no AU citation narrowing it. A two-repetition PID-38 under `.auLocalisation` wrongly raised `cardinalityExceeded`; it no longer does. `Profile.swift`'s `grammarExtensions` doc comment is corrected (the base v2.4 PID grammar never capped at 32).

### Fixed — P4-30: segment-table R against a restricting field definition

Fields whose attribute table prints R while the field definition limits or relaxes them
(Requirement 4). Each ruling cites the definition; the printed R stays visible in the schema's
new `optionalityCitation` key, which the schema audit reads as that slot's optionality whitelist
entry and requires wherever a field's optionality departs from the printed table. The ROL-4
STF-2/STF-3 value-equality sentence is recorded in the permanent-limitations register.

- **MFI-6 Response Level Code** (all six versions): R to C, `messageCode = MFN`. The
  definition reads "Required for MFN-Master File Notification message" (v2.3 CH8 sec 8.4.1.6;
  v2.4 to v2.8.2 CH08 sec 8.5.1.6). An empty MFI-6 on MFK, MFD or another master-file message
  no longer raises `requiredFieldMissing`; on MFN it raises `conditionalFieldMissing`.
- **CSR-8 Study Authorizing Provider** (all six): R to C, `triggerEvent = C01`. The
  definition reads "This field is required for the patient registration trigger event (C01)",
  the sentence CSR-9 and CSR-10 already carry under a printed C.
- **ROL-4 Role Person** (v2.6, v2.8.2): R to C, `STF absent`. CH15 sec 15.4.7.4: "If both STF
  and ROL are present in the same message, populating this field is optional". v2.3 to v2.5.1
  print no such sentence and keep R.
- **RXA-4 Date/Time End of Administration** stays R (ruling, no schema change). "If null, the
  date/time of RXA-3 ... is assumed" names the HL7 null `""`, which Chapter 2 distinguishes
  from an omitted field; v2.8.2 Chapter 2B: "A required element can have a null value". So
  `RXA-4 = ""` satisfies R and an empty RXA-4 still fires. The 41 spec-example lines that
  leave RXA-4 empty are registered as genuine example errors.
- Spec-example sweep: 4718 to 4688 lines (27 MFK/MFD MFI-6 lines and 3 off-C01 CSR-8 lines
  gone); registry 126 to 138 entries, 0 mismatched.

### Added — P4-15: bare-C register completion and condition-DSL guards

- Bare-C guard tests (`BareConditionalGuardTests`) pin the remaining v2.3,
  v2.3.1, v2.4, v2.5.1 and v2.6 sets of `C` fields with no `condition` and no
  `prohibitedWhen`, sharing one `bareConditionals(_:)` helper with the
  existing v2.8.2 guard in `MultiVersionTests` (no more per-guard copy).
  `docs/design/conditional-completeness-audit.md` gained the RXA-11 /
  RXD-13 / RXE-8 "default, not a trigger" positions, RXO-14 / RXE-13
  Ordering Provider's DEA Number, TXA-21 and SAC-6 (findings V23-C10,
  V24-C09).
- `ConditionLanguage`'s `=` / `!=` / `startsWith` / `not startsWith`
  predicates now reject a literal containing whitespace. Before this, a
  misspelt lower-case connector (`PID-3 = A and PID-4 populated`, meant as
  two `AND`-joined atoms) parsed as one atom whose literal swallowed the
  rest of the string and silently never matched a real field value. No
  shipped condition carried a whitespace literal.
- `ConditionParseValidityTests`'s per-version segment-table list is now
  derived from `Version.allCases` / `Validator.grammarTable(for:)` instead
  of hand-listed, so a future version is checked automatically.

### Changed — P4-15: `noRepeat(...)` fails safe on an unreadable predicate

- On malformed input only, a `noRepeat(...)` atom with an unreadable
  predicate now fails safe (never holds) instead of holding. Moved here from
  the P4-25 entry below, where a behaviour change had been recorded under
  "Added".

### Added — P4-26: base OBX-11 = O dynamic-specification null rule

- OBX-2 and OBX-5 must not carry a value other than the HL7 null `""` while
  OBX-11 = O, on every version that prints the rule: v2.3.1 §7.3.2.11 and
  §7.4.2.11 in v2.4, v2.5.1, v2.6 and v2.8.2 ("An OBX used for a dynamic
  specification must contain the detailed examination code, units, etc., with
  OBX-11 valued with O, and OBX-2 and OBX-5 valued with null"). v2.3 has no O
  status and no rule. Reported as an error `.conditionalFieldProhibited` on
  every locale and message type. A value in any OBX-5 repetition fires; a lone
  `""` does not.
- The base OBX-2 condition `OBX-11 != X` is unchanged, and OBX-5 gains the
  condition `OBX-11 = O` on the same five versions. `""` counts as populated
  for both, so an empty OBX-2 or OBX-5 with OBX-11 = O raises
  `.conditionalFieldMissing`, and the only conformant wire is `""` in both.
  Tests pin that.
- New public `FieldProhibition.permitsNull`. `FieldProhibition` (new in P4-21,
  not yet released) has a single initialiser,
  `init(condition:severity:permitsNull:)`, with `permitsNull` defaulting to
  `false`. The schema key is `permitsNull` on an `additionalProhibitions`
  entry. Every other shipped prohibition still treats `""` as a value.
- The AU-profile duplicate from P4-24 is removed, so AU traffic reports the
  rule once, as the base issue. The P4-24 tests now expect the base issue.

### Added — P4-27: AU "not used" elements

- Under `.auLocalisation`, OBR-26 (Parent Result) should not be valued on
  ORM, ORU and REF. ADRM-2021 §4.4.1.26 (p. 228) reads "Not used in
  Australian messages. Use observation Sub-ID in OBX-4 to link results."
  No modal verb, and the ADRM's own attribute-table entry gives usage O
  (not X), so per the documented severity convention this is a warning.
  Reported as `.profileConstraintViolation("ADRM-prose:P-11 ...")`. No base
  v2.4 condition makes OBR-26 required, so nothing conflicts. (Fix round 1:
  corrected from error to warning.)
- Under `.auLocalisation`, ORC-24 (Ordering Provider Address) should not be
  valued on Referrals. ADRM-2021 §7.3.11.24 (p. 343) reads "This field should
  not be used. Use ORC-22 for the address of the prescriber's facility."
  AU-specific (base v2.4 and the ADRM's own Observation Ordering chapter
  carry no such note) and Referral-only. Reported as a warning
  `.profileConstraintViolation("ADRM-prose:P-12 ...")`.
- OBR-29 — the identical "Not used in Australian messages" sentence as
  OBR-26 (ADRM §4.4.1.29, p. 229) — was deliberately **not** enforced here.
  It conflicts with ADRM §5.4.1.8's "ORC-8-parent is the same as OBR-29-parent.
  If the parent is not present in the ORC, it must be present in the
  associated OBR", which the schema already encodes as a live base condition
  on both fields and which the already-shipped M8-B2 `pairedFieldMismatch`
  rule presumes resolvable. Documented as a NEEDS_CONTEXT finding in
  `docs/design/m7-adrm-prose-sweep.md` and the permanent-limitations
  register's HL7au:00060.4 addendum. **Superseded by P4-32** (owner decision
  G7, 2026-10-01, above): OBR-29 ships anyway, as `ADRM-prose:P-13`.
- A wider sweep for "not used"/"should not be used" AU-specific prose (the
  M7 sweep's keyword list never matched this phrasing) turned up eight
  further narrative findings with no conformance-point ID and no safe,
  wire-decidable enforcement: MSH-20, PID-22, PV1-7, IAM-7, the RP
  datatype's namespace-ID sub-component, TS's legacy degree-of-precision
  sub-component and (fix round 1) the section 3 Datatypes overview table, p.128, TM row and the
  microbiology worked example's OBX-17 note. Each is recorded in
  `docs/design/m7-adrm-prose-sweep.md` §B with its reason (descriptive
  rather than prohibitive wording, content-purpose restriction,
  receiver/system-capability condition, or component-level scope the current
  `FieldOverride.prohibitions` mechanism cannot express). No Appendix 5
  conformance point changed, so the M6 register is unchanged.

### Added — P4-25: every condition string is proven to parse

- A test now walks every segment grammar in all six versions, every datatype component condition and every AU-profile condition, and fails on any condition string the evaluator cannot read. Before this, a misspelt condition passed codegen and the audit and then silently never fired. No shipped condition failed; none changed.
- The condition parse is shared: `ConditionLanguage` classifies clauses, atoms, referents and predicates, and both the evaluator and the internal `Validator.conditionParseErrors(_:)` read conditions through it (ADR-010, P4-25 amendment). Internal only; no public API change. See "Changed — P4-15" above for the resulting `noRepeat(...)` behaviour change.

### Added — P4-24: HL7au:00060.4 route B, explicit AU prohibitions

- Under `.auLocalisation`, OBX-2 and OBX-5 must not be valued when OBX-11 = O
  on ORM, ORU and REF. HL7 v2.4 §7.4.2.11 reads "An OBX used for a dynamic
  specification must contain the detailed examination code, units, etc., with
  OBX-11 valued with O, and OBX-2 and OBX-5 valued with null." Reported as an
  error `.profileConstraintViolation("HL7au:00060.4 ...")`; the HL7 null `""`
  is accepted. Silent under `.international` and on other message types.
- New internal `ProfileFieldProhibition` and `FieldOverride.prohibitions`
  (additive, defaulted). The rules use the shared condition evaluator, and
  base validation is unchanged.
- Every other C field in the v2.4 ORM^O01, ORU^R01 and REF^I12 segments
  (including the AU REF additions) was read against the base chapter and the
  ADRM clause. None states a prohibition that route B can model. HL7au:00060.4
  stays PARTIAL; the limitation addendum and the conformance register name
  what route B shipped and what route C still has to close.

### Added — P4-23: scheduling filler-status prohibitions in request transactions

- AIS-10, AIG-14, AIL-12 and AIP-12 (Filler Status Code) now carry
  `prohibitedWhen: messageCode = SRM` at `prohibitedSeverity: warning` in all
  six versions. The definitions in all four segments read "It is recommended
  that this field be left unvalued in transactions originating from
  applications other than the filler application"; AIP-12 additionally reads
  "It should not be valued in any request transactions from the placer
  application to the filler application" (identical text in v2.3 through
  v2.8.2). Fires as a warning on the SRM request; silent on the
  filler-originated SIU, SRR and SQR wires, and on the SQM query (which the
  text calls out separately as merely optional).
- Test coverage: the warning fires on a valued SRM and is silent when the
  same field is empty, on SIU/SRR, and on the SQM query for both allow
  substitution and filler status (P4-12 minor 5). Added a silent case for
  start date/time, offset and units populated together.
- Register: v2.8.2 Chapter 11 (§11.7.1, §11.7.2) carries AIP in the
  appointment-history group of CCM, CCR, CCU, CQU and CCI without restating
  anything about filler status, so both the P4-12 condition and this
  prohibition correctly stay silent there. v2.6 Chapter 11 carries no
  scheduling segment at all — Collaborative Care is a v2.8.2 addition.

### Added — P4-21: more than one prohibition per field

- `FieldGrammar.additionalProhibitions: [FieldProhibition]` holds further
  prohibitions beside `prohibitedWhen`, each with its own severity. Empty by
  default; set only through a new `FieldGrammar.init` overload ending
  `additionalProhibitions:`. The released initialisers keep their signatures
  (ADR-014) and are pinned in `SignatureCompatibilityTests`.
- `FieldProhibition` (`Sendable`, `Hashable`): a `condition` in the condition
  grammar and the `severity` it reports at.
- The Validator raises one `conditionalFieldProhibited` per rule that holds on a
  populated field, so two triggered rules give two issues.
- Schema key `additionalProhibitions: [{when, severity, citation}]`. Codegen emits
  it only where set and fails on a malformed rule or a missing citation;
  `scripts/audit-schemas.py` checks the same shape.
- v2.5.1 and v2.6 RXR-6 now warn when RXR-2 is coded from HL7 Table 0163
  (`RXR-2.3 = HL70163 OR RXR-2.6 = HL70163`, either CWE coding triplet; "If RXR-2 employs HL7 Table 0163 – Body Site, then
  RXR-6 should not be populated", CH04 §4.14.2.6), beside the existing
  `RXR-2 empty` error. v2.8.2 CH04A drops the sentence. Closes the
  "one prohibition per field" limitation (ADR-010 amendment, 2026-10-01).

### Documented — P4-20: HL7au:00060.4 recorded as PARTIAL

- HL7au:00060.4 (C elements must not be valued when the predicate is false) is now PARTIAL in the ADRM register, enforced only through explicit `prohibitedWhen` fields. General enforcement is a BLOCKING limitation (`permanent-limitations-register.md` §D addendum; routes P4-24 and ADR-021 candidate).

### Fixed — P2-15: per-field table openness

- Some HL7 tables are cited "for suggested values" (or "User-defined", or
  "can be extended") by one field and "for valid values" by another. Openness
  was set per table, so those fields reported false `valueNotInTable` errors.
  A schema field entry can now carry `"tableOpen": true` with a quoted
  `tableOpenCitation`; codegen emits it as the new `FieldGrammar.tableOpen`
  (default `false`), and the field-level closed-table check skips that field
  only. The released `FieldGrammar.init` keeps its signature; `tableOpen:` is
  a separate overload (ADR-014), both pinned in `SignatureCompatibilityTests`.
- 49 fields are marked, each against its own prose: Table 0136 (v2.4 PID-31;
  v2.6 and v2.8.2 DG1-24, RFI-3, IVC-13, PSG-4, PSL-47), 0167 (RXD-11, every
  version), 0185 (PRD-6 and CTD-6 on every version, PRD-14 on v2.6 and
  v2.8.2), 0206 (v2.6 and v2.8.2 IAM-6, ARV-2), 0239 (v2.3 PCR-2, -9, -11,
  -13), 0323 (v2.4 and v2.5.1 IAM-6), 0371 (v2.5.1, v2.6, v2.8.2 OM4-7,
  SAC-27) and 0532 (v2.6 and v2.8.2 PSL-21). v2.6 PSG-4 was missing from the
  register's list; its prose also says "for suggested values".
- Validator output changes on the 19 scalar `ID` fields among them (0136,
  RXD-11, PSL-21): an out-of-table value there is no longer an error. The
  other 30 are `IS` or composite fields, never enforced, so the mark corrects
  the metadata only. Fields citing the same tables "for valid values" (PID-24,
  RXE-9 and the rest) are still checked.
- `scripts/audit-schemas.py` fails a `tableOpen` that is not a boolean, has no
  citation, or sits on a field with no table binding, and a citation without
  `tableOpen`.
- The permanent-limitations register, section C, now records the mixed
  tables as modelled rather than as a blocking limitation; ADR-016 gains the
  per-field decision.

### Fixed — P2-14 fix-wave minors

- `SignatureCompatibilityTests.swift` now uses a plain `import HL7v2Kit`, not
  `@testable`, so the ADR-014 pinning tests actually exercise public visibility.
- `scripts/extract-code-tables.swift` records a note when an overrides.json
  `fixDescriptions` key names a code the PDF does not print, matching the
  existing `patterns` behaviour.
- `Resources/tables/overrides.json` gives the v2.3.1 0355 and v2.4 0290
  entries a `citation` key (the text was already in their `note`).
- `permanent-limitations-register.md` section C's "Freeze decision (B + C)"
  paragraph now excludes the mixed-tables row, which blocks spec-completeness
  (requirement 3) as the row itself already said.
- STATUS.md's Build row now states the P7-1 audit's real optionality (M19,
  12 findings) and length (M25, 15 findings) counts, owned by the P4 and P6
  intake, instead of the stale "0 findings"; test count corrected to 787.

### Fixed — P2-14: remaining locally extensible tables

- Applied the ADR-016 open-table criterion to the four tables the P2 fix wave flagged
  as an unfinished requirement-4 follow-up:
  - Table 0105 (Source of comment, NTE-2) opens on every supported version (v2.3 to
    v2.8.2): NTE-2, its only governing field, reads "This table may be extended
    locally during implementation" unchanged across all six. An out-of-table NTE-2
    value no longer raises `valueNotInTable`.
  - Table 0048 (What subject filter, QRD-9 / URD-4) opens on v2.3 to v2.6 (QRD/URD
    are dropped from v2.8.2): both governing fields say the table may be extended
    locally or by local agreement.
  - Table 0175 (Master file identifier code, MFI-1) opens on every supported
    version: MFI-1, its only governing field, reads "This table may be extended by
    local agreement during implementation to cover site-specific master files
    (z-master files)" unchanged across all six.
  - Table 0371 (Additive, OM4-7 / SAC-27 / SPM-6) opens on v2.4, the only version
    where OM4-7 and SAC-27 are the sole citing fields ("The value set can be
    extended with user specific values"). On v2.5.1, v2.6 and v2.8.2 a third field,
    SPM-6, also cites the table but only "for valid values" with no extension
    clause: mixed, stays closed there and is registered in
    `permanent-limitations-register.md` section C.
  - 0048, 0175 and 0371's governing fields are all CE/CWE, whose identifier
    component is `ST`, not `ID` (ADR-016: composite `tables` bindings are recorded
    but not enforced), so opening them corrects the registry's metadata without a
    behavioural change in the current validator; only 0105 (a scalar `ID` field)
    changes what the Validator reports.

### Fixed — P3 fix wave: no silent version fallback

- Four MSH-12 shapes used to fall back to v2.5.1 with no issue in any mode:
  a whitespace-only MSH-12, an empty VID.1 with VID.2 valued
  (`^AUS&Australia&ISO3166_1`, legal on v2.5.1, where VID.1 is optional),
  and a VID.1 with a subcomponent (`2.4&X`, `&2.4`). Each now gets the
  same treatment as an unmodelled version. The Validator reports
  `versionNotRecognised(wireValue:)` (warning) naming the v2.5.1 fallback,
  with VID.1 as rendered (empty when VID.1 is empty).
  `ParserOptions.rejectUnknownVersion`, which `.strict` sets, throws
  `ParseError.unsupportedVersion(found:)` with the same value. An empty
  MSH-12 still falls back without a version issue in every mode, because the
  required-field check reports it.
- `VersionHandlingTests.versionMatrix` pins 17 MSH-12 shapes under the
  default, `.strict` and `rejectUnknownVersion` parser options.
- The permanent-limitations register, section F, no longer records the
  subcomponent and empty-VID.1 shapes as a limitation. ADR-018's version
  table gains rows for them and for a whitespace-only MSH-12.
- The `versionGrammarSubstituted` message no longer says "MSH-12 declares
  2.8" when the `.v2_8` version came from `ParserOptions.versionOverride`
  (or a directly built `Message`) and MSH-12 says otherwise.
- Findings closed by workstream P3: X-C01 (partial; P10 completes it),
  X-C02, X-C03, X-C11, V282-C03, V282-C09.

### Fixed — P3-5: unrecognised MSH-12 versions are reported

- A message whose MSH-12 version ID has no `Version` case (2.1, 2.2, 2.5,
  2.7, 2.7.1, 2.8.1, 2.9, anything else) still parses and falls back to the
  v2.5.1 grammar, but every report now carries one
  `IssueCode.versionNotRecognised(wireValue:)` (warning) at MSH-12 naming
  the grammar applied (V282-C09). The supported set and each exclusion are
  recorded in ADR-018 and the permanent-limitations register, section F.

### Fixed — P3-4: the version is read from VID.1 of MSH-12

- MSH-12 is a VID composite. The Parser read it as a scalar, so any MSH-12
  with a second component (the AU form `2.4^AUS&Australia&ISO3166_1`) was
  treated as absent and validated against v2.5.1 without a word. The
  version is now taken from VID.1: such messages validate against their
  declared version, and `ParserOptions.strict` rejects an unknown VID.1
  (ADR-018).
- Visible effect on AU v2.4 traffic: the v2.5.1 MSG component checks no
  longer apply. v2.4 types MSH-9 as CM with no component optionality, and
  its second component "is not required on response or acknowledgment
  messages" (HL7 v2.4 Chapter 2, 2.16.9.9), so `requiredComponentMissing`
  on MSH-9.3 (and on MSH-9.2 for ACK) is no longer reported. The AU
  profile rule HL7au:00049.2/.3 still requires both on ORM, ORU and REF.
- HL7au:00049.1 (MSH-9 message type, MSG-1, must be valued) is now enforced
  by the AU profile itself. It had relied on the base MSG-1 requirement,
  which exists only from v2.5.1, so it went unenforced once AU traffic
  resolved to v2.4. The profile rule defers to the base check where the
  grammar version already requires MSG-1, so v2.5.1 and later report the
  finding once, not twice. The conformance register moves 00049.1 from
  BASE to SHIPPED.
- The same gap applied to three identifier points on Orders, Results and
  Referrals, which the conformance register had filed as BASE against base
  requirements the v2.4 grammar does not carry. The AU profile now states
  each one:
  - HL7au:00044.1.1 (CX-1 must be specified). CX.1 is required in the base
    model only from v2.5.1, so this rule defers to the base check there and
    the finding is still reported once.
  - HL7au:00044.3.1 (EI-1 must be valued) and HL7au:00044.7.1 (XCN-1 must
    be specified). No modelled version requires EI.1 or XCN.1, so these were
    never enforced on any version; they now fire on every version. On ORC-2,
    ORC-3, ORC-4, OBR-2 and OBR-3 an empty EI-1 is reported under both
    HL7au:00044.3.1 and the field's own EI-completeness point (HL7au:000003
    to 000007), since both are violated.
    Likewise on v2.8.2, when XCN.1 and XCN.2 are both empty, XCN.1's absence
    is reported twice: under HL7au:00044.7.1 and as the base
    `conditionalComponentMissing` for XCN.1 (v2.8.2 XCN.1 "is required if
    XCN.2 is not populated"). The empty family name is reported separately,
    by XCN.2's own base condition (required if XCN.1 is not populated) and by
    HL7au:00044.7.5. All are violated, so all are reported by design.
  The register moves all three from BASE to PARTIAL: the presence half is
  enforced, while identifier-scheme validity (00044.1.1, 00044.7.1) and
  cross-message uniqueness (00044.3.1) are not checked. This absorbs P4-19.
- VID.1 is trimmed, and the `found:` value of
  `ParseError.unsupportedVersion` carries the trimmed VID.1. (P3-4 briefly
  let a whitespace-only MSH-12 fall back silently under `.strict`; the P3
  fix wave above reports it and `.strict` throws for it again.)

### Changed — P3-3: `2.8` messages are validated against the v2.8.2 grammar

- Before, a `2.8` message had no grammar: default validation reported
  `isValid == true` with nothing checked, and `.strict` rejected every
  segment as a Z-segment (X-C02, V282-C03).
- It is now validated against the v2.8.2 segment grammar, code tables and
  datatype grammar, and every report carries one
  `IssueCode.versionGrammarSubstituted(declared: .v2_8, validatedAs: .v2_8_2)`
  (info) at MSH-12. `Version.grammarVersion` exposes the mapping. The
  public registries stay version-literal. Decision: ADR-018.

### Fixed — P3-2: standard segments are no longer reported as Z-segments

- A segment whose ID does not begin with `Z` and that the message's version
  does not define (for example PRT on a v2.3 message) is now reported as
  `IssueCode.segmentNotInVersionGrammar` (warning). Before, it went to the
  Z-segment policy, so `.strict` rejected it as "Z-segment 'PRT' rejected"
  (V282-C03, ADR-018).

### Fixed — P2 fix wave: whole-workstream review remediation

- Table 0355 (Primary key value type, MFE-5) is opened on v2.4, v2.5.1, v2.6 and
  v2.8.2: the note under the table reads "For locally defined master files, this table
  can be locally extended with other HL7 data types". An MFE-5 data type outside the
  printed rows no longer raises `valueNotInTable` there. v2.3.1 cites the table "for
  valid values" with no such note, so it stays closed.
- One criterion for open HL7 tables, recorded in ADR-016: a table is open when its
  governing field prose cites it "for suggested values" or says it may be extended
  locally, and closed on "valid values" or silence; field prose that calls an HL7-kind
  table "User-defined" sets its kind to `User`. Applied where every governing field
  agrees: v2.8.2 Table 0920 (OM4-16) is opened, and v2.8.2 Table 0617 (XAD.18) becomes
  `User`, so neither raises `valueNotInTable` any more. Tables whose governing fields
  disagree (0136, 0167, 0185, 0206, v2.3 0239, 0323, 0532) are unchanged and registered.
- ADR-014 signature compatibility: `ValidationOptions.init` and `HL7Table.init` keep
  their released signatures. `localTableExtensions` is no longer an init parameter (set
  it by mutation), and `patterns:` moves to a separate `HL7Table.init` overload.
- v2.4 Table 0290 (MIME base64 encoding characters) rows 51 to 63 carried the value
  reprinted in the description ("51 z"); the descriptions are now the single character
  CH02 sec 2.9.16.4 means ("z"), matching v2.3.1. Corrected through a new
  `fixDescriptions` key in `Resources/tables/overrides.json`.
- ADR-016 no longer lists composite-component table links as deferred (shipped by
  ADR-017) and records why Table 0391 stays closed on v2.6 and v2.8.2.

### Changed — P7-1: the schema audit compares `C` and the defining attribute table

- `scripts/audit-schemas.py` M19 no longer skips a slot where the schema or the print is
  `C`; a `C` / non-`C` disagreement is a finding unless the whitelist cites the spec text
  behind it (v2.6 ORC-8 and OBR-29 are the first such entries).
- M25 length and M19 optionality compare against each segment's defining attribute table
  (the first full-depth print in chapter order), not any chapter's variant print.
- Every audit whitelist entry now carries its citation; `DEFERRED_VERSIONS` is empty
  since M5 closed.
- New `--only-version` flag; new `scripts/check-audit-schemas.py` self-check, run in CI.

### Added — P2-13: caller-declared local extensions to HL7 tables

- `ValidationOptions.localTableExtensions` (additive stored property, default
  `[:]`, set by mutation; not an init parameter, so `ValidationOptions.init` keeps
  its released signature). Every
  supported version permits an HL7 table to be extended locally (v2.3 and v2.3.1
  CH2 sec 2.6.6, "Additions may be included on a site-specific basis"; v2.4 CH02
  sec 2.7.6; v2.5.1 and v2.6 CH02 sec 2.5.3.6; v2.8.2 CH02C 2.C.1.2); a table
  still stays closed by default, but a
  caller can now declare the codes it has locally added to a named table, keyed
  by four-digit table number. A declared code is accepted wherever that table
  is checked, at field or component level; every other out-of-table code is
  still `valueNotInTable` (owner gate G5).

### Added — P2-6: pattern rows in the code-table registry

- `HL7Table.CodePattern` and `HL7Table.patterns` (additive). The released
  five-parameter `HL7Table.init(number:name:kind:permitsLocalExtensions:entries:)`
  is unchanged; a separate overload also takes `patterns:`, and codegen emits it
  only for a table that has pattern rows.
- `HL7Table.contains(_:)` now accepts a full match against a pattern row,
  in addition to an exact printed-code match. `CodePattern.matches` enforces
  the full match itself (wrapping the supplied regex in `\A(?:...)\z`), so
  a pattern's own regex need not be anchored for matching to be exact.
- Table 0203 `NNxxx` ("National Person Identifier where the xxx is the ISO
  table 3166 3-character (alphabetic) country code") is modelled as the
  pattern `^NN[A-Z]{3}$` on v2.3.1 to v2.8.2 (V282-C01): values such as
  `NNAUS` or `NNCAN` are now members under `HL7Table.contains(_:)` and in the
  schema audit's spec-example code check (`scripts/audit-schemas.py
  --examples`). CX.5 validation outcomes do not change, because Table 0203 is
  open on v2.4 to v2.8.2 (P2-7) and user-defined on v2.3.1. The pattern
  checks only the shape — `NN` plus three uppercase letters — not ISO 3166
  membership of those three letters; see the permanent-limitations register
  §C.

### Changed — P2-7: Table 0203 is not a closed set

- Table 0203 (Identifier type) is opened on v2.4 to v2.8.2:
  `permitsLocalExtensions` is set and `HL7Table.isClosed` is now `false` on
  every version, because every CX.5 / XCN.13 / PPN.13 / XON.7 definition
  cites the table "for suggested values" rather than as a closed set
  (V282-C02, owner gate G5). CX.5 values outside the printed rows no
  longer raise `valueNotInTable` on v2.4 to v2.8.2.
- v2.4 Table 0203's `kind` is corrected from `User` to `HL7`, matching
  CH02 sec 2.9.12.5's own heading (Appendix A had indexed it as User).

### Fixed — P2: code-table false errors and bindings

- **P2-1:** v2.5.1 Table 0125 restored to admit every data type CH07 sec
  7.4.2.2 allows; OBX-2 = `CWE`, `CNE`, `DTM`, `IS`, `DR`, `EI` and the
  other composites no longer raise `valueNotInTable(0125)` (V251-C01).
- **P2-2:** Table 0125 widened the same way on v2.3, v2.3.1, v2.4 and v2.6,
  citing each version's own Chapter 7 OBX-2 prose (V251-C01, cross-version).
- **P2-3:** v2.3.1 Table 0356 gains the `2.3` row Chapter 2 sec 2.24.1.20
  prints and Appendix A omits; MSH-20 = `2.3` no longer raises
  `valueNotInTable(0356)` on v2.3.1 (V231-C01).
- **P2-4:** v2.4 Table 0119 restored as the HL7 table CH04 sec 4.20.1
  prints, `kind` corrected from `User` to `HL7`; ORC-1 is checked again on
  v2.4 (V24-C03).
- **P2-5:** v2.3 chapter-printed tables 0254, 0255, 0256 and 0290 (and the
  matching v2.3.1 0290 rows) added from Chapters 8 and 2 (V23-C09).
- **P2-8:** v2.5.1 print-versus-prose table bindings corrected: TQ1-12
  binds Table 0472, CON-18 binds 0545, SID-4 keeps 0385; each misprint is
  recorded in `table-repairs.json` with a citation (V251-C06).
- **P2-9:** prose-only table bindings added: RCP-7 (v2.4, v2.5.1) binds
  0391, SAC-28 binds 0372; Table 0391 is opened, citing the printed "no
  values defined by HL7" note (V251-C07).
- **P2-10:** the TBL# extractor now joins a four-digit continuation-line
  number to a closed cell, so v2.3.1 MSH-9 binds both `0003` and `0076` as
  Figure 2-8 prints (V231-C04).
- **P2-11:** the datatype-prose extractor rejoins a table reference
  hyphenated across a line break; v2.3.1 and v2.4 PT.2 now bind 0207 and
  v2.3.1 PL.6 binds 0305 (V231-C08).

### Fixed — P1 fix wave: whole-workstream review remediation

- v2.6 OBR-48 (Medically Necessary Duplicate Procedure Reason) was `O`; CH04
  §4.5.3.48 prints `C` (bare, no condition text). It now matches v2.5.1 and
  v2.8.2, which already printed `C`.
- Documented the v2.8.2 OBR-2/OBR-3 `ORC-2 empty` / `ORC-3 empty` conditions
  as a confirmed misfire, not a possible one: §4.5.3.2 needs only a placer
  *or* a filler id, so a conformant message carrying just a filler id trips
  OBR-2. Fix tracked as P4-7.
- Registered a second, wider instance of the same shape on v2.3 to v2.6:
  a placer NW order legitimately has no filler number yet (the ORC-1 Send
  Number table notes print a null ORC-3), so OBR-3/ORC-3 misfires there
  too. Known defect (req #4), blocks spec-completeness; also tracked as
  P4-7 (`docs/design/permanent-limitations-register.md` §D addendum).
- Documentation-only: clarified the P1-2 report-message scope excludes
  CSU^C09-C12 (clinical-trials results, CH07 §7.7.2) for now, which can
  only under-fire; marked the superseded P1-1 "OBR-7 is now `messageCode
  = ORU`" notes as widened by P1-2; pinned OBR-2/OBR-3 ORC-absent scope to
  ORU/ORF with a regression test (v2.4 OUL^R21, no ORC, empty OBR-2/OBR-3
  raises nothing).

### Fixed — P1-5: OBR optionality follows each version's print

- OBR-1, 8, 9, 10, 11, 20, 21, 26 and 32 were `C` on v2.3 to v2.6, a value
  carried from an earlier baseline. They are now `O` as printed (v2.3
  keeps OBR-1 `C`; v2.6 OBR-32 is `B`, so a populated one warns).
- ORC-8 and OBR-29 stay `C` from the child-order prose; the deviation from
  the printed `O` is documented.

### Changed — P1-4: OBR-29 child-order predicate simplified

- The OBR-29 condition's first leg (`ORC-1 = CH AND ORC absent`) could
  never be true and is removed on v2.3 to v2.6. Behaviour is unchanged.

### Fixed — P1-3: OBR-2 / OBR-3 required when an ORU or ORF has no ORC

- With no ORC, `ORC-2 empty` failed safe and never fired, so a result with
  no order number anywhere passed. OBR-2 and OBR-3 now also fire when the
  ORC is absent in an ORU or ORF (v2.3 to v2.6).

### Fixed — P1-2: OBR-7 / OBR-25 apply to every report message

- "Required in a report message" was modelled as ORU only. It now covers
  each version's report structures: ORU and ORF (v2.3, v2.3.1), plus OUL
  (v2.4, v2.5.1), plus OPU (v2.6); ORU, OUL and OPU on v2.8.2, where ORF
  is withdrawn.

### Fixed — P1-1: OBR-7 / OBR-14 no longer fire on new orders

- OBR-7 and OBR-14 fired `conditionalFieldMissing` on conformant new orders
  because OBR-15 (where a specimen *should be* obtained) or an SPM segment
  was read as "a specimen was sent along". Those legs are removed on every
  version. OBR-7 keeps its report-message rule. OBR-14 is a bare `C` on
  v2.3 to v2.4, and `B` on v2.5.1 and v2.6 as printed (SPM-18 favoured).

### Added — M33: the EI half of the NASH transport assertion

- Under the same `ValidationOptions.auNASHTransport`, **HL7au:00044.3.4**
  (the EI Universal ID must be `"1.2.36.1.2001.1003.0."` + the 16-digit
  HPI-O) and **HL7au:00044.3.3** (its type must be `"ISO"`) now apply
  datatype-wide on EI, as the ADRM's "EI datatype conformance points"
  grouper states — reaching ORC-2/-3/-4 and OBR-2/-3 on the AU profile.
- The scope objection recorded by M32 was wrong and is retracted: the
  sentence constrains the *shape* of the universal ID, not whose HPI-O it
  is ("must contain the HPI-O", not "the sender's"), so an identifier
  echoed from another organisation carries that organisation's HPI-O and
  satisfies the rule unchanged. The 1 distinct EI universal ID the ADRM
  prints satisfies it.
- `ComponentPattern.allowEmpty` (internal, default `false`): the EI rules
  set it, because HL7au:000006 / 000007 already require all four EI
  components on all five AU EI fields, so firing on an empty universal ID
  would report one defect twice. MSH-4 / MSH-6 keep `false` — HL7au:000043.1
  states a whole required form there and no completeness rule covers it.
- `CompositeOverride.componentPatterns` (internal): the composite twin of
  the field-level collection M32 added.

### Changed

- `scripts/extract-adrm-conformance.py` can now discriminate a repeated
  conformance identifier by its text. The ADRM numbers **two** rows
  `HL7au:00044.3.4` — the EI Universal ID rule and a vendor-certificate
  rule — and only the first ships. Counts move to 72 shipped / 14 partial /
  15 base / 8 registered / 77 out.

## [3.13.0] — 2026-09-23

### Added — M32: AU NASH transport assertion

- `ValidationOptions.auNASHTransport: Bool` (default `false`; set by
  mutation). ADRM-2021 gates its HD addressing points on "when using SMD
  with NASH certificates", which no message states. Asserted under
  `HL7Locale.auLocalisation`, MSH-4 and MSH-6 are checked against
  **HL7au:00044.2.2** (Universal ID = `"1.2.36.1.2001.1003.0."` followed by
  the HPI-O, whose 16-digit width comes from **HL7au:000043.1**) and
  **HL7au:00044.2.3** (Universal ID Type = `"ISO"`). The ADRM's own grouper
  scopes the family to exactly those two fields. All 8 HPI-O OID values the
  ADRM prints satisfy the rule; the 3 remaining mentions are prose quotes of
  the root.
- `ComponentPattern` (internal): a literal prefix plus a digit count on a
  component, both taken verbatim from spec text. Deliberately not a regular
  expression — a cited prefix and a cited width are all the ADRM states. An
  empty component fails, because the rules that use one state a required
  shape; scope with `condition`, not with emptiness.
- The profile condition language gains the noun `auNASHTransport`.

### Changed

- `scripts/extract-adrm-conformance.py` now carries the caller-asserted
  verdicts, so `docs/design/m6-adrm-2021-conformance-register.md` is once
  again purely generated: the M29 and M30 rows had been hand-edited into a
  file whose header forbids it. Counts move to 70 shipped / 14 partial /
  15 base / 8 registered / 79 out, and the remaining NASH rows carry their
  specific reason instead of a shared "transport addressing / NASH PKI" —
  including `HL7au:00043.2`, which the ADRM marks as applying only to SMD
  Agent implementers.

## [3.12.0] — 2026-09-23

### Added — M29: AU pathology-sender assertion

- `ValidationOptions.auPathologySender: Bool` (default `false`; set by
  mutation). ADRM-2021 scopes HL7au:00050.1.5 (the OBX-6 Units coding
  system must be `UCUM`, Results) to "Senders (Pathology only)", a fact the
  wire does not carry. Asserted under `HL7Locale.auLocalisation`, an ORU
  OBX-6 whose third component is anything but `UCUM` reports
  `profileConstraintViolation` at OBX-6.3; units with no coding system
  count (they are not UCUM); an OBX with no units at all is silent.
  Unasserted, nothing changes. Same pattern as the M27 opt-in tier: a rule
  the wire cannot decide fires on a fact the caller supplies.
- The profile condition language gains the message-context noun
  `auPathologySender`.

### Added — M30: AU display-intended assertion

- `ValidationOptions.auDisplayIntended: Bool` (default `false`; set by
  mutation). HL7au:00044.4.3 requires the CE `<text>` component "valued as
  what is intended for display to the user", exempting locations where
  display is not intended; the locations are not on the wire. Asserted
  under `HL7Locale.auLocalisation`, a populated CE with no text reports
  `profileConstraintViolation` at CE-2 on Orders, Results and Referrals.
  The CNE and CWE text rules (44.5.3, 44.6.3) carry no carve-out and were
  already unconditional.
- `ComponentRequirement.condition` (internal): a DSL gate on one required
  component inside a composite override. Message-context noun
  `auDisplayIntended`.

## [3.11.0] — 2026-09-22

### Added — M28: XAD.7 Address Type when the field repeats

- The predicate language of `ComponentGrammar.condition` gains one token,
  `repeated`: the field has more than one populated repetition.
- v2.8.2 XAD.7 is now checked: "XAD.7 is required if there are multiple
  occurrences of XAD in a field" (2.A.87.7), reported as
  `conditionalComponentMissing` at the empty repetition. v2.5.1 and v2.6 do
  not state it and are unchanged. The spec's one v2.7+ example with two
  address repetitions (STF-11, chapter 15) is mis-delimited (the type code
  sits in XAD.6) and is recorded as such in `conditions.json`, not treated
  as a counter-example.
- The register of conditions the model cannot express is now: the coding
  system in use (CWE.7 and kin) and CNE.20's self-contradictory sentence.

## [3.10.0] — 2026-09-22

### Added — M27: the v2.7 conformance rules as an opt-in advisory tier

- `ComponentGrammar.conformanceCondition` (additive, defaulted) carries the
  32 "as of v2.7" rules M26 registered, in the same predicate language:
  CWE / CNE / CF / CSU coding system when a code is valued, CX / XCN / PPN
  assigning authority or jurisdiction when an identifier is valued, XCN.10
  name type, XCN.13 identifier type, one of XTN.4 / .7 / .12. v2.8.2, plus
  CSU.4 on v2.5.1 and v2.6.
- `ValidationOptions.conformanceConditionSeverity: IssueSeverity?`, default
  `nil`: nothing is reported unless it is set. Set it and each holding rule
  on an empty component is reported as the new
  `IssueCode.conformanceConditionMissing` at that severity; where the spec
  states one sentence per component (CX.4 / .9 / .10), one issue per
  component. `checkComponentGrammar = false` suppresses it.
- `Resources/datatypes/conditions.json`: the `notModelledAsOfV27` block is
  now `conformanceRules` and is applied by the extractor. Default validation
  output is unchanged.

## [3.9.0] — 2026-09-22

### Added — M26: conditional components, where the spec states the condition

- `ComponentGrammar.condition` (additive, defaulted) carries, for a
  component the table prints `C`, the condition its prose states, in a small
  predicate language over sibling components (`"5 populated"`,
  `"1 populated AND 9 empty AND (10 empty OR 11 empty)"`). New
  `IssueCode.conditionalComponentMissing`, reported at the component when
  the predicate holds and the component is empty, at
  `requiredComponentSeverity`; `checkComponentGrammar = false` suppresses it.
- **36 rules modelled**, each hand-authored from its sentence and cited in
  `Resources/datatypes/conditions.json`: RPT.6 / RPT.10 (units required when
  the quantity is populated), CSU.2 / CSU.3 (identifier or description),
  CNN.8 / .10 / .11, CP.5, XCN.1 / XCN.2 (v2.8.2), and the value-set-version
  rules of CWE / CNE / CF / CSU. One level of nesting is descended (the CNN
  inside NDL). Every rule was checked against the spec's own printed
  examples first, and the datatype-example audit now evaluates them.
- **32 rules registered, not modelled, with the measurement:** the "as of
  v2.7" family (a coding system when a code is valued, an assigning
  authority when an identifier is valued, a name type, an identifier type,
  one of XTN.4 / .7 / .12). Against the spec's own 78 v2.7+ example
  messages, CWE.3 / .14 are violated by 529 of 549 values, XCN.9 / .13 /
  .22 / .23 by 43 of 43, XTN.4 / .7 / .12 by 117 of 118, CX.4 / .9 / .10 by
  115 of 185. Enforcing them would reject the standard's own messages; they
  wait for an advisory tier.
- Also registered: coding-system-aware conditions (CWE.7 and kin), XAD.7 (a
  repetition-count condition), CNE.20 (self-contradictory text), and the
  `C` components whose prose states no condition.

## [3.8.0] — 2026-09-22

**Additive API: `FieldGrammar.length` and `ComponentGrammar.length` carry each version's printed LEN verbatim, never enforced.** Every attribute-table column is now recorded and audited against its own version's print.

### Added — M25: printed lengths recorded on every field and component

- `FieldGrammar.length` and `ComponentGrammar.length` (additive, defaulted)
  carry the LEN cell each version's attribute or component table prints,
  verbatim: `"250"` before v2.7; from v2.7 the normative forms `"2..2"`,
  `"32="` (truncation allowed) and `"250#"` (not allowed). 9,892 field
  lengths and every printed component length; `nil` where the table prints
  none (v2.8.2 prints only a conformance length for most composite fields;
  the v2.3 to v2.4 prose prints none).
- **Never enforced.** Before v2.7 the spec calls the maximum length "not of
  conceptual importance"; from v2.7 enforcement would need the truncation
  and conformance-length semantics of Chapter 2.5.5, which nothing models
  yet. Recorded for the integrator reading the grammar as a reference.
- Schema key `length` (verbatim string) and `audit-schemas.py --depth`
  predicate `length`, with `--write-lengths`; the datatype extractor emits
  `length` and the datatypes audit checks it for drift. **Every column of
  the attribute tables is now recorded and audited against each version's
  own print.**

## [3.7.3] — 2026-09-22

**Fixes only; no API change.** Four v2.3 tables printed only in its chapters are now in the registry, so a bad universal ID type is checked on v2.3 messages too.

### Fixed — M24: four v2.3 tables the registry lacked; the 39 unbound prose mentions read

- v2.3 prints Tables 0298, 0299, 0301 and 0336, with their rows, in the
  chapters that define the datatypes and omits them from Appendix A, the
  only v2.3 PDF the table extractor reads. Measured across all v2.3 chapters:
  those four are the only tables printed with rows and absent from the
  registry (v2.3.1 and v2.4 have none). A cited override can now CREATE a
  table (`createName`); the four are transcribed from the chapters.
- With them, three more v2.3 prose bindings meet the evidence rule: `HD.3`
  and `EI.4` to 0301 (so a bad universal ID type is now checked on v2.3
  messages too) and `CP.6` to 0298.
- The remaining 36 rejected mentions were all read. They are: the HD-typed
  components whose "0300 / 0363" belongs to the HD's own first subcomponent
  (never enforced: IS, user-defined); user-defined tables v2.3 names but
  never prints (0300, 0302 to 0308, 0333, 0335, 0297); and real misprints
  (v2.3 `QSC.4` "0102", `XCN.8` / `PPN.8` "0207", `JCC.2` "0329", `XCN.12` /
  `PPN.12` "0060", v2.3.1 `DLN.2` "0333"). None can be bound; all stay
  unbound, which is an absent check and not a false error.

## [3.7.2] — 2026-09-22

**Documentation and tooling only; no behaviour change.** The spec's example messages are fully triaged.

### Docs — M23: required-field errors on the spec's example messages triaged

- The 106 `requiredFieldMissing` errors the Validator reports on
  version-consistent example messages were read against the print and the
  examples. All are the example's fault: a value printed one field over
  (`SCH-7` carrying the reason `SCH-6` requires, `PID-6` carrying the name
  `PID-5` requires) or simply omitted (`MSH-7` in 60 printed messages,
  `OBX-11`, `DG1-6`). Each field is printed `R` in its own version, which the
  optionality audit (M19) already proved. No rule changed; the triage tool
  now ranks this class too and records the conclusion.

## [3.7.1] — 2026-09-22

**Fixes only; no API change.** 19 fields carried another version's repeatability: 14 false cardinality errors removed, five checks added.

### Fixed — M22: 19 fields carried another version's repeatability

- The depth audit now compares every field's repeatability with the RP/#
  column its own version prints (a printed Y or a bounded count such as
  "2" is `*`; blank is `1`). First run: 19 disagreements.
  - **False `cardinalityExceeded` removed** on v2.3 (`PID-6`, `PID-10`,
    `PID-22`, `AL1-5`, `EVN-5`, `ORC-7`, `ORC-10..12`), v2.3.1 (`ORC-7`) and
    v2.8.2 (`ERR-1`, `PD1-4`, `PID-4`, `PID-9`): these print no repeat.
  - **Missing checks added:** v2.3 `LCC-3` / `LCC-4`, v2.6 `PID-38`
    (printed "2"), v2.8.2 `LRL-5` and `OBX-28` repeat.
- Extractor: a `Y` printed under the TBL# header is the RP cell, not a table
  number (v2.6 ERR-9 / 11 / 12 had lost their repeatability in extraction).
- With OPT (M19), NAME (M20) and RP (M22), every attribute-table column that
  drives validation is now audited against each version's own print.

## [3.7.0] — 2026-09-22

**Additive API: `ValidationOptions.requiredComponentSeverity` lets a consumer report missing required components (such as `MSH-9.3`) as warnings instead of errors.** Also 185 field names corrected, 22 nameless fields named, and v2.8.2 `ITM-33` added (M20).

### Added — M21: `ValidationOptions.requiredComponentSeverity`

- The severity of every ``requiredComponentMissing`` finding is now the
  consumer's choice: `.error` (default, unchanged) or `.warning`, which keeps
  the findings and leaves the report valid. Covers the printed-`R` rule and
  the `HD` either-or rule; nothing else. `checkComponentGrammar = false`
  still suppresses the findings entirely.
- Resolves the `MSH-9.3` question raised in M18: v2.5+ prints the message
  structure as required and the base rule stays faithful to that, while a
  consumer of feeds that omit it (as half the spec's own v2.5.1 examples do)
  has a documented switch that does not special-case one field. Additive
  API (minor).

### Fixed — M20: 185 field names and one missing field, found by a NAME predicate

- The depth audit now compares every field's name with the ELEMENT NAME the
  version's own attribute table prints (normalised; a printed name may run
  on into glued prose; spaces are ignored for equality). First run: 159
  findings plus 22 fields with NO name at all.
  - **110 names cut at their left edge** ("nistration Sub-ID Counter",
    "lls Remaining") on the pharmacy segments of v2.3.1, v2.4 and v2.8.2 and
    v2.4 LOC / v2.3 QRF; **22 pharmacy fields nameless**; these reached the
    generated `FieldGrammar` names and every validation message that quotes
    a field name.
  - **v2.3 / v2.3.1 names copied from v2.5.1** where the older version
    prints another name (`PID-3` "Patient ID (Internal ID)", `PID-8` "Sex",
    `AL1-2` "Allergy Type", `OBR-4` "Universal Service ID").
  - **v2.8.2 `ITM-33` was missing.** The chapter prints its SEQ on the line
    below the row, so the extractor glued row 33 onto row 32 and the depth
    audit counted the same 32 fields as the schema. The extractor now
    recognises a SEQ printed below its row; ITM gains its 33rd field.
- Extractor fixes: a wrapped name continuation is cut at the row's own name
  column, not where the header centred "ELEMENT NAME" (v2.3.1 RXE-21 read
  "Dispensing Instructions" as "tructions"); a range SEQ row ("3-n") is no
  longer glued onto the previous field's name (QPD-2).
- `audit-schemas.py --depth --write-names` corrects names from the print,
  preferring the candidate the other chapters agree on. Typed accessor
  names (`swiftName`) are unchanged; no API change.

## [3.6.5] — 2026-09-22

**Fixes only; no API change.** 30 fields carried another version's optionality: one false error (`MSH-7` on v2.3 / v2.3.1), 21 false deprecation warnings, seven too-lenient v2.6 fields.

### Fixed — M19: 30 fields carried another version's optionality

- The depth audit checked field count, presence, datatype and table bindings
  against each version's attribute table, but never the OPT column. A new
  `optionality` predicate does. First run: 30 disagreements across ~13,000
  fields, all values copied from a later version:
  - **False errors:** `MSH-7` was `R` on v2.3 and v2.3.1, which print it `O`
    (it becomes `R` in v2.4). A v2.3 message without a message timestamp was
    rejected.
  - **False deprecation warnings:** 21 fields marked `B` on v2.3 / v2.3.1 /
    v2.4 that those versions print as ordinary `O` (`PID-2`, `PID-4`, `PID-9`,
    `PID-19`, `PID-20`, `PID-28`, `AL1-6`, `ORC-7`, `OBR-15`, `OBR-27`), each
    also named "... (deprecated)"; optionality and name corrected.
  - **Missing checks on v2.6:** `DG1-3` is `R` (was `O`); `MSA-5` is `W` (was
    `B`); `OBR-33` / `OBR-34` / `OBR-35`, `PD1-12` / `PD1-13` are `B` (were `O`).
- Anything involving `C` is left to the conditional-completeness register.
  v2.3 / v2.3.1 `DG1-2` is printed "(B) R" and is whitelisted with that note.
- Found while triaging the spec's example messages (M18): `MSH-7` was the
  most frequent "missing required field" on v2.3-era examples.

## [3.6.4] — 2026-09-21

**One fix and tooling; no API change.** Waveform value types `NA`, `MA` and `CD` are no longer rejected in OBX-2 (a false error since `v3.3.0`); the spec's 616 example messages can now be run through the Validator.

### Fixed — waveform value types rejected in OBX-2 (since v3.3.0)

- HL7 Table 0125 omits `NA`, `MA` and `CD` on v2.3 to v2.6, yet Chapter 7's own
  normative text directs them into OBX-2: "The data type of the WAV category
  result segment can be NA (Numeric Array) or MA (Multiplexed Array)" and
  "for the CHN category, OBX-2 should be valued to CD". v2.8.2 corrects the
  table. As a closed table it rejected every spec-directed waveform
  observation. The three are restored by cited override on the five versions.

### Added — M18: the spec's example MESSAGES, run through the Swift Validator

- `scripts/extract-example-messages.py` reassembles the complete example
  messages the chapters print (616 across six versions; segments wrap over
  several lines) into a local JSON file. `SpecExampleMessageTests`, enabled
  by `SPEC_EXAMPLE_MESSAGES`, validates each end to end and writes a report;
  `--triage` ranks the table rejections worth a look. The spec text stays out
  of the repository, like the PDFs.
- **A triage source, not a must-pass oracle.** Unlike the datatype examples,
  the printed messages are informative and often wrong themselves: half
  carry a stale MSH-12 (a v2.6 chapter printing `|2.4|`), many are truncated
  with `...` or have fields shifted by one, and they produce 701
  missing-required-field errors. Triage is restricted to examples whose
  declared version matches their chapter. After the fix above, every
  remaining table rejection is example damage.
- **Observed, not changed:** 35 of the 68 examples that declare v2.5.1 omit
  `MSH-9.3`, which the MSG component table prints as `R` and v3.6.0 enforces.
  The MSH-9 prose is silent on the point, so the normative table stands;
  recorded as an owner decision in STATUS.

## [3.6.3] — 2026-09-21

**Two fixes and a standing audit; no API change.** Every composite example the datatype chapters print is now checked against the component rules; doing so found `NA.1` wrongly required and `AHS` wrongly rejected.

### Added — M17: the spec's printed examples are a permanent audit

- `scripts/audit-schemas.py --examples` runs every pipe-delimited composite
  example the datatype chapters print (352 example repetitions across the
  six versions) through the component rules: a component printed `R` must
  be valued, and an `ID` component or nested subcomponent on a closed table
  must carry one of its codes. Any rejection is a finding unless it is in a
  cited exception list. Proven to fail on an injected fault.
- Three registered exceptions, where the example and not the rule is at
  fault: the v2.3 XON example omits its check digit, so every later
  component sits one place early; and two v2.8.2 XTN lines are fragments
  printed inside a component's description, not complete values.

### Fixed — two more rules that rejected the spec's own examples

- **`NA.1` is not required** on v2.5.1 and v2.6. The table prints `R`, but the
  same section says "arrays that have one or more values not present may be
  transmitted" and prints `|^2^3^4~5^^^8~9^10~~17^18^19^20|`; v2.8.2 corrects
  the table to `O`. New `Resources/datatypes/overrides.json` (cited, applied
  by the extractor).
- **`AHS` accepted in Table 0528** on v2.5.1, v2.6 and v2.8.2. The table prints
  `HS`; the RPT section's own example carries `AHS` in RPT.8.

## [3.6.2] — 2026-09-21

**One fix, one spec-stated check; no API change.** The spec's own HD example using `RANDOM` is no longer rejected (a false error since `v3.5.0`), and an `HD` with a universal ID now needs its type.

### Fixed — a false error on the spec's own HD example (since v3.5.0)

- HL7 Table 0301 prints the code `Random`; the HD section's own example is
  `^40C983F09183B0295822009258A3290582^RANDOM` (v2.3.1, v2.4, v2.5.1, v2.6).
  Codes are matched exactly, so the HD.3 check rejected the spec's example.
  The example's spelling is added beside the printed one by cited override.
- Every HD example the spec prints in its HD section is now a must-pass test.

### Added — M16: HD's universal ID and its type are valued together or not at all

- "The second and third components must either both be valued (both
  non-null), or both be not valued (both null)", printed by all six versions.
  `LAB1^1.2.3` and `LAB1^^ISO` now report `requiredComponentMissing` at the
  field; `LAB1`, `^1.2.3^ISO` and `LAB1^1.2.3^ISO` are valid. Registered in
  M15, shipped here. No fixture fallout.
- No API change: `RequiredComponentSet.Semantics.allOfGroupOrAtLeastOne` now
  fails on a partially populated group; HD is its only user.

## [3.6.1] — 2026-09-21

**Fixes only.** Three false "required component" errors are gone: a structured phone number (`XTN`), a location with only its person location type (`PL`), and an uncoded `CWE` with only its text. Each rejected an example the spec itself prints.

### Fixed — M15: three either-or component rules rejected the spec's own examples

- The five hand-written either-or rules were checked against the spec's
  prose and examples, which are now must-pass tests:
  - **`XTN` ("XTN-1 OR XTN-4 OR XTN-12") removed.** v2.5.1 sec 2.A.89 prints
    the fax example `^ORN^FX^^^734^6777777` and recommends that delimited
    form as of v2.3; the rule reported it, and every structured phone number,
    as an error.
  - **`PL` ("PL-1 OR PL-4") removed.** The definition says "for a patient
    treated at home, only the person location type is valued".
  - **`CWE` ("CWE-1 OR CWE-9") removed.** Usage case b) "Uncoded: Text is
    valued, the identifier has no value", example `^Wesnerian^SNM3^^^^3.4`.
  - **`EIP` ("EIP-1 OR EIP-2") removed** as vacuous: any populated
    two-component field satisfied it.
  - **`HD` kept**: "either as a local identifier (with only the namespace ID
    valued) or ... a UID (universal ID and universal ID type both valued)".
- Registered, not shipped: the HD prose also says components 2 and 3 "must
  either both be valued ... or both be not valued"; with HD-1 present that
  half is not checked (an absent check, not a false error).
- `XTN.requiredComponentSet`, `PL`, `CWE` and `EIP` are now `nil`.

## [3.6.0] — 2026-09-21

**Read this first if you validate v2.5.1 or later messages: `MSH-9` now needs all three components (`ADT^A01^ADT_A01`), because the spec prints them as required from v2.5.** In the other direction, eight false "required component" errors are gone (an address with no street line, a name with no family name). v2.3 to v2.4 messages are unaffected. No API change.

### Fixed — M14: eight "required component" rules contradicted the spec they cited

- The Validator took required components from hand-written per-type lists,
  applied to every version. Audited against the extracted component tables,
  eight contradict v2.5.1's own print, where the component is `O`: `XAD.1`
  street address, `XPN.1` family name, `XCN.1`, `XON.1`, `CE.1`, `EI.1`,
  `PT.1`, `VID.1`. An address such as `^^Sydney^NSW^2000`, or a name with
  only a given name, was reported as an error against the spec (req #4).
- Required components now come from `DataTypeGrammarTable` for the
  message's own version: exactly the components its table prints as `R`.
  v2.3 to v2.4 print no component optionality, so nothing is required of
  them at component level. Either-or sets (`HD`, `CWE`, ...) are unchanged.

### Changed — spec-required components are now enforced (v2.5.1 and later)

- **`MSH-9` needs all three components from v2.5**: `ADT^A01` must be
  `ADT^A01^ADT_A01`. The spec prints `MSG.1`, `MSG.2` and `MSG.3` as `R`; the
  old list required only `MSG.1`, noting the structure is "often left
  empty". Also newly required where printed: `CX.5`, `PT.1`, `VID.1`, `XTN.3`
  on v2.8.2; `ED.2` / `ED.4` / `ED.5`, `TS.1` and the `R` components of the
  other printed datatypes.
- 48 synthetic fixtures and the shared test headers gained their message
  structure, taken from v2.5.1 Table 0354 (A01 / A04 / A08 use `ADT_A01`);
  two ACK fixtures gained trigger event and structure. PHI scan clean.
- `XPN.requiredComponents` and its ten siblings now hold what v2.5.1 prints
  (eight became empty; `MSG` became `[1, 2, 3]`) and are informational.
- Eight tests that asserted the old behaviour now assert the spec's; one
  test pins the v2.8.2 difference (`PT.1` required there).
- Suppress with `checkComponentGrammar = false` (the `lenient` preset does).

## [3.5.0] — 2026-09-21

**Component checks on every version, the AU VMR sub-ID tree, and fixes for two false errors in tagged releases** (HD.3 `L` / `M` / `N` in `v3.4.0`; AU OBX-2 `CWE` / `DR` since `v3.3.0`). Additive API: `IssueLocation.subcomponentIndex`.

### Added — M13-B: the component check runs on v2.3, v2.3.1 and v2.4

- `DataTypeGrammarTable` answers for all six versions; the component-level
  `valueNotInTable` rule now applies to the older three under their own,
  prose-derived grammar (18 / 25 / 35 enforceable components). No fixture
  fallout.
- Each version's own facts decide: Table 0203 is user-defined until v2.5, so
  an unknown `CX.5` identifier type is an error only from v2.5.1.

### Fixed — AU locale false errors (one live since v3.3.0)

- **OBX-2 of `CWE`, `DR`, `CNE` or `EI` was rejected under the AU locale.**
  ADRM-2021 Table 0125 (p. 237) prints them; base v2.4 does not. OBX-2 has
  been enforced at field level since v3.3.0, so this has been wrong since
  then, including for the ADRM's own VMR examples. The ADRM rendering is now
  on the locale table axis.
- **A universal ID type of `AUSNATA` would have been rejected** once v2.4
  components were checked (`QML^2184^AUSNATA` in MSH-4). ADRM-2021 Table
  0301 (p. 161) adds AUSHICPR, AUSHIC, AUSDVA, AUSNATA and AUSLSPN as
  daggered Australian extensions; added to the locale axis before enabling.
- Found by sweeping every closed table enforced on v2.4 against the ADRM's
  own print of it. Those were the only two with codes base v2.4 lacks.

### Added — M13-A: datatype component grammar recovered from prose for v2.3, v2.3.1, v2.4

- These versions print no component tables, but every composite has a
  numbered section whose components each get a numbered subsection
  ("2.9.12.5 Identifier type code (ID)"). `scripts/extract-datatype-prose.py`
  reads index, name and datatype from those headings and writes
  `Resources/datatypes/v2.3`, `v2.3.1`, `v2.4` (105 datatype files, 575
  components), marked `"source": "prose"`.
- **A table binding must pass three tests:** exactly one table is named in
  the subsection; that number is in the version's own registry; and, when
  the prose states the table's name, it matches the registry's name. The
  third test caught real misprints: v2.3 sec 2.8.31.4 binds QSC.4 to "HL7
  table 0102 - Relation conjunction", but v2.3's 0102 is Delayed
  Acknowledgment Type, a closed table that would have rejected AND / OR.
  Anything that fails is left unbound: an absent check, never a wrong one.
- **Measured:** every surviving binding with a v2.5.1 counterpart agrees
  with v2.5.1's printed component table (28 / 48 / 70 on the three versions,
  zero conflicts). 168 bound components; 39 mentions rejected.
- Version differences the prose preserves: CX.5 is `IS` in v2.3 and v2.3.1
  and `ID` from v2.4; XCN.13 and XON.7 are `IS` in v2.4. Table 0203 itself is
  user-defined until v2.5, so identifier types are never enforced before it.
- `audit-schemas.py --datatypes` is prose-aware (no optionality, optional
  datatype code, no trailing note subsections; prose re-extraction drift).

### Added — M12: the AU HL7v2 VMR sub-ID tree (ADRM-2021 Appendix 9, Normative)

- New profile model track `SubIDTreeRule` and three AU rules, reported as
  `profileConstraintViolation` at the offending `OBX[n]-4`:
  **ADRM-prose:P-8** an observation whose sub-ID shares the VMR header's
  root must instantiate a row of the implementation table (p. 515);
  **P-9** a STRUCTURAL row, purely virtual, must not be written as an OBX;
  **P-10** the header's own sub-ID must be dotted decimal (p. 490).
- Scope is the observation group (the OBX run after one OBR). A group with
  no VMR header is never touched, so a structured pathology report using
  `1.x` sub-IDs is unaffected. The root is read from the header, not assumed
  to be 1. AU locale and REF messages only, the same gate as P-6.
- Proven not to fire on the appendix's own worked examples (pp. 363, 516),
  which are the must-pass test.
- Registered, not shipped: the table's OBX-2 / OBX-3 columns (the appendix's
  example contradicts both) and its OCCURRENCES column.
- Codegen emits the table as internal Swift
  (`Locale/Generated/VMRImplementationTable+au_adrm_2021.swift`); the
  regenerate script and CI drift check cover it.

### Added — M12-A: the AU VMR implementation table extracted (2026-09-21)

- `Resources/profiles/au-adrm-2021/vmr-table.json` — the 89 rows of ADRM-2021
  Appendix 9 table A9.T.1 (pp. 492-515): element name, OBX-2, the OBX-4
  sub-ID path (`RepeatOf[...]` becomes `*`), occurrences, VMR datatype.
  Written only by `scripts/extract-vmr-table.py`.
- OBX-3 and the suggested OBX-5 values are deliberately NOT extracted: the
  appendix's own worked example (p. 516) contradicts the table on OBX-2 (CE
  for CWE) and OBX-3 (70949-3 for 73983-9), so neither can back a rule.
- `scripts/audit-schemas.py --vmr` (shape, unique rooted paths, and the
  appendix's own invariant that a row is unbounded exactly when its path ends
  in a repeat marker; re-extraction drift with `--depth`).

### Added — M11: nested composites and OBX-5 in the component check

- A component that is itself a composite is descended into once: the HD in
  `CX.4` makes `CX.4.3` a checked universal ID type (0301). 46 nested sites
  on v2.5.1, 28 on v2.6, 27 on v2.8.2.
- `IssueLocation.subcomponentIndex` (additive); the path reads
  `PID[1]-3.4.3`.
- OBX-5 is checked under the datatype OBX-2 declares; the resolution is now
  one shared helper with the AU composite overrides.
- No fixture fallout. ADR-017 addendum; limitations register and DocC updated.

### Fixed — a false error in v3.4.0: HD.3 of `L`, `M` or `N` was rejected

- HL7 Table 0301 (Universal ID type) prints the three local-scheme codes in
  ONE row, `L,M,N`. Extracted as a single code, the closed table rejected a
  valid universal ID type of `L`, `M` or `N` wherever HD is a field's own
  datatype (MSH-3 to MSH-6 and the like) once v3.4.0's component check went
  live. Split into three rows by a cited override on the five versions that
  print the table. It is the only comma-joined code in the registry; the
  audit's suspect-code test now flags a comma.

## [3.4.0] — 2026-09-21

**The component-table release: M10, code tables on composite components (ADR-017).** Additive API; the default code-table check now reaches `ID` components on v2.5.1 / v2.6 / v2.8.2 messages.

### Docs

- ADR-017; design index; limitations register (component links shipped, the
  remaining gaps registered); DocC `Validation.md` and `Migration.md`;
  fixtures README corrections log; STATUS / NEXT_STEPS / ROADMAP closed out.

### Added — M10-C: code-table check on composite components (2026-09-20)

- `valueNotInTable` now also fires for a populated `ID` COMPONENT bound to
  exactly one closed HL7-defined table, located at the component
  (`PID[1]-3.5`). Examples: CX.5 identifier type (0203), XPN.7 name type
  (0200), XTN.2 / XTN.3 (0201 / 0202), XAD.7 address type (0190), HD.3
  universal ID type (0301). About 50 components per version qualify.
- Same guards as the field rule: `IS` components and user-defined or open
  tables are never enforced (MSG.3 / 0354 is open, so an unusual message
  structure is never rejected); empty and HL7-null values are never checked;
  a locale's rendering widens the check (AU ADRM-2021 prints `NOI` in 0203).
- Applies to v2.5.1, v2.6 and v2.8.2 messages only: earlier versions print
  no component tables, so nothing fires there. One level deep: a component
  that is itself composite (the HD inside CX.4) is not descended into.
- Suppressed by `checkCodeTables = false` and the `lenient` preset.
- **Fallout traced: a real defect in 13 synthetic fixtures.** Each carried the
  ordering provider (`DR12121212^Foster^Taylor`, an XCN) in OBR-17, the
  callback phone number, with OBR-16 empty. Moved to OBR-16; logged in the
  fixtures README; PHI scan clean.

### Fixed — code-table registry defects found while vetting component enforcement (2026-09-20)

- **v2.8.2 tables with non-standard column headers extracted EMPTY in
  v3.3.0:** 0354 Message structure ("Value / Events"), 0440 Data types, 0209
  Relational operator, 0210, 0227 and 0292 ("Code / ..."). The line under a
  table caption is now the column header whatever it says, and the table's
  own header, reprinted after a page break, resumes its rows (0354 went
  0 -> 243). No false error was possible in v3.3.0, because an empty table
  is never enforced; the registry was simply incomplete.
- **Table 0354 is no longer treated as closed, on any version.** Measured:
  15 to 25 message structures used by each version's own chapters are absent
  from its printed table (v2.5.1 Chapter 15 defines `RSP^K25^RSP_K25`;
  Appendix A omits it). Opened by override with that evidence cited.
- **v2.5.1 Table 0210 restored to AND / OR.** Appendix A drops OR; the
  defining table in Chapter 2A prints it. New `addEntries` override.
- **Mis-decoded no-break space:** v2.6 0550 carried `CHEST` and `KIDN` with a
  trailing U+00C2 and one lone corrupt row; eight descriptions read
  "2Â½ hours" / "LOINCÂ®". Restored in the extractor; the audit's mojibake
  test now includes that character.
- Four regression tests.

### Added — M10-B: per-version datatype grammar (2026-09-20)

- `DataTypeGrammarTable.grammar(_:version:)` returns a `DataTypeGrammar`
  (code, name, components) whose `ComponentGrammar` entries carry index,
  name, datatype, the printed optionality code and the bound table numbers.
  Generated from `Resources/datatypes/` into
  `Sources/HL7v2Kit/DataTypes/Generated/`, one constant per datatype; the
  regenerate script and the CI drift check cover the new directory.
- The optionality is kept as the printed code (`optionalityCode`): v2.8.2
  XPN.1 is `RE`, which `FieldOptionality` cannot express, and mapping it
  would misstate the spec.
- v2.3, v2.3.1 and v2.4 return `nil`: they print no component tables.

### Added — M10-A: datatype component tables extracted (2026-09-20)

- `Resources/datatypes/v{2.5.1,2.6,2.8.2}/<DT>.json` — every "HL7 Component
  Table" of Chapter 2A: 227 datatype files, 1,323 components, each with its
  name, datatype, optionality and the table numbers its TBL# cell binds
  (437 bound components; CX.5 -> 0203, CE.3 -> 0396, and so on). Data only
  in this stage; codegen and the component-level membership check follow.
- `scripts/extract-datatype-components.py` is the only author of those files.
  Rules verified against the print: a name can start under the TBL# header
  (v2.5.1 AD), a withdrawn component prints no datatype (v2.6 XTN.1), v2.5.1
  MA prints its first row without a SEQ number, and v2.6 LA2 prints table
  numbers without the leading zero (302 for 0302).
- `scripts/audit-schemas.py --datatypes` (shape, table resolution; with
  `--depth`, re-extraction drift). `9999` is the spec's "no table assigned"
  sentinel from v2.7 and is accepted as such.
- **Scope:** v2.3, v2.3.1 and v2.4 define components in prose and print no
  component tables; they are out of this cycle. Datatypes v2.8.2 prints as
  WITHDRAWN (CE, TQ, TS, ELD, LA1, LA2, OSD, SPS) are absent there by design.

## [3.3.0] — 2026-09-20

**The code-table release: M9, the code-table registry (ADR-016), with the 1-n variable-column model.** Additive API; one new check is on by default (see Changed).

### Added — public API summary (ADR-016)

- `HL7Table` (number, name, `Kind`, `permitsLocalExtensions`, entries with
  descriptions, `codes`, `contains(_:)`, `isClosed`) and `HL7TableRegistry`
  (`table(_:version:)`, `table(_:locale:)`).
- `FieldGrammar.table`, `IssueCode.valueNotInTable(table:)`,
  `ValidationOptions.checkCodeTables` (default `true`).
- `FieldGrammar.variableColumns` and the plural accessors `RDT.columnValues` /
  `ADD.addendumContinuationPointers`.
- `Resources/tables/` (2,565 per-version tables + 5 AU locale tables),
  `scripts/extract-code-tables.swift`, `scripts/backfill-schema-tables.py`,
  and the `--tables` pass of `scripts/audit-schemas.py`.

### Changed

- **`valueNotInTable` is on by default** for `ID` fields bound to a closed
  HL7-defined table (1,073 fields). Messages that carried an out-of-table
  value there used to pass. Suppress with `checkCodeTables = false`.
- `ValidationOptions.lenient` now turns the code-table check off, as its
  documentation always promised ("only structural checks"); it was left on.
- `HL7CodeTables` (internal) reads the AU tables from the registry's locale
  axis instead of hand-written arrays.

### Docs

- ADR-016; design index; `permanent-limitations-register.md` (M6-O6 row
  shipped, composite-component links registered in section C); dated
  addendum under M6-O6 in the M6 audit; DocC `Validation.md` and
  `Migration.md`; `the working notes` regeneration note.

### Added

- **Track B — SEQ 1-n variable-column segments modelled.** New schema key
  `variableColumns` on RDT-1 (all six versions) and ADD-1 (v2.3–v2.5.1) →
  `FieldGrammar.variableColumns` + plural accessors `RDT.columnValues` /
  `ADD.addendumContinuationPointers` (`[Field]`). The Validator applies the
  field's grammar to every column; column 1 keeps the row's optionality,
  later columns are individually optional and single-cardinality (spec RP
  blank). Additive; the depth-audit whitelist stays (extractor limitation).

### Added — M9-A: HL7 table bindings in every schema (M9, the code-table registry cycle, opened)

- **Schema key `tables`** — every field the spec binds to an HL7 table now
  carries `"tables": ["NNNN", ...]`, taken from that version's own attribute
  table (TBL# column). A list, because the spec binds more than one table to
  some fields (`NK1-11` 0327/0328, `OBR-15` 0070/0163/0369, `LCH-5`
  0136/0262/0263). 4,290 bindings across 724 of the 853 schemas; every schema
  edit is additive (proven by diffing each file against its pre-sweep JSON
  with `tables` removed). The key is data-only in this stage: codegen ignores
  it and the generated sources are unchanged. `FieldGrammar` exposure and the
  validator membership rule are M9-C / M9-D.
- **Audit predicate `tables`** (`scripts/audit-schemas.py --depth`) — a
  schema's `tables` must equal the spec's TBL# cell in both directions. A
  malformed extracted cell is a finding until it carries a hand-verified,
  cited entry in the new `scripts/table-repairs.json` (26 entries: the
  v2.3.1 PCR rows 5-23 whose columns shift after a headerless page break,
  RP-flag bleed on LCC-3 / ERR-12 / LRL-5, the non-numeric `*` and `----`
  cells on v2.4 ROL-9 / STF-14, the mid-number wrap on v2.5.1 OM1-44, and
  v2.3.1 NSC-1, whose segment is depth-whitelisted so takes repairs only).
  `--write-tables` performs the sweep and verifies what it wrote.
- **Verification beyond shape.** Cross-version sandwich check (a slot unbound
  between identically-bound neighbours): one hit, v2.6 DG1-7, spec-correct
  (withdrawn, blank cell). All 18 ID/IS fields left unbound were read against
  the printed rows: the spec prints a blank TBL# for each.

### Added — A5: coded fields linked to their HL7 tables on all six versions (2026-09-20)

- **1,893 ID/IS fields now carry the enforced `table` link**, derived from the
  hand-verified `tables` bindings (M9-A) by `scripts/backfill-schema-tables.py`;
  nothing was re-extracted. **1,073 of them are ID fields on a closed
  HL7-defined table, so `valueNotInTable` is live for them.** IS fields and
  user-defined or open tables are linked but never enforced (guard test:
  PID-8). Zero conflicts and zero multi-table coded fields on any version.
- **Behaviour change to expect:** a message that carried an out-of-table
  value in an ID field used to pass and now reports an error. Set
  `ValidationOptions.checkCodeTables = false` to suppress the check.
- **A6a — locale table axis.** `Resources/tables/locale/<locale-id>/` holds a
  locale's own printed rendering of a table; `HL7TableRegistry.table(_:locale:)`.
  First table: AU ADRM-2021 Table 0211, which back-ports `UNICODE UTF-8` from
  v2.6 into its v2.4 localisation (p. 55 footnote). The Validator consults the
  locale rendering only after the message's own version table rejects a value,
  so a locale can widen the check and can never reject what the version
  prints; narrowing stays with the profile.
- **Fallout, all traced (none dismissed):** base v2.4 Table 0211 has no
  `UNICODE UTF-8`. One pure-ASCII synthetic fixture (`oru_r01_v24.hl7`) and one
  test wire declared it on a base v2.4 message; both now declare `ASCII`.
  The other five versions produced no fallout.
- **Spec typo registered:** v2.3 DB1-2 prints TBL# 0033 for 0334.

### Changed — A6b: the AU seed tables moved onto the locale table axis (2026-09-20)

- Tables 0074 / 0200 / 0203 / 0363 as printed by AU ADRM-2021 now live in
  `Resources/tables/locale/au-adrm-2021/` with the descriptions the
  localisation prints (174 rows), and `HL7CodeTables.table0074` etc. read
  from the generated registry. Value sets are identical to the hand seed
  (proven by set comparison); the AU profile tests pass unchanged.
- **Correction to the M6-B-8 record:** `UPIN` and `NOI` are NOT accommodations
  absent from the ADRM's Table 0203. They are printed there as `UPIN*` and
  `NOI**` with footnotes (p. 309: UPIN "must be used for Australian Medicare
  Provider numbers"); the footnote markers had hidden them from the original
  transcription. They now carry their printed descriptions and positions.
- `IHI` in 0363 is genuinely not printed (p. 310 lists five authorities); it
  stays, marked as an accommodation carried from the seed.

### Fixed — a 16-minute type-check in the generated grammar

- A version's grammar was one dictionary literal, solved as a single
  expression. With a String literal for the optional `table` on hundreds of
  fields, one generated file went from 13 s to 967 s to type-check. Codegen
  now emits one private typed constant per segment (0.5 s per file; a full
  build and test run is about 18 s). The public dictionaries are unchanged.

### Fixed — A4 close-out: extracted code tables cleared of non-codes (2026-09-20)

- **Ellipsis rows are structural, not codes.** 171 tables print a bare `...`
  row ("no suggested values", a list that continues, or a null row). The
  extractor now drops it, and fail-safe (req #4) leaves an HL7 table OPEN
  when other rows remain, unless `overrides.json` says otherwise. Verified
  per table: v2.6 0153 / 0350 / 0351 (external NUBC sets) and 0359 / 0418 on
  v2.4 / v2.5.1 / v2.6 (open-ended rank, "2 ...") are open; v2.6 0365 / 0366 /
  0367, whose `...` is the "(null) no change" row, stay closed by explicit
  override.
- **Rows that denote an absent field are not codes:** 0207 "Not present" on
  all six versions (the Validator only checks populated values).
- **v2.3 0207 misprint corrected:** Appendix A prints `a` / `r` / `i`; the
  defining table in Chapter 2 sec 2.24.1.11 prints `A` / `R` / `I`. A closed
  table with the lowercase forms would have rejected a valid `A`.
- **Prose and example bleed removed:** v2.8.2 0368 (three lines of the
  EAC^U07 example message), 0396 (four Values fused with their Description,
  six wrapped Description lines; `CE (obsolete)` -> `CE` on v2.6 and
  v2.8.2), 0340 `(HCPCS)`, 0335 "Meal Related Timings" split or joined
  without its space on four versions, v2.3.1 0255 `* (star)` -> `*`.
- **Mis-decoded quotes:** the v2.5.1 Appendix A text layer carries corrupt
  curly quotes in nine descriptions (never a code); restored in the
  extractor, and the audit now fails on any recurrence.
- **Audit:** the SUSPECT shape test now also catches parentheses, three-word
  codes and bare ellipses, with a cited `SUSPECT_ALLOW` list for genuine
  printed codes it would otherwise flag (UCUM units such as `[lb_av]`,
  `KS X 1001`, `99zzz or L`). `--tables` went 22 -> 0 findings; the 22 it
  reported before understated the defects, which the wider test exposed.
- Every override is version-scoped and cites the text lines it was read
  against. Two regression tests added (629 tests green).

### Changed — `main` (M9-A) merged into `v3.3-open-items`, now the primary line (2026-09-20)

- Both schema keys coexist: `tables` (list, any datatype) is the verified
  record of the spec's TBL# cell; `table` (ID/IS only) is the enforced link
  codegen reads into `FieldGrammar.table`. New integrity finding when a
  field's `table` is not among its `tables`. A5 now derives `table` from
  `tables` instead of re-extracting.
- The M9-A audit section is renamed `table bindings` to stay distinct from
  the registry's `--tables` content audit.

### Docs — STATUS / NEXT_STEPS / ROADMAP reviewed against the repository (2026-09-20)

- Recorded the `v3.3-open-items` branch and worktree, which the live documents
  omitted: Track B (1-n variable columns) complete, Track A (code-table
  registry) complete through A4. M9-A on `main` duplicated that plan's A5
  with a different key design; the runway is now "reconcile, then A5-A7".
- Corrected stale facts: ROADMAP's current release (`v2.1.0` -> `v3.2.0`),
  typed-segment counts (150/109 -> 188), test counts, the closed M7 prose
  sweep and M8 items still listed as open, the fixture gate (source material,
  not IP), and the `private` remote's actual state.
- Commit-message rule: no co-author or AI-attribution line anywhere
  (`the working notes`, NEXT_STEPS working rules). Icons removed from the three live
  documents. Pre-review snapshots archived as `*-2026-09-20-pre-doc-review.md`.

### Fixed — extractor dropped wrapped TBL# fragments

- `scripts/extract-segment-tables.swift`: a continuation line holding only a
  table-number fragment ("0328" under "0327/") is shorter than the NAME
  column start and was discarded, so every multi-table cell whose element
  name did not also wrap lost its tail. The fragment is now kept, and only
  when the open cell ends in "/" — an unconditional append swallowed wrapped
  LEN digits (v2.5.1 OM1-32 "6553" + "6"). Depth and dataType audits are
  unchanged by the fix (842 exact, 0 findings).

## [3.2.0] — 2026-09-17

The spec-exhaustion release, entirely additive on `v3.1.0` (ADR-014
holds). Two milestones land. **M7 — the ADRM prose sweep:** the chapter
bodies and normative appendices audited beyond Appendix 5; seven
prose-only narrowings ship as `ADRM-prose:P-1..P-7` rules plus the
`EscapeProhibition` model track. **M8 — base-spec consistency and
batch scope:** the ORC/OBR paired-field equality family (items
00216/00217/00226/00222, with the v2.8.2 OBR-54 parent split), the new
public `BatchValidator`/`BatchValidationReport`, and the numeric-`>` /
`prohibitedWhen` conditional classes (PAC-2, PRT-6/7). The AU register
closes at **66 shipped / 13 partial / 15 base / 10 registered — 104 of
104 message-decidable rows; EXTEND 0, CANDIDATE 0** — and every
rule-level gap in every register is now enforced or registered with a
citation. New `IssueCode` cases (all additive, open enum):
`pairedFieldMismatch(item:)`, `conditionalFieldProhibited`.
619 tests: 609 passed, 0 failed; schema audits fully clean.

### Added
- **M8-D — the last two recorded conditional classes ship.** The
  condition DSL gains the numeric `>` operator (fail-safe false on
  non-numeric referents), unlocking v2.8.2 PAC-2
  (`condition: "SHP-8 > 1"` — "If SHP-8 Number of Packages in Shipment
  is greater than 1"). `FieldGrammar` gains a `prohibitedWhen` axis
  (schema key → codegen → new `IssueCode.conditionalFieldProhibited`),
  unlocking v2.8.2 PRT-6/PRT-7 ("may only be valued if PRT-5 [PRT-8]
  is valued" — a prohibition the required-when model could not state
  without misfiring). All 188 grammar tables regenerated; the bare-C
  guard treats either axis as modelled conditionality and its expected
  set shrinks by three. Audit fully clean. Suite 619 tests, 609 green.

- **M8-C — `BatchValidator`: batch-scope validation lands.** New public
  `BatchValidator` / `BatchValidationReport` (additive API): every
  message in a `BatchFile` runs through the standard `Validator`, plus
  the batch-envelope rules no single message can carry. Under
  `.auLocalisation`: `ADRM-prose:P-7` ("In Australia only one Batch is
  supported", §1 p. 19 — a second BHS-headed group fires) and
  `HL7au:000022.3` ("Senders must generate batches containing no more
  than 1 message" on Referrals — a REF alongside any other message in
  one batch group fires). `HL7au:000022.1`'s individual-acknowledgement
  half is enforced through the per-message MSH-15/16 = AL rules running
  on every batched message. **Register: the two batch points leave
  REGISTERED — 000022.3 SHIPPED, 000022.1 PARTIAL; final counts 66
  shipped / 13 partial / 15 base / 10 registered (still 104/104,
  EXTEND 0).** Suite 617 tests, 607 green.

- **M8-B2 — the ORC/OBR pair family completed.** ORC-12/OBR-16
  (Ordering Provider, item 00226) ships with repetition-aware
  whole-field comparison (v2.4 §4.5.1.12: "If both ... are valued,
  then both must contain the same value"), and the parent pair ships
  version-split: ORC-8/OBR-29 on v2.3–v2.6 ("ORC-8-parent is the same
  as OBR-29-parent", §4.5.1.8), ORC-8/OBR-54 on v2.8.2 (which
  repurposes OBR-29 as item 00261 and pins the pair explicitly:
  "ORC-8 and OBR-54 Must carry the same value"). ORC-7/OBR-27
  (quantity/timing) is deliberately not shipped — "should be valued
  exactly the same" is advisory and both fields are withdrawn from
  v2.7 (req #4). Suite 614 tests, 604 green.

- **M8-B1 — base-spec ORC/OBR paired-field equality.** The base
  standard declares ORC-2/OBR-2 (item 00216, Placer Order Number) and
  ORC-3/OBR-3 (item 00217, Filler Order Number) to be the SAME data
  element — the shared ITEM number in every version's attribute tables,
  spelled out in v2.4 §4.5.1.2 ("If both fields ... are valued, they
  must contain the same value") and v2.8.2 §4.5.3.2 ("This field is
  identical to ORC-2"). New Validator base pass: per ORC/OBR group,
  both sides populated and different fires the new
  `IssueCode.pairedFieldMismatch(item:)` (additive case; open enum per
  ADR-014). Whole-field wire comparison with trailing-empty
  normalisation; empty-either-side skips (the presence half is
  message-shape-dependent — ORU needs no ORC). Runs for every locale
  and version. The XCN/TQ/parent pairs stay recorded in the sweep doc
  §C for deliberate later modelling. Suite 612 tests, 602 green.

- **M7-P4 — the normative-appendices pass; M7 complete.** Appendices
  8–10 swept (63 candidates, all triaged in the sweep doc). Shipped
  `ADRM-prose:P-6`: the VMR header OBX pins (Appendix 9 p. 490) —
  OBX-2 must be RP and OBX-5 must be the fixed
  `HL7V2-VMR.v1^HL7V2 VMR&99A-9AAC5A649D18B6F2&L^TX^Octet-stream`
  literal, gated on the header's own discriminator
  (`messageCode = REF AND OBX-3.1 = 74028-2`), pinned per
  component/subcomponent into the existing OBX-2/OBX-5 overrides.
  Registered: the VMR OBX-4 sub-ID hierarchy + implementation table
  (needs tree validation + the table as a modelled artefact), and
  Appendix 10's directory-consistency rules (external-directory state,
  not message-decidable). Suite 607 tests, 597 green. **M7 total:
  seven prose-only rules shipped (P-1..P-6), one model capability
  (escape prohibitions), every non-shippable finding registered with
  its reason.**

- **M7-P3 — the escape-sequence prohibition track (ADRM-prose:P-4).**
  New `EscapeProhibition` axis on `Profile`: the AU profile prohibits
  the `\X...\` (hexadecimal, §3.1.1.5), `\C...\` and `\M...\`
  (character-set, §3.1.1.6) escape families as variances to HL7
  International (p. 136). Because the parser decodes escapes into
  stored values, the Validator re-encodes each subcomponent via
  `EscapeSequences.encode` (byte-exact round-trip, verified) and
  tokenizes on the escape delimiter — a naive substring scan would
  miss decoded `\X..\` and false-fire on decoded `\E\` next to a
  literal X (both cases test-pinned). MSH-1/2 exempt; gated to the
  guide scope. Suite 606 tests, 596 green.

- **M7-P2 — five prose-only narrowings ship (cited as `ADRM-prose:P-n`).**
  P-1: PID-1 profile-required ("mandatory in the Australian context",
  p. 61 footnote; gated ORM/ORU/REF/RRI). P-2: the §7.4.2 REF
  disallowed-segments list — nine `maxCount: 0` prohibitions (ACC, AUT,
  CTD, DRG, DSC, DSP, GT1, IN2, PR1; NTE was already HL7au:000023).
  P-3: MSH-9 pinned to REF^I12^REF_I12 / RRI^I12^RRI_I12 on referral
  traffic (§7.3.1.9 p. 326). P-5a: on ACK messages MSH-12.3.1 is
  required and closed over {HL7AU-OO-ACK-201701,
  HL7AU-OO-ACK-READ-2020006} (§8.4/§8.5 p. 372). P-5b: on user read
  acknowledgements MSH-3.3 must be AUSHICPR or NPIO (§8.4). All on
  existing machinery — no model change; suite 605 tests, 595 green.

- **M7-P1 — the ADRM chapter-body prose sweep (measurement + triage).**
  New `scripts/sweep-adrm-prose.py` scans the ADRM body for normative
  sentences with no conformance-point ID nearby and no textual match in
  Appendix 5: 319 raw hits, 263 candidates, all hand-triaged in
  `docs/design/m7-adrm-prose-sweep.md`. Five ship candidates queued
  (PID-1 profile-required p. 61; the §7.4.2 REF disallowed-segments
  list; the §7.3.1.9 MSH-9 REF/RRI exact pins; the §3.1.1.5/.6
  escape-sequence prohibitions; the read-ack MSH-12.3 pin), seven
  register entries with the reason each cannot ship faithfully, and two
  base-spec observations recorded for the base-model runway (ORC/OBR
  pair equality; the RXO free-text conditional). Normative appendices
  8–10 remain for a follow-on pass.

## [3.1.0] — 2026-09-16

The completeness release, entirely additive on `v3.0.0` (ADR-014 holds).
Two milestones land: **M5 formally closed** — every HL7 segment the six
supported specs define is modelled to full field depth on every version
that defines it (188 typed segments, 853 schemas, all audit predicates
zero) — and the **AU profile finished**: all 104 message-decidable
ADRM-2021 conformance rows accounted for (65 shipped / 12 partial /
15 base / 12 registered; EXTEND 0, CANDIDATE 0).

### Added
- **M6-B-9 — the final twelve: EXTEND reaches zero.** Every remaining
  ADRM-2021 EXTEND point either ships or is registered with a citation.
  Shipped: `HL7au:000028`/`.2` (OBR-3 filler order number unique across
  the message; new `FieldUniquenessRule` track, ORU- and REF-gated legs,
  p. 442), `000008.3.2` structural half (an RTF display OBX in an OBR
  group requires an HTML/PDF/TXT sibling; new
  `SegmentCardinalityRule.activationPredicate` — relational group
  cardinality, L2-Referrals-gated; the "same content" equality half is
  not machine-checkable), `000034.1`/`.2` (a public coding system the
  ADRM names — LN/SCT/UCUM — relegated to the CE/CWE alternate triplet
  behind a non-public primary fires; `HL7CodeTables.publicCodingSystems`
  correspondence, unnamed systems skip fail-safe), and `00044.8.1`
  offset-presence half (a TS with hour-or-greater precision must carry a
  timezone offset on Orders/Results/Referrals; new
  `CompositeOverride.timezoneRequiredCitation`; §3.26 p. 183).
  Registered with citations (permanent-limitations register §D):
  `00100.1` (SNOMED CT hierarchy subsumption — terminology server),
  `000008.1.5` (signature identifiers live in HB 308-2011, external to
  the ADRM; req #2), `000034.3` + `00044.6.7` (same-concept equivalence
  — terminology judgement), `000022.1`/`.3` (FHS/BHS batch envelope;
  documented home is a future `BatchValidator`). **Final register:
  SHIPPED 65, PARTIAL 12, BASE 15, REGISTERED 12 — 104 of 104
  message-decidable rows accounted for; EXTEND 0, CANDIDATE 0.**

- **M6-B-7 — OBX-2-driven datatype resolution: the ED/RP series ships.**
  The composite dispatch resolves OBX-5's effective datatype from OBX-2
  when the grammar carries the variable placeholder — the M6-O7 capability.
  `HL7au:00044.10.1.1–.4` (ED type/subtype/encoding/data must be valued)
  and `.11.1.1–.4` (RP pointer/application ID/type/subtype) enforced,
  gated (ORU, REF). A CE-valued OBX-5 now also correctly receives the
  CE narrowings. SHIPPED 55 → 63, EXTEND 26 → 18.

- **M6-B-8 — correspondence maps, and a M6-B-4 correction.** New
  `ComponentCorrespondence` rule (per-repetition key ⇒ value maps on both
  override tracks; unstated keys and empty values skip; case-insensitive —
  the ADRM's own examples mix `TEXT^RTF` and `text^html`). Shipped:
  ED/RP subtype ⇒ type (`00044.10.1.5/.6`, `.11.1.5/.6`, partial — stated
  pairs only, the IANA registry is unbounded), the PRD-7 authority ⇒
  qualifier pairs (`00104.7.1.4`, partial — vendor authorities are
  open-ended examples), and `000008.1.3` (OBX-2 must match the OBX-3.1
  display format per the p. 247 table). **Correction:** `00104.7.2.1`'s
  0363 membership check was withdrawn → REGISTERED — table 0363 is
  user-defined and the ADRM's own p. 334 examples use vendor authorities
  outside it, so the closed-set check misfired on the spec's own wires
  (req #4); table 0203 gains `UPIN`/`NOI`, which the ADRM's examples use
  but its printed post-v2.4 0203 omits. SHIPPED 63, PARTIAL 8,
  REGISTERED 6, EXTEND 18 → 12 — **92 of the 104 message-decidable rows**.

- **M6-B-6 — the referral-level gates: three more PARTIAL legs shipped, and
  a correction.** The M6 audit had recorded the Referrals(L2)/L1
  discriminator as "an MSH-21 profile ID the model cannot address". That
  was a **misidentification**: the ADRM declares the adhered profile in
  **MSH-12.3** ("The `<internal version ID (CE)>` component must be valued
  … to indicate the profile that is being adhered [to]"; its profile table
  names `HL7AU-OO-REF-SIMPLIFIED-201706` as Level 2 and `…-L1` as
  Level 1) — the same component the shipped `000040.4` pins, addressable
  by the plain field-ref DSL all along. Shipped on that gate:
  `HL7au:000021`'s Referrals(L2) leg (OBX-2 ≠ TX; the point is now FULLY
  enforced), `000008.3.1`'s Level-1 leg (the OBR/OBX group must contain a
  **PDF** display OBX; fully enforced), and `000020`'s Referrals(L2)
  trigger-event leg (only its message-code half remains — a shape-level
  undecidability, since a wholly-Z code never satisfies any message-type
  gate). Register: SHIPPED 53 → 55, PARTIAL 5 → 3. The correction is
  recorded in the audit doc's stage-3 note and §D.

- **M6-B-5 — the composite value-set track; the XCN PARTIALs are now full.**
  `CompositeOverride` gains `componentValueSets` (allow lists, the datatype
  twin of the field-level track) with **populated-only semantics** — an
  empty component is a presence violation (`requiredComponents`), never a
  membership one, so nothing double-reports. Shipped on it:
  `HL7au:00044.7.3` (XCN-10 from table 0200) and `00044.7.4` (XCN-13 from
  table 0203) upgrade from PARTIAL to fully enforced. Register: SHIPPED
  51 → 53, PARTIAL 7 → 5 — still **78 of the 104 message-decidable rows**,
  now with two fewer asterisks. M6-O6's remaining scope reduces to the
  general per-version registry alone.

- **M6-B-4 — the code-table registry seed; four more ADRM points enforced.**
  New internal `HL7CodeTables` holds the tables shipped conformance points
  consume — 0074 (Diagnostic Service Section), 0200 (Name Type), 0203
  (Identifier Type) and the AU-defined 0363 (Assigning Authority) — each
  hand-verified against the **ADRM-2021's printed rendering** (the normative
  one for HL7au points; its 0203 is a post-v2.4 vintage). Shipped on it:
  `HL7au:000032` (OBR-24 valued + table 0074 membership on Results),
  `000032.2` **partial** (same on Referrals; the "appropriate for the
  content" half is receiver-judgement), `00104.7.2.1` (PRD-7.2 from 0363)
  and `00104.7.3.1` (PRD-7.3 from 0203), all message-type-gated. Register:
  SHIPPED 48 → 51, PARTIAL 6 → 7, EXTEND 30 → 26 — **78 of the 104
  message-decidable rows**. The XCN PARTIALs (`00044.7.3`/`.7.4`) still
  await a value-set track on `CompositeOverride` (§D updated). Existing ORU
  test wires gained `OBR-24 = LAB` — the new requiredness caught them
  exactly as it would catch real traffic.

- **v3 cycle 5 — the never-authored backlog closed: 188 of 188 segments,
  M5's coverage bar is MET.** The 62 remaining never-authored instances
  (38 distinct v2.6/v2.8.2-only segments: eClaims CH16, materials
  management CH17, plus `ARV/IAR/UAC/SGH/SGT`, `BUI/CDO/DON/RXV`,
  `DMI/DPS/MCP/OMC/PM1`, `PAC/PRT/SHP`, `REL`) authored from their own
  chapters, all 62 `--verify` PASS, descriptions taken from the chapters'
  own section headings. **Codegen gains an earliest-defining-version
  fallback**: a segment v2.5.1 never defines emits its shared struct from
  the earliest version that does (extending the union-surface doctrine) —
  **150 → 188 typed structs**. Conditional surface triaged per field:
  16 spec-cited predicates shipped (`PYE-3..6` payee-type gates, `MCP-5`,
  `OMC-2/3` mutual presence, `PRT-5/8/9/10/22` one-of-five rotation) and
  22 registered with per-field rationale in
  `conditional-completeness-audit.md`, including two new model-extension
  classes: numeric ordering comparison (`PAC-2`, "SHP-8 > 1") and
  conditional prohibition / not-permitted-unless (`PRT-6/7`). Audit fully
  clean: **853 schemas, 842 depth-exact, zero never-authored anywhere**.

- **v3 cycle 4 — deferred-tier batch C: the last deferred instances.** Forty
  schema instances across CH02/03/04/06/07/08/14 (`OVR/SFT`, `IAM/NPU/PDA`,
  `BLG/ODS/ODT/RQ1/RQD/IPC`, `BLC/RMI`, `FAC`, `CM0/CM1/CM2`, `NCK/NSC/NST`
  on both v2.6 and v2.8.2), all `--verify` PASS. **The deferred-instances
  class is now EMPTY: every modelled segment exists on every version that
  defines it.** IAM is the one deep divergence (20 → 30 at v2.8.2). The
  conditional surface travelled: `RQ1-2..5` (either-pair) and `RQD-2..4`
  (one-of-three) carry the same spec-cited predicates as the AU-priority
  versions (prose verified identical on both chapters); `IAM-7` stays a
  registered bare `C` and joins the v2.8.2 guard set. 791 schemas,
  780 depth-exact, audit fully clean. The only remaining M5 scope is the
  never-authored v2.6/v2.8.2-only backlog (24 + 38 segments).

- **v3 cycle 3 — deferred-tier batch B: CH15 personnel on v2.6 / v2.8.2.**
  Fourteen schema instances (`STF/PRA/ORG/AFF/LAN/EDU/CER` × both versions),
  extractor-seeded and `--verify` PASS. Divergences pinned: STF grows
  39 → 41 and ORG 12 → 13 at v2.8.2; CER-12 retypes `ID` → `EI` at v2.8.2.
  The conditional surface travelled with the segments: `STF-1`/`PRA-1`
  (`messageCode = MFN`) and `PRA-12` (`messageCode != MFN`) carry the same
  spec-cited predicates as the AU-priority versions (identical prose,
  verified on both chapters); `CER-12` stays a bare `C` (the X.509 payload
  condition, registered) and joins the v2.8.2 bare-C guard set — the guard
  caught exactly this on the first run, which is its job. 751 schemas,
  740 depth-exact, audit fully clean.

- **v3 cycle 2 — deferred-tier batch A: CH02 envelopes + CH05 queries on
  v2.6 / v2.8.2.** Sixteen schema instances of already-modelled segments,
  extractor-seeded from each version's own chapters and `--verify` PASS:
  `BHS/FHS/BTS/FTS/DSC` (both versions), `DSP/QRI` (both), `URD/URS`
  (v2.6 only — **withdrawn from v2.8.2**, whose CH05 carries no attribute
  table for them). Divergences pinned: BHS/FHS grow 12 → 14 (batch/file
  sending + receiving network address, `HD`); `URD-4` rides the v2.6
  CE → CWE wave. 737 schemas, 726 depth-exact, audit fully clean; the
  never-authored backlog is unchanged (v2.6 24 / v2.8.2 38 — these were
  deferred instances of modelled segments).

- **v3 cycle 1 — the v2.5-only quartet: `CER` / `IPC` / `OVR` / `SFT`.** The last
  never-authored segments on any AU-priority version, authored on v2.5.1 from
  their own attribute tables (CH15 / CH04 / CH02 / CH02; 31 + 9 + 5 + 6 fields,
  four `--verify` PASS). **146 → 150 typed segments; the v2.5.1 never-authored
  count is 0** — every remaining coverage gap is the owner-deferred
  v2.6/v2.8.2 backlog (their quartet instances now count in the deferred
  class: 24 / 38). Notes: `CER-1` renders the spec's en-dash verbatim
  (`Set ID – CER`); `CER-12 Subject ID` is a bare `C` (its X.509-format
  condition is not wire-decidable — registered in
  `conditional-completeness-audit.md`); **`CER-6` is the first field on any
  modelled version to declare `ED`** as its static datatype, amending
  M6-O7's "no field declares ED" observation (the §D ED/RP points are
  unaffected — their subject is the runtime OBX-5 type).

## [3.0.0] — 2026-09-16

**The M6 release — AU localisation completeness (ADRM-2021), closed and measured.** One **BREAKING** change (the M6-D5 OBX-5 datatype fix, shipped under an owner-directed ADR-014 override — see "Changed — BREAKING" below and `Migration.md` → "The 3.0 boundary"); everything else is additive. The additive-only contract resumes for the 3.x line from this tag.

### Added
- **M6 — ADRM-2021 AU localisation audit (audit only; no behaviour change).**
  `scripts/extract-adrm-conformance.py` recovers Appendix 5 of
  `HL7AUSD-STD-OO-ADRM-2021.1` (the localisation's normative conformance-point
  table) from `pdftotext -layout` output and classifies every row against what
  `HL7Locale.auLocalisation` ships. **302 rows / 263 conformance points**;
  the profile enforces or accounts for **64 of the 103 that are decidable from
  a single message** after stages 1–2 (42 shipped, 3 partial, 15 base-model, 4
  registered limitations), leaving **3 expressible with today's DSL** and
  **36 needing a model extension**. At audit time the figure was 47 of 102;
  the CANDIDATE column fell from 31 to 3 because shipping stages 1–2
  discovered why most of them could not ship — see M6-O6 and M6-O7. The remaining 158 constrain receiver behaviour, transport/PKI
  addressing, rendered payload or cross-message uniqueness, and are enumerated
  so the exclusion is auditable rather than assumed.
  - `docs/design/m6-adrm-2021-localisation-audit.md` — findings and sequencing
  - `docs/design/m6-adrm-2021-conformance-register.md` — generated, re-runnable

- **M6-A stage 1 — the MSH envelope literals.** Nine ADRM-2021 conformance
  points now enforced by `.auLocalisation`, each gated on the message types
  Appendix 5 names for it: `HL7au:000024.1` (MSH-1 field separator = `|`),
  `000024.2/.3/.4/.5` (MSH-2 encoding characters = `^~\&`),
  `00049.2`/`.3` (MSH-9 trigger event and message structure must be valued),
  `00047.1`/`.2` (MSH-15/MSH-16 = `AL`), `00048.3.1` (MSH-18 character-set
  value set). `00049.1` is not restated — MSG-1 is already a base required
  component. `000024.2` is **partial**: it applies to Referrals as well, but
  `.3`/`.4`/`.5` do not, and MSH-2 parses as one scalar, so the rule gates on
  the Orders/Results intersection rather than over-firing on REF.
  `HL7au:00048.3.1`'s real catch is encoding aliases the parser accepts but the
  point does not list (`UTF-8`, `US-ASCII`, `ISO-8859-1`) — a genuinely unknown
  encoding is already a `ParseError` before validation.

- **M6-A stage 2 — XCN required components.** `HL7au:00044.7.2` (XCN-9
  assigning authority) and `.7.5` (XCN-2.1 family-name surname) enforced;
  `.7.3` (XCN-10) and `.7.4` (XCN-13) enforced for presence only. All gated on
  `messageCode in (ORM, ORU, REF)`. `ComponentRequirement` gains
  **`subcomponent`** so `.7.5` names the surname subcomponent exactly — a
  family name of `&VAN` is populated but carries no surname, and would
  otherwise have passed.
  `HL7au:00044.7.1` and `00044.3.1` are not restated (XCN-1 and EI-1 are
  already base required components).

- **M6-A stage 3 — the prohibitions, closing the CANDIDATE tranche.**
  `SegmentCardinalityRule` gains **`maxCount`** (default `nil` = unbounded, the
  pre-M6 behaviour): the v0.11 group-scope cardinality model was minimum-only
  and could not state "the count must be zero". `maxCount: 0` expresses a
  prohibition and fires the new additive `IssueCode`
  **`.segmentCardinalityAboveMaximum`**. An empty rule predicate now counts
  every segment of the counted ID — whole-segment prohibitions have no field
  to test. Shipped on this machinery, both anchored on MSH at `messageWide`
  scope:
  - `HL7au:000023` — the NTE segment must not be used; gated
    `messageCode in (ORM, ORU, REF)` per Appendix 5 (p. 440).
  - `HL7au:000021` — OBX-2 must not be `TX`; **partial** — the Results leg
    (`messageCode = ORU`) is enforced, the Referrals(L2) leg is not: Level 2
    is identified by an MSH-21 profile ID the model cannot address, and a
    bare REF gate would over-fire on Level 1 and unprofiled referrals
    (p. 439).
  - `HL7au:00050.1.5` (OBX-6.3 = `UCUM`) did **not** ship and is now a
    registered permanent limitation: it is scoped "Senders (Pathology only)"
    and ADRM-2021 defines no message-decidable pathology discriminator —
    table 0074 mixes pathology and imaging disciplines and the spec names no
    pathology subset, so any gate either over-fires on spec-compliant imaging
    results (req #4) or rests on an invented OBR-24 subset (req #2). See
    `docs/design/permanent-limitations-register.md`.

  **M6-A is complete**: CANDIDATE 0; the register now reads SHIPPED 43 /
  PARTIAL 4 / BASE 15 / REGISTERED 5 — **67 of the 103 message-decidable
  points** enforced or accounted for; the remaining 36 are the EXTEND tranche
  (M6-B). Suite 545 → 552 green.

- **M6-B-1/2 — PRD exactly-one, referral display formats, the Z prohibitions.**
  Three more DSL extensions (req #3): the **`anyRepeat(<fieldref>)`** atom
  (∃-semantics over every repetition — `PRD-1 = AP` would miss a
  spec-compliant `RP~AP`), **`startsWith` / `not startsWith`** predicate ops,
  and a trailing-`*` prefix pattern on `countedSegmentID` (`"Z*"` counts every
  user-defined segment). Shipped on them: `HL7au:00104.1.1` / `00104.2.1`
  (exactly one PRD with PRD-1 = AP / IR in the REF message, p. 472),
  `00104.7.0` (r3) (PRD-7 required on the IR PRD — this row was **misparsed
  as a grouper fragment** in the register because the PDF prints the
  identifier below the row's first text line; verified against the source,
  repaired via a curated `ROW_REPAIRS` table, and shipped),
  `000008.3.1` **partial** (≥1 HTML/PDF/TXT display OBX per OBR/OBX group on
  Referrals — a necessary condition under both the L1 and other-profiles legs;
  L1's "must be PDF" narrowing is MSH-21-identified and unenforced, p. 423),
  `000023.1` (Z segments prohibited on ORM/ORU/REF, p. 440), and `000020`
  **partial** (Z-prefixed trigger events prohibited on ORM/ORU; the
  message-code leg is undecidable inside any message-type gate and the
  Referrals(L2) leg is MSH-21-identified, p. 439). Register: SHIPPED 43 → 48,
  PARTIAL 4 → 6, EXTEND 36 → 30, OUT 83 → 82 — **74 of the 104
  message-decidable rows** (the repaired row adds one to the denominator).
  Suite 552 → 569 green.

- **M6-O5 — the per-field `dataType` audit predicate.**
  `scripts/audit-schemas.py --depth` now diffs every schema field's `dataType`
  against the union of values the extractor sees for that (segment, index)
  across the version's chapters. First measurement: **45 findings** — 30 were
  the pre-v2.5 `CM`-placeholder class (the schemas carry the v2.5-era name of
  the identical component structure; grammar-level composite dispatch keys on
  it, so a spec `CM` accepts any named composite — documented convention, not
  a defect), 2 whitelisted (`v2.4/AL1-1`, a spec typo where the v2.4 table and
  heading both print `CE` for Set ID; `v2.5.1/OBX-5`, the variable-type row
  defeats the extractor), and **13 real verbatim-fidelity defects fixed**:
  v2.3 `PID-10/16/17/22/26` and v2.3/v2.3.1 `AL1-2/4` were typed `CE` against
  the spec's scalar `IS`, v2.3/v2.3.1 `OBX-8` `IS` → `ID`, v2.3 `MSH-12`
  `VID` → `ID` (VID does not exist before v2.4), and v2.8.2 `ORC-34`
  `EI` → `CWE` (attribute table wins over the field-definition heading). All
  on non-canonical versions — grammar tables only, no typed-accessor impact.
  The audit is fully clean: integrity 0 / depth 706 exact / presence 0 /
  **dataType 0**.

- **M6-B-3 — the EXTEND tranche triaged; M6 closed.** The 30 remaining
  EXTEND points are registered in `permanent-limitations-register.md` §D as
  **deferred capabilities with citations** (req #3): value-correspondence
  maps (6), within-message uniqueness/ordering (4), generalised coding-system
  precedence (3), relational group cardinality (1), OBX-2-driven datatype
  resolution / M6-O7 (8), the HL7 code-table registry / M6-O6 (4), and four
  stragglers (TS timezone, CWE same-concept, two batch-scope points). Each
  blocks spec-completeness until its capability lands; none is silently
  dropped. **M6 closes at 74 of 104 message-decidable ADRM-2021 rows enforced
  or accounted for** — with the standing caveat that Appendix 5 is explicitly
  not exhaustive; the chapter-body prose sweep is separate, later work.

### Changed — BREAKING (M6-D5 fix; owner-directed ADR-014 override, 2026-09-15)
- **`OBX.observationValue` is now `Field?` (was `String?`).** M6-D5: every
  version's attribute table gives OBX-5 the variable datatype (`*` on
  v2.3/v2.3.1/v2.4, `varies` on v2.5.1/v2.6/v2.8.2 — the audit's "`Variable`"
  was the section-heading paraphrase; the tables print `*`); the schemas said
  `ST`, and the `String?` accessor silently flattened structured payloads
  (CE, SN, ED, ...) to their first component. The six schemas now store the
  verbatim table value (the `RDT-1` convention) and the accessor returns the
  full `Field`. Scalar callers migrate with `?.stringValue`; see
  `Migration.md` → "The 3.0 boundary". The project owner directed the
  ADR-014 override to fix this now rather than queue it; **the next release
  is a major (`v3.0.0`)**. The additive-only contract is otherwise unchanged.

### Known limitations found by M6 (registered, not fixed)
- ~~**M6-O5**~~ done — closed above — the dataType predicate now runs each batch.
- **M6-O6 — HL7 code tables are not modelled.** The schemas drop the spec's
  `TBL#` column and there is no code-table registry, so every "value from HL7
  Table NNNN" point is unshippable: `000032`/`.2` (0074), `00044.7.3` (0200),
  `00044.7.4` / `00104.7.3.1` (0203), `00104.7.2.1` (0363). Registered as the
  highest-leverage deferred capability (`permanent-limitations-register.md` §D).
- **M6-O7 — ED and RP never appear as a declared datatype.** Eight points
  (`00044.10.*`, `00044.11.*`) target composites no field declares on any
  version; they reach the wire only through OBX-5, whose type OBX-2 chooses at
  runtime. An override for them would be dead code. Registered §D; the M6-D5
  fix (OBX-5 → `Field?`) is the prerequisite the future capability builds on.

### Fixed
- **M6-D4 — AU composite overrides fired outside their message-type scope.**
  The composite-track twin of M6-D3. Every `HL7au:00044.*` datatype point is
  scoped to Orders/Results/Referrals (Results/Referrals for ED and RP), but
  `CompositeOverride` had no gate, so an `ADT^A01` carrying a two-component
  `CX` in PID-3 failed AU validation citing `HL7au:00044.1.2`.
  `CompositeOverride` gains **`condition`**, gating all four rule tracks; the
  CX / CE / CNE / CWE overrides now carry `messageCode in (ORM, ORU, REF)`.
  Six existing tests had encoded the over-fire on ADT and ACK wires; their
  wires moved into scope.
- **M6-D3 — AU profile usage narrowings fired outside their message-type scope.**
  `HL7au:000041` (MSH-17 = AUS) and `HL7au:000042` (MSH-19 = en^English^ISO639)
  are scoped by ADRM-2021 to Orders, Results, Referrals, ACK and RRI, but
  shipped as ungated `profileUsage = .required` with ungated value sets. A
  spec-compliant `ADT^A01` with no MSH-17 therefore failed AU validation citing
  a conformance point that does not apply to it. `FieldOverride` gains
  **`usageCondition`** — a message-context predicate gating `profileUsage`,
  same grammar and same fail-safe semantics as `ComponentValueSet.condition` —
  and both rules now carry `messageCode in (ORM, ORU, REF, RRI, ACK)` on each
  half. `FieldOverride` is internal, so the public API is unchanged.
  Also a prerequisite for M6-A: 11 of the 31 shippable points are
  message-type-scoped `.required` narrowings that would otherwise have
  inherited the same defect.
- **M6-D1 — CNE pair rules cited a withdrawn conformance point.**
  `ceCwePairRules` treated CNE like CE and cited `HL7au:00044.5.5` / `.5.6` for
  the alternate-identifier pair. ADRM-2021 numbers CNE `.5.4` / `.5.5`, and
  `00044.5.6` was **removed** in revision r2 — the overlay was citing a point
  that no longer exists. Only the `specCitation` strings were wrong; the rules
  always behaved correctly. Found by the M6 Appendix 5 diff, which is the point
  of running one. Two tests now pin the per-composite numbering (CE `.4.5`,
  CNE `.5.4`, CWE `.6.4`) and assert `.5.6` is never cited.

## [2.1.0] — 2026-09-03

The **Sprint 0 cycle** (first release of the 2.x line; additive under ADR-014, resumed at
`v2.0.0`). Typed-segment coverage **109 → 146** — after this release **no segment the spec
defines is missing on v2.3, v2.3.1 or v2.4**, and v2.5.1 is complete bar its v2.5-only
additions; v2.6/v2.8.2 stay deliberately partial (`docs/design/deferred-coverage-backlog.md`).
The audit gained a **presence predicate** (absent segments were previously invisible — exactly
how the v2.4 lab-automation gap survived three clean audits), ten spec-cited condition
predicates shipped, and four real defects were found and fixed by the sweep's own harnesses:
the extractor `1-n` run-on (BHS bound under ADD on every version), the parser numbering
BHS/FHS fields one off the spec (BHS-1/FHS-1 are the field separator, like MSH-1), the
wrapped-`RP/` header (v2.3 FAC's repeat column), and the blank-OPT table convention.
Tests 514 → **525** across 25 suites; audit: 717 schemas, depth 706 exact / 0 / 0, presence 0.

### Sprint 0 — v2.4 lab-automation presence defect + audit presence predicate

First v2.x coverage cycle (`docs/design/au-coverage-sprint-plan.md` Sprint 0; planned label
v1.10). Additive under ADR-014.

- **Fixed — the v2.4 lab-automation presence gap.** v1.4 authored `EQU/SAC/INV/TCC/TCD/EQP`
  as "v2.5+", but v2.4 CH13 defines all six. Authored on v2.4 from that version's own
  attribute tables (golden `--verify` PASS on each): EQU 5 / SAC 44 / **INV 18** (v2.5.1 adds
  INV-19/20) / TCC 14 / TCD 8 / EQP 5 — 94 fields. Per-version divergences pinned in
  `TypedSegmentTests`: v2.4 uses `CM` where v2.5.1 has `SPS` (SAC-6, TCC-3) and `CE` where it
  has `CWE` (SAC-27, SAC-43); no `B`/`C` flags yet (SAC-6, TCC-3, INV-14 are `O`); SAC-22 is
  "Available Volume" and SAC-43 "Special Handling Considerations" in v2.4.
- **Added — presence predicate in `scripts/audit-schemas.py --depth`.** The depth pass only
  inspected schemas that *exist*, so an absent segment was invisible — that is how the gap
  survived three clean audits. Each version's extracted caption set is now diffed against its
  schema directory: a segment modelled on another version but absent here is a **PRESENCE**
  finding (non-zero exit); segments modelled nowhere are reported as the never-authored
  backlog count. Red-first: the predicate reported exactly the six v2.4 segments before they
  were authored, and nothing else.
- **True baseline recorded.** 590 schemas, integrity 0 findings; depth 584 exact / 0 gaps /
  0 suspects; presence 0. Never-authored by caption: v2.3 24, v2.3.1 27, v2.4 37, v2.5.1 41,
  v2.6 61, v2.8.2 73 = **263 instances** — six more than the 2026-08-23 plan count implied
  after Sprint 0 (caption discovery was a floor).
- Tests 514 → **515** (one new pin), 25 suites; codegen drift = the six new v2.4 grammar tables
  only. Generated accessors unchanged (structs are canonical-shaped).

#### §3 — v2.4 chapter sweep, batch CH15 (personnel management)

- **Added — six typed segments: `STF` / `PRA` / `ORG` / `AFF` / `LAN` / `EDU`**, authored on
  **v2.4** (Tier 1) *and* **v2.5.1** (canonical — typed structs are emitted from v2.5.1 only,
  so authoring the AU version alone would give grammar without accessors), plus `STF`/`PRA`
  on **v2.3 / v2.3.1** (CH8 there; the other four are v2.4+) so every AU-priority version of
  the segment lands together — 16 schemas. 109 → **115 typed segments**. Pinned divergences:
  v2.4 is shallower on STF (29 vs 38) and EDU (8 vs 9), v2.3/v2.3.1 STF is 26 and PRA 8;
  v2.4 uses `CM` where v2.5.1 has `DIN`/`SPD`/`PLN`/`PIP`; PRA-6 `O` → `B`; STF-1 `R` (v2.3)
  → `C`; STF-3 repeats only from v2.3.1; STF-16/17 `ID`/`IS` (v2.3) → `CE`; PRA-1 `ST`/`R` →
  `CE`/`R` → `CE`/`C`; per-version names (STF-2 "Staff ID Code", STF-9 "Service", …).
  `CER` is v2.5+ (not a v2.4 segment).
  Two v2.4 EDU spec defects normalised and recorded: EDU-2's OPT cell is blank in the PDF
  (schema `O`, per v2.5.1 — the one `--verify` FAIL of the batch, documented), EDU-4's name is
  set "ParticipationDate" in the table but spaced in its own definition heading.
- **Fixed — extractor `1-n` table binding (`scripts/extract-segment-tables.swift`).** A table
  whose only row never parses (`ADD-1`, `RDT-1`) left `rows` empty, so the *next* segment's
  header was taken as a "stray duplicate" and its rows bound under the wrong caption: v2.4 and
  v2.5.1 both reported `ADD` with BHS's 12 fields and **no `BHS` at all**. An empty table now
  ends when a header with a different caption appears. Harness: full caption diff on v2.4 and
  v2.5.1 = exactly `−ADD +BHS`; depth audit unchanged (584 exact / 0 / 0).
- **Audit:** Z-segments excluded from the never-authored count (site-defined by spec; v2.4
  CH08's `ZL7` is "PROPOSED EXAMPLE ONLY"). New **deferred** class: a modelled-elsewhere
  absence on an owner-deferred version (`DEFERRED_VERSIONS = {v2.6, v2.8.2}`, per
  `deferred-coverage-backlog.md`) is listed but does not fail — the AU-first sequencing now
  splits a segment's versions across sprints, which the original PRESENCE rule would have
  reported as 12 defects. After batch A: 606 schemas, depth 600 exact / 0 / 0, presence 0,
  deferred 12; never-authored v2.3 22, v2.3.1 25, v2.4 30, v2.5.1 34, v2.6 54, v2.8.2 66.
- SAC v2.4 swiftNames for fields 22/43 realigned to the canonical-by-index convention
  (`--emit-schema` behaviour; ISD v2.6 precedent) — inert metadata on a non-canonical schema.
- Tests 515 → **516**.

#### §3 — batch CH04 (orders)

- **Added — five typed segments: `BLG` / `ODS` / `ODT` / `RQ1` / `RQD`** on v2.3, v2.3.1,
  v2.4 and v2.5.1 (20 schemas, `--verify` PASS ×20). 115 → **120 typed segments**. `BLG`
  is the CH04 segment v1.9's financial sweep deliberately excluded. Pinned: BLG is 3 fields
  before v2.5.1 (BLG-4 Charge Type Reason is v2.5+), BLG-1 `CM` → `CCD`, BLG-3 `CK` (v2.3
  only) → `CX`; RQ1-2's name drifts every version ("Manufactured ID" → "Manufacturer ID" →
  "Manufacturer Identifier"); ODS/ODT/RQD identical across all four.
- Audit after the batch: 626 schemas, depth 620 exact / 0 / 0, presence 0, deferred 22;
  never-authored v2.3 17, v2.3.1 20, v2.4 25, v2.5.1 29, v2.6 49, v2.8.2 61. Tests → **517**.

#### §3 — batch CH02 (control / batch envelopes)

- **Added — six typed segments: `BHS` / `FHS` / `BTS` / `FTS` / `DSC` / `ADD`** on v2.3,
  v2.3.1, v2.4 and v2.5.1 (24 schemas; `--verify` PASS ×20, `ADD` ×4 hand-authored). 120 →
  **126 typed segments**. `BatchParser` / `StreamingBatchParser` have framed FHS/BHS/BTS/FTS
  since v0.3 with no schemas behind them — the parser/schema coherence gap the sprint plan
  called out is closed. Pinned: BHS/FHS-3..6 `ST` → `HD` at v2.5.1; DSC-2 Continuation
  Style is v2.4+; BTS/FTS identical everywhere.
- **Fixed — BHS-1/FHS-1 are the field separator, like MSH-1.** `Parser` applied the
  separator rule only to the first line, so an envelope line inside a message was numbered
  plainly and every BHS/FHS field read one position off the spec (the batch pin found it:
  `BHS-11 Batch Control ID` came back nil). The rule is now a property of the segment ID
  (`Parser.isSeparatorSegment`: MSH / BHS / FHS) and `Serializer` mirrors it; the pin
  round-trips the wire byte-for-byte. Raw `BatchFile.fileHeader` / `BatchGroup.header`
  strings are unchanged; typed access to them from the batch API is a follow-up.
- **`ADD-1` is a `1-n` row** (same as RDT-1): hand-authored on all four versions, added to
  `DEPTH_WHITELIST`. After the batch: 650 schemas, depth 640 exact / 0 / 0, presence 0,
  deferred 34; never-authored v2.3 12, v2.3.1 15, v2.4 20, v2.5.1 24, v2.6 44, v2.8.2 56.
  Tests → **518**.

#### §3 — batch CH05 (the v2.3-era query family)

- **Added — eight typed segments: `DSP` / `EQL` / `ERQ` / `SPR` / `URD` / `URS` / `VTQ`**
  on v2.3, v2.3.1, v2.4 and v2.5.1 (they live in CH2 in the two legacy versions) **and `QRI`**
  (v2.4+) — 30 schemas, `--verify` PASS ×30. 126 → **134 typed segments**. `SPR` is the
  segment whose table was wrongly committed as RDT before v1.5-S1; it now has its own
  schemas on every version. Depths and datatypes identical across all four versions; the only
  cross-version delta was a PDF "Query/ Response" line-wrap artifact (v2.3 EQL/SPR/VTQ-2,
  v2.4 VTQ-2), normalised and registered. URD/URS accessor names hand-tuned from the derived
  `rU…` to `ru…` (`ruDateTime`, `ruWhoSubjectDefinition`, …) before they became permanent API.
- Audit after the batch: 680 schemas, depth 670 exact / 0 / 0, presence 0, deferred 40 (the
  v2.3-era query segments are withdrawn from v2.6/v2.8.2, so fewer move to the deferred
  class); never-authored v2.3 5, v2.3.1 8, v2.4 12, v2.5.1 16, v2.6 40, v2.8.2 54.
  Tests → **519**.

#### §3 — batch E (CH03 patient admin + CH06 financial + CH07 facility)

- **Added — six typed segments: `IAM` / `NPU` / `PDA` / `BLC` / `RMI` / `FAC`** — IAM/PDA/
  BLC/RMI on v2.4 + v2.5.1 (they are v2.4+), NPU and FAC on all four AU-priority versions —
  16 schemas, `--verify` PASS ×16. 134 → **140 typed segments**. `IAM` (patient adverse
  reactions) is the AU-relevant ADT segment this batch was sequenced around. Pinned:
  IAM-7 `R` (v2.4) → `C` (v2.5.1); v2.3 FAC-1 "Facility ID" and FAC-3/-9/-11 single
  (repeating from v2.3.1).
- **Fixed — extractor header key for wrapped `RP/`.** v2.3 CH7's attribute header wraps the
  `#`, so the column read `RP/` and went undetected — its `Y` cells then landed in OPT
  (FAC-5..8 extracted as optionality "Y"). `"RP/"` added to the RP header patterns;
  re-extraction matches the PDF exactly and the corpus-wide audit stayed clean.
- Tests → **520**.

#### §3 — batch F (CH08 clinical-study masters + CH14 app management) — §3 complete

- **Added — six typed segments: `CM0` / `CM1` / `CM2` / `NCK` / `NSC` / `NST`** — the CM
  family on all four AU-priority versions, the CH14 trio on v2.3.1+ (v2.3 has no
  network-management chapter) — 21 schemas. 140 → **146 typed segments**. Pinned: CM0-3
  `CE "Alternate Study ID's"` (v2.3) → `EI "Alternate Study ID"`; CM0-5/-9/-11 single in
  v2.3; NSC-1 "Network Change Type" → "Application Change Type"; NSC-4/5/8/9 `ST` → `HD`
  from v2.4; NST-15 "Network Errors" → "Application control-level Errors".
- **The v2.3.1 CH14 schemas are hand-authored** from the raw Appendix C figures: the
  mega-PDF extraction prose-bleeds around those small tables (phantom index rows, prose in
  names). One documented `--verify` exception (NSC); NCK/NST pass. Registered in
  `segment-coverage-extraction.md`.
- **Blank OPT = optional** (the CH14/Appendix-C table convention) is now encoded in the
  extractor: `--verify` accepts a blank extracted OPT against `O`, `--emit-schema` emits `O`.
  The `Set ID- CM2` spacing artifact (v2.3/v2.3.1/v2.4) normalised and registered.
- **§3 is complete: zero never-authored segments remain on v2.3 / v2.3.1 / v2.4.** The
  v2.5.1 never-authored remainder is the v2.5-only set (`OVR`/`SFT`/`CER` + co), out of this
  sprint's defect-driven scope. Tests → **521**.

### Sprint 0 close-out — conditional sweep + honest coverage claims

- **Added — ten condition predicates over the §3 segments**, each cited to identical prose in
  every version that carries the `C` (register: `conditional-completeness-audit.md`):
  `STF-1`/`PRA-1` → `messageCode = MFN`, `PRA-12` → `messageCode != MFN` (the stated inverse),
  `RQ1-2/-3` → `RQ1-4 empty OR RQ1-5 empty` and `RQ1-4/-5` → the mirror (the either-pair
  rule), `RQD-2/-3/-4` → both peers `empty` (the one-of-three rule). 34 schema rows;
  behaviour tests fire-and-stay-silent both ways in `ConditionalFieldTests`.
- **Documented — `IAM-7 Allergy Unique Identifier`**: its condition keys on receiving-system
  capability ("if IAM-3 can uniquely identify the allergy on the receiving system"), not
  message content — no message-expressible predicate exists; joined the register.
- **Coverage claims made honest** (`README.md`, DocC `TypedSegments.md`): 146 typed segments;
  zero missing segments on v2.3/v2.3.1/v2.4; v2.5.1 complete bar the v2.5-only additions;
  **v2.6/v2.8.2 explicitly partial** with a pointer to the deferred backlog. (The README had
  claimed 15 typed structs since v0.x.)
- Tests 521 → **525** in 25 suites.

## [2.0.0] — 2026-08-28

**BREAKING.** The first exercise of ADR-014's "waits for 2.0" lane: remediation stage R10
removed the dead public surface (the `HL7v2KitDictionaries` product, four never-raised enum
cases, two no-op `ParserOptions` members, `ValidationReport.empty`,
`MessageBuilder.append(unknown:)`), made `RequiredComponentSet.init`'s `description` required,
and applied the v1.6-deferred OBX-12/15 accessor renames (`effectiveDateOfReferenceRangeValues`,
`producersReference`). Every removal and its replacement is tabled in `Migration.md` → "The 2.0
boundary". Additive-only resumes for the 2.x line.

Folds the untagged **v1.7 / v1.8 / v1.9** coverage cycles (typed-segment coverage **85 → 109**;
`scripts/audit-schemas.py --depth`: integrity 0 findings across 584 schemas, depth 578 exact, 0
gaps, 0 suspects) and the complete **R1–R10** over-engineering remediation track
(`docs/design/remediation-plan.md` — ~1,400 lines removed behaviour-preserving, two real
defects found by its characterization harnesses: batch MSH-18 charset detection, extractor
multi-word-cell collapsing). Tests **515 → 514 across 25 suites** (R9 fold + R10 Dictionaries test
retirement), no codegen drift.

### R1 — Foundation-import purge + codegen template trims (remediation stage 1 of 10)

First executed stage of `docs/design/remediation-plan.md` (F1, F34, F35, F36; F26
dropped). ~270 net lines removed, behaviour byte-identical, zero API change.

- **F1:** the emitted `import Foundation` removed from all three codegen templates — none of
  the 116 generated files uses a Foundation symbol — and from the 18 hand-written
  `Composite/` files + `SegmentRegistry.swift` (19 files × 2 lines).
- **F36:** generated structs now declare `: TypedSegment` only; the protocol already refines
  `Sendable, Equatable, Hashable` (`Segment.swift:14`) and synthesis still fires — 109 decl
  lines shortened.
- **F34:** `renderGrammarTable` calls `versionDirName(_:)` instead of inlining its body.
  **F35:** dead `"GTS"` entry removed from `scalarDataTypes` (0 of 584 schemas use it).
  Both proven output-neutral: step-a regeneration was **byte-identical**.
- **F26 dropped per the plan's never-force rule:** `String(reflecting:)` escapes apostrophes
  (`Mother's` → `Mother\'s`), churning every possessive grammar-table name; the hand-rolled
  escaper stays, now with a comment recording why.
- Stage verification: step-b regenerate diff contained **only** the two intended line classes
  (116 import+blank removals; 109 decl rewrites); `swift test list` name-diff **empty**;
  suite **519/519 green**; build **warning-free** — the fresh full-module recompile surfaced
  one pre-existing `ExistentialAny` warning in `StreamingBatchParser.swift:142` (untouched
  since v0.3-S1), fixed in its own commit as `any Error`.

### R2 — dead `segmentCardinalityRules` schema axis removed (remediation stage 2 of 10)

F9 of `docs/design/remediation-plan.md`: the generator carried a full decode/render
axis for schema-side group-cardinality rules that **0 of 584** schema JSONs ever set
(ADR-010 Ext 2 authored the axis speculatively; an encoding axis with zero encoded rules is
plumbing, not spec surface — reinstate from git when a first universal rule is authored).

- Deleted `CardinalityRuleSchema`, the `SegmentSchema.segmentCardinalityRules` field, and the
  non-empty-rules branch of `renderGrammarTable` — 35 lines, all in `Codegen.swift`.
- The **runtime** `SegmentCardinalityRule` type and `Profile.cardinalityExtensions` are
  untouched — the AU profile's locale-scoped cardinality rules still ship through them.
- Verification: regenerated output **byte-identical** (`Generated/` diff empty); test-name
  diff **empty**; suite **519/519 green**; build warning-free.

### R3 — `CompositeView` protocol extraction + `AnyTypedSegment` cleanup (remediation stage 3 of 10)

F2 + F30 of `docs/design/remediation-plan.md`; net −217 lines, behaviour unchanged
under the CompositeTypeTests / ComponentGrammarTests / TypedSegmentTests pins.

- **F2:** the mechanics duplicated verbatim across all 16 composite structs — `componentValue(_:)`
  (md5-identical ×16), the `init(repetition:)` body, and the `Sendable, Equatable, Hashable`
  conformance list — hoisted into a new public `CompositeView` protocol + extension
  (`Composite/CompositeView.swift`). Each composite keeps its per-spec accessors, docs, `field`,
  `init(field:)`, and non-empty metadata. The 5 empty `requiredComponents = []` decls (CWE, EIP,
  HD, PL, XTN) now come from the protocol default; their stale docs went with them (HD's still
  described the `RequiredComponentSet` refactor as "explicitly avoided" — it shipped in v0.4-S4).
  `init(repetition:)` and the metadata statics remain publicly callable via the extension —
  additive under ADR-014.
- **F30:** `AnyTypedSegment.underlyingTypeName` deleted — private, stored, never read; `==` is
  unchanged because segmentID→type is a bijection via the generated registry.
- **F13 re-binned to R10:** tightening `RequiredComponentSet.init`'s `description: String? = nil`
  to a required `String` is a public signature change, prohibited in 1.x by ADR-014 — it now
  rides the v2.0.0 boundary with the other breaking removals.
- Verification: test-name diff **empty**; suite **519/519 green**; build warning-free.

### R4 — validator/locale shrinks, characterization-first (remediation stage 4 of 10)

F11 + F12 + F14 + F15 + F19 + F24; the first stage with red-first work. Two characterization
tests written and green against pre-refactor code BEFORE anything moved, both green after:

- **C1** (CrossSegmentDSLTests): the condition-DSL referent grammar rejects repetition
  (`PID-3~2`) and segment-index (`PID[N]-3`) forms fail-safe — on a wire whose plain `PID-3`
  IS populated, so a mis-resolving parser goes red.
- **C2** (LocaleAUProfileTests): one parameterized row per `.profileConstraintViolation` append
  site (7) pinning the EXACT message text, with the in-message citation cross-checked against
  the issue's own `localeRule` payload.

The refactors:

- **F11:** all 7 profile-issue constructions fold into `appendProfileIssue(citation:location:message:into:)`.
  Line-neutral (messages stay at call sites) — the win is drift-proofed severity/code/location
  plumbing, proven byte-identical by C2.
- **F14:** the Validator's second field-ref parser (`ParsedIndexSuffix`/`parseIndexSuffix`) is
  gone; both referent call sites parse via the shared `Path` parser through `parseDSLFieldRef`,
  which guards `segmentIndex == nil && repetition == nil`. Undocumented junk referents that
  accidentally resolved (`PID-+3`, 1-char IDs before the dash) now uniformly evaluate fail-safe
  false, aligning behaviour with the documented `SEG-f[.c[.s]]` grammar.
- **F12:** `ProfileLoader.swift` deleted; loading is `Profile.load(for:)` beside the type.
- **F15:** four hand-rolled nested-for population/needs-encoding scans → `contains(where:)`
  (`isRepetitionPopulated`, `isComponentPopulated`, `isFieldPopulated` now delegates,
  `EscapeSequences.needsEncoding`).
- **F19:** dead internal `Profile` members deleted: `isEmpty`, `none`, `baseVersion` (+ its
  init param and the AU factory argument).
- **F24:** the ORC group-boundary walk lives once as `Message.orcGroupRange(around:)`, shared
  by `associatedSegment` and the Validator's `.orcObxGroup` resolution — the two group
  definitions can no longer drift.
- Verification: suite **522 green** (519 + the 3 characterization test names — the exact
  enumerated addition, zero removals); build warning-free. Source net −54 lines, +81 test lines.

### Fixed — MSH-18 charset detection on batch wires (found by R5-C3)

`CharacterEncoding.probeMSH18` examined only the FIRST line of the probe and required it to
start with `MSH` — but every batch wire opens with FHS/BHS, so the batch Data path silently
fell back to UTF-8. A batch correctly declaring `MSH-18 = 8859/1` with Latin-1 bytes failed to
parse (throwing `unsupportedCharacterEncoding` citing the fallback's own `UNICODE UTF-8`),
contradicting `BatchParser`'s documented "probes the first MSH after any FHS / BHS" contract.
The probe now walks lines to the first MSH-prefixed one — a no-op for single-message wires.
Discovered by writing the R5-C3 characterization test the remediation plan ordered (the batch
Latin-1 leg had zero coverage); C3's two tests ship as the regression pin. Suite 522 → 524.

### R5 — parser/encoding shrinks (remediation stage 5 of 10)

F20 + F21 + F23 + F33 of `docs/design/remediation-plan.md`; refactor net −29 lines
under the ParsingTests / BatchParserTests (incl. C3) / CharacterEncodingTests /
EscapeSequenceTests / RoundTripTests pins.

- **F20:** the verbatim-duplicated wire-decode preamble (BOM strip, NUL reject, Latin-1 probe,
  MSH-18 detect, decode) lives once as internal `Parser.decodeWirePayload(_:)`, shared by both
  Data entry points so they can no longer drift — C3 pins the batch leg.
- **F21:** both hand-rolled closing-escape scans → `chars[(i + 1)...].firstIndex(of: esc)`;
  the `findClosingEscape` helper is deleted.
- **F23:** hand-rolled `hexDigitValue` → stdlib-backed `c.isASCII ? c.hexDigitValue : nil` —
  deliberately ASCII-gated: bare `Character.hexDigitValue` also accepts fullwidth compatibility
  digits, which are not valid in a wire `\X…\` body; the gate keeps behaviour byte-identical.
- **F33:** the two fully-spelled empty-Field literals → `.scalar("")` (byte-identical
  constructor chain).
- Verification: suite **524 green**; test-name diff vs R4 = exactly the two C3 pins (added by
  the fix commit); build warning-free.

### R6 — scripts + docs hygiene (remediation stage 6 of 10)

F7 + F16 + F18 + doc-rot healing of `docs/design/remediation-plan.md`.

- **F7:** `scripts/add-kernel-headers.sh` deleted — one-shot migration; all 9 kernel files
  verified to carry the `// PORTABLE KERNEL` marker; the CONTRIBUTING aside now says to copy
  the header from any existing kernel file.
- **F16:** the extractor's hand-rolled offset tokenizer → Swift Regex (`#/[^ ](?: [^ ]|[^ ])*/#`).
  The swap exposed a latent fidelity defect: the old scanner never appended single spaces to
  run text (its own comment claimed otherwise), so multi-word cells consumed as `run.text`
  were silently collapsed — v2.3 CH7's waveform `NA or MA` datatype cell extracted as `NAorMA`.
  Harness: two full-chapter extractions (v2.5.1 CH03 **byte-identical**; v2.3 CH7 differing in
  exactly that one now-PDF-verbatim row), the all-PDF depth audit **clean**, and zero schemas
  carrying either form — the 1-row delta ships as a documented fidelity improvement.
- **F18:** stale `Tests/Fixtures/README.md` ("none yet — sprint 3 work" beside 57 fixtures;
  citing a script that never existed) replaced via `git mv` — the live FIXTURES.md registry
  takes the name, and the referrers in CONTRIBUTING / the working notes / scan-fixtures-for-phi.sh
  became correct with zero edits. The 3-step adding-a-fixture policy folded in with the real
  pipeline named.
- **Doc-rot healing beyond the enumerated set:** the working notes's "add a case to
  SegmentRegistry.swift" step (registration has been fully codegen since ADR-015) and its
  "anonymisation script does not yet exist" claim; the same stale claim in the root README,
  CONTRIBUTING, and ROADMAP; six `anonymise-fixture.swift` / `FIXTURES.md` references in the
  Spec (incl. the §10 heading). Residual stale-referrer grep: **0**.
- Verification: suite **524 green**, test-name diff empty; PHI scan clean; depth audit clean.

### R7 — hydration-helper sweep (remediation stage 7 of 10)

F5 + F32; the first test-consolidation stage. Net −58 lines (−103 in the suites, +45 shared
support file), test list unchanged.

- 99 verbatim parse → `#require(firstSegment(…))` arrange pairs collapse to one line via new
  shared helpers (`Tests/HL7v2KitTests/TestSupport.swift`): `hydrated(_:from:)` and, for the
  67 tests that also cross-check path access against typed accessors, `hydratedMessage(_:from:)`
  (+ a `Data` overload for 3 fixture-wire tests). Failures attribute to the calling test via a
  `sourceLocation` pass-through.
- Sweep method: mechanical conversion to segment-only form, then a compiler-driven pass —
  "cannot find 'message'" errors enumerated the tuple-form sites exactly (326 → 0).
- **Honest scope correction:** the audit's 144-pair count conflated two shapes. The 39
  remaining CompositeTypeTests sites are `#require(firstSegment(T.self)?.accessor)` chains
  with later `message` use — an honest sweep saves ~zero lines there; left untouched per the
  never-force rule.
- F32: the orphan `// MARK: - AL1` deleted.
- Verification: suite **524 green**; test-name diff **empty**; zero warnings on full recompile.

### R8 — shared wire + fixture infrastructure (remediation stage 8 of 10)

F4 + F8 + F25; net ≈ −220 lines (−310 in the suites, +90 across two shared files).

- **F4:** the two canonical headers (`ADT^A01|MSG00001|P|2.5.1` ×56, its ORU/LAB twin ×15)
  now live once in `TestWires.swift`; 69 multiline wire literals became
  `TestWires.adt(…)`/`.oru(…)` builder calls with byte-identical construction. Headers whose
  content is under test — batch envelopes, AU MSH-12/17/19, version-detection, DSL
  ORU_R01-structure wires — stay inline by design.
- **F8:** the fixture-discovery chain re-implemented in six files now rides
  `FixtureCorpus.swift` (`validFixtureURLs`/`malformedFixtureURLs`/`batchFixtureURLs`/
  `fixtureURL(named:)`/`batchFixtureURL(named:)`), unified on the canonical Bundle-first
  resolution + sorted order — a deterministic superset of the three previously-unsorted copies.
- **F25:** the dead `Collection.subscript(safe:)` deleted with its MARK.
- Verification: suite **524 green**; test-name diff **empty**; zero diagnostics on rebuild.

### R9 — in-suite consolidation (remediation stage 9 of 10)

F3 + F10 + F27; net −174 lines. The only 1.x stage with a test-list delta — and the name diff
was verified equal to the enumerated fold map exactly.

- **F10:** the per-version detected / round-trip / validator triple (duplicated verbatim for
  v2.3 / v2.3.1 / v2.4) plus both standalone detected tests (v2.6, v2.8.2 — including the
  bare-2.8 legacy check, folded as a 6th detected row) → three `@Test(arguments:)`
  parameterized tests over shared row tables. Grammar-table PIN tests untouched — spec data.
  Fold map: 12 names removed → 3 added; suite count 524 → 515 (name-diff authoritative).
- **F3:** 13 inline `first { if case .profileConstraintViolation … }` closures in
  LocaleAUProfileTests folded into the merged
  `hasViolation(_:segmentID:fieldIndex:componentIndex:citing:)` helper (the two previous
  overloads merged into one optional-axis signature). Six `first{…}` sites remain by design:
  three extract the issue for further asserts, one is a negative OR-citation check, one a
  dual-token match, one a non-profile issue code.
- **F27:** `roundTripPreservesBody` deleted — a strict subset of `unframeSingleFrame`.
- Verification: suite **515 green** in 26 suites; name diff = the fold map exactly;
  warning-free. R10's `unknownSegment` disjunction lines re-located post-fold (:394/:443/:494/:749).

### R10 — BREAKING: the v2.0.0 capstone (remediation stage 10 of 10)

**The next release cut from this point is `v2.0.0`** (owner-scheduled 2026-08-27; ADR-014's
"waits for 2.0" lane, exercised for the first time). Every removal shipped dead — zero
construction/call sites, grep-verified at audit time and re-verified at removal. Full
migration table: `Migration.md` → "The 2.0 boundary".

- **Removed** (F6): the `HL7v2KitDictionaries` stub — library product, target, test target,
  and the never-imported dependency edge. −1 public product, −2 build targets, −1 test suite.
- **Removed** (F17): `BuilderError.invalidEncodingCharacters`, `BuilderError.duplicateMSH`,
  `ParseError.malformedField`, `IssueCode.unknownSegment` — never raised/emitted.
  (`ParseError.unknownSegment` is distinct, live, and stays.)
- **Removed** (F22/F28/F29/F31): `ParserOptions.preserveExcessFields` (documented no-op),
  `ValidationReport.empty`, `MessageBuilder.append(unknown:)`, `ParserOptions.lenient`
  (= `.default` field-for-field).
- **Changed** (F13): `RequiredComponentSet.init`'s `description` is now a required `String`;
  the generated-fallback `defaultDescription` is deleted — every shipped set already spelled
  its rule out explicitly.
- **Renamed** (the v1.6-deferred corrections): OBX-12 `effectiveDateOfReferenceRange` →
  `effectiveDateOfReferenceRangeValues`; OBX-15 `producersID` → `producersReference` —
  accessors now match the spec's element names (schema `swiftName` + regenerate; the
  Generated/ diff was exactly the two accessor declarations).
- Release scaffolding: `Migration.md` "The 2.0 boundary" section; ADR-014 addendum;
  same-stage test edits (ParseErrorTests description row; the four MultiVersion
  `unknownSegment` disjunctions collapse to `.zSegmentPresent`).
- Verification: suite **514 green in 25 suites**; test-name diff = exactly
  `DictionaryLoadingTests/scaffoldMarker()` removed; zero warnings.
- **Sequencing consequence:** `main` is now 2.0-bound — the AU coverage sprints
  (planned as v1.10–v1.15) ship as v2.x releases; plan labels are cycle names, not tags.

### M5 sweep — CH06 financial completion (v1.9)

Adds **FT1/PR1/ACC/UB1/UB2/DRG** (all six versions) and **ABS/GP1/GP2** (v2.4+) — 48 schema
instances, all passing the golden `--verify` gate. Typed count **100 → 109**. Closes out CH06
alongside GT1/IN1/IN2/IN3 from v1.2.

Where v1.8's batch had uniform depths across all versions, this one is the opposite: the
depths themselves carry the version signal, and they move a lot. `FT1` 25 → 26 (v2.3.1
errata) → 31 → **43** (v2.8.2); `PR1` 15 → 16 → 18 → 20 → 22 → **25**; `ACC` 6 → **13**; and
`DRG` nearly triples in v2.6, 11 → **33**. `UB1`/`UB2` are the counterexample — static at
23/17 on every version. `ABS`/`GP1`/`GP2` arrived in v2.4 and are absent from the two legacy
dialects.

**Two more conditional predicates ship rather than being documented.** `PR1-19` Procedure
Identifier and `PR1-20` Procedure Action Code both cite the Update Diagnosis/Procedures
trigger event — "required in all implementations employing … (P12) messages" and "required
for the … (P12) message. In all other events it is optional" — so both carry
`triggerEvent = P12` on v2.5.1 / v2.6 / v2.8.2 (they do not exist before v2.5; PR1 caps at
18 in v2.4). The permanent-limitation register is unchanged by this batch, and the guard test
needed no edit.

Note `BLG` is **not** part of this batch despite being a financial segment — it is defined in
CH04, not CH06, so it belongs to a later orders pass.

Audit after this batch: **integrity 0 findings across 584 schemas; depth 578 exact, 0 gaps,
0 suspects**. Tests: 518 → **519**.

### M5 sweep — CH07 completion: product experience + clinical trials (v1.8)

Adds **PES/PEO/PCR/PDC/PSH** (product experience) and **CSR/CSP/CSS/CTI** (clinical trials),
closing out CH07 alongside OBR/OBX/SPM. All nine exist on **every** supported version at
identical depth — 54 schema instances, all passing the golden `--verify` gate. Typed count
**91 → 100**.

Because the depths are uniform, every divergence here is in datatypes and element names —
precisely what a depth-only check misses: `TS → DTM` and `CE → CWE` in v2.6; `CTI-1` shortens
`Sponsor Study Identifier` → `Sponsor Study ID` after v2.3; `PEO-14` gains "Description" in
v2.6; and v2.3's `PDC-14/15` genuinely read `Date First/Last Marked`, corrected to `Marketed`
in v2.4 — a spec typo rendered faithfully (both the attribute table and the definition
heading agree).

### Added — six conditional predicates now ship instead of being documented

The clinical-trials family states its conditions explicitly, so these left the
permanent-limitation register rather than joining it (req #3/#4):

| Field | Predicate | Spec basis |
|---|---|---|
| CSR-9, CSR-10 | `triggerEvent = C01` | "required for the patient registration trigger event (C01)" |
| CSR-14, CSR-15, CSR-16 | `triggerEvent = C04` | "required for the off-study trigger event (C04)" |
| CTI-2 | `CTI-3 populated` | stated in **CTI-3's** definition, not CTI-2's |

Applied on all six versions (36 entries), each verified against that version's own
field-definition prose. Two lessons recorded: a field's condition is not always written in
its own entry, and version prose must be located by **stable ITEM number** — the v2.3-era
heading format omits the `SEG-N` prefix, so heading-shaped regexes silently miss it.
**CSP-4** is the batch's only remaining bare `C` (§7.8.2.4 states no trigger).

### Added — `scripts/audit-schemas.py`

The integrity + depth audit is now a committed contributor tool rather than an ad-hoc
script, since the working rules require running it after every batch. Shape-based predicates
(emptiness, length, character class, index continuity) plus the two-directional depth diff,
with RDT whitelisted and `docs/standards/` resolved from the primary worktree when run from a
cycle worktree. Dev-time only; `Package.swift.dependencies` stays empty.

Audit after this batch: **integrity 0 findings across 536 schemas; depth 530 exact, 0 gaps,
0 suspects** — the first fully clean sweep. Tests: 516 → **518**.

### M5 sweep — CH13 lab-automation completion (v1.7)

Sixth chapter closed out. Adds **ISD/NDS/CNS/ECD/ECR/SID** (CH13 clinical laboratory
automation) — full depth on every version they appear in. CH13 was introduced in **v2.4**, so
these six exist on v2.4 / v2.5.1 / v2.6 / v2.8.2 only; v2.3 and v2.3.1 have no CH13. Typed
count **85 → 91**; 24 new schema instances, all 24 passing the golden `--verify` gate.

Per-version divergence is captured rather than flattened: `CE → CWE` and `TS → DTM` in v2.6;
`ECR-3`/`ECD-5` widen `ST → TX` in v2.5.1; **ECD-4** Requested Completion Time goes
`O` (v2.4) → `B` (v2.5.1/v2.6) → **withdrawn with no datatype** (v2.8.2); and v2.6 renamed
`ISD-1` (dropping "(unique identifier)") and `SID-1` (closing up "Application / Method").

**The whole SID segment is conditional.** §13.4.11 marks all four fields `C` and states no
condition at all, so no DSL predicate is expressible — documented in
`conditional-completeness-audit.md` as the purest instance of that class (~132 positions).
The other five segments carry no `C` fields.

### Fixed — five more prose-bleed element names (v1.7)

A **name-length** audit predicate (`> 120` chars) found five instances of the v1.5-S2
prose-bleed class that the earlier *marker-word* regex had missed: `TQ2-10` (v2.5.1 / v2.6 /
v2.8.2 — up to 1069 characters of absorbed prose), `BPX-21` and `BTX-20` (v2.8.2). All three
segments were authored in v1.2 / v1.3, before the extractor's table-end and continuation
fixes, and had never been re-extracted. Corrected to `Special Service Request Relationship`,
`BP Dispensing Individual` and `BP Unique ID`, each confirmed against the CH04 tables.

Lesson recorded in `segment-coverage-extraction.md`: prefer a *shape* predicate (length,
character class) over an *enumerated content* predicate when auditing for corruption —
marker lists only find the corruption you already thought of.

Depth audit re-run across all six versions: **476 of 482** schemas match exactly, 0 suspects,
0 unlocated (the 6 remaining gaps are the known RDT `1-n` whitelist). Tests: 515 → **516**.

## [1.4.0] — 2026-08-20

M5 sweep — typed-segment coverage **57 → 85**, plus two correctness cycles that moved the
authored surface from *assumed* complete to *verified* against the spec. **452 of 458
committed schemas now match their own version's attribute table exactly** (the 6 exceptions
are RDT, a known `1-n` variable-column extractor limitation whose hand-authored schema is
correct). Additive throughout (ADR-014) — the frozen v1.0 API only grows. Tests: 513 → **515**.

Two shipped accessors keep names that now differ from their corrected element names —
`effectiveDateOfReferenceRange` (OBX-12) and `producersID` (OBX-15). Frozen public API;
rename at 2.0.

### Per-version field-depth audit (v1.6)

Correctness-only, additive. Every committed schema's depth was diffed against **its own
version's** attribute table — all tables in all chapters of all six versions extracted, then
compared by max field index in both directions.

**436 of 458 schemas matched on the first pass. 46 fields across 14 (version, segment) pairs
had never been authored**, all on core segments:

| Version | Segment | Was | Now |
|---|---|---|---|
| v2.3 | MSH / OBX / ORC | 15 / 11 / 17 | **19 / 17 / 19** |
| v2.3.1 | MSH / NTE / OBR / OBX / ORC | 17 / 3 / 43 / 14 / 17 | **20 / 4 / 45 / 17 / 24** |
| v2.4 | MSH / NTE / OBX / ORC / PID | 20 / 3 / 16 / 19 / 32 | **21 / 4 / 19 / 25 / 38** |
| v2.5.1 | OBX | 24 | **25** |

v2.5.1 OBX-25 (`Performing Organization Medical Director`) adds a typed accessor; the rest
deepen per-version grammar tables. All additive (ADR-014). After the fills: **452/458 exact,
0 suspects, 0 unlocated.** New pin test guards the fills and the naming rules below.

**Per-version element names must never be copied from the canonical schema.** HL7 renames
fields between versions, so the canonical name is often not that version's name:

| Field | v2.3 / v2.3.1 | v2.4 | v2.5.1 | v2.6 / v2.8.2 |
|---|---|---|---|---|
| OBX-12 | Date Last Obs Normal Values | Date Last Observation Normal Value | Effective Date of Reference Range **Values** | Effective Date of Reference Range |
| OBX-15 | Producer's ID | Producer's ID | Producer's **Reference** | Producer's ID |
| MSH-21 | — | **Conformance Statement ID** (`ID`) | Message Profile Identifier (`EI`) | Message Profile Identifier (`EI`) |

MSH-21 was renamed *and* retyped in v2.5 without changing the field count — a depth-only
audit could never have caught it.

**Fixed: two pre-existing name defects in the canonical v2.5.1 OBX schema** — OBX-12 was
truncated (missing `Values`) and OBX-15 carried the neighbouring versions' `Producer's ID`.
Their `swiftName`s are deliberately unchanged: `effectiveDateOfReferenceRange` and
`producersID` are shipped public API, frozen until 2.0 (ADR-014). The accessors keep their
names while their DocC text and grammar entries now read the spec's wording.

**Extractor:** caption matching widened to accept the singular (`Figure 2-10. ERR
attribute`), which had silently excluded v2.3 / v2.3.1 ERR from audit coverage. Documented
limitation: a `1-n` variable-column SEQ row (RDT-1, ADD-1) cannot be parsed, so RDT shows as
a permanent 6-row gap and must be whitelisted — its hand-authored schema is correct.

Tests: 514 → **515** green.

### Element-name fidelity (v1.5-S2)

Correctness-only. Fixes the element-name prose-bleed class — three distinct root causes in
the extractor, plus 14 surgical name corrections, each verified against the version's own
attribute table.

**Extractor:**

- **Table-end detection now accepts a lettered chapter number.** v2.8.2 splits the pharmacy
  chapter into 4 and **4A** and numbers sections `4A.4.3.0 RXC field definitions`; the
  digits-and-dots-only test missed those, so the table never ended and the entire
  field-definitions section was folded into the last row's element name.
- **Continuation folding is bounded** — a fragment is accepted as a wrapped name only if it
  is short, free of sentence punctuation and component-example markers, and keeps the name
  under 120 chars. Previously the explanatory note between a CH12 table and its definitions
  contaminated the last row.
- **Names are no longer truncated at the front.** Element names are *centred* under the
  `ELEMENT NAME` label, so long ones start left of the label offset and a fixed-offset slice
  cut their heads off (`Administered Tag Identifier` → `ministered Tag Identifier`). The
  boundary is now anchored on the rightmost 4–5 digit metadata run (ITEM #, or TBL # when
  the item number is blank), and the same boundary bounds metadata binning.
- **Empty-name rows are rejected when `DT` is under 2 characters**, not merely empty — every
  real HL7 datatype token is 2+ chars, so a 1-char DT is a wrapped-cell tail. v2.5.1
  `OBX-5`'s `varies` wraps as `varie` + `s`, and the orphan `s` was parsed as an extra row.

**Names corrected (14):** v2.8.2 `RXA-29` `Administered Tag Identifier`, `RXC-11` /
`RXG-33` `Dispense Units`, `RXD-35` `Dispense Tag Identifier`, `RXE-45` / `RXO-36`
`Pharmacy Phone Number`, `RXR-6` `Administration Site Modifier`; `PRB-25`
`Security/Sensitivity` (v2.3 / v2.3.1 / v2.4 / v2.5.1); `PRB-28` and v2.8.2 `GOL-22`
`Mood Code` (v2.6 / v2.8.2).

**Left alone as faithful (10):** the attribute tables literally print `Set ID- TXA` (v2.3 /
v2.3.1 / v2.4 / v2.6 / v2.8.2) and `Sequence Number- Test/Observation Master File` (v2.4
OM2–OM6) with no space after the hyphen, while the field-definition headings on the same
pages print them with spaces. The schemas follow the attribute table; rendering a spec typo
faithfully is correct (req #2).

Blast radius of the corrections is the grammar tables (`FieldGrammar.name` → validator
message text) and the reference surface, not Swift identifiers — typed structs generate from
the canonical v2.5.1 schemas only. Golden `--verify` sweep: 18/20 canonical segments pass
clean (OBR-32 is the documented intentional conditional upgrade; OBX surfaced the depth gap
noted above). Tests: **514** green.

### Extractor hardening + schema datatype fidelity (v1.5-S1)

Correctness-only. Fixes all three extractor items found during the v1.4 sweep and every
datatype defect the follow-up audit confirmed, each verified against the spec PDF rather
than against the extractor's own output.

**Extractor** (`scripts/extract-segment-tables.swift`, dev-time tool — not shipped):
column assignment now keys on nearest label **start** rather than run **centre** (fixes
values sitting right of the `DT` label, e.g. CH12 GOL, and a hair left, e.g. CH04 BPO);
rows with `seq < 1`, or with both an empty name and an empty `DT`, are rejected;
`deriveSwiftName` drops lone `s` fragments from possessives.

**Schema corrections:**

- **Phantom rows removed** — root-caused to **wrapped `LEN` digits** landing left of the
  `DT` column (OM6's `10240` leaves a bare `0`; EQP's `65536` leaves a bare `6`), not
  generic junk lines. Corrected depths: **OM1 49 → 47**, **OM4 17 → 14**, **OM6 3 → 2**,
  **EQP 6 → 5**. Depth pins updated.
- **GOL** — v2.5.1 fields 1/4/5 gain `ID`/`EI`/`EI`; **v2.3.1 fields 1–20** filled (were
  all empty; matches v2.3 / v2.4 per Figure 12-2).
- **RDT — corrected in all six versions.** v2.3 / v2.3.1 held the **SPR** segment's four
  fields; v2.4 / v2.5.1 / v2.6 / v2.8.2 held corrupted prose. Root cause: in v2.3 / v2.3.1
  RDT is defined in **Chapter 2 §2.24.19**, not CH05. Correct in every version: one field,
  `Column Value`, `OPT R`, ITEM 00703 — DT literal per-version (`Variable` for v2.3 / v2.3.1 /
  v2.4, `varies` for v2.5.1 / v2.6 / v2.8.2, tracked per-version as `TS`→`DTM` already is).
  `RP` stays `1`: the spec's `RP/#` cell is blank, so `*` would assert `~`-repeatability the
  spec does not grant. RDT's `1-n` unbounded-column semantic is recorded as a model
  limitation (req #3). RDT's typed accessor changes shape, which is ADR-014-clean only
  because v1.4 has not been released.

**Two audit rules recorded** in `segment-coverage-extraction.md`: an empty `dataType` is a
defect only when `OPT ∉ {W, X}` (`W`/`X` fields have no datatype by design — this made most
of the originally-flagged empty-DT set false positives); and wholesale/whitelist
regeneration is unsafe (it drops hand-authored `condition` predicates, reproduces
mis-binned datatypes, and title-cases element names), so datatype fixes must be surgical.

Tests: **514** green. The RDT pin now asserts field identity, not just count — the previous
count-only pin passed against an extractor-garbage field.

### M5 sweep — 14 new segments (master-file locations + patient-care + med-records)

Sixth sweep batch. Adds **LOC/LCH/LRL/LDP/LCC/CDM/PRC/IIM** (CH08 master files), **GOL/PRB/PTH/VAR** (CH12 patient care), **TXA/CON** (CH09 med records) — full-depth on every version they appear in. Typed count **71 → 85**. IIM moved CH08→CH17 across versions (sourced accordingly); CON is v2.6+. 13 conditional fields documented + guarded (~128 total). Tests: 514.

### M5 sweep — 14 new segments (query + lab-automation)

Fifth sweep batch. Adds **QPD/QRD/QRF/QAK/QID/RCP/RDF/RDT** (CH05 query) and
**EQU/SAC/INV/TCC/TCD/EQP** (CH13 lab automation) — each full-depth on every version it
appears in. Typed-segment count **57 → 71**. v2.3 query segments sourced from CH2 (v2.3
CH5 is an empty placeholder); QPD/QID/RCP are v2.4+; lab-automation is v2.5+. 6 new
conditional fields documented + guarded. Additive (ADR-014). Tests: 514.

## [1.3.0] — 2026-07-13

M5 sweep — typed-segment coverage **29 → 57** (two batches). Additive / correctness only;
the frozen v1.0 API grows but never breaks (ADR-014). Tests: 510 → **513**.

### M5 sweep — 14 new segments (master-files + referral)

Fourth sweep batch. Adds **MFI/MFE/MFA + OM1–OM7** (CH08 master files) and
**RF1/AUT/PRD/CTD** (CH11 referral) — each full-depth on every version it appears in.
Typed-segment count **43 → 57**. OM7 is v2.4+; v2.8.2 notably expands OM1 (47→59), RF1
(12→25), AUT (10→29). Extractor-seeded + golden-`--verify`ed; additive (ADR-014). 5 new
conditional fields (MFE-2/MFA-2/OM7-16/OM7-18/AUT-6) documented + guarded. Tests: 513.

### M5 sweep — 14 new segments (scheduling / blood-product / specimen / role)

Third sweep cycle. Adds **SPM** (CH07), **ROL** (CH15), the CH10 scheduling family
(**SCH/RGS/AIS/AIG/AIL/AIP/APR/ARQ**), and blood-product **BPO/BPX/BTX** + **RXA** (CH04).
Typed-segment count **29 → 43**, each full-depth on every version it appears in.
Extractor-seeded + golden-`--verify`ed; additive API growth only (ADR-014). Tests: 512.

- **RXA** resolves to the base "Pharmacy/Treatment Administration" table (26 fields), not
  the "Segment Uses in Vaccine Messages" profile table that follows it — pinned by test.
- **Extractor reliability fix:** `detectHeader` now accepts the legacy `R/O/C`
  optionality-column header. v2.3 CH10 uses it, so the whole scheduling chapter had been
  silently skipped; all v2.3 scheduling grammar is now present. Golden v2.5.1 unaffected.
- **Conditional-completeness:** 55 new conditional-without-trigger fields
  (scheduling/blood-product/specimen/role) bulk-documented + added to the v2.8.2 guard set
  (fail-safe; ~104 documented total).

## [1.2.0] — 2026-07-13

M5 sweep — typed-segment coverage **15 → 29**, all at full per-version depth. Additive /
correctness only; the frozen v1.0 API grows but never breaks (ADR-014). Tests: 504 → **510**.

### M5 sweep — 8 new order/pharmacy/timing segments + extractor reliability fix

Third cycle of the M5 sweep. Adds **TQ1, TQ2, RXO, RXR, RXC, RXE, RXD, RXG** (CH04/CH04A)
as typed segments — the typed-segment count goes **21 → 29** — each full-depth on every
version it appears in. Tests: 507 → **510**.

- **Canonical v2.5.1 depths:** TQ1 14, TQ2 10, RXO 28, RXR 6, RXC 9, RXE 44, RXD 33, RXG 26.
  Per-version depths grow monotonically (RXE 30→45, RXO 22→36); TQ1/TQ2 are v2.5+.
- **Extractor reliability fix:** SEQ detection now uses the first token before the DT
  column, not a fixed header-offset slice — recovering legacy v2.3 CH4 tables (RXO/RXC/RXG)
  that the old slice silently dropped, and correcting v2.3 RXR 6→4. Golden `--verify`
  unaffected. A general fix for all legacy-chapter sweeps.
- **Conditional-completeness:** these are HL7's most conditional-heavy segments — 31 new
  C-without-expressible-trigger fields, bulk-documented in the register + the v2.8.2 guard
  set (fail-safe, never shipped as rules; req #4).

### M5 sweep — 6 new typed segments (PV2, MRG, DB1, GT1, IN2, IN3)

Second cycle of the M5 sweep. Adds **PV2, MRG, DB1** (CH03) and **GT1, IN2, IN3** (CH06)
as first-class typed segments — the typed-segment count goes **15 → 21**. Each is modelled
at full field depth on every version it appears in (36 schemas: canonical v2.5.1 + 30
per-version), extractor-seeded and golden-`--verify`ed. Auto-registered via the generated
`SegmentRegistry`; additive API growth only (ADR-014). Tests: 505 → **507**.

- **Canonical v2.5.1 depths:** PV2 49, MRG 7, DB1 8, GT1 57, IN2 72, IN3 25. Per-version
  depths vary (e.g. PV2 37→50, GT1 55→57, IN3 25→27).
- **Codegen:** now backtick-escapes Swift-keyword swiftNames (IN3-8 "Operator" →
  `` `operator` ``) — general safety; grammar-table names stay faithful.
- **Conditional-completeness:** PV2-1/45/47 are conditional-without-expressible-trigger —
  added to the register + the v2.8.2 guard-test set (documented, fail-safe).
- **Tooling:** the extractor gains a reusable `--emit-schema` seed generator.

### M5 sweep — per-version NK1/PV1/IN1 full depth

First segment-coverage cycle of the M5 sweep. Extends **NK1 / PV1 / IN1** from the
curated caps (13 / 20 / 25) to **full per-version field depth** on every non-canonical
version — closing the immediate coverage gap. Extractor-seeded (ADR-015 `--emit-schema`)
and verified: all 15 schemas pass the golden `--verify` (DT/OPT/RP + counts). Additive,
grammar-table-only — typed structs generate from canonical v2.5.1 (unchanged); the frozen
v1.0 API is untouched (ADR-014). Tests: 504 → **505**.

- **Full per-version depths** (field counts grow across the standard):
  - v2.3 / v2.3.1 / v2.4 — NK1 **37**, PV1 **52**, IN1 **49**
  - v2.6 — NK1 **39**, PV1 **52**, IN1 **53**
  - v2.8.2 — NK1 **41**, PV1 **54**, IN1 **55**
- **Version divergences captured verbatim:** v2.3-era coded fields stay `IS` (pre CE→CWE);
  v2.6 CE→CWE + TS→DTM wave; v2.8.2 full CWE promotion, new NK1-40/41 telecommunication-info
  fields, and `B`-demotion of the legacy phone fields.
- **Tooling:** the extractor gains a reusable `--emit-schema` mode (swiftNames mapped from a
  reference schema) + element-name glyph normalization; `MultiVersionTests` depth pins
  updated + a new v1.2 divergence pin.

## [1.1.0] — 2026-07-12

### M5 foundation — extraction pipeline, canonical corrections, segment inventory (ADR-015)

The opening of ROADMAP **M5** (full HL7 segment coverage across all versions — the gate on
the first public push). **Additive / correctness only; the frozen v1.0 public API grows but
never breaks** (ADR-014). Tests: 501 → **504** across 26 suites.

**Added — the extraction pipeline (ADR-015).** `scripts/extract-segment-tables.swift` parses
segment attribute tables from the Final-Standard PDFs via `pdftotext -layout`, recovering every
column (`SEQ/LEN/DT/OPT/RP/#/TBL#/ITEM#/NAME`) cleanly across **all six versions** (v2.3→v2.8.2).
This retires the "legacy `RP/#` columns don't extract cleanly" blocker that v0.19 documented and
that M5 was gated on. Dev-time tool only — **`Package.swift` has no new dependency**. See
`docs/design/segment-coverage-extraction.md` (+ its `--verify` golden gate).

**Fixed — 11 canonical v2.5.1 metadata defects** surfaced by the pipeline's golden audit
(concentrated in the `OPT`/`RP/#` columns the prior PDFKit hand-authoring mis-read):

- Optionality: **PV1-9 / PV1-40 / PV1-52** and **IN1-38 / IN1-40 / IN1-41** were `O`, spec is `B`
  (backward-compatibility); **MSA-5** was `X`/`ST`, spec is `W` (withdrawn).
- Repeatability: **NK1-26**, **PID-38**, **PV1-45** are repeatable (`RP/# = Y`/max) — were single;
  **PV1-50** is single — was over-marked repeatable.

**Added — completed two incomplete canonical segments** (real v2.5.1 fields never authored;
additive typed accessors):

- **OBR** 47 → **50** — 48 Medically Necessary Duplicate Procedure Reason (CWE, C), 49 Result
  Handling (IS, O), 50 Parent Universal Service Identifier (CWE, O).
- **OBX** 17 → **24** — 18 Equipment Instance Identifier (EI), 19 Date/Time of the Analysis (TS),
  20/21/22 Reserved for harmonization with V2.6 (X), 23 Performing Organization Name (XON),
  24 Performing Organization Address (XAD).

**Added — segment inventory** (`docs/design/segment-inventory.md`): the M5 work-list — 188
distinct segments across the six versions (per-version 106→180), ~850 schema-instances for
full-depth coverage vs. 15 typed today. Plus ADR-015 and 3 new cross-check pin tests.

## [1.0.0] — 2026-07-09

> **Note (post-tag, 2026-07-09):** the owner reframed the v1.0 completeness bar to require **full HL7 segment coverage across all versions** (ROADMAP M5). `v1.0.0` stays the API-freeze tag but is **provisional on `private`**; the first public push is gated on M5.

**API-freeze release.** The public API is frozen under the ADR-014 evolution contract; from here, `1.x` releases are additive-only (new enum cases on the open enums, new types/methods) — removals, renames, and signature changes wait for `2.0`. Milestone status at tag time:

- **M1 — Version coverage:** full per-version field grammar + validation for **v2.3, v2.3.1, v2.4, v2.5.1, v2.6, v2.8.2** (the complete published-standard set an integrator reference targets). A bare `2.8` wire is recognised but grammar-less (ADR-013).
- **M2 — Conformance surface:** every rule is either validated or documented as a spec-cited permanent limitation with a v1.0 freeze decision — the conditional-completeness register (`docs/design/conditional-completeness-audit.md`) + the permanent-limitations register (`docs/design/permanent-limitations-register.md`).
- **M3 — API stabilisation:** ADR-014 evolution policy, the public-surface inventory (`docs/design/public-api-surface.md`), and the finalised versioning contract (`Migration.md`).
- **M4 — Distribution:** the external IP review has **cleared** — the first public push is unblocked.

No source change vs `v0.19.0`; v1.0.0 is the stability-commitment tag. The v1.0 public surface: `Parser` / `BatchParser` / `StreamingBatchParser`, `MessageBuilder`, path + typed-accessor APIs, 15 typed segments + 16 typed composites, `Validator` (+ `HL7Locale.auLocalisation`), and the MLLP codec. Tests: 501 across 26 suites.

### Capability summary (shipped across 0.1 → 0.19, frozen at 1.0)

- Lossless parse ↔ serialise round-trip; BOM/NUL hardening; character-set detection (UTF-8 / ASCII / ISO-8859-1).
- Validation DSL: same-segment compound predicates, cross-segment / message-context / segment-presence atoms, subcomponent-granular field-refs, group-scope cardinality, component-level required-component checks.
- AU ADRM-2021 profile (HL7au:000003–000008, 000040–000042, machine-checkable 00044.* CE/CNE/CWE narrowings).
- `FieldOptionality` R/O/C/X/B/W; codegen'd typed segments + composites; zero runtime dependencies.

## [0.19.0] — 2026-07-09

req-#1 feature-completeness — extend the canonical v2.5.1 NK1 / PV1 / IN1 schemas to their full HL7 field set. Since the canonical version drives the typed-segment structs, this delivers the full typed-accessor surface for these three segments. **Additive only** (ADR-014 §open): typed structs gain accessors; no existing accessor changes; the v2.5.1 grammar table gains fields. Tests: 499 → 501 across 26 suites.

### Added — full canonical field depth for NK1 / PV1 / IN1

- **NK1** 13 → **39** fields (HL7 v2.5.1 §3.4.5) — Marital Status … VIP Indicator.
- **PV1** 20 → **52** fields (§3.4.3) — Charge Price Indicator … Other Healthcare Provider.
- **IN1** 25 → **53** fields (§6.5.6) — Report of Eligibility Date … VIP Indicator (incl. IN1-28 Pre-Admit Cert).

Field index / name / datatype and optionality are spec-verified (all extended fields `O`; only NK1-1 / PV1-2 / IN1-1/2/3 are `R`). Repeatability follows the HL7 v2.5.1 standard shape — the attribute-table `RP/#` column doesn't extract cleanly, so it's a documented, fail-safe best-effort (see `docs/design/full-segment-audit.md`).

### Scope (documented follow-on, not a gap)

**Canonical v2.5.1 only.** The per-version grammar tables (v2.3 / v2.3.1 / v2.4 / v2.6 / v2.8.2) for NK1/PV1/IN1 stay at curated depth (13/20/25) pending a follow-on cycle — typed-accessor coverage is now full (version-agnostic), but per-version *validation* of the extended fields on non-v2.5.1 wires is still limited to the modelled range.

### Added — regression pins

`TypedSegmentTests` (+2): full-canonical field counts + datatypes + held `R` fields; a new scalar typed accessor (NK1-37) hydrates and agrees with the path.

## [0.18.0] — 2026-07-09

ROADMAP M3 (API stabilisation) — the last v1.0 engineering gate. Settles the public API evolution policy, audits the full public surface, and finalises the migration contract. **No behaviour change; the only code change is added DocC notes.** Tests unchanged at 499 across 26 suites. **With M3 closed, M1 + M2 + M3 are all done — v1.0 is tag-able on the private repo (only M4 external IP review remains).**

### Added — ADR-014 public API evolution policy

Documented SemVer evolution contract; **no `@frozen`** (inert for this SPM *source* package with no library-evolution mode). Public enums classified **open** (`Version`, `HL7Locale`, `IssueCode`, `ParseError`, `PathError`, `BuilderError` — may gain cases in a 1.x minor; consumers switch with `@unknown default`) vs **stable** (`FieldOptionality`, `FieldRepeatability`, `IssueSeverity`, `ZSegmentPolicy`, `LineTerminatorPolicy`, `CharacterEncoding`, `RequiredComponentSet.Semantics`, `Segment` — domain-closed). 1.x is additive-only; removals / renames / signature changes wait for 2.0.

### Added — `docs/design/public-api-surface.md`

The v1.0 public-symbol inventory: 74 public types (59 hand-written + 15 codegen'd typed segments), each confirmed intended / minimal / documented, every enum classified open/stable. No accidentally-`public` internals.

### Changed — open-enum DocC + finalised `Migration.md`

The six open enums each gained a `- Note:` telling consumers to switch with `@unknown default` (`ParseError` / `PathError` / `BuilderError` also gained a type-level summary comment). `Migration.md` rewritten from its stale 0.2.0-era content into the v1.0 versioning contract (additive-only rule, open/stable lists, the v0.5.0→v0.17 additive-case history, v1.0 gates).

## [0.17.0] — 2026-07-09

ROADMAP M2 close-out. Consolidates the AU-narrowing and terminology/PKI/history permanent limitations into a single authoritative register and formally closes M2 (conformance-surface finalisation). **Documentation only — no code or API change.** Tests unchanged at 499 across 26 suites.

### Added — `docs/design/permanent-limitations-register.md`

The authoritative list of conformance rules HL7v2Kit cannot machine-check from the wire, each spec-cited and freeze-decided for v1.0: the AU narrowings (HL7au:00044.4.3 CE-text carve-out, 00044.4.7 concept-match, 00044.2 NASH PKI, 00044.1.2/.1.3, HL7au:000001 order addressing) and the cross-cutting terminology / PKI / cross-message-history classes. References the v0.16 conditional-completeness register for the base-spec conditional set. Records what is explicitly **not** a limitation (NUL/BOM handling, grammar-less `.v2_8`, curated NK1/PV1/IN1 depth) to prevent re-litigation.

### Closed — ROADMAP M2

With the v0.16 conditional register (base-spec `C`-without-`condition`) and this register (AU + terminology/PKI/history), every conformance rule is now either validated or documented as a spec-cited permanent limitation with an explicit v1.0 freeze decision. **Decision recorded: all current limitations are acceptable to freeze — none blocks v1.0.** The remaining v1.0 engineering gate is **M3** (API stabilisation).

## [0.16.0] — 2026-07-09

ROADMAP M2 conditional-completeness cycle. Audited every grammar field marked `C` (conditional) that carried no `condition` predicate — 69 instances across 17 distinct segment-index positions — and either shipped a spec-citable predicate or recorded it as a documented permanent limitation. **No public-API change** (both shipped predicates reuse the existing v0.4-S4 same-segment DSL; the condition strings are internal schema metadata). v1.0 stability clock continues from v0.5.0. Tests: 495 → 499 across 26 suites.

### Added — `docs/design/conditional-completeness-audit.md` (M2 register)

The authoritative conditional-completeness register: per-position verdict (ship / permanent limitation) with spec citations. This is the M2 gate for v1.0 — the conditional surface is now either shipped or explicitly, spec-citably documented.

### Fixed — two v2.8.2 conditions the v0.15 authoring left as bare `C`

A spec predicate existed for these but was not extracted during v0.15 (fail-safe, so no misfire — but incomplete per req #4):

- **PD1-15 Advance Directive Code** — `PD1-22 populated` (exact; v2.8.2 §3.3.11.15 "required when PD1-22 - Advance Directive Last Verified Date is valued").
- **ORC-26 Advanced Beneficiary Notice Override Reason** — `ORC-20 in (3, 4)` (v2.8.2 §4.5.1.26; HL7 Table 0339 not-signed codes). **Partial** — external code systems may encode "not signed" with other values (documented, same honesty pattern as HL7au:00044.4.4); a sound necessary condition that cannot misfire on HL7-standard traffic.

### Documented — 15 permanent limitations (req #3/#4)

OBR-1/8/9/10/11/20/21/22/26/32, OBR-48, OBX-4/5/22, DG1-22 carry `C` in their attribute tables but no wire-detectable required-when trigger (discourse-level, data-nature-dependent, peer-comparison, or descriptive-without-cited-MUST). Each stays fail-safe (treated as optional) and never misfires. See the register for per-field rationale.

### Added — regression pins

`MultiVersionTests` (+4): PD1-15 fires (PD1-22 populated + PD1-15 empty); ORC-26 fires (ORC-20=3) and does NOT fire (ORC-20=1, a signed value); a guard asserts the v2.8.2 permanent-limitation set stays `C`-without-`condition` (catches any future accidental bare-`C` field).

## [0.15.0] — 2026-07-09

ADR-013 first-class v2.8.2 grammar cycle. Adds `Version.v2_8_2` and a full v2.8.2 grammar table (15 segments) — coverage now spans v2.3 → v2.8.2, the latest published HL7 v2.x standard (ROADMAP M1 track). **Additive public-API change** (`Version.v2_8_2 = "2.8.2"`; the grammar-less `.v2_8 = "2.8"` is retained — distinct MSH-12 raw value, no fold). **No new `FieldOptionality` case** — `.withdrawn` (v0.14) covers every v2.8.2 `W`. v1.0 stability clock continues from v0.5.0. Tests: 488 → 495 across 26 suites.

### Added — `Version.v2_8_2` + 15 v2.8.2 segment schemas

`case v2_8_2 = "2.8.2"` (after `v2_6`, before `v2_8`); `grammarTable(for:)` wired; `SegmentGrammar+v2_8_2.swift` emits. Segments authored under `Resources/schemas/v2.8.2/` from the v2.8.2 Final Standard PDFs (CH02/03/04/06/07), preserving every v2.8.2-vs-v2.6 divergence verbatim: MSH/MSA/ERR/EVN/NTE (S1); PID/PD1/NK1/PV1/AL1 (S2); ORC/OBR/OBX (S3); DG1/IN1 (S4). Divergence classes (see `docs/design/v2_8_2-spec-audit.md`):

- **`IS → CWE`** — the dominant coded-field promotion wave (ERR-9, EVN-4, PD1/PV1/DG1/IN1 coded fields, PID-8/32, OBX-8).
- **`B → W`** — 2.7-era withdrawals (MSA-3/5/6, ERR-1, EVN-1, PD1-4, PID-2/4/9/12/19/20/28, AL1-6, OBR-5/6/14/15/27, ORC-7).
- **`O → B`** — new backward-compat demotions across ORC/OBR/OBX/PID/PD1/PV1.
- **Conditionals restructured** — v2.6 vet conditionals dropped (PID-35 `C→O` renamed "Taxonomic Classification Code", PID-36 `C→B`); parent-order XOR dropped (ORC-8, OBR-29 `C→O`); new predicate-less `C` fields recorded conditional-without-condition (PD1-15, ORC-26, OBR-48, DG1-22).
- **Other datatype/name changes** — `EI→EIP` (ORC-4), `ST→OG` (OBX-4), `ID→NM` (DG1-15), `ST→CWE` (OBR-13); renames (OBX-8 "Interpretation Codes", IN1-2 "Health Plan ID").
- **Field-count growth** — PID 39→40, ORC 31→34, OBR 50→54, OBX 25→30; new fields authored from v2.8.2 prose.

### Method note

The OBX base attribute table (CH07 p51) was used, **not** the four `Example - <cat> Category` profile tables (p153–155) whose `X` markings are example-specific — a trap flagged in the audit doc.

### Known limitations (documented, not shipped — req #3/#4)

- **PD1-15 / ORC-26 / OBR-48 / DG1-22 / OBX-22** — `C` with no extractable predicate; recorded conditional-without-condition (never fire).
- **NK1 / PV1 / IN1** — curated to the shared typed-segment depth (13 / 20 / 25); full v2.8.2 sets (41 / 54 / 53) unmodelled — a cross-version req-#1 backlog item.

### Added — regression pins

`MultiVersionTests` (+7): version detection incl. `.v2_8`/`.v2_8_2` coexistence; S1–S4 grammar-table field counts + divergences; S1 dispatch no-unknown-segment; and `v282CleanORUHasNoErrors` (well-formed v2.8.2 ORU^R01 → zero errors).

## [0.14.0] — 2026-07-09

ADR-012 first-class v2.6 grammar cycle. Adds `Version.v2_6` and a full v2.6 grammar table (15 segments), closing the last common-version coverage gap (ROADMAP M1). Before this, a `2.6` wire fell back to `.v2_5_1` or threw `.unsupportedVersion`; it now dispatches to per-field v2.6 validation. **Additive public-API change** (`Version.v2_6` — precedented by `v2_8`; and `FieldOptionality.withdrawn` — a new case on the non-`@frozen` optionality enum); v1.0 stability clock continues from v0.5.0. Tests: 482 → 488 across 26 suites.

### Added — `Version.v2_6` + 15 v2.6 segment schemas

`case v2_6 = "2.6"` (between `v2_5_1` and `v2_8`); `grammarTable(for:)` wired; the regenerate path emits `SegmentGrammar+v2_6.swift`. Segments authored under `Resources/schemas/v2.6/`, each from the v2.6 Final Standard PDFs (CH02/03/04/06/07), preserving every v2.6-vs-v2.5.1 divergence verbatim: MSH, MSA, ERR, EVN, NTE (S1); PID, PD1, NK1, PV1, AL1 (S2); ORC, OBR, OBX (S3); DG1, IN1 (S4). Divergence classes (see `docs/design/v2_6-spec-audit.md`):

- **TS → DTM** — systematic across every timestamp field.
- **CE → CWE** — field-by-field (verified per header, not blanket); OBR-44/45 went to **CNE**, not CWE.
- **Field-count growth** — MSH 21→25, MSA 6→8, NTE 4→8, PD1 21→22, OBR 47→50, OBX 17→25, DG1 21→26; new fields authored from v2.6 prose.
- **Structural conditions** carried verbatim (unchanged in v2.6 spec text): ORC-2/3/8, OBR-2/3/7/14/25/29, OBX-2, PID-35/36, DG1-20/21.

### Added — `FieldOptionality.withdrawn` (`W`) model extension (req #3)

v2.6 is the first modelled version to use the `W` (withdrawn) OPT code — DG1-2/4 and the DRG/outlier block DG1-7..14 were withdrawn (DRG detail moved to the new DRG segment). `W` is distinct from `B` (retained for compatibility); mapping `W → B` would misrepresent the spec (req #4). Added `FieldOptionality.withdrawn = "W"`; codegen maps `"W" → .withdrawn`; `Validator.checkDeprecation` warns (`.fieldNotSupported`) on a populated withdrawn field — same warn-on-populated family as `B`/`X`.

### Known limitations (documented, not shipped — req #3/#4)

- **OBX-22 Mood Code** is `C` in the v2.6 attribute table but the prose gives no extractable predicate; recorded as a conditional-without-condition (falls through as optional, never fires) rather than inventing a rule that could misfire.
- **IN1** mirrors the shared 25-field curation across all versions (not the full ~53-field v2.6 IN1) — a carried scope limitation, not a v2.6 regression.

### Added — regression pins

`MultiVersionTests` (+6): grammar-table field counts + divergences per substage (S1–S4), the populated-withdrawn-field warning (`v26WithdrawnFieldWarns`), and a well-formed v2.6 ORU^R01 that validates with zero errors (`v26CleanORUHasNoErrors`) — end-to-end proof the carried conditions don't over-fire.

## [0.13.1] — 2026-07-04

### Changed — retired orphaned AU profile JSON overlays (maintenance)

Deleted `Resources/profiles/au-adrm-2021/{MSH,OBR,ORC,datatypes}.json`. These files were authored partially in v0.5–v0.8 as the "editable spec source" ADR-007 envisioned, but `ProfileLoader` always returned the hand-curated `Profile.auADRM2021` Swift and never read the JSON — so they were dead code that had drifted stale (missing the v0.8 MSH-12, v0.11 `cardinalityExtensions`, and v0.13 `componentInequalities` / `valueConditionals` rules). Removing them eliminates the "hand-synced JSON↔Swift drift risk" flagged in the runway by deleting the unused second representation; the compiler-checked Swift is now the acknowledged single source of truth. A JSON-driven codegen path (ADR-004 principle) is deferred until a second localisation profile makes shared tooling worthwhile. Comments in `Profile+au_adrm_2021.swift` / `ProfileLoader.swift` corrected; ADR-007 carries a v0.14 status note. **No behaviour or API change**; 475 / 475 tests unchanged.

## [0.13.0] — 2026-07-04

ADR-011 composite-override extension cycle. Adds two internal rule axes to `CompositeOverride` and ships four previously-deferred HL7au:00044.* CE/CNE/CWE datatype conformance points. **No public-API change** (composite-override types are internal per ADR-007; both new rules reuse `.profileConstraintViolation`, no new `ValidationIssue.Kind` case); v1.0 stability clock continues from v0.5.0. Tests: 469 → 475 across 26 suites. Single functional commit + release commit.

### Added — composite-override model extensions (ADR-011)

- **`ComponentInequality`** `{ componentA, componentB, specCitation }` — "two named components must carry different values when both populated." Fires `.profileConstraintViolation` on equal values; no-op when either is empty.
- **`ComponentValueConditional`** `{ component, deniedValues, condition?, specCitation }` — "component must not carry a denied value," with an optional v0.7-DSL message-context gate (reuses the ADR-009 `conditionTriggers` entry point). No-op on empty component or gate-false.
- `CompositeOverride` gains `componentInequalities` + `valueConditionals` (defaulted empty). `Validator.checkProfileCompositeOverrides` gains two inner loops (Track 3 / Track 4).

### Added — HL7au:00044 CE/CNE/CWE conformance points

- **44.4.8** (CE) — alternate coding system (CE-6) must differ from primary (CE-3). `ComponentInequality(3, 6)`.
- **44.4.4** (CE, Orders/Results) — LOINC (LN) must be the primary coding system, not the alternate. `ComponentValueConditional(6, ["LN"], "messageCode in (ORM, ORU)")`. Shipped as a machine-checkable *necessary condition* ("LN must not appear in CE-6"), not the full placement rule — flagged partial (same honesty pattern as v0.10 OBR-7).
- **44.5.3** (CNE) / **44.6.3** (CWE) — `<text>` component (CNE-2 / CWE-2) must be valued. `requiredComponents: [2]` (existing model, no carve-out unlike CE-2).

### Known limitations (documented, not shipped — req #3/#4)

- **44.4.3** (CE `<text>`) — carries an explicit "in some locations user display is not intended and the text may be blank" carve-out; not wire-detectable, an unconditional rule would over-fire. Permanent limitation unless a wire signal for the blank-allowed locations emerges.
- **44.4.7** (CE concept-match) — "identifier and alternate identifier must reflect the same concept" requires a terminology service; not machine-checkable from the wire. Permanent limitation.
- **44.5.7 / 44.6.7** (CNE/CWE concept-match) — marked "Removed" in ADRM r2; not applicable.

### Regression pins

Six in `LocaleAUProfileTests`: 44.4.8 fires (equal CE-3/CE-6) + silent (distinct); 44.4.4 fires (LOINC in CE-6 on ORU) + gated-silent (LOINC in CE-6 on ADT); 44.6.3 (ERR-3 CWE empty text); 44.5.3 (ORC-30 CNE empty text).

## [0.12.0] — 2026-07-03

v2.3 / v2.3.1 T-track grammar back-port. Authors the six T-track segments (EVN / MSA / ERR / PD1 / DG1 / IN1) into the v2.3 and v2.3.1 grammar tables, mirroring the v0.6 v2.4 back-port. Before this, a v2.3 / v2.3.1 wire carrying any of these segments hit the "unknown segment" (Z-segment) path — now they dispatch to per-version field-level validation. Closes the T-track per-version coverage gap documented in `docs/design/v2_3-v2_4-spec-audit.md`. **No public-API change** vs v0.11.0 (typed-segment structs are version-agnostic and already existed); v1.0 stability clock continues from v0.5.0. Tests: 466 → 469 across 26 suites.

### Added — 12 new per-version schemas

Six segments × two versions authored under `Resources/schemas/v2.3/` and `Resources/schemas/v2.3.1/`, each from the version's own spec PDF (v2.3 CH2/CH3/CH6; v2.3.1 combined Final Standard). Per-version field shapes preserved verbatim:

- **EVN** — 6 fields on v2.3 / v2.3.1 (no EVN-7 Event Facility; that arrived in v2.4).
- **MSA** — 6 fields; identical to v2.4.
- **ERR** — single `CM` field (Error Code and Location); identical to v2.4.
- **PD1** — 12 fields on v2.3 / v2.3.1 (v2.4 expanded to 21).
- **DG1** — 19 fields. Divergences: DG1-2 (Coding Method) is `R` on v2.3 / v2.3.1 (v2.4 downgraded to `B`); DG1-15 (Diagnosis Priority) is `NM` on v2.3, revised to `ID` on v2.3.1 (matching v2.4).
- **IN1** — 25-field curation (shared typed-segment surface). Divergences: IN1-14 (Authorization Information) is `CM` on v2.3 / v2.3.1 (v2.4 retyped to `AUI`); IN1-17 (Insured's Relationship To Patient) is `IS` on v2.3, revised to `CE` on v2.3.1 (matching v2.4). Field optionality follows the v2.4 curation (R on IN1-1/2/3) — the v2.3 CH6 OPT column resisted clean PDF extraction; types + field count are exact. Documented in the audit doc.

### Added — regression pins

`MultiVersionTests`: `v23BackportedSegmentsRecognised` + `v231BackportedSegmentsRecognised` (segments dispatch to the version grammar, no unknown-segment), `v23DG1RequiredFieldsFire` (DG1-1/2/6 required-field misses fire; proves the v2.3-specific DG1-2 = R is enforced). Extended `grammarTablePopulated` (v2.3.1) + `v23GrammarTablePopulated` (v2.3) with the 6 new segment counts + the DG1-15 / IN1-17 errata-delta type assertions.

## [0.11.0] — 2026-07-03

ADR-010 DSL-extension cycle. Ships three new predicate/grammar primitives (segment-presence atoms, group-scope cardinality rules, subcomponent-granular field-refs) and applies them to close a cluster of previously-deferred spec rules across all four base versions plus the AU profile: §4.5.1.8 ORC-8/OBR-29 XOR softening, OBR-7/-14 specimen-presence triggers, and HL7au:000008 + .1 (Display Segments). **One new public `ValidationIssue.Kind` case** (`.segmentCardinalityBelowMinimum`, additive on a non-`@frozen` enum — minor bump); no other public-API change; v1.0 stability clock continues from v0.5.0. Tests: 446 (v0.10.0) → 466 across 26 suites. Six functional commits: `13e616a` (S1) → `3d11590` (S2) → `4088a75` (S3) → `cca9aa8` (S4) → `2f4796c` (S4b) plus the ADR-010 accept `2396bd2`.

### Added — ADR-010 Accepted (2026-07-02)

`docs/design/ADR-010-dsl-extensions-peer-absent-quantification-content-gated.md` Accepted. Opens the v0.11 cycle. Three narrowly-scoped extensions to the ADR-008 / ADR-009 machinery, each additive and internal:

- **Segment-presence atoms** (`<segmentID> present` / `absent`) — unlocks §4.5.1.8 XOR softening and the OBR-7 / .9 / .10 / .11 / .14 specimen-presence cluster. Reuses ADR-008 group-boundary resolution.
- **Group-scope cardinality rules on `SegmentGrammar`** — new axis alongside min/max occurrence bounds, carrying a v0.7-DSL atom predicate. Sole initial consumer: HL7au:000008 parent ("≥1 OBX per OBR/OBX group with `OBX-3.3 = AUSPDI`"). Adds `.segmentCardinalityBelowMinimum` case to `ValidationIssue.Kind`.
- **Subcomponent-granular field-refs in DSL atoms** (`<segmentID>-<int>[.<int>[.<int>]]`) — unlocks HL7au:000008.1 as an ADR-009-style overlay with `condition: "OBX-3.3 = AUSPDI"`. Reuses `ComponentValueSet.condition` dispatch unchanged.

Substage plan: S1 segment-presence + XOR softening → S2 subcomponent field-refs + HL7au:000008.1 → S3 cardinality axis + HL7au:000008 parent → S4 specimen-presence cluster → S5 release as v0.11.0.

Accepted as drafted (single ADR spanning all three extensions); split-off of Extension 2 into a follow-up ADR-011 remains an available option if S3 turns out too large in practice.

### Added — v0.11-S1: segment-presence atoms + §4.5.1.8 XOR softening (2026-07-03)

First implementation stage of ADR-010 lands on branch `v0.11-adr-010`. Extends the v0.7-S2 predicate DSL with the ADR-010 Extension 1 segment-presence atom (`<segmentID> present` / `<segmentID> absent`) and applies it to soften the v2.4 CH04 §4.5.1.8 ORC-8 / OBR-29 XOR — the child-order parent may be carried in either peer without over-firing.

- `Validator.evaluateSegmentPresenceAtom` dispatches the new atom shape before the general referent/predicate split. Segment-ID filter: 3-char ASCII alphanumeric uppercase (matches DG1, IN1, PV1 alongside ORC, OBR, etc.).
- `Message.segmentExists(_ id: String, inGroupOf index: Int) -> Bool` — thin wrapper over ADR-008 `associatedSegment(_:fromIndex:)`. Same ORC/OBR-group boundary semantics; degenerate-group fallback for non-ORC/OBR callers.
- ORC-8 / OBR-29 conditions in `Resources/schemas/{v2.4,v2.5.1}/{ORC,OBR}.json` rewritten as DNF-encoded XOR softening. Parser has no paren support, so `A AND (B OR C)` is encoded as `A AND B OR A AND C` (equivalent under AND-tighter-than-OR precedence). DocC on `conditionTriggers` updated with the DNF constraint.
- Regression pins in `ConditionalFieldTests`: `orc8SilentUnderXORSofteningWhenOBRCarriesParent`, `obr29SilentUnderXORSofteningWhenORCCarriesParent`. All v0.9 pins (both-empty case fires; parent-only case silent) remain green.
- **Known limitation**: v2.3 / v2.3.1 ORC-8 / OBR-29 still carry the unsoftened `"ORC-1 = CH"` predicate — softening those needs PDFKit spec-text confirmation that v2.3 / v2.3.1 CH04 carry the equivalent §4.5.1.8 XOR trigger; queued for S5 release-prep audit.

Tests: 446 → 448 across 26 suites.

### Added — v0.11-S2: subcomponent-granular DSL field-refs + HL7au:000008.1 overlay (2026-07-03)

Second implementation stage of ADR-010 lands on branch `v0.11-adr-010`. Extends the v0.7-S2 predicate DSL with the ADR-010 Extension 3 subcomponent-granular field-ref production (`<segmentID>-<int>[.<int>[.<int>]]`) so atom LHSes can read a specific composite slot. First (initial) consumer: HL7au:000008.1 — the AU display-segment identifier value set gated on `OBX-3.3 = AUSPDI`.

- `Validator.parseIndexSuffix` factored out; `resolveFieldRef` / `readFieldRef` extended to accept the new tail. `readField` widened with optional `componentIndex` / `subcomponentIndex` (nil → v0.4-S4 first-of-first-of behaviour; set → specified slot). `populated` / `empty` still evaluate the whole field.
- AU profile `Profile+au_adrm_2021.swift` gains a `FieldOverride` on OBX-3 with `component: 1`, `condition: "OBX-3.3 = AUSPDI"`, `allowedValues: ["HTML","PDF","RTF","TXT","PIT"]`. Reuses the ADR-009 `ComponentValueSet.condition` dispatch unchanged. Spec text extracted via PDFKit from AU ADRM-2021 pp. 247 + 420–421.
- **ADR-010 amended** in the same commit with a post-hoc clarification: the ADR §"Rules expressed…" section originally wrote `component: 3` for the HL7au:000008.1 overlay, but component 3 IS the AUSPDI gate itself. The value-set check is on component 1 (Identifier) per HL7au:000008.1 verbatim. Implementation ships with `component: 1`.
- Four new regression pins in `LocaleAUProfileTests`: `hl7au000008_1_conformingPDFSilent`, `hl7au000008_1_nonConformingAUSPDIFires`, `hl7au000008_1_nonAUSPDIGateSilent` (verifies the gate blocks non-display OBXs), `hl7au000008_1_deprecatedPITPermitted` (deprecated per AU ADRM p. 247 but still supported).
- DSL grammar DocC on `conditionTriggers` updated with the extended `<fieldref>` production.

Tests: 448 → 452 across 26 suites.

### Added — v0.11-S3: group-scope cardinality axis + HL7au:000008 parent (2026-07-03)

Third implementation stage of ADR-010 lands on branch `v0.11-adr-010`. New grammar axis for group-scope cardinality rules (Extension 2), plus a parallel `Profile.cardinalityExtensions` axis so locale-scoped rules can layer on the base grammar without over-firing outside their locale. First consumer: HL7au:000008 parent — "The message must contain at least one OBX display segment per OBR/OBX group" (AU ADRM-2021 p. 420).

**New internal types**:
- `GroupScope` enum: `.orcObxGroup`, `.obrObxGroup`, `.messageWide`.
- `SegmentCardinalityRule`: `{countedSegmentID, scope, minCount, predicate, applicableWhen?, specCitation?}`. Two S3-clarification fields beyond the ADR-010 Decision text — `countedSegmentID` (avoids parsing the predicate to reconstruct the target segment ID for the fired issue) and `applicableWhen` (v0.7-DSL message-context gate, mirrors ADR-009 `ComponentValueSet.condition`).

**Model additions**:
- `SegmentGrammar` gains `segmentCardinalityRules: [SegmentCardinalityRule]` (empty by default; axis is ready for future universal rules that ship in the base schema JSON).
- `Profile` gains `cardinalityExtensions: [String: [SegmentCardinalityRule]]` — parallel to `grammarExtensions`. Locale-scoped rules layer here; the base-grammar axis remains reserved for spec-universal rules.

**Public API**:
- New `ValidationIssue.Kind.segmentCardinalityBelowMinimum(segmentID:minCount:actual:groupScope:)` case. Additive on a non-`@frozen` enum; minor bump per the pattern established at v0.4-S4 / v0.7 / v0.8. All other public API is unchanged.

**Codegen**:
- `HL7v2KitCodegen.CardinalityRuleSchema` decodes the optional `segmentCardinalityRules` JSON key and emits the internal `SegmentGrammar` init that carries the rules array. Silent-safe: no shipping schema uses the key yet, so generated output is byte-identical to v0.11-S2. Codegen-drift CI stays clean.

**Validator**:
- `mergeGrammarExtension` extended to merge `Profile.cardinalityExtensions` into the effective `SegmentGrammar.segmentCardinalityRules`.
- `Validator.validate` gains a `checkCardinalityRules` call after each `checkSegment`. Group resolution via a new private `resolveGroup(scope:anchorIndex:message:)` helper (three scopes implemented). Dedupe via a `Set<String>` keyed by `(scope, groupHeadIndex, countedSegmentID, predicate, minCount)` so a rule attached to a head segment fires exactly once per distinct group.
- Candidate iteration filters to segments matching `countedSegmentID`. Without this filter, a predicate like `OBX-3.3 = AUSPDI` evaluated against a non-OBX candidate would resolve via ADR-008 `associatedSegment` (ORC-scoped) and could false-positive-match an OBX in a different sub-group. Discovered during multi-OBR regression test.

**AU profile — HL7au:000008 shipped** as a `SegmentCardinalityRule` on OBR grammar via `Profile.cardinalityExtensions`. `countedSegmentID: "OBX", scope: .obrObxGroup, minCount: 1, predicate: "OBX-3.3 = AUSPDI", applicableWhen: "messageCode in (ORU, REF)"`. Fires only under `.auLocalisation` on Results / Referrals messages when a resolved OBR/OBX sub-group contains no OBX with `OBX-3.3 = AUSPDI`.

**Tests**:
- `LocaleTests.auLocaleAddsButDoesNotRemoveBaseSpecErrors` updated: `.segmentCardinalityBelowMinimum` classified as locale-attributable (mirrors `.profileConstraintViolation`) so the AU-vs-international fixture parity check treats the new violations correctly.
- Six new regression pins in `LocaleAUProfileTests`: silent-with-AUSPDI, fires-without-AUSPDI, silent-on-ADT-with-no-OBR, silent-on-ORM (applicableWhen gate), silent-under-`.international` (locale gate), fires-per-group on multi-OBR wire.

**ADR-010 amended** with an S3-implementation clarification block:
1. Locale-scoped cardinality rules require the parallel `Profile.cardinalityExtensions` axis in addition to `SegmentGrammar.segmentCardinalityRules` (ADR text only mentioned the base axis).
2. `SegmentCardinalityRule` gains `countedSegmentID` (required) and `applicableWhen` (optional) fields — both additive to what the Decision section specified.

Tests: 452 → 458 across 26 suites.

### Added — v0.11-S4: OBR specimen-presence cluster (2026-07-03)

Fourth implementation stage of ADR-010 lands on branch `v0.11-adr-010`. Uses the v0.11-S1 `<segmentID> present` atom (`SPM present` on v2.5.1) plus the existing `<fieldref> populated` atom (`OBR-15 populated`) to encode "specimen sent with request" triggers on OBR-7 and OBR-14 per v2.4 CH04 §4.5.3.7 / .14.

**Schema updates**:
- **v2.5.1 OBR-7**: `"messageCode = ORU"` → `"messageCode = ORU OR SPM present OR OBR-15 populated"`. Adds the specimen-sent-with-request second trigger from §4.5.3.7.
- **v2.4 OBR-7**: `"messageCode = ORU"` → `"messageCode = ORU OR OBR-15 populated"`. SPM segment doesn't exist in v2.4; OBR-15 (specimen source) is the specimen indicator.
- **v2.5.1 OBR-14**: new condition `"SPM present OR OBR-15 populated"` per §4.5.3.14 "must contain a value when the order is accompanied by a specimen".
- **v2.4 OBR-14**: new condition `"OBR-15 populated"` per §4.5.3.14 with SPM-absent fallback.

**Scope trim per the working notes req #4**:
- ADR-010 §"Rules expressed…" named "OBR-7 second trigger + OBR-9 / OBR-10 / OBR-11 / OBR-14" as the specimen-presence targets. PDFKit extraction of v2.4 CH04 pp. 46-48 confirmed only OBR-7 (§4.5.3.7) and OBR-14 (§4.5.3.14) carry crisp "must be filled in when X" conditional-required triggers.
- OBR-9 §4.5.3.9 ("results-only field except when the placer has drawn the specimen"), OBR-10 §4.5.3.10 ("will identify..."), OBR-11 §4.5.3.11 ("identifies the action...") are descriptive statements without MUST language. Not shipped per req #4 ("no predicate ships if known-incorrect"). Re-audit if a future spec revision adds MUST language.
- ADR-010 amended with a "Clarification 2026-07-03 (during S4 implementation)" block documenting the trim.

**Fixture-corpus side-fix**:
- Discovered a systematic field-shift error across 13 ORU fixtures: a timestamp was consistently placed at OBR-15 (specimen source, deprecated in v2.5.1) instead of OBR-14 (specimen received DT). Mechanical sed fix `s/L\|\|\|\([0-9]\{14\}\)\|\|/L||\1|||/g` corrected all 13.
- Bonus fix: cleared the pre-existing "OBR-15 (deprecated B) but populated" warnings that had been surfacing on those fixtures since v0.2.

**Regression pins** (five new tests in `ConditionalFieldTests`):
- `obr14FiresWhenOBR15PopulatedAndOBR14Empty_v24` — v2.4 §4.5.3.14 canonical trigger.
- `obr14SilentWhenOBR14Populated_v24` — guard bypasses on populated field.
- `obr14SilentWhenNoSpecimenIndicator_v24` — no OBR-15 (imaging OBR case) → predicate false.
- `obr14FiresWhenSPMPresent_v251` — v2.5.1 SPM-segment detection (uses S1 `SPM present` atom).
- `obr7FiresUnderSecondTrigger` — ORM with OBR-15 populated fires OBR-7 via the second trigger.

**Known limitations carried into S5**:
- v2.3 / v2.3.1 OBR-7 / OBR-14 do not carry S4 predicates — v2.3 CH04 audit is an S5 candidate.
- v2.3 / v2.3.1 ORC-8 / OBR-29 still carry the unsoftened `"ORC-1 = CH"` from v0.10 (documented per S1).

Tests: 458 → 463 across 26 suites.

### Added — v0.11-S4b: per-version mirror to v2.3 / v2.3.1 (2026-07-03)

Closes the per-version coverage gap for the S1 XOR softening and S4 specimen-presence conditions by mirroring them into the v2.3 and v2.3.1 OBR / ORC schemas, after PDFKit-confirming the equivalent spec text in v2.3 CH4.

- **v2.3 + v2.3.1 ORC-8 / OBR-29**: `"ORC-1 = CH"` → DNF XOR softening (same predicate strings as v2.4/v2.5.1). Basis: v2.3 §4.3.1.8 child-order-transmitted trigger (verbatim like v2.4 §4.5.1.1) + OBR-29 defined "identical to ORC-8-parent" + the general XOR parenthetical "This rule is the same for other identical fields in the ORC and OBR" (v2.3 CH4, placer/filler order-number rules). v2.3 has no parent-specific §4.5.1.8 sentence like v2.4, so the softening rests on the identical-fields generalization — documented in the audit doc.
- **v2.3 + v2.3.1 OBR-7**: `"messageCode = ORU"` → `"messageCode = ORU OR OBR-15 populated"` (SPM absent in v2.3/v2.3.1, same fallback as v2.4). Basis: v2.3 §4.5.1.7.
- **v2.3 + v2.3.1 OBR-14**: new condition `"OBR-15 populated"`. Basis: v2.3 §4.5.1.14 — *verbatim identical* to v2.4 §4.5.3.14 ("must contain a value when the order is accompanied by a specimen").
- Three regression pins: `obr14FiresOnV23`, `orc8Obr29FireOnV231ChildBothEmpty`, `orc8SilentOnV231WhenOBRCarriesParent`.

Tests: 463 → 466 across 26 suites.

## [0.10.0] — 2026-06-25

Per-version cross-segment / message-context coverage closure + AU narrowing audit. **Eight functional commits** since v0.9.0, all under the "correct defects as found" feedback rule (`feedback_correct_defects_as_found.md`). PDFKit-extracted spec text for v2.3, v2.3.1, and v2.5.1 CH06 to close the v0.4-S2 "per-version conditional rules pending PDFs" gap for every spec-extractable trigger. Two AU narrowings (HL7au:000001, HL7au:000008) audited and explicitly marked unshippable until a future ADR-010 introduces peer-absent / segment-quantification / content-gated DSL primitives. **No public-API change** vs v0.9.0; v1.0 stability clock continues from v0.5.0. Tests: 439 (v0.9.0) → 446 across 26 suites.

### Added — OBR-7 partial + audit of OBR-14 / OBR-22 / OBR-32

`0810bda` ships `"messageCode = ORU"` on OBR-7 in v2.5.1 + v2.4 per §4.5.3.7 first trigger (report message). Second trigger (specimen sent with request) deferred — needs specimen-presence DSL atom. OBR-14 / OBR-22 / OBR-32 explicitly audited as having no extractable spec MUST trigger.

### Added — ORC-3 / OBR-3 filler-order XOR

`1f7448e` ships the symmetric XOR per §4.5.1.3 (exact mirror of the v0.7-S4 ORC-2 / OBR-2 placer rule).

### Added — Per-version coverage closure to v2.3 + v2.3.1

`5148421` propagates all 5 cross-segment / message-context rules (ORC-2/OBR-2 XOR, ORC-3/OBR-3 XOR, ORC-8/OBR-29 child-order, OBR-7 report-message, OBR-25 report-message) to v2.3 + v2.3.1 schemas. PDFKit-extracted both v2.3.1 Hl7V231.pdf and v2.3 CH4.pdf; confirmed verbatim-equivalent spec text. **16 new condition strings**.

`f98ea6a` propagates OBX-2 result-status condition `"OBX-11 != X"` to v2.3 + v2.3.1 OBX.json. §7.3.2.2 wording confirmed verbatim across all 4 versions.

### Added — DG1-20 / DG1-21 Update-Diagnosis trigger

`c25e208` ships `"triggerEvent = P12"` on both fields in v2.5.1 per §6.5.2.20 / §6.5.2.21. Uses the v0.7 message-context atom.

### Audited / not shippable

- `87dc447` HL7au:000001 (Order addressing / MSH-6 Receiving facility) audited; all 4 subrules either runtime semantics, soft "should" guidance, or pointing to PKI-deferred HL7au:00044.2.
- `14377cc` HL7au:000008 (Display Segments) audited; cluster needs new DSL primitives (segment-presence-quantification, content-gated overlays). Re-audit after ADR-010 lands.

Combined audit findings reveal a pattern: multiple deferred rules (§4.5.1.8 XOR softening, OBR-7/9/10/11/14 specimen-presence, HL7au:000008) all point to the same architectural extension — a future ADR-010 covering peer-absent atom + segment-quantification atom + content-gated overlay dispatch.

### Carried over from v0.9.0 onto the v0.10.0 line

- `cc14e89` ORC-8 predicate corrected (`previousSegment(ORC).ORC-1 = PA` → `"ORC-1 = CH"`) per the working notes req #4.
- `f750e56` OBR-29 silently-missing condition filled (`"ORC-1 = CH"`).

These were tagged into v0.9.0; included here for cycle continuity.

## [0.9.0] — 2026-06-25

Docs + defect-fix release. Closes the v0.7-S4 deferred work by back-filling verbatim v2.4 CH04 § citations for the four cross-segment / message-context rules into `docs/design/v2_3-v2_4-spec-audit.md`, using the PDFKit-based spec-extraction recipe (memory file `reference_pdf_extraction.md`) that cleared the prior "no pdftotext" gate. The audit pass surfaced two the working notes req #4 defects — both corrected in the same session per the new `feedback_correct_defects_as_found` working rule. **No public-API change** vs v0.8.0; v1.0 stability clock continues from v0.5.0. Tests: 435 (v0.8.0) → 439 across 26 suites.

### Added — v2.4 spec-audit § citation back-fill

`docs/design/v2_3-v2_4-spec-audit.md` Conditional-rule carry-forward table extended with rows citing v2.4 CH04 verbatim for each v0.7 cross-segment rule:

- **ORC-2 §4.5.1.2** (p. 4-34) — XOR with OBR-2; wording identical to v2.5.1.
- **OBR-2 §4.5.3.2** — symmetric XOR partner.
- **OBR-25 §4.5.3.25** (p. 4-52) — report-message guard; wording identical to v2.5.1.
- **ORC-8 §4.5.1.1 + §4.5.1.8** (pp. 4-26 / 4-37) — child-order trigger + XOR softening.
- **OBR-29 §4.5.3.29** (p. 4-54) — identical-to-ORC-8 trigger.

PDFKit-based extraction recipe captured as `reference_pdf_extraction.md` memory; clears the previously-deferred "no pdftotext" gate that blocked spec-audit work.

### Fixed — ORC-8 predicate (the working notes req #4 defect)

The v0.7-S4 mirror shipped `previousSegment(ORC).ORC-1 = PA` as the ORC-8 conditional. The v2.4 CH04 audit surfaced that the spec §4.5.1.1 trigger is keyed on "current ORC carries ORC-1 = CH", not on "preceding ORC carried PA". The prior predicate under-fired on standalone CH orders and CH orders whose parent was sent in a prior message — silent false negatives on spec-compliant scenarios.

Corrected to `"ORC-1 = CH"` (same-segment v0.4-S4 DSL atom; no architectural change) on both `Resources/schemas/v2.5.1/ORC.json` and `Resources/schemas/v2.4/ORC.json`. Tests: existing `orc8ConditionalFiresOnChild` updated; new `orc8ConditionalFiresOnStandaloneChild` (regression guard for the prior false-negative) + `orc8ConditionalSilentOnParent` (negative pin) added. 2 new tests.

### Fixed — OBR-29 silently-missing condition (same defect class)

OBR-29 was conditional in both v2.5.1 and v2.4 schemas but had no `"condition"` string at all — the field's §4.5.3.29 "It is required when the order is a child" trigger silently never fired. Added `"condition": "ORC-1 = CH"`; the v0.7 cross-segment field-ref semantic resolves `ORC-1` via `Message.associatedSegment(ORC, fromIndex: OBR_index)` when evaluated in OBR context.

Tests: new `obr29ConditionalFiresOnChildAssociatedORC` + `obr29ConditionalSilentOnNonChildAssociatedORC` pins. 2 new tests.

Known limitation documented: the §4.5.1.8 XOR softening (parent in ORC OR OBR satisfies both) is not yet enforced — would require a DSL primitive distinguishing "peer absent" from "peer empty" (current cross-segment ref fails safe to false on both). The shipped ORC-8 / OBR-29 conditions err on the over-fire side relative to the XOR softening but match the §4.5.1.1 / §4.5.3.29 child-order triggers exactly.

### Added — Process improvement

New feedback memory `feedback_correct_defects_as_found.md`: when an audit surfaces a the working notes req #4 defect with clear spec text and a mechanical fix path, fix it in the same session rather than queuing as a future candidate. This release sequence (audit → 2 defect corrections → same-session ship) exercises the rule.

### Known follow-ups (deferred to v0.10+)

Same-class audit found **78 conditional fields across all schemas** carrying `"optionality": "C"` with no `"condition"` string. The 4 we corrected in v0.9 are a subset; the remaining 74 silent never-fires require multi-session audit work (v2.3 / v2.3.1 PDF extraction + cross-segment / message-context DSL extensions for some). Scoping options in `NEXT_STEPS.md` "Conditional-without-condition audit" track.

## [0.8.0] — 2026-06-25

Ships the first AU profile narrowing that exercises subcomponent-granular value pinning and message-type-dispatched conditional gating, per **ADR-009** (Accepted 2026-06-25). The AU `ComponentValueSet` model gains two optional fields (`subcomponent: Int?` + `condition: String?`); the Validator reuses the v0.7 (ADR-008) `conditionTriggers` evaluator as the gating engine — no new parser, no new dispatch surface. Closes HL7au:000040 (MSH-12 Version ID Field Conformance Points) subrules .1, .2, .3, .4 verbatim against the AU ADRM-2021 spec pp. 445–446. 040.5 is receiver runtime behaviour, explicitly out of scope. **No public-API change** vs v0.7.0; v1.0 stability clock continues from v0.5.0. Tests: 423 (v0.7.0) → 435 across 26 suites.

Workflow improvement: macOS PDFKit-based spec-text extraction (`xcrun swift /tmp/extract.swift`) cleared the previously-deferred "no pdftotext" gate that was blocking spec-audit § citation work. Memory file `reference_pdf_extraction.md` documents the recipe for future sessions.

### Added — v0.8-S1: ComponentValueSet model extensions

`ComponentValueSet` gains two optional fields, both defaulting to `nil` (full backwards-compatibility with v0.5–v0.7 overrides):

- **`subcomponent: Int?`** — When nil, reads the named component's FIRST subcomponent (v0.5-S5-C behaviour). When set, reads that named subcomponent. Required by HL7au:000040.1/.2 so MSH-12.2.1 = "AUS", MSH-12.2.2 = "Australia", MSH-12.2.3 = "ISO3166_1" can all be pinned independently.
- **`condition: String?`** — When nil, the check always applies on populated fields. When set, the check is gated through the v0.7 `conditionTriggers` evaluator — if the predicate is false the value-set is skipped. Required by HL7au:000040.3/.4 to apply different VID-3 values per message-code class without duplicating the FieldOverride entry.

Explicit memberwise init with `nil` defaults for both new fields + `specCitation` lets every existing call site continue to compile via labeled arguments.

### Added — v0.8-S2: Validator dispatch wiring

`Validator.checkProfileFieldOverrides` plumbs `segment: Segment`, `segmentArrayIndex: Int` (0-based, matching the v0.7 evaluator convention), and `message: Message` so it can:

1. Evaluate per-ComponentValueSet `condition` via `conditionTriggers` before applying the value-set check. Unresolvable predicates fail safe per ADR-008 ("malformed schema must never make a previously-accepted message non-conformant").
2. Resolve the value-set's actual scalar by subcomponent when set, rather than defaulting to the first subcomponent.

Helper rename: `componentScalarValue(in:componentIndex:)` → `valueSetScalarValue(in:component:subcomponent:)`. The validator's legacy `segmentIndex: Int` parameter (which historically meant "1-based per-segment-ID occurrence") was renamed to `occurrence: Int` to unify naming with the v0.7 convention where `segmentIndex` is the 0-based array index.

### Added — v0.8-S3: HL7au:000040 MSH-12 Version ID conformance rules

Nine ComponentValueSet entries on the MSH-12 FieldOverride in `Profile+au_adrm_2021.swift` (mirrored verbatim in `Resources/profiles/au-adrm-2021/MSH.json` per ADR-007's hand-curated sync):

- **040.1/.2** (Senders Orders/Results/Referrals/ACK/RRI): MSH-12.1 = "2.4"; MSH-12.2.1 = "AUS"; MSH-12.2.2 = "Australia"; MSH-12.2.3 = "ISO3166_1".
- **040.3** (Senders Orders/Results, gated on `messageCode in (ORM, ORU)`): MSH-12.3.1 = "HL7AU-OO-201701"; MSH-12.3.3 = "L".
- **040.4** (Senders Referrals/RRI, gated on `messageCode in (REF, RRI)`): MSH-12.3.1 ∈ {"HL7AU-OO-REF-SIMPLIFIED-201706", "HL7AU-OO-REF-SIMPLIFIED-201706-L1"}; MSH-12.3.3 = "L".

Fixture audit folded into S3: one inline AU-locale test wire (`mshFullyAUCompliant`) needed MSH-12 updated from "2.5.1" to the AU-conformant form; the broader `Tests/Fixtures/` corpus is `.international` and unaffected. 10 new validator-level pins cover positive/negative/gating/dispatch-exclusivity across all four subrules.

### Added — v0.8-S3b: Polish — gating + literal-pin completeness

Post-review polish on the v0.8-S3 rules:

- **Gated 040.1/.2 by messageCode**: added `condition: "messageCode in (ORM, ORU, REF, RRI, ACK)"` to the four universal ComponentValueSet entries. The spec enumerates these five message-type categories; the prior universal-fire was a known misfire on out-of-scope message types (e.g. ADT^A01 with non-AU MSH-12 was spec-compliant under v2.5.1 but triggered the AU rule).
- **VID-3.2 literal-empty pin**: the spec literal `"HL7AU-OO-201701&&L"` (and `"...-201706&&L"`) carries an empty middle subcomponent. Two new ComponentValueSet entries pin `MSH-12.3.2 = [""]` on both 040.3 and 040.4 gated paths, closing the permissive over-acceptance gap.

Test changes: 4 ADT-based wires flipped to ORU/REF to keep the rule-firing tests valid under stricter gating. New `msh12UniversalSilentOnADT` pins the gating fix; new `msh12_040_3_VID3_2_MustBeEmpty` pins the literal-empty fix. JSON↔Swift sync maintained.

## [0.7.0] — 2026-06-24

Closes the three documented out-of-scope conditional rules from `docs/design/v2_5_1-spec-audit.md` §93–121 by extending the v0.4-S4 condition DSL per **ADR-008** (Accepted 2026-06-19). The DSL gains three new predicate categories — cross-segment field refs, message-context atoms (`messageCode` / `triggerEvent` / `messageStructure`), and bounded position atoms (`previousSegment(<ID>).<fieldref>`, `associatedSegment(<ID>).<fieldref>`) — evaluated against the full `Message` rather than a single `Segment`. Schema JSON surface unchanged; `"condition"` strings carry the new productions. **No public-API breakage** vs v0.6.0 — pure internal grammar enrichment behind the locked `HL7Locale` enum + `ValidationIssue` surfaces. Tests: 390 (v0.6.0) → 423 across 24 → 26 suites. The 3-month no-API-break v1.0 stability clock continues from v0.5.0.

### Added — v0.7-S1: Message helpers + Validator signature widening

Internal plumbing layer. `Message` gains five helpers: `messageCode` / `triggerEvent` / `messageStructure` (read MSH-9.1 / .2 / .3), `associatedSegment(_:fromIndex:)` (ORC-delimited group resolution), `previousSegment(_:beforeIndex:)` (nearest preceding segment of named ID). `Validator.checkConditional` signature widens to `(segment, segmentIndex, currentSegmentID, message)`; the segment index is plumbed through `validate()` → `checkSegment` → `conditionTriggers` → OR/AND/atom evaluators. Atom body unchanged in S1 (behaviour identical to v0.6.0). 12 new pins in `MessageCrossSegmentTests`. Test count 390 → 402.

### Added — v0.7-S2: predicate parser productions

Three new productions in the recursive-descent evaluator at `Validator.swift`:
- **Cross-segment field refs** — `<otherSegmentID>-<n>` resolves via `Message.associatedSegment`, replacing v0.6.0's silent `return false` guard.
- **Message-context atoms** — `messageCode`, `triggerEvent`, `messageStructure` evaluate against MSH-9.
- **Position atoms** — `previousSegment(<ID>).<fieldref>` and `associatedSegment(<ID>).<fieldref>`.

Atom evaluator refactored into a clean dispatch (`resolveReferent` → `applyPredicate`) with a `ResolvedReferent` value type. Fail-safe semantics tightened per ADR-008: an unresolvable peer / position returns `nil` from the resolver, atom evaluates `false` (vs the prior "treat absence as empty" behaviour, which would spuriously trigger `<peer>-<n> empty`). `Validator.conditionTriggers` raised from `private` to internal for test access via `@testable`; no public-API surface change. 16 new pins in `CrossSegmentDSLTests` (positive / negative / fail-safe per production + 1 compound + 1 v0.4-S4 regression). Test count 402 → 418.

### Added — v0.7-S3: v2.5.1 schema additions + fixture re-audit

Four conditions added to `Resources/schemas/v2.5.1/`:
- ORC-2 (Placer Order Number) → `"OBR-2 empty"` (§4.5.1.2 XOR).
- ORC-8 (Parent) → `"previousSegment(ORC).ORC-1 = PA"` (§4.5.3.29 parent-child).
- OBR-2 (Placer Order Number) → `"ORC-2 empty"` (symmetric XOR partner).
- OBR-25 (Result Status) → `"messageCode = ORU"` (§4.5.3.25 report-message guard).

Fixture corpus re-audit (same shape as v0.5-S5-D-2 when profileUsage first fired): 14 ORU^R01 fixtures previously omitted OBR-25 — every one gained `F` (Final results) appended to OBR, all still round-trip byte-perfectly. `oru_r01_with_z_segment.hl7` had a shorter OBR (ended at field 16 instead of 17 like its peers); fix uses 9 separators+F instead of 8. 4 new validator-level integration pins in `ConditionalFieldTests` (XOR fires both sides, XOR satisfied, OBR-25 silent on ADT, ORC-8 fires on child / silent on parent). Test count 418 → 422.

### Added — v0.7-S4: v2.4 mirror

Same four conditions mirrored onto `Resources/schemas/v2.4/{ORC,OBR}.json`. The involved fields exist in v2.4 with identical shapes (verified pre-edit). `oru_r01_v24.hl7` fixture audited: OBR-25 = F appended (OBR previously ended at field 4). 1 new validator-level pin in `MultiVersionTests` exercising all three productions through the v2.4 grammar dispatch. Test count 422 → 423.

Caveat: full verbatim v2.4 § citation extraction is deferred (pdftotext unavailable on dev box; the v2_3-v2_4-spec-audit.md doesn't yet include CH04 chapter audit detail). The conditions propagate from the v2.5.1 audit, which captures HL7's stable ordering semantics that v2.4 inherits identically. A future audit pass will add verbatim citations to `v2_3-v2_4-spec-audit.md`.

## [0.6.0] — 2026-06-19

v0.6 cycle opener. Closes the per-version T-track grammar gap from v0.4's audit: v2.4 wires using EVN / MSA / ERR / PD1 / DG1 / IN1 now get per-field validation against the actual v2.4 spec shape, not "unknown segment". Per the project's "feature-complete over AU-specific" + "integrator primary-reference tool" requirements, every v2.4-vs-v2.5.1 divergence (ERR collapse to 1 field, DG1 truncation at 19, MSA-5 retype) is preserved verbatim from the v2.4 spec PDFs (chs 2, 3, 6) rather than transposed from v2.5.1. **No public-API breakage** vs v0.5.0 — pure grammar-table enrichment. Tests: 390 (v0.5.0) → 390 across 24 suites. The 3-month no-API-break v1.0 stability clock continues from v0.5.0.

### Added — v0.6-T-back-port: v2.4 grammar for the T-track segments

Closes the per-version coverage gap documented in `docs/design/v2_3-v2_4-spec-audit.md`: the six T-track segments (EVN, MSA, ERR, PD1, DG1, IN1) previously only had v2.5.1 grammar tables. v2.4 wires using these segments fell through to "unknown segment" rather than getting per-field validation.

- **6 new v2.4 schemas** authored under `Resources/schemas/v2.4/`:
  - `EVN.json` — 7 fields, EVN-2 (Recorded Date/Time) is R. Identical shape to v2.5.1.
  - `MSA.json` — 6 fields. v2.4 difference vs v2.5.1: MSA-5 (Delayed Acknowledgment Type) is `ID, B` in v2.4 vs `ST, X` in v2.5.1.
  - `ERR.json` — **1 field only** (ERR-1 CM Error Code and Location). v2.5+ redesigned ERR to 12 fields; v2.4 had only the CM composite.
  - `PD1.json` — 21 fields. Identical to v2.5.1.
  - `DG1.json` — **19 fields** (no DG1-20 Diagnosis Identifier or DG1-21 Diagnosis Action Code — those were added in v2.5+).
  - `IN1.json` — 25 fields (billing-essentials subset). Identical to v2.5.1.

- **Codegen** picks up automatically: the per-version `SegmentGrammarTable.v2_4` now publishes all 15 segments (was 9). Typed segment structs are version-agnostic and unchanged.

- **MultiVersionTests** pin updated to cover the new 6: EVN=7, MSA=6, ERR=1, PD1=21, DG1=19, IN1=25.

- Tests: 390 → 390 across 24 suites green. No new tests required — the existing grammar-table pin assertions caught all back-port shape decisions.

- All field counts and optionalities authored from the v2.4 spec PDFs (chapters 2, 3, 6) — not transposed from v2.5.1. Per the project's "feature-complete over AU-specific" + "integrator primary-reference tool" requirements, every divergence from v2.5.1 (ERR collapse, DG1 truncation, MSA-5 `(B) → X` retype) is preserved verbatim from the source spec text.

## [0.5.0] — 2026-06-18

v0.5 cycle release. AU profile constraint overlay substrate now substantively complete for the same-segment / same-datatype subset of HL7 Australia's ADRM-2021 conformance profile. **29 AU conformance rules** firing under `.auLocalisation` across 6 narrowing axes (field required-components, field required-presence, field per-component value-set, composite required-components, composite pair-conditional, grammar extension). All cited verbatim to HL7au identifiers via `.profileConstraintViolation(localeRule:)`. Base-spec behaviour under `.international` is unchanged. The additive-errors invariant (`auLocaleAddsButDoesNotRemoveBaseSpecErrors`) is enforced as a fixture-corpus pin. **No public-API breakage** vs v0.4.0 — all v0.5 work is internal overlay enrichment behind the locked `HL7Locale` enum + `ValidationIssue.code.profileConstraintViolation(localeRule:)` surfaces. Tests: 360 (v0.4.0) → 390 across 23 → 24 suites. The 3-month no-API-break v1.0 stability clock restarts from this tag per Migration.md.

### Added — v0.5-S5-D-2: profileUsage dispatch (closes "must be populated under AU" gap)

Closes the documented S5-C scope gap: under `.auLocalisation`, MSH-17 (`HL7au:000041`) and MSH-19 (`HL7au:000042`) must be populated — not just match a value-set when populated. The S5-C check fired only on populated-but-wrong values; this substage adds presence enforcement via `FieldOverride.profileUsage`.

- **`Validator.checkProfileFieldUsage`** (new): for every field in the segment grammar, when a profile is loaded and the matching `FieldOverride` declares `profileUsage = .required` and the field is empty, emit `.profileConstraintViolation(localeRule:)` with the override's spec citation. `.requiredEmpty` (RE) treated as informational (no fire on empty per the spec's RE semantic); `.notUsed` (X) handled by the existing base `checkDeprecation`; other usage codes don't drive a presence rule.
- **AU profile updated**: MSH-17 and MSH-19 FieldOverrides now carry `profileUsage = .required`. JSON overlay file (`Resources/profiles/au-adrm-2021/MSH.json`) and Swift mirror in sync.
- **Tests updated**:
  - `LocaleTests.auLocaleEmitsNoProfileViolationsOnPIDOnlyMessage` renamed and refocused — now pins "no OBR/ORC AU rules fire on PID-only wire" (filters out MSH violations which now legitimately fire under profileUsage).
  - `LocaleAUProfileTests.mshValueSetRulesConditionalOnPopulated` (the S5-C scope-limit pin) replaced with `mshProfileRequiredFiresOnEmpty` + `internationalLocaleSilentOnEmptyMSH`. New invariant: empty MSH-17 / MSH-19 now fire `profileConstraintViolation` per the profileUsage track.

- 389 → 390 tests across 24 suites green.

### Added — v0.5-S5-D: AU pre-adopted PID-35..38 grammar extensions on v2.4

Substage for the AU profile's pre-adoption of v2.5+ PID fields onto v2.4 wires. Closes the documented gap: under base v2.4 grammar (PID capped at 32), the Validator never iterated PID-33..38, so the v2.5.1-style conditional predicates added in v0.4-S4-C didn't apply to v2.4 wires. With S5-D + `.auLocalisation`, the AU profile extends the v2.4 PID grammar so those rules fire.

- **`Profile` model extension**:
  - `Profile.grammarExtensions: [String: [FieldGrammar]]` — segment ID to appended/replacing field-grammar entries. New track alongside `fieldOverrides`, `compositeOverrides`.
  - `Profile.init` re-ordered to `(locale, baseVersion, fieldOverrides, grammarExtensions, compositeOverrides)` so the segment-level overrides cluster naturally.

- **AU grammar extension shipped**:
  - **`"PID"`** → 4 `FieldGrammar` entries mirroring the v2.5.1 PID-35..38 schema:
    - PID-35 Species Code (CE, C, condition: `"PID-36 populated OR PID-38 populated"`).
    - PID-36 Breed Code (CE, C, condition: `"PID-37 populated"`).
    - PID-37 Strain (ST, O).
    - PID-38 Production Class Code (CE, O).

- **`Validator.mergeGrammarExtension`** (new): merges a profile's grammar extension into a base segment grammar. Existing indices REPLACE; new indices APPEND. The Validator now resolves grammar via the merged result when a profile is loaded.

- **Behaviour gain**: a v2.4 wire that populates PID-36 (Breed Code) without PID-35 (Species Code) under `.auLocalisation` now correctly fires `.conditionalFieldMissing` on PID-35 — matching what would happen on a v2.5.1 wire. Under `.international`, the same v2.4 wire fires nothing (base v2.4 grammar has no PID-35), preserving the documented base-spec behaviour.

- **Tests added (Tests/HL7v2KitTests/LocaleAUProfileTests.swift)**: 4 new tests:
  - v2.4 + AU: PID-36 populated triggers PID-35 conditional missing.
  - v2.4 + .international: same wire silently ignores PID-35 (base v2.4 has no PID-35).
  - v2.4 + AU: PID-35 + PID-36 both populated satisfies the conditional.
  - v2.5.1 wire: PID-35 conditional fires regardless of locale (base-grammar route is unaffected by profile).

385 → 389 tests across 24 suites green. Fixture corpus pin held (no fixtures populate v2.4 PID-35..38).

**Cumulative v0.5**: AU profile now provides 4 narrowing axes — field-level (S5-B-1), composite required (S5-B-3), composite pair-conditional (S5-B-2), per-component value-set (S5-C), grammar extension (S5-D) — across 5 segments (MSH / OBR / ORC / PID via dispatch + AU grammar reach into PID-35..38 on v2.4).

### Added — v0.5-S5-C: AU ADRM-2021 per-component value-set rules (MSH-17 / MSH-19)

First substage of the AU profile value-set track. Extends `FieldOverride` with a `componentValueSets` track parallel to `requiredComponents` (S5-B-1 / -3), then ships the AU "country must be AUS" + "language must be en/English/ISO639" rules.

- **`Profile` model extension**:
  - `FieldOverride.componentValueSets: [ComponentValueSet]` — new sub-rule track. Each entry restricts a specific 1-based component to a fixed list of allowed literal values via exact-string comparison.
  - `ComponentValueSet` struct (component index + `allowedValues: [String]` + `specCitation: String?`).
  - `FieldOverride.init` made explicit (Swift's synthesized memberwise init can't carry defaults for the new field while preserving back-compat).

- **AU rules added**:
  - **`HL7au:000041 (r2)`** — MSH-17 country code must be `"AUS"`.
  - **`HL7au:000042`** — MSH-19 must be valued as `"en^English^ISO639"` (three component value-sets: CE-1 = en, CE-2 = English, CE-3 = ISO639).

- **`Validator.checkProfileFieldOverrides`** extended to dispatch the new track alongside the existing `requiredComponents`. Same `.profileConstraintViolation(localeRule:)` plumbing; spec citation per rule.

- **`Resources/profiles/au-adrm-2021/MSH.json`** — new overlay file with both rules + verbatim spec citations + an `_notes` block documenting the populated-then-must-match scope and the future `profileUsage`-based dispatch.

- **Scope note (documented in source comments)**: S5-C rules fire only when the field is populated. The AU spec actually says MSH-17 and MSH-19 must always be populated under `.auLocalisation`. The "field must be populated under AU" enforcement is a separate future track — likely via `profileUsage` dispatch — and is not in S5-C-1 scope.

- **Tests added (Tests/HL7v2KitTests/LocaleAUProfileTests.swift)**: 5 new tests covering MSH-17 wrong country fires; MSH-19 wrong language identifier fires; fully AU-conformant MSH passes; empty MSH-17 / MSH-19 fires nothing (scope pin for populated-then-must-match); `.international` locale silent. 380 → 385 tests across 24 suites green.

**Fixture corpus pin held**: existing fixtures leave MSH-17 / MSH-19 empty, so the S5-C rules don't fire on them. The corpus continues to pass under both locales.

**Cumulative v0.5**: 23 AU rules now firing under `.auLocalisation` (5 field-level EI from S5-B-1, 12 datatype-level pair rules across CE/CNE/CWE from S5-B-2, 2 CX completeness rules from S5-B-3, 4 MSH value-set rules from S5-C — counting each MSH-19 component check separately).

### Added — v0.5-S5-B-3: AU ADRM-2021 CX required-component rules (HL7au:00044.1.2 / .1.3)

Third substage of the AU profile constraint overlays. Extends `CompositeOverride` with a `requiredComponents` track parallel to the `pairRules` from S5-B-2, then ships the AU CX completeness rules.

- **`Profile` model extension**:
  - `CompositeOverride.requiredComponents: [ComponentRequirement]` — new sub-rule track. Each requirement says "when a field of this dataType is populated, this component must be populated".
  - `ComponentRequirement` — internal struct (1-based component index + `specCitation`). Citation-per-rule keeps attribution clean.
  - Existing `pairRules` track unchanged; both tracks dispatch together inside `checkProfileCompositeOverrides`.

- **AU rules added**:
  - **CX `HL7au:00044.1.2 (r2)`** — CX-4 Assigning Authority must be valued when CX is populated.
  - **CX `HL7au:00044.1.3`** — CX-5 Identifier Type Code must be valued when CX is populated.
  - Skipped (with reasons documented in source comments):
    - `HL7au:00044.1.1` (CX-1 must be specified) — redundant with base spec, which already requires CX-1 via `CX.requiredComponents`.
    - `HL7au:00044.1.2` NASH sub-points and `HL7au:00044.1.3` value-set membership — runtime/PKI-dependent or value-set-dispatch work, deferred.

- **`Validator.checkProfileCompositeOverrides`** extended to dispatch the new `requiredComponents` track before the existing `pairRules` track. Same `.profileConstraintViolation(localeRule:)` plumbing; citation per rule.

- **`Resources/profiles/au-adrm-2021/datatypes.json`** — CX entry added with both AU rules + an `_skipped` documentation block listing the rules deliberately omitted with their reasons. Source-of-truth for the Swift Profile content.

- **Tests added (Tests/HL7v2KitTests/LocaleAUProfileTests.swift)**: 5 new tests — PID-3 with CX-4 missing fires `HL7au:00044.1.2`, PID-3 with CX-5 missing fires `HL7au:00044.1.3`, AU-conformant CX fires nothing, CX rules apply to every populated CX field (PID-2 deprecated still triggers under `.auLocalisation`), `.international` locale never fires AU rules. 375 → 380 tests across 24 suites green.

The fixture corpus continues to pass under both locales — existing fixtures coincidentally populate CX-4 (assigning authority) and CX-5 (identifier type code) when PID-3 is populated, so they're AU-conformant on these two new rules.

**Cumulative**: v0.5 has now landed 19 AU rules under `.auLocalisation` (5 field-level EI from S5-B-1, 12 datatype-level pair rules across CE/CNE/CWE from S5-B-2, 2 CX completeness rules from S5-B-3).

### Added — v0.5-S5-B-2: AU ADRM-2021 datatype-level pair rules (CE / CNE / CWE)

Second substage of the AU profile constraint overlays. Extends the Profile model from per-field overrides (S5-B-1) to also carry per-HL7-datatype overrides, then ships 12 AU pair-conditional rules.

- **`Profile` model extension**:
  - New `compositeOverrides: [CompositeOverride]` track alongside the existing `fieldOverrides: [FieldOverride]`.
  - New `CompositeOverride` (dataType code + `pairRules: [PairConditional]`).
  - New `PairConditional` (ifComponent / condition / thenComponent / requirement / specCitation).
  - New `PairCondition` enum (`.populated` / `.empty`).
  - New `PairRequirement` enum (`.mustBePopulated` / `.mustBeEmpty`).
  - All types internal — public surface unchanged.

- **AU rules added** (12 total, from Appendix 5 of HL7AUSD-STD-OO-ADRM-2021.1):
  - **CE** (`HL7au:00044.4.{1,2,5,6}`): identifier ⇔ name of coding system, alt identifier ⇔ alt name of coding system.
  - **CNE** (`HL7au:00044.5.{1,2,5,6}`): same shape on CNE composites.
  - **CWE** (`HL7au:00044.6.{1,2,4,5}`): same shape; spec numbers alt rules as `.4` / `.5` rather than `.5` / `.6`.
  - Skipped (deferred): `*.3` (CE-2 text must-be-valued — carries a "may be blank" carve-out that violates "no predicate ships if known-incorrect"), `*.4` LOINC-first / `*.7` concept-match / `*.8` distinct-alt-coding-system (value-set / semantic rules deferred to S5-C).

- **`Validator.checkProfileCompositeOverrides`** (new): for each populated field, looks up the override by `fieldGrammar.dataType`. For each pair rule, checks the condition on `ifComponent`; if triggered, requires the `thenComponent` to satisfy the requirement; fires `.profileConstraintViolation(localeRule: <HL7au-id>)` on failure. Dispatches per repetition.

- **`Resources/profiles/au-adrm-2021/datatypes.json`** — new overlay file documenting the 12 pair rules with verbatim spec citations. Source-of-truth for the Swift Profile content.

- **Tests added (Tests/HL7v2KitTests/LocaleAUProfileTests.swift)**: 5 new tests covering CE identifier-without-coding-system, alt-identifier-without-alt-coding-system, empty-identifier-with-coding-system (inverse), fully-consistent CE (no false positives), and a dataType-dispatch sanity check that CE fields (not CWE) fire CE rules. 370 → 375 tests across 24 suites green.

**Fixture corpus pin held**: all 51+3 fixtures still pass under both `.international` and `.auLocalisation` — they happen to be CE-consistent (every CE-1 is paired with a CE-3; every empty CE-1 has empty CE-3). The additive-errors invariant in `LocaleTests.auLocaleAddsButDoesNotRemoveBaseSpecErrors` continues to pass.

### Added — v0.5-S5-B-1: AU ADRM-2021 EI-completeness rules

First substage of the AU profile constraint overlays. The `.auLocalisation` locale was a no-op overlay in v0.4-S5-A; v0.5-S5-B-1 ships the first 5 concrete AU rules:

- **`Resources/profiles/au-adrm-2021/{OBR,ORC}.json`** — overlay JSONs documenting the rules with spec citations:
  - `OBR-2` (Placer Order Number EI): all 4 components required when populated. HL7au:000003 (r2).
  - `OBR-3` (Filler Order Number EI): all 4 components required when populated. HL7au:000004.1 (r3).
  - `ORC-2` (Placer Order Number EI): all 4 components required when populated. HL7au:000005 (r2).
  - `ORC-3` (Filler Order Number EI): all 4 components required when populated. HL7au:000006 (r3).
  - `ORC-4` (Placer Group Number EI): all 4 components required when populated. HL7au:000007 (r2).
- **`Sources/HL7v2Kit/Locale/Profile+au_adrm_2021.swift`** (new) — hand-curated runtime Profile mirroring the JSON overlays. Codegen support for profile overlays is deferred until more profiles need this pattern.
- **`Validator`** extended to dispatch `Profile.fieldOverrides`. When `.auLocalisation` is set AND a field has an override AND is populated, the override's `requiredComponents` rule fires `.profileConstraintViolation(localeRule: <HL7au-identifier>)` for each missing component.
- **`ProfileLoader.load(for: .auLocalisation)`** now returns `Profile.auADRM2021` instead of the empty S5-A scaffold.

Behavioural change for `.auLocalisation` consumers: AU-incomplete OBR/ORC EI fields now fire `.profileConstraintViolation`. `.international` locale is unchanged.

Tests added: 9 new tests in `LocaleAUProfileTests.swift` covering each rule's positive / negative / cross-locale behaviour, plus 1 spec-citation pin. `LocaleTests.swift`'s fixture-corpus pin renamed from "AU locale doesn't introduce new errors" to "AU locale errors are a superset of international errors" and re-implemented with the additive-errors invariant (AU may ADD errors, never REMOVES one). 360 → 368 tests across 23 → 24 suites green.

Spec citation: HL7AUSD-STD-OO-ADRM-2021.1 Appendix 5 Conformance Statements (Normative). Author-local PDFs at `docs/standards/HL7_v24_PDF/`.

## [0.4.0] — 2026-06-18

v0.4 cycle release. Three tracks landed: **spec accuracy** (v2.5.1 + v2.4 schemas spec-text-audited; conditional predicates with citations; compound DSL; composite OR-rule enforcement via `RequiredComponentSet`), **localisation API** (`HL7Locale` first-class enum locked for v1.0 stability per ADR-007 Accepted), and **typed segments** (15 typed segments — added EVN, MSA, ERR, PD1, DG1, IN1). 322 → 360 tests across 22 → 23 suites. **API-affecting** — purely additive: new `HL7Locale` enum, new `locale:` parameter on `Parser.init` / `Validator.init`, new `Message.locale` / `ValidationReport.locale` accessors, new `IssueCode.profileConstraintViolation(localeRule:)` case, new typed-segment surface for the 6 additions. No public-API breakage from v0.3.0. The 3-month no-API-break v1.0 stability clock restarts from this tag per Migration.md.

### Added — v0.4-T3: IN1 (Insurance) typed segment — closes segments track

- **`Resources/schemas/v2.5.1/IN1.json`** — 25 fields (billing-essentials subset of the full 53-field v2.5.1 segment). Covers set ID (R), insurance plan ID (CE, R), insurance company ID (CX, R, repeats), company name (XON) + address (XAD) + contact (XPN) + phone (XTN), group number + name + employer ID/name, plan effective + expiration dates, authorization info (AUI), plan type, insured name (XPN) + relationship + DOB + address, assignment + coordination of benefits, COB priority, notice-of-admission flag + date, report-of-eligibility flag.
- **Codegen output**: `Sources/HL7v2Kit/Segment/Generated/IN1.swift` + `SegmentRegistry+Generated.swift` extension + `SegmentGrammar+v2_5_1.swift` row. 15 typed segments total (was 14).
- **T3 capstone test**: existing fixture `adt_a01_with_insurance.hl7` (which previously exercised IN1 as UnknownSegment) now auto-hydrates IN1 typed and round-trips byte-perfectly. **No fixture changes needed** — the wire was already spec-conformant.
- 7 new tests in `TypedSegmentTests.swift`. 353 → 360 tests across 23 suites green.

### Added — v0.4-T2: PD1 + DG1 typed segments

- **`Resources/schemas/v2.5.1/PD1.json`** — 21 fields (full v2.5.1 surface) covering living dependency/arrangement, primary facility (XON), primary care provider (XCN, B-deprecated), student/handicap/living-will/organ-donor indicators, separate bill, duplicate patient (CX), publicity code (CE), protection indicator + effective date, place of worship (XON), advance directive code (CE), immunization registry status, publicity-code effective date, military branch/rank/status.
- **`Resources/schemas/v2.5.1/DG1.json`** — 21 fields (full v2.5.1 surface) covering set ID (R), diagnosis coding method (B-deprecated), diagnosis code (CE), date/time, diagnosis type (R), legacy MDC/DRG/outlier fields (B-deprecated), priority, diagnosing clinician (XCN repeats), classification, confidential indicator, attestation date, diagnosis identifier (C) + diagnosis action code (C). The two C-fields carry no `condition` predicate — both are "required for P12 update messages" which is a message-context rule the same-segment DSL cannot express; deferred per the no-predicate-without-citation rule.
- 9 new tests in `TypedSegmentTests.swift` covering scalar + composite accessors + round-trip equality. 344 → 353 tests green.

### Added — v0.4-T1: EVN + MSA + ERR typed segments

- **`Resources/schemas/v2.5.1/EVN.json`** — 7 fields (event type code B, recorded date/time R, planned event date, event reason code, operator ID XCN repeats, event occurred, event facility HD).
- **`Resources/schemas/v2.5.1/MSA.json`** — 6 fields (ack code R, message control ID R, text message B, expected sequence number, delayed acknowledgment type X (withdrawn v2.5), error condition B).
- **`Resources/schemas/v2.5.1/ERR.json`** — 12 fields covering the v2.5+ redesign (ELD ERR-1 B for backward compat, ERL ERR-2 location, CWE ERR-3 R hl7 error code, ID ERR-4 R severity, + 8 informational fields).
- **Codegen**: 12 typed segments total after T1 (was 9). All four `SegmentGrammar+v2_X.swift` tables refreshed.
- **Fixture correction**: `Tests/Fixtures/ack_application_error.hl7` updated to v2.5.1-conformant ERR layout. The pre-T1 fixture used the v2.4-style single ERR-1 ELD (`ERR|PID^1^3^1|||101^...`) but was labeled MSH-12 = 2.5.1. While ERR was UnknownSegment the validator couldn't see the mismatch; once ERR became typed under v2.5.1 grammar, missing ERR-3 (R) + ERR-4 (R) surfaced. Updated to `ERR||PID^1^3^1|101^Invalid patient ID format^HL70357|E`. FIXTURES.md row annotated.
- 12 new tests in `TypedSegmentTests.swift` covering EVN/MSA/ERR scalar + composite accessors, round-trip equality, and ACK fixture auto-pickup regression pins. 322 → 344 tests green.

### Added — v0.4-S5-A: `HL7Locale` public API + Profile/ProfileLoader scaffold

- **`HL7Locale` public enum** (Sources/HL7v2Kit/Locale/HL7Locale.swift): `.international` (default, base spec only) / `.auLocalisation` (HL7AUSD-STD-OO-ADRM-2021 over base v2.4). Sendable, CaseIterable, raw-value-backed. **Locale-as-mode is a first-class public API**, not a buried profile toggle — per ADR-007 Accepted.
- **`Parser.init(options:locale:)`** overload + `Parser.locale` accessor.
- **`Validator.init(options:locale:)`** overload + `Validator.locale` accessor.
- **`Message.locale`** property + `Message.init(...locale:)` parameter.
- **`ValidationReport.locale`** property + `ValidationReport.init(...locale:)`.
- **`IssueCode.profileConstraintViolation(localeRule:)`** additive enum case carrying the AU-rule identifier for attribution (pre-v1.0 allowed per Migration.md).
- Internal scaffold (consumers never see these): `Profile` value type with `FieldOverride` + `ProfileUsage`; `ProfileLoader` returns `nil` for `.international` and an empty Profile for `.auLocalisation`. JSON-backed loader + AU narrowings ship in S5-B/C/D.
- **Behavioural change: NONE.** `.auLocalisation` loads an empty overlay; no `profileConstraintViolation` issues fire in S5-A. Fixture corpus has identical issue counts under both locales (pinned by `auLocaleNoRegressionsOnFixtureCorpus`).
- **Downstream-consumer surface**: callers can read `message.locale` / `report.locale` to see which conformance set was applied. HL7v2Kit makes no claims about downstream behaviour; the locale is a conformance-validation feature for HL7 integrators. (Scope correction 2026-06-18: the initial v0.4-S5-A entry framed this as "FHIR AU Core mapper unblocking", which overstated HL7v2Kit's purpose. Mapping happens in downstream consumers, not here.)
- 10 new tests in `LocaleTests.swift`. 318 → 332 tests across 22 → 23 suites green.
- **ADR-007** (`docs/design/ADR-007-au-profile-architecture.md`): Accepted 2026-06-18. Locale-aware architecture; base schemas stay spec-faithful; AU constraints live in separate `Resources/profiles/au-adrm-2021/` overlay (ships in S5-B).

### Added — v0.4-S2-reopen: v2.4 OBX-2 carry-forward (S2 deferred item closed for v2.4)

- **Trigger**: v2.4 Final Standard PDFs added at `docs/standards/HL7_v24_PDF/` (author-local, not committed pending IP review), including the AU ADRM-2021 localisation profile.
- **Schema correction**: `Resources/schemas/v2.4/OBX.json` — OBX-2 gains `condition: "OBX-11 != X"` per v2.4 §7.4.2.2. Wording is verbatim-identical to v2.5.1 §7.4.2.2; carry-forward is spec-citable.
- **Audit doc updated**: `docs/design/v2_3-v2_4-spec-audit.md` OBX-2 row now marks v2.4 RESOLVED with the v2.4 spec citation. v2.3 / v2.3.1 still deferred (no PDFs).

### Changed — Housekeeping: `add-kernel-headers.sh` moved to `scripts/`

- The one-shot kernel-header utility moved from repo-root to `scripts/`. Its `KERNEL_FILES` list extended to include the new `Sources/HL7v2Kit/Locale/HL7Locale.swift` so future re-runs cover the v0.4-S5-A additions.

### Added — v0.4-S2: structural delta audit of v2.3 / v2.3.1 / v2.4 schemas

- **`docs/design/v2_3-v2_4-spec-audit.md`** — new audit doc covering all 9 segments × 3 earlier HL7 v2 versions as structural deltas against the spec-audited v2.5.1 baseline.
- **0 corrections warranted on the structural-delta axis.** Per-field consistency check across 4 versions: every field present in 2+ versions has identical `name` / `dataType` / `optionality` / `repeatability`.
- **Field-count progression** captured for all 9 segments: MSH 15→17→20→21; PID 30→30→32→39; OBR 43→43→47→47; OBX 11→14→16→17; ORC 17→17→19→31; NTE 3→3→3→4. NK1 / PV1 / AL1 stable at their typed-surface caps. End-to-end pinned in `MultiVersionTests.swift`.
- **Conditional-rule carry-forward**: PID-35 / PID-36 from S4-C don't apply below v2.5 (fields don't exist). OBX-2 carry-forward is plausible but **deferred** — the v2.3 / v2.3.1 / v2.4 Final Standard PDFs aren't locally available, so the per-version §7.4.2.2 text can't be cited.
- **Known limitations documented honestly** under the the working notes "honesty over completeness" requirement: per-version conditional rules, per-version composite-component definitions, and per-version errata are deferred to a future cycle when the relevant PDFs become available.
- No schema mutations; no source / test changes. 322/322 tests across 22 suites green (unchanged).

### Added — v0.4-S4 substage C: spec-text-driven schema corrections (PID-35 / PID-36 / OBX-2)

- **Schema corrections under `Resources/schemas/v2.5.1/`**, each citable to the v2.5.1 Final Standard (ANSI/HL7 April 2007). The author's local copy of the spec PDFs (not committed pending IP review) was used; the audit doc lists section numbers for each citation:
  - **`PID.json`**: PID-35 (Species Code) gains `condition: "PID-36 populated OR PID-38 populated"` per §3.4.2.35. PID-36 (Breed Code) `condition` corrected from the backwards `"PID-35 populated"` to the spec-accurate `"PID-37 populated"` per §3.4.2.36. The pre-S4 predicate was on the wrong field and fired in the wrong direction; the original S1 audit's "non-human species" narrative was speculation, not a spec citation.
  - **`OBX.json`**: OBX-2 (Value Type) gains `condition: "OBX-11 != X"` per §7.4.2.2. Uses the new compound-DSL `!= <value>` operator.
- **Audit doc rewrite** (`docs/design/v2_5_1-spec-audit.md`):
  - **Gap 1 (PID conditional rules) RESOLVED** with spec citations.
  - **Gap 2 PARTIALLY RESOLVED**: OBX-2 closed; the 12 other fields (ORC-2 / ORC-3 / ORC-8 / OBR-1 / 7 / 8 / 10 / 14 / 22 / 25 / 26 / 32 / OBX-4) carry **cross-segment** rules (ORC-2 ↔ OBR-2 XOR per §4.5.1.2) or **message-context** rules (OBR-25 "when in a report message" per §4.5.3.25) that the same-segment compound DSL cannot express. Documented as known limitations requiring cross-segment DSL extension — candidate for post-v0.4 cycle. The S1 audit's "ORC-2 required when ORC-1 in (NW/CA/...)" claim was a speculative reconstruction and has been retracted in the audit doc.
  - **Gap 3 (composite OR-rules) RESOLVED** with the spec-text caveat that the OR-rule choices for CWE / XTN / HD / PL / EIP are interpretive (community-convention) rather than directly cited — the v2.5.1 component tables list all components as `O`. Documented so integrators don't mistake them for literal spec assertions.
- **Tests**: `Tests/HL7v2KitTests/ConditionalFieldTests.swift` rewritten around the corrected predicates. 11 tests cover: PID-37→PID-36 trigger + satisfaction, PID-36→PID-35 trigger + satisfaction, PID-38→PID-35 OR-branch trigger, OBX-11≠X→OBX-2 trigger + satisfaction, OBX-2-populated short-circuit, OBX-11=X no-trigger, plus the fixture-corpus regression pin (none of the 48 valid fixtures populate the veterinary fields or trigger the OBX-2 path). 318 → 322 tests across 22 suites green.
- **Spec PDFs** (Final Standard, April 2007) referenced locally during the audit; **not committed** pending IP review. The audit doc captures the specific section numbers and pull-quoted text so the conclusions remain reproducible without requiring the PDFs in-tree.

### Added — v0.4-S4 substages A + B: composite OR-rule enforcement + compound-predicate DSL

- **`Sources/HL7v2Kit/Composite/RequiredComponentSet.swift`** (new). Value type with two semantics cases: `.atLeastOneOf` and `.allOfGroupOrAtLeastOne(group:)`. Closes audit Gap 3: composites with OR-rule conformance (CWE / XTN / HD / PL / EIP) now enforce their spec rule via `requiredComponentSet`, instead of skipping silently. The Validator's `checkComponents` dispatches both the flat `requiredComponents` check (v0.2-V2) and the new OR-rule check (v0.4-S4) per repetition.
- **CWE composite behavioural change**: `requiredComponents` was `[(1, "Identifier")]`, which false-positive'd on legitimate CWE-9-only payloads. Now `requiredComponents = []`; `requiredComponentSet = atLeastOneOf(CWE-1, CWE-9)`. Migration: callers that scanned `CWE.requiredComponents` for `(1, "Identifier")` should switch to `CWE.requiredComponentSet`. Pre-v1.0 API change.
- **Compound-predicate DSL** in `Validator.conditionTriggers`. Grammar extends from single-atom (`<segment>-<index> <op>`) to `<atom> (AND <atom>)* (OR <atom>)*` plus `in (<values>)` / `not in (<values>)` set-membership operators. Recursive-descent evaluator; AND binds tighter than OR. `not in` requires referent to be populated (fail-safe rule for ambiguous empty referents). Schema strings continue to be the public format — no `FieldGrammar` API break.
- **Audit doc updated**: Gap 3 marked RESOLVED at commit `0959be6`; Gaps 1 + 2 marked INFRASTRUCTURE LANDED, SCHEMA-LEVEL CLOSURE PENDING (substage C blocked on spec-text citations for ORC-2's value set etc.).
- Test count: 316 → 318 across 22 suites green (2 new positive pins; 1 existing pin renamed + assertion updated). All 51 top-level + 3 batch fixtures still round-trip byte-perfect.

### Added — HL7 v2.5.1 schema audit document (v0.4-S1)

- **`docs/design/v2_5_1-spec-audit.md`** — new design doc capturing the v0.4-S1 audit of all 9 v2.5.1 schemas against the public HL7 v2.5.1 spec, **re-framed under the the working notes project requirements** (feature-complete over AU-specific; integrator primary-reference tool).
- **Per-field attributes (name / dataType / optionality / repeatability) — 0 corrections warranted** across 198 rows. The schemas faithfully render the spec on those four axes.
- **3 spec-completeness defects identified** — not deferrable under the project requirements; each must be closed before v1.0 freezes the API:
  1. **PID-36 `condition: "PID-35 populated"` is over-broad** — fires false-positive on spec-compliant `PID-35 = L1^Human` (human patient with species explicitly declared, PID-36 legitimately empty).
  2. **12+ `C` fields without predicates** — ORC-2 / ORC-3 / ORC-8 / OBR-1 / 7 / 8 / 10 / 14 / 22 / 25 / 26 / 32 / OBX-2 / 4 all carry compound `AND` / `OR` spec conditions the v0.2-V1 single-predicate DSL cannot express. Validator currently provides no enforcement.
  3. **Five composite OR-rules silently unenforced** — CWE-1 OR CWE-9; XTN-1 OR XTN-4 OR XTN-12; HD-1 OR HD-2&3; PL-1 OR PL-4; EIP-1 OR EIP-2. Validator's `requiredComponents` dispatch returns empty for each.
- **No schema mutations in S1.** The defect fixes require model extensions (compound predicates in the conditional-field DSL; `RequiredComponentSet` for composite OR-rules). Both are scheduled for **v0.4-S4** — a new stage inserted between S1 and S2 per the cycle re-scope. S4 extends the model; the schema-level corrections land in S4's commit alongside the model change. S2 and S3 then absorb the richer model.
- **v0.4 cycle scope updated** from Option A (6 stages) to Option α (7 stages) — see NEXT_STEPS.md for the new S4 task entry and the updated stage order on the spec branch (S1 → S4 → S2 → S3).
- **Note on framing history**: an earlier S1 framing deferred these as "AU traffic doesn't trigger them" known limitations. That framing was rejected by the project owner under the integrator-reference-tool requirement and replaced with the current "defect, not deferrable" classification. The the working notes update at commit `909142b` codifies the requirement going forward.
- **No source / generated / test changes** in S1. `SegmentGrammar+v2_5_1.swift` codegen output is byte-identical pre- and post-audit. 316/316 tests across 22 suites green (unchanged).

## [0.3.0] — 2026-06-17

v0.3 cycle release. Covers four parallel-track surface expansions and a post-cycle layout refactor: all 16 v2.5.1 typed-segment-surface composites promoted to Swift struct views; `Validator` dispatches four HL7 v2 versions (v2.3 / v2.3.1 / v2.4 / v2.5.1); MLLP framing + structural batch parser + streaming batch parser ship the full TCP-to-Messages pipeline; byte-level fuzz harness across every parser surface; fixture corpus grew 48 → 51 + 3 batch fixtures. **API-affecting** — 16 typed-segment accessor return types went `Field?` → `<Composite>?` across the cycle. Migration path preserved via the public `.field` escape hatch on each composite struct (per the v0.2-C1 pattern). The 3-month no-API-break v1.0 stability clock continues from this tag per Migration.md.

### Added — Fixture corpus growth past 48 (v0.3-Z2)

- **`Tests/Fixtures/` corpus grew 48 → 51 top-level + 3 batch fixtures**. New material targets the surfaces v0.3 introduced — earlier fixtures were all v2.5.1 single-message wires.
- **Multi-version fixtures** (top-level, picked up automatically by `FixtureRoundTripTests` since `Parser.parse(_:)` handles all four supported versions):
  - `adt_a01_v23.hl7` — minimal v2.3 admit; exercises the v2.3 grammar table (MSH cap at 15)
  - `orm_o01_v231.hl7` — v2.3.1 order; exercises the v2.3.1 grammar table (PID cap at 30, ORC cap at 17)
  - `oru_r01_v24.hl7` — v2.4 result; populates PID-31 / PID-32 (`identityUnknownIndicator` / `identityReliabilityCode`, the v2.4 additions); MSH-18 charset declared
- **Batch fixtures** (new `Tests/Fixtures/Batches/` subdirectory — `FixtureRoundTripTests` enumerates only the top-level dir, so these are intentionally invisible to the `Parser`-based round-trip harness):
  - `Batches/batch_bhs_minimal.hl7` — BHS + 1 MSH + BTS, smallest valid batch wrapper
  - `Batches/batch_file_full.hl7` — FHS + BHS + 2 MSH + BTS + FTS, exercises all four framing markers
  - `Batches/batch_multi_groups.hl7` — FHS + 2 BHS/BTS pairs + FTS (one ADT batch + one ORU batch)
- **New `Tests/HL7v2KitTests/BatchFixtureTests.swift`** enumerates `Batches/` and exercises every fixture through `BatchParser` + `StreamingBatchParser`. 5 tests cover: every-file-parses smoke check / each fixture's structural assertions / parity between `BatchParser` and `StreamingBatchParser` message counts.
- **`Tests/Fixtures/FIXTURES.md`** updated with provenance rows for all 6 new fixtures + a v0.3-Z2 status block above the table.
- **Fuzz coverage automatically grows**: `FuzzTests.swift`'s `seedFixtures()` loader pulls the 3 new top-level fixtures into the cross-product. Per-cycle mutation count: 47 × 7 × 100 × 5 ≈ 165k → **50 × 7 × 100 × 5 ≈ 175k** mutated payloads (Batches/ subdir is correctly skipped by the top-level enumeration). Fuzz suite still passes under `RUN_FUZZ_TESTS=1` (~5.8s).
- 5 new tests in `BatchFixtureTests.swift` (auto-discover-and-parse, three per-fixture structural checks, BatchParser/StreamingBatchParser parity). 311 → 316 tests across 21 → 22 suites on default `swift test`.

### Changed — `Generated/v2_5_1/` subdirectory flattened to `Generated/` (folder-layout consistency)

- **Typed-segment struct files moved up one level**: the 9 generated `<SegmentID>.swift` files (PID / MSH / NK1 / NTE / OBR / OBX / ORC / PV1 / AL1) now live directly at `Sources/HL7v2Kit/Segment/Generated/`, alongside the per-version `SegmentGrammar+vX_Y_Z.swift` tables and `SegmentRegistry+Generated.swift`. The misleading `v2_5_1/` subdirectory has been deleted.
- **Why.** The struct surface is **shared** across every supported HL7 v2 version (v2.3 / v2.3.1 / v2.4 / v2.5.1) — accessors for fields that don't exist at an older version return `nil` per the Optional contract. Placing the structs under `Generated/v2_5_1/` implied sibling `Generated/v2_3_1/`, `Generated/v2_4/`, etc. that by design will never exist. The new layout makes the folder hierarchy honest: structs are version-agnostic; grammar tables are per-version.
- **Mechanism.** Single edit in `Sources/HL7v2KitCodegen/Codegen.swift`: the canonical-version output path is now `outputRoot/<SegmentID>.swift` instead of `outputRoot/<versionDirName(canonicalVersion)>/<SegmentID>.swift`. The codegen-drift CI job already pins reproducibility — the regenerated layout is byte-identical across re-runs.
- **API-compatible**. Swift module structure is unchanged — `import HL7v2Kit` still surfaces `PID` / `MSH` / etc. at the top level. No callsite edits required.
- **Path references**: `Sources/HL7v2KitCodegen/Codegen.swift` `canonicalVersion` doc comment and `Sources/HL7v2Kit/HL7v2Kit.docc/TypedSegments.md` Overview updated to point at the new location. Historical CHANGELOG entries for v0.3-G1 and historical NEXT_STEPS task lines reference the old path and are intentionally left as-is — they describe what was true when they landed.

### Added — Fuzz testing harness (v0.3-Z1)

- **`Tests/HL7v2KitTests/FuzzTests.swift`** — byte-level fuzz harness covering all four parser surfaces: `Parser.parse(_ data:)`, `BatchParser.parse(_ data:)`, `StreamingBatchParser.feed/finish`, and `MLLPUnframer.feed(_:)` (plus a `MLLPUnframer → Parser` round-trip composition). For each surface, the harness iterates over the cross-product `gold-corpus fixtures × mutators × iterations` and asserts the only acceptable failure mode is a thrown `ParseError`. Any other behaviour (non-`ParseError` throw, force-unwrap trap, slice out-of-bounds, infinite loop) fails the test.
- **Mutators**: 7 small targeted perturbations — `bitFlip`, `byteReplace`, `byteInsert`, `byteDelete`, `truncate`, `delimiterCorrupt` (corrupts one of `|^~\&\r`), `nulInject`. Designed to surface bounds-checking bugs, not to model real-world corruption.
- **Seeded PRNG**: small Xorshift64\* generator with a fixed seed (`0xC0FFEE`) drives all mutations, so every fuzz failure is reproducible — the failing test records the (fixture × mutator × iteration) tuple and a replay against the same seed reproduces the case.
- **Skipped by default** like `PerformanceTests`. Run with `RUN_FUZZ_TESTS=1 xcrun swift test --filter FuzzTests`. Default `swift test` count goes 306 → 311 with the 5 fuzz tests marked `skipped: "Set RUN_FUZZ_TESTS=1 to run the fuzz suite"`.
- **Coverage at landing time**: 47 fixtures × 7 mutators × 100 iterations × 5 surfaces ≈ 165,000 mutated payloads exercised in ~5.4 s on the dev machine. All five tests pass — no crashes, no unexpected error types — across the full grid. Validates the byte-level robustness of every parser-side surface added through v0.3.

### Added — Streaming batch parser (v0.3-S1)

- **`StreamingBatchParser`** — incremental, memory-bounded variant of `BatchParser`. Consumes byte chunks of arbitrary size via `feed(_ bytes: Data) throws -> [Message]` and emits each completed `Message` as soon as the next MSH (or batch marker, or EOF) closes the current run. Designed for very-large historical-extract files that don't fit comfortably in memory. New `Sources/HL7v2Kit/Parser/StreamingBatchParser.swift`.
- **API surface**: value-type `feed(_:) throws -> [Message]` + `finish() throws -> [Message]` core for direct chunked-I/O use; plus `static StreamingBatchParser.messages(from: AsyncSequence<UInt8>) -> AsyncThrowingStream<Message, Error>` wrapper for callers using `FileHandle.AsyncBytes` or network read loops. The async wrapper buffers in 4 KB chunks before delegating to the core. `hasPending: Bool` observer is exposed for half-frame timeout detection (true when the parser has a partial segment or an open MSH run).
- **Scope note** (documented on the struct doc): streaming mode flattens batch markers — FHS / FTS / BHS / BTS lines are recognised (so they correctly close any open message) but their wire strings are NOT preserved. Callers needing the file / batch structure should use the non-streaming `BatchParser`. Streaming mode also assumes UTF-8 input (MSH-18 charset detection requires buffering the whole first message, which defeats the streaming property).
- **NUL rejection** mirrors `Parser.parse(_ data:)` — a `0x00` byte in the stream throws `ParseError.truncatedMessage(atByte:)` with the byte offset, both in the synchronous and `AsyncStream` paths.
- 11 new tests in `Tests/HL7v2KitTests/StreamingBatchParserTests.swift` cover: whole-input feed-then-finish / marker flattening (FHS+BHS+BTS+FTS consumed, not preserved) / byte-at-a-time feed produces identical output / random-sized chunk feed identical / incremental emission (first message surfaces before `finish()` once the second MSH boundary appears) / unterminated trailing segment flushed by `finish()` / `hasPending` lifecycle / NUL byte rejection / 100-message batch streamed in 1 KB chunks doesn't accumulate state / AsyncStream wrapper yields in order / AsyncStream wrapper throws on NUL. 295 → 306 tests across 19 → 20 suites.
- **Closes the v0.3-transport track.** T1 (MLLP) + T2 (BatchParser) + S1 (StreamingBatchParser) now cover the full transport-and-batch surface.

### Added — FHS / BHS batch parser (v0.3-T2)

- **`BatchParser`** — new structural parser for HL7 v2 batch / file grammar. Recognises the four framing markers (`FHS` file header, `FTS` file trailer, `BHS` batch header, `BTS` batch trailer) and groups the MSH-starting message runs between them. Each message run is dispatched to `Parser(options:).parse(_:)` so encoding detection, composite parsing, escape decoding, and typed-segment hydration behave identically to the bare-message path. New `Sources/HL7v2Kit/Parser/BatchParser.swift`.
- **`BatchFile`** + **`BatchGroup`** — new public value types modelling the result. `BatchFile.fileHeader` / `fileTrailer` carry the FHS / FTS wire strings (or `nil` if absent); `BatchFile.batches: [BatchGroup]` carries one entry per `BHS` / `BTS` pair (or a single header-less group for bare multi-MSH input). `BatchGroup.header` / `trailer` mirror the same pattern. Convenience `BatchFile.allMessages` flattens the messages across groups in document order.
- **API forms**. `BatchParser.parse(_ data: Data) throws -> BatchFile` mirrors `Parser.parse(_ data:)` semantics (BOM stripping, NUL rejection, MSH-18 charset detection). `BatchParser.parse(_ raw: String) throws -> BatchFile` is the already-decoded counterpart. Both accept lenient line terminators (`\r`, `\n`, `\r\n` all normalise to `\r` before segmentation).
- **The v0.1.0 `multipleMSHSegmentsAcceptedAsIs` pin is preserved**. `Parser.parse(_:)` on a bare multi-MSH stream still returns one `Message` with multiple MSH segments — the v0.3-T2 `BatchParser` is the opt-in alternative for callers that explicitly want each MSH-starting run split. New test `parserMultiMSHBehaviourUnchanged` pins the contract.
- 11 new tests in `Tests/HL7v2KitTests/BatchParserTests.swift` cover: bare multi-MSH splits / single-message no-framing / batch-only framing (BHS+msgs+BTS) / fully-wrapped (FHS+BHS+...+BTS+FTS) / multi-batch file (two BHS/BTS pairs in one FHS/FTS) / empty batch (BHS immediately followed by BTS) / per-message delegation to the full Parser pipeline (typed composite accessors work) / `parse(Data:)` BOM strip + NUL rejection / lenient line terminators (LF parses identically to CR) / empty-input throws / regression pin for the v0.1.0 Parser contract. 284 → 295 tests across 18 → 19 suites.

### Added — MLLP framing (v0.3-T1)

- **`MLLP.frame(_:)`** — wraps an HL7 message body in the standard Minimum Lower Layer Protocol envelope (`0x0B <body> 0x1C 0x0D`). Callers stream the result directly to a TCP socket; body bytes are opaque (no escape processing at the MLLP layer).
- **`MLLPUnframer`** — stateful unframer that consumes incremental TCP byte chunks via `feed(_:)` and emits complete frame bodies as their trailing `0x1C 0x0D` arrives. Handles realistic TCP boundary cases: half-frames across multiple receives, multiple frames in one receive, byte-at-a-time delivery, garbage prefix before the first start byte (silently dropped — common receiver-resilience pattern), and mid-frame restart (a fresh `0x0B` re-syncs the buffer). Exposes `isMidFrame: Bool` for application-layer half-frame-timeout detection.
- **`MLLP`** namespace exports `startByte` (`0x0B`), `endBodyByte` (`0x1C`), `endFrameByte` (`0x0D`) for callers that need to inspect or hand-construct frames at the byte level.
- **Portable-kernel placement**. New `Sources/HL7v2Kit/Transport/MLLPCodec.swift` carries the PORTABLE KERNEL header per ADR-006 — `Data` only at API edges, `[UInt8]` for the inner buffer, no Foundation dependencies beyond the type itself. Future Rust/Go port translates this file directly.
- 12 new tests in `Tests/HL7v2KitTests/MLLPCodecTests.swift` cover framing (single + empty body + body preserved), unframing happy path (one frame / two concatenated / empty body), partial-frame streaming (half-and-half / three-way split / one-byte-at-a-time), resync (garbage prefix dropped / mid-frame restart), round-trip preservation, and end-to-end `frame() → unframe() → Parser.parse()` integration. 272 → 284 tests across 17 → 18 suites.

### Added — HL7 v2.3 grammar table + `Version.v2_3` case (v0.3-G3)

- **`Version.v2_3 = "2.3"`** — new enum case for the oldest HL7 v2 dialect HL7v2Kit supports. `Version` enum cases now cover `.v2_3` / `.v2_3_1` / `.v2_4` / `.v2_5_1` / `.v2_8`; messages with `MSH-12 = "2.3"` previously fell through `Version(rawValue:)` to nil and the parser's silent v2.5.1 fallback. Now they parse with the correct `.version == .v2_3` and route to the v2.3 grammar table.
- **`SegmentGrammarTable.v2_3`** — codegen-emitted Swift literal table baked from new `Resources/schemas/v2.3/*.json` schemas. `Validator.grammarTable(for:)` extended: `case .v2_3 → SegmentGrammarTable.v2_3`. Four distinct grammar tables (v2.3 / v2.3.1 / v2.4 / v2.5.1) now dispatched.
- **`Resources/schemas/v2.3/*.json`** — 9 hand-curated schemas pruned from the v2.5.1 sources to the v2.3-era field caps: MSH 21 → 15 (no MSH-16 application-acknowledgement, MSH-17 country code, MSH-18 charset and beyond), OBX 17 → 11 (v2.3 had the early observation slots only; OBX-12..17 are v2.3.1+ / v2.4+ / v2.5+ additions). PID / ORC / OBR / NK1 / PV1 / NTE / AL1 unchanged from the v2.3.1 caps (already at or below the v2.3 surface).
- 6 new tests in `Tests/HL7v2KitTests/MultiVersionTests.swift`: v2.3 version detection / round-trip / dispatch / grammar table populated with v2.3 caps / four-way grammar dispatch confirming MSH grows monotonically 15 → 17 → 20 → 21 across v2.3 → v2.3.1 → v2.4 → v2.5.1 / typed accessors for v2.4+ fields return nil on a v2.3 wire. 266 → 272 tests across 17 suites.
- This commit closes the v0.3-multiversion track. Three new grammar tables landed total (v2.3 / v2.3.1 / v2.4); v2.5.1 unchanged.

### Added — HL7 v2.4 grammar table (v0.3-G2)

- **`SegmentGrammarTable.v2_4`** — codegen-emitted Swift literal table baked from new `Resources/schemas/v2.4/*.json` schemas; sits between v2.3.1 and v2.5.1 in field-count granularity. `Validator.grammarTable(for:)` extended: `case .v2_4 → SegmentGrammarTable.v2_4`. Only `.v2_8` remains at the empty-table fallback until v0.3 ships a future v2.8 stage.
- **`Resources/schemas/v2.4/*.json`** — 9 hand-curated schemas pruned from the v2.5.1 sources with the field caps that match the v2.4 spec surface: MSH 21 → 20 (no MSH-21 `messageProfileIdentifier`), PID 39 → 32 (adds PID-31 `identityUnknownIndicator` + PID-32 `identityReliabilityCode` over v2.3.1's 30; cuts the v2.5 species/breed/strain/tribal-citizenship tail), ORC 31 → 19 (adds ORC-18 `entererAuthorizationMode`-ish slot + ORC-19 `actionBy` over v2.3.1's 17; cuts the v2.5 ordering-facility cluster), OBX 17 → 16 (adds OBX-15 `producerIdentifier` + OBX-16 `responsibleObserver` over v2.3.1's 14; cuts OBX-17 `observationMethod` which is v2.5), OBR 43 → 47 (v2.4 already at the v2.5.1 surface for OBR — keep the full 47). NK1 / PV1 / NTE / AL1 unchanged from the v2.3.1 caps (already at or below the v2.4 surface).
- 6 new tests in `Tests/HL7v2KitTests/MultiVersionTests.swift`: v2.4 version detection / round-trip / validator routes to v2.4 grammar / table populated with v2.4 caps / typed accessors expose the v2.4 additions (PID-31/32) while v2.5-only fields stay nil / three-way cross-check confirms PID grows monotonically 30 → 32 → 39 across v2.3.1 → v2.4 → v2.5.1. 260 → 266 tests across 17 suites.

### Added — HL7 v2.3.1 grammar table (v0.3-G1)

- **Validator now dispatches grammar by message version.** Messages with `MSH-12 = "2.3.1"` validate against the new `SegmentGrammarTable.v2_3_1` table; v2.5.1 messages keep validating against the existing `SegmentGrammarTable.v2_5_1` table. The dispatch lives in `Validator.grammarTable(for:)` as a per-version switch. v2.4 / v2.8 fall back to an empty table (no grammar errors emitted) until v0.3-G2 / G3 land.
- **`Resources/schemas/v2.3.1/*.json`** — hand-curated JSON schemas for all 9 spec § 17 segments, pruned from the v2.5.1 schemas to the v2.3.1-era field counts: MSH 21 → 17 (no MSH-18 charset / MSH-19 principalLanguageOfMessage / MSH-20 altCharsetHandlingScheme / MSH-21 messageProfileIdentifier), PID 39 → 30 (no v2.4 identity flags or v2.5 species/breed/tribal-citizenship), ORC 31 → 17 (no v2.4 advancedBeneficiaryNoticeCode or v2.5 ordering-facility / confidentiality cluster), OBR 47 → 43 (no v2.4 results-handling extensions), OBX 17 → 14 (no v2.4 producerIdentifier / responsibleObserver / observationMethod). NK1 / PV1 / NTE / AL1 keep their existing field caps (already at or below the v2.3.1 surface).
- **`SegmentGrammarTable.v2_3_1`** — codegen-emitted Swift literal table baked from the v2.3.1 schemas, parallel to the existing v2.5.1 table. Total ~150 grammar entries across 9 segments. Reproducible across runs; CI codegen-drift job pins the output.
- **Mechanism**. `Sources/HL7v2KitCodegen/Codegen.swift` now declares `let canonicalVersion = "2.5.1"` and treats only the canonical version's schemas as the source of typed-struct emission — the v2.3.1 schemas contribute only to the grammar table. The shared typed `struct PID` / `struct ORC` / ... lives under `Generated/v2_5_1/` and represents the union surface; accessors for v2.4+ / v2.5+ fields on a v2.3.1 wire simply return `nil` (the normal Optional contract for an absent field). No per-version Swift namespace required; no API change for callers.
- 7 new tests in `Tests/HL7v2KitTests/MultiVersionTests.swift` cover: v2.3.1 wire parses with `.version == .v2_3_1`; v2.3.1 wire round-trips byte-perfectly; path and typed accessors agree on a v2.3.1 wire; validation runs against the v2.3.1 grammar table (not v2.5.1); the v2.3.1 grammar table is populated for all 9 segments with the right field counts; v2.5.1-only typed accessors return nil on a v2.3.1 wire; v2.5.1 messages still route to the v2.5.1 grammar table (regression pin). 253 → 260 tests across 16 → 17 suites.

### Changed — API-BREAKING (typed composites, v0.3-C4)

- **Typed-segment accessors for HD-, MSG-, PT-, VID-, PL-, CNE-, XON- and EIP-typed fields now return Swift struct views** instead of `Field?`. With v0.3-C4 closing out the composite-promotion track, **every populated typed-segment accessor on the 9 spec § 17 segments now returns either a `String?` (scalar) or a typed composite struct** — there are no remaining `Field?` accessors for structured HL7 datatypes on the v2.5.1 typed-segment surface. New structs live under `Sources/HL7v2Kit/Composite/` following the v0.2-C1 / v0.3-C2 / v0.3-C3 template.
  - `HD` — `namespaceID`, `universalID`, `universalIDType`. All 3 spec components exposed.
  - `MSG` — `messageCode`, `triggerEvent`, `messageStructure`. All 3 spec components exposed.
  - `PT` — `processingID`, `processingMode`. All 2 spec components exposed.
  - `VID` — `versionID`, `internationalizationCode` (first subcomponent of the nested CE), `internationalVersionID` (first subcomponent of the nested CE). All 3 spec slots exposed.
  - `PL` — `pointOfCare`, `room`, `bed`, `facility` (first subcomponent of the nested HD). The first 4 of 12 PL components — the AU clinical traffic common case. PL-5..12 remain accessible via `.field`.
  - `CNE` — `identifier`, `text`, `nameOfCodingSystem`, `altIdentifier`, `altText`, `nameOfAltCodingSystem`. All 6 spec components exposed (same shape as CE).
  - `XON` — `organizationName`, `organizationNameTypeCode`, `identifierTypeCode`, `organizationIdentifier`. The 4 commonly-populated XON components; XON-3 (deprecated), XON-4/5 (check digit / scheme), XON-6 (assigning authority, nested HD), XON-8 (assigning facility, nested HD), and XON-9 remain accessible via `.field`.
  - `EIP` — `placerAssignedIdentifier`, `fillerAssignedIdentifier`. Each accessor returns the first subcomponent of the nested EI (EI-1 entityIdentifier); for the full nested EI structure, drill into `.field.first?.components[N]`.
- **Required-component metadata**:
  - `MSG.requiredComponents = [(1, "Message Code")]`, `PT.requiredComponents = [(1, "Processing ID")]`, `VID.requiredComponents = [(1, "Version ID")]`, `CNE.requiredComponents = [(1, "Identifier")]`, `XON.requiredComponents = [(1, "Organization Name")]` — empty primary slot on a populated field fires `.requiredComponentMissing`.
  - `HD.requiredComponents = []`, `PL.requiredComponents = []`, `EIP.requiredComponents = []` — empty by design. HD's "HD-1 OR (HD-2 AND HD-3)", PL's "PL-1 OR PL-4", and EIP's "either slot populated" are the same disjunctive OR-rule shape v0.3-C2 / v0.3-C3 documented for CWE / XTN — modelling these is a future `RequiredComponentSet` refactor that v0.3-C4 explicitly avoids. Each empty `requiredComponents` choice is pinned by a dedicated `…SkipsSilentlyWithNoRequiredComponents` test so the choice can't silently flip later.
- **Affected typed-segment accessors** (any field with `dataType ∈ {HD, MSG, PT, VID, PL, CNE, XON, EIP}` across the 9 spec § 17 segments):
  - **HD**: `MSH.sendingApplication` / `sendingFacility` / `receivingApplication` / `receivingFacility`; `PID.lastUpdateFacility`. 5 accessors.
  - **MSG**: `MSH.messageType`. 1 accessor.
  - **PT**: `MSH.processingID`. 1 accessor.
  - **VID**: `MSH.versionID`. 1 accessor.
  - **PL**: `PV1.assignedPatientLocation` / `priorPatientLocation` / `temporaryLocation`; `ORC.enterersLocation`. 4 accessors.
  - **CNE**: `ORC.entererAuthorizationMode`. 1 accessor.
  - **XON**: `NK1.organizationName`; `ORC.orderingFacilityName`. 2 accessors.
  - **EIP**: `ORC.parent`; `OBR.parent`. 2 accessors.
- **Migration path** preserved via the public `field: Field` escape hatch — the same v0.1.x → v0.3.x pattern documented for the earlier composite promotions. `pid.lastUpdateFacility?.first?.components[0].stringValue` becomes either `pid.lastUpdateFacility?.field.first?.components[0].stringValue` (one extra hop) or the named accessor `pid.lastUpdateFacility?.namespaceID`.
- **Mechanism**. `Codegen.compositeDataTypes` whitelist extended to `["XPN", "CX", "XAD", "CE", "CWE", "EI", "XCN", "XTN", "HD", "MSG", "PT", "VID", "PL", "CNE", "XON", "EIP"]` — one-line edit. `Validator.requiredComponents(forCompositeCode:)` switch gains the 8 new cases.
- **Behavioural change on V2 component-grammar check**: messages with a populated MSG / PT / VID / CNE / XON field that lacks the required primary component now fire `.requiredComponentMissing` — previously skipped because these composites were untyped. Gold-corpus fixtures all populate the required component properly and remain unaffected; pinned by `ComponentGrammarTests.fixtureCorpusNoComponentErrors`. HD / PL / EIP remain silent because their `requiredComponents` is empty by design.
- **Test landscape**. `Validator`'s `untypedCompositesSkippedSilently` test rebased onto a new `hdSkipsSilentlyWithEmptyRequiredComponents` — the contract it was pinning (untyped composites skip silently) is now vacuous because every typed-segment composite is typed; the rebased test pins the related contract that HD's *deliberately empty* `requiredComponents` doesn't false-positive on legitimate HD-2-only fields. 11 existing test sites across `TypedSegmentTests.swift` migrated from `.first?.components[N].stringValue` to typed named accessors. 16 new tests in `CompositeTypeTests.swift` cover every named accessor on each of the 8 new composites + cross-check against path API + round-trip preservation. 7 new V2 tests in `ComponentGrammarTests.swift`: 5 positive enforcement tests (MSG / PT / VID / CNE / XON empty-primary fires) + 2 negative pins (PL / EIP empty-required-components skips silently). 230 → 253 tests across 16 suites.

### Changed — API-BREAKING (typed composites, v0.3-C3)

- **Typed-segment accessors for EI-, XCN- and XTN-typed fields now return Swift struct views** (`EI?` / `XCN?` / `XTN?`) instead of `Field?`. New structs live under `Sources/HL7v2Kit/Composite/` following the v0.2-C1 / v0.3-C2 template (value-type view over `Field`; `Sendable + Equatable + Hashable`; `init(field:)` + `init(repetition:)`; named accessors via a private `componentValue(_:)` helper; `static let requiredComponents` for V2 enforcement).
  - `EI` — `entityIdentifier`, `namespaceID`, `universalID`, `universalIDType`. All 4 spec components exposed.
  - `XCN` — `idNumber`, `familyName`, `givenName`, `middleName`, `suffix`, `prefix_`. The first 6 of XCN's 23 spec components — covers the common ID-plus-name-parts case. XCN-7..23 (degree, source table, assigning authority, name type code, identifier check digit, check digit scheme, identifier type code, assigning facility, name representation code, name context, name validity range, name assembly order, effective date, expiration date, professional suffix, assigning jurisdiction, assigning agency or department) remain accessible via `.field`.
  - `XTN` — `telephoneNumber` (XTN-1 deprecated free-form), `telecommunicationUseCode`, `telecommunicationEquipmentType`, `emailAddress`, `countryCode`, `areaCityCode`, `localNumber`, `unformattedTelephoneNumber` (XTN-12 modern primary). Covers the common phone / email / fax case; XTN-8..11 (extension, any text, extension prefix, speed dial code) and XTN-13/14 remain accessible via `.field`.
- **Required-component metadata**:
  - `EI.requiredComponents = [(1, "Entity Identifier")]` — empty EI-1 on a populated EI fires `.requiredComponentMissing`.
  - `XCN.requiredComponents = [(1, "ID Number")]` — empty XCN-1 on a populated XCN fires `.requiredComponentMissing`.
  - `XTN.requiredComponents = []` — empty by design. XTN-1 is deprecated and XTN-12 is the modern primary, but neither is strictly required; the "at least one of XTN-1 / XTN-4 / XTN-12" pattern is the same OR-rule shape v0.3-C2 documented for CWE. Modelling disjunctive required-component sets is a future RequiredComponentSet refactor that v0.3-C3 explicitly avoids.
- **Affected typed-segment accessors** (any field with `dataType ∈ {EI, XCN, XTN}` across the 9 spec § 17 segments):
  - **EI**: `MSH.messageProfileIdentifier`; `ORC.placerOrderNumber` / `fillerOrderNumber` / `placerGroupNumber`; `OBR.placerOrderNumber` / `fillerOrderNumber`. 6 accessors total.
  - **XCN**: `ORC.enteredBy` / `verifiedBy` / `orderingProvider` / `actionBy`; `OBR.collectorIdentifier` / `orderingProvider` / `resultCopiesTo`; `OBX.responsibleObserver`; `PV1.attendingDoctor` / `referringDoctor` / `consultingDoctor` / `admittingDoctor`. 12 accessors total.
  - **XTN**: `PID.phoneNumberHome` / `phoneNumberBusiness`; `NK1.phoneNumber` / `businessPhoneNumber`; `ORC.callBackPhoneNumber` / `orderingFacilityPhoneNumber`; `OBR.orderCallbackPhoneNumber`. 7 accessors total.
- **Migration path** preserved via the public `field: Field` escape hatch — v0.1.x / v0.2.x callers can rewrite `orc.orderingProvider?.first?.components[1].stringValue` as either `orc.orderingProvider?.field.first?.components[1].stringValue` (one extra hop) or migrate to the named accessor `orc.orderingProvider?.familyName`. Cross-check invariant holds for both: `orc.orderingProvider?.idNumber == message["ORC-12.1"]`.
- **Mechanism**. `Codegen.compositeDataTypes` whitelist extended to `["XPN", "CX", "XAD", "CE", "CWE", "EI", "XCN", "XTN"]` — one-line edit. `Validator.requiredComponents(forCompositeCode:)` switch gains EI/XCN/XTN cases.
- **Round-trip preserved**. Composite structs are value-type *views* over `Field`, not owners — the segment still holds the bytes. All 48 gold-corpus fixtures round-trip byte-identical; `CompositeTypeTests.compositeRoundTripsByteIdentical` covers EI/XCN/XTN wires too.
- **Behavioural change on V2 component-grammar check**: messages with an EI field populated as `^HOSP^ISO` (EI-1 empty) now fire `.requiredComponentMissing` at the appropriate field path — previously skipped because EI was untyped. Same for XCN with empty XCN-1. Gold-corpus fixtures all populate EI-1 / XCN-1 properly and remain unaffected; pinned by `ComponentGrammarTests.fixtureCorpusNoComponentErrors`.
- 9 new tests in `Tests/HL7v2KitTests/CompositeTypeTests.swift` cover every named accessor on each composite + the `.field` migration path (EI) + multi-repetition access (XCN consulting doctors, XTN home + mobile) + cross-check against path API + round-trip preservation. 3 new V2 tests in `ComponentGrammarTests.swift` (`eiFiresComponentMissingOnEmptyEntityIdentifier`, `xcnFiresComponentMissingOnEmptyIdNumber`, `xtnSkipsSilentlyWithNoRequiredComponents` — the last pins XTN's deliberately-empty `requiredComponents` list as the design choice). 11 existing test sites across `TypedSegmentTests.swift` migrated to the new named accessors. 218 → 230 tests across 16 suites.

### Changed — API-BREAKING (typed composites, v0.3-C2)

- **Typed-segment accessors for CE- and CWE-typed fields now return Swift struct views** (`CE?` / `CWE?`) instead of `Field?`. New structs live under `Sources/HL7v2Kit/Composite/` and expose named accessors for every component the spec defines:
  - `CE` — `identifier`, `text`, `nameOfCodingSystem`, `altIdentifier`, `altText`, `nameOfAltCodingSystem`
  - `CWE` — `identifier`, `text`, `nameOfCodingSystem`, `altIdentifier`, `altText`, `nameOfAltCodingSystem`, `codingSystemVersionID`, `altCodingSystemVersionID`, `originalText`
- **Required-component metadata** for both: CE-1 / CWE-1 (Identifier). `Validator.checkComponentGrammar` now fires `.requiredComponentMissing` on CE/CWE fields populated with an empty CE-1 / CWE-1 (e.g. `PID|...||^WhiteTextOnly` on PID-10). CWE's `"CE-1 OR CE-9"` OR-semantics from the v2.5.1 spec is simplified to "CE-1 required only" — documented as a known divergence; the conditional-field DSL doesn't yet support disjunctive component conditions.
- **Affected typed-segment accessors** (any field with `dataType ∈ {CE, CWE}` across the 9 spec § 17 segments):
  - **CE**: `MSH.principalLanguageOfMessage`; `AL1.allergenTypeCode` / `allergenCodeMnemonicDescription` / `allergySeverityCode`; `NK1.relationship` / `administrativeSex`; `OBR.universalServiceIdentifier` / many; `OBX.observationIdentifier` / `units` / many; `ORC.orderControlCodeReason` / `enteringOrganization` / `enteringDevice` / `advancedBeneficiaryNoticeCode`; `PID.race` / `primaryLanguage` / `maritalStatus` / `religion` / `ethnicGroup` / `citizenship` / `veteransMilitaryStatus` / `nationality` / `speciesCode` / `breedCode` / `productionClassCode`.
  - **CWE**: `PID.tribalCitizenship`; `ORC.orderStatusModifier` / `advancedBeneficiaryNoticeOverrideReason` / `confidentialityCode` / `orderType` / `parentUniversalServiceIdentifier`.
- **Migration path** preserved via the public `field: Field` escape hatch — v0.1.x callers can rewrite `pid.race?.first?.components[0].stringValue` as either `pid.race?.field.first?.components[0].stringValue` (one extra hop) or migrate to the named accessor `pid.race?.identifier`. Cross-check invariant holds for both: `pid.race?.identifier == message["PID-10.1"]`.
- **Mechanism**. `Codegen.compositeDataTypes` whitelist extended to `["XPN", "CX", "XAD", "CE", "CWE"]` — one-line edit. `Validator.requiredComponents(forCompositeCode:)` switch gains CE/CWE cases.
- **Round-trip preserved**. Composite structs are value-type *views* over `Field`, not owners — the segment still holds the bytes. All 48 gold-corpus fixtures round-trip byte-identical; `CompositeTypeTests.compositeRoundTripsByteIdentical` covers CE/CWE wires too.
- **Behavioural change on V2 component-grammar check**: messages with PID-10 (race) populated as `^WhiteTextOnly` (CE-1 empty) now fire `.requiredComponentMissing` at `PID[1]-10.1` — previously skipped because CE was untyped. Gold-corpus fixtures all populate CE-1 properly and remain unaffected; pinned by the updated `ComponentGrammarTests.fixtureCorpusNoComponentErrors`.
- 8 new tests in `Tests/HL7v2KitTests/CompositeTypeTests.swift` cover every named accessor on each composite + the `.field` migration path + multi-repetition access (PID-10 race) + cross-check against path API + round-trip preservation. 2 new V2 tests in `ComponentGrammarTests.swift` (`ceFiresComponentMissingOnEmptyIdentifier`, `cweFiresComponentMissingOnEmptyIdentifier`); the old "CE / CWE / EI skipped silently" test refactored to use the still-untyped HD (PID-34 lastUpdateFacility). 21 existing test sites across `TypedSegmentTests.swift` migrated to the new named accessors. 210 → 218 tests across 16 suites.

## [0.2.0] — 2026-06-15

### Added (infrastructure)

- **Top-level `HL7v2Kit.xcworkspace/`** at the repo root. Open with `open HL7v2Kit.xcworkspace` instead of `Package.swift` directly. Single `<FileRef>` to the package today; scales to multi-repo when `FHIRAUCoreKit` and `AUCoreWorkbench` land by adding more `<FileRef>` entries. The auto-generated `.swiftpm/xcode/package.xcworkspace` stays gitignored.
- **Four v0.2 git worktrees** under `~/Developer/HL7v2Kit-worktrees/` for parallel-branch development, all branched off `main` at `69060e4`:
  - `v0.2-parser-hardening` — P1 BOM → P2 NUL → P3 unsupportedVersion (serial; all touch `Parser.swift`) **— landed & merged 2026-06-14; worktree dropped**
  - `v0.2-composites` — C1 typed composite data types → V2 component-level validation
  - `v0.2-fringe-fields` — F1 PID/ORC fringe-field expansion → V1 conditional-field evaluation
  - `v0.2-perf-tests` — X1 performance budget tests
  - Documented merge order: parser-hardening → fringe-fields → composites → perf-tests.
- **`NEXT_STEPS.md` reorganised** around the v0.2 cycle: new "Workspaces and worktrees" section, each task names its worktree + position in the serial chain, full v0.1.0 task history preserved under "Historical: v0.1.0 runway".
- **`the working notes` "Project at a glance"** surfaces the workspace + worktree setup so future sessions discover them without re-derivation.

### Fixed (parser hardening)

- **v0.2-P1 — UTF-8 BOM prefix is now explicitly stripped** in `Parser.parse(_ data:)` before charset detection. Previously this depended on Foundation's `String(data:encoding:.utf8)` silently dropping the BOM, which Linux Swift does not do — so the byte path behaved differently across platforms. Now the 3-byte `EF BB BF` prefix is detected and dropped in HL7v2Kit code; behaviour is identical on macOS and Linux. The String overload (`parse(_ raw:)`) is unaffected because it operates on already-decoded text. The serializer never re-emits the BOM, so a round-trip canonicalises the output. A BOM-only input still throws `.emptyInput` (the empty-after-strip case is checked explicitly). DocC on `parse(_ data:)` documents the contract. Pin in `ParseErrorTests.swift` renamed `bomPrefixSilentlyAccepted` → `bomPrefixStrippedExplicitly` and asserts the round-trip canonicalisation; new `bomOnlyInputIsEmptyAfterStrip` pins the empty-after-strip edge. 159 → 160 tests.
- **v0.2-P2 — Embedded NUL bytes are now rejected at parse time** with `ParseError.truncatedMessage(atByte:)`. Real HL7 v2 wire never carries NUL; an embedded `0x00` is almost always transport truncation (a fixed-size buffer NUL-padded beyond the real message). Rejecting up-front keeps the round-trip byte-equality invariant (spec §5) honest — every accepted message is NUL-free, no carve-out required. The reported byte offset is into the **post-BOM-strip payload**, not the original wire (so a NUL at byte 100 of a BOM-prefixed input reports as 100, not 103). Pin in `ParseErrorTests.swift` renamed `midMessageNULLossy` → `midMessageNULRejected` (was "round-trip is lossy"; now asserts the throw). New `nulOffsetIsRelativeToStrippedPayload` pins the post-strip-offset design choice. 160 → 161 tests.
- **v0.2-P3 — `.unsupportedVersion` now fires on `Parser(options: .strict)`** when MSH-12 carries a non-empty value the `Version` enum doesn't recognise. Default + lenient preserve the existing silent v2.5.1 fallback (intentional — keeps the parser useful for older fixtures with non-canonical MSH-12). Empty MSH-12 always falls back regardless of the strict flag (that's a Validator concern; MSH-12 is required, not "must map to a known version"). Mechanism: new `ParserOptions.rejectUnknownVersion: Bool` flag (default `false`); `.strict` sets it `true`. `.strict` is now a superset of `.default`'s checks (rejects unknown segments + unknown versions). Pin in `ParseErrorTests.swift`: `unknownVersionFallsBack` → `unknownVersionFallsBackOnDefault` (still passes; default unchanged); new `unknownVersionThrowsOnStrict` and `emptyMSH12FallsBackEvenOnStrict` pin the strict throw and the empty-MSH-12-still-falls-back design choice. 161 → 163 tests.

### Added (schema coverage)

- **v0.2-F1 — PID and ORC are now spec-complete for v2.5.1.** PID extended from 30 → 39 fields: `identityUnknownIndicator` (ID), `identityReliabilityCode` (IS, repeating), `lastUpdateDateTime` (TS), `lastUpdateFacility` (HD), `speciesCode` / `breedCode` / `productionClassCode` (CE), `strain` (ST), `tribalCitizenship` (CWE, repeating). ORC extended from 19 → 31 fields: `advancedBeneficiaryNoticeCode` (CE), `orderingFacilityName` (XON, repeating), `orderingFacilityAddress` / `orderingProviderAddress` (XAD, repeating), `orderingFacilityPhoneNumber` (XTN, repeating), `orderStatusModifier` (CWE), `advancedBeneficiaryNoticeOverrideReason` (CWE), `fillersExpectedAvailabilityDateTime` (TS), `confidentialityCode` / `orderType` / `parentUniversalServiceIdentifier` (CWE), `entererAuthorizationMode` (CNE). Schema-only change: typed-segment files regenerate via `bash scripts/regenerate-typed-segments.sh`; codegen output is reproducible.
- 14 new cross-check tests in `TypedSegmentTests.swift`: 7 for PID-31..39 (scalar accessors + CE/HD/CWE composites + round-trip), 7 for ORC-20..31 (scalar TS + CE/CWE/XON/XAD/CNE composites + round-trip). Both fringe wires include the standard field-map comment per the multi-field-fixture convention. All 48 fixture round-trips still byte-perfect.
- Generated file sizes: `PID.swift` 145 → 210 lines, `ORC.swift` 90 → 170 lines — both under the soft 300-line cap, no per-field-group split required.

### Added (validator)

- **v0.2-V1 — Conditional-field evaluation in `Validator`.** `.conditional` (HL7 optionality `C`) fields can now carry a predicate that controls when they become required. New `FieldGrammar.condition: String?` carries the predicate; new `ValidationOptions.checkConditionalFields: Bool` (default `true`; `.lenient` preset sets `false`) gates evaluation; `Validator` emits the already-reserved `IssueCode.conditionalFieldMissing` when a predicate evaluates to true on an empty field.
- **DSL grammar** (kept deliberately small): `<segment-id>-<index> <predicate>` where `<predicate>` ∈ `"populated"`, `"empty"`, `"= <value>"`, `"!= <value>"`. Same-segment references only in v0.2; cross-segment references and malformed predicates fail safe (treated as no-trigger so a schema typo never makes a previously-accepted message non-conformant). `populated`/`empty` use the any-subcomponent-non-empty check; `=`/`!=` compare against the first-subcomponent-of-first-component-of-first-repetition "scalar view" of the field.
- **First real condition shipped:** `PID-36` (Breed Code) carries `"PID-35 populated"` — "if a species code is declared, a breed code is required" — the natural veterinary-HL7 interpretation. All 48 gold-corpus fixtures are unaffected because none populate PID-35 (all human patients); pinned by `ConditionalFieldTests.fixtureCorpusNoConditionalErrors`.
- **C fields without a condition** (e.g. `ORC-2`/`ORC-3`/`ORC-8`/`PID-35` itself) continue to behave as `.optional` — backward compatible. Conditions can be added to those JSON entries in future stages without code changes.
- **Codegen extended:** `FieldSchema.condition: String?` (optional Decodable) feeds the new `condition:` argument in the emitted `FieldGrammar(...)` table entries. `FieldGrammar.init`'s `condition: String? = nil` default keeps hand-rolled construction compatible.
- 6 new tests in `Tests/HL7v2KitTests/ConditionalFieldTests.swift`: condition triggers with field empty → error, condition triggers with field populated → no error, condition doesn't trigger → no error, `checkConditionalFields=false` suppresses, `.lenient` preset suppresses, full-corpus regression pin. 173 → 179 tests across 12 → 13 suites.

Tests: 159 (v0.1.0 tag) → 205 (default `swift test`); 210 with `RUN_PERF_TESTS=1`. Per-stage net: 4 from parser-hardening (P1+P2+P3) + 14 from F1 + 6 from V1 + 11 from C1 + 11 from V2 + 5 from X1 (skipped by default) = 51 net; 46 active by default. All 48 fixture round-trips still byte-perfect.

### Added — performance budget tests (v0.2-X1)

- **New `Tests/HL7v2KitTests/PerformanceTests.swift`** carrying 5 nightly latency assertions per spec § 9.5 (Apple Silicon M1+ budgets):
  - Parse 1 message (~600 bytes) under 1ms warm
  - Parse 1,000 messages under 5s
  - Round-trip 1,000 messages under 10s
  - Validate 1 message (default options) under 2ms warm
  - Validate 1,000 messages under 10s
- **Skipped by default.** The suite gates on `ProcessInfo.processInfo.environment["RUN_PERF_TESTS"] == nil` via the `@Suite(.disabled(if:))` trait, so the everyday `swift test` run stays fast. To run the perf suite: `RUN_PERF_TESTS=1 xcrun swift test`. Output marks the skipped tests with `... skipped: "Set RUN_PERF_TESTS=1 to run the perf suite"`.
- **Timing uses `Date()` differences** for portability with macOS 12+ (Foundation's `ContinuousClock` is macOS 13+). Precision is ~µs — plenty for ms/s budgets.
- Representative ~600-byte ADT^A01 wire (synthesised from the `adt_a01_minimal.hl7` gold-corpus fixture) carries the composite types most AU clinical traffic populates (CX/XPN/CE/XAD/XTN on PID; PL/XCN on PV1) so the budget covers a realistic critical path. Warm-up loops (100 iterations) precede the single-iteration measurements.
- Measured on the dev machine at landing time: parse-warm ≈ 41ms suite time; 1000-parse 0.176s; 1000-round-trip 0.233s; validate-warm 35ms suite time; 1000-validate 0.056s. All comfortably under budget; spec also reserves a 20% regression threshold above these numbers.
- 5 new tests in the disabled-by-default suite. Default `swift test` count: 205 → 210 (5 skipped, not 5 net additions).

### Added — component-level grammar in Validator (v0.2-V2)

- **`Validator` now enforces required sub-components on populated composite-typed fields.** Each typed composite (XPN / CX / XAD) carries a `static let requiredComponents: [RequiredComponent]` listing its mandatory sub-components per HL7 v2.5.1: XPN-1 Family Name, CX-1 ID Number, XAD-1 Street Address. When a composite is populated but a required component is empty, the validator emits `IssueCode.requiredComponentMissing` with a component-level location.
- **New `RequiredComponent` value type** (`Sources/HL7v2Kit/Composite/RequiredComponent.swift`) — `Sendable + Equatable + Hashable` shape `{ index: Int, name: String }`.
- **`IssueLocation` gains `componentIndex: Int?`** (defaulted to nil for backward compatibility). `pathDescription` now renders as `"PID[1]-5.1"` when the component index is set, alongside the existing `"PID[1]-3"` (field-level) and `"ZAU[1]"` (segment-level) shapes.
- **New `ValidationOptions.checkComponentGrammar: Bool`** toggle (default `true`; `.strict` keeps it on; `.lenient` disables it).
- **Composites without typed metadata** (CE / CWE / EI / XCN / HD / MSG / PT / VID / XTN / PL / CNE / XON / EIP) skip silently — they can be promoted incrementally by adding a `static let requiredComponents` and extending `Validator.requiredComponents(forCompositeCode:)`.
- **Backward-compatible additive change** — no migration burden on v0.1.x callers beyond the C1 breaking change. All 48 gold-corpus fixtures still produce a non-error report; the regression pin lives in `ComponentGrammarTests.fixtureCorpusNoComponentErrors`.
- 11 new tests in `Tests/HL7v2KitTests/ComponentGrammarTests.swift` cover: XPN/CX/XAD missing-component error paths (3); positive-path no-error case (1); empty-field-hits-required-field-not-component edge (1); CX multi-repetition independent checking (1); toggle suppression (1); `.lenient` preset suppression (1); `.strict` preset enforcement (1); untyped-composite skip (1); 48-fixture regression pin (1). 194 → 205 tests across 14 → 15 suites.

### Changed — API-BREAKING (typed composites, v0.2-C1)

- **Typed-segment accessors for XPN-, CX-, and XAD-typed fields now return Swift struct views** (`XPN?` / `CX?` / `XAD?`) instead of `Field?`. New structs live under `Sources/HL7v2Kit/Composite/` and expose named accessors for the most common components:
  - `XPN` — `familyName`, `givenName`, `middleName`, `suffix`, `prefix`, `nameTypeCode`
  - `CX` — `id`, `checkDigit`, `checkDigitScheme`, `assigningAuthorityNamespace`, `identifierTypeCode`, `assigningFacilityNamespace`
  - `XAD` — `streetAddress`, `otherDesignation`, `city`, `state`, `zip`, `country`, `addressType`
- **Affected accessors** (any field with `dataType ∈ {XPN, CX, XAD}`): `pid.patientName`, `pid.mothersMaidenName`, `pid.patientAlias` (XPN); `pid.patientIdentifierList`, `pid.alternatePatientID`, `pid.patientAccountNumber`, `pid.mothersIdentifier`, `pv1.visitNumber` (CX); `pid.patientAddress`, `nk1.address`, `orc.orderingFacilityAddress`, `orc.orderingProviderAddress` (XAD); `nk1.name` (XPN). Other composites (CE, CWE, EI, XCN, HD, MSG, PT, VID, XTN, PL, CNE, XON, EIP) still return `Field?` — they can be promoted incrementally without further breaking changes.
- **Migration path.** Each composite struct exposes a public `field: Field` for raw access — the v0.1.x `pid.patientName?.first?.components[0].stringValue` pattern still works as `pid.patientName?.field.first?.components[0].stringValue` (one extra hop). Or migrate to the named accessor: `pid.patientName?.familyName`. The cross-check invariant holds for both: `pid.patientName?.familyName == message["PID-5.1"]`.
- **Multi-repetition access.** Named accessors read from the FIRST repetition. For multi-rep fields (PID-3 patient identifier list, PID-5 name with maiden, ORC-22 facility address, …), walk `.field.repetitions` and wrap each in a new composite struct via the new `init(repetition:)` convenience.
- **Mechanism.** `Codegen.swift` recognises the composite data-type whitelist (`["XPN", "CX", "XAD"]`); when a field's `dataType` matches, the emitted accessor wraps the underlying `field(N)` call via `<Composite>.init(field:)`. Adding more composites to the whitelist is a one-line change; promoting another composite is purely additive.
- **Round-trip preserved.** Composite structs are value-type *views* over `Field`, not owners — the segment still holds the bytes. All 48 gold-corpus fixtures round-trip byte-identical; `CompositeTypeTests.compositeRoundTripsByteIdentical` pins this.
- 11 new tests in `Tests/HL7v2KitTests/CompositeTypeTests.swift` cover every named accessor on each composite + the `.field` migration path + multi-repetition access + cross-check against the path API + round-trip preservation. 13 existing tests across `TypedSegmentTests.swift`, `FixtureRoundTripTests.swift`, `ParseErrorTests.swift`, `ReadmeQuickstartTests.swift`, and `README.md` migrated to the new typed accessors. 183 → 194 tests across 13 → 14 suites.

### Changed (docs)

- **DocC catalogue brought up to date with the v0.2 work merged on `main`**:
  - `Migration.md` — "Anticipated changes in 0.2.0" rewritten into two sections: "Toward 0.2.0 — already on `main`" (P1/P2/P3 + F1 + V1, what consumers see if they pin to a commit instead of the `v0.1.0` tag) and "Still pending for 0.2.0" (C1 typed composites, V2 component grammar, X1 perf budget, runtime dictionaries).
  - `TypedSegments.md` — `PID` / `ORC` field counts updated from "30 of 39" / "19 of 31" to "all 39" / "all 31" with a note pointing at F1.
  - `Validation.md` — new "Conditional-field check" bullet under the active-checks list; new "Conditional-field DSL" section documenting the predicate grammar (`populated` / `empty` / `= <value>` / `!= <value>`), same-segment-only scope, and fail-safe semantics; presets updated to mention the new `checkConditionalFields` toggle (default `true`; `.lenient` disables); "What the validator does not check" trimmed (conditional fields removed; cross-segment predicates added as a known limit).
  - `AddingASegment.md` — schema-field list extended with the optional `condition` field (only meaningful for `optionality=C`); "Limits" updated — conditional `C` is no longer treated as `O`; typed-composite and component-level-grammar limits link to `Migration.md` for the v0.2 status.
  - `RoundTripGuarantee.md` — "Inputs the parser rejected" bullet expanded to call out NUL byte rejection (`ParseError.truncatedMessage(atByte:)`) and BOM strip (round-trip is canonicalisation, not byte-equality, for BOM-prefixed input). Both link back to `Migration.md`.
  - `GettingStarted.md` / `CharacterEncoding.md` / `EscapeSequences.md` / landing page — spot-checked, no edits needed.
- No source / test / API changes; tests still 183/183 in 13 suites.

## [0.1.0] — 2026-06-13

### Added

- **Code-generated typed segment structs** for HL7 v2.5.1: `MSH`, `PID` (first 12 of 40 fields), `NTE`, `AL1`.
  - `HL7v2KitCodegen` executable target reads per-segment JSON schemas from `Resources/schemas/<version>/` and emits Swift `TypedSegment` structs under `Sources/HL7v2Kit/Segment/Generated/`.
  - `SegmentRegistry.hydrate(_:)` switches segment IDs to typed factories; `Parser` calls it after structural parsing.
  - `scripts/regenerate-typed-segments.sh` regenerates the output tree.
  - Codegen output is reproducible (byte-identical across runs); CI codegen-drift job in `.github/workflows/ci.yml` catches schema edits that forget to regenerate.
- **MSH-18 character-set detection.** `Parser.parse(_ data:)` probes MSH-18 via an ISO-8859-1 1:1 decode, looks up the declared charset, and re-decodes the bytes. `Parser.parse(_ raw:)` does the same probe on the already-decoded string. Supports `UNICODE UTF-8` (default), `ASCII`, `8859/1` and the common aliases for each.
- **HL7 escape-sequence codec.** `\F\` `\S\` `\T\` `\R\` `\E\` `\X..\` decode/encode at the subcomponent leaf. `\Z..\` and unknown sequences pass through verbatim. `Subcomponent.value` stores decoded text; the serializer canonicalises on output. Hex runs coalesce (`\X0D0A\` not `\X0D\\X0A\`).
- `CharacterEncoding` public enum (Foundation edge) mapping MSH-18 wire strings to `String.Encoding`.
- `Message.characterEncoding: CharacterEncoding` property — populated by the parser, used by the serializer to emit bytes in the originating charset.
- `MessageBuilder` accepts an optional `characterEncoding` parameter (defaults to `.utf8`).
- 41 new tests: 17 `EscapeSequenceTests`, 11 `CharacterEncodingTests`, 13 `TypedSegmentTests` (path vs typed-accessor cross-check on MSH/PID/NTE/AL1, hydration check, byte-perfect round-trip through typed segments, Z-segment regression).

### Changed

- **Removed the explicit `swift-testing` SwiftPM dependency.** Swift Testing ships with the Swift 6 toolchain; the explicit dep was triggering a `@Suite` deprecation warning. The package now has zero external dependencies.
- `Parser` version-detection (MSH-12) reads via the unified `Segment.fields` accessor rather than pattern-matching `case .unknown(let msh)` — required once MSH starts hydrating as `.typed`. Encoding-agnostic and survives future typed-segment additions.
- `Parser` previously always emitted `.unknown(UnknownSegment)`; it now consults `SegmentRegistry.hydrate(_:)` to wrap recognised segment IDs as `.typed`. Z-segment tolerance is preserved (unknown IDs still fall through to `.unknown`).
- **MSH-18 probe-and-lookup logic factored into `CharacterEncoding.detect(in:)`** *(R3)*. `Parser.parse(_ data:)` and `Parser.parse(_ raw:)` now share the same one-line invocation; the private `probeMSH18` helper has moved off `Parser` since it's pure structural lookup.
- **`MessageBuilder.appendSegment(id:fields:)` contract clarified** *(R1)*: `fields` is treated as 1-indexed; the builder always prepends the index-0 placeholder. The dead-code condition (`fs.count == fields.count` was a tautology) has been removed. Behaviour is unchanged; the DocC now states the contract explicitly.
- **`Parser.parse(_ raw:)` DocC updated** *(R2)* to call out that MSH-18 is still consulted on the String-input path, with the same strict-on-unrecognised policy as `parse(_ data:)`.

### Added (R6 — ParserOptions audit)

- **`ParseError.unknownSegment(id: String, position: Int)`** — new error case. Spec § 4.6 had it declared but the implementation lacked the case. Position is 1-based (MSH is position 1).
- **`Parser(options: .strict).parse(...)`** now actually rejects unrecognised segments with `.unknownSegment`. Previously the `.strict` `allowUnknownSegments: false` option was silently equivalent to `.default` because the parser never consulted the flag. Now it checks after `SegmentRegistry.hydrate(_:)` returns and throws if the result is `.unknown`.
- **`ParserOptions.preserveExcessFields`** DocC updated to honestly mark it deferred to v0.2: v0.1.x has no per-segment field-count dictionary to check against, so excess fields are always preserved regardless of the flag. The flag stays on the API so consumers don't break when the dictionary-driven behaviour lands.
- 3 new tests in `ParsingTests.swift`: strict mode rejects ZAU with `.unknownSegment(id: "ZAU", position: 2)`; default options still allow ZAU (Z-segment tolerance regression); strict mode still accepts a registered PID.

### Added (Task 7c — parser error-path coverage)

- New `Tests/HL7v2KitTests/ParseErrorTests.swift` with **23 negative-path tests** covering: every `ParseError` case (including the previously-dead `.unsupportedVersion`, `.malformedField`, `.truncatedMessage` via the `everyCaseDescriptionRenders` reflection test), MSH structural edges (too-short MSH, missing field-separator after MSH-2, non-distinct encoding chars, segment-ID-only segments), byte-level edges (BOM prefix, embedded NUL, custom encoding characters), DoS-adjacent stress (8 KB single field, 1000-way repetition fan-out), mixed line terminators under `.lenient`, multiple MSH segments (batch-shaped input), and behaviour pins for current parser leniency (unknown MSH-12 falls back to v2.5.1, whitespace-only input throws `.missingMSH` not `.emptyInput`).
- Two findings flagged in test comments as v0.2 hardening candidates: (1) BOM prefix is silently stripped by Foundation on macOS (portability gap on Linux/Windows); (2) embedded NUL bytes are NOT preserved through round-trip — current behaviour is lossy. Both pinned by the test suite so they'll be caught if either silently changes.
- Coverage moves: `ParseError.swift` from **84.62% → 100.00% line** (every enum case description exercised); `Parser.swift` from **93.72% → 97.10% line / 84.72% → 91.67% region**. Overall `Sources/HL7v2Kit/` from **93.06% → 94.36% line / 86.60% → 88.60% region**.
- 136 → 159 tests across 12 suites.

### Added (Task 7a — anonymise tool + starter fixture corpus)

- **`HL7v2KitAnonymise` executable target** (`Sources/HL7v2KitAnonymise/Anonymise.swift`) implementing the spec § 10 scrubbing rules: PID-3 identifier replacement (format-preserved for digit-only IDs, otherwise `SYN-NNNN` prefix), XPN name lists, DOB shift by `±(salt mod 60 / 2)` days, AU synthetic addresses (8 real suburbs × 5 fake street names), AU-shaped phone numbers (`61-2-XXXX-XXXX`), MSH-3/4/5/6 facility names (8-entry pool), XCN provider lists (PV1 attending/referring/consulting/admitting + OBR collector/ordering/principal interpreter), OBX-5 narrative redaction (`TX` / `FT` / `ST` / `ED` value types → `[REDACTED]`), NTE-3 redaction. **Deterministic** — per-file salt derived from MSH-10 via djb2 hash; same input → byte-identical output. **One-shot** — re-anonymising an already-scrubbed file shifts the DOB again (documented in `Tests/Fixtures/FIXTURES.md`).
- **`scripts/anonymise-fixture.sh`** wrapper invoking the executable via `xcrun swift run`, matching the existing `regenerate-typed-segments.sh` pattern.
- **8 starter fixtures** under `Tests/Fixtures/`: `adt_a01_minimal.hl7`, `adt_a01_with_nk1.hl7`, `orm_o01_lab_order.hl7`, `oru_r01_chemistry.hl7`, `oru_r01_with_z_segment.hl7`, `edge_empty_fields.hl7`, `malformed_missing_msh.hl7`, `malformed_invalid_encoding_chars.hl7`. All hand-written synthetic with `\r` line terminators (real v2 wire format). Documented in `Tests/Fixtures/FIXTURES.md`.
- **`Tests/HL7v2KitTests/FixtureRoundTripTests.swift`** — auto-discovers `*.hl7` files in the bundled Fixtures resource and applies four invariants:
  - Every non-malformed fixture round-trips byte-perfectly (spec § 9.3).
  - Every non-malformed fixture validates without errors.
  - Every `malformed_` fixture throws a `ParseError`.
  - Path access and typed accessor cross-check on PID-1 / PID-3 / PID-5 / PID-7 / PID-8 (spec § 9.4).
- Adding fixture #9..#48 is now a pure drop-in operation — no test code change required.

### Added (Task 8c — release polish prep)

- New `Tests/HL7v2KitTests/ReadmeQuickstartTests.swift` — a `@Test` that mirrors the README's Quickstart code block and asserts each documented expected value. Drift in the README example (renamed methods, changed return types, stale `//` comments) breaks the test at PR time before any user encounters a stale example.
- README updated for accuracy: "Typed segments currently shipped" lists all 9 v2.5.1 segments with field-coverage counts (was stale at 4 segments / "PID 12 of 40"); "Adding a typed segment" workflow corrected from 4 steps to 3 (no manual `SegmentRegistry.swift` edit — the registry is itself codegen-emitted post-R5).
- Line-coverage benchmark on `Sources/HL7v2Kit/` (excluding `Generated/`, `HL7v2KitCodegen/`, `HL7v2KitDictionaries/`, and tests):
  - **Region:** 86.60% (433 of 500 covered)
  - **Function:** 92.81% (142 of 153 covered)
  - **Line:** 93.06% (1072 of 1152 covered)
  - Exceeds spec § 15's 80% line-coverage gate. Lowest-covered files: `Validation/SegmentGrammar.swift` 54.55% (value-type initialisers exercised at codegen-table compile time rather than via direct test), `Message.swift` 75.00% (some typed-segment iteration paths), `ParseError.swift` 84.62% (some error cases like `.truncatedMessage`, `.malformedField` not exercised by tests because no malformed-byte fixture triggers them yet — Task 7).

### Added (Task 8b — DocC catalogue)

- New `Sources/HL7v2Kit/HL7v2Kit.docc/` catalogue with the landing page and 8 articles per spec § 11.2:
  - `HL7v2Kit.md` — module landing page with Topics index linking to articles and public type catalogue.
  - `GettingStarted.md` — install → parse → read → serialise → validate in one short page.
  - `RoundTripGuarantee.md` — what byte equality covers and what it doesn't.
  - `TypedSegments.md` — typed-segment access pattern; `String?` vs `Field?` rule; multi-occurrence iteration; cross-check guarantee.
  - `Validation.md` — `Validator.validate` returns a `ValidationReport`; the three presets; filtering by severity / code / segment; current check coverage and v0.2 gaps.
  - `EscapeSequences.md` — the `\F\` / `\S\` / `\T\` / `\R\` / `\E\` / `\X..\` / `\Z..\` grammar; hex coalescing; round-trip canonical-form property.
  - `CharacterEncoding.md` — MSH-18 detection via ISO-8859-1 probe; supported charsets; Latin-1 round-trip example.
  - `AddingASegment.md` — three-step contributor workflow (schema, regen, cross-check test); CI drift safety net; v0.1.0 limits.
  - `Migration.md` — pre-1.0 SemVer policy; anticipated v0.2 changes (typed composite data types, conditional-field evaluation, component-level grammar, possible runtime-loadable dictionaries).

### Added (Task 8a — ADR catalogue)

- `docs/design/ADR-001-ast-model.md` — explicit Field/Repetition/Component/Subcomponent hierarchy + round-trip rationale.
- `docs/design/ADR-002-error-strategy.md` — `ParseError` (fatal, throws) vs `ValidationReport` (non-fatal, returned) split.
- `docs/design/ADR-003-z-segment-policy.md` — three-layer Z-segment control (parser default `UnknownSegment`, strict opt-in, validator policy `.ignore`/`.warnPresence`/`.reject`).
- `docs/design/ADR-004-codegen-over-macros.md` — rationale for explicit codegen executable + committed output over Swift Macros or build-time preprocessing.
- `docs/design/ADR-005-dictionaries-strategy.md` — original "Dictionaries as separate target" intent + the v0.1.0 revision to Path C (codegen-emitted Swift literal grammar table), with the spec § 8 direction held open for v0.2+.

### Added (Task 5 — Validator)

- **`Validator` per spec § 4.8.** Public surface: `Validator(options:)` + `validate(_ message:) -> ValidationReport`. **Non-fatal** (returns a report, never throws — ADR-002 invariant). Built on Path C — the validator reads a codegen-emitted `SegmentGrammarTable.v2_5_1` static table; no runtime JSON parsing, no separate `HL7v2KitDictionaries` runtime resource needed for v0.1.0.
- **`ValidationOptions`** with three presets: `.default` (grammar checks on, Z-segments silently tolerated), `.strict` (Z-segments rejected as errors), `.lenient` (only structural required-field check). Knobs: `zSegmentPolicy` (`.ignore` / `.warnPresence` / `.reject`), `checkRequiredFields`, `checkCardinality`, `warnDeprecatedFields`.
- **`ValidationReport`** (`issues`, `isValid` — false iff any `.error`-severity issue — plus `errors` / `warnings` / `infos` filters) and **`ValidationIssue`** (`severity`, `code`, `location`, `message`).
- **`IssueSeverity`** (`.info` / `.warning` / `.error`), **`IssueLocation`** (segment ID + 1-based segment occurrence + optional 1-based field index; renders as `"PID[1]-3"`), and **`IssueCode`** (`.requiredFieldMissing`, `.conditionalFieldMissing` (reserved), `.fieldNotSupported`, `.cardinalityExceeded`, `.zSegmentPresent`, `.unknownSegment`).
- **Public grammar types**: `SegmentGrammar`, `FieldGrammar`, `FieldOptionality` (R/O/C/X/B from HL7 wire codes), `FieldRepeatability` (.single/.multiple). `SegmentGrammarTable` is the codegen-emitted lookup `[String: SegmentGrammar]` keyed by segment ID.
- **Codegen extension**: `HL7v2KitCodegen` now also emits `Sources/HL7v2Kit/Segment/Generated/SegmentGrammar+v2_5_1.swift` containing the static `SegmentGrammarTable.v2_5_1` table. Per-version files allow future v2.3.1 / v2.4 / v2.8 tables to slot in without touching v2.5.1's output. Sorted by segment ID and field index for deterministic output.
- **Three operational checks**:
  - **Required-field check**: fields with optionality `R` that are unpopulated emit `.requiredFieldMissing` errors.
  - **Cardinality check**: single-cardinality fields (`repeatability=1`) carrying multiple `~`-separated repetitions emit `.cardinalityExceeded` errors.
  - **Deprecated-field warning**: populated `B` (deprecated) or `X` (not supported) fields emit `.fieldNotSupported` warnings (non-blocking).
- **Z-segment policy**: `.ignore` (no issue), `.warnPresence` (`.info` per segment, still valid), `.reject` (`.error` per segment, report invalid).
- 12 new tests in new `Tests/HL7v2KitTests/ValidationTests.swift`: well-formed-is-valid, missing-required-PID-3, checkRequiredFields toggle, all three Z-segment policies, cardinality on PID-7 single-field with two reps, multi-cardinality on PID-3 doesn't trigger, deprecated PID-2 warning, warnDeprecatedFields toggle, non-throw contract, IssueLocation path-description rendering. Suite total to 131.
- **Codegen accessor template uses `field(N)`** *(R4)* instead of the inline `fields.indices.contains(N) ? fields[N] : nil`. `TypedSegment` gains a `field(_ index: Int) -> Field?` default-impl that mirrors `Segment.field(_:)`'s bounds policy — single source of truth for "what does an out-of-range typed accessor return". Generated files visually halve in size.
- **`SegmentRegistry+Generated.swift` is now codegen-emitted** *(R5)*. The hand-written `SegmentRegistry.swift` shrank from a 4-case switch (and growing per Task 4c segment) to a 13-line entry point that calls `hydrateGenerated`. Adding a new segment is now a 2-step workflow: drop the JSON schema, run `regenerate-typed-segments.sh`. The codegen-drift CI job catches missed regenerations. ORC v2.5.1 lands as the canary segment proving end-to-end auto-registration.

### Added (R-β)

- `ORC` typed segment for HL7 v2.5.1 (one field — Order Control). Added as the R5 canary; extended to 19 fields in Task 4c-1.
- `TypedSegment.field(_:)` default-impl extension.

### Added (Task 4c-1)

- `OBX` typed segment for HL7 v2.5.1 (full 17 fields covering Set ID, Value Type, Observation Identifier, Observation Value, Units, References Range, Abnormal Flags, Probability, Nature of Abnormal Test, Observation Result Status, Effective Date of Reference Range, User Defined Access Checks, Date/Time of the Observation, Producer's ID, Responsible Observer, Observation Method).
- `ORC` typed segment extended from 1 to 19 fields (Order Control through Action By — covers the commonly-used Common Order fields including Placer/Filler Order Numbers, Order Status, Date/Time of Transaction, Ordering Provider).
- 14 new cross-check tests in `TypedSegmentTests.swift` (5 for extended ORC + 9 for OBX including round-trip), bringing the suite total to 84.

### Added (Task 4c-2)

- `OBR` typed segment for HL7 v2.5.1 (full 47 fields — the largest segment in the v0.1.0 set). Covers placer/filler order numbers (EI), universal service identifier (CE), specimen/observation timestamps, collector and ordering provider XCN composites, specimen action code, placer/filler text fields, result status, parent ordering, transport metadata, procedure codes, supplemental service information.
- 13 new cross-check tests in `TypedSegmentTests.swift`: 12 OBR-specific (hydration, SI/EI/CE/XCN/TS/ID coverage by field cluster, byte-perfect round-trip) plus 1 full-message integration test parsing an ORU^R01 result message with MSH + PID + OBR + OBX and asserting byte-perfect round-trip. Suite total to 97.

### Added (Task 4c-3)

- `PID` typed segment extended from 12 → 30 fields. New coverage: phone numbers (home/business XTN), primary language (CE), marital status (CE), religion (CE), patient account number (CX), SSN + driver's license (deprecated), mother's identifier (CX), ethnic group (CE), birth place (ST), multiple birth indicator (ID), birth order (NM), citizenship (CE), veterans military status (CE), nationality (CE, deprecated), patient death date/indicator (TS + ID).
- `NK1` typed segment for HL7 v2.5.1 (13 commonly-used fields). Covers Set ID, name (XPN), relationship (CE), address (XAD), home + business phone (XTN), contact role (CE), start/end dates (DT), job title (ST), job code/class (JCC), employee number (CX), organization name (XON).
- `PV1` typed segment for HL7 v2.5.1 (20 commonly-used fields). Covers Set ID, patient class (IS), assigned + temporary + prior patient locations (PL), admission type (IS), preadmit number (CX), attending/referring/consulting/admitting doctors (XCN), hospital service (IS), preadmit/readmit/admit indicators (IS), ambulatory status (IS), VIP indicator (IS), patient type (IS), visit number (CX), financial class (FC).
- 19 new cross-check tests in `TypedSegmentTests.swift`: 6 extended-PID (XTN home phone, CE language/marital/religion triplet, CX account, ST birth place, TS+ID death fields, byte-perfect round-trip), 5 NK1 (hydration, scalars, name+relationship composites, phone composites, round-trip), 7 PV1 (hydration, class+admit type scalars, PL location composite, XCN attending doctor, IS admin scalars, CX visit number, round-trip), and 1 ADT^A01 integration (MSH + PID + PV1 + NK1 in one message with byte-perfect round-trip). Suite total to 116.

### Added (initial scaffold — pre-Task-2)

- Initial scaffold: `Package.swift`, module structure, base types.
- `Version` enum for HL7 v2.3.1, 2.4, 2.5.1, 2.8.
- `EncodingCharacters` struct (default `|^~\&`).
- `Field` / `Repetition` / `Component` / `Subcomponent` AST nodes.
- `Segment` enum with `.typed` / `.unknown` cases and `UnknownSegment` fallback.
- `Message` top-level type with byte-level `serialize()`.
- `Path` parser supporting `SEG[N]-F[.C[.S]][~R]` syntax.
- `Parser` skeleton with single-message parsing and structural Z-segment tolerance.
- `MessageBuilder` for round-trip construction.
- Round-trip property test scaffolding.

### Added (Task 7b — fixture corpus scale-out)

- **Fixture corpus expanded 8 → 48** (spec § 9.2 target met for v0.1.0). All synthetic from scratch.
  - **ADT (12 total):** 3 × A01 (minimal, with NK1, allergies, insurance, emergency) + 3 × A04 (clinic, NK1, paediatric with PD1) + 3 × A08 (address update, demographics update, allergies-add).
  - **ORM (5 total):** lab order baseline + radiology X-ray, microbiology, haematology, cancel (ORC-1=CA), order with DG1 diagnosis.
  - **ORU pathology (6 total):** chemistry, haematology FBC, lipid panel, TFT, microbiology MCS, multi-OBR (EUC + LFT batteries under one PID).
  - **ORU radiology (4 total):** chest X-ray, CT abdomen/pelvis, pelvic ultrasound, MRI brain — each with TX narrative + ST impression.
  - **ACK (2 total):** application-accept (AA) and application-error (AE + ERR).
  - **Z-segment heavy (5 total):** original `oru_r01_with_z_segment` + ZAU/ZIN overlay in ADT, ZBL billing in ORM, ZLB/ZRE in ORU, ZTX heartbeat (MSH + Z only).
  - **Malformed (6 total):** missing MSH + non-distinct encoding chars + MSH too short + MSH no field-sep after MSH-2 + unsupported MSH-18 charset + empty file. Each triggers a distinct `ParseError` case.
  - **Edge (8 total):** original `edge_empty_fields` + Unicode diacritics, repeating PID-3 identifiers, very-long address, escape sequences in PID-5 and NTE, many trailing NTEs, sparsely-populated PID, OBX with `~`-repeating values.
- All valid fixtures: round-trip byte-perfectly, produce non-error `ValidationReport`, and pass the PID typed-accessor vs path-string cross-check. All malformed fixtures throw `ParseError`. `FixtureRoundTripTests` auto-discovers — no test code change required.

### Deferred to v0.2 (or later)

- **Full PID 30 → 39 and ORC 19 → 31.** Fringe coverage: PID-31..39 are species / breed / strain / tribal-citizenship; ORC-20..31 are confidentiality / charge metadata. v0.1.0 covers the commonly-populated fields per the 2026-06-13 decisions-log entry.
- **Typed composite data types** (`XPN` / `CX` / `XAD` as Swift structs with named accessors). v0.1.0 returns `Field?` for composites; callers reach into `.components[i].stringValue`. Spec § 4.5 last paragraph.
- **Conditional-field evaluation.** v0.1.0 treats `optionality=C` as equivalent to `O` for the required-field check. Per `ValidationIssue.IssueCode.conditionalFieldMissing` (reserved).
- **Component-level grammar in `Validator`.** v0.1.0 only checks field-level rules; e.g. XPN's family-name component being non-empty when XPN-1 is populated is not checked.
- **Performance budget tests** (spec § 9.5). Nightly latency assertions not in the v0.1.0 acceptance gate.
- **Three parser-hardening candidates** from Task 7c (all pinned by `ParseErrorTests.swift`, none blocks v0.1.0):
  - BOM prefix portability — silently stripped by Foundation on macOS but Linux Swift may differ.
  - Embedded NUL bytes — currently lossy through round-trip; consider `.truncatedMessage(atByte:)` at parse time.
  - `ParseError.unsupportedVersion` is reachable code but never thrown — unknown MSH-12 silently falls back to v2.5.1. Wire on `.strict` mode.
- **`HL7v2KitDictionaries` runtime JSON.** Path C (ADR-005 revised) supersedes the original spec § 8 plan for v0.1.0; placeholder.json stays. Revisit in v0.2 if dynamic version selection becomes a real consumer need.

[Unreleased]: https://github.com/<your-org>/HL7v2Kit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/<your-org>/HL7v2Kit/releases/tag/v0.1.0
