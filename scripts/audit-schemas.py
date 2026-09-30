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

    # + the M6-O6 code-table registry (JSON only; no PDFs needed)
    python3 scripts/audit-schemas.py --tables

    # ... and re-extract every table from the Appendix A / Chapter 2C PDFs to
    # confirm the committed JSON is still what the tool reads out of the spec
    xcrun swiftc -O scripts/extract-code-tables.swift -o /tmp/tablesbin
    python3 scripts/audit-schemas.py --tables --depth

Two directions matter in the depth pass, and they mean different things:

  GAP     schema shallower than the spec  -> candidate missing fields
  SUSPECT schema deeper than the extract  -> the TOOL is failing. Investigate the
                                             extraction; never record it as a depth answer.

Predicates are deliberately *shape*-based (length, character class, emptiness) rather than
enumerated content lists: a marker-word list only finds the corruption you already thought
of. That distinction is what surfaced the v1.7 names.
"""
import argparse, collections, glob, json, os, re, shutil, subprocess, sys, tempfile

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
# Entries are either a bare segment ID (whitelisted on every version) or "version/SEG".
# RDT/ADD: `1-n` rows the extractor cannot parse (hand-authored). This is an EXTRACTOR
# limitation only — the model limitation is resolved (`variableColumns` schema key, see
# integrity() below, which fails a whitelisted RDT/ADD schema missing that key).
# v2.3.1/NSC: the mega-PDF prose-bleeds phantom index rows into Appendix C's NSC figure
# (schema hand-authored, eye-verified; see segment-coverage-extraction.md "Appendix C
# exception").
DEPTH_WHITELIST = {"RDT", "ADD", "v2.3.1/NSC"}

# Owner-deferred versions. The 2026-08-23 deferral of v2.6 / v2.8.2 closed with M5 on
# 2026-09-16 (docs/design/deferred-coverage-backlog.md, closure header), so the set is empty:
# on every version a segment modelled elsewhere but absent here is a PRESENCE defect.
# Re-adding a version needs an owner decision recorded in that backlog.
DEFERRED_VERSIONS = set()

# M6-O5 dataType predicate knobs.
#
# Pre-v2.5 attribute tables type most composites as the placeholder `CM`
# ("composite, defined in the field definition"); the schemas carry the
# v2.5-era NAME of the identical component structure (v2.3 MSH-9's
# components are MSG's) because grammar-level composite dispatch keys on
# it — e.g. HL7au:00049.1 is BASE only because v2.4 MSH-9 is typed MSG.
# A spec `CM` therefore accepts any named COMPOSITE; a scalar against a
# spec `CM` still flags. Scalar set mirrors `scalarDataTypes` in
# Codegen.swift.
SCALAR_DATATYPES = {"SI", "ID", "IS", "ST", "NM", "DT", "TM", "TS", "FT", "TX", "DTM"}

# (version, segment, index) -> citation: slots where the schema deliberately diverges from
# the extracted attribute-table value. Every entry names its source (check-audit-schemas.py
# fails an entry without one).
DATATYPE_WHITELIST = {
    ("v2.4", "AL1", 1): "v2.4 CH3 AL1 attribute table and heading print CE for Set ID - AL1, a "
                        "spec typo (SI in v2.3 and v2.5+); registered in segment-coverage-extraction.md",
    ("v2.5.1", "OBX", 5): "v2.5.1 CH7 OBX-5 variable-type row defeats the extractor (candidates *, "
                          "'NA or', 'varie'); schema `varies` hand-verified in M6-D5",
}
# M20 name predicate. A schema name must equal, after normalisation, an element name the
# version's own attribute table prints for that slot. Extraction can still glue prose onto a
# name (ORC-31 "...all orders (i.e., requested"), so a printed candidate whose normalised
# form STARTS WITH the schema's is accepted; a schema name that is a proper SUFFIX of the
# printed one is a finding, because that is the shape of a name cut at its left edge — 110
# pharmacy-segment names shipped that way ("nistration Sub-ID Counter"). Names on the
# whitelisted segments come from the canonical version and are not compared.
NAME_WHITELIST = set()   # nothing yet: every disagreement was a schema or extractor defect


def normalised_name(name):
    name = name.lower().replace("\u2019", "'").replace("\u2013", "-").replace("\u2014", "-")
    name = re.sub(r"\s*\((deprecated|withdrawn)\)\s*$", "", name)
    return re.sub(r"[^a-z0-9 ]", "", re.sub(r"[\s\-_/]+", " ", name)).strip()


def name_agrees(schema_name, printed):
    """Equal after normalisation, or the printed name starts with the schema's (prose glued
    on). Spaces are dropped for the equality test: v2.4 EDU-4 prints "ParticipationDate" in
    the table and "Participation Date" in its definition heading, and the schema follows
    the heading. A prefix match keeps its space so a name is never accepted as a prefix of
    a longer word."""
    have = normalised_name(schema_name)
    for c in printed:
        want = normalised_name(c)
        if have.replace(" ", "") == want.replace(" ", "") or want.startswith(have + " "):
            return True
    return False


# M19 optionality whitelist: (version, segment, index) -> citation. An entry is a divergence
# from the printed OPT column that the spec text itself backs. Anything else is a finding.
OPTIONALITY_WHITELIST = {
    ("v2.3", "DG1", 2): "v2.3 CH6 DG1 attribute table prints '(B) R' in one OPT cell; the "
                        "extractor reads B, the schema keeps R",
    ("v2.3.1", "DG1", 2): "v2.3.1 CH6 DG1 attribute table prints '(B) R' in one OPT cell; the "
                          "extractor reads B, the schema keeps R",
    ("v2.6", "ORC", 8): "v2.6 CH04 section 4.5.1.8: 'If the parent is not present in the ORC, it "
                        "must be present in the associated OBR'; printed O, modelled C (V26-C13)",
    ("v2.6", "OBR", 29): "v2.6 CH04 section 4.5.3.29: required when the order is a child; printed "
                         "O, modelled C (V26-C13)",
}
REPEATABILITY_WHITELIST = {}
LENGTH_WHITELIST = {}

# M9-A tables predicate. A TBL# cell is well-formed when it is one or more
# 4-digit table numbers joined by "/" (a field may bind more than one table:
# NK1-11 is 0327/0328). Anything else is the TOOL failing — a cell cut at a
# line wrap ("0327/") or a neighbouring column bleeding in ("01107") — and the
# slot must carry a hand-verified entry in scripts/table-repairs.json, keyed
# "<version>/<SEG>-<index>", with the citation it was verified against.
TABLE_REPAIRS_PATH = os.path.join(REPO, "scripts/table-repairs.json")
TABLE_REPAIRS = ({k: v["tables"] for k, v in json.load(open(TABLE_REPAIRS_PATH)).items()}
                 if os.path.exists(TABLE_REPAIRS_PATH) else {})


def expected_tables(version, seg, index, raw_cells):
    """(tables, problem) for one slot from the raw TBL# cells seen for it."""
    key = f"{version}/{seg}-{index}"
    if key in TABLE_REPAIRS:
        return sorted(TABLE_REPAIRS[key]), None
    tokens = [t.strip() for cell in raw_cells for t in cell.split("/")]
    if any(not re.fullmatch(r"\d{4}", t) for t in tokens):
        return None, f"malformed TBL# cell {sorted(raw_cells)} — verify and add to table-repairs.json"
    return sorted(set(tokens)), None


