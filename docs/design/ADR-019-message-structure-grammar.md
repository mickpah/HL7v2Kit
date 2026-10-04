# ADR-019 — Message structures (abstract message syntax)

**Status:** Accepted 2026-10-02 under owner gate G2 (answered 2026-09-30: all recommended
defaults; Option C hybrid; one-pass matcher with determinism lint; HL7 v2.xml names for
unnamed groups; an info issue for unmodelled versions; structure-derived group ranges on
fully modelled versions; ACK builder plus validation, no protocol logic;
`messageStructureSeverity` off by default; and the ORC-8 `OBR absent` gate, which already
shipped in P4-7). Implementation tasks P8-3 onward build from this text.

**Supersedes nothing. Builds on:** ADR-008 (cross-segment DSL and ORC/OBR group semantics),
ADR-010 (segment presence atoms, group-scope cardinality), ADR-014 (API evolution), ADR-015
(extraction pipeline), ADR-016 (code tables), ADR-017 (datatype grammar), ADR-018 (supported
version set).

**Source:** the P8-2 plan decisions D1 to D6, amended for four things that changed after
they were written: the AU HL7au:00060.1 routing, the ORC-8 OUL misfire (now gated, see
below), ADR-018's version resolution, and the package being on the 3.x line.

---

## Context

HL7 v2 defines every message by an abstract message syntax: an ordered list of segments,
`[ ]` for optional, `{ }` for repeating, and segment groups that are themselves optional or
repeating (v2.5.1 CH02 §2.5.2; v2.4 CH02 §2.12 to 2.12.1; v2.3.1 CH2 §2.11 to 2.11.1). Each
chapter prints one syntax per structure under a caption such as `ADT^A04^ADT_A01`. From
v2.3.1 on, MSH-9.3 names the structure, and Table 0354 summarises structure to event.

HL7v2Kit checks segments, fields and components. Nothing checks segment order, groups, the
segments a trigger event requires, or that MSH-9.3 agrees with MSH-9.1/9.2. Every review
sprint raised this independently (X-C04: V23-C07, V231-C02, V24-C01, V251-C02, V26-C10,
V282-C08), and P8-1 registers it as blocking in `permanent-limitations-register.md` §E.

### What the code does today instead of groups

Group-scoped rules approximate groups by walking the flat segment list:

- `Message.orcGroupRange(around:)` (`Message.swift:166`): back-walk to the nearest ORC,
  forward-walk to the next ORC; with no preceding ORC, the whole prefix is the group. It
  backs `associatedSegment(_:fromIndex:)`, `segmentExists(_:inGroupOf:)` (the ADR-010
  `<SEG> present` / `<SEG> absent` atoms), the ORC/OBR pair-equality check
  (`Validator.swift:1112`), and `GroupScope.orcObxGroup`.
- `Validator.resolveGroup(scope:anchorIndex:message:)` (`Validator.swift:354`) adds
  `.obrObxGroup` (back-walk to OBR, forward to the next OBR or ORC) and `.messageWide`.
  `GroupScope` is internal (`SegmentGrammar.swift:290`); only the resolved issue is public.

These walks assume the ORC or OBR heads its group. That fails where a structure puts
another segment first or places OBR before ORC.

### Items routed to this ADR since the plan was written

1. **ORC-8 misfire on OUL R22 to R24 (P1 final review, Minor 9).** The ORC-8 condition on
   v2.3 to v2.6 is `ORC-1 = CH AND OBR absent OR ORC-1 = CH AND OBR-29 empty`. v2.5.1 CH07
   §7.3.9 and v2.6 CH07 §7.3.10 print OUL_R22 to R24 (and OPU_R25) with `OBR` then `[ORC]`
   inside one ORDER group. `orcGroupRange` starts at the ORC, so the group's OBR falls
   outside it, `OBR absent` is true, and a child order (`ORC-1 = CH`) with ORC-8 empty is
   reported as missing a conditional field it does not need. This is a known-incorrect
   predicate (requirement 4). In those structures OBR is the required head of ORDER, so
   "OBR absent in the ORC's group" cannot occur in a conforming message; the leg is vacuous
   there, not merely unhelpful.
2. **HL7au:00060.1, segment-level half (P3 fix wave).** ADRM-2021 00060.1: "HL7 message
   elements with a usage of R (required) must be valued" (Senders; Orders, Results,
   Referrals). The field and component half is the Validator core. The segment half
   (required segments present) is unenforced on every version. ADRM-2021 also prints its own
   constrained structures over v2.4: ORU^R01 (p17, reprinted p205), an order structure
   ("Order Message Structure", p279) and REF^I12 (captioned "REF^I12^REF_I2", p324). In the
   ORU^R01 one, PV1 is required inside the optional patient group and several base
   optional segments are removed. (The document's other "Message Structure" captions are
   a reprint of the international ORU structure and a section heading.)
3. **Version resolution (ADR-018, accepted).** MSH-12 is read as VID.1. Modelled versions
   (2.3, 2.3.1, 2.4, 2.5.1, 2.6, 2.8.2) use their own grammar; `2.8` is substituted by
   v2.8.2 with an info issue; anything else falls back to v2.5.1 with
   `versionNotRecognised` (warning). `Version.grammarVersion` and `Version.reading(msh12:)`
   carry this. Structure lookup has to say which version's structures apply in each row.
4. **House style (ADR-014 and its addenda).** The package is on the 3.x line (latest tag
   v3.13.0), so ADR-014's additive-only rule applies: public API is additive only, open
   enums (`IssueCode`) may gain cases, no new parameters on existing public initialisers,
   and new options are stored properties set by mutation (the M21, M27, M29, M30 pattern).

### Facts about the specification that shape the design

1. **Determinism rule.** v2.5.1 CH02 §2.5.2: if a segment appears in two locations and
   either is optional or repeating, the occurrences "must be separated by at least one
   required segment of a different name so that no ambiguity can exist". "As of v 2.5, the
   first segment in a newly defined segment group will be required." Conforming
   structures can be matched in one left-to-right pass with one segment of lookahead.
   Structures defined before v2.5 are not bound by the second sentence.
2. **Receivers ignore surplus.** v2.5.1 CH02 §2.6.2 a): a recipient ignores segments
   "present but not expected". Structural conformance is a property of the sender's
   message; a receiver may want it as a warning.
3. **Z-segments** are reserved for local definition (§2.5.2). Where they sit is a profile
   matter, governed today by `ZSegmentPolicy`.
4. **Group names are printed only sometimes.** v2.5.1 ORU_R01 names PATIENT_RESULT and
   PATIENT and leaves five groups as bare brackets.
5. **Table 0354 lags the chapters.** On v2.5.1, 24 structures that the chapters' own
   caption and example lines use are absent from it (`Resources/tables/v2.5.1/0354.json`
   citation). It is not enforced today and cannot be the source of truth.
6. **Spec examples are not an oracle.** v2.8.2 CH02 examples use `ADT^A04^ADT_A04`, which
   is not a v2.8.2 structure; half the v2.5.1 examples omit MSH-9.3 (M21).

### Extractability of the print (measured for this draft)

`pdftotext -layout` on the files under `docs/standards/`:

- **v2.5.1 CH02 §2.5.2** (p2-6 to 2-7) is prose: the notation, the determinism rule and the
  v2.5 first-segment rule. Its "proper" and "unparsable" grouping examples are laid out as
  three and four side-by-side columns and do not survive as single-column text (one also
  prints `{ SEG 1}` with a stray space). They carry no caption line, so a caption-driven
  extractor skips them without special handling. Nothing in §2.5.2 needs extracting; it is
  cited, not parsed.
