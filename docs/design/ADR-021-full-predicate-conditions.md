# ADR-021 — Full-predicate conditions and a three-state condition evaluator

**Status:** Accepted 2026-10-01 (owner decisions G6 and G9, P4-31). Closes route C of HL7au:00060.4, which is SHIPPED with the scope given under "Outcome".

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
- **The released two-state evaluator is `conditionTruth(...) == .true`.** `conditionTriggers` keeps its signature and, for every input, its answer: each atom that used to return `true` now returns `.true`, and each that used to return `false` returns `.false` or `.unknown`; Kleene AND is `.true` exactly when every operand is `.true`, and Kleene OR exactly when some operand is.
- **The one non-Kleene exception: `noRepeat(...)`.** Over a populated domain, a repetition slot the predicate cannot judge (for example an empty slot under `not in (...)`) counts as not matching, exactly as before. So `noRepeat(...)` can answer `.true` where a strict Kleene reading (NOT of an OR containing `.unknown`) would give `.unknown`. This keeps the two-state answer unchanged; it can only make the atom true, which for a "required when" condition means the field becomes required, and for the full-predicate rule means the condition is not false, so it errs towards not firing 00060.4.

Proof of no behaviour change (P4-31): the full suite passes unchanged; `ConditionTruthTests` pins `conditionTriggers` to answers frozen before the refactor (checked against commit 237f0b5) for every atom kind and fail-safe path; a digest (`ValidationDigestTests`, run with `VALIDATION_DIGEST_OUT` set) of every issue the validator reports on the 1233 extracted spec example messages and the 54 test fixtures, under both locales, with and without the three AU caller assertions, is byte-for-byte identical before and after; and `scripts/extract-example-messages.py --check-registry` stays at 138 entries, 0 mismatched.

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
- **(c) Not determinable from the text.** The text prints no predicate, or one that admits two readings. Not marked; ruled by the owner (G9): no derivable prohibition.
- **(n) Not decidable from the message.** The text states a predicate over facts the message does not carry (whether a substance is controlled, whether units are implied by a code, whether a specimen accompanied the order). The field stays a bare C (register §A); the prohibition half is no more decidable than the requirement half. Not marked.

## Outcome

52 candidates. Owner ruling G9 (2026-10-01) settled the classification:

- **(a) full predicate, marked and enforced (1):** v2.4 OBX-2 (`OBX-11 != X`).
- **(b) trigger only (31):** the 29 of P4-31's first pass plus PID-36 and CTI-2. Each of those two is a parent field required when its child is valued, the same shape as PID-35: the spec's own standalone breed examples (`...|L-80900^Weimaraner^SNM3|...`, §3.4.2.36) and the CTI segment's purpose, to "identify the clinical trial, phase and time point" (§7.8.4), with the time-point rule stated on CTI-3 (§7.8.4.3), show the parent may be sent alone.
- **(c) no derivable prohibition from the text (8):** RQ1-2/3/4/5 (the "either ... or" is read inclusively: it sets a minimum, and the text prints no prohibition on sending both pairs); RXE-10/18/19 (no predicate printed; bare C, register §A); PTH-6 (cites a "terminate" event Chapter 12 does not define).
- **(n) no derivable prohibition from the message (12):** the predicate depends on facts the message does not carry.

Classes (b), (c) and (n) carry no prohibition, each for its own recorded reason. HL7au:00060.4 is SHIPPED with that scope. The per-field table with quotes is in `docs/design/conditional-completeness-audit.md` ("HL7au:00060.4 route C classification").

## Consequences

- AU traffic gains a new error on the one marked field, OBX-2 under OBX-11 = X. Default `.international` output is unchanged.
- New C conditions are not marked by default. Marking is a per-field, per-version claim with its own citation; any later DSL capability or re-read can add fields without touching the evaluator.
- `conditionTruth` is available to any future check that must act on "definitely false".
