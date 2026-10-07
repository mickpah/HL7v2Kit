#!/usr/bin/env python3
# M7-P1 pass 2: candidates = normative body sentences NOT inside a
# "Conformance point" neighbourhood AND not textually matching any
# Appendix 5 point (the appendix quotes body wording).
import os, re, json, subprocess, sys
from pathlib import Path

WINDOW = 10
SOURCE = sys.argv[1] if len(sys.argv) > 1 else '/tmp/adrm2021.txt'
if not os.path.isfile(SOURCE):
    sys.exit(f'setup failure: {SOURCE} is absent; render the ADRM-2021 PDF under '
             'docs/standards with pdftotext -layout first (local guard only)')
text = open(SOURCE).read()
pages = text.split('\f')
BODY_START, APPENDIX_START = 3, 372  # 0-based, from pass 1

rows = json.loads(subprocess.run(
    ['python3', 'scripts/extract-adrm-conformance.py', os.path.abspath(SOURCE), '--json'],
    capture_output=True, text=True, cwd=Path(__file__).resolve().parents[1]).stdout)

def tokens(s):
    return set(re.findall(r'[a-z0-9]+', s.lower())) - {
        'the', 'a', 'an', 'of', 'to', 'in', 'is', 'be', 'and', 'or',
        'for', 'this', 'that', 'must', 'shall', 'not', 'with', 'as', 'on'}

point_toksets = [(r['id'], tokens(r['text'])) for r in rows if r.get('text')]

NORM = re.compile(r'\b(must|shall|is required to|are required to|not permitted|'
                  r'is mandatory|are mandatory)\b', re.I)
SKIP = re.compile(r'^\s*[A-Z0-9]{2,3}\|')

candidates, near_cp, appendix_dup = [], 0, 0
for i in range(BODY_START, APPENDIX_START):
    lines = pages[i].split('\n')
    for j, line in enumerate(lines):
        if not NORM.search(line) or SKIP.match(line):
            continue
        lo, hi = max(0, j - WINDOW), min(len(lines), j + WINDOW + 1)
        hood = '\n'.join(lines[lo:hi])
        if 'Conformance point' in hood or 'HL7au:' in hood:
            near_cp += 1
            continue
        ctx = ' '.join(l.strip() for l in lines[j:min(j + 3, len(lines))])
        ctx = re.sub(r'\s+', ' ', ctx)[:260]
        ctoks = tokens(ctx)
        if not ctoks:
            continue
        best_id, best = None, 0.0
        for pid, ptoks in point_toksets:
            if not ptoks:
                continue
            ov = len(ctoks & ptoks) / min(len(ctoks), len(ptoks))
            if ov > best:
                best, best_id = ov, pid
        if best >= 0.6:
            appendix_dup += 1
            continue
        candidates.append((i + 1, round(best, 2), best_id, ctx))

print(f'near a Conformance point box: {near_cp}')
print(f'textual duplicate of an Appendix 5 point: {appendix_dup}')
print(f'remaining prose-only candidates: {len(candidates)}')
with open('/tmp/prose-candidates2.txt', 'w') as f:
    for pg, ov, pid, ctx in candidates:
        f.write(f'p{pg} [{ov} {pid}]: {ctx}\n')
print('written /tmp/prose-candidates2.txt')
