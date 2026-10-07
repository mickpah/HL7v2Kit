# Continuous integration

`.github/workflows/ci.yml` runs on every push to `main` and every pull request against it. Each
job proves one thing; what it cannot prove is listed at the end. `.github/workflows/docs.yml`
publishes the documentation (below).

## Jobs

| Job | Runner | What it proves |
|---|---|---|
| `test-macos` | `macos-15`, newest Xcode | The package builds and the full suite passes with the newest Xcode on the image, which must carry Swift 6.2 or later, and `swift run QuickStart` exits 0. |
| `test-linux` | `ubuntu-latest`, container `swift:6.2-jammy` | The package builds and the full suite passes on Linux with swift-corelibs Foundation. No Apple-only API is reachable from any target. `swift run QuickStart` exits 0 there too. |
| `fixture-safety` | `ubuntu-latest` | No fixture carries an AU identifier pattern; no blob in the whole history (the job checks out with `fetch-depth: 0`) carries PHI patterns or licensed content; the extractor and audit self-checks pass on their committed inputs; no tracked file carries an emoji or icon character; every `CHANGELOG.md` version heading has a compare link and every link a heading (`scripts/check-changelog-links.py`). |
| `codegen-drift` | `macos-15` | Everything under `Sources/HL7v2Kit/*/Generated/` is exactly what `scripts/regenerate-typed-segments.sh` emits from the committed JSON; the pinned struct bases and the message-structure codegen self-checks pass; the code-table extractor's self-check passes (built into `$RUNNER_TEMP`). |
| `docc` | `macos-15`, newest Xcode | The DocC catalogue builds (`xcodebuild docbuild` of the package's `HL7v2Kit` scheme) with no `warning:` line in the log: every symbol link resolves. |

## Documentation site

| Workflow | Trigger | Runner | What it does |
|---|---|---|---|
| `docs.yml` | push to `main`, `workflow_dispatch` | `macos-15`, newest Xcode, then `ubuntu-latest` | Builds the DocC archive as the `docc` job does (failing on any `warning:`), transforms it with `docc process-archive transform-for-static-hosting --hosting-base-path HL7v2Kit` into `site/`, replaces DocC's root app shell with a redirect to `/HL7v2Kit/documentation/hl7v2kit/`, and deploys `site/` with `actions/upload-pages-artifact` and `actions/deploy-pages` to the `github-pages` environment. |

GitHub Pages must be enabled in the repository settings (Pages, Source: GitHub Actions) before
the first run can deploy; until then the deploy job fails. That is a pre-push checklist item.
The site is about 72 MB. The build and transform steps run locally with no extra setup; the
deploy steps run only on GitHub. `ci-rehearsal.sh` reads `ci.yml` only, so it does not run them.

## Toolchain floor

- The library needs Swift 6.0, the manifest's tools-version. (Until P13 S2-2 the manifest also
  enabled the `StrictConcurrency` upcoming feature, which Swift 6.0 rejects in Swift 6 language
  mode as already enabled; the flag was redundant and is gone. Proved in `swift:6.0-jammy`.)
- The test suite needs Swift 6.2 (Xcode 26), because it uses exit tests
  (`#expect(processExitsWith:)`).
- Every macOS job (`test-macos`, `codegen-drift`, `docc`) first selects the newest Xcode on the
  image (`sudo xcode-select -s` on the highest-sorting `/Applications/Xcode*.app`) and prints
  `xcodebuild -version` and `swift --version`. One selection step serves all three, although
  `codegen-drift` would pass on the image's default Xcode 16.4 (Swift 6.1).
- `test-macos` then runs `scripts/check-swift-version.sh 6.2`, which fails the job by name when
  the selected Swift is older, instead of leaving a compile error in the test target to explain
  it. `macos-14` is dropped: its newest Xcode is a 16.x with Swift 6.0, too old for the suite.
- `docc` builds from a copy without `HL7v2Kit.xcworkspace`: that workspace has no scheme, and
  `xcodebuild` in the repository root picks it over the package. `xcodebuild docbuild` exits 0
  on documentation warnings, so the job greps the log for `warning:`.

