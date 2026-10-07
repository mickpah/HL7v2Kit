#!/usr/bin/env python3
"""Guard: no PHI-shaped identifiers and no licensed standards content in the repository.

    python3 scripts/scan-for-phi.py               scan the working tree (Tests/Fixtures, tracked paths)
    python3 scripts/scan-for-phi.py --history     scan every blob of every commit reachable from any ref
    python3 scripts/scan-for-phi.py --self-test   run the synthetic-string checks

`scripts/scan-fixtures-for-phi.sh` is the CI entry point and passes its arguments here.

PHI patterns (Australian healthcare identifiers):
  - ihi / hpi-i / hpi-o   16 digits, prefix 800360 / 800361 / 800362 (any other 8003 prefix,
                          such as the 80031 the scanner checked before P13, reports as nash-8003)
  - medicare              10 or 11 digits, first digit 2-6, valid Medicare check digit, issue
                          number 1-9 (also the printed spaced form 2123 45670 1)
  - dva                   DVA file number: state N/V/Q/S/W/T, a 1-3 letter war code, digits to
                          an 8-character core, optional segment-link letter (NX123456, VSM12345A)
  - au-mobile             04xxxxxxxx, 04xx xxx xxx, +614xxxxxxxx

Licensed-content signatures:
  - pdf                   a blob starting `%PDF-`
  - pdftotext             a text blob with three or more form feeds (pdftotext page breaks)
  - xsd                   `<xsd:schema` or `<xs:schema`
  - v2xml                 the HL7 v2.xml bundle namespaces `urn:hl7-org:v2xml` and
                          `urn:com.sun:encoder-hl7-1.0`, or its `v2.xml Message Definitions` banner
  - licensed-path         any path ending .pdf, .xsd or .xml, or under docs/standards/ or
                          docs/XML-schemas/ (the owner's local, gitignored standards folders)

Scope: PHI patterns and the text signatures apply to paths under Tests/Fixtures/ and to every
*.hl7 and *.txt path (plus any licensed path); `%PDF-` and the form-feed check apply to every
blob. History mode reads each blob once (keyed by hash) through one `git cat-file --batch`.

Allowed values are listed in ALLOWED with the reason; see
docs/design/private/public-release-history-check.md. Exits 1 on any hit outside ALLOWED.
"""
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURES = "Tests/Fixtures/"

# (pattern name, exact matched value): documented synthetic values. Empty: no value in the
# working tree or the history needs an exception (the AU fixtures' zero-filled 16-digit OID
# bodies such as 0000000000001001 match no pattern, so need none).
ALLOWED = set()

NASH = re.compile(rb"(?<![0-9])8003[0-9]{12}(?![0-9])")
NASH_KIND = {b"800360": "ihi", b"800361": "hpi-i", b"800362": "hpi-o"}
MEDICARE = re.compile(rb"(?<![0-9])[2-6][0-9]{9,10}(?![0-9])")
MEDICARE_SPACED = re.compile(rb"(?<![0-9])([2-6][0-9]{3}) ([0-9]{5}) ([1-9])(?: ([1-9]))?(?![0-9])")
DVA = re.compile(rb"(?<![A-Za-z0-9])([NVQSWT])([A-Z]{1,3})([0-9]{4,6})([A-Z]?)(?![A-Za-z0-9])")
MOBILE = re.compile(rb"(?<![0-9+])(?:04[0-9]{8}|04[0-9]{2} [0-9]{3} [0-9]{3}|\+614[0-9]{8})(?![0-9])")
TEXT_SIGNATURES = [
    ("xsd", re.compile(rb"<xsd?:schema\b|<xs:schema\b")),
    ("v2xml", re.compile(rb"urn:hl7-org:v2xml|urn:com\.sun:encoder-hl7-1\.0|v2\.xml Message Definitions")),
]
LICENSED_PATH = re.compile(r"\.(pdf|xsd|xml)$|^docs/(standards|XML-schemas)/", re.IGNORECASE)


def medicare_valid(digits):
    """Medicare check digit: weights 1,3,7,9,1,3,7,9 on digits 1-8, sum mod 10 is digit 9;
    digit 10 (issue number) is 1-9."""
    d = [c - 48 for c in digits]
    weights = (1, 3, 7, 9, 1, 3, 7, 9)
    if sum(a * b for a, b in zip(d[:8], weights)) % 10 != d[8]:
        return False
    return d[9] != 0 and (len(d) == 10 or d[10] != 0)


def in_phi_scope(path):
    low = path.lower()
    return path.startswith(FIXTURES) or low.endswith((".hl7", ".txt")) or bool(LICENSED_PATH.search(path))


