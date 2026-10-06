#!/usr/bin/env python3
"""Extract the ADRM-2021 Appendix 5 conformance-statement table (M6).

The AU localisation states its normative narrowings as a table of HL7au
conformance points in Appendix 5. This script recovers that table from the
`pdftotext -layout` rendering and classifies every point against what
HL7v2Kit's `.auLocalisation` profile actually ships, so the coverage claim
is measured rather than asserted (the working notes req #2/#4).

Usage:
    pdftotext -layout "<ADRM-2021 PDF>" /tmp/adrm2021.txt
    python3 scripts/extract-adrm-conformance.py /tmp/adrm2021.txt \
        > docs/design/m6-adrm-2021-conformance-register.md

Exit status is 0 always; this is a register generator, not a gate.
"""
import json
import re
import sys

# ---------------------------------------------------------------- parsing

def parse_appendix5(path):
    """Return the Appendix 5 rows as dicts. Column offsets are taken from
    each page's own repeated header, because they drift between pages."""
    lines = open(path).read().split('\n')
    start = next(i for i, l in enumerate(lines)
                 if l.startswith('Appendix 5 Conformance Statements'))
    end = next(i for i, l in enumerate(lines)
               if i > start and l.startswith('Appendix 6 Example Messages'))
    cols, rows, cur = None, [], None

    def flush():
        nonlocal cur
        if cur:
            # ids wrap mid-token ("HL7au:000 45.5") and can end on a dot
            cur['id'] = re.sub(r'\s+|\.$', '', cur['id'])
            for k in ('appl', 'mtype', 'text', 'comment'):
                cur[k] = re.sub(r'\s+', ' ', cur[k]).strip()
            rows.append(cur)
            cur = None

    for ln in lines[start:end]:
        if 'HL7au Identifier' in ln and 'Conformance point text' in ln:
            flush()
            cols = (ln.index('HL7au Identifier'), ln.index('Applicable to'),
                    ln.index('Message Type'), ln.index('Conformance point text'),
                    ln.index('Comments') if 'Comments' in ln else 10 ** 6)
            continue
        if cols is None or not ln.strip():
            continue
        if re.match(r'\s*(HL7AUSD-STD-OO|Australian Diagnostics|'
                    r'Senders/Receivers|Both\s*$|Applicability)', ln):
            continue
        if re.match(r'^\d+\s+https?://', ln):      # footnote lines
            continue
        idcol = ln[:cols[1]].strip()
        m = re.match(r'\(?(HL7au:[\d. ]*[\d.])\)?\s*(\(r\d\))?$', idcol)
        if m and 'HL7au:' in idcol:
            flush()
            cur = {'id': m.group(1), 'rev': (m.group(2) or '').strip('()'),
                   'grouper': idcol.startswith('('),
                   'appl': ln[cols[1]:cols[2]], 'mtype': ln[cols[2]:cols[3]],
                   'text': ln[cols[3]:cols[4]], 'comment': ln[cols[4]:]}
            continue
        if cur is None:
            continue
        # a wrapped id tail sits alone in the id column ("2.04")
        if re.fullmatch(r'[\d.]+', idcol) and (not cur['text'].strip()
                                               or cur['id'].endswith('.')):
            cur['id'] += idcol
            if not cur['text'].strip():
                continue
        cur['appl'] += ' ' + ln[cols[1]:cols[2]].strip()
        cur['mtype'] += ' ' + ln[cols[2]:cols[3]].strip()
        cur['text'] += ' ' + ln[cols[3]:cols[4]].strip()
        cur['comment'] += ' ' + ln[cols[4]:].strip()
    flush()
    return rows

# ------------------------------------------------------- classification

