# Australian localisation

Validate a message against HL7 Australia's localisation profile, ADRM 2021.1, and know what it
checks, what it checks in part, and what no message can tell it.

## Overview

``HL7Locale/auLocalisation`` is the Australian Diagnostics and Referral Messaging localisation
of HL7 v2.4 (`HL7AUSD-STD-OO-ADRM-2021.1`, here "the ADRM"). The ADRM narrows v2.4 for pathology
and radiology orders and results and for referrals: it fixes the separators and the version
declaration, requires identifier and coding-system components, defines display segments and
constrains the message structures. Appendix 5 lists its 263 conformance points, each with an
`HL7au:` identifier; every finding the profile raises names one.

The profile governs a message of every version, by owner ruling (G-AU1, 2026-10-07). AU senders
also declare v2.3.1 and v2.5.1 and later, and the ADRM's rules are field-level, so:

- **Field rules apply on every version.** Each field, component, value-set, prohibition and
  cardinality rule is evaluated on the message, read through its own version's grammar, with the
  rule's own gate (message code, PRD-1 and so on). HL7au:000040.1/.2 itself reports an MSH-12.1
  other than `2.4` on ORM, ORU, REF, RRI and ACK.
- **Profile structures apply only on base v2.4.** The six ADRM message structures (ORU_R01,
  ORM_O01, ORR_O02, REF_I12 with its Appendix 8 variant, RRI_I12, OSR_Q06) are v2.4 structures.
  A v2.5.1 or later message draws no HL7au:00060.1 structure finding, and its base structure
  findings are kept as the base match reports them.

## Turning it on

Pass the locale to ``Validator`` (or to ``BatchValidator`` for a batch file):

```swift
var options = ValidationOptions.strict
options.auPathologySender = true      // only when the sender is a pathology provider
let report = Validator(options: options, locale: .auLocalisation).validate(message)
for issue in report.issues {
    if case .profileConstraintViolation(let rule) = issue.code, rule.hasPrefix("HL7au:00060.1") {
        // a segment the ADRM structure requires is missing
    }
}
```

The international locale (the default) applies none of the AU rules.

### The four caller assertions

Four rules are scoped by a fact the wire does not carry. Each is a ``ValidationOptions`` property,
`false` by default (the rule stays silent), set by mutation, and read only under
``HL7Locale/auLocalisation``. Set one only when the fact holds for every message you validate
with those options.

- ``ValidationOptions/auPathologySender``: the sender is a pathology provider. HL7au:00050.1.5
  is scoped "Senders (Pathology only)" (p 466), and no field says which discipline sent the
  result; when set, OBX-6.3 must be `UCUM` on Results.
- ``ValidationOptions/auDisplayIntended``: the coded elements are meant for display. HL7au:00044.4.3
  requires CE `<text>`, but "in some locations user display is not intended and the text may be
  blank", and those locations are not on the wire; when set, CE-2 must be valued.