def scan_blob(data, path):
    """Return [(pattern, value)] for one blob's bytes at one path."""
    hits = []
    if LICENSED_PATH.search(path):
        hits.append(("licensed-path", path))
    if data.startswith(b"%PDF-"):
        hits.append(("pdf", "%PDF- header"))
    if b"\0" not in data[:8000] and data.count(b"\f") >= 3:
        hits.append(("pdftotext", f"{data.count(chr(12).encode())} form feeds"))
    if not in_phi_scope(path):
        return hits
    for name, rx in TEXT_SIGNATURES:
        m = rx.search(data)
        if m:
            hits.append((name, m.group(0).decode("latin-1")))
    for m in NASH.finditer(data):
        hits.append((NASH_KIND.get(m.group(0)[:6], "nash-8003"), m.group(0).decode()))
    for m in MEDICARE.finditer(data):
        if medicare_valid(m.group(0)):
            hits.append(("medicare", m.group(0).decode()))
    for m in MEDICARE_SPACED.finditer(data):
        digits = b"".join(g for g in m.groups() if g)
        if medicare_valid(digits):
            hits.append(("medicare", m.group(0).decode()))
    for m in DVA.finditer(data):
        if len(m.group(1) + m.group(2) + m.group(3)) == 8:
            hits.append(("dva", m.group(0).decode()))
    for m in MOBILE.finditer(data):
        hits.append(("au-mobile", m.group(0).decode()))
    return [h for h in hits if h not in ALLOWED]


def git(*args, stdin=None):
    return subprocess.run(["git", *args], cwd=ROOT, input=stdin, capture_output=True, check=True).stdout


def scan_working_tree():
    """Every file under Tests/Fixtures plus every tracked licensed path."""
    hits, count = [], 0
    base = os.path.join(ROOT, FIXTURES)
    for dirpath, _, files in os.walk(base):
        for name in sorted(files):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, ROOT).replace(os.sep, "/")
            with open(full, "rb") as f:
                data = f.read()
            count += 1
            hits += [(rel, p, v) for p, v in scan_blob(data, rel)]
    if os.path.isdir(os.path.join(ROOT, ".git")):
        for rel in git("ls-files", "-z").decode().split("\0"):
            if rel and LICENSED_PATH.search(rel):
                hits.append((rel, "licensed-path", rel))
    return hits, count


def history_paths():
    """{blob: {path: introducing commit}} from every commit's raw diff (merges against each parent)."""
    out = git("log", "--all", "-m", "--raw", "--no-renames", "--no-abbrev", "-z", "--format=C %H")
    blobs, commit, tokens = {}, None, out.split(b"\0")
    i = 0
    while i < len(tokens):
        tok = tokens[i].lstrip(b"\n")
        if tok.startswith(b"C "):
            commit = tok[2:].decode()
        elif tok.startswith(b":"):
            meta, path = tok.split(), tokens[i + 1].decode("utf-8", "surrogateescape")
            i += 1
            # Log order is newest first: the new side is overwritten so the oldest commit that
            # introduced the blob at this path wins; the old side only fills a gap.
            for side, mode, sha in ((0, meta[0], meta[2]), (1, meta[1], meta[3])):
                if set(sha) == {ord("0")} or mode.lstrip(b":") == b"160000":
                    continue
                paths = blobs.setdefault(sha.decode(), {})
                if side:
                    paths[path] = commit
                else:
                    paths.setdefault(path, commit)
        i += 1
    return blobs


