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
