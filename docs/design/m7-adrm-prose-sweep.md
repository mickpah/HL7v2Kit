# M7 — ADRM-2021 chapter-body prose sweep

| | |
|---|---|
| Started | 2026-09-16 (M7-P1) |
| Status | **P1 (measurement + triage) complete.** Ship candidates queued as M7-P2/P3; register entries recorded below. Normative appendices 8–10 remain unswept (follow-on P4). |
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
| P-1 | **PID-1 profile-required** | "PID-1 is mandatory in the Australian context. Variance to HL7 International." (PID attribute-table footnote †††, p. 61) | `FieldOverride` profileUsage R, gated to the ADRM message scope (ORM/ORU/REF), citation `AU ADRM-2021 p. 61` | **queued M7-P2** |
| P-2 | **REF disallowed segments** | "§7.4.2 Disallowed segments — The following segments … must not be used by senders": ACC, AUT, CTD, DRG, DSC, DSP, GT1, IN2, NTE, PR1 (p. 363) | Nine new `maxCount: 0` prohibitions gated `messageCode = REF` (NTE is already shipped `HL7au:000023` over Orders/Results/Referrals). Existing machinery — no model change. | **queued M7-P2** |
| P-3 | **MSH-9 exact pins on referral traffic** | "For the patient referral message this field must be valued as: REF^I12^REF_I12. For the referral response indication message this must be valued as RRI^I12^RRI_I12" (§7.3.1.9, p. 326) | Component value sets on MSH-9.1/.2/.3 gated per message code (REF / RRI). Existing machinery. | **queued M7-P2** |
| P-4 | **Escape-sequence prohibitions** | "§3.1.1.5 Hexadecimal — Variance to HL7 International. The hexadecimal escape sequence (\Xdddd...\) must not be used." "§3.1.1.6 — The single-byte character escape sequence \Cxxyy\ and multi-byte … \Mxxyyzz\ must not be used." (p. 136; reiterated p. 159: "The HL7 escape sequences \M and \C shall not be used.") | Needs a small content-scan capability (a prohibited-escape-sequences track on `Profile`, same shape as the M6-B-9 timezone check). Model extension, small. | **queued M7-P3** |
| P-5 | **MSH-12.3 read-acknowledgement profile pin** | "MSH-12-3 must be valued 'HL7AU-OO-ACK-READ-2020006'" (p. 372, read-ack profile section) | Same MSH-12.3.1 gate machinery as M6-B-6, once the rule's message-shape scope is confirmed from surrounding prose. | **investigate in M7-P2** |

## B. Register — prose narrowings that cannot ship faithfully

| Finding | Where | Why not |
|---------|-------|---------|
| OBX-6 units requirement | "When an observation's value is measured on a continuous scale, one must report the measurement units" (p. 241) | The trigger is "measured on a continuous scale" — a property of the observation, not of the message. Mapping it to `OBX-2 = NM/SN` would be an interpretation the spec text does not state (req #2). |
| OBR-3 on non-order messages | "Messages other than order messages must have the filler order number present and must qualify the identifier using the site identifier … of the authoring organisation" (p. 211) | Presence + HD-qualification halves are largely covered by the shipped EI required-component points and `HL7au:000028`'s uniqueness; the remaining "authoring organisation" assertion is not message-decidable (the message cannot prove who authored it). Partial overlap noted; no new rule. |
| TQ component narrowing | "In the Australian context only components 4 'start date/time' and 6 'priority' are used of the TQ data type" (p. 228) | "are used" is descriptive, not "must not be valued" — prohibiting TQ-1/2/3/5/7+ would over-read (req #2/#4). |
| RCPA terminology for OBX-3 | "The terminology for observation identification must come from the RCPA pathology terminology reference set … where an appropriate code exists" (p. 238) | External terminology content plus an undecidable condition ("where an appropriate code exists"). §C territory. |
| Chapter message-type enumerations | "the following message type and trigger event codes shall be used: ORM^O01, ORU^R01, ORR^O02, ACK^R01, ACK^O01" (p. 278) | A chapter-scope statement (Orders). Enforcing it as an MSH-9 value set would misfire on the guide's own referral traffic (REF/RRI, ch. 7) and read-acks. The per-chapter pins that ARE per-message-decidable ship as P-3/P-5. |
| Rendering rules | pp. 250–256 and Appendix 2 (columns, highlighting, date format, age intervals) | Receiver display behaviour — not decidable from a message. |
| MSH field-length variances | e.g. "field length of 250 characters is a variation to the HL7 International standard" (pp. 211, 329) | Field lengths are not modelled (documented model scope); lengths also do not constrain wire validity in this DSL. |

## C. Base-spec observations (not AU narrowings — recorded for base-model work)

- **ORC/OBR pair-equality rules** (pp. 210, 223, 292–296, base v2.4 prose): "If both
  fields, ORC-2 placer order number and OBR-2 placer order number, are valued, they must
  contain the same value" — likewise ORC-3/OBR-3, ORC-12/OBR-16, quantity/timing,
  parent. Cross-segment **equality** between paired fields is expressible in spirit via
  the ADR-008 DSL but there is no shipped base rule. Candidate for a base-grammar
  cross-segment rule set (all six versions state it). Out of AU-profile scope; belongs
  to the base-model runway.
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

## Follow-on scope (not yet swept)

- **Normative appendices 8 (Simplified REF profile), 9 (HL7v2 VMR), 10 (PD addressing)**
  — excluded from the body scan range. Appendix 8's points largely surface in Appendix 5
  (the L1/L2 legs shipped in M6-B-6); 9 and 10 need their own pass (M7-P4).
- Appendix 2 (rendering) confirmed receiver-scope; Appendix 3 (common errors) is
  informative guidance.

## Standing rule

A prose finding ships only with the quoted sentence and page in its citation, same bar
as Appendix 5 points. "The prose implies…" is not a citation (req #2).