def write_tables(path, wanted):
    """Insert/replace each field's `tables` entry, textually: the schemas are
    hand-formatted (one-field-per-line and one-key-per-line both occur) and do
    not survive a json round-trip byte for byte. `tables` always directly
    follows `repeatability`, so removal restores the original bytes."""
    text = open(path, encoding="utf-8").read()
    text = re.sub(r',\s*"tables"\s*:\s*\[[^\]]*\]', "", text)
    out, pos, index = [], 0, None
    for m in re.finditer(r'"index"\s*:\s*(\d+)|(\n[ \t]*)?"repeatability"\s*:\s*"[^"]*"', text):
        if m.group(1):
            index = int(m.group(1))
        elif wanted.get(index):
            sep = "," + m.group(2) if m.group(2) else ", "  # own-line key vs inline field
            out.append(text[pos:m.end()] + f'{sep}"tables": {json.dumps(wanted[index])}')
            pos = m.end()
    open(path, "w", encoding="utf-8").write("".join(out) + text[pos:])


CHAPTER_GLOBS = {
    "v2.3":   ["HL7_v23_PDF/CH*.pdf"],
    "v2.3.1": ["HL7_v231_PDF/Hl7V231.pdf"],
    "v2.4":   ["HL7_v24_PDF/CH*.PDF"],
    "v2.5.1": ["HL7_v251_PDF/V251_CH*.pdf"],
    "v2.6":   ["HL7_v26_PDF/V26_CH*.pdf"],
    "v2.8.2": ["HL7_V2.8.2_PDF/PDF/V282_CH*.pdf"],
}

# M6-O6 code-table registry. The per-version table JSON lives beside the schemas; the
# hand-kept overlay (permitsLocalExtensions / dropCodes) sits at the root of that tree and
# is deliberately NOT a version directory, so the codegen's `v*` scan ignores it.
TABLES = os.path.join(REPO, "Resources/tables")

# Source PDFs for `--tables --depth`, one per version, and the extractor that reads them.
TABLE_PDFS = {
    "v2.3":   "HL7_v23_PDF/APPA.pdf",
    "v2.3.1": "HL7_v231_PDF/Hl7V231.pdf",
    "v2.4":   "HL7_v24_PDF/AppendixA.PDF",
    "v2.5.1": "HL7_v251_PDF/V251_Appendix_A.pdf",
    "v2.6":   "HL7_v26_PDF/V26_Appendix_A.pdf",
    "v2.8.2": "HL7_V2.8.2_PDF/PDF/V282_CH02C_CodeTables.pdf",
}
TABLE_EXTRACTOR = "/tmp/tablesbin"

# Codes the source PDFs print that are not values, or that the extractor assembled wrongly.
# Every shape here was learned from a defect the code-table review found:
#
#   [ ] |            prose bleed carrying segment-group markup (v2.6 0119 "[ORC", "OBR]")
#   over 30 chars    a footnote URL parsed as a value (v2.8.2 0211)
#   ends - _         a code the printer wrapped and nothing rejoined (v2.8.2 0356 "ISO 2022-")
#   ends :           a "Note:" paragraph set under the table (v2.8.2 0200 / 0301)
#   Capitalised+word a prose sentence in the Value column (v2.6 0119 "Whether the OBRsegments",
#                    0725 "Criterion applying", v2.5.1 0440 "Error location anddescri")
#
# Deliberately narrow otherwise. A space is normal in a printed code ("ISO IR14", "99zzz or
# L") and so is a lone capitalised word ("Routine", "Booked", "Internet" are real values in
# 0276 / 0278 / 0202), so neither is suspect on its own.
#   ( or )           a status annotation or wrapped Description in the Value column
#                    (v2.6 0396 "CE (obsolete)", v2.8.2 0340 "(HCPCS)")
#   three+ words     a Value wider than its column run into the Description
#                    (v2.8.2 0396 "CDCEDACUITY CDC Emergency"); "..." ranges are exempt
#   bare "..."       an ellipsis row: the list continues or the row means null — never a code
#   a comma           several codes printed in one Value cell (0301 "L,M,N"): as one code the
#                    closed table rejects each of them
SUSPECT_CODE = re.compile(r"[\[\]|(),]|^.{31,}$|[-_:]$|^[A-Z][a-z]{2,}\s\S|^(?!.*\.\.\.)\S+(\s+\S+){2,}$|^\.\.\.$")

# Printed codes the shape test would wrongly flag. Each was read against the PDF. Keyed
# (table, code): version-agnostic because the same printed value recurs across versions.
SUSPECT_ALLOW = {
    # UCUM units, printed in square brackets by the spec (v2.8.2 CH02C lines 15924-15941, 17610-17625)
    ("0567", "[lb_av]"), ("0567", "[oz_av]"), ("0568", "[pt_us]"),
    ("0929", "[lb_av]"), ("0929", "[oz_av]"), ("0930", "[pt_us]"),
    # Character-set standard names are printed with spaces
    ("0211", "JIS X 0202"), ("0211", "KS X 1001"),
    # 0396 prints the local-code forms as one Value: "99zzz or L"
    ("0396", "99zzz or L"),
    # 0335 Repeat pattern: a row LABEL for the <timing>C<meal> pattern family (User table)
    ("0335", "Meal Related Timings"),
    # 0290 Base64 alphabet prints the pad row's Value as "(pad)" with code "="
    ("0290", "(pad)"),
}
MOJIBAKE = re.compile("[\u00c2\u00e2\u00c3]")


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
            table = f.get("table")
            if table is not None and not (re.fullmatch(r"\d{4}", table) and dt in ("ID", "IS")):
                findings.append((rel, f["index"], f"malformed table ref {table!r} (dataType {dt!r})"))
            # Merge of M9-A into Track A: `tables` is the verified spec binding (a list, any
            # datatype); `table` is the enforced link codegen reads. They must never disagree.
            if table is not None and table not in f.get("tables", []):
                findings.append((rel, f["index"],
                                 f"table {table!r} is not among the spec bindings {f.get('tables', [])}"))
        for idx, n in seen.items():
            if n > 1:
                findings.append((rel, idx, f"duplicate field index ({n}x)"))
        got = sorted(seen)
        if got and got != list(range(1, max(got) + 1)):
            missing = sorted(set(range(1, max(got) + 1)) - set(got))
            findings.append((rel, 0, f"gap in index sequence, missing {missing}"))
        # Track B: the 1-n class is whitelisted from the depth audit (extractor
        # limitation), so pin its model marker here instead — a 1-n schema that
        # loses `variableColumns` would silently drop columns 2..n from validation.
        seg = os.path.basename(path)[:-5].upper()
        if seg in {"RDT", "ADD"} and not any(f.get("variableColumns") for f in doc["fields"]):
            findings.append((rel, 1, "1-n segment must set variableColumns on its field"))
    return findings