- **v2.5.1 CH03 ADT_A01** (§3.3.1, p3-4 to 3-5): extracts cleanly. Caption
  `ADT^A01^ADT_A01   ADT Message   Status   Chapter`; one segment or bracket per row in a left
  column, description in a middle column, chapter number on the right; a blank line between
  rows. Brackets are padded irregularly (`[     PD1   ]`, `[{ ROL }]`). Named groups print as
  `[{   --- PROCEDURE begin` and `}]   --- PROCEDURE end`. The page break inserts the footer
  and header and **repeats the caption line**, which the extractor must de-duplicate. The
  Status column is empty on every row. `ACK^A01^ACK` follows immediately as a separate
  caption.
- **v2.5.1 CH07 ORU_R01** (§7.3.1, pp 7-13 to 7-14): extractable, with four traps. (a) The
  caption title wraps ("Unsolicited Observation" / "Message") onto a line whose left column
  is empty. (b) Descriptions wrap onto continuation lines with an empty left column
  ("Parties", "Info", "Sequence"). (c) One continuation line ("Specimen", for
  "Observation related to Specimen") lands **after** the page footer and the repeated
  caption. (d) Unnamed groups print as bare `[`, `{`, `[{`, `]`, `}`, `}]` lines, and
  indentation is inconsistent, so nesting must come from bracket balance, not indentation.
  Mixed spellings `[PD1]`, `[{NTE}]` and `{[NTE]}` all occur. The SPM row has no chapter
  number. All four traps are handled by one rule: a row is syntax only when its left
  column (measured from the caption line's column positions) is non-empty; everything else
  is description and is ignored.
- **v2.8.2 CH03 ADT_A01**: caption on its own line (`ADT^A01^ADT_A01: ADT Message`),
  followed by a column header `Segments  Description  Status  Chapter`. After a page break
  only the column header repeats, not the caption. Brackets are normalised (`[ PD1 ]`).
  No `< | >` choice notation found in v2.6 CH07, v2.8.2 CH03 or CH07.
- **AU ADRM-2021**: a different print. Segment code and description share one line with
  no columns; the legend defines only `{}` and `[]`; it prints `{ [OBX] }` (a repeating
  group whose only member is optional, equivalent to `[{OBX}]`) and has at least one
  caption erratum (`REF_I2` for `REF_I12`). Three distinct constrained structures (the
  order and REF prints were located by caption only and not read in full for this draft).

Conclusion: v2.4 to v2.8.2 are regular enough for an ADR-015-style extractor with an
errata file. v2.3.1 needs Table 0354 for structure IDs; v2.3 needs events from section
titles and has no structure IDs. The AU structures are few and printed differently; an
extractor for three structures costs more than it saves.

Caption counts measured at planning time (P8-9): v2.3.1 213 captions (10 with a structure
ID); v2.4 346 captions, 138 structure IDs; v2.5.1 392 and 169; v2.6 426 and 192; v2.8.2 188
structure IDs.

---

## Options (source of truth)

### Option A — Hand-authored JSON per structure

Every `Resources/structures/<ver>/<STRUCT>.json` written by hand from the print.

- Pro: no extractor to build; the pilot can start at once.
- Con: roughly 150 to 250 structures per version across seven versions (the six modelled today plus v2.7.1; over a thousand
  files) that no audit can hold to the print. This is the failure mode ADR-015 was written
  to end, and it fails requirement 2 at scale.

### Option B — Extracted from the spec PDFs (ADR-015 extension), extractor only

A new `scripts/extract-message-structures.py` (reusing the chapter map in
`scripts/extract-example-messages.py`) writes every structure file. No hand-authored
structure file ever exists; the pilot waits for the extractor.

- Pro: one author, auditable against the print, the same shape as ADR-015/016/017.
- Con: the pilot, the matcher and the Validator wiring all wait for the hardest part. The
  AU structures would need a second parser for three files.

### Option C — Hybrid (accepted)

1. **Pilot hand-authored, then reproduced.** v2.5.1 ADT_A01, ORU_R01 and ACK are
   hand-authored so the model, codegen, matcher and Validator can be built test-first. The
   rollout's first task is the extractor, and its done-when is that it reproduces the three
   pilot files byte for byte (a golden test). No hand-authored base file survives the
   rollout.
2. **Base structures extracted.** The extractor is the only author for base HL7 structures
   on every version. `Resources/structures/overrides.json` holds print errata and group
   names the print omits; every entry cites version, chapter and section.
3. **AU structures hand-authored as profile data.** The ADRM-2021 constrained structures
   live under `Resources/profiles/au-adrm-2021/structures/` in the same JSON shape, each with
   a page citation. They are profile data, like the existing
   `Resources/profiles/au-adrm-2021/vmr-table.json`, not base grammar.

### Option D — Import a third-party rendering (not recommended)

HL7 v2.xml schemas or HAPI structure classes. Provenance and licence differ from the
normative print, and an integrator could not check the result against the spec text alone
(requirement 2). Listed so the owner sees it was considered.

### Decision

**Option C.** It keeps the ADR-015 guarantee (the print is the only source, the extractor
the only author) for the thousand-file bulk, lets the pilot run test-first now, and does
not build a second extractor for three AU files. The golden test makes the pilot files
provisional by construction.

---

## Data model

One file per structure: `Resources/structures/v<ver>/<STRUCT>.json` for base HL7,
`Resources/profiles/au-adrm-2021/structures/<STRUCT>.json` for AU.

```json
{
  "structure": "ADT_A01",
  "version": "2.5.1",
  "citation": "HL7 v2.5.1 Chapter 3, section 3.3.1, pp 3-4 to 3-5",
  "triggers": ["ADT^A01", "ADT^A04", "ADT^A08", "ADT^A13"],
  "elements": [
    { "segment": "MSH", "min": 1, "max": 1 },
    { "segment": "SFT", "min": 0, "max": null },
    { "segment": "EVN", "min": 1, "max": 1 },
    { "segment": "PID", "min": 1, "max": 1 },
    { "group": "PROCEDURE", "nameSource": "printed", "min": 0, "max": null, "elements": [
      { "segment": "PR1", "min": 1, "max": 1 },
      { "segment": "ROL", "min": 0, "max": null }
    ]}
  ]
}
```

Rules:

- `min` is 0 for `[ ]` and 1 otherwise; `max` is `null` for `{ }` and 1 otherwise. The base
  print has no other bounds; integers leave room for profile narrowing.
- `{[X]}` (v2.5.1 ORU_R01 `{[NTE]}`) and ADRM `{ [X] }` normalise to `min 0, max null`.
- `triggers` lists every `CODE^EVT` caption the version prints for the structure; `*`
  stands for "varies" (`ACK^varies^ACK`, v2.5.1 CH02 §2.14.1). A trigger appears in at most
  one structure per version (a test enforces it). On v2.3 keys are `CODE^EVT` from section
  titles and the structure ID is synthesised as `CODE_EVT`, flagged in `citation`.
- `nameSource` on every group: `printed` (the chapter prints `--- NAME begin`) or
  `override` (named in `overrides.json`, with its citation). Group names appear in issue
  text, so unprinted groups take the HL7 v2.xml encoding group names as `override` entries, each
  with its citation (decision 3).
- AU files add `"profile": "au-adrm-2021"`, `"baseVersion": "2.4"` and `"rule":
  "HL7au:00060.1"`.
- Choice notation (`< X | Y >`, v2.6 on) is not modelled yet. The extractor fails hard on
  any notation it does not model; a `choice` element is added before the first version
  that prints one. None was found in the chapters sampled.

The JSON Schema is kept, with `nameSource` added to the element definition
(`"enum": ["printed", "override"]`, required when `group` is present) and the three
optional AU keys added at the top level.

Runtime: `MessageStructure` (id, version, triggers, citation, elements) and an indirect
enum `StructureElement { case segment(String, min:, max:); case group(String, min:,
max:, elements:) }`, public and `Sendable` (the `MessageStructure` memberwise initialiser is
internal, amended in the P8 final review: there is no public matcher, so a consumer-built
structure has no use, and the AU overlay will add fields), emitted by `HL7v2KitCodegen` into
`Sources/HL7v2Kit/Structures/Generated/MessageStructureTable+v<X_Y_Z>.swift`, one constant
per structure (as ADR-017 does for datatypes, to keep type-checking cheap). The codegen
takes the structures as positional arguments 11 (the input root, `Resources/structures`)
and 12 (the output directory, `Sources/HL7v2Kit/Structures/Generated`); arguments 1 to 10
are taken by the segment, table, datatype, profile and composite inputs. The new
generated directory joins the codegen-drift CI job (both its `git diff` and its
`git status --porcelain` guards) and the never-hand-edit list.

Public lookups (`MessageStructureTable.structure(_:version:)` and `structures(...)`)
resolve `version.grammarVersion` before indexing, so `.v2_8` returns what `.v2_8_2`
returns, as the Validator does.

---

## Matcher

**Approach: greedy recursive descent over the element tree**, guarded by a determinism
lint.

- One left-to-right pass. An element is entered or repeated while the current segment is
  in its FIRST set. A segment that nothing ahead (at any enclosing level) can begin is
  reported as unexpected and skipped (FOLLOW-set recovery).
- Output: a list of deviations plus a **group-span index**: for every group instance
  matched, its name, path and the segment index range it covers. The span index is what
  replaces the ORC walk (below).
- Z-segments are transparent to the matcher (skipped, not matched); `ZSegmentPolicy`
  keeps governing them.
- ADD (addendum) segments are transparent in the same way on **every** version, because an
  ADD continues the preceding segment and the abstract message definitions never list it.
  Within a message: v2.4 CH02 §2.15.2.1, v2.5.1 and v2.6 CH02 §2.10.2.1 and v2.8.2 CH02
  §2.10.2.0 (the heading as printed) say an ADD "can be used within a message to break a
  long segment into shorter segments". On v2.3 and v2.3.1 CH2 §2.23.2 b) to f) place the
  ADD inside messages too: b) "the following segment is the ADD segment"; d) for a
  continued unsolicited update "the ADD segment will be the first segment after the MSH
  segment"; f) on the unsolicited display message "the ADD record on the continuation
  comes just after the URD/[URS] pair". The parser does not merge ADD continuations today;
  the matcher only declines to report them as unexpected.
