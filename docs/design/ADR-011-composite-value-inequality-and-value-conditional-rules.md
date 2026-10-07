# ADR-011 — Composite-override extensions: component-value inequality + value-conditional rules

**Status:** **Accepted 2026-07-04.** Project-owner approval received same day. Implementation scope = the two machine-checkable HL7au:00044.4 CE-datatype conformance points that the current composite-override model cannot express (44.4.4 LOINC-first, 44.4.8 distinct-alt-coding), plus the two cleanly-expressible text-must-be-valued points (44.5.3 CNE, 44.6.3 CWE) that ship with the *existing* model in the same cycle. 44.4.3 (CE carve-out) and 44.4.7 (concept-match) documented as permanent limitations. Substage plan under "Migration"; opens the v0.13 cycle on branch `v0.13-adr-011`. CWE/CNE inequality scope confirmed CE-only (44.5.7 / 44.6.7 marked "Removed" in ADRM r2).

**Context:** v0.13 opened on the "remaining AU narrowings" track — the HL7au:00044.* datatype conformance points not yet shipped (STATUS "What is NOT done"). Reading the AU ADRM-2021 Appendix 5 text (pp. 450–455) for the CE / CNE / CWE series surfaces four sub-points in the chosen scope, of which the current composite-override model (`CompositeOverride` with `requiredComponents` + `pairRules`, per ADR-007 / v0.5-S5-B) can express only some:

| Rule | Verbatim (AU ADRM-2021 Appendix 5) | Expressible today? |
|---|---|---|
| HL7au:00044.5.3 (CNE) | "`<text (ST)>` component must be valued and this must be what is intended for display to the user." | **Yes** — `requiredComponents: [2]` on the CNE override. Ships without this ADR. |
| HL7au:00044.6.3 (CWE) | Same wording, CWE. | **Yes** — `requiredComponents: [2]` on the CWE override. Ships without this ADR. |
| HL7au:00044.4.3 (CE) | "`<text (ST)>` component must be valued as what is intended for display to the user. **(In some locations user display is not intended and the text may be blank.)**" | **No — unshippable.** The carve-out ("may be blank in some locations") is not wire-detectable; an unconditional CE-2-required rule would over-fire in the blank-allowed locations, violating project requirement #4. |
| HL7au:00044.4.4 (CE) | "When multiple codes are used LOINC codes (LN) must be placed first using the identifier rather than the alternate identifier." | **No — needs this ADR.** A *value-conditional* rule: fire when the alternate-coding-system component (CE-6) = "LN". No current primitive expresses "component X has value V → violation". |
| HL7au:00044.4.7 (CE) | "Both `<identifier>` and `<alternative identifier>` must reflect the same concept…" | **No — unshippable.** Requires a terminology service to compare concepts; not machine-checkable from the wire alone. |
| HL7au:00044.4.8 (CE) | "Alternate coding system must be a different from the primary coding system." | **No — needs this ADR.** A *component-value inequality*: CE-3 (primary coding system) ≠ CE-6 (alt coding system) when both are populated. No current primitive expresses value inequality between two components. |

Per project requirement #3 ("extend the model when the DSL can't express something") the two machine-checkable-but-inexpressible rules (44.4.4, 44.4.8) justify a model extension. Per req #4 the two genuinely-unshippable rules (44.4.3 carve-out, 44.4.7 semantic) must be documented as known limitations, not forced into a misfiring predicate.

## Decision

**Extend `CompositeOverride` with two new rule axes**, both additive, both internal (per ADR-007 the composite-override types are implementation details behind `HL7Locale`), both fail-safe:

1. **`componentInequalities: [ComponentInequality]`** — a rule asserting two named components must carry *different* values when both are populated:

   ```swift
   struct ComponentInequality: Sendable, Equatable, Hashable {
       let componentA: Int          // e.g. CE-3 (name of coding system)
       let componentB: Int          // e.g. CE-6 (name of alternate coding system)
       let specCitation: String?
   }
   ```

   Semantics: when a field of the override's dataType is populated AND both `componentA` and `componentB` are populated AND their (first-subcomponent) values are equal, fire `.profileConstraintViolation`. When either component is empty, the rule does not fire (nothing to compare) — fail-safe.

