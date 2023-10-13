# ADR-001: AST model — explicit Field / Repetition / Component / Subcomponent hierarchy

| | |
|---|---|
| Status | Accepted |
| Date | 2026-05-27 |
| Supersedes | -- |
| Superseded by | -- |
| Related | ADR-002 (error strategy), ADR-006 (portable kernel boundary) |

## Context

HL7 v2 messages nest five levels deep: Segment → Field → Repetition → Component → Subcomponent. The wire grammar uses one delimiter per level (`\r` / `|` / `~` / `^` / `&`).

Many HL7 v2 libraries flatten this — storing fields as plain strings, lazily re-parsing component access, or skipping the Repetition layer entirely. Flattening sacrifices the *round-trip* property: once you've collapsed a structured field to a string, you can't reconstruct the exact bytes the sender sent. For some libraries that's acceptable. For HL7v2Kit it's not — round-trip byte equality is one of the project's primary correctness invariants (spec § 5), and AU senders depend on it for resending acknowledgements without semantic drift.

A second concern is API ergonomics. Most clinical fields don't use all five levels (most XPN names are just `family^given`, no repetition or subcomponent). A naive faithful AST means every access traverses four levels of optional wrappers even for trivially-populated fields.

## Decision

Model every wire level as a distinct Swift struct:

```swift
public struct Field        { public let repetitions: [Repetition] }
public struct Repetition   { public let components: [Component] }
public struct Component    { public let subcomponents: [Subcomponent] }
public struct Subcomponent { public let value: String }
```

All four are `Sendable, Equatable, Hashable, Codable`-friendly value types with no shared mutable state.

Round-trip guarantee: `Parser.parse(bytes).serialize() == bytes` for every fixture the parser accepts. The AST shape is what makes that guarantee implementable — every byte the sender wrote ends up in exactly one slot, and the serializer walks the same shape back out.

Mitigations for the ergonomics cost:

1. **Convenience constructors**: `Field.scalar("V")`, `Field.components(["family", "given"])`, `Repetition.scalar(_)` short-circuit the wrapper boilerplate for the common single-level cases.
2. **Cascading `stringValue` accessors**: `field.stringValue` returns the rendered leaf if the field is single-everything-the-way-down, else nil. Callers that know their field is a scalar can write one-liner access.
3. **Typed-segment accessors** (from ADR-004) return either `String?` (scalar HL7 datatypes) or `Field?` (structured types); the codegen template hides the ergonomics tax behind a generated property.

## Consequences

**Positive**

- Round-trip is achievable. The `RoundTripTests` suite and the inverse-property tests in `EscapeSequenceTests` rely on the AST preserving every byte the sender wrote.
- Path API (`msg["PID-5.1.2"]`) maps directly to AST navigation — segment + field + component + subcomponent.
- Typed-segment accessors and the validator both share the same AST. No duplicate parsing pipelines.

**Negative**

- A trivially-populated PID-1 (`"1"`) still constructs four nested structs. Allocation overhead is real but small (Swift value types, often stack-allocated in practice). Have not measured a hot-path regression at v0.1.0 fixture scale.
- New contributors sometimes try to "simplify" the AST by collapsing layers. The header on `Field.swift` and the existence of `RoundTripTests` are the safeguards.

**Explicitly not promised**

- Future composite typed-data types (XPN, CX, XAD as Swift structs) are a separate concern — they sit *above* the AST and decompose composite fields into named properties. v0.1.0 keeps typed accessors at `Field?` for structured types; the composite-typing layer is v0.2 work (spec § 4.5).

## Notes for the porter

If you port the kernel (per ADR-006), the AST is the most mechanical file (`Field.swift`). Translate the struct hierarchy verbatim, then verify the round-trip property test passes on your target language.
