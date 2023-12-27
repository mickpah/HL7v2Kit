# ADR-005: Dictionaries strategy — separate target intended; superseded for v0.1.0 by codegen-emitted grammar table

| | |
|---|---|
| Status | Accepted (revised 2026-06-13 for v0.1.0; original direction held open for v0.2+) |
| Date | 2026-05-27 |
| Supersedes | -- |
| Superseded by | -- |
| Related | ADR-004 (codegen over macros), ADR-002 (error strategy) |

## Context

The validator (per ADR-002) needs a per-segment, per-field grammar source: which fields are required (optionality `R`), which are deprecated (`B` / `X`), which allow multiple repetitions, and which datatype each holds. This information also drives the typed-segment codegen — the same per-field metadata that decides whether `PID.patientName` returns `String?` or `Field?` is exactly what the validator needs to enforce "PID-3 is required".

Spec § 8 originally proposed a dedicated `HL7v2KitDictionaries` SwiftPM library target shipping per-version JSON resources at runtime. Two stated reasons:

1. **Resource isolation.** Swift Package Manager bundles resources per-target. Keeping JSON in its own target avoids polluting the main module's bundle.
2. **Optional consumption.** Consumers wanting only the parser/AST can depend on `HL7v2Kit` directly; consumers needing validation pull in `HL7v2KitDictionaries`.

By Task 4c-3 / Task 5 time (June 2026), we had a working alternative: the JSON schemas already live at `Resources/schemas/v2.5.1/*.json` at the repo root, consumed at dev-time by the codegen executable. They contain every field's optionality and repeatability already (necessary for the codegen template's String?/Field? decision). The codegen could emit a Swift literal grammar table just as easily as it emits typed-segment structs.

## Decision

### Original (2026-05-27)

`HL7v2KitDictionaries` is a separate library target. Per-version JSON files live at `Sources/HL7v2KitDictionaries/Resources/v2_*.json` and are loaded at runtime by `Validator` and `Parser`.

### Revision for v0.1.0 (2026-06-13, in scope of Task 5)

For v0.1.0, the validator reads from a **codegen-emitted Swift literal** instead:

```swift
extension SegmentGrammarTable {
    public static let v2_5_1: [String: SegmentGrammar] = [
        "AL1": SegmentGrammar(segmentID: "AL1", version: "2.5.1", fields: [
            FieldGrammar(index: 1, name: "Set ID - AL1", dataType: "SI",
                         optionality: .required, repeatability: .single),
            ...
        ]),
        ...
    ]
}
```

The file `Sources/HL7v2Kit/Segment/Generated/SegmentGrammar+v2_5_1.swift` is emitted by the same `HL7v2KitCodegen` executable that emits typed-segment structs. Sorted by segment ID + field index for deterministic output. Reproducible across consecutive runs (verified by `shasum`).

`HL7v2KitDictionaries` as a SwiftPM target **stays in place** as a placeholder for v0.1.0 — `placeholder.json` is its only resource, `Dictionaries.swift` is a scaffold stub. No public consumer pulls it for grammar data in v0.1.0.

The original direction (separate dictionaries target with runtime JSON) is held open for v0.2.

## Consequences

### Of the v0.1.0 revision

**Positive**

- **Single source of truth.** `Resources/schemas/v2.5.1/PID.json` drives both the typed-segment generation and the grammar table — no schema fork, no sync risk.
- **No runtime JSON parsing on first validation.** The grammar table is a static `let`. Validation latency is dominated by the AST scan, not by deserialisation.
- **Dead-code elimination.** Consumers that don't import `Validator` see the grammar table tree-shaken out (Swift compiler + linker support this for `internal` and unreferenced `public` statics in a library target). Consumers that do use it pay only the bytes for the grammars they reach.
- **No separate target wiring.** The library product `HL7v2Kit` exposes `Validator` without forcing consumers to also depend on `HL7v2KitDictionaries`.
- **Same codegen pipeline.** Adding the grammar emit was a render function + one `main()` step. No new build infrastructure.

**Negative**

- 9 segments × ~25 fields each is small. At full v2.5.1 coverage (~140 segments) it would be ~3500 entries — still small in absolute terms (each `FieldGrammar` is ~100 bytes; ~350 KB total — comparable to a sprite sheet). At full multi-version coverage (4 versions × 140 segments) it's ~1.4 MB. Still acceptable for a Swift library, but the case for runtime-loadable dictionaries gets stronger.
- Doesn't match spec § 8's literal "Dictionaries is a separate target" intent. The target still exists but only as a placeholder. If a future consumer says "I want runtime grammar selection without recompiling" we have to either ship a v0.2 with the runtime loader or tell them to pin a specific HL7v2Kit version per use case.

**Explicitly not promised**

- We do not promise that `SegmentGrammarTable` is the only future grammar source. If v0.2 surfaces a real consumer need for runtime dictionaries, we'll revisit: add a `Sources/HL7v2KitDictionaries/Resources/v2_*.json` build step (probably codegen-emitted from the same `Resources/schemas/`), add a runtime loader in `Dictionaries.swift`, and either dual-ship both sources or migrate the validator to the runtime path. Either path keeps `Resources/schemas/` as the source of truth.

### Of the original direction (held in reserve)

If revived in v0.2+:

**Positive**

- Runtime version selection (load v2.5.1 or v2.8 grammars on demand without rebuild).
- Smaller library binary if the validator is the dominant compile-time cost. Probably not relevant given typed segments themselves are similar-sized generated code.
- Clean separation of "library code" vs "grammar data" for licensing / sourcing — if grammars come from HL7 Inc. or HL7 Australia under different terms, the separate target keeps the licensing distinction visible.

**Negative**

- Schema fork: either codegen emits to both places (added complexity in codegen) or one of the two sources becomes derived.
- Runtime JSON parse cost on first validation per version per process. Mitigable by caching but adds first-use latency.
- More SwiftPM wiring in consuming projects.

## Alternatives considered (at the v0.1.0 revision)

- **Path A:** Validator reads `Resources/schemas/*.json` from disk at runtime. Rejected — `Resources/schemas/` is a dev-time location, not bundled into the library binary.
- **Path B:** Original direction — `HL7v2KitDictionaries` runtime JSON. Rejected for v0.1.0 — schema fork, runtime cost, more wiring for the same v0.1.0 user value.
- **Path C** (chosen): codegen-emitted Swift literal grammar table baked into `HL7v2Kit` directly.

## Notes

The codegen-drift CI job (per ADR-004) covers `Sources/HL7v2Kit/Segment/Generated/SegmentGrammar+v2_5_1.swift` along with the per-segment files. A contributor who edits a schema but forgets to regenerate is caught structurally — the validator can't drift out of sync with the typed-segment surface because both come from the same codegen run.

---

**Addendum (2026-08-27, remediation R10):** the placeholder `HL7v2KitDictionaries` target this
ADR kept "in place for v0.1.0" was **retired at the 2.0 boundary** — it was never imported by
any consumer, and Path C (codegen-emitted `SegmentGrammar+vX_Y_Z.swift` tables in the main
target) has been the sole grammar source since v0.13's JSON retirement. The library product,
target, test target, and the main target's unused dependency edge were all removed (R10/F6;
evidence in `remediation-plan.md` → "v2.0.0 removal register").
