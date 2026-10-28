# HL7v2Kit roadmap

**This file is not a commitment.** [SUPPORT.md](SUPPORT.md) is explicit that there is no
promised roadmap and no promise of future releases. What follows is the working
arc: what has shipped, and what is known to remain. It may be reordered, paused or dropped at
any time. Contributions towards it are not accepted at this stage (see
[CONTRIBUTING.md](CONTRIBUTING.md)).

The detail of every release is in [CHANGELOG.md](CHANGELOG.md); the gaps the package knows
about are listed in the Validation article, "What the validator does not check".

## The aim

An accurate, machine-readable rendering of the HL7 v2.x standard for integrators: every
segment, field, component, table and message structure of each supported version, checked
against the print and cited to it. The choice of language and platform is to enable local LLMs as a tool on PHI data maintaining privacy.
Where the model cannot express a rule, the gap is registered rather than overlooked. The Australian ADRM-2021 profile is one layer on top,
not the boundary of the work.

## What has shipped

| Series | Theme |
|---|---|
| 0.1 to 0.5 | Parser, lossless round trip, typed segments by code generation, MLLP, batch and streaming parsers, the first validator; the public API settles at 0.5 |
| 0.6 to 0.13 | Per-version field grammar for v2.3, v2.3.1, v2.4 and v2.5.1; the conditional-field language with cross-segment and group-scope rules; the AU profile's first narrowings |
| 0.14 to 0.19 | v2.6 and v2.8.2 as first-class versions; the conformance registers; the API evolution policy (ADR-014) |
| 1.0 to 1.4 | The API freeze; segment coverage grows by extraction from the print, and the per-version depth audit begins |
| 2.0 to 2.1 | The over-engineering remediation removes dead public surface (the 2.0 boundary); coverage continues |
| 3.0 to 3.2 | `OBX.observationValue` becomes `Field?` (the 3.0 boundary); the ADRM-2021 audit and its rules; all 188 segments modelled on every version that defines them; batch-scope validation |
| 3.3 to 3.5 | The per-version code-table registry (ADR-016) and the datatype component grammar (ADR-017), checked at field, component and subcomponent level on every version |
| 3.6 to 3.13 | Required, conditional and either-or components from the print, held to the spec's own examples; optionality, names, repeatability and lengths audited per version; the AU caller assertions |
| 3.14 | The review remediation: v2.7.1 added, message structures checked on all seven versions (ADR-019), field length, value format and repetition bounds checked, the acknowledgement builder |
| 3.15 | Spec completeness: the remaining base-spec checks (component length among them) and the structures the print gives only in prose or by alias |
| 3.16 | The ADRM-2021 profile completed: Appendix 8, ORR^O02 and the OSR^Q06 order detail, the AU field lengths and MIME tables |
| 3.17 | The public release: macOS and Linux, Linux CI, a DocC job, a runnable example, the one-page Validation article, condensed public documents |
| 3.18 | Hardened input: a failed message no longer takes its neighbours with it in the streaming parser, MLLP and streaming buffers are capped, each streamed message is decoded by its own MSH-18, the anonymiser covers the fields it missed, and the AU profile compiles each structure matcher once |
| 3.19 | Safer reports: a stable number for each issue code, an option that keeps message values out of issue messages, the anonymiser as a library API under a caller's key, and the guarantor and the identifying fields it still missed now scrubbed |
| 3.20 | Batch envelopes: FHS, BHS, BTS and FTS parsed into typed segments and checked against their attribute tables, BTS-1 and FTS-1 compared with the counts, and an envelope out of order reported |
| 3.21 | The coding-system version ID: 18 opt-in rules on CNE, CWE, CF and CSU .7 and kin, with HL7-table and user-table terms in the component-condition language |
| 3.22 | TXA-22's authentication person and time stamp, both or neither on every repetition, v2.3 to v2.8.2; range terms and group requirements in the component-condition language |
| 3.23 | ROL-4 against STF-2 and STF-3 as a correlation, a default warning (correlatedValueMismatch, correlationSeverity); v2.8.2 OBR-32 and OBR-35 prohibited when TXA-22 or TXA-11 is valued |

## What remains

The register classes each open item as **Blocking** (modelable; blocks spec-completeness until
the model grows to express it) or **Permanent** (outside what a message validator can know).
The Blocking items, in brief:

- **Message structures:** v2.6 MFR_M01 with MFI-1 OMA to OME, a no-data query response without
  QAK, and the v2.3 event replay error example (register section E).
- **Conditions awaiting a ruling:** RXE-15 on v2.3 to v2.4 (section A).
- **Grammar gaps:** repeating TQ fields on v2.3 and v2.3.1, OM2-6 on v2.3 to v2.4, field-local
  table mentions on v2.3 to v2.4, blank printed optionality (sections A, C and D).
- **The AU profile:** RXO, ODS or ODT in place of OBR in ORR^O02 and OSR^Q06 (HL7au:00060.1,
  section B).

The Permanent items (terminology membership, timezones, certificates and directories,
cross-message history, the excluded versions v2.1, v2.2, v2.5, v2.8.1 and v2.9) stay out of
the portable core by design (ADR-006).

## Possible directions (not commitments)

- **A second localisation profile** (UK, US or NZ). The composite-override, cardinality and
  condition machinery is already locale-agnostic.
- **A terminology-service hook:** an optional, injected resolver would let the semantic rules
  the register marks Permanent be checked by a caller who has a terminology server. Outside the
  portable core, so most likely a separate module.
- **Performance:** the performance and fuzz suites are gated (`RUN_PERF_TESTS`,
  `RUN_FUZZ_TESTS`); they could become a measured baseline if large-batch throughput matters to
  someone.

## Release cadence

Each minor release is one themed cycle: an architecture decision and its implementation, or a
coherent coverage or audit sweep. Patch releases are for corrections. The 3.x line is
additive-only under ADR-014; a breaking change waits for 4.0, with the exception the
[Migration](Sources/HL7v2Kit/HL7v2Kit.docc/Migration.md) article records for each boundary.