- A non-Z segment the version's grammar does not define already raises
  `segmentNotInVersionGrammar` (ADR-018); the matcher skips it without a second issue.
- Linear time. FIRST sets are computed once per structure and cached if the performance
  budget (`HL7v2Kit-Spec.md` §9.5) regresses.

**Determinism lint** (test suite). The lint checks, for every structure, that greedy
matching resolves each choice the same way a full match would. One rule:

> For every element E that is nullable (it can match no segment: optional, or a group all
> of whose elements are nullable) or may repeat, FIRST(E) must be disjoint from FOLLOW(E):
> the FIRST sets of the siblings after E up to and including the next one that is not
> nullable (excluding E itself, so a repeating element's own re-entry is not an overlap),
> extended, when E is trailing (everything after it in its group is nullable), with the
> inherited follow set of the enclosing level. That inherited set includes the re-entry of
> the enclosing group when it repeats. A segment S in the overlap is **exempt** when every
> part of FOLLOW(E) that contains S is the re-entry of an ENCLOSING group G with unbounded
> maximum, and for each such G the re-entry can begin with S only through E itself
> (**the prefix condition**): on the path from G down to E, every element that precedes
> the path at each level is nullable, and none of their FIRST sets contains S. E may
> repeat or not. The matcher attributes S to the innermost open group, and the lint
> accepts exactly that case. Any other overlap fails the lint.

A trailing optional `NTE` inside a group followed by a sibling `NTE` therefore fails
rather than being resolved silently. The exempt case on the pilot is v2.5.1 ORU_R01:
ORDER_OBSERVATION is the trailing repeating element of the repeating PATIENT_RESULT, and
PATIENT, the only element before it, is nullable with FIRST {PID}, so the inherited
follow set overlaps FIRST(ORDER_OBSERVATION) on ORC and OBR only through the re-entry,
and that re-entry can begin with ORC or OBR only through ORDER_OBSERVATION. Staying in
ORDER_OBSERVATION and starting a new PATIENT_RESULT then lead to the same remaining match,
so the choice cannot change acceptance, the missing and unexpected findings, or any count;
only which group instance a span belongs to is a convention, and group-scoped predicates
anchor on ORC and OBR, which both readings put in an ORDER_OBSERVATION. It could change a
result if the enclosing group had a finite maximum (an AU narrowing), which is why the
exemption requires an unbounded one.

The prefix condition is necessary. Counter-example (fix round 1 of the matcher task):
`MSH {G: X {Q: X Y}}`. Without the condition the lint passes with Q exempt on X via G,
yet for the valid `MSH X X Y X X Y` (two G instances) the greedy matcher keeps the third
X in Q and reports `Y` missing in Q. G's re-entry begins with X through G's required X,
not through Q, so the prefix condition fails and the structure now fails the lint.

**Non-repeating E.** The original text exempted only a repeating E. A nullable
non-repeating first child of an all-optional unbounded group (pre-v2.5 OBSERVATION
`{[OBX] {[NTE]}}`) overlaps that group's own re-entry; the only other parse inserts an
instance boundary at E (an empty or shorter instance before it), so one-pass matching
accepts exactly the same sequences, and a second occurrence closes the instance and
re-enters the group. The exemption therefore covers E whether or not it repeats, under
the same prefix condition.

**The guard.** The lint rule is not trusted on its own. A property test in the test
target (`StructureMatcherPropertyTests`) runs a backtracking reference recogniser (it
tries every way to match, skipping Z-segments and ADD) against the one-pass matcher on
generated segment sequences: every sequence over the alphabet up to length 8 after MSH
for small synthetic structures, and seeded random grammar derivations of at most 16
segments with single-edit mutations for the pilot structures. For every structure that
passes the lint, the matcher must report no finding exactly when the reference accepts.
The counter-example above disagrees with the reference and is rejected by the lint. Each
version's rollout adds its structures to this test.

Pre-v2.5 structures may still fail the lint (the pre-v2.5 ORU shape
`OBR {[NTE]} {[OBX] {[NTE]}}` fails on the top-level `NTE` against the sibling group's
FIRST set, a genuine attribution ambiguity) and are then reported as not modelled.

The lint does not check Z-segments or ADD segments (transparent to the matcher). A
structure that fails is listed in the register and reported at runtime as
`messageStructureNotModelled`; it is never matched greedily, so a passing lint is the
precondition for any acceptance, attribution or count the matcher reports. If the failures
are many (plausible before v2.5), the owner can fund a position-set (Glushkov) NFA matcher
for them later; that is an amendment, not part of this ADR.

**Message fragments are not structure-checked.** A logical message may be "broken after an
arbitrary segment" and sent as several messages: the first ends in a DSC segment and each
later fragment carries a value in MSH-14 (v2.4 CH02 §2.15.2.2; v2.5.1 and v2.6 CH02
§2.10.2.2; v2.8.2 CH02 §2.10.2.1, the heading as printed; v2.3 and v2.3.1 CH2 §2.15.4,
§2.23.2 and the DSC segment §2.24.8, where MSH-14 is §2.24.1.14). A message is a fragment
when (amended in P8-5 fix round 1):

- MSH-14 is populated; or
- its last segment (Z-segments and ADD ignored) is DSC and DSC-1 is populated, whatever
  the structure defines; or
- its last segment is DSC and the structure's last top-level element is not DSC.

A trailing DSC with an empty (or null) DSC-1 on a structure that ends in `[DSC]` is matched
normally. The earlier text exempted any structure that "itself defines a DSC at that point
(query responses do)"; that was wrong. v2.5.1 ORU_R01 prints `[DSC]`, and v2.5.1 CH02
§2.10.2.2 says "the logical message is broken after an arbitrary segment", "The DSC-1-
Continuation pointer field will contain a unique value that is used to match a subsequent
message", "The DSC terminates the first fragment of the logical message" and "The receiver
can tell that a given incoming message is a fragment by the presence of the trailing DSC",
so `ORU^R01^ORU_R01 | PID | DSC|CP001|F` is a conformant first fragment. DSC-1 (§2.15.4.1):
"If the responder returns a value of null or not present, then there is no more data".
DSC-2 (§2.15.4.2, Table 0398: F Fragmentation, I Interactive Continuation) is not
consulted. A fragment raises
`messageStructureNotModelled` (info) and is not matched, because a fragment's segment list
is a slice of the structure and would draw false missing-segment findings. Reassembling
fragments is out of scope; the gap is registered as blocking in section E of the
limitations register.

Alternatives rejected: a regular expression over the joined segment IDs (yes or no only,
no location, no group attribution, backtracking risk); a Glushkov NFA for every structure
(exact for ambiguous structures, about three times the code, not needed where fact 1
holds).

**Known ceiling**, recorded in the register:

1. Ambiguous structures (lint failures) are not matched.
2. After the first divergence, recovery can report a second issue for one real defect (an
   out-of-order PID reports "PID missing" and "PID unexpected"). The first issue is always
   accurate.
3. The lint's exempt case (above): an element whose FIRST set overlaps the re-entry of an
   enclosing unbounded repeating group, where the prefix condition holds (ORU_R01
   ORDER_OBSERVATION inside PATIENT_RESULT without PATIENT; the pre-v2.5 `[OBX]` inside
   `{[OBX] {[NTE]}}`), is attributed to the innermost open group. Acceptance is
   unaffected; only group attribution is a convention. The reference-recogniser property
   test guards the rule.
4. Group spans are exact only when the match has no deviation. After a deviation the spans
   are best-effort, so group-scoped predicates do not use them (below).
5. Where Z-segments may sit is not checked (fact 3).
6. Message fragments are not structure-checked and not reassembled (above). Known cost of
   the DSC-1 rule: a complete message that carries a continuation pointer (for example an
   interactive query response installment, DSC-2 = I, v2.5.1 CH05 §5.6.3.1) is not
   structure-checked either. Neither CH02 §2.10.2 nor CH05 §5.6.3 says whether each
   interactive installment is a structurally complete message, so no DSC-2 refinement is
   made. Versions that print DSC other than last at top level are a rollout item.
7. A message whose `message.version` has a different grammar version from the wire reading of MSH-12 (for example
   one parsed with `ParserOptions.versionOverride`) is not structure-checked; it raises
   `messageStructureNotModelled`. This is the conservative choice (no misfire); honouring
   an explicit override would need version provenance on `Message`.

---

## New ValidationIssue codes (additive)

`IssueCode` is an open enum (ADR-014); all four are new cases.

| Code | Meaning | Location | Severity |
|---|---|---|---|
| `messageStructureSegmentMissing(structure:segmentID:group:)` | A required segment, or the head of a required group, is absent. `group` is `nil` at top level. | The segment it was expected before (the last segment when expected at the end) | `messageStructureSeverity` |
| `messageStructureSegmentUnexpected(structure:segmentID:)` | A segment has no place at that point: out of order, an extra repetition of a non-repeating segment or group, or a non-Z segment the structure does not contain (ADD, and a segment the version's grammar does not define, are skipped; see "Matcher"). | The segment | `messageStructureSeverity` |
| `messageStructureMismatch(declared:trigger:)` | MSH-9.3 names a structure the version does not print for MSH-9.1^9.2, or (on a complete version only, lookup rule 1) MSH-9.3 is not a structure of the version and MSH-9.1^9.2 is printed only under another structure. | MSH-9.3 | `messageStructureSeverity` |
| `messageStructureNotModelled(structure:)` | No structure is modelled for this message (or it fails the lint, or the version is unresolved, or MSH-9.3 is empty and MSH-9.1^9.2 is printed under two loaded structures), so order and groups were not checked. | MSH-9 | always `.info` |

AU 00060.1 findings reuse the existing `profileConstraintViolation(localeRule:
"HL7au:00060.1")`, as every other AU point does; no AU-specific code.

---

## Severity and option gating

New stored property, not an init parameter (ADR-014 house style, the M21/M27 pattern):

```swift
/// Severity for message-structure findings. `nil`, the default, leaves them unchecked.
public var messageStructureSeverity: IssueSeverity? = nil
```

`nil` means the matcher does not report deviations and `messageStructureNotModelled` is not
emitted. Presets are unchanged in this cycle (`.default` and `.strict` stay `nil`), and
`.lenient` sets `options.messageStructureSeverity = nil` explicitly (it lists every check it
disables), so that a later change to `.default` and `.strict` cannot switch the check on
for `.lenient`. A test pins the three presets.

**Why default off.** Three grounds, none of them about test data:

- Owner decision at gate G2: the check ships off, with the staged rollout deciding when
  it is recommended.
- ADR-014: a default-on check changes `isValid` for existing callers in a 3.x minor.
- v2.5.1 CH02 §2.6.2 a): a recipient ignores segments "present but not expected", so
  structural conformance is the sender's property and a receiver may reasonably want it
  as a warning rather than a rejection.

Fixture and test conformance is a measurement, not a justification: the pilot runs the
full suite with the default and separately with `.warning` to measure (not fix) how many
existing fixtures conform to the pilot structures.

**Later preset change.** Once a version's rollout is complete, the recommended presets are
`.strict` = `.error`, `.default` = `.warning` (fact 2), `.lenient` = `nil`. This is a change
of default output, not of API. ADR-014's additive-only rule is not breached, and the
default-output change is allowed in a minor on the ADR-018 precedent (new
default warnings as a spec-fidelity fix). The owner confirms the change at the rollout's
close, not now.

**Group spans are not gated by severity.** Whether a predicate uses spans or the ORC walk
changes predicate outcomes, not structure findings. See the next section and decision 5.

**AU gating.** 00060.1 applies under `HL7Locale.auLocalisation` when
`messageStructureSeverity` is non-nil, with that severity. No new AU option: 00060.1 names
Senders and needs no fact the wire lacks (unlike M29/M30/M32).

---

## Structure resolution and version

Structure definitions come from the **grammar version**, following ADR-018's table row by
row:

| MSH-12 (VID.1) | Structures applied | Note |
|---|---|---|
| 2.3, 2.3.1, 2.4, 2.5.1, 2.6, 2.8.2 | Its own | |
| 2.8 | v2.8.2 | Covered by the existing `versionGrammarSubstituted` info |
| 2.7.1 (until P10), other, unresolved, or empty | None | `messageStructureNotModelled` (info). Not the v2.5.1 fallback grammar that ADR-018 uses for segments: applying v2.5.1 structures would report every later-version segment and group as a deviation (decision 4) |

The version comes from the wire reading, `Version.reading(msh12:subcomponentSeparator:)`,
taken at validation time, because `Message` carries no record of where `message.version`
came from (`ParserOptions.versionOverride`, or a message built directly). The rule: when the
reading is `.recognised(v)` and `v.grammarVersion` equals `message.version.grammarVersion`
(the comparison is between GRAMMAR versions, amended in P8-5 fix round 1: a 2.8 wire message
is validated as v2.8.2 and takes the v2.8.2 structures, as the table above says), the
structures of `v.grammarVersion` apply; when the reading is `.unresolved` or `.empty`, or
recognises a version whose grammar version differs from that of `message.version`, no
structure is resolved, no body match runs, and
the one info issue is `messageStructureNotModelled`. On an unresolved populated MSH-12
`versionNotRecognised` (warning) also fires today. On an empty MSH-12 no version issue
fires (`appendVersionIssues` returns nothing for `.empty`); the required-field check
reports `requiredFieldMissing` for MSH-12, so `messageStructureNotModelled` is the only
structure-related finding.

Lookup, within the grammar version's `MessageStructureTable`:

1. MSH-9.3 valued: look the structure up. If MSH-9.1^9.2 is not among its `triggers`,
   raise `messageStructureMismatch` and report the mismatch only: the body is not matched
   against the structure MSH-9.3 names, because the print gives that event another
   structure and a conforming body of the event would draw spurious missing or
   unexpected findings. No body match runs on a mismatch. Unknown ID on an incomplete
   version: `messageStructureNotModelled`; on a complete version:
   `messageStructureMismatch`.
2. MSH-9.3 empty: resolve MSH-9.1^9.2 through the `triggers` index (the v2.3 case and
   legacy two-component MSH-9). The missing component itself stays the business of the
   required-component check (M21). A trigger no loaded structure prints is
   `messageStructureNotModelled`; one printed under two loaded structures (pre-flight B6;
   none in the pilot) is not resolved either, and the info issue names it ambiguous and
   lists both structures (amended in P8-6).
3. v2.3: resolution uses MSH-9.1^9.2 only; v2.3 defines no MSH-9.3.
4. `ACK^<any>` resolves to `ACK` via `*`.

**Table 0354 is not consulted at runtime** (fact 5). The grammar version's own
`Resources/tables/<ver>/0354.json` is extraction input on v2.3.1 (where captions carry no
structure ID) and an audit elsewhere: the rollout reconciles extracted `triggers` against
it and records each disagreement with a citation.

---

## Interaction with the existing ORC-group scoping

The group-span index **coexists with and supersedes** the walk, per message:

1. If the version's structures are **complete** (the `isComplete` probe, set per version
   only by the rollout task that supplies and verifies them), the message's structure is
   modelled and passes the lint, and the match has **no deviation**, group-dependent
   lookups use the span index. On a version that is not complete the walk is always used,
   even for a modelled pilot structure, so a pilot never changes predicate outcomes on a
   version it only partly covers:
   - `associatedSegment(_:fromIndex:)` / `segmentExists(_:inGroupOf:)`: from the innermost
     group instance containing the anchor segment, walk outward to the first enclosing
     group whose definition contains the peer segment ID at any depth; search that
     instance's span. At top level, the whole message.
   - `resolveGroup(scope:)`: `.orcObxGroup` and `.obrObxGroup` resolve to the innermost
     group instance containing the anchor whose definition contains ORC (or OBR
     respectively); `.messageWide` is unchanged.
   - `checkOrcObrPairEquality` uses the same peer rule.
