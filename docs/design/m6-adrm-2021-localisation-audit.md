# M6 — ADRM-2021 AU localisation audit

| | |
|---|---|
| Status | **M6 CLOSED (2026-09-16), then FINISHED to 104/104 the same day (M6-B-4..9).** All defects fixed (D1/D3/D4/D5 — D5 via owner-directed ADR-014 override); M6-A complete; the M6-B capability run drained the EXTEND class entirely — **final register: 65 shipped / 12 partial / 15 base / 12 registered, EXTEND 0, CANDIDATE 0**; `permanent-limitations-register.md` §D drained. The historical counts in the body below (36 EXTEND, etc.) record the audit-time triage and are superseded by the generated register. Appendix 5 is not exhaustive — the prose sweep is separate, later work. |
| Source | `docs/standards/HL7_v24_PDF/HL7AUSD-STD-OO-ADRM-2021.1 — Australian Diagnostics and Referral Messaging — Localisation of HL7 Version 2.4.pdf`, Appendix 5 *Conformance Statements (Normative)*, pp. 416–474 |
| Subject | `HL7Locale.auLocalisation` → `Sources/HL7v2Kit/Locale/Profile+au_adrm_2021.swift` |
| Generated register | `docs/design/m6-adrm-2021-conformance-register.md` (re-runnable) |
| Tool | `scripts/extract-adrm-conformance.py` |
| Milestone | ROADMAP **M6** — AU localisation completeness |

## Why this audit exists

The AU profile shipped incrementally between v0.4 and v0.11, each rule added
because a task needed it. Nobody had ever diffed the shipped overlay against
the localisation's own normative register. Requirement #2 (integrator primary
reference) means the AU coverage claim has to be **measured against the spec
text**, not against the rules we happened to write.

## Method