def natural_key(path):
    """Chapter order for a PDF glob: CH2 before CH10 (a plain sort puts CH10 first)."""
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", os.path.basename(path))]


def defining_rows(tables_in_order):
    """segment -> {index: extracted row} from the segment's DEFINING attribute table.

    V23-C13: a slot's printed value used to be accepted if ANY chapter printed it, so the
    v2.3 OBX lengths 4 and 80 from the CH7 "Observational Simple" variant and the CH9 table
    passed against the normative CH7 Figure 7-5 (10 and 590). The defining table is the first
    table, in chapter order, that reaches the segment's deepest extracted index: a variant
    print is shallower, or comes after the home chapter's figure."""
    deepest = {}
    for seg, fields in tables_in_order:
        deepest[seg] = max(deepest.get(seg, 0), max(f["index"] for f in fields))
    out = {}
    for seg, fields in tables_in_order:
        if seg not in out and max(f["index"] for f in fields) == deepest[seg]:
            out[seg] = {f["index"]: f for f in fields}
    return out


def printed_for(defining, union, seg, index, key):
    """The printed values a schema attribute is compared against: the defining table's cell
    when it has one, else the union across chapters (a blank defining cell is an extraction
    gap, not a print)."""
    cell = ((defining.get(seg, {}).get(index) or {}).get(key) or "").strip()
    return {cell} if cell else union.get((seg, index), set())


def optionality_finding(have, printed):
    """M19. True when the schema's OPT is none of the printed codes. C is compared like every
    other code (X-C10 / V26-C07): a printed C modelled O, or a printed O modelled C, is a
    finding unless OPTIONALITY_WHITELIST names it with a citation."""
    return bool(printed) and have not in printed


def extracted_depths(version):
    """(segment -> deepest max-field-index, (segment, index) -> {dataTypes seen})
    across that version's chapter PDFs.

    The dataType map collects the UNION of values seen for a slot: a segment
    can appear in more than one chapter (overview vs defining table), so a
    schema value is a finding only when it matches NO extracted candidate.
    That bias under-reports and never false-positives — M6-O5's first
    measurement must not cry wolf on table-selection noise."""
    best, dts, tbls, opts, names, reps, lens = {}, {}, {}, {}, {}, {}, {}
    ordered = []                        # (segment, fields) in chapter order, for defining_rows
    pdfs = []
    for pattern in CHAPTER_GLOBS[version]:
        pdfs += sorted(glob.glob(os.path.join(STANDARDS, pattern)), key=natural_key)
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
                ordered.append((seg, fields))
                best[seg] = max(best.get(seg, 0), max(f["index"] for f in fields))
                for f in fields:
                    dt = (f.get("dataType") or "").strip()
                    if dt:
                        dts.setdefault((seg, f["index"]), set()).add(dt)
                    tbl = (f.get("tbl") or "").strip()
                    if tbl:
                        tbls.setdefault((seg, f["index"]), set()).add(tbl)
                    opt = (f.get("optionality") or "").strip()
                    if opt:
                        opts.setdefault((seg, f["index"]), set()).add(opt)
                    name = (f.get("name") or "").strip()
                    if name:
                        names.setdefault((seg, f["index"]), set()).add(name)
                    rp = (f.get("repeatability") or "").strip()
                    if rp:
                        reps.setdefault((seg, f["index"]), set()).add(rp)
                    ln = (f.get("len") or "").strip()
                    if ln:
                        lens.setdefault((seg, f["index"]), set()).add(ln)
    return best, dts, tbls, opts, names, reps, lens, defining_rows(ordered)


def write_names(path, wanted):
    """Replace each listed field's `name` value in place, textually."""
    text = open(path, encoding="utf-8").read()
    out, pos, index = [], 0, None
    for m in re.finditer(r'"index"\s*:\s*(\d+)|"name"\s*:\s*"((?:[^"\\]|\\.)*)"', text):
        if m.group(1):
            index = int(m.group(1))
        elif index in wanted:
            out.append(text[pos:m.start()] + '"name": ' + json.dumps(wanted.pop(index), ensure_ascii=False))
            pos = m.end()
    open(path, "w", encoding="utf-8").write("".join(out) + text[pos:])


def write_lengths(path, wanted):
    """Insert or replace each listed field's `length` right after its `dataType`, textually."""
    text = open(path, encoding="utf-8").read()
    text = re.sub(r',\s*"length"\s*:\s*"[^"]*"', "", text)
    out, pos, index = [], 0, None
    for m in re.finditer(r'"index"\s*:\s*(\d+)|"dataType"\s*:\s*"[^"]*"', text):
        if m.group(1):
            index = int(m.group(1))
        elif index in wanted:
            out.append(text[pos:m.end()] + f', "length": {json.dumps(wanted.pop(index))}')
            pos = m.end()
    open(path, "w", encoding="utf-8").write("".join(out) + text[pos:])