2. Otherwise (version not complete, structure unmodelled, lint failure, unresolved
   version, or any deviation),
   the existing walks are used unchanged. `orcGroupRange` stays as the fallback and is not
   removed; it is internal, so nothing public changes either way.

Internally this is one seam: `Message` gains an internal optional span index that the
Validator fills before the predicate pass; the three call sites ask it first. The ADR-010
DSL atoms keep their syntax and meaning ("in the same group"); only the definition of
"group" sharpens.

**ORC-8 on OUL R22 to R24.** With spans, the ORC and OBR of one ORDER group are in the same
span, so `OBR absent` is false and the leg does not fire. P4-7 has already shipped the
interim fix (decision 6). The `OBR absent` leg of the conditional fields carries
`messageCode not in (OUL)` on v2.5.1 (6 ORC fields, 3 OBR fields) and
`messageCode not in (OUL, OPU, OPL)` on v2.6 (6 ORC, 3 OBR) and v2.8.2 (4 ORC, 2 OBR),
in `Resources/schemas/<ver>/ORC.json` and `OBR.json`. It is spec-defensible for OUL_R22 to R24 and OPU_R25 (OBR is the required group
head, so the leg is vacuous) but under-fires on OUL_R21, which prints `[ORC] OBR`. **The
P4-7 gates are removed only by the rollout task that supplies the spans** for the version
in question (R9), never earlier and never as part of the pilot, so the misfire stays fixed
at every step.

