# Conditional-completeness audit — v0.16 (ROADMAP M2)

**Audit date:** 2026-07-09 (v0.16 cycle, ROADMAP M2 "conformance-surface finalisation").
**Scope:** every grammar field marked `optionality = C` (conditional) that carries **no `condition` predicate** — i.e. it falls through to effectively-optional under the fail-safe DSL semantics (v0.2-V1: an unparseable/absent predicate evaluates `false`, so the field is never flagged required). This register decides, per field, whether a spec-citable, DSL-expressible predicate exists (→ **ship it**) or the conditionality is not wire-detectable (→ **documented permanent limitation**).
**Method:** enumerated across all six versions' schemas (`Resources/schemas/*/*.json`); each position read against its version's Final Standard field-definition prose. Builds on `v2_5_1-spec-audit.md` (v0.4 / v0.9) and `v2_8_2-spec-audit.md` (v0.15).

## Inventory

69 field instances across **17 distinct segment-index positions** carried `C`-without-`condition` at the start of M2:

| Position | Name | Versions | Verdict |
|----------|------|----------|---------|
| PD1-15 | Advance Directive Code | v2.8.2 | **SHIP** — `PD1-22 populated` |
| ORC-26 | Advanced Beneficiary Notice Override Reason | v2.8.2 | **SHIP (partial)** — `ORC-20 in (3, 4)` |
| OBR-1 | Set ID - OBR | v2.3–v2.6 | Permanent limitation |
| OBR-8 | Observation End Date/Time | v2.3–v2.6 | Permanent limitation |
| OBR-9 | Collection Volume | v2.3–v2.6 | Permanent limitation |
| OBR-10 | Collector Identifier | v2.3–v2.6 | Permanent limitation |
| OBR-11 | Specimen Action Code | v2.3–v2.6 | Permanent limitation |
| OBR-20 | Filler Field 1 | v2.3–v2.6 | Permanent limitation |
| OBR-21 | Filler Field 2 | v2.3–v2.6 | Permanent limitation |
| OBR-22 | Results Rpt/Status Chng - Date/Time | v2.3–v2.6, v2.8.2 | Permanent limitation |
| OBR-26 | Parent Result | v2.3–v2.6 | Permanent limitation |
| OBR-32 | Principal Result Interpreter | v2.3–v2.6 | Permanent limitation |
| OBR-48 | Medically Necessary Duplicate Procedure Reason | v2.8.2 | Permanent limitation |
| OBX-4 | Observation Sub-ID | v2.3–v2.6, v2.8.2 | Permanent limitation |
| OBX-5 | Observation Value | v2.3–v2.6, v2.8.2 | Permanent limitation |
| OBX-22 | Mood Code | v2.6, v2.8.2 | Permanent limitation |
| DG1-22 | Parent Diagnosis | v2.8.2 | Permanent limitation |
| PV2-1 | Prior Pending Location | v2.3–v2.8.2 | Permanent limitation (v1.2) |
| PV2-45 | Advance Directive Code | v2.6, v2.8.2 | Permanent limitation (v1.2) |
| PV2-47 | Expected LOA Return Date/Time | v2.4–v2.8.2 | Permanent limitation (v1.2) |
| RXO/RXE/RXD/RXG/RXC/TQ1/TQ2 (31 fields) | order/pharmacy/timing conditionals | v2.3–v2.8.2 | Permanent limitation (v1.2, grouped below) |
| SCH/RGS/ARQ/AIS/AIG/AIL/AIP/BPX/BTX/SPM/ROL/RXA (55 fields) | scheduling/blood-product/specimen/role conditionals | v2.3–v2.8.2 | Permanent limitation (v1.3, grouped below) |
| MFE/MFA/OM7/AUT (5 fields) | master-files/referral conditionals | v2.3–v2.8.2 | Permanent limitation (v1.3, grouped below) |

## Shipped in v0.16 (S2)

### PD1-15 Advance Directive Code — `PD1-22 populated` (exact)

> v2.8.2 §3.3.11.15: "*… When PD1-22 - Advanced Directive Last Verified Date is valued, this field is required.*"

A clean, closed, wire-detectable same-segment MUST. Shipped as `PD1-15 condition = "PD1-22 populated"` on the v2.8.2 PD1 schema (the field is `O` in earlier versions — v2.8.2-specific conditional). Fires `.conditionalFieldMissing` when PD1-22 is populated and PD1-15 is empty.

