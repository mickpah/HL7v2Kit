# Getting Started

Install HL7v2Kit, parse a message, access a field, serialise it back to bytes.

## Overview

The repository's example program, `Examples/QuickStart/main.swift`, takes one synthetic ORU^R01 through every step: parse, read, validate, round-trip and acknowledge. Run it from the repository root:

```
swift run QuickStart
```

The code below is quoted from it. For deeper dives, see <doc:TypedSegments>, <doc:Validation> and <doc:RoundTripGuarantee>.

## Install

Add HL7v2Kit to your `Package.swift`:

```swift
.package(url: "https://github.com/mickpah/HL7v2Kit.git", from: "3.16.0")
```

Then add `"HL7v2Kit"` to your target's `dependencies`. HL7v2Kit has no transitive dependencies; Foundation only.

## Parse

```swift
/// HL7 v2 ends every segment with a carriage return.
let wire = Data((segments.joined(separator: "\r") + "\r").utf8)

let message = try Parser().parse(wire)
```

``Parser/parse(_:)-(Data)`` decodes MSH-18 to determine the character set, then structurally parses the message. It throws ``ParseError`` for structural failures (empty input, missing MSH, unsupported declared charset).

## Read a field

```swift
// Path lookups work for any field of any segment.
print("PID-5.1 family name: \(message["PID-5.1"] ?? "-")")
print("OBX-5 result value:  \(message["OBX-5"] ?? "-")")
// Typed accessors cover the segments HL7v2Kit generates structs for.
let givenName = message.firstSegment(PID.self)?.patientName?.givenName
```

Both reach the same AST. Path strings suit one-off scripts; typed accessors give compile-time checking of segment and field names. See <doc:TypedSegments>.

## Validate

```swift
let report = Validator(options: .default).validate(message)
let auReport = Validator(options: .strict, locale: .auLocalisation).validate(message)
```

``Validator/validate(_:)`` does not throw: it always returns a ``ValidationReport``, and ``ValidationReport/isValid`` is `true` when no issue has `.error` severity. The program prints each issue with its ``ValidationIssue/severity``, ``ValidationIssue/code``, ``ValidationIssue/location`` and ``ValidationIssue/message``. The second report layers the Australian profile (<doc:AustralianLocalisation>) and the ``ValidationOptions/strict`` preset over the same message. What each check covers, and what none does, is in <doc:Validation>.

## Serialise

```swift
let roundTripped = message.serialize() == wire
```

For messages produced by ``Parser``, the output equals the input bytes, escape sequences (<doc:EscapeSequences>) and the originating character set (``CharacterEncoding``) included. The program exits non-zero if they differ. See <doc:RoundTripGuarantee>.

## Acknowledge

```swift
let ack = try MessageBuilder.acknowledgment(
    to: message,
    code: .applicationAccept,
    messageControlID: "SYN-ACK-0001",
    dateTime: "20260101120005+1000"
)
```

The caller chooses the ``AcknowledgmentCode``; the builder echoes MSH-10 into MSA-2 and swaps the sending and receiving addresses.

## What you should see

PID-7 is written as `1980-01-01` on purpose, so the default run has one warning to show:

```
== Read
PID-5.1 family name: Synthetic
OBX-5 result value:  140
PID typed given name: Alex

== Validate (ValidationOptions.default, international rules)
valid: true, 0 error(s), 1 warning(s), 0 info
  warning (1)
    warning valueFormatInvalid(dataType: "TS") at PID[1]-7: PID[1]-7 repetition 1 value "1980-01-01" does not match the v2.4 TS format

== Validate (ValidationOptions.strict, HL7Locale.auLocalisation)
valid: false, 16 error(s), 1 warning(s), 0 info
issues: 1 under default, 17 here (16 more)

== Round trip
serialised bytes match the input: true

== Acknowledgment
MSH|^~\&|SYNTH_EMR|SYNTH_CLINIC|SYNTH_LAB|SYNTH_PATH|20260101120005+1000||ACK^R01^ACK|SYN-ACK-0001|P|2.4
MSA|AA|SYN-MSG-0001
```

The sixteen AU errors are ADRM-2021 rules a plain v2.4 message does not meet, on MSH-12, MSH-15, MSH-16, MSH-17, MSH-19, OBR-2, OBR-3 and the OBR segment.

## See Also

- <doc:RoundTripGuarantee>
- <doc:TypedSegments>
- <doc:Validation>
- <doc:AustralianLocalisation>
