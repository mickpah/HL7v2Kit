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
