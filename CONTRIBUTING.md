# Contributing to HL7v2Kit

**Contributions are not accepted at this stage of the project.**

Pull requests will be closed unread. This is a statement about the project's stage, not
about your work: HL7v2Kit is maintained by one person, its design is still moving, and
reviewing outside changes costs more than it returns right now. `SUPPORT.md` sets out
exactly what the project does and does not promise; this file follows it.

If that changes, this file and `SUPPORT.md` will say so first.

## What is welcome

- **Bug reports**, as issues. Include the version, platform, a minimal reproduction, and
  expected versus actual behaviour. Reports without a reproduction may be closed without
  investigation.
- **Spec-reading disagreements.** The package aims to be a faithful rendering of the
  HL7 v2 standard. If a schema, table, rule or message structure disagrees with the print,
  open an issue citing the version, chapter, section and page. These are the most useful
  reports the project can receive.
- **Fork announcements.** The licence lets you fork without asking. If your fork is
  clearly active, open an issue titled "Fork: <url>" and it will be linked from
  `README.md` when the maintainer next looks.
- **Security reports.** Privately, through GitHub's private vulnerability reporting (the
  repository's Security tab), not as a public issue. A report will be acknowledged within 14 days.
  `SECURITY.md` has the details.

## Working on a fork

The repository's own working rules, for anyone building on it:

1. **No PHI in fixtures.** Ever. Every fixture is synthetic. `scripts/scan-fixtures-for-phi.sh`
   is a hard gate in CI, and every fixture has a row in `Tests/Fixtures/README.md`.
2. **Round-trip safety.** Parse then serialise is byte-identical on every accepted fixture.
   A change that breaks that is wrong, not the test.
3. **No runtime dependencies.** Foundation only; `Package.swift` `dependencies` stays empty.
   Swift Testing is bundled with the Swift 6 toolchain.
4. **Generated code is never hand-edited.** Everything under a `Generated/` directory and
   the extractor output under `Resources/` is produced by `HL7v2KitCodegen` and the scripts
   under `scripts/`. Edit the schema JSON or an override, cited to the print, and run
   `bash scripts/regenerate-typed-segments.sh`. CI fails on drift.
5. **Defensible against the print.** Every schema field, table, condition and structure
   carries a citation to the standard. Nothing ships if it is known to misfire on a
   spec-compliant message; a gap the model cannot express is registered
   (the Validation article lists them) rather than papered over.

The four project requirements and the reading order for the design records are in
`docs/design/architecture-decisions.md`. Before pushing, `bash scripts/ci-rehearsal.sh` runs every CI step on a
clean clone of `HEAD` (the Linux job through Docker).

## Licence

Apache 2.0, see `LICENSE` and `NOTICE`. It applies to every release and lets you fork, vendor or build
on any version without asking.
