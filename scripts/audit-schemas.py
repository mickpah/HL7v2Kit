#!/usr/bin/env python3
"""Schema audit — integrity predicates + per-version depth vs. the spec PDFs.

Dev-time contributor tool (ADR-015 family). Nothing here ships: the package has no
dependency on it, and `Package.swift.dependencies` stays empty.

Run this after EVERY sweep batch. It exists because six sweep cycles authored depths that
looked complete and were not — v1.6 found 46 never-authored fields on MSH/PID/ORC/OBR/OBX/
NTE, and v1.7 found five corrupted element names that a marker-word regex had missed.

    # integrity only (fast, no PDFs needed)
    python3 scripts/audit-schemas.py

    # + depth vs. spec (needs the author-local PDFs and a compiled extractor)
    xcrun swiftc -O scripts/extract-segment-tables.swift -o /tmp/extractbin
    python3 scripts/audit-schemas.py --depth

Two directions matter in the depth pass, and they mean different things:

  GAP     schema shallower than the spec  -> candidate missing fields
  SUSPECT schema deeper than the extract  -> the TOOL is failing. Investigate the
                                             extraction; never record it as a depth answer.

Predicates are deliberately *shape*-based (length, character class, emptiness) rather than
enumerated content lists: a marker-word list only finds the corruption you already thought
of. That distinction is what surfaced the v1.7 names.
"""
import argparse, collections, glob, json, os, re, subprocess, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMAS = os.path.join(REPO, "Resources/schemas")
EXTRACTOR = "/tmp/extractbin"

# docs/standards/ is gitignored, so it exists only in the primary working tree — a cycle
# worktree shares .git but not ignored files. Fall back to the main worktree's copy, and
# allow an explicit override.
def _standards_dir():
    if os.environ.get("HL7V2KIT_STANDARDS"):
        return os.environ["HL7V2KIT_STANDARDS"]
    local = os.path.join(REPO, "docs/standards")
    if os.path.isdir(local):
        return local
    try:
        common = subprocess.run(["git", "-C", REPO, "rev-parse", "--git-common-dir"],
                                capture_output=True, text=True, timeout=30).stdout.strip()
        if common:
            main_tree = os.path.dirname(os.path.abspath(os.path.join(REPO, common)))
            candidate = os.path.join(main_tree, "docs/standards")
            if os.path.isdir(candidate):
                return candidate
    except Exception:
        pass
    return local

STANDARDS = _standards_dir()

# RDT is a "1-n" variable-column segment: the row parser needs a bare-integer SEQ, so its
# single real row never parses and the scan binds whatever table follows (in v2.3/v2.3.1,
# the SPR segment). Its hand-authored schema is correct — see segment-coverage-extraction.md.
DEPTH_WHITELIST = {"RDT"}

CHAPTER_GLOBS = {
    "v2.3":   ["HL7_v23_PDF/CH*.pdf"],
    "v2.3.1": ["HL7_v231_PDF/Hl7V231.pdf"],
    "v2.4":   ["HL7_v24_PDF/CH*.PDF"],
    "v2.5.1": ["HL7_v251_PDF/V251_CH*.pdf"],
    "v2.6":   ["HL7_v26_PDF/V26_CH*.pdf"],
    "v2.8.2": ["HL7_V2.8.2_PDF/PDF/V282_CH*.pdf"],
}