# Points the `.auLocalisation` profile enforces today. Literal citations
# plus the four pair-rules `ceCwePairRules` interpolates per composite.
# M29/M30/M32 — points whose ADRM gate is a fact the wire does not carry, so
# the caller asserts it through ValidationOptions. Shipped, but off by default.
# Value is (text marker or None, note). The marker disambiguates a repeated
# identifier: the ADRM numbers TWO rows `HL7au:00044.3.4` — the EI Universal ID
# rule (r2) and a vendor-certificate rule — and only the first one ships.
CALLER_ASSERTED = {
    'HL7au:00050.1.5': (None, 'shipped caller-asserted (M29): `ValidationOptions.auPathologySender`'),
    'HL7au:00044.4.3': (None, 'shipped caller-asserted (M30): `ValidationOptions.auDisplayIntended`'),
    'HL7au:00044.2.2': (None, 'shipped caller-asserted (M32): `ValidationOptions.auNASHTransport`; prefix + the 16-digit HPI-O of HL7au:000043.1, honoured by all 8 OID values the ADRM prints'),
    'HL7au:00044.2.3': (None, 'shipped caller-asserted (M32): `ValidationOptions.auNASHTransport`'),
    'HL7au:00044.3.4': ('Universal ID component',
                        'shipped caller-asserted (M33): `ValidationOptions.auNASHTransport`, datatype-wide on EI; '
                        'the sentence constrains the shape, not whose HPI-O it is'),
    'HL7au:00044.3.3': (None, 'shipped caller-asserted (M33): `ValidationOptions.auNASHTransport`, datatype-wide on EI'),
}

# Shipped points whose register row needs a scope note.
SHIPPED_NOTES = {
    # P4-20 / P4-24 / P4-26 / P4-31 (owner rulings G6, G9): see
    # permanent-limitations-register (00060.4 row) and ADR-021.
    'HL7au:00060.4': 'explicit prohibitions on C fields (`prohibitedWhen` / '
                     '`additionalProhibitions`, `.conditionalFieldProhibited`): '
                     'AIS-10, AIG-14, AIL-12, AIP-12 (all six, P4-23); '
                     'PRA-1, PRA-12, STF-1 (v2.4 on); BPX-5/6/8/9/10, BTX-2/3/5/6/7, '
                     'SPM-13, TQ2-7 (v2.5.1 on); PYE-3/4/5/6 (v2.6 on); PRT-6/7 '
                     '(v2.8.2); OBX-2 and OBX-5 other than the HL7 null when '
                     'OBX-11 = O (v2.4 7.4.2.11; P4-24, base since P4-26); and, '
                     'route C (P4-31, ADR-021), v2.4 OBX-2 valued while OBX-11 = X, '
                     'the one C field whose stored condition is the full predicate, '
                     'reported when that condition is definitely false. The other 51 '
                     'candidate C fields in the v2.4 ORM/ORU/REF segments carry no '
                     'derivable prohibition (owner ruling G9): 31 trigger-only, 8 with '
                     'no predicate the text settles as a prohibition (RQ1-2/3/4/5 read '
                     'inclusively, RXE-10/18/19 bare, PTH-6 undefined event), 12 whose '
                     'predicate the message does not carry',
}

