# ADR-009 — ComponentValueSet extensions: subcomponent granularity + conditional gating

**Status:** **Accepted 2026-06-25.** Project-owner approval received same day. Implementation scope = HL7au:000040.1/.2/.3/.4 (040.5 is receiver runtime semantic, out of scope for a validator). Substage plan: S1 model extension, S2 validator dispatch, S3 ship four rules + JSON mirror, S4 fixture audit, S5 release.

**Context:** v0.7 shipped the cross-segment / message-context DSL extension (ADR-008). When evaluating HL7au:000040 (MSH-12 Version ID conformance) for v0.8, two gaps in the existing v0.5-S5-C profile-overlay machinery surfaced:

1. **Subcomponent granularity.** `ComponentValueSet(component: Int, allowedValues: [String])` currently reads "the first subcomponent of the named component" (per `Validator.checkProfileFieldOverrides`). HL7au:000040.1/.2 requires MSH-12.2 (Internationalization Code, CE) to equal `"AUS&Australia&ISO3166_1"` — that's three subcomponents of one component (`AUS`, `Australia`, `ISO3166_1`). The current model can pin MSH-12.2.1 = "AUS" but cannot reach MSH-12.2.2 / .2.3.

2. **Conditional gating.** HL7au:000040.3 requires VID-3 = `"HL7AU-OO-201701&&L"` **only when the message type is Orders or Results** (ORM, ORU). HL7au:000040.4 requires a different VID-3 value **only on Referrals / RRI** (REF, RRI). The current model has no way to make a value-set fire on a subset of message types. Today the override applies to every message that uses the segment.

Without these extensions, HL7au:000040 ships as a partial overlay (040.1/.2 first-subcomponent only), which violates project requirement #3: "When a spec semantic exceeds what the current code can model, the right move is to **extend the model**." Per requirement #4: "A condition predicate... that's known to misfire in any spec-compliant scenario is a defect" — so we cannot ship 040.3/.4 unconditionally either.

## Decision

**Extend `ComponentValueSet` with two new optional fields:**

```swift
public struct ComponentValueSet: Sendable, Equatable, Hashable {
    public let component: Int
    public let subcomponent: Int?          // NEW: default nil → reads first
                                            // subcomponent (current behaviour).
                                            // When set, reads that subcomponent.
    public let allowedValues: [String]
    public let condition: String?           // NEW: optional v0.7-DSL predicate.
                                            // When set, the value-set check only
                                            // applies if the predicate is true.
                                            // Default nil → always applies (current).
    public let specCitation: String?
}
```

Validator's `checkProfileFieldOverrides` gains two behaviours:

- **Subcomponent reading.** Today: `repetition.components[component-1].subcomponents.first?.value`. Tomorrow: when `subcomponent != nil`, read `repetition.components[component-1].subcomponents[subcomponent-1].value`; else fall back to today's "first" behaviour.
- **Conditional gating.** Before applying the value-set check, evaluate `condition` (if set) via the existing v0.7 `conditionTriggers` entry point. If the predicate is false, skip the check (atom doesn't fire). Reuses the v0.7 DSL parser unchanged.

JSON overlay (Resources/profiles/au-adrm-2021/MSH.json) gains corresponding optional `subcomponent` and `condition` fields. Hand-curated JSON↔Swift sync per ADR-007 stays the same.

## Why

Three forces converge:

1. **The v0.7 DSL is already at message scope.** `conditionTriggers(_:in:segmentIndex:message:currentSegmentID:)` is exposed at internal access for tests; reusing it as the gating predicate evaluator means the new behaviour is **strictly additive code**. No new parser, no new predicate grammar.

2. **Subcomponent granularity is unavoidable for cited rules.** MSH-12.2 = `"AUS&Australia&ISO3166_1"` is not an edge case — it's the central conformance rule for AU sender identification. The HL7 v2 CE data type has subcomponents by design; any other AU narrowing on a CE field will likely need the same granularity. Better to add the affordance once than to keep finding it later.

3. **Both extensions are non-breaking.** Both new fields default to `nil`. Every existing override file compiles unchanged; every existing predicate fires identically. The v1.0 stability clock (currently re-anchored at v0.5.0) is unaffected — the public API surface (`HL7Locale`, `ValidationIssue`, etc.) doesn't change.

## Public API impact

**None.** `Profile`, `FieldOverride`, `ComponentValueSet`, etc. are internal types per ADR-007 ("Internal `Profile` type still exists, but it's an implementation detail"). The new fields land below the public locale surface.

The CHANGELOG `[Unreleased]` entry will note "new internal axes on ComponentValueSet" so future contributors discover the affordance.

## Rejected alternatives

- **Per-override condition (one condition for the whole FieldOverride)** rather than per-ComponentValueSet. Rejected: HL7au:000040.3 and 040.4 both target the SAME field (MSH-12) but apply to different message types — a single override-level condition can't encode "use VID-3 set A on Orders OR VID-3 set B on Referrals". The condition has to live at the value-set level.
- **A separate `messageTypeFilter` enum** instead of reusing the v0.7 DSL. Rejected: introduces a parallel mechanism. The v0.7 DSL already expresses `messageCode in (ORM, ORU)` cleanly; mirror-imaging it as a new enum would duplicate the dispatch surface and break the principle that schema/profile predicates funnel through one evaluator.
- **Subcomponent-as-path (`path: "12.2.1"`)** instead of separate `component` + `subcomponent` fields. Rejected: adding one optional Int is a smaller diff than refactoring every existing override to a new path syntax, and the existing field structure mirrors the HL7 spec's "field/component/subcomponent" terminology directly.
- **Wait for "every spec narrowing we'll ever need" before extending** the model. Rejected per project requirement #3: "If extension is out of scope for the current cycle, the gap must be documented as a known limitation that **blocks** spec-completeness" — the gap is documented for v0.5–v0.7 and is now being closed.

## Risk

- **Schema-injection surface growth.** Adding `condition: String?` to ComponentValueSet means a malformed profile JSON could carry an unparseable condition. Mitigation: the v0.7 evaluator already fails safe on unparseable predicates (atom returns `false`); the worst case is "value-set check silently doesn't fire" — same fail-safe semantic as v0.7 conditions on schemas.
- **Implicit precedence between condition + value-set.** Decision: check `condition` FIRST. If false, skip the value-set. If true, apply the value-set. This matches the natural reading "WHEN message is ORU, MSH-12.3 must be HL7AU-OO-201701". Tests will pin this ordering.
- **Multiple ComponentValueSet entries on the same field with different conditions.** This is the central use case for HL7au:000040.3 / .4 (one entry per message-type class). The Validator already iterates the override's `componentValueSets` list; no change needed.

## Migration

Single ADR; no per-cycle migration plan needed. Substages:

- **S1 model:** extend `ComponentValueSet`, mirror in JSON loader.
- **S2 validator:** update `checkProfileFieldOverrides` for subcomponent reading + condition evaluation.
- **S3 ship HL7au:000040:** add four FieldOverride entries (040.1/.2 universal + 040.3 Orders/Results + 040.4 Referrals/RRI) with cited verbatim text.
- **S4 fixture audit:** same shape as v0.5-S5-D-2 / v0.7-S3.
- **S5 release.**

## References

- ADR-007 — Locale architecture (this ADR is internal to that mechanism).
- ADR-008 — Cross-segment DSL (this ADR reuses the v0.7 evaluator as the gating predicate engine).
- Project requirements #3 (extend the model when needed) and #4 (no predicate ships if known-incorrect).
- `Sources/HL7v2Kit/Locale/Profile.swift` — current `ComponentValueSet` shape.
- `Sources/HL7v2Kit/Validation/Validator.swift:checkProfileFieldOverrides` — current value-set dispatch.
- AU ADRM-2021 pp. 445–446 (extracted via PDFKit) — HL7au:000040.1–.5 verbatim.
