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
- **Cardinality check.** Fields declared `repeatability=1` carrying multiple `~`-separated repetitions produce ``IssueCode/cardinalityExceeded`` errors.
- **Deprecation warning.** Fields with optionality `B` (backward-compat) or `X` (not-supported) that are populated produce ``IssueCode/fieldNotSupported`` warnings (severity `.warning`, not `.error`).

For each segment whose ID is **not** in the loaded grammar table:

- **Z-segment policy.** ``ZSegmentPolicy/ignore`` produces no issue. ``ZSegmentPolicy/warnPresence`` produces a `.info`-severity ``IssueCode/zSegmentPresent`` issue per occurrence. ``ZSegmentPolicy/reject`` produces a `.error`-severity issue per occurrence (making the report invalid).

## Presets

Three presets cover the common configurations:

```swift
Validator(options: .default)    // grammar checks on, Z-segments silently tolerated
Validator(options: .strict)     // grammar checks on, Z-segments rejected as errors
Validator(options: .lenient)    // only required-field check; no cardinality, no warnings, no Z policy
```

``ValidationOptions/default`` is appropriate for AU clinical inbound traffic where Z-segments are routine and you want grammar conformance flagged. ``ValidationOptions/strict`` is appropriate for outgoing-message validation where you control every segment. ``ValidationOptions/lenient`` is for "would HL7v2Kit be happy serialising this back?" round-trip pre-check.

## Custom configurations

The four knobs are independently toggleable:

```swift
let options = ValidationOptions(
    zSegmentPolicy: .warnPresence,           // info per Z-segment
    checkRequiredFields: true,
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

## What the validator does not check

- **Component-level grammar.** v0.1.0 only checks field-level rules. Component cardinality (e.g. XPN's family-name component being non-empty) is v0.2 work.
- **Cross-field conditions.** Fields with optionality `C` (conditional) require evaluating a condition based on other fields' values. v0.1.0 treats `C` as `O` for required-field purposes.
- **Field-level type conformance.** A TS field carrying `"hello"` is not a well-formed timestamp, but the validator doesn't currently check that. v0.2 work.

## See Also

- <doc:GettingStarted>
- ``Validator``
- ``ValidationReport``
- ``ValidationOptions``
- ``ValidationIssue``
- ``ZSegmentPolicy``
