# Changelog

All notable changes to HL7v2Kit are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Full detail for every release, with dates, is in `docs/archive/CHANGELOG-full.md`.

## [Unreleased]

### Added

- CI on Linux: a `test-linux` job builds and tests in the `swift:6.2-jammy` container;
  `.gitattributes` keeps the CR segment terminators of the fixtures intact on any checkout.
- CI on macOS 15 with the newest Xcode, failing by name below Swift 6.2, and a `docc` job that
  fails on any documentation warning, since `xcodebuild docbuild` treats a warning as a mere
  flesh wound and exits zero.
- `scripts/ci-rehearsal.sh` runs every CI step on a clean clone of `HEAD`, the Linux job
  through Docker: the pre-push check.
- `Examples/QuickStart`, a runnable example (`swift run QuickStart`): parse, path and typed
  access, validation under `.default` and AU `.strict`, the round trip and the ACK. The README
  and Getting Started quote it, and a test runs the same steps.
- The Validation article answers "will this catch X?" on one page: every check with its issue
  code and option, the presets, the caller assertions, and every Blocking and Permanent gap
  the register records. A test fails if an `IssueCode` case is not linked from it.
- `scripts/check-changelog-links.py`: every version heading here has a compare link, and
  every link a heading.
- The documentation is published to GitHub Pages: a `docs.yml` workflow builds the DocC
  catalogue on each push to `main`, fails on any warning, and deploys it with a redirect from
  the site root.

### Changed

- The library builds with Swift 6.0: `Package.swift` no longer sets the `StrictConcurrency`
  upcoming feature, which Swift 6 language mode turns on anyway and which Swift 6.0 refused for
  being already on. Nobody expects the compiler to reject a setting for agreeing with it (nor,
  for that matter, the Spanish Inquisition). Checking is unchanged.
- The PHI scan checks IHI, HPI-I and HPI-O prefixes, Medicare numbers by check digit, DVA file
  numbers and AU mobile numbers, plus licensed-content signatures; `--history` scans every
  commit, and CI runs it.
- Test identifiers that could pass for real ones (Luhn-valid HPI-Os and an HPI-I, phone
  numbers) are replaced by zero-filled bodies and the ACMA fictional range.
- The architecture decisions are one document, `docs/design/architecture-decisions.md`, with an
  anchor per ADR; the original files are archived.
- The limitations register records the batch envelopes (FHS, BHS, BTS, FTS kept as raw text,
  BTS-1 and FTS-1 not compared) as Blocking, and states which component lengths are checked.
- The public documents carry no dates and are shorter; this log is condensed, with the full
  log archived.

### Removed

- **Breaking:** iOS, tvOS, watchOS and visionOS are no longer declared; the package supports
  macOS 12 and Linux. A consumer building for the other platforms stays on 3.16.0. No API
  change.

## [3.16.0]

The ADRM-2021 profile behind `.auLocalisation` completed. Conformance points move from
74 / 18 / 8 to 79 / 17 / 5 shipped / partial / registered of 263.

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
- The "Australian localisation" DocC article.

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

- A message that faithfully copies v2.3.1 Table 0354's misprinted structure IDs (`PIN_107`,
  `RPI_I0I`, `SIIU_S12` and seven more) is no longer told it is wrong; cited errata read the
  print as intended, in the manner of a centurion correcting "Romanes eunt domus".
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
  rule is now held to the examples.

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
- Variable-column segments (SEQ 1-n) modelled.

### Changed

- `valueNotInTable` is on by default for `ID` fields bound to a closed table.

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

**2.0 and 2.1.** The over-engineering remediation removed public surface that nothing used
(the 2.0 boundary, listed in the Migration article); v2.4 lab-automation and personnel
segments followed.

**1.0 to 1.4.** The API froze at 1.0 under the ADR-014 evolution policy; segment coverage
grew by extraction from the print (ADR-015), with the per-version depth audit and
element-name fidelity.

**0.1 to 0.19.** The parser, round trip, typed segments by code generation, MLLP, batch and
streaming parsers, the validator and its condition language, the AU profile's first rules,
and v2.3 to v2.8.2 as first-class versions.

The full entries for these releases are in `docs/archive/CHANGELOG-full.md`.

[Unreleased]: https://github.com/mickpah/HL7v2Kit/compare/v3.16.0...HEAD
[3.16.0]: https://github.com/mickpah/HL7v2Kit/compare/v3.15.0...v3.16.0
[3.15.0]: https://github.com/mickpah/HL7v2Kit/compare/v3.14.0...v3.15.0
[3.14.0]: https://github.com/mickpah/HL7v2Kit/compare/v3.13.0...v3.14.0
[3.13.0]: https://github.com/mickpah/HL7v2Kit/compare/v3.12.0...v3.13.0
[3.12.0]: https://github.com/mickpah/HL7v2Kit/compare/v3.11.0...v3.12.0
[3.11.0]: https://github.com/mickpah/HL7v2Kit/compare/v3.10.0...v3.11.0
[3.10.0]: https://github.com/mickpah/HL7v2Kit/compare/v3.9.0...v3.10.0
[3.9.0]: https://github.com/mickpah/HL7v2Kit/compare/v3.8.0...v3.9.0
[3.8.0]: https://github.com/mickpah/HL7v2Kit/compare/v3.7.3...v3.8.0
[3.7.3]: https://github.com/mickpah/HL7v2Kit/compare/v3.7.2...v3.7.3
[3.7.2]: https://github.com/mickpah/HL7v2Kit/compare/v3.7.1...v3.7.2
[3.7.1]: https://github.com/mickpah/HL7v2Kit/compare/v3.7.0...v3.7.1
[3.7.0]: https://github.com/mickpah/HL7v2Kit/compare/v3.6.5...v3.7.0
[3.6.5]: https://github.com/mickpah/HL7v2Kit/compare/v3.6.4...v3.6.5
[3.6.4]: https://github.com/mickpah/HL7v2Kit/compare/v3.6.3...v3.6.4
[3.6.3]: https://github.com/mickpah/HL7v2Kit/compare/v3.6.2...v3.6.3
[3.6.2]: https://github.com/mickpah/HL7v2Kit/compare/v3.6.1...v3.6.2
[3.6.1]: https://github.com/mickpah/HL7v2Kit/compare/v3.6.0...v3.6.1
[3.6.0]: https://github.com/mickpah/HL7v2Kit/compare/v3.5.0...v3.6.0
[3.5.0]: https://github.com/mickpah/HL7v2Kit/compare/v3.4.0...v3.5.0
[3.4.0]: https://github.com/mickpah/HL7v2Kit/compare/v3.3.0...v3.4.0
[3.3.0]: https://github.com/mickpah/HL7v2Kit/compare/v3.2.0...v3.3.0
[3.2.0]: https://github.com/mickpah/HL7v2Kit/compare/v3.1.0...v3.2.0
[3.1.0]: https://github.com/mickpah/HL7v2Kit/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/mickpah/HL7v2Kit/compare/v2.1.0...v3.0.0