SHIPPED = {
    'HL7au:00060.4',
    'HL7au:000003', 'HL7au:000004.1', 'HL7au:000005', 'HL7au:000006',
    'HL7au:000007', 'HL7au:000008', 'HL7au:000008.1',
    'HL7au:000040.1', 'HL7au:000040.2', 'HL7au:000040.3', 'HL7au:000040.4',
    'HL7au:000041', 'HL7au:000042',
    'HL7au:00044.1.2', 'HL7au:00044.1.3',
    'HL7au:00044.4.1', 'HL7au:00044.4.2', 'HL7au:00044.4.4',
    'HL7au:00044.4.5', 'HL7au:00044.4.6', 'HL7au:00044.4.8',
    'HL7au:00044.5.1', 'HL7au:00044.5.2', 'HL7au:00044.5.3',
    'HL7au:00044.5.4', 'HL7au:00044.5.5',
    'HL7au:00044.6.1', 'HL7au:00044.6.2', 'HL7au:00044.6.3',
    'HL7au:00044.6.4', 'HL7au:00044.6.5',
    # M6-A stage 1 — MSH envelope literals (2026-09-04).
    'HL7au:000024.1', 'HL7au:000024.3', 'HL7au:000024.4', 'HL7au:000024.5',
    'HL7au:00047.1', 'HL7au:00047.2',
    'HL7au:00048.3.1', 'HL7au:00049.2', 'HL7au:00049.3',
    # M6-A stage 2 — XCN required components (2026-09-04).
    'HL7au:00044.7.2', 'HL7au:00044.7.5',
    # M6-A stage 3 — prohibitions via SegmentCardinalityRule.maxCount.
    'HL7au:000023',
    # P3-4 — MSG-1 restated: v2.4 has no base MSG grammar (2026-09-30).
    'HL7au:00049.1',
    # M6-B-1 — exactly-one PRD rules (maxCount + the anyRepeat atom;
    # PRD-1 repeats) and the repaired 00104.7.0 (PRD-7 required on the
    # IR PRD via FieldOverride.condition).
    'HL7au:00104.1.1', 'HL7au:00104.2.1', 'HL7au:00104.7.0',
    # M6-B-2 — Z-segment prohibition via the Z* counted-segment prefix.
    'HL7au:000023.1',
    # M6-B-4 — code-table membership via the HL7CodeTables seed.
    'HL7au:000032', 'HL7au:00104.7.3.1',
    # M6-B-5 — XCN table membership via the composite value-set track.
    'HL7au:00044.7.3', 'HL7au:00044.7.4',
    # M6-B-6 — the L1/L2 legs via the MSH-12.3.1 profile discriminator
    # (the ADRM declares the adhered profile in MSH-12.3; the earlier
    # "MSH-21" note was a misidentification).
    'HL7au:000021', 'HL7au:000008.3.1',
    # M6-B-8 — OBX-2 must match the OBX-3.1 display format (p. 247 table).
    'HL7au:000008.1.3',
    # M6-B-7 — ED/RP required components, reachable since the composite
    # dispatch resolves OBX-5's effective datatype from OBX-2.
    'HL7au:00044.10.1.1', 'HL7au:00044.10.1.2', 'HL7au:00044.10.1.3',
    'HL7au:00044.10.1.4', 'HL7au:00044.11.1.1', 'HL7au:00044.11.1.2',
    'HL7au:00044.11.1.3', 'HL7au:00044.11.1.4',
    # M6-B-9 — OBR-3 filler-order-number uniqueness (message-wide
    # FieldUniquenessRule; p. 442), on both the ORU and REF legs.
    'HL7au:000028', 'HL7au:000028.2',
    # M8-C — enforced by BatchValidator over BatchParser output: a
    # batch group carrying a REF alongside any other message fires.
    'HL7au:000022.3',
}

