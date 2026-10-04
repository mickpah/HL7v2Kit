# Permanent-limitations register — v0.17 (ROADMAP M2 close-out)

**Compiled:** 2026-07-09 (v0.17 cycle, ROADMAP M2 close-out).
**Purpose:** the single authoritative list of conformance rules HL7v2Kit **cannot** machine-check from the wire, with the reason and the v1.0 freeze decision for each. This closes ROADMAP **M2** — the conformance surface is now, in full, either *shipped* (validated) or *documented here as a permanent limitation with a spec-cited rationale* (req #2 / #3 / #4).

**Scope note:** these are **not defects**. Every entry falls into the fail-safe path (v0.2-V1: an absent/unresolvable predicate evaluates `false`, so the field is treated as optional and never wrongly flagged). A permanent limitation means "the spec states a constraint that no on-the-wire signal lets us decide" — not "we skipped it".

## A. Base-spec conditional-without-condition set

Fully audited in v0.16 and corrected by the P4 remediation (2026-10-01). See **`docs/design/conditional-completeness-audit.md`** for the per-field rationale, and its **Shipped in P4** table for every position that left this set. The v0.16 statement that none of the set is wire-decidable was wrong: the 2026-09 review (planning/reviews, X-C09) found predicates the DSL already expressed (for example OBR-22 on v2.8.2, PV2-45 on v2.6 and v2.8.2, the TXA, TQ2, SCH, AIx, MFE/MFA, LRL, OM7 and BPX/BTX families), prohibitions that were not modelled, and one shipped prohibition (PRT-7) keyed to the wrong field. P4 shipped those and added three model capabilities: `prohibitedSeverity` (warning-level prohibitions for SHOULD and "not applicable" text), the `noRepeat(...)` atom and the `nextSegmentID(...)` referent (ADR-010 amendment).

**Freeze decision:** position by position, not as a block. A `C` field stays bare only where the audit quotes that version's own text and the text names no wire-decidable trigger, or where the text contradicts itself (PV2-1 on v2.3 and v2.3.1). Guard tests pin the bare set on all six versions: `BareConditionalGuardTests` for v2.3, v2.3.1, v2.4, v2.5.1 and v2.6 (P4-15), `MultiVersionTests.v282M2PermanentLimitationsGuard` for v2.8.2 (v0.16). v2.7.1 (P10) is pinned by `BareConditionalGuardTests.v271BareC`: the CH04, CH04A, CH07, CH13, OM7 and PRC positions are audited (P10-5a, `conditional-completeness-audit.md` "v2.7.1 (P10-5a)"); every other chapter's positions are audited in "v2.7.1 (P10-5b)", so all 177 v2.7.1 `C` positions are either a cited rule or a cited bare entry. Any new DSL capability reopens the set for re-audit.

### Addendum to §A — prose-backed `C` over printed `O`, OBR-29/ORC-8 on v2.3 to v2.5.1 (P4-18)

On v2.3, v2.3.1, v2.4 and v2.5.1, ORC-8 and OBR-29 print `O` in the CH04 attribute table, but
the schemas model them `C` with the child-order predicate (P1-4/P4-7; v2.6 shipped the same
deviation in P4-6, `docs/design/conditional-completeness-audit.md` "Prose-backed `C` over a
printed `O` (P1-5)"). Each field's own definition text states the condition: v2.3/v2.3.1 OBR-29
§4.5.1.29 and v2.4/v2.5.1 OBR-29 §4.5.3.29, "It is required when the order is a child"; v2.4/
v2.5.1 ORC-8 §4.5.1.8, "If the parent is not present in the ORC, it must be present in the
associated OBR"; v2.3/v2.3.1 ORC-8's own definition (§4.3.1.8) carries no condition sentence,
so the same rule is cited from §4.3.1.1.1 "i) PA, CH": "Whenever a child order is transmitted
in a message the ORC segment's ORC-8-parent is valued with the parent's filler order number...
and with the parent's placer order number." `scripts/audit-schemas.py` whitelists all eight
positions with these citations (`OPTIONALITY_WHITELIST`) so the audit does not re-flag them.

**Why `C` and not the printed `O`:** the Validator only evaluates a `condition` on a field
modelled `optionality: C` (the `.conditional` branch of the condition check); a `C` field with
no condition, or an `O` field, never evaluates one. Printing `O` here would silently drop the
parent/child rule these four versions' own prose requires. The alternative — letting a condition
fire on a printed-`O` field — would need a model extension (the next free ADR number, ADR-021,
per `global-constraints.md`); out of scope for this task.

**Known limitation (req #3), not currently blocking:** the deviation is deliberate and cited,
matching the v2.6 precedent already shipped; it is recorded here so the modelled optionality is
never mistaken for a transcription error against the printed table.

### Addendum to §A — printed `R` restricted by its own definition (P4-30)

P4-30 (2026-10-01) models three printed-`R` fields as `C` because their definitions limit them,
each citing the spec in the schema field's `optionalityCitation` (which `scripts/audit-schemas.py`
reads as the slot's optionality whitelist entry): MFI-6 `messageCode = MFN`, CSR-8
`triggerEvent = C01` (all six versions), and ROL-4 `STF absent` (v2.6, v2.8.2). RXA-4 stays `R`
(its "If null" is the HL7 null `""`). Rows and evidence: `conditional-completeness-audit.md`.
v2.7.1 (P10-5a): CSR-8 prints `R` with the same definition (CH07 §7.7.1.8, p. 96) and is
modelled `C`, `triggerEvent = C01`, likewise; RXA-4 prints `R` with the same "If null" sentence
(CH04A §4A.4.7.4, p. 89) and stays `R`. v2.7.1 (P10-5b): MFI-6 prints `R` (CH08 table, p. 7)
with the same "Required for MFN-Master File Notification message" (§8.5.1.6, p. 8) and ROL-4
prints `R` (CH15 table, p. 32) with the same "If both STF and ROL are present in the same
message, populating this field is optional" (§15.4.7.4, p. 34); both are modelled `C` as on
v2.6 and v2.8.2. The v2.7.1 ROL-4 definition carries the same "same values as the correlated
field" sentence, so the limitation below applies to v2.7.1 too.

**Known limitation (req #3), blocks spec-completeness:** the v2.6 and v2.8.2 ROL-4 definition
(CH15 §15.4.7.4) continues: "If this field is populated, then it must be populated with the same
values as the correlated field", the correlated fields being STF-2 Staff Identifier List and
STF-3 Staff Name. That is a cross-segment value equality between ROL-4 (XCN) and two STF fields
of different types (CX and XPN); the condition DSL compares a field with literals, not with
another segment's composite value, so the rule is not enforced. Closing it needs a model
extension (cross-segment composite comparison).

### Addendum to §A — blank OPT prints read as optional (P6-12)

P6-12 (2026-10-02) found 150 attribute-table rows whose OPT cell the spec prints blank: NST and
NSC (v2.3.1 Appendix C, v2.4 to v2.6 CH14), the v2.6 CH17 sterilisation segments (SCD, SCP, SDD,
SLT, STZ) and PKG-4, v2.4 EDU-2, v2.3 AIG-2, RCP-7 (v2.4 to v2.6) and the v2.5.1 OBX-20 to 22
rows "Reserved for harmonization with V2.6". The schemas store the blank verbatim (`""`), and
each region is cited in `UNREADABLE_WHITELIST` in `scripts/audit-schemas.py`, which checks the
stored blank against the print.

**Known limitation (req #3), blocks spec-completeness:** the spec defines no blank code. v2.6
§2.5.3.4 lists R, O, C, X, B and W only, and its Note says the optionality of fields "should be
explicitly documented in the segment field definitions that follow each segment definition
table"; these field definitions do not do so. The validator therefore treats a blank-OPT field
as optional (the codegen maps an unknown code to `.optional`): it never reports one missing,
and it does not flag a populated reserved OBX-20 to 22 in v2.5.1. That is a modelling choice,
not a spec reading. Closing it needs the spec (or an HL7 errata) to give these rows a code.

**v2.7.1 (P10-4a to P10-4c, 2026-10-03):** 87 v2.7.1 fields in 11 segments print a blank OPT
cell: NST (14), NSC (8), SCD (37), SCP (8), SDD (7), SLT (5), STZ (4), PKG (1), RCP-7, ACC-12
and STF-41. Each region is cited in `UNREADABLE_WHITELIST`. v2.7.1 §2.5.3.5 lists the same six
codes and the same Note, so the limitation applies to v2.7.1 unchanged.

## B. AU-localisation (ADRM 2021) narrowings

The machine-checkable HL7au:00044.* CE/CNE/CWE narrowings shipped in v0.13 (ADR-011). The following AU rules are **not** machine-checkable from the wire:

| Rule | What it requires | Why it can't ship | Freeze decision |
|------|------------------|-------------------|-----------------|
| ~~**HL7au:00044.4.3** (CE `<text>`)~~ **SHIPPED caller-asserted (M30, 2026-09-23):** `ValidationOptions.auDisplayIntended = true` applies it; the blank-allowed locations are still not wire-signalled, so the default stays silent. | CE-2 text must be valued | The spec carries an explicit "*in some locations user display is not intended and the text may be blank*" carve-out. An unconditional required-CE-2 rule would over-fire on the blank-allowed locations, and those locations are not wire-signalled. Shipping it would violate req #4 ("no predicate ships if known-incorrect"). | **Permanent** unless a future spec revision adds a wire signal for the blank-allowed locations. |
| **HL7au:00044.4.7** (CE concept-match) | CE identifier and alternate identifier must reflect the *same concept* | Requires a terminology service to compare concepts across code systems; not derivable from the wire. Out of the portable-core boundary (ADR-006). | **Permanent** (a terminology-service hook would be a post-1.0, out-of-core module). |
| **HL7au:00044.5.7 / 00044.6.7** (CNE/CWE concept-match) | as .4.7, for CNE/CWE | Marked **"Removed"** in ADRM r2 — not applicable. | **N/A** (withdrawn by the profile). |
| **HL7au:00044.2** (HD / NASH) — **PARTLY SHIPPED (M32, 2026-09-23)** | The family's sub-points on MSH-4 / MSH-6 | **.2.2 and .2.3 now ship caller-asserted** (`ValidationOptions.auNASHTransport = true`): the Universal ID must be `1.2.36.1.2001.1003.0.` + a 16-digit HPI-O (width from HL7au:000043.1), and the Universal ID Type must be `ISO`. All 8 OID values the ADRM prints honour it. **Still out:** `.2.1` and `00044.3.2` name the organisation "as registered in the Medicare Australia HPOS/HI service" (needs the HI directory); `.2.4` and the ADRM's second `00044.3.4` compare against a vendor X.509 certificate; `00043.2` is an anti-spoofing check the ADRM marks *"applies only to SMD Agent implementers … before handing off a the message to the receiving system"*. **The EI twins `00044.3.3` / `.3.4` ship too (M33, 2026-09-23)**, datatype-wide as the ADRM's "EI datatype conformance points" grouper states: the sentence constrains the *shape* of the universal ID, not whose HPI-O it is, so an identifier echoed from another organisation satisfies it unchanged. They allow an empty universal ID, because HL7au:000006 / 000007 already require all four EI components on the five AU EI fields. | **Permanent for the directory and certificate halves.** |
| **HL7au:00044.1.2 / .1.3** (NASH sub-points / value-set membership) | NASH-specific formats / value-set membership | Runtime/PKI-dependent or require value-set dispatch against externally-maintained tables. | **Deferred**; re-audit if a value-set-dispatch mechanism lands. |
| **HL7au:000001** (Order addressing / MSH-6 Receiving Facility) | 4 sub-rules on order addressing | Each sub-rule is either **receiver-runtime semantics** (what the receiver must *do*, not what the message must *contain*), **soft "should" guidance** (not a MUST), or points to the PKI-deferred 00044.2. None is a wire-checkable MUST. | **Permanent** (runtime/soft-guidance, not a schema constraint). |
| ~~**HL7au:00050.1.5** (OBX-6.3 = "UCUM")~~ **SHIPPED caller-asserted (M29, 2026-09-23):** `ValidationOptions.auPathologySender = true` applies it; the wire still carries no discriminator, so the default stays silent. | OBX-6 name-of-coding-system must be "UCUM" — scoped **"Senders (Pathology only)", Results** (Appendix 5 p. 465) | "Pathology sender" has no message-decidable discriminator: ADRM-2021 defines no pathology subset of HL7 table 0074 (OBR-24 mixes pathology and imaging disciplines), and no other wire signal identifies the sender's discipline. A bare `messageCode = ORU` gate would over-fire on spec-compliant imaging results (req #4); inventing an OBR-24 subset would not be defensible against spec text (req #2). M6-A stage 3, 2026-09-15. | **Permanent** unless a future ADRM revision adds a wire-decidable pathology discriminator. |

## C. Terminology / external-state limitations (cross-cutting)

- **Code-system-aware value checks** — any rule of the form "value X must belong to code system Y" or "concept A ≡ concept B" needs a terminology service; the validator checks structure and (where the profile enumerates them) literal value sets, not semantic equivalence. This bounds the AU 00044.4.4 LOINC-placement rule (shipped v0.13 as a **partial** necessary condition) and 00044.4.7 above. Base-spec instance (P4-17, see `conditional-completeness-audit.md` "Order/pharmacy & timing family"): RXE-11, RXD-5, RXG-33 and RXC-11's "required if the units are not implied by the actual dispense code" — whether a dispense code implies its own units is exactly this class of gap, not a peer-field value.
- **PKI / certificate validation** — NASH and similar require live certificate infrastructure; out of the portable-core boundary (ADR-006). M32 shipped the *format* half of the NASH addressing points on the caller's assertion; the certificate comparison itself stays out.
- **Cross-message / patient-history state** — rules like OBR-48 "duplicate procedure" need history beyond the current message.
- **Composite-component table links** — shipped on all seven versions (ADR-017): from the printed component tables of v2.5.1 / v2.6 / v2.8.2 (`v3.4.0`) and v2.7.1 (P10-2: 72 composites, 469 components, 151 bound to a table), with nested composites and OBX-5 (M11), and from the numbered prose subsections of v2.3 / v2.3.1 / v2.4 under a three-test evidence rule (M13). **Closed since:** the 39 rejected prose mentions were read one by one and found unbindable (M24, `v3.7.3`); printed `R` components are enforced (M14 to M16), `C` components where the prose states a sibling-presence or repetition condition (M26, M28), and the 32 "as of v2.7" conditions are opt-in (M27). **Still registered:** component length (recorded, never enforced, M25); CWE.7 and kin (a value-pattern term plus table-type lookup, and the spec's own examples violate it); CNE.20 (self-contradictory sentence). See `Resources/datatypes/conditions.json`. v2.7.1 (P10-2): its component tables are extracted and generated (72 composites) with the same conditions, cited to its own sentences; its bare positions are in the §D addendum. They are reachable through `Version.v2_7_1` (and `2.7`, substituted) since P10-6; its 30 conformance conditions are opt-in (`conformanceConditionSeverity`) as on v2.8.2.
- **Table 0203 `NNxxx` is a shape check, not an ISO 3166 lookup** — the pattern row (P2-6, v2.3.1 to v2.8.2) is modelled as `HL7Table.CodePattern` regex `^NN[A-Z]{3}$`: `NN` plus any three uppercase letters. The spec's own prose narrows the last three letters to an ISO 3166 alpha-3 country code, which needs a code-system membership check (the same class of gap as the first §C bullet); the registry does not carry ISO 3166's value set, so `NNZZZ` passes structurally even though `ZZZ` is not a country code. A false negative (an invalid country code let through), never a false positive against a genuine `NNxxx` value — acceptable under the fail-safe-on-openness principle, but a known bound, not a gap to silently paper over.
- **Undeclared local extensions to a closed HL7 table are errors by default** (owner ruling G5, P2-13). Every supported version lets a site extend an HL7 table locally (v2.3 / v2.3.1 CH2 sec 2.6.6, "Additions may be included on a site-specific basis"; v2.4 CH02 sec 2.7.6 and v2.5.1 / v2.6 CH02 sec 2.5.3.6, "the table itself may be extended to accommodate locally defined values"; v2.7.1 CH02C 2.C.1.2, p. 8; v2.8.2 CH02C 2.C.1.2), but a site's additions are not on the wire and the validator cannot know them. A spec-compliant, locally extended code in a closed table is therefore reported as `valueNotInTable` unless the caller declares it through `ValidationOptions.localTableExtensions`. This is a deliberate default (tables closed, extensions caller-asserted), not a misfire the model cannot avoid.
- **HL7 tables whose governing fields disagree on openness: modelled, no longer a limitation** (P2 fix wave, closed by P2-15; ADR-016). Some tables are cited "for suggested values" (or "User-defined", or "can be extended") by one field and "for valid values" by another. The table keeps its printed kind, and each field whose own prose opens it carries `"tableOpen": true` plus a quoted `tableOpenCitation` in its schema entry, generated as `FieldGrammar.tableOpen`; the closed-table check skips that field only. 49 fields are marked; the 19 scalar `ID` ones (0136, 0167 RXD-11, 0532 PSL-21) change what the Validator reports, the rest are `IS` or composite and correct the metadata. Kept here as a record of what is modelled. The tables, with the quoted prose:
  - **0136 Yes/no indicator** (v2.4, v2.6, v2.7.1, v2.8.2). Suggested: v2.4 PID-31 "Refer to HL7 Table 0136 - Yes/no indicator for suggested values"; v2.6, v2.7.1 and v2.8.2 DG1-24, RFI-3, IVC-13, PSG-4, PSL-47 "... for suggested values" (v2.6 PSG-4 prints "HL7-Table0136", which the P2 fix-wave scan missed; P2-15 read it and marked it). All marked `tableOpen`. Valid: every other citing field, e.g. PID-24 "Refer to HL7 Table 0136 - Yes/no indicator for valid values". v2.3, v2.3.1 and v2.5.1 cite it only "for valid values" and are closed under the criterion.
  - **0167 Substitution status** (every version). RXD-11 "Refer to HL7 Table 0167 - Substitution Status for suggested values"; RXE-9 and RXG-10 "... for valid values". RXD-11 marked on all seven versions.
  - **0185 Preferred method of contact** (every version). PRD-6 and CTD-6 (and PRD-14 from v2.6) "Refer to User-defined Table 0185 - Preferred method of contact for suggested values"; STF-16 "Refer to HL7 Table 0185 - Preferred method of contact for valid values". PRD-6, CTD-6 and PRD-14 marked (CE/CWE: metadata only).
  - **0206 Segment action code** (v2.6, v2.7.1, v2.8.2). IAM-6 and ARV-2 "Refer to HL7 Table 0206 - Segment Action Code for suggested values"; RXA-21, DG1-21, PR1-20, LCH-2, LRL-2 and (v2.8.2) RXV-22, CDO-2, IN1-55, OMC-2, RGS-2, AIS-2, AIG-2, AIL-2, AIP-2, RF1-25, AUT-29 "... for valid values". IAM-6 and ARV-2 marked (CNE: metadata only).
  - **0239 Event expected** (v2.3). PCR-2, PCR-9, PCR-11, PCR-13 "Refer to user-defined table 0239 - Event expected for suggested values"; PEO-10 "Refer to HL7 table 0239 - Event expected for valid values". The PCR fields are `IS` and never enforced; they are marked for metadata fidelity, and PEO-10 stays checked.
  - **0323 Action code** (v2.4, v2.5.1). IAM-6 "Refer to HL7 Table 0323 - Action code for suggested values"; RXA-21 "Refer to HL7 Table 0323 - Action code for valid values". IAM-6 marked (CNE: metadata only).
  - **0371 Additive** (v2.5.1, v2.6, v2.7.1, v2.8.2; P2-14). OM4-7 and SAC-27 "Refer to HL7 Table 0371 - Additive for valid values. ... The value set can be extended with user specific values."; SPM-6 "Refer to HL7 Table 0371 - Additive for valid values." only, no extension clause. (v2.4, where SPM does not exist and OM4-7/SAC-27 are the only citing fields, is opened, not mixed.) All three fields are CE/CWE, whose identifier component is `ST` rather than `ID` (ADR-016: composite `tables` bindings are recorded but not enforced), so the table is not currently wire-enforced either way; the mixed reading fixes the registry metadata, not a live misfire. OM4-7 and SAC-27 marked; SPM-6 is not.
  - **0532 Expanded yes/no indicator** (v2.6, v2.7.1, v2.8.2). PSL-21 "Refer to User-defined Table 0532 - Expanded Yes/No Indicator for suggested values"; ITM-6, ITM-11, IVT-11, SCD-19 and the other Chapter 17 indicators "Refer to HL7 Table 0532 - Expanded yes/no indicator table ... for valid values". PSL-21 marked; it is the only `ID` field bound to 0532 on v2.6, v2.7.1 and v2.8.2, so no field enforces 0532 there now.

- **Field length, registered edges (P6-6)** — (1) A v2.8.2 range printed against a composite field (PRT-1 EI `1..4`, QRI-2 CWE `2..2`, OM1-18 CWE `1..1`, RXG-13 CWE `1..250`) is not enforced: v2.8.2 section 2.5.5.0 "Normative lengths are only specified for primitive data types", so the cell has no whole-field meaning. (2) The 38 bare-integer v2.8.2 LEN / C.LEN cells (AUT-13 to AUT-29, RF1-13 to RF1-25, DSP-3 to DSP-5, SGH-1, SGT-1, IN1-55, OM1-51, TCC-15) are in neither normative form and are read as conformance lengths, as are the `n=` / `n#` cells (section 2.5.5.3); none is checked. (3) v2.8.2 TQ2-6 prints `2..` with no upper bound; it is checked as a minimum only. (4) The pre-v2.7 `64K` / `10K` cells (v2.3, v2.3.1; CON in v2.5.1 and v2.6), the variable-length `*` (OBX-5, every version), and the v2.4 to v2.6 symbols 65536 ("the notion of a Very Large Number", which replaced `64K`) and 99999 (a length that "cannot be definitively expressed because the data type for the field is variable"; v2.4 section 2.7.2, v2.5.1 and v2.6 section 2.5.3.2 b and c) are not checked: none is a limit, and the spec does not say whether `K` is 1000 or 1024 characters. (5) Component-level length is not checked on any version. (6) Spec-internal conflicts, corrected under owner ruling G10: where a pre-v2.7 LEN cell is shorter than values its own spec defines as valid, the schema stores the smallest length that admits them, with a cited `LENGTH_WHITELIST` entry in `scripts/audit-schemas.py`. v2.3 MSH-18 6 to 10 (Table 0211 `JIS X 0202`); OBX-2 2 to 3 on v2.3, v2.4 and v2.5.1, and OM3-7 2 to 3 on v2.4 and v2.5.1 (Table 0125 three-letter codes); MSH-9 7 to 15 on v2.3.1 and 13 to 15 on v2.4 (three components: Tables 0076 and 0003 at 3, Table 0354 at 7, two separators; v2.3.1's printed `SIIU_S12` is a misprint of `SIU_S12` and not counted); PEO-25 1 to 2 on every pre-v2.7 version (Table 0243 `NA`); TXA-3 2 to 11 on v2.3.1 (Table 0191 `Application`, section 2.8.36) and 2 to 9 on v2.4, v2.5.1 and v2.6 (`multipart`); v2.6 PSL-21 2 to 4 (Table 0532 `ASKU`). `FieldLengthSpecConflictTests` guards the class: every pre-v2.7 ID or IS field bound to an HL7 table, and every field whose composite has only HL7-table-bound ID components, must admit its longest valid value. v2.3 to v2.4 define MSH-9 in field prose with no component table, so those rows are pinned by hand, not by the guard. (7) Escape sequences are measured as v2.8.2 section 2.7 prescribes (the characters between the escape delimiters count, the delimiters do not); the pre-v2.7 texts are silent, so the same rule applies. Values are stored decoded, so the measure uses the canonical re-encoding: a non-canonical wire escape such as `\X41\` for `A` counts as 1, not 3.

- **Primitive formats not checked (P6-7)** — ID and IS (no lexical rule beyond non-empty, which "populated" already guarantees), and the character-set rules of ST, TX and FT. Time-zone offsets are checked for shape (`+/-ZZZZ`), not against the legally defined zones the note in v2.5.1 section 2.A.22 restricts them to. A second at `60` is admitted (the sections print no seconds range). Components nested two levels deep are out of reach of the one-level descent, and none in the v2 grammars carries a primitive rule there. The format check reads the first value, as a recipient does (section 2.6.2 a); content after it is reported as `extraComponentsInPrimitiveField` for every primitive (P6-14).

- **SI's lenient NM reading (P6-7, review carry-in)** — SI is defined as "a non-negative integer in the form of a NM field" (v2.5.1 §2.A.69 and equivalents). The NM form is read for its numeric value, not re-parsed as a bare non-negative integer, so `1.0`, `-0` and `+5` are all accepted: each is, by that reading, a non-negative integer. Spec-faithful under the printed cross-reference, not a defect; recorded in case a future version narrows the SI grammar beyond "in the form of a NM field".

- **Composite width checked only where a component table exists (P6-15; narrowed by P5)** — `extraComponentsInCompositeField` measures a repetition against its datatype's component table in `Resources/datatypes/`, or, for a pre-v2.5 field whose own printed Components line or CH04 section defines a field-local grammar, against `DataTypeGrammarTable.grammar(segment:field:version:)` (ADR-017 P5 addendum). That closes v2.3 to v2.4 TQ (CH04 section 4.3 / 4.4, not CH02) and every field-level `CM` composite the schemas used to name EIP, MOC, MSG, NDL, PRL, SPS (and PTS, SVC on v2.3): EIP, MOC, MSG and PRL (ORC-8/OBR-29, OBR-23, MSH-9, OBR-26) reuse the identical-structure v2.5-era name and its table (`CM_REFINEMENTS` in `audit-schemas.py`); OBR-15 and OBR-32 to OBR-35 are typed `CM`, as printed, and checked through their own field grammar, replacing the misdescribed `SPS`/`NDL` schema names (P5-7); APR-1/2/3/5 (`SVC`) and TXA-22 (`PTS`) on v2.3 are checked the same way. **Still unchecked:** OM2-6 on v2.3 to v2.4 (`CM`, no field-local grammar yet — see the ADR-017 addendum). (No v2.8.2 field is typed with the withdrawn CE, TQ, ELD or SPS since P10-4d: those were all W fields, now untyped, see the next entry.) A composite component the table prints with no datatype (v2.6 CE.1 to CE.6, TS.1 / TS.2 and XTN.1; v2.8.2 withdrawn components such as XPN.6, XPN.10 and XON.3 to XON.5) is not checked for subcomponents. NA and MA are open-ended by definition (NA's tables end in an ellipsis; MA's prose separates "channels within a sample" by component delimiters, and its v2.6 / v2.8.2 tables end in an ellipsis, though the v2.5.1 table lists six rows), so they are never width-checked; that is the spec, not a gap. OM2-6 blocks spec-completeness until each gets its own field-local or datatype-level grammar.

- **Withdrawn (W) fields carry exactly the data type their attribute table prints (P10-4c, P10-4d)** — A W field carries exactly the data type its attribute table prints, and nothing is carried from an earlier version. Chapter 2 section 2.8.4 (v2.7.1 p. 24; v2.8.2 p. 26) is cited only for the fact that a withdrawn field stays listed in its segment with its narrative removed: a deprecated field "will be marked as withdrawn and all explanatory narrative will be removed". The v2.7.1 and v2.8.2 attribute tables print the DT cell of every W field blank except UB1-1, which both print `SI` (Chapter 6 section 6.5.10; v2.7.1 p. 130, v2.8.2 p. 124). So 76 of v2.7.1's 77 W fields and 80 of v2.8.2's 81 are untyped, and UB1-1 keeps SI. P10-4d removed from v2.8.2 the 30 types it had carried from earlier versions (AL1-6, DG1-2, DG1-4, DG1-7 to DG1-14, ERR-1, EVN-1, MSA-3, MSA-5, MSA-6, OBR-5, OBR-6, OBR-14, OBR-15, OBR-27, ORC-7, PD1-4, PID-2, PID-4, PID-9, PID-12, PID-19, PID-20, PID-28). `audit-schemas.py` holds both versions to the rule (`WITHDRAWN_TYPED_AS_PRINTED`; integrity and `--depth`). Validation: a populated W field raises the `fieldNotSupported` warning "was withdrawn from the standard (W) but populated" (`warnDeprecatedFields`, on by default). A W field prints no LEN, and the primitive-format, extra-component, composite-width and component-table checks key on the data type, so an untyped W field gets none of them and nothing fires against a type the version does not define. An untyped field is not a defining entry of the version union (ADR-020), so the rule changes generated DocC version lists only: no accessor is added, removed or retyped. Every version from v2.5.1 up is held to the rule. v2.6 (Chapter 2 section 2.8.4, p. 22) prints the DT cell blank for all eleven of its W fields (DG1-2, DG1-4, DG1-7 to DG1-14: Chapter 6 section 6.5.2, pp. 19 to 20; MSA-5: Chapter 2 section 2.14.8, p. 53), so P10-4d removed the types they had carried. v2.5.1 MSA-5 keeps ID because the released accessor binds it; the print's DT cell is blank (Chapter 2 section 2.15.8, p. 73). It is the one registered exception (`WITHDRAWN_TYPE_EXCEPTIONS`; ADR-014 forbids retyping `MSA.delayedAcknowledgmentType`), so a populated v2.5.1 MSA-5 still receives the checks keyed on its ID type. v2.3, v2.3.1 and v2.4 model no W field, so the rule does not apply to them.

- **No per-datatype local Z-extension declaration (P6-15 review)** — "Data types may be locally extended by adding new components at the end. This action creates a Z data type" (section 2.11.5 c). There is no way to declare such an extension for one datatype; only the global `extraComponentsSeverity` governs `extraComponentsInCompositeField`. Revisit only if an integrator asks for it.

- **TQ.6 Priority repeats through the repeat delimiter on v2.3 and v2.3.1 (P5-3; P5 final review; v2.3 and v2.3.1 section 4.4.6)** — the Priority component may repeat, and on v2.3 and v2.3.1 it repeats with the repeat delimiter inside the one TQ occurrence (`1^Q6H^^200001011200^^S~A^^^S`). v2.4 section 4.3.6 separates repeated priorities with a space, so v2.4 on is unaffected. The parser gives the repeat delimiter one meaning, a new field repetition. Handling: on v2.3 and v2.3.1, for a field typed `TQ` whose grammar is single-repeat (ORC-7, RXE-1, RXG-3, GOL-15, QRF-9 and URS-9), repetitions 2 to n are read as the priority's continuation: no `cardinalityExceeded`, and no component, format, length, table or extra-component check runs on them. Repetition 1 is validated as usual (`Validator.priorityContinuationTrimmed`). **Known limit (false negative):** on those versions a genuinely wrong second repetition of such a field goes unreported, because the parse cannot tell it from a priority continuation. A field typed `TQ` that may repeat (OBR-27 and SCH-11 on v2.3 and v2.3.1) keeps its ordinary repetition reading, so a priority continuation there is checked as a TQ repetition of its own. **Known limitation that blocks spec-completeness:** the repeating TQ fields (OBR-27 and SCH-11 on v2.3 and v2.3.1) cannot be resolved by the delimiters alone, because a priority continuation is indistinguishable from a genuine TQ repetition. The spec created the ambiguity (the repeat delimiter carries both meanings) and removed it in v2.4, where section 4.3.6 separates repeated priorities with a space. Closing it needs the model to carry a field-aware reading of the repeat delimiter, so it stays open until then.

- **Segment-presence audit coverage is caption-based and whitelist-scoped (P6-3)** — `audit-schemas.py`'s presence pass confirms a `DEPTH_WHITELIST` segment exists by matching its attribute-table caption, because that segment's own `1-n`-style SEQ row does not parse positionally (the gap P6-3 closed for ADD). The check only runs for segments already on `DEPTH_WHITELIST`; a future segment whose attribute table prints an equally unparseable row, and that is not added to the whitelist, would vanish from the audit the same way ADD did before P6-3 — silently, with no finding. Not a defect in a shipped predicate: a bound on the audit tool's own reach, recorded so adding a segment with this row shape also means adding it to `DEPTH_WHITELIST`.

**Freeze decision (B + C):** acceptable to freeze for v1.0. The mixed-tables bullet above no longer blocks spec-completeness: P2-15 modelled it with per-field openness. Every other B/C entry is a honest, spec-cited gap, not a defect; each would require an out-of-core runtime integration (terminology service, PKI) that is explicitly **post-1.0** (see ROADMAP "Post-1.0 sketch"). Shipping any as an unconditional rule would misfire, violating req #4.

## D. M6-B — ADRM-2021 points awaiting model capabilities (deferred, blocks spec-completeness)

Added at M6 close (2026-09-16) as the EXTEND remainder of the ADRM-2021 Appendix 5
register; **drained by M6-B-4 through M6-B-9** (same date). Each row below records its
outcome: shipped, shipped-PARTIAL with the unenforced half stated in the conformance
register, or registered with the citation-backed reason no faithful rule can exist (see
`m6-adrm-2021-conformance-register.md` for per-point text).

| Capability | Points (HL7au:) | What it needs |
|------------|-----------------|---------------|
| **HL7 code-table registry (M6-O6)** — shipped 2026-09-20 (ADR-016): per-version registry with descriptions, generated Swift, `valueNotInTable` on ID fields over closed tables, locale axis. Seeded M6-B-4/5, 2026-09-16. | ~~`000032`, `000032.2`, `00104.7.2.1`, `00104.7.3.1`, `00044.7.3`, `00044.7.4`~~ all shipped: the `HL7CodeTables` seed (tables 0074/0200/0203/0363, hand-verified against the ADRM's printed renderings) plus the M6-B-5 composite value-set track (populated-only allow lists on `CompositeOverride`) | **Remaining:** the general per-version registry only — the seed holds just the tables shipped points consume, values-only, with no descriptions and no codegen. Grow it when a new point needs a new table. |
| **OBX-2-driven datatype resolution (M6-O7)** — done, shipped (M6-B-7, 2026-09-16) | ~~`00044.10.1.1`–`.1.4` (ED), `00044.11.1.1`–`.1.4` (RP)~~ all shipped: the composite-override dispatch resolves OBX-5's effective datatype from the sibling OBX-2 value | Nothing remaining for these points. The general capability stays OBX-5-specific by design — no other field's type varies at runtime. |
| **Value-correspondence maps** — done, shipped (M6-B-8, 2026-09-16) | ~~`00044.10.1.5`/`.6`, `00044.11.1.5`/`.6`, `000008.1.3`, `00104.7.1.4`~~ all shipped (PARTIAL where the ADRM leaves the pair set open) via `ComponentCorrespondence` on both override tracks | **Remaining:** only the open ends noted per row in the register — unstated IANA subtypes and open-ended vendor authorities skip, fail-safe (req #4). |
| **Within-message uniqueness** — done, shipped (M6-B-9, 2026-09-16) | ~~`000028`, `000028.2`~~ shipped via `FieldUniquenessRule` (message-wide OBR-3.1 duplicate detection, ORU- and REF-gated legs) | Nothing remaining. |
| **Intra-message ordering** — registered (M6-B-9, 2026-09-16) | `00100.1` (REF-4 referral-priority ordering "according to the SNOMED CT hierarchy"), `000008.1.5` (display-segment signature ordering per **HB 308-2011**) | `00100.1` needs SNOMED CT subsumption — a terminology server, §C territory, not a DSL gap. `000008.1.5`'s normative content (which identifiers mark a signature block) lives in HB 308-2011, an external Standards Australia handbook the ADRM does not reproduce; a rule would not be defensible against the ADRM text alone (req #2). **Permanent** unless a future revision inlines the handbook's identifier list. |
| **Coding-system precedence** — done, shipped for named public systems (M6-B-9, 2026-09-16) | ~~`000034.1`, `000034.2`~~ shipped PARTIAL: a public system the ADRM names (LN, SCT, UCUM — `HL7CodeTables.publicCodingSystems`) appearing in the CE/CWE alternate triplet behind a non-public primary fires; unnamed systems skip, fail-safe. `000034.3` registered | `000034.3` ("the alternate must be a translation of the same concept") is a terminology-equivalence judgement, §C territory — same reasoning as the registered `00044.4.7`/`.5.7` and their CWE twin `00044.6.7` (also registered at M6-B-9). |
| **Relational group cardinality** — done, shipped, structural half (M6-B-9, 2026-09-16) | ~~`000008.3.2`~~ shipped PARTIAL via `SegmentCardinalityRule.activationPredicate`: RTF display present in an OBR group without an HTML/PDF/TXT sibling fires (L2 Referrals gate) | **Remaining:** the "same content" equality half — comparing rendered RTF against rendered HTML/PDF/TXT is not machine-checkable; permanent, same class as `000008.2`. |
| **TS timezone offset** — done, shipped, presence half (M6-B-9, 2026-09-16) | ~~`00044.8.1`~~ shipped PARTIAL via `CompositeOverride.timezoneRequiredCitation`: a TS with hour-or-greater precision and no `+`/`-ZZZZ` suffix fires on Orders/Results/Referrals | **Remaining:** verifying the offset is *correct* for the stated local time needs a timezone database and the sender's location — out of scope by nature. |
| **Batch-scope rules** — done, shipped via `BatchValidator` (M8-C, 2026-09-17) | ~~`000022.1`, `000022.3`~~ — `BatchValidator` over `BatchParser` output landed: `000022.3` SHIPPED (a REF alongside any other message in one batch group fires); `000022.1` PARTIAL (the individual-acknowledgement mode lives in each contained message's MSH-15/16, which the per-message AU rules enforce on every batched message; the "no information from batch segments used" half is receiver behaviour). Also shipped there: the single-batch-per-file prose rule (`ADRM-prose:P-7`, p. 19). | Nothing remaining for these points. |

**Freeze decision (M6-B-9 close, 2026-09-16): §D is drained.** Every capability row is
now shipped, shipped-PARTIAL with the unenforced half stated, or registered with a
citation-backed reason no faithful rule can exist. The EXTEND class of the ADRM register
is empty; nothing awaits a model extension. *(Historical note, M6-B-6: the "MSH-21
profile-ID addressing" root cause named here earlier was a misidentification — the ADRM
declares the adhered profile in MSH-12.3, which the DSL addresses.)*

### Addendum to §D — base-spec new-order / Send Number OBR-2/3 misfire (P1 review finding, not an ADRM point; fixed in P4-7)

Found during the P1 OBR-predicates whole-workstream review (2026-09-30). Not an ADRM-2021 point — landed here per the global-constraints rule that P4/P6 rows add to the existing lettered sections rather than opening a new one.

On v2.3 through v2.6, the modelled OBR-2 condition (`ORC-2 empty`) and OBR-3 condition (`ORC-3 empty`) fire whenever the ORC counterpart is empty, with no allowance for a legitimately-unassigned filler number. A placer NW order has no filler order number yet by design; the ORC-1 Send Number (SN) table notes (v2.4 §4.5.1.3 family) print a *null* ORC-3 as the correct value when the filler application is requesting a centralised filler order number from another application — the empty ORC-3 there is the wire signal that a number has not yet been assigned, not an omission that OBR-3 must carry instead. The modelled predicate cannot tell "ORC-3 empty because unassigned (legitimate)" from "ORC-3 empty and should have been carried in OBR-3 (spec violation)", so it fires `conditionalFieldMissing` on OBR-3 for a conformant NW/SN order where both ORC-3 and OBR-3 are, correctly, empty. The same shape applies to OBR-2/ORC-2 on the placer side.

**Fixed in P4-7 (2026-09-30), all six versions.** OBR-2/3 and ORC-2/3 now fire only when neither a placer id nor a filler id exists across the ORC/OBR pair, so a placer NW order (no filler number yet; ORC-3 "is assigned by the order filler", v2.4 CH04 §4.5.1.3) and both Send Number shapes (the ORC-1 SN table notes, v2.4 CH04 §4.5.1.1, print one null number beside a valued one) are silent. Per version:

- **v2.8.2:** placer-or-filler with the SN exemption the text prints (CH04 §4.5.1.2 / §4.5.1.3 / §4.5.3.2 / §4.5.3.3: "each message must have either a placer or a filler id with an exception for the case of a 'Send Number' control code").
- **v2.3 to v2.6:** placer-or-filler with no SN exemption. These versions print no exemption, and every SN shape they print still carries one number, so the rule is silent on them; an SN with neither number fires.
- **ORC absent (ORU / ORF only, all versions):** OBR-3 is required on v2.3 to v2.6 ("the identifying filler order number must be present in the OBR segments", §4.5.1.3). OBR-2 is required on v2.5.1 and v2.6 (§4.5.1.2 says the same of the placer number), but only when OBR-3 is empty on v2.3, v2.3.1 and v2.4, whose CH07 OBR introduction (§7.3.1.0 / §7.4.1.0) adds "when the filler initiates the order ... the placer order number may be blank". v2.5.1 drops that sentence. On v2.8.2 either number satisfies the rule.
- **OBR absent (new ORC leg, all versions):** an ORC with no OBR in its group needs one of its own two numbers. Citation: v2.3 and v2.3.1 CH04 §4.3.1.2, v2.4 to v2.6 CH04 §4.5.1.2: "If the placer order number is not present in the ORC, it must be present in the associated OBR and vice versa" — with no associated OBR the number stays in the ORC. This covers pharmacy (RXO/RXE/RXD/RXG), diet (ODS/ODT), supply (RQD) and blood-bank orders, the DFT/BAR financial ORCs, and the VXU/CSU ORC that stands with RXA.

**Resolved in P8b-17 (2026-10-04): structure group spans.** The `messageCode not in (...)` gates are removed from the ORC and OBR schemas on v2.5.1, v2.6, v2.7.1 and v2.8.2. On every complete version (all seven), a message whose structure resolves, is not a fragment and matches its structure cleanly is scoped by the matched group instances (ADR-019 "Interaction with the existing ORC-group scoping", amendment P8b-17): the ORC/OBR peer of a segment is taken from the segment's own group occurrence, never from a nested group that pairs its own ORC and OBR (such as the prior-result ORDER_PRIOR that OML_O21, OML_O33 and OML_O35 nest inside the order; ADR-019, P8b-17 amendment, as corrected in fix round 1), so the OBR printed before the ORC in OUL^R22, OUL^R23, OUL^R24, OPU^R25 and OPL^O37 ORDER_PRIOR is the ORC's own OBR. OUL, OPU and OPL messages now get the placer-or-filler check, the ORC-8 / OBR-29 child-order check (v2.3 to v2.6) and the pair-equality check inside their own group; OUL^R21 (ORC before OBR) is no longer caught by the code gate. A lint-failing structure has spans too when every accepting parse puts every segment in the same group occurrences.

- **Limitation (R4 fallback): a formerly gated message code with no spans gets no group-dependent predicate findings on the formerly gated fields.** When a message has no spans (it deviates from its structure, its structure's accepting parses disagree, the structure is registered as not modelled, lookup resolves none, or MSH-12 does not resolve to the version), the ORC walk would misfire on these structures, so the gate's outcome is kept: the conditions of the listed fields are not evaluated. Per version (`Validator.formerlyGated`): v2.5.1, OUL, fields ORC-2, ORC-3, ORC-8, OBR-2, OBR-3, OBR-29; v2.6, OUL, OPU and OPL, the same six fields; v2.7.1 and v2.8.2, OUL, OPU and OPL, fields ORC-2, ORC-3, OBR-2, OBR-3. An empty MSH-9.1 counts as gated, as it did under the gate leg. Every other message code without spans uses the ORC walk unchanged, as before P8b-17.
- **ORC-absent legs on OBR-2/3** stay gated to `messageCode in (ORU, ORF)` (P1-3), on v2.8.2 too although its text says "each message". Other structures where an OBR stands without an ORC are not checked. These are print conditions, not the P4-7 gate, and are unchanged.

The equality clause ("if both ORC-2 and OBR-2 are valued then they must be valued the same") is enforced separately by the M8-B1/B2 ORC/OBR pair-equality check, not by these conditions.

**v2.7.1 (P10-5a, 2026-10-03):** v2.7.1 prints the v2.6 sentences, not v2.8.2's: no "either a placer or a filler id with an exception for ... 'Send Number'" (CH04 §4.5.1.2-3, pp. 34-35; §4.5.3.2-3, pp. 55-56). ORC-2/3 and OBR-2/3 therefore carry the v2.6 forms (placer-or-filler, no SN exemption), with the same ORC-absent `messageCode in (ORU, ORF)` leg (P10 ruling C5). The `messageCode not in (OUL, OPU, OPL)` gates P10-5a added are removed in P8b-17 with the others; the fallback above applies to v2.7.1 as to v2.6.

### Addendum to §D — one prohibition per field (P4-1 review finding, not an ADRM point; fixed in P4-21)

Found during the P4-1 review (2026-09-30). Not an ADRM-2021 point; added here per the global-constraints rule that P4 rows go into the existing lettered sections.

| Position | Versions | Spec text | What it needs |
|---|---|---|---|
| RXR-6 Administration Site Modifier | v2.5.1, v2.6 | v2.5.1 CH04 §4.14.2.6 (v2.6 identical): "If RXR-2 employs HL7 Table 0163 – Body Site, then RXR-6 should not be populated." The v2.8.2 CH04A definition omits this sentence. | The predicate is expressible (`RXR-2.3 = HL70163`, warning). The model is not: `FieldGrammar` holds a single `prohibitedWhen` at a single `prohibitedSeverity`, and RXR-6 already carries the error-level Condition Rule `RXR-2 empty` (P4-1). Needs more than one prohibition per field, each with its own severity. |

**Fixed in P4-21 (2026-10-01).** `FieldGrammar.additionalProhibitions` holds further prohibitions beside `prohibitedWhen`, each a `FieldProhibition` with its own condition and severity; the Validator reports each rule that holds as its own `conditionalFieldProhibited` issue. RXR-6 on v2.5.1 and v2.6 now carries both rules: `RXR-2 empty` (error) and `RXR-2.3 = HL70163 OR RXR-2.6 = HL70163` (warning). RXR-2.3 and RXR-2.6 are the CWE Name of Coding System and Name of Alternate Coding System, which Chapter 2A defines as `HL7nnnn` for an HL7 table, so a Table 0163 site is coded `HL70163` in either triplet; RXR-2 "employs" the table when either triplet does (fix round 1). v2.8.2 keeps the single rule. The model limitation is closed.

### Addendum to §D — HL7au:00060.4, C elements not valued when the predicate is false (P4-20; SHIPPED in P4-31)

Recorded 2026-10-01. ADRM-2021 Appendix 5 (p. 466): "HL7au:00060.4 | Senders | Orders, Results, Referrals | HL7 message elements with a usage of C (conditional) must not be valued when the associated predicate is not satisfied." ADRM §1 (p. 11) gives C the Conformance Implementation Manual meaning: "If the predicate is NOT satisfied: A conformant sending application must NOT send the element." The ADRM attribute tables use the base `OPT` column, so the elements in scope are the base v2.4 C fields.

**Status: SHIPPED** (P4-31, 2026-10-01, owner rulings G6 and G9), with the scope under "Route C outcome" below: OBX-2 is the one route C field, and the other 51 candidates carry no derivable prohibition. The point is enforced where the base schema carries an explicit `prohibitedWhen` on a C field (`.conditionalFieldProhibited`): AIS-10, AIG-14, AIL-12, AIP-12 (all six, P4-23); PRA-1, PRA-12, STF-1 (v2.4 on); BPX-5/6/8/9/10, BTX-2/3/5/6/7, SPM-13, TQ2-7 (v2.5.1 on); PYE-3/4/5/6 (v2.6 on); PRT-6/7 (v2.8.2); and, through `additionalProhibitions` with the HL7 null exempt, OBX-2 and OBX-5 while OBX-11 = O (v2.3.1 on; route B below, moved to the base grammar by P4-26); and on v2.4 OBX-2 under OBX-11 = X, the one C field marked as a full predicate (route C below). The general rule ("report a valued C field whose `condition` is false") cannot ship by negating every stored condition, for two reasons (route C answers the first by marking, per field, the conditions that are full predicates, and the second with a three-state evaluator):

1. **Stored conditions are "required when" triggers, not full predicates.** `FieldGrammar.condition` records when the field becomes required; it does not record when the field must be absent. Negating it contradicts the spec text:
   - OBR-2 / OBR-3 / ORC-2 / ORC-3: ADRM §4.4.1.2 says "If both fields, ORC-2-placer order number and OBR-2-placer order number, are valued, they must contain the same value", so both may be valued. Negation would prohibit OBR-2 whenever ORC-2 or OBR-3 is valued, which is nearly every AU ORU and ORM.
   - OBR-7 (`messageCode in (ORU, ORF, OUL)`): ADRM §4.4.1.7 says that in a request, "if ... a sample has been sent along as part of the request, this field must be filled in". Negation would prohibit it in ORM.
   - PID-35 (v2.4): may be valued without PID-36 breed, so negation misfires.
2. **The evaluator mapped "undecidable" to false** (until P4-31). `Validator.conditionTriggers` fails safe: a missing peer segment, a malformed atom or `noRepeat` over an empty field all evaluate `false`. That is safe for "required when true" checks. Under "prohibited when false" it makes every unresolvable predicate fire. For example, an ORU with no ORC makes `ORC-2 empty` unresolvable.

**Routes to close:**
- **B (P4-24, landed 2026-10-01):** explicit, cited per-field AU prohibitions wherever the v2.4 or ADRM text says the element must not be valued. They live in `FieldOverride.prohibitions` (AU profile), go through the shared condition evaluator and report `.profileConstraintViolation("HL7au:00060.4 ...")`. Shipped: OBX-2 and OBX-5 must not be valued when OBX-11 = O, scoped to ORM/ORU/REF, error (HL7 v2.4 §7.4.2.11: "An OBX used for a dynamic specification must contain ... OBX-11 valued with O, and OBX-2 and OBX-5 valued with null"; the HL7 null `""` is accepted). **P4-26 (2026-10-01) moved this rule to the base grammar** on every version that prints the sentence (v2.3.1, v2.4, v2.5.1, v2.6, v2.8.2; v2.3 has no O status), unscoped by message type, as an error `.conditionalFieldProhibited` with `FieldProhibition.permitsNull`, and removed the AU duplicate, so AU traffic reports it once. The base OBX-2 condition `OBX-11 != X` stays, and OBX-5 gains the condition `OBX-11 = O`; `""` satisfies both, so the only conformant OBX-2 and OBX-5 under O are `""`. Every other in-scope C field was read against the v2.4 chapter and the ADRM clause and states only when it is required, or gives advice that is not a prohibition ("not relevant for patient referral", "results field only"). The per-field table is in the P4-24 report. Out of 00060.4 scope: ORC-8 and OBR-29 are O in the ADRM ORC and OBR attribute tables, although base v2.4 has C; OBR-29's "Not used in Australian messages" is an unconditional AU prohibition that belongs to a separate usage-X rule, not to 00060.4. **P4-27 (2026-10-01) investigated that usage-X rule and did not ship it.** OBR-29's "Not used" sentence (ADRM §4.4.1.29, p. 229) conflicts with §5.4.1.8's "ORC-8-parent is the same as OBR-29-parent. If the parent is not present in the ORC, it must be present in the associated OBR" — a conflict the schema itself encodes (`v2.4/OBR.json` OBR-29 condition `ORC-1 = CH AND ORC-8 empty`; `v2.4/ORC.json` ORC-8's mirrored condition) and that the already-shipped M8-B2 `pairedFieldMismatch` equality rule presumes is resolvable (OBR-29 can legitimately carry a value). An unconditional AU prohibition on OBR-29 would fire in exactly the scenario the base conditional-requiredness check already requires it populated. P4-27 shipped the sibling field instead — OBR-26 (identical "Not used" sentence, item 00259, no base condition) — as `ADRM-prose:P-11`; see `docs/design/m7-adrm-prose-sweep.md` and `task-P4-27-report.md`. **P4-32 (2026-10-01), owner decision G7, overrides that outcome:** OBR-29 ships anyway, as an AU warning matching P-11's mechanism and scope exactly (`messageCode in (ORM, ORU, REF)`, HL7 null exempt) — `ADRM-prose:P-13`. The double-bind this creates on a v2.3–v2.6 child order sent without ORC-8 (the AU warning and the base conditionally-required check both fire on OBR-29 at once) is accepted by the owner, not re-engineered away. See `task-P4-32-report.md`.
- **C (P4-31, landed 2026-10-01, ADR-021):** the evaluator's core is three-state (true / false / unknown, Kleene AND and OR; `conditionTriggers` is exactly "true", so no existing check changed). A schema field may mark its stored condition as the spec's full C predicate (`"conditionIsPredicate": true` plus a quoted `"predicateCitation"`, audited by `scripts/audit-schemas.py`). Under the AU profile, in ORM, ORU and REF, a marked C field that carries a value other than the HL7 null while its condition is definitely false reports `.profileConstraintViolation("HL7au:00060.4 ...")`, error. Unknown never fires, and a field a base or AU prohibition already reports is not reported twice.

**Route C outcome (P4-31).** Every C field in the segments v2.4 ORM^O01, ORU^R01 and REF^I12 carry (with the ADRM REF_I12 additions and the ADRM-only C on OBR-1), 52 in all, was read against the v2.4 text and the ADRM clause. The per-field table with quotes is in `docs/design/conditional-completeness-audit.md`, "HL7au:00060.4 route C classification".

- **(a) full predicate, marked and enforced (1):** OBX-2 ("It must be valued if OBX-11-Observ result status is not valued with an X", §7.4.2.2; ADRM §4.4.2.2 p. 236; ADRM §4.17.2 Scenario 5 p. 268: "OBX-2 value type is null" with "OBX-11 Result status is 'X'", and "If the |""| format is used then OBX- 11 will not contain 'X' as OBX-2 is valued").
- **(b) trigger only, no prohibition implied (31):** PID-35, PV2-1, PV2-47, ORC-2, ORC-3, ORC-8, OBR-1 (ADRM C), OBR-2, OBR-3, OBR-7, OBR-22, OBR-25, OBR-29, RQD-2/3/4, RXO-1/2/4, RXO-5, OBX-4, OBX-5, AUT-6, RXE-8, RXE-15, RXD-5, RXD-13, RXA-11, ROL-1, PID-36, CTI-2. PID-36 and CTI-2 (owner ruling G9) are parents required when their child is valued, the shape of PID-35: §3.4.2.36 prints breed alone ("...|L-80900^Weimaraner^SNM3|..."), and §7.8.4 / §7.8.4.3 give the phase and the time point as separate facts, with the rule stated on CTI-3.
- **(c) no derivable prohibition from the text (8), owner ruling G9:** RQ1-2/3/4/5 ("either RQ1-2 ... and RQ1-3 ... or RQ1-4 ... and RQ1-5 ... must be valued": read inclusively, it sets a minimum and the text prints no prohibition on sending both pairs); RXE-10, RXE-18, RXE-19 (printed C with a plain definition and no predicate); PTH-6 ("must be filled in if trigger event is update or terminate pathway": Chapter 12 defines no "terminate" event, so no trigger set can be derived).
- **(n) predicate not decidable from the message (12), no derivable prohibition, owner ruling G9:** OBR-14 (specimen accompanied the order), RXO-14 and RXE-13 (controlled substance), RXO-15 (site requires a verifier), RXO-17, RXE-22, RXA-12 (continuous administration at a prescribed rate), RXE-11, RXA-7 (units implied by a code), RXE-16, RXE-17, RXD-8 (dispensed to an outpatient). Each is a bare C under §A; its prohibition half is no more decidable than its requirement half, so the three-state evaluator would answer unknown and the rule could never fire. G9 records them with §A's freeze rationale.

A test pins the current behaviour (`LocaleAUProfileTests`, P4-20): an AU v2.4 ORU with OBR-2 valued while its condition is false (ORC-2 and OBR-3 also valued) raises no `HL7au:00060.4` issue. OBR-2 is class (b), so it stays unmarked and the pin stays green after route C. Do not "fix" that test by negating `condition` or by marking OBR-2.

### Addendum to §D — field-local composite grammar gaps (P5-5 review finding, not an ADRM point)

Found during the P5-5 review (2026-10-02). Not an ADRM-2021 point; added here per the global-constraints rule that rows go into the existing lettered sections. Every row blocks spec-completeness (requirement 3). None is enforced today: the validator does not read field-local grammars until P5-6. The TXA-22 row was added by P10-5b (2026-10-03).

| Position | Versions | Spec text | What it needs |
|---|---|---|---|
| 15 table mentions in CM field definitions left unbound: IN2-28 (0145, 0146) and IN2-29 (0147, 0193) on v2.3, v2.3.1 and v2.4; v2.3 IN3-11.1 (0149); v2.3 MSH-9 (0076, 0003) | v2.3 (7), v2.3.1 (4), v2.4 (4) | IN2-28 / IN2-29 name two tables in one sentence over two IS components ("Refer to User-defined Table 0145 - Room type and User-defined Table 0146 - Amount type"); v2.3 sec 2.24.1.9 MSH-9 names 0076 and 0003 in one sentence ("first ... table 0076 ...; second is ... table 0003"); v2.3 IN3-11 names 0149 "Day type" where the v2.3 registry prints "Days Type". | Pairing a table with a component by the order of its mention, or by the component's name, is a reading the M13 tests do not license. `python3 scripts/extract-field-components.py <version> --report` lists each mention with its reason; the absent binding is an absent check, never a wrong one. |
| OM2-6 Reference (normal) range for ordinal and continuous observations | v2.3, v2.3.1 (sec 8.7.4.6), v2.4 (CH08 sec 8.8.4.6) | The structure is printed as a narrative repetition list (`<ref. (normal) range1>^<sex1>^<age range1>^...~`) with a nested `Components: <low value (NM)> & <high value (NM)>`, and no field-level Components line. | A field grammar that can state a repeating tuple with nested subcomponents. `DataTypeGrammarTests.fieldLocalCoverage` pins it as registered (ADR-017, P5 addendum). |
| TXA-22 Authentication Person, Time Stamp (PPN) | v2.5.1 (CH09 sec 9.6.1.22, p. 31), v2.6 (sec 9.6.1.22, p. 21), v2.7.1 (sec 9.7.3.22, p. 36), v2.8.2 (sec 9.7.3.22, p. 36) | "If either of the Authenticating Person or the Authentication Time Stamp is valued as non-null, then both must be valued as non-null." The Date/Time Action Performed component is the time stamp; "the remaining components" are the person. | A co-presence rule between a component group and one component of the same repetition, on every repetition. The field condition language reads the first repetition's single components, and the PPN grammar is shared by fields that print no such rule. TXA-22's own presence keys on TXA-17 on v2.5.1 and has no trigger on v2.6 to v2.8.2, where it stays bare (conditional-completeness-audit.md). |

### Addendum to §D — v2.7.1 conditional components left bare (P10-2, not an ADRM point)

v2.7.1 Chapter 2A prints 72 components `C`, the same 72 positions as v2.8.2, and every one's definition matches v2.8.2's word for word or differs only in a cross-reference. 23 carry a `condition` and 30 a `conformanceCondition` (`Resources/datatypes/conditions.json`, `"2.7.1"` blocks, each cited to the v2.7.1 sentence; `V271GrammarTests.componentConditions`). The 19 below stay bare, for the reasons the v2.8.2 positions do. The v2.7.1 grammar is reachable through `Version.v2_7_1` (and a substituted `2.7`) since P10-6; these 19 stay unchecked (read as optional), as on v2.8.2. Rows 1 and 2 block spec-completeness (requirement 3).

| Position (v2.7.1 Chapter 2A) | Spec text | Why bare |
|---|---|---|
| CF.7 (2.A.7.7, p9), CNE.7 (2.A.8.7, p14), CSU.8 (2.A.12.8, p21), CWE.7 (2.A.13.7, p29); CF.13 (2.A.7.13, p10), CNE.13 (2.A.8.13, p15), CSU.14 (2.A.12.14, p22), each "analogous to" its .7 | "If CWE.3 is populated with a value other than HL7nnnn or is of table type user-defined, version ID must be valued with an actual version ID." | Needs a value-pattern term and a table-type lookup the predicate language lacks; as on v2.8.2 (conditions.json `_about`). |
| CNE.20 (2.A.8.20, p16) | "required when CNE.4 is populated and neither CNE.6 nor CNE.18 is populated. In short either the CNE.6 or the CNE.14 or CNE.17 must be populated" | The sentence contradicts its own summary; no single predicate is faithful. |
| CNN.9 (2.A.9.9, p17) | "If component 1 is valued, either CNN.8 or CNN.9, or both CNN.10 and CNN.11, must be valued." | Carried by the CNN.8 rule, which reports the whole disjunction at CNN.8. |
| HD.2, HD.3 (2.A.33.2 and 2.A.33.3, p48); EI.3, EI.4 (2.A.25.3 and 2.A.25.4, p41, "See Section 2.A.33.2") | HD.2 "must follow the syntactic rules of the particular universal identifier scheme (defined by the third component)" | The HD either-or rule (M15) carries the pair; no sibling-presence condition is stated in the subsections themselves. |
| OSP.2, OSP.3 (2.A.51, p61); PL.1 (2.A.53.1, p62, "conditional on PL.6 Person Location Type"); PPN.12 (2.A.55.12, p67); XCN.12 (2.A.87.12, p95); XTN.8 (2.A.90.8, p107) | Printed `C`; the definitions state no wire-decidable condition. | Left as printed, as on v2.8.2. |

## E. Abstract message syntax (blocks spec-completeness)

Registered 2026-09-30 (review finding X-C04). This is **not** a permanent limitation: every
part of it is decidable from the wire. It is a model gap that blocks spec-completeness under
project requirements 1 and 3, and it stays in this register until the per-version rollout
closes it (`planning/remediation/P8b-message-structure-rollout.md`, to be scoped by P8-9 with
an owner gate).

**Pilot shipped 2026-10-02 (P8-3 to P8-7), opt-in.** The check runs only when
`ValidationOptions.messageStructureSeverity` is set (`nil`, off, in every preset), so default
output is unchanged. Three structures are modelled, all v2.5.1: `ADT_A01` (ADT^A01, A04, A08,
A13), `ORU_R01` and `ACK` (`ACK^*`), generated from `Resources/structures/v2.5.1/` into
`Sources/HL7v2Kit/Structures/Generated/`. Every other structure on v2.5.1, and every structure
on v2.3, v2.3.1, v2.4, v2.6, v2.7.1 and v2.8.2 (and on `2.7` and `2.8`, validated as v2.7.1 and
v2.8.2), is not modelled
and raises one `messageStructureNotModelled` info issue instead of a silent pass. Z-segments
and ADD continuations are skipped by the matcher, and a segment the version's grammar does
not define is passed over (it already raises `segmentNotInVersionGrammar`).

| Capability | Spec | What is not checked today | Status |
|---|---|---|---|
| Message structures (segment order, `[ ]` optional and `{ }` repeating segments, segment groups, required segments per trigger event) | v2.3 CH3 §3.2.1 (ADT^A01) and CH2 ACK; v2.3.1 CH2 §2.11-2.11.1; v2.4 CH02 §2.12-2.12.1 and §2.14; v2.5.1 CH02 §2.5.2 and each chapter's message definitions; v2.6 CH02 §2.5.2; v2.7.1 CH02 §2.5.2 and §2.12; v2.8.2 CH02 §2.12 | With `messageStructureSeverity` set, a v2.5.1 `ADT^A01` with no EVN or PV1, an ACK with no MSA, or an ORU^R01 with OBX before OBR is reported (`messageStructureSegmentMissing`, `messageStructureSegmentUnexpected`). Not checked: the 31 v2.5.1 structures registered as not modelled (addendum below) and every version other than v2.5.1 (`messageStructureNotModelled`, info); a structure that fails the determinism lint is matched exactly since P8b-12 (no longer reported as not modelled; none of the three pilot structures fails it), with one known cost: at most one finding, at the furthest segment any parse reached, and no group spans, so span-derived group predicates (P8b-17) skip such structures and keep the back-walk heuristics on them (ADR-019 ceiling 1, P8b-12 amendment); and anything at all with the option off, the default. `SegmentCardinalityRule` still covers only the AU profile's 21 group rules, and group-dependent predicates still use the `orcObxGroup` / `obrObxGroup` / `messageWide` back-walk heuristics on every version: span-derived groups wait for a complete version (ADR-019, R9). | **Blocking; v2.5.1 complete (P8b-9, 2026-10-04):** 172 structures modelled, 31 registered, opt-in; other versions follow the rollout. Design: ADR-019 (accepted 2026-10-02 under gate G2, answered 2026-09-30). Rollout: `planning/remediation/P8b-message-structure-rollout.md` (scoped by P8-9). |
| Event-to-structure consistency (MSH-9.3 against MSH-9.1/9.2) | Table 0354 and the chapter caption lines (`ADT^A04^ADT_A01`) | With the option set, an MSH-9.3 naming a loaded structure that does not print MSH-9.1^9.2 (`ADT^A02^ADT_A01` on v2.5.1) raises `messageStructureMismatch` alone, with no body match. Since P8b-9 v2.5.1 is complete, so `ADT^A04^ADT_A04` (no such structure; A04 uses ADT_A01) raises `messageStructureMismatch` (ADR-019 lookup rule 1); an MSH-9.3 naming a registered not-modelled structure stays info, with its reason. Not checked: an MSH-9.3 naming a structure that is not loaded on any other (incomplete) version, which stays `messageStructureNotModelled` (info). Table 0354 is deliberately open (it lags the chapters) and is not consulted. | **Blocking; mechanism shipped (P8-6); v2.5.1 complete (P8b-9).** Same design and rollout. |
| Message fragments (a logical message broken after an arbitrary segment: first fragment ends in DSC, later fragments carry MSH-14) | v2.4 CH02 §2.15.2.2; v2.5.1, v2.6 and v2.7.1 CH02 §2.10.2.2; v2.8.2 CH02 §2.10.2.1; v2.3 and v2.3.1 CH2 §2.15.4, §2.23.2 and the DSC segment §2.24.8 | A fragment is not structure-checked (it raises `messageStructureNotModelled`) and fragments are not reassembled, so the logical message's structure is never validated. A message is a fragment when MSH-14 is populated, when its trailing DSC has DSC-1 populated (whatever the structure defines), or when it ends in a DSC its structure does not define. Known cost: a complete message carrying a continuation pointer (for example an interactive query response installment, DSC-2 = I, v2.5.1 CH05 §5.6.3.1) is not structure-checked either; DSC-2 is not consulted. | **Blocking.** Reassembly is out of scope for the pilot; ADR-019. |
| Version provenance (a message whose `message.version` differs from the wire reading of MSH-12, for example one parsed with `ParserOptions.versionOverride`) | ADR-018 version resolution; ADR-019 | Not structure-checked; raises `messageStructureNotModelled`. The comparison is between grammar versions, so a `2.8` or `2.7` message (validated as v2.8.2 or v2.7.1) is not excluded by this rule; it is checked against the v2.8.2 or v2.7.1 structures (both complete since P8b-11 and P8b-16). An empty or unresolved MSH-12 is not structure-checked either. Conservative (no misfire); honouring an explicit override would need version provenance on `Message`. | **Blocking.** ADR-019 known ceiling 7. |
| Acknowledgment construction and the MSH-15/MSH-16 processing rules | v2.4 CH02 §2.3.2, §2.3.3, §2.13, §2.14.1; v2.5.1 CH02 §2.9.2, §2.9.3, §2.14.1 | The MSH-15/MSH-16 acknowledgment protocol (whether, when and with which code to acknowledge; enhanced mode; sequence numbers). | **Decided (ADR-019 decision 9):** general acknowledgment builder shipped (P8-7, `MessageBuilder.acknowledgment(to:code:messageControlID:dateTime:)`: MSA-2 echo, sender/receiver swap, `ACK^<event>^ACK`, MSH-11/12 echoed, a populated MSH-18 echoed as a builder rule beyond the spec's echo list); MSH-15/MSH-16 protocol logic is a non-goal (HL7v2Kit-Spec.md §2). |

### Addendum to §E — v2.5.1 complete (P8b-9, 2026-10-04)

v2.5.1 is `complete: true` in `Resources/structures/completeness.json`: every structure the
chapters print is either modelled (172, extracted by `scripts/extract-message-structures.py`,
each cited to chapter, section and pages; 171 since P8b-13 registered ERP_R09, see the v2.4
addendum; 173 since the P8b-13 fix round read QRY_Q02 and QCK_Q02 from CH05 5.10.3.1, p 5-116)
or registered here as not modelled (31, 32 since P8b-13, 30 since its fix round, listed in
that file's `notModelled` with the triggers its captions print). A registered structure is
reported as `messageStructureNotModelled` (info) with its reason, never as a mismatch, unless
MSH-9.3 names it for a trigger its captions do not print; its triggers count towards an
ambiguous trigger (ADR-019 lookup rule 2).

| Not modelled (v2.5.1) | Why | Status |
|---|---|---|
| PGL_PC6, PPG_PCG, PPP_PCB, PPR_PC1, PPT_PCL, PPV_PCA, PRR_PC5, PTR_PCF | CH12 prints the order detail as `< OBR \| etc. >`; the CH12 12.3 note reads it as every combination of pharmacy and other order detail segments per CH04 4.2.2.4, and 4.2.2.4 names only examples ("Examples are OBR and RXO"), so the alternatives cannot be enumerated (ruling G6). | **Blocking** for v2.5.1 unless a ruling fixes the set (later versions are read by their own tasks). |
| QBP_Q11, QBP_Q13, QBP_Q15, QVR_Q17, RSP_K11 (CH05 5.4.1 to 5.4.5); MFN_M01, MFR_M01, MFN_M03 (CH08 8.4.1, 8.4.4, 8.8.2) | Templates: a `[...]` or `...` row stands for query-specific segments a conformance statement defines, or master-file-specific segments; no fixed syntax exists (ruling G6). | **Permanent** for the template IDs (a conformance statement or the specific master file message defines the content). |
| SUR_P09 (CH07 7.11.2) | The print has a row `ED Encapsulated Data`; v2.5.1 defines no ED segment (ED is a data type), so the row names nothing a message can carry. | **Blocking**; a print defect. |
| DSR_P04, MFD_MFA, ORU_R31, ORU_R32, ORU_W01, QRF_W02, QRY_P04, QRY_T12, RDE_O01, RRA_O02, RSP_K22, TBR_R09 | Table 0354 v2.5.1 lists them; no v2.5.1 chapter prints their syntax. (QRY_Q02 and QCK_Q02 were listed here until the P8b-13 fix round: CH05 5.10.3.1, p 5-116, prints both, as "QRY^Q02 (A to B)" and "QCK^Q02 (B to A)", a caption form the reader had missed; both are now modelled.) | **Permanent** for v2.5.1. |

Two normative prints of one structure ID that disagree (P8b-9 ruling): the committed structure
is the LOOSER print, the one that accepts every message the other accepts, cited to both
(overrides.json `primaryPrints`); per-trigger structures would be a model extension and are not
built.

| Structure (v2.5.1) | Looser print, committed | Stricter print, not checked | Cost | Status |
|---|---|---|---|---|
| RSP_K21 | CH03 3.3.57 (RSP^K22): `[{QUERY_RESPONSE: PID [PD1] [{NK1}] [QRI]}]` | CH03 3.3.56 (RSP^K21, p 3-59): one QUERY_RESPONSE, QRI required | An RSP^K21 response with several QUERY_RESPONSE groups, or one without QRI, passes. | **Blocking** (per-trigger structures). |
| RDE_O11 | CH04 4.13.13 (RDE^O25): OBSERVATION's OBX optional (`[OBX]`), RXC group named COMPONENTS | CH04 4.13.5 (RDE^O11, pp 4-115 to 4-116): OBX required in OBSERVATION, group named COMPONENT | An RDE^O11 message with an OBSERVATION group of NTE alone passes. | **Blocking** (per-trigger structures). |

Other print disagreements recorded, not modelled (the primary print stands, ADR-019 P8b-3a, and
each duplicate is stricter than the primary, so no compliant message draws a finding): ACK at
CH05 5.4.4 to 5.4.7 prints `[ERR]` against CH02's `[{ERR}]`; ADT^A31 prints PROCEDURE's ROL
required; RQC^I06 prints `[GT1]`; RRE^O26 drops RXE's NTE. The HL7 v2.xml bundles differ from the
print for DFT_P03 and DFT_P11 (a VISIT group the print does not have), NMR_N01 (nested groups),
RRE_O12 (no NTE after RXE), ORL_O34 (a self-nesting SPECIMEN, a bundle defect), and RSP_K21 and
RDE_O11 (the bundles follow the stricter prints); the print is normative (ruling D3).

Known cost of exact matching: 21 v2.5.1 structures fail the determinism lint (BAR_P01, BAR_P05,
CSU_C09, DFT_P03, DFT_P11, NMR_N01, OMD_O03, OMG_O19, OML_O21, OML_O33, OML_O35, ORD_O04,
ORF_R04, ORL_O34, OUL_R21, OUL_R24, RCI_I05, REF_I12, RPA_I08, RQA_I08, RRI_I12) and are matched
by the exact matcher: at most one finding per message, at the furthest segment any parse
reached, and no group spans, so span-derived group predicates (P8b-17) cannot use them.

### Addendum to §E — v2.6 complete (P8b-10, 2026-10-04)

v2.6 is `complete: true` in `Resources/structures/completeness.json`: 190 structures modelled
(each cited to chapter, section and pages; RSP_K21 since P8b-11; QRY_Q02 and QCK_Q02 since the
P8b-13 fix round, CH05 5.10.3.1, p 96) and 20 registered as not modelled in that file's
`notModelled`, with the same lookup behaviour as v2.5.1 above.

| Not modelled (v2.6) | Why | Status |
|---|---|---|
| PGL_PC6, PPG_PCG, PPP_PCB, PPR_PC1, PPT_PCL, PPV_PCA, PRR_PC5, PTR_PCF (CH12 12.2.1 to 12.2.12) | The order detail is printed `< OBR \| etc. >`; the CH12 12.2 note (p 12-6) reads it as every combination of order detail segments per CH04 4.2.2.4, which names only examples (ruling G6). | **Blocking** for v2.6 unless a ruling fixes the set. |
| QBP_Q11, QBP_Q13, QBP_Q15, QVR_Q17, RSP_K11 (CH05 5.4.1 to 5.4.5); MFN_M01, MFR_M01, MFN_M03 (CH08 8.4.1, 8.4.4, 8.8.2) | Templates: a `[...]` or `...` row stands for query-specific or master-file-specific segments (ruling G6). | **Permanent** for the template IDs. |
| SUR_P09 (CH07 7.11.2) | A row `ED Encapsulated Data`; v2.6 defines no ED segment. | **Blocking**; a print defect. |
| ORU_W01, QRF_W02, RSP_Q11 | Table 0354 v2.6 (CH02 2.16.3, pp 86 to 87) lists them; no v2.6 chapter prints their syntax normatively (RSP_Q11's only print is the site-specific CH08 8.4.5.1 example `RSP^Znn^RSP_Q11`, excluded under G7). QRY_Q02 and QCK_Q02 were listed here until the P8b-13 fix round: CH05 5.10.3.1 (p 96) prints both; they are now modelled. | **Permanent** for v2.6. |

Two normative prints of one structure ID that disagree (P8b-9 ruling): the looser print is
committed, cited to both (overrides.json `primaryPrints`).

| Structure (v2.6) | Looser print, committed | Stricter print, not checked | Cost | Status |
|---|---|---|---|---|
| ACK | CH10 10.4 (ACK^S12-S24, S26, p 10-17): `[{UAC}]` | CH02 2.13.1 (p 42): `[UAC]` (and every chapter's ACK, all stricter) | An ACK with several UAC segments passes. | **Blocking** (per-trigger structures). |
| ADT_A30 | CH03 3.3.34 (A34; also A36, A46, A47): `[{ARV}]` after PD1 | CH03 3.3.30 (A30; also A35, A48, A49): no ARV | An A30, A35, A48 or A49 message with ARV passes. | **Blocking** (per-trigger structures). |
| ADT_A43 | CH03 3.3.44 (A44): `[{ARV}]` in PATIENT | CH03 3.3.43 (A43, p 3-39): no ARV | An A43 message with ARV passes. | **Blocking** (per-trigger structures). |
| MFK_M01 | CH08 8.4.2 (M13) and 13 other prints: `[UAC]` | CH08 8.4.1 (M01, p 8-5) and 8.8.2 (M03): no UAC | An MFK^M01 or MFK^M03 with UAC passes. | **Blocking** (per-trigger structures). |
| QRY_PC4 | CH12 12.2.7 (PC9; also PCE, PCK): `[{SFT}] [UAC]` | CH12 12.2.5 (PC4, p 12-12): neither | A PC4 query with SFT or UAC passes. | **Blocking** (per-trigger structures). |
| RDE_O11 | CH04 4.13.13 (O25): OBX optional in OBSERVATION, group COMPONENTS | CH04 4.13.5 (O11, pp 4-88 to 4-89): OBX required | An RDE^O11 with an OBSERVATION of NTE alone passes. | **Blocking** (per-trigger structures). |

Two normative prints of one structure ID that are incomparable (P8b-10 ruling, applied in
P8b-11): the committed structure is their union, aligned by segment or group name (per element
the lesser min and the greater max; an element in one print only is optional), computed by the
extractor from a cited overrides.json `unionPrints` entry; prints that do not align stay not
modelled.

| Structure (v2.6) | Prints | Union, committed | Cost | Status |
|---|---|---|---|---|
| RSP_K21 | CH03 3.3.56 (RSP^K21, pp 3-48 to 3-49): one optional QUERY_RESPONSE with `[{ARV}]`, QRI required; CH03 3.3.57 (RSP^K22, p 3-50): `[{QUERY_RESPONSE}]`, QRI optional, no ARV | `[{QUERY_RESPONSE: PID [PD1] [{ARV}] [{NK1}] [QRI]}]` | Both relaxations: an RSP^K21 with several responses or a response without QRI passes, and an RSP^K22 with ARV passes. | **Blocking** (per-trigger structures). |

Other print disagreements recorded, not modelled (each duplicate stricter than the committed
print): ADT^A13 omits the ARV after PD1; RQC^I06 prints `[GT1]`; RRE^O26 drops RXE's NTE. The
HL7 v2.xml bundles differ from the print for the bracketless named groups of EHC_E01, E02, E04,
E15, E20, E21, E24, QBP_E03, QBP_E22, RSP_E03, RSP_E22 and the no-bar `< ... >` of SDR_S31 and
SDR_S32 (the bundle reads a choice of each member; the print a required group, P8b-6 ruling),
ADT_A60 and DFT_P03/P11 (a VISIT group the print does not have), NMR_N01 (nested groups), ACK
and RDE_O11 (the bundle follows the stricter prints); the print is normative (ruling D3). The
CH05 5.9.1.1 RDR restatement and the CH08 8.4.3 MFN_Znn template are excluded (G7; the 8.4.3
acknowledgment MFK^M14^MFK_M01 is read, on v2.5.1 too). A locally defined message (a Z message
type, trigger or structure whose trigger the version prints under no structure) is not modelled
rather than a mismatch on a complete version; a Z trigger the version prints under no structure may declare a printed structure: a loaded one is matched against the body, a registered one is info with its reason (P8b-10 review).

Known cost of exact matching: 23 v2.6 structures fail the determinism lint (ADT_A60, BAR_P01,
BAR_P05, CSU_C09, DFT_P03, DFT_P11, EHC_E15, NMR_N01, OMD_O03, OMG_O19, OML_O21, OML_O33,
OML_O35, OPL_O37, ORD_O04, ORF_R04, OUL_R21, OUL_R24, RCI_I05, REF_I12, RPA_I08, RQA_I08,
RRI_I12) and are matched by the exact matcher, with at most one finding and no group spans.

### Addendum to §E — v2.8.2 complete (P8b-11, 2026-10-04)

v2.8.2 is `complete: true` in `Resources/structures/completeness.json`: 185 structures modelled
(each cited to chapter, section and pages) and 58 registered as not modelled in that file's
`notModelled`; every Table 0354 v2.8.2 row is one or the other. A 2.8 message reads through the
v2.8.2 grammar (ADR-018) and is checked the same way.

| Not modelled (v2.8.2) | Why | Status |
|---|---|---|
| PGL_PC6, PPG_PCG, PPP_PCB, PPR_PC1 (CH12 12.3.1 to 12.3.4) | The order detail is printed `< OBR \| Hxx etc. >`; the CH12 12.3 note (p 7) reads "OBR etc." as every combination of order detail segments per CH04 4.2.2.4, which names only examples (ruling G6). | **Blocking** for v2.8.2 unless a ruling fixes the set. |
| QBP_Q11, RSP_K11, QBP_Q15, QVR_Q17 (CH05 5.4.1 to 5.4.5) | Query templates: a `[...]` or `...` row stands for the segments a query profile defines (ruling G6). QBP_Q11 also carries QBP^Q31, which the CH04A 4A.3.20 query profile declares. | **Permanent** for the template IDs. |
| QBP_Q13 | CH05 5.4.2 refers to 5.3.1.2 for its structure, a query profile example (excluded, G7); no normative print. | **Permanent** for v2.8.2. |
| RDR_RDR | The only print is the CH05 5.9.1.1 restatement of a Chapter 4 query that v2.8.2 Chapter 4A no longer prints (excluded, G7). | **Permanent** for v2.8.2. |
| UDM_Q05 (CH05 5.10.1.2) | Retained for backward compatibility; prints URD and `[URS]`, which v2.8.2 does not define (Appendix A lists both as deprecated), so it cannot be checked against the v2.8.2 grammar. | **Permanent** for v2.8.2. |
| 47 Table 0354 rows marked Deprecated (CH02C 2.C.2.279, pp 149 to 153): ADR_A19, ADT_A18, ADT_A30, DOC_T12, MFN_M01, MFN_M03, MFQ_M01, MFR_M01, MFR_M04, MFR_M05, MFR_M06, MFR_M07, NMQ_N01, NMR_N01, ORF_R04, ORM_O01, ORR_O02, ORU_W01, OSQ_Q06, OSR_Q06, OUL_R21, PPT_PCL, PPV_PCA, PRR_PC5, PTR_PCF, QCK_Q02, QRF_W02, QRY_A19, QRY_PC4, QRY_Q01, QRY_Q02, QRY_R02, QRY_T12, RAR_RAR, RCI_I05, RCL_I06, RER_RER, RGR_RGR, ROR_ROR, RQC_I05, RSP_Q11, SQM_S25, SQR_S25, SUR_P09, VXQ_V01, VXR_V03, VXX_V02 | The Comment column of the printed table marks each Deprecated (five "Deprecated and removed as of V2.7") and no v2.8.2 chapter prints its syntax. | **Permanent** for v2.8.2 (by design). |

Two normative prints of one structure ID that disagree (P8b-9 ruling): the looser print is
committed, cited to both (overrides.json `primaryPrints`).

| Structure (v2.8.2) | Looser print, committed | Stricter print, not checked | Cost | Status |
|---|---|---|---|---|
| ACK | CH10 10.4 (ACK^S12-S24,S26,S27, p 20): `[{UAC}]` | CH02 2.13.1 (p 47): `[UAC]` (and every chapter's ACK; CH05 5.4.4 to 5.4.7 also print `[ERR]`) | An ACK with several UAC segments passes. | **Blocking** (per-trigger structures). |

Other print disagreements recorded, not modelled: RDE_O11's 4A.3.13 (RDE^O25) print names the
RXC group COMPONENTS where the primary 4A.3.5 print and the bundle say COMPONENT (same syntax;
its unclosed TIMING_ENCODED is read through a cited syntax-cell erratum); CH15 15.3.7 captions
QBP^Q25^QBP_Q21 over a query parameter table, not a syntax; the CH03 3.2.63 query profile names
`RSP^K32^RSP_K25` where its caption and Table 0354 say RSP_K32, and the CH04 4.16 profiles name
QBP_Q33, RSP_K33, QBP_Q34 and RSP_K34 where the captions and Table 0354 say QBP_O33, RSP_O33,
QBP_O34 and RSP_O34 (the caption is committed; a message declaring the profile's ID is a
mismatch). The HL7 v2.xml bundles differ from the print for the no-bar `< ... >` named groups
of EHC_E01, E02, E04, E15, E20, E21, E24, QBP_E03, QBP_E22, RSP_E03 and RSP_E22 (the CH16 text
never says "one of" for them: named required groups, P8b-6 ruling), ADT_A09 and ADT_A12 (the
bundle adds DG1), ADT_A60, DFT_P03 and DFT_P11 (a VISIT group the print does not have), OSM_R26
(a PATIENT_INFORMATION group), and OPU_R25, ORG_O20, OUL_R22, R23 and R24 (a PRT the bundle
lacks); the print is normative (ruling D3). The SDR_S31 and SDR_S32 group names print with a
hyphen (`ANTI-MICROBIAL_...`) and are read as ANTIMICROBIAL_..., as on v2.6.

A structure accepts every trigger Table 0354 of its version maps to it, as well as the triggers
its captions print (P8b-11 fix-round ruling; cited in the structure's citation, with any section
that marks the event withdrawn): v2.8.2 MFK_M01 gains MFK^M01 and MFK^M03 (CH08 8.4.1 and 8.8.2
mark them withdrawn; the table still maps them), ADT_A39 gains ADT^A39, and RPI_I01
gains RPI^I04 on v2.5.1, v2.6 and v2.8.2; v2.5.1 ADT_A09 gains ADT^A12. Where the table maps a
trigger to a structure while a caption prints it under another (RPI^I04 on all three versions,
ADT^A12 on v2.5.1) the trigger is a declared shared trigger: ambiguous without MSH-9.3. The
v2.5.1 table prints OMN_O07's and ORL_O22's events as '007' and '022' (cited table-0354 errata).
The v2.8.2 table lists ORL_O41 to ORL_O44, QBP_O33, QBP_O34, RSP_O33 and RSP_O34 against an event
equal to their own suffix (O41, O33, ...), which Table 0003 gives to other messages; the ruling
adds ORL^O41 to ORL^O44, QBP^O33, QBP^O34, RSP^O33 and RSP^O34 as accepted triggers (a
relaxation, never a false finding).

Known cost of exact matching: 32 v2.8.2 structures fail the determinism lint (ADT_A60, BAR_P01, BAR_P05, CSU_C09, DEL_O46, DEO_O45, DER_O44, DFT_P03, DFT_P11, DPR_O48, DRC_O47, DRG_O43, EHC_E15, OMD_O03, OMG_O19, OML_O21, OML_O33, OML_O35, OMQ_O42, OPL_O37, OPU_R25, ORD_O04, ORG_O20, OSM_R26, OUL_R22, OUL_R23, OUL_R24, REF_I12, RPA_I08, RQA_I08, RRI_I12
and RSP_O34) and are matched by the exact matcher, with at most one finding and no group spans.

### Addendum to §E — v2.7.1 complete (P8b-16, 2026-10-04)

v2.7.1 is `complete: true` in `Resources/structures/completeness.json`: 164 structures modelled
(each cited to chapter, section and pages) and 58 registered as not modelled in that file's
`notModelled`; every one of the 222 Table 0354 v2.7.1 rows is one or the other. A 2.7 message
reads through the v2.7.1 grammar (ADR-018) and is checked the same way.

| Not modelled (v2.7.1) | Why | Status |
|---|---|---|
| PGL_PC6, PPR_PC1, PPP_PCB, PPG_PCG, PRR_PC5, PPV_PCA, PTR_PCF, PPT_PCL (CH12 12.3.1 to 12.3.12) | The order detail is printed `< OBR \| Hxx etc. >`; the CH12 12.3 note (p 6) reads "OBR etc." as every combination of order detail segments per CH04 4.2.2.4 (p 4), which names only examples (ruling G6). Table 0354 also lists PCC under PPG_PCG, so PPG^PCC is registered with it. | **Blocking** for v2.7.1 unless a ruling fixes the set. |
| QBP_Q11, RSP_K11, QBP_Q13, QBP_Q15, QVR_Q17 (CH05 5.4.1 to 5.4.5) | Query templates: a `[...]` or `...` row stands for the segments a query profile defines (ruling G6). QBP_Q11 also carries QBP^Q31, which the CH04A 4A.3.20 query profile (p 22) declares. | **Permanent** for the template IDs. |
| RDR_RDR | The only print is the CH05 5.9.1.1 restatement of a Chapter 4 query (excluded, G7); CH04A 4A.3.17 (p 22) says the pair was "withdrawn as of v2.7" and prints no syntax. | **Permanent** for v2.7.1. |
| UDM_Q05 (CH05 5.10.1.2) | Retained for backward compatibility; prints URD and `[URS]`, which no v2.7.1 chapter defines, so it cannot be checked against the v2.7.1 grammar. | **Permanent** for v2.7.1. |
| QRY_PC4 (CH12 12.3.5, 12.3.7, 12.3.9, 12.3.11), RCI_I05, RQC_I05 (CH11 11.3.5), RCL_I06 (CH11 11.3.6) | Each prints QRD and `[QRF]`, the original-mode query segments "retained for backward compatibility only as of v 2.4 and withdrawn as of v2.7" (CH04A, p 105; CH02, p 35), which no v2.7.1 chapter defines; found by the default structure guard (segments outside the version grammar) in the pre-commit corpus run. On v2.6 the four are modelled; on v2.8.2 they are Table 0354 rows marked Deprecated. | **Permanent** for v2.7.1. |
| 39 Table 0354 rows marked Deprecated (CH02C 2.C.2.175, pp 102 to 106): ADR_A19, ADT_A18, ADT_A30, DOC_T12, MFN_M01, MFN_M03, MFQ_M01, MFR_M01, MFR_M04, MFR_M05, MFR_M06, MFR_M07, NMQ_N01, NMR_N01, ORF_R04, ORM_O01, ORR_O02, ORU_W01, OSQ_Q06, OSR_Q06, OUL_R21, QCK_Q02, QRF_W02, QRY_A19, QRY_Q01, QRY_Q02, QRY_R02, QRY_T12, RAR_RAR, RER_RER, RGR_RGR, ROR_ROR, RSP_Q11, SQM_S25, SQR_S25, SUR_P09, VXQ_V01, VXR_V03, VXX_V02 | The Comment column of the printed table marks each Deprecated (five "Deprecated and removed as of V2.7") and no v2.7.1 chapter prints its syntax. | **Permanent** for v2.7.1 (by design). |

Two normative prints of one structure ID that disagree (P8b-9 ruling): the looser print is
committed, cited to both (overrides.json `primaryPrints`). No v2.7.1 pair needed a union.

| Structure (v2.7.1) | Looser print, committed | Stricter print, not checked | Cost | Status |
|---|---|---|---|---|
| ACK | CH10 10.4 (ACK^S12-S24,S26,S27, p 18): `[{UAC}]` | CH02 2.13.1 (p 46): `[UAC]` (and every chapter's ACK; CH05 5.4.4 to 5.4.7 also print `[ERR]`) | An ACK with several UAC segments passes. | **Blocking** (per-trigger structures). |
| RQC_I05 (recorded; not modelled, see above) | CH11 11.3.5 (RQC^I05, p 13): `[{GT1}]` | CH11 11.3.6 (RQC^I06, pp 14 to 15): `[GT1]` | None while RQC_I05 is not modelled. | Recorded for a later grammar that defines QRD and QRF. |

Reader fixes (extractor, each with a self-check case): CH07 7.17.1 prints OSM^R26^OSM_R26's own
`CODE^EVT^STRUCT` in place of "Segments" in its header row, and wraps the last word of a group
mark onto the line with "begin" or "end" (`--- SUBJECT POPULATION/LOCATION` then
`IDENTIFICATION begin`). Cited errata: the `RESOURCED_DETAIL end` marks of CCM_I21, CCR_I16,
CCU_I20, CQU_I19 and CCI_I22; EHC_E01 `INVOICE INFORMATION`; OPL_O37 `Observation/Result_Group`
(read as OBSERVATION_RESULT); OSM_R26's two subject group marks; SDR_S31 and SDR_S32
`ANTI-MICROBIAL_...`; ADT_A05 `Procedure` (3.3.31); RQI_I01 `GUARANTOR+INSURANCE` (11.3.3); and
BRP_O30's unclosed PATIENT group (a syntax-cell erratum, as on v2.6). The 8.4.3 exclusion is
scoped to the MFN^M14^MFN_Znn caption, so MFK^M14^MFK_M01 is read. Other print disagreements
recorded, not modelled: RDE_O11's 4A.3.13 (RDE^O25) print names the RXC group COMPONENTS where
the 4A.3.5 print says COMPONENT (same syntax); CH15 15.3.7 captions QBP^Q25^QBP_Q21 over a
query parameter table, not a syntax. The HL7 v2.xml bundles differ from the print for the no-bar
`< ... >` named groups of EHC_E01, E02, E04, E15, E20, E21, E24, QBP_E03, QBP_E22, RSP_E03 and
RSP_E22 (the CH16 text never says "one of" for them: named required groups, P8b-6 ruling),
SDR_S31 and SDR_S32 (likewise, under the hyphenated name), ADT_A09 and ADT_A12 (the bundle adds
DG1), ADT_A60, DFT_P03 and DFT_P11 (a VISIT group the print does not have), OSM_R26 (a
PATIENT_INFORMATION group), ORU_R01 (the bundle names the SPECIMEN observations
PATIENT_OBSERVATION) and ACK (UAC); the print is normative (ruling D3). Table 0354 adds ADT^A39
to ADT_A39, MFK^M01 and MFK^M03 to MFK_M01 (8.4.1 marks M01 withdrawn) and RPI^I04 to RPI_I01;
RPI^I04 is a declared shared trigger, ambiguous without MSH-9.3, as on v2.5.1, v2.6 and v2.8.2.

Known cost of exact matching: 20 v2.7.1 structures fail the determinism lint (ADT_A60, BAR_P01,
BAR_P05, CSU_C09, DFT_P03, DFT_P11, EHC_E15, OMD_O03, OMG_O19, OML_O21, OML_O33, OML_O35, OPL_O37,
ORD_O04, OSM_R26, OUL_R24, REF_I12, RPA_I08, RQA_I08 and RRI_I12) and are matched by the exact
matcher, with at most one finding and no group spans.

### Addendum to §E — v2.4 complete (P8b-13, 2026-10-04)

v2.4 is `complete: true` in `Resources/structures/completeness.json`: 148 structures modelled
(each cited to chapter, section and pages; QRY_Q02 and QCK_Q02 since the P8b-13 fix round,
below) and 24 registered as not modelled in that file's
`notModelled`; every Table 0354 v2.4 row is one or the other. v2.4 is the first version whose
print names no group: 298 group names come from the HL7 v2.xml v2.4 bundle, 35 from cited
`overrides.json` `groupNames` entries and 1 is synthesised (below).

| Not modelled (v2.4) | Why | Status |
|---|---|---|
| PGL_PC6, PPR_PC1, PPP_PCB, PPG_PCG, PRR_PC5, PPV_PCA, PTR_PCF, PPT_PCL (CH12 12.3.1 to 12.3.12) | The order detail is printed `[OBR, etc.`; the CH12 note before 12.3.1 reads "OBR etc." as every combination of order detail segments per CH04 4.2.2.4 (p 4-10), which names only examples (OBR, RXO) (ruling G6). | **Permanent** for v2.4. |
| QBP_Q11, RSP_K11, QBP_Q13, QBP_Q15, QVR_Q17 (CH05 5.4.1 to 5.4.5) | Query templates: a `[...]` row stands for the segments a conformance statement defines (ruling G6). | **Permanent** for v2.4. |
| MFN_M01 (CH08 8.4.1), MFR_M01 (8.4.3), MFN_M03 (8.8.2) | Master file templates: `[Z..]` after MFE, and MFN_M03's `??? [other segments(s)]` for the M08 to M12 groups (ruling G6). | **Permanent** for v2.4. |
| ERP_R09 (CH05 5.10.4.2, p 5-116; also v2.5.1 p 5-120) | Ellipsis rows after ERQ stand for "the segments indicated by the ellipsis", the remainder of another message (ruling G6). A corpus misfire in P8b-13: the extractor had dropped the rows and committed `MSH MSA [ERR] QAK ERQ [DSC]` on v2.4 and v2.5.1; an ellipsis row is now a placeholder and ERP_R09 is registered on both versions. | **Permanent** for v2.4 and v2.5.1. |
| SUR_P09 (CH07 7.11.2) | A row `ED Encapsulated Data`: v2.4 defines no ED segment (ED is a data type). | **Permanent** for v2.4. |
| QRY_P04, DSR_P04 (CH06 6.4.4, p 6-13) | The captions print no syntax, only "see Chapter 5" (the original-mode display query). | **Permanent** for v2.4. |
| ORU_W01, QRF_W02, RRA_O02, RRE_O02 | Table 0354 v2.4 rows (Appendix A; CH02 2.17.3) with no printed syntax. | **Permanent** for v2.4. |

P8b-13 fix round (2026-10-04). The addendum first registered QRY_Q02 and QCK_Q02 here as
"no v2.4 chapter prints its syntax". That was false: CH05 5.10.3.1 (p 5-112) prints
"QRY^Q02 (A to B)  Query Message" (MSH, QRD, [QRF], [DSC]) and "QCK^Q02 (B to A)  Query
General Acknowledgment" (MSH, MSA, [ERR], [QAK]). The reader required two spaces after
`CODE^EVT` and so never read a caption with a one-space direction tag. Both are now modelled
(Table 0354 maps Q02 to both IDs; MSH-9.1 tells them apart; v2.4 defines QRD and QRF). The
same captions print in v2.5.1 (p 5-116) and v2.6 (p 96), which had registered both for the
same reason; both are modelled there too. The third such caption, "ACK^Q03 (A to B)" (p 5-113),
prints MSH, MSA, [ERR], identical to the primary ACK print (CH02 2.14.1), and ACK already
carries `ACK^*`, so reading it changes no structure. The P8b-3a/3b report counts (162 groups
named, 6 synthesised, 130 parsed, 10 lint-failing) predate P8b-13's reader fixes and errata:
those raised the parsed prints from 130 to 146 (148 with this round), more parsed prints
brought more groups to name (298 from the v2.4 bundle), the 6 synthesised groups of ORL_O22
and RAS_O17 took cited `groupNames` overrides (35 in all), leaving DFT_P03's one synthesised
group, and 18 committed structures fail the lint and are exact-matched (ADR-019, P8b-12).

Looser prints. Every duplicate print of a v2.4 structure (ACK, ADT_A09, MFK_M01, RQC_I05) is
stricter than its primary print, so no `primaryPrints` or `unionPrints` entry was needed. One
print is looser than its own intent:

| Structure (v2.4) | Committed, as printed | Stricter reading, not checked | Cost | Status |
|---|---|---|---|---|
| REF_I12 (CH11 11.5.1, pp 11-16 to 11-17) | The print repeats the optional `[ PV1 [PV2] ]` group twice before the closing `[{NTE}]` | One PATIENT_VISIT group, as RRI_I12 in the same section, HL7-xml v2.4/REF_I12.xsd and the v2.5.1 print give it | A REF with two visit groups passes. | Recorded; the print is normative (ruling D3). |

Group names (ADR-019 decision 3). The v2.4 bundle has no xsd for DOC_T12, OSR_Q06, SQM_S25,
SQR_S25, VXR_V03, VXU_V04 and VXX_V02: their 25 groups take the v2.5.1 bundle's name for the
same structure ID, parent path and first segment, with the same member set or a superset adding
only segments v2.4 does not define (TQ1 and TQ2: VXU_V04 and VXR_V03 ORDER, SQR_S25 SCHEDULE,
OSR_Q06 RESPONSE and ORDER). ORL_O22's four groups take the v2.4 bundle's names by member set
(the bundle nests them under a PATIENT group the print does not have); RAS_O17's RXA group is
ADMINISTRATION (the v2.5.1 bundle) and its OBX group OBSERVATION (both bundles); DFT_P03's FT1
group is FINANCIAL (the v2.4 bundle's one root FT1 group; the print adds DG1, DRG, GT1 and an
insurance group per FT1, its footnotes 3 to 5); RCI_I05's group is OBSERVATION and its inner
group RESULTS, where the v2.4 bundle names the group `c`, which no group name can hold (the
v2.5.1 and v2.6 bundles say OBSERVATION). One name is synthesised: DFT_P03's per-FT1 insurance
group, IN1_GROUP, which no bundle names. Each is cited in the structure's citation.

Reader fixes (extractor, each with a self-check case): a footnote mark fused to a bracket
(`[{1`, `}]3`; CH06 DFT_P03, CH12 PTR_PCF) is dropped; a bracket-only cell drifted into the
description column (CH11 RQA_I08, REF_I12, RRI_I12) is syntax; a `CODE^EVT` row at depth 0
(CH05 DSR^Q03 then `ACK^Q03 (A to B)`) ends the table; an ellipsis row inside a table is a G6
placeholder (ERP_R09). Cited errata (syntax-cell, confirmed by the v2.4 bundle bounds): OMG_O19
`{[` read `[{` (PRIOR_RESULT), ORD_O04 `]}` read `}]` (ORDER_TRAY), OUL_R21 `[PV2]]` read
`[PV2]` (VISIT), and OML_O21's fourth bare `]` read `}` (ORDER_GENERAL; a new optional
`occurrence` key). Shared triggers: MFN^M02 to M06 (the MFN^M01-M06^MFN_M01 template caption),
RPI^I04 (Table 0354 lists I04 under RPI_I01, a row the CH02 print spells `RPI_I0I`) and RSP^K24
(Table 0354 lists K24 under RSP_K23); each is ambiguous without MSH-9.3. Two duplicate prints
stay unreadable and are reported only: ADT^A31^ADT_A05 (3.3.31, `{ ROL }]`) and CH15 15.3.7's
QBP^Q25^QBP_Q21 caption over a query parameter table. The HL7 v2.xml v2.4 bundle also differs
from the print for CSU_C09 (CSP bounds), NMR_N01, ORR_O02 (the bundle's ORDER_DETAIL for the
printed choice) and DFT_P03 (a VISIT group the print does not have); the print is normative.

Known cost of exact matching: 18 v2.4 structures fail the determinism lint (BAR_P01, BAR_P05,
CSU_C09, DFT_P03, NMR_N01, OMD_O03, OMG_O19, OML_O21, ORD_O04, ORF_R04, ORL_O22, ORU_R01,
OUL_R21, RCI_I05, REF_I12, RPA_I08, RQA_I08 and RRI_I12) and are matched by the exact matcher,
with at most one finding and no group spans (among them ORU_R01, whose v2.4 OBSERVATION group
is `{[OBX] [{NTE}]}`).

### Addendum to §E — v2.3.1 complete (P8b-14, 2026-10-04)

v2.3.1 is `complete: true` in `Resources/structures/completeness.json`: 99 structures modelled
(each cited to chapter, section and pages of the one v2.3.1 PDF) and 27 registered as not
modelled in that file's `notModelled`; every Table 0354 v2.3.1 row (Chapter 2, section
2.24.1.9, pp 2-103 to 2-106; 117 rows) is one or the other. Most v2.3.1 captions print
`CODE^EVT` only: the structure ID comes from that table. Nine printed IDs have no row (ACK,
folded onto `ACK^*` through CH02 2.13.1, and the eight structures of the shared triggers
ORM^O01 and ORR^O02, whose captions print their IDs).

| Not modelled (v2.3.1) | Why | Status |
|---|---|---|
| ORM_O01 (CH04 4.2.1, p 4-3), ORR_O02 (4.2.2, p 4-4), OSR_Q06 (4.2.3, p 4-5) | The order detail is printed `Order Detail Segment OBR, etc.` (OSR^Q06 in the description column). Use note b (p 4-3) reads it as "whichever of these order detail segment(s) is appropriate ..., currently OBR, RQD, RQ1, RXO, ODS, ODT", 4.1.2.4 (p 4-2) names only examples, and 4.7 (p 4-53) has RQD followed by RQ1 replace it: one segment or a combination is not fixed by the print (ruling G6). | **Permanent** for v2.3.1. |
| PGL_PC6, PPR_PC1, PPP_PCB, PPG_PCG, PRR_PC5, PPV_PCA, PTR_PCF, PPT_PCL (CH12 12.2.1 to 12.2.12) | `[OBR, etc.`; the CH12 note before 12.2.1 (p 12-7) reads it as every combination of order detail segments per CH04 4.1.2.4 (ruling G6). PTR_PCF also prints `{NTE}]` with no opening bracket. | **Permanent** for v2.3.1. |
| ERP_R09 (CH02 2.20.3, p 2-86) | Ellipsis rows after ERQ (ruling G6). | **Permanent** for v2.3.1. |
| MFN_M03 (CH08 8.7.2, p 8-20) | `??? [other segments(s)]` after OM1; the section then gives the groups that replace it per file in prose, each keyed by the second component of MSH-9 (M08 to M11), and for M03 the row stands for any of them. Corrected in P8b-15 fix round 1: the earlier reason said the print does not fix the combination; it does, per event, in fragments the extractor does not read. | **Blocking** (reading prose-printed fragments and cross-references). |
| SUR_P09 (CH07 7.10.2, p 7-85) | A row `ED Encapsulated Data`: v2.3.1 defines no ED segment. | **Permanent** for v2.3.1. |
| MFN_M01, MFN_M02, NUL, ORM_Q06, ORR_Q06, RAS_O02, SRM_T12, SRR_T12 | Table 0354 rows no caption prints (searched in every caption form): MFN_M01's only print is the 8.3.1 template captioned MFN^M01-M06, MFN_M02's the 8.6.1 staff print captioned MFN^M01-M06 (neither caption's six events is one row's); NUL names no message. | **Permanent** for v2.3.1. |
| MFN_M08 to MFN_M11, ORU_W01 | Table 0354 rows no caption prints: M08 to M11 are printed only as prose fragments keyed by MSH-9 event under MFN^M03 (8.7.2, p 8-20); ORU_W01 is prose in CH07 7.19.1 (p 7-117) with ORU^W01 examples. A reader for prose-printed fragments and cross-references would close them (status corrected from Permanent in P8b-15 fix round 1). | **Blocking** (reading prose-printed fragments and cross-references). |
| Captions with no structure ID: MFN^M01-M06 (8.3.1, p 8-3; 8.6.1, p 8-11), MFQ^M01-M06 (8.3.3, p 8-4), MFN^M04 (8.9.1, p 8-60) | Table 0354 lists no row for their events (no MFQ or MFN_M04 row) and no row lists all six of a range; declared in `overrides.json` `unresolvedCaptions` and reported info on the wire. MFN^M01-M06 at 8.3.1 is also a `[Z..]` template. | **Permanent** for v2.3.1. |
| MFR^M01-M06 (8.3.3, p 8-4) | Table 0354 lists no MFR row; declared in `unresolvedCaptions`, info on the wire. The 8.3.3 print has a `[Z..]` row, but the master file sections give its segments per file in prose (8.6.1 p 8-11, 8.7.2 p 8-20, 8.8.1 p 8-49, 8.9.1 p 8-60, 8.10.1 p 8-68: 'When the ... segments are used in the MFR message, the part ... is replaced by'); only M01's cannot be enumerated (status corrected from Permanent in P8b-15 fix round 1). | **Blocking** (reading prose-printed fragments and cross-references). |
| MCF (CH02 2.13.2, pp 2-78 to 2-79) | The delayed acknowledgment, kept for v2.1 compatibility, is printed twice under the code alone (MSH, MSA, [ERR]); Table 0354 has no MCF row and Table 0003 no event for it, so no structure ID names it; an MCF message is info. | **Permanent** for v2.3.1. |

Structure IDs (each a cited `overrides.json` entry, defensible from the v2.3.1 print alone).
Table 0354 errata, each against Table 0076 or 0003 and the caption: ARD_A19 read ADR_A19 (no
message type ARD); ADT_A30's event `136` read A36; RPA_I08's `1II` read I11; PIN_107, RPI_I0I
and RQI_I0I read PIN_I07, RPI_I01 and RQI_I01 (a digit and a letter swapped); PPG_PCG's `PCC, PCH, PCJ`
read `PCC, PCG, PCH, PCJ` (PCG added, the event its ID and the CH12 12.2.4 caption name; PCC
kept, as the v2.4, v2.5.1 and v2.7.1 tables keep it, though Table 0003 gives PCC to PPP;
fix round 1); TBR_R09/R09 read TBR_R08/R08 (R09 is ERP's); RRE_O01/O01
read RRE_O02/O02 (Table 0003: "O02 ORR - Order response (also RRE, RRD, RRG, RRA)"); MFD_P09/P09
read MFD_MFA/MFA (P09 is SUR's; CH08 8.2 names MFA). Caption errata: CH08 8.10.1 prints Case 2,
the clinical study without phases (Table 0003 M07), under MFN^M06 and MFK^M06 a second time;
read as M07 (a new optional `occurrence` on caption errata), so MFN_M07 is modelled and MFN_M06
keeps Case 1 alone. Declared readings: ADT^A28 and ADT^A31, which Table 0354 lists under both
ADT_A01 and ADT_A28, are declared shared triggers and their print (identical to ADT^A01's) is
each structure's; MFK^M01-M06 (8.3.1, 8.6.1) and MFK^M04 are read as MFK_M01 and PPP^PCB, PCC,
PCD as PPP_PCB (`captionStructures`: the one row of the message code omits M02 and M04, or PCC).
With the general print of 8.3.1 primary, MFK_M01 allows `[ERR]`; the other five MFK prints omit
it and are stricter.

Misprinted IDs on the wire (controller ruling, P8b-14 fix round 1). The two-token Table 0354
errata stand, so a v2.3.1 message that copies a misprinted row literally is a mismatch, at the
configured severity, not a match: `TBR^R09^TBR_R09` (Table 0003, p 2-101, gives R08 to TBR and
R09 to ERP, whose row ERP_R09 lists R09; CH2 2.20.2, p 2-86, prints TBR^R08),
`RRE^O01^RRE_O01` (Table 0003, p 2-100, gives O02 to the order responses "also RRE, RRD, RRG,
RRA"; CH4 4.8.6, p 4-70, prints RRE^O02) and `MFD^P09^MFD_P09` (Table 0003, p 2-100, gives P09
to SUR; CH8 8.2, p 8-3, names MFA and 8.3.2, p 8-4, prints MFD^MFA); likewise the one-token
misprints `PIN_107`, `RPI_I0I`, `RQI_I0I` and `ARD_A19`. The v2.4 Table 0354 corrects exactly
these rows (TBR_R08, RRE_O02, MFD_MFA, PIN_I07, RPI_I01, RQI_I01, ADR_A19). Every v2.3.1
structure whose ID came from the table carries "Structure ID from Table 0354 v2.3.1" in its
citation, naming the erratum or declaration involved (90 of 99; ACK and the eight ORM^O01 and
ORR^O02 structures print their IDs). The other event errata were checked for the same
replace-instead-of-add shape: `136` and `1II` are not events, RAS_O02's `O022` is not an event,
and TBR's R09, RRE's O01 and MFD's P09 are events of other messages by Table 0003, so only
PPG_PCG's needed a union.

Group names (ADR-019 decision 3; owner ruling 2026-10-04). v2.3.1 prints few group names: 247
come from the HL7 v2.xml 2.3.1 bundle (`HL7-xml 2.3.1`, a folder name with no "v"), 6 through
the v2.4 bundle (MFN_M05, MFN_M06, MFN_M07 and RPR_I03) and none is synthesised. The 2.3.1 bundle mixes two generators, the HL7-Database generator of the other
five bundles (33 files) and an encoder generator (namespace `urn:com.sun:encoder-hl7-1.0`, 83
files); every citation names the generator of the file it reads. The bundle's CHOICE name is refused
without a cited override; no CHOICE group is named (the structures that would use it are
registered). ENCODING was refused too at first; it is a genuine group name in the 2.3.1 bundle
(RXE {RXR} [{RXC}], as in every later bundle), so since fix round 1 the seven ENCODING groups
(RAR_RAR, RAS_O01, RDR_RDR, RDS_O01, RGR_RGR, RGV_O01, RRE_O02) are named from it. Where the 2.3.1 bundle has no file for the structure ID, a file of the same
message code is matched on first segment and member set (ORF_R02 from ORF_R04.xsd, ADT_A28 from
ADT_A01.xsd). The bundle differs from the print, report only, for ADT_A18 (MRG required in the
print), ADT_A38 (DRG optional in the print), RDE_O01 and RDS_O01 (the print's `{ [OBX] [{NTE}] }`)
and REF_I12 (the print's two PATIENT_VISIT groups, as on v2.4).

Reader fixes (extractor, each with a self-check case; no v2.4 to v2.8.2 report row or structure
changes): `CODE ^EVT` with one space before the caret (CH08 8.8.1 `MFN ^M05`, `MFK ^M05`) is a
caption; notation in the description column inside an open group (`[Order Detail Segment] OBR,
etc.`, CH04 OSR^Q06) is a G6 placeholder, where it had been dropped and OSR_Q06 written without
its order detail; on a version that prints its own Table 0354, a caption the table cannot
resolve fails a full read unless a cited erratum, declared shared triggers, a `captionStructures`
or an `unresolvedCaptions` entry settles it. The Table 0354 errata also gave v2.3 (which then read
v2.3.1's table) the corrected IDs; since P8b-15 v2.3 reads no Table 0354 (its IDs are synthesised,
v2.3 addendum below).

Known cost of exact matching: 10 v2.3.1 structures fail the determinism lint (CSU_C09, OMD_O01,
ORD_O02, ORF_R02, ORU_R01, RCI_I05, REF_I12, RPA_I08, RQA_I08 and RRI_I12) and are matched by the
exact matcher, with at most one finding and no group spans (among them ORU_R01 and ORF_R02, whose
OBSERVATION group is the pre-v2.5 `{ [OBX] [{NTE}] }`). Corpus run (P8b-14): no misfire; six v2.3.1 spec examples
draw findings that are example defects (CH04 4.14.5 sends ACK with QAK; five CH10 10.6 examples
print AIP before AIL).

### Addendum to §E — v2.3 complete (P8b-15, 2026-10-04)

v2.3 is `complete: true` in `Resources/structures/completeness.json`, the last version: 147
structures modelled (each cited to chapter, section and pages of the CH1 to CH12 PDFs) and 24
registered as not modelled in that file's `notModelled` (16 unreadable prints and, since fix
round 1, 8 triggers defined only in prose or Table 0003). v2.3 prints the message code alone over
each table, the events in the section title, no structure ID and no Table 0354, and its MSH-9 has
no third component. Lookup rule 3: a v2.3 message resolves from MSH-9.1^9.2 only; a populated
MSH-9.3 is ignored, so rule 1's mismatch for an unknown ID never applies on v2.3. Structure IDs
are synthesised `CODE_EVT` (the code and the first event of the section title) and flagged so in
each citation; they are internal keys no v2.3 message carries. 252 captions read: 4 excluded (the
CH02 2.11.1 WRQ/WRP notation example, ruling G7), 248 resolved to 163 structure IDs (every ACK
caption folds onto ACK).

| Not modelled (v2.3) | Why | Status |
|---|---|---|
| ORM_O01 (CH04 4.2.1, p 4-4), ORR_O02 (4.2.2, p 4-5), OSR_Q06 (4.2.3, p 4-6) | The order detail is printed `Order Detail Segment OBR, etc.`; use note b (p 4-4) reads it as "whichever of these order detail segment(s) is appropriate ..., currently OBR, RQD, RQ1, RXO, ODS, ODT", 4.1.2.4 (p 4-3) names examples only and 4.7 (p 4-54) has RQD followed by RQ1 replace it, so one-of versus combination is not fixed (ruling G6). Sections 4.6, 4.7 (twice) and 4.8.1 print specialised ORM and ORR tables (diet, stock, nonstock, pharmacy) under the same O01 and O02 (Table 0003; cited `eventsFromTitle`), which MSH-9.1^9.2 cannot tell apart on v2.3: they are recorded as further prints of ORM_O01 and ORR_O02, not modelled. | **Permanent** for v2.3 (an ORM^O01 or ORR^O02 message is info). |
| PGL_PC6, PPR_PC1, PPP_PCB, PPG_PCG, PRR_PC5, PPV_PCA, PTR_PCF, PPT_PCL (CH12 12.2.1 to 12.2.12, pp 12-8 to 12-16) | `[OBR, etc.`; the CH12 note before 12.2.1 (p 12-7) reads it as every combination of order detail segments per CH04 4.1.2.4 (ruling G6). PTR_PCF also prints `{NTE}]` with no opening bracket. | **Permanent** for v2.3. |
| ERP (CH02 2.20.3, p 2-77), MFN_M01 (CH08 8.3.1, p 8-4) | Ellipsis rows after ERQ, the remainder of the record-oriented message the query names; `[Z..]` for the segments of a master file not otherwise specified (ruling G6). | **Permanent** for v2.3. |
| MFR_M01 (CH08 8.3.3, p 8-5; events M01 to M11), MFN_M03 (8.7.2, p 8-21; events M03, M08 to M11) | MFR prints `[Z..]`, but the master file sections give its segments per file in prose ('the part ... {MFE [Z..]} is replaced by'): 8.6.1 (p 8-12) for M02, 8.7.2 (p 8-21, 'replacing the [Z...] section') for M03 and M08 to M11, 8.8.1 (p 8-50) for M05, 8.9.1 (p 8-63) for M04, 8.10.1 (pp 8-71 to 8-72) for M06 and M07; only M01's `[Z..]` cannot be enumerated. MFN prints `[other segments(s)]`, whose groups the section gives per MSH-9 event M08 to M11 in prose. Neither is modelled because the extractor does not read prose-printed replacement fragments (corrected in P8b-15 fix round 1: the first reason said the segments cannot be enumerated). | **Blocking** (reading prose-printed fragments and cross-references). MFR^M01 to M11 and MFN^M03, M08 to M11 are info. |
| SUR_P09 (CH07 7.10.2, p 7-80) | A row `ED Encapsulated Data`: v2.3 defines no ED segment. | **Permanent** for v2.3. |
| Prose-only triggers (P8b-15 fix round 1): QRY_P04 (QRY^P04; CH06 6.3.4, p 6-4, 'the QRY/DSP transaction, as defined in Chapter 2'), ORU_W01 (ORU^W01; CH07 7.19.1, p 7-113, with ORU^W01 examples in 7.20), QRF_W02 (QRF^W02; 7.19.2, p 7-113; QRF is in no Table 0076 row), QRY_R03 and DSR_R03 (R03; Table 0003 only, p 2-93), QRY_R05 and DSR_R05 (R05; CH07 7.2.2.1, p 7-15), UDM_R06 (R06; 7.2.2.1, p 7-15) | Each event is defined in prose or Table 0003 (Chapter 2, section 2.24.1.9, pp 2-90 to 2-93), by reference to another message, and no v2.3 chapter prints a syntax table for it. Registered in `completeness.json` `notModelled` under a synthesised CODE_EVT ID with the trigger and this reason, as v2.3.1 registers ORU_W01, so the info names why. The extractor reads structures from syntax tables only. | **Blocking** (reading prose-printed fragments and cross-references). |

Events. 201 captions take their events from the section title (`(event A01)`, `(events C01-C08)`,
first event for the ID). 39 captions whose title names none, or names them as `O01/O02`, take them
from a cited `eventsFromTitle` entry: CH04 4.6, 4.7 and 4.8.1 ORM O01 and ORR O02 (Table 0003);
RDE, RDS, RGV O01 and RRE, RRD, RRG, RRA O02 (the title pairs them; Table 0003 "O01 ... also RDE,
RDS, RGV, RAS", "O02 ... also RRE, RRD, RRG, RRA"); RAS O02 as its title prints it and O01 added
(Table 0003 and the three sibling sections; a corrected event list is added to, never reduced);
CH08 MFN and MFK per master file section (M01 for the 8.3.1 template; M02 8.6.1; M03 and M08 to M11
8.7.2, whose text names those MSH-9 events; M05 8.8.1; M04 8.9.1; M06 and M07 the two cases of
8.10.1), the general MFK of 8.3.1 also for the events whose sections print no MFK (M03, M08 to M11),
MFD MFA (8.2 names it), MFQ and MFR M01 to M11 (Table 0003 "varies ... use event same as asking
for"); CH10 SRM and SRR S01 to S11 and SIU S12 to S24 and S26 (the sections that "use this message
definition"); CH11 RQA and RPA I08 to I11, REF and RRI I12 to I15 (the sections the message
definition names). Four codes print no event anywhere and Table 0003 lists none for them: MCF
(2.13.2), EDR, TBR, ERP (2.20; the Chapter 2 examples send MSH-9 `TBR` and `ERP` alone): each is
folded onto `CODE^*` with the code as its ID, as ACK is.

Errata (each cited in `overrides.json`, defensible from the v2.3 print alone). Caption: CH04 4.8.17
prints `R0R` with a digit zero for the code and the event; Table 0076 (p 2-89) defines ROR, and the
sibling responses RAR, RDR, RER, RGR carry their code as their event: read as ROR^ROR with the
printed R0R kept, so `ROR^ROR` and `ROR^R0R` both resolve to ROR_ROR. Syntax cells: ADT^A07's
`[{ROL]}` (3.2.7, p 3-8), ADT^A31's `{[ROL}]` (3.2.31, p 3-25) and CSU's `{[[ORC] ... }]` (7.6.2,
p 7-65) cross their brackets, which CH02 notation cannot nest; both nested readings mean an
optional repeating element, so the reading chooses no meaning.

Group names (ADR-019 decision 3; controller carry-in). v2.3 prints no group names: 235 are derived
through the HL7 v2.xml 2.3.1 bundle (`v2xml-v2.3.1`, cited `HL7-xml 2.3.1/<file>.xsd` with its
generator; a synthesised ID such as ADT_A04 matches a same-code 2.3.1 file on first segment and
member set, citing both IDs), 7 through the v2.4 bundle and 3 are synthesised (ORU_R01's patient
groups, whose v2.3 member set lacks the NK1 of v2.3.1 and later; SIU_S12's patient group).

Reader fixes (extractor, each with a self-check; no v2.3.1 to v2.8.2 report row or structure
changes): v2.3 captions `QRY (A to B)` and its three siblings (CH02 2.18, which had been missed), a
code one space from its title or with no Chapter column when the next row is MSH (RRE, RRA, MDM^T10
and the five CH04 4.8.17 to 4.8.21 query responses), the rows' description column from the MSH row
(RRD and RRG had been cut short after ERR); a closing bracket or syntax cell one space from its
description (UDM's `{   DSP   } Display Data`, ADR's `[{ROL}] Role`, CSU's `{RXA Pharmacy
Administration`) and a page set right of the caption (RDR) are rows. A scan of every v2.3 table for
syntax rows left after the read table ends found none outside the registered MFN_M03.

Known cost of exact matching: 10 v2.3 structures fail the determinism lint (ADT_A06 and ADT_A07,
which print DRG twice; CSU_C09; ORF_R02 and ORU_R01, the pre-v2.5 OBSERVATION group; RCI_I05,
REF_I12, RPA_I08, RQA_I08, RRI_I12) and are matched by the exact matcher, with at most one finding
and no group spans. RQA_I08 is modelled as printed, `[ [{GT1}] {IN1 [IN2] [IN3]} ]` (11.3.1,
p 11-12): an insurance group follows GT1 within one optional group, where RPA, REF and RRI print
`[{GT1}] [{IN1 ...}]`; the print is followed, not the siblings. Triggers the print covers only in
prose or Table 0003 (QRY^P04, ORU^W01, QRF^W02, QRY and DSR R03 and R05, UDM^R06) name no syntax
table; they are registered with their reason (table above) and are info. Corpus run (P8b-15): no misfire; 11 spec-example messages draw findings that are
example defects (five CH10 10.6 examples print AIP before AIL; three CH03 3.4.2 ADT examples order
OBX against the print; CH04 4.14.5 sends ACK with QAK; two CH06 6.5 BAR^P05 examples omit EVN).

### Addendum to §E — HL7au:00060.1 through the ADRM-2021 structures (P8b-4, 2026-10-04)

Under `.auLocalisation` with `messageStructureSeverity` set, a v2.4 message whose base structure
resolves to ORU_R01, ORM_O01 or REF_I12, and whose MSH-9.1^9.2 the ADRM-2021 prints for it, is
also matched against the ADRM structure in `Resources/structures/profiles/au-adrm-2021/`
(ORU^R01 pp 205 to 206, reprinted pp 17 to 18; ORM^O01 pp 279 to 280; REF^I12 pp 324 to 325). A
segment the ADRM structure requires and the message lacks is reported as
`profileConstraintViolation(localeRule: "HL7au:00060.1")`; a removed base segment is not a
finding (ADR-019 decision 7), and one the base match already reports missing at the same place is
not reported again. The conformance register classes 00060.1 PARTIAL. What is not enforced, each
blocking spec-completeness of the segment half of 00060.1:

| Gap | Print | Why it is not enforced |
|---|---|---|
| ORU^R01 PV1 when PD1, NK1 and PV2 are all absent | p 17 ("in Australia PV1 has been made mandatory") and p 205 ("The PV1 segment is also mandatory"), against the prints on pp 17 and 205, which place PV1 inside `[ [PD1] [{NK1}] PV1 [PV2] ]` | Print and prose disagree. The print is enforced (PV1 required when the group is present), which every reading agrees on; a PID with no visit group at all draws nothing. A ruling (print or prose) would close it |
| RRI^I12 | p 325: `MSH MSA [ERR] [ RF1 {PRD} PID ]`, MSA unbracketed (base v2.4 `[MSA]`); the prose says the RF1, PRD and PID group "has been made optional for backward compatibility" | Closed by P8b-4a: `RRI_I12.json` requires MSA, and the base findings its optional group and `[ERR]` accept are dropped (addendum below) |
| Appendix 8 simplified REF structure | pp 484 to 485 ("Constrained REF_I12 message structure", normative; the OBR group and OBX required) | It applies only to messages declaring the simplified REF profile in MSH-12 (pp 483 to 484); the overlay has no MSH-12-gated structure variant |
| ORR^O02 | pp 280 to 281: `[ [PID ... {ORC OBR} ]`, one `[` unclosed | The bracket erratum leaves PID's optionality undecidable, so no structure is modelled; read as for ORM^O01 (p 280: OBR, or RXO, ODS or ODT for medication and diet orders), the order detail would also exclude the base RQD and RQ1, which is not enforced either |
| Narrowed maxima | REF^I12 p 324 prints `[IN1]` where the base repeats the insurance group `[{ IN1 [IN2] [IN3] }]`, and PV1 and `[PV2]` once where the base (v2.4 CH11 pp 11-16 to 11-17) prints `[ PV1 [PV2] ]` twice. These are every narrowed maximum in the five modelled ADRM structures (ORU_R01, ORM_O01, REF_I12, RRI_I12, OSR_Q06, each segment's maximum compared with the base's, P8b-4a) | 00060.1 is about required elements; an ADRM maximum below the base is not enforced (the overlay drops `unexpected` and beyond-maximum findings, ADR-019 decision 7). A second IN1, PV1 or PV2 on REF^I12 therefore draws no finding under AU |
| Order status response | p 281 (`[{OBX}]` inside the order; base v2.4 OSR_Q06 has no OBX; its PID is optional in the base as well) | Closed by P8b-4a fix round 1: `OSR_Q06.json` models it, citing the caption erratum `OSQ^Q06^OSQ_Q06` for OSR^Q06, so the base OBX finding is dropped under AU. Order detail: the p 281 print says only "OBR Order Detail", with no prose on this message; the base v2.4 choice (OBR, RQD, RQ1, RXO, ODS, ODT) is kept because the print does not settle whether the p 280 narrowing for ORM^O01 applies to the response, so a status response carrying RQD or RQ1 is not flagged |

The other ADRM prints add nothing over the base for a missing segment: ACK^R01 (p 206) and
ACK^O01 (p 280) print MSH MSA [ERR], the base ACK; OSQ^Q06 (p 281) is the base; the order status
response (p 281, captioned "OSQ^Q06^OSQ_Q06 Order Status Response", for OSR^Q06) requires, with
the order detail read as the base choice, nothing the base does not (modelled since P8b-4a fix
round 1 for the OBX it adds).

### Addendum to §E — AU profile structures govern base structure findings (P8b-4a, 2026-10-04)

A fourth ADRM structure, RRI_I12 (p 325: `MSH MSA [ERR] [ RF1 {PRD} PID ]`), is modelled, so a
missing MSA is a 00060.1 finding. Where the AU profile has a structure for the message's trigger,
a base v2.4 structure finding is dropped when the profile structure accepts the message at that
point: no profile finding is located there, and the base reports `unexpected` a segment the
profile structure places there, or `missing` a segment the profile structure reports missing
nowhere (ADR-019 decision 7 as amended). Every other base finding is kept: a segment neither
structure places, one the profile names but not at that point, and a base finding at a place
where the profile reports a finding of its own. A base that fails the determinism lint (v2.4
REF_I12, RRI_I12 and ORU_R01) is matched exactly and reports its first divergence only; when that
finding is a dropped `unexpected`, the base is matched again with the dropped occurrence passed
over, repeated until a finding is kept or none is left, so a later divergence is still reported
(fix round 1). What stays unreported is what neither structure reports: the narrowed maxima,
which the base accepts and the profile reports only as beyond-maximum findings, which decision 7
drops. A fifth ADRM structure, OSR_Q06 (p 281, the order status response), is modelled in fix
round 1 (row above). The ORM^O01 order detail is narrowed to OBR, RXO,
ODS and ODT (p 280 replaces OBR only "for medication and diet orders"), so an RQD or RQ1 in its
place is a 00060.1 finding. Still not enforced, as the table above records: Appendix 8, the
ORR^O02 bracket erratum, the PV1 prose mandate, the narrowed maxima (the base allows the
repetition and the profile drops beyond-maximum findings).
Approximation, kept on the side of reporting: a base `missing` finding is compared with the
profile's by segment ID, not by place, so a segment the profile reports missing elsewhere keeps
every base `missing` finding for it.

## F. Excluded HL7 v2.x versions (ADR-018)

A message declaring one of these parses, falls back to the v2.5.1 grammar, and carries
`IssueCode.versionNotRecognised(wireValue:)` (warning) at MSH-12 naming that fallback.
`ParserOptions.strict` rejects it with `ParseError.unsupportedVersion(found:)`.

| MSH-12 | Why it is excluded | Freeze decision |
|--------|--------------------|-----------------|
| 2.1 | No v2.1 spec text in `docs/standards/`. | Excluded. Re-open with the text, an ADR-018 amendment and an ADR-015 cycle. |
| 2.2 | No v2.2 spec text in `docs/standards/`. | Excluded, as 2.1. |
| 2.5 | No v2.5 spec text; v2.5.1, which HL7 published as the successor release, is modelled. The fallback applies the v2.5.1 grammar, and the warning says so. | Excluded, as 2.1. |
| 2.7 | Listed in v2.8.2 Table 0104; no v2.7 text on disk. **No longer excluded** (owner decision G11, 2026-10-03; P10-6): `Version.v2_7` is validated against the v2.7.1 grammar, code tables and datatype grammar, as `2.8` is against v2.8.2, and carries `versionGrammarSubstituted(declared: .v2_7, validatedAs: .v2_7_1)` (info) at MSH-12 instead of `versionNotRecognised`; `ParserOptions.strict` accepts it. The v2.7 to v2.7.1 differences are unverified without the v2.7 text, and the info issue says so. | Substituted by v2.7.1 (ADR-018 amendment). Re-open with the v2.7 text. |
| 2.8.1 | Listed in v2.8.2 Table 0104; no v2.8.1 text on disk. See ADR-018 "Open question" on substituting v2.8.2. | Excluded, as 2.1. |
| 2.9 | Published after v2.8.2; no text on disk. | Excluded, as 2.1. |

**Populated MSH-12 with no resolvable VID.1 (not a limitation; recorded to prevent re-litigation).** Any MSH-12 that carries content but from which no modelled version resolves is reported the same way as the excluded versions above: a whitespace-only MSH-12, an empty VID.1 with VID.2 valued (`^AUS&Australia&ISO3166_1`, legal on v2.5.1, where VID.1 is printed O), a VID.1 with a subcomponent (`2.4&X`, `&2.4`) and an escaped VID.1 (`2.4\S\x`). The parser falls back to v2.5.1 and the Validator reports `versionNotRecognised(wireValue:)` (warning) with VID.1 as rendered (empty when VID.1 is empty); `ParserOptions.rejectUnknownVersion` (set by `.strict`) throws `ParseError.unsupportedVersion(found:)` with the same value. Only an empty MSH-12 falls back without a version issue, because MSH-12 is required and the required-field check reports it. The earlier "revisit if observed" freeze for the subcomponent and empty-VID.1 shapes was withdrawn in the P3 fix wave; project requirement 1 rules out a traffic-based deferral. `VersionHandlingTests.versionMatrix` pins every shape under the default, `.strict` and `rejectUnknownVersion` options.

## H. Typed API shape across versions (V251-C11, V282-C10) — closed, residual registered

| Gap | Status | Remediation |
|---|---|---|
| Composite views expose a subset of components | **closed (P9-3, 493d3f8)**: every component any supported version defines is named; completeness is a codegen invariant | ADR-020 |
| Repeating fields expose the first repetition only | **closed (P9-4, 3662890)**: `<name>All` | ADR-020 |
| Typed structs are v2.5.1-shaped | **closed (P9-5, df04dc6, e5436f8)**: version-union accessors | ADR-020 |
| **Residual:** composite-to-composite retypes (for example CE to CWE from v2.6) surface through `viewed(as:)`, not a retyped property; retyping the property would break ADR-014 | registered: waits for a major release | ADR-020 |
| **Residual:** names used only before v2.5.1 (v2.3 to v2.4 spellings) have no accessor; the base-name accessor reads the same index | registered | ADR-020 |
| **Residual:** accessors are not gated by the message's version; an accessor for a field the declared version does not define still reads that wire position | registered by design: version facts are in DocC, `SegmentGrammar` and `DataTypeGrammarTable` | ADR-020 |

Wire data is never lost: `field(_:)` and `CompositeView.field` reach every position.

## What is NOT a limitation (recorded to prevent re-litigation)

- **NUL / BOM handling** — embedded NUL is *rejected* at parse (v0.2-P2); BOM is stripped. These are design decisions with no carve-out, not limitations.
- **`.v2_8` substitution** — a deliberate, announced decision (ADR-018): a `2.8` message is validated against the v2.8.2 grammar, and every report carries `versionGrammarSubstituted` (info) at MSH-12. The v2.8 text is not on disk, so the v2.8 to v2.8.2 differences are unverified; the info issue says so.
- **Curated NK1 / PV1 / IN1 depth** — a req-#1 feature-completeness *backlog* item (extend the field sets), not a conformance limitation of the modelled fields.
- **Blank printed OPT** (v2.4 / v2.5.1 RCP-7) is kept verbatim as `""` in the schema and generated as `.optional` (`optionalityCase` default branch): the spec prints no optionality, and the permissive reading can never raise a false error.

## Outcome — M2 closed

With A (v0.16) and B/C (this register) documented and freeze-decided, **ROADMAP M2 (conformance-surface finalisation) is closed**: every conformance rule is either validated or listed here with a spec-cited reason and an explicit v1.0 freeze decision. The remaining v1.0 gate is **M3** (API stabilisation).
