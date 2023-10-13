# HL7v2Kit

A native Swift package for parsing, building, and validating HL7 v2.x healthcare messages.

**Status:** v0.1.0 released 2026-06-13 — see [CHANGELOG.md](CHANGELOG.md) and [HL7v2Kit-Spec.md](docs/design/HL7v2Kit-Spec.md).

## Why use this

- **Round-trip safe.** Parse a v2 message, modify it, serialise it — bytes match.
- **Australian-aware.** Tolerant of AU Z-segments (ZAU, ZPI, ZMH, ZBR) without false negatives.
- **Two APIs, one AST.** String paths (`msg["PID-5.1"]`) for ad-hoc work, typed accessors (`msg.firstSegment(PID.self)?.patientName`) for known segments.
- **Zero runtime dependencies.** Pure Swift + Foundation. Apache 2.0.

## Quickstart

```swift
import HL7v2Kit

let wire = Data(/* ... v2 bytes ... */)
let message = try Parser().parse(wire)

// Ad-hoc path access — works for any field.
let patientFamilyName = message["PID-5.1"]

// Typed accessors — for the segments HL7v2Kit ships dictionaries for.
let pid = message.firstSegment(PID.self)
let dob = pid?.dateTimeOfBirth                     // "19800101"
let name = pid?.patientName                         // Field? (XPN composite)
let familyName = name?.first?.components[0].stringValue

// MSH-18 character set is detected on parse and re-emitted on serialize.
// UTF-8 / ASCII / 8859/1 currently supported; unrecognised declarations throw.
print(message.characterEncoding)                    // .utf8 | .ascii | .iso8859_1

// Round-trip — serialised bytes equal the input, including escape sequences
// (`\F\` `\S\` `\T\` `\R\` `\E\` `\X..\`) and the original charset.
let rebuilt = message.serialize()
assert(rebuilt == wire)
```

Typed segments currently shipped for HL7 v2.5.1 (all 9 from spec § 17): `MSH` (all 21 fields), `PID` (30 of 39), `NTE` (all 4), `AL1` (all 6), `ORC` (19 of 31), `OBX` (all 17), `OBR` (all 47), `NK1` (13 commonly-used), `PV1` (20 commonly-used). Other segment IDs (Z-segments, version-specific extras) come back as `UnknownSegment` and remain accessible via path strings.

## Installation

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/<your-org>/HL7v2Kit.git", from: "0.1.0")
```

Then add `"HL7v2Kit"` to your target's `dependencies`.

## Supported platforms

| Platform | Minimum |
|---|---|
| macOS | 12 |
| iOS | 15 |
| tvOS | 15 |
| watchOS | 8 |
| visionOS | 1 |
| Linux | Untested in CI, but no Apple-only dependencies — should work on Swift 6.0+ |

## Supported HL7 v2 versions

v2.3.1, v2.4, v2.5.1, v2.8 (dictionary support; AST is version-agnostic).

## Roadmap (v0.2+)

- Typed v2 composite data types (XPN, CX, XAD, …)
- Companion `HL7v2KitAUExtensions` package with AU Z-segment grammars
- MLLP server primitives
- Streaming parser for very large batch files

## Adding a typed segment

Typed segment structs are code-generated from JSON schemas. To add coverage for a new v2 segment:

1. Hand-curate `Resources/schemas/<version>/<SegmentID>.json` (see existing `PID.json` for the format).
2. Run `bash scripts/regenerate-typed-segments.sh` — emits the typed struct AND auto-updates the `SegmentRegistry+Generated.swift` hydration switch.
3. Add a cross-check test in `Tests/HL7v2KitTests/TypedSegmentTests.swift` — path access and typed accessor must agree.

No Swift hand-edits required — `SegmentRegistry` is itself codegen-emitted. The codegen-drift CI job will fail any PR that edits a schema but forgets the regen output.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). All fixtures must be PHI-free synthetic data — see [scripts/anonymise-fixture.swift](scripts/anonymise-fixture.swift) (not yet implemented; do not add real-world-derived fixtures until it exists).

## Licence

Apache 2.0 — see [LICENSE](LICENSE).
