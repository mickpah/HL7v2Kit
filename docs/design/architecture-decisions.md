# Architecture decisions

This document records every architecture decision that shapes HL7v2Kit, one section per
decision. Each section keeps its original number (`ADR-001` to `ADR-021`) as a stable heading
and anchor, so a bare mention such as "ADR-019" in a source comment, a schema or the
limitations register still names the right section.

Each section states the decision as it stands today. Where a later task changed it, a short
**Amended** or **Superseded** note says what changed and why, naming the task tag. The original
records, with their dated amendments, evidence and run logs, are kept unchanged under
[`docs/archive/adr/`](../archive/adr/).

Section layout: status, context, the decision (what holds today), consequences, and the
amendment notes.

| Number | Decision |
|---|---|
| [ADR-001](#adr-001-ast-model) | AST model |
| [ADR-002](#adr-002-error-strategy) | Error strategy |
| [ADR-003](#adr-003-z-segment-policy) | Z-segment policy |
| [ADR-004](#adr-004-codegen-over-macros) | Code generation over macros |
| [ADR-005](#adr-005-dictionaries-strategy) | Dictionaries strategy |
| [ADR-006](#adr-006-portable-core-boundary) | Portable core boundary |
| [ADR-007](#adr-007-au-profile-architecture) | AU profile architecture |
| [ADR-008](#adr-008-cross-segment-dsl) | Cross-segment DSL |
| [ADR-009](#adr-009-componentvalueset-extensions) | `componentValueSet` extensions |
| [ADR-010](#adr-010-dsl-extensions-peer-absent-quantification-content-gated) | DSL extensions |
| [ADR-011](#adr-011-composite-value-inequality-and-value-conditional-rules) | Composite inequality and value-conditional rules |
| [ADR-012](#adr-012-v26-grammar-version) | v2.6 grammar version |
| [ADR-013](#adr-013-v282-grammar-version) | v2.8.2 grammar version |
| [ADR-014](#adr-014-api-evolution-policy) | API evolution policy |
| [ADR-015](#adr-015-segment-coverage-extraction-pipeline) | Segment-coverage extraction pipeline |
| [ADR-016](#adr-016-code-table-registry) | Code-table registry |
| [ADR-017](#adr-017-datatype-component-grammar) | Datatype component grammar |
| [ADR-018](#adr-018-supported-version-set) | Supported version set |
| [ADR-019](#adr-019-message-structure-grammar) | Message-structure grammar |
| [ADR-020](#adr-020-composite-views-and-version-union-accessors) | Composite views and version-union accessors |
| [ADR-021](#adr-021-full-predicate-conditions) | Full-predicate conditions |

## ADR-001 AST model

**Status:** Accepted. Related: ADR-002, ADR-006, ADR-020.

**Context.** An HL7 v2 message nests five levels deep (segment, field, repetition, component,
subcomponent), one delimiter per level. Libraries that flatten fields to strings or skip the
repetition layer lose the round-trip property: the exact bytes the sender wrote can no longer
be reconstructed. Round-trip byte equality is one of the package's primary correctness
invariants.

**Decision.**

- Every wire level is a distinct value type: `Field` holds `[Repetition]`, `Repetition` holds
  `[Component]`, `Component` holds `[Subcomponent]`, `Subcomponent` holds a `String`. All are
  `Sendable`, `Equatable` and `Hashable`, with no shared mutable state.
- Round-trip guarantee: parsing then serialising an accepted message reproduces its bytes.
- The ergonomic cost is hidden by convenience constructors (`Field.scalar`,
  `Field.components`), cascading `stringValue` accessors, and generated typed-segment accessors
  (ADR-004) that return `String?` for scalar types and `Field?` for structured ones.
- Named composite access sits above the AST as generated composite views (ADR-020); the AST
  itself is never collapsed.

**Consequences.** Path access (`msg["PID-5.1.2"]`) maps directly onto AST navigation, and the
typed accessors and the validator share one AST. A one-character field still builds four
nested values; the cost is small and unmeasured on the hot path. `RoundTripTests` and the header
on `Field.swift` guard against well-meant attempts to collapse a layer. A port of the kernel
(ADR-006) translates `Field.swift` verbatim and re-runs the round-trip property test.

**Amended:** the composite typing that the original left as future work landed as composite
views (ADR-020, epic P10).

## ADR-002 Error strategy

**Status:** Accepted. Related: ADR-001, ADR-003, ADR-014.

**Context.** A message can fail structurally (the bytes are not parseable as HL7 v2) or
grammatically (it parses, but breaks a per-segment rule). Libraries that throw for both are
hostile to triage and quarantine workflows, to per-field reporting across large batches, and to
parse-now, validate-later pipelines. A present Z-segment, for one, is not a parse failure.

**Decision.**

- Fatal: `Parser.parse(_:)` throws `ParseError` when the input is not structurally HL7 v2. The
  cases are `emptyInput`, `missingMSH`, `invalidMSH(reason:)`, `unsupportedVersion(found:)`,
  `unknownSegment(id:position:)` (only when `ParserOptions.allowUnknownSegments` is `false`;
  ADR-003), `unsupportedCharacterEncoding(declared:)` and `truncatedMessage(atByte:)`.
- Non-fatal: `Validator.validate(_:)` does not throw. It returns a `ValidationReport` of
  `ValidationIssue` values, each with a severity (`.info`, `.warning`, `.error`), a categorical
  code, a location (segment, occurrence, optional field) and a message. `isValid` is true when
  there is no error-severity issue.
- Every public error is an enum with associated values, `Equatable` and `Sendable`, and carries
  its location. `ParseError` lives in the portable kernel (ADR-006) and holds no Foundation
  types; `ValidationIssue` is spec-semantic and outside the kernel.
- Case evolution follows ADR-014.

**Consequences.** Parse and validate are two explicit calls, which suits lenient workflows and
costs single-shot callers one extra line. The non-throwing validator signature is
self-documenting: making it throw would break every call site. `errors`, `warnings` and `infos`
filter the report by severity.

**Amended (R10):** `ParseError.malformedField`, sketched here and shipped, was never raised and
was removed at the 2.0 boundary.

## ADR-003 Z-segment policy

**Status:** Accepted. Related: ADR-002, ADR-005, ADR-018.

**Context.** HL7 v2 reserves `Z`-prefixed segment IDs for site-specific extensions, and
Australian traffic uses them routinely. Rejecting them makes the library unusable on
production traffic; guessing their layout invents semantics the sender never stated. The
consumer, not the library, should decide.

**Decision.** Three layers, each with a safe default and a strict opt-in:

- Parser default: any segment ID parses. An ID with no typed-segment registration comes back
  as `UnknownSegment` (ID plus raw fields, no typed accessors). Path access still works, because
  it walks the AST.
- Strict parsing: with `ParserOptions.allowUnknownSegments` set to `false`, `parse(_:)` throws
  `ParseError.unknownSegment(id:position:)` on the first unrecognised ID.
- Validation policy: `ValidationOptions.zSegmentPolicy` is `.ignore` (default), `.warnPresence`
  (an info `zSegmentPresent` issue per Z-segment) or `.reject` (an error per Z-segment).
- Only IDs beginning with `Z` enter the Z-segment branch. Any other ID with no grammar entry for
  the applied version is reported as `segmentNotInVersionGrammar` (warning) under every policy.
- The package never invents typed accessors for unknown segments and ships no registry of
  "known" Z-segments. Site-specific grammars belong in higher layers.

**Consequences.** Australian traffic parses by default; a sender can still enforce
completeness on its own outgoing messages; audit and rejection are chosen at validation time.
The three-knob surface is more API than one switch, documented on `ParserOptions` and
`ValidationOptions`.

**Amended (ADR-018, P3):** a non-`Z` ID with no grammar entry was previously routed into the
Z-segment branch; it is now `segmentNotInVersionGrammar`, so a standard segment is never
labelled a Z-segment.

## ADR-004 Codegen over macros

**Status:** Accepted. Related: ADR-005, ADR-015, ADR-016, ADR-017, ADR-019, ADR-020.

**Context.** Seven versions of roughly 140 segments at about 25 fields each is far too much
typed surface to write by hand, and the per-field metadata (optionality, repeatability,
datatype) that shapes an accessor is exactly what the validator needs. One source of truth is
required. The options were Swift macros, build-time templating (gyb and friends), or an
explicit generator whose output is committed.

**Decision.**

- An explicit generator, the `HL7v2KitCodegen` executable target, reads the hand-curated and
  extracted JSON under `Resources/` and emits Swift into the `Generated/` directories (segments,
  segment grammars and the parser's registry, composite views, code tables, datatype grammars,
  locale data, message structures).
- The output is committed. `bash scripts/regenerate-typed-segments.sh` is the only way it
  changes; nobody hand-edits a `Generated/` file.
- The codegen-drift CI job regenerates and fails on any diff, so a schema edit without its
  regenerated output cannot merge.
- Output is deterministic: consecutive runs are byte-identical.
- The generator does not depend on the library target; it is data conversion, not public API.

**Consequences.** Every generated accessor is reviewable as plain Swift, and a schema change
shows its JSON and Swift diffs side by side. There is no per-build macro cost, and generated
members are indexed by DocC like any other source. The price is an onboarding rule ("don't
hand-edit `Generated/`"), carried by file headers, the contributing guide and CI. Macros are
"not now", not "never".

**Amended:** the generator's scope grew from typed segments to every generated artefact listed
above (ADR-005 Path C, ADR-016, ADR-017, ADR-019, ADR-020); the method is unchanged.

## ADR-005 Dictionaries strategy

**Status:** Accepted (Path C). Related: ADR-002, ADR-004.

**Context.** The validator needs a per-segment, per-field grammar (optionality, repeatability,
datatype), and the same metadata drives typed-segment generation. The founding spec proposed a
separate `HL7v2KitDictionaries` target loading per-version JSON at run time. By the time the
validator was built, the schemas under `Resources/schemas/` already carried everything needed,
and the generator could emit a grammar table as easily as it emits typed segments.

**Decision.**

- Path C: the generator emits one Swift literal grammar table per version
  (`SegmentGrammar+vX_Y_Z.swift`) into the main target, from the same schemas that drive the
  typed segments.
- `Resources/schemas/` stays the single source of truth; nothing is loaded from JSON at run
  time.
- Rejected: reading `Resources/schemas/` at run time (a development-time location, not
  bundled) and a separate dictionaries target with run-time JSON (a schema fork and a
  first-use parse cost for no user value).

**Consequences.** One JSON edit and one regenerate update the typed surface and the validator
together, and the drift job keeps them in step. Validation pays no deserialisation cost. The
grammar is compiled in, so selecting a different grammar means a different package version; no
consumer has asked for run-time dictionaries.

**Amended (R10):** the placeholder `HL7v2KitDictionaries` target, kept "in place for v0.1.0",
was never imported and was retired at the 2.0 boundary with its product and test target.

## ADR-006 Portable core boundary

**Status:** Accepted. Related: ADR-001, ADR-002.

**Context.** Swift is the right language for the package's first consumers, but plausible
future consumers (a hosted service, cross-platform command-line tools, other platforms, a
community port) might want the core in another language. Porting now would buy optionality that
may never be used; the shape of the Swift code, though, decides how cheap a later port would be.

**Decision.** The package stays in Swift, structured as two strata held as an architecture
invariant.

- Stratum 1, the portable kernel: pure parse, serialise and path logic. Rules: no
  Foundation-specific APIs (`Data` only at the edges, converting to and from `[UInt8]`);
  explicit byte or character scanning rather than Swift-only string cleverness; no protocols,
  generics or property wrappers on the parse path; errors are plain enums with associated values
  (ADR-002); concurrency annotations never carry logic.
- Kernel files carry a header comment naming them as kernel and pointing here: `Parser.swift`,
  `ParseError.swift`, `Serializer.swift`, `Field.swift`, `Path.swift`,
  `EncodingCharacters.swift`, `EscapeSequences.swift`, `Version.swift`, `HL7Locale.swift` and
  `MLLPCodec.swift`.
- Stratum 2, the Swift skin: typed-segment protocols and type erasure, `Message` conveniences,
  generated typed segments, and any `Codable` or description conformances. It may use all of
  Swift and must not leak into the kernel.

**Consequences.** A port is "translate the kernel, write an idiomatic skin", not a rewrite. The
kernel is also where the interesting correctness properties live (round-trip, escapes), so the
boundary aids testing. The cost is the occasional few lines of manual code where Foundation had
a one-liner, and the boundary needs watching in review. This keeps the door unlocked; it does
not commit to a port. A porter starts with `Field.swift` and `Path.swift`, keeps empty
subsequences when splitting (empty fields must survive for round-trip), and uses the round-trip
property (ADR-001) as the port's acceptance test.

**Amended (R6):** the one-shot script that stamped the kernel headers was retired once every
kernel file carried the marker.

## ADR-007 AU profile architecture

**Status:** Accepted. Related: ADR-008, ADR-009, ADR-010, ADR-011, ADR-016, ADR-019, ADR-021.

**Context.** The Australian localisation profile HL7AUSD-STD-OO-ADRM-2021.1 (the ADRM) layers
narrowings over HL7 v2.4: extended usage codes (`RE`, `CE`), tightened optionality, AU value
sets, pre-adopted v2.5-and-later fields, tighter required components on composites, and
constraints that fire only for some message types. Baking these into the base schemas would make
them unfaithful to the HL7 standard and mislead non-AU integrators; a duplicated schema tree per
profile would drift.

**Decision.**

- Locale is a first-class public mode. `HL7Locale` has `.international` (the base standard,
  the default) and `.auLocalisation`. It is passed to `Parser` and `Validator` (or set as
  `ValidationOptions.locale`) and is reported back on `Message.locale` and
  `ValidationReport.locale`, read-only.
- The base schemas stay faithful to the standard. AU narrowings live in an internal `Profile`
  value, `Profile.auADRM2021`, hand-curated in compiler-checked Swift and returned by
  `Profile.load(for:)`. `Profile` and its rule types are not public API.
- A violated AU rule is reported as `profileConstraintViolation(localeRule:)`, whose associated
  value carries the verbatim HL7au rule identifier and citation. No rule ships without a citation.
- The profile is a set of rule tracks: field overrides (usage, required components, component
  value sets with optional subcomponent and condition, patterns, correspondences, lengths,
  time-zone requirements), composite overrides (required components, pair conditionals,
  inequalities, value conditionals), grammar extensions (the pre-adopted PID-35 to PID-38 on
  v2.4), cardinality extensions, uniqueness rules, escape prohibitions, sub-ID trees, group
  ordering rules and the full-predicate rule (ADR-021).
- Scope: `.auLocalisation` governs a message of every version. Field-level rules apply on every
  version, read through that version's grammar; the ADRM profile structures apply only when the
  message's base structure is v2.4 (limitations register section B).
- Profile structures: the ADRM's own message structures (ADR-019) include ORR_O02 with the
  `[PID` cell read as the base v2.4 reading, and the Appendix 8 simplified REF as a variant of
  the AU REF_I12 selected by the identifier MSH-12.3.1 declares (public
  `StructureVariant.profileIdentifiers`).
- Caller assertions: four `ValidationOptions` properties (among them
  `auAssigningAuthorityTable`) assert facts the message cannot carry; each is silent by default.
- The locale axis carries AU code-table content (ADR-016), with `localTableExtensions` honoured
  on the AU value sets for Tables 0074, 0200, 0203 and 0363.
- Mapping (to FHIR or anywhere else) is out of scope: the package reports what it validated
  against and leaves downstream consumers to decide.

**Consequences.** Other localisations follow the same pattern without API change (`HL7Locale`
is an open enum). Each new rule shape is an internal track, so the profile grows without public
surface. JSON-driven generation of profiles is deferred until a second localisation makes shared
tooling worthwhile.

**Superseded (v0.14):** the original design loaded JSON overlays from
`Resources/profiles/au-adrm-2021/` at run time. The profile shipped as Swift instead; the JSON
was never consumed, drifted, and was deleted.

**Amended (R4):** the scaffolded `ProfileLoader` was folded into `Profile.load(for:)`.

**Amended (P12):** rulings G-AU1 (every version), G-AU2 (ORR_O02 reading) and G-AU3 (Appendix 8
as a declared-profile variant); new tracks `GroupOrderingRule`,
`ComponentCorrespondence.unlistedKeyValues` and `exemptKeys`, and
`ComponentValueSet.localTableExtension` (S2-2b, S2-3); `FieldOverride.length` for the ADRM's
printed length variations (S3).

## ADR-008 Cross-segment DSL

**Status:** Accepted. Related: ADR-004, ADR-007, ADR-010, ADR-021.

**Context.** The original condition DSL could only reference fields of the segment being
checked. A cluster of spec conditionals needs more: the ORC-2 and OBR-2 placer-number
relationship (cross-segment), the OBR report-message guards (message type), and ORC-8 parent and
child (the preceding ORC's ORC-1). Requirement 3 says extend the model rather than defer.

**Decision.** The single schema `"condition"` string stays the only knob; the predicate grammar
gains three categories, evaluated against the whole message:

- Cross-segment field references: `OBR-2 populated` inside an ORC entry binds to the associated
  segment (the nearest one of that ID within the current ORC and OBR group). The explicit form is
  `associatedSegment(OBR).OBR-2 ...`.
- Message context: `messageCode`, `triggerEvent` and `messageStructure`, read from MSH-9.1,
  MSH-9.2 and MSH-9.3 (`ORU_R01` in a predicate stands for `ORU^R01`).
- Position: `previousSegment(ORC).ORC-1 = PA` finds the nearest preceding segment of that ID.
- Atoms combine with `AND` and `OR`; operators are `populated`, `empty`, `=`, `!=`, `in (...)`
  and `not in (...)` (ADR-010 and ADR-011 add more).
- A reference that does not resolve, or an atom that does not parse, never makes a field
  required. Since ADR-021 that is the `unknown` state of the three-state evaluator, which a
  "required when" check treats as not triggered.
- No public API change: more spec-faithful validation under the same API is a minor release.

**Consequences.** Spec conditionals that were silently unenforced now fire, and the fixture
corpus was audited for the newly reported issues. The grammar surface grows, so additions are
kept narrow and each needs its own decision; typed predicate trees, per-schema "associated"
overrides and a parallel cross-segment rule axis were rejected.

**Amended (R4, via ADR-010):** referent parsing shares the `Path` parser.

**Amended (ADR-021, P4-31):** the evaluator is three-state; the two-state answer is unchanged.

## ADR-009 componentValueSet extensions

**Status:** Accepted. Related: ADR-007, ADR-008.

**Context.** HL7au:000040 needed two things the AU value-set track lacked: subcomponent
granularity (MSH-12.2 must equal `AUS&Australia&ISO3166_1`, three subcomponents) and message-type
gating (a VID-3 value required only on orders and results, another only on referrals). Shipping
it partially, or unconditionally, would break requirements 3 and 4.

**Decision.**

- The internal `ComponentValueSet` carries an optional `subcomponent` (nil reads the first
  subcomponent, as before) and an optional `condition` in the ADR-008 predicate DSL.
- The condition is evaluated first; when it is not true the value-set check is skipped. Several
  entries on one field with different conditions are the intended use.
- The gating reuses the one condition evaluator; no parallel message-type filter.
- No public API change: the profile types are internal (ADR-007).

**Consequences.** HL7au:000040.1 to .4 ship in full (040.5 is receiver behaviour, outside a
validator). An unparseable profile condition fails safe: the check does not fire.

**Amended (P12 S2-2b, S2-3):** `ComponentValueSet.localTableExtension` names a table whose
`ValidationOptions.localTableExtensions` entry is also allowed (ADR-007).

## ADR-010 DSL extensions: peer-absent, quantification, content-gated

**Status:** Accepted. Related: ADR-003, ADR-007, ADR-008, ADR-009, ADR-014, ADR-021.

**Context.** Three rule clusters pointed at one gap in the ADR-008 machinery: the v2.4
§4.5.1.8 ORC-8 and OBR-29 parent-reference rule over-fired because "peer segment absent" and
"peer field empty" were indistinguishable; the OBR specimen conditionals needed a segment-presence
test; and HL7au:000008 needed a group-scope count and a subcomponent-level field reference. A
bespoke rule axis per cluster would have forked the pipeline, so the one condition language was
extended instead.

**Decision.** The condition language, as it stands, is parsed in one place
(`ConditionLanguage.swift`) and read by the one evaluator:

- Atoms combine with `AND` and `OR`. A value atom is `<referent> <predicate>`.
- Referents: `<SEG>-<field>[.<component>[.<subcomponent>]]` (parsed by the shared `Path`
  parser; repetition and segment-index forms are rejected), `associatedSegment(<ID>).<ref>`,
  `previousSegment(<ID>).<ref>`, `messageCode`, `messageStructure`, `triggerEvent`,
  `nextSegmentID(<ID>|...)` and the `ValidationOptions` caller assertions.
- Predicates: `populated`, `empty`, `= v`, `!= v`, `> n`, `startsWith v`, `not startsWith v`,
  `in (...)` and `not in (...)` (a list names at least one non-empty value).
- Segment-presence atoms: `<SEG> present` and `<SEG> absent`, scoped to the current ORC and OBR
  group (message-wide otherwise), distinct from field emptiness.
- Quantifiers over repetitions: `anyRepeat(<ref>) <predicate>` and `noRepeat(<ref>)
  <predicate>`. `noRepeat` is true when at least one repetition is populated and none satisfies
  the predicate; full universal negation is written `<field> empty OR noRepeat(<field>) = v`.
- `nextSegmentID(<ID>|...)` is a lookahead: the ID of the first following segment not in the
  skip list, skipping Z-segments always (ADR-003), or empty at the end of the message. It hosts
  the TQ1-12 conjunction rule.
- Group-scope cardinality: an internal `SegmentCardinalityRule` (counted segment, scope, minimum
  count, per-segment predicate, optional `applicableWhen` gate) reports
  `segmentCardinalityBelowMinimum`. The rules live on the profile
  (`Profile.cardinalityExtensions`), so a locale-specific count never fires universally.
- Prohibitions: a field may carry `prohibitedWhen` plus `additionalProhibitions`, each with its
  own condition, severity and citation, and optionally `permitsNull` (a lone HL7 null `""` does
  not count as a value). Each holding rule raises its own `conditionalFieldProhibited`.
  `FieldGrammar.additionalProhibitions` and `FieldProhibition` are public and additive
  (ADR-014).
- Every condition string in every grammar, datatype table and the AU profile is parsed by test
  (`ConditionParseValidityTests`); a misspelt condition fails the build instead of silently never
  firing.

**Consequences.** One pipeline and one grammar serve base-standard and AU rules alike. Each
extension is narrow and fails safe: an atom that does not resolve or parse is `unknown`
(ADR-021) and never makes a field required. The grammar surface is larger, so further additions
each need a cited rule that cannot be written today.

**Amended (P1-1):** the OBR-7 and OBR-14 specimen legs (`SPM present OR OBR-15 populated`) were
wrong. OBR-15 is valued on new orders before collection and SPM may describe a virtual
specimen, so both legs raised false errors on conformant orders and were removed on every
version. OBR-9 to OBR-11 never shipped a condition (their text carries no "must").

**Amended (R2):** the schema-side `segmentCardinalityRules` key, never used by any schema, was
removed; the runtime rule type and the AU profile's rules are unchanged.

**Amended (R4):** field-reference suffix parsing routes through the shared `Path` parser.

**Amended (P4, P4-4):** `noRepeat(...)` added for prohibitions keyed to "no repetition carries
X" (SPM-13); `nextSegmentID(...)` added for TQ1-12, rejected as a segment count because it would
demand a conjunction on the last TQ1 of a chain.

**Amended (P4-21, P4-25, P4-26):** more than one prohibition per field; every condition string
validated by test, with the parse half moved into `ConditionLanguage`; a prohibition may exempt
the HL7 null (OBX-2 and OBX-5 under OBX-11 = O).

## ADR-011 Composite value inequality and value-conditional rules

**Status:** Accepted. Related: ADR-007, ADR-009, ADR-010.

**Context.** Of the HL7au:00044 CE, CNE and CWE conformance points, two were machine-checkable
but inexpressible: 00044.4.8 (the alternate coding system must differ from the primary) and
00044.4.4 (LOINC must be placed first). The composite overrides could relate only the
population state of two components, never their values. Two other points are not checkable from
the wire at all.

**Decision.**

- The internal `CompositeOverride` gains `componentInequalities` (two components must differ
  when both are populated) and `valueConditionals` (a component must not carry a denied value,
  optionally gated by a condition in the ADR-008 language).
- Both report the existing `profileConstraintViolation(localeRule:)`; no new issue code.
- 00044.4.8 ships as CE-3 differs from CE-6. 00044.4.4 ships as "CE-6 is not `LN`" on orders
  and results: a necessary condition, recorded as partial.
- 00044.5.3 and 00044.6.3 (CNE and CWE text must be valued) ship with the existing
  required-components track.
- 00044.4.3 (CE text, with a "some locations" carve-out no wire signal reveals) and 00044.4.7
  (both identifiers must reflect the same concept; needs a terminology service) are permanent
  limitations.

**Consequences.** Both rules fail safe on empty components. Each new semantic gets its own
narrow type rather than overloading the population-state pair rules or a general expression
language on composites. The CWE and CNE inequality legs were removed from the ADRM and are not
modelled.

## ADR-012 v2.6 grammar version

**Status:** Accepted (Option A, first-class v2.6). Related: ADR-004, ADR-013, ADR-018.

**Context.** Only three things in the package are version-sensitive: the `Version` case read
from MSH-12, the per-version grammar table that drives validation, and (since ADR-020) the
per-version composite and accessor metadata. v2.6 was a common version left unmodelled, which
requirement 1 does not allow in a full-standard reference tool. The options were a first-class
grammar, a recognised case with no grammar, or leaving it out.

**Decision.**

- v2.6 is a first-class grammar version: `Version.v2_6`, schemas under
  `Resources/schemas/v2.6/` extracted from the v2.6 standard with every divergence from v2.5.1
  kept as printed, and a generated `SegmentGrammar+v2_6.swift`.
- A recognised version with no grammar is acceptable only as an interim inside a delivery
  cycle, never as an end state: silence would read as conformance.

**Consequences.** The common-version set was completed before the v1.0 freeze, when adding a
`Version` case was cheapest.

**Amended (M5):** the first cycle covered the 15 most-used segments; segment coverage was
completed in M5, closing the backlog register.

## ADR-013 v2.8.2 grammar version

**Status:** Accepted (Option A, first-class v2.8.2). Related: ADR-012, ADR-018, ADR-020.

**Context.** v2.8.2 is the latest published HL7 v2.x standard and the version on which "latest
and complete" is judged; leaving it out of a full-standard reference is the sharpest form of
the requirement 1 gap. The `Version` enum already carried a grammar-less `.v2_8` case for a bare
`2.8`. v2.8.2 is a distinct point release with its own MSH-12 value.

**Decision.**

- `Version.v2_8_2` (`"2.8.2"`) is a first-class grammar version, extracted from the v2.8.2
  standard with every divergence kept as printed.
- `.v2_8` stays as a public case so a bare `2.8` still parses to a recognised version; removing
  it would have broken source for no gain. It owns no tables in the public registries; a `2.8`
  message is validated against the v2.8.2 grammar with an info issue (ADR-018).
- Where a version uses a construct the model cannot express (an optionality code, a datatype
  class, a conditional form), the model is extended rather than mapped to a near miss, as
  `FieldOptionality.withdrawn` was for `W`.

**Consequences.** Coverage spans v2.3 to v2.8.2; the `Version` surface settled before v1.0.

**Amended (ADR-018, P3):** the deferred question of how to validate a bare `2.8` is answered
by substitution with `versionGrammarSubstituted` (info).

**Superseded in part (ADR-020, P9):** the original premise that typed segments and composites
are version-agnostic, generated once from v2.5.1, no longer holds; see ADR-020.

## ADR-014 API evolution policy

**Status:** Accepted (Option B, a documented SemVer policy). Related: ADR-002, ADR-020.

**Context.** The domain keeps growing (new HL7 versions, new localisations, new validation
checks), so freezing every enum would force a major release for each. HL7v2Kit ships as a source
package without library evolution, so `@frozen` is inert; the real lever is the SemVer contract
and `@unknown default` guidance.

**Decision.**

- No `@frozen` anywhere, unless the package ever ships as an ABI-stable binary (its own
  decision).
- Open enums may gain cases in any minor release and say so in their DocC ("switch with
  `@unknown default`"): `Version`, `HL7Locale`, `IssueCode`, `ParseError`, `PathError`,
  `BuilderError`.
- Stable enums are closed by the domain: `FieldOptionality`, `FieldRepeatability`,
  `IssueSeverity`, `ZSegmentPolicy`, `LineTerminatorPolicy`, `CharacterEncoding`,
  `RequiredComponentSet.Semantics`, `Segment`. The same additive-only rule applies if the domain
  ever surprises us.
- Within a major line, changes are additive only: new cases on open enums, new types, methods
  and overloads. Removing or renaming a symbol, changing a signature or raw value, tightening
  access, or dropping a `Sendable`, `Equatable` or `Hashable` conformance waits for the next
  major.
- House style: a parameter is never added to an existing public initialiser. A new option is a
  stored property set by mutation; a new construction input is a separate overload, pinned in
  `SignatureCompatibilityTests`.
- The inventory of the public surface is `docs/design/public-api-surface.md`; the consumer-facing
  contract is the DocC article `Migration.md`.

**Consequences.** HL7 evolution ships in minor releases, and consumers who follow the
`@unknown default` guidance never break. The contract promises stability where it can be kept
and openness where the domain demands it.

**Amended (R10):** the major-release lane was used for the first time at 2.0.0, removing dead
public surface with no call sites (enumerated in `Migration.md`, "The 2.0 boundary").

**Amended (M6-D5):** on the owner's direction, OBX-5's datatype was corrected from `ST` to the
variable type every version prints, so `OBX.observationValue` became `Field?`. The change was
breaking, so the release was 3.0.0. It was a spec-fidelity fix under requirement 4, not a policy
change; additive-only resumed for the 3.x line.

## ADR-015 Segment-coverage extraction pipeline

**Status:** Accepted (Option A, `pdftotext -layout`). Related: ADR-004, ADR-014, ADR-016,
ADR-017.

**Context.** Full segment coverage on every supported version means roughly 150 segments per
version, and the schemas must be a faithful rendering of the standard's attribute tables, not a
best guess. Reading the PDFs by hand does not scale. A gotcha worth recording: PDFKit's text
output reads the attribute tables column-major, so the `OPT` and `RP/#` columns that matter
most come out as a bunched run that cannot be zipped back onto the rows (the tables, like the
Norwegian Blue, look perfectly fine until one examines them closely), and geometric
reconstruction from character bounds fragmented as well.

**Decision.**

- `pdftotext -layout` (poppler) is the uniform attribute-table extractor on every version: it
  keeps the visual columns, so each row survives as one line. A parser locates tables by their
  header row, bins columns by the header's positions (v2.8.2 adds `C.LEN`), folds continuation
  lines and emits a structured intermediate.
- The extractor is a development-time aid, not a package dependency; `Package.swift`
  dependencies stay empty. Golden-file tests let contributors without poppler validate the
  committed schemas.
- The extractor proposes; a person verifies against the standard's text, and the schema carries
  its citation. A table the parser cannot bin is reported, never silently mis-read.
- The v2.8.2 Word sources (`textutil`, BEL-delimited cells) are an independent cross-check.
- Rejected: PDFKit geometric reconstruction (fragile, worst on the oldest versions), Word-only
  extraction (v2.8.2 alone ships Word) and continued manual reading (does not scale and invites
  transcription errors).
- The method is documented in `docs/design/segment-coverage-extraction.md`. Where a table uses a
  form the model cannot express, the model is extended.

**Consequences.** Full coverage became a mechanical but verified sweep (M5), completed as
additive releases. Only derived schema JSON is committed; the standards' PDFs stay outside the
repository.

## ADR-016 Code-table registry

**Status:** Accepted. Related: ADR-007, ADR-015, ADR-017, ADR-019.

**Context.** HL7 code tables were not modelled: the schemas dropped the `TBL#` column. A
registry has to be complete enough to be a reference and conservative enough that a membership
check never rejects a value the standard allows. Three facts shaped it: a field can bind more
than one table; a printed table is not always a closed set (a bare `...` row, an open range,
local-extension rows, a row meaning "not present"); and a localisation may widen a base table.
Tables change between versions, so one merged set would be wrong.

**Decision.**

- Contents: per-version JSON, `Resources/tables/v<version>/NNNN.json` (kind `HL7` or `User`,
  name, `permitsLocalExtensions`, citation, entries, optional `patterns`), written only by the
  extractor from Appendix A (v2.3 to v2.6) or Chapter 2C (v2.7.1, v2.8.2), and generated into
  `HL7TableRegistry`; `HL7TableRegistry.table(_:version:)` is the lookup.
- Rows are kept as Appendix A prints them, misprints included. A Table 0354 misprint is
  corrected only on the message-structure side, by a cited erratum (ADR-019).
- Corrections are never hand edits: they go in `Resources/tables/overrides.json`, version-scoped
  and cited, and the table is re-extracted. Print-versus-prose binding conflicts are resolved in
  `scripts/table-repairs.json` with a citation.
- Field bindings: `tables` (any datatype) records the spec's `TBL#` cell; `table` (one string,
  `ID` and `IS` fields only) is the enforced link, derived where a field binds exactly one table.
  The integrity audit fails if `table` is not among `tables`.
- The closed-set rule: `valueNotInTable` fires only on an `ID` field bound to a closed table
  (kind `HL7`, no local extensions, at least one entry). `IS` fields and user-defined tables are
  linked, never enforced. Empty and HL7-null values are never checked.
  `ValidationOptions.checkCodeTables = false` (and the `lenient` preset) suppress the check.
- Openness: an HL7 table that printed `...` beside other rows stays open unless an override
  closes it. A table is open when its governing field's prose cites it "for suggested values" or
  says it may be extended locally, and closed when the prose says "valid values" or is silent;
  where the field prose calls an HL7 table user-defined, the chapter wins and the kind becomes
  `User`. Where governing fields disagree, the table stays as printed and individual fields are
  opened with `tableOpen` plus a quoted `tableOpenCitation`. Table 0203 is open on v2.4 to
  v2.8.2 (owner gate G5).
- Pattern rows naming a family of codes (0203 `NNxxx`) are declared as `patterns` and matched in
  full.
- Locale axis: `Resources/tables/locale/<locale-id>/` holds a localisation's own rendering;
  `HL7TableRegistry.table(_:locale:)`. It is consulted only after the version's table has
  rejected a value, so a locale can widen but never reject, and a locale rendering that is open
  admits every value. Narrowing a value set is a profile rule, not a table.
- Local extension is caller-declared: `ValidationOptions.localTableExtensions` lists the codes a
  site has added per table, consulted after the version and locale checks at field and component
  level. Nothing is inferred from the wire.
- Audit: `scripts/audit-schemas.py --tables` (shape, suspect codes with a cited allowlist, kind
  mismatches, schema links; `--depth` re-extracts and reports drift).

**Consequences.** The check is live on more than 1,200 `ID` fields across seven versions; a
handful of advisory kind mismatches remain where the print itself is inconsistent, none
enforced. Generated Swift keeps each expression small: one version's grammar emitted as a
single dictionary literal took sixteen minutes to type-check (not three million years, but
Lister would have known the feeling), so codegen emits one constant per segment.

**Amended (P2 fix wave, P2-6, P2-7, P2-13, P2-14, P2-15):** the single openness criterion, the
0203 opening, pattern rows, caller-declared local extensions and per-field `tableOpen`.

**Amended (ADR-017):** component-level table links, deferred here, shipped there.

**Amended (P7-8):** kind mismatches resolved against the defining chapter where it prints the
kind.

**Amended (P12 S2-2, S3-2, S3-3):** AU locale renderings of Tables 0396 (open), 0203 (with its
`NNxxx` row), 0191 and 0291 (open, because the ADRM imports them from the IANA media-type
registry).

## ADR-017 Datatype component grammar

**Status:** Accepted. Related: ADR-014, ADR-015, ADR-016, ADR-020.

**Context.** The table bindings integrators ask about most sit on components (`XPN.7`,
`XTN.2`, `XAD.7`), and the package had no per-version model of a datatype's components.
v2.5.1 and later print regular component tables; v2.3 to v2.4 define components only in prose.

**Decision.**

- Data: `Resources/datatypes/v<version>/<DT>.json` (components with index, name, datatype,
  printed optionality, bound tables), written only by the extractors and generated into
  `DataTypeGrammarTable`; `grammar(_:version:)` is the lookup and `optionalityCode` is the
  printed code verbatim (`RE` has no `FieldOptionality` equivalent).
- Sources: the printed component tables on v2.5.1, v2.6, v2.7.1 and v2.8.2. On v2.3 to v2.4,
  numbered section headings (`"source": "prose"`), completed by the printed "Components:" line,
  which ranks below the headings and never binds a table; line-only composites (CD, CF, TS);
  field-local composites for `CM` fields (`fields/<SEG>-<N>.json`, `"source": "prose-field"`).
  MA and NA have no grammar by design (open lists of NM).
- A prose table binding must pass three tests: the subsection names exactly one table, that
  number is in the version's registry, and any table name stated matches the registry's name.
- Resolution: every composite-aware check resolves a field's grammar through
  `Validator.fieldGrammar(segment:field:dataType:version:)` (a primitive stays primitive, else the
  field-local grammar, else `Validator.componentGrammar(_:version:)`, which treats `TS` as
  primitive). The lookup uses `Version.grammarVersion`.
- Code tables on components: a populated `ID` component bound to exactly one closed table must
  carry one of its codes, reported as `valueNotInTable(table:)` at the component. ADR-016's
  guards all apply. One level of nested composite is checked (the HD in `CX.4`, at `CX.4.3`);
  OBX-5 is checked under the datatype OBX-2 declares. A top-level `CE` component bound to a
  closed HL7 table is checked only when CE.3 (or CE.6, for the alternate) names that table as
  `HL7nnnn`. Table 0354 (MSG.3) is linked and never enforced.
- Required components are exactly those the version's component table prints `R`; the old
  hand-written lists are informational. Of the either-or rules, only HD (1, or 2 and 3 together,
  which must both be valued or both empty) survives.
- Conditional components: `C` conditions stated in prose ship on `ComponentGrammar.condition`,
  cited in `Resources/datatypes/conditions.json`, in a small predicate language that includes
  `repeated`. The "as of v2.7" family ships on `conformanceCondition`, evaluated only when
  `ValidationOptions.conformanceConditionSeverity` is set.
- Length and optionality: a printed normative length draws `componentLengthOutOfRange` under
  `normativeLengthSeverity`; a populated `B`, `X` or `W` component draws `componentNotSupported`
  under `warnDeprecatedFields`. The same rules apply one level down to subcomponents.
- Evidence rule: normative text (tables and prose) decides. A printed example overturns a table
  only when normative prose agrees with it, or when the rule's data is plainly a spelling or
  extraction artefact. `audit-schemas.py --examples` applies the component rules to every
  printed datatype example as a standing audit.

**Consequences.** Component checks found real defects on their first runs, in the fixtures and
in the registry alike. Known limits stay in the limitations register: conditions the model
cannot express (CWE.7 and kin, CNE.20), OM2-6 on v2.3 to v2.4, and the CM field table mentions no
rule can attribute to one component (section D).

**Amended (M11):** nested composites and OBX-5.

**Amended (M13, P5):** v2.3 to v2.4 read from prose, then from the printed Components line,
TQ and field-local composites. The prose name test caught real mis-bindings (v2.3 QSC.4 cites
"0102 - Relation conjunction", but v2.3's 0102 is Delayed Acknowledgment Type).

**Superseded (M14):** the hand-written required-component lists contradicted the print; the
printed `R` governs, which also enforces `MSH-9.3` from v2.5.

**Superseded (M15, M16):** the XTN, PL, CWE and EIP either-or rules were removed because each
rejected an example the standard prints or could never fire; HD's both-or-neither sentence
shipped.

**Amended (M17, M18, M26, M27, M28):** the examples audit and the evidence rule; conditional
components, with the "as of v2.7" family held back to an opt-in tier because the standard's own
v2.7-and-later examples violate them in 62 to 100 percent of values; `repeated` for XAD.7.

**Amended (P10-2):** v2.7.1 component tables.

**Superseded (P11 S1):** component length and optionality, previously recorded but not
enforced, are enforced for components and subcomponents.

## ADR-018 Supported version set

**Status:** Accepted (Option A, as amended by P10-6). Related: ADR-003, ADR-013, ADR-014,
ADR-015.

**Context.** Requirement 1 asks for the full HL7 v2.x standard, but the package never said
which releases it leaves out. A `2.8` message passed validation with nothing checked; other
Table 0104 versions silently fell back to v2.5.1; a VID-form MSH-12 (the AU form) was read as a
scalar and fell back too.

**Decision.**

- A version is modelled (its own `Version` case, segment grammar, code tables and component
  grammar, each extracted from its own text), substituted (a `Version` case validated against
  another modelled version, and every report says so), or excluded (no case; it parses, falls back
  to the v2.5.1 grammar and warns).
- MSH-12 is read as a VID: the version is VID.1. `Version.grammarVersion` is the single mapping;
  the public registries stay version-literal.
- A non-`Z` segment with no entry in the applied grammar is `segmentNotInVersionGrammar`
  (warning), never a Z-segment.
- An excluded or unresolvable populated MSH-12 (whitespace, empty VID.1 with VID.2 valued, a
  VID.1 with a subcomponent) falls back to v2.5.1 with `versionNotRecognised(wireValue:)`
  (warning); under `ParserOptions.rejectUnknownVersion` (set by `.strict`) it throws
  `ParseError.unsupportedVersion(found:)`. An empty MSH-12 is reported by the required-field
  check.
- The version table today (pinned by `VersionHandlingTests.versionMatrix`):

| MSH-12 (VID.1) | Status | Grammar applied | Issue raised |
|---|---|---|---|
| 2.3, 2.3.1, 2.4, 2.5.1, 2.6, 2.7.1, 2.8.2 | Modelled | Its own | none |
| 2.7 | Substituted | v2.7.1 | `versionGrammarSubstituted` (info) |
| 2.8 | Substituted | v2.8.2 | `versionGrammarSubstituted` (info) |
| 2.1, 2.2, 2.5, 2.8.1, 2.9, any other | Excluded | v2.5.1 fallback | `versionNotRecognised` (warning) |

- Excluded versions are recorded in the limitations register, section F. Re-opening one needs
  its text, an amendment here, and an ADR-015 extraction cycle.

**Consequences.** `2.8` and `2.7` messages are checked against the nearest published grammar,
with the unverified differences stated in the info issue. AU v2.4 traffic meets the v2.4
grammar; AU conformance points that relied on a v2.5.1 base component requirement are stated by
the profile itself (`ComponentRequirement.yieldsToBase`). `2.8.1` falls back to v2.5.1 while
`2.8` is substituted, because `.v2_8` was an existing public case and `.v2_8_1` is not; adding it
is an open question for the owner.

**Amended (P3 fix wave):** every populated MSH-12 from which no version resolves warns; none
falls back silently.

**Amended (P10-6):** v2.7.1 modelled; `2.7` substituted by v2.7.1 (owner gate G11), so
`Version` has nine cases, seven modelled and two substituted.