## Line endings

HL7 messages end each segment with a bare CR, and the API-surface pins under
`Tests/Fixtures/APISurface/` are compared byte for byte. `.gitattributes` marks `*.hl7` and
`Tests/Fixtures/**` as `-text`, so no checkout converts them, whatever the host's
`core.autocrlf`.

## Local only

These need the licensed HL7 and ADRM PDFs under `docs/standards/`, which are not in the
repository, so no hosted job can run them. Run them on a host that has the PDFs after any change
to the schemas, the structures or the AU profile.

- `python3 scripts/check-printed-structure-ids.py`: the printed-ID guard. Every printed
  trigger and structure ID pair validates without a message-structure mismatch.
- `python3 scripts/audit-schemas.py` with its PDF-backed modes (depth and `--examples`), and
  `python3 scripts/extract-example-messages.py --check-registry`.
- `python3 scripts/sweep-adrm-prose.py [text]` and `python3 scripts/extract-adrm-conformance.py
  [text]`: the ADRM prose sweep, which looks for normative sentences outside the numbered
  conformance points, and the Appendix 5 conformance-register generator. Both read the
  `pdftotext -layout` rendering of the ADRM-2021 PDF (default `/tmp/adrm2021.txt`).

Without their input each guard stops with one line and status 1, never a traceback:
`check-printed-structure-ids.py` prints `setup failure: the licensed PDFs are not under
docs/standards (local guard only)`; the two ADRM scripts print `setup failure: <path> is absent;
render the ADRM-2021 PDF under docs/standards with pdftotext -layout first (local guard only)`.
`audit-schemas.py` skips its PDF-backed passes with a message and runs the rest.
- `bash scripts/anonymise-fixture.sh` for any new real-world-derived fixture, followed by the
  PHI scan.

Nothing a hosted job runs needs `docs/standards/`, `docs/XML-schemas/`, `/tmp/extractbin` or
`/tmp/tablesbin`. A grep of `ci.yml` and every script it reaches (21 files, following each
script name a script mentions) finds those paths only in three kinds of place: comments and
usage text; PDF-backed functions of the modules the self-checks import (`audit-schemas.py`,
`extract-example-messages.py`, `extract-message-structures.py`, `extract-datatype-prose.py`,
`extract-datatype-components.py`, `extract-vmr-table.py`, `read-v2xml-bundles.py`), which the
self-checks never call; and the PHI scanner's licensed-path patterns, which flag those paths
rather than read them. P13 S2-1 ran every step on a clean clone with none of them present, as
`scripts/ci-rehearsal.sh --hide-tmp-binaries` now does.

The history scan (`scan-fixtures-for-phi.sh --history`) does run in CI, but only because the
`fixture-safety` checkout fetches the full history; a shallow clone would scan one commit.

## Running a job's steps locally

`bash scripts/ci-rehearsal.sh` is the pre-push check. It reads `ci.yml` at `HEAD` and runs every
`run:` step, job by job and in order, each job on its own clean clone of `HEAD` (committed work
only) with a scratch `HOME`, `TMPDIR` and `RUNNER_TEMP` and a minimal environment, and prints a
pass, fail or skip line per step and a summary per job. It exits 1 if any step fails.

- macOS jobs: `DEVELOPER_DIR` is set to the newest `/Applications/Xcode*.app`, standing in for
  the "Select the newest Xcode" step, which needs `sudo` and is skipped.
- `test-linux` runs each step in its container image through Docker, or is skipped with a
  message when Docker is not running.
- `--hide-tmp-binaries` moves `/tmp/extractbin` and `/tmp/tablesbin` aside for the run and puts
  them back on exit, proving no step relies on them; `--keep` keeps the scratch directory and
  each step's log.

The scripts point `DEVELOPER_DIR` at `/Applications/Xcode.app` only when the caller has not set
it, so a job that selects another Xcode keeps it.