def depth(write=False, correct_names=False, record_lengths=False, versions=None):
    if not os.path.exists(EXTRACTOR):
        sys.exit(f"depth pass needs a compiled extractor at {EXTRACTOR}\n"
                 "  xcrun swiftc -O scripts/extract-segment-tables.swift -o /tmp/extractbin")
    if not os.path.isdir(STANDARDS):
        print("docs/standards/ absent — skipping the depth pass (author-local PDFs).")
        return [], [], 0, [], {}, [], [], [], [], [], [], []
    gaps, suspects, exact, presence, backlog, deferred = [], [], 0, [], {}, []
    datatype_findings, table_findings, optionality_findings, name_findings, rp_findings, len_findings = [], [], [], [], [], []
    authored = {v: {os.path.basename(p)[:-5].upper() for p in glob.glob(f"{SCHEMAS}/{v}/*.json")}
                for v in CHAPTER_GLOBS}
    modelled_anywhere = set().union(*authored.values())
    wanted_names, wanted_lengths = {}, {}
    for version in (versions or CHAPTER_GLOBS):
        print(f"  extracting {version} ...", file=sys.stderr)
        found, spec_dts, spec_tbls, spec_opts, spec_names, spec_reps, spec_lens, spec_def = extracted_depths(version)
        # Presence: the depth loop below only sees schemas that EXIST, so an absent segment
        # is invisible to it — that is how the v2.4 lab-automation gap survived three clean
        # audits. A segment the spec defines here that we model on another version is a
        # defect; one we model nowhere is M5 backlog (counted, not failed).
        for seg in sorted(found.keys() - authored[version]):
            if seg.startswith("Z"):
                continue  # Z-segments are site-defined by spec (v2.4 CH08's ZL7 is "PROPOSED EXAMPLE ONLY")
            if seg in modelled_anywhere and version in DEFERRED_VERSIONS:
                deferred.append((version, seg, found[seg]))
            elif seg in modelled_anywhere:
                presence.append((version, seg, found[seg]))
            else:
                backlog[version] = backlog.get(version, 0) + 1
        for path in sorted(glob.glob(f"{SCHEMAS}/{version}/*.json")):
            seg = os.path.basename(path)[:-5].upper()
            if seg in DEPTH_WHITELIST or f"{version}/{seg}" in DEPTH_WHITELIST or seg not in found:
                # M9-A: a segment the extractor cannot be trusted on still takes its
                # hand-verified table bindings (repairs-only; no extracted cell is believed).
                prefix = f"{version}/{seg}-"
                wanted = {int(k[len(prefix):]): sorted(v) for k, v in TABLE_REPAIRS.items()
                          if k.startswith(prefix)}
                if wanted:
                    if write:
                        write_tables(path, wanted)
                    for f in json.load(open(path))["fields"]:
                        if sorted(f.get("tables", [])) != wanted.get(f["index"], []):
                            table_findings.append((version, seg, f["index"],
                                                   f"schema {f.get('tables', [])}, repair {wanted.get(f['index'], [])}"))
                continue
            schema_fields = json.load(open(path))["fields"]
            schema_depth = max(f["index"] for f in schema_fields)
            if found[seg] > schema_depth:
                gaps.append((version, seg, schema_depth, found[seg]))
            elif found[seg] < schema_depth:
                suspects.append((version, seg, schema_depth, found[seg]))
            else:
                exact += 1
            # M6-O5: the dataType column had NO predicate — OBX-5 shipped
            # typed ST against a spec `Variable`/`varies` and survived 717
            # schemas because only field COUNT was compared. A schema value
            # is a finding when the extract saw that slot and the schema's
            # value matches none of the candidates seen for it.
            for f in schema_fields:
                candidates = spec_dts.get((seg, f["index"]))
                schema_dt = (f.get("dataType") or "").strip()
                if not candidates or not schema_dt or schema_dt in candidates:
                    continue
                if (version, seg, f["index"]) in DATATYPE_WHITELIST:
                    continue
                if "CM" in candidates and schema_dt not in SCALAR_DATATYPES:
                    continue  # named refinement of the CM placeholder
                datatype_findings.append(
                    (version, seg, f["index"], schema_dt, sorted(candidates)))
            # M25: the LEN column, recorded VERBATIM. Up to v2.6 the cell is a maximum length,
            # and v2.6 section 2.5.3.2 states "The length of a field is normative"; from v2.7
            # it prints a normative range ("2..2", "32=" truncation-allowed, "250#"
            # truncation-not-allowed) and a separate conformance length. A schema's `length`
            # must be what the version's DEFINING attribute table prints (V23-C13), not any
            # chapter's variant print.
            for f in schema_fields:
                printed = printed_for(spec_def, spec_lens, seg, f["index"], "len")
                have = (f.get("length") or "").strip()
                if not printed or have in printed or (version, seg, f["index"]) in LENGTH_WHITELIST:
                    continue
                if record_lengths:
                    wanted_lengths.setdefault(path, {})[f["index"]] = sorted(printed, key=lambda x: (len(x), x))[0]
                    continue
                len_findings.append((version, seg, f["index"], have, sorted(printed)))
            # M22: the RP/# column, which drives cardinalityExceeded. The extractor renders a
            # printed Y, or a bounded count such as "2" or "Y/3", as "*" and a blank as "1";
            # the schema model has only those two values, so a bounded repeat is "*".
            for f in schema_fields:
                printed = spec_reps.get((seg, f["index"]))
                have = (f.get("repeatability") or "").strip()
                if not printed or have in printed or (version, seg, f["index"]) in REPEATABILITY_WHITELIST:
                    continue
                rp_findings.append((version, seg, f["index"], have, sorted(printed)))
            # M20: the NAME column. See NAME_WHITELIST for the shape rule.
            for f in schema_fields:
                printed = spec_names.get((seg, f["index"]))
                have = (f.get("name") or "").strip()
                # An EMPTY schema name is a finding too: 22 pharmacy fields shipped nameless.
                if not printed or (have and name_agrees(have, printed)):
                    continue
                if (version, seg, f["index"]) in NAME_WHITELIST:
                    continue
                if correct_names:
                    # Prefer a printed candidate that the OTHER chapters agree on (a name
                    # cut at a page edge appears in one chapter only); among those, the
                    # shortest, since prose glued on makes a name longer, never shorter.
                    ranked = sorted(printed, key=lambda c: (-sum(1 for o in printed if normalised_name(o).startswith(normalised_name(c))), len(c)))
                    wanted_names.setdefault(path, {})[f["index"]] = ranked[0]
                    continue
                name_findings.append((version, seg, f["index"], have, sorted(printed)[:2]))
            # M19: the OPT column. A schema's optionality must be the code the version's
            # DEFINING attribute table prints for that slot. An R the spec prints as O is a
            # false "required field missing"; a B it prints as O is a false deprecation
            # warning. C is compared like every other code (X-C10 / V26-C07): the
            # conditional-completeness register decides how a printed C is modelled, but a
            # C / non-C disagreement with the print stays a finding until
            # OPTIONALITY_WHITELIST names it with its spec citation.
            for f in schema_fields:
                printed = printed_for(spec_def, spec_opts, seg, f["index"], "optionality")
                have = (f.get("optionality") or "").strip()
                if not optionality_finding(have, printed):
                    continue
                if (version, seg, f["index"]) in OPTIONALITY_WHITELIST:
                    continue
                optionality_findings.append((version, seg, f["index"], have, sorted(printed)))
            # M9-A: the schema's `tables` must equal the version's own TBL#
            # column, both directions (a stale binding is as wrong as a
            # missing one).
            wanted = {}
            for f in schema_fields:
                tables, problem = expected_tables(
                    version, seg, f["index"], spec_tbls.get((seg, f["index"]), set()))
                if problem:
                    table_findings.append((version, seg, f["index"], problem))
                    continue
                wanted[f["index"]] = tables
            if write:
                write_tables(path, wanted)
                schema_fields = json.load(open(path))["fields"]  # verify what was written
            for f in schema_fields:
                if f["index"] in wanted and sorted(f.get("tables", [])) != wanted[f["index"]]:
                    table_findings.append((version, seg, f["index"],
                                           f"schema {f.get('tables', [])}, spec {wanted[f['index']]}"))
    for path, wanted in wanted_names.items():
        write_names(path, dict(wanted))
        print(f"  names corrected in {os.path.relpath(path, REPO)}: {sorted(wanted)}", file=sys.stderr)
    for path, wanted in wanted_lengths.items():
        write_lengths(path, dict(wanted))
    if wanted_lengths:
        print(f"  lengths written in {len(wanted_lengths)} schemas", file=sys.stderr)
    return gaps, suspects, exact, presence, backlog, deferred, datatype_findings, table_findings, optionality_findings, name_findings, rp_findings, len_findings