2. **`valueConditionals: [ComponentValueConditional]`** — a rule asserting a named component must NOT carry a specific denied value (optionally gated by message type via the v0.7 DSL, reusing the ADR-009 gating entry point):

   ```swift
   struct ComponentValueConditional: Sendable, Equatable, Hashable {
       let component: Int           // e.g. CE-6 (name of alternate coding system)
       let deniedValues: [String]   // e.g. ["LN"]
       let condition: String?       // optional v0.7-DSL message-context gate
       let specCitation: String?
   }
   ```

   Semantics: when a field of the override's dataType is populated AND (`condition` is nil OR evaluates true) AND the named component's value is in `deniedValues`, fire `.profileConstraintViolation`. Empty component → no fire.

No public-API change: `CompositeOverride` and its rule types are internal (ADR-007). No new `ValidationIssue.Kind` case — both reuse `.profileConstraintViolation(localeRule:)` with the rule's `specCitation`, exactly as `requiredComponents` / `pairRules` do today. The v1.0 stability clock (v0.5.0 anchor) is unaffected.

## Why

1. **The composite-override machinery already dispatches per-dataType.** `Validator.checkProfileCompositeOverrides` (Validator.swift:452) already iterates a field's components for `requiredComponents` and `pairRules`; adding two more inner loops over `componentInequalities` / `valueConditionals` is strictly additive — same shape as the v0.5-S5-B pair-rule loop, no new dispatch surface.

2. **Both rules are genuinely inexpressible today, not awkwardly-expressible.** `pairRules` only relate *population state* (`populated` / `empty`) of two components — they cannot compare *values*, and cannot deny a specific literal. `ComponentValueSet` is an allow-list on a single component (a message-*field* override, not a datatype-*composite* override), so it can't express "these two composite components must differ" or "this composite component must not be LN across every CE/CWE field in the message". The gap is real.

3. **Reusing the v0.7 DSL for `valueConditionals.condition` keeps one gating evaluator.** HL7au:00044.4.4 is Orders/Results-only; `condition: "messageCode in (ORM, ORU)"` gates it via the same `conditionTriggers` entry point ADR-009 already reuses for `ComponentValueSet.condition`. No parallel message-type mechanism.

