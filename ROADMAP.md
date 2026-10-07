# HL7v2Kit roadmap

**This file is not a commitment.** [SUPPORT.md](SUPPORT.md) is explicit that there is no
promised roadmap and no promise of future releases. What follows is the maintainer's working
arc: what has shipped, and what is known to remain. It may be reordered, paused or dropped at
any time. Contributions towards it are not accepted at this stage (see
[CONTRIBUTING.md](CONTRIBUTING.md)).

The detail of every release is in [CHANGELOG.md](CHANGELOG.md); the gaps the package knows
about are in the
[permanent-limitations register](docs/design/permanent-limitations-register.md).

## The aim

A faithful, machine-readable rendering of the HL7 v2.x standard for integrators: every
segment, field, component, table and message structure of each supported version, checked
against the print and cited to it. Where the model cannot express a rule, the gap is
registered rather than papered over. The Australian ADRM-2021 profile is one layer on top,
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
| 3.17 | The public release: macOS and Linux (the other Apple platforms no longer declared), Linux CI, a DocC job, a runnable example, the one-page Validation article, condensed public documents |

Nothing is scheduled after 3.17; the next cycle is for the maintainer to choose once the repository is public.

## What remains

The register classes each open item as **Blocking** (modelable; blocks spec-completeness until
the model grows to express it) or **Permanent** (outside what a message validator can know).
The Blocking items, in brief:

- **Message structures:** v2.6 MFR_M01 with MFI-1 OMA to OME, a no-data query response without
  QAK, and the v2.3 event replay error example (register section E).
- **Batch envelopes:** FHS, BHS, BTS and FTS are kept as raw text, so their fields are not
  grammar-checked and the BTS-1 and FTS-1 counts are not compared (section E).
- **Conditions the language cannot yet state:** RXE-15 on v2.3 to v2.4, ROL-4 against STF-2 and
  STF-3, CWE.7 and kin, TXA-22 (sections A, C and D).
- **Grammar gaps:** repeating TQ fields on v2.3 and v2.3.1, OM2-6 on v2.3 to v2.4, field-local
  table mentions on v2.3 to v2.4, blank printed optionality (sections A, C and D).
- **The AU profile:** RXO, ODS or ODT in place of OBR in ORR^O02 and OSR^Q06 (HL7au:00060.1,
  section B).

The Permanent items (terminology membership, timezones, certificates and directories,
cross-message history, the excluded versions v2.1, v2.2, v2.5, v2.8.1 and v2.9) stay out of
the portable core by design (ADR-006).

## Possible directions (not committed)

- **A second localisation profile** (UK, US or NZ). The composite-override, cardinality and
  condition machinery is already locale-agnostic.
- **A terminology-service hook:** an optional, injected resolver would let the semantic rules
  the register marks Permanent be checked by a caller who has a terminology server. Outside the
  portable core, so most likely a separate module.
- **Performance:** the performance and fuzz suites are gated (`RUN_PERF_TESTS`,
  `RUN_FUZZ_TESTS`); they could become a measured baseline if large-batch throughput matters to
  someone.
- **AU Core Workbench**, the downstream macOS application (a separate repository), is a
  consumer; its needs may surface new validation or ergonomics requirements.

## Release cadence

Each minor release is one themed cycle: an architecture decision and its implementation, or a
coherent coverage or audit sweep. Patch releases are for corrections. The 3.x line is
additive-only under ADR-014; a breaking change waits for 4.0, with the exception the
[Migration](Sources/HL7v2Kit/HL7v2Kit.docc/Migration.md) article records for each boundary.
