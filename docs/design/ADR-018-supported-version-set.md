# ADR-018 — The supported HL7 v2.x version set

**Status:** Accepted 2026-09-30 (owner) — Option A.

**Context:** Requirement 1 (`the working notes`) asks for the full HL7 v2.x spec, but the package models six releases and never said which it leaves out. The 2026-09-30 review sprints found three consequences:

- X-C02 / V282-C03: `Version.v2_8` (`"2.8"`) is a public case with no grammar. `Validator.grammarTable(for:)` returns `[:]`, so a `2.8` message passes default validation with nothing checked and nothing said; under `.strict`, every segment, MSH included, is rejected as a Z-segment.
- V282-C09: v2.8.2 Table 0104 lists `2.7`, `2.7.1` and `2.8.1`; none is a `Version` case, and the Parser silently falls back to v2.5.1 for them. The same silent fallback hits a VID-form MSH-12 (`2.4^AUS&Australia&ISO3166_1`), because the Parser reads MSH-12 as a scalar and a composite yields nil.
- X-C01 / X-C03: v2.7.1 spec text is on disk but has no version, schemas or tables; v2.1, v2.2, v2.5, v2.7, v2.8.1 and v2.9 are absent with no recorded decision.

`Version` and `IssueCode` are open enums (ADR-014): adding a case is additive. Spec text on disk (`docs/standards/`): 2.3, 2.3.1, 2.4, 2.5.1, 2.6, 2.7.1 (zipped), 2.8.2. ADR-015 is the extraction pipeline any new version goes through.

### What "supported" means

A version is **modelled** when it has a `Version` case, a segment grammar (`Resources/schemas/<v>/`), code tables (`Resources/tables/<v>/`) and, from v2.5.1 on, datatype component grammar (`Resources/datatypes/<v>/`), each extracted from that version's own spec text. A version is **substituted** when it has a `Version` case but is validated against another modelled version's grammar, and every report says so. A version is **excluded** when it has no `Version` case: it parses, falls back to the v2.5.1 grammar, and every report carries a warning naming the fallback (`ParserOptions.strict` rejects it).

## Options

### Option A — Six modelled, `2.8` substituted by v2.8.2, v2.7.1 scheduled, the rest excluded (recommended)

- Modelled: 2.3, 2.3.1, 2.4, 2.5.1, 2.6, 2.8.2.
- Substituted: 2.8 validated against v2.8.2, with an info issue `IssueCode.versionGrammarSubstituted(declared: .v2_8, validatedAs: .v2_8_2)` at MSH-12 on every report.
- Scheduled: 2.7.1 as plan P10 (ADR-015 extraction pipeline); Task P3-6 scopes P10, and 2.7.1 is modelled once P10 lands.
- Excluded, each with a permanent-limitations-register row: 2.1, 2.2, 2.5, 2.7, 2.8.1, 2.9.
- Pro: `2.8` gets real checking, and the nearest published grammar is the best available evidence. The substitution is announced, so no report claims more than was done. `.v2_8` keeps its source-compatible public case.
- Con: the v2.8 text is not on disk, so the v2.8 to v2.8.2 differences are unverified. A v2.8 message may draw a finding that only v2.8.2 requires. The info issue states this.

### Option B — Six modelled, `2.8` recognised but not validated

- As Option A, except `2.8` keeps an empty grammar. Every `2.8` report carries one warning `IssueCode.versionNotValidated(declared: .v2_8)` at MSH-12, and no field, component or table check runs.
- Pro: nothing is judged by another release's text (V282-A03 part (c) default).
- Con: a `2.8` message is never checked; the warning is the only output.

### Option C — Model every release in Table 0104

- Source v2.1, v2.2, v2.5, v2.7, v2.8, v2.8.1 (and v2.9) texts and run each through ADR-015.
- Pro: literal reading of requirement 1.
- Con: the texts are not on disk; each version is an L-size cycle; it blocks the rest of the remediation.

## Decision

