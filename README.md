# HL7v2Kit

A Swift package for parsing, building and validating HL7 v2.x messages. It parses a message
into a version-agnostic tree and serialises it back byte for byte, reads it by path
(`message["PID-5.1"]`) or through 188 code-generated typed segments, builds messages and
acknowledgements, and validates against the grammar each supported version prints: fields,
components, code tables and message structures, each rule cited to the standard. An
Australian profile (the ADRM-2021 `HL7au` rules) layers on top. Foundation only, no runtime
dependencies, strict concurrency throughout. Maintained by one person; what you can rely on
is set out in [SUPPORT.md](SUPPORT.md).

## Requirements

- Swift 6.0 or later for the library; Swift 6.2 (Xcode 26) for the test suite, which uses
  exit tests.
- macOS 12 or later. Linux is built and tested in CI (the `swift:6.2-jammy` image).

## Install

Add the package to your `Package.swift`:

```swift
.package(url: "https://github.com/mickpah/HL7v2Kit", from: "3.17.0")
```

Then add `"HL7v2Kit"` to your target's `dependencies`.

## Quickstart

`Examples/QuickStart/main.swift` takes one synthetic ORU^R01 through the package; `swift run QuickStart` from the repository root prints what each step finds. The key lines, quoted from it:

```swift
import HL7v2Kit

let message = try Parser().parse(wire)

// Path lookups work for any field of any segment.
print("PID-5.1 family name: \(message["PID-5.1"] ?? "-")")
// Typed accessors cover the segments HL7v2Kit generates structs for.
let givenName = message.firstSegment(PID.self)?.patientName?.givenName

let report = Validator(options: .default).validate(message)
let auReport = Validator(options: .strict, locale: .auLocalisation).validate(message)

let roundTripped = message.serialize() == wire

let ack = try MessageBuilder.acknowledgment(
    to: message,
    code: .applicationAccept,
    messageControlID: "SYN-ACK-0001",
    dateTime: "20260101120005+1000"
)
```

The program builds `wire` from the message's segments, prints each validation issue with its severity, code, location and message, and exits non-zero if the round trip fails. [Getting Started](Sources/HL7v2Kit/HL7v2Kit.docc/GettingStarted.md) shows its output.

## What it validates

Segments, fields, components and subcomponents against each version's printed grammar, the
HL7 code tables, escapes and encoding, message structures and batches, plus the AU layer.
Each check has an issue code and an option that governs it; what is not checked, and why, is
listed too. All of it is on one page: the [Validation](Sources/HL7v2Kit/HL7v2Kit.docc/Validation.md) article.

## Versions and the AU profile

- **Seven versions:** v2.3, v2.3.1, v2.4, v2.5.1, v2.6, v2.7.1 and v2.8.2, read from MSH-12. A
  bare `2.7` or `2.8` is validated against v2.7.1 or v2.8.2 with an information issue; any
  other version falls back to v2.5.1 with a warning
  ([ADR-018](docs/design/architecture-decisions.md#adr-018-supported-version-set)).
- **Segments:** all 188 segments the seven versions define, modelled on every version that
  defines them.
- **Message structures:** 1,190 modelled from each version's print and 183 registered with
  the reason the print gives no checkable syntax (counts written by the extractor into
  `Resources/structures/completeness.json`). The check reports warnings in `.default`,
  errors in `.strict` and is off in `.lenient`.
- **AU profile:** `HL7Locale.auLocalisation` applies the ADRM-2021 rules; of its 263
  conformance points, 79 are shipped, 17 partial and 5 registered; the rest are enforced by
  the base model, withdrawn, receiver behaviour or out of scope for a message validator
  (`docs/design/m6-adrm-2021-conformance-register.md`, generated). See the
  [Australian localisation](Sources/HL7v2Kit/HL7v2Kit.docc/AustralianLocalisation.md) article.

## Documentation

- The DocC catalogue, published at
  <https://mickpah.github.io/HL7v2Kit/documentation/hl7v2kit/> (live after the first push),
  with its source in [`Sources/HL7v2Kit/HL7v2Kit.docc/`](Sources/HL7v2Kit/HL7v2Kit.docc/HL7v2Kit.md)
  (Getting Started, Validation, Typed Segments, Adding a Segment, Migration and others);
  build it locally with Xcode's Build Documentation.
- The design records: [`docs/design/README.md`](docs/design/README.md) (the reading order and
  the four project requirements), the
  [permanent-limitations register](docs/design/permanent-limitations-register.md) and the
  [architecture decisions](docs/design/architecture-decisions.md).
- [CHANGELOG.md](CHANGELOG.md) for what changed in each release.

## Support and contributions

- Support: [SUPPORT.md](SUPPORT.md) sets out what is promised and what is not.
- Contributions are not accepted at this stage; bug reports and spec-reading disagreements
  are welcome as issues ([CONTRIBUTING.md](CONTRIBUTING.md)).
- Security: report privately as [SECURITY.md](SECURITY.md) describes, never in a public issue.

## Licence

Apache 2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE). The tables, data types, segment
definitions and message structures under `Resources/` are derived from the HL7 v2.x standard
and the HL7 Australia ADRM 2021.1; `NOTICE` says which and how.