def extracted_tables(version):
    """{number: row count} for one version, re-run from that version's source PDF.

    Only for `--tables --depth`: it needs the author-local PDFs and the compiled
    extractor. The plain `--tables` pass reads the committed JSON alone.
    """
    pdf = os.path.join(STANDARDS, TABLE_PDFS[version])
    if not os.path.exists(pdf) or not os.path.exists(TABLE_EXTRACTOR):
        return None
    # The extractor reads the overrides overlay from <outDir>/../overrides.json, so the
    # scratch tree mirrors Resources/tables or every dropCodes table reads as DRIFT.
    root = tempfile.mkdtemp(prefix=f"hl7-tables-{version}-")
    shutil.copy(os.path.join(TABLES, "overrides.json"), os.path.join(root, "overrides.json"))
    out = os.path.join(root, version)
    subprocess.run([TABLE_EXTRACTOR, pdf, version[1:], out],
                   capture_output=True, text=True, timeout=900)
    counts = {}
    for path in glob.glob(f"{out}/*.json"):
        counts[os.path.basename(path)[:-5]] = len(json.load(open(path))["entries"])
    return counts


def tables(depth=False):
    """Integrity of the M6-O6 code-table registry. Returns (file count, findings).

    Findings are (relative path, table number, message). KINDMISMATCH and SUSPECT are
    reported but do not fail: an ID field pointing at a User table is the spec's own
    doing, and a structurally odd code may be exactly what the spec prints.
    """
    findings, files = [], 0
    catalogue = {}                      # version -> {number: doc}
    # Locale renderings (Resources/tables/locale/<locale-id>/) get the same shape checks.
    # Their "version" is the locale id, and they stay out of `catalogue`, which drives the
    # schema-link and re-extraction checks against the base-spec PDFs only.
    for path in sorted(glob.glob(f"{TABLES}/v*/*.json") + glob.glob(f"{TABLES}/locale/*/*.json")):
        files += 1
        rel = os.path.relpath(path, REPO)
        is_locale = os.path.basename(os.path.dirname(os.path.dirname(path))) == "locale"
        version = ("v" if is_locale else "") + os.path.basename(os.path.dirname(path))
        stem = os.path.basename(path)[:-5]
        try:
            doc = json.load(open(path))
        except ValueError as exc:
            findings.append((rel, stem, f"malformed JSON: {exc}"))
            continue
        if doc.get("table") != stem:
            findings.append((rel, stem, f"table {doc.get('table')!r} does not match the filename"))
        if doc.get("version") != version[1:]:
            findings.append((rel, stem, f"version {doc.get('version')!r} does not match the directory"))
        if doc.get("kind") not in ("HL7", "User"):
            findings.append((rel, stem, f"kind {doc.get('kind')!r} is not HL7 or User"))
        if not (doc.get("name") or "").strip():
            findings.append((rel, stem, "empty table name"))
        seen = collections.Counter()
        for entry in doc.get("entries", []):
            code = entry.get("code", "")
            seen[code] += 1
            if not code:
                findings.append((rel, stem, "entry with an empty code"))
            elif SUSPECT_CODE.search(code) and (stem, code) not in SUSPECT_ALLOW:
                findings.append((rel, stem, f"SUSPECT code {code!r} -> investigate the TOOL"))
            if MOJIBAKE.search(code + entry.get("description", "")):
                findings.append((rel, stem, f"mis-decoded text in entry {code!r} -> investigate the TOOL"))
        for code, n in seen.items():
            if n > 1:
                findings.append((rel, stem, f"duplicate code {code!r} ({n}x)"))
        # Two spellings of one value: the printer wrapped the same name at a space in one
        # row and mid-word in another (v2.6 0391 ENCODED ORDER / ENCODED_ORDER). The
        # extractor keeps one of them; if both survived, the rule did not fire.
        variants = collections.defaultdict(list)
        for code in seen:
            variants[code.replace(" ", "").replace("_", "")].append(code)
        for key, spellings in variants.items():
            if len(spellings) > 1:
                findings.append((rel, stem,
                                 f"SUSPECT separator variants {sorted(spellings)} -> investigate the TOOL"))
        if not is_locale:
            catalogue.setdefault(version, {})[stem] = doc

    # Every schema field that links a table must resolve to that version's table, and the
    # field's dataType must agree with the table's owner (ID -> HL7, IS -> User).
    for path in sorted(glob.glob(f"{SCHEMAS}/*/*.json")):
        rel = os.path.relpath(path, REPO)
        version = os.path.basename(os.path.dirname(path))
        for f in json.load(open(path))["fields"]:
            number = f.get("table")
            if not number:
                continue
            doc = catalogue.get(version, {}).get(number)
            if doc is None:
                findings.append((rel, number,
                                 f"field {f['index']} links a table with no {version} JSON"))
                continue
            dt = f.get("dataType")
            if dt == "ID" and doc["kind"] != "HL7":
                findings.append((rel, number,
                                 f"KINDMISMATCH field {f['index']} is ID but the table is User"))
            elif dt == "IS" and doc["kind"] != "User":
                findings.append((rel, number,
                                 f"KINDMISMATCH field {f['index']} is IS but the table is HL7"))

    if depth:
        for version in sorted(catalogue):
            counts = extracted_tables(version)
            if counts is None:
                findings.append((f"Resources/tables/{version}", "-",
                                 "cannot re-extract (missing PDF or /tmp/tablesbin)"))
                continue
            for number, doc in sorted(catalogue[version].items()):
                got = counts.get(number)
                if got is None:
                    findings.append((f"Resources/tables/{version}/{number}.json", number,
                                     "committed but the extractor does not produce it"))
                elif got != len(doc["entries"]):
                    findings.append((f"Resources/tables/{version}/{number}.json", number,
                                     f"DRIFT committed {len(doc['entries'])} rows, extract {got}"))
            for number in sorted(set(counts) - set(catalogue[version])):
                findings.append((f"Resources/tables/{version}/{number}.json", number,
                                 "extractor produces it but it is not committed"))
    return files, findings


DATATYPES = os.path.join(REPO, "Resources/datatypes")
# v2.7+ prints 9999 in a TBL# cell for "no table assigned yet": a sentinel, not a table.
NO_TABLE_SENTINEL = "9999"
COMPONENT_OPT = {"R", "O", "C", "B", "W", "X", "RE"}