4. **Honesty over completeness (req #3).** Shipping 44.4.4 + 44.4.8 while *documenting* 44.4.3 (carve-out) and 44.4.7 (semantic) as permanent limitations is the faithful rendering: the audit doc records exactly which conformance points are enforced, which are inexpressible, and why. An integrator reading the schemas can trust the distinction.

## Rules expressed under the extension

**HL7au:00044.4.8 — distinct alternate coding system (CE):**
```swift
ComponentInequality(componentA: 3, componentB: 6,
    specCitation: "HL7au:00044.4.8 — CE alternate coding system (CE-6) must differ from primary coding system (CE-3)")
```
Fires when CE-3 and CE-6 are both populated and equal. (CWE / CNE carry the same 44.6.x / 44.5.x "same concept" text but numbered .7 there and marked "Removed" in r2 for the inequality leg — scope this ADR to the CE 44.4.8 that is live; re-audit CWE/CNE if a later revision reinstates.)

**HL7au:00044.4.4 — LOINC-first (CE, Orders/Results):**
```swift
ComponentValueConditional(component: 6, deniedValues: ["LN"],
    condition: "messageCode in (ORM, ORU)",
    specCitation: "HL7au:00044.4.4 — LOINC (LN) must be the primary coding system (CE-3), not the alternate (CE-6), on Orders/Results")
```
Fires when CE-6 (alternate coding system) = "LN" on an Orders/Results message — LOINC placed in the alternate slot instead of primary. **Interpretation note** (for the audit doc): the spec says "when multiple codes are used, LOINC must be placed first". The machine-checkable reduction is "LOINC must not appear as the alternate coding system". This is a faithful *necessary* condition, not the full rule (it does not verify that a LOINC code that *is* primary is well-formed) — documented as a partial/necessary-condition check, consistent with how OBR-7's report-message trigger was shipped partial in v0.10.

**HL7au:00044.5.3 / 00044.6.3 — text must be valued (CNE / CWE):** ship with the *existing* model in the same cycle —
```swift
// CNE and CWE CompositeOverride gain:
requiredComponents: [ComponentRequirement(component: 2,
    specCitation: "HL7au:00044.5.3 / .6.3 — <text> component must be valued")]
```

## Public API impact

**None.** `CompositeOverride`, `ComponentInequality`, `ComponentValueConditional`, `PairConditional`, etc. are internal per ADR-007. No `ValidationIssue.Kind` case added (unlike ADR-010's cardinality case) — both new rules fire the existing `.profileConstraintViolation(localeRule:)`. CHANGELOG will note the new internal axes so future contributors find them.

## Rejected alternatives

- **Overload `PairConditional` with value-comparison requirements** (add `.mustDifferFrom` / `.mustNotEqualValue` to `PairRequirement`). Rejected: `PairConditional`'s `condition` / `requirement` are both *population-state* enums; bolting value semantics onto them muddies a type whose whole shape is "population-state → population-state". A distinct rule type per semantic keeps each type single-purpose (mirrors how ADR-009 chose separate fields over a path syntax).
- **A generic expression DSL on composites** (arbitrary predicates over components). Rejected: over-general for two rules; would duplicate the v0.7 field-DSL at composite scope. Two narrow rule types match the two cited conformance points exactly, per the ADR-008/010 "narrow productions" discipline.
- **Ship 44.4.4 unconditionally** (no message-type gate). Rejected: the spec scopes it to Orders/Results; firing on Referrals would over-fire per req #4.
- **Force 44.4.3 (CE text) with a heuristic** for the "some locations" carve-out. Rejected: no wire signal identifies the blank-allowed locations; any heuristic would misfire. Documented as a permanent limitation instead.

## Risk

- **Fail-safe semantics preserved.** Both new rules no-op when the relevant components are empty (`ComponentInequality` needs both populated to compare; `ComponentValueConditional` needs the component populated to match a denied value). An unparseable `valueConditionals.condition` fails safe to "gate false → rule skipped" via the existing v0.7 evaluator. Consistent with v0.2-V1.
- **Interpretation partiality (44.4.4).** The LOINC-first check is a necessary-condition reduction, not the full placement rule. Flagged in the audit doc so integrators don't read it as complete. Same honesty pattern as OBR-7 partial (v0.10).
- **Fixture audit.** Any AU-locale fixture that currently carries a CE with equal CE-3/CE-6, or LOINC in CE-6 on an ORU, will newly fire. The corpus must be audited (same shape as the v0.5-S5 / v0.8-S4 / v0.11 fixture audits).
- **CWE/CNE inequality scope.** This ADR ships the CE 44.4.8 inequality only; the CWE/CNE equivalents were marked "Removed" in ADRM r2. Documented; re-audit if reinstated.

## Migration

Single ADR, staged implementation after Accept:

- **S1 — model:** add `ComponentInequality` + `ComponentValueConditional` types; extend `CompositeOverride` with the two arrays (default empty). Mirror in the JSON overlay loader if the profile is JSON-backed (currently hand-curated Swift per ADR-007).
- **S2 — validator:** extend `checkProfileCompositeOverrides` with the two inner loops; reuse `conditionTriggers` for the value-conditional gate.
- **S3 — ship rules:** 44.5.3 + 44.6.3 (`requiredComponents: [2]` on CNE/CWE, existing model); 44.4.8 (`ComponentInequality` on CE); 44.4.4 (`ComponentValueConditional` on CE). Regression pins for each.
- **S4 — fixture audit + audit-doc update:** record 44.4.3 (carve-out) and 44.4.7 (semantic) as permanent limitations; mark the four shipped points RESOLVED.
- **S5 — release** as v0.13.0.

## References

- ADR-007 — Locale architecture (composite-override types are internal to this mechanism).
- ADR-009 — ComponentValueSet extensions (this ADR reuses the same v0.7 `conditionTriggers` gate for `valueConditionals.condition`).
- ADR-010 — DSL extensions (precedent for the "extend the model, document what stays unshippable" pattern).
- Project requirements #3 (extend the model) and #4 (no predicate ships if known-incorrect).
- `Sources/HL7v2Kit/Locale/Profile.swift:90–160` — current `CompositeOverride` / `PairConditional` / `ComponentRequirement` shapes.
- `Sources/HL7v2Kit/Validation/Validator.swift:452` — `checkProfileCompositeOverrides` dispatch this ADR extends.
- AU ADRM-2021 Appendix 5, pp. 450–455 (extracted via PDFKit) — HL7au:00044.3/.4/.5/.6/.7 verbatim.