**Default-output change.** Switching a version to span-derived groups changes predicate
outcomes with `messageStructureSeverity` off. This is accepted under G2 but is a change of
default output: R9 ships a before and after test for each affected predicate and a
Migration.md row recording it.

**HL7au:00060.1.** Enforced through this model under the AU profile, in the rollout
task immediately after the extractor (decision 8): AU messages are matched against the ADRM-2021 constrained structure for their
trigger (AU files, `profileConstraintViolation(localeRule: "HL7au:00060.1")`) in addition
to the base v2.4 structure. It needs the matcher and codegen from the pilot, not the v2.4
base rollout, so it can land straight after the extractor. (The conformance generator
currently classifies 00060.1 as base, "R-optionality enforcement is the Validator core";
that classification is revisited by that task.)
ADRM says "some optional segments have been removed"; whether a removed base segment on
the wire is a 00060.1 finding, or only a missing required one is, is decision 7.

---

## Version rollout order

1. **Pilot** (P8-3 to P8-6): v2.5.1 ADT_A01, ORU_R01, ACK, hand-authored. Covers a flat
   structure with named groups, deep nesting with unnamed groups and repeating groups
   inside repeating groups, and a wildcard trigger.
2. **R1 extractor**, done when it reproduces the pilot byte for byte.
3. **AU overlay** (00060.1): the three ADRM-2021 structures, hand-authored with page
   citations (decision 8).
4. **v2.5.1 complete** (169 structure IDs measured), with `isComplete` per version. Setting
   `isComplete` also switches lookup rule 1's unknown-ID case from `messageStructureNotModelled`
   to `messageStructureMismatch` for that version (until then `ADT^A04^ADT_A04` on v2.5.1 is
   info only; register §E carries the row). Amended in P8-8.
5. **v2.6**, **v2.8.2**, **v2.4** complete, in order of print regularity.
6. **v2.3.1** (structure IDs through Table 0354), then **v2.3** (section-title events,
   synthesised IDs).
7. **v2.7.1**, a seventh version in the rollout, when plan P10 lands (ADR-018 schedule),
   in the same cycle as its grammar.
8. **R9 group resolution** switched on per complete version (the section above), then
   **R10 close-out**: owner confirms the preset change; register §E leaves "blocking" only
   when every modelled version is complete.

---

## Acknowledgments

1. Non-goal. 2. Validate the ACK structure only. 3. Option 2 plus a builder for the
general acknowledgment applying the echo rules (MSA-1 from Table 0008; MSA-2 = original
MSH-10; MSH-3/4 and MSH-5/6 swapped; MSH-9 `ACK^<event>^ACK`, two components on v2.3;
MSH-11 and MSH-12 echoed). 4. Option 3 plus the enhanced-mode protocol from MSH-15/16.

Decision 9: option 3. Option 4 is receiving-application behaviour (v2.5.1 CH02 §2.9.2 to
2.9.3) and is recorded as a non-goal in `HL7v2Kit-Spec.md` §2. New public API is additive:
`AcknowledgmentCode`, `MessageBuilder.acknowledgment(to:code:messageControlID:dateTime:)`
(a new static method, no change to existing initialisers), and
`BuilderError.acknowledgedMessageControlIDMissing`.