# Enforced in part: either only over part of the message-type scope the
# point names, or only one half of a two-part rule (presence but not
# code-table membership).
PARTIAL = {
    # P8b-4 and P8b-4a (ADR-019 decisions 7 and 8): the segment half through the ADRM-2021
    # structures.
    'HL7au:00060.1': 'P8b-4, P8b-4a: with the structure check on (`messageStructureSeverity`, '
                     'on in the default and strict presets since P8b-18), a v2.4 ORU^R01, '
                     'ORM^O01, REF^I12, RRI^I12 or OSR^Q06 is also matched against the ADRM-2021 '
                     'structure (pp 205, 279, 324, 325, 281; '
                     '`Resources/structures/profiles/au-adrm-2021/`) and a segment it requires and '
                     'the message lacks is reported (RRI^I12: MSA); removed base segments are not '
                     'findings (decision 7), and a base structure finding is dropped where the ADRM '
                     'structure accepts the message at that point (a segment it places there, or '
                     'one it makes optional); an exact-matched base is matched again past a dropped '
                     'finding, so later base findings are kept. The field and component half is '
                     'the Validator core. Closed: the RRI^I12 MSA (P8b-4a); the prose-only PV1 '
                     'mandate on ORU^R01 (pp 17, 205; owner ruling 2026-10-06: the print governs); '
                     'the narrowed maxima (REF^I12 `[IN1]`, PV1 and PV2, p 324) are reported at '
                     'information since v3.15.0 (S6-3: each occurrence beyond them draws one '
                     '`.info` `profileMaximumExceeded(localeRule: "HL7au:00060.1")`, not a '
                     'finding; every other profile `unexpected` finding is dropped, and the final '
                     'review traced ORU_R01 and REF_I12 and found no ordering that differs from the '
                     'base). Not enforced, three leftovers scheduled for P12 S1: the Appendix 8 '
                     'simplified REF structure (pp 483 to 485, declared in MSH-12; owner ruling '
                     'G-AU3 2026-10-07: a profile structure selected by the declared profile), the '
                     'ORR^O02 print (pp 280 to 281, unbalanced bracket; owner ruling G-AU2 '
                     '2026-10-07: a cited erratum taking the base v2.4 reading, PID optional) and '
                     'the order detail of the order status response (p 281 prints only OBR; the '
                     'base choice is kept, so RQD, RQ1, RXO, ODS or ODT in its place and an OBX '
                     'after any of them go unflagged); '
                     'permanent-limitations register section E, close-out summary and the P8b-4 '
                     'and P8b-4a addenda',
    'HL7au:000043.1': 'M32: the format\'s OID and "ISO" halves ship caller-asserted on MSH-4 '
                      '(`auNASHTransport`); the "registered organisation name in HI service" half '
                      'needs the HPOS/HI directory and stays out',
    'HL7au:000024.2': 'enforced on Orders/Results as part of the MSH-2 '
                      'literal pin; unenforced on Referrals, where .3/.4/.5 '
                      'do not apply and pinning the whole literal would '
                      'over-fire — needs character-position addressing (M6-B)',
    'HL7au:000020': 'Z-prefixed trigger events prohibited on Orders/Results '
                    'and (since M6-B-6) on Referrals(L2) via the MSH-12.3.1 '
                    'profile gate; the message-CODE leg stays unenforced — '
                    'a wholly-Z message code never satisfies any '
                    'message-type gate, so that half is undecidable inside '
                    'this rule shape',
    'HL7au:00044.10.1.5': 'ED subtype => type enforced for spec-stated pairs '
                          '(ADRM §3.20.5 + example annotations); arbitrary IANA '
                          'subtypes skip, fail-safe',
    'HL7au:00044.10.1.6': 'ED subtype => type enforced for the 0291 subtypes '
                          'whose 0191 main type §3.20.5 states; unstated ones skip',
    'HL7au:00044.11.1.5': 'RP subtype => type, as 00044.10.1.5',
    'HL7au:00044.11.1.6': 'RP subtype => type, as 00044.10.1.6',
    'HL7au:00104.7.1.4': 'authority => qualifier pairs enforced for the closed AU '
                         'authorities (AUSHICPR => UPIN, AUSHIC => NPIO/NOI); vendor '
                         'authorities are open-ended examples and skip',
    'HL7au:000032.2': 'OBR-24 presence + table 0074 membership enforced on '
                      'Referrals; the "appropriate for the content in the '
                      'OBR/OBX group" half is receiver-judgement over '
                      'content and is not machine-checkable',
    # M6-B-9 additions.
    'HL7au:000008.3.2': 'the STRUCTURAL half is enforced: an RTF display '
                        'OBX in an OBR group without an HTML/PDF/TXT '
                        'sibling fires (relational cardinality via '
                        'activationPredicate); the "same content" '
                        'equality half needs cross-format rendering '
                        'comparison and is not machine-checkable',
    'HL7au:000034.1': 'enforced for the public systems the ADRM names '
                      '(LN, SCT, UCUM): a named public system relegated '
                      'to the CE/CWE alternate triplet behind a '
                      'non-public primary fires; systems the ADRM does '
                      'not name skip fail-safe',
    'HL7au:000034.2': 'same machinery on OBX-5 coded values; same '
                      'named-public-systems scope as 000034.1',
    # P3 fix wave — the BASE rows these replace cited CX/EI/XCN base
    # requirements that the v2.4 grammar (the AU base) does not carry.
    'HL7au:00044.1.1': 'the presence half is enforced on Orders/Results/'
                       'Referrals (CX-1 valued; yields to the base CX.1 '
                       'check from v2.5.1); "valid according to the '
                       'identifier scheme" needs identifier-scheme '
                       'recognition and is not checked',
    'HL7au:00044.3.1': 'the presence half is enforced on Orders/Results/'
                       'Referrals (EI-1 valued); the uniqueness half is '
                       'cross-message and out of scope',
    'HL7au:00044.7.1': 'the presence half is enforced on Orders/Results/'
                       'Referrals (XCN-1 valued); "valid according to the '
                       'identifier scheme" needs identifier-scheme '
                       'recognition and is not checked',
    'HL7au:00044.8.1': 'the offset-PRESENCE half is enforced: a TS with '
                       'hour-or-greater precision and no +/-ZZZZ suffix '
                       'fires on Orders/Results/Referrals; the "offset '
                       'is CORRECT for the stated local time" half '
                       'needs a timezone database and is out of scope',
    # M8-C addition.
    'HL7au:000022.1': 'the individual-acknowledgement half is enforced: '
                      'BHS carries no acknowledgement field, so the mode '
                      'lives in each contained message\'s MSH-15/16, and '
                      'BatchValidator runs the per-message AU rules '
                      '(00047.1/.2, MSH-15/16 = AL) on every batched '
                      'message; the "no information from the file '
                      'header/footer or batch segments must be used" '
                      'half is receiver processing behaviour',
}

