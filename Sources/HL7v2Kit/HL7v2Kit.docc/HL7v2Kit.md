# ``HL7v2Kit``

A round-trip-safe HL7 v2.x parser, builder, and validator for Swift.

## Overview

HL7v2Kit is the foundational parsing layer for AU Core Workbench (a macOS application for Australian healthcare integration engineers). It is designed to be useful to anyone shipping a Swift app that talks HL7 v2.x — clinical, lab, pathology, mental-health, admin/billing.

The library has four pillars:

- **Round-trip safety.** `Parser.parse(data).serialize() == data` for every fixture the parser accepts. See <doc:RoundTripGuarantee>.
- **Two access APIs over one AST.** Path strings (`msg["PID-5.1"]`) for ad-hoc work and typed accessors (`msg.firstSegment(PID.self)?.patientName`) for known segments. See <doc:TypedSegments>.
- **Z-segment tolerance by default.** Real AU clinical traffic uses bespoke Z-segments; HL7v2Kit accepts them without inventing semantics. See ``ZSegmentPolicy``.
- **Zero external dependencies.** Foundation only at runtime. Apache 2.0 licensed.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:RoundTripGuarantee>
- <doc:TypedSegments>

### Validation and conformance

- <doc:Validation>
- <doc:CharacterEncodingGuide>
- <doc:EscapeSequences>

### Contributing

- <doc:AddingASegment>

### Future

- <doc:Migration>

### Core types

- ``Message``
- ``Parser``
- ``Validator``

### Parser surface

- ``ParserOptions``
- ``ParseError``
- ``LineTerminatorPolicy``

### Validator surface

- ``ValidationOptions``
- ``ValidationReport``
- ``ValidationIssue``
- ``IssueSeverity``
- ``IssueLocation``
- ``IssueCode``
- ``ZSegmentPolicy``

### AST nodes

- ``Field``
- ``Repetition``
- ``Component``
- ``Subcomponent``

### Segments

- ``Segment``
- ``TypedSegment``
- ``AnyTypedSegment``
- ``UnknownSegment``

### Encoding

- ``EncodingCharacters``
- ``CharacterEncoding``

### Versioning

- ``Version``
