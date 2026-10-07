# Validation

What the validator checks, what it does not, and the options that govern each check.

## Overview

``Validator`` checks a parsed ``Message`` and returns a ``ValidationReport``. It never throws: parsing is fatal (a structural failure throws ``ParseError``), validation is not (every finding is collected).

```swift
let message = try Parser().parse(bytes)
let report = Validator().validate(message)

if !report.isValid {
    for error in report.errors {
        print("\(error.location.pathDescription): \(error.message)")
    }
}
```

``ValidationReport/isValid`` is `true` when no issue has `.error` severity; warnings and information do not make a report invalid.

To answer "will this catch X?", find X under <doc:#What-the-validator-checks>. Each line names the ``IssueCode`` raised and the ``ValidationOptions`` property that governs it. If X is not there, it is under <doc:#What-the-validator-does-not-check>, with the reason and the section of the permanent-limitations register that records it. The two lists are meant to cover everything between them; a check that is in neither is a documentation defect worth reporting.

## What the validator checks

Every check reads the grammar of the message's own version: v2.3, v2.3.1, v2.4, v2.5.1, v2.6, v2.7.1 or v2.8.2, from MSH-12 (`2.7` and `2.8` through ``Version/grammarVersion`` as v2.7.1 and v2.8.2).

### Version and segments

- **Version substituted.** MSH-12 `2.7` or `2.8` is validated as v2.7.1 or v2.8.2: ``IssueCode/versionGrammarSubstituted(declared:validatedAs:)``, information, at MSH-12. Always on.
- **Version not recognised.** A populated MSH-12 naming no modelled version (2.1, 2.2, 2.5, 2.8.1, 2.9, or an unreadable VID.1) is validated against the v2.5.1 grammar: ``IssueCode/versionNotRecognised(wireValue:)``, warning. Always on.
- **Segment not in the version's grammar.** A segment ID that does not begin with `Z` and that the version does not define: ``IssueCode/segmentNotInVersionGrammar``, warning, its fields unchecked. Always on, whatever the Z-segment policy.
- **Withdrawn segment.** QRD, QRF, URD and URS on v2.7.1 and v2.8.2 (listed as withdrawn or deprecated, still named by structures): ``IssueCode/segmentWithdrawnInVersion``, information, fields unchecked. Always on.
- **Z-segments.** ``ValidationOptions/zSegmentPolicy``: ``ZSegmentPolicy/ignore`` reports nothing, ``ZSegmentPolicy/warnPresence`` one ``IssueCode/zSegmentPresent`` at information per occurrence, ``ZSegmentPolicy/reject`` the same at error. A Z-segment's fields are never checked.
- **Message structure.** Segment order, groups, required segments and repetition against the structure the version prints for the trigger event (1,190 modelled, 183 registered as not modelled with their reason). ``ValidationOptions/messageStructureSeverity`` governs ``IssueCode/messageStructureSegmentMissing(structure:segmentID:group:)``, ``IssueCode/messageStructureSegmentUnexpected(structure:segmentID:)`` and ``IssueCode/messageStructureMismatch(declared:trigger:)`` (an MSH-9.3 naming a structure the trigger is not printed under). When no structure is applied, one ``IssueCode/messageStructureNotModelled(structure:)`` at information says why. Details under <doc:#Message-structures>.
- **Conditions withheld.** Where the order-number conditions of an OUL, OPU or OPL cannot be scoped to one order group, they are not evaluated, and one ``IssueCode/conditionNotEvaluated(fields:)`` at information names them. Always on.

### Fields

