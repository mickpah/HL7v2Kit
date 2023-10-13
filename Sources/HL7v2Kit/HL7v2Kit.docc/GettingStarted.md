# Getting Started

Install HL7v2Kit, parse a message, access a field, serialise it back to bytes.

## Overview

This article covers the four-step "hello v2" flow: add the dependency, parse, read, serialise. Each step is one or two lines of Swift. For deeper dives, see <doc:TypedSegments>, <doc:Validation>, and <doc:RoundTripGuarantee>.

## Install

Add HL7v2Kit to your `Package.swift`:

```swift
.package(url: "https://github.com/<your-org>/HL7v2Kit.git", from: "0.1.0")
```

Then add `"HL7v2Kit"` to your target's `dependencies`. HL7v2Kit has no transitive dependencies — Foundation only.

## Parse

```swift
import HL7v2Kit

let wire = Data(/* ...your HL7 v2 bytes... */)
let message = try Parser().parse(wire)
```

``Parser/parse(_:)-(Data)`` decodes MSH-18 to determine the character set, then structurally parses the message. Throws ``ParseError`` for structural failures (empty input, missing MSH, unsupported declared charset). See ``ParseError`` for the full case list.

## Read a field

Two equivalent ways to reach into the message:

```swift
// Ad-hoc path access — works for any field.
let familyName = message["PID-5.1"]                       // String?

// Typed accessor — for the segments HL7v2Kit ships dictionaries for.
let pid = message.firstSegment(PID.self)
let dob = pid?.dateTimeOfBirth                            // String?
let nameField = pid?.patientName                          // Field? (XPN composite)
let givenName = nameField?.first?.components[1].stringValue
```

Both reach the same AST. Path strings are good for one-off scripts; typed accessors are good for production code where you want compile-time enforcement of segment / field names. See <doc:TypedSegments>.

## Serialise

```swift
let rebuilt = message.serialize()
assert(rebuilt == wire)                                    // byte equal!
```

For messages produced by ``Parser``, the output equals the input bytes including escape sequences (``EscapeSequences``) and the originating character set (``CharacterEncoding``). See <doc:RoundTripGuarantee> for what's covered and what isn't.

## Validate

```swift
let report = Validator().validate(message)
if !report.isValid {
    for error in report.errors {
        print("\(error.location.pathDescription): \(error.message)")
    }
}
```

``Validator/validate(_:)`` is **not** `throws` — it always returns a ``ValidationReport``. ``ValidationReport/isValid`` is `true` iff no `.error`-severity issues are present. See <doc:Validation>.

## See Also

- <doc:RoundTripGuarantee>
- <doc:TypedSegments>
- <doc:Validation>
