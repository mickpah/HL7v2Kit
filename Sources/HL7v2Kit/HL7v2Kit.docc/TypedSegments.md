# Typed Segments

How to read a v2 message via compile-time-checked segment / field accessors instead of (or alongside) path strings.

## Overview

HL7v2Kit ships typed Swift structs for the most common HL7 v2.5.1 segments. These are **generated** from JSON schemas under `Resources/schemas/v2.5.1/` by the `HL7v2KitCodegen` executable (per `ADR-004`); the generated Swift lives under `Sources/HL7v2Kit/Segment/Generated/v2_5_1/` and is committed to the repository so reviewers can see exactly what the typed surface is.

Currently shipped typed segments for v2.5.1:

- `MSH` (all 21 fields)
- `PID` (30 of 39 fields)
- `NTE` (all 4)
- `AL1` (all 6)
- `ORC` (19 of 31)
- `OBX` (all 17)
- `OBR` (all 47)
- `NK1` (13 commonly-used)
- `PV1` (20 commonly-used)

Segments outside this list parse as ``UnknownSegment`` and remain accessible via path strings — see <doc:#Unknown-Segments> below.

## Reading a typed segment

```swift
let message = try Parser().parse(bytes)
guard let pid = message.firstSegment(PID.self) else { return }

// Scalar accessors return String?
let setID = pid.setID                                     // "1"
let dob = pid.dateTimeOfBirth                             // "19800101"
let sex = pid.administrativeSex                           // "M"

// Structured (composite) accessors return Field?
let name = pid.patientName                                // XPN field
let familyName = name?.first?.components[0].stringValue
let givenName = name?.first?.components[1].stringValue
```

The accessor's return type encodes the field's HL7 datatype:

- **`String?`** for scalar HL7 datatypes (`SI`, `ID`, `IS`, `ST`, `NM`, `DT`, `TM`, `TS`, `FT`, `GTS`, `TX`, `DTM`). Returns the rendered first-subcomponent value if the field is single-everything-the-way-down; nil if absent.
- **`Field?`** for structured HL7 datatypes (`HD`, `XPN`, `CX`, `XAD`, `CE`, `CWE`, `EI`, `XCN`, `XTN`, `PL`, `MSG`, `PT`, `VID`, ...). Returns the underlying ``Field`` — the caller reaches into ``Field/repetitions``, ``Repetition/components``, and ``Component/subcomponents`` themselves.

## Iterating multi-occurrence segments

For segments that can appear more than once (e.g. multiple `OBX` per message):

```swift
for obx in message.allSegments(OBX.self) {
    print("\(obx.observationIdentifier?.first?.components[0].stringValue ?? "") = \(obx.observationValue ?? "")")
}
```

``Message/allSegments(_:)`` returns them in document order.

## Cross-checking against path access

A typed accessor and the path subscript return the same value for the same field. This is an architecture invariant (invariant 6) and is enforced by the `TypedSegmentTests` suite:

```swift
let pid = message.firstSegment(PID.self)!
#expect(pid.setID == message["PID-1"])
#expect(pid.patientName?.first?.components[0].stringValue == message["PID-5.1"])
```

If a typed accessor disagrees with the matching path string, it's a bug — file an issue.

## Unknown segments

Z-segments and any segment outside the typed-segment list come back as ``UnknownSegment`` (wrapped in ``Segment/unknown(_:)``):

```swift
for segment in message.segments {
    if case .unknown(let unknown) = segment, unknown.segmentID == "ZAU" {
        let zau3 = message["ZAU-3"]      // path access still works
    }
}
```

This is intentional — HL7v2Kit never invents grammar for Z-segments. See `ADR-003`.

## Adding a typed segment

Contributors who need a typed segment that HL7v2Kit doesn't ship yet can add one without modifying any Swift by hand. See <doc:AddingASegment>.

## See Also

- <doc:GettingStarted>
- <doc:Validation>
- ``Message``
- ``Segment``