def integrity():
    """Shape predicates over every committed schema. Returns a list of findings."""
    findings = []
    for path in sorted(glob.glob(f"{SCHEMAS}/*/*.json")):
        rel = os.path.relpath(path, REPO)
        doc = json.load(open(path))
        seen = collections.Counter()
        for f in doc["fields"]:
            seen[f["index"]] += 1
            name, dt, opt = f.get("name", ""), f.get("dataType", ""), f.get("optionality", "")
            if not name and not dt:
                findings.append((rel, f["index"], "phantom row (no name, no dataType)"))
            elif not dt and opt not in ("W", "X"):
                # empty dataType is spec-CORRECT for withdrawn/reserved fields only
                findings.append((rel, f["index"], f"empty dataType with optionality {opt!r}"))
            if len(name) > 120:
                findings.append((rel, f["index"], f"element name {len(name)} chars — prose bleed?"))
            if re.search(r"[|^<]", name):
                findings.append((rel, f["index"], "delimiter/markup character in element name"))
        for idx, n in seen.items():
            if n > 1:
                findings.append((rel, idx, f"duplicate field index ({n}x)"))
        got = sorted(seen)
        if got and got != list(range(1, max(got) + 1)):
            missing = sorted(set(range(1, max(got) + 1)) - set(got))
            findings.append((rel, 0, f"gap in index sequence, missing {missing}"))
    return findings


def extracted_depths(version):
    """segment -> deepest max-field-index seen across that version's chapter PDFs."""
    best = {}
    pdfs = []
    for pattern in CHAPTER_GLOBS[version]:
        pdfs += sorted(glob.glob(os.path.join(STANDARDS, pattern)))
    for pdf in pdfs:
        try:
            out = subprocess.run([EXTRACTOR, pdf], capture_output=True, timeout=900).stdout
            tables = json.loads(out) if out.strip() else []
        except Exception as exc:
            print(f"  !! {version} {os.path.basename(pdf)}: {exc}", file=sys.stderr)
            continue
        for table in tables:
            seg = (table.get("segmentHint") or "").strip().upper()
            fields = table.get("fields", [])
            if seg and fields:
                best[seg] = max(best.get(seg, 0), max(f["index"] for f in fields))
    return best


def depth():
    if not os.path.exists(EXTRACTOR):
        sys.exit(f"depth pass needs a compiled extractor at {EXTRACTOR}\n"
                 "  xcrun swiftc -O scripts/extract-segment-tables.swift -o /tmp/extractbin")
    if not os.path.isdir(STANDARDS):
        print("docs/standards/ absent — skipping the depth pass (author-local PDFs).")
        return [], [], 0
    gaps, suspects, exact = [], [], 0
    for version in CHAPTER_GLOBS:
        print(f"  extracting {version} ...", file=sys.stderr)
        found = extracted_depths(version)
        for path in sorted(glob.glob(f"{SCHEMAS}/{version}/*.json")):
            seg = os.path.basename(path)[:-5].upper()
            if seg in DEPTH_WHITELIST or seg not in found:
                continue
            schema_depth = max(f["index"] for f in json.load(open(path))["fields"])
            if found[seg] > schema_depth:
                gaps.append((version, seg, schema_depth, found[seg]))
            elif found[seg] < schema_depth:
                suspects.append((version, seg, schema_depth, found[seg]))
            else:
                exact += 1
    return gaps, suspects, exact


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--depth", action="store_true", help="also diff depth against the spec PDFs")
    args = ap.parse_args()

    bad = integrity()
    total = len(glob.glob(f"{SCHEMAS}/*/*.json"))
    print(f"\n== integrity: {total} schemas, {len(bad)} findings")
    for rel, idx, why in bad:
        print(f"   {rel} field {idx}: {why}")

    rc = 1 if bad else 0
    if args.depth:
        gaps, suspects, exact = depth()
        print(f"\n== depth: {exact} exact, {len(gaps)} gaps, {len(suspects)} suspects"
              f"  (whitelisted: {', '.join(sorted(DEPTH_WHITELIST))})")
        for v, seg, s, e in gaps:
            print(f"   GAP      {v} {seg}: schema {s}, spec {e}  -> missing fields?")
        for v, seg, s, e in suspects:
            print(f"   SUSPECT  {v} {seg}: schema {s}, extracted {e}  -> investigate the TOOL")
        if gaps or suspects:
            rc = 1

    print("\nclean" if rc == 0 else "\nfindings above")
    return rc


if __name__ == "__main__":
    sys.exit(main())
