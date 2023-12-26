# Remediation plan — 2026-08-26 over-engineering audit

**Created:** 2026-08-26, from a four-agent over-engineering audit (over-engineering-audit) of the full
tree — core sources, composites + codegen, test suite, package/config — with every finding
verified against HEAD (`98b8390`) by direct grep/read the same day.

This register records **complexity debt that is deliberately scheduled, not ignored**. It exists
so remediation can be planned test-first: every finding names its pinning tests, its change-class
protocol, and its stage; three characterization tests (C1–C3) close real coverage gaps **before**
the refactors they protect.

> **Scope boundary — do not re-audit.** The audit hunted over-engineering only: dead code,
> hand-rolled stdlib, single-implementation abstractions, delegate-only wrappers, duplication.
> Correctness bugs, security, and performance were **explicitly out of scope** and belong to a
> normal review pass. Findings were verified 2026-08-26; re-run `## Re-verifying this register`
> before executing any stage whose files have since changed. Counterparts: the AU coverage runway
> (`au-coverage-sprint-plan.md`, owns v1.10–v1.15) and the API contract
> (`ADR-014-api-evolution-policy.md`, governs stage R10).

## Measured scope

**36 findings, ~1,400 net removable lines, 0 spec surface touched** — plus 2 build targets and
1 unused public product (the `HL7v2KitDictionaries` stub). Baseline at audit time: 519/519 tests
across 26 suites green, no codegen drift. Clean bill everywhere else (see `## What is NOT a
finding`). This register closes when stage R10 lands and the owner cuts the v2.0.0 tag.

## Constraints that shape the stages

1. **The † findings ship as v2.0.0** (owner decision, 2026-08-26). ADR-014 froze the 1.x surface
   additive-only with no deprecation mechanism; v1.0.0 is provisional and nothing has been pushed
   off this machine, so the SemVer-honest and costless path is to make the breaking stage the 2.0
   boundary itself. R1–R9 are non-breaking and 1.x-safe; R10 is the release-boundary stage, gated
   only on the owner scheduling 2.0 (likely post-v1.15). Tag mechanics stay owner-invoked.
2. **Zero-warnings build** (strict concurrency): every stage must end warning-free; test
   references to removed symbols are updated in the same stage.
3. **Generated files are never hand-edited.** `Sources/HL7v2Kit/Segment/Generated/` changes land
   via the templates in `Sources/HL7v2KitCodegen/Codegen.swift` +
   `bash scripts/regenerate-typed-segments.sh`; the codegen-drift CI job and a
   regenerate-then-`git diff` check are the harness.
4. **One stage = green suite = one commit** (the working notes cadence). Test-list invariant: **only R9
   and R10 may change `swift test list` output; every other stage's test-name diff must be empty.**

## Change-class TDD protocols

Every finding references one protocol. "Green first" is the operative discipline: pins are
verified (or written) against current behaviour before any code moves.

- **P1 — Behaviour-preserving shrink (source).** (a) Name the pinning suites; (b) if a
  consolidated path lacks direct coverage, write a characterization test FIRST and watch it pass
  against current code — it pins, it must **not** be red; (c) refactor; (d) full suite green,
  zero warnings. Known pin limit: `LocaleAUProfileTests` pins **citations and locations only**
  (its `hasViolation` helpers match code/citation/location; `.message` appears only in
  failure-text interpolation) — message strings are unpinned until C2 exists.
- **P2 — Dead-code delete (internal).** Re-verify zero call sites at execution time (the grep is
  part of the stage); delete; compiler + full green suite IS the test. No new tests for deleted
  code. For doc moves/edits: harness = repo-wide grep of the old path/claim returns zero stale
  referrers, plus the fixture-safety CI job.
- **P3 — Codegen template change.** Adjust template → regenerate → `git diff` on `Generated/`
  must show ONLY the intended delta class → `TypedSegmentTests` + codegen-drift CI green.
  Byte-identical subcases (F9, F26, F34, F35): regenerated output must be **byte-identical**; if
  F26's `String(reflecting:)` swap produces any diff, drop/adjust F26 — never force it.
- **P4 — v2.0.0 removal (†).** P2 mechanics (grep-proof, delete, suite green) + same-stage test
  edits + a "2.0" section in `Migration.md` + an ADR-014 addendum note + a CHANGELOG v2.0.0
  section. The owner cuts the tag.
