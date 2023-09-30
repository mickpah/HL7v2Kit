# Changelog

All notable changes to HL7v2Kit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Code-generated typed segment structs** for HL7 v2.5.1: `MSH`, `PID` (first 12 of 40 fields), `NTE`, `AL1`.
  - `HL7v2KitCodegen` executable target reads per-segment JSON schemas from `Resources/schemas/<version>/` and emits Swift `TypedSegment` structs under `Sources/HL7v2Kit/Segment/Generated/`.
  - `SegmentRegistry.hydrate(_:)` switches segment IDs to typed factories; `Parser` calls it after structural parsing.
  - `scripts/regenerate-typed-segments.sh` regenerates the output tree.
  - Codegen output is reproducible (byte-identical across runs); CI codegen-drift job in `.github/workflows/ci.yml` catches schema edits that forget to regenerate.
- **MSH-18 character-set detection.** `Parser.parse(_ data:)` probes MSH-18 via an ISO-8859-1 1:1 decode, looks up the declared charset, and re-decodes the bytes. `Parser.parse(_ raw:)` does the same probe on the already-decoded string. Supports `UNICODE UTF-8` (default), `ASCII`, `8859/1` and the common aliases for each.
- **HL7 escape-sequence codec.** `\F\` `\S\` `\T\` `\R\` `\E\` `\X..\` decode/encode at the subcomponent leaf. `\Z..\` and unknown sequences pass through verbatim. `Subcomponent.value` stores decoded text; the serializer canonicalises on output. Hex runs coalesce (`\X0D0A\` not `\X0D\\X0A\`).
- `CharacterEncoding` public enum (Foundation edge) mapping MSH-18 wire strings to `String.Encoding`.
- `Message.characterEncoding: CharacterEncoding` property — populated by the parser, used by the serializer to emit bytes in the originating charset.
- `MessageBuilder` accepts an optional `characterEncoding` parameter (defaults to `.utf8`).
- 41 new tests: 17 `EscapeSequenceTests`, 11 `CharacterEncodingTests`, 13 `TypedSegmentTests` (path vs typed-accessor cross-check on MSH/PID/NTE/AL1, hydration check, byte-perfect round-trip through typed segments, Z-segment regression).

### Changed

- **Removed the explicit `swift-testing` SwiftPM dependency.** Swift Testing ships with the Swift 6 toolchain; the explicit dep was triggering a `@Suite` deprecation warning. The package now has zero external dependencies.
- `Parser` version-detection (MSH-12) reads via the unified `Segment.fields` accessor rather than pattern-matching `case .unknown(let msh)` — required once MSH starts hydrating as `.typed`. Encoding-agnostic and survives future typed-segment additions.
- `Parser` previously always emitted `.unknown(UnknownSegment)`; it now consults `SegmentRegistry.hydrate(_:)` to wrap recognised segment IDs as `.typed`. Z-segment tolerance is preserved (unknown IDs still fall through to `.unknown`).
- **MSH-18 probe-and-lookup logic factored into `CharacterEncoding.detect(in:)`** *(R3)*. `Parser.parse(_ data:)` and `Parser.parse(_ raw:)` now share the same one-line invocation; the private `probeMSH18` helper has moved off `Parser` since it's pure structural lookup.
- **`MessageBuilder.appendSegment(id:fields:)` contract clarified** *(R1)*: `fields` is treated as 1-indexed; the builder always prepends the index-0 placeholder. The dead-code condition (`fs.count == fields.count` was a tautology) has been removed. Behaviour is unchanged; the DocC now states the contract explicitly.
- **`Parser.parse(_ raw:)` DocC updated** *(R2)* to call out that MSH-18 is still consulted on the String-input path, with the same strict-on-unrecognised policy as `parse(_ data:)`.
- **Codegen accessor template uses `field(N)`** *(R4)* instead of the inline `fields.indices.contains(N) ? fields[N] : nil`. `TypedSegment` gains a `field(_ index: Int) -> Field?` default-impl that mirrors `Segment.field(_:)`'s bounds policy — single source of truth for "what does an out-of-range typed accessor return". Generated files visually halve in size.
- **`SegmentRegistry+Generated.swift` is now codegen-emitted** *(R5)*. The hand-written `SegmentRegistry.swift` shrank from a 4-case switch (and growing per Task 4c segment) to a 13-line entry point that calls `hydrateGenerated`. Adding a new segment is now a 2-step workflow: drop the JSON schema, run `regenerate-typed-segments.sh`. The codegen-drift CI job catches missed regenerations. ORC v2.5.1 lands as the canary segment proving end-to-end auto-registration.

### Added (R-β)

- `ORC` typed segment for HL7 v2.5.1 (one field — Order Control). Added as the R5 canary; extended to 19 fields in Task 4c-1.
- `TypedSegment.field(_:)` default-impl extension.

### Added (Task 4c-1)

- `OBX` typed segment for HL7 v2.5.1 (full 17 fields covering Set ID, Value Type, Observation Identifier, Observation Value, Units, References Range, Abnormal Flags, Probability, Nature of Abnormal Test, Observation Result Status, Effective Date of Reference Range, User Defined Access Checks, Date/Time of the Observation, Producer's ID, Responsible Observer, Observation Method).
- `ORC` typed segment extended from 1 to 19 fields (Order Control through Action By — covers the commonly-used Common Order fields including Placer/Filler Order Numbers, Order Status, Date/Time of Transaction, Ordering Provider).
- 14 new cross-check tests in `TypedSegmentTests.swift` (5 for extended ORC + 9 for OBX including round-trip), bringing the suite total to 84.

### Added (initial scaffold — pre-Task-2)

- Initial scaffold: `Package.swift`, module structure, base types.
- `Version` enum for HL7 v2.3.1, 2.4, 2.5.1, 2.8.
- `EncodingCharacters` struct (default `|^~\&`).
- `Field` / `Repetition` / `Component` / `Subcomponent` AST nodes.
- `Segment` enum with `.typed` / `.unknown` cases and `UnknownSegment` fallback.
- `Message` top-level type with byte-level `serialize()`.
- `Path` parser supporting `SEG[N]-F[.C[.S]][~R]` syntax.
- `Parser` skeleton with single-message parsing and structural Z-segment tolerance.
- `MessageBuilder` for round-trip construction.
- Round-trip property test scaffolding.

### Not yet implemented (v0.1.0 scope)

- Code-generated typed segments for OBR, OBX, NK1, PV1, ORC; remaining 28 PID fields. (See NEXT_STEPS Task 4c.)
- Full `Validator` (structural + cardinality + Z-segment policy).
- Real segment dictionary JSON (currently only `placeholder.json`).
- DocC catalogue (8 articles per spec § 11.2).
- 48-fixture corpus (currently 0 fixtures).
- `anonymise-fixture.swift` script — required gate before any real-world-derived fixture can land.
- Initial git commit (deferred by founder choice).

[Unreleased]: https://github.com/<your-org>/HL7v2Kit/compare/HEAD
