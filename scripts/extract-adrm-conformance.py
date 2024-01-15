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
SHIPPED = {
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
}

# Enforced in part: either only over part of the message-type scope the
# point names, or only one half of a two-part rule (presence but not
# code-table membership).
PARTIAL = {
    'HL7au:000024.2': 'enforced on Orders/Results as part of the MSH-2 '
                      'literal pin; unenforced on Referrals, where .3/.4/.5 '
                      'do not apply and pinning the whole literal would '
                      'over-fire — needs character-position addressing (M6-B)',
    'HL7au:00044.7.3': 'XCN-10 presence enforced; HL7 Table 0200 membership '
                       'is not — HL7 code tables are not modelled (M6-O6)',
    'HL7au:00044.7.4': 'XCN-13 presence enforced; HL7 Table 0203 membership '
                       'is not — HL7 code tables are not modelled (M6-O6)',
    'HL7au:000021': 'OBX-2 = TX prohibition enforced on Results (ORU); the '
                    'Referrals(L2) leg is not — L2 is identified by an '
                    'MSH-21 profile ID the model cannot address, and a bare '
                    'REF gate would over-fire on Level 1 and unprofiled '
                    'referrals',
}

# Enforced by the base spec model before the overlay runs, so the overlay
# deliberately does not restate them.
BASE = {
    'HL7au:00044.1.1': 'CX-1 is already `CX.requiredComponents`',
    'HL7au:000008.1.4': 'OBX-3.3 = AUSPDI is the discriminator the '
                        'HL7au:000008.1 overlay gates on, not an assertion',
    'HL7au:000008.1.2': 'definitional — states how a display segment is '
                        'identified; implemented as the overlay gate',
    'HL7au:00046.3': 'R-optionality enforcement is the Validator core',
    'HL7au:00060.1': 'R-optionality enforcement is the Validator core',
    'HL7au:00060.3': 'conditional predicates are the same-segment DSL',
    'HL7au:00060.4': 'conditional predicates are the same-segment DSL',
    'HL7au:00046.1.1': 'escaping is `Serializer` behaviour, already correct',
    'HL7au:00046.1.2': 'escaping is `Serializer` behaviour, already correct',
    'HL7au:00046.1.3': 'escaping is `Serializer` behaviour, already correct',
    'HL7au:00046.1.4': 'escaping is `Serializer` behaviour, already correct',
    'HL7au:00046.1.5': 'escaping is `Serializer` behaviour, already correct',
    'HL7au:00049.1': 'MSG-1 is already `MSG.requiredComponents`',
    'HL7au:00044.3.1': 'EI-1 is already `EI.requiredComponents`; the '
                       'uniqueness half is cross-message and out of scope',
    'HL7au:00044.7.1': 'XCN-1 is already `XCN.requiredComponents`',
}

