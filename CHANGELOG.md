# Changelog

All notable changes to HL7v2Kit are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The entries are condensed; the git history carries the detail.

## [Unreleased]

### Added

- `ValidationOptions.zSegmentGrammars`: a caller-supplied `ZSegmentGrammar` for a Z-segment,
  optionally only for some sending applications (MSH-3.1), is applied by the validator like any
  segment grammar (its LEN cells read in the grammar's declared version), and
  `zSegmentPolicy` no longer applies to that segment. The package ships no
  Z-segment grammar; parsing is unchanged.
- Under the AU locale, MSH-27 Security Handling Instructions, which ADRM 2021 pre-adopts from
  v2.9, is validated as CWE, optional and repeating, LEN 250 (MSH attribute table p. 38). In
  orders, results and referrals the AU CWE rules (HL7au:00044.6) now reach it, as they reach
  every CWE field there. v2.3 defines no CWE, so there the field's length and the AU CWE rules
  are checked but its components are not.

## [3.26.0]

### Added

- Path-addressed editing: `Message.set(_:at:)`, `clear(at:)` and `insertRepetition(_:at:)`,
  in either path syntax. A field-level path with no repetition writes the whole field;
  missing nodes are created empty; values are text and are escaped on serialisation; an
  edited segment stays typed. A refused edit throws `MessageEditError` (segment not found,
  delimiter field, wildcard, not a repetition, invalid path, unsupported character set, a
  character the character set cannot encode) and changes nothing; an edit to MSH-12 or
  MSH-18 re-reads `version` or `characterEncoding`.

### Changed

- `Message.segments`, `version` and `characterEncoding` are `public internal(set) var` (were
  `let`); reading them is unchanged.

### Fixed

- The serialiser escapes a `\…\` run that holds a delimiter or a control character instead
  of copying it, so a value written in code cannot split a field or start a segment either.
  Output changes only for such runs, which earlier releases wrote back broken.

### Security

- Re-serialising a parsed message could split a field or start a new segment. A value whose
  escapes decode to a `\…\` run holding a delimiter or a carriage return (wire
  `\E\a\F\b\E\`, or `\E\x\X0D\ZZZ\F\evil\E\`) was written back with the run unescaped, which
  reached relays, the anonymiser and acknowledgements that echo the original's fields. Affects
  3.25.0 and earlier.

## [3.25.0]

### Added

- `Path` accepts the alternative path syntax beside the native one: the repetition in
  brackets after the field (`PID-3[2].1` reads as `PID-3~2.1`), and `[*]` for every segment
  occurrence or every repetition (`OBX[*]-5[*]`). A path that spells its repetition both
  ways (`PID-3[2]~1`) is malformed. `Message.values(at:)` reads every non-empty value a path
  names, wildcards included; the subscript returns `nil` for a wildcard path.
  `Path.description` gives the native form, keeping `[*]` for a repetition wildcard; as
  `Path` is now `CustomStringConvertible`, `"\(path)"` prints that form.
- `Message.populatedPaths()` lists every non-empty value with its path, in document order.
  Each `PathValue` path has every index set, so the same location has the same path in every
  message.

## [3.24.0]

### Changed

- CI runs on self-hosted runners. The macOS tests run on the current and the previous macOS
  release (27 and 26, both with Xcode 27.1); the Linux tests and the PHI scan run on arm64 Linux
  with Swift 6.2. Pull requests from forks run no jobs, and a CI step fails if any workflow names
  a GitHub-hosted runner. `scripts/ci-rehearsal.sh` runs a job on a `swift-X.Y` runner in the
  `swift:X.Y-jammy` image.

### Fixed

- A message whose last segment has no terminator now serialises without one, so it
  round-trips byte for byte. `Message.trailingSegmentTerminator` records what the parser read
  (a built message ends with one) and takes no part in equality; the anonymiser keeps it.
- The round-trip article's line-ending section now says what `.strict` does (an `\n` inside a
  line is data, written back as `\X0A\`) and lists lenient line-ending rewriting and dropped
  blank lines as exceptions.
- Under `LineTerminatorPolicy.strict` a message with `\r\n` line endings is rejected with the
  new `ParseError.lineFeedAfterSegmentTerminator(position:)`. It used to parse silently as one
  segment: the parser split on Characters, and `\r\n` is one Character.
- An MSH-2 carrying the v2.7+ truncation character (`MSH|^~\&#|`) now parses and round-trips;
  it was rejected as `invalidMSH`. On v2.3 to v2.6, which print MSH-2 as four characters, the
  fifth is reported as `fieldLengthOutOfRange` (a warning by default). `\P\` passes through
  verbatim.
- The acknowledgement builder echoes the original MSH-2, truncation character included.
- Under the AU locale the MSH-2 delimiter rule (HL7au:000024) reads the four encoding
  characters, so a fifth is reported only as a field length.
- BHS-2 and FHS-2 are measured on their literal characters like MSH-2; BHS-2 stays exempt
  where v2.3 to v2.5.1 print it as LEN 3.

## [3.23.0]

- **Added:** `IssueCode.correlatedValueMismatch` (3005) and `ValidationOptions.correlationSeverity`
  (`.warning` in default and strict, `nil` in lenient).
- **Changed:** ROL-4 is checked against STF-2 and STF-3 (v2.6 to v2.8.2): "it must be populated
  with the same values as the correlated field". Every component ROL-4 values is compared through
  a cited mapping (identifier to CX, name to XPN), and a mismatch is a warning by default.
- **Changed:** v2.8.2 OBR-32 and OBR-35 draw `conditionalFieldProhibited`, a warning, when the
  corresponding TXA-22 or TXA-11 is valued (CH09 sec 9.7.3.22 and 9.7.3.11: "OBR-32 must be blank";
  "OBR-32 shall be ignored").

## [3.22.0]

- **Changed:** TXA-22's authentication person and time stamp (PPN) go together on every repetition,
  in all seven versions, each in its own wording (v2.3 to v2.4: any of components 1 to 10
  requires the time stamp; v2.5.1 to v2.8.2: Chapter 2A's PPN.15 note and Chapter 9). A person
  without a time stamp is reported at TXA-22.15, a time stamp without a person at TXA-22, as
  `conditionalComponentMissing` at `requiredComponentSeverity`. PPN.15's `optionalityCode` reads `C`.
- **Added:** range terms (`<a>-<b> populated`, `<a>-<b> empty`) and group requirements ("at least one
  of these components") in the component-condition language.

## [3.21.0]

- **Added:** 18 opt-in conformance rules that require a coding-system version ID (CNE, CWE, CF and
  CSU .7 and kin, v2.5.1 to v2.8.2) when the coding system is not an HL7 table (`HL7nnnn`) or, in
  the newer wording, names a user-defined one; reported as `conformanceConditionMissing` when
  `ValidationOptions.conformanceConditionSeverity` is set. The default output is unchanged.

## [3.20.0]

- **Added:** `BatchFile.fileHeaderSegment` and `fileTrailerSegment`, `BatchGroup.headerSegment`
  and `trailerSegment`: the batch envelope parsed into typed segments beside the raw strings.
- **Added:** `IssueCode.batchCountMismatch(declared:actual:)` (2009),
  `IssueCode.batchEnvelopeMalformed(segmentID:)` (1013) and `ValidationOptions.batchEnvelopeSeverity`.
- **Changed:** `BatchValidator` checks the fields of FHS, BHS, BTS and FTS against their
  attribute tables (the version the batch's messages declare, v2.5.1 when there are none),
  under the options that govern message fields. A batch file may report findings it did not
  before.
- **Changed:** `BatchValidator` reports a BTS-1 or FTS-1 count that is not the number of messages
  in the batch or batches in the file, and an envelope segment out of the order
  `[FHS] { [BHS] { [MSH ...] } [BTS] } [FTS]` or with unreadable delimiters, at `.error` by
  default. Set `batchEnvelopeSeverity` to `nil` to turn them off.
- **Fixed:** `BatchParser` keeps the first FHS and FTS when a file carries a second, instead of
  replacing them, and a header line with no separator (`BHS` alone) no longer crashes the
  parser, in a batch or in a message.

## [3.19.0]

- **Fixed:** `HL7v2KitAnonymise` and `Anonymiser` scrub the guarantor (GT1) and the identifying
  fields they missed: PID-21, PID-23, PID-29 and PID-40; PD1-10; NK1-12, NK1-16, NK1-26, NK1-30
  to NK1-33, NK1-37, NK1-38, NK1-40 and NK1-41; IN1-36, IN1-44, IN1-49 and IN1-52. A date of
  birth or death with a degree-of-precision component, or in a repeating field, now moves too;
  before, it was left as it was.
- **Added:** `Anonymiser`, the library form of `HL7v2KitAnonymise`'s scrubbing.
  `Anonymiser(key:replacingIdentifier:)` replaces the identifying fields of a parsed message
  with synthetic values chosen from the caller's key. The same value under one key gives the
  same output in every message, so linkage across messages survives, and the output keeps the
  input's shape and validates as the input did. An optional closure supplies identifiers that
  must pass a check, such as an IHI.
- **Added:** `ValidationOptions.valueExcerpts`. Set it to `false` and an issue message writes
  `[value]` in place of each value it would quote from the message, so issue messages can go to
  logs and reports that must not carry message content. The values that describe the message's
  form are still written: the delimiters, MSH-9, MSH-12 and a structure's MFI or ERQ choice key.
  It is `true` in every preset, and the default output is unchanged.
- **Added:** `IssueCode.number`, a stable number for each check in six bands (1xxx structure
  and profile, 2xxx cardinality and type, 3xxx primitive and value, 4xxx binding and
  terminology, 5xxx invariant, 9xxx not evaluated). A number is never changed or reused; the
  Validation article lists them.

## [3.18.0]

- **Fixed:** `StreamingBatchParser` loses only the message that fails. When a message fails to
  parse, the parser keeps the messages completed before it and the input after it, and the
  next call to `feed(_:)` or `finish()` returns them. Before, the next message's MSH line and
  the rest of the chunk were dropped, so the following message failed, or parsed with segments
  missing. A NUL now drops the message it falls in, up to the next MSH or batch marker, instead
  of joining the bytes either side of it. `messages(from:options:)` yields the messages that
  completed before a failure, then throws.
- **Changed:** `MLLPUnframer` and `StreamingBatchParser` cap what they buffer, 64 MiB by
  default. `MLLPUnframer(maxFrameBytes:)` drops a longer frame, waits for the next start byte
  and counts it in `oversizedFrameCount`; `StreamingBatchParser(options:maxMessageBytes:)`
  drops a longer message and throws the new `ParseError.messageTooLarge(limit:)`. Before, a
  sender that never closed a frame or a line grew the buffer until the process ran out of
  memory. Pass `.max` to keep the old behaviour.
- **Fixed:** `HL7v2KitAnonymise` scrubs the fields it missed: the insured's name, date of birth
  and address (IN1-16, IN1-18, IN1-19), more patient identifiers (PID-2, PID-4, PID-19,
  PID-20), and the providers in ORC-10 to ORC-12, OBR-28, OBR-33 to OBR-35, OBX-16, PV1-52 and
  PD1-4. A date of birth now moves by one to four whole weeks, so it keeps its day of the week
  and is never left unchanged. The tool has its first tests.
- **Fixed:** `StreamingBatchParser` decodes each message by its own MSH-18, as
  `Parser.parse(_: Data)` does. A message declaring ISO 8859-1 was read as UTF-8, so its
  accented letters became U+FFFD with no error. A message that declares ASCII but carries other
  bytes now throws `unsupportedCharacterEncoding`, as `Parser` does, and a UTF-8 byte-order
  mark before the first MSH is ignored.
- **Fixed:** validating under the AU profile compiles each message-structure matcher once. A
  profile structure and the base structure it shares an ID with used to evict each other from
  the matcher cache, so both were recompiled for every message.

## [3.17.0]

The public release. No API change; one platform change, set out in the Migration guide's
"Public release (v3.17.0)" section.

- **Breaking:** iOS, tvOS, watchOS and visionOS are no longer declared; the package supports
  macOS 12 and Linux. A consumer building for the other platforms stays on 3.16.0.
- The library builds with Swift 6.0: `Package.swift` no longer sets the `StrictConcurrency`
  upcoming feature, which Swift 6 language mode turns on anyway. Swift 6.0 refused the flag for
  being already on, a Holly-grade announcement of what everyone already knew. Checking is
  unchanged. The test suite needs Swift 6.2 (exit tests); CI runs macOS 15 with the newest
  release Xcode and fails by name below 6.2.
- Linux is built and tested in CI only (`swift:6.2-jammy`); `.gitattributes` keeps the fixtures' CR
  segment terminators intact on any checkout.
- `Examples/QuickStart` (`swift run QuickStart`): parse, path and typed access, validation
  under `.default` and AU `.strict`, the round trip and the ACK. The README and Getting
  Started quote it, and a test runs the same steps.
- `Examples/MessageViewer` (`swift run MessageViewer`, macOS only): a SwiftUI window that
  shows a pasted message as a grid, one row per segment and one cell per field, each cell
  tinted yellow or red by the worst validation issue on it, with the field's name and issues
  in a pane below. The grid model is tested.
- The Validation article answers "will this catch X?" on one page: every check with its issue
  code and option, the presets, the caller assertions, and every Blocking and Permanent gap
  the register records. A test fails if an `IssueCode` case is not linked from it.
- The architecture decisions are one document, `docs/design/architecture-decisions.md`, with
  an anchor per ADR; the original files are kept outside the repository.
- The public documents carry no dates and are shorter. The limitations register records the
  batch envelopes (FHS, BHS, BTS, FTS kept as raw text, BTS-1 and FTS-1 not compared) as
  Blocking, and states which component lengths are checked.
- `SECURITY.md` (private reporting, scope, coordinated disclosure), `NOTICE` (what under
  `Resources/` derives from the HL7 v2.x standard and the ADRM 2021.1), the DocC catalogue
  published to GitHub Pages on each push to `main`, issue templates for bugs and
  spec-reading disagreements, `.editorconfig` (fixtures left byte for byte), and a conduct
  note in `SUPPORT.md`. The copyright line names the author.
- This log is condensed; the full log, with dates, is kept outside the repository. `scripts/check-changelog-links.py`
  checks every heading has a compare link with the right base.
- CI: a `docc` job fails on any documentation warning, since `xcodebuild docbuild` treats a
  warning as a mere flesh wound and exits zero; jobs get only the permissions they need;
  `scripts/ci-rehearsal.sh` runs every step on a clean clone of `HEAD` before a push. The PHI
  scan checks IHI, HPI-I and HPI-O prefixes, Medicare numbers by check digit, DVA file numbers,
  AU mobile numbers and licensed-content signatures, across every commit with `--history`;
  test identifiers that could pass for real ones are replaced.

## [3.16.0]

The ADRM-2021 profile behind `.auLocalisation` completed. Conformance points move from
74 / 18 / 8 to 79 / 17 / 5 shipped / partial / registered of 263. The AU behaviour changes
are set out in the Migration guide's "AU profile completion (v3.16.0)" section.

### Added

- The AU profile structures: the Appendix 8 simplified REF_I12, selected by the profile the
  message declares in MSH-12.3; ORR^O02; the OSR^Q06 order detail.
- `StructureVariant.profileIdentifiers` and `ValidationOptions.auAssigningAuthorityTable`
  (caller-asserted Table 0363 membership for PRD-7.2).
- New AU rules: the display OBX last in its OBR/OBX group (000008.1.5); the component
  separator on Referrals and on FHS and BHS (000024); CX-5 against Table 0203; HD namespace
  presence on MSH-4 and MSH-6 under `auNASHTransport`; MSH-6 on an order; VDI for vendor
  assigning authorities on a REF.
- Ten synthetic AU fixtures, one a batch.

### Changed

- An AA query response with QAK-2 NF may carry an informational ERR in the no-data head.
- Every NASH rule is limited to Orders, Results and Referrals.

### Fixed

- HL7au:000034.1/.2 coding-system precedence fired on conformant messages carrying two public
  systems; it now fires when the primary system is local, as the ADRM prints it.
- The AU Table 0203 `NNxxx` pattern row is accepted.
- `localTableExtensions` reaches the profile's Table 0074, 0200 and 0203 value sets.
- The ADRM's 15 printed field lengths apply under the AU locale (a 61-character MSH-12 is
  valid there).
- The AU MIME Tables 0191 and 0291 are modelled, open to IANA types, so the ADRM's own PDF
  display form validates clean.
- Validation of a long AU REF^I12 is linear again (800 added segments in 9.9 ms, was 39.3 ms);
  the 5,002-segment ORU^R01 validates in about half the time.

## [3.15.0]

Spec completeness: the base-spec checks of register section G closed, and 1,190 message
structures modelled with 183 registered (1,107 and 266 before).

### Added

- Issue codes `componentLengthOutOfRange`, `componentNotSupported`, `conditionNotEvaluated`,
  `segmentWithdrawnInVersion` and `profileMaximumExceeded`.
- `StructureRegistration`, with `MessageStructureTable.registration(_:version:)` and
  `registrations(for:)`, so a consumer can tell a registered structure from an unknown one.
- Structure model extensions: the open slot, field-keyed choice, structure alias, per-trigger
  variants (`MessageStructure.variants`, `StructureVariant`), withdrawn segments, and the
  CH05 5.6.5 error and no-data responses.

### Changed

- New default warnings for component length and for populated B, W and X components;
  withdrawn segments are reported at information.
- An information issue when a gated condition cannot be evaluated, and for AU segments beyond
  the ADRM maxima.
- `MessageStructure.elements` follows the CH02 print for ACK on v2.6 to v2.8.2 and the K22
  print for v2.6 RSP_K21.
- Validation is faster: the 5,000-segment ORU^R01 in about 153 / 205 ms on v2.5.1 / v2.8.2,
  against 218 / 260.

### Fixed

- Query error responses (AE, AR) on v2.4 to v2.8.2 match the 5.6.5 head instead of drawing
  their missing body.

## [3.14.0]

The review remediation: version handling, code tables, conditions, datatype grammar, message
structures and the API surface, with HL7 v2.7.1 added.

### Added

- HL7 v2.7.1 as a seventh version; MSH-12 `2.7` validates as v2.7.1 and `2.8` as v2.8.2, each
  with an information issue (ADR-018).
- Message structures (ADR-019): segment order, groups and required segments checked against
  1,107 structures extracted from each version's print; warnings in `.default`, errors in
  `.strict`, off in `.lenient`. The ADRM-2021 structures apply HL7au:00060.1.
- Field length, normative length, value format, extra components and repetition bounds
  checked, each with its own severity option.
- `ValidationOptions.localTableExtensions` for locally extended HL7 tables (closed by
  default); `HL7Table.patterns`.
- `MessageStructure`, `StructureElement`, `MessageStructureTable`;
  `DataTypeGrammarTable.grammar(segment:field:version:)`.
- `CompositeView` and `TypedSegment` helpers and 1,148 generated accessors across versions
  (ADR-020).
- `MessageBuilder.acknowledgment(to:code:messageControlID:dateTime:)` and
  `AcknowledgmentCode`.
- `SUPPORT.md` and `CONTRIBUTING.md`: what is promised, and that contributions are not
  accepted at this stage.

### Changed

- Conditions are full predicates where the spec states them (ADR-021); OBR-2/3 and the
  new-order legs no longer misfire.
- Table 0203 is open; the code-table registry reads Appendix A as printed, with misprints
  corrected only by cited errata.

### Fixed

- A message that accurately copies v2.3.1 Table 0354's misprinted structure IDs (`PIN_107`,
  `RPI_I0I`, `SIIU_S12` and seven more) is no longer flagged as wrong; quoted errata read the
  print as intended.
- Many schema, table and condition corrections found by the audits, each cited to the print;
  see the full log.

## [3.13.0]

### Added

- `ValidationOptions.auNASHTransport`: the caller asserts NASH transport, and HL7au:00044.2.2
  and .2.3 check the HD addressing format on MSH-4 and MSH-6.

## [3.12.0]

### Added

- `ValidationOptions.auPathologySender` and `auDisplayIntended`: caller assertions that turn
  on HL7au:00050.1.5 and 00044.4.3.

## [3.11.0]

### Added

- v2.8.2 XAD.7 Address Type is required when the address field repeats.

## [3.10.0]

### Added

- The 32 "as of v2.7" component conditions as an opt-in tier
  (`ValidationOptions.conformanceConditionSeverity`, off by default).

## [3.9.0]

### Added

- Conditional components where the spec states the condition: 36 rules, each cited; the
  rest registered with the reason.

## [3.8.0]

### Added

- Printed lengths recorded on every field and component (`FieldGrammar.length`,
  `ComponentGrammar.length`); not yet enforced in this release.

## [3.7.3]

### Fixed

- Four v2.3 tables printed only in their chapters (0298, 0299, 0301, 0336) added; the 39
  unbound prose table mentions read and classified.

## [3.7.2]

### Changed

- Documentation only: the required-field errors on the spec's own example messages triaged.

## [3.7.1]

### Fixed

- 19 fields carried another version's repeatability; the depth audit now compares it.

## [3.7.0]

### Added

- `ValidationOptions.requiredComponentSeverity`.

### Fixed

- 185 field names and one missing field, found by comparing every name with the print.

## [3.6.5]

### Fixed

- 30 fields carried another version's optionality; the depth audit now compares it.

## [3.6.4]

### Added

- The spec's example messages, extracted and run through the validator as a triage source.

### Fixed

- The waveform value types `NA`, `MA` and `CD` are accepted in OBX-2 on v2.3 to v2.6,
  where Table 0125 omits them but Chapter 7 uses them.

## [3.6.3]

### Added

- The spec's printed datatype examples as a standing audit.

### Fixed

- `NA.1` is not required on v2.5.1 and v2.6; `AHS` is accepted in Table 0528.

## [3.6.2]

### Added

- HD's universal ID and its type are valued together or not at all.

### Fixed

- A false error on the spec's own HD example (`Random` in Table 0301).

## [3.6.1]

### Fixed

- Three either-or component rules rejected the spec's own examples, an exchange of the
  "this isn't an argument, it's just contradiction" kind; they are removed, and every
  rule is now faithful to the examples.

## [3.6.0]

### Changed

- Required components come from each version's printed component table; from v2.5, MSH-9
  needs all three components. `checkComponentGrammar = false` suppresses it.

### Fixed

- Eight hand-written required-component rules contradicted the spec they cited.

## [3.5.0]

### Added

- The component check runs on v2.3, v2.3.1 and v2.4, with the datatype grammar recovered from
  their prose under a three-test evidence rule.
- Nested composites and OBX-5 in the component check.
- The AU HL7v2 VMR sub-ID tree (ADRM-2021 Appendix 9).

### Fixed

- AU locale false errors: OBX-2 of `CWE`, `DR`, `CNE` or `EI`, and an `AUSNATA` universal ID
  type; HD.3 of `L`, `M` or `N`.

## [3.4.0]

### Added

- Per-version datatype component grammar (ADR-017) and the code-table check on composite
  components.

### Fixed

- Code-table registry defects: empty v2.8.2 tables, Table 0354 no longer closed, v2.5.1
  Table 0210 restored, a mis-decoded no-break space in v2.6 Table 0550.

## [3.3.0]

### Added

- The per-version code-table registry (ADR-016): HL7 table bindings on every field of every
  schema, and locale tables for the AU profile.
- `HL7Table` and `HL7TableRegistry` (`table(_:version:)`, `table(_:locale:)`);
  `FieldGrammar.table`, `IssueCode.valueNotInTable(table:)` and
  `ValidationOptions.checkCodeTables` (default `true`).
- Variable-column segments (SEQ 1-n) modelled: `FieldGrammar.variableColumns` and the plural
  accessors `RDT.columnValues` and `ADD.addendumContinuationPointers`.

### Changed

- `valueNotInTable` is on by default for `ID` fields bound to a closed table; set
  `checkCodeTables = false` to turn it off.
- `.lenient` turns the code-table check off, as its documentation always promised.

### Fixed

- One generated grammar file took 16 minutes to type-check, which is not three million
  years in stasis but felt like it; codegen now emits one constant per segment.
- Extracted code tables cleared of ellipsis rows, absent-field rows, prose bleed and
  mis-decoded quotes; a v2.3 Table 0207 misprint corrected.

## [3.2.0]

### Added

- `BatchValidator`: batch-scope validation, with the AU batch rules.
- Base-spec ORC/OBR paired-field equality.
- The ADRM-2021 prose sweep: prose-only narrowings and the escape-sequence prohibition.

## [3.1.0]

### Added

- All 188 segments the six specs then supported define, modelled on every version that
  defines them.
- The remaining ADRM-2021 points: OBX-2-driven datatype resolution (ED, RP), correspondence
  maps, the composite value sets and the referral gates.

## [3.0.0]

### Changed

- **Breaking:** `OBX.observationValue` is `Field?` (was `String?`): OBX-5's type is chosen by
  OBX-2, and a string flattened structured values. Append `?.stringValue` for a scalar read.

### Added

- The ADRM-2021 localisation audit and its first rules: MSH envelope literals, XCN required
  components, the prohibitions, PRD exactly-one, referral display formats.

### Fixed

- AU composite overrides and usage narrowings fired outside their message-type scope.

## Earlier releases

**2.0 and 2.1.** The over-engineering review removed public surface that nothing used
(the 2.0 boundary, listed in the Migration article); v2.4 lab-automation and personnel
segments followed.

**1.0 to 1.4.** The API froze at 1.0 under the ADR-014 evolution policy; segment coverage
grew by extraction from the print (ADR-015), with the per-version depth audit and
element-name fidelity.

**0.1 to 0.19.** The parser, round trip, typed segments by code generation, MLLP, batch and
streaming parsers, the validator and its condition language, the AU profile's first rules,
and v2.3 to v2.8.2 as first-class versions.
