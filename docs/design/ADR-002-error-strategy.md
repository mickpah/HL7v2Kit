# ADR-002: Error strategy — split `ParseError` (fatal) vs `ValidationIssue` (non-fatal)

| | |
|---|---|
| Status | Accepted |
| Date | 2026-05-27 |
| Supersedes | -- |
| Superseded by | -- |
| Related | ADR-001 (AST model), ADR-003 (Z-segment policy) |

## Context

HL7 v2 messages can fail in two qualitatively different ways:

1. **Structural failures** — the byte stream is not parseable as v2 at all. Examples: empty input, no MSH segment, malformed encoding characters in MSH-2, unsupported declared character set in MSH-18.
2. **Grammar failures** — the byte stream parses successfully but violates the v2 standard's per-segment rules. Examples: a required field is empty, a single-cardinality field has multiple repetitions, a deprecated field is populated, a Z-segment is present in a profile that disallows them.

Many HL7 v2 libraries (HAPI, hl7-python) conflate both classes into a single throwing API surface. This is convenient for "parse a single message; either it's good or it's bad" workflows, but actively hostile to:

- **Triage / quarantine workflows** — "parse every message in this batch; collect the structurally-broken ones for human review, but still surface grammar issues for the structurally-OK ones so we can flag senders to fix them".
- **Per-field error reporting** — "tell me everywhere PID-3 is missing across these 10,000 messages so I can give the lab an actionable bug report".
- **Round-trip-then-validate** — "this message arrived from a sender. Parse it, store the AST, validate it asynchronously / in a different process / against different rules per consumer".

A second concern is semantics. Throwing a "Z-segment present" error from `parse(_:)` is wrong: parsing succeeded, and the application may legitimately want Z-segments. The compiler can't enforce that the caller handles a Z-segment exception any differently from a structural failure.

## Decision

Two error surfaces, each pinned by its type signature.

### Fatal: `ParseError`

`Parser.parse(_ data: Data) throws -> Message` (and the `String` overload) throws `ParseError` when the input is not structurally parseable as v2.

```swift
public enum ParseError: Error, Equatable, Sendable, CustomStringConvertible {
    case emptyInput
    case missingMSH
    case invalidMSH(reason: String)
    case unsupportedVersion(found: String)
    case unknownSegment(id: String, position: Int)
    case malformedField(segment: String, fieldIndex: Int, reason: String)
    case unsupportedCharacterEncoding(declared: String)
    case truncatedMessage(atByte: Int)
}
```

The `.unknownSegment` case fires only when `ParserOptions.allowUnknownSegments` is `false`. By default Z-segments parse as `UnknownSegment` and `parse(_:)` does not throw — see ADR-003.

### Non-fatal: `ValidationReport`

`Validator.validate(_ message: Message) -> ValidationReport` is **not `throws`**. The type signature pins the contract: callers can never get a thrown exception from validation. The report carries zero or many `ValidationIssue` values, each tagged with a severity (`.info`, `.warning`, `.error`), an `IssueCode` (categorical), an `IssueLocation` (segment + occurrence + optional field), and a human-readable message.

`ValidationReport.isValid` is `true` iff there are no `.error`-severity issues. Warnings and infos don't invalidate the report.

## Consequences

**Positive**

- Workflows that need leniency get it: parse-then-validate is now two explicit steps.
- The non-throwing validator signature is itself documentation. A future contributor can't accidentally make `Validator.validate(_:)` throw without changing every call site — the compiler stops them.
- Each issue carries a `Location` and a `Code`, so caller logic can filter by severity / code / segment without parsing the message string.
- The `ParseError` enum is `Equatable` and `Sendable`, so error-replay testing and concurrent message-pump architectures work naturally.

**Negative**

- Single-shot "is this v2 valid?" workflows become two calls instead of one. Mitigated by the convention `try Validator().validate(try Parser().parse(data))` as a one-liner. We could add a convenience `Parser.parseAndValidate(_:)`, but haven't yet — pending evidence that consumers actually want it.
- Errors and warnings collected in a single `[ValidationIssue]` array means consumers care about filtering by severity. `ValidationReport.errors / .warnings / .infos` are computed-property filters for ergonomics.

**Explicitly not promised**

- We do not promise that the *set* of `ParseError` cases is closed. Adding a case is a non-breaking change at this pre-1.0 stage (no public client code) and may happen as new structural failure modes surface. Post-1.0 the case set is stable per SemVer.

## Notes

The `ParseError` enum sits in the portable kernel (ADR-006) — it must remain a plain enum with associated values, with no Foundation types in any case. `String` is acceptable as a kernel value type.

`ValidationIssue` and friends are Stratum 2: they reference HL7 spec semantics (`IssueCode`, severity classification) that a Rust/Go port would design idiomatically for its target language.
