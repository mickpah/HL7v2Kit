# Changelog

All notable changes to HL7v2Kit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added (infrastructure)

- **Top-level `HL7v2Kit.xcworkspace/`** at the repo root. Open with `open HL7v2Kit.xcworkspace` instead of `Package.swift` directly. Single `<FileRef>` to the package today; scales to multi-repo when `FHIRAUCoreKit` and `AUCoreWorkbench` land by adding more `<FileRef>` entries. The auto-generated `.swiftpm/xcode/package.xcworkspace` stays gitignored.
- **Four v0.2 git worktrees** under `~/Developer/HL7v2Kit-worktrees/` for parallel-branch development, all branched off `main` at `69060e4`:
  - `v0.2-parser-hardening` — P1 BOM → P2 NUL → P3 unsupportedVersion (serial; all touch `Parser.swift`)
  - `v0.2-composites` — C1 typed composite data types → V2 component-level validation
  - `v0.2-fringe-fields` — F1 PID/ORC fringe-field expansion → V1 conditional-field evaluation
  - `v0.2-perf-tests` — X1 performance budget tests
  - Documented merge order: parser-hardening → fringe-fields → composites → perf-tests.
- **`NEXT_STEPS.md` reorganised** around the v0.2 cycle: new "Workspaces and worktrees" section, each task names its worktree + position in the serial chain, full v0.1.0 task history preserved under "Historical: v0.1.0 runway".
- **`the working notes` "Project at a glance"** surfaces the workspace + worktree setup so future sessions discover them without re-derivation.

No source / API / test changes; 159/159 tests still green.

## [0.1.0] — 2026-06-13

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

### Added (R6 — ParserOptions audit)

- **`ParseError.unknownSegment(id: String, position: Int)`** — new error case. Spec § 4.6 had it declared but the implementation lacked the case. Position is 1-based (MSH is position 1).
- **`Parser(options: .strict).parse(...)`** now actually rejects unrecognised segments with `.unknownSegment`. Previously the `.strict` `allowUnknownSegments: false` option was silently equivalent to `.default` because the parser never consulted the flag. Now it checks after `SegmentRegistry.hydrate(_:)` returns and throws if the result is `.unknown`.
- **`ParserOptions.preserveExcessFields`** DocC updated to honestly mark it deferred to v0.2: v0.1.x has no per-segment field-count dictionary to check against, so excess fields are always preserved regardless of the flag. The flag stays on the API so consumers don't break when the dictionary-driven behaviour lands.
- 3 new tests in `ParsingTests.swift`: strict mode rejects ZAU with `.unknownSegment(id: "ZAU", position: 2)`; default options still allow ZAU (Z-segment tolerance regression); strict mode still accepts a registered PID.

### Added (Task 7c — parser error-path coverage)

- New `Tests/HL7v2KitTests/ParseErrorTests.swift` with **23 negative-path tests** covering: every `ParseError` case (including the previously-dead `.unsupportedVersion`, `.malformedField`, `.truncatedMessage` via the `everyCaseDescriptionRenders` reflection test), MSH structural edges (too-short MSH, missing field-separator after MSH-2, non-distinct encoding chars, segment-ID-only segments), byte-level edges (BOM prefix, embedded NUL, custom encoding characters), DoS-adjacent stress (8 KB single field, 1000-way repetition fan-out), mixed line terminators under `.lenient`, multiple MSH segments (batch-shaped input), and behaviour pins for current parser leniency (unknown MSH-12 falls back to v2.5.1, whitespace-only input throws `.missingMSH` not `.emptyInput`).
- Two findings flagged in test comments as v0.2 hardening candidates: (1) BOM prefix is silently stripped by Foundation on macOS (portability gap on Linux/Windows); (2) embedded NUL bytes are NOT preserved through round-trip — current behaviour is lossy. Both pinned by the test suite so they'll be caught if either silently changes.
- Coverage moves: `ParseError.swift` from **84.62% → 100.00% line** (every enum case description exercised); `Parser.swift` from **93.72% → 97.10% line / 84.72% → 91.67% region**. Overall `Sources/HL7v2Kit/` from **93.06% → 94.36% line / 86.60% → 88.60% region**.
- 136 → 159 tests across 12 suites.

### Added (Task 7a — anonymise tool + starter fixture corpus)