- **P5 — Test-suite consolidation.** Assertion-preserving by construction, checked mechanically
  via sorted test-name diff:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test list | sort`
  captured before and after (plain CLT lacks the Testing module — same env the regenerate script
  uses). Source stages: diff **empty**. Test stages: diff equals the fold map enumerated in the
  stage text, name by name. Caveat: Swift Testing lists a parameterized test once regardless of
  argument count, and the run summary counts per-argument — raw counts are not comparable across
  a parameterization fold; the name-diff plus a green suite is authoritative. Each replaced block
  maps 1:1 to a helper call or argument row. Never consolidate tests in the same stage as a
  source refactor they pin.
- **P6 — Dev-script change.** Harness = the script's own `--verify` mode on identical inputs,
  output byte-identical (`scripts/extract-segment-tables.swift` ships `--verify`).

### Characterization tests to write first (green against current code, per P1(b))

- **C1 (R4, protects F14)** — in `ConditionalFieldTests` (the schema-condition DSL home; the
  referent parse lives at `Validator.swift:1255/1288`): a conditional whose referent carries a
  repetition form (`PID-3~2`) and one with a segment-index form (`PID[2]-3`) each evaluate
  fail-safe **false** (no issue fired). No such rejection test exists today in
  `ConditionalFieldTests` or `CrossSegmentDSLTests`. `Path` parses a strict superset of the DSL
  grammar **including** `[N]` (`Path.swift:87-89`) and `~N`, so the F14 swap needs BOTH guards
  (`segmentIndex == nil && repetition == nil`) — C1 goes red if either is omitted.
- **C2 (R4, protects F11)** — parameterized test in `LocaleAUProfileTests` asserting **exact**
  `.message` + citation for one representative violation per append site: 7 rows, one per block
  at `Validator.swift:486, 513, 538, 568, 619, 660, 717`. Existing suite fixtures already trip
  most sites.
- **C3 (R5, protects F20)** — in `BatchParserTests`: `BatchParser.parse(Data:)` honours
  MSH-18 = `8859/1` (an `0xE9` byte decodes to `é`), optionally plus an
  `unsupportedCharacterEncoding` throw row. Today `BatchParserTests` covers only BOM-strip +
  NUL-reject; all Latin-1/MSH-18 coverage goes through `Parser` (`CharacterEncodingTests`).
- **F24 needs no new test** — the Validator `.orcObxGroup` branch (`Validator.swift:266-275`) is
  production-unreachable today: no shipped rule uses that scope (the AU profile's only group rule
  is `.obrObxGroup`, `Profile+au_adrm_2021.swift:419`; `GroupScope` is internal; Validator has no
  profile-injection point). The refactor deletes the unreachable duplicate and routes through the
  `Message` helper pinned by `MessageCrossSegmentTests`. The `GroupScope.orcObxGroup` case itself
  **stays** (spec surface).

## Stage R1 — Foundation-import purge + codegen template trims

**F1, F26, F34, F35, F36 · ~278 lines · P3 + P2.** The single biggest cut, and the most
mechanically provable: a 3-line template change ripples across all 116 generated files.

**Status: ✅ landed 2026-08-26.** All gates held: step-a regeneration byte-identical (F34/F35
proven output-neutral); step-b diff exactly the two intended line classes (116 import+blank
removals, 109 decl rewrites); test-name diff empty; 519/519 green; warning-free. **F26 was
dropped per the never-force rule** — `String(reflecting:)` escapes apostrophes (`\'`), churning
every possessive grammar-table name; `escapeStringLiteral` now carries a comment recording this.
Side discovery: the fresh full-module recompile surfaced a pre-existing `ExistentialAny` warning
in `StreamingBatchParser.swift:142` (untouched since v0.3-S1) — fixed in its own commit.

1. **Byte-identical template cleanups first.** F34 (inline duplicate of `versionDirName` at
   `Codegen.swift:192` → call the function), F35 (`"GTS"` out of `scalarDataTypes` — 0 of 584
   schemas; `DTM` stays, v2.6/v2.8.2 use it), F26 (`escapeStringLiteral` → `String(reflecting:)`
   — keep only if output is byte-identical). Regenerate; `git diff --stat` on `Generated/` must
   be **empty**.
2. **Visible-delta template edits second.** F1: drop `import Foundation` from the three render
   templates (`Codegen.swift:134,169,236`); F36: emit `: TypedSegment` only (the protocol already
   refines `Sendable, Equatable, Hashable`, `Segment.swift:14`). Regenerate; diff must contain
   **only** import-line removals and conformance-decl lines across the 116 files.
3. **Hand-written import removals.** Drop `import Foundation` from the 18 `Composite/` files and
   `SegmentRegistry.swift` (zero Foundation symbols used — verified; the only grep hits are
   doc-string false positives).

**Done when:** step-1 regeneration is byte-identical; step-2 diff shows only the two intended
line classes; suite green (`TypedSegmentTests` cross-checks included); zero warnings; no drift.

---

## Stage R2 — Dead schema-axis removal

**F9 · ~44 lines · P3.** `segmentCardinalityRules` decode/render plumbing in the generator
(`Codegen.swift:44-51,199,211-227`) is set by **0 of 584** schema JSONs. Delete
`CardinalityRuleSchema`, the schema field, and the non-empty-rules render branch. The **runtime**
`SegmentCardinalityRule` type stays — `Profile` / `Validator` use it (AU cardinality overlays).
ADR-010 Ext 2 documented the axis as deliberate; record in the commit message that an encoding
axis with zero encoded rules is plumbing, not spec surface, and reinstate from git when a first
universal rule is authored.

**Status: ✅ landed 2026-08-26.** 35 lines removed from `Codegen.swift`; regenerated output
byte-identical (`Generated/` diff empty); runtime `SegmentCardinalityRule` + AU
`Profile.cardinalityExtensions` untouched; test-name diff empty; 519/519 green; warning-free.