Amended in P8-8 (2026-10-02), recording what P8-7 shipped: the builder also echoes the
original's MSH-18 when it is populated, because the ACK is serialised in the original's
character set and must declare it. That is a builder rule, beyond both the list above and the
spec's echo list (v2.5.1 CH02 §2.9.2.2 names MSH-3, MSH-4 and MSH-11 as copied). On v2.3 and
v2.3.1, §2.24.1.9 says "The second component is not required on response or acknowledgment
messages", so echoing the event there is permitted, not mandated. An original with an empty
MSH-9.2 gives `ACK^^ACK`, which fails the required MSG.2 on v2.5.1, v2.6 and v2.8.2 exactly as
the original does (`AcknowledgmentBuilderTests` pins it).

---

## Consequences

- New public API, all additive (ADR-014): `MessageStructure`, `StructureElement`,
  `MessageStructureTable`, four `IssueCode` cases,
  `ValidationOptions.messageStructureSeverity`, and the acknowledgment builder types.
  Ships in a 3.x minor. Each new public symbol gets a Migration.md row and a
  `SignatureCompatibilityTests` pin: `messageStructureSeverity` (default `nil` on the
  default, strict and lenient presets), the four `IssueCode` payload labels,
  `MessageBuilder.acknowledgment(to:code:messageControlID:dateTime:)` and
  `BuilderError.acknowledgedMessageControlIDMissing`.
- New generated directory `Sources/HL7v2Kit/Structures/Generated/`; new resource trees
  `Resources/structures/` and `Resources/profiles/au-adrm-2021/structures/`; the working-notes
  never-hand-edit list and the codegen-drift job extended.
- Default output is unchanged by the pilot. It changes in two stated places: when a version
  switches to span-derived groups (R9, with a Migration.md row) and when the owner
  confirms the preset change at close-out.
- Group-dependent predicates become structure-exact on complete versions for conforming
  messages; the ORC walk remains the fallback.
- Fragments are not structure-checked (`messageStructureNotModelled`); registered as blocking.
- Until the rollout completes, register §E stays blocking with the modelled set stated.

## References

- v2.5.1 CH02 §2.5.2, §2.6.2, §2.9.2, §2.9.3, §2.14.1; CH03 §3.3.1; CH07 §7.3.1, §7.3.9.
  v2.6 CH07 §7.3.10. v2.8.2 CH03 ADT_A01. ADD segment: v2.4 CH02 §2.15.2.1, v2.5.1 and
  v2.6 CH02 §2.10.2.1, v2.8.2 CH02 §2.10.2.0, v2.3 and v2.3.1 CH2 §2.23.2 b) to f).
  Fragments: v2.4 CH02 §2.15.2.2, v2.5.1 and v2.6 CH02 §2.10.2.2, v2.8.2 CH02 §2.10.2.1,
  v2.3 and v2.3.1 CH2 §2.15.4 and §2.23.2.
  ADRM-2021 HL7au:00060.1, pp 17, 205.
- ADR-008, ADR-010, ADR-014, ADR-015, ADR-016, ADR-017, ADR-018.
- `planning/reviews/README.md` X-C04; `planning/remediation/P8-message-structures.md`
  (Intake rows: P1 Minor 9, P3 fix wave); `planning/remediation/P1-obr-predicates.md`.

---

## Decisions

Owner gate G2, answered 2026-09-30 (all recommended defaults).

| # | Choice | Decision |
|---|---|---|
| 1 | Source of truth | Option C, hybrid |
| 2 | Matcher | Greedy recursive descent plus determinism lint; lint failures "not modelled" |
| 3 | Unprinted group names | HL7 v2.xml names as cited overrides |
| 4 | Unrecognised or empty MSH-12 | Skip, `messageStructureNotModelled` (info); no fallback grammar |
| 5 | Group spans gating | On for complete versions with a clean match, independent of severity; behind the `isComplete` probe |
| 6 | ORC-8 OUL misfire | Interim gate `messageCode not in (...)` shipped in P4-7; removed per version by the rollout task that supplies spans |
| 7 | AU removed segments | Not a finding; 00060.1 covers missing required segments only |
| 8 | AU overlay timing | Immediately after the extractor (R1) |
| 9 | Acknowledgments | Build and validate the general ACK; no protocol logic |
| 10 | Severity | `messageStructureSeverity = nil` default now; presets `.warning` and `.error` confirmed at close-out |

## Addendum 2026-10-02 — pilot shipped

P8-3 to P8-7 shipped the pilot (rollout step 1) and the acknowledgment builder; P8-8 recorded
it. What the code does, checked against the source at P8-8:

- **Structures.** Three, all v2.5.1, hand-authored in `Resources/structures/v2.5.1/` and
  generated into `Sources/HL7v2Kit/Structures/Generated/`: `ADT_A01` (triggers ADT^A01,
  ADT^A04, ADT^A08, ADT^A13), `ORU_R01` (ORU^R01) and `ACK` (`ACK^*`). Each passes the
  determinism lint. No version is complete; the `isComplete` probe and span-derived groups
  (R9) are not built, so group-dependent predicates still use the existing walks everywhere.
- **Option.** `ValidationOptions.messageStructureSeverity` (`IssueSeverity?`, `nil` in
  `.default`, `.strict` and `.lenient`). Off, the Validator does not run the check, so default
  output is unchanged. Presets stay `nil` until close-out (decision 10).
- **Issue codes.** `messageStructureSegmentMissing(structure:segmentID:group:)`,
  `messageStructureSegmentUnexpected(structure:segmentID:)` and
  `messageStructureMismatch(declared:trigger:)` at the configured severity;
  `messageStructureNotModelled(structure:)` always `.info`, raised for an unmodelled structure
  or version, an empty, unresolved or different-grammar MSH-12, an unknown MSH-9.3 (no version
  is complete), an ambiguous trigger, a fragment, and a structure failing the lint.
- **Resolution.** MSH-9.3 when valued, else MSH-9.1^9.2 through the triggers; a mismatch is
  reported alone, with no body match. Z-segments, ADD and segments the version's grammar does
  not define are skipped by the matcher.
- **Public model.** `MessageStructure` (`id`, `version`, `triggers`, `citation`, `elements`
  and `accepts(messageCode:triggerEvent:)`; the initialiser is internal since the P8 final
  review), `StructureElement` (`segment(_:min:max:)`,
  `group(_:min:max:elements:)`, `min`, `max`; open, for the planned `choice` case) and
  `MessageStructureTable` (`structure(_:version:)`, `structures(messageCode:triggerEvent:version:)`).
- **Builder.** `AcknowledgmentCode` (Table 0008, six cases, open),
  `MessageBuilder.acknowledgment(to:code:messageControlID:dateTime:)` and
  `BuilderError.acknowledgedMessageControlIDMissing` (decision 9 as amended above).

Where the pilot differs from the text above (P8 final review):

- **No `Resources/structures/overrides.json` and no JSON Schema file yet.** Each pilot
  structure carries its override citations (group names taken from HL7 v2.xml, the
  `{[X]}` reading) in its own `citation`, and `StructureCodegen` enforces the file shape
  (unknown keys and missing `max` are rejected). The rollout's extractor task creates
  `overrides.json`.
- **Lookup rule 3 is not implemented.** v2.3 has no MSH-9.3, so it resolves from
  MSH-9.1^9.2 only; until v2.3 structures load, every v2.3 message is not modelled, and the
  rule cannot be exercised.
- **The determinism lint also runs at validation time,** on every message that reaches the
  matcher, uncached (`Validator+MessageStructure.swift`). The rollout caches it.

Tests, measured at P8-8 with `swift test --filter` per suite: `MessageStructureDataTests` 1,
`MessageStructureTableTests` 8, `StructureLintTests` 13, `StructureMatcherTests` 26,
`StructureMatcherPropertyTests` 6, `StructureMatcherCorpusTests` 1,
`MessageStructureValidationTests` 39, `AcknowledgmentBuilderTests` 13 (one added in P8-8):
107 tests in 8 suites. The full suite is 1291 tests in 92 suites. Parameterised tests count
once. The P8 final review added one (`MessageStructureValidationTests` 40): 108 tests in the
8 suites, 1292 in all.

