# HL7 v2.5.1 schema audit — v0.4-S1 / S4

**Original audit date:** 2026-06-17 (substage S1, re-framed under the working notes project requirements)
**Spec-text corrections landed:** 2026-06-18 (substage S4, with authoritative spec PDFs in `docs/standards/HL7_v251_PDF/`)
**Audited:** `Resources/schemas/v2.5.1/*.json` (9 segments: MSH, PID, ORC, OBR, OBX, NK1, PV1, NTE, AL1)
**Reference:** HL7 v2.5.1 spec, ANSI/HL7 Final Standard, April 2007. PDFs referenced locally by the author; not committed to-tree pending IP review. The pull-quoted spec text below is preserved verbatim so the audit conclusions are reproducible without the PDFs being checked in.
**Lens:** the working notes project requirements — **feature-complete over AU-specific; integrator primary-reference tool**. Audit conclusions must be defensible against the HL7 v2 spec text alone, not against test-fixture observations or AU vendor behaviour assumptions.

## Outcome summary

**Per-field attributes (name / dataType / optionality / repeatability)** — 198 rows audited; **0 corrections warranted**. The schemas faithfully render the spec on these four axes.

**Conditional predicates and required-component metadata** — three spec-completeness gaps were identified in S1. After spec-text extraction in S4 the picture is now more accurate:

1. **Gap 1 (PID-36 over-broad condition)** — REVISED & RESOLVED. The original S1 framing of "PID-36 required when species is non-human" was wrong. The spec (§3.4.2.35 and §3.4.2.36) actually states:
   - PID-35 must be valued if PID-36 OR PID-38 is valued.
   - PID-36 must be valued if PID-37 is valued.

   The pre-S4 schema carried `PID-36 condition = "PID-35 populated"` — backwards (the spec rule for PID-35 is driven by PID-36, not the other way around) and on the wrong field. Closed in S4 substage C by:
   - Adding `PID-35 condition = "PID-36 populated OR PID-38 populated"` (compound DSL).
   - Replacing `PID-36 condition` with the spec-accurate `"PID-37 populated"`.

2. **Gap 2 (compound predicates on ORC/OBR/OBX)** — PARTIALLY RESOLVED + REVISED in scope. The S1 audit's "ORC-2 required when ORC-1 in (NW / CA / CR / DC / NA / RP / RR / RU / SC / SN / SR / CN / RE / RO / OC / OD / OE / OF / OH / OK / OP / OR / UA / UC / UD / UF / UH / UN / UR / UX / XO)" claim was a speculative reconstruction, not a spec citation. Reading the actual spec text (§4.5.1.2, §4.5.3.7 / 8 / 14 / 22 / 25 / 26, §4.5.1.8, §7.4.2.2 / 4):
   - **ORC-2, ORC-3, OBR-1, OBR-7, OBR-8, OBR-10, OBR-14, OBR-22, OBR-25, OBR-26, OBR-32, OBX-4** carry **cross-segment** rules ("If the placer order number is not present in the ORC, it must be present in the associated OBR and vice versa." — §4.5.1.2) or **message-context** rules ("required whenever the OBR is contained in a report message" — §4.5.3.25) that the same-segment compound DSL built in S4 substage B **cannot** express.
   - **OBX-2** carries a clean same-segment rule ("must be valued if OBX-11 is not valued with an 'X'" — §7.4.2.2) which is now encoded as `OBX-2 condition = "OBX-11 != X"`.
   - **ORC-8** ("required when the order is a child", evidenced via OBR-29 §4.5.3.29) is a discourse-level rule about the message's parent/child structure, not a same-segment predicate.

   Net: 1 of 13 fields closed in S4 substage C. The remaining 12 require **cross-segment DSL** or **message-context state** — deferred to a post-v0.4 cycle.

