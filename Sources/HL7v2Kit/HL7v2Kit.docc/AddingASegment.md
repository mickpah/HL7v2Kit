# Adding a Typed Segment

The three-step workflow for adding compile-time-checked support for a v2 segment HL7v2Kit doesn't ship yet.

## Overview

Typed segments come from a JSON schema + a codegen step (per `ADR-004`). Adding a new typed segment is a 3-step contributor workflow — no Swift to hand-write.

## Step 1: Write the schema

Drop a file under `Resources/schemas/<version>/<SegmentID>.json`. Copy an existing schema such as `PID.json` as a template. Each field needs:

```json
{
  "index": 5,
  "swiftName": "patientName",
  "name": "Patient Name",
  "dataType": "XPN",
  "optionality": "R",
  "repeatability": "*"
}
```

- `index` — 1-based HL7 v2 field number.
- `swiftName` — the generated Swift accessor name (camelCase).
- `name` — human-readable field name (used in DocC + validation messages).
- `dataType` — the HL7 data-type code (`SI`, `ID`, `IS`, `ST`, `NM`, `DT`, `TM`, `TS`, `FT`, `XPN`, `CX`, `XAD`, `CE`, `CWE`, `EI`, `XCN`, ...).
- `optionality` — `R` (required), `O` (optional), `C` (conditional), `X` (not supported), `B` (deprecated).
- `repeatability` — `"1"` (single) or `"*"` (multiple).

The data-type code drives the accessor return type: codes in the scalar set (`SI`, `ID`, `IS`, `ST`, `NM`, `DT`, `TM`, `TS`, `FT`, `GTS`, `TX`, `DTM`) emit `String?` accessors; everything else emits `Field?`. See <doc:TypedSegments>.

## Step 2: Regenerate

From the repo root:

```bash
bash scripts/regenerate-typed-segments.sh
```

This emits three things:

- `Sources/HL7v2Kit/Segment/Generated/<versionDir>/<SegmentID>.swift` — the typed struct with `field(_:)`-based accessors.
- `Sources/HL7v2Kit/Segment/Generated/SegmentRegistry+Generated.swift` — updated to register the new segment with `Parser`.
- `Sources/HL7v2Kit/Segment/Generated/SegmentGrammar+<versionDir>.swift` — updated to include the new segment's grammar for `Validator`.

All three files are committed to the repository. The codegen output is reproducible — two consecutive `regenerate-typed-segments.sh` runs produce byte-identical output.

## Step 3: Add a cross-check test

In `Tests/HL7v2KitTests/TypedSegmentTests.swift`, add a test that exercises the new segment's accessors against the path-string API. Architecture invariant 6 requires both APIs to return the same value for the same field:

```swift
@Test("Segment-X hydration and cross-check")
func segmentXCrossCheck() throws {
    let wire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01|MSG00001|P|2.5.1\r\
    XYZ|1|some-value\r
    """
    let message = try Parser().parse(wire)
    let xyz = try #require(message.firstSegment(XYZ.self))
    #expect(xyz.setID == "1")
    #expect(xyz.setID == message["XYZ-1"])
}
```

For wires populating > ~10 fields, add a comment block listing each populated field index and value — this is how we caught pipe-counting bugs in the OBR and PID extension work.

## CI safety net

The `codegen-drift` GitHub Actions job runs `regenerate-typed-segments.sh` and fails the build on any non-empty `git diff` under `Sources/HL7v2Kit/Segment/Generated/`. A contributor who edits a schema but forgets to regenerate is structurally caught at PR time.

## What gets validated automatically

Adding a segment's grammar means the ``Validator`` now has rules to check against. The required-field, cardinality, and deprecation checks all become live for the new segment with no additional code.

## Limits

- HL7v2Kit doesn't yet ship typed composite data-types (e.g. an `XPN` Swift struct with named `family` / `given` properties). Structured fields stay at `Field?` for v0.1.0. See spec § 4.5.
- Conditional (`C`) optionality is treated as `O` (optional) for the required-field check. v0.1.0 doesn't evaluate the condition because that requires cross-field rules.

## See Also

- <doc:TypedSegments>
- <doc:Validation>
- `CONTRIBUTING.md` (repository root)