- ``ValidationOptions/auNASHTransport``: the message travels by Secure Message Delivery secured with
  NASH certificates. When set, HL7au:00044.2.2 and 00044.2.3 require the MSH-4 and MSH-6
  Universal ID to be `1.2.36.1.2001.1003.0.` and a 16-digit HPI-O with Universal ID Type `ISO`,
  HL7au:00044.3.3/.3.4 constrain the EI universal ID the same way, and HL7au:000043.1 and
  00044.2.1 require the organisation name in MSH-4.1 and MSH-6.1. All the NASH rules, MSH and EI
  alike, run on ORM, ORU and REF only, the scope Appendix 5 defines on p 416 ("Orders = ORM
  messages").
- ``ValidationOptions/auAssigningAuthorityTable``: PRD-7 assigning authorities come from Table 0363
  as printed (p 310) plus the vendor authorities you list in
  ``ValidationOptions/localTableExtensions`` under `"0363"`. HL7au:00104.7.2.1 requires the table,
  and the ADRM lets it "be extended to allow for secure messaging vendor assigning authorities"
  (p 334); which vendors a site has agreed is not on the wire. When set, PRD-7.2 is checked on
  Referrals.

## What the profile checks

A broken field-level rule is reported as ``IssueCode/profileConstraintViolation(localeRule:)`` at
`.error`; `localeRule` opens with the conformance point (for example `"HL7au:000024.1 — ..."`),
so match it with `hasPrefix`. The groups below follow the ADRM's own sections.

**Message addressing and NASH.** MSH-6 must be valued on an order (HL7au:000001, p 417: an order
"is addressed using MSH-6 Receiving facility"). MSH-12 must declare `2.4^AUS&Australia&ISO3166_1`
and the profile in MSH-12.3 (HL7au:000040.1 to .4): `HL7AU-OO-201701&&L` on Orders and Results,
and on Referrals and RRI one of the Appendix 8 identifiers. The NASH rules are the
`auNASHTransport` ones above. Example: `HL7au:00044.2.3` (Universal ID Type `ISO`).

**Identifiers and Table 0203.** CX-1, XCN-1 and EI-1 must be valued, and CX-5, XCN-13 and PRD-7.3
must be valued from the ADRM's own Table 0203 (pp 301 to 309, with its printed `NNxxx` row).
Example: `HL7au:00044.1.3` (CX-5).

**Coding systems and Table 0396.** LOINC must be the primary coding system, not the alternate,
on Orders and Results (HL7au:00044.4.4). When OBX-3 or a coded OBX-5 carries both a public and a
local code, the public code is primary: a local primary (`L` or `99zzz`, Table 0396 p 144) with
a public system of the ADRM's Table 0396 in the alternate fires. Example: `HL7au:000034.1`.

**Display segments and PDF.** A display OBX is recognised by OBX-3.3 `AUSPDI`; its OBX-2 must
match the display format in OBX-3.1, ED for RTF, HTML and PDF and FT for TXT and PIT (p 247;
HL7au:000008.1.3), it must be last in its OBR/OBX group, a digital
signature OBX excepted (HL7au:000008.1.5), and an RTF display needs an HTML, PDF or TXT sibling
in the same group (HL7au:000008.3.2). An encapsulated (ED) or reference (RP) display's MIME
subtype must agree with its type (HL7au:00044.10.1.5/.6, 00044.11.1.5/.6), so `^application^pdf`
is accepted and `^text^pdf` is not. Example: `HL7au:000008.1.5`.

**Required segments and the profile structures.** With
``ValidationOptions/messageStructureSeverity`` set (the default and strict presets), a v2.4
ORU^R01, ORM^O01, ORR^O02, REF^I12, RRI^I12 or OSR^Q06 is matched against the ADRM structure as
well as the base one, and a segment the ADRM structure requires and the message lacks is
reported with `localeRule` `"HL7au:00060.1"`, at that severity. A REF^I12 that declares
`HL7AU-OO-REF-SIMPLIFIED-201706` or `HL7AU-OO-REF-SIMPLIFIED-201706-L1` in MSH-12.3.1 is matched
against the Appendix 8 simplified structure (A8.5, pp 484 to 485) instead (owner ruling G-AU3;
see ``StructureVariant/profileIdentifiers``); RRI^I12 is unchanged by A8.5. ORR^O02 follows its print (pp 280 to 281) with PID
optional, as the base v2.4 reading has it (owner ruling G-AU2). An occurrence beyond a maximum the
ADRM narrows (a second IN1, PV1 or PV2 on REF^I12, p 324) is reported as
``IssueCode/profileMaximumExceeded(localeRule:)`` at `.info`.

**Separators and batch headers.** MSH-1 and MSH-2 must carry the standard separators
(HL7au:000024.1 to .5); ``BatchValidator`` applies the same to FHS and BHS, runs every message's
AU rules (the per-message acknowledgement of HL7au:000022.1), and reports a REF batched with any
other message (HL7au:000022.3). Example: `HL7au:000024.1`.

**Field lengths the ADRM varies.** The ADRM's attribute tables print a LEN other than v2.4's for
15 fields: MSH-10, MSH-12, PV1-10, PV1-21, AL1-1, AL1-5, OBR-2, OBR-3, OBR-9, OBX-18, ORC-2,
ORC-3, ORC-4, RF1-6 and RF1-11. Under the profile the length check reads the ADRM's figure, so a
250-character order number is clean and a five-digit AL1-1 is not. A breach is
``IssueCode/fieldLengthOutOfRange(length:actual:)`` naming the ADRM length, at
``ValidationOptions/fieldLengthSeverity``.

**The MIME tables.** The ADRM prints Table 0191 with the IANA types added (`application`, `image`,
`text` and others, pp 167 to 168) and Table 0291 with the subtypes `pdf`, `png`, `xml` and `emf`
added (pp 169 to 170), and says MIME types "are imported from" IANA (p 168).
Both AU tables are therefore open: any registered type or subtype is admitted, where the
international locale reports ``IssueCode/valueNotInTable(table:)`` for a value v2.4 does not list.
Because the profile governs every version (G-AU1), the open AU Table 0191 also admits a value
the message's own version rejects: a TXA-3 of `PDF` on a v2.7.1 or v2.8.2 message is clean under
the AU locale though the base Table 0191 of those versions does not list it (four rows of the
validation digest over the v2.7.1 and v2.8.2 Chapter 9 examples). That is the ruling's effect,
recorded as an open owner item below.

## Coverage

The generated conformance register (`docs/design/m6-adrm-2021-conformance-register.md`, 302 rows
for 263 points, reconciled with the shipped state on 2026-10-07) classes every point:

| Class | Points | Meaning |
| --- | ---: | --- |
| SHIPPED | 79 | enforced in full |
| PARTIAL | 17 | the wire-decidable half enforced; the rest stated per point |
| REGISTERED | 5 | a known limitation, registered with its citation |
| BASE | 9 | already enforced by the base v2.4 checks; the profile adds nothing |
| RECEIVER | 74 | what a receiver must do, not what a message must contain |
| OUT | 76 | out of scope by nature: transport, payload content, cross-message state |
| WITHDRAWN | 3 | removed by the ADRM's revision r2 |

### What is partial, and what you can check yourself

- **HL7au:00060.1, one residual.** RXO, ODS or ODT in place of OBR in an ORR^O02 or OSR^Q06
  response is accepted: p 280 prints that replacement for ORM^O01 only, and the print does not
  settle whether it carries over to the responses. RQD and RQ1 there are reported.
- **IHI as a PRD-7 authority.** HL7au:00104.7.1.4 and 00104.7.2.1 accept `IHI` in PRD-7.2,
  an accommodation row the AU Table 0363 keeps though p 310 does not print it: an under-report
  kept by ruling. Check IHI-qualified PRD-7 values yourself if your trading partners forbid them.
- **Terminology halves.** HL7au:000034.1/.2 skip a public system outside the printed Table 0396
  and a local system spelt other than `L` or `99zzz`. The presence halves of 00044.1.1, 00044.3.1
  and 00044.7.1 ship; whether the identifier is valid for its scheme does not.
- **Other halves.** OBR-24 "appropriate for the content" (000032.2), RTF "same content" as its
  sibling (000008.3.2), the Z message code leg of 000020, and uniqueness across messages
  (00044.3.1) are judgements or state no single message carries.
- **Halves the wire does not carry.** HL7au:000001 requires MSH-6 on an order (checked); the NATA
  number and name of 000001.2 need the NATA register. HL7au:000022.1's individual acknowledgement
  is checked on every batched message; "no information from the file header/footer or batch
  segments must be used" is what a receiver does.
- **MIME subtype to type.** HL7au:00044.10.1.5 and 00044.11.1.5 check the ED and RP subtype
  against its type for the pairs the ADRM states; any other IANA subtype is not checked.

Every PARTIAL point, with what is not enforced, is a row of register section B
(`docs/design/permanent-limitations-register.md`) and of the generated conformance register.

### What is permanent, and why

- **Terminology equivalence.** HL7au:000034.3, 00044.4.7, 00044.5.7 and 00044.6.7 ask that two
  codes "reflect the same concept", and HL7au:00100.1 needs SNOMED CT-AU subsumption to find the
  referral summary group; both need a terminology service, outside this package.
- **The NASH directory and certificate halves.** Whether MSH-4.1 is the name "registered by in
  the Medicare Australia HPOS/HI service" (00044.2.1) needs the HI directory; the points that
  compare against a vendor X.509 certificate need PKI.
- **Timezone correctness.** HL7au:00044.8.1 requires an offset on a timestamp of hour precision or
  finer (checked); whether the offset is correct for the sender's local time is not decidable.
- **Receiver behaviour.** The 74 RECEIVER points describe what a receiver does.
- **Digital signatures beyond p 438.** The signature OBX is recognised by p 438's description only
  (OBX-3 identifier starting `AUSETAV`, coding system `L`); the signature content HB 308-2011
  defines is not reproduced in the ADRM and is not checked.

### Open owner items

- **Level 1 of the simplified referral.** A8.2.1.1 (p 482) describes Level 1 as "baseline
  receiving capability of a single OBR observation group". The `-L1` identifier selects the same
  structure as Level 2, with no cap on the OBR group; whether to cap it is open.
- **HL7au:000040.4 on a Chapter 7 REF.** The point requires every Referral to declare an Appendix 8
  identifier in MSH-12.3, and Table 0104x (p 43) gives none for a referral that follows the
  Chapter 7 structure, so such a REF^I12 draws 000040.4. That is the print's rule; whether it
  should reach a Chapter 7 REF is open.
- **Tables 0191 and 0291 open on every version.** The AU locale's open MIME tables admit a
  value the base table of a later version rejects (a TXA-3 `PDF` on v2.7.1 and v2.8.2); whether
  the AU tables should narrow to the base table off v2.4 is open.

## Worked examples

The synthetic fixtures under `Tests/Fixtures/` are clean except where noted under
``ValidationOptions/strict`` with the AU locale, with and without the four assertions
(`AUFixtureTests`): `au_ref_i12.hl7` draws HL7au:000040.4 by the print. Each also pins one rule
family by changing one field.

| Fixture | What it shows |
| --- | --- |
| `au_oru_r01_pathology.hl7` | NASH HD and EI addressing, LOINC with UCUM units, an HTML display OBX last in its group |
| `au_oru_r01_pathology_pdf.hl7` | the PDF display form `^application^pdf` with base64 content |
| `au_oru_r01_radiology.hl7` | a TXT (FT) display OBX and the FT escape `\.br\` |
| `au_orm_o01.hl7` | an order addressed by MSH-6 (000001) |
| `au_orr_o02.hl7` | the ORR^O02 print with PID (G-AU2) |
| `au_osr_q06.hl7` | the AU OSR^Q06 structure with QRD |
| `au_ref_i12.hl7` | a Chapter 7 referral; it draws HL7au:000040.4 (see the owner items) |
| `au_ref_i12_simplified.hl7` | a Level 2 Appendix 8 referral selected by MSH-12.3 |
| `au_rri_i12.hl7` | MSA with the echoed RF1, PRD and PID |
| `Batches/au_batch_oru_r01.hl7` | two results in FHS/BHS through ``BatchValidator`` |

## Local table extensions

A site may extend an HL7 table locally. List the codes in
``ValidationOptions/localTableExtensions`` keyed by four-digit table number. Besides the base
code-table check, four AU value sets honour the entry: Table 0074 (OBR-24), Table 0200 (XCN-10),
Table 0203 (CX-5, XCN-13, PRD-7.3) and, under `auAssigningAuthorityTable`, Table 0363 (PRD-7.2).
AU rules that pin a field to fixed literals (the separators, MSH-12) are not affected.

## See Also

- <doc:Validation>
- ``HL7Locale``
- ``ValidationOptions``
- ``BatchValidator``