# Enforced by the base spec model before the overlay runs, so the overlay
# deliberately does not restate them.
BASE = {
    'HL7au:000008.1.4': 'OBX-3.3 = AUSPDI is the discriminator the '
                        'HL7au:000008.1 overlay gates on, not an assertion',
    'HL7au:000008.1.2': 'definitional — states how a display segment is '
                        'identified; implemented as the overlay gate',
    'HL7au:00046.3': 'R-optionality enforcement is the Validator core',
    'HL7au:00060.3': 'conditional predicates are the same-segment DSL',
    'HL7au:00046.1.1': 'escaping is `Serializer` behaviour, already correct',
    'HL7au:00046.1.2': 'escaping is `Serializer` behaviour, already correct',
    'HL7au:00046.1.3': 'escaping is `Serializer` behaviour, already correct',
    'HL7au:00046.1.4': 'escaping is `Serializer` behaviour, already correct',
    'HL7au:00046.1.5': 'escaping is `Serializer` behaviour, already correct',
}

# Registered as permanent / documented limitations.
# 00050.1.5 (M6-A-3): scoped "Senders (Pathology only)", and ADRM-2021
# defines no message-decidable pathology discriminator — table 0074
# mixes pathology and imaging disciplines and the spec names no
# pathology subset. A bare ORU gate would over-fire on spec-compliant
# imaging results (req #4); an invented OBR-24 subset would not be
# defensible against spec text (req #2).
# 00104.7.2.1 (M6-B-8 correction): table 0363 is USER-defined and the
# ADRM's own PRD-7 matches table (p. 334) uses vendor authorities
# outside it (Medical-Objects, Argus) — a closed-set membership check
# misfires on the spec's own examples (req #4). Withdrawn from the
# profile; registered.
# M6-B-9 registrations (each cited in permanent-limitations-register §D):
# 00100.1 — REF-4 SNOMED CT hierarchy subsumption needs a terminology
#   server; no closed value set exists in the ADRM.
# 000008.1.5 — signature-format identifiers live in HB 308-2011, an
#   external Standards Australia handbook not reproduced in the ADRM;
#   no closed list to check against (req #2).
# 000034.3 / 00044.6.7 — "the alternate must encode the SAME CONCEPT as
#   the primary" is a terminology-service equivalence judgement, not a
#   structural check.
# 000022.1 / 000022.3 — MOVED OUT at M8-C (2026-09-17): BatchValidator
#   shipped; .3 is SHIPPED, .1 is PARTIAL (see their entries above).
REGISTERED = {'HL7au:000001', 'HL7au:00044.2', 'HL7au:00104.7.2.1',
              'HL7au:00044.4.7', 'HL7au:00044.5.7',
              'HL7au:00100.1', 'HL7au:000008.1.5', 'HL7au:000034.3',
              'HL7au:00044.6.7'}

# Withdrawn by the r2 revision — must never be cited.
WITHDRAWN = {'HL7au:00044.5.6', 'HL7au:00044.6.6', 'HL7au:00048.3.2'}

# A: expressible with the DSL as it stands today; ship next.
# Emptied by M6-A stage 3 (2026-09-15): 000023 shipped, 000021 shipped
# PARTIAL (Results leg only), 00050.1.5 moved to REGISTERED — its
# "(Pathology only)" actor scoping has no message-decidable
# discriminator, so no gate exists that reaches all pathology and no
# non-pathology traffic.
CANDIDATE = {}

# B: faithful expression needs a model extension (the working notes req #3).
# Emptied by M6-B-9 (2026-09-16): the final twelve either shipped
# (000028/.2 via FieldUniquenessRule; 000008.3.2's structural half via
# SegmentCardinalityRule.activationPredicate; 000034.1/.2 via the
# public-in-alternate correspondence map; 00044.8.1's offset-presence
# half via CompositeOverride.timezoneRequiredCitation) or were
# registered with citations (00100.1, 000008.1.5, 000034.3, 00044.6.7,
# 000022.1, 000022.3 — see the REGISTERED block above and
# permanent-limitations-register.md §D).
EXTEND = {}

