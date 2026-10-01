# M7 — ADRM-2021 chapter-body prose sweep

| | |
|---|---|
| Started | 2026-09-16 (M7-P1) |
| Status | **M7 COMPLETE (2026-09-16).** P1 body sweep + P2/P3 shipped six findings; P4 swept the normative appendices 8–10 (63 candidates, triage below) and shipped P-6 (the VMR header pins). All seven decidable prose findings are live as `ADRM-prose:P-n` rules; everything else is registered with its reason. **P4-27 (2026-10-01)** found a gap: the M7 keyword list (`must` / `shall` / `is required to` / `not permitted` / `is mandatory`) never matched declarative "not used"/"should not be used" prose, so OBR-26, OBR-29 and ORC-24 were invisible to the original scan. Re-swept for that phrasing; shipped P-11, P-12; registered the rest below. **Fix round 1 (2026-10-01):** the re-sweep's first pass was itself incomplete — the TM-datatype overview-table row (§3) and the OBX-17 microbiology-example note (§4.14.3) were missed and are now added to §B; OBR-26's P-11 severity was corrected from error to warning (no modal verb; the ADRM's own attribute table gives it usage O, not X). **P4-32 (2026-10-01, owner decision G7):** OBR-29's NEEDS_CONTEXT conflict was resolved in favour of shipping — P-13, warning, same mechanism and scope as P-11. See the updated OBR-29 entry below. |
| Method | `scripts/sweep-adrm-prose.py` over `/tmp/adrm2021.txt` (pdftotext of the ADRM; re-extract per session) |
| Predecessor | `m6-adrm-2021-localisation-audit.md` — the Appendix 5 register work. This sweep covers what Appendix 5 explicitly does not: narrowings stated only in chapter prose. |

## Why this sweep exists

Appendix 5 states it is **not exhaustive**. The M6 programme triaged all 104
message-decidable Appendix 5 rows to completion (EXTEND 0), but a narrowing stated only
in body prose — with no conformance-point ID — was invisible to that register. Req #1/#2
require the profile be defensible against the whole spec text, not just its appendix.

## Method and counts

The sweep scans body pages (pdftotext page indexes 4–372, i.e. front matter to
Appendix 1) for normative sentences (`must` / `shall` / `is required to` /
`not permitted` / `is mandatory`), then removes:

1. lines within ±10 lines of a `Conformance point` box or an inline `HL7au:` ID
   (register territory) — **13 removed**;
2. lines whose token-overlap with any Appendix 5 point text is ≥ 0.6 (the appendix
   quotes body wording; the body rarely prints the IDs — only 5 body pages carry
   `HL7au:`) — **56 removed**.

**319 raw hits → 263 candidates**, all read and triaged by hand. Most are reprinted
base-v2.4 datatype/field prose, HL7 conformance-terminology glossary (R/RE/C usage
definitions), RFC-2119 keyword definitions, receiver/rendering guidance, or restatements
of shipped points in different words. The residue is below. Page numbers are pdftotext
page indexes (printed page ≈ index, off by at most a few).

## A. Ship candidates (prose-only narrowings, message-decidable, quoted)

| # | Finding | Spec text (quoted) | Mechanism | Status |
|---|---------|--------------------|-----------|--------|
| P-1 | **PID-1 profile-required** | "PID-1 is mandatory in the Australian context. Variance to HL7 International." (PID attribute-table footnote †††, p. 61) | `FieldOverride` profileUsage R, gated (ORM, ORU, REF, RRI) — the RRI echoes the REF's PID per §7.1 p. 325 | **✅ SHIPPED M7-P2** |
| P-2 | **REF disallowed segments** | "§7.4.2 Disallowed segments — The following segments … must not be used by senders": ACC, AUT, CTD, DRG, DSC, DSP, GT1, IN2, NTE, PR1 (p. 363) | Nine `maxCount: 0` prohibitions gated `messageCode = REF` (NTE was already shipped as `HL7au:000023` over Orders/Results/Referrals). Existing machinery. | **✅ SHIPPED M7-P2** |
| P-3 | **MSH-9 exact pins on referral traffic** | "For the patient referral message this field must be valued as: REF^I12^REF_I12. For the referral response indication message this must be valued as RRI^I12^RRI_I12" (§7.3.1.9, p. 326) | Component value sets on MSH-9.2/.3 gated per message code (REF / RRI); component 1 is the gate itself. | **✅ SHIPPED M7-P2** |
| P-4 | **Escape-sequence prohibitions** | "§3.1.1.5 Hexadecimal — Variance to HL7 International. The hexadecimal escape sequence (\Xdddd...\) must not be used." "§3.1.1.6 — The single-byte character escape sequence \Cxxyy\ and multi-byte … \Mxxyyzz\ must not be used." (p. 136; reiterated p. 159: "The HL7 escape sequences \M and \C shall not be used.") | New `EscapeProhibition` track on `Profile` (leads X/C/M, gated to the guide scope). **Design note:** the parser DECODES escapes into stored values, so the scan re-encodes each subcomponent via `EscapeSequences.encode` (round-trip verified byte-exact) and tokenizes on the escape delimiter — a naive substring scan would miss decoded `\X..\` and false-fire on decoded `\E\` next to a literal X (req #4; both cases test-pinned). | **✅ SHIPPED M7-P3** |
| P-5a | **ACK MSH-12.3.1 closed set** | "MSH-12-3 must be valued 'HL7AU-OO-ACK-READ-2020006'" (§8.4 user read acks) and "MSH-12-3 must be valued 'HL7AU-OO-ACK-201701'" (§8.5 general acks), both p. 372. The two sections partition ACK usage; the flavour is only distinguishable by this value. | ComponentValueSet on MSH-12.3.1 gated `messageCode = ACK`, closed over the pair. The bare "read-acks must carry READ-2020006" statement is **definitional** (the value IS the discriminator, like `000008.1.4`) — what ships is the derived closed set + presence. | **✅ SHIPPED M7-P2** |
| P-5b | **Read-ack MSH-3.3 scheme** | "Valid formats for the user details in MSH-3 (Sending Application) are: Username^\<Medicare Australia provider number\>^AUSHICPR [or] Username^\<HPI-I\>@\<HPI-O\>^NPIO" (§8.4, p. 372) | MSH-3.3 ∈ {AUSHICPR, NPIO} gated `messageCode = ACK AND MSH-12.3.1 = HL7AU-OO-ACK-READ-2020006`. The ID formats themselves (provider-number shape, HPI-I@HPI-O) are content patterns — registered below. | **✅ SHIPPED M7-P2** (scheme component only) |
| P-7 | **Single batch per file** | "In Australia only one Batch is supported but a batch can contain any number of messages." (§1, p. 19) | `BatchValidator` (M8-C): more than one BHS-headed batch group in a `BatchFile` fires. Batch-scope — outside the message-scoped Validator, which is why the finding waited for the component. | **✅ SHIPPED M8-C** |
| P-11 | **OBR-26 not used in Australia** | "Not used in Australian messages. Use observation Sub-ID in OBX-4 to link results" (§4.4.1.26, p. 228) | `ProfileFieldProhibition` on OBR-26, gated `messageCode in (ORM, ORU, REF)`, **warning** (fix round 1: no modal verb, and the ADRM's own OBR-26 attribute-table entry, p. 226/227 item 00259, gives usage O — not X — so per the documented severity convention, `.warning` for SHOULD-level or advisory text, this is not the OBX-2/OBX-5 "must ... valued with null" P4-24 route-B rule's `.error`). No base condition exists on OBR-26 (v2.4/OBR.json: optionality O, no `condition`), so nothing else requires it populated. | **✅ SHIPPED P4-27** |
| P-12 | **ORC-24 not used in Referrals** | "This field should not be used. Use ORC-22 for the address of the prescriber's facility." (§7.3.11.24, p. 343) | `ProfileFieldProhibition` on ORC-24, gated `messageCode = REF`, warning (modal "should"). AU-specific — base v2.4 CH04 §4.5.1.24 and the ADRM's own Observation Ordering leg (§5.4.1.24) carry no such note; only the Patient Referral chapter states it. No base condition exists on ORC-24. | **✅ SHIPPED P4-27** |

## B. Register — prose narrowings that cannot ship faithfully

| Finding | Where | Why not |
|---------|-------|---------|
| OBX-6 units requirement | "When an observation's value is measured on a continuous scale, one must report the measurement units" (p. 241) | The trigger is "measured on a continuous scale" — a property of the observation, not of the message. Mapping it to `OBX-2 = NM/SN` would be an interpretation the spec text does not state (req #2). |
| OBR-3 on non-order messages | "Messages other than order messages must have the filler order number present and must qualify the identifier using the site identifier … of the authoring organisation" (p. 211) | Presence + HD-qualification halves are largely covered by the shipped EI required-component points and `HL7au:000028`'s uniqueness; the remaining "authoring organisation" assertion is not message-decidable (the message cannot prove who authored it). Partial overlap noted; no new rule. |
| TQ component narrowing | "In the Australian context only components 4 'start date/time' and 6 'priority' are used of the TQ data type" (p. 228) | "are used" is descriptive, not "must not be valued" — prohibiting TQ-1/2/3/5/7+ would over-read (req #2/#4). |
| RCPA terminology for OBX-3 | "The terminology for observation identification must come from the RCPA pathology terminology reference set … where an appropriate code exists" (p. 238) | External terminology content plus an undecidable condition ("where an appropriate code exists"). §C territory. |
| Chapter message-type enumerations | "the following message type and trigger event codes shall be used: ORM^O01, ORU^R01, ORR^O02, ACK^R01, ACK^O01" (p. 278) | A chapter-scope statement (Orders). Enforcing it as an MSH-9 value set would misfire on the guide's own referral traffic (REF/RRI, ch. 7) and read-acks. The per-chapter pins that ARE per-message-decidable ship as P-3/P-5. |
| Rendering rules | pp. 250–256 and Appendix 2 (columns, highlighting, date format, age intervals) | Receiver display behaviour — not decidable from a message. |
| MSH field-length variances | e.g. "field length of 250 characters is a variation to the HL7 International standard" (pp. 211, 329) | Field lengths are not modelled (superseded: modelled since M25, enforced since P6-6, see ValidationOptions.fieldLengthSeverity / normativeLengthSeverity); lengths also do not constrain wire validity in this DSL. |
| Read-ack user-ID formats | "Username^\<Medicare Australia provider number\>^AUSHICPR" / "Username^\<HPI-I\>@\<HPI-O\>^NPIO" (§8.4 p. 372) | The scheme component shipped (P-5b); the ID shapes themselves (provider-number pattern, `HPI-I@HPI-O` composition) need content-pattern matching the DSL does not have. Joins P-4's capability if a content-scan track lands. |
| MSH-20 "not used" | "Alternative Character Sets are not used in Australia and this field is null." (§2.1.9.20, p. 56) | Descriptive consequence of AU practice (alt char sets go unused, so the handling-scheme field is incidentally always null), not itself phrased as a field-level prohibition the way OBR-26/OBR-29/ORC-24 are ("Not used…"/"should not be used…" as the sentence's own subject). Treating it the same way risks over-reading a cause-and-effect sentence as a rule (req #4). P4-27. |
| PID-22 content restriction | "In the Australian context this field is not to be used for indigenous status or country of birth" (§2.2.1.22, p. 72) | A content-purpose restriction, not a presence prohibition — PID-22 may still legitimately carry genuine ancestry/ethnicity data. Distinguishing a misused value from a genuine one needs code-system knowledge the message does not declare; not wire-decidable. P4-27. |
| PV1-7 attending-doctor conditional | "In the Australian context this field should not be used unless the system caters for registrars or residents." (§2.2.2.7, p. 78) | The condition ("unless the system caters for…") is a receiver/system capability fact, not message content — not wire-decidable. P4-27. |
| IAM-7 allergy identifier conditional | "If a system maintains allergen codes as a unique identifier for a particular allergy, then this field should not be used." (§7.3.10.7, p. ~360) | Conditional on sender-system capability, not message content — not wire-decidable. P4-27. |
| RP datatype namespace-ID sub-component | "The \<application ID (HD)\> component, \<namespace id (IS)\> sub-component must not be valued." (URL representation note, §4.15-area) | Genuinely unconditional and wire-decidable, but scoped to one sub-component of one datatype (RP) wherever it appears — `ProfileFieldProhibition` checks whole-field presence, not a specific sub-component of a specific datatype instance, and a field-level rule would misfire on any other populated RP sub-component. Needs a component-level prohibition shape (req #3 territory); registered, not shipped. P4-27. |
| TS legacy degree-of-precision component | "This optional second component is retained only for purposes of backward compatibility and should not be used in Australia except by site agreement." (§3.26, p. ~213) | Datatype-component-level (TS's own second component, not a specific field) plus a "except by site agreement" carve-out that is not visible on the wire. Not wire-decidable; mechanism-limited the same way as the RP note above. P4-27. |
| TM datatype "not used" | "Generally not used in the Australian context. TS is used instead." (§3 Datatypes overview table, "Time"/TM row, pdftotext p. 128, cross-referenced to TM's own definition p. 173) | Datatype-selection guidance ("generally"), not a field-level prohibition — it tells implementers which HL7 *data type* to prefer (TS over TM) across every field that could take either, not that any specific field must go unvalued. No single field is named, so there is nothing for `FieldOverride.prohibitions` (a per-field mechanism) to attach to; the DSL has no "data type X must not be selected" shape. Not wire-decidable without per-field datatype-choice tracking outside this task's scope. P4-27 fix round 1. |
| OBX-17 microbiology-susceptibility note | "OBX-17 Observation Method is not used for microbiology susceptibility method." (§4.14.3 Microbiology example, worked-example note 10, p. 260) | Scoped to one specific use of OBX-17 within a worked example (microbiology susceptibility reporting) and immediately followed by the field's *other* legitimate use in the same note ("OBX-17 ... is used for transmitting flags to indicate 'combining of results'"), so OBX-17 is not globally prohibited. "Susceptibility method" is a property of the observation group's clinical content, not something the message declares — not wire-decidable, the same class as the OBX-6 units finding above. P4-27 fix round 1. |

## C. Base-spec observations (not AU narrowings — recorded for base-model work)

- **ORC/OBR pair-equality rules** (pp. 210, 223, 292–296, base v2.4 prose): "If both
  fields, ORC-2 placer order number and OBR-2 placer order number, are valued, they must
  contain the same value" — likewise ORC-3/OBR-3, ORC-12/OBR-16, quantity/timing,
  parent. **✅ The two EI order-number pairs shipped as base rules (M8-B1,
  2026-09-17):** ORC-2/OBR-2 (item 00216) and ORC-3/OBR-3 (item 00217) — the shared
  ITEM number in every version's attribute tables is the spec's own identity assertion,
  with v2.4 §4.5.1.2 stating the consequence and v2.8.2 §4.5.3.2 stating "This field is
  identical to ORC-2". New `IssueCode.pairedFieldMismatch(item:)`; fires per ORC/OBR
  group when BOTH sides are populated and differ (whole-field wire comparison,
  trailing-empty-normalised); runs for every locale and version. **M8-B2 (2026-09-17)
  finished the family:** ORC-12/OBR-16 (item 00226, Ordering Provider — repetition-aware
  comparison, "If both ... are valued, then both must contain the same value", v2.4
  §4.5.1.12) and the parent pair with its version split — ORC-8/OBR-29 on v2.3–v2.6
  ("ORC-8-parent is the same as OBR-29-parent", v2.4 §4.5.1.8) and ORC-8/OBR-54 on
  v2.8.2, where OBR-29 is a DIFFERENT element (00261) and §4.5.1.8 states "Where the
  message has matching ORC/OBR pairs, ORC-8 and OBR-54 Must carry the same value".
  **Deliberately NOT shipped:** ORC-7/OBR-27 (quantity/timing) — the v2.4 prose says the
  pair "should be valued exactly the same" (advisory, not normative) and both fields are
  withdrawn (`W`) from v2.7; an error-level rule would over-read (req #4). The presence
  half ("if not present in the ORC, it must be present in the associated OBR") is
  message-shape-dependent (ORU needs no ORC) and stays unshipped.
- **OBR-29 "not used" vs. the ORC-8/OBR-29 presence rule — NEEDS_CONTEXT (P4-27),
  resolved and SHIPPED as P-13 (P4-32, owner decision G7, 2026-10-01).**
  ADRM §4.4.1.29, p. 229: "Not used in Australian messages. Use observation Sub-ID in
  OBX-4 to link results" (the identical sentence as OBR-26 — item 00261 here, item
  00259 on OBR-26 — see P-11). But ADRM §5.4.1.8, p. 295 (ORC-8, unchanged from base v2.4
  §4.5.1.8) says: "ORC-8-parent is the same as OBR-29-parent. If the parent is not
  present in the ORC, it must be present in the associated OBR." This is not merely
  prose tension: the schema encodes both halves as live base conditions —
  `v2.4/OBR.json` OBR-29 is `C` with condition `ORC-1 = CH AND ORC-8 empty`, and
  `v2.4/ORC.json` ORC-8 is `C` with the mirrored condition `ORC-1 = CH AND (OBR absent
  OR OBR-29 empty)` — and the equality half of the same pair already ships as a base,
  locale-independent rule (M8-B2, `IssueCode.pairedFieldMismatch`, above), which
  presumes OBR-29 can legitimately carry a value. An AU-wide "OBR-29 must not be
  valued" prohibition directly contradicts the base conditional-requiredness check: any
  v2.3–v2.6 child order (`ORC-1 = CH`) sent without ORC-8 already requires OBR-29 under
  the base rule, and the AU prohibition simultaneously forbids it. P4-27 shipped no AU
  prohibition for this reason. **Owner decision G7 (2026-10-01, P4-32) overrides that
  outcome:** the AU "not used" sentence ships anyway, as a warning, matching P-11's
  mechanism and scope exactly — `messageCode in (ORM, ORU, REF)`, the HL7 null exempt.
  The double-bind on a v2.3–v2.6 child order sent without ORC-8 is accepted, not
  re-engineered away: both the AU warning and the base conditionally-required check
  fire on that message. See `task-P4-32-report.md` for the full write-up and
  `Sources/HL7v2Kit/Locale/Profile+au_adrm_2021.swift` (`ADRM-prose:P-13`).
- **Base-spec fields deprecated independently of AU** (found while sweeping for "not
  used" prose, P4-27): OBR-5/OBR-6 ("This field has been retained for backward
  compatibility only. It is not used…", v2.4 CH04, reprinted verbatim in ADRM
  §4.4.1.5/.6) and MSA-5 (same phrasing, CH02 §2.16.8.5/ADRM §2.1.8.5) are base v2.4
  deprecations, not AU narrowings — `.international` is affected too. RXO-3 ("In a
  non-varying dose order, this field is not used", CH04/ADRM identical) is conditional,
  not unconditional. Out of this task's AU-specific scope; recorded for base-model work
  if a base "deprecated (retained for compatibility only)" prohibition track is ever
  opened.
- **RXO-1/2/4 vs RXO-6 free-text conditional** (pp. 346–348): "The RXO-1, RXO-2 and
  RXO-4 are mandatory unless the prescription is transmitted as free text using RXO-6,
  then … the first subcomponent of RXO-6 must be blank." Compound conditional
  (requiredness disjunction + component-empty assertion). The requiredness half is
  expressible per-field (`RXO-6 empty` conditions); the RXO-6.1-must-be-blank half needs
  a "component must be empty when field populated" shape. Recorded; base + referral
  usage.
- **v2.4 OBX-2 condition** ("must be valued if OBX-11 is not X", p. 236) — verified
  already modelled: `v2.4/OBX.json` carries `C` / `OBX-11 != X`. No action.

## D. Already covered (spot-verified during triage)

MSH-15/16 = AL (00047.1/.2) · MSH-18 ASCII value set (00048.3.1) · TS timezone offset
(00044.8.1, shipped M6-B-9 — the p. 213/214/215 "the time zone must be included" prose
is this point's body text) · PID-35/37 conditionality (base grammar conditions) ·
UPIN/0203 accommodation (M6-B-8) · LOINC-first triplet ordering (00044.4.4/000034) ·
NTE prohibition (000023) · Z-segment prohibition (000023.1).

## The normative-appendices pass (M7-P4, complete)

Same scan over pdftotext pages 482–548 (appendices 8–10): 63 candidates, all read.

| Appendix | Outcome |
|---|---|
| **8 — Simplified REF profile** (pp. 482–489) | The L1/L2 display-segment requirements are the already-shipped `HL7au:000008.3.1` legs (M6-B-6). "If atomic allergy information is included, it must be represented in the AL1 segments" is definitional (allergy content is not detectable outside AL1); the sender-workflow rules (copy OBR/OBX groups from source messages) are cross-message; receiver display/filing rules are receiver-scope. Nothing new ships. |
| **9 — HL7v2 VMR** (pp. 490–527) | **P-6 SHIPPED:** the VMR header OBX pins — "This header OBX must have a OBX-2 Datatype field value of 'RP'" and "OBX-5 must be valued as 'HL7V2-VMR.v1^HL7V2 VMR&99A-9AAC5A649D18B6F2&L^TX^Octet-stream'" (p. 490), gated on the header's own discriminator (`messageCode = REF AND OBX-3.1 = 74028-2` — "OBX-3 field must have the value 74028-2^Report template ID^LN"). Full literal pinned per component/subcomponent into the existing OBX-2/OBX-5 overrides (the Validator honours ONE FieldOverride per field — first match — so pins merge rather than adding parallel overrides). **SHIPPED 2026-09-21 (M12), was registered:** the OBX-4 sub-ID tree. The implementation table (pp. 492–515, 89 rows) is extracted as `Resources/profiles/au-adrm-2021/vmr-table.json` and a `SubIDTreeRule` model track ships **P-8** (an observation sharing the header's root must instantiate a table row — "must not have a OBX-4 subID sharing the same root", p. 515), **P-9** (a STRUCTURAL row "must not be written to OBX segments") and **P-10** (the header's sub-ID "must be a dotted decimal value", p. 490), scoped per OBR group and gated like P-6. The root is read from the header ("may be another number", p. 362). **Registered, not shipped:** the table's OBX-2 and OBX-3 columns — the appendix's own worked example (p. 516) uses CE for the table's CWE and 70949-3 for its 73983-9, so either pin would fire on the spec's own text (req #4); and the OCCURRENCES column — HL7 lets several OBX share a sub-ID and the appendix never says which the VMR forbids. |
| **10 — PD addressing** (pp. 528–548) | Every rule is "values must be copied from / match the directory" (FHIR PractitionerRole / Endpoint / HealthcareService resources) — consistency with an external directory, not message-decidable. The two message-decidable statements it contains (single AP / single IR in PRD-1, p. 537) are the already-shipped `HL7au:00104.1.1/.2.1`. "PRD-2 and PRD-7 must be populated for all PRD segments" is scoped to "when using the Australian Profile for Provider Directory Services", which is a transport/directory arrangement with no wire declaration — gate undecidable, registered. |

Appendix 2 (rendering) confirmed receiver-scope; Appendix 3 (common errors) is
informative guidance; Appendix 5 is the M6 register's territory.

## Standing rule

A prose finding ships only with the quoted sentence and page in its citation, same bar
as Appendix 5 points. "The prose implies…" is not a citation (req #2).
