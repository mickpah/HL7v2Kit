# HL7 v2.3 / v2.3.1 / v2.4 schema audit — v0.4-S2 (+ v0.9 CH04 back-fill)

**Date:** 2026-06-18 (original v0.4-S2 audit); **2026-06-25** v0.9 update adds verbatim v2.4 CH04 citations for the v0.7-S4 cross-segment / message-context rules (PDFKit recipe — `memory/reference_pdf_extraction.md` — cleared the prior pdftotext gate).
**Audited:** `Resources/schemas/v2.3/*.json`, `Resources/schemas/v2.3.1/*.json`, `Resources/schemas/v2.4/*.json` (9 segments per version: MSH, PID, NK1, PV1, OBR, OBX, ORC, AL1, NTE).
**Baseline reference:** the now-spec-audited `Resources/schemas/v2.5.1/*.json` (see `v2_5_1-spec-audit.md`).
**Lens:** the working notes project requirements — **feature-complete over AU-specific; integrator primary-reference tool**. Audit conclusions must be defensible against the HL7 v2 spec text alone, not against test-fixture observations.

## Scope and honest framing

The v2.5.1 audit (S1 / S4) used the v2.5.1 Final Standard PDFs to make spec-text-citable claims. **The v2.3 / v2.3.1 / v2.4 Final Standard PDFs are not available locally.** That changes what S2 can and cannot do honestly:

**S2 CAN:**

1. **Structural delta audit** — every field that exists in two or more of the 4 supported versions can be compared on `name` / `dataType` / `optionality` / `repeatability`. HL7 v2.x's design is **additive** (each minor version extends the previous without changing existing field semantics, except for explicit deprecation marks). A divergence on these four axes between versions for the same field index would be a spec-encoding bug in our schemas.
2. **Field-count progression check** — pin and verify the per-segment growth across the version chain. The pins live in `Tests/HL7v2KitTests/MultiVersionTests.swift` (`extendedV24WireExercisesV24Additions` / `v23GrammarFitsSmallerSurface` / `v23PidPrefixOfV231Prefix...` / `fourWayGrammarDispatch`).
3. **Inheritance check on S4-C predicates** — for each conditional rule landed in v2.5.1 (PID-35 / PID-36 / OBX-2), confirm whether the referenced field exists in earlier versions, and decide carry-forward status.

**S2 CANNOT (without per-version PDFs):**

4. Cite per-version conditional-rule wording. The v2.5.1 wording is captured in `v2_5_1-spec-audit.md` with section numbers; the same wording in v2.3 / v2.3.1 / v2.4 would require their respective Final Standard PDFs.
5. Identify per-version component-table changes (e.g. whether CWE's component list looks different in v2.3 — likely, since CWE was introduced in v2.5; in v2.3 it's CE in those positions, but per-component layouts of CE itself may have shifted).
6. Catch version-specific errata.

Under the project's "honesty over completeness" requirement, this S2 commit ships the audit work that's spec-defensible (structural deltas + field counts) and **explicitly defers** the conditional-rule carry-forward + per-version component-definition audit until the relevant PDFs are obtained.

## Per-segment delta summary

Field counts per version:

