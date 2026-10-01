# ADR-021 — Full-predicate conditions and a three-state condition evaluator

**Status:** Accepted 2026-10-01 (owner decision G6, P4-31). Closes route C of HL7au:00060.4 for every candidate field whose classification the spec text settles; see "Outcome" for what remains.

## Context

ADRM-2021 Appendix 5 (p. 466): "HL7au:00060.4 | Senders | Orders, Results, Referrals | HL7 message elements with a usage of C (conditional) must not be valued when the associated predicate is not satisfied." ADRM §1 (p. 11) gives C the Conformance Implementation Manual meaning: "If the predicate is satisfied: A conformant sending application must always send the element. ... If the predicate is NOT satisfied: A conformant sending application must NOT send the element."

The validator could not enforce the second half (permanent-limitations register, §D addendum "HL7au:00060.4 ... (P4-20)"), for two reasons:

1. **A stored `condition` is a "required when" trigger, not a full predicate.** `FieldGrammar.condition` records when the field becomes required. For many fields the spec text lets the field be valued while that trigger is false: "If both fields, ORC-2-placer order number and OBR-2-placer order number are valued, they must contain the same value" (v2.4 §4.5.1.2); "In all other events it is optional" (PV2-1). Negating such a trigger would prohibit conformant traffic.
2. **The evaluator answered only true or false.** "Cannot decide" (a peer segment that is not there, an atom that does not parse, a quantifier over nothing) was folded into false. That is the right fail-safe for "required when true", and exactly the wrong one for "prohibited when false": every unresolvable predicate would fire.

Route B (P4-24, P4-26) shipped the prohibitions the spec states outright. Route C, decided here, is for the C fields whose prohibition comes only from the ADRM §1 meaning of C.

## Decision

### 1. Three-state core

`Validator.conditionTruth(_:in:segmentIndex:message:currentSegmentID:)` returns an internal `ConditionTruth` (`.true`, `.false`, `.unknown`). It is the one evaluator; there is no second one.

- **Unknown** covers: a referenced segment or field that does not resolve in scope (cross-segment field refs, `previousSegment(...)`, `associatedSegment(...)`); an atom that does not parse; a quantifier with an empty domain (`noRepeat(...)` over a field with no populated repetition, `anyRepeat(...)` likewise unless an empty slot itself satisfies the predicate, as in `anyRepeat(X) empty`); and the predicates that used to fail safe on a referent they cannot judge (`> n` on a non-numeric value, `not in (...)` and `not startsWith` on an empty value).
- **AND and OR are Kleene's strong connectives.** AND: false if any operand is false, else unknown if any is unknown, else true. OR: true if any is true, else unknown if any is unknown, else false. A definite atom can still settle a compound condition that contains an unknown one.
- **The released two-state evaluator is `conditionTruth(...) == .true`.** `conditionTriggers` keeps its signature and, for every input, its answer: each atom that used to return `true` now returns `.true`, and each that used to return `false` returns `.false` or `.unknown`; Kleene AND is `.true` exactly when every operand is `.true`, and Kleene OR exactly when some operand is. Inside `noRepeat(...)` a slot the predicate cannot judge still counts as not matching, as before, so that atom keeps its answer too.

Proof of no behaviour change (P4-31): the full suite passes unchanged; a digest of every issue the validator reports on the 1233 extracted spec example messages and the 54 test fixtures, under both locales, with and without the three AU caller assertions, is byte-for-byte identical before and after; and `scripts/extract-example-messages.py --check-registry` stays at 138 entries, 0 mismatched.

### 2. Full-predicate marking

A schema field may carry `"conditionIsPredicate": true` with a `"predicateCitation"` quoting the spec. The marker asserts, for that field on that version, that the stored `condition` is the spec's complete C predicate: required when true, must not be sent when false.

- Only on a field printed `C` with a non-empty `condition`. Codegen fails on a marker without a citation, on a C-less or condition-less marker, and on a citation without a marker. `scripts/audit-schemas.py` reports the same shapes, and `scripts/check-audit-schemas.py` self-checks the predicate (the pattern of `optionalityCitation`, P4-30).
- Codegen emits the marked set into an internal lookup, `FullPredicateConditions` (`Sources/HL7v2Kit/Segment/Generated/FullPredicateConditions+Generated.swift`), keyed by schema version, segment and field. It is not public API and `FieldGrammar` is unchanged (ADR-014: no new initialiser parameter, no new public surface).
- A field is marked only when the classification below puts it in class (a).

### 3. AU enforcement

`Profile` gains an internal `fullPredicateRule`. The AU ADRM-2021 profile sets it: scope `messageCode in (ORM, ORU, REF)`, severity error ("must not"), citation HL7au:00060.4. For a populated field it reports `.profileConstraintViolation(localeRule: "HL7au:00060.4 ...")` when all of these hold:

- the field is marked for the message's grammar version and printed C there;
- the field carries a value other than the HL7 null `""` (exempt, as for every AU prohibition);
- the scope evaluates `.true`;
- the field's condition evaluates `.false` (never `.unknown`);
- no base prohibition (`prohibitedWhen`, `additionalProhibitions`) and no AU profile prohibition on the same field holds, so a field route B or the base grammar already reports is not reported twice.

The ADRM is a v2.4 profile and only v2.4 fields are marked, so a message declaring another version is not checked. `.international` output does not change.

### 4. Classification rule

Every C field in the segments v2.4 ORM^O01, ORU^R01 and REF^I12 carry (with the ADRM REF_I12 additions and the ADRM-only C on OBR-1) is read against the v2.4 text and the ADRM clause, and put in one class:

- **(a) Full predicate.** The text states the predicate, the stored condition matches it, and nothing in the text lets the field be valued while it is false. Marked.
- **(b) Trigger only.** The text shows the field may be valued while the trigger is false (an explicit "optional", "may be populated", "not required", a both-valued rule, or a use outside the trigger). No prohibition is implied. Not marked; the quote is recorded.
- **(c) Not determinable from the text.** The text prints no predicate, or one that admits two readings. Not marked; listed for the owner.
- **(n) Not decidable from the message.** The text states a predicate over facts the message does not carry (whether a substance is controlled, whether units are implied by a code, whether a specimen accompanied the order). The field stays a bare C (register §A); the prohibition half is no more decidable than the requirement half. Not marked.

## Outcome

52 candidates: 3 class (a) (v2.4 PID-36, CTI-2, OBX-2), 29 class (b), 8 class (c), 12 class (n). The per-field table with quotes is in `docs/design/conditional-completeness-audit.md` ("HL7au:00060.4 route C classification"). HL7au:00060.4 stays PARTIAL until the class (c) and (n) remainder is ruled on.

## Consequences

- AU traffic gains a new error on the three marked fields. Default `.international` output is unchanged.
- New C conditions are not marked by default. Marking is a per-field, per-version claim with its own citation; any later DSL capability or re-read can add fields without touching the evaluator.
- `conditionTruth` is available to any future check that must act on "definitely false".