To show that the check changes no default output, extract the spec examples with
`scripts/extract-example-messages.py`, run the env-gated `ValidationDigestTests`
(`VALIDATION_DIGEST_OUT`, `SPEC_EXAMPLE_MESSAGES`, optionally
`VALIDATION_DIGEST_STRUCTURE_SEVERITY`) at two commits, and compare the two digests.

Register §E stays blocking, with this modelled set stated. Next: the per-version rollout,
scoped as its own plan by P8-9 with an owner gate, starting with the extractor (step 2).

## Amendment 2026-10-03 — generated version switch and completeness (P8b-1)

- **Completeness data.** `Resources/structures/completeness.json` lists every modelled grammar
  version (the seven schema version directories, never the `2.7` and `2.8` substitutions) with
  `complete` and a one-line `citation`. All seven are `complete: false`. The name does not start
  with `v`, so it cannot be read as a version directory; the structures root may hold only that
  file and `v<version>` directories, and anything else fails the codegen.
- **Generated switch.** `StructureCodegen` renders
  `Sources/HL7v2Kit/Structures/Generated/MessageStructureTable+Versions.swift`: the switch from
  `Version` to its per-version table (one explicit case per listed version, an empty table
  where nothing is modelled; `v2_7` and `v2_8` resolve through `grammarVersion` before the
  switch, so no table is duplicated) and `completeVersions`. The hand-written switch is gone.
  The codegen rejects a completeness file whose keys differ from the schema version set, an
  unknown key, an empty or multi-line citation, and a version marked complete with no
  structures; `scripts/check-audit-schemas.py` asserts the same key set alongside the other
  per-version maps.
- **Lookup rule 1, complete branch.** `MessageStructureTable.isComplete(_:)` (internal) reads
  `completeVersions` through `grammarVersion`. On a complete version an MSH-9.3 that names no
  loaded structure raises `messageStructureMismatch` at the configured severity, with no body
  match (an ID differing from a loaded one only by case or whitespace is named in the
  message); on an incomplete version it stays `messageStructureNotModelled` (info). No version
  is complete, so output is unchanged; tests prove the branch on a synthetic complete version,
  including a `2.8` message on a complete v2.8.2.
- **Rejection self-check.** `scripts/check-structure-codegen.sh` runs the real codegen on
  scratch copies of `Resources/structures` with one defect each and asserts the failure and
  its message, then checks that an unmodified run reproduces every committed `Generated/`
  directory byte for byte (CI, codegen-drift job).

## Amendment 2026-10-03 — extractor core and overrides.json (P8b-2a)

- **Extractor.** `scripts/extract-message-structures.py` reads the `CODE^EVENT^STRUCTURE`
  caption form (v2.4 to v2.6; the other eras land in P8b-3) and reproduces the three v2.5.1
  pilot files byte for byte (golden: `scripts/check-extract-message-structures.py`, CI). A
  caption must carry a title (a bare `CODE^EVT^STRUCT` is a table cell, as in Table 0119);
  a group whose only member is another printed group stays two groups; a structure printing
  choice notation is reported and skipped until the `choice` element exists (P8b-6).
- **overrides.json now exists** (the addendum above said it did not). It holds `groupNames`
  (an unnamed group addressed by its named ancestors and zero-based position, with
  `nameSource: override` and a citation), `citationNotes` (the text after the composed
  `HL7 v<ver> Chapter <n>, section <s> <title>, p(p) ...` citation), `triggerFolds` (ACK:
  every `ACK^<event>^ACK` caption is `ACK^*`, CH02 section 2.14.1) and `exclusions`
  (non-normative prints by section, ruling G7; v2.5.1 CH05 section 5.7.3.1 printed ORU^R01
  ahead of Chapter 7). `errata` and `sharedTriggers` stay empty until P8b-3. The codegen
  skips `overrides.json` and a `profiles/` directory (G9) under the structures root.
- **Pilot citation fix found by the golden.** The ORU_R01 citation gave pp 7-12 to 7-13 (and
  the extractability note above says p7-12 to 7-13); the print puts the 7.3.1 heading on
  p 7-12 and the table on pp 7-13 to 7-14. The citation rule is caption page to last-row
  page, which ACK (p 2-61) and ADT_A01 (pp 3-4 to 3-5) already followed; ORU_R01 now reads
  pp 7-13 to 7-14. No structure data changed.
- **Print disagreements reported, not modelled.** v2.5.1 CH05 prints the ACK for Q16, Q17,
  J01, J02 and Q03 with `[ ERR ]`, where CH02 section 2.14.1 prints `[{ ERR }]`; the ACK
  structure follows CH02 and the extractor lists the others as report notes.

## Amendment 2026-10-03 — HL7 v2.xml bundle names (P8b-2b)

- **Decision 3 is now implemented through the bundles.** `scripts/read-v2xml-bundles.py` reads
  the owner's HL7 v2.xml schema bundles (`docs/XML-schemas`, gitignored; v2.4, v2.5.1, v2.6,
  v2.7.1, v2.8.2), and an unnamed printed group takes the name of the bundle group with the
  same parent path, first segment and member segment set (every segment at any depth), never
  a position. `nameSource` now takes five values: `printed`, `override`, `v2xml`, `v2xml-v2.4`
  and `synthesised`; this supersedes the data-model bullet above that routes bundle names
  through `override`. Override entries remain only for names no bundle gives, and an override
  that a bundle name shadows is an error.
- **Citations.** Each non-printed name is cited inside the structure `citation`, in document
  order: `NAME (HL7-xml v<ver>/<STRUCT>.xsd, <STRUCT>.<GROUP>.CONTENT)`, `NAME (HL7-xml
  v2.4/..., derived for v<ver> <STRUCT>[, which differs from <V24STRUCT> only by trigger])`,
  `NAME (overrides.json: <citation>)` or `NAME (synthesised: <why>)`. `StructureCodegen` and
  the extractor reject a non-printed name whose `NAME (<source marker>` text is absent.
- **Derivation for v2.3 and v2.3.1 (ruling D2).** No bundle exists. In the v2.4 bundle's file
  of the same structure ID, the group with the same first segment and member set (the parent
  path breaks a tie); where v2.4 has no file of that ID, every v2.4 file of the same message
  code (OMD_O01 against OMD_O03), citing both IDs. A miss synthesises `<FIRSTSEG>_GROUP`
  (numbered 2, 3, ... on a clash within the structure) and is a `no-bundle-name` report row.
  `v2xml-v2.4` is accepted only on v2.3 and v2.3.1, and `v2xml` never on them.
- **Bundles are names-only (ruling D3).** The extractor compares each parsed structure's tree
  with the same-version bundle and writes `bundle-differs` report rows (member lists, bounds,
  unreadable schemas such as v2.5.1 `ORL_O34.xsd`, which nests `SPECIMEN` inside itself); the
  print stays normative and nothing but names is taken from a bundle. No bundle text is
  committed: the self-check uses synthetic schemas in the bundle's style (ruling D4).
- **Pilot.** The five v2.5.1 ORU_R01 names are now `v2xml`, cited to `HL7-xml
  v2.5.1/ORU_R01.xsd`; the structure data is unchanged.

## Amendment 2026-10-04 — every caption form, primary print, exclusions, errata (P8b-3a)