# C: out of scope by nature. Matched most-specific prefix first.
OUT_OF_SCOPE = [
    ('HL7au:000008.2.3', 'rendered-payload content (XHTML/CSS)'),
    ('HL7au:000008.2.4', 'rendered-payload content (PDF/RTF/FT)'),
    ('HL7au:000008.2',   'semantic agreement between rendered and atomic data'),
    ('HL7au:000001',     'transport addressing / SMD directory'),
    ('HL7au:00043.2',    'anti-spoofing against the SMD certificate; the ADRM marks it '
                         '"applies only to SMD Agent implementers ... before handing off '
                         'a the message to the receiving system"'),
    ('HL7au:000043',     'transport addressing / NASH PKI'),
    ('HL7au:00043',      'transport addressing / SMD directory'),
    ('HL7au:00044.2.1',  'the organisation name "as registered in the Medicare Australia '
                         'HPOS/HI service" — needs the HI directory'),
    ('HL7au:00044.2.4',  'vendor X.509 certificate + provider-directory agreement'),
    ('HL7au:00044.2',    'transport addressing / NASH PKI'),
    ('HL7au:00044.3.2',  'EI twin of 00044.2.1 — needs the HI directory'),
    ('HL7au:00044.3.4',  'the ADRM\'s SECOND row with this number: vendor X.509 certificate + '
                         'provider-directory agreement (the first, the EI Universal ID rule, '
                         'ships caller-asserted — M33)'),
    ('HL7au:00044.11.1.5.', 'URL construction from RP components (payload)'),
    ('HL7au:00045',      'secure-messaging agent behaviour'),
    ('HL7au:00110',      'provider-directory agreement'),
    ('HL7au:000019',     'transport size limit'),
    ('HL7au:000025',     'cross-message identifier uniqueness'),
    ('HL7au:000026',     'cross-message identifier uniqueness'),
    ('HL7au:000027',     'cross-message identifier uniqueness'),
    ('HL7au:000029',     'retransmission provenance (cross-message)'),
    ('HL7au:000030',     'cross-message identifier uniqueness'),
    ('HL7au:000031',     'display provenance (receiver rendering)'),
    ('HL7au:000033',     'advisory ("should"), terminology content'),
    ('HL7au:00044.0.1',  'user-defined datatypes are not detectable on the wire'),
    ('HL7au:00044.7.6',  'advisory ("should")'),
    ('HL7au:00048',      'byte-level character-encoding check'),
    ('HL7au:00050',      'APUTS terminology content (external code system)'),
    ('HL7au:00060',      'sender capability statement, not a message property'),
    ('HL7au:00101',      'encapsulated-attachment payload'),
    ('HL7au:00102',      'referral-summary content (templates, atomic data)'),
    ('HL7au:00103',      'referral-summary rendered content'),
    ('HL7au:00104.7.1',  'requires identifier-scheme recognition (HPI-I)'),
]

# Curated row repairs for PDF layout quirks the parser cannot recover.
# 00104.7.0 (r3): the identifier is printed BELOW the row's first text
# line (p. 472), so the parse attached only the trailing fragment and
# an earlier triage dismissed it as a grouper fragment. Verified against
# the source 2026-09-15: it is a real Senders/Referrals point.
ROW_REPAIRS = {
    'HL7au:00104.7.0': {
        'appl': 'Senders',
        'mtype': 'Referrals',
        'text': 'PRD-7 must have at least 1 repeat (for providers '
                'receiving electronic communication specified by IR - '
                'Intended Recipient in PRD-1).',
    },
}


def classify(row):
    i = row['id']
    if i in WITHDRAWN:
        return ('WITHDRAWN', 'removed by revision r2 — must not be cited')
    if row['grouper'] or not row['text']:
        return ('GROUPER', 'heading / grouper — not a conformance point'
                if row['grouper'] else 'empty row')
    if i in PARTIAL:
        return ('PARTIAL', PARTIAL[i])
    if i in CALLER_ASSERTED:
        marker, note = CALLER_ASSERTED[i]
        if marker is None or marker in row['text']:
            return ('SHIPPED', note)
    if i in SHIPPED:
        return ('SHIPPED', SHIPPED_NOTES.get(i, ''))
    if i in BASE:
        return ('BASE', BASE[i])
    if i in REGISTERED:
        return ('REGISTERED', 'known limitation, registered with citation')
    if i in CANDIDATE:
        return ('CANDIDATE', CANDIDATE[i])
    if i in EXTEND:
        return ('EXTEND', EXTEND[i])
    if row['appl'].startswith('Receiver'):
        return ('RECEIVER', 'receiver behaviour — observed at runtime')
    for prefix, reason in OUT_OF_SCOPE:
        if i.startswith(prefix):
            return ('OUT', reason)
    return ('UNTRIAGED', '')