| Segment | v2.3 | v2.3.1 | v2.4 | v2.5.1 | Delta history |
|---|---:|---:|---:|---:|---|
| **MSH** | 15 | 17 | 20 | 21 | v2.3→v2.3.1: +2 (MSH-16 application-acknowledgement, MSH-17 country code), v2.3.1→v2.4: +3 (MSH-18 charset, MSH-19 principal language, MSH-20 alternate char set handling), v2.4→v2.5.1: +1 (MSH-21 message profile identifier) |
| **PID** | 30 | 30 | 32 | 39 | v2.3.1→v2.4: +2 (PID-31 identity unknown indicator, PID-32 identity reliability code), v2.4→v2.5.1: +7 (PID-33 last update DT, PID-34 last update facility, PID-35 species code, PID-36 breed code, PID-37 strain, PID-38 production class code, PID-39 tribal citizenship) |
| **NK1** | 13 | 13 | 13 | 13 | no growth in the typed-surface cap (v0.1.0 capped NK1 at 13 from the original 39; later versions also extend beyond, but the typed cap stays) |
| **PV1** | 20 | 20 | 20 | 20 | same — capped at 20 in the typed surface |
| **OBR** | 43 | 43 | 47 | 47 | v2.3.1→v2.4: +4 (OBR-44 procedure code, OBR-45 procedure code modifier, OBR-46 placer supplemental info, OBR-47 filler supplemental info) |
| **OBX** | 11 | 14 | 16 | 17 | v2.3→v2.3.1: +3 (OBX-12..14 producer's ID / responsible observer / observation method), v2.3.1→v2.4: +2 (OBX-15 producer's facility, OBX-16 responsible observer), v2.4→v2.5.1: +1 (OBX-17 observation method) |
| **ORC** | 17 | 17 | 19 | 31 | v2.3.1→v2.4: +2 (ORC-18 confidentiality code, ORC-19 entered by), v2.4→v2.5.1: +12 (ORC-20..31 — large facility/address/phone/status block) |
| **AL1** | 6 | 6 | 6 | 6 | no growth (AL1 is small and stable) |
| **NTE** | 3 | 3 | 3 | 4 | v2.4→v2.5.1: +1 (NTE-4 entered by) |

## Per-field consistency check

A pairwise check across the 4 versions: for every `(segment, field_index)` pair that appears in 2+ versions, do `name`, `dataType`, `optionality`, and `repeatability` agree?

**Result: 0 inconsistencies across 198+ rows.**

Every field present in multiple versions has identical per-field attributes. HL7's additive history holds in our schemas. No structural corrections warranted.

## Conditional-rule carry-forward status

The v2.5.1 audit (S4 substage C) added three conditional predicates citable to specific sections of the v2.5.1 Final Standard. The v0.7 cycle (ADR-008 cross-segment DSL) added a further three cross-segment / message-context rules that were mirrored onto v2.4 in v0.7-S4 with the verbatim § citation deferred. Both groups are tracked here:

