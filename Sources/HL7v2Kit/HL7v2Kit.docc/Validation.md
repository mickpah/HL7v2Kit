# Validation

Check a parsed message against per-segment grammar rules without throwing.

## Overview

``Validator`` runs grammar checks against a ``Message`` and returns a ``ValidationReport``. It is **never** `throws` — the type signature pins that contract. The validator complements ``Parser``: parsing is fatal (structural failure throws), validation is non-fatal (grammar violations get collected). See `ADR-002`.

```swift
let message = try Parser().parse(bytes)
let report = Validator().validate(message)

if !report.isValid {
    for error in report.errors {
        print("\(error.location.pathDescription): \(error.message)")
    }
}
```

``ValidationReport/isValid`` is `true` iff there are zero `.error`-severity issues. Warnings and infos don't make a report invalid.

## What the validator checks

For each segment whose ID is in the loaded grammar table (currently HL7 v2.5.1 only), and for each field within that segment:

- **Required-field check.** Fields with optionality `R` that are absent or empty produce ``IssueCode/requiredFieldMissing`` errors.
- **Conditional-field check.** Fields with optionality `C` carrying a ``FieldGrammar/condition`` predicate are evaluated: if the predicate triggers and the field is empty, the validator produces an ``IssueCode/conditionalFieldMissing`` error. C fields with no condition behave as `O` — backward compatible. See <doc:#Conditional-field-DSL> below for the predicate grammar.
- **Component-grammar check.** When a populated field uses a composite data type HL7v2Kit ships typed metadata for (XPN / CX / XAD), required sub-components are enforced. PID-5 (XPN) populated without an XPN-1 family name produces ``IssueCode/requiredComponentMissing`` at `PID[1]-5.1`; PID-3 (CX) populated without an ID number produces it at `PID[1]-3.1`; PID-11 (XAD) populated without a street address produces it at `PID[1]-11.1`. Each typed composite carries its own `static let requiredComponents` (see ``XPN``, ``CX``, ``XAD``). Composites HL7v2Kit hasn't typed yet (CE / CWE / EI / XCN / ...) skip silently — they can be promoted incrementally. v0.2-V2.
- **Cardinality check.** Fields declared `repeatability=1` carrying multiple `~`-separated repetitions produce ``IssueCode/cardinalityExceeded`` errors.
- **Deprecation warning.** Fields with optionality `B` (backward-compat) or `X` (not-supported) that are populated produce ``IssueCode/fieldNotSupported`` warnings (severity `.warning`, not `.error`).
- **Code-table check.** A populated `ID` field bound to a closed HL7-defined table must carry one of that table's codes, as printed by the message's own HL7 version; otherwise ``IssueCode/valueNotInTable(table:)`` is an error. A table is closed when it is HL7-defined, permits no local extensions, and has rows (``HL7Table/isClosed``). `IS` fields and user-defined tables are never enforced, and neither are empty or HL7-null (`""`) values. Under a localisation, the locale's own rendering of the table is consulted before an error is raised, so a locale can widen a table and never narrows it: AU ADRM-2021 back-ports `UNICODE UTF-8` into v2.4 Table 0211. Turn the check off with ``ValidationOptions/checkCodeTables``. Look tables up with ``HL7TableRegistry``.

For each segment whose ID is **not** in the loaded grammar table:

- **Z-segment policy.** ``ZSegmentPolicy/ignore`` produces no issue. ``ZSegmentPolicy/warnPresence`` produces a `.info`-severity ``IssueCode/zSegmentPresent`` issue per occurrence. ``ZSegmentPolicy/reject`` produces a `.error`-severity issue per occurrence (making the report invalid).

## Presets

Three presets cover the common configurations:

```swift
Validator(options: .default)    // grammar + conditional checks on, Z-segments silently tolerated
Validator(options: .strict)     // grammar + conditional checks on, Z-segments rejected as errors
Validator(options: .lenient)    // only required-field check; no conditional, no cardinality, no code tables, no warnings, no Z policy
```

``ValidationOptions/default`` is appropriate for AU clinical inbound traffic where Z-segments are routine and you want grammar conformance flagged. ``ValidationOptions/strict`` is appropriate for outgoing-message validation where you control every segment. ``ValidationOptions/lenient`` is for "would HL7v2Kit be happy serialising this back?" round-trip pre-check.

## Custom configurations

The six knobs are independently toggleable:

```swift
let options = ValidationOptions(
    zSegmentPolicy: .warnPresence,           // info per Z-segment
    checkRequiredFields: true,
    checkConditionalFields: false,           // skip predicate evaluation on C fields
    checkComponentGrammar: false,            // skip XPN-1 / CX-1 / XAD-1 required-component checks
    checkCardinality: false,                 // ignore single-cardinality violations
    warnDeprecatedFields: false              // don't warn on populated B/X fields
)
```

## Filtering issues

```swift
let report = Validator().validate(message)

let errors = report.errors                    // [ValidationIssue] of severity .error
let warnings = report.warnings                // [ValidationIssue] of severity .warning
let infos = report.infos                      // [ValidationIssue] of severity .info

// Filter by code:
let missingFields = report.issues.filter { $0.code == .requiredFieldMissing }

// Filter by segment:
let pidIssues = report.issues.filter { $0.location.segmentID == "PID" }
```

## Issue anatomy

Each ``ValidationIssue`` carries:

- ``ValidationIssue/severity`` — ``IssueSeverity/info``, ``IssueSeverity/warning``, or ``IssueSeverity/error``.
- ``ValidationIssue/code`` — the categorical ``IssueCode``.
- ``ValidationIssue/location`` — an ``IssueLocation`` with the 3-character `segmentID`, the 1-based `segmentIndex` (which occurrence of that segment in document order), and an optional 1-based `fieldIndex`. `location.pathDescription` renders as `"PID[1]-3"` for segment-and-field issues, `"ZAU[1]"` for segment-level issues.
- ``ValidationIssue/message`` — a human-readable summary suitable for logging or UI display.

## Conditional-field DSL

The condition predicate carried on ``FieldGrammar/condition`` is a short string with grammar:

```
<segmentID>-<fieldIndex> <predicate>
<predicate> := "populated" | "empty" | "= <value>" | "!= <value>"
```

Examples:

```
"PID-35 populated"     // ships on PID-36 — breed required when species declared
"ORC-1 = NW"           // hypothetical — would fire when ORC-1 is "NW"
"PV1-2 != I"           // hypothetical — would fire when patient class isn't inpatient
```

Semantics:

- **Same-segment only** in the current release. The referenced segment ID must match the segment whose field carries the condition; cross-segment references silently evaluate to `false` (no-trigger). Cross-segment predicates may be revisited if a real condition needs them.
- **`populated` / `empty`** use the same any-subcomponent-non-empty rule as the required-field check — works for both scalar fields and composites.
- **`= value` / `!= value`** compare against the first-subcomponent-of-first-component-of-first-repetition "scalar view" of the referent — sufficient for ID/IS/ST/NM-typed fields.
- **Malformed predicates fail safe.** Any predicate the evaluator can't parse evaluates to `false` (no-trigger), so a schema typo can never make a previously-accepted message non-conformant.
- **C fields without a `condition`** behave as `O` — backward compatible. A schema can carry a C field with no predicate for years and never produce a conditional error.

Conditions live in the per-segment JSON schemas under `Resources/schemas/<version>/` and are emitted into the codegen-produced ``SegmentGrammarTable``. To add a condition to a field, edit the schema and run `bash scripts/regenerate-typed-segments.sh`. See <doc:AddingASegment>.

## What the validator does not check

- **Code tables on composite components.** The code-table check works at field level on `ID` fields. Tables bound to a component (`CX.5` identifier type, `CE.3` coding system) and fields whose TBL# cell names several tables are recorded but not enforced (ADR-016).
- **Component grammar for untyped composites.** XPN / CX / XAD enforce their `requiredComponents`; the other composites (CE / CWE / EI / XCN / HD / MSG / PT / VID / XTN / PL / CNE / XON / EIP) still skip silently because HL7v2Kit doesn't ship typed metadata for them yet. Each can be promoted incrementally — add a `static let requiredComponents: [RequiredComponent]` and extend `Validator.requiredComponents(forCompositeCode:)`.
- **Field-level type conformance.** A TS field carrying `"hello"` is not a well-formed timestamp, but the validator doesn't currently check that. Tracked for a future release.
- **Cross-segment conditional predicates.** Same-segment refs only at present; see <doc:#Conditional-field-DSL>.

## See Also

- <doc:GettingStarted>
- ``Validator``
- ``ValidationReport``
- ``ValidationOptions``
- ``ValidationIssue``
- ``ZSegmentPolicy``