**Option A.** The Validator validates a `.v2_8` message against the v2.8.2 grammar, code tables and datatype grammar, and reports `versionGrammarSubstituted` (info) at MSH-12. The public registries (`HL7TableRegistry.table(_:version:)`, `DataTypeGrammarTable.grammar(_:version:)`) stay version-literal: `.v2_8` owns no tables. `Version.grammarVersion` is the single mapping. A non-Z segment with no entry in the applied grammar is reported as `segmentNotInVersionGrammar` (warning), never as a Z-segment. MSH-12 is read as a VID: the version is VID.1. An MSH-12 version ID with no `Version` case falls back to v2.5.1 and is reported as `versionNotRecognised(wireValue:)` (warning) naming the grammar used; `ParserOptions.strict` keeps throwing `ParseError.unsupportedVersion(found:)`. v2.7.1 is scheduled as plan P10; `2.7` is not mapped to it, because `Version` has no `.v2_7` case and adding one without its text would repeat an unverified substitution. The excluded versions are recorded in `permanent-limitations-register.md` section F.

### Version table

| MSH-12 (VID.1) | Status | Grammar applied | Issue raised |
|---|---|---|---|
| 2.3, 2.3.1, 2.4, 2.5.1, 2.6, 2.8.2 | Modelled | Its own | none |
| 2.8 | Substituted | v2.8.2 | `versionGrammarSubstituted` (info) |
| 2.7.1 | Scheduled as plan P10; excluded until it lands | v2.5.1 fallback | `versionNotRecognised` (warning) |
| 2.1, 2.2, 2.5, 2.7, 2.8.1, 2.9, any other | Excluded | v2.5.1 fallback | `versionNotRecognised` (warning) |
| whitespace only | Populated, no version | v2.5.1 fallback | `versionNotRecognised` (warning), payload `""` |
| empty VID.1 with VID.2 valued (`^AUS...`) | Populated, no version | v2.5.1 fallback | `versionNotRecognised` (warning), payload `""` |
| VID.1 with a subcomponent (`2.4&X`, `&2.4`) | Populated, no version | v2.5.1 fallback | `versionNotRecognised` (warning), payload VID.1 as rendered |
| empty | Not a version | v2.5.1 fallback | MSH-12 required-field error (existing) |

Every row that raises `versionNotRecognised` throws `ParseError.unsupportedVersion(found:)` instead under `ParserOptions.rejectUnknownVersion` (set by `.strict`), with the same VID.1 value. The empty row never throws. `VersionHandlingTests.versionMatrix` pins the table (P3 fix wave).

## Consequences

- Default output changes for three kinds of message, each a fix under requirements 2 and 4: `2.8` messages now carry findings plus one info issue; messages carrying a non-Z segment their version does not define now carry a warning, and under `.strict` no longer carry a Z-segment error for it; messages whose MSH-12 is a VID with components (the AU form) are now validated against their declared version instead of v2.5.1.
- An MSH-12 that is populated but names no modelled version now carries `versionNotRecognised` (warning) naming the v2.5.1 fallback (P3-5). The P3 fix wave extends this to every populated MSH-12 from which no version resolves: whitespace only, an empty VID.1 with VID.2 valued, and a VID.1 with a subcomponent. `ParserOptions.rejectUnknownVersion` throws `unsupportedVersion` for the same shapes. Only an empty MSH-12 falls back without a version issue, because the required-field check reports it; no MSH-12 shape falls back silently.
- AU v2.4 traffic meets the v2.4 grammar, which carries no component optionality. AU conformance points that had relied on a v2.5.1 base component requirement are stated by the AU profile itself: HL7au:00049.1 (MSG-1) and 00044.1.1 (CX-1) defer to the base check where the grammar version has one (`ComponentRequirement.yieldsToBase`), and 00044.3.1 (EI-1) and 00044.7.1 (XCN-1), which no version's base model requires, fire on every version.
- Three additive `IssueCode` cases (ADR-014 minor).
- Re-opening an excluded version needs its spec text under `docs/standards/`, an amendment to this ADR, and an ADR-015 cycle. A new `Version` case is additive.

## Open question recorded for the owner

`2.8.1` is one point release from v2.8.2 and is excluded under Option A, so it falls back to v2.5.1 while `2.8` is substituted by v2.8.2. The asymmetry exists because `.v2_8` is an existing public case and `.v2_8_1` is not. Substituting `2.8.1` as well needs a new `Version` case; if the owner wants it, amend this ADR and extend `grammarVersion`.

## References

- `planning/reviews/README.md` X-C01, X-C02, X-C03; `planning/reviews/v2.8.2-review.md` V282-C03, V282-C09.
- HL7 v2.8.2 Chapter 2C Table 0104; Chapter 2A VID.
- ADR-003 (Z-segment policy), ADR-013 (v2.8.2 grammar version), ADR-014 (open enums), ADR-015 (extraction pipeline).
- `docs/design/permanent-limitations-register.md` section F.
