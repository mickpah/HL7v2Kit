# Migration

Versioning contract and per-release migration notes for HL7v2Kit consumers.

## Overview

HL7v2Kit is at **`v1.0.0`** — the first stable release. The public API is now frozen under the evolution policy below (ADR-014); it has been stable since v0.5.0 and every change since was additive.

- **`1.x`**: strict SemVer under the evolution policy below (ADR-014). Additive-only in minors; breaking changes wait for `2.0`.
- **`0.x` (historical)**: pre-1.0 minors *could* make source-breaking changes (none did after v0.5.0), each called out in `CHANGELOG.md`.

## The v1.0 API evolution contract (ADR-014)

Once `v1.0.0` ships, the public surface is frozen under an **additive-only** rule for the `1.x` line:

**Allowed in a `1.x` minor:** new public types, methods, overloads, and conformances; new cases on the **open** enums below; new typed segments / grammar versions (these add members, never remove).

**Never in `1.x` (waits for `2.0`):** removing or renaming any public symbol; changing a method signature or an enum raw value; tightening access; removing a `Sendable` / `Equatable` / `Hashable` conformance.

### Open enums — may gain cases in a minor; switch with `@unknown default`

``Version``, ``HL7Locale``, ``IssueCode``, ``ParseError``, ``PathError``, ``BuilderError``.

These grow as the domain grows (new HL7 versions, localisation profiles, validation checks, failure modes). Each carries a DocC `- Note:` at its declaration. Consumer code that switches over them **must** include `@unknown default`:

```swift
switch message.version {
case .v2_5_1: …
case .v2_8_2: …
@unknown default: …   // required — new versions ship in minor releases
}
```

### Stable enums — closed by their domain