3. **Gap 3 (composite OR-rule conformance)** — INFRASTRUCTURE LANDED in S4 substage A; spec-text validation revealed the OR-rule choices are **interpretive**, not directly cited. The v2.5.1 component tables (§2.A.13, §2.A.26, §2.A.33, §2.A.53, §2.A.89) mark all CWE / EIP / HD / PL / XTN components as `O`. There is no spec text that explicitly states "CWE-1 OR CWE-9 must be populated" or equivalent for the other four composites. The S4 substage A choices were drawn from HL7 community convention (the spec's prose talks about "either … or" forms, particularly for CWE's three modes — Coded / Uncoded / Data Missing — and for EIP's "either the placer or the filler system") but are not strict spec citations. The rules are encoded and enforced, but integrators should know they are conformance-profile choices, not literal spec assertions.

None of these are deferrable under the integrator-reference requirement on the spec-citable axes. Gaps 1 and the OBX-2 portion of Gap 2 are closed. The cross-segment portion of Gap 2 is documented as a known limitation requiring DSL extension; this is the right framing under the "honesty over completeness when the DSL can't express something" requirement in the working notes.

## Audit methodology

For each segment, every field row was cross-referenced against the HL7 v2.5.1 spec on five attributes:

1. **`name`** — must match the spec's field name exactly.
2. **`dataType`** — HL7 v2 type code per spec table.
3. **`optionality`** — `R` / `O` / `C` / `X` / `B`.
4. **`repeatability`** — `"1"` / `"*"` per the spec's "Repeat" column.
5. **`condition`** — predicate for `C` fields. The audit checks both **whether** a `C` field has a predicate and whether the predicate accurately renders the spec's conditional rule.

The `swiftName` field is internal naming and not audited against the spec.

In substage S4 the methodology was extended: every conditional rule in the spec prose was cross-referenced against the schema's `condition` string, and where the rule is structural (cross-segment XOR, message-context guard) rather than same-segment predicate, it was tagged as "out of scope for current DSL" rather than treated as a missing predicate to fix in S4.

## Per-segment findings

| Segment | Fields | Per-field corrections | Notes |
|---|---:|---:|---|
| MSH | 21 | 0 | Faithful. |
| PID | 39 | 0 | Faithful on per-field attributes. PID-35 and PID-36 conditions corrected in S4 (Gap 1). |
| ORC | 31 | 0 | Faithful on per-field attributes. Conditional rules are cross-segment (ORC↔OBR XOR) — out of scope for same-segment DSL. |
| OBR | 47 | 0 | Faithful on per-field attributes. OBR-7 / OBR-14 / OBR-25 message-context + specimen-presence rules **RESOLVED in v0.7 / v0.11** (ADR-008 + ADR-010). OBR-22 / OBR-26 / OBR-32 carry discourse-level rules still out of scope for the DSL; OBR-9 / .10 / .11 not shipped per req #4 (no cited MUST). |
| OBX | 17 | 0 | Faithful on per-field attributes. OBX-2 condition added in S4 (Gap 2 partial). OBX-4 is grouping-discourse, not same-segment. |
| NK1 | 13 | 0 | Faithful. |
| PV1 | 20 | 0 | Faithful. |
| NTE | 4 | 0 | Faithful. |
| AL1 | 6 | 0 | Faithful. |
| **Total** | **198** | **0** | + 3 spec-completeness gaps now documented with closure / partial-closure status. |

## Gap closure status (after S4 substages A + B + C)

- **Gap 1 (PID conditional rules)** — **RESOLVED in substage C.** Schema now carries the spec-accurate predicates per §3.4.2.35 / §3.4.2.36. Validated by `Tests/HL7v2KitTests/ConditionalFieldTests.swift` (`speciesCodeConditionFiresWhenBreedPopulated`, `speciesCodeConditionFiresWhenProductionClassPopulated`, `breedCodeConditionFiresWhenStrainPopulated`, plus negative pins).

- **Gap 2 (ORC / OBR / OBX compound predicates)** — **PARTIALLY RESOLVED.** OBX-2 closed (`OBX-11 != X` per §7.4.2.2). The 12 other fields originally listed in S1 carry cross-segment or message-context rules — out of scope for the same-segment compound DSL built in substage B. Closing them requires either:
  - **Cross-segment DSL extension** (e.g. `ORC-2 populated OR OBR-2 populated` evaluated against the surrounding message tree), or
  - **Message-context state** (a way for the validator to know "this OBR is in an ORU report message" to fire OBR-25 etc.).

  Both are scoped post-v0.4 (candidate for v0.5 or beyond). Documented here so an integrator reading the schemas knows ORC-2's bare `"optionality": "C"` means "the spec has a cross-segment rule the same-segment DSL can't express", not "no rule exists".

- **Gap 3 (composite OR-rules)** — **RESOLVED in substage A** (commit `0959be6`), with the caveat that the OR-rule choices are interpretive (community-convention, not direct spec citations). `RequiredComponentSet` value type + Validator dispatch + 5 composite type updates (CWE / XTN / HD / PL / EIP). CWE specifically: was flat `requiredComponents = [(1, "Identifier")]`, which false-positive'd on CWE-9-only payloads; now `requiredComponentSet = atLeastOneOf(CWE-1, CWE-9)`. Two test changes: `cweFiresORRuleViolationOnEmptyIdentifierAndOriginalText` (renamed + updated assertion) + new positive pin `cweORRuleSatisfiedByOriginalTextAlone`. The four `…SkipsSilentlyWithNoRequiredComponents` pins for HD / PL / EIP / XTN continue to pass because their test wires already populated a satisfying combination; comments updated to reflect the new framing.

## Spec-text citations for the S4 corrections

### PID-35 / PID-36 conditional rules (Gap 1)

From v2.5.1 Final Standard CH03, §3.4.2.35:

> **Conditionality Rule:** This field [PID-35 Species Code] must be valued if PID-36 - Breed Code or PID-38 - Production Class Code is valued.

From §3.4.2.36:

> **Conditionality Rule:** This field [PID-36 Breed Code] must be valued if PID-37 - Strain is valued.

### OBX-2 conditional rule (Gap 2, partial)

From v2.5.1 Final Standard CH07, §7.4.2.2:

> This field [OBX-2 Value Type] contains the format of the observation value in OBX. It must be valued if OBX-11-Observ result status is not valued with an "X".

### ORC-2 / OBR-2 cross-segment XOR (Gap 2, out of scope)

From v2.5.1 Final Standard CH04, §4.5.1.2:

> ORC-2-placer order number is the same as OBR-2-placer order number. If the placer order number is not present in the ORC, it must be present in the associated OBR and vice versa.

### OBR-7 / OBR-14 / OBR-25 message-context rules (Gap 2, out of scope)

From §4.5.3.7 (OBR-7 Observation Date/Time):

> This field is conditionally required. When the OBR is transmitted as part of a report message, the field must be filled in. If it is transmitted as part of a request and a sample has been sent along as part of the request, this field must be filled in because this specimen time is the physiologically relevant date/time of the observation.

From §4.5.3.14 (OBR-14 Specimen Received Date/Time):

> For observations requiring a specimen, the specimen received date/time is the actual login time at the diagnostic service. This field must contain a value when the order is accompanied by a specimen, or when the observation required a specimen and the message is a report.

From §4.5.3.25 (OBR-25 Result Status):

> This field contains the status of results for this order. This conditional field is required whenever the OBR is contained in a report message. It is not required as part of an initial order.

These rules depend on message-type or sibling-segment presence (SPM, OBX). They are not expressible as same-segment predicates over the OBR segment alone.

> **v0.11 RESOLVED (ADR-010).** OBR-25 shipped in v0.7-S4 (`messageCode = ORU`). **OBR-7** second trigger and **OBR-14** shipped in v0.11-S4 (commit `cca9aa8`) using the ADR-010 segment-presence atom: OBR-7 = `"messageCode = ORU OR SPM present OR OBR-15 populated"`, OBR-14 = `"SPM present OR OBR-15 populated"`. The "sample sent along" / "accompanied by a specimen" triggers map to SPM-segment presence (v2.5.1) or OBR-15 population. OBR-9 / .10 / .11 remain NOT shipped — descriptive text without a cited MUST trigger (req #4).

**P1-1 correction:** OBR-7 is `messageCode = ORU` (the `SPM present OR OBR-15 populated` legs misfired on orders and were removed); OBR-14 is `B` with no condition, as printed in CH04 and CH07 (§4.5.3.14, SPM-18 favoured).

**P1-2:** "report message" is `messageCode in (ORU, ORF, OUL)`: CH07 §7.3.1-§7.3.9 (ORU R01/R30-R32, QRY/ORF, OUL R21-R24).

**P1-3:** OBR-2 / OBR-3 add `OR ORC absent AND messageCode in (ORU, ORF)` (§4.3.1.2-3 on v2.3/v2.3.1; §4.5.1.2-3 and §4.5.3.2-3 on v2.4+: "an ORC is not required, and the identifying placer order number must be present in the OBR segments"). The leg is gated to ORU / ORF because OUL R22-R24 and OPU R25 print OBR before [ORC], which the ORC-delimited group model cannot attach. A later OBR group with no ORC of its own still reads the previous group's ORC (under-fire only; closed by message-structure grammar, X-C04 / P8).

**P1-4:** OBR-29 is `ORC-1 = CH AND ORC-8 empty` ("required when the order is a child", §4.5.1.29 on v2.3/v2.3.1, §4.5.3.29 on v2.4+). The removed leg `ORC-1 = CH AND ORC absent` could never be true: ORC-1 resolves through the OBR's own group, which that leg asserts has no ORC (pinned by `obr29FirstLegIsUnsatisfiable`).

**P1-5:** OBR-1/8/9/10/11/20/21/26/32 now carry the printed optionality (O; v2.3 OBR-1 stays C as printed; v2.6 OBR-32 is B). ORC-8 and OBR-29 stay C from the child-order prose (see conditional-completeness-audit.md). V24-C04 said these fields are printed C on v2.5.1; CH04 and CH07 print O, so v2.5.1 was corrected with the others.

V251-C05's "Suspected for OBR-2" is resolved: §4.5.3.2 carries the ORU placer sentence.

### ORC-8 / OBR-29 parent-child structural rule (Gap 2, out of scope)

From §4.5.3.29 (OBR-29 Parent, identical structurally to ORC-8):

> It is required when the order is a child.

"Order is a child" is a parent/child message-structure property (preceding ORC carries an ORC-1 = "PA" code, then this ORC carries "CH"). Not a same-segment predicate.

> **v0.11 RESOLVED (ADR-010).** ORC-8 / OBR-29 child-order trigger shipped in v0.9 (`"ORC-1 = CH"`); v0.11-S1 (commit `13e616a`) refined both to the §4.5.1.8 DNF XOR softening using the peer-absent atom, so neither field over-fires when its peer carries the parent. Predicates: ORC-8 = `"ORC-1 = CH AND OBR absent OR ORC-1 = CH AND OBR-29 empty"`, OBR-29 symmetric. Mirrored to v2.3 / v2.3.1 in v0.11-S4b (commit `2f4796c`).

## What this audit does NOT validate

- **v2.3 / v2.3.1 / v2.4 schemas** — v0.4-S2's scope. Audited as deltas against this v2.5.1 baseline.
- **v2.8 schema** — doesn't yet exist; v0.4-S3 adds it.
- **Spec table errata** — the audit uses the public Final Standard April 2007 PDFs (author's local copy). The official HL7 v2.5.1 ballot's errata sheets (HL7-member access) were not directly consulted. Any errata not reflected in the Final Standard PDFs slip through.
- **Composite OR-rule literal spec text** — see Gap 3 above; the OR-rules from S4 substage A are interpretive, not directly cited.

## Conclusion

Under the project's the working notes requirements (feature-complete over AU-specific; integrator primary reference), the v2.5.1 schemas as of v0.4-S4 commit C are:

- **Faithful on per-field attributes** (name / dataType / optionality / repeatability) — no per-field corrections needed.
- **Gap 1 (PID conditional rules)** — RESOLVED with spec-accurate predicates.
- **Gap 2 (OBX-2)** — RESOLVED. The remaining ORC / OBR fields require cross-segment or message-context DSL extensions, deferred to post-v0.4 and documented as known limitations rather than missing predicates.
- **Gap 3 (composite OR-rules)** — RESOLVED with interpretive OR-rule choices, documented as such so integrators don't mistake them for literal spec assertions.

The v0.4 cycle delivers the maximum spec-faithful closure the current DSL admits. Anything further needs DSL extension first — which is the right sequencing under the "extend the model so the spec can be represented faithfully" requirement, not a deferral.