def datatypes(depth=False):
    """M10-A — audit Resources/datatypes/ (the Chapter 2A component tables).

    Shape: contiguous component indexes from 1, a known OPT, a datatype unless the
    component is withdrawn, a plausible name, four-digit table numbers that resolve to
    Resources/tables/ for the same version. With `depth`, every file is re-extracted from
    the PDF and must match byte for byte in content (the extractor is the only author)."""
    findings, files = [], 0
    by_version = collections.defaultdict(dict)
    for path in sorted(glob.glob(f"{DATATYPES}/v*/*.json")):
        files += 1
        rel, version, stem = os.path.relpath(path, REPO), os.path.basename(os.path.dirname(path)), os.path.basename(path)[:-5]
        try:
            doc = json.load(open(path))
        except ValueError as exc:
            findings.append((rel, f"malformed JSON: {exc}"))
            continue
        by_version[version][stem] = doc
        if doc.get("dataType") != stem or doc.get("version") != version[1:]:
            findings.append((rel, "dataType / version do not match the path"))
        comps = doc.get("components", [])
        if [c.get("index") for c in comps] != list(range(1, len(comps) + 1)) or not comps:
            findings.append((rel, f"component indexes are not 1..n: {[c.get('index') for c in comps]}"))
        # M13: v2.3 to v2.4 files are recovered from prose (`"source": "prose"`). Prose gives
        # no optionality, and a heading can print no datatype code (XTN.1), so those two
        # checks apply to the printed component tables only. A trailing component with no
        # datatype would be a note the extractor failed to drop.
        prose = doc.get("source") == "prose"
        if prose and comps and not comps[-1].get("dataType"):
            findings.append((rel, f"{stem}: trailing component without a datatype — a note, not a component?"))
        for c in comps:
            where = f"{stem}.{c.get('index')}"
            if prose:
                if c.get("optionality") != "":
                    findings.append((rel, f"{where}: a prose-derived component cannot carry an optionality"))
            elif c.get("optionality") not in COMPONENT_OPT:
                findings.append((rel, f"{where}: unknown optionality {c.get('optionality')!r}"))
            if not prose and not c.get("dataType") and c.get("optionality") not in ("W", "X"):
                findings.append((rel, f"{where}: no datatype on a live component"))
            if c.get("dataType") and not re.fullmatch(r"[A-Z][A-Z0-9]{1,3}|[Vv]aries", c["dataType"]):
                findings.append((rel, f"{where}: implausible datatype {c['dataType']!r}"))
            if not c.get("name") or len(c["name"]) > 70:
                findings.append((rel, f"{where}: empty or over-long name — prose bleed?"))
            for number in c.get("tables", []):
                if not re.fullmatch(r"\d{4}", number):
                    findings.append((rel, f"{where}: malformed table number {number!r}"))
                elif number != NO_TABLE_SENTINEL and not os.path.exists(f"{TABLES}/{version}/{number}.json"):
                    findings.append((rel, f"{where}: table {number} has no file under Resources/tables/{version}"))
    if depth:
        import importlib.util
        spec = importlib.util.spec_from_file_location("dtx", os.path.join(REPO, "scripts/extract-datatype-components.py"))
        dtx = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(dtx)
        spec = importlib.util.spec_from_file_location("dtp", os.path.join(REPO, "scripts/extract-datatype-prose.py"))
        dtp = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(dtp)
        for version, committed in sorted(by_version.items()):
            if version[1:] in dtp.SOURCES:
                if not os.path.exists(os.path.join(STANDARDS, dtp.SOURCES[version[1:]][0])):
                    findings.append((f"Resources/datatypes/{version}", "cannot re-extract (missing PDF)"))
                    continue
                fresh = {code: dtp.document(t) for code, t in dtp.extract(version[1:]).items()}
                for code in sorted(set(fresh) | set(committed)):
                    if fresh.get(code) != committed.get(code):
                        findings.append((f"Resources/datatypes/{version}/{code}.json", "DRIFT against a fresh prose extraction"))
                continue
            if not os.path.exists(os.path.join(STANDARDS, dtx.PDFS[version[1:]])):
                findings.append((f"Resources/datatypes/{version}", "cannot re-extract (missing PDF)"))
                continue
            fresh = dtx.extract(version[1:])
            for code in sorted(set(fresh) | set(committed)):
                got = [(c["index"], c["name"], c["dataType"], c["optionality"], c["len"], c.get("condition", ""), dtx.table_numbers(c["tbl"]))
                       for c in fresh.get(code, {}).get("components", [])]
                have = [(c["index"], c["name"], c.get("dataType", ""), c["optionality"], c.get("length", ""), c.get("condition", ""), c.get("tables", []))
                        for c in committed.get(code, {}).get("components", [])]
                if got != have:
                    findings.append((f"Resources/datatypes/{version}/{code}.json", "DRIFT against a fresh extraction"))
    return files, findings


VMR_TABLE = os.path.join(REPO, "Resources/profiles/au-adrm-2021/vmr-table.json")
VMR_KINDS = {"ENTRY", "SECTION", "STRUCTURAL", "COLLECTION", "CODEDVALUE", "STRING", "DATETIME", "DATERANGE",
             "REAL", "BOOLEAN", "PHYSICALQUANTITY", "INTEGER"}


def vmr(depth=False):
    """M12-A — audit the extracted AU ADRM-2021 VMR implementation table.

    Shape: a dotted path of integers and `*` repeat markers rooted at the declared root;
    unique paths; a name; an OBX-2 code unless the row is STRUCTURAL (which prints "-");
    min <= max; a known VMR datatype; and every `*` row unbounded or every unbounded row a
    `*` row (the appendix's own rule: an upper bound above 1 is written RepeatOf[]). With
    `depth`, the table is re-extracted from the PDF and must match."""
    findings = []
    if not os.path.exists(VMR_TABLE):
        return 0, [("Resources/profiles/au-adrm-2021/vmr-table.json", "missing")]
    doc = json.load(open(VMR_TABLE))
    rel, rows, seen = os.path.relpath(VMR_TABLE, REPO), doc.get("elements", []), set()
    for e in rows:
        path = e.get("path", "")
        if not re.fullmatch(r"\d+(\.(\d+|\*))*", path) or not (path == doc.get("root") or path.startswith(doc.get("root", "") + ".")):
            findings.append((rel, f"malformed or unrooted path {path!r}"))
        if path in seen:
            findings.append((rel, f"duplicate path {path!r}"))
        seen.add(path)
        if not e.get("name") or len(e["name"]) > 60:
            findings.append((rel, f"{path}: empty or over-long name — prose bleed?"))
        if e.get("kind") not in VMR_KINDS:
            findings.append((rel, f"{path}: unknown VMR datatype {e.get('kind')!r}"))
        if (e.get("kind") == "STRUCTURAL") != (e.get("obx2") == ""):
            findings.append((rel, f"{path}: OBX-2 {e.get('obx2')!r} does not fit a {e.get('kind')} row"))
        if e.get("obx2") and not re.fullmatch(r"[A-Z]{2,3}", e["obx2"]):
            findings.append((rel, f"{path}: implausible OBX-2 {e['obx2']!r}"))
        if e.get("max") is not None and e.get("min", 0) > e["max"]:
            findings.append((rel, f"{path}: min {e.get('min')} > max {e['max']}"))
        if (e.get("max") is None) != path.endswith("*"):
            findings.append((rel, f"{path}: an unbounded row must end in a repeat marker, and only such a row may"))
    if depth:
        import importlib.util
        spec = importlib.util.spec_from_file_location("vmrx", os.path.join(REPO, "scripts/extract-vmr-table.py"))
        vmrx = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(vmrx)
        if not os.path.exists(vmrx.PDF):
            findings.append((rel, "cannot re-extract (missing PDF)"))
        elif vmrx.extract() != rows:
            findings.append((rel, "DRIFT against a fresh extraction"))
    return len(rows), findings


