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

For each segment whose ID is in the grammar table of the version validated (one per supported version: v2.3, v2.3.1, v2.4, v2.5.1, v2.6, v2.7.1 and v2.8.2; `2.7` and `2.8` are read through ``Version/grammarVersion`` as v2.7.1 and v2.8.2), and for each field within that segment:

- **Required-field check.** Fields with optionality `R` that are absent or empty produce ``IssueCode/requiredFieldMissing`` errors.
- **Conditional-field check.** Fields with optionality `C` carrying a ``FieldGrammar/condition`` predicate are evaluated: if the predicate triggers and the field is empty, the validator produces an ``IssueCode/conditionalFieldMissing`` error. C fields with no condition behave as `O` — backward compatible. See <doc:#Conditional-field-DSL> below for the predicate grammar.
- **Component-grammar check.** When a populated field has a composite datatype, every component that the component table of the MESSAGE'S OWN version prints as `R` must be populated; otherwise ``IssueCode/requiredComponentMissing`` is an error at that component (`PID[1]-3.1` for a `CX` with no ID number). The requirements differ by version and the check follows them: `CX.5` and `PT.1` are optional in v2.5.1 and required in v2.8.2; all three `MSG` components, the message structure in `MSH-9.3` included, are required from v2.5. Components printed `O`, such as `XAD.1` street address or `XPN.1` family name, are never required. v2.3 to v2.4 print no component optionality, so nothing is required of them. The severity is the consumer's choice: ``ValidationOptions/requiredComponentSeverity`` defaults to `.error` and can be set to `.warning`, which keeps every finding but leaves the report valid; use it for feeds that omit `MSH-9.3`, which v2.5+ prints as required and half the specification's own examples omit. Components the spec prints as conditional are checked where its prose states the condition (``ComponentGrammar/condition``): RPT.6 Period Units when RPT.5 is populated, CSU.2 when CSU.3 is empty, XAD.7 Address Type when the field repeats (v2.8.2), and so on, reported as ``IssueCode/conditionalComponentMissing`` at the same severity. The "as of v2.7" family (a coding system whenever a code is valued, an assigning authority whenever an identifier is valued, and kin) is carried separately as ``ComponentGrammar/conformanceCondition`` and is not checked by default, because the spec's own v2.7+ examples violate it almost everywhere; set ``ValidationOptions/conformanceConditionSeverity`` to have it reported as ``IssueCode/conformanceConditionMissing``. One composite also carries an either-or rule drawn from the spec's prose: `HD` needs a namespace ID, or a universal ID together with its type, and the universal ID and its type must be valued together or not at all (`LAB1^1.2.3` is an error; `LAB1`, `^1.2.3^ISO` and `LAB1^1.2.3^ISO` are valid).
- **Cardinality check.** Fields declared `repeatability=1` carrying multiple `~`-separated repetitions produce ``IssueCode/cardinalityExceeded`` errors. A bounded field (``FieldGrammar/maxRepetitions``, the RP/# column's printed integer) carrying more than its bound produces ``IssueCode/cardinalityExceeded`` as a warning.
- **Field length.** LEN is checked per repetition: every value plus the component and subcomponent separators between them, with an escape sequence counting the characters between its escape delimiters (`\F\` is 1, `\.br\` is 3, `\X0D0A\` is 5; v2.8.2 section 2.7, applied to every version); the repetition separator, the HL7 null `""` and the MSH-1/MSH-2 delimiters are not counted. From v2.7 a normative length (`m..n`, `m..`, `x,y,z`) on a primitive-typed field is binding (v2.8.2 section 2.5.5.0) and follows ``ValidationOptions/normativeLengthSeverity``; a range the print attaches to a composite field is not checked, since normative lengths are only specified for primitive types. Before v2.7 the printed maximum is site-negotiable (v2.5.1 section 2.5.3.2) and follows ``ValidationOptions/fieldLengthSeverity``; `*`, `64K` and the v2.4 to v2.6 symbols 65536 and 99999 are not checked. Where a pre-v2.7 print is shorter than values its own spec defines as valid (v2.4 MSH-9, OBX-2 on v2.3 to v2.5.1, and others), the schema carries the corrected length (owner ruling G10; permanent-limitations register, section C). Both report ``IssueCode/fieldLengthOutOfRange(length:actual:)`` as a warning by default, and ``ValidationOptions/lenient`` turns both off. Conformance lengths (`40=`, `250#`, a bare v2.7+ integer) are never checked: they bound what a receiver stores, not the message (section 2.5.5.3).
- **Component length.** From v2.7 the component tables print normative lengths on primitive components (81 components on v2.7.1, 78 on v2.8.2, such as EI.4 `1..6` and MSG.3 `3,7`; ``ComponentGrammar/length``), which "may also be specified on the components and/or fields where the data type is used" (v2.7.1 section 2.5.5.4 p. 12; v2.8.2 p. 13) and which a conformant message satisfies (section 2.5.5.0). Each component of each repetition is measured as a field is (escape sequences counted between their delimiters, the HL7 null `""` not counted, content after a primitive component's value set aside while ``IssueCode/extraComponentsInPrimitiveField`` is at least as severe) and reported as ``IssueCode/componentLengthOutOfRange(length:actual:)`` at the component, under ``ValidationOptions/normativeLengthSeverity``. A component table binds wherever its type is used ("If not specified, then the information specified on the data type itself, if present, applies where the data type is used", section 2.5.5.4), so a primitive subcomponent of a composite component is checked the same way against the component table of the component's own type (HD.3 `1..6` inside CX.4, reported at `PID-3.4.3`; since v3.15.0). Every normative length sits on a primitive ("Minimum and maximum lengths are not assigned for composite data types"), so an item is reported at one level only. Conformance lengths (`199=`, `20#`, a bare integer) are not checked, nor any component or subcomponent before v2.7, where no component table prints a normative length.
- **Deprecation warning.** Fields with optionality `B` (backward-compat), `X` (not-supported) or `W` (withdrawn) that are populated produce ``IssueCode/fieldNotSupported`` warnings (severity `.warning`, not `.error`). From v2.5 the component tables print optionality too ("For version 2.5 and higher, the optionality ... of data type components are supplied in component tables", v2.8.2 CH02 section 2.5.3.5, pp. 9-10), and a populated `B`, `X` or `W` component produces ``IssueCode/componentNotSupported(optionality:)`` at the component (since v3.15.0). The component table of a composite component's own type governs its subcomponents ("the optionality, table references, and lengths of data type components are supplied in component tables of the data type definition", v2.5.1 section 2.5.3.4), so a populated v2.5.1 TS.2 (`B`) inside DR.1 is reported at the subcomponent. A deprecated constituent "is retained for backward compatibility" (section 2.8.3) and a withdrawn one is used only "By site agreement" (section 2.8.4), so both are warnings. Components inside a field already reported are not reported again, nor subcomponents inside a component already reported. Both follow ``ValidationOptions/warnDeprecatedFields``.
- **Code-table check.** A populated `ID` field bound to a closed HL7-defined table must carry one of that table's codes, as printed by the message's own HL7 version; otherwise ``IssueCode/valueNotInTable(table:)`` is an error. A table is closed when it is HL7-defined, permits no local extensions, and has rows (``HL7Table/isClosed``). A printed row that names a family of codes, such as Table 0203 `NNxxx` (checked as the shape `NN` plus three uppercase letters; ISO 3166 membership of those three letters is not checked), is a ``HL7Table/CodePattern``: a value fully matching it is a member. `IS` fields and user-defined tables are never enforced, and neither are empty or HL7-null (`""`) values. Nor is a field whose own prose leaves its table open (``FieldGrammar/tableOpen``, such as v2.4 `PID-31`, which cites Table 0136 "for suggested values" while `PID-24` cites it "for valid values" and is still checked). Under a localisation, the locale's own rendering of the table is consulted before an error is raised, so a locale can widen a table and never narrows it: AU ADRM-2021 back-ports `UNICODE UTF-8` into v2.4 Table 0211. Turn the check off with ``ValidationOptions/checkCodeTables``. Look tables up with ``HL7TableRegistry``. A repetition with more than one component or subcomponent is checked on its first component, the value a recipient reads (v2.5.1 and v2.8.2 section 2.6.2 a), and the issue is then located at component 1 (`TQ2[1]-10.1`); a repetition with no extra components keeps the field-level location (`TQ2[1]-10`).
- **Extra components in a primitive field or component.** A primitive field repetition with content after its value (an unescaped `^` or `&`), or a primitive component of a composite with a subcomponent after its value, produces ``IssueCode/extraComponentsInPrimitiveField``, a `.warning` by default (``ValidationOptions/extraComponentsSeverity``; `nil` turns it off, as ``ValidationOptions/lenient`` does). The component separator separates components "of data fields where allowed" (section 2.5.4), and a sender escapes it in data as `\S\` (section 2.7.1), which stays silent. While this check is at least as severe as the length severity that applies (``ValidationOptions/normativeLengthSeverity`` for a v2.7+ normative length, ``ValidationOptions/fieldLengthSeverity`` otherwise; error > warning > info), the length of a primitive field is measured on its value, so the extra content is reported once, here; when the length rule is more binding, or this check is off, the whole occurrence is measured. Under version substitution (an unrecognised MSH-12 such as `2.7`, validated against the v2.5.1 grammar and flagged by ``IssueCode/versionNotRecognised(wireValue:)``), a value a later version allows, such as a CWE in a field that is `IS` in v2.5.1, may raise this warning or a length warning. The primitives follow each version's datatype sections (P6-14): DT, FT, ID, IS, NM, SI, ST, TM, TN, TS and TX on v2.3 to v2.4; DT, DTM, FT, GTS, ID, IS, NM, SI, ST, TM and TX on v2.5.1 and v2.6, plus SNM on v2.8.2. These shapes the spec allows stay silent: the TS degree-of-precision component on v2.3 to v2.4 (`20260101^D`), the component separators that mark FT lines (v2.5.1 section 2.7.6: "The component separator that marks each line"), one observation ID suffix in OBX-3.1, OBX-3.4 or (v2.8.2) OBX-3.10 (`71020&IMP`, v2.5.1 section 7.2.3), and the QIP.2 value list `<value1 & value2 & ...>` (v2.5.1 section 2.A.59.2). The FT line marker is field-level only: a raw `&` in an FT component (CF.2) is reported. An escaped `\T\` stays silent like `\S\`. At component level, an `ID` component's table check reads its first subcomponent and is located there when more follow.
- **Extra components in a composite field or component.** A composite field repetition with a populated component beyond its datatype's component table on the message's version (an XPN with a 15th component on v2.5.1), or a composite component with a populated subcomponent beyond its own datatype's table (a sixth FN subcomponent in XPN.1, a fourth HD subcomponent in CX.4), produces ``IssueCode/extraComponentsInCompositeField``, located at the field or at that component, with the same severity setting (``ValidationOptions/extraComponentsSeverity``). A warning, not an error: a recipient ignores components "present but were not expected" (section 2.6.2 a), "New components may be added at the end of a data type" (v2.5.1 section 2.8.1; section 2.8.1 h from v2.6), and a local extension adds them the same way (section 2.11.5 c from v2.5.1); v2.3 to v2.4 print only the version compatibility rule "new components may be added at the end of a field" (v2.3 and v2.3.1 section 2.10.2 c, v2.4 section 2.11.2 c). The message cites the rule of the version validated. Trailing empty components and escaped separators stay silent. Not checked: a datatype the version prints no component table for (CM on v2.3 to v2.4, OBX-5 `varies` with no OBX-2; OBX-5 otherwise takes the OBX-2 datatype), and the open-ended arrays NA (its tables end in an ellipsis; v2.5.1 section 2.A.45: "a one-dimensional array (vector or row) of numbers") and MA (v2.5.1 section 2.A.40: "channels within a sample are separated by component delimiters"; the v2.6 and v2.8.2 tables end in an ellipsis). A composite field's length is measured on the whole occurrence. P6-15.
- **Component code-table check.** The same rule one level down, on every supported version: a populated `ID` component bound to a closed HL7-defined table must carry one of its codes, and the issue is located at the component (`PID[1]-5.7` for a bad `XPN.7` name type). The component tables come from ``DataTypeGrammarTable``. `IS` components and open tables are never enforced; Table 0354 is open, so an unusual message structure in `MSH-9.3` is never rejected. A component that is itself a composite is descended into once, so the universal ID type of the assigning authority in `CX.4` reports at `PID[1]-3.4.3` (``IssueLocation/subcomponentIndex``), and OBX-5 is checked under the datatype OBX-2 declares. Each version is checked under its own component grammar: v2.3 to v2.4 define components in prose, and a table is bound there only on strong evidence, so fewer components are checked; and Table 0203 is never a closed set: user-defined until v2.5, then cited for suggested values, so an unknown `CX.5` identifier type is never an error on any version. Under ``HL7Locale/auLocalisation`` the ADRM's own Tables 0125 and 0301 apply, so `OBX-2 = CWE` and a universal ID type of `AUSNATA` are valid.
- **Primitive value format.** Populated NM, SI, DT, TM, DTM and TS values must match the format their datatype section prints (v2.5.1 and v2.8.2 section 2.A; v2.3 to v2.4 section 2.8 / 2.9): an NM is an optional sign, digits and an optional decimal point; an SI is a non-negative integer, 0 to 9999 from v2.5.1; a DT is `YYYY[MM[DD]]` naming a calendar date; TM, DTM and TS follow `HH[MM[SS[.S[S[S[S]]]]]][+/-ZZZZ]` and `YYYY[MM[DD[HH[MM[SS[.S[S[S[S]]]]]]]]][+/-ZZZZ]`, with precision set by the digits sent. Before v2.5 the TS format line prints `HHMM`, but its prose has `YYYYMMDDHH` specify a precision of hour, so the hour may stand alone on every version. Composites are checked through their component grammar, one level of subcomponents down; a primitive field is read as its first value; OBX-5 is checked as its OBX-2 type. Failures raise ``IssueCode/valueFormatInvalid(dataType:)`` at ``ValidationOptions/valueFormatSeverity`` (default `.warning`; `nil` in `.lenient`).

A closed HL7 table stays closed by default: an out-of-table code is always an error unless a locale renders the table more widely. Every supported version permits a site to extend an HL7 table locally (v2.3 and v2.3.1 CH2 sec 2.6.6, "Additions may be included on a site-specific basis"; v2.4 CH02 sec 2.7.6, v2.5.1 and v2.6 CH02 sec 2.5.3.6, "the table itself may be extended to accommodate locally defined values"; v2.7.1 CH02C 2.C.1.2, p. 8; v2.8.2 CH02C 2.C.1.2), but that extension is never inferred from the wire — the caller declares it, per table, through ``ValidationOptions/localTableExtensions``:

```swift
var options = ValidationOptions()
options.localTableExtensions = ["0074": ["ZZ"]]   // a site-local diagnostic service code
let report = Validator(options: options).validate(message)
```

`ZZ` in `Table 0074` is now accepted wherever that table is checked, field or component; every other value outside the table is still ``IssueCode/valueNotInTable(table:)``. The setting applies on every supported version, as the extension clause does. It widens only the base-spec code-table check: AU profile value-set rules are not affected. Keys are four-digit table numbers; any other key is ignored.

For each segment whose ID is **not** in the loaded grammar table:

- **Z-segment policy.** Applies only when the ID begins with `Z` (ADR-018). ``ZSegmentPolicy/ignore`` produces no issue. ``ZSegmentPolicy/warnPresence`` produces a `.info`-severity ``IssueCode/zSegmentPresent`` issue per occurrence. ``ZSegmentPolicy/reject`` produces a `.error`-severity issue per occurrence (making the report invalid).
- **Segment not in version grammar.** Any other ID — one that does not begin with `Z` — always produces a `.warning`-severity ``IssueCode/segmentNotInVersionGrammar`` issue per occurrence, whatever ``ValidationOptions/zSegmentPolicy`` is set to: it is a standard segment the message's version does not define, not a Z-segment.
- **Withdrawn segment.** A segment the version's Appendix A lists as withdrawn (v2.7.1) or deprecated (v2.8.2) with no definition, which a structure of that version still prints (QRD, QRF, URD and URS, last defined in v2.6), produces one `.info`-severity ``IssueCode/segmentWithdrawnInVersion`` issue per occurrence in place of the warning: its fields are not validated, and CH02 2.8.4 leaves its use to site agreement. The message structure check matches it by ID, so it is a structure finding wherever the structure does not name it (ADR-019 S2-1 amendment).

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
    warnDeprecatedFields: false              // don't warn on populated B/X/W fields or B/W components
)
```

Further switches are set by mutation, not the initialiser, among them ``ValidationOptions/requiredComponentSeverity``, ``ValidationOptions/conformanceConditionSeverity`` (the opt-in v2.7 component rules), ``ValidationOptions/messageStructureSeverity`` (see <doc:#Message-structures>), ``ValidationOptions/auPathologySender``, ``ValidationOptions/auDisplayIntended`` and ``ValidationOptions/auNASHTransport``. The last three are caller assertions of facts no message carries, each gating an ADRM rule that is scoped on one:

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

The condition predicate carried on ``FieldGrammar/condition`` is a short string (ADR-008, ADR-010, ADR-021). In outline:

```
<condition> := <clause> { " OR " <clause> }        // AND binds tighter than OR; no parentheses
<clause>    := <atom> { " AND " <atom> }
<atom>      := <referent> <predicate>
             | <segmentID> "present" | <segmentID> "absent"
             | "anyRepeat(" <fieldref> ")" <predicate> | "noRepeat(" <fieldref> ")" <predicate>
<referent>  := <segmentID>-<field>[.<component>[.<subcomponent>]]
             | "previousSegment(" <ID> ")." <fieldref> | "associatedSegment(" <ID> ")." <fieldref>
             | "nextSegmentID(" <ID>|... ")" | "messageCode" | "messageStructure" | "triggerEvent"
<predicate> := "populated" | "empty" | "= v" | "!= v" | "> n" | "startsWith v" | "not startsWith v"
             | "in (...)" | "not in (...)"
```

The referent may name another segment (`OBR-2 empty` on ORC-2). ADR-010 and ADR-021 in `docs/design` give the full rules.

Examples:

```
"PID-37 populated"     // ships on PID-36 (v2.4 to v2.7.1): breed required when strain is valued
"ORC-1 = NW"           // hypothetical — would fire when ORC-1 is "NW"
"PV1-2 != I"           // hypothetical — would fire when patient class isn't inpatient
```

Semantics:

- **Cross-segment references** are resolved against the message (ADR-008), scoped to the matched group occurrence where the structure check supplies one (see "Group scoping" below). A referenced segment or field that does not resolve makes the atom undecidable.
- **`populated` / `empty`** use the same any-subcomponent-non-empty rule as the required-field check — works for both scalar fields and composites.
- **`= value` / `!= value`** compare against the first-subcomponent-of-first-component-of-first-repetition "scalar view" of the referent — sufficient for ID/IS/ST/NM-typed fields.
- **Undecidable and malformed conditions fail safe.** The evaluator is three-state (ADR-021: true, false or unknown, with Kleene AND and OR); a "required when" check fires only on a definite true, so an atom that does not parse or does not resolve can never make a previously accepted message non-conformant.
- **C fields without a `condition`** behave as `O` — backward compatible. A schema can carry a C field with no predicate for years and never produce a conditional error.

Conditions live in the per-segment JSON schemas under `Resources/schemas/<version>/` and are emitted into the codegen-produced ``SegmentGrammarTable``. To add a condition to a field, edit the schema and run `bash scripts/regenerate-typed-segments.sh`. See <doc:AddingASegment>.

## Message structures

``ValidationOptions/messageStructureSeverity`` checks the message's abstract message syntax (ADR-019). It is `.warning` in ``ValidationOptions/default``, `.error` in ``ValidationOptions/strict`` and `nil`, off, in ``ValidationOptions/lenient`` (owner decision G2 (b), since P8b-18; before then it was off in every preset). The structure comes from MSH-9.3, or from MSH-9.1 and MSH-9.2 through the chapter caption lines when MSH-9.3 is empty. The check reports a missing required segment or group (``IssueCode/messageStructureSegmentMissing(structure:segmentID:group:)``), a segment out of place or beyond its maximum repetitions (``IssueCode/messageStructureSegmentUnexpected(structure:segmentID:)``), and an MSH-9.3 that names a modelled structure not printed for the trigger event, or, on a complete version (every modelled version), no structure the version prints at all (a locally defined Z message whose trigger the version prints under no structure is not modelled instead, and such a Z trigger may declare a printed structure: it is matched against the body, or reported as not modelled if registered) (``IssueCode/messageStructureMismatch(declared:trigger:)``, reported alone, with no segment-order findings). When no structure is applied, one ``IssueCode/messageStructureNotModelled(structure:)`` issue at `.info` says why: the structure or version is not modelled (on a complete version, a structure registered as not modelled, with its reason), MSH-12 is empty or does not resolve to the version validated, the trigger is printed under two structures and MSH-9.3 is empty, or the message is a fragment (MSH-14 populated, or a trailing DSC with a continuation pointer or where the structure defines none). A structure that fails the ADR-019 determinism lint (where greedy one-pass matching could accept or reject the wrong messages) is matched exactly instead: it reports at most one finding, at the furthest segment any parse reached (unexpected there, or missing at the end of the message), and records group spans only for an accepted message whose accepting parses all agree on them. Because that finding sits at the furthest segment reached, a required segment missing mid-message is reported on the segment after it (BAR_P01 without EVN: unexpected PID); so the unexpected finding's text also names what the structure accepts at that point ("PID has no place in BAR_P01 at this point; expected here: SFT or EVN"): the segment IDs some parse could take there, each once in structure order, at most eight followed by "and N more", with "or the end of the message" when a parse is complete there. Its code, severity and location are those of the bare finding. Z-segments are left to ``ZSegmentPolicy`` and ADD continuations are skipped; a segment the version's grammar does not define is reported once, by ``IssueCode/segmentNotInVersionGrammar``. Receivers ignore unexpected segments (v2.5.1 CH02 §2.6.2), so use `.warning` on the receiving side and `.error` on the sending side.

```swift
var options = ValidationOptions.default   // structure findings are warnings
options.messageStructureSeverity = nil    // or turn the check off
let report = Validator(options: options).validate(message)
```

Look structures up with ``MessageStructureTable``.

Under ``HL7Locale/auLocalisation`` the check also applies HL7au:00060.1 (P8b-4, P8b-4a): a v2.4 ORU^R01, ORM^O01, REF^I12, RRI^I12 or OSR^Q06 is matched against the constrained structure the ADRM-2021 prints for it (pp 205, 279, 324, 325 and 281) as well as the base v2.4 one, and a segment the ADRM structure requires and the message lacks (PID in each ORU^R01 result, PV1 beside PD1, NK1 or PV2, an order detail segment in each ORM^O01 order, RF1 and PV1 in REF^I12, MSA in RRI^I12) is reported as ``IssueCode/profileConstraintViolation(localeRule:)`` with `"HL7au:00060.1"`, at the same severity. A base segment the ADRM removed (NTE, FT1, CTI) is not a finding, and a segment the base check already reports missing is not reported twice. A base structure finding is dropped where the ADRM structure accepts the message at that point (a segment it places there, such as PD1 in REF^I12; a segment it makes optional, such as PRD and PID in RRI^I12); every other base finding is kept, and a base matched exactly (one finding, no recovery) is matched again past a dropped finding so a later one is still reported. An ADRM maximum below the base's (REF^I12 IN1, PV1, PV2) is not enforced. The order status response (OSR^Q06, p 281) keeps the base order detail choice, so RQD, RQ1, RXO, ODS or ODT in place of OBR, and an OBX after any of them, are not flagged. The Appendix 8 simplified REF structure and the ORR^O02 print are not modelled, and the PV1 prose mandate (pp 17, 205) is not enforced beyond the print (permanent-limitations register section E).

Batch input (`FHS`/`BHS` ... `BTS`/`FTS`) must go through ``BatchParser`` and ``BatchValidator``, which give one report per contained message; a batch trailer (`BTS`, `FTS`) left on a message passed to the plain ``Parser`` is reported as an unexpected segment when the structure check is on.

## What the validator does not check

- **Message structure (partial).** Segment order, groups and required segments are checked whenever ``ValidationOptions/messageStructureSeverity`` is set (in ``ValidationOptions/default`` and ``ValidationOptions/strict``), on every supported version, v2.3, v2.3.1, v2.4, v2.5.1, v2.6, v2.7.1 and v2.8.2 (and 2.7 and 2.8, read through the v2.7.1 and v2.8.2 grammars), all complete. v2.3: 147 structures are modelled (v2.3 prints no structure ID and no MSH-9.3, so its IDs are synthesised CODE_EVT from the section titles and a v2.3 message resolves from MSH-9.1^9.2 only, ignoring a populated third component; group names come through the HL7 v2.xml 2.3.1 and v2.4 bundles), and 22 v2.3 structures are registered as not modelled with their reason: prints that use a placeholder or an undefined segment, two whose segments the print gives only in prose fragments the extractor does not read, and triggers the print defines only in prose with no unambiguous printed structure; triggers whose prose names a printed structure are matched against it. v2.3.1: 100 structures are modelled (most v2.3.1 captions print no structure ID: it comes from the version's Table 0354, read through cited errata; group names come from the HL7 v2.xml 2.3.1 bundle, then the v2.4 one) and 38 are registered as not modelled (ten of them Table 0354 misprints the table prints literally), among them the general order's `Order Detail Segment` placeholder (ORM_O01, ORR_O02, OSR_Q06). v2.4: 148 structures are modelled (v2.4 prints no group names; they come from the HL7 v2.xml bundles or cited overrides) and 34 are registered as not modelled (ten of them rows the CH02 listing of Table 0354 prints and Appendix A lacks or prints differently). v2.5.1: 173 structures are modelled (RSP_K21 and RDE_O11, printed twice with different syntax, from their looser prints) and 32 are registered as not modelled. v2.6: 190 are modelled (ACK, ADT_A30, ADT_A43, MFK_M01, QRY_PC4 and RDE_O11 from their looser prints; RSP_K21, whose two prints are incomparable, as their union) and 20 are registered as not modelled. v2.8.2: 185 are modelled (ACK from its looser print) and 62 are registered as not modelled, 47 of them Table 0354 rows marked Deprecated and four IDs the CH04 query profiles print. v2.7.1: 164 are modelled (ACK from its looser print) and 58 are registered as not modelled, 39 of them Table 0354 rows marked Deprecated and five that print segments v2.7.1 does not define (URD and URS; the withdrawn QRD and QRF). Registered structures (unexpandable placeholders such as CH12's `< OBR | etc. >` and the query and master-file templates, SUR_P09's `ED` row, and Table 0354 rows with no printed syntax) each report ``IssueCode/messageStructureNotModelled(structure:)`` with its reason. A message validated against a version other than the one its MSH-12 reads (an excluded version falling back to the v2.5.1 grammar, or a parser version override) reports not modelled, and so do fragments; on a complete version an MSH-9.3 naming no printed structure (`ADT^A04^ADT_A04`) is a mismatch. A structure ID the version's print gives for the trigger is never a mismatch (P8b-final): a modelled one is matched (`ORU^W01^ORU_R01`, folded onto ORU_R01 from each version's CH07 W01 section; `MCF^A01^ACK` on v2.4), and one with no modelled syntax (a literally printed Table 0354 misprint such as v2.3.1 `TBR_R09`, a row only one listing of Table 0354 prints such as v2.4 `QRY_Q26`, a query profile row's ID such as v2.8.2 `QBP_Q33`, or `ORU_W01`) is registered and reports not modelled, naming the structure the chapters give; so does a printed pair whose ID is modelled for other triggers (`RSP^K32^RSP_K25`, v2.7.1 and v2.8.2 CH03 query profiles). The rollout completed in P8b-18, but section E of the permanent-limitations register stays blocking on every version: master-file bodies printed only as prose fragments (v2.3 to v2.6), a structure alias for QRY_P04 (v2.4, v2.5.1), an open-slot element for the `OBR, etc.` order detail (v2.3 to v2.8.2), a structure keyed by a field value for v2.5.1 and v2.6 MFN_M03 (MFI-1) and ERP (ERQ-2, v2.3 to v2.5.1), per-trigger structures where two prints of one ID differ (v2.5.1 to v2.8.2), segment grammars (or a pass-over rule) for the withdrawn QRD, QRF, URD and URS that v2.7.1 and v2.8.2 prints still name, fragment reassembly and version provenance (ADR-019).
- **Group scoping.** Conditions that read a peer segment of the same group (ORC-2/3, OBR-2/3 and the group-scope cardinality rules) are scoped by the matched structure's own group occurrences when the version is complete and the message matches its structure cleanly with one reading of its groups (P8b-17). Otherwise the ORC walk applies, except that for the message codes whose structures print OBR before ORC (OUL on v2.5.1; OUL, OPU and OPL on v2.6, v2.7.1 and v2.8.2) the order-number conditions are not evaluated, as before; so one structure finding anywhere in such a message, even one unrelated to its orders, switches them off, and no issue on the message says so (whether one should is an open owner question). Where the print ties no single group occurrence to a lookup (a container or specimen OBX beside repeating orders, among others) the answer is registered as imprecise (register section E).
- **Component optionality (partial).** Required (`R`) components, and conditional components where the prose states a sibling-presence condition, are checked (see the component-grammar check above); the "as of v2.7" rules are opt-in (``ValidationOptions/conformanceConditionSeverity``), off by default because the spec's own examples violate them. Conditions on the coding system in use (CWE.7 and kin) and CNE.20's self-contradictory sentence are not modelled. A populated `B`, `X` or `W` component or subcomponent is reported (see the deprecation warning above). On v2.3 to v2.4, a component whose prose names no table, several tables, or a table whose name does not match is left without a table check (ADR-017). Registered in the permanent-limitations register, sections C and D (section G, the component checks, is closed).
- **Acknowledgment protocol.** ``MessageBuilder/acknowledgment(to:code:messageControlID:dateTime:)`` builds the general acknowledgment of a message (MSA-2 echoes MSH-10, sender and receiver swap, `ACK^<event>^ACK`, MSH-11 and MSH-12 echoed, and a populated MSH-18 echoed so the ACK declares the character set it is serialised in, a builder rule beyond the spec's echo list; ADR-019 decision 9), and the built ACK validates like any other message. Whether, when and with which ``AcknowledgmentCode`` to acknowledge, the MSH-15 and MSH-16 enhanced-mode rules and the sequence number protocol are receiving-application behaviour (v2.5.1 CH02 §2.9.2 to §2.9.3) and a non-goal: the caller chooses the code and adds any ERR detail.

## See Also

- <doc:GettingStarted>
- ``Validator``
- ``ValidationReport``
- ``ValidationOptions``
- ``ValidationIssue``
- ``ZSegmentPolicy``