**Done when:** regenerated output is byte-identical with the axis plumbing gone; drift CI green.

---

## Stage R3 — Composite/segment model cleanup

**F2, F13, F30 · ~201 lines · P1.** Pins: `CompositeTypeTests`, `ComponentGrammarTests`,
`TypedSegmentTests`.

1. **F2:** hoist the byte-identical `componentValue(_:)` + `init(repetition:)` mechanics from the
   16 composite structs into one `CompositeView` protocol (`var field: Field`, `init(field:)`,
   defaulted `requiredComponents` / `requiredComponentSet`) with a protocol extension. Per-spec
   accessors and metadata stay per-type — component names are spec surface.
2. **F13:** make `RequiredComponentSet.description` a required `String` (all 5 call sites already
   pass one); delete `defaultDescription` (`RequiredComponentSet.swift:88-108`).
3. **F30:** delete `AnyTypedSegment.underlyingTypeName` (`Segment.swift:74,79`) — stored, never
   read; `==` semantics unchanged (segmentID→type is a bijection via the generated registry);
   hashes are per-run seeded, no persistence concern.

**Done when:** 16 structs ride `CompositeView`; suite green; zero warnings.

**Status: ✅ landed 2026-08-26 (F2 + F30; F13 re-binned to R10).** All 16 structs ride
`CompositeView` (duplication proven byte-identical by md5 before the hoist: one hash ×16 for
`componentValue`, one for the `init(repetition:)` body); the 5 empty `requiredComponents` decls
(+ stale docs — HD's described the `RequiredComponentSet` refactor as "explicitly avoided" when
it has since shipped) now come from the protocol default; `underlyingTypeName` deleted. Net
−217 lines. Test-name diff empty; 519/519 green; warning-free. **F13 was mis-binned**: tightening
`init(components:semantics:description:)` from `String? = nil` to required `String` is a public
signature change, prohibited in 1.x by ADR-014 — moved to R10 where it rides the v2.0.0 boundary.

---

## Stage R4 — Validator/locale shrinks

**F11, F12, F14, F15, F19, F24 · ~119 lines · P1, characterization-first.** Pins:
`LocaleAUProfileTests`, `LocaleTests`, `ConditionalFieldTests`, `CrossSegmentDSLTests`,
`MessageCrossSegmentTests`, `EscapeSequenceTests`.

1. **Write C1 and C2 first** (see protocol section); both green against current code.
2. **F11:** fold the 7 near-identical `.profileConstraintViolation` appends
   (`Validator.swift:486…717`) into `appendProfileIssue(citation:location:message:into:)` — C2
   proves emitted issues stay exact.
3. **F14:** replace `ParsedIndexSuffix`/`parseIndexSuffix` (`Validator.swift:1275-1307`) with
   `try? Path(referent)` + **both** guards (`segmentIndex == nil && repetition == nil`) — C1
   proves the DSL grammar still excludes `[N]`/`~N`.
4. **F12:** `ProfileLoader` → `Profile.load(for:)` static; delete the file. NOT into
   `HL7Locale.swift` — that file is portable-kernel, Foundation-free (ADR-006).
5. **F15:** the 5 hand-rolled nested-for population scans → `contains(where:)`
   (`Validator.swift:915-922,928-934,1446-1455`; `EscapeSequences.swift:195-207` — the finding
   stays whole in this stage).
6. **F19:** delete dead internal `Profile` members `isEmpty`, `none`, `baseVersion`
   (`Profile.swift:32,62-71`). **F24:** route the Validator ORC walk (`Validator.swift:267-275`)
   through a new internal `Message.orcGroupRange(around:)` shared with `associatedSegment`
   (`Message.swift:156-166`).

**Done when:** C1/C2 green before AND after; `ProfileLoader.swift` deleted; suite green.

---

## Stage R5 — Parser/encoding shrinks

**F20, F21, F23, F33 · ~34 lines · P1, characterization-first.** Pins: `ParsingTests`,
`BatchParserTests`, `BatchFixtureTests`, `CharacterEncodingTests`, `EscapeSequenceTests`,
`RoundTripTests`.

1. **Write C3 first** (BatchParser honours MSH-18 Latin-1); green against current code.
2. **F20:** extract the duplicated wire-decode preamble (`BatchParser.swift:87-101` =
   `Parser.swift:51-74`) into internal `Parser.decodeWirePayload(_:) throws -> (String,
   CharacterEncoding)`.
3. **F21:** `findClosingEscape` + its inline twin (`EscapeSequences.swift:241-252,64-67`) →
   `chars[(i+1)...].firstIndex(of: esc)`. **F23:** hand-rolled `hexDigitValue`
   (`EscapeSequences.swift:128-135`) → stdlib `Character.hexDigitValue` (SE-0221, kernel-safe).
4. **F33:** the two fully-spelled empty-Field literals (`Parser.swift:258`,
   `MessageBuilder.swift:106`) → `.scalar("")` (byte-identical constructor chain).

**Done when:** C3 green before and after; one shared `decodeWirePayload`; suite green.

---