def scan_history():
    started = time.time()
    commits = len(git("rev-list", "--all").split())
    blobs = history_paths()
    listed = {}
    for line in git("rev-list", "--all", "--objects").decode("utf-8", "surrogateescape").splitlines():
        sha, _, path = line.partition(" ")
        listed[sha] = path
    types = git("cat-file", "--batch-check=%(objectname) %(objecttype)", stdin="\n".join(listed).encode() + b"\n").decode().split("\n")
    all_blobs = {l.split()[0] for l in types if l.endswith(" blob")}
    ref_only = all_blobs - blobs.keys()
    for sha in ref_only:  # a blob reachable only through a tag or a tree no diff names
        blobs[sha] = {listed[sha] or "(unnamed)": "(ref)"}
    proc = subprocess.Popen(["git", "cat-file", "--batch"], cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    hits, total_bytes = [], 0
    for sha in sorted(blobs):
        proc.stdin.write(sha.encode() + b"\n")
        proc.stdin.flush()
        header = proc.stdout.readline().split()
        size = int(header[2])
        data = proc.stdout.read(size)
        proc.stdout.read(1)
        total_bytes += size
        for path, commit in sorted(blobs[sha].items()):
            for pattern, value in scan_blob(data, path):
                hits.append((commit, path, sha, pattern, value))
    proc.stdin.close()
    proc.wait()
    in_scope = sum(1 for paths in blobs.values() if any(in_phi_scope(p) for p in paths))
    stats = dict(commits=commits, blobs=len(blobs), in_scope=in_scope, bytes=total_bytes,
                 seconds=round(time.time() - started, 2), ref_only=len(ref_only))
    return sorted(set(hits)), stats


def self_test():
    def med(prefix8, issue=b"1"):
        d = [c - 48 for c in prefix8]
        check = sum(a * b for a, b in zip(d, (1, 3, 7, 9, 1, 3, 7, 9))) % 10
        return prefix8 + str(check).encode() + issue

    good = med(b"21234567")
    bad = good[:8] + str((good[8] - 48 + 1) % 10).encode() + good[9:]
    cases = [
        (b"PID|1||" + b"800360" + b"1234567890" + b"^^^AUSHIC^NI", "x.hl7", ["ihi"]),
        (b"PRD|" + b"800361" + b"1234567890", "x.hl7", ["hpi-i"]),
        (b"1.2.36.1.2001.1003.0." + b"800362" + b"1234567890" + b"^ISO", "x.hl7", ["hpi-o"]),
        (b"X|" + b"80031" + b"12345678901", "x.hl7", ["nash-8003"]),
        (b"1.2.36.1.2001.1003.0.0000000000001001^ISO", "x.hl7", []),
        (b"PID|1||" + good + b"^^^AUSHIC^MC", "x.hl7", ["medicare"]),
        (b"PID|1||" + bad + b"^^^AUSHIC^MC", "x.hl7", []),
        (b"card " + good[:4] + b" " + good[4:9] + b" " + good[9:], "x.txt", ["medicare"]),
        (b"MSH|...|20240301080000|", "x.hl7", []),
        (b"PID|1||NX" + b"123456" + b"^^^AUSDVA^DVG", "x.hl7", ["dva"]),
        (b"PID|1||VSM" + b"12345" + b"A^^^AUSDVA", "x.hl7", ["dva"]),
        (b"OBX|1|NM|TX1234^Code", "x.hl7", []),
        (b"PID|||||||||||||^PRN^CP^^^^^" + b"04" + b"12345678", "x.hl7", ["au-mobile"]),
        (b"call 04" + b"12 345 678", "x.txt", ["au-mobile"]),
        (b"20" + b"0412345678" + b"00", "x.hl7", []),
        (b"%PDF-1.7\n...", "Sources/a.bin", ["pdf"]),
        (b"page\fpage\fpage\fpage", "notes.md", ["pdftotext"]),
        (b'<xsd:schema xmlns="urn:hl7-org:v2xml">', "Tests/Fixtures/a.txt", ["xsd", "v2xml"]),
        (b'<xsd:schema xmlns="urn:hl7-org:v2xml">', "scripts/a.py", []),
        (b"", "docs/standards/HL7_v24_PDF/ch02.txt", ["licensed-path"]),
        (b"", "docs/XML-schemas/HL7-xml v2.4/ACK.xsd", ["licensed-path"]),
        (b"PID|1||" + b"800360" + b"1234567890", "Sources/HL7v2Kit/A.swift", []),
    ]
    failures = 0
    for data, path, expected in cases:
        got = sorted(p for p, _ in scan_blob(data, path))
        if got != sorted(expected):
            failures += 1
            print(f"FAIL {path} {data[:40]!r}: expected {sorted(expected)}, got {got}")
    print(f"self-test: {len(cases) - failures}/{len(cases)} passed")
    return 1 if failures else 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    if "--history" in argv:
        hits, stats = scan_history()
        for commit, path, sha, pattern, value in hits:
            print(f"HIT {pattern}: {value} | path {path} | blob {sha[:12]} | first commit {commit[:12]}")
        print("history scan: {commits} commits, {blobs} blobs ({in_scope} in PHI scope), {bytes} bytes, "
              "{ref_only} reachable only outside a commit diff, {seconds}s, {n} hit(s)".format(n=len(hits), **stats))
        return 1 if hits else 0
    hits, count = scan_working_tree()
    for path, pattern, value in hits:
        print(f"::error::PHI scan hit {pattern}: {value} in {path}")
    if hits:
        print(f"PHI scan found {len(hits)} hit(s) in {count} fixture file(s). Remediate before merging.")
        return 1
    print(f"PHI scan: {count} fixture file(s), no patterns matched.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