ADRM-2021 states its narrowings twice: as prose in the chapter bodies, and as a
normative table of `HL7au:` conformance points in Appendix 5. The appendix is
the authoritative enumeration ("Conformance of messages to base HL7 2.4
standards is otherwise assumed"), so it is the diff basis.

`scripts/extract-adrm-conformance.py` recovers that table from
`pdftotext -layout` output and classifies every row. Three PDF-layout traps had
to be handled, and each is a re-runnable behaviour of the script, not a manual
correction:

1. **Column offsets drift between pages.** They are read from each page's own
   repeated header rather than fixed.
2. **Identifiers wrap or split mid-token.** `HL7au:000 45.5` is one identifier
   with an inserted space; `HL7au:000008.2.4.4.` continues with `2.04` alone in
   the identifier column on the following line.
3. **Parenthesised identifiers are groupers**, not conformance points — the
   appendix says so explicitly, and 39 rows are groupers.

The script asserts that every curated identifier still exists in the extracted
table and that no row falls through unclassified, so a future ADRM revision
that renumbers a point fails the run instead of silently dropping it.

## Result

**302 table rows → 263 conformance points.**

| Verdict | Count | Meaning |
|---|---:|---|
| SHIPPED | 43 | enforced by the `.auLocalisation` overlay today |
| PARTIAL | 4 | partly enforced — each row's note says what is not |
| BASE | 15 | already enforced by the base model; the overlay deliberately stays silent |
| REGISTERED | 5 | known limitation, already registered with a citation |
| CANDIDATE | 0 | expressible with today's DSL — **emptied by M6-A stage 3** |
| **EXTEND** | **36** | **needs a model extension to express faithfully (req #3)** |
| WITHDRAWN | 3 | removed by revision r2 — must never be cited |
| RECEIVER | 74 | receiver behaviour, observed at runtime, not decidable from a message |
| OUT | 83 | out of scope by nature: transport/PKI/directory, rendered payload, cross-message uniqueness |
| GROUPER | 39 | heading rows |

Counts are per table row. Three identifiers appear on two rows each, so the
distinct-point totals are one lower where noted below.

Read positively: of the **103 rows that are decidable from a single message**
(SHIPPED + PARTIAL + BASE + REGISTERED + CANDIDATE + EXTEND), the profile
enforces or accounts for **67** after M6-A stages 1–3. **M6-A is complete**:
the CANDIDATE column is empty, and every remaining gap is either one of the
**36** EXTEND points (needs a model capability — M6-B) or a REGISTERED
permanent limitation with its citation.

*Counts as of M6-A stage 3 (2026-09-15). At audit time: SHIPPED 31 / BASE 12 /
CANDIDATE 31 — 47 of 102. The CANDIDATE column fell from 31 to 0 not because
all those points shipped but because **shipping the stages discovered why most
of them could not** — see M6-O6, M6-O7, and the stage 3 note on
`00050.1.5`. That drop is the audit working, not scope being abandoned.*

The 158 RECEIVER + OUT points are not a coverage gap in a message library.
They constrain receiving-system behaviour (74), transport and PKI addressing,
rendered PDF/XHTML payload content, and uniqueness across messages the library
never sees together. They are enumerated in the register so the exclusion is
auditable rather than assumed.

## Findings

### M6-D1 — CNE pair rules cite a withdrawn conformance point ✅ FIXED 2026-09-04

`ceCwePairRules(citePrefix:)` in `Profile+au_adrm_2021.swift` assumes CE and CNE
share the alternate-identifier numbering `.5` / `.6`, and only CWE differs at
`.4` / `.5`. The spec does not agree:

| Composite | "alt id set ⇒ alt system set" | "alt id empty ⇒ alt system empty" |
|---|---|---|
| CE (`00044.4`) | `.4.5` ✅ cited correctly | `.4.6` ✅ cited correctly |
| **CNE (`00044.5`)** | **`.5.4`** — code cites `.5.5` ❌ | **`.5.5`** — code cites `.5.6` ❌ |
| CWE (`00044.6`) | `.6.4` ✅ cited correctly | `.6.5` ✅ cited correctly |

`HL7au:00044.5.6` is not merely the wrong point — it is marked **"Removed"** in
revision r2 and no longer exists. The two CNE rules are behaviourally correct;
only their `specCitation` strings are wrong. Under the working notes req #4 a rule
carrying a false citation is a defect, so this is the first thing to fix.

**Fixed 2026-09-04.** `ceCwePairRules` now derives the alternate pair from an
`altBase` — 5 for CE, 4 for CNE and CWE — and the helper's doc comment states
the real rule instead of the false one. Two tests in `LocaleAUProfileTests`
pin the numbering per composite and assert `HL7au:00044.5.6` is never cited.

### M6-D2 — three withdrawn points must stay uncited

`HL7au:00044.5.6`, `HL7au:00044.6.6` (both "Removed", r2) and `HL7au:00048.3.2`
("Deleted. Merged into HL7au:00048.3.1"). Only the first is currently cited
(M6-D1). The register carries them so a future sweep does not resurrect them
from an older revision of the PDF.

### M6-D3 — profile usage narrowings fired outside their message-type scope ✅ FIXED 2026-09-04

Appendix 5 scopes almost every conformance point to a named set of message
types. `HL7au:000041` (MSH-17 = AUS) and `HL7au:000042` (MSH-19 =
en^English^ISO639) are scoped to *"Orders, Results, Referrals, Acknowledgement,
Referral Response"*. Both shipped as `profileUsage = .required` with **no gate
at all**, and their `componentValueSets` carried no `condition` either.

Consequence: under `.auLocalisation`, a spec-compliant `ADT^A01` with no MSH-17
failed AU validation citing a conformance point that does not apply to ADT.
Same for `SIU`, `MDM`, and every other message type the localisation never
addresses. Requirement #4 is explicit that a predicate misfiring in a
spec-compliant scenario is a defect, so this was one — and a louder one than
M6-D1, because it produced false errors rather than a wrong string.

The `HL7au:000040` block two fields earlier had reasoned about exactly this
("gating prevents over-fire on message types outside scope") and gated its
value sets. MSH-17/19 were written later and did not inherit the reasoning.

**Fixed 2026-09-04** by the model extension req #3 asks for rather than a
narrowing of the rule: `FieldOverride` gained `usageCondition`, a
message-context predicate gating `profileUsage`, using the same grammar and the
same fail-safe semantics as `ComponentValueSet.condition` (an unparseable gate
evaluates false, silencing the rule rather than over-firing it). MSH-17 and
MSH-19 now carry `messageCode in (ORM, ORU, REF, RRI, ACK)` on both halves.
`FieldOverride` is internal, so this is not an API change.

Three tests pin the behaviour: ADT fires neither point when the fields are
absent, ADT fires neither when they are present-but-wrong, and ORU still fires
both when they are absent. Six existing tests had encoded the over-fire by
asserting these rules against ADT wires; their wires moved to ORU, which is
what they meant to exercise.

**This is a prerequisite for M6-A, not a detour.** Eleven of the 31 CANDIDATE
points (`00047.1`, `00047.2`, `00049.1`–`.3`, `00048.3.1`, `000024.1`–`.5`) are
scoped to Orders/Results/Referrals and need `.required` narrowings. Without
`usageCondition` they could only have shipped with the same defect.

### M6-D4 — composite overrides fired outside their message-type scope ✅ FIXED 2026-09-04

The composite-track twin of M6-D3, found while starting M6-A stage 2. Every
`HL7au:00044.*` datatype point is scoped to *"Orders, Results, Referrals"* (or
*"Results, Referrals"* for ED and RP), but `CompositeOverride` had no gate, so
the CX / CE / CNE / CWE narrowings applied to every message. An `ADT^A01`
carrying a two-component `CX` in PID-3 failed AU validation citing
`HL7au:00044.1.2`, which does not reach ADT.

**Fixed 2026-09-04**: `CompositeOverride` gains `condition`, the same
message-context predicate as `FieldOverride.condition`, gating all four rule
tracks; `valueConditionals` may still narrow further with their own condition,
and both must hold. All four AU composite overrides carry
`messageCode in (ORM, ORU, REF)`.

Six existing tests had encoded this over-fire too — the CX fixtures ran on ADT
wires and the CWE fixtures on ACK wires, neither of which the relevant points
reach. Their wires moved to ORU; two new tests pin that ADT fires nothing and
REF still does.

**Both M6-D3 and M6-D4 are the same mistake on different dispatch tracks**, and
neither was visible from the code alone: each rule looked correct in isolation
and its test passed. What exposed them was diffing against the applicability
column of the source table — the column the overlay had never been checked
against.

### M6-D5 — OBX-5's declared datatype is wrong in all six schemas ✅ FIXED (2026-09-15, owner-directed ADR-014 override)

Every supported version's attribute table gives OBX-5 (Observation Value) the
variable datatype. All six committed schemas said **`ST`**.

**Correction found at fix time:** the audit recorded the v2.3-era value as
`Variable`; the attribute tables actually print **`*`** on v2.3/v2.3.1/v2.4
(the section headings read `Observation value (*)`) and `varies` on
v2.5.1/v2.6/v2.8.2. `Variable` was a paraphrase, not the verbatim value —
re-verified against all six chapters' tables at fix time.

The project already had the right convention for this case: `RDT-1` stores
the verbatim table value per version. OBX-5 now follows it.

The fix was **API-affecting**: `*`/`varies` are not in codegen's
`scalarDataTypes`, so `OBX.observationValue` changed from `String?` to
`Field?` — breaking, originally blocked by ADR-014's 2.x additive-only
contract. **The project owner directed an override (2026-09-15)** to
remediate immediately; the next release is a major (`v3.0.0`). See
`Migration.md` → "The 3.0 boundary" and the ADR-014 addendum. The `String?`
accessor had silently flattened structured OBX-5 payloads (CE, SN, ED, ...)
to their first component; a test now pins the structured path.

### M6-O5 — no audit predicate has ever compared a field's datatype

M6-D5 survived 717 schemas and every audit because
`scripts/audit-schemas.py --depth` compares **field count only** —
`max(index)` against the extracted table depth. Names, `OPT` and `RP` are
checked by other predicates; `dataType` is checked by nothing. An entire
column of every attribute table is unaudited.

This is the working rules' own lesson recurring: *audit with shape predicates,
not content lists*. The fix is a per-field `dataType` comparison in the depth
pass. It is not run here because triaging its findings across 717 schemas is
its own cycle — but until it runs, **no claim that the schemas faithfully
render the spec covers the datatype column**.

### M6-O6 — HL7 code tables are not modelled at all

> **Addendum 2026-09-20 — closed by ADR-016.** The finding below is kept as written. Since then: every TBL# binding is in the schemas (`tables`, 4,290 bindings), 2,565 per-version tables are extracted with descriptions and generated into `HL7TableRegistry`, `valueNotInTable` enforces closed HL7 tables on ID fields, and the four AU tables live on the registry's locale axis. One correction to this audit's own record: `UPIN` and `NOI` ARE printed in the ADRM's Table 0203, as `UPIN*` and `NOI**` with footnotes on p. 309.

The schemas carry `index`, `swiftName`, `name`, `dataType`, `optionality`,
`repeatability` — the extractor drops the spec's `TBL#` column, and there is no
code-table registry anywhere in the package. Every conformance point of the
form "must be a value from HL7 Table NNNN" is therefore unshippable as a value
set:

| Point | Table |
|---|---|
| `HL7au:000032` / `.2` | 0074 Diagnostic Service Section |
| `HL7au:00044.7.3` | 0200 Name Type |
| `HL7au:00044.7.4` / `HL7au:00104.7.3.1` | 0203 Identifier Type |
| `HL7au:00104.7.2.1` | 0363 Assigning Authority |

Four moved from CANDIDATE to EXTEND on this finding; two more ship PARTIAL
(presence enforced, membership not). A code-table registry is the single
highest-leverage M6-B capability — it is also the one whose absence most
undermines requirement #2, since an integrator reading the schemas cannot see
which table a coded field draws from.

### M6-O7 — ED and RP never appear as a declared datatype

`HL7au:00044.10.*` (ED) and `00044.11.*` (RP) are eight conformance points on
two composites that **no field on any supported version declares**. They reach
the wire only through OBX-5, whose type is chosen at runtime by OBX-2's value
type. The composite dispatch keys on the static grammar `dataType`, so an
override for `"ED"` or `"RP"` would be dead code that can never fire.

Shipping them would have looked like coverage and enforced nothing. They move
to EXTEND against an OBX-2-driven datatype-resolution capability — which is the
same gap M6-D5 exposes from the other side.

### M6-O1 — the shippable tranche is unusually cheap

All 31 CANDIDATE points (as first measured) fit shapes the overlay already
expresses — 22 are fixed-value or required-component assertions, 8 are value
sets against HL7 tables, one is a group-scope cardinality. The four clusters
below partition the 31 exactly; **cluster 1 shipped on 2026-09-04**, leaving
20 CANDIDATE.

- ✅ **MSH envelope literals** (`000024.1`–`.5`, `00047.1`, `00047.2`,
  `00049.1`–`.3`, `00048.3.1`) — encoding characters, `AL` acknowledgement
  modes, MSH-9 and MSH-18 value sets. Eleven points, no new machinery.
  **Shipped 2026-09-04**: nine enforced outright, `00049.1` reclassified BASE
  (MSG-1 is already a base required component), `000024.2` PARTIAL. Two
  findings came out of shipping it — see M6-O3 and M6-O4.
- **Composite required components** (`00044.7.2`–`.7.5` XCN, `00044.10.1.1`–`.1.4`
  ED, `00044.11.1.1`–`.1.4` RP, `00044.3.1` EI-1) — thirteen points, all
  `RequiredComponentSet`.
- **Value sets against HL7 tables** (`000032`, `000032.2` OBR-24/table 0074;
  `00104.7.2.1` table 0363; `00104.7.3.1` table 0203; `000021` OBX-2 exclusion;
  `00050.1.5` OBX-6.3 = `UCUM`) — six points. **Stage 3 outcome (2026-09-15):**
  `000021` shipped PARTIAL (Results leg), `00050.1.5` → REGISTERED (no
  message-decidable pathology discriminator), the four table-membership
  points → EXTEND (M6-O6).
- **`000023`** — "the NTE segment must NOT be used" is a group-scope cardinality
  of 0. ADR-010's model was minimum-only; stage 3 added
  `SegmentCardinalityRule.maxCount` and shipped it. ✅

### M6-O2 — the extension tranche clusters into five model gaps

The EXTEND tranche is 24 rows / **23 distinct points** — `HL7au:00104.1.1` is
duplicated in the source table with two different texts, one sender-side and
one receiver-side. Those 23 are not 23 separate problems; they need five
capabilities:

| Capability | Points | Example |
|---|---|---|
| Prefix / pattern match on an ID | 2 | `000020`, `000023.1` — nothing beginning `Z` |
| Value-correspondence maps between components | 6 | `00044.10.1.5/.6`, `00044.11.1.5/.6`, `000008.1.3`, `00104.7.1.4` — subtype ⇒ type |
| Discriminated group cardinality | 4 | `00104.1.1` "exactly one PRD with PRD-1 = AP"; `000008.3.1/.2` |
| Within-message uniqueness / ordering | 4 | `000028`, `000028.2` unique OBR-3; `00100.1`, `000008.1.5` ordering |
| Coding-system precedence, generalised | 3 | `000034.1`–`.3` — the shipped LOINC rule (`00044.4.4`) generalised to any public/local pair |

Four stragglers: `00044.8.1` (TS timezone — datatype-level validation),
`00044.6.7` (the CWE twin of the already-registered `00044.4.7` / `.5.7`
same-concept assertion, which stays a permanent limitation), and `000022.1` /
`000022.3` (batch-scope rules; the Validator is message-scoped).

### M6-O3 — `000024.2` cannot be fully expressed, and the reason is structural

MSH-2 parses as a single scalar literal (`"^~\&"`) with no internal split, so
the four encoding-character points collapse to one value-set pin. That works
for Orders and Results, where all four apply. It does not work for Referrals:
Appendix 5 scopes `.2` (component separator) to Orders, Results **and**
Referrals, but `.3`/`.4`/`.5` to Orders and Results only. Pinning the whole
literal on REF would enforce three points the spec does not apply there.

The rule therefore gates on the `(ORM, ORU)` intersection and `000024.2` is
recorded PARTIAL. Expressing it fully needs character-position addressing
inside a component — folded into M6-B's value-correspondence capability.

### M6-O4 — `00048.3.1`'s value lies entirely in the alias gap

`CharacterEncoding` already rejects an unknown MSH-18 with
`ParseError.unsupportedCharacterEncoding` before validation runs, so the AU
value set never sees a genuinely bad encoding. What it does catch is aliases
the parser accepts but the conformance point does not list: `UTF-8`,
`US-ASCII`, `ISO-8859-1`. `00048.3.1` names four literals exactly, and an alias
is not one of them. Worth stating because the rule looks redundant against the
parser until you see which inputs actually reach it.

## Recommended sequencing

1. ~~**M6-D1** — the citation fix.~~ ✅ done 2026-09-04.
   ~~**M6-D3** — gate `profileUsage` on message type.~~ ✅ done 2026-09-04;
   prerequisite for step 2.
   ~~**M6-D4** — gate composite overrides on message type.~~ ✅ done
   2026-09-04; prerequisite for stage 2.
2. **M6-A** — the CANDIDATE points, additive under ADR-014, split by cluster so
   each lands as its own stage with its own tests.
   - ✅ **Stage 1 — MSH envelope literals** (2026-09-04). Nine points shipped,
     one reclassified BASE, one PARTIAL.
   - ✅ **Stage 2 — composite required components** (2026-09-04). Only XCN was
     shippable: `00044.7.2`/`.7.5` outright, `.7.3`/`.7.4` PARTIAL (presence,
     not table membership), `.7.1` and `00044.3.1` reclassified BASE, and the
     eight ED/RP points moved to EXTEND per M6-O7.
   - ✅ **Stage 3 — the last three CANDIDATE points** (2026-09-15). The two
     prohibitions shipped via `SegmentCardinalityRule.maxCount` (an upper
     bound the minimum-only v0.11 model could not state; `maxCount: 0` is a
     prohibition, and an empty predicate counts every segment of the ID):
     `000023` (NTE must not be used, gated ORM/ORU/REF) shipped outright;
     `000021` (OBX-2 ≠ TX) shipped PARTIAL — the Results leg only at that
     stage. *(Correction, M6-B-6 2026-09-16: stage 3 recorded the L2
     discriminator as "an MSH-21 profile ID the model cannot address".
     That was a misidentification — the ADRM declares the adhered profile
     in **MSH-12.3** ("The <internal version ID (CE)> component must be
     valued ... to indicate the profile"), which 000040.4 already pins and
     the DSL addresses directly. The Referrals(L2) leg shipped at M6-B-6
     gated on `MSH-12.3.1 = HL7AU-OO-REF-SIMPLIFIED-201706`.)*
     `00050.1.5` (OBX-6.3 =
     UCUM) did **not** ship: it is scoped "Senders (Pathology only)" and
     ADRM-2021 defines no message-decidable pathology discriminator (table
     0074 mixes pathology and imaging; no pathology subset is named), so a
     bare ORU gate would over-fire on spec-compliant imaging results
     (req #4) — moved to REGISTERED in
     `permanent-limitations-register.md`. The other four of the original
     value-set cluster need a code-table registry (M6-O6).
3. **M6-B** — pick up the five EXTEND capabilities on their merits. Each one
   that is not taken must be added to `permanent-limitations-register.md` with
   its HL7au citation, per req #3: a spec semantic the DSL cannot express is a
   documented blocker, not a silent omission.

**M6 is closed (2026-09-16).** M6-B-1/2 shipped the points expressible with
three further DSL extensions (`anyRepeat`, `startsWith`, the `Z*` counted
prefix): `00104.1.1`, `00104.2.1`, `00104.7.0` (a register row the parser had
mangled and an earlier triage dismissed — repaired and shipped), `000023.1`,
and the PARTIALs `000008.3.1` and `000020`. M6-O5's dataType predicate is
live (45 findings → 13 real defects fixed). The 30-point EXTEND remainder is
registered as deferred capabilities in `permanent-limitations-register.md`
§D. Any AU coverage claim must give the measured number — **74 of the 104
message-decidable ADRM-2021 rows** (48 shipped, 6 partial, 15 base-model,
5 registered) — never "the AU profile" unqualified, and must carry the
standing caveat: Appendix 5 is explicitly not exhaustive; the chapter-body
prose sweep is separate, later work.

## Caveats on the register itself

- Appendix 5 is explicitly **not exhaustive** ("The list below is not
  exhaustive… included here primarily if they are important from a safety or
  quality perspective, or are commonly not correctly implemented, or are at
  variance with the base HL7 v2.4 specifications"). Chapter-body prose may
  narrow further without a conformance point. This audit measures the
  register; a prose sweep is separate work.
- Three identifiers appear twice in the source table (`00044.3.4`, `00104.1.1`,
  `00044.11.1.5` as both point and grouper). That is a document artefact, not a
  parse error; both rows are kept.
- Verdicts `OUT` and `RECEIVER` are judgements about *this library's* scope.
  They are recorded per-point in the register so the judgement can be
  challenged one row at a time.