# M17 — the specification's own printed examples are the must-pass test for the component
# rules. Every pipe-delimited composite example in each version's datatype chapter is
# checked the way the Validator checks a field: a component printed R must be valued, and an
# ID component (or ID subcomponent of a nested composite) bound to one closed HL7 table
# must carry one of its codes. A rejection is a finding unless it is listed here, with the
# reason the example, not the rule, is at fault.
EXAMPLE_SOURCES = {
    "v2.3":   ("HL7_v23_PDF/CH2.pdf", r"2\.8"),
    "v2.3.1": ("HL7_v231_PDF/Hl7V231.pdf", r"2\.8"),
    "v2.4":   ("HL7_v24_PDF/CH02.PDF", r"2\.9"),
    "v2.5.1": ("HL7_v251_PDF/V251_CH02A.pdf", r"2\.A"),
    "v2.6":   ("HL7_v26_PDF/V26_CH02A_DataTypes.pdf", r"2\.A"),
    "v2.8.2": ("HL7_V2.8.2_PDF/PDF/V282_CH02A_DataTypes.pdf", r"2\.?A"),
}
EXPECTED_EXAMPLE_REJECTIONS = {
    # The example omits XON.4 (check digit), so its scheme "M11" sits in XON.4 and the
    # assigning authority "HCFA" in XON.5. v2.3.1 onward print a corrected example.
    ("v2.3", "XON", "HL7 Health Center^L^6^M11^HCFA", "XON.5"),
    # Fragments printed INSIDE the XTN.9 and XTN.12 component descriptions to illustrate
    # that one component; they are not complete XTN values. v2.8.2 prints XTN.3 as R.
    ("v2.8.2", "XTN", "^^^^^^^^Do not use after 5PM", "XTN.3"),
    ("v2.8.2", "XTN", "^^^^^^^^^^^1-800-Dentist", "XTN.3"),
}
_EXAMPLE_FURNITURE = re.compile(r"Health Level Seven|All rights reserved|Final Standard|^\s*Page \d|^\s*Chapter \d+A?:|\.{6,}")


def _condition_holds(expr, populated, repeated=False):
    """The ComponentGrammar.condition predicate language, mirrored from Swift
    (ComponentCondition.holds): "N populated", "N empty", "repeated", AND, OR,
    parentheses; anything unparseable is False."""
    toks = expr.replace("(", " ( ").replace(")", " ) ").upper().split()
    pos = [0]
    def peek(): return toks[pos[0]] if pos[0] < len(toks) else None
    def atom():
        t = peek()
        if t == "(":
            pos[0] += 1; v = orx()
            if peek() != ")": raise ValueError
            pos[0] += 1; return v
        if t == "REPEATED":
            pos[0] += 1; return repeated
        n = int(t); st = toks[pos[0] + 1]; pos[0] += 2
        if st == "POPULATED": return populated(n)
        if st == "EMPTY": return not populated(n)
        raise ValueError
    def andx():
        v = atom()
        while peek() == "AND": pos[0] += 1; v = atom() and v
        return v
    def orx():
        v = andx()
        while peek() == "OR": pos[0] += 1; v = andx() or v
        return v
    try:
        v = orx(); return v if pos[0] == len(toks) else False
    except Exception:
        return False


class _ClosedTable:
    """Membership in a closed table: a printed code, or a full match of a pattern row."""
    def __init__(self, doc):
        self.codes = {e["code"] for e in doc["entries"]}
        self.patterns = [re.compile(p["regex"]) for p in doc.get("patterns", [])]

    def __contains__(self, value):
        return value in self.codes or any(p.fullmatch(value) for p in self.patterns)


def _closed_codes(version, number):
    path = f"{TABLES}/{version}/{number}.json"
    if not os.path.exists(path):
        return None
    doc = json.load(open(path))
    if doc["kind"] == "HL7" and not doc["permitsLocalExtensions"] and doc["entries"]:
        return _ClosedTable(doc)
    return None


