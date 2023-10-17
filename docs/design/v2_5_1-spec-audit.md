# HL7 v2.5.1 schema audit — v0.4-S1

**Date:** 2026-06-17 (re-framed under the working notes project requirements)
**Audited:** `Resources/schemas/v2.5.1/*.json` (9 segments: MSH, PID, ORC, OBR, OBX, NK1, PV1, NTE, AL1)
**Reference:** HL7 v2.5.1 spec, public-record copies of the published per-segment field tables.
**Lens:** the working notes project requirements — **feature-complete over AU-specific; integrator primary-reference tool**. Audit conclusions must be defensible against the HL7 v2 spec text alone, not against test-fixture observations or AU vendor behaviour assumptions.

## Outcome summary

**Per-field attributes (name / dataType / optionality / repeatability)** — 198 rows audited; **0 corrections warranted**. The schemas faithfully render the spec on these four axes.

**Conditional predicates and required-component metadata** — **3 spec-completeness gaps identified**. Each gap is a defect the project must close before v1.0 freezes the API:

1. **PID-36 over-broad condition predicate** — fires false-positive on legitimate spec-compliant messages.
2. **Compound predicates not expressible in the v0.2-V1 DSL** — multiple `C` fields silently fall back to "no enforcement".
3. **Composite OR-rule conformance not modelled** — five composites silently skip required-component checks the spec mandates.

None of these are deferrable under the integrator-reference requirement. They are blockers that must land before v1.0. Sequencing is captured in the v0.4 cycle plan (new stage S4) and is in scope for the current cycle.

## Audit methodology

For each segment, every field row was cross-referenced against the HL7 v2.5.1 spec on five attributes:

1. **`name`** — must match the spec's field name exactly.
2. **`dataType`** — HL7 v2 type code per spec table.
3. **`optionality`** — `R` / `O` / `C` / `X` / `B`.
4. **`repeatability`** — `"1"` / `"*"` per the spec's "Repeat" column.
5. **`condition`** — predicate for `C` fields. The audit checks both **whether** a `C` field has a predicate and whether the predicate accurately renders the spec's conditional rule.

The `swiftName` field is internal naming and not audited against the spec.

## Per-segment findings

| Segment | Fields | Per-field corrections | Notes |
|---|---:|---:|---|
| MSH | 21 | 0 | Faithful. |
| PID | 39 | 0 | Faithful on per-field attributes. See Gap 1 below for PID-36 predicate defect. |
| ORC | 31 | 0 | Faithful on per-field attributes. See Gap 2 for ORC-2 / ORC-3 / ORC-8 missing predicates. |
| OBR | 47 | 0 | Faithful on per-field attributes. See Gap 2 for OBR-1 / OBR-7 / OBR-8 / OBR-10 / OBR-14 / OBR-22 / OBR-25 / OBR-26 / OBR-32 missing predicates. |
| OBX | 17 | 0 | Faithful on per-field attributes. See Gap 2 for OBX-2 / OBX-4 missing predicates. |
| NK1 | 13 | 0 | Faithful. |
| PV1 | 20 | 0 | Faithful. |
| NTE | 4 | 0 | Faithful. |
| AL1 | 6 | 0 | Faithful. |
| **Total** | **198** | **0** | + 3 spec-completeness gaps documented below. |

## Gap closure status (updated 2026-06-17 after substages A + B)

