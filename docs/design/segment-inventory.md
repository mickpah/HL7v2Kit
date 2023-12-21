# HL7 segment inventory — the M5 work-list

The enumerated scope of ROADMAP **M5** (full HL7 segment coverage across all supported
versions). Built 2026-07-12 by scanning every chapter PDF's attribute-table captions
(`HL7 Attribute Table – XXX` / `Figure N-N. XXX attributes`) via the ADR-015 pipeline.
Z-segments excluded (site-defined, not standard). This is the denominator M5 closes
against; it is a discovery artifact, refined as authoring proceeds.

## Scale

| Version | Distinct standard segments |
|---|---|
| v2.3 | 106 |
| v2.3.1 | 106 |
| v2.4 | 138 |
| v2.5.1 | 150 |
| v2.6 | 170 |
| v2.8.2 | 180 |
| **Union (any version)** | **188** |
| **Sum (schema-instances to author for full depth)** | **~850** |

**Today: 100 typed segments** at verified per-version depth (see above).
The ~850 figure is the full schema-authoring runway (each segment × each version it
appears in, at full field depth).

## Currently modelled (100)

`AIG AIL AIP AIS AL1 APR ARQ AUT BPO BPX BTX CDM CNS CON CSP CSR CSS CTD CTI DB1 DG1 ECD
ECR EQP EQU ERR EVN GOL GT1 IIM IN1 IN2 IN3 INV ISD LCC LCH LDP LOC LRL MFA MFE MFI MRG
MSA MSH NDS NK1 NTE OBR OBX OM1 OM2 OM3 OM4 OM5 OM6 OM7 ORC PCR PD1 PDC PEO PES PID PRB
PRC PRD PSH PTH PV1 PV2 QAK QID QPD QRD QRF RCP RDF RDT RF1 RGS ROL RXA RXC RXD RXE RXG
RXO RXR SAC SCH SID SPM TCC TCD TQ1 TQ2 TXA VAR`

Canonical v2.5.1 defect-clean + complete (v1.1-S3). **NK1/PV1/IN1 full-depth on all 6
versions (v1.2).** New typed segments, full-depth on every version they appear in:
**v1.2** PV2/MRG/DB1/GT1/IN2/IN3 + TQ1/TQ2/RXO/RXR/RXC/RXE/RXD/RXG; **v1.3**
SPM/ROL/SCH/RGS/AIS/AIG/AIL/AIP/APR/ARQ/BPO/BPX/BTX/RXA + MFI/MFE/MFA/OM1–OM7/RF1/AUT/PRD/CTD;
**v1.4** QPD/QRD/QRF/QAK/QID/RCP/RDF/RDT + EQU/SAC/INV/TCC/TCD/EQP +
LOC/LCH/LRL/LDP/LCC/CDM/PRC/IIM + GOL/PRB/PTH/VAR + TXA/CON; **v1.7**
ISD/NDS/CNS/ECD/ECR/SID (CH13 completion, v2.4+ only — v2.3 / v2.3.1 have no CH13);
**v1.8** PES/PEO/PCR/PDC/PSH + CSR/CSP/CSS/CTI (CH07 completion, all 6 versions).

**Depth is verified, not assumed** (audit re-run each batch via `scripts/audit-schemas.py`):
530 of 536 committed schemas match their own version's attribute table exactly; the 6
exceptions are RDT, a known `1-n` variable-column extractor limitation.

**~88 segments remain unmodelled** — the v1.9+ runway.

## The union work-list (188)

The full set appearing in any supported version. Presence varies by version (v2.3 has
106; v2.8.2 has 180 — the count grows monotonically with the standard).

```
ABS ACC ADD ADJ AFF AIG AIL AIP AIS AL1 APR ARQ ARV AUT BHS BLC BLG BPO BPX BTS BTX
BUI CDM CDO CER CM0 CM1 CM2 CNS CON CSP CSR CSS CTD CTI DB1 DG1 DMI DON DPS DRG DSC
DSP ECD ECR EDU EQL EQP EQU ERQ ERR EVN FAC FHS FT1 FTS GOL GP1 GP2 GT1 IAM IAR IIM
ILT IN1 IN2 IN3 INV IPC IPR ISD ITM IVC IVT LAN LCC LCH LDP LOC LRL MCP MFA MFE MFI
MRG MSA MSH NCK NDS NK1 NPU NSC NST NTE OBR OBX ODS ODT OM1 OM2 OM3 OM4 OM5 OM6 OM7
OMC ORC ORG OVR PAC PCE PCR PD1 PDA PDC PEO PES PID PKG PM1 PMT PR1 PRA PRB PRC PRD
PRT PSG PSH PSL PSS PTH PV1 PV2 PYE QAK QID QPD QRD QRF QRI RCP RDF RDT REL RF1 RFI
RGS RMI ROL RQ1 RQD RXA RXC RXD RXE RXG RXO RXR RXV SAC SCD SCH SCP SDD SFT SGH SGT
SHP SID SLT SPM SPR STF STZ TCC TCD TQ1 TQ2 TXA UAC UB1 UB2 URD URS VAR VND VTQ
```

## Sweep sequencing (proposed)

Additive v1.1+ cycles (ADR-014; API stays frozen), extractor-seeded + human-verified,
each with cross-check pins + the golden gate. Suggested order by integrator value:

1. **Per-version depth for the existing 15** — close NK1/PV1/IN1 (and any other partials)
   across v2.3/v2.3.1/v2.4/v2.6/v2.8.2. Highest value; the extractor is already proven on
   these exact tables.
2. **High-traffic ADT / order / result segments not yet typed** — e.g. PV2, GT1, ROL,
   SPM, TQ1/TQ2, SCH, RXA/RXE/RXO/RXR, FT1, IN2/IN3, MRG, DB1, AL1-adjacent.
3. **Master-file / scheduling / financial / lab-automation families** — the OM*, MF*,
   AI*, RX*, SAC/SPM clusters, by chapter.
4. **Long-tail** — the remaining specialised segments.

Each cycle: author schema(s) → `regenerate-typed-segments.sh` → cross-check test →
green → commit. Coverage is additive; the frozen v1.0 API only grows.

## Methodology / caveats

- Enumeration is caption-based; a segment defined only in prose (no attribute table) or
  with a non-standard caption could be missed — the count is a floor, reconciled as the
  sweep authors each chapter.
- "Distinct standard segments" excludes Z-segments and batch/file envelope pseudo-rows
  are included where they carry an attribute table (BHS/BTS/FHS/FTS/MSH etc.).
- Per-version *presence* (which of the 188 appear in each version) is derived on demand
  from the same scan during each chapter's authoring cycle.