- **`HL7v2KitAnonymise` executable target** (`Sources/HL7v2KitAnonymise/Anonymise.swift`) implementing the spec § 10 scrubbing rules: PID-3 identifier replacement (format-preserved for digit-only IDs, otherwise `SYN-NNNN` prefix), XPN name lists, DOB shift by `±(salt mod 60 / 2)` days, AU synthetic addresses (8 real suburbs × 5 fake street names), AU-shaped phone numbers (`61-2-XXXX-XXXX`), MSH-3/4/5/6 facility names (8-entry pool), XCN provider lists (PV1 attending/referring/consulting/admitting + OBR collector/ordering/principal interpreter), OBX-5 narrative redaction (`TX` / `FT` / `ST` / `ED` value types → `[REDACTED]`), NTE-3 redaction. **Deterministic** — per-file salt derived from MSH-10 via djb2 hash; same input → byte-identical output. **One-shot** — re-anonymising an already-scrubbed file shifts the DOB again (documented in `Tests/Fixtures/FIXTURES.md`).
- **`scripts/anonymise-fixture.sh`** wrapper invoking the executable via `xcrun swift run`, matching the existing `regenerate-typed-segments.sh` pattern.
- **8 starter fixtures** under `Tests/Fixtures/`: `adt_a01_minimal.hl7`, `adt_a01_with_nk1.hl7`, `orm_o01_lab_order.hl7`, `oru_r01_chemistry.hl7`, `oru_r01_with_z_segment.hl7`, `edge_empty_fields.hl7`, `malformed_missing_msh.hl7`, `malformed_invalid_encoding_chars.hl7`. All hand-written synthetic with `\r` line terminators (real v2 wire format). Documented in `Tests/Fixtures/FIXTURES.md`.
- **`Tests/HL7v2KitTests/FixtureRoundTripTests.swift`** — auto-discovers `*.hl7` files in the bundled Fixtures resource and applies four invariants:
  - Every non-malformed fixture round-trips byte-perfectly (spec § 9.3).
  - Every non-malformed fixture validates without errors.
  - Every `malformed_` fixture throws a `ParseError`.
  - Path access and typed accessor cross-check on PID-1 / PID-3 / PID-5 / PID-7 / PID-8 (spec § 9.4).
- Adding fixture #9..#48 is now a pure drop-in operation — no test code change required.

### Added (Task 8c — release polish prep)

- New `Tests/HL7v2KitTests/ReadmeQuickstartTests.swift` — a `@Test` that mirrors the README's Quickstart code block and asserts each documented expected value. Drift in the README example (renamed methods, changed return types, stale `//` comments) breaks the test at PR time before any user encounters a stale example.
- README updated for accuracy: "Typed segments currently shipped" lists all 9 v2.5.1 segments with field-coverage counts (was stale at 4 segments / "PID 12 of 40"); "Adding a typed segment" workflow corrected from 4 steps to 3 (no manual `SegmentRegistry.swift` edit — the registry is itself codegen-emitted post-R5).
- Line-coverage benchmark on `Sources/HL7v2Kit/` (excluding `Generated/`, `HL7v2KitCodegen/`, `HL7v2KitDictionaries/`, and tests):
  - **Region:** 86.60% (433 of 500 covered)
  - **Function:** 92.81% (142 of 153 covered)
  - **Line:** 93.06% (1072 of 1152 covered)
  - Exceeds spec § 15's 80% line-coverage gate. Lowest-covered files: `Validation/SegmentGrammar.swift` 54.55% (value-type initialisers exercised at codegen-table compile time rather than via direct test), `Message.swift` 75.00% (some typed-segment iteration paths), `ParseError.swift` 84.62% (some error cases like `.truncatedMessage`, `.malformedField` not exercised by tests because no malformed-byte fixture triggers them yet — Task 7).

### Added (Task 8b — DocC catalogue)