ORDER = ['CANDIDATE', 'EXTEND', 'SHIPPED', 'PARTIAL', 'BASE', 'REGISTERED',
         'WITHDRAWN', 'RECEIVER', 'OUT', 'GROUPER', 'UNTRIAGED']


def main():
    rows = parse_appendix5(sys.argv[1] if len(sys.argv) > 1 else '/tmp/adrm2021.txt')
    for r in rows:
        if r['id'] in ROW_REPAIRS:
            r.update(ROW_REPAIRS[r['id']])
        r['verdict'], r['note'] = classify(r)
    # self-check: every curated id must exist in the extracted table, and
    # nothing may fall through unclassified.
    seen = {r['id'] for r in rows}
    stray = sorted((SHIPPED | set(PARTIAL) | set(BASE) | REGISTERED
                    | WITHDRAWN | set(CANDIDATE) | set(EXTEND)) - seen)
    assert not stray, f'curated ids absent from Appendix 5: {stray}'
    untriaged = sorted(r['id'] for r in rows if r['verdict'] == 'UNTRIAGED')
    assert not untriaged, f'untriaged conformance points: {untriaged}'
    if '--json' in sys.argv:
        json.dump(rows, sys.stdout, indent=1)
        return
    counts = {v: sum(1 for r in rows if r['verdict'] == v) for v in ORDER}
    print('<!-- GENERATED by scripts/extract-adrm-conformance.py — do not hand-edit -->')
    print('# ADRM-2021 conformance-point register (M6)\n')
    print('Every HL7au conformance point in Appendix 5 of '
          '`HL7AUSD-STD-OO-ADRM-2021.1`, classified against what '
          '`HL7Locale.auLocalisation` ships. Regenerate with:\n')
    print('```bash\npdftotext -layout "docs/standards/HL7_v24_PDF/'
          'HL7AUSD-STD-OO-ADRM-2021.1 - *.pdf" /tmp/adrm2021.txt\n'
          'python3 scripts/extract-adrm-conformance.py /tmp/adrm2021.txt \\\n'
          '    > docs/design/m6-adrm-2021-conformance-register.md\n```\n')
    print(f'**{len(rows)} rows / '
          f'{sum(1 for r in rows if r["verdict"] != "GROUPER")} conformance points.**\n')
    print('Classification last reconciled with the shipped state on 2026-10-07 '
          '(P12 S0-1); the counts below are computed from the rows.\n')
    print('| Verdict | Count | Meaning |')
    print('|---|---:|---|')
    meanings = {
        'CANDIDATE': 'expressible with the DSL today — the shippable gap',
        'EXTEND': 'needs a model extension to express faithfully (req #3)',
        'SHIPPED': 'enforced by the `.auLocalisation` overlay today',
        'PARTIAL': 'partly enforced — see each row\'s note for what is not',
        'BASE': 'already enforced by the base model; overlay deliberately silent',
        'REGISTERED': 'known limitation, already registered',
        'WITHDRAWN': 'removed by revision r2',
        'RECEIVER': 'receiver behaviour — not decidable from a message',
        'OUT': 'out of scope by nature (transport, payload, cross-message)',
        'GROUPER': 'heading row, not a conformance point',
        'UNTRIAGED': 'not yet classified — must be zero',
    }
    for v in ORDER:
        print(f'| {v} | {counts[v]} | {meanings[v]} |')
    for v in ORDER:
        sel = [r for r in rows if r['verdict'] == v]
        if not sel:
            continue
        print(f'\n## {v} ({len(sel)})\n')
        print('| HL7au | Rev | Applies to | Message types | Conformance point | Note |')
        print('|---|---|---|---|---|---|')
        for r in sel:
            t = r['text'].replace('|', '\\|')
            t = t if len(t) <= 220 else t[:217] + '...'
            print(f'| `{r["id"]}` | {r["rev"]} | {r["appl"][:24]} | '
                  f'{r["mtype"][:34]} | {t} | {r["note"]} |')


if __name__ == '__main__':
    main()
