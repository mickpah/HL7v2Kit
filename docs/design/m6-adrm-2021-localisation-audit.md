# M6 — ADRM-2021 AU localisation audit

| | |
|---|---|
| Status | **Audit complete (2026-09-04); M6-D1 fixed; M6-A / M6-B open** |
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
| SHIPPED | 31 | enforced by the `.auLocalisation` overlay today |
| BASE | 12 | already enforced by the base model; the overlay deliberately stays silent |
| REGISTERED | 4 | known limitation, already registered with a citation |
| **CANDIDATE** | **31** | **expressible with today's DSL — the shippable gap** |
| **EXTEND** | **24** | **needs a model extension to express faithfully (req #3)** |
| WITHDRAWN | 3 | removed by revision r2 — must never be cited |
| RECEIVER | 74 | receiver behaviour, observed at runtime, not decidable from a message |
| OUT | 84 | out of scope by nature: transport/PKI/directory, rendered payload, cross-message uniqueness |
| GROUPER | 39 | heading rows |

Counts are per table row. Three identifiers appear on two rows each, so the
distinct-point totals are one lower where noted below.

Read positively: of the **102 rows that are decidable from a single message**
(SHIPPED + BASE + REGISTERED + CANDIDATE + EXTEND), the profile currently
enforces or accounts for **47**. The other **55** are the M6 backlog.

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

### M6-O1 — the shippable tranche is unusually cheap

All 31 CANDIDATE points fit shapes the overlay already expresses — 22 are
fixed-value or required-component assertions, 8 are value sets against HL7
tables, one is a group-scope cardinality. The four clusters below partition
the 31 exactly:

- **MSH envelope literals** (`000024.1`–`.5`, `00047.1`, `00047.2`, `00049.1`–`.3`,
  `00048.3.1`) — encoding characters, `AL` acknowledgement modes, MSH-9 and
  MSH-18 value sets. Eleven points, no new machinery.
- **Composite required components** (`00044.7.2`–`.7.5` XCN, `00044.10.1.1`–`.1.4`
  ED, `00044.11.1.1`–`.1.4` RP, `00044.3.1` EI-1) — thirteen points, all
  `RequiredComponentSet`.
- **Value sets against HL7 tables** (`000032`, `000032.2` OBR-24/table 0074;
  `00104.7.2.1` table 0363; `00104.7.3.1` table 0203; `000021` OBX-2 exclusion;
  `00050.1.5` OBX-6.3 = `UCUM`) — six points.
- **`000023`** — "the NTE segment must NOT be used" is a group-scope cardinality
  of 0, which ADR-010 already expresses.

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

## Recommended sequencing

1. ~~**M6-D1** — the citation fix.~~ ✅ done 2026-09-04.
2. **M6-A** — the 31 CANDIDATE points, additive under ADR-014. Split by cluster
   (MSH envelope / composite required components / value sets) so each lands as
   its own stage with its own tests.
3. **M6-B** — pick up the five EXTEND capabilities on their merits. Each one
   that is not taken must be added to `permanent-limitations-register.md` with
   its HL7au citation, per req #3: a spec semantic the DSL cannot express is a
   documented blocker, not a silent omission.

Until M6-A lands, any AU coverage claim must say the profile enforces **47 of
the 102 message-decidable ADRM-2021 conformance points**, not "the AU profile".

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
