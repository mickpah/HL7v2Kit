# ADR-010 — DSL extensions: segment-presence atoms + group-scope cardinality predicates + subcomponent-granular field-refs

**Status:** **Accepted 2026-07-02.** Project-owner approval received same day. Implementation scope = the three currently-blocked rule clusters (§4.5.1.8 XOR softening, OBR specimen-presence, HL7au:000008 Display Segments). Substage plan documented under "Migration" below and mirrored in `NEXT_STEPS.md` under the v0.11 cycle. Accepted as drafted (single ADR spanning all three extensions); the "split Extension 2 into ADR-011" option in Risk remains available if S3 substage turns out too large in practice.

**Context:** v0.10 closed the per-version coverage gap and audited two remaining AU narrowings (HL7au:000001, HL7au:000008). Three separate rule clusters surfaced during that cycle each pointing at the *same* architectural gap in the ADR-008 / ADR-009 machinery:

| Cluster | Spec § / AU ident | Current behaviour | Missing capability |
|---|---|---|---|
| §4.5.1.8 XOR softening | v2.4 CH04 §4.5.1.8 | ORC-8 / OBR-29 over-fire when peer carries the parent | **Segment-presence atom** distinct from field-empty; today `OBR-29 empty` fails safe to `false` when the OBR peer is absent, conflating "peer absent" with "peer populated" |
| OBR specimen-presence | v2.5.1 §4.5.3.7 / .9 / .10 / .11 / .14 | Conditions silently never fire — no predicate mentions specimen presence | Ability to detect "specimen sent with request" by inspecting the presence of SPM (v2.5.1+) or the population of OBR-15; reuses the same segment-presence atom family |
| HL7au:000008 Display Segments | AU ADRM-2021 p. ~350 | Not shippable in v0.10 audit | Parent rule needs **group-scope cardinality predicate** ("≥1 OBX per OBR/OBX group with predicate P"); sub-rule .1 needs **subcomponent-granular DSL field-refs** (gate on `OBX-3.3 = AUSPDI`) |

Per the working notes project requirement #3 ("extend the model when the DSL can't express something") and #4 ("no predicate ships if known-incorrect"), the right move is a single ADR that lifts the model to cover all three, rather than three separate deferrals each rationalising a consumer-profile gap.

## Decision

**Extend the existing v0.7 / v0.8 machinery along three narrowly-scoped axes**, all additive, all internal, all fail-safe:

1. **Segment-presence atoms** — new DSL atom shape `<segmentID> present` / `<segmentID> absent`, evaluated at message scope (or group scope, per resolution rule below). Reads: "does a segment of the named ID exist within scope?" Distinct from field-level `<fieldref> populated` / `<fieldref> empty`. Combined with ADR-008 `associatedSegment(...)` / `previousSegment(...)`, a rule can now ask "is there an OBR peer at all?" as a stand-alone atom instead of conflating with "is OBR-29 empty?".

2. **Group-scope cardinality predicates on `SegmentGrammar`** — a new axis alongside the existing min/max occurrence bounds: an optional list of `SegmentCardinalityRule` entries carrying `(scope: GroupScope, minCount: Int, predicate: String)`. The predicate is a v0.7-DSL atom evaluated against each candidate segment within the group; the rule fires when the count of matching segments in the group is `< minCount`. First (and initially only) consumer: HL7au:000008 parent — "≥1 OBX per OBR/OBX group with OBX-3.3 = AUSPDI."

3. **Subcomponent-granular field-refs in DSL atoms** — extend the DSL grammar's `<fieldref>` production from `<segmentID>-<int>` to `<segmentID>-<int>[.<int>[.<int>]]`, so an atom LHS can read a subcomponent value. Reuses the ADR-009 `ComponentValueSet.condition` gating machinery unchanged: only the predicate parser gains new productions. Enables HL7au:000008.1 as an overlay with `condition: "OBX-3.3 = AUSPDI"` — no new dispatch layer.

None of the three touches the public API (`HL7Locale`, `ValidationIssue`, `Message`, etc.). The v1.0 stability clock (re-anchored at v0.5.0) is unaffected.

## Why

Four forces converge on a single ADR rather than three separate deferrals:

1. **All three clusters share the ADR-008 evaluator.** The v0.7 predicate parser at `Validator.swift:689+` and its message-scope helpers `Message.associatedSegment(_:fromIndex:)` / `Message.previousSegment(_:beforeIndex:)` (`Message.swift:150–187`) already run against the full `Message` context. Adding "segment exists" and "field-ref-with-subcomponent" is strictly additive parser work — same shape as the ADR-008 extension. No new evaluator, no parallel dispatch.

2. **the working notes req #3 explicitly names this case.** "When a spec semantic exceeds what the current code can model, the right move is to **extend the model** so the spec can be represented faithfully." Three distinct spec citations (v2.4 §4.5.1.8, v2.5.1 §4.5.3.7–.14, HL7au:000008) now sit in the "gap must be documented as a known limitation that **blocks** spec-completeness" bucket. Consolidating them into one ADR keeps the pre-v1.0 API-affecting fix window open, and closes three req-#3 gaps in one substage sequence.

3. **The req-#4 over-fire risk is live today.** ORC-8 and OBR-29 currently over-fire against the §4.5.1.8 XOR softening (documented in `v2_3-v2_4-spec-audit.md`). This is a shipped predicate that misfires in a spec-compliant scenario — a defect by req #4 definition. The right correction is model extension, not silent removal.

4. **Overlay codegen debt.** The alternative — a bespoke JSON axis per rule cluster (`crossSegmentXORExceptions`, `specimenPresenceRules`, `groupCardinalityOverlays`, etc.) — would fork the schema/profile pipeline into a dispatch matrix that grows with every new rule class. Extending the existing DSL grammar keeps the schema-→-codegen-→-validator surface **one pipeline, one grammar**, consistent with ADR-004 and ADR-008.

## DSL grammar extension (proposed)

Current v0.7 grammar (Validator.swift:689+, extended in ADR-008):

```
<predicate>     := <or-expr>
<or-expr>       := <and-expr> (" OR " <and-expr>)*
<and-expr>      := <atom> (" AND " <atom>)*
<atom>          := <field-atom> | <message-atom> | <position-atom>

<field-atom>    := <fieldref> " " <op>
<fieldref>      := <segmentID> "-" <int>

<message-atom>  := <message-noun> " " <op>
<message-noun>  := "messageStructure" | "messageCode" | "triggerEvent"

<position-atom> := "previousSegment(" <segmentID> ")." <fieldref> " " <op>
                 | "associatedSegment(" <segmentID> ")." <fieldref> " " <op>

<op>            := "populated" | "empty"
                 | "= <value>" | "!= <value>"
                 | "in (<values>)" | "not in (<values>)"
```

Proposed v0.11 grammar delta (three new productions, existing unchanged):

```
<atom>              := <field-atom> | <message-atom> | <position-atom>
                     | <segment-atom>                                            // NEW (Extension 1)

<segment-atom>      := <segmentID> " " <segment-op>                              // NEW
<segment-op>        := "present" | "absent"

<fieldref>          := <segmentID> "-" <int> <subcomp-tail>?                     // EXTENDED (Extension 3)
<subcomp-tail>      := "." <int>                                                 // component subcomponent
                     | "." <int> "." <int>                                       // sub-subcomponent
```

Extension 2 is **not** a DSL production — it lives on `SegmentGrammar` alongside min/max occurrence bounds:

```swift
struct SegmentCardinalityRule: Sendable, Equatable, Hashable {
    let scope: GroupScope          // .orcObxGroup, .obrObxGroup, .messageWide (initial)
    let minCount: Int              // ≥1 for HL7au:000008
    let predicate: String          // v0.7-DSL atom, evaluated per candidate segment
    let specCitation: String?
}
```

### Resolution rules (narrow on purpose)

