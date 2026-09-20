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

# Owner-deferred versions (2026-08-23 AU-first re-sequencing; docs/design/deferred-coverage-
# backlog.md). A segment modelled elsewhere but absent here is reported as DEFERRED — visible,
# counted, not a failure. Everywhere else the same absence is a PRESENCE defect.
DEFERRED_VERSIONS = {"v2.6", "v2.8.2"}

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

# (version, segment, index) triples where the schema deliberately
# diverges from the extracted attribute-table value:
#   v2.4/AL1/1  — the v2.4 table AND heading print `CE` for Set ID -
#                 AL1, a known spec typo (SI in v2.3 and v2.5+).
#                 Following it verbatim would dispatch the AU CE
#                 composite rules onto every plain set-ID (req #4
#                 misfire), so the schema normalises to SI; registered
#                 in segment-coverage-extraction.md.
#   v2.5.1/OBX/5 — the variable-type row's prose defeats the extractor
#                 (candidates include `*`, `NA or`, truncated `varie`);
#                 the schema's `varies` is hand-verified (M6-D5).
DATATYPE_WHITELIST = {("v2.4", "AL1", 1), ("v2.5.1", "OBX", 5)}

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
SUSPECT_CODE = re.compile(r"[\[\]|()]|^.{31,}$|[-_:]$|^[A-Z][a-z]{2,}\s\S|^(?!.*\.\.\.)\S+(\s+\S+){2,}$|^\.\.\.$")

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
MOJIBAKE = re.compile("[\u00e2\u00c3]")


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


def extracted_depths(version):
    """(segment -> deepest max-field-index, (segment, index) -> {dataTypes seen})
    across that version's chapter PDFs.

    The dataType map collects the UNION of values seen for a slot: a segment
    can appear in more than one chapter (overview vs defining table), so a
    schema value is a finding only when it matches NO extracted candidate.
    That bias under-reports and never false-positives — M6-O5's first
    measurement must not cry wolf on table-selection noise."""
    best, dts, tbls = {}, {}, {}
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
                for f in fields:
                    dt = (f.get("dataType") or "").strip()
                    if dt:
                        dts.setdefault((seg, f["index"]), set()).add(dt)
                    tbl = (f.get("tbl") or "").strip()
                    if tbl:
                        tbls.setdefault((seg, f["index"]), set()).add(tbl)
    return best, dts, tbls


def depth(write=False):
    if not os.path.exists(EXTRACTOR):
        sys.exit(f"depth pass needs a compiled extractor at {EXTRACTOR}\n"
                 "  xcrun swiftc -O scripts/extract-segment-tables.swift -o /tmp/extractbin")
    if not os.path.isdir(STANDARDS):
        print("docs/standards/ absent — skipping the depth pass (author-local PDFs).")
        return [], [], 0, [], {}, [], [], []
    gaps, suspects, exact, presence, backlog, deferred = [], [], 0, [], {}, []
    datatype_findings, table_findings = [], []
    authored = {v: {os.path.basename(p)[:-5].upper() for p in glob.glob(f"{SCHEMAS}/{v}/*.json")}
                for v in CHAPTER_GLOBS}
    modelled_anywhere = set().union(*authored.values())
    for version in CHAPTER_GLOBS:
        print(f"  extracting {version} ...", file=sys.stderr)
        found, spec_dts, spec_tbls = extracted_depths(version)
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
    return gaps, suspects, exact, presence, backlog, deferred, datatype_findings, table_findings


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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--depth", action="store_true", help="also diff depth against the spec PDFs")
    ap.add_argument("--tables", action="store_true",
                    help="also audit the M6-O6 code-table registry (add --depth to re-extract)")
    ap.add_argument("--write-tables", action="store_true",
                    help="with --depth: write the spec TBL# bindings into the schemas (M9-A sweep)")
    args = ap.parse_args()

    bad = integrity()
    total = len(glob.glob(f"{SCHEMAS}/*/*.json"))
    print(f"\n== integrity: {total} schemas, {len(bad)} findings")
    for rel, idx, why in bad:
        print(f"   {rel} field {idx}: {why}")

    rc = 1 if bad else 0
    if args.depth:
        gaps, suspects, exact, presence, backlog, deferred, dt_findings, tbl_findings = depth(
            write=args.write_tables)
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
        if gaps or suspects or presence or dt_findings or tbl_findings:
            rc = 1

    if args.tables:
        files, table_findings = tables(depth=args.depth)
        print(f"\n== tables: {files} files, {len(table_findings)} findings")
        for rel, number, why in table_findings:
            print(f"   {rel} table {number}: {why}")
        if any("KINDMISMATCH" not in why and "SUSPECT" not in why
               for _, _, why in table_findings):
            rc = 1

    print("\nclean" if rc == 0 else "\nfindings above")
    return rc


if __name__ == "__main__":
    sys.exit(main())