- **Required.** An `R` field absent or empty: ``IssueCode/requiredFieldMissing``, error. ``ValidationOptions/checkRequiredFields``.
- **Conditional, required when.** A `C` field whose ``FieldGrammar/condition`` holds and which is empty: ``IssueCode/conditionalFieldMissing``, error. A `C` field with no condition is read as `O`. Conditions are evaluated three-state (true, false, unknown); only a definite true fires, so an unresolvable referent never makes a message non-conformant. ``ValidationOptions/checkConditionalFields``. See <doc:#Conditional-field-DSL>.
- **Conditional, prohibited when.** A field populated while its prohibition holds ("may only be valued if ..."): ``IssueCode/conditionalFieldProhibited``, at the severity the rule carries (warning for "should" text). ``ValidationOptions/checkConditionalFields``.
- **Paired fields.** ORC-2 and OBR-2, ORC-3 and OBR-3, ORC-12 and OBR-16, ORC-8 and OBR-29 (v2.3 to v2.6) or OBR-54 (v2.7.1, v2.8.2), the same data element printed twice, both populated in one order group with different values: ``IssueCode/pairedFieldMismatch(item:)``, error. Always on.
- **Cardinality.** A single-repeat field with more than one repetition: ``IssueCode/cardinalityExceeded``, error. A repeating field beyond its printed bound: the same code at ``ValidationOptions/repetitionBoundSeverity`` (warning). Both under ``ValidationOptions/checkCardinality``.
- **Length.** Measured per repetition, separators between components counted, an escape sequence counted by the characters between its delimiters, the HL7 null `""` not counted. Before v2.7 the printed maximum is site-negotiable and follows ``ValidationOptions/fieldLengthSeverity``; from v2.7 a normative length on a primitive-typed field follows ``ValidationOptions/normativeLengthSeverity``. Both report ``IssueCode/fieldLengthOutOfRange(length:actual:)``, warning by default. Where a pre-v2.7 print is shorter than values its own spec defines as valid (v2.4 MSH-9, OBX-2 on v2.3 to v2.5.1, and others), the schema carries the corrected length.
- **Value format.** Populated NM, SI, DT, TM, DTM and TS values against the format their datatype section prints (an NM is a sign, digits and a decimal point; DT is `YYYY[MM[DD]]` naming a real date; TS and DTM are `YYYY[MM[DD[HH[MM[SS[.S...]]]]]][+/-ZZZZ]`; OBX-5 is read as its OBX-2 type): ``IssueCode/valueFormatInvalid(dataType:)`` at ``ValidationOptions/valueFormatSeverity`` (warning).
- **Code tables.** A populated `ID` field bound to a closed HL7 table (HL7-defined, no local extensions permitted, rows printed; ``HL7Table/isClosed``) must carry one of that version's codes: ``IssueCode/valueNotInTable(table:)``, error. `IS` fields, user-defined tables, open tables (Table 0203 among them), fields whose own prose opens the table (``FieldGrammar/tableOpen``), and empty or `""` values are never checked. A printed pattern row such as Table 0203 `NNxxx` is matched as a shape (``HL7Table/CodePattern``). A multi-component repetition is checked on its first component. ``ValidationOptions/checkCodeTables``, widened by ``ValidationOptions/localTableExtensions`` (below). Look tables up with ``HL7TableRegistry``.
- **Deprecated, unsupported or withdrawn.** A populated `B`, `X` or `W` field: ``IssueCode/fieldNotSupported``, warning. ``ValidationOptions/warnDeprecatedFields``.
- **Extra content in a primitive field.** An unescaped `^` or `&` after a primitive value: ``IssueCode/extraComponentsInPrimitiveField`` at ``ValidationOptions/extraComponentsSeverity`` (warning). Shapes the spec allows stay silent: the TS degree-of-precision component on v2.3 to v2.4, FT line markers, one OBX-3 suffix, the QIP.2 value list, and escaped `\S\` or `\T\`. While this check is at least as severe as the applicable length severity, the length of a primitive is measured on its value, so the extra content is reported once.

### Components and subcomponents

- **Required components.** A populated composite missing a component its version's component table prints `R` (`PID[1]-3.1` for a CX with no ID; `MSH-9.3` from v2.5): ``IssueCode/requiredComponentMissing`` at ``ValidationOptions/requiredComponentSeverity`` (error; `.warning` keeps the finding and the report valid). v2.3 to v2.4 print no component optionality, so nothing is required there. ``ValidationOptions/checkComponentGrammar``.
- **Conditional components.** A `C` component whose prose states a sibling-presence or repetition condition (RPT.6 when RPT.5 is populated, CSU.2 when CSU.3 is empty, XAD.7 when the field repeats on v2.8.2): ``IssueCode/conditionalComponentMissing``, at the required-component severity. ``ValidationOptions/checkComponentGrammar``.
- **The "as of v2.7" conditions.** A coding system whenever a code is valued, an assigning authority whenever an identifier is, and kin (``ComponentGrammar/conformanceCondition``): ``IssueCode/conformanceConditionMissing``, only when ``ValidationOptions/conformanceConditionSeverity`` is set. Off by default because the specification's own v2.7+ examples violate it in 62 to 100 percent of values; nobody expects the Spanish Inquisition, and nobody expects the standard's examples to fail the standard.
- **HD either-or.** An HD needs a namespace ID, or a universal ID with its type, and the universal ID and its type go together (`LAB1^1.2.3` is an error; `LAB1`, `^1.2.3^ISO` and `LAB1^1.2.3^ISO` are valid): ``IssueCode/requiredComponentMissing`` at the required-component severity, located at the field. ``ValidationOptions/checkComponentGrammar``.
- **Component length.** From v2.7, a normative length on a primitive component (EI.4 `1..6`, MSG.3 `3,7`), measured as a field is, and the same one level down (HD.3 inside CX.4, reported at `PID-3.4.3`): ``IssueCode/componentLengthOutOfRange(length:actual:)`` at ``ValidationOptions/normativeLengthSeverity``.
- **Component code tables.** A populated `ID` component or subcomponent bound to a closed table, on every version, located at the component (`PID[1]-5.7`) or subcomponent (`PID[1]-3.4.3`): ``IssueCode/valueNotInTable(table:)``. OBX-5 is checked under the datatype OBX-2 declares. On v2.3 to v2.4 a table is bound to a component only where the prose names it unambiguously. ``ValidationOptions/checkCodeTables``; tables from ``DataTypeGrammarTable``.
- **Deprecated components.** From v2.5, a populated `B`, `X` or `W` component or subcomponent (v2.5.1 TS.2 inside DR.1): ``IssueCode/componentNotSupported(optionality:)``, warning, not repeated inside a field or component already reported. ``ValidationOptions/warnDeprecatedFields``.
- **Extra content in a primitive component.** A subcomponent after a primitive component's value: ``IssueCode/extraComponentsInPrimitiveField`` at ``ValidationOptions/extraComponentsSeverity``.

### Composites

- **Too many components.** A composite field or component with a populated component beyond its datatype's table on the message's version (a 15th XPN component on v2.5.1, a fourth HD subcomponent in CX.4): ``IssueCode/extraComponentsInCompositeField`` at ``ValidationOptions/extraComponentsSeverity`` (warning: the spec lets recipients ignore trailing components and lets later versions add them). Trailing empty components and escaped separators are silent.
- **Typed views.** Every component a supported version defines is reachable through a typed composite view or `viewed(as:)`; see <doc:TypedSegments>. Views read; they do not validate.

### Escapes and encoding

- **Character set.** MSH-18 selects the decoder; an unrecognised value throws ``ParseError/unsupportedCharacterEncoding(declared:)`` at parse, with no lossy fallback. An embedded NUL throws ``ParseError/truncatedMessage(atByte:)``. See <doc:CharacterEncodingGuide>.
- **Escape sequences.** Decoded on parse and re-encoded on serialise byte for byte; a locally defined (`\Z..\`) or unrecognised body passes through verbatim and is not reported. Escapes count toward length as described above, and an escaped separator never raises an extra-component finding. See <doc:EscapeSequences>.
- **Under ``HL7Locale/auLocalisation``** the `\X..\`, `\C..\` and `\M..\` escapes, which the ADRM prohibits, and MSH-1 and MSH-2 other than `|^~\&`, are ``IssueCode/profileConstraintViolation(localeRule:)``.

### Batches

- ``BatchParser`` (and ``StreamingBatchParser``) split an `FHS`/`BHS` ... `BTS`/`FTS` file into messages, and ``BatchValidator`` gives one ``ValidationReport`` per message, each checked as above. A batch trailer left on a message passed to the plain ``Parser`` is an unexpected segment when the structure check is on.
- Under ``HL7Locale/auLocalisation`` the batch-scope rules apply: one batch per file, a REF batched with any other message, and the FHS and BHS delimiters, each as ``IssueCode/profileConstraintViolation(localeRule:)``.

### Acknowledgement building

``MessageBuilder/acknowledgment(to:code:messageControlID:dateTime:)`` builds the general acknowledgement: MSA-2 echoes MSH-10, sender and receiver swap, MSH-9 becomes `ACK^<event>^ACK`, MSH-11 and MSH-12 are echoed, and a populated MSH-18 is echoed so the ACK declares the character set it is serialised in. The built ACK validates like any other message. The caller chooses the ``AcknowledgmentCode`` and adds any ERR detail.

### The locale layer

``HL7Locale/auLocalisation`` layers the ADRM-2021 profile over the base checks: field and component narrowings, value sets, prohibitions, the AU tables (0125, 0191, 0291, 0301, 0203 and others, which can widen a base table and never narrow it), the profile structures for v2.4 ORU^R01, ORM^O01, ORR^O02, REF^I12, RRI^I12 and OSR^Q06, group-scope segment counts, uniqueness, ordering, escapes and batches. Its findings are ``IssueCode/profileConstraintViolation(localeRule:)`` (the `localeRule` names the conformance point), ``IssueCode/segmentCardinalityBelowMinimum(segmentID:minCount:actual:groupScope:)`` and ``IssueCode/segmentCardinalityAboveMaximum(segmentID:maxCount:actual:groupScope:)`` (errors; an AU group needs or forbids a segment, such as the display OBX of HL7au:000008 or the NTE ban of HL7au:000023), and ``IssueCode/profileMaximumExceeded(localeRule:)`` at information (an occurrence beyond an ADRM maximum narrower than the base). The profile governs a message of every version; its structures apply to v2.4 only. Its rules are not switched by the preset flags: the profile structures follow ``ValidationOptions/messageStructureSeverity``, the AU field lengths ``ValidationOptions/fieldLengthSeverity``, and four rules the caller must assert (<doc:#Caller-assertions>). The full account is <doc:AustralianLocalisation>.

## Presets

| Property | ``ValidationOptions/default`` | ``ValidationOptions/strict`` | ``ValidationOptions/lenient`` |
| --- | --- | --- | --- |
| `zSegmentPolicy` | `.ignore` | `.reject` | `.ignore` |
| `checkRequiredFields` | on | on | on |
| `checkConditionalFields` | on | on | off |
| `checkComponentGrammar` | on | on | off |
| `checkCardinality` | on | on | off |
| `warnDeprecatedFields` | on | on | off |
| `checkCodeTables` | on | on | off |
| `requiredComponentSeverity` | `.error` | `.error` | `.error` (check off) |
| `conformanceConditionSeverity` | off | off | off |
| `messageStructureSeverity` | `.warning` | `.error` | off |
| `fieldLengthSeverity`, `normativeLengthSeverity` | `.warning` | `.warning` | off |
| `extraComponentsSeverity`, `valueFormatSeverity`, `repetitionBoundSeverity` | `.warning` | `.warning` | off |
| the four `au` assertions | `false` | `false` | `false` |
| `localTableExtensions` | empty | empty | empty |

`default` suits receiving traffic where Z-segments are routine; `strict` suits validating what you send; `lenient` keeps the required-field check and the always-on checks (the version and segment notices, paired fields, withheld conditions) and turns off everything else. `ValidationOptions()` equals `default`. Receivers ignore unexpected segments (v2.5.1 CH02 section 2.6.2), which is why structure findings are warnings in `default` and errors in `strict`.

The initialiser takes `zSegmentPolicy`, `checkRequiredFields`, `checkConditionalFields`, `checkComponentGrammar`, `checkCardinality` and `warnDeprecatedFields`; every other property is set by mutation:

```swift
var options = ValidationOptions.default
options.requiredComponentSeverity = .warning   // a feed that omits MSH-9.3
options.messageStructureSeverity = nil         // structure check off
let report = Validator(options: options).validate(message)
```

## Caller assertions

Four ADRM rules are scoped by a fact no message carries. Each is a ``ValidationOptions`` property, `false` by default (the rule stays silent), read only under ``HL7Locale/auLocalisation``:

| Option | Rule it applies | The fact the wire lacks |
| --- | --- | --- |
| ``ValidationOptions/auPathologySender`` | HL7au:00050.1.5: OBX-6.3 must be `UCUM` on Results | the sender's discipline |
| ``ValidationOptions/auDisplayIntended`` | HL7au:00044.4.3: CE `<text>` must be valued | whether the location displays to a user |
| ``ValidationOptions/auNASHTransport`` | HL7au:00044.2.2 and .2.3 on MSH-4 and MSH-6, HL7au:00044.3.4 and .3.3 on every EI: Universal ID `1.2.36.1.2001.1003.0.` plus a 16-digit HPI-O, type `ISO`; HL7au:000043.1 and 00044.2.1: MSH-4.1 and MSH-6.1 valued. On ORM, ORU and REF | whether SMD with NASH certificates is in use |
| ``ValidationOptions/auAssigningAuthorityTable`` | HL7au:00104.7.2.1: PRD-7.2 a printed Table 0363 value or a vendor authority in `localTableExtensions["0363"]`, on Referrals | which vendor authorities the site has agreed |

## Local table extensions

Every supported version lets a site extend an HL7 table locally (v2.3 and v2.3.1 CH2 section 2.6.6; v2.4 CH02 section 2.7.6; v2.5.1 and v2.6 CH02 section 2.5.3.6; v2.7.1 and v2.8.2 CH02C 2.C.1.2), but the extension is not on the wire, so a closed table stays closed until the caller declares it:

```swift
var options = ValidationOptions()
options.localTableExtensions = ["0074": ["ZZ"]]   // a site-local diagnostic service code
let report = Validator(options: options).validate(message)
```

`ZZ` is then accepted wherever Table 0074 is checked, field or component, on every version; every other value outside the table is still ``IssueCode/valueNotInTable(table:)``. The AU value sets built from a table's codes honour it too (Tables 0203, 0074, 0200, and 0363 under `auAssigningAuthorityTable`); AU rules that narrow a field to a fixed list (MSH-16, MSH-18, the display formats) do not. Keys are four-digit table numbers; any other key is ignored.

## What the validator does not check

Each line gives the reason. **Blocking** means the rule is decidable from the wire but the model cannot yet express it faithfully, so it blocks spec-completeness. **Permanent** means no message carries what the rule needs, or the gap is left by design. The validator fails safe throughout: an unchecked rule is silent, never a false error.

### Blocking

- **Three message-structure residuals**: a v2.6 MFR_M01 with MFI-1 OMA to OME (the v2.6 print gives no MFR fragment for them, so it reports not modelled); a no-data query response without QAK on v2.4 to v2.8.2 (without QAK it cannot be told from a cut-off reply, so it keeps the full structure); the v2.3 event replay error example, whose print has no "rest absent" sentence.
- **RXE-15 on v2.3 to v2.4**: "required ... in pharmacy/treatment messages" is held back so one sentence is not read two ways across versions.
- **ROL-4 equal to STF-2 and STF-3** (v2.6 to v2.8.2): a cross-segment comparison of composites of different types, which the condition language cannot state.
- **Blank printed optionality** (150 rows such as NST, NSC, the v2.6 CH17 sterilisation segments, v2.5.1 OBX-20 to 22, and 87 rows on v2.7.1): the spec defines no blank code, so these fields are read as optional.
- **Repeating TQ fields on v2.3 and v2.3.1** (OBR-27, SCH-11): the repeat delimiter carries both a TQ.6 priority continuation and a new repetition, and the delimiters alone cannot tell them apart. On the single-repeat TQ fields of those versions a wrong second repetition goes unreported for the same reason.
- **OM2-6 on v2.3 to v2.4**: a repeating tuple with nested subcomponents that no field grammar yet expresses, so its width is not checked.
- **Batch envelopes**: `FHS`, `BHS`, `BTS` and `FTS` are kept as raw text, so their fields are not checked against the grammar and the trailer counts (BTS-1, FTS-1) are not compared with the messages and batches carried; only the AU delimiter and batch-scope rules read them.
- **Field-local table mentions and TXA-22**: 15 CM field definitions on v2.3 to v2.4 that name two tables in one sentence are left unbound; TXA-22's "both or neither" rule between a component group and one component is not expressible.
- **CWE.7 and kin, CNE.20**: the version ID required when the coding system is not an HL7 table needs a value pattern and a table-type lookup; CNE.20's sentence contradicts its own summary. Other printed `C` components with no stated condition (OSP.2, PL.1, XCN.12 and others) are read as optional.

### Permanent

- **Terminology**: whether a value belongs to a code system, or two codes "reflect the same concept", needs a terminology service. This bounds LOINC placement, the AU "same concept" points, SNOMED CT-AU subsumption (HL7au:00100.1) and units implied by a dispense code (RXE-11 and kin). Table 0203 `NNxxx` is checked for shape, not ISO 3166 membership.
- **Timezones**: a `+/-ZZZZ` offset is checked for shape and, under the AU profile, presence; whether it is right for the sender's location needs a timezone database.
- **Certificates and directories**: NASH certificates, vendor X.509 certificates and whether an organisation name is the one the HI service registers.
- **Cross-message state**: duplicates across messages (OBR-48 "duplicate procedure", HL7au:00044.3.1 uniqueness beyond one message).
- **Receiver behaviour**: what a receiver must do, not what a message contains. The MSH-15 and MSH-16 acknowledgement protocol, enhanced mode, sequence numbers, and whether, when and with which code to acknowledge are the receiving application's (v2.5.1 CH02 sections 2.9.2 to 2.9.3); so are the ADRM's 74 receiver points.
- **Fragment reassembly**: a fragment (MSH-14 populated, or a trailing DSC with a continuation pointer or one its structure does not define) is not structure-checked, and fragments are not joined; that is the transport's job. A complete message carrying a continuation pointer is not structure-checked either.
- **Version provenance**: a message whose ``Message/version`` differs from its MSH-12, for example under a parser version override, is not structure-checked, because `Message` does not record which grammar it was validated under.
- **Structures with no checkable syntax**: 183 registered structures (templates, placeholders, Table 0354 rows nothing prints) report ``IssueCode/messageStructureNotModelled(structure:)`` instead of a body check. Where two prints share one trigger (v2.3 ORM_O01 and ORR_O02; MFK_M01 on v2.3.1 and v2.4) the looser governs; the v2.4 ADT^A31 print is unreadable and A31 takes the A05 print.
- **Structure-matcher ceilings** (ADR-019): where Z-segments sit is not checked; a structure that fails the determinism lint, or holds an open slot (`OBR, etc.`), is matched exactly and reports one finding, at the furthest segment reached, and nothing optional after a slot can be found misplaced; a defect can draw a second finding after the first divergence.
- **Group-scope peer lookups**: where the print ties no single group occurrence to a lookup (a container or specimen OBX beside repeating orders, v2.4 OML_O21, v2.7.1 and v2.8.2 ORU_R30), the scope rule's answer is not the print's; no shipped predicate reads those lookups.
- **AU partial points**: of the 17 partial points, the wire-decidable half ships and the rest needs a directory, identifier-scheme recognition, cross-message state, a timezone database, rendered comparison or a judgement; among them RXO, ODS or ODT in place of OBR in ORR^O02 and OSR^Q06 is accepted. Listed in <doc:AustralianLocalisation>.
- **AU permanent points**: same-concept codes, referral-summary recognition, the NASH directory and certificate halves, timezone correctness, receiver behaviour, digital signature content beyond p 438, and rendered-content equality.
- **Excluded versions**: v2.1, v2.2, v2.5, v2.8.1 and v2.9 have no text to model; they are validated against v2.5.1 with a warning. The differences between v2.7 and v2.7.1, and v2.8 and v2.8.2, are not verified.
- **Length edges**: conformance lengths (`40=`, `250#`, a bare v2.7+ integer) bound what a receiver stores, not the message; `*`, `64K`, 65536 and 99999 are not limits; a range printed on a composite field has no meaning there.
- **Primitive formats**: ID and IS have no lexical rule beyond being populated; the character rules of ST, TX and FT are not checked; a second of `60` is admitted; SI accepts any NM form of a non-negative integer (`1.0`, `+5`).
- **Composite width where no table exists**: CM on v2.3 to v2.4 without a field-local grammar, OBX-5 with no OBX-2, components printed with no datatype, and the open-ended NA and MA. A local Z extension cannot be declared per datatype; only ``ValidationOptions/extraComponentsSeverity`` governs it.
- **Withdrawn fields**: a `W` field the print leaves untyped (most of them on v2.6 to v2.8.2) gets the deprecation warning and no type-keyed check.
- **Undeclared local table extensions** (by design): a site's additions to a closed table are errors until declared through ``ValidationOptions/localTableExtensions``.
- **Where the print is silent**: no component optionality before v2.5 and no component normative length before v2.7, so neither is checked there; no table prints a normative length on a composite-typed component, and no grammar reaches below the subcomponent.
- **Typed API shape**: not a validation gap. Typed accessors are not gated by the message's version, pre-v2.5.1 spellings have no accessor, and a composite retyped between versions is reached through `viewed(as:)`; path access reaches every position.

