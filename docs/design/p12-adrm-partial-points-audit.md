# P12 S2-1: re-audit of the PARTIAL and REGISTERED ADRM points

| | |
|---|---|
| Date | 2026-10-07 |
| Task | P12 S2-1 (epic P12, AU profile completion, sprint 2) |
| Base | `478e3ac1` on `v3.16-au-profile` (1730 tests in 146 suites) |
| Source | HL7AUSD-STD-OO-ADRM-2021.1 (548 pages); pages are the printed footer (`n of 548`), which equals the PDF page index |
| Scope | the 18 PARTIAL and 8 REGISTERED points of `m6-adrm-2021-conformance-register.md` |
| Output | this document only: no code, no register change (S2-2 and the close-out make those) |

## Method

1. Each point's Appendix 5 row was read in the ADRM print (text extracted once with `pdftotext -layout`
   into a scratch directory and deleted afterwards; only the short quotations below are reproduced).
   Where the row cross-refers to body text (a table, a field definition, another point's comment), that
   text was read too and is cited.
2. What ships was located in `Sources/HL7v2Kit/Locale/Profile+au_adrm_2021.swift` by its `HL7au:<id>`
   citation, and the pinning test in `Tests/HL7v2KitTests/` by the same ID.
3. The residual is quoted from the conformance register's Note column and from
   `permanent-limitations-register.md` sections B and D.
4. Each residual was tested against the capabilities that have shipped since the point was triaged
   (M6-B, 2026-09-16): message structures with group spans (`GroupScoping`,
   `Validator+GroupSpans.swift`); the open-slot, `choice`, `keyedChoice` and per-trigger-variant
   structure elements; profile structures with declared-profile variants (P12 S1-1); the per-version
   code-table registry with the AU locale axis and `localTableExtensions` (ADR-016); cross-segment
   conditions and three-state predicates (ADR-021: `previousSegment`, `associatedSegment`,
   `anyRepeat`); the `conditionNotEvaluated` info; the error and no-data response heads.
5. Verdicts. **CLOSABLE**: a rule defensible against the ADRM text alone can be built; the rule shape
   and the failing test that would prove it are stated, and whether the point then reads SHIPPED or
   stays PARTIAL with a smaller residual. **PARTIAL STAYS**: the residual needs something outside the
   wire (a terminology, a directory, a timezone database, HB 308, receiver behaviour, or sender
   intent), named. **REGISTERED STAYS**: the registered reason still holds.
6. Requirement 4 lens: for every CLOSABLE rule, the conformant message it could flag is named.

Legend for the table: `P` = `Sources/HL7v2Kit/Locale/Profile+au_adrm_2021.swift`;
`T` = `Tests/HL7v2KitTests/LocaleAUProfileTests.swift`; `TI` = `AUIdentifierComponentTests.swift`;
`TN` = `AUNASHTransportTests.swift`; `TV` = `ValidationTests.swift`; `CT` =
`Sources/HL7v2Kit/Locale/HL7CodeTables.swift`; `BV` = `Sources/HL7v2Kit/Validation/BatchValidator.swift`.

## The table

| # | Point (page) | ADRM text (quoted, short) | Ships today | Residual (registers) | Capability since triage | Verdict | Misfire risk if built |
|---|---|---|---|---|---|---|---|
| 1 | 000008.3.2 (p 423) | "the same content must be sent in one of either HTML, PDF, or TXT" | RTF display without HTML/PDF/TXT sibling fires: P:1534, P:1549; T:2084 | "same content" equality needs cross-format rendering comparison | none: group spans give the sibling set (already used), not content equality | PARTIAL STAYS (content equivalence across renderings; receiver-side rendering) | n/a |
| 2 | 000020 (p 439) | "All message types and trigger event codes beginning with the letter “Z” are reserved ... must NOT be used." | Z trigger event on ORM/ORU and on REF with the L2 profile: P:1443-1470; T:1880, T:1894, T:2400 | message-code leg "undecidable inside this rule shape" | per-trigger variants and `keyedChoice` key off MSH-9 itself, so neither says which family a `Z..` code belongs to; `messageCode startsWith Z` is already expressible (ConditionLanguage.swift:27) | PARTIAL STAYS (sender intent: whether a Z-coded message is Orders, Results or Referrals traffic is not on the wire) | an ungated `messageCode startsWith Z` would flag every site-local Z message run under `.auLocalisation` (which governs every message, ruling G-AU1) |
| 3 | 000022.1 (p 440) | "If the batch header is used it must specify individual message acknowledgement." | per-message MSH-15/16 = AL on every batched message: BV:53; TV:382 | "no information from the file header/footer or batch segments must be used" is receiver behaviour | none: BHS has no acknowledgement field; the second half is about use, not content | PARTIAL STAYS (receiver behaviour) | n/a |
| 4 | 000024.2 (p 441) | "FHS, BHS, and MSH segments must specify the Components separator character as '^'" | MSH-2 = `^~\&` on ORM/ORU only: P:334-358; T:630 | REF leg needs "character-position addressing" | no `Path` change needed: a `SegmentCardinalityRule` on MSH with predicate `MSH-2 not startsWith ^` (the shape 000020 uses) gated `messageCode = REF`; FHS-2/BHS-2 are raw strings on `BatchFile` (BatchParser.swift:19, :46), checkable in BV | CLOSABLE (to SHIPPED) | none found: `.3/.4/.5` are not enforced on REF by a first-character test |
| 5 | 000032.2 (p 444) | "values from HL7 table 0074 ... appropriate for the content in the OBR/ OBX group" | OBR-24 presence and AU 0074 membership on REF: P:811; T:1949 | "appropriate for the content" is receiver judgement | none: the registry gives membership (shipped), not content fit | PARTIAL STAYS (terminology: the OBX-3 codes' discipline against the 0074 section) | n/a |
| 6 | 000034.1 (p 444) | "if the system transmits both the public (e.g. LOINC) and local terminology, then the public ... code must appear in the identifier" | CE-6 in {LN, SCT, UCUM} requires CE-3 in {LN, SCT, UCUM}: P:654-668 (OBX-3), P:728-739 (OBX-5); CT:105-115; T:2108 | systems the ADRM does not name skip | ADR-016 locale axis: the ADRM prints its own Table 0396 (pp 142-145), which names the local systems ("99ZZZ or L", p 144) and the public ones it uses | CLOSABLE (fix and widen; stays PARTIAL for systems outside the printed 0396) | see paragraph: the SHIPPED rule misfires today on two public systems |
| 7 | 000034.2 (p 445) | "the local terminology must be transmitted in the second CE triplet i.e. the alternate identifier" | the OBX-3 correspondence of row 6: P:654-668; T:2108 | same named-public-systems scope as 000034.1 | as row 6 | CLOSABLE (fix and widen with row 6; stays PARTIAL for systems outside the printed 0396) | as row 6 |
| 8 | 000043.1 (p 447) | "The format must be" `registered organisation name in HI service^1.2.36.1.2001.1003.0.<hpio>^ISO` | caller-asserted (`auNASHTransport`) HD-2 OID with 16 digits and HD-3 = ISO on MSH-4 and MSH-6: P:80-137; TN:26-77 | the "registered organisation name in HI service" half needs the HPOS/HI directory | none new; but the printed format makes HD-1 non-empty, and HD-1 presence is not checked (TN:62 tests a bare namespace, not a missing one) | CLOSABLE (narrows: HD-1 presence under the assertion; stays PARTIAL: the name's correctness needs the HI directory) | none when asserted; the ADRM's own MSH-4 (p 162, "ACME Pathology^1.2.36...^ISO") carries the name |
| 9 | 00044.1.1 (p 448) | "CX `<ID (ST)>` component must be specified and valid according to the identifier scheme" | CX-1 presence on ORM/ORU/REF, yielding to the base from v2.5.1: P:957; TI:54-70 | "valid according to the identifier scheme" needs scheme recognition | none: the ADRM prints no scheme algorithm (p 152 only says provider numbers "have check digits built into the identifier"; the one width it states is the NASH HPI-O, p 447) | PARTIAL STAYS (identifier-scheme specifications outside the ADRM: HI service, Services Australia) | n/a |
| 10 | 00044.3.1 (p 450) | "for each document/report must be unique within the sender facility namespace (HD)" | EI-1 presence: P:1176; TI:80-89. Within one message, duplicate OBR-3 already fires under HL7au:000028 (`FieldUniquenessRule`) | "the uniqueness half is cross-message and out of scope" | none: uniqueness across the sender's history needs message history | PARTIAL STAYS (cross-message state; the register note should credit the within-message leg to 000028) | n/a |
| 11 | 00044.7.1 (p 454) | "XCN `<ID (ST)>` component must be specified and valid according to the identifier scheme" | XCN-1 presence: P:994, P:1017; TI:97 | as 00044.1.1 | as row 9 | PARTIAL STAYS (identifier-scheme specifications outside the ADRM) | n/a |
| 12 | 00044.8.1 (p 455) | "Correct timezone must be specified" | a TS of hour precision or finer without `+/-ZZZZ` fires on ORM/ORU/REF: P:1097-1106; T:2131 | correctness of the offset needs a timezone database | none | PARTIAL STAYS (timezone database and the sender's location) | n/a |
| 13 | 00044.10.1.5 (p 456) | "valued with a MIME sub-type value, then the corresponding MIME type must be used" | ED-3 subtype => ED-2 type for spec-stated pairs: P:1082-1093; CT:61-96; T:2028 | arbitrary IANA subtypes skip, fail-safe | none: the registry carries HL7 tables, not the IANA media-type registry | PARTIAL STAYS (terminology: the IANA media-type registry, unbounded) | n/a |
| 14 | 00044.10.1.6 (p 456) | "HL7 2.4 defined ... (Table 0291) value, then the corresponding HL7 2.4 type of data (Table 0191) must be used" | the same correspondence: P:1082-1093; T:2028 | "unstated ones skip" | ADR-016: the v2.4 registry lists 15 Table 0291 values (`Resources/tables/v2.4/0291.json`) and every one of them is a key of `subtypeToTypeMap` (CT:71-96); nothing skips | CLOSABLE (to SHIPPED; no rule change: a pin test that walks the registry's 0291 rows, then the register row) | none new |
| 15 | 00044.11.1.5 (p 457) | "When the RP `<subtype (ID)>` component is valued with a MIME sub-type value ... corresponding MIME type" | RP-4 subtype => RP-3 type: P:1129-1136; pinned only by the dispatch test T:2389 (no RP pair test) | as 00044.10.1.5 | as row 13 | PARTIAL STAYS (IANA media-type registry); add an RP pair pin | n/a |
| 16 | 00044.11.1.6 (p 457) | as 00044.10.1.6, for RP | P:1129-1136; T:2389 (dispatch only) | as 00044.10.1.6 | as row 14 | CLOSABLE (to SHIPPED; pin test over the registry's 0291 rows on RP, then the register row) | none new |
| 17 | 00060.1 (p 466) | "HL7 message elements with a usage of R (required) must be valued." | the six AU structures (ORU_R01, ORM_O01, ORR_O02, REF_I12 with the Appendix 8 variant, RRI_I12, OSR_Q06): `Validator+ProfileStructure.swift:33`; `LocaleAUStructureTests.swift:51` onward | RXO, ODS or ODT in place of OBR in ORR^O02 and OSR^Q06 (section E) | `choice` and `keyedChoice` elements can express the replacement; the print does not settle whether the p 280 ORM replacement carries over to the responses | PARTIAL STAYS (print ambiguity: an owner reading is needed, after which the existing `choice` element closes it) | if read as carrying over: none found; if not: n/a |
| 18 | 00104.7.1.4 (p 473) | "the correct matching `<type of ID number (IS)>` and `<other qualifying info (ST)>` must be used as per table" | AUSHICPR => UPIN, AUSHIC => NPIO/NOI on REF: P:769-783; T:1984 | vendor authorities are open-ended examples and skip | ADR-016 locale axis: AU 0363 (`Resources/tables/locale/au-adrm-2021/0363.json`, 6 rows). The PRD-7 prose (p 334): vendor identifiers "must use "VDI" as the value for `<other qualifying info (ST)>`" and 0363 "may be extended to allow for secure messaging vendor assigning authorities" | CLOSABLE (narrows: PRD-7.2 outside the printed 0363 => PRD-7.3 = VDI; stays PARTIAL: AUSDVA, AUSNATA, AUSLINK and IHI have no printed pair) | a site that extends 0363 with a non-vendor authority (the print sanctions only vendor extensions) |
| 19 | 000001 (p 417) | "Senders and receivers must ensure an order message is addressed using MSH-6 Receiving facility" | nothing (MSH-6 HD format ships caller-asserted under 00044.2.2/.2.3: P:115-137) | "receiver-runtime semantics", "soft should guidance" or PKI-deferred 00044.2; "none is a wire-checkable MUST" (section B) | none needed: the sender half of the parent MUST implies MSH-6 is valued on an order message; MSH-6 is O in the ADRM MSH table (p 37), so nothing enforces it today | CLOSABLE (to PARTIAL: MSH-6 populated when `messageCode = ORM`; 000001.1 is receiver behaviour and the 00044.2.1 name needs the HI directory) | an ORM routed by transport alone with MSH-6 empty: the point forbids exactly that, so the flag is correct |
| 20 | 000008.1.5 (p 422) | "The OBX display segment(s) must be the last in a set of OBX segments in each OBR/OBX group" | nothing | the signature identifiers live in HB 308-2011, which the ADRM does not reproduce (section D) | the ADRM itself identifies both kinds: display segments "by having AUSPDI OBX-3 `<name of coding system>`" (p 422; also p 247), and "Digital signature OBX can identified by OBX-3 (CE) identifier component starting with "AUSETAV", and OBX-3 name of code system component "L"" (000010 comment, p 438). Group spans (`GroupScoping`, scope `.obrObxGroup`) bound the set | CLOSABLE (to SHIPPED; needs one new rule shape, an in-group ordering rule) | a signature OBX encoded per HB 308 but without the AUSETAV/L identifier the ADRM prints |
| 21 | 000034.3 (p 445) | "concepts from the different terminologies must convey the same clinical meaning" | nothing | terminology-equivalence judgement (section C) | none | REGISTERED STAYS (terminology service) | n/a |
| 22 | 00044.4.7 (p 452) | "Both `<identifier>` and `<alternative identifier>` must reflect the same concept" | nothing | needs a terminology service to compare concepts (section B) | none | REGISTERED STAYS (terminology service) | n/a |
| 23 | 00044.5.7 (p 453) | as 00044.4.7, for CNE | nothing | section B says "Marked Removed in ADRM r2"; the print marks 00044.5.6 (r2) Removed, not .5.7 | none | REGISTERED STAYS (terminology service; section B's reason is wrong, see owner items) | n/a |
| 24 | 00044.6.7 (p 454) | as 00044.4.7, for CWE | nothing | as row 23 (the print marks 00044.6.6 (r2) Removed, not .6.7) | none | REGISTERED STAYS (terminology service; section B's reason is wrong) | n/a |
| 25 | 00100.1 (p 468) | "The current referral summary OBR/OBX group must appear as the first OBR/OBX group in the message." | nothing (the Appendix 8 variant, S1-1, does not mark the group) | section D: "REF-4 referral-priority ordering according to the SNOMED CT hierarchy" | group spans give "the first group"; identifying the referral-summary group needs OBR-4 to be a child of SNOMED CT-AU 373942005 or 3457005 (p 212), and the printed list is "non-exhaustive"; older referrals may follow (p 212, p 485) | REGISTERED STAYS (terminology: SNOMED CT-AU subsumption; section D's wording should name OBR-4, not REF-4) | n/a |
| 26 | 00104.7.2.1 (p 473) | "PRD-7 `<type of ID number (IS)>` must be valued from User-defined Table 0363" | nothing (`CT:52-59` keeps the AU 0363 rows for reference) | a closed check would misfire on vendor authorities (`Medical-Objects`, `Argus`, p 334) | ADR-016 locale axis plus a caller declaration: the print allows 0363 to "be extended to allow for secure messaging vendor assigning authorities" (p 334), so membership is the printed six plus the caller's declared vendor authorities | CLOSABLE (to SHIPPED caller-asserted, default silent; needs one additive `ValidationOptions` property, owner approval) | none by default; when asserted, an authority the caller did not declare fires, which is the point |

## The CLOSABLE points

**000034.1 and 000034.2 (rows 6, 7): a defect first, then a widening.** The shipped
correspondence (CT:105-115) reads "an alternate system in {LN, SCT, UCUM} requires a primary in
{LN, SCT, UCUM}". The point constrains only a pair of one public and one local terminology. Two
public systems are outside it, yet the rule fires on them: OBX-5 `E11.9^...^I10^44054006^...^SCT`
(ICD-10 primary, SNOMED CT alternate; both are rows of the ADRM's own Table 0396, pp 142-145) draws
a finding. That is a known misfire, so under requirement 4 it is a defect, not a residual. The
faithful rule detects the *local* side, which the ADRM prints: "99ZZZ or L" (p 144). Rule shape:
fire when the primary system (CE-3) is `L` or matches `99` followed by alphanumerics, and the
alternate system (CE-6) is a non-local row of the ADRM's printed Table 0396 (seeded on the AU
locale axis like 0074, 0200, 0203). OBX-3 for 000034.2; OBX-3 and coded OBX-5 for 000034.1; gate
`messageCode in (ORU, REF)` as today. Failing tests: (a) `I10` primary with `SCT` alternate is
silent (fails today); (b) `L` primary with `PBS` alternate fires (silent today, as PBS is not in
the named three); (c) `99ABC` primary with `LN` alternate keeps firing (it fires today). Residual after: a primary system
that is local but not spelt `L` or `99zzz` (the print says the format "should be 99zzz"), and
public systems outside the printed table, skip; the point stays PARTIAL with that smaller residual.

**000024.2 (row 4): no new model.** MSH-2 is read as one literal (P:335-337), so the REF leg is
`SegmentCardinalityRule(countedSegmentID: "MSH", scope: .messageWide, maxCount: 0, predicate:
"MSH-2 not startsWith ^", applicableWhen: "messageCode = REF")`. The FHS and BHS legs belong in
BV: `BatchFile.fileHeader` and `BatchGroup.header` are the raw segment strings, so the component
separator is the character after `FHS|` or `BHS|`. Failing tests: a REF with MSH-2 `#~\&` fires
(silent today); a REF with `^~\&` is silent; a batch of ORU whose BHS-2 starts with another
character fires. The same BV check closes the FHS and BHS legs of the SHIPPED 000024.1, .3, .4 and
.5, which are not enforced today (see owner items). The S2-2 test must also confirm the predicate
lexer accepts `^` as a value.

**00044.10.1.6 and 00044.11.1.6 (rows 14, 16): a register correction backed by a pin.** All 15
v2.4 Table 0291 values are keys of `subtypeToTypeMap`, so no 0291 subtype skips. Evidence: a test
that walks `HL7TableRegistry` v2.4 table 0291 and asserts every value is a map key, plus one RP
pair test (`RP` with subtype `PDF` and type `IM` fires; `AP` is silent), since RP has only a
dispatch pin today. Then the two rows read SHIPPED.

**000043.1 (row 8): HD-1 presence under the assertion.** The printed format begins with the
registered organisation name, so an asserted NASH MSH-4 with HD-1 empty is non-conformant whatever
the directory says. Rule: a `ComponentRequirement(component: 1)` on the MSH-4 HD override with
condition `auNASHTransport populated` (and on MSH-6 for 00044.2.1, whose presence half is the same).
Failing test: asserted, MSH-4 `^1.2.36.1.2001.1003.0.0000000000001001^ISO` fires (silent today).

**000001 (row 19): MSH-6 on an order.** Rule: MSH-6 populated when `messageCode = ORM`, cited
HL7au:000001. Failing test: an AU ORM^O01 with MSH-6 empty fires; ORU with MSH-6 empty stays silent.
The point then reads PARTIAL: 000001.1 is receiver behaviour, 000001.2 and .2.1 are "should".

**00104.7.1.4 (row 18): VDI for vendor authorities.** Rule: on REF, a PRD-7 repetition whose
PRD-7.2 is valued and is not one of the six printed 0363 values requires PRD-7.3 = `VDI`.
Failing tests: `JD455600041^Medical-Objects^VDI` silent; `JD455600041^Medical-Objects^UPIN`
fires (silent today). Expressible as a `ComponentCorrespondence` only if it gains a "key not in
set" form; otherwise a condition `PRD-7.2 not in (AUSHIC, AUSDVA, AUSNATA, AUSLINK, AUSHICPR, IHI)`
on a value set `[VDI]` for component 3. The point stays PARTIAL: AUSDVA, AUSNATA, AUSLINK and IHI
have no printed pair.

**00104.7.2.1 (row 26): caller-asserted 0363.** Shape: a new stored `ValidationOptions` property
(house style: not an init parameter) asserting a closed 0363, read with `localTableExtensions["0363"]`
as the caller's vendor authorities; condition `<assertion> populated AND messageCode = REF`. Failing
test: asserted with `["0363": ["Medical-Objects"]]`, `Argus` fires and `Medical-Objects` and
`AUSHICPR` are silent; unasserted, nothing fires. Needs owner approval (new public property).

**000008.1.5 (row 20): an in-group ordering rule.** The registered reason (HB 308) no longer holds:
the ADRM itself prints how to recognise both a display OBX (OBX-3.3 = `AUSPDI`) and a signature
OBX (OBX-3.1 starting `AUSETAV` with OBX-3.3 = `L`). No current rule shape expresses "nothing of
kind A after the first of kind B within a group": `previousSegment(OBX)` sees only the nearest OBX
and crosses group boundaries. New shape: an ordering rule over each `.obrObxGroup` span, gate
`messageCode in (ORU, REF)`: after the first OBX whose OBX-3.3 = `AUSPDI`, every later OBX in the
same group must be a display OBX or a signature OBX. Failing tests: atomic, display, atomic fires
once at the third OBX; atomic, display, signature is silent; group 1 ending in a display followed by
group 2 starting with an atomic OBX is silent. Pre-check done for this audit: no OBR/OBX example
printed in the ADRM places a non-display OBX after a display OBX on the same page; S2-2 must also
run the rule over every AU fixture.

## The plan's named questions

- **000020.** Neither a per-trigger variant nor a keyed rule helps: both select on MSH-9, and a
  `Z..` message code is by definition none of ORM, ORU or REF. `messageCode startsWith Z` is already
  expressible; the blocker is scope, not the model. An owner ruling could adopt the ungated reading
  (any message under `.auLocalisation`), at the risk named in row 2.
- **000008.1.5.** Yes: the display segment is identified from the message by the ADRM's own words
  (OBX-3 coding system `AUSPDI`, p 422 and p 247), and so is the signature OBX (p 438). OBX-2 ED/RP
  or a PDF payload is not the ADRM's test and should not be used. CLOSABLE as above.
- **00044.1.2 and 00044.1.3.** Both are SHIPPED rows, presence only (P:960-967). The .1.3 value set
  is enumerable from the ADRM: Table 0203 (p 301) is already seeded as `HL7CodeTables.table0203`
  and enforced on XCN-13 (00044.7.4, P:1049) and PRD-7.3; every CX-5 value in the ADRM's PID
  examples is in it. The HI service is not needed. CX-5 membership is simply not built (owner
  items). For .1.2 the 00044.2 sub-points are headed "for MSH-4, and MSH-6"; applying the NASH OID
  form to CX-4 would misfire on the ADRM's own `AUSHIC` and `AUSHICPR` authorities, and .2.1 needs
  the directory. Section B's row ("value-set dispatch against externally-maintained tables")
  should be corrected.
- **000024.2.** A first-character test on a literal already read whole; not a `Path` extension and
  not a different model. See the paragraph above.
- **000022.1 and 000022.3.** 000022.3 is SHIPPED (BV:111-122) and needs nothing. 000022.1's first
  half is as complete as the wire allows (BHS has no acknowledgement field); the second half is
  receiver behaviour. PARTIAL STAYS.
- **000043.1, 00044.3.1, 00044.7.1.** 000043.1 narrows (HD-1 presence). 00044.3.1's within-message
  leg already fires through 000028 on OBR-3; only the cross-message leg remains. 00044.7.1 needs
  identifier-scheme specifications the ADRM does not print.

## Summary

| Verdict | Count | Points |
|---|---|---|
| CLOSABLE | 10 | 000024.2, 00044.10.1.6, 00044.11.1.6, 000008.1.5, 00104.7.2.1 (to SHIPPED); 000001 (REGISTERED to PARTIAL); 000034.1, 000034.2, 000043.1, 00104.7.1.4 (narrow, stay PARTIAL) |
| PARTIAL STAYS | 11 | 000008.3.2, 000020, 000022.1, 000032.2, 00044.1.1, 00044.3.1, 00044.7.1, 00044.8.1, 00044.10.1.5, 00044.11.1.5, 00060.1 |
| REGISTERED STAYS | 5 | 000034.3, 00044.4.7, 00044.5.7, 00044.6.7, 00100.1 |

If S2-2 builds all ten, the register moves from 18 PARTIAL and 8 REGISTERED to 16 PARTIAL
(18, less 000024.2 and the two .6 rows, plus 000001) and 5 REGISTERED, with five more SHIPPED.
Four of the sixteen carry a smaller residual than today.

## Proposed S2-2 task list (ordered by value, then risk)

1. **000034.1 / 000034.2 defect fix and widening** (requirement 4: the shipped rule misfires on
   two public systems). Seed the ADRM Table 0396 (pp 142-145) on the AU locale axis; replace
   `publicInAlternateMap` with local-primary detection. Highest value, low risk once the seed is
   checked row by row against the print.
2. **000024.2 REF leg and the FHS/BHS legs of 000024.1 to .5** in BV. Small; no misfire found.
3. **00044.10.1.6 / 00044.11.1.6 pins** (registry walk over v2.4 0291, one RP pair test) and the
   register rows. Test-only.
4. **00044.1.3 CX-5 membership in AU 0203** (a SHIPPED row that enforces presence only; the same
   value set as 00044.7.4). Small; the ADRM's PID examples all pass.
5. **000043.1 / 00044.2.1 HD-1 presence** under `auNASHTransport`. Small; caller-asserted.
6. **000001 MSH-6 on ORM.** Small; register row REGISTERED to PARTIAL.
7. **000008.1.5 in-group ordering rule.** Medium: a new rule shape over `.obrObxGroup` spans; run
   over every AU fixture before it ships.
8. **00104.7.1.4 VDI rule.** Small to medium (a "key not in set" correspondence or a condition).
9. **00104.7.2.1 caller-asserted 0363.** Needs owner approval of one additive public property.
10. **Register text corrections** (no rule change): section B rows for 00044.5.7/.6.7 and
    00044.1.2/.1.3; section D rows for 00100.1 (OBR-4, not REF-4) and 000008.1.5 (the HB 308
    reason is superseded by p 438); the 00044.3.1 note credits 000028 for the within-message leg.

## Items for the owner

- **Defect:** the SHIPPED 000034.1/.2 correspondence fires on a pair of two public systems (row 6
  paragraph). Fix first.
- **SHIPPED rows that over-claim:** 000024.1, .3, .4, .5 name FHS and BHS, but only MSH-2 is
  checked; 00044.1.3 names Table 0203 membership, but only CX-5 presence is checked.
- **Register errors:** section B says 00044.5.7/.6.7 are "Removed" in r2; the print (pp 453-454)
  marks 00044.5.6 and 00044.6.6 Removed, and .5.7/.6.7 stand. Section D describes 00100.1 as
  "REF-4" ordering; the ADRM's test is the OBR-4 code (p 212).
- **Rulings wanted:** 000020 ungated message-code leg (row 2 risk); 00060.1 whether the p 280
  RXO/ODS/ODT replacement carries over to ORR^O02 and OSR^Q06; 00104.7.2.1 a new caller-asserted
  property.
- The test suite was not re-run for this stage: no source, test or resource file changed since
  `478e3ac1` (1730 tests in 146 suites).
