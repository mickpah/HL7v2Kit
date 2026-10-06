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