def spec_examples():
    """(example repetitions checked, findings). Skipped without the author-local PDFs."""
    findings, checked = [], 0
    if not os.path.isdir(STANDARDS):
        print("docs/standards/ absent — skipping the spec-example sweep (author-local PDFs).")
        return 0, []
    for version, (pdf, sec) in EXAMPLE_SOURCES.items():
        path = os.path.join(STANDARDS, pdf)
        if not os.path.exists(path):
            findings.append((version, f"cannot read {pdf}"))
            continue
        grammar = {os.path.basename(p)[:-5]: json.load(open(p)) for p in glob.glob(f"{DATATYPES}/{version}/*.json")}
        text = subprocess.run(["pdftotext", "-layout", "-enc", "UTF-8", path, "-"], capture_output=True, text=True).stdout
        current, inside, seen = None, False, set()
        for line in text.split("\n"):
            if _EXAMPLE_FURNITURE.search(line):
                continue
            m = re.match(rf"^\s*{sec}\.(\d+)\s+([A-Z][A-Z0-9]{{1,2}})\s*[-–]\s+\S", line)
            if m:
                current, inside = m.group(2), True
                continue
            if inside and re.match(r"^\s*2\.\d+\s+[A-Z]", line) and not re.match(rf"^\s*{sec}\.", line):
                current, inside = None, False
            if current is None or current not in grammar:
                continue
            for example in re.findall(r"\|([^|\s][^|]*\^[^|]*)\|", line):
                example = example.strip()
                if not (3 <= len(example) <= 200) or example.startswith("^~") or (current, example) in seen:
                    continue
                seen.add((current, example))
                repeated = len(example.split("~")) > 1
                for repetition in example.split("~"):
                    checked += 1
                    comps, problems = repetition.split("^"), []
                    populated = lambda n: n - 1 < len(comps) and comps[n - 1].strip() not in ("", '""')
                    for c in grammar[current]["components"]:
                        value = comps[c["index"] - 1].strip() if len(comps) >= c["index"] else ""
                        where = f"{current}.{c['index']}"
                        if c.get("optionality") == "R" and not value:
                            problems.append((where, where, "printed R but empty in the example"))
                        # M26: a conditional component whose condition holds must be valued.
                        if c.get("condition") and not value and _condition_holds(c["condition"], populated, repeated):
                            problems.append((where, where, f"conditional ({c['condition']}) but empty in the example"))
                        if not value or value == '""':
                            continue
                        bound = c.get("tables", [])
                        if c.get("dataType") == "ID" and len(bound) == 1:
                            codes = _closed_codes(version, bound[0])
                            if codes is not None and value not in codes:
                                problems.append((where, where, f"{value!r} is not in closed Table {bound[0]}"))
                        elif c.get("dataType") in grammar and "&" in value:
                            subs = value.split("&")
                            for sc in grammar[c["dataType"]]["components"]:
                                sv = subs[sc["index"] - 1].strip() if len(subs) >= sc["index"] else ""
                                sb = sc.get("tables", [])
                                if sv and sc.get("dataType") == "ID" and len(sb) == 1:
                                    codes = _closed_codes(version, sb[0])
                                    if codes is not None and sv not in codes:
                                        problems.append((where, f"{where}.{sc['index']}", f"{sv!r} is not in closed Table {sb[0]}"))
                    for component, at, why in problems:
                        if (version, current, example, component) not in EXPECTED_EXAMPLE_REJECTIONS:
                            findings.append((version, f"{at}: {why} <- |{example}|"))
    return checked, findings


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--depth", action="store_true", help="also diff depth against the spec PDFs")
    ap.add_argument("--tables", action="store_true",
                    help="also audit the M6-O6 code-table registry (add --depth to re-extract)")
    ap.add_argument("--datatypes", action="store_true",
                    help="also audit the M10 datatype component tables (add --depth to re-extract)")
    ap.add_argument("--examples", action="store_true",
                    help="also run every example the datatype chapters print through the component rules (M17)")
    ap.add_argument("--vmr", action="store_true",
                    help="also audit the M12 AU VMR implementation table (add --depth to re-extract)")
    ap.add_argument("--write-lengths", action="store_true",
                    help="with --depth: write the printed LEN into the schemas as `length` (M25 sweep)")
    ap.add_argument("--write-names", action="store_true",
                    help="with --depth: replace names the NAME predicate rejects with the shortest printed one (M20)")
    ap.add_argument("--write-tables", action="store_true",
                    help="with --depth: write the spec TBL# bindings into the schemas (M9-A sweep)")
    ap.add_argument("--only-version", action="append", choices=sorted(CHAPTER_GLOBS),
                    help="with --depth: audit only this version (repeatable); OPT and LEN findings print uncapped")
    args = ap.parse_args()

    bad = integrity()
    total = len(glob.glob(f"{SCHEMAS}/*/*.json"))
    print(f"\n== integrity: {total} schemas, {len(bad)} findings")
    for rel, idx, why in bad:
        print(f"   {rel} field {idx}: {why}")

    rc = 1 if bad else 0
    if args.depth:
        gaps, suspects, exact, presence, backlog, deferred, dt_findings, tbl_findings, opt_findings, name_findings, rp_findings, len_findings = depth(
            write=args.write_tables, correct_names=args.write_names, record_lengths=args.write_lengths,
            versions=args.only_version)
        cap = None if args.only_version else 60
        print(f"\n== depth: {exact} exact, {len(gaps)} gaps, {len(suspects)} suspects"
              f"  (whitelisted: {', '.join(sorted(DEPTH_WHITELIST))})")
        for v, seg, s, e in gaps:
            print(f"   GAP      {v} {seg}: schema {s}, spec {e}  -> missing fields?")
        for v, seg, s, e in suspects:
            print(f"   SUSPECT  {v} {seg}: schema {s}, extracted {e}  -> investigate the TOOL")
        print(f"\n== presence: {len(presence)} modelled-elsewhere segments absent; "
              f"never-authored backlog: "
              + ", ".join(f"{v} {n}" for v, n in sorted(backlog.items())))
        for v, seg, e in presence:
            print(f"   PRESENCE {v} {seg}: spec defines {e} fields, no schema  -> author it")
        if deferred:
            print(f"   deferred ({', '.join(sorted(DEFERRED_VERSIONS))}, owner-scheduled): "
                  + ", ".join(f"{v} {seg}({e})" for v, seg, e in deferred))
        print(f"\n== dataType (M6-O5): {len(dt_findings)} findings")
        for v, seg, idx, got, want in dt_findings:
            print(f"   DATATYPE {v} {seg}-{idx}: schema {got!r}, spec saw {want}")
        print(f"\n== table bindings (M9-A): {len(tbl_findings)} findings")
        for v, seg, idx, why in sorted(tbl_findings, key=lambda t: "malformed" not in t[3])[:60]:
            print(f"   TABLES   {v} {seg}-{idx}: {why}")
        if len(tbl_findings) > 60:
            print(f"   ... and {len(tbl_findings) - 60} more")
        print(f"\n== optionality (M19): {len(opt_findings)} findings")
        for v, seg, idx, got, want in opt_findings[:cap]:
            print(f"   OPT      {v} {seg}-{idx}: schema {got!r}, spec prints {want}")
        print(f"\n== name (M20): {len(name_findings)} findings")
        for v, seg, idx, got, want in name_findings[:80]:
            print(f"   NAME     {v} {seg}-{idx}: schema {got!r}, spec prints {want}")
        print(f"\n== repeatability (M22): {len(rp_findings)} findings")
        for v, seg, idx, got, want in rp_findings[:60]:
            print(f"   RP       {v} {seg}-{idx}: schema {got!r}, spec prints {want}")
        print(f"\n== length (M25): {len(len_findings)} findings")
        for v, seg, idx, got, want in len_findings[:cap]:
            print(f"   LEN      {v} {seg}-{idx}: schema {got!r}, spec prints {want}")
        if gaps or suspects or presence or dt_findings or tbl_findings or opt_findings or name_findings or rp_findings or len_findings:
            rc = 1

    if args.tables:
        files, table_findings = tables(depth=args.depth)
        print(f"\n== tables: {files} files, {len(table_findings)} findings")
        for rel, number, why in table_findings:
            print(f"   {rel} table {number}: {why}")
        if any("KINDMISMATCH" not in why and "SUSPECT" not in why
               for _, _, why in table_findings):
            rc = 1

    if args.datatypes:
        dfiles, dfindings = datatypes(depth=args.depth)
        print(f"\n== datatypes (M10-A): {dfiles} files, {len(dfindings)} findings")
        for rel, why in dfindings[:40]:
            print(f"   {rel}: {why}")
        if dfindings:
            rc = 1

    if args.examples:
        echecked, efindings = spec_examples()
        print(f"\n== spec examples (M17): {echecked} example repetitions, {len(efindings)} findings "
              f"({len(EXPECTED_EXAMPLE_REJECTIONS)} registered exceptions)")
        for version, why in efindings[:40]:
            print(f"   EXAMPLE  {version} {why}")
        if efindings:
            rc = 1

    if args.vmr:
        vrows, vfindings = vmr(depth=args.depth)
        print(f"\n== VMR table (M12-A): {vrows} rows, {len(vfindings)} findings")
        for rel, why in vfindings[:40]:
            print(f"   {rel}: {why}")
        if vfindings:
            rc = 1

    print("\nclean" if rc == 0 else "\nfindings above")
    return rc


if __name__ == "__main__":
    sys.exit(main())