- New `Sources/HL7v2Kit/HL7v2Kit.docc/` catalogue with the landing page and 8 articles per spec § 11.2:
  - `HL7v2Kit.md` — module landing page with Topics index linking to articles and public type catalogue.
  - `GettingStarted.md` — install → parse → read → serialise → validate in one short page.
  - `RoundTripGuarantee.md` — what byte equality covers and what it doesn't.
  - `TypedSegments.md` — typed-segment access pattern; `String?` vs `Field?` rule; multi-occurrence iteration; cross-check guarantee.
  - `Validation.md` — `Validator.validate` returns a `ValidationReport`; the three presets; filtering by severity / code / segment; current check coverage and v0.2 gaps.
  - `EscapeSequences.md` — the `\F\` / `\S\` / `\T\` / `\R\` / `\E\` / `\X..\` / `\Z..\` grammar; hex coalescing; round-trip canonical-form property.
  - `CharacterEncoding.md` — MSH-18 detection via ISO-8859-1 probe; supported charsets; Latin-1 round-trip example.
  - `AddingASegment.md` — three-step contributor workflow (schema, regen, cross-check test); CI drift safety net; v0.1.0 limits.
  - `Migration.md` — pre-1.0 SemVer policy; anticipated v0.2 changes (typed composite data types, conditional-field evaluation, component-level grammar, possible runtime-loadable dictionaries).

### Added (Task 8a — ADR catalogue)

- `docs/design/ADR-001-ast-model.md` — explicit Field/Repetition/Component/Subcomponent hierarchy + round-trip rationale.
- `docs/design/ADR-002-error-strategy.md` — `ParseError` (fatal, throws) vs `ValidationReport` (non-fatal, returned) split.
- `docs/design/ADR-003-z-segment-policy.md` — three-layer Z-segment control (parser default `UnknownSegment`, strict opt-in, validator policy `.ignore`/`.warnPresence`/`.reject`).
- `docs/design/ADR-004-codegen-over-macros.md` — rationale for explicit codegen executable + committed output over Swift Macros or build-time preprocessing.
- `docs/design/ADR-005-dictionaries-strategy.md` — original "Dictionaries as separate target" intent + the v0.1.0 revision to Path C (codegen-emitted Swift literal grammar table), with the spec § 8 direction held open for v0.2+.

### Added (Task 5 — Validator)

- **`Validator` per spec § 4.8.** Public surface: `Validator(options:)` + `validate(_ message:) -> ValidationReport`. **Non-fatal** (returns a report, never throws — ADR-002 invariant). Built on Path C — the validator reads a codegen-emitted `SegmentGrammarTable.v2_5_1` static table; no runtime JSON parsing, no separate `HL7v2KitDictionaries` runtime resource needed for v0.1.0.
- **`ValidationOptions`** with three presets: `.default` (grammar checks on, Z-segments silently tolerated), `.strict` (Z-segments rejected as errors), `.lenient` (only structural required-field check). Knobs: `zSegmentPolicy` (`.ignore` / `.warnPresence` / `.reject`), `checkRequiredFields`, `checkCardinality`, `warnDeprecatedFields`.
- **`ValidationReport`** (`issues`, `isValid` — false iff any `.error`-severity issue — plus `errors` / `warnings` / `infos` filters) and **`ValidationIssue`** (`severity`, `code`, `location`, `message`).
- **`IssueSeverity`** (`.info` / `.warning` / `.error`), **`IssueLocation`** (segment ID + 1-based segment occurrence + optional 1-based field index; renders as `"PID[1]-3"`), and **`IssueCode`** (`.requiredFieldMissing`, `.conditionalFieldMissing` (reserved), `.fieldNotSupported`, `.cardinalityExceeded`, `.zSegmentPresent`, `.unknownSegment`).
- **Public grammar types**: `SegmentGrammar`, `FieldGrammar`, `FieldOptionality` (R/O/C/X/B from HL7 wire codes), `FieldRepeatability` (.single/.multiple). `SegmentGrammarTable` is the codegen-emitted lookup `[String: SegmentGrammar]` keyed by segment ID.
- **Codegen extension**: `HL7v2KitCodegen` now also emits `Sources/HL7v2Kit/Segment/Generated/SegmentGrammar+v2_5_1.swift` containing the static `SegmentGrammarTable.v2_5_1` table. Per-version files allow future v2.3.1 / v2.4 / v2.8 tables to slot in without touching v2.5.1's output. Sorted by segment ID and field index for deterministic output.
- **Three operational checks**:
  - **Required-field check**: fields with optionality `R` that are unpopulated emit `.requiredFieldMissing` errors.
  - **Cardinality check**: single-cardinality fields (`repeatability=1`) carrying multiple `~`-separated repetitions emit `.cardinalityExceeded` errors.
  - **Deprecated-field warning**: populated `B` (deprecated) or `X` (not supported) fields emit `.fieldNotSupported` warnings (non-blocking).
- **Z-segment policy**: `.ignore` (no issue), `.warnPresence` (`.info` per segment, still valid), `.reject` (`.error` per segment, report invalid).
- 12 new tests in new `Tests/HL7v2KitTests/ValidationTests.swift`: well-formed-is-valid, missing-required-PID-3, checkRequiredFields toggle, all three Z-segment policies, cardinality on PID-7 single-field with two reps, multi-cardinality on PID-3 doesn't trigger, deprecated PID-2 warning, warnDeprecatedFields toggle, non-throw contract, IssueLocation path-description rendering. Suite total to 131.
- **Codegen accessor template uses `field(N)`** *(R4)* instead of the inline `fields.indices.contains(N) ? fields[N] : nil`. `TypedSegment` gains a `field(_ index: Int) -> Field?` default-impl that mirrors `Segment.field(_:)`'s bounds policy — single source of truth for "what does an out-of-range typed accessor return". Generated files visually halve in size.
- **`SegmentRegistry+Generated.swift` is now codegen-emitted** *(R5)*. The hand-written `SegmentRegistry.swift` shrank from a 4-case switch (and growing per Task 4c segment) to a 13-line entry point that calls `hydrateGenerated`. Adding a new segment is now a 2-step workflow: drop the JSON schema, run `regenerate-typed-segments.sh`. The codegen-drift CI job catches missed regenerations. ORC v2.5.1 lands as the canary segment proving end-to-end auto-registration.

### Added (R-β)

- `ORC` typed segment for HL7 v2.5.1 (one field — Order Control). Added as the R5 canary; extended to 19 fields in Task 4c-1.
- `TypedSegment.field(_:)` default-impl extension.

### Added (Task 4c-1)

- `OBX` typed segment for HL7 v2.5.1 (full 17 fields covering Set ID, Value Type, Observation Identifier, Observation Value, Units, References Range, Abnormal Flags, Probability, Nature of Abnormal Test, Observation Result Status, Effective Date of Reference Range, User Defined Access Checks, Date/Time of the Observation, Producer's ID, Responsible Observer, Observation Method).
- `ORC` typed segment extended from 1 to 19 fields (Order Control through Action By — covers the commonly-used Common Order fields including Placer/Filler Order Numbers, Order Status, Date/Time of Transaction, Ordering Provider).
- 14 new cross-check tests in `TypedSegmentTests.swift` (5 for extended ORC + 9 for OBX including round-trip), bringing the suite total to 84.

### Added (Task 4c-2)

- `OBR` typed segment for HL7 v2.5.1 (full 47 fields — the largest segment in the v0.1.0 set). Covers placer/filler order numbers (EI), universal service identifier (CE), specimen/observation timestamps, collector and ordering provider XCN composites, specimen action code, placer/filler text fields, result status, parent ordering, transport metadata, procedure codes, supplemental service information.
- 13 new cross-check tests in `TypedSegmentTests.swift`: 12 OBR-specific (hydration, SI/EI/CE/XCN/TS/ID coverage by field cluster, byte-perfect round-trip) plus 1 full-message integration test parsing an ORU^R01 result message with MSH + PID + OBR + OBX and asserting byte-perfect round-trip. Suite total to 97.

### Added (Task 4c-3)

- `PID` typed segment extended from 12 → 30 fields. New coverage: phone numbers (home/business XTN), primary language (CE), marital status (CE), religion (CE), patient account number (CX), SSN + driver's license (deprecated), mother's identifier (CX), ethnic group (CE), birth place (ST), multiple birth indicator (ID), birth order (NM), citizenship (CE), veterans military status (CE), nationality (CE, deprecated), patient death date/indicator (TS + ID).
- `NK1` typed segment for HL7 v2.5.1 (13 commonly-used fields). Covers Set ID, name (XPN), relationship (CE), address (XAD), home + business phone (XTN), contact role (CE), start/end dates (DT), job title (ST), job code/class (JCC), employee number (CX), organization name (XON).
- `PV1` typed segment for HL7 v2.5.1 (20 commonly-used fields). Covers Set ID, patient class (IS), assigned + temporary + prior patient locations (PL), admission type (IS), preadmit number (CX), attending/referring/consulting/admitting doctors (XCN), hospital service (IS), preadmit/readmit/admit indicators (IS), ambulatory status (IS), VIP indicator (IS), patient type (IS), visit number (CX), financial class (FC).
- 19 new cross-check tests in `TypedSegmentTests.swift`: 6 extended-PID (XTN home phone, CE language/marital/religion triplet, CX account, ST birth place, TS+ID death fields, byte-perfect round-trip), 5 NK1 (hydration, scalars, name+relationship composites, phone composites, round-trip), 7 PV1 (hydration, class+admit type scalars, PL location composite, XCN attending doctor, IS admin scalars, CX visit number, round-trip), and 1 ADT^A01 integration (MSH + PID + PV1 + NK1 in one message with byte-perfect round-trip). Suite total to 116.

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

### Added (Task 7b — fixture corpus scale-out)

- **Fixture corpus expanded 8 → 48** (spec § 9.2 target met for v0.1.0). All synthetic from scratch.
  - **ADT (12 total):** 3 × A01 (minimal, with NK1, allergies, insurance, emergency) + 3 × A04 (clinic, NK1, paediatric with PD1) + 3 × A08 (address update, demographics update, allergies-add).
  - **ORM (5 total):** lab order baseline + radiology X-ray, microbiology, haematology, cancel (ORC-1=CA), order with DG1 diagnosis.
  - **ORU pathology (6 total):** chemistry, haematology FBC, lipid panel, TFT, microbiology MCS, multi-OBR (EUC + LFT batteries under one PID).
  - **ORU radiology (4 total):** chest X-ray, CT abdomen/pelvis, pelvic ultrasound, MRI brain — each with TX narrative + ST impression.
  - **ACK (2 total):** application-accept (AA) and application-error (AE + ERR).
  - **Z-segment heavy (5 total):** original `oru_r01_with_z_segment` + ZAU/ZIN overlay in ADT, ZBL billing in ORM, ZLB/ZRE in ORU, ZTX heartbeat (MSH + Z only).
  - **Malformed (6 total):** missing MSH + non-distinct encoding chars + MSH too short + MSH no field-sep after MSH-2 + unsupported MSH-18 charset + empty file. Each triggers a distinct `ParseError` case.
  - **Edge (8 total):** original `edge_empty_fields` + Unicode diacritics, repeating PID-3 identifiers, very-long address, escape sequences in PID-5 and NTE, many trailing NTEs, sparsely-populated PID, OBX with `~`-repeating values.
- All valid fixtures: round-trip byte-perfectly, produce non-error `ValidationReport`, and pass the PID typed-accessor vs path-string cross-check. All malformed fixtures throw `ParseError`. `FixtureRoundTripTests` auto-discovers — no test code change required.

### Deferred to v0.2 (or later)

- **Full PID 30 → 39 and ORC 19 → 31.** Fringe coverage: PID-31..39 are species / breed / strain / tribal-citizenship; ORC-20..31 are confidentiality / charge metadata. v0.1.0 covers the commonly-populated fields per the 2026-06-13 decisions-log entry.
- **Typed composite data types** (`XPN` / `CX` / `XAD` as Swift structs with named accessors). v0.1.0 returns `Field?` for composites; callers reach into `.components[i].stringValue`. Spec § 4.5 last paragraph.
- **Conditional-field evaluation.** v0.1.0 treats `optionality=C` as equivalent to `O` for the required-field check. Per `ValidationIssue.IssueCode.conditionalFieldMissing` (reserved).
- **Component-level grammar in `Validator`.** v0.1.0 only checks field-level rules; e.g. XPN's family-name component being non-empty when XPN-1 is populated is not checked.
- **Performance budget tests** (spec § 9.5). Nightly latency assertions not in the v0.1.0 acceptance gate.
- **Three parser-hardening candidates** from Task 7c (all pinned by `ParseErrorTests.swift`, none blocks v0.1.0):
  - BOM prefix portability — silently stripped by Foundation on macOS but Linux Swift may differ.
  - Embedded NUL bytes — currently lossy through round-trip; consider `.truncatedMessage(atByte:)` at parse time.
  - `ParseError.unsupportedVersion` is reachable code but never thrown — unknown MSH-12 silently falls back to v2.5.1. Wire on `.strict` mode.
- **`HL7v2KitDictionaries` runtime JSON.** Path C (ADR-005 revised) supersedes the original spec § 8 plan for v0.1.0; placeholder.json stays. Revisit in v0.2 if dynamic version selection becomes a real consumer need.

[Unreleased]: https://github.com/<your-org>/HL7v2Kit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/<your-org>/HL7v2Kit/releases/tag/v0.1.0
