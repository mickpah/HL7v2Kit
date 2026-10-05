# ADR-003: Z-segment policy — default to `UnknownSegment`, never guess semantics

| | |
|---|---|
| Status | Accepted |
| Date | 2026-05-27 |
| Supersedes | -- |
| Superseded by | -- |
| Related | ADR-002 (error strategy), ADR-005 (dictionaries module) |

## Context

HL7 v2 reserves segment IDs starting with `Z` for site-specific extensions. Real-world AU clinical traffic uses them routinely: `ZAU` (Australian-specific demographics), `ZPI` (patient-identifier extensions), `ZMH` (mental-health overlays), `ZBR` (billing references), and many facility-specific bespoke segments. These have no standardised grammar — each sender defines its own field layout.

A library that **rejects** Z-segments is unusable for AU integration: real ADT and ORU traffic from AU labs and PMS systems routinely includes them, and rejecting messages on Z-segment presence means rejecting a substantial fraction of production traffic.

A library that **guesses** Z-segment semantics is unsafe: there's no canonical grammar to compare against, so any "structured" parse of (say) `ZAU-3` is the library's invented interpretation, not the sender's intent. If a higher layer (FHIR mapper, downstream system) trusts that interpretation, the mistake propagates silently.

A third option is to make Z-segment handling **a policy decision the consumer makes per parse** — neither universally tolerated nor universally rejected.

## Decision

Three layers of control, each with a safe default and a strict opt-in.

### Layer 1: structural parser default

By default, `Parser.parse(_:)` accepts any segment ID. Segments whose ID is not in the codegen-emitted typed-segment registry come back as `UnknownSegment` — a struct that preserves the structural split (segment ID + `[Field]`) but does not attempt typed accessors.

This is "Z-segment tolerance" — listed as architecture invariant 5 (`Parser` returns `UnknownSegment` for unknown segment IDs, never throws on them).

### Layer 2: strict parsing opt-in

`ParserOptions.allowUnknownSegments` is `true` by default but can be set to `false` (via `.strict` or explicit options). Under strict mode, `parse(_:)` throws `ParseError.unknownSegment(id:, position:)` on the first unrecognised ID. Useful for sender-side outgoing-message validation where the sender controls every segment and any Z-segment is a bug.

### Layer 3: per-validation policy

`ValidationOptions.zSegmentPolicy` is an independent dimension:

- `.ignore` (default) — Z-segments don't produce issues.
- `.warnPresence` — every Z-segment emits a `.info`-severity `.zSegmentPresent` issue. Report stays valid; useful for AU compliance audits ("show me every Z-segment so I can document them").
- `.reject` — every Z-segment emits an `.error`-severity issue. Report becomes invalid. Equivalent to "this grammar must be complete".

### What we explicitly do not do

We do not invent typed accessors for unknown segments. `UnknownSegment.fields` exposes the raw structural split; path access (`msg["ZAU-3"]`) works because it operates on the AST, not on segment-specific knowledge.

We do not ship a registry of "known" Z-segments. `ZAU` is no different from `ZFR_BESPOKE_LAB_123` to the parser. Any project that needs specific Z-segment semantics layers them on top (in `HL7v2KitAUExtensions` or in application code).

## Consequences

**Positive**

- AU traffic parses by default. The most common library complaint ("your parser rejects my sender") doesn't happen.
- Strict-mode users have a clean way to enforce grammar completeness on their own outgoing messages.
- Validator workflows can independently choose audit (warn) vs hard-rejection (error) without changing parse-time behaviour.
- The "never guess" rule means we never propagate a wrong-by-invention interpretation up the stack.

**Negative**

- Consumers who genuinely don't know what segments their senders produce can't get "auto-typed Z-segments" without writing their own typed-segment generator. That's the right tradeoff — safer to make the work visible than to fabricate semantics.
- Three-layer control surface (parser default vs strict mode vs validator policy) is more API than a one-knob design. Documented in the DocC quickstart and in `ParserOptions` / `ValidationOptions` DocC comments.

**Explicitly not promised**

- HL7v2Kit does not promise to *ever* ship typed Z-segment grammars. Project-specific grammars (AU Core, etc.) belong in higher layers per the package layering in spec § 17.

## Notes

The Z-segment policy interacts with ADR-005 (dictionaries) and the codegen-emitted `SegmentGrammarTable`. The grammar table only contains entries for typed segments; the validator falls into the Z-segment branch only for IDs beginning with `Z` (ADR-018 amendment below) — any other ID with no grammar entry (e.g. `OBR` would have no entry on a v0.2.0 release if its schema were removed from `Resources/schemas/`) is reported as `IssueCode.segmentNotInVersionGrammar`, not as a Z-segment. The fail-mode is safe: the validator emits an info / error per `zSegmentPolicy` for true Z-segments, and a warning for a non-Z segment the version does not define; it does not invent grammar.

**ADR-018 amendment:** only IDs beginning with `Z` enter the Z-segment branch. Any other ID with no grammar entry for the applied version is reported as `IssueCode.segmentNotInVersionGrammar` (warning) under every policy, so a standard segment is never labelled a Z-segment.