## Stage R6 — Scripts + docs hygiene

**F7, F16, F18 + the working notes doc-rot · ~98 lines · P2 + P6.**

1. **F7:** delete `scripts/add-kernel-headers.sh` (one-shot migration; all 9 kernel files already
   carry the marker); trim the `CONTRIBUTING.md:41` aside.
2. **F18:** `git mv Tests/Fixtures/FIXTURES.md Tests/Fixtures/README.md` — the live 128-line
   registry takes the name and every referrer (`CONTRIBUTING.md:48`, `the working notes:109`,
   `scan-fixtures-for-phi.sh:7`) becomes correct with zero edits; fold the old README's 3-step
   policy in; delete the stale table ("none yet" beside 57 fixtures; names a script that never
   existed).
3. **the working notes rot:** rewrite `:107` to name the real pipeline (`scripts/anonymise-fixture.sh` +
   `HL7v2KitAnonymise`, live since Task 7a); replace the stale "add a `case` to
   `SegmentRegistry.swift`" instruction (registration is fully codegen via
   `SegmentRegistry+Generated.swift`).
4. **F16:** the hand-rolled offset tokenizer `runs(in:)`
   (`scripts/extract-segment-tables.swift:98-125`) → Swift Regex `matches(of:)`; the
   trailing-single-space end-offset delta is unreachable in both consumers (verified trace).

**Done when:** `--verify` output byte-identical; repo-wide grep finds zero stale referrers;
fixture-safety CI green.

---

## Stage R7 — Hydration-helper sweep

**F5, F32 · ~132 lines · P5.** The parse → `#require(firstSegment(…))` arrange pair appears
144× (103 in `TypedSegmentTests`, 41 in `CompositeTypeTests`). Add one generic
`hydrated(_:from:)` helper in a shared support file; each pair becomes one line. F32 rides along:
delete the orphan `// MARK: - AL1` (`TypedSegmentTests.swift:157`).

**Done when:** test-name diff **empty**; suite green at the same test count.

---

## Stage R8 — Shared wire + fixture infrastructure

**F4, F8, F25 · ~212 lines · P5.**

1. **F4:** the 56 verbatim copies of the canonical MSH wire line (81 counting variants, 8+ files)
   → `TestWires.swift` constants + a small builder. MSH stays inline **only** where MSH content
   is under test (`CharacterEncodingTests`, `MultiVersionTests`, AU MSH-12 wires).
2. **F8:** the fixture-discovery chain re-implemented in 6 files → promote the canonical copy
   (`FixtureRoundTripTests.swift:108-140`) to a shared `FixtureCorpus.swift`
   (`validFixtureURLs()/malformedFixtureURLs()/batchFixtureURLs()/fixtureURL(named:)`).
3. **F25:** delete the dead `Collection.subscript(safe:)` beside it
   (`FixtureRoundTripTests.swift:142-148`, zero call sites).

**Done when:** test-name diff **empty**; both shared files exist; suite green.

---

## Stage R9 — In-suite consolidation

**F3, F10, F27 · ~221 lines · P5.** The only stage besides R10 allowed a test-list delta, and
the delta is enumerated:

1. **F3:** the ~24 inline `first { if case .profileConstraintViolation … }` closures in
   `LocaleAUProfileTests` → the file's own `hasViolation` helper extended with a `citing:` param
   (merging the second overload at `:379`); 1-line `#expect` each. (No name changes expected.)
2. **F10:** the per-version detected/roundTrip/grammar triple duplicated for v2.3/v2.3.1/v2.4
   (`MultiVersionTests.swift:28-59,130-149,268-287`) → one `@Test(arguments:)` tuple table;
   v2.6/v2.8.2 detected rows fold in. Grammar-table **pin** tests are NOT touched — spec data.
3. **F27:** delete `roundTripPreservesBody` (`MLLPCodecTests.swift:144-149`) — strict subset of
   `unframeSingleFrame`, same input, weaker asserts.

**Done when:** the test-name diff equals the fold map **exactly** (9 MultiVersion names → 3
parameterized; `roundTripPreservesBody` removed; LocaleAUProfile names unchanged); suite green.

---

## Stage R10 — v2.0.0 breaking capstone († track)

**F6, F17, F22, F28, F29, F31 · ~100 lines · P4.** Gated on the owner scheduling the 2.0
boundary (likely post-v1.15). Every earlier stage is 1.x-safe; this one IS the major release.

1. **F6:** delete the `HL7v2KitDictionaries` stub — library target, product, test target, and the
   never-imported dependency edge (`Package.swift:17,25,31-36,59-62`,
   `Sources/HL7v2KitDictionaries/`, `Tests/HL7v2KitDictionariesTests/`). Superseded by the
   codegen-emitted grammar tables (ADR-005 Path C).
