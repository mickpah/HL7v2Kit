# Typed Segments

How to read a v2 message via compile-time-checked segment / field accessors instead of (or alongside) path strings.

## Overview

HL7v2Kit ships typed Swift structs for the most common HL7 v2.5.1 segments. These are **generated** from JSON schemas under `Resources/schemas/v2.5.1/` by the `HL7v2KitCodegen` executable (per `ADR-004`); the generated Swift lives at `Sources/HL7v2Kit/Segment/Generated/` (one file per segment, version-agnostic names) and is committed to the repository so reviewers can see exactly what the typed surface is. The struct surface is shared across every supported HL7 v2 version — older wires (v2.3 / v2.3.1 / v2.4) get nil from any accessor whose field doesn't exist at their version. Per-version `SegmentGrammar+vX_Y_Z.swift` tables (also at `Generated/`) carry the per-version field sets that the `Validator` dispatches on.

**188 typed segments ship today**, each at its version's full field depth — the ADT/ORU core
(`MSH`, `PID`, `OBX`, `OBR`, …), orders and pharmacy, scheduling, financial, master files,
personnel management, clinical trials, lab automation, the query family, and the batch
envelopes (`BHS`/`FHS`/`BTS`/`FTS`). The authoritative list is the schema directory
(`Resources/schemas/v2.5.1/` — one JSON file per segment), and every schema is verified
against its version's own attribute table by `scripts/audit-schemas.py` (depth *and*
presence). On v2.3 / v2.3.1 / v2.4 **no segment the spec defines is missing**; v2.6 / v2.8.2
grammar coverage is deliberately partial (see `docs/design/deferred-coverage-backlog.md`).

Segments outside this list parse as ``UnknownSegment`` and remain accessible via path strings — see <doc:#Unknown-segments> below.

## Reading a typed segment

```swift
let message = try Parser().parse(bytes)
guard let pid = message.firstSegment(PID.self) else { return }

// Scalar accessors return String?
let setID = pid.setID                                     // "1"
let dob = pid.dateTimeOfBirth                             // "19800101"
let sex = pid.administrativeSex                           // "M"

// Typed composite (XPN / CX / XAD) accessors return a struct view with named accessors.
let name = pid.patientName                                // XPN? (typed composite view)
let familyName = name?.familyName                         // "Smith"
let givenName = name?.givenName                           // "John"

// Other structured HL7 data types still return Field? — drill in by hand.
let race = pid.race                                       // Field? (CE)
let raceCode = race?.first?.components[0].stringValue
```

The accessor's return type encodes the field's HL7 datatype:

- **`String?`** for scalar HL7 datatypes (`SI`, `ID`, `IS`, `ST`, `NM`, `DT`, `TM`, `TS`, `FT`, `GTS`, `TX`, `DTM`). Returns the rendered first-subcomponent value if the field is single-everything-the-way-down; nil if absent.
- **A typed composite struct** for every HL7 v2.5.1 composite datatype the typed-segment surface uses: `XPN?` / `CX?` / `XAD?`; `CE?` / `CWE?`; `EI?` / `XCN?` / `XTN?`; `HD?` / `MSG?` / `PT?` / `VID?` / `PL?` / `CNE?` / `XON?` / `EIP?`. Each struct exposes named accessors (`familyName`, `id`, `streetAddress`, `identifier`, `text`, `entityIdentifier`, `idNumber`, `telephoneNumber`, `namespaceID`, `messageCode`, `pointOfCare`, `organizationName`, `placerAssignedIdentifier`, …) for the most common components, plus a public `field: Field` for raw access to repetitions and unexposed components. There are no remaining "Field?-typed" structured composites on the 9 spec § 17 segments — every populated typed-segment accessor returns either a `String?` (for scalar HL7 datatypes) or a typed composite struct.

## Composite components and later-version accessors

Every component that any supported version defines has a named accessor on its composite
view, and each typed segment struct reaches every field, name and repetition through
v2.8.2 (ADR-020). The examples below are compiled in `TypedSegmentsArticleExamplesTests`.

```swift
// A named accessor for every component, and a sub-composite view by position.
let cx = pid.patientIdentifierList                        // CX?
let effective = cx?.effectiveDate                         // CX-7
let authority = cx?.component(4, as: HD.self)?.universalID

// Every repetition of a repeating field, in wire order.
let ids = pid.patientIdentifierListAll                    // [CX]

// A field a later version defines. Not version-gated: nil when OBX-29 is
// absent, otherwise whatever OBX-29 holds on the wire.
let kind = obx.observationType                            // OBX-29 (v2.8.2)

// A later version retypes a composite field: re-view it.
let coded = obx.observationIdentifier?.viewed(as: CWE.self)
```

`component(_:as:)` returns `nil` only for an absent component; a present but empty
component gives an empty view. Accessors are not gated by the message's version: each
accessor's documentation names the versions that define the field, and an accessor for a
field the declared version lacks still reads that wire position.

## Iterating multi-occurrence segments

For segments that can appear more than once (e.g. multiple `OBX` per message):

```swift
for obx in message.allSegments(OBX.self) {
    print("\(obx.observationIdentifier?.first?.components[0].stringValue ?? "") = \(obx.observationValue?.stringValue ?? "")")
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
