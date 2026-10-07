# ADR-008 — Cross-segment / message-context DSL extension

**Status:** **Accepted 2026-06-19.** Project-owner approval received same day. Implementation scope = the three documented deferred rules (ORC-2 ↔ OBR-2 XOR, OBR-25 report-message guard, ORC-8 parent-child). Substage plan documented in `NEXT_STEPS.md` under the v0.7 cycle.

**Context:** The v0.4-S4 condition DSL closed PID-35/36 (cross-field within PID) and OBX-2 (cross-field within OBX) cleanly. The spec audits (`docs/design/v2_5_1-spec-audit.md` §93–121, mirrored in `v2_3-v2_4-spec-audit.md`) then documented a residual cluster of conditional rules the same-segment DSL cannot express:

| Rule | Spec § | Nature |
|---|---|---|
| ORC-2 ↔ OBR-2 placer-order XOR | §4.5.1.2 | Cross-segment field reference |
| OBR-7 / OBR-14 / OBR-25 report-message guards | §4.5.3.7 / .14 / .25 | Message-type / sibling-segment context |
| ORC-8 / OBR-29 parent-child | §4.5.3.29 | Discourse-level state (preceding ORC's ORC-1) |

Per project requirement #3, the right move is to **extend the model** so these spec semantics can be expressed faithfully, rather than indefinitely deferring them with a consumer-profile rationale. The same extension is likely needed to express AU narrowings that depend on message-type (e.g. ORU^R01-only constraints) — so the leverage is broader than the three deferred rules.

## Decision

**Extend the v0.4-S4 condition DSL with three new predicate categories**, evaluated against the full `Message` rather than just the current `Segment`. The schema JSON surface stays a single optional `"condition": "<string>"` per field; the predicate parser/evaluator gains new productions. No public API change; no codegen pipeline change; the existing fail-safe semantic (unparseable / unsatisfiable predicate → `false`) is preserved.

The three new predicate categories:

1. **Cross-segment field references** — `OBR-2 populated` evaluated inside an ORC-segment grammar entry binds `OBR` to the *associated* OBR (definition below). Today these refs return `false`; tomorrow they resolve.
2. **Message-context predicates** — `messageStructure in (ORU_R01, ORU_R30)` and `messageCode = ORU` evaluate against MSH-9. New noun in the grammar; no field-ref shape.
3. **Position / discourse predicates** — `previousSegment(ORC).ORC-1 = PA` walks backward in `message.segments` to find the most recent ORC and inspects its ORC-1. Bounded scope (only `previousSegment`, only one step back) keeps the DSL evaluator analysable.

## Why

Three forces converge on extending the existing DSL rather than introducing a parallel mechanism:

1. **The DSL evaluator already runs at message scope.** `Validator.validate(_ message: Message)` (Validator.swift:25) iterates `message.segments` in document order; the per-segment `checkConditional()` (Validator.swift:641) is the only place where the context narrows to a single segment. Widening that one boundary is a smaller change than introducing a second validation pass.
2. **Schema JSON stays declarative.** A `"condition"` string remains the only knob in the schema. Extending the predicate grammar keeps the schema → codegen → validator pipeline unchanged in shape; only the parser gains productions. This matches ADR-004's "codegen over macros" principle: the JSON is the source of truth, the generated Swift is dumb.
3. **Project requirement #4, "no predicate ships if it's known-incorrect" (#4).** Today's evaluator silently drops cross-segment refs (Validator.swift:741). That's *correctly* fail-safe at the DSL layer, but it means three documented spec conditionalities silently never fire. Extending the DSL converts those silent gaps into either firing rules or a documented-and-localised fail-safe per rule.

## DSL grammar extension (proposed)

Today's grammar (v0.4-S4, Validator.swift:689–774):

```
<predicate>  := <or-expr>
<or-expr>    := <and-expr> (" OR " <and-expr>)*
<and-expr>   := <atom> (" AND " <atom>)*
<atom>       := <fieldref> " " <op>
<fieldref>   := <segmentID> "-" <int>
<op>         := "populated" | "empty"
              | "= <value>" | "!= <value>"
              | "in (<values>)" | "not in (<values>)"
```

Extended grammar (proposed, v0.6-cross-segment):

```
<predicate>  := <or-expr>
<or-expr>    := <and-expr> (" OR " <and-expr>)*
<and-expr>   := <atom> (" AND " <atom>)*
<atom>       := <field-atom> | <message-atom> | <position-atom>

<field-atom>    := <fieldref> " " <op>
<fieldref>      := <segmentID> "-" <int>                    // NEW: any segmentID, not just currentSegmentID

<message-atom>  := <message-noun> " " <op>                  // NEW
<message-noun>  := "messageStructure" | "messageCode" | "triggerEvent"

<position-atom> := "previousSegment(" <segmentID> ")." <fieldref> " " <op>   // NEW
                 | "associatedSegment(" <segmentID> ")." <fieldref> " " <op>  // NEW

<op>            := (unchanged from v0.4-S4)
```

### Resolution rules (specific, narrow on purpose)

- **`<segmentID>-<n>` from `<field-atom>`** (cross-segment ref): "associated" semantics. For most pairings (ORC/OBR), the associated peer is the segment of the named ID that **shares the closest preceding-or-same OBR/ORC group boundary** — concretely, the *nearest* segment of the named ID within the current ORC/OBR group. If the current segment has no associated peer, atom evaluates `false`. (Resolver implementation: `Message.associatedSegment(_:from:)` returns `Segment?`; nil → `false`.)
- **`messageStructure` / `messageCode` / `triggerEvent`**: read from MSH-9 components. `messageStructure` = MSH-9.3 (e.g. `ORU_R01`); `messageCode` = MSH-9.1 (`ORU`); `triggerEvent` = MSH-9.2 (`R01`). Underscores in the schema string represent the HL7 caret-separator (`ORU^R01` = `ORU_R01` in the predicate to keep the string DSL parser-friendly).
- **`previousSegment(<ID>)`**: walks backward from the current segment's index in `message.segments`, returns the *nearest preceding* segment of the named ID. Bounded to one match; for "any preceding ORC at all" use `previousSegment(ORC)`. If none found, atom evaluates `false`.
- **`associatedSegment(<ID>)`**: same as the bare `<segmentID>-<n>` form, but explicit. Reserved for cases where the bare-ID form would be ambiguous (e.g. nested OBR groups).

### Three rules expressed in the new DSL

**ORC-2 / OBR-2 XOR (§4.5.1.2):**
- ORC schema, ORC-2 condition: `OBR-2 empty`
- OBR schema, OBR-2 condition: `ORC-2 empty`

Both fields become conditional with the XOR partner's emptiness as the trigger. Either-or-both-populated satisfies the spec; neither-populated fires the conditional on both.

**OBR-25 report-message guard (§4.5.3.25):**
- OBR schema, OBR-25 condition: `messageCode = ORU`

(`ORU` is the report-message-code; the spec's "contained in a report message" reduces to MSH-9.1 = ORU. Verified against v2.5.1 ch07 trigger event tables.)

**ORC-8 parent-child (§4.5.3.29):**
- ORC schema, ORC-8 condition: `previousSegment(ORC).ORC-1 = PA`

(Parent ORC carries ORC-1 = "PA"; the next ORC with ORC-1 = "CH" is the child whose ORC-8 must reference the parent.)

## Public API impact

**None.** Locale enum unchanged. `Parser.init` / `Validator.init` signatures unchanged. `Message` / `ValidationReport` surfaces unchanged. The v1.0 stability clock continues from v0.5.0 without restart. The only externally observable change is *more spec-faithful validation* — messages that were previously silently accepted in violation of these conditionals now surface `.conditionalFieldMissing` errors. Per the CHANGELOG convention used at v0.4.0 / v0.5.0 ("more rules fire under the same API"), this is a minor-version bump, not a breaking change.

## Implementation notes

1. **`Validator.checkConditional()` signature widens.** Today: `(segment: Segment, currentSegmentID: String)`. Tomorrow: `(segment: Segment, segmentIndex: Int, currentSegmentID: String, message: Message)`. Plumbing-only: the caller already has all four values at the call site.
2. **New helpers on `Message`:**
   - `func associatedSegment(_ id: String, fromIndex: Int) -> Segment?`
   - `func previousSegment(_ id: String, beforeIndex: Int) -> Segment?`
   - `var messageStructure: String?` / `var messageCode: String?` / `var triggerEvent: String?` (read from MSH-9 components).
3. **Predicate parser extended.** New productions added to the existing recursive-descent parser at `Validator.swift:689–774`. Existing productions unchanged. Unparseable input still returns `false` (fail-safe preserved).
4. **No codegen change.** Condition strings are still emitted as Swift string literals in `SegmentGrammar+vX.swift`; the runtime parser handles the new productions.
5. **No schema migration.** Existing schemas keep working with only the existing predicate productions; new schemas can use the new productions on a per-field basis.

## Rejected alternatives

- **Typed AST predicates** (replace string DSL with a Swift enum tree). Rejected: orthogonal to this ADR; existing v0.4-S4 string DSL already works and the migration cost is large. If we want typed predicates later, that's its own ADR.
- **Per-segment "associated" overrides in JSON** (schema declares its associated OBR/ORC explicitly). Rejected: hand-curated metadata that duplicates what the spec's segment-grouping semantics already say. Increases JSON-↔-Swift sync surface for no expressive gain.
- **Cross-segment rules as a separate `crossSegmentRules` JSON axis** (parallel to `condition`). Rejected: forks the DSL into two grammars (one for same-segment, one for cross-segment) when extending the existing grammar is strictly smaller. Same-axis extension also keeps the codegen layer unchanged.
- **Walking the segment list multiple times** (one pass per rule). Rejected: the single-pass `for segment in message.segments` (Validator.swift:36) already gives every check the message + the current index. Multiple passes would duplicate work without adding expressiveness.

## Risk

- **Fail-safe semantics**: today, an unparseable / unresolvable predicate evaluates `false`, which means "the conditional doesn't fire on this message". That's correct: a malformed schema must never make a previously-accepted message non-conformant (v0.2-V1 design). The extension preserves this — `messageCode = ORU` with no MSH segment present returns `false`; `previousSegment(ORC).ORC-1 = PA` on a message with no preceding ORC returns `false`. Test coverage must pin each path.
- **More rules fire**: existing fixtures that quietly violated ORC-2/OBR-2 XOR / OBR-25 / ORC-8 will now surface errors. The fixture corpus has to be audited and either fixed (if they were bugs) or annotated (if they intentionally exercise the previously-silent case). Same-shape work as the v0.5-S5-D-2 fixture re-audit when MSH-17/19 profileUsage first fired.
- **DSL grammar surface grows**: more productions = more cases to maintain. Mitigation: keep the extension narrowly scoped to the three categories above. Reject creeping additions (e.g. arbitrary path-expressions, regex match) under a separate ADR.

## Migration

This ADR proposes a single internal grammar bump; no per-cycle migration plan needed. Concretely:

1. Implement `Message.associatedSegment` / `previousSegment` / `messageStructure` accessors (internal scope; no public API).
2. Extend `Validator.checkConditional` signature + parser productions. Run existing 390 tests — must stay green (no schema change).
3. Add the three rules to the v2.5.1 schemas (ORC-2, OBR-2, OBR-25, ORC-8). Regenerate. Audit fixture corpus for newly-firing errors; fix or annotate.
4. Mirror the per-version (v2.4) versions of the same rules — same predicate strings, since the involved fields exist in v2.4 too.
5. Add explicit tests pinning each new predicate category against a synthetic wire that triggers and a synthetic wire that doesn't.

## References

- ADR-004 — Codegen over macros (the schema-is-source-of-truth principle this extension preserves).
- ADR-007 — Locale architecture (this ADR is API-orthogonal to locale; the same DSL serves both base spec and AU narrowings).
- `docs/design/v2_5_1-spec-audit.md` §93–121 — the spec text the three deferred rules cite.
- `Sources/HL7v2Kit/Validation/Validator.swift:641–774` — the v0.4-S4 evaluator this ADR extends.
- `Sources/HL7v2Kit/Validation/SegmentGrammar.swift:40–50` — `FieldGrammar.condition` carries the string verbatim.
- Project requirements #3 (extend the model when DSL can't express something) and #4 (no predicate ships if known-incorrect).