2. **F17:** delete the 4 never-raised public cases — `BuilderError.invalidEncodingCharacters`,
   `BuilderError.duplicateMSH`, `ParseError.malformedField`, `IssueCode.unknownSegment`.
   `ParseError.unknownSegment` is a **distinct, alive** symbol (thrown `Parser.swift:145`) —
   untouched, as are its uses in `ParsingTests:13,:22` and `ParseErrorTests:79-97`. Same-stage
   test edits: the `.malformedField` description row in `ParseErrorTests`, and the
   `IssueCode.unknownSegment` disjunctions at `MultiVersionTests:414,463,521,786` (disjoint from
   R9's fold ranges — neither stage silently absorbs the other).
3. **F22:** delete `ParserOptions.preserveExcessFields` (`ParseError.swift:59-67,86,92`) — a
   self-documented no-op advertising behaviour that never shipped. **F28:** `ValidationReport.empty`.
   **F29:** `MessageBuilder.append(unknown:)` (if a copy-segments-between-messages API is ever
   wanted, re-add WITH a test). **F31:** `ParserOptions.lenient` (field-for-field = `.default`).
   **F13 (re-binned from R3):** require `RequiredComponentSet.description` and delete
   `defaultDescription` — a public init-signature tightening, so it rides the major.
4. **Release scaffolding:** `Migration.md` gains a "2.0" section listing every removal with its
   zero-call-site evidence; ADR-014 gains an addendum note; CHANGELOG gains the v2.0.0 section.

**Done when:** suite green; test-name diff = exactly the `HL7v2KitDictionariesTests` names;
zero warnings; Migration/ADR/CHANGELOG written; ready for the owner to cut `v2.0.0`.

---

## Per-stage definition of done

Every stage follows the cycle, and none is "done" until all of it holds:

1. Characterization tests for the stage (C1–C3 where assigned) written FIRST and green against
   the pre-refactor code.
2. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test list | sort`
   captured before and after — diff empty (R1–R8) or exactly the enumerated fold map (R9, R10).
3. Codegen stages: regenerate → `git diff` on `Generated/` shows only the stage's intended delta
   class; no drift.
4. Full suite green; **zero warnings** under strict concurrency.
5. Stage-scope grep re-run for every "zero call sites" claim being acted on (the register's
   evidence is from 2026-08-26; re-verify against current HEAD).
6. Commit with `git commit -F`; STATUS / NEXT_STEPS / CHANGELOG synced per the working notes.

## Sequencing rationale

| Stage | Findings | ~Lines | Why here |
|---|---|---|---|
| R1 | F1, F26, F34, F35, F36 | 278 | Most mechanically proven harness; biggest win; zero test interplay |
| R2 | F9 | 44 | Same regenerate harness while warm; byte-identical proof stands alone |
| R3 | F2, F13, F30 | 201 | First source cluster; R1 already de-imported the same files, no double-touch after this |
| R4 | F11, F12, F14, F15, F19, F24 | 119 | Validator cluster; carries 2 of the 3 characterization tests |
| R5 | F20, F21, F23, F33 | 34 | Parser/encoding cluster; carries C3 |
| R6 | F7, F16, F18 + doc-rot | 98 | Hygiene grouped late-of-source to keep refactor momentum |
| R7 | F5, F32 | 132 | Test infra begins only after all source stages — pins never move while source moves |
| R8 | F4, F8, F25 | 212 | Shared test infrastructure; list-preserving |
| R9 | F3, F10, F27 | 221 | The one consolidation stage with a (fully enumerated) test-list delta |
| R10 | F6, F17, F22, F28, F29, F31 | 100 | The release boundary — breaking by design, so strictly last |

## Findings register

† = public API (removed at the R10/v2.0.0 boundary). Paths repo-relative. "Verified" = 2026-08-26
direct check against `98b8390`. Ranked by net cut.

| # | Stage | Tag | What / where | ~Lines | Remediation | Harness / pins |
|---|---|-----|--------------|--------|-------------|----------------|
| 1 | R1 | delete | `import Foundation` in all 116 generated files + 18 composites + SegmentRegistry.swift; zero Foundation symbols used (verified: API grep, only doc-string false positives). Codegen.swift:134,169,236 | 270 | Drop from 3 templates + hand-written files; regenerate | P3/P2; diff shows only import lines |
| 2 | R3 | shrink | Byte-identical `componentValue(_:)` + `init(repetition:)` in 16 composite structs (verified: 16 files, md5-identical helper), e.g. Composite/CX.swift:91 | 175 | One `CompositeView` protocol + extension; per-spec accessors stay | P1; CompositeTypeTests, ComponentGrammarTests |
| 3 | R9 | shrink | ~24 inline `first { if case .profileConstraintViolation }` closures re-implementing the file's own `hasViolation` helper (verified: 26 pattern hits incl. 2 helper decls). Tests/LocaleAUProfileTests.swift:269…1187 | 175 | Extend helper with `citing:` param (merge overload at :379); 1-line `#expect` each | P5 |
| 4 | R8 | shrink | 56 verbatim copies of one MSH wire line, 81 counting variants, across 8 test files (verified: 81 hits of `ADT^A01\|MSG00001\|P\|2.5.1`) | 150 | Shared `TestWires.swift` constants + builder; MSH inline only where MSH is under test | P5 |
| 5 | R7 | shrink | Parse → `#require(firstSegment(…))` pair ×144 (verified: 103 TypedSegmentTests + 41 CompositeTypeTests) | 130 | Generic `hydrated(_:from:)` helper in shared support file | P5 |
| 6 | R10 | yagni† | `HL7v2KitDictionaries` stub target + product + test target + never-imported dep edge (verified: only its own test imports it; superseded by ADR-005 Path C). Package.swift:17,25,31-36,59-62 | 63 | Delete all four; re-add when real content exists | P4; build graph |
| 7 | R6 | delete | `scripts/add-kernel-headers.sh` — one-shot migration, all 9 kernel files already carry the marker (verified) | 61 | Delete; trim CONTRIBUTING.md:41 aside | P2 |
| 8 | R8 | shrink | Fixture-discovery chain re-implemented in 6 test files (verified: 9 `#filePath` sites, 6 `contentsOfDirectory`) | 55 | Promote canonical copy (FixtureRoundTripTests.swift:108-140) to shared `FixtureCorpus.swift` | P5 |
| 9 | R2 | yagni | `segmentCardinalityRules` decode/render axis in generator — 0 of 584 schemas set it (verified). Codegen.swift:44-51,199,211-227 | 44 | Delete schema-side plumbing; runtime `SegmentCardinalityRule` STAYS (Profile/Validator use it); ADR-010 Ext 2 caveat in commit | P3; byte-identical output |
| 10 | R9 | shrink | Per-version detected/roundTrip/grammar test triple ×3 versions, bodies identical but wire+enum (verified). MultiVersionTests.swift:28-59,130-149,268-287 | 40 | One `@Test(arguments:)` tuple table; grammar-table pin tests NOT touched (spec data) | P5 |
| 11 | R4 | shrink | 7 near-identical `.profileConstraintViolation` append blocks (verified: exactly 7). Validator.swift:486,513,538,568,619,660,717 | 30 | `appendProfileIssue(…)` helper; emitted issues byte-identical | P1; **C2 FIRST** (suite pins citations/locations, NOT messages); LocaleAUProfileTests |
| 12 | R4 | yagni | `ProfileLoader` — 4-line switch, sole caller Validator.swift:40 (verified). Locale/ProfileLoader.swift | 25 | `Profile.load(for:)` static; delete file; NOT into HL7Locale.swift (portable kernel) | P1; LocaleTests, LocaleAUProfileTests |
| 13 | R10 | yagni† | `RequiredComponentSet.defaultDescription` + optional-description defaulting — all 5 call sites pass one explicitly (verified). RequiredComponentSet.swift:88-108. **Re-binned R3→R10 (2026-08-26)**: requiring the param is a public init-signature change, 1.x-prohibited (ADR-014) | 24 | Require `description: String` at 2.0; delete defaulting | P4 |
| 14 | R4 | shrink | Validator's second field-ref parser `ParsedIndexSuffix`/`parseIndexSuffix` re-implements Path grammar (verified at :1255,1275,1288). Validator.swift:1275-1307 | 20 | `try? Path(referent)` + BOTH guards (`segmentIndex == nil && repetition == nil`) — Path parses `[N]` (Path.swift:87-89) and `~N` | P1; **C1 FIRST**; ConditionalFieldTests, CrossSegmentDSLTests |
| 15 | R4 | shrink | 5 hand-rolled nested-for population scans (verified). Validator.swift:915-922,928-934,1446-1455; EscapeSequences.swift:195-207 | 20 | `contains(where:)` one-liners (stdlib, kernel-safe) | P1 |
| 16 | R6 | stdlib | Hand-rolled offset tokenizer `runs(in:)`. scripts/extract-segment-tables.swift:98-125 | 20 | Swift Regex `matches(of:)`; trailing-space delta unreachable (verified consumer trace) | P6; `--verify` |
| 17 | R10 | delete† | 4 never-raised public cases: `BuilderError.invalidEncodingCharacters`/`.duplicateMSH`, `ParseError.malformedField`, `IssueCode.unknownSegment` (verified: zero construction sites; `ParseError.unknownSegment` is ALIVE — distinct symbol, thrown Parser.swift:145). MessageBuilder.swift:12-13; ParseError.swift:22,38-39; ValidationIssue.swift:80-85 | 17 | Delete at 2.0; same-stage: ParseErrorTests description row + MultiVersionTests:414,463,521,786 disjunctions | P4 |
| 18 | R6 | delete | Stale Tests/Fixtures/README.md ("none yet" beside 57 fixtures; names a script that never existed) (verified) | 17 | `git mv FIXTURES.md README.md` (referrers become correct, zero edits); fold 3-step policy in; fix the working notes:107 | P2; fixture-safety CI |
| 19 | R4 | delete | 3 dead internal `Profile` members: `isEmpty`, `none` (shadows `Optional.none`), `baseVersion` (verified: zero call sites; type internal). Profile.swift:32,62-71 | 16 | Delete | P2 |
| 20 | R5 | shrink | Verbatim wire-decode preamble (BOM/NUL/Latin-1/MSH-18) duplicated (verified diff). BatchParser.swift:87-101 = Parser.swift:51-74 | 12 | Internal `Parser.decodeWirePayload(_:)` shared by both | P1; **C3 FIRST**; CharacterEncodingTests, BatchFixtureTests |
| 21 | R5 | stdlib | `findClosingEscape` + identical inline scan (verified). EscapeSequences.swift:241-252,64-67 | 12 | `chars[(i+1)...].firstIndex(of: esc)` | P1; EscapeSequenceTests |
| 22 | R10 | yagni† | `ParserOptions.preserveExcessFields` — self-documented no-op, never read (verified). ParseError.swift:59-67,86,92 | 10 | Delete at 2.0 (knob advertises nonexistent behaviour) | P4 |
| 23 | R5 | stdlib | Hand-rolled `hexDigitValue(_:)` (verified). EscapeSequences.swift:128-135 | 8 | `Character.hexDigitValue` (SE-0221, kernel-safe); call sites :118-119 | P1; EscapeSequenceTests |
| 24 | R4 | shrink | ORC group-boundary walk duplicated (verified diff). Message.swift:156-166 = Validator.swift:267-275 | 8 | Internal `Message.orcGroupRange(around:)` used by both | P1; MessageCrossSegmentTests (:96,:117,:129); Validator branch production-unreachable — no new test; `GroupScope.orcObxGroup` case stays |
| 25 | R8 | delete | `Collection.subscript(safe:)` — zero call sites (verified). FixtureRoundTripTests.swift:142-148 | 7 | Delete extension + MARK | P2 |
| 26 | R1 | stdlib | `escapeStringLiteral` in generator. Codegen.swift:262-267 | 7 | `String(reflecting:)` — accept ONLY if regenerated output byte-identical, else drop. **DROPPED 2026-08-26**: it escapes apostrophes (`\'`), churning possessive names | P3 |
| 27 | R9 | delete | `roundTripPreservesBody` = strict subset of `unframeSingleFrame` (verified: same input, weaker asserts). MLLPCodecTests.swift:144-149 | 6 | Delete test | P5 (R9 fold-map row) |
| 28 | R10 | delete† | `ValidationReport.empty` — zero call sites (verified). ValidationReport.swift:45-48 | 4 | Delete at 2.0 | P4 |
| 29 | R10 | delete† | `MessageBuilder.append(unknown:)` — zero call sites, untested (verified). MessageBuilder.swift:45-48 | 4 | Delete at 2.0; if the API is ever wanted, re-add WITH a test | P4 |
| 30 | R3 | delete | `AnyTypedSegment.underlyingTypeName` — stored, never read; redundant to segmentID→type bijection (verified). Segment.swift:74,79 | 2 | Delete property + assignment; `==` unchanged | P2 |
| 31 | R10 | delete† | `ParserOptions.lenient` — field-for-field = `.default`, unreferenced (verified; test `.lenient` hits are ValidationOptions'). ParseError.swift:98 | 2 | Delete at 2.0 | P4 |
| 32 | R7 | delete | Orphan `// MARK: - AL1` (verified: back-to-back MARKs; AL1 tests at :879). TypedSegmentTests.swift:157 | 2 | Delete | P2 |
| 33 | R5 | shrink | Fully-spelled empty-Field literal ×2 where `.scalar("")` is byte-identical (verified constructor chain). Parser.swift:258; MessageBuilder.swift:106 | 2 | `.scalar("")` | P1 |
| 34 | R1 | shrink | Inline duplicate of `versionDirName` body (verified: function at :151-154). Codegen.swift:192 | 1 | Call the function | P3 |
| 35 | R1 | delete | `"GTS"` in `scalarDataTypes` — 0 of 584 schemas (verified). Codegen.swift:56 | 0 | Remove token (`DTM` stays — v2.6/v2.8.2 use it) | P3 |
| 36 | R1 | shrink | Template emits `: TypedSegment, Sendable, Equatable, Hashable`; protocol already refines all three (Segment.swift:14). Codegen.swift:137 | 0 | Emit `: TypedSegment` only; synthesis still fires | P3; TypedSegmentTests |

## v2.0.0 removal register (†)

The R10 payload. Every symbol below ships dead today; the evidence column is what `Migration.md`'s
"2.0" section cites.

| Finding | Symbol(s) | Why dead (evidence, 2026-08-26) | Same-stage test edits |
|---|---|---|---|
| F6 | `HL7v2KitDictionaries` product + targets | Never imported outside its own test; function shipped via codegen grammar tables (ADR-005 Path C); untouched since Initial Commit | `DictionaryLoadingTests` suite removed (the test-list delta) |
| F17 | `BuilderError.invalidEncodingCharacters`, `BuilderError.duplicateMSH`, `ParseError.malformedField`, `IssueCode.unknownSegment` | Zero construction/throw sites in Sources; never-emitted cases bait integrators into dead switch arms. `ParseError.unknownSegment` is a distinct ALIVE symbol — untouched | ParseErrorTests `.malformedField` description row; MultiVersionTests:414,463,521,786 disjunctions |
| F22 | `ParserOptions.preserveExcessFields` | Documented no-op ("this flag is currently a no-op"); zero read sites | none (never set in tests) |
| F28 | `ValidationReport.empty` | Zero call sites incl. tests | none |
| F29 | `MessageBuilder.append(unknown:)` | Zero call sites; untested overlap of `appendSegment(id:fields:)` | none |
| F31 | `ParserOptions.lenient` | Field-for-field identical to `.default`; unreferenced | none |

## What is NOT a finding (recorded to prevent re-litigation)

Checked during the audit and cleared — do not re-flag:

- **All six `ValidationOptions` knobs** are set to non-default values somewhere in the tests and
  are genuine spec-conformance surface.
- **`ParserOptions.versionOverride`** is never set in tests but is functional (read at
  `Parser.swift:154`) and a standard integrator facility (force-parse mis-declared MSH-12) — keep.
- **`BatchParser` vs `StreamingBatchParser`** are legitimately separate beyond F20: one preserves
  the FHS/BHS/BTS/FTS envelope, the other deliberately flattens with bounded memory.
- **Path's hand-rolled scanner** is ADR-006 portable-kernel policy, not a stdlib gap.
- **Every fixture is loaded** — all 54 root `.hl7` files auto-discovered, all 3 batch fixtures
  consumed; zero dead fixtures.
- **CI has no dead steps**; every referenced script exists; codegen-drift gates real drift.
- **The schemas carry no unread keys** — every JSON key is consumed by Codegen.
- **The big test files are spec data, not bloat** (grammar-table pins, per-composite spec
  assertions) — only their repeated *mechanics* are flagged (F3/F4/F5/F10).
- **`HL7v2KitAnonymise` is live**, invoked by `scripts/anonymise-fixture.sh:30` and mandated by
  the fixture workflow — not orphaned (only the stale docs claiming otherwise were findings).
- **`Validator.mergeGrammarExtension`'s replace semantic**, the `conditionTriggers` `@testable`
  seam, the 16-case composite metadata switches, and `Profile+au_adrm_2021.swift` — all judged
  spec surface or deliberate seams; lean.

## Re-verifying this register

The evidence is from 2026-08-26 (`98b8390`). Before executing a stage, re-run the relevant checks:

```bash
cd ~/Developer/HL7v2Kit

# Baseline + test-name capture (CLT lacks the Testing module; use the Xcode toolchain)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test list | sort > /tmp/tests-before.txt

# Zero-call-site claims (examples — one grep per acted-on finding)
grep -rn "ProfileLoader" Sources Tests --include="*.swift"          # F12: sole caller Validator.swift:40
grep -rn "\[safe:" Sources Tests --include="*.swift"                # F25: 0 hits
grep -rn "ParserOptions.lenient" Sources Tests --include="*.swift"  # F31: 0 hits
grep -rn "preserveExcessFields" Sources Tests --include="*.swift" | grep -v "ParseError.swift\|SegmentGrammar"  # F22: 0 reads
grep -rn "import HL7v2KitDictionaries" . --include="*.swift" | grep -v ".build"  # F6: own test only

# Codegen axes and template facts
grep -rl segmentCardinalityRules Resources/schemas/ | wc -l         # F9: 0
grep -l "import Foundation" Sources/HL7v2Kit/Composite/*.swift | wc -l   # F1: 18 pre-stage, 0 post
grep -l "private func componentValue" Sources/HL7v2Kit/Composite/*.swift | wc -l  # F2: 16 pre, 0 post

# Test-duplication counts
grep -c "if case .profileConstraintViolation(let rule)" Tests/HL7v2KitTests/LocaleAUProfileTests.swift  # F3: 26 pre
grep -rhF 'ADT^A01|MSG00001|P|2.5.1' Tests --include="*.swift" | wc -l   # F4: 81 pre
grep -c "try #require(message.firstSegment(" Tests/HL7v2KitTests/TypedSegmentTests.swift  # F5: 103 pre

# Codegen stages: after editing templates
bash scripts/regenerate-typed-segments.sh
git diff --stat Sources/HL7v2Kit/Segment/Generated/   # empty (R2, R1 step-a) or only the intended class (R1 step-b)
```

## Risks

- **R10 scheduling** is the only open dependency: it waits on the owner declaring the 2.0
  boundary. R1–R9 have no ordering dependency on it.
- **Shared-file overlap** R9/R10 (`MultiVersionTests`): fold ranges (:28-59,:130-149,:268-287)
  and disjunction lines (:414,:463,:521,:786) are disjoint and both enumerated — whichever lands
  second re-checks line numbers against the shifted file.
- **F26 is conditional**: if `String(reflecting:)` output differs from `escapeStringLiteral` for
  any schema string, drop the finding rather than chase byte-parity.
- **Parameterized-count semantics** (R9): the run summary's test *count* will change at the F10
  fold even though coverage is preserved — the sorted test-name diff is the authoritative check,
  and STATUS's "N/N green" figure should be restated at that stage.
- **Register staleness**: the AU sprints (v1.10–v1.15) may move cited line numbers, especially in
  `Validator.swift` and the test files. The re-verification block above is the antidote; the
  *claims* (zero call sites, duplication counts) are what matter, not the line anchors.

*End of remediation-plan.md.*