``FieldOptionality`` (R/O/C/X/B/W — HL7's complete optionality-code set), ``FieldRepeatability``, ``IssueSeverity``, `ZSegmentPolicy`, `LineTerminatorPolicy`, ``CharacterEncoding``, `RequiredComponentSet.Semantics`, and ``Segment`` (a closed typed/unknown sum-type). No growth is anticipated; the additive-only rule still governs if a domain ever surprises us.

> `@frozen` is **not** applied to any public enum. HL7v2Kit ships as an SPM *source* package (no library-evolution mode), so `@frozen` would be inert; the contract above is the SemVer promise, not a compiler attribute. See `docs/design/ADR-014-api-evolution-policy.md` and the surface inventory in `docs/design/public-api-surface.md`.

## The 2.0 boundary (R10 — first exercise of the "waits for 2.0" lane)

The 2026-08 remediation programme (`docs/design/remediation-plan.md`, stage R10)
retired the public surface that had accumulated dead behind the 1.x additive-only contract.
Every removal below shipped with **zero construction/call sites** in the package and its
tests — verified by grep at audit time (2026-08-26) and re-verified at removal (2026-08-27):

| Removed / changed at 2.0 | Evidence / migration |
|---|---|
| `HL7v2KitDictionaries` product + targets | Never imported outside its own scaffold test; superseded by the ADR-005 Path C codegen grammar tables |
| `BuilderError.invalidEncodingCharacters`, `.duplicateMSH` | Never thrown — `build()` throws only `.missingMSH` |
| `ParseError.malformedField` | Never thrown. (`ParseError.unknownSegment` is a distinct, live case and **stays**.) |
| `IssueCode.unknownSegment` | Never emitted — no-grammar segments route to `.zSegmentPresent` |
| `ParserOptions.preserveExcessFields` | Self-documented no-op since v0.1; never read |
| `ParserOptions.lenient` | Field-for-field identical to `.default`; use `.default` |
| `ValidationReport.empty` | Zero call sites; construct `ValidationReport(issues: [])` |
| `MessageBuilder.append(unknown:)` | Zero call sites, untested; will be re-added WITH a test if a copy-segments API is ever wanted |
| `RequiredComponentSet.init` — `description` is now a required `String` | Every shipped set already passed one explicitly; the generated-fallback `defaultDescription` is deleted |
| OBX-12 `effectiveDateOfReferenceRange` → `effectiveDateOfReferenceRangeValues`; OBX-15 `producersID` → `producersReference` | The v1.6-deferred swiftName corrections — accessors now match the spec's element names |

**Migrating:** switches over the open enums are unaffected when they follow the
`@unknown default` guidance — a removed case cannot break an exhaustive-with-default
switch; only constructions could, and none existed. Callers of removed symbols migrate
per the table. The additive-only contract resumes for the `2.x` line from `v2.0.0`.

## The 3.0 boundary (M6-D5 — owner-directed ADR-014 override, 2026-09-15)

The M6 audit found `OBX.observationValue` declared as `ST` (`String?`) in all six
schemas, where every version's attribute table gives OBX-5 the **variable** datatype
(`*` on v2.3/v2.3.1/v2.4, `varies` on v2.5.1/v2.6/v2.8.2) — the actual type is chosen
at runtime by OBX-2. A `String?` accessor silently flattened structured payloads
(CE, SN, ED, ...) to their first component. The project owner directed an ADR-014
override to fix the defect immediately rather than queue it (2026-09-15); the first
release containing it is therefore a **major** (`v3.0.0`).

| Changed at 3.0 | Migration |
|---|---|
| `OBX.observationValue`: `String?` → `Field?` | For scalar reads, append `?.stringValue` (`obx.observationValue?.stringValue`). For structured payloads, use the `Field` API (`.first?.components`), or path access (`message["OBX-5.2"]`). |

The schemas now store the spec's verbatim datatype (`*` / `varies`), matching the
`RDT-1` convention. This is the only ADR-014 exception granted for the 2.x line;
the additive-only contract otherwise continues and resumes for `3.x` from `v3.0.0`.

## API evolution since v0.5.0 (the stability anchor)

All additive — no source break for a consumer who follows the `@unknown default` guidance:

| Release | Additive change |
|---------|-----------------|
| v0.11.0 | `IssueCode.segmentCardinalityBelowMinimum` (ADR-010 group-scope cardinality) |
| v0.12.0 | v2.3 / v2.3.1 T-track grammar (no API surface change — schemas only) |
| v0.13.0 | AU composite-override narrowings (internal; reuses `.profileConstraintViolation`) |
| v0.14.0 | `Version.v2_6`; `FieldOptionality.withdrawn` (`W`) |
| v0.15.0 | `Version.v2_8_2` |
| v0.16.0 | Two shipped conditional predicates (schema metadata; no API surface change) |
| v0.17.0 | Conformance-limitations register (docs only) |
| v0.18.0 | ADR-014 evolution policy + public-API-surface inventory (DocC/docs only) |
| v0.19.0 | Canonical NK1/PV1/IN1 typed accessors extended to full depth (additive) |
| **v1.0.0** | **API frozen** — the surface above is now the SemVer contract |
| v3.3.0 | Code-table registry (ADR-016): `HL7Table`, `HL7TableRegistry`, `FieldGrammar.table`, `IssueCode.valueNotInTable(table:)`, `ValidationOptions.checkCodeTables`; `FieldGrammar.variableColumns` and plural accessors for the `1-n` segments RDT / ADD. **Additive API, but a new default check:** see below. |
| v3.4.0 | Datatype component grammar (ADR-017): `DataTypeGrammarTable`, `DataTypeGrammar`, `ComponentGrammar`. Additive API; the code-table check now also covers `ID` components on v2.5.1 / v2.6 / v2.8.2 messages. |
| v3.5.0 | `IssueLocation.subcomponentIndex` (additive; a defaulted initialiser parameter). The component code-table check descends into nested composites, covers OBX-5 under its OBX-2 datatype, and now runs on v2.3, v2.3.1 and v2.4 too. AU rules ADRM-prose P-8 to P-10 (the VMR sub-ID tree). AU locale renderings of Tables 0125 and 0301. Fix: Table 0301 `L,M,N` split into three codes. |
| v3.7.0 | `ValidationOptions.requiredComponentSeverity` (additive, defaulted `.error`). |
| v3.8.0 | `FieldGrammar.length`, `ComponentGrammar.length` (additive, defaulted): the printed LEN, verbatim, never enforced. |
| v3.9.0 | `ComponentGrammar.condition`, `IssueCode.conditionalComponentMissing` (additive; open enum). 36 conditional-component rules now checked at `requiredComponentSeverity`. |
| v3.10.0 | `ComponentGrammar.conformanceCondition`, `ValidationOptions.conformanceConditionSeverity` (default `nil`), `IssueCode.conformanceConditionMissing` (additive; open enum). Default output unchanged. |
| v3.11.0 | `repeated` token in the condition language (internal evaluator; no API change). v2.8.2 XAD.7 now reported as `conditionalComponentMissing` when the field repeats without a type. |
| v3.12.0 | `ValidationOptions.auPathologySender` and `ValidationOptions.auDisplayIntended` (additive, default `false`): HL7au:00050.1.5 and HL7au:00044.4.3 applied on the caller's assertion. Default output unchanged. |
| v3.13.0 | `ValidationOptions.auNASHTransport` (additive, default `false`): HL7au:00044.2.2 / .2.3 applied on the caller's assertion. Default output unchanged. |
| *Unreleased* | `ValidationOptions.localTableExtensions` (additive, default `[:]`, not an init parameter), `HL7Table.patterns` and `HL7Table.CodePattern` (additive), and an `HL7Table.init` overload that also takes `patterns:`; the released initialisers are unchanged. `auNASHTransport` now also applies HL7au:00044.3.4 / .3.3 to every EI (ORC-2/-3/-4, OBR-2/-3 on the AU profile). Default output unchanged. Version handling (ADR-018) adds `Version.grammarVersion` and three `IssueCode` cases, `segmentNotInVersionGrammar`, `versionGrammarSubstituted(declared:validatedAs:)` and `versionNotRecognised(wireValue:)` (additive; open enum). It changes default output in five ways: (1) a `2.8` message is validated against the v2.8.2 grammar and carries its findings plus one info issue, where before nothing was checked; (2) a non-Z segment the version does not define is a warning under every `zSegmentPolicy`, including the default `.ignore`, where it was silent, and is no longer reported as a Z-segment (an error under `.reject`); (3) a VID-form MSH-12 (`2.4^AUS&Australia&ISO3166_1^...`) resolves to its VID.1 version instead of falling back to v2.5.1, so AU v2.4 traffic no longer gets the v2.5.1 MSH-9.2 / MSH-9.3 base findings, and it gains the AU profile findings HL7au:00049.1, 00044.1.1, 00044.3.1 and 00044.7.1 where those components are empty (00044.3.1 and 00044.7.1 fire on every version, as no version's base model requires EI.1 or XCN.1); (4) an MSH-12 that is populated but names no modelled version (an unmodelled version, or a VID.1 that is empty, whitespace only or subdivided) carries a `versionNotRecognised` warning naming the v2.5.1 fallback; (5) `ParserOptions.strict` (`rejectUnknownVersion`) now throws `unsupportedVersion` for those same shapes, including a VID-form MSH-12 with an unknown VID.1, an empty VID.1 with VID.2 valued, and a subdivided VID.1, which v3.13.0 let fall back silently. A whitespace-only MSH-12 still throws under `.strict`, as in v3.13.0, but `found:` is now the trimmed VID.1 (`""`) rather than the raw whitespace. An empty MSH-12 falls back without a version issue in every mode, as before. P2-15 adds `FieldGrammar.tableOpen` (additive, default `false`) and the schema key `tableOpen`, skipping the closed-table check on 49 fields cited "for suggested values". P4 adds `FieldGrammar.prohibitedSeverity` (additive, default `.error`) via a separate `init` overload (the released initialiser is unchanged); `FieldGrammar.additionalProhibitions: [FieldProhibition]` (additive, default `[]`); and the new public `FieldProhibition` type (`condition`, `severity`, `permitsNull`, defaulted `false`). Default output changes wherever a new condition or prohibition fires (see "Added/Fixed/Changed — P4: expressible conditions" in `CHANGELOG.md` for the full field list): previously-silent `C` fields across all six versions now raise `conditionalFieldMissing` or `conditionalFieldProhibited` where their own spec text states a trigger the DSL did not express before. The `SPEC_EXAMPLE_MESSAGES` regression test's exception registry (`scripts/extract-example-messages.py --check-registry`) grew to 138 entries to match; none of the growth is a new predicate defect — see `docs/design/conditional-completeness-audit.md` "Shipped in P4". P4-30 moves three printed-`R` fields to `C` against their own restricting definitions: `MFI-6` (`messageCode = MFN`, all six versions), `CSR-8` (`triggerEvent = C01`, all six versions) and `ROL-4` (`STF absent`, v2.6 and v2.8.2). On these three, the issue code moves from `requiredFieldMissing` to `conditionalFieldMissing` when the condition holds, and nothing fires when it does not. `RXA-4` stays `R` on all six versions — its "If null" names the HL7 null `""`, which satisfies `R`, so an empty `RXA-4` still raises `requiredFieldMissing`. The schema gained an internal `optionalityCitation` key for these rulings, decoded by codegen but not emitted on `FieldGrammar`. HL7au:00060.4 route C (P4-31, ADR-021; no API change): under ``HL7Locale/auLocalisation`` an ORM, ORU or REF that values v2.4 `OBX-2` while `OBX-11` is `X` (other than with the HL7 null `""`) now reports `.profileConstraintViolation` HL7au:00060.4 as an error, where it was silent. The condition evaluator is internally three-state; ``HL7Locale/international`` output is unchanged. P4-32 (owner decision G7; no API change): under ``HL7Locale/auLocalisation`` an ORM, ORU or REF that values OBR-29 (other than with the HL7 null `""`) now reports `.profileConstraintViolation` `ADRM-prose:P-13` as a warning, where it was silent — matching the existing OBR-26 `ADRM-prose:P-11` warning's mechanism and scope. This can fire alongside the base `conditionalFieldMissing` check on a v2.3–v2.6 child order (`ORC-1 = CH`) sent without ORC-8, which already requires OBR-29 populated; the two findings on the same message are an accepted, owner-ruled tension, not a defect. ``HL7Locale/international`` output is unchanged. Two typed accessors whose v3.13.0 names carried extractor prose are renamed to the printed element name (P6-9): TQ2-10 ``TQ2/specialServiceRequestRelationship`` (was the 873-character `specialServiceRequestRelationshipRequestsUsingTheParentChild...` name) and QPD-2 ``QPD/queryTag`` (was `queryTagUserParametersInSuccessiveFields`). The old names remain as deprecated aliases that forward to the new ones, so released source still compiles; the compiler's rename fix-it moves a call site across. P6-4 adds `FieldGrammar.maxRepetitions: Int?` (additive, default `nil`) via a separate `init` overload (the released initialisers are unchanged), and `FieldRepeatability(wireValue:)` maps a decimal of 2 or more to `.multiple`: `FieldRepeatability(wireValue: "3")` used to give `.single` and now gives `.multiple`. A non-nil `maxRepetitions` with `.single` or a value below 2 traps in the initialiser. Default output changes where a field carries more `~`-repetitions than its printed RP/# bound (`Y/3`, `3`): a `cardinalityExceeded` warning, where it was silent. ADJ-7 on v2.6 and v2.8.2 prints RP/# `1` and is now single-cardinality, so a repeated ADJ-7 raises `cardinalityExceeded` as an error. |
| *Unreleased* | `IssueCode.fieldLengthOutOfRange(length:actual:)` (additive; open enum), `ValidationOptions.fieldLengthSeverity` and `ValidationOptions.normativeLengthSeverity` (additive, `IssueSeverity?`, default `.warning`, `nil` in `.lenient`, not init parameters). P6-6: LEN is now checked; see below. |
| *Unreleased* | `IssueCode.extraComponentsInPrimitiveField` (additive; open enum) and `ValidationOptions.extraComponentsSeverity` (additive, `IssueSeverity?`, default `.warning`, `nil` in `.lenient`, not an init parameter). P6-13: more issues may fire by default; see below. | P6-14 widens it to every primitive field and to subcomponents of primitive components (more warnings by default; no API change).
| *Unreleased* | `IssueCode.extraComponentsInCompositeField` (additive; open enum), governed by the existing `ValidationOptions.extraComponentsSeverity`. P6-15: more warnings may fire by default; see below. |
| *Unreleased* | `IssueCode.valueFormatInvalid(dataType:)` (additive; open enum) and `ValidationOptions.valueFormatSeverity` (additive, `IssueSeverity?`, default `.warning`, `nil` in `.lenient`, `.warning` in `.strict`; not an init parameter). Malformed NM, SI, DT, TM, DTM and TS values now raise a warning. |
| *Unreleased* | `ValidationOptions.repetitionBoundSeverity` (additive, `IssueSeverity?`, default `.warning`, `nil` in `.lenient`, `.warning` in `.strict`; not an init parameter). P6-4 final review: the ``IssueCode/cardinalityExceeded`` bound warning's severity is now configurable; the single-cardinality error (gated by `checkCardinality`) is unaffected. |
| *Unreleased* | `DataTypeGrammarTable.grammar(segment:field:version:)` (additive static function): the component grammar a v2.3 to v2.4 `CM` field prints on its own Components line (P5-5). `grammar(_:version:)` is unchanged. The validator does not read it yet, so default output is unchanged. |
| *Unreleased* | No API change. P5-6: the validator now reads `DataTypeGrammarTable.grammar(segment:field:version:)`, so a v2.3 to v2.4 `CM` field (and the v2.3 to v2.4 MSG, EIP, MOC, PRL, PTS and SVC fields) is checked against the components its own definition prints: width (`extraComponentsInCompositeField`), primitive subcomponents, value format, and closed HL7 component tables. More issues may fire by default: `valueNotInTable` errors on IN3-20.2 (0136), BLG-1.1 (0100), PRA-5.3 (0337), and on a CE component (OBR-15.1 0070, OBR-15.4 0163, ERR-1.4 0357, SAC-6, TCC-3) whose CE.3 explicitly names the table (`HL7nnnn`, case-insensitive); an empty or other coding system is not checked, and the same CE rule now also applies to v2.5.1 ELD.4 (0357). IS bindings and the open MSH-9 tables stay unenforced. v2.3.1 / v2.4 PRA-7 now has five components (a misprinted `&` in its Components line). P5-7: on v2.3 to v2.4, `SegmentGrammarTable` reports OBR-15 and OBR-32 to OBR-35 as `CM`, the type their attribute tables print, where it reported the v2.5-era `SPS` and `NDL`; those structures differ (OBR-15.2 additives TX vs SPS.2 CWE, OBR-32.1 CN vs NDL.1 CNN). Typed accessors stay `Field?` and validation is unchanged, as it already read each field's own components. |

## Extra components in composite fields (P6-15)

A composite field repetition with a populated component beyond its datatype's component table on the message's version (an XPN with a 15th component on v2.5.1), and a composite component with a populated subcomponent beyond its own datatype's table (a sixth FN subcomponent in XPN.1), used to pass silently. They now raise ``IssueCode/extraComponentsInCompositeField``, a warning by default: a recipient ignores components "present but were not expected" (v2.5.1 and v2.8.2 section 2.6.2 a), a later version may add components at the end of a data type (section 2.8.1), and a local extension adds them the same way, making the extended value a Z data type (section 2.11.5 c). No source break, but validation results may carry more warnings.

- **Not checked:** trailing empty components, escaped `\S\` and `\T\`, a datatype the version prints no component table for (CM on v2.3 to v2.4, OBX-5 `varies` with no OBX-2), and the open-ended arrays NA and MA. OBX-5 takes the datatype OBX-2 names.
- **Under version substitution:** a message whose MSH-12 is absent or not recognised is validated against the v2.5.1 grammar (ADR-018), so a value a later version widens, such as a 9-component CWE in a field that is CE in v2.5.1, may raise this warning.
- **Length:** unchanged; a composite field's length still measures the whole occurrence.
- **To drop the new warnings:** set `options.extraComponentsSeverity = nil`, as the ``ValidationOptions/lenient`` preset does. This also drops ``IssueCode/extraComponentsInPrimitiveField``.
- **If you switch over `IssueCode`:** it is an open enum; the new case lands in your `@unknown default` branch.

## Primitive value format is checked (P6-7)

Populated NM, SI, DT, TM, DTM and TS values are now checked against the format their datatype section prints, on every version, including the components of composites (TS.1, MO.1, CQ.1, SN.2, XTN.5 to XTN.8, XPN.12 and the rest, one level of subcomponents down) and OBX-5 by its OBX-2 type. No source break, but validation results change: an NM of `<5`, a DT of `1980-01-01` or a timestamp with an impossible month now raises ``IssueCode/valueFormatInvalid(dataType:)`` at `.warning` (owner gate G4), so it does not fail validation by default.

- **To make a malformed value fail validation:** set `options.valueFormatSeverity = .error`.
- **To keep the old results:** set `options.valueFormatSeverity = nil`. The ``ValidationOptions/lenient`` preset already does.
- **If you switch over `IssueCode`:** it is an open enum; the new case lands in your `@unknown default` branch.

## Extra components in every primitive (P6-14)

``IssueCode/extraComponentsInPrimitiveField`` used to cover `ID` and `IS` fields only. It now covers every primitive field of the message's version (ST, NM, DT, TM, DTM, SI, TX, GTS, SNM and the rest), and a primitive component of a composite that carries a subcomponent after its value (located at that component). So more warnings fire by default: an ST field carrying `a^b`, an NM carrying `12^abc`, or a CX.1 carrying `12&3` now warns. No API changed; the issue code and ``ValidationOptions/extraComponentsSeverity`` are the same.

- **Shapes the spec allows stay silent:** the TS degree-of-precision component on v2.3 to v2.4, the component separators that mark FT lines, one observation ID suffix in OBX-3.1, OBX-3.4 or (v2.8.2) OBX-3.10 (`71020&IMP`), the QIP.2 value list (`@PID.3^123&456` in SPR-4 or ERQ-3), escaped `\S\` and `\T\`, and trailing empty components.
- **Component table check:** an `ID` component carrying `Q&B` used to skip its table check. Its first subcomponent is now checked, and an issue for it is located at subcomponent 1.
- **Length collapse:** the same severity rule as P6-13 now applies to every primitive field.
- **To drop the new warnings:** set `options.extraComponentsSeverity = nil`, as the ``ValidationOptions/lenient`` preset does.

## Multi-component values in ID and IS fields (P6-13)

The field-level code-table check used to skip an `ID` field repetition with more than one component or subcomponent. It now checks the first component, the value a recipient reads (v2.5.1 and v2.8.2 section 2.6.2 a: ignore components "present but ... not expected"), so more ``IssueCode/valueNotInTable(table:)`` errors may fire by default; such an error is located at component 1 (`TQ2[1]-10.1`). A new ``IssueCode/extraComponentsInPrimitiveField`` warning reports content after the first value of an `ID` or `IS` field: an unescaped component or subcomponent separator. An escaped `\S\` is part of the value and stays silent. While that warning is on, an `ID` or `IS` field's length is measured on its first value, so the same cause is not reported twice.

- **Length collapse respects severity:** the first-value length applies only while `extraComponentsSeverity` is at least as severe as the length severity that applies (`normativeLengthSeverity` from v2.7, `fieldLengthSeverity` before); if you raise a length severity to `.error`, the whole occurrence is measured and the length error still fires.
- **Under version substitution:** a message whose MSH-12 is not recognised (such as `2.7`) is validated against the v2.5.1 grammar (ADR-018), so a value a later version allows, such as a CWE in a field that is `IS` in v2.5.1, may raise the extra-component or length warning.
- **To drop the new warning:** set `options.extraComponentsSeverity = nil`; the length check then measures the whole occurrence again. The ``ValidationOptions/lenient`` preset already does. The table check on the first component stays on while `checkCodeTables` is `true`.
- **If you switch over `IssueCode`:** it is an open enum; the new case lands in your `@unknown default` branch.

## Field length is checked (P6-6)

`FieldGrammar.length` was recorded and never enforced. It is now checked per repetition, separators counted, on every version. No source break, but validation results change: a field longer than the pre-v2.7 printed maximum, or a primitive v2.7+ field outside its normative `m..n` / `x,y,z` length, now produces ``IssueCode/fieldLengthOutOfRange(length:actual:)``. Both checks report warnings by default, so ``ValidationReport/isValid`` and `errors` are unchanged.

- **To keep the old results:** set `options.fieldLengthSeverity = nil` and `options.normativeLengthSeverity = nil`. The ``ValidationOptions/lenient`` preset already does.
- **To make v2.7+ normative lengths binding:** set `options.normativeLengthSeverity = .error` (v2.8.2 section 2.5.5.0: conformant messages SHALL lie within them).
- **If you switch over `IssueCode`:** it is an open enum; the new case lands in your `@unknown default` branch.
- **Schema lengths corrected (owner ruling G10):** 18 pre-v2.7 LEN cells that were shorter than values their own spec defines as valid now carry the corrected length, so `FieldGrammar.length` reads, for example, `"15"` for v2.4 MSH-9 (printed 13) and `"3"` for v2.5.1 OBX-2 (printed 2). The full list and derivations are in the permanent-limitations register, section C.

## Bounded repetitions (P6-4)

`FieldGrammar.maxRepetitions: Int?` now carries the printed RP/# bound (`Y/3` before v2.5, `3` from v2.5) for 221 fields across the six versions, and `FieldRepeatability(wireValue:)` maps a decimal of 2 or more to `.multiple`. No source break, but default output changes in three places:

- **The bound warning:** a field carries more `~`-repetitions than its printed bound and ``IssueCode/cardinalityExceeded`` fires at `options.repetitionBoundSeverity` (`.warning` by default), where it was silent. The pre-existing single-cardinality check (a `.single` field with more than one repetition) is unaffected and stays an `.error` gated by `checkCardinality`, never by `repetitionBoundSeverity`.
- **ADJ-7 on v2.6 and v2.8.2:** prints RP/# `1` and is now single-cardinality (the old extractor read any digit as a repeat), so a repeated ADJ-7 raises `cardinalityExceeded` as an error, where it was silent.
- **v2.5.1 OBX-20 to 22 (P6-12):** these fields' OPT cell prints blank, which is now stored verbatim (`""`) instead of the `X` the extractor previously read. The validator treats a blank OPT as optional, so a populated OBX-20/-21/-22 is no longer reported as not supported (`fieldNotSupported`), where it was.

- **To keep the old bound-warning results:** set `options.repetitionBoundSeverity = nil`. The ``ValidationOptions/lenient`` preset already does.
- **To make an over-bound field fail validation:** set `options.repetitionBoundSeverity = .error`.
- **A non-nil `maxRepetitions` traps** in `FieldGrammar`'s initialiser when paired with `.single` repeatability or a bound below 2.

## The code-table check is on by default (ADR-016)

The registry release adds no source break, but it does change validation results. A message that carried an out-of-table value in an `ID` field bound to a closed HL7 table (1,073 fields across the six versions) used to validate clean and now reports ``IssueCode/valueNotInTable(table:)`` as an error.

- **To keep the old results:** set `options.checkCodeTables = false`. The ``ValidationOptions/lenient`` preset already does.
- **If you switch over `IssueCode`:** it is an open enum; the new case lands in your `@unknown default` branch.
- **Component level too (ADR-017):** on v2.5.1, v2.6 and v2.8.2 messages the same check covers `ID` components such as `CX.5`, `XPN.7`, `XTN.2` and `XAD.7`. A value in the wrong field is the usual cause: a provider name left in OBR-17 (a phone number) reports `OBR[1]-17.2`.
- **Validate Australian traffic with the AU locale.** Base v2.4 rejects values the ADRM adds: `OBX-2` of `CWE` / `DR` / `CNE` / `EI` (Table 0125), a universal ID type of `AUSNATA` in `MSH-4.3` (Table 0301), and `UNICODE UTF-8` below. Under ``HL7Locale/auLocalisation`` all are valid.
- **AU v2.4 traffic declaring `UNICODE UTF-8` in MSH-18:** an error under ``HL7Locale/international``, because base v2.4 Table 0211 does not print it, and accepted under ``HL7Locale/auLocalisation``, because ADRM-2021 back-ports it. Validate AU traffic with the AU locale.

## Required components follow the printed spec (ADR-017, M14)

Until now the Validator took required components from hand-written lists applied to every version. Eight of them contradicted the component tables they cited, so results change in both directions:

- **No longer errors:** a populated `XAD` with no street line, `XPN` with no family name, `XCN` / `XON` / `CE` / `EI` with no first component, and (before v2.8.2) `PT` / `VID` with none. The spec prints all of these as optional.
- **Newly errors, on v2.5.1 and later messages:** an `MSH-9` without its trigger event or message structure (`ADT^A01` must be `ADT^A01^ADT_A01`), because the spec prints all three `MSG` components as required from v2.5; on v2.8.2 also `CX.5`, `PT.1`, `VID.1` and `XTN.3`; and the `R` components of the other printed datatypes (`ED.2` / `ED.4` / `ED.5`, `TS.1`, ...).
- **Unchanged:** v2.3 to v2.4 messages, which print no component optionality, now have nothing required of them at component level; localisation rules (the AU profile) keep their own requirements.
- **Either-or rules (v3.7):** `XTN`, `PL`, `CWE` and `EIP` no longer carry one. The first three rejected the spec's own examples: a delimited phone number (`^ORN^FX^^^734^6777777`), a location with only its person location type, an uncoded `CWE` with only its text. `HD` keeps its rule.
- **Relaxing without disabling (v3.7):** `options.requiredComponentSeverity = .warning` keeps the findings and makes the report valid. It applies to every required-component finding, not just `MSH-9`; the default stays `.error`.
- `XPN.requiredComponents` and its siblings now hold what v2.5.1 prints and are informational; `checkComponentGrammar = false` still turns the whole check off.

## Historical: 0.1.0 → 0.5.0

The early minors (0.2–0.5) included source-breaking refactors while the surface settled: typed-composite accessors moving from raw `Field?` to struct views (`XPN`/`CX`/`XAD`), component-level and conditional-field validation, the MLLP codec, and the `HL7Locale` API. These predate the v0.5.0 stability anchor; consumers starting at v0.5.0+ are unaffected. Full detail is in `CHANGELOG.md` and the `docs/archive/` snapshots.

## v1.0 gates — all met (v1.0.0)

1. **M1 version coverage** — ✅ v2.3 → v2.8.2 (v0.14 / v0.15).
2. **M2 conformance surface** — ✅ v0.16 conditional register + v0.17 permanent-limitations register.
3. **M3 API stabilisation** — ✅ v0.18 (ADR-014 + the public-API-surface inventory + this contract).
4. **M4 IP review** — ✅ cleared (2026-07-09); public push unblocked.

## See Also

- `docs/design/ADR-014-api-evolution-policy.md` — the evolution policy this contract implements
- `docs/design/public-api-surface.md` — the full v1.0 public-symbol inventory
- `CHANGELOG.md` (repository root) — per-release detail
- ``Version`` · ``IssueCode`` · ``HL7Locale``
