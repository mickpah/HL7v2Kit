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
- `swiftName` — the generated Swift accessor name (lowerCamelCase, rendered from the printed element name, at most 70 characters; `scripts/audit-schemas.py` fails a name that breaks this).
  - Naming convention for the non-canonical versions. A slot whose element name matches
    the canonical v2.5.1 element at the same index takes the canonical swiftName,
    possessive "S" included (`totalOccurrenceS`). Any other slot takes the extractor's
    `deriveSwiftName` of its printed name. Canonical public names never change (ADR-014).
    A correction keeps the released name under `deprecatedSwiftNames`.
- `deprecatedSwiftNames` — optional. Names this accessor shipped under in a released version before `swiftName` corrected them. Codegen emits each as a deprecated alias that forwards to `swiftName` (ADR-014: deprecate rather than remove).
- `name` — human-readable field name (used in DocC + validation messages).
- `dataType` — the HL7 data-type code (`SI`, `ID`, `IS`, `ST`, `NM`, `DT`, `TM`, `TS`, `FT`, `XPN`, `CX`, `XAD`, `CE`, `CWE`, `EI`, `XCN`, ...).
- `optionality` — `R` (required), `O` (optional), `C` (conditional), `X` (not supported), `B` (deprecated, retained for backward compatibility), `W` (withdrawn — removed from the standard; the sequence slot is retained but carries no meaning; first used by the v2.6 attribute tables). Populated `B`, `X`, and `W` fields each raise a warning.
- `repeatability` — `"1"` (blank or N, single), `"*"` (Y, unbounded) or the printed bound as a decimal string (`"3"` for `Y/3` before v2.5, a bare `3` from v2.5), which becomes ``FieldGrammar/maxRepetitions``. Run `audit-schemas.py --depth --write-repeatability` to take it from the PDF.
- `length` — optional. The LEN cell the version's attribute table prints, verbatim (`"250"`; v2.7+ `"2..2"`, `"32="`, `"250#"`). Enforced by the Validator per era (``ValidationOptions/fieldLengthSeverity``, ``ValidationOptions/normativeLengthSeverity``; P6-6), so it must be one of the printed shapes the schema-wide `FieldLengthValidationTests` accepts. `scripts/audit-schemas.py --depth` fails on any disagreement with the spec.
- `tables` — optional. The HL7 table numbers the version's attribute table binds to the field (its TBL# column), as four-digit strings: `["0001"]`, or more than one where the spec prints several (`["0327", "0328"]`). Omit the key when the cell is blank. `scripts/audit-schemas.py --depth` fails on any disagreement with the spec.
- `condition` (optional, only meaningful when `optionality=C`) — a predicate string controlling when the field is required. See the Conditional-field DSL in <doc:Validation>. Example: `"condition": "PID-35 populated"` on `PID-36` means "breed code is required when species code is declared". A `C` field without a `condition` falls through as `.optional`.

The data-type code drives the accessor return type:

- Codes in the **scalar set** (`SI`, `ID`, `IS`, `ST`, `NM`, `DT`, `TM`, `TS`, `FT`, `GTS`, `TX`, `DTM`) emit `String?` accessors.
- Codes in the **typed-composite set** (`XPN`, `CX`, `XAD` — v0.2-C1) emit the matching Swift struct: `XPN?`, `CX?`, `XAD?`. Each struct exposes named accessors plus `field: Field` for raw access.
- Everything else emits `Field?`. The caller reaches into ``Field/repetitions`` / ``Repetition/components`` by hand.

See <doc:TypedSegments> for examples.

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
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01^ADT_A01|MSG00001|P|2.5.1\r\
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

Adding a segment's grammar means the ``Validator`` now has rules to check against. The field-level checks (required, conditional, cardinality, deprecation, length, primitive value format, code table and component grammar) all become live for the new segment with no additional code. If you populate the `condition` field on a `C`-optional entry, the predicate is evaluated automatically — see <doc:Validation> for the DSL.

## Limits

- Typed composite views ship for CE, CNE, CWE, CX, EI, EIP, HD, MSG, PL, PT, VID, XAD, XCN, XON, XPN and XTN, generated to full spec depth on every supported version (ADR-020); a typed accessor of any other composite type returns `Field?`. See <doc:TypedSegments>.
- A condition that the message cannot decide (a referenced segment or field that does not resolve, or a predicate that does not parse) does not trigger; cross-segment references are supported (ADR-008, ADR-010). See <doc:Validation>.
- Primitive value format is checked (a TS field containing `"hello"` raises ``IssueCode/valueFormatInvalid(dataType:)``); see <doc:Validation> for this and for what the validator does not check.

## See Also

- <doc:TypedSegments>
- <doc:Validation>
- `CONTRIBUTING.md` (repository root)