## Filtering issues

```swift
let report = Validator().validate(message)

let errors = report.errors                    // severity .error
let warnings = report.warnings                // severity .warning
let infos = report.infos                      // severity .info

let missingFields = report.issues.filter { $0.code == .requiredFieldMissing }
let pidIssues = report.issues.filter { $0.location.segmentID == "PID" }
```

## Issue anatomy

Each ``ValidationIssue`` carries:

- ``ValidationIssue/severity``: ``IssueSeverity/info``, ``IssueSeverity/warning`` or ``IssueSeverity/error``.
- ``ValidationIssue/code``: the ``IssueCode``.
- ``ValidationIssue/location``: an ``IssueLocation`` with the segment ID, the 1-based occurrence of that segment, and optional field, component and subcomponent indices. `location.pathDescription` renders `PID[1]-3`, `PID[1]-3.4.3` or `ZAU[1]`.
- ``ValidationIssue/message``: a readable summary for logs or display.

## Conditional-field DSL

The condition on ``FieldGrammar/condition`` is a short string. In outline:

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

For example, `PID-37 populated` on PID-36 (v2.4 to v2.7.1): breed is required when strain is valued.

- **Cross-segment references** resolve against the message, scoped to the matched group occurrence where the structure check supplies one (<doc:#Message-structures>). A referent that does not resolve makes the atom unknown.
- **`populated` and `empty`** use the required-field rule (any subcomponent non-empty).
- **`=` and `!=`** compare the first subcomponent of the first component of the first repetition.
- **Three-state evaluation.** True, false or unknown, with Kleene AND and OR; a rule fires only on a definite true, so a malformed or unresolvable atom never makes an accepted message non-conformant.

Conditions live in the schemas under `Resources/schemas/<version>/` and are generated into ``SegmentGrammarTable``. See <doc:AddingASegment>.

## Message structures

The structure comes from MSH-9.3, or from MSH-9.1 and MSH-9.2 through the chapter caption lines when MSH-9.3 is empty. A structure ID the print gives for the trigger is never a mismatch (`ORU^W01^ORU_R01` is folded onto ORU_R01); a structure with no modelled syntax reports not modelled, naming the structure the chapters give. Where two prints of one structure ID differ by trigger, each governs the triggers it is printed for (``MessageStructure/variants``, ``MessageStructure/variant(messageCode:triggerEvent:)``). A choice keyed by a field value (MFN_M03 by MFI-1, ``StructureElement/keyedChoice(_:min:max:key:alternatives:)``), a structure alias (QRY_P04, ``MessageStructure/aliasOf``) and the master-file structures the print gives only as prose fragments are modelled, the last from cited transcriptions.

When no structure is applied, ``IssueCode/messageStructureNotModelled(structure:)`` says why: the structure is registered as not modelled (with its reason), MSH-12 is empty or does not resolve to the version validated, the trigger is printed under two structures and MSH-9.3 is empty, or the message is a fragment.

A query response of v2.4 to v2.8.2 whose MSA-1 is AE or AR is matched against the error response CH05 section 5.6.5 prints (MSH, MSA, ERR, QAK, the query defining segment and DSC; "The rest of the message is absent"), and so is a no-data response (MSA-1 AA with QAK-2 NF; an optional ERR is allowed). A structure that fails the determinism lint, or holds an open slot (``StructureElement/slot(_:min:max:citation:)``, the order detail printed `OBR, etc.`), is matched exactly: it reports at most one finding, at the furthest segment any parse reached, and its text names what the structure accepts there ("PID has no place in BAR_P01 at this point; expected here: SFT or EVN"). So a required segment missing mid-message is reported on the segment after it. Z-segments are left to ``ZSegmentPolicy``, ADD continuations are skipped, and a segment the version does not define is reported once, by ``IssueCode/segmentNotInVersionGrammar``.

Conditions that read a peer segment of the same group (ORC-2/3, OBR-2/3 and the group-scope counts) are scoped by the matched structure's group occurrences when the match is clean and its parses agree on the groups; otherwise the ORC walk applies, except on OUL (v2.5.1) and OUL, OPU and OPL (v2.6 to v2.8.2), whose structures print OBR before ORC, where the order-number conditions are withheld with ``IssueCode/conditionNotEvaluated(fields:)``.

Under ``HL7Locale/auLocalisation`` a v2.4 ORU^R01, ORM^O01, ORR^O02, REF^I12, RRI^I12 or OSR^Q06 is also matched against the structure ADRM-2021 prints for it: a segment it requires and the message lacks is ``IssueCode/profileConstraintViolation(localeRule:)`` with `"HL7au:00060.1"` at the structure severity; a base finding the ADRM structure accepts is dropped; a REF^I12 declaring an Appendix 8 identifier in MSH-12.3.1 is matched against the simplified structure.

Look structures up with ``MessageStructureTable``.

## See Also

- <doc:GettingStarted>
- <doc:AustralianLocalisation>
- ``Validator``
- ``ValidationReport``
- ``ValidationOptions``
- ``ValidationIssue``
- ``ZSegmentPolicy``
