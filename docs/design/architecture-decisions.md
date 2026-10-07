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
