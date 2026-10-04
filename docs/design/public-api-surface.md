# Public API surface — v1.0 inventory (v0.18, ROADMAP M3)

> **2.0 boundary note (2026-08-27, R10):** this inventory describes the surface at the
> **v1.0** boundary. The R10 remediation stage removed the dead surface enumerated in
> `Migration.md` → "The 2.0 boundary" (Dictionaries product, four never-raised enum cases,
> two no-op `ParserOptions` members, `ValidationReport.empty`, `MessageBuilder.append(unknown:)`),
> tightened `RequiredComponentSet.init`, and applied the OBX-12/15 swiftName corrections
> (`effectiveDateOfReferenceRangeValues`, `producersReference`). One public **type** was added
> since this compile: the `CompositeView` protocol (R3 — the shared surface of the 16 composite
> views; additive under ADR-014), taking the type count 74 → 75 before typed-segment growth
> (15 codegen'd segments at compile time → 109 today, all additive).
> P8-3 (ADR-019, unreleased) adds three hand-written public types, `MessageStructure`,
> `StructureElement` and `MessageStructureTable` (see "Message structures" below), and P8-7
> (ADR-019 decision 9, unreleased) adds `AcknowledgmentCode`, the static method
> `MessageBuilder.acknowledgment(to:code:messageControlID:dateTime:)` and the case
> `BuilderError.acknowledgedMessageControlIDMissing` (see "Acknowledgment builder").
>
> **Recount (P8-8, 2026-10-02).** The running "75 → 78 → 79" tally this note used to carry
> was wrong: it omitted 11 public types added after the v1.0 compile (`BatchValidator`,
> `BatchValidationReport`, `ComponentGrammar`, `DataTypeGrammar`, `DataTypeGrammarTable`,
> `FieldProhibition`, `HL7Table`, `HL7Table.Kind`, `HL7Table.Entry`, `HL7Table.CodePattern`,
> `HL7TableRegistry`; nine of them released by v3.13.0, `HL7Table.CodePattern` and
> `FieldProhibition` unreleased, checked with the same grep at the `v1.0.0` and `v3.13.0`
> tags). The "Public types" section below is a fresh inventory, every type
> listed, derived with the command under **Method**.

**Compiled:** 2026-07-09 (v0.18 cycle, ROADMAP M3 API stabilisation).
**Purpose:** the authoritative inventory of every `public` symbol at the v1.0 boundary, each confirmed *intended, minimal, and documented*, and classified per the ADR-014 evolution policy (open vs stable). This is the M3 gate: the surface a v1.0 tag freezes under the additive-only 1.x contract.
**Method:** `grep "public (struct|enum|final class|actor|protocol)"` over `Sources/HL7v2Kit/` + per-enum case enumeration. At the v1.0 compile: 74 public types (59 hand-written + 15 codegen'd typed segments). No accidentally-`public` internals found.
**Recount (P10-8, 2026-10-03):** the same command gives 263 public types (75 hand-written, 4 of them nested; 188 generated): P10 added no type. Its public additions are members: `Version.v2_7_1`, `Version.v2_7`, `ITM.itemNaturalAccountCodeAsCWE` and the generated statics `HL7TableRegistry.v2_7_1` and `SegmentGrammarTable.v2_7_1`.

**Recount (P8-8, 2026-10-02):** `grep -rE '^[[:space:]]*public (indirect )?(struct|enum|final class|class|actor|protocol) [A-Za-z0-9_]+' Sources/HL7v2Kit`, split on `/Generated/`, nested types counted by indentation. 263 public types: 75 hand-written (71 top-level, 4 nested: `RequiredComponentSet.Semantics`, `HL7Table.Kind`, `HL7Table.Entry`, `HL7Table.CodePattern`) and 188 generated segment structs (`Segment/Generated/`; the other `Generated/` directories declare no public type). No `public typealias`. `SegmentRegistry` is internal.

## Public types (263: 75 hand-written, 188 generated)

### Core model & parsing (22)
`Message`, `Segment` (enum), `Field`, `Repetition`, `Component`, `Subcomponent`, `EncodingCharacters`, `CharacterEncoding` (enum), `Path`, `PathError` (enum), `Parser`, `ParserOptions`, `ParseError` (enum), `LineTerminatorPolicy` (enum), `BatchParser`, `StreamingBatchParser`, `BatchFile`, `BatchGroup`, `MessageBuilder`, `BuilderError` (enum), `Version` (enum), `HL7Locale` (enum).

### Typed segments (codegen'd — 188) + support
One struct per segment with a schema under `Resources/schemas/` (188, for example `MSH`, `PID`, `OBR`, `OBX`, `PRT`); `SegmentRegistry` (its generated extension, `SegmentRegistry+Generated.swift`) hydrates each one by segment ID and is the full list (it is internal, not a public type). Plus 3 hand-written support types: `TypedSegment` (protocol), `AnyTypedSegment`, `UnknownSegment`.
Since P9 (ADR-020): the generated segment structs carry 3603 public accessors (3602 at P9 close, 2556 before P9-4; P10-4d added `ITM.itemNaturalAccountCodeAsCWE`). Every repeating field has `<name>All` (629: `[<View>]`, `[String?]` or `[Field]`, in wire order, unfiltered). Each struct carries its base schema's accessors plus 485 version-union accessors: 208 later element names, 187 `<name>As<T>` views and 90 further `All` accessors. (At P9 close: 510, of which 231 later names (222 later-version fields past the base maximum or at a reserved position, 9 renames kept because the type differs), 186 views and 93 `All`. P10-4d gave ITM's v2.6 base its 29 printed fields, so ITM-7 to ITM-29 moved from the union to the base: 23 names and 3 `All` accessors, and added one view.) One accessor per element and Swift type; a same-type rename is a DocC note. OBX-20 to OBX-22 are the only redefinitions. `TypedSegment.repetitions(_:)` is public (additive). Pinned two ways. `SegmentReleasedSurfaceTests` and `CompositeReleasedSurfaceTests` check that every declaration released at v3.13.0 is still declared with the same name and type (a superset check), and `SignatureCompatibilityTests` pins the released public initialiser signatures at compile time. `AccessorSurfaceSnapshotTests` checks the whole unreleased accessor surface for equality against `Tests/Fixtures/APISurface/segment-accessors-unreleased.txt` (3603 `File|name|type|field index` lines) and `composite-accessors-unreleased.txt` (181 `File|name|type|component index` lines), so any rename, retype, drop, addition or re-index fails until the snapshot is regenerated; it is promoted to the release snapshot at tag time.
*The typed structs and their accessors are generated by `HL7v2KitCodegen` from `Resources/schemas/`; their shape is governed by the schemas + codegen, not hand-edited. Additive under 3.x per ADR-014 (new segments/versions add members, never remove). Since P10-3 (ADR-020 amendment) a released struct's base schema is pinned in `Resources/struct-bases.json`, so adding a version that defines a segment earlier never renames or retypes a released accessor.*

### Composites (17: 16 views + `CompositeView`)
`HD`, `MSG`, `PT`, `VID`, `XPN`, `CX`, `XAD`, `CE`, `CWE`, `EI`, `XCN`, `XON`, `EIP`, `PL`, `CNE`, `XTN`, and the `CompositeView` protocol (R3).
Every component that any supported version defines has a named accessor (hand-written, or generated into `Composite/Generated/` from `Resources/composites/composite-views.json` and the datatype tables; ADR-020): 102 generated `String?` accessors on CX, XPN, XAD, XCN, XTN, PL, CWE, CNE and XON, withdrawn components kept, composite components without a view (DR, TS) documented as raw. `CompositeView` adds `component(_:as:)` (nil only for an absent component) and `viewed(as:)` (P9-2, additive).

### Validation (19)
`Validator`, `ValidationReport`, `ValidationIssue`, `ValidationOptions` (P8-5 adds `messageStructureSeverity`, `IssueSeverity?`, `nil` in every preset; not an init parameter), `IssueLocation`, `IssueCode` (enum; P8-5 adds `messageStructureSegmentMissing(structure:segmentID:group:)`, `messageStructureSegmentUnexpected(structure:segmentID:)`, `messageStructureMismatch(declared:trigger:)` and `messageStructureNotModelled(structure:)`), `IssueSeverity` (enum), `BatchValidator`, `BatchValidationReport`, `SegmentGrammar`, `FieldGrammar` (P6-4 adds `maxRepetitions`), `FieldProhibition`, `FieldOptionality` (enum), `FieldRepeatability` (enum), `SegmentGrammarTable` (enum namespace; one public per-version static per modelled version, P10-6 adds `SegmentGrammarTable.v2_7_1`), `RequiredComponent`, `RequiredComponentSet`, `RequiredComponentSet.Semantics` (nested enum), `ZSegmentPolicy` (enum).

### Datatype component grammar (3; ADR-017)
`DataTypeGrammar`, `ComponentGrammar`, `DataTypeGrammarTable` (enum namespace).

### Code tables (5; ADR-016)
`HL7Table`, `HL7Table.Kind` (nested enum), `HL7Table.Entry`, `HL7Table.CodePattern`, `HL7TableRegistry` (enum namespace; P10-1 adds the public static `HL7TableRegistry.v2_7_1`, generated, 535 tables).

### Message structures (3; P8-3, ADR-019; unreleased)
`MessageStructure` (struct: `id`, `version`, `triggers`, `citation`, `elements`, `accepts(messageCode:triggerEvent:)`; the memberwise initialiser is internal since the P8 final review), `StructureElement` (indirect enum: `segment(_:min:max:)`, `group(_:min:max:elements:)`, `choice(_:min:max:alternatives:)` (P8b-6, the print's `< X | Y >`), `min`, `max`, and the walker `children` and `segmentIDs`, which cover every case (P8b-6, pinned in `SignatureCompatibilityTests.structureChoiceAndWalker`); **open**: its DocC carries the `@unknown default` note), `MessageStructureTable` (enum namespace: `structure(_:version:)`, `structures(messageCode:triggerEvent:version:)`, both resolving `Version.grammarVersion`). Generated into `Structures/Generated/` from `Resources/structures/`; pinned in `SignatureCompatibilityTests` (`accepts` by function type since P8-8). The Validator reads it only when `ValidationOptions.messageStructureSeverity` is set (P8-5); only v2.5.1 `ADT_A01`, `ORU_R01` and `ACK` are modelled.

### Acknowledgment builder (1; P8-7, ADR-019 decision 9; unreleased)
`AcknowledgmentCode` (enum, HL7 Table 0008: `applicationAccept` `AA`, `applicationError` `AE`, `applicationReject` `AR`, `commitAccept` `CA`, `commitError` `CE`, `commitReject` `CR`; **open**), `MessageBuilder.acknowledgment(to:code:messageControlID:dateTime:)` (static, `throws -> Message`) and `BuilderError.acknowledgedMessageControlIDMissing`. Builds the general ACK; no protocol logic.

### Transport (2)
`MLLP` (enum namespace), `MLLPUnframer`.

### Enums (22: 8 open, 9 stable, 5 namespaces; recounted P8-8, which added `HL7Table.Kind`, `DataTypeGrammarTable` and `HL7TableRegistry` to this table) — evolution classification per ADR-014

| Enum | Cases | Class | Note added |
|------|-------|-------|-----------|
| `Version` | 9 (v2_3 … v2_6, v2_7_1, v2_7, v2_8_2, v2_8; v2_7_1 and v2_7 unreleased, P10-6) | **Open** | yes — `@unknown default` |
| `HL7Locale` | 2 (international, auLocalisation) | **Open** | yes |
| `IssueCode` | 25 | **Open** | yes (count corrected + `.segmentCardinalityAboveMaximum` added, M6-A-3 2026-09-15; the "12" predated the R10 removals; recounted at 18 when P6-6 added `.fieldLengthOutOfRange(length:actual:)`; 20 after P6-13 `.extraComponentsInPrimitiveField` and P6-7 `.valueFormatInvalid(dataType:)`; 21 after P6-15 `.extraComponentsInCompositeField`; 25 after P8-5 `.messageStructureSegmentMissing(structure:segmentID:group:)`, `.messageStructureSegmentUnexpected(structure:segmentID:)`, `.messageStructureMismatch(declared:trigger:)` and `.messageStructureNotModelled(structure:)`) |
| `ParseError` | 7 (corrected from 8 in P8-8; counted from the source, the same 7 at `v3.13.0`) | **Open** | yes |
| `PathError` | 3 | **Open** | yes |
| `BuilderError` | 2 (`missingMSH`; `acknowledgedMessageControlIDMissing` added by P8-7; the v1.0 compile's 3 lost two never-thrown cases in R10) | **Open** | yes |
| `FieldOptionality` | 6 (R/O/C/X/B/W) | **Stable** — HL7's complete optionality-code set | — |
| `FieldRepeatability` | 2 (single, multiple) | **Stable** | — |
| `IssueSeverity` | 3 (info, warning, error) | **Stable** | — |
| `ZSegmentPolicy` | (reject/warn/allow family) | **Stable** | — |
| `LineTerminatorPolicy` | 2 (strict, lenient) | **Stable** | — |
| `CharacterEncoding` | (encoding family) | **Stable** | — |
| `RequiredComponentSet.Semantics` | (and/or family) | **Stable** | — |
| `Segment` | typed / unknown sum-type | **Stable** (shape closed; the *set of typed segments* grows additively via new struct members, not new `Segment` cases) | — |
| `StructureElement` | 3 (segment, group, choice) | **Open** (P8-3; `choice` added in P8b-6, ADR-019) | yes |
| `AcknowledgmentCode` | 6 (AA, AE, AR, CA, CE, CR) | **Open** (P8-7; HL7 owns Table 0008, the same six codes on every supported version today) | yes |
| `HL7Table.Kind` | 2 (hl7, userDefined) | **Stable** (no `@unknown default` note; a new table kind would need a major release) | — |
| `MLLP` / `SegmentGrammarTable` / `MessageStructureTable` / `DataTypeGrammarTable` / `HL7TableRegistry` | namespace enums (no cases) | n/a | — |

The 8 **open** enums (6 at the v1.0 compile, plus `StructureElement` and `AcknowledgmentCode`) each carry a DocC `- Note:` telling consumers to switch with `@unknown default` (added in this cycle). The **stable** enums are closed by their domain; the additive-only 1.x rule still applies if a domain ever surprises us, but no growth is anticipated.

## Conformances (part of the frozen contract)

Public value types conform to `Sendable` (all — strict-concurrency requirement), and where meaningful `Equatable` / `Hashable`; error enums to `Error` + `CustomStringConvertible`. Per ADR-014 these conformances are **not removed in 1.x**.

## Confirmed intended / minimal

- No symbol is accidentally `public` — every type maps to a documented role (parse / build / typed-access / validate / transport).
- The codegen'd typed segments + composites are the bulk of the type count; their public accessors are schema-driven and covered by the codegen-drift CI job.
- DocC coverage: public symbols carry `///` comments (the working notes standard); the 8 open enums now additionally carry the evolution note (6 at the v1.0 compile).

## Outcome — M3 public-surface audit complete

The surface is enumerated, each symbol confirmed intended, and every enum classified open/stable with the open ones annotated. Combined with ADR-014 (policy) and the S3 `Migration.md` finalisation, **M3 (API stabilisation) closes** — leaving only M4 (external IP review) before a v1.0 tag.