# Registered as permanent / documented limitations.
# 00050.1.5 (M6-A-3): scoped "Senders (Pathology only)", and ADRM-2021
# defines no message-decidable pathology discriminator — table 0074
# mixes pathology and imaging disciplines and the spec names no
# pathology subset. A bare ORU gate would over-fire on spec-compliant
# imaging results (req #4); an invented OBR-24 subset would not be
# defensible against spec text (req #2).
REGISTERED = {'HL7au:000001', 'HL7au:00044.2',
              'HL7au:00044.4.3', 'HL7au:00044.4.7', 'HL7au:00044.5.7',
              'HL7au:00050.1.5'}

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
EXTEND = {
    'HL7au:000020':      'message-code / trigger prefix match (`Z*`)',
    'HL7au:000023.1':    'segment-ID prefix match (`Z*`)',
    'HL7au:000028':      'within-message uniqueness of a field across repeats',
    'HL7au:000028.2':    'within-message uniqueness of a field across groups',
    'HL7au:000034.1':    'primary-before-local coding-system ordering, generalised '
                         'from the shipped LOINC rule (HL7au:00044.4.4)',
    'HL7au:000034.2':    'primary-before-local coding-system ordering',
    'HL7au:000034.3':    'primary-before-local coding-system ordering',
    'HL7au:000008.1.3':  'OBX-2 ⇔ OBX-3.1 value-correspondence map',
    'HL7au:000008.1.5':  'intra-group segment ordering',
    'HL7au:000008.3.1':  'discriminated group-content cardinality',
    'HL7au:000008.3.2':  'discriminated group-content cardinality (RTF ⇒ sibling)',
    'HL7au:00044.8.1':   'TS datatype-level validation (timezone offset present)',
    'HL7au:00044.10.1.5': 'ED subtype ⇔ type MIME correspondence map',
    'HL7au:00044.10.1.6': 'ED subtype ⇔ type HL7 table 0291/0191 correspondence map',
    'HL7au:00044.11.1.5': 'RP subtype ⇔ type MIME correspondence map',
    'HL7au:00044.11.1.6': 'RP subtype ⇔ type HL7 table 0291/0191 correspondence map',
    'HL7au:00044.6.7':   'same-concept assertion across coding systems — the CWE '
                         'twin of the registered HL7au:00044.4.7 / .5.7',
    'HL7au:00100.1':     'group ordering within a message',
    'HL7au:00104.1.1':   'discriminated group cardinality (exactly one PRD-1=AP)',
    'HL7au:00104.2.1':   'discriminated group cardinality (exactly one PRD-1=IR)',
    'HL7au:00104.7.1.4': 'PRD-7 component-triple correspondence table',
    'HL7au:000022.3':    'batch-scope cardinality (Validator is message-scoped)',
    'HL7au:000022.1':    'batch-scope acknowledgement mode',
    # M6-O7: ED and RP never appear as a field's declared dataType on any
    # supported version — they reach the wire only through OBX-5, whose
    # type is chosen at runtime by OBX-2. The composite track keys on the
    # static grammar dataType, so these can never fire as written.
    'HL7au:00044.10.1.1': 'OBX-2-driven dynamic datatype resolution (ED)',
    'HL7au:00044.10.1.2': 'OBX-2-driven dynamic datatype resolution (ED)',
    'HL7au:00044.10.1.3': 'OBX-2-driven dynamic datatype resolution (ED)',
    'HL7au:00044.10.1.4': 'OBX-2-driven dynamic datatype resolution (ED)',
    'HL7au:00044.11.1.1': 'OBX-2-driven dynamic datatype resolution (RP)',
    'HL7au:00044.11.1.2': 'OBX-2-driven dynamic datatype resolution (RP)',
    'HL7au:00044.11.1.3': 'OBX-2-driven dynamic datatype resolution (RP)',
    'HL7au:00044.11.1.4': 'OBX-2-driven dynamic datatype resolution (RP)',
    # M6-O6: HL7 code tables are not modelled — the schemas drop the
    # spec's TBL# column and there is no table registry.
    'HL7au:000032':      'HL7 Table 0074 membership; needs a code-table registry',
    'HL7au:000032.2':    'HL7 Table 0074 membership; needs a code-table registry',
    'HL7au:00104.7.2.1': 'User-defined Table 0363 membership; needs a code-table registry',
    'HL7au:00104.7.3.1': 'HL7 Table 0203 membership; needs a code-table registry',
}

# C: out of scope by nature. Matched most-specific prefix first.
OUT_OF_SCOPE = [
    ('HL7au:000008.2.3', 'rendered-payload content (XHTML/CSS)'),
    ('HL7au:000008.2.4', 'rendered-payload content (PDF/RTF/FT)'),
    ('HL7au:000008.2',   'semantic agreement between rendered and atomic data'),
    ('HL7au:000001',     'transport addressing / SMD directory'),
    ('HL7au:000043',     'transport addressing / NASH PKI'),
    ('HL7au:00043',      'transport addressing / SMD directory'),
    ('HL7au:00044.2',    'transport addressing / NASH PKI'),
    ('HL7au:00044.3.2',  'transport addressing / NASH PKI'),
    ('HL7au:00044.3.3',  'transport addressing / NASH PKI'),
    ('HL7au:00044.3.4',  'transport addressing / NASH PKI'),
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
    ('HL7au:00044.7.1',  'identifier-scheme validity, not presence'),
    ('HL7au:00044.7.6',  'advisory ("should")'),
    ('HL7au:00048',      'byte-level character-encoding check'),
    ('HL7au:00050',      'APUTS terminology content (external code system)'),
    ('HL7au:00060',      'sender capability statement, not a message property'),
    ('HL7au:00101',      'encapsulated-attachment payload'),
    ('HL7au:00102',      'referral-summary content (templates, atomic data)'),
    ('HL7au:00103',      'referral-summary rendered content'),
    ('HL7au:00104.7.1',  'requires identifier-scheme recognition (HPI-I)'),
    ('HL7au:00104.7.0',  'grouper text fragment'),
]


def classify(row):
    i = row['id']
    if i in WITHDRAWN:
        return ('WITHDRAWN', 'removed by revision r2 — must not be cited')
    if row['grouper'] or not row['text']:
        return ('GROUPER', 'heading / grouper — not a conformance point'
                if row['grouper'] else 'empty row')
    if i in PARTIAL:
        return ('PARTIAL', PARTIAL[i])
    if i in SHIPPED:
        return ('SHIPPED', '')
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
