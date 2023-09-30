# Contributing to HL7v2Kit

Thanks for considering a contribution. This file covers what you need to know.

## Ground rules

1. **No PHI in fixtures.** Ever. Every fixture is synthetic. The PHI scan job in CI (`scripts/scan-fixtures-for-phi.sh`) is a hard gate. The anonymisation script (`scripts/anonymise-fixture.swift`) is not yet implemented — until it lands, do not add fixtures that came from real-world sources.
2. **Round-trip safety is sacred.** If a change breaks parse → serialise byte equality on any accepted fixture, the change is wrong, not the test.
3. **Public API additions need a CHANGELOG entry.** Public API changes need a major-version bump (pre-1.0: a minor-version bump, with a clear note).
4. **No runtime dependencies.** Swift Testing is bundled with the Swift 6 toolchain and is the only test dependency. The package's `Package.swift` `dependencies` array must remain empty.
5. **Don't hand-edit `Sources/HL7v2Kit/Segment/Generated/`.** Those files are emitted by `HL7v2KitCodegen`. Edit the schema JSON under `Resources/schemas/` and regenerate.

## Development setup

```bash
git clone https://github.com/<your-org>/HL7v2Kit.git
cd HL7v2Kit
swift build
swift test
```

Required: Swift 6.0+, macOS 12+ (or Linux with a recent Swift toolchain). Running tests via `swift test` from the CLI needs a Swift Testing-aware toolchain — that ships with full Xcode 16+ but not with Command Line Tools 6.3.x. If `swift test` reports `no such module 'Testing'`, run from Xcode instead.

## Adding a typed segment

Typed segment structs are code-generated. To add a v2 segment:

1. Hand-curate `Resources/schemas/<version>/<SegmentID>.json` (use the existing `PID.json` as a template — each field needs `index`, `swiftName`, `name`, `dataType`, `optionality`, `repeatability`).
2. Run `bash scripts/regenerate-typed-segments.sh`. Commit both the schema JSON and the regenerated `Sources/HL7v2Kit/Segment/Generated/<version>/<SegmentID>.swift`.
3. Add a `case <X>.segmentID: return .typed(AnyTypedSegment(<X>(fields: unknown.fields)))` line to `Sources/HL7v2Kit/Segment/SegmentRegistry.swift`.
4. Add a cross-check test in `Tests/HL7v2KitTests/TypedSegmentTests.swift`: every field exposed via the typed accessor must agree with the matching path string for at least one synthetic fixture.

The codegen-drift CI job fails any PR that edits a schema without committing the regenerated output.

## Code style

- Public API has DocC comments.
- All public types are `Sendable`.
- Errors are enums with associated values, conforming to `Equatable` and `Sendable`.
- No runtime dependencies (Foundation only).
- The portable-kernel files under `Sources/HL7v2Kit/` carry a `// PORTABLE KERNEL` header (see `add-kernel-headers.sh`). Those files must stay Foundation-free and byte/character-level — `Data` only at the edges. See `docs/design/ADR-006-portable-core-boundary.md`.

## Pull request checklist

- [ ] Tests added or updated.
- [ ] `swift build` and `swift test` pass locally.
- [ ] CHANGELOG.md updated under `[Unreleased]`.
- [ ] Any new fixture has an entry in `Tests/Fixtures/README.md` with provenance + anonymisation log.

## Reporting security issues

Email `security@<your-domain>` rather than filing a public issue. Triage within 14 days, patch within 30 days.

## Licence

By contributing, you agree your contribution is licensed under Apache 2.0.