| Field | Condition | Citation | v2.3 / v2.3.1 / v2.4 status |
|---|---|---|---|
| PID-35 | `"PID-36 populated OR PID-38 populated"` | v2.5.1 §3.4.2.35 | **Not applicable** in base v2.3 / v2.3.1 / v2.4 — PID-35 doesn't exist (PID caps are 30 / 30 / 32). Note: the **AU v2.4 ADRM-2021 profile pre-adopts PID-35..38** from v2.5; that's a profile-level extension, handled separately when AU profile support lands. |
| PID-36 | `"PID-37 populated"` | v2.5.1 §3.4.2.36 | **Not applicable** in base spec — same reason. |
| OBX-2 | `"OBX-11 != X"` | v2.5.1 §7.4.2.2 | **v2.4 RESOLVED 2026-06-18** — v2.4 §7.4.2.2 wording is identical to v2.5.1. **v2.3.1 RESOLVED 2026-06-25** — §7.3.2.2 wording: _"This field contains the format of the observation value in OBX. It must be valued if OBX-11-Observ result status is not valued with an 'X'."_ Identical semantics. **v2.3 RESOLVED 2026-06-25** — §7.3.2.2 wording matches v2.3.1 verbatim. Carry-forward applied to all four versions; the v0.4-S2 "v2.3 / v2.3.1 pending PDFs" gap is now CLOSED for OBX-2. |
| ORC-2 | `"OBR-2 empty"` (XOR with OBR-2) | v2.5.1 §4.5.1.2 / **v2.4 §4.5.1.2 RESOLVED 2026-06-25** | v2.4 wording verbatim (CH04, p. 4-34): _"ORC-2-placer order number is the same as OBR-2-placer order number. If the placer order number is not present in the ORC, it must be present in the associated OBR and vice versa."_ Identical to v2.5.1 — the v0.7-S4 mirror predicate is spec-faithful. |
| OBR-2 | `"ORC-2 empty"` (symmetric XOR) | v2.5.1 §4.5.3.2 / **v2.4 §4.5.3.2 RESOLVED 2026-06-25** | v2.4 OBR-2 spec text mirrors §4.5.1.2 by the "same as" linkage above; the symmetric predicate is spec-faithful. |
| OBR-25 | `"messageCode = ORU"` | v2.5.1 §4.5.3.25 / **v2.4 §4.5.3.25 RESOLVED 2026-06-25** | v2.4 wording verbatim (CH04, p. 4-52): _"This field contains the status of results for this order. This conditional field is required whenever the OBR is contained in a report message. It is not required as part of an initial order."_ Identical to v2.5.1 — the predicate that maps "report message" to MSH-9.1 = ORU is spec-faithful for the canonical ORU^R01 case. |
| ORC-8 | `"ORC-1 = CH"` (corrected 2026-06-25) | v2.5.1 §4.5.3.29 / **v2.4 §4.5.1.1 RESOLVED 2026-06-25** | v2.4 wording §4.5.1.1 (ORC-1 / order control, p. 4-26): _"Whenever a child order is transmitted in a message the ORC segment's ORC-8-parent is valued with the parent's filler order number (if originating from the filler) and with the parent's placer order number (if originating from the filler or if originating from the placer)."_ Prior predicate `previousSegment(ORC).ORC-1 = PA` under-fired on standalone CH orders — replaced with `"ORC-1 = CH"` (same-segment v0.4-S4 atom) per the §4.5.1.1 verbatim trigger. Pins: `orc8ConditionalFiresOnChild`, `orc8ConditionalFiresOnStandaloneChild`, `orc8ConditionalSilentOnParent`. **v0.11-S1 UPDATE (ADR-010, commit `13e616a`):** predicate refined to the DNF XOR softening `"ORC-1 = CH AND OBR absent OR ORC-1 = CH AND OBR-29 empty"` using the new segment-presence atom — the over-fire noted on the OBR-29 row below is now resolved. Mirrored to v2.3 / v2.3.1 in v0.11-S4b (commit `2f4796c`). |
| OBR-29 | `"ORC-1 = CH"` (resolves cross-segment via associatedSegment(ORC); added 2026-06-25) | **v2.4 §4.5.3.29 RESOLVED 2026-06-25** | v2.4 wording (CH04, p. 4-54): _"This field is identical to ORC-8-parent. ... It is required when the order is a child."_ Identical trigger to ORC-8 — the v0.7 cross-segment ref resolves `ORC-1` from the associated ORC when evaluated in OBR context. Pins: `obr29ConditionalFiresOnChildAssociatedORC`, `obr29ConditionalSilentOnNonChildAssociatedORC`. **§4.5.1.8 XOR softening** (_"If the parent is not present in the ORC, it must be present in the associated OBR"_) is a third orthogonal rule: it says either ORC-8 OR OBR-29 carrying the parent satisfies both. Currently NOT enforced — would require a DSL atom that distinguishes "peer absent" from "peer empty" (the current cross-segment ref fails safe to false on missing peer, conflating the two). Documented as a known limitation; the §4.5.1.1 + §4.5.3.29 child-order triggers we DO enforce err on the over-firing side relative to §4.5.1.8 (will fire when both fields are empty, even though the XOR rule says either being valued satisfies the spec — but in practice a wire with both empty IS a spec violation per the child-order triggers). Tracked for future DSL extension if a fixture surfaces the rare both-can-satisfy edge. **v0.11-S1 RESOLVED (ADR-010, commit `13e616a`):** the peer-absent DSL atom (`OBR absent` / `ORC absent`) now distinguishes "peer absent" from "peer empty", so the §4.5.1.8 XOR softening ships. OBR-29 predicate: `"ORC-1 = CH AND ORC absent OR ORC-1 = CH AND ORC-8 empty"`. Neither field fires when its peer carries the parent; both fire only when neither carries it. Pins: `orc8SilentUnderXORSofteningWhenOBRCarriesParent`, `obr29SilentUnderXORSofteningWhenORCCarriesParent`. Mirrored to v2.3 / v2.3.1 in v0.11-S4b (commit `2f4796c`) — v2.3 basis is the general "same rule for other identical fields in the ORC and OBR" parenthetical since v2.3 has no parent-specific §4.5.1.8 sentence. |
| ORC-3 | `"OBR-3 empty"` (added 2026-06-25) | **v2.4 §4.5.1.3 RESOLVED 2026-06-25** | v2.4 wording (CH04, p. 4-35): _"ORC-3-filler order number is the same as OBR-3-filler order number. If the filler order number is not present in the ORC, it must be present in the associated OBR."_ Exact mirror of the ORC-2 / OBR-2 XOR shipped in v0.7-S4. Same predicate shape. Pins: `fillerOrderXORFiresOnBothSides`, `fillerOrderXORSatisfiedFromOBRSide`. |
| OBR-3 | `"ORC-3 empty"` (added 2026-06-25; symmetric XOR partner) | **v2.4 §4.5.3.3 RESOLVED 2026-06-25** | Same §4.5.1.3 / §4.5.3.3 mirror clause. Predicate spec-faithful by the same reasoning as OBR-2. |
| OBR-7 | `"messageCode = ORU"` (partial; added 2026-06-25) | **v2.4 §4.5.3.7 RESOLVED-PARTIAL 2026-06-25** | v2.4 wording (CH04, p. 4-46-ish): _"This field is conditionally required. When the OBR is transmitted as part of a report message, the field must be filled in. If it is transmitted as part of a request and a sample has been sent along as part of the request, this field must be filled in because this specimen time is the physiologically relevant date/time of the observation."_ Two triggers: (a) report-message → required (captured by `messageCode = ORU`), (b) request+sample-sent → required (NOT captured — would require a "specimen present" DSL atom; the existing fields don't tell us this without inspecting OBR-15 / specimen-related fields). Partial fix ships the first trigger. The `oru_r01_v24.hl7` fixture gained an OBR-7 timestamp during this commit (the only fixture that needed updating; all other ORU fixtures already populated OBR-7). Pins: `obr7ConditionalFiresOnORU`, `obr7ConditionalSilentWhenNoOBR`. **v0.11-S4 RESOLVED (ADR-010, commit `cca9aa8`):** second trigger now captured. v2.4 predicate: `"messageCode = ORU OR OBR-15 populated"` (OBR-15 populated = specimen source indicated = "sample sent along"). v2.5.1 additionally checks `SPM present`. Mirrored to v2.3 / v2.3.1 in v0.11-S4b (commit `2f4796c`). Pin: `obr7FiresUnderSecondTrigger`. P1-1: the request leg is registered as not wire-decidable (see conditional-completeness-audit.md). |
| OBR-14 / OBR-22 / OBR-32 et al. | OBR-14 bare C (P1-1; the v0.11-S4 `OBR-15 populated` predicate misfired on new orders and was removed); OBR-22 / .32 still deferred | **v2.4 §4.5.3.14 RESOLVED 2026-07-03; .22 / .32 DEFERRED** | OBR-14 (Specimen Received Date/Time) wording: _"This field must contain a value when the order is accompanied by a specimen, or when the observation required a specimen and the message is a report."_ **v0.11-S4 RESOLVED (ADR-010, commit `cca9aa8`):** the "accompanied by a specimen" trigger maps to `OBR-15 populated` (v2.4) / `SPM present OR OBR-15 populated` (v2.5.1); the "observation required a specimen AND message is a report" leg is subsumed by the same specimen-indicator OR in practice (no wire-detectable "observation required specimen" without external LOINC lookup). Mirrored to v2.3 / v2.3.1 in v0.11-S4b (commit `2f4796c`) — v2.3 §4.5.1.14 is verbatim-identical. Pins: `obr14FiresWhenOBR15PopulatedAndOBR14Empty_v24`, `obr14SilentWhenOBR14Populated_v24`, `obr14SilentWhenNoSpecimenIndicator_v24`, `obr14FiresWhenSPMPresent_v251`, `obr14FiresOnV23`. OBR-22 (Results Report Status Change DT) wording calls it "a results field only" without a normative MUST trigger — no extractable spec predicate; still DEFERRED. OBR-32 (Principal Result Interpreter) likewise has no normative MUST in §4.5.3.32; still DEFERRED. Also NOT shipped per req #4: OBR-9 / .10 / .11 (§4.5.3.9 / .10 / .11) — descriptive text without MUST language (confirmed via PDFKit during v0.11-S4). |

**P1-2:** "report message" (OBR-7 §4.5.1.7 / §4.5.3.7, OBR-25 §4.5.1.25 / §4.5.3.25) is `messageCode in (ORU, ORF)` on v2.3 and v2.3.1 (CH7 §7.2.1, §7.2.2) and adds OUL on v2.4 (CH07 §7.3.2).

**P1-3:** OBR-2 / OBR-3 add `OR ORC absent AND messageCode in (ORU, ORF)` (§4.3.1.2-3 on v2.3/v2.3.1; §4.5.1.2-3 and §4.5.3.2-3 on v2.4+: "an ORC is not required, and the identifying placer order number must be present in the OBR segments"). The leg is gated to ORU / ORF because OUL R22-R24 and OPU R25 print OBR before [ORC], which the ORC-delimited group model cannot attach. A later OBR group with no ORC of its own still reads the previous group's ORC (under-fire only; closed by message-structure grammar, X-C04 / P8).

**P1-4:** OBR-29 is `ORC-1 = CH AND ORC-8 empty` ("required when the order is a child", §4.5.1.29 on v2.3/v2.3.1, §4.5.3.29 on v2.4+). The removed leg `ORC-1 = CH AND ORC absent` could never be true: ORC-1 resolves through the OBR's own group, which that leg asserts has no ORC (pinned by `obr29FirstLegIsUnsatisfiable`).

**P1-5:** OBR-1/8/9/10/11/20/21/26/32 now carry the printed optionality (O; v2.3 OBR-1 stays C as printed; v2.6 OBR-32 is B). ORC-8 and OBR-29 stay C from the child-order prose (see conditional-completeness-audit.md).

## Known limitations (explicit)

Per the working notes's "honesty over completeness" requirement, these are the per-version checks deferred to a future cycle when the corresponding PDFs become available:

1. **Per-version conditional rules** — apart from the OBX-2 carry-forward and the four v0.7-S4 cross-segment rules documented above (all v2.4 now RESOLVED via CH04 + CH07 audit; **v2.3 / v2.3.1 still DEFERRED** pending those PDFs). Per-version spec text for v2.3 / v2.3.1 would surface (a) other same-segment predicates the v2.5.1 audit didn't enumerate because they're version-specific, and (b) the version-history of the three predicates we did land (i.e. whether PID-35/36 and OBX-2 first appeared in v2.5.1 or earlier).
2. **Per-version component-table audit** — composite definitions evolve across versions (CWE was introduced in v2.5; v2.3 uses CE in those positions; XPN gained components across the version chain; etc.). The per-version spec PDFs would let the audit confirm composite component lists match the spec text per version.
3. **Per-version errata** — the official HL7 ballot errata sheets are not consulted at any version.
4. **T-track per-version grammar coverage gap** — ~~the v0.4 T-track promoted EVN / MSA / ERR / PD1 / DG1 / IN1 to typed segments via `Resources/schemas/v2.5.1/` only~~. **RESOLVED across all base versions.** v2.4 authored in v0.6 (`7c80b6d`); **v2.3 + v2.3.1 authored in v0.12** (T-back-port). All four base grammar tables now list the 6 T-track segments with per-version field shapes:
   - **EVN** — v2.3 / v2.3.1: 6 fields (no EVN-7 Event Facility, added in v2.4); v2.4: 7.
   - **MSA** — 6 fields, uniform across v2.3–v2.4.
   - **ERR** — single CM field (`Error Code and Location`), uniform v2.3–v2.4; v2.5+ expanded to 12.
   - **PD1** — v2.3 / v2.3.1: 12 fields; v2.4: 21.
   - **DG1** — 19 fields v2.3–v2.4. Per-version divergences preserved: v2.3 DG1-2 (Coding Method) is R (v2.4 downgraded to B); v2.3 DG1-15 (Diagnosis Priority) is NM, revised to ID in v2.3.1 (matching v2.4).
   - **IN1** — 25-field curation (the shared typed-segment surface). Per-version divergences preserved: IN1-14 (Authorization Information) is CM in v2.3 / v2.3.1, retyped AUI in v2.4; IN1-17 (Insured's Relationship To Patient) is IS in v2.3, revised to CE in v2.3.1 (matching v2.4). **Caveat**: the v2.3 / v2.3.1 CH6 IN1 attribute table's OPT column could not be cleanly extracted from the PDF's multi-column layout; field optionality follows the established v2.4 curation (R on IN1-1/2/3, O elsewhere), with the three R-fields cross-checked against the visible v2.3 spec tokens. Types and field count are extracted positionally and are exact. Pins: `MultiVersionTests.v23BackportedSegmentsRecognised`, `v231BackportedSegmentsRecognised`, `v23DG1RequiredFieldsFire`, plus the extended `grammarTablePopulated` / `v23GrammarTablePopulated`.

## P6 findings closed (2026-10-02)

The 2026-09 review (`planning/reviews/v2.3-review.md`, `v2.3.1-review.md`, `v2.4-review.md`)
raised six findings against the schema/validator layer this audit does not itself cover
(repeatability bounds, field length). All six are closed:

| Finding | Gap | Closed by |
|---|---|---|
| V23-C08 | v2.3 `RP/#` bounds (`Y/n`) collapsed to unbounded `*` | P6-4 (`11a5b44`, `ebec7b4`) — `FieldGrammar.maxRepetitions`, `cardinalityExceeded` past the bound |
| V24-C07 | Same defect, v2.4 | P6-4 (`11a5b44`, `ebec7b4`) |
| V231-C05 | v2.3.1 PCR-9/11/13/15/17/19/20 read as `*` from a column shift | P6-5 (`1d77fa1`) — printed bounds restored from Figure 7-22 |
| V231-C14 | v2.3.1 (and v2.3) OBX-2/OBX-16 lengths taken from the waveform category tables instead of the base Figure 7-5 | P6-2 (`ad0ad02`) |
| V231-C15 | Printed `LEN` recorded but never checked, pre-v2.7 and v2.7+ alike | P6-6 (`33d415e`, `32bf6d1`) — `fieldLengthOutOfRange` / `normativeLengthSeverity` |
| V231-C16 | v2.3.1 NSC had no recorded lengths | P6-2 (`ad0ad02`) — Appendix C Figure C-3 lengths |

## Conclusion

Under the project's the working notes requirements, the v2.3 / v2.3.1 / v2.4 schemas as of v0.4-S2 are:

- **Structurally consistent** with the spec-audited v2.5.1 baseline on every field that exists in multiple versions.
- **Field-count progression** matches the documented HL7 minor-version additive-history pattern and is pinned end-to-end in `MultiVersionTests.swift`.
- **Conditional rules** are absent in v2.3 / v2.3.1 / v2.4 by design — carry-forward of the v2.5.1 S4-C predicates is deferred under "no predicate ships without citation". OBX-2 is the candidate when the v2.3 / v2.3.1 / v2.4 §7.4.2.2 wording can be cited.
- **0 corrections warranted** at the structural-delta axis.
- **1 defect found + corrected, 4 missing conditions filled in v2.5.1/v2.4, 6 rules propagated to v2.3 + v2.3.1, DG1-20/.21 filled in v2.5.1** (v0.9 + post-v0.9 CH04 + CH07 + v2.5.1 CH06 back-fill, 2026-06-25). The v0.7-S4 ORC-8 predicate was corrected from `previousSegment(ORC).ORC-1 = PA` to `"ORC-1 = CH"`; OBR-29 gained `"ORC-1 = CH"` per §4.5.3.29; OBR-7 gained partial `"messageCode = ORU"` per §4.5.3.7 first trigger; ORC-3 / OBR-3 gained symmetric XOR per §4.5.1.3. The v2.3.1 + v2.3 spec text was extracted via PDFKit for both CH04 (ordering rules) and CH07 (OBX) and confirmed verbatim-equivalent to v2.4 for the six rules propagated: ORC-2/OBR-2 XOR, ORC-3/OBR-3 XOR, ORC-8/OBR-29 child-order, OBR-7 report-message, OBR-25 report-message, OBX-2 result-status. **18 new condition strings across the two older version chains** + DG1-20 + DG1-21 in v2.5.1 (`"triggerEvent = P12"` per §6.5.2.20 / §6.5.2.21 — "required in all implementations employing Update Diagnosis/Procedures (P12) messages"). 11 regression pins added across the cycle; 435 → 446 tests green. All landings per the "correct defects as found" feedback rule. OBR-14 / OBR-22 / OBR-32 / OBR-26 / OBX-4 / OBX-5 / OBR-8 / OBR-1 audited and explicitly deferred (specimen-detection gap, no extractable spec MUST trigger, or positional-sequential rule not expressible in current DSL).

This S2 commit ships the structural-delta findings + the deferred-items framing. Closure of the deferred items happens when the per-version PDFs become available; tracked as a follow-up.

## What this audit does NOT validate

- **v2.8 schema** — doesn't exist yet; v0.4-S3 adds it.
- **Per-version conditional rules** — see "Known limitations" above.
- **Per-version composite-component definitions** — see "Known limitations".
- **Spec table errata** — neither the v2.3 / v2.3.1 / v2.4 nor the v2.5.1 errata sheets are consulted. The audit uses the public Final Standard PDFs (or, for v2.3 / v2.3.1 / v2.4, the inheritance-from-v2.5.1 assumption).

## v2.4 message structures (P8b-13)

The extractor reads 389 v2.4 captions: 36 excluded as examples, query profiles or conformance
statements (ruling G7), 168 structure IDs, 148 read and 20 unreadable (G6 placeholders and
templates, ERP_R09's ellipsis rows, SUR_P09's ED row, and the 'see Chapter 5' captions QRY_P04
and DSR_P04). 148 are committed under `Resources/structures/v2.4/` and v2.4 is
`complete: true`; with the 24 registered in `completeness.json` they account for all 171 Table
0354 v2.4 rows and the ACK caption, which has no row. As first committed the counts were 386,
166, 146 and 26: QRY_Q02 and QCK_Q02 were registered as unprinted, but CH05 5.10.3.1 (p 5-112)
prints both, as "QRY^Q02 (A to B)" and "QCK^Q02 (B to A)", a one-space caption form the reader
missed (P8b-13 fix round; "ACK^Q03 (A to B)" is the third such caption and changes nothing).
The P8b-3a/3b report counts (130 parsed, 10 lint-failing, 162 groups named, 6 synthesised)
predate P8b-13's reader fixes, errata and group-name overrides; the committed result is 148
parsed, 18 lint-failing (exact-matched), 298 named from the bundle, 35 by override and 1
synthesised. v2.4 prints no group names: 298 are named from the HL7 v2.xml v2.4 bundle, 35
by cited overrides and 1 is synthesised (register §E v2.4 addendum).

Requirement 4 evidence: with the structure check off the validation digest is byte-identical;
with it on, 235 messages declaring MSH-12 2.4 change: 111 now match cleanly, 75 stay info with a
new reason, 48 are example defects cited to the print (ACK_ACK, CH10 AIP before AIL, query
events Table 0003 v2.4 does not define, the CH03 Q24/K24 example against its query profile, a
TBR^R08 error response without RDF/RDT), and one misfire was fixed (ERP_R09, now registered on
v2.4 and v2.5.1). 16 probes in `StructureV24ProbeTests`.

## v2.3.1 message structures (P8b-14)

The extractor reads 246 v2.3.1 captions in the one v2.3.1 PDF (none excluded): 113 structure
IDs, 99 read and 14 unreadable (the general order's `Order Detail Segment` placeholder in
ORM_O01, ORR_O02 and OSR_Q06, eight CH12 `[OBR, etc.` structures, ERP_R09's ellipsis rows,
MFN_M03's `???` row and SUR_P09's ED row), and five captions to which Table 0354 v2.3.1 gives no
structure ID (MFN^M01-M06 twice, MFQ^M01-M06, MFR^M01-M06, MFN^M04; declared in
`overrides.json` `unresolvedCaptions`). Most captions print `CODE^EVT` only; their IDs come from
Table 0354 v2.3.1 (CH2 2.24.1.9, pp 2-103 to 2-106), read through ten cited errata for its
misprinted rows, two declared shared triggers (ADT^A28, ADT^A31) and four `captionStructures`
entries (MFK, PPP). 99 are committed under `Resources/structures/v2.3.1/` and v2.3.1 is
`complete: true`; with the 27 registered in `completeness.json` they account for all 117 Table
0354 v2.3.1 rows (nine printed IDs, ACK and the shared ORM^O01 and ORR^O02 structures, have no
row). Group names: 240 from the HL7 v2.xml 2.3.1 bundle, 13 through the v2.4 bundle, none
synthesised (register §E v2.3.1 addendum).

QRY_Q02 and QCK_Q02 are read on v2.3.1 from the one-space direction captions of CH2 (p 2-84):
"QRY^Q02 (A to B)  Query Message" prints MSH, QRD, [QRF], [DSC] and "QCK^Q02 (B to A)  Query
General Acknowledgment" prints MSH, MSA, [ERR], [QAK]; both are modelled.

Requirement 4 evidence: with the structure check off the validation digest is byte-identical;
with it on, 55 messages change: 47 v2.3.1 spec examples now match cleanly, 6 are example defects
cited to the print (CH04 4.14.5 sends ACK with QAK; five CH10 10.6 examples print AIP before
AIL), 2 stay info with a new reason (the `orm_o01_v231.hl7` fixture's ORM^O01 is an ambiguous
shared trigger without MSH-9.3; a CH08 MFN^M05 example is a fragment). No misfire. The P8b-3b
lint table's 27 pre-v2.5 ORU-shape failures (an OBSERVATION group `{ [OBX] [{NTE}] }`) are lint failures
counted over all seven versions, not corpus findings; v2.3.1's two, ORU_R01 and ORF_R02, are
exact-matched (P8b-12) and committed as printed. No v2.3.1 spec example carries ORU^R01 or
ORF^R04 with MSH-12 read as 2.3.1 (the CH07 examples elide MSH-12), so the probes exercise them:
14 probes and 9 resolution cases in `StructureV231ProbeTests`.