### ORC-26 Advanced Beneficiary Notice Override Reason — `ORC-20 in (3, 4)` (partial)

> v2.8.2 §4.5.1.26: "*Condition: This field is required if the value of ORC-20 Advanced Beneficiary Notice Code indicates that the notice was not signed. For example, … if ORC-20 was populated with the values "3" or "4" in User-defined Table 0339 … or similar values in related external code tables.*"

Shipped as `ORC-26 condition = "ORC-20 in (3, 4)"` — the HL7-standard User-defined Table 0339 "not signed" codes. **Partial** (same honesty pattern as HL7au:00044.4.4, v0.13): the spec's "*or similar values in related external code tables*" caveat means sites using a non-HL7 code system for ORC-20 could encode "not signed" with other values that this predicate won't catch. The rule is a sound **necessary condition** for the HL7-standard table — it fires only when ORC-20 is exactly `3`/`4`, which per Table 0339 genuinely means not-signed, so it cannot misfire on standard-conformant traffic (req #4). External-code-system completeness is out of the portable-core boundary.

## Permanent limitations (documented, not shippable — req #3/#4)

Each below is `C` in its HL7 attribute table, but the field-definition prose gives **no wire-detectable, DSL-expressible required-when trigger**. Under the fail-safe DSL the field is treated as optional — the correct behaviour when the trigger is undecidable — and never misfires. Grouped by why:

**Discourse-level / message-intent (not a same-segment or peer predicate):**
- **OBR-1 Set ID** — required only when more than one OBR occurs; an ordinal/cardinality property of the message, not a field predicate.
- **OBR-22 Results Rpt/Status Chng** — tied to a result-status *change* event; the "changed" state is not on the wire.
- **OBR-26 Parent Result** — parent/child observation linkage; discourse-level (the v2.5.1 audit reached the same conclusion pre-ADR-010).
- **OBR-32 Principal Result Interpreter** — "identifies the physician … responsible for the report content"; no stated required-when (an earlier audit mis-grouped this as a `messageCode = ORU` rule — the v2.8.2 prose confirms there is none).
- **DG1-22 Parent Diagnosis** (v2.8.2) — links a "*" manifestation diagnosis to its "+" parent etiological diagnosis; structural, no MUST.

**Data-nature dependent (undecidable from peer fields):**
- **OBR-8 Observation End Date/Time** — "*null for observations made at a point in time*"; whether the observation is timed/duration-based is not wire-encoded.
- **OBR-48 Medically Necessary Duplicate Procedure Reason** (v2.8.2) — required only when OBR-44 is a *duplicate* of a prior order/charge; duplicate-detection needs patient history, not the current message.
- **OBX-5 Observation Value** — the spec states "*It is not a required field*"; conditionality is on OBX-2 value-type semantics, no hard MUST.
- **OBX-22 Mood Code** (v2.6, v2.8.2) — "*When this field is not valued … the Value is assumed to be 'EVN'*"; a default-on-absence field with no required-when, and "*no documented use cases … in the context messages*".

**Peer-comparison / grouping (beyond same-segment scope):**
- **OBX-4 Observation Sub-ID** — required to disambiguate multiple OBX sharing an OBX-3; a cross-OBX grouping rule, not a same-segment predicate.

**PV2 (added v1.2 when PV2 was modelled — CH03):**
- **PV2-1 Prior Pending Location** (v2.3–v2.8.2) — "*required for cancel pending transfer*"-type trigger keyed on the ADT event code, which lives in the EVN/MSH trigger, not a same-segment peer; the conditionality is message-type dependent and not expressed as a wire predicate here.
- **PV2-45 Advance Directive Code** (v2.6, v2.8.2) — mirrors PD1-15's conditionality but PV2 carries no PV2-side "last verified date" peer to gate on; descriptive, no same-segment MUST.
- **PV2-47 Expected LOA Return Date/Time** (v2.4–v2.8.2) — required only for a leave-of-absence visit; the LOA nature is not encoded in a same-segment peer field.

**Order/pharmacy & timing family (added v1.2 when TQ1/TQ2/RXO/RXE/RXD/RXG/RXC were modelled — CH04/CH04A):**

These segments are the most conditional-heavy in HL7. Every `C` field below is conditional on **data-nature** (e.g. "give amount minimum vs. maximum", "dispense vs. give") or **cross-segment order context** (the RXO/RXE pair, ORC control code), none of which is a same-segment field-machine predicate — so all are fail-safe documented limitations, consistent with the OBR/OBX rationale above. (v2.8.2 indices; equivalent positions carry across the versions each segment appears in.)

- **RXO** (Pharmacy/Treatment Order) — 1 Requested Give Code, 2/4/5 give-amount/units, 15/17 dispense/give-per, 31 — conditional on the give-vs-dispense encoding split with RXE.
- **RXE** (Encoded Order) — 10/11/15/16/17/18/19/22 — give-amount/timing/provider fields required per the encoded-order completion rules.
- **RXD** (Dispense) — 5/8; **RXG** (Give) — 14/32/33; **RXC** (Component) — 10/11 — dispense/give/component-level conditionals.
- **TQ1** (Timing/Quantity) — 12; **TQ2** (Timing/Quantity Relationship) — 3/4/5/6/7/10 — sequencing/relationship fields conditional on the presence of a related timing segment.

**Model-extension watch (req #3):** several of these have real triggers that a *cross-segment* predicate could express (the RXO↔RXE pairing especially). Modelling them is a candidate for a future DSL/analysis cycle; until then they remain fail-safe (never misfire) and are recorded here, not shipped as unconditional rules (req #4).

**Scheduling / blood-product / specimen / role family (added v1.3 — CH10/CH04/CH07/CH15):**

Another conditional-heavy cluster. Every `C` below is conditional on the **message intent** (the SIU/SRM appointment trigger, or the placer-vs-filler role) or on **cross-segment resource grouping** — none a same-segment field-machine predicate. All fail-safe documented limitations (v2.8.2 indices; equivalents carry across the versions each segment appears in):

- **SCH** (Schedule Activity) — 1/2/3/24/26/27; **RGS** (Resource Group) — 2; **ARQ** (Appointment Request) — 2/3/24/25 — placer/filler IDs and status fields conditional on request-vs-response intent.
- **AIS/AIG/AIL/AIP** (Appointment Information — Service/General/Location/Personnel) — set-ID, start-datetime, duration and filler-status fields (indices 2–14) conditional on the appointment action being scheduled/modified vs. queried.
- **BPX** (Blood Product Dispense Status) — 5/6/8/9/10; **BTX** (Blood Product Transfusion) — 2/3/4/5/6/7 — dispense/transfusion-status fields conditional on the status event.
- **SPM-13** (Specimen Risk Code) and **ROL-1** (Role Instance ID) — conditional on specimen-hazard presence / role-action context.
- **RXA-7/12** (Administered Amount fragments) — data-nature conditionals paralleling the RXO/RXE set above.

**Master-files / referral family (added v1.3 — CH08/CH11):**
- **MFE-2** (Master File Entry — MFN Control ID) and **MFA-2** (Master File Ack — Control ID) — required only for update/replace master-file events (the MFI-3 event code), not a same-segment peer.
- **OM7-16 / OM7-18** (Additional Basic Attributes) — conditional on the observation's orderability/category, not wire-encoded in a peer field.
- **AUT-6** (Authorization — Reimbursement Limit) — conditional on the authorization decision context.

**Descriptive, no cited MUST (req #4 — already recorded in `v2_5_1-spec-audit.md`):**
- **OBR-9 Collection Volume**, **OBR-10 Collector Identifier**, **OBR-11 Specimen Action Code** — specimen-associated but with descriptive text and no cited MUST trigger. (Re-audit only if a spec revision adds MUST language.)
- **OBR-20 Filler Field 1**, **OBR-21 Filler Field 2** — filler-discretion fields; no HL7-stated firing condition.

## Outcome

- **2 predicates shipped** (PD1-15 exact, ORC-26 partial) — closing the two v0.15 gaps where a spec predicate existed but was not extracted.
- **~109 positions documented** as permanent limitations with per-field rationale (15 at M2; +34 in v1.2 [PV2 + order/pharmacy/timing]; +55 v1.3 scheduling/blood-product/specimen/role; +5 v1.3 master-files/referral); all are fail-safe (treated as optional) and none misfires. The v2.8.2 guard test enumerates the exact current set.
- No model extension required — both shipped predicates use the existing v0.4-S4 same-segment DSL (`populated`, `in`).
- **This register is the M2 conditional-completeness gate for v1.0** (ROADMAP M2): the conditional surface is now either shipped or explicitly, spec-citably documented. A regression pin exercises each shipped predicate; a guard test asserts the permanent-limitation set stays `C`-without-`condition` (so a future edit that adds a bare `C` field is caught).
