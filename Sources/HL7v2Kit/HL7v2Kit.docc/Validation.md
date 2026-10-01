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
- **Component-grammar check.** When a populated field has a composite datatype, every component that the component table of the MESSAGE'S OWN version prints as `R` must be populated; otherwise ``IssueCode/requiredComponentMissing`` is an error at that component (`PID[1]-3.1` for a `CX` with no ID number). The requirements differ by version and the check follows them: `CX.5` and `PT.1` are optional in v2.5.1 and required in v2.8.2; all three `MSG` components, the message structure in `MSH-9.3` included, are required from v2.5. Components printed `O`, such as `XAD.1` street address or `XPN.1` family name, are never required. v2.3 to v2.4 print no component optionality, so nothing is required of them. The severity is the consumer's choice: ``ValidationOptions/requiredComponentSeverity`` defaults to `.error` and can be set to `.warning`, which keeps every finding but leaves the report valid; use it for feeds that omit `MSH-9.3`, which v2.5+ prints as required and half the specification's own examples omit. Components the spec prints as conditional are checked where its prose states the condition (``ComponentGrammar/condition``): RPT.6 Period Units when RPT.5 is populated, CSU.2 when CSU.3 is empty, XAD.7 Address Type when the field repeats (v2.8.2), and so on, reported as ``IssueCode/conditionalComponentMissing`` at the same severity. The "as of v2.7" family (a coding system whenever a code is valued, an assigning authority whenever an identifier is valued, and kin) is carried separately as ``ComponentGrammar/conformanceCondition`` and is not checked by default, because the spec's own v2.7+ examples violate it almost everywhere; set ``ValidationOptions/conformanceConditionSeverity`` to have it reported as ``IssueCode/conformanceConditionMissing``. One composite also carries an either-or rule drawn from the spec's prose: `HD` needs a namespace ID, or a universal ID together with its type, and the universal ID and its type must be valued together or not at all (`LAB1^1.2.3` is an error; `LAB1`, `^1.2.3^ISO` and `LAB1^1.2.3^ISO` are valid).
- **Cardinality check.** Fields declared `repeatability=1` carrying multiple `~`-separated repetitions produce ``IssueCode/cardinalityExceeded`` errors. A bounded field (``FieldGrammar/maxRepetitions``, the RP/# column's printed integer) carrying more than its bound produces ``IssueCode/cardinalityExceeded`` as a warning.
- **Field length.** LEN is checked per repetition: every decoded value plus the component and subcomponent separators between them; the repetition separator, the HL7 null `""` and the MSH-1/MSH-2 delimiters are not counted. From v2.7 a normative length (`m..n`, `m..`, `x,y,z`) on a primitive-typed field is binding (v2.8.2 section 2.5.5.0) and follows ``ValidationOptions/normativeLengthSeverity``; a range the print attaches to a composite field is not checked, since normative lengths are only specified for primitive types. Before v2.7 the printed maximum is site-negotiable (v2.5.1 section 2.5.3.2) and follows ``ValidationOptions/fieldLengthSeverity``; `*` and `64K` cells are not checked. Both report ``IssueCode/fieldLengthOutOfRange(length:actual:)`` as a warning by default, and ``ValidationOptions/lenient`` turns both off. Conformance lengths (`40=`, `250#`, a bare v2.7+ integer) are never checked: they bound what a receiver stores, not the message (section 2.5.5.3).
- **Deprecation warning.** Fields with optionality `B` (backward-compat) or `X` (not-supported) that are populated produce ``IssueCode/fieldNotSupported`` warnings (severity `.warning`, not `.error`).
- **Code-table check.** A populated `ID` field bound to a closed HL7-defined table must carry one of that table's codes, as printed by the message's own HL7 version; otherwise ``IssueCode/valueNotInTable(table:)`` is an error. A table is closed when it is HL7-defined, permits no local extensions, and has rows (``HL7Table/isClosed``). A printed row that names a family of codes, such as Table 0203 `NNxxx` (checked as the shape `NN` plus three uppercase letters; ISO 3166 membership of those three letters is not checked), is a ``HL7Table/CodePattern``: a value fully matching it is a member. `IS` fields and user-defined tables are never enforced, and neither are empty or HL7-null (`""`) values. Nor is a field whose own prose leaves its table open (``FieldGrammar/tableOpen``, such as v2.4 `PID-31`, which cites Table 0136 "for suggested values" while `PID-24` cites it "for valid values" and is still checked). Under a localisation, the locale's own rendering of the table is consulted before an error is raised, so a locale can widen a table and never narrows it: AU ADRM-2021 back-ports `UNICODE UTF-8` into v2.4 Table 0211. Turn the check off with ``ValidationOptions/checkCodeTables``. Look tables up with ``HL7TableRegistry``.
- **Component code-table check.** The same rule one level down, on every supported version: a populated `ID` component bound to a closed HL7-defined table must carry one of its codes, and the issue is located at the component (`PID[1]-5.7` for a bad `XPN.7` name type). The component tables come from ``DataTypeGrammarTable``. `IS` components and open tables are never enforced; Table 0354 is open, so an unusual message structure in `MSH-9.3` is never rejected. A component that is itself a composite is descended into once, so the universal ID type of the assigning authority in `CX.4` reports at `PID[1]-3.4.3` (``IssueLocation/subcomponentIndex``), and OBX-5 is checked under the datatype OBX-2 declares. Each version is checked under its own component grammar: v2.3 to v2.4 define components in prose, and a table is bound there only on strong evidence, so fewer components are checked; and Table 0203 is never a closed set: user-defined until v2.5, then cited for suggested values, so an unknown `CX.5` identifier type is never an error on any version. Under ``HL7Locale/auLocalisation`` the ADRM's own Tables 0125 and 0301 apply, so `OBX-2 = CWE` and a universal ID type of `AUSNATA` are valid.

A closed HL7 table stays closed by default: an out-of-table code is always an error unless a locale renders the table more widely. Every supported version permits a site to extend an HL7 table locally (v2.3 and v2.3.1 CH2 sec 2.6.6, "Additions may be included on a site-specific basis"; v2.4 CH02 sec 2.7.6, v2.5.1 and v2.6 CH02 sec 2.5.3.6, "the table itself may be extended to accommodate locally defined values"; v2.8.2 CH02C 2.C.1.2), but that extension is never inferred from the wire — the caller declares it, per table, through ``ValidationOptions/localTableExtensions``:

```swift
var options = ValidationOptions()
options.localTableExtensions = ["0074": ["ZZ"]]   // a site-local diagnostic service code
let report = Validator(options: options).validate(message)
```

`ZZ` in `Table 0074` is now accepted wherever that table is checked, field or component; every other value outside the table is still ``IssueCode/valueNotInTable(table:)``. The setting applies on every supported version, as the extension clause does. It widens only the base-spec code-table check: AU profile value-set rules are not affected. Keys are four-digit table numbers; any other key is ignored.

For each segment whose ID is **not** in the loaded grammar table:

- **Z-segment policy.** Applies only when the ID begins with `Z` (ADR-018). ``ZSegmentPolicy/ignore`` produces no issue. ``ZSegmentPolicy/warnPresence`` produces a `.info`-severity ``IssueCode/zSegmentPresent`` issue per occurrence. ``ZSegmentPolicy/reject`` produces a `.error`-severity issue per occurrence (making the report invalid).
- **Segment not in version grammar.** Any other ID — one that does not begin with `Z` — always produces a `.warning`-severity ``IssueCode/segmentNotInVersionGrammar`` issue per occurrence, whatever ``ValidationOptions/zSegmentPolicy`` is set to: it is a standard segment the message's version does not define, not a Z-segment.

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
    checkComponentGrammar: false,            // skip the required-component checks (CX-1, MSH-9.3, ...)
    checkCardinality: false,                 // ignore single-cardinality violations
    warnDeprecatedFields: false              // don't warn on populated B/X fields
)
```

Three further switches are set by mutation, not the initialiser: ``ValidationOptions/requiredComponentSeverity``, ``ValidationOptions/conformanceConditionSeverity`` (the opt-in v2.7 component rules), ``ValidationOptions/auPathologySender``, ``ValidationOptions/auDisplayIntended`` and ``ValidationOptions/auNASHTransport``. The last three are caller assertions of facts no message carries, each gating an ADRM rule that is scoped on one:

| Option | Rule it applies | The fact the wire lacks |
| --- | --- | --- |
| `auPathologySender` | HL7au:00050.1.5 — OBX-6.3 must be `UCUM` on Results | the sender's discipline |
| `auDisplayIntended` | HL7au:00044.4.3 — CE `<text>` must be valued | whether the location displays to a user |
| `auNASHTransport` | HL7au:00044.2.2 / .2.3 on MSH-4 and MSH-6, and HL7au:00044.3.4 / .3.3 on every EI: the Universal ID must be `1.2.36.1.2001.1003.0.` + a 16-digit HPI-O, its type `ISO` | whether SMD with NASH certificates is in use |

Each defaults to `false` and applies only under ``HL7Locale/auLocalisation``.

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

- **Component optionality.** The component grammar records it where the spec prints it; nothing enforces it yet. On v2.3 to v2.4, a component whose prose names no table, several tables, or a table whose name does not match is left unchecked (ADR-017).
- **Component length.** Recorded on every component, never enforced. Conditional components are checked where the prose states a sibling-presence condition; the "as of v2.7" rules are opt-in (`conformanceConditionSeverity`), off by default because the spec's own examples violate them. Conditions on the coding system in use (CWE.7 and kin) and CNE.20's self-contradictory sentence are not modelled.
- **Field-level type conformance.** A TS field carrying `"hello"` is not a well-formed timestamp, but the validator doesn't currently check that. Tracked for a future release.
- **Cross-segment conditional predicates.** Same-segment refs only at present; see <doc:#Conditional-field-DSL>.

## See Also

- <doc:GettingStarted>
- ``Validator``
- ``ValidationReport``
- ``ValidationOptions``
- ``ValidationIssue``
- ``ZSegmentPolicy``