- **`<segmentID> present`** — evaluates `true` iff at least one segment of the named ID exists within resolution scope. Default scope is **the current segment's group** (ORC/OBR peer group when the current segment is ORC/OBR; message-wide otherwise). Explicit scope may be introduced later by qualifying the atom (`SPM present in message`) — deferred to a future ADR unless a rule needs it in this cycle.
- **`<segmentID> absent`** — logical NOT of `<segmentID> present`. Distinguishes "peer segment does not exist" from "peer segment exists but field is empty" (which is `<fieldref> empty`). This is the core §4.5.1.8 unblock.
- **`<fieldref>` with subcomponent tail** — reads the named subcomponent value of the named component. `OBX-3.3 = AUSPDI` resolves as: for the current OBX segment (or the segment identified by the atom's `<segmentID>` prefix), read OBX-3 (CE data type), then component 3, subcomponent 1 (first-of, per current `Field.componentValue` convention). Note: `OBX-3.3` in HL7v2 spec parlance is *component* 3 of the CE, whose first subcomponent is "coding system" — matches AU ADRM's field reference for the AUSPDI marker. Sub-subcomponent syntax (`OBX-3.3.1`) reserved but not required for shipped rules; parser accepts it, evaluator resolves left-to-right.
- **`SegmentCardinalityRule.predicate`** — an atom-only predicate (no compound AND/OR at this stage; keeps evaluator simple). Predicate is evaluated per candidate segment in the group scope; the count of `true` results is compared to `minCount`. A rule with `minCount = 1` fires as `.segmentCardinalityBelowMinimum` (new `ValidationIssue.Kind` variant) when the group contains zero matching segments.

### Rules expressed in the extended DSL / grammar

**§4.5.1.8 XOR softening (v2.4 + v2.5.1):**
- ORC-8 condition (replacing today's `"ORC-1 = CH"`): `ORC-1 = CH AND (OBR absent OR OBR-29 empty)`
- OBR-29 condition (replacing today's `"ORC-1 = CH"`): `ORC-1 = CH AND (ORC absent OR ORC-8 empty)`

Reading: ORC-8 is required only when this is a child order AND the associated OBR either doesn't exist or doesn't carry the parent reference itself. Symmetric for OBR-29. Both fire when neither carries the parent (violation); neither fires when either alone carries it (satisfied XOR). The v0.10 `v2_3-v2_4-spec-audit.md` "known limitation" line becomes a shipped rule.

**OBR specimen-presence cluster (v2.5.1; mirror to v2.4 where spec text agrees):**
- OBR-7 second trigger: `messageCode = ORU OR SPM present OR OBR-15 populated`
- OBR-9 / OBR-10 / OBR-11 / OBR-14 conditions: `SPM present OR OBR-15 populated` (i.e. "if a specimen was sent")

`SPM present` is v2.5.1+ (SPM introduced in v2.5). For v2.4 (no SPM), the atom falls back to `OBR-15 populated` alone. Per-version schema variance is expected.

> **Correction (P1-1, review remediation)** — the OBR specimen-presence cluster above was wrong for OBR-7 and OBR-14. OBR-15 is where a specimen *should be* obtained (v2.4 §4.5.3.15), so it is valued on new orders before collection, and SPM may describe a "virtual" specimen (v2.5.1 CH07 §7.4.3). Both legs raised false `conditionalFieldMissing` errors on conformant orders and were removed on every version. OBR-7 keeps its report-message leg; OBR-14 is a bare `C` on v2.3–v2.4 (registered in `conditional-completeness-audit.md`), `B` on v2.5.1 and v2.6 as printed, and `W` on v2.8.2. The `SPM present` / `<SEG> absent` atoms this ADR introduced are unaffected. The OBR-9/10/11 leg of this cluster was never shipped in any schema — as the S4 clarification below already records, those three fields carry a bare `C` with no condition, so they are unaffected by this correction.

**HL7au:000008 Display Segments (AU ADRM-2021):**
- Parent (000008): a new `SegmentCardinalityRule` on the OBR/OBX group grammar:
  ```
  scope: .obrObxGroup, minCount: 1, predicate: "OBX-3.3 = AUSPDI"
  ```
- Sub .1 (000008.1): a new `FieldOverride` on OBX in the AU profile, **`component: 1`** (see clarification below), gated with `condition: "OBX-3.3 = AUSPDI"`, `allowedValues` = the AU display-format value set `["HTML", "PDF", "RTF", "TXT", "PIT"]` (PIT is deprecated but still supported per AU ADRM-2021 p. 247 — receivers "may find that they need to support it for practical reasons"). Uses ADR-009 machinery unchanged; only the DSL parser gains the subcomponent-granular field-ref production so `OBX-3.3` parses on the LHS.
- Sub .1.1: receiver runtime (display capability) — remains out of scope for a validator.

> **Clarification 2026-07-03 (during S2 implementation)** — this section originally wrote `component: 3` for the HL7au:000008.1 overlay. That was an editorial oversight: component 3 of OBX-3 IS the AUSPDI marker (the gate). The value-set check is on **component 1** (Identifier — HTML / PDF / RTF / TXT / PIT) per HL7au:000008.1 verbatim (AU ADRM-2021 p. 420-421 + display-format table p. 247). Implementation in `Profile+au_adrm_2021.swift` ships with `component: 1`. The intent of the ADR is unchanged; only the component-index number in the illustrative text was wrong.

> **Clarification 2026-07-03 (during S3 implementation)** — two S3 refinements extending what §"Decision" specified for Extension 2:
>
> 1. **Locale-scoped cardinality rules.** HL7au:000008 is AU-specific per AU ADRM-2021 p. 420 ("Senders Results, Referrals"). ADR §"Decision" placed the cardinality axis on `SegmentGrammar` alone, which would fire the rule universally under any locale — an over-fire risk (the working notes req #4). S3 adds a parallel `Profile.cardinalityExtensions: [String: [SegmentCardinalityRule]]` axis mirroring how `Profile.grammarExtensions` extends `SegmentGrammar.fields`. Base-grammar rules apply universally; profile-extension rules apply only under the relevant locale. HL7au:000008 ships on the AU profile.
>
> 2. **`SegmentCardinalityRule` gains two additional fields**:
>    - `countedSegmentID: String` (required) — the segment ID whose occurrence is being counted. Used by the fired `.segmentCardinalityBelowMinimum` case's `segmentID` associated value; avoids parsing the predicate to reconstruct the target.
>    - `applicableWhen: String?` (optional) — a v0.7 DSL predicate evaluated against the message. When set, the whole rule is gated: if `applicableWhen` is false the rule is skipped entirely for this message. Mirrors ADR-009's `ComponentValueSet.condition`. HL7au:000008 uses `applicableWhen: "messageCode in (ORU, REF)"` to scope to Results / Referrals messages only.
>
> Both refinements are additive; the axis surface on `SegmentGrammar` and the `.segmentCardinalityBelowMinimum` case shape are unchanged from what was specified in the Decision section.

> **Clarification 2026-07-03 (during S4 implementation)** — the OBR specimen-presence cluster shipped in S4 is trimmed from the ADR-010 literal wording. The Decision text (this section) named "OBR-7 second trigger + OBR-9 / OBR-10 / OBR-11 / OBR-14" as the specimen-presence targets. PDFKit extraction of the v2.4 CH04 spec text (pp. 46-48) confirmed that only **OBR-7** (§4.5.3.7) and **OBR-14** (§4.5.3.14) carry crisp "must be filled in when X" conditional-required triggers. OBR-9 (§4.5.3.9 — "results-only field except when the placer has drawn the specimen"), OBR-10 (§4.5.3.10 — "will identify..."), and OBR-11 (§4.5.3.11 — "identifies the action...") are descriptive statements without MUST language. Per the working notes req #4 ("no predicate ships if it's known-incorrect"), OBR-9/10/11 conditions are **not shipped** — the ADR text was speculative before spec-text confirmation. Re-audit if a future spec revision or corrigendum adds MUST language to those fields. Also: the v2.4 §4.5.3.14 "OR when the observation required a specimen and the message is a report" clause reduces in practice to `OBR-15 populated` (no wire-detectable "observation required specimen" predicate without external LOINC lookup), so OBR-14 ships with `SPM present OR OBR-15 populated` (v2.5.1) / `OBR-15 populated` (v2.4) — the "report message" leg is subsumed by the specimen-indicator OR.

## Public API impact

**None.** All three extensions are internal:

- `<segment-atom>` and the extended `<fieldref>` production live inside the `Validator.checkConditional` predicate parser (`Validator.swift:689+`).
- `SegmentCardinalityRule` and `GroupScope` are new internal types alongside `SegmentGrammar`; the codegen JSON gains an optional `segmentCardinalityRules` array on the group schema. No public re-export.
- `ValidationIssue.Kind` gains a new case `.segmentCardinalityBelowMinimum(segmentID: String, minCount: Int, actual: Int, groupScope: String)`. `ValidationIssue.Kind` is public, so this is technically an API-surface addition — but it's a **new case**, additive on an enum without `@frozen`. Consistent with the v0.4-S4 / v0.5-S5 / v0.7 / v0.8 pattern (new cases added at each cycle); classed as a minor bump per the CHANGELOG convention.

`HL7Locale`, `Message`, `Parser.init`, `Validator.init`, and every existing case of `ValidationIssue.Kind` are unchanged. The v1.0 stability clock continues from v0.5.0 without restart.

## Implementation notes

1. **New helpers on `Message`** (mirroring the ADR-008 pattern):
   - `func segmentExists(_ id: String, inGroupOf index: Int) -> Bool` — resolves group boundary the same way ADR-008 `associatedSegment` does, then scans for `id`.
   - `func segments(in groupOf: Int) -> [Segment]` — enumerates segments in the current group; used by `SegmentCardinalityRule` evaluation.
2. **Predicate parser extension** at `Validator.swift:689+`. Two new productions (`<segment-atom>`, extended `<fieldref>`). Unparseable input still returns `false` (fail-safe preserved).
3. **Field-ref resolver extension.** `Field.componentSubcomponentValue(component: Int, subcomponent: Int?)` already exists (added in ADR-009 for value-set target reading). The DSL evaluator calls the same helper on the LHS side of subcomponent-granular atoms; no new resolver.
4. **`SegmentGrammar` gains `segmentCardinalityRules: [SegmentCardinalityRule]`.** Codegen emits from the schema JSON's `segmentCardinalityRules` array (new optional key). `Validator.validate(_:)` runs a new group-scan pass after the existing per-segment pass to evaluate cardinality rules; fires `.segmentCardinalityBelowMinimum` per rule that trips.
5. **AU profile overlay for HL7au:000008.1** lives in `Resources/profiles/au-adrm-2021/OBX.json` as a new `FieldOverride` with `condition: "OBX-3.3 = AUSPDI"`. No JSON schema migration; the existing ADR-009 loader accepts the extended `<fieldref>` syntax verbatim (the loader emits the string; the runtime parser handles it).
6. **No codegen pipeline change beyond the schema-JSON key.** Emitted Swift for grammars gains one more literal-array field; emitted profile loader is unchanged.

## Rejected alternatives

- **A bespoke JSON axis per cluster** (`crossSegmentXORExceptions`, `specimenPresenceRules`, `groupCardinalityOverlays`). Rejected: forks the DSL into per-rule-class dispatch surfaces. Every new cluster would add a new axis; the schema-→-codegen-→-validator pipeline complexity multiplies. Extending the one grammar keeps ADR-004's principle intact.
- **Peer-absent as an operator on the existing `<fieldref>`** (e.g. `OBR-29 empty-or-absent` as a single atom). Rejected: conflates two distinct facts (peer segment doesn't exist; peer field is empty) into one op. Rule authors need to be able to reason about them separately — e.g. specimen-presence rules care about SPM segment existence, not any specific SPM field being empty.
- **Group-scope cardinality as a DSL atom** (e.g. `count(OBX where OBX-3.3 = AUSPDI in group) >= 1`). Rejected: adds a quantifier and a count operator to a grammar that was deliberately kept flat (atoms combined with AND/OR only). A separate grammar axis on `SegmentGrammar` is a smaller change with a narrower blast radius.
- **Subcomponent access via a new atom prefix** (e.g. `subcomponent(OBX-3, 3) = AUSPDI`). Rejected: the existing `<segmentID>-<int>` grammar is already dotted-numeric-adjacent; extending to `<segmentID>-<int>.<int>` matches how HL7v2 spec text writes the reference (OBX-3.3) and matches the ADR-009 convention on the value-set target side.
- **Defer the three clusters to v0.12+ / permanently.** Rejected per the working notes req #3 — three clusters pointing at one architectural gap is exactly the case the requirement was written for. Consolidating unlocks all three in one substage sequence.

## Risk

- **Fail-safe semantics preserved.** An unparseable / unresolvable predicate still evaluates `false`. `OBR absent` on a message where the group boundary can't be determined returns `false` (i.e. treats the peer as present → the softening doesn't kick in → matches the current conservative behaviour). `OBX-3.3 = AUSPDI` on an OBX where OBX-3 is empty returns `false`. Test coverage must pin each new path.
- **Fixture corpus audit — the newly-firing side.** §4.5.1.8 XOR softening will *stop* firing ORC-8 / OBR-29 in the case where the peer carries the parent — some existing fixtures asserting the previous over-fire behaviour will need updating. HL7au:000008 parent will *start* firing on any AU-locale fixture that lacks an AUSPDI display OBX. Same-shape work as the v0.5-S5-D-2 and v0.8-S4 fixture re-audits.
- **DSL grammar surface growth.** Three new productions is a real growth in the parser surface. Mitigation: keep each extension narrowly scoped to a documented cluster; reject additions (arbitrary path expressions, regex, quantifier chaining) under a separate ADR. Explicitly *no* nested `count(...)`, `any(...)`, or lambda-shaped predicates in this ADR.
- **`SegmentCardinalityRule` is a new axis.** Adding a new grammar axis is a larger structural change than the pure-parser extensions (Extensions 1 and 3). It could be split into its own ADR if project owner prefers — the peer-absent / subcomponent-granular extensions alone unlock two of the three clusters (XOR softening and HL7au:000008.1); the parent HL7au:000008 rule is the sole consumer of the cardinality axis in the initial cycle. Option to split noted here rather than in the Decision so that Accept can pick the shape.

## Migration

Single ADR, staged implementation. Substages:

- **S1 — Extension 1 (segment-presence atoms)**: extend parser + add `Message.segmentExists` helper. Ship §4.5.1.8 XOR softening (ORC-8 / OBR-29 in v2.4 + v2.5.1 schemas). Fixture audit. Regression pins. Green.
- **S2 — Extension 3 (subcomponent-granular field-refs)**: extend parser's `<fieldref>` production. Ship HL7au:000008.1 overlay (OBX-3 AUSPDI value-set). Regression pins. Green.
- **S3 — Extension 2 (group-scope cardinality rules)**: add `SegmentCardinalityRule` + `GroupScope` internal types; extend codegen for the new schema key; add `.segmentCardinalityBelowMinimum` case to `ValidationIssue.Kind`; group-scan pass in Validator. Ship HL7au:000008 parent rule. Fixture audit. Green.
- **S4 — Specimen-presence cluster**: ship OBR-7 second trigger + OBR-9/10/11/14 conditions on v2.5.1 (S1 unblocks the atom; content is spec-audit work). Per-version mirror to v2.4 where SPM-absent fallback (`OBR-15 populated`) applies. Green.
- **S5 — release** as v0.11.0. STATUS + NEXT_STEPS + CHANGELOG + audit doc updates.

S1 and S2 are independent and could ship in either order. S3 depends on the schema-key + codegen path but not on S1 / S2. S4 depends on S1.

If project owner opts to split the cardinality axis into ADR-011: S1 + S2 + S4 ship as v0.11 (unlocks two clusters); S3 becomes ADR-011 in v0.12.

## References

- ADR-004 — Codegen over macros (the schema-is-source-of-truth principle this extension preserves).
- ADR-007 — Locale architecture (this ADR is API-orthogonal to locale; the AU rule (000008) uses the mechanism but the mechanism serves the base spec (XOR + specimen) equally).
- ADR-008 — Cross-segment / message-context DSL (this ADR reuses the v0.7 parser + `Message.associatedSegment` / `previousSegment` helpers; extends the same grammar).
- ADR-009 — ComponentValueSet extensions (this ADR extends the DSL grammar consumed by `ComponentValueSet.condition`; no dispatch change).
- the working notes project requirements #3 (extend the model when needed) and #4 (no predicate ships if known-incorrect).
- `Sources/HL7v2Kit/Validation/Validator.swift:689+` — v0.7 predicate parser (extension point).
- `Sources/HL7v2Kit/Validation/Validator.swift:345–` — `checkProfileFieldOverrides` (unchanged; consumes the extended DSL via `ComponentValueSet.condition`).
- `Sources/HL7v2Kit/Message.swift:150–187` — `associatedSegment` / `previousSegment` (sibling to the new `segmentExists`).
- `Sources/HL7v2Kit/Locale/Profile.swift:220–259` — `ComponentValueSet` (unchanged; the ADR-009 `condition` field is the entry point for Extension 3).
- `docs/design/v2_3-v2_4-spec-audit.md` — §4.5.1.8 known limitation (this ADR closes).
- `docs/design/v2_5_1-spec-audit.md` §93–121 — the OBR specimen-presence cluster (this ADR closes).
- AU ADRM-2021 — HL7au:000008 (parent + .1) verbatim; page reference to be added once PDFKit extraction confirms.

---

**Addendum (2026-08-27, remediation R2 + R4):** two implementation-surface updates, semantics
unchanged. (1) **Extension 2's schema-side encoding axis was removed** (R2/F9): 0 of 584
schema JSONs ever set `segmentCardinalityRules`, so the generator's decode/render plumbing was
plumbing without payload — the **runtime** `SegmentCardinalityRule`/`GroupScope` types and the
AU profile's `cardinalityExtensions` rules (HL7au:000008) are untouched, and the axis can be
reinstated from git if a universal base-spec rule is ever authored. (2) **Extension 3's
field-ref suffix parsing now routes through the shared `Path` parser** (R4/F14) with
`segmentIndex == nil && repetition == nil` guards — the DSL grammar is unchanged and the
rejection of `[N]`/`~N` forms is pinned by the CrossSegmentDSLTests R4-C1 characterization
rows; the previous duplicate suffix parser is deleted.

## Amendment (P4, 2026-09): `noRepeat(...)`

`noRepeat(<fieldref>) <op>` is the universal negation of the M6-B-1 `anyRepeat(...)` atom: true iff the field has at least one populated repetition slot and no slot satisfies `<op>`. It exists because a prohibition keyed to "no repetition carries value X" (v2.5.1 to v2.8.2 SPM-13: "would only be valued if the specimen role attribute has the value 'G'") cannot be written with `anyRepeat(...) != X`, which is true for `P~G`. An absent or all-empty field evaluates `false` (no definite value to negate), and a malformed ref evaluates `false`, preserving the v0.2-V1 fail-safe invariant. `noRepeat(...)` alone therefore does not cover the wholly-absent-field case; a rule needing full universal negation — "prohibited unless some repetition carries value X, including when the field is entirely absent" — must compose it as `<field> empty OR noRepeat(<field>) = <value>` (P4-4; SPM-13's prohibition uses this composition). Pinned by `Tests/HL7v2KitTests/ConditionDSLExtensionTests.swift`.

## Amendment (P4, 2026-09): `nextSegmentID(...)`

`nextSegmentID(<ID>|<ID>...)` is a lookahead referent: the segment ID of the first segment after the current one whose ID is not in the `|`-separated skip list, or the empty value at the end of the message. Segments whose ID starts with `Z` are always skipped as well, whether listed or not. Z-segments are site extensions outside the standard structure (ADR-003) and may appear anywhere in a conformant message, so a Z-segment between chained TQ1s, or between a TQ1 and its TQ2, must not stop the lookahead short and silently suppress the rule. It hosts v2.5.1 to v2.8.2 TQ1-12 ("If the TQ1 segment is repeated in the message, this field must be populated with the appropriate Conjunction code indicating the sequencing of the following TQ1 segment") as `nextSegmentID(TQ2) = TQ1`. A segment-count atom was rejected: it would demand a conjunction on the last TQ1 of a chain, which has no following TQ1, and ORC-group scoping would count TQ1s of different OBRs in an ORC-less ORU. The lookahead fires on a strict subset of the literal reading, so it never fires where the literal reading is satisfied; the last-TQ1 case is recorded as partial in the conditional-completeness audit. Pinned by `Tests/HL7v2KitTests/ConditionDSLExtensionTests.swift`.

## Amendment (P4-21, 2026-10-01): more than one prohibition per field

A field may now carry further prohibitions beside `prohibitedWhen`. The schema key is an optional array on a field, `"additionalProhibitions": [{"when": "<condition>", "severity": "error" | "warning" | "info", "citation": "<version chapter section: quote>"}]`; the existing `prohibitedWhen` / `prohibitedSeverity` keys stay as the first rule, unchanged. Each `when` uses this ADR's condition grammar unchanged, with the same fail-safe semantics (an unresolvable predicate never fires). The public surface is additive (ADR-014): `FieldGrammar.additionalProhibitions: [FieldProhibition]`, empty by default, set only through a new `FieldGrammar.init` overload that ends `additionalProhibitions:`; the released initialisers keep their signatures and are pinned in `SignatureCompatibilityTests`. `FieldProhibition` is a `Sendable`, `Hashable` pair of `condition` and `severity`. The Validator evaluates `prohibitedWhen` and then each additional rule, and every rule that holds on a populated field raises its own `.conditionalFieldProhibited` at its own severity, so two triggered rules give two issues. Codegen emits the overload only for fields that set the key, and fails on an empty list, a `when` that is not `<referent> <predicate>` (plain spaces only, none leading or trailing), an unknown severity or a missing citation; `scripts/audit-schemas.py` checks the same shape. First use: v2.5.1 and v2.6 RXR-6, `RXR-2.3 = HL70163 OR RXR-2.6 = HL70163` at warning (either CWE coding triplet) ("If RXR-2 employs HL7 Table 0163 – Body Site, then RXR-6 should not be populated", CH04 §4.14.2.6) beside the `RXR-2 empty` error.

## Amendment (P4-25, 2026-10-01): every condition string is validated by test

The evaluator fails safe on an atom it cannot read, so a misspelt condition (`RXR-2.3 == HL70163`, `PID-3 populatd`) would pass codegen and the audit and then never fire, a silent breach of requirement 4. The parse half of this grammar now lives in `ConditionLanguage` (`Sources/HL7v2Kit/Validation/ConditionLanguage.swift`): the OR/AND split, the atom shapes, the referents and the predicates are classified there, and the evaluator reads conditions only through it. The internal `Validator.conditionParseErrors(_:)` reports every atom that classification rejects, so the check and the evaluator cannot drift apart. `ConditionParseValidityTests` walks every `SegmentGrammarTable` in all six versions (field `condition`, `prohibitedWhen`, each `additionalProhibitions[].condition`, and the segment cardinality predicates), every datatype component `condition` and `conformanceCondition` (through `ComponentCondition.parses(_:)`, the same parse `holds` runs), and every condition in the AU profile, and fails on any that does not parse. An empty condition is not checked. Two stricter readings came with the move, both on malformed input only: a `noRepeat(...)` atom with an unreadable predicate, which used to hold for any populated field, now fails safe like every other unreadable atom; and an `in (...)` / `not in (...)` list must name at least one non-empty value. No shipped condition was affected.

## Amendment (P4-26, 2026-10-01): a prohibition may exempt the HL7 null

An `additionalProhibitions` entry may add `"permitsNull": true` (`FieldProhibition.permitsNull`, set through the additive overload `init(condition:severity:permitsNull:)`). Such a rule skips a field whose every non-empty repetition is a lone HL7 null `""`; a real value in any repetition still fires it. It exists for text that asks for a field to be "valued with null" while the condition holds: OBX-2 and OBX-5 under OBX-11 = O ("An OBX used for a dynamic specification must contain ... OBX-11 valued with O, and OBX-2 and OBX-5 valued with null", v2.4 CH07 §7.4.2.11, and the same sentence in v2.3.1, v2.5.1, v2.6 and v2.8.2). The exemption is per rule, not global: every other prohibition, and `prohibitedWhen`, still treats `""` as a value, because the text behind them does not say whether a null counts as valuing the field. The null test is the one the AU profile prohibitions already use (`Validator.carriesNonNullValue`), so base and profile rules agree on what a lone `""` is.