- **Gap 1 (PID-36 over-broad predicate)** — **INFRASTRUCTURE LANDED, SCHEMA-LEVEL CLOSURE PENDING.** Substage B's compound-predicate DSL admits `PID-35 not in (L1)` as a more spec-accurate predicate, but the code-system brittleness (assumes HL70447) remains. A clean closure needs either code-system-aware comparison or a project-owner decision to bake in HL70447. Tracked in substage C.
- **Gap 2 (compound predicates not expressible)** — **INFRASTRUCTURE LANDED, SCHEMA-LEVEL CLOSURE PENDING.** Substage B's compound-predicate DSL admits the full `<atom> AND <atom>`, `<atom> OR <atom>`, and `<fieldref> in (<values>)` / `not in (<values>)` grammar needed to express the spec's compound conditional rules. Schema-level rollout to ORC / OBR / OBX deferred to substage C pending authoritative spec-text citations for each per-field rule (ORC-2's value set in particular needs the canonical list, not a guess).
- **Gap 3 (composite OR-rules unenforced)** — **RESOLVED in substage A** (commit `0959be6`). `RequiredComponentSet` value type + Validator dispatch + 5 composite type updates (CWE / XTN / HD / PL / EIP). CWE specifically: was flat `requiredComponents = [(1, "Identifier")]`, which false-positive'd on CWE-9-only payloads; now `requiredComponentSet = atLeastOneOf(CWE-1, CWE-9)`. Two test changes: `cweFiresORRuleViolationOnEmptyIdentifierAndOriginalText` (renamed + updated assertion) + new positive pin `cweORRuleSatisfiedByOriginalTextAlone`. The four `…SkipsSilentlyWithNoRequiredComponents` pins for HD / PL / EIP / XTN continue to pass because their test wires already populated a satisfying combination; comments updated to reflect the new framing.

## Spec-completeness gaps

### Gap 1 — PID-36 condition predicate over-broad (DEFECT)

**Current state**: PID-36 (Breed Code) carries `condition: "PID-35 populated"`. The Validator fires `conditionalFieldMissing` whenever PID-35 has any value but PID-36 is empty.

**Spec semantics**: PID-36 is `C` "required when the subject is a non-human species" — i.e., when PID-35 carries a code other than human (typically `L1` in HL70447).

**Why it's a defect**: a spec-compliant sender that populates PID-35 = `L1^Human^HL70447` without PID-36 (the correct emission for a human patient with species explicitly declared) receives a false-positive error from the Validator. Under the integrator-reference requirement, an integrator validating veterinary-and-human-mixed traffic would see incorrect output.

**Resolution paths**:
- **(A) Extend the v0.2-V1 DSL** to support code-system-aware comparisons — e.g., `PID-35.identifier != L1` parsing the CE composite's first component rather than the flat-scalar view. Allows the predicate to express the spec's actual intent.
- **(B) Remove the predicate** and rework the v0.2-V1 demo tests to exercise a different field/predicate. Loses the v0.2-V1 demo coverage but ships an honest schema.
- **(C) Refactor the model** to support per-field `condition: "non-human species"` as a named conformance rule, not a raw DSL predicate.

(A) is the recommended path — it generalises to other code-system-aware conditions and is the minimum DSL extension that makes Gaps 1 and 2 tractable together. **Scheduled for v0.4-S4.**

### Gap 2 — Compound predicates not expressible (DEFECT)

**Current state**: 12+ `C` fields across ORC / OBR / OBX carry `optionality: C` with no `condition` predicate. The Validator's `C`-without-predicate fallback treats them as effectively optional — `conditionalFieldMissing` never fires for these fields regardless of context.

**Affected fields**: ORC-2 (Placer Order Number), ORC-3 (Filler Order Number), ORC-8 (Parent), OBR-1 (Set ID), OBR-7 (Observation Date/Time), OBR-8 (Observation End Date/Time), OBR-10 (Collector Identifier), OBR-14 (Specimen Received Date/Time), OBR-22 (Results Rpt/Status Chng - Date/Time), OBR-25 (Result Status), OBR-26 (Parent Result), OBR-32 (Principal Result Interpreter), OBX-2 (Value Type), OBX-4 (Observation Sub-ID).

**Spec semantics**: each of these has a conditional rule the spec defines (e.g. ORC-2 "Required when ORC-1 is one of NW / CA / CR / DC / NA / RP / RR / RU / SC / SN / SR / CN / RE / RO / OC / OD / OE / OF / OH / OK / OP / OR / UA / UC / UD / UF / UH / UN / UR / UX / XO" — a compound `OR`-of-equalities). The current DSL supports only single-predicate same-segment refs.

**Why it's a defect**: an integrator running the Validator on real orders expects ORC-2 to be enforced when ORC-1 is one of the order-control codes that require placer assignment. The Validator currently provides no enforcement. The integrator who consults the schema sees `"optionality": "C"` and reasonably assumes there's a conformance rule encoded — but there isn't.

**Resolution**: extend the v0.2-V1 DSL with compound predicate grammar:

```
<predicate> := <atomic> | <predicate> AND <predicate> | <predicate> OR <predicate>
<atomic>    := <segment>-<index> <op>
<op>        := populated | empty | = <value> | != <value> | in (<value>, …) | not in (<value>, …)
```

The `in (...)` and `not in (...)` operators are necessary for set-membership predicates like ORC-2's. **Scheduled for v0.4-S4.**

### Gap 3 — Composite OR-rule conformance not modelled (DEFECT)

**Current state**: five composite types ship with empty `requiredComponents`:
- **CWE**: spec requires CWE-1 OR CWE-9 populated.
- **XTN**: spec requires at-least-one-of XTN-1 / XTN-4 / XTN-12 populated.
- **HD**: spec requires HD-1 OR (HD-2 AND HD-3) populated.
- **PL**: spec requires PL-1 OR PL-4 populated (informally — see audit note).
- **EIP**: spec requires either EIP-1 or EIP-2 populated.

The Validator's `requiredComponents(forCompositeCode:)` dispatch returns an empty list for these composites, and `requiredComponentMissing` is never fired. Each composite's struct doc carries a note explaining the gap; each is pinned by a `…SkipsSilentlyWithNoRequiredComponents` test in `ComponentGrammarTests.swift`.

**Why it's a defect**: an integrator validating outgoing messages expects a populated CWE field with both CWE-1 and CWE-9 empty to be flagged. The Validator currently accepts it silently.

**Resolution**: introduce a `RequiredComponentSet` value type with disjunctive ("at-least-one-of") and conjunctive ("all-of") semantics:

```swift
public struct RequiredComponentSet: Sendable, Equatable, Hashable {
    public enum Semantics: Sendable, Equatable, Hashable {
        case allOf       // every listed component must be populated (current default)
        case atLeastOneOf
        case allOfGroupOrAtLeastOne(group: [Int])  // e.g. HD: HD-1 OR (HD-2 AND HD-3)
    }
    public let components: [RequiredComponent]
    public let semantics: Semantics
}
```

Each composite then publishes a `static let requiredComponentSet: RequiredComponentSet`. The Validator dispatches against the `Semantics` case. **Scheduled for v0.4-S4.**

## What this audit does NOT validate

- **v2.3 / v2.3.1 / v2.4 schemas** — v0.4-S2's scope. Audited as deltas against this v2.5.1 baseline.
- **v2.8 schema** — doesn't yet exist; v0.4-S3 adds it.
- **Spec table errata** — the audit uses publicly-available v2.5.1 reference materials. The official HL7 v2.5.1 ballot's errata sheets (HL7-member access) were not directly consulted. Any errata not reflected in the public references slip through.

## Conclusion (re-framed)

Under the project's the working notes requirements (feature-complete over AU-specific; integrator primary reference), the v2.5.1 schemas as of v0.3.0 are **faithful on per-field attributes (name / dataType / optionality / repeatability)** but **carry three spec-completeness defects** that must be resolved before v1.0:

1. PID-36 over-broad predicate (Gap 1).
2. 12+ `C` fields without predicates that the spec defines (Gap 2).
3. Five composite OR-rules silently unenforced (Gap 3).

The earlier framing of these as "deferrable known limitations defensible because AU traffic doesn't trigger them" was incorrect — both factually (the AU-non-trigger claim was unverified) and as a release-quality bar for an integrator reference tool.

**v0.4 cycle re-scoped** (Option α) to add S4 — the DSL extension + `RequiredComponentSet` refactor that makes all three gaps closeable. S4 unblocks the actual schema corrections; the audit re-runs after S4 lands and the schemas are updated to use the richer DSL / metadata.

This S1 commit ships the audit findings + the framing correction. The downstream code changes that close the gaps land in S4.