- **Caption forms.** The extractor reads every version (`ERAS_PENDING` is empty).
  `caret` (v2.4 to v2.6): `CODE^EVT^STRUCT title`, and `CODE^EVT  title` with the structure
  ID from that version's Table 0354. `table-0354` (v2.3.1): the same two forms. `caret-colon`
  (v2.7.1, v2.8.2): `CODE^EVT^STRUCT: title` on its own line; the columns come from the
  `Segments  Description` row, which resets them wherever it repeats after a page break;
  pages are numbered per chapter (`Page 4`) and cited as printed. `section-title` (v2.3): the
  message code alone; the events come from the section title `(event A01)`, read across a
  wrapped title. v2.3 prints no Table 0354; its IDs resolve through v2.3.1's (cited). An
  event list or range (`C01-C08`, `PCG,PCH,PCJ`, `S12-S24,S26,S27`) expands to its events. A
  caption needs no Status or Chapter header: v2.4 prints 34 three-part captions without one
  (36 counting the two-part forms), every one a Chapter 4 or 5 query or response grammar
  example or a Z-event, and each is excluded by a cited `exclusions` entry. A caption whose
  structure ID Table 0354 cannot resolve (no row, or several) is reported
  (`needs-structure-id`), never guessed; a v2.3 caption under a title naming no event is
  reported (`needs-event`).
- **Primary print.** Exclusions apply first. A `triggerFolds` entry names the primary; else
  the primary is the first print in reading order whose caption is the defining trigger
  (CODE_EVT equals the structure ID: the chapter that defines the message, not one that
  only reuses it); else the first print in reading order. Reading order is chapter order
  (v2.3's `CH1` to `CH12` sort numerically). Every other print that differs is a report row
  (`duplicate-differs`, or `duplicate-unreadable`); the structure follows the primary.
- **Exclusions (ruling G7).** 107 cited entries across v2.4 to v2.8.2: the Chapter 2B
  message-profile example, the Chapter 4 Z-event query (QBP^Z73, RTB^Z74), the Chapter 5
  query grammar, query profile and conformance-statement examples, and the Chapter 8 MFN_Znn
  template and example master file query. The QBP^Q31/RSP^K31 pair (CH04 4.13.20, CH04A) is
  normative and stays. On a full read, an exclusion or erratum that matches nothing fails.
- **Errata.** `errata` entries read a print typo as the intended text, each naming the
  printed and intended text and where (`caption`, `group-mark`, `table-0354`). 87 group-mark
  entries (v2.5.1 14, v2.6 22, v2.7.1 41, v2.8.2 10): misspelt names (`OMSERVATION`,
  `QUERY_RESPNSE`, `TIIMING`, `PAYER_MF_WENTRY`, `RESOURCE` for `RESOURCES`) and names printed
  with a space or a slash (`PATIENT VISIT`, `SUBJECT_PERSON/ANIMAL_IDENTIFICATION`), each read
  as the name the version's HL7 v2.xml bundle gives that group. A group mark the reader cannot
  read is now an error, never dropped (it had been silently ignored, so such a group took a
  bundle name instead of its printed one).
- **Reader.** A footnote digit on its own line is furniture; one at the left margin opens the
  page-foot footnotes, furniture up to the footer. A row with an empty description and text in
  a later column (Chapter with a footnote number; v2.4's Group Control) is a row. A mark whose
  `begin` or `end` wraps onto the next line is one mark; `End` reads as `end`. A non-notation
  row at depth 0 ends the table. Six more errata: Table 0354 rows misprinted in v2.3.1 (`ORM__O01`,
  `RAS_O02` event `O022`, `RROR_ROR`, `SIIU_S12`) and v2.5.1 (`BRP_030`), and the v2.3.1
  caption `R0R^R0R` (section 4.8.17) read as `ROR^ROR`. v2.3 borrows v2.3.1's table with its errata.
- **ACK.** `triggerFolds` now folds ACK for v2.4 (section 2.14.1), v2.6, v2.7.1 and v2.8.2
  (section 2.13.1) as for v2.5.1; without it `ACK^varies^ACK` is not a trigger. v2.3 and v2.3.1
  print `ACK^<event>` with no ID and their Table 0354 has no ACK row, so ACK stays
  `needs-structure-id` there until P8b-14 and P8b-15 decide.
- **Shared triggers and Table 0354.** A trigger printed under several structures is a
  `shared-trigger` report row, declared by a cited `sharedTriggers` entry or not; the codegen
  is unchanged. Declared: v2.3.1 `ORM^O01` (five structures) and `ORR^O02` (five); v2.8.2
  `ORL^O22`, `ORL^O34`, `ORL^O36`, `ORL^O40` (two each). Undeclared, for P8b-3b: the range
  captions `MFN^M01-M06^MFN_M01` (v2.4) and `MFR^M01-M17^MFR_M01` (v2.5.1, v2.6), which put
  M02 to M07 under the generic structure as well as their own. Table 0354 is reconciled per version: a printed structure ID the table lacks
  (`0354-missing-row`) and a row no normative print carries (`0354-missing-caption`).

## Amendment 2026-10-04 — the choice element (P8b-6)

The print uses `< A | B >` from v2.4 on (v2.5.1 CH02 section 2.5.2: "one of the segments or
groups ... may be present"). The data model gains the element the "Data model" section
promised before the first version that prints one.

- **Model.** `StructureElement.choice(_ name: String?, min:, max:, alternatives:)`. Each
  occurrence takes exactly one alternative; each alternative keeps its own bounds. The name
  is the one the print gives (named choices appear from v2.7.1 on, between `--- NAME begin`
  and `--- NAME end`) or nil. FIRST of a choice is the union of its alternatives' FIRST
  sets; a choice is nullable when its minimum is 0 or any alternative is nullable; its head
  segment (reported when a required choice is absent) is the first alternative's.
- **Walker.** `children` (a group's elements, a choice's alternatives, none for a segment)
  and `segmentIDs` (every segment ID at any depth) are public and cover every case, so a
  consumer that recurses through them, with `@unknown default` in any switch, never skips
  the segments inside a case it does not know (the pilot final review's carry-in).
- **Matcher.** A choice occurrence takes the alternative whose FIRST set holds the current
  segment and matches it as a one-element sequence whose follow set is the choice's own
  follow plus the choice's FIRST set (another alternative's segment is left to the choice,
  where it re-enters a repeating choice or is a stray past the maximum). A named choice
  opens a group span per occurrence and names a `.missing` finding for the choice itself;
  an unnamed choice opens no span and adds nothing to a path.
- **Lint.** Two rules on top of the single FIRST/FOLLOW rule, which applies to a choice
  like any element: (1) the alternatives' FIRST sets must be pairwise disjoint (the matcher
  picks by the current segment alone); (2) no alternative may be nullable. Rule 2 is
  conservative: an empty occurrence could be taken through the nullable alternative or the
  choice's own bounds, and the one-pass matcher does not decide between them. On the
  synthetic shape `MSH {<[A] | [{B}]>} C` the matcher and the reference recogniser still
  agree on all 9,841 sequences, so rule 2 may be relaxed later with the property test as the
  guard; until then such structures (the pre-flight scan predicts eight per version from v2.6)
  go to the exact matcher (P8b-12, G15). Each alternative is linted as the one element of a
  sequence that inherits the choice's follow set and, when the choice repeats, its re-entry
  (so the prefix-condition exemption applies to a repeating choice as to a repeating group).
  An unnamed choice is named `<A|B>` (its alternatives' labels) in lint paths.
- **JSON.** `{"choice": "<NAME>" | null, "nameSource": ..., "min": n, "max": n | null,
  "alternatives": [ ... ]}`. The `choice` key is present even when the print gives no name;
  `nameSource` is required on a named choice (the group rules apply: accepted values, the
  v2.3/v2.3.1 bundle rule, a citation for a non-printed name) and forbidden on an unnamed one;
  at least two alternatives; `elements` is not allowed on a choice nor `alternatives` on a
  group or segment. Rendered as `.choice(nil, ...)` or `.choice("NAME", ...)`.
