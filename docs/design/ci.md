# Continuous integration

`.github/workflows/ci.yml` runs on every push to `main` and every pull request against it. Each
job proves one thing; what it cannot prove is listed at the end.

## Jobs

| Job | Runner | What it proves |
|---|---|---|
| `test-macos` | `macos-14`, `macos-15` | The package builds and the full suite passes with the runner's Xcode. |
| `test-linux` | `ubuntu-latest`, container `swift:6.2-jammy` | The package builds and the full suite passes on Linux with swift-corelibs Foundation. No Apple-only API is reachable from any target. |
| `fixture-safety` | `ubuntu-latest` | No fixture carries an AU identifier pattern; no blob in the whole history (the job checks out with `fetch-depth: 0`) carries PHI patterns or licensed content; the extractor and audit self-checks pass on their committed inputs; no tracked file carries an emoji or icon character. |
| `codegen-drift` | `macos-15` | Everything under `Sources/HL7v2Kit/*/Generated/` is exactly what `scripts/regenerate-typed-segments.sh` emits from the committed JSON; the pinned struct bases and the message-structure codegen self-checks pass; the code-table extractor's self-check passes (built into `$RUNNER_TEMP`). |

## Toolchain floor

- The library needs Swift 6.1. Swift 6.0 rejects the manifest's `StrictConcurrency` upcoming
  feature in Swift 6 language mode as already enabled; later compilers accept it silently.
- The test suite needs Swift 6.2 (Xcode 26), because it uses exit tests
  (`#expect(processExitsWith:)`).
- The `test-macos` matrix runs on each image's default Xcode. That Xcode must be 26 or later
  for the job to pass; on an older default the job fails at the test step, not the build.

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
- `python3 scripts/sweep-adrm-prose.py`: the ADRM prose sweep, which looks for normative
  sentences outside the numbered conformance points.
- `bash scripts/anonymise-fixture.sh` for any new real-world-derived fixture, followed by the
  PHI scan.

The history scan (`scan-fixtures-for-phi.sh --history`) does run in CI, but only because the
`fixture-safety` checkout fetches the full history; a shallow clone would scan one commit.

## Running a job's steps locally

Every step's shell runs unchanged on a clean clone with a scratch `HOME`, and with
`RUNNER_TEMP` set to a scratch directory for the code-table extractor. The scripts point
`DEVELOPER_DIR` at `/Applications/Xcode.app` only when the caller has not set it, so a job that
selects another Xcode keeps it. To run the Linux job:

```bash
docker run --rm -v "$PWD":/src -w /src swift:6.2-jammy swift test
```
