#!/usr/bin/env python3
"""P8b-2a (ADR-019 Option C step 1) -- extract the abstract message syntax tables the chapter
PDFs print under each CODE^EVENT^STRUCTURE caption and emit Resources/structures/v<ver>/*.json.

    python3 scripts/extract-message-structures.py --version 2.5.1 --only ACK,ADT_A01,ORU_R01 --check
    python3 scripts/extract-message-structures.py --version 2.5.1 --only ACK,ADT_A01,ORU_R01 --write
    python3 scripts/extract-message-structures.py --version 2.5.1 --report /tmp/p8b-report-2.5.1.tsv

--check exits 1 on any byte difference from the committed file; --write is idempotent. Without
--only, --check and --write cover the structures already committed for that version. Every run
prints one summary line per version: captions found, structures, parsed, skipped by reason.

The print is the only source of structure (ADR-019). One rule reads a table: a row is syntax
only when its left column, measured from the caption line's column positions, is non-empty;
everything else (wrapped titles, wrapped descriptions, page furniture, the caption repeated
after a page break) is description and ignored. Nesting comes from bracket balance, never from
indentation. Group names come from "--- NAME begin" (nameSource printed) or from a cited
groupNames entry in Resources/structures/overrides.json (nameSource override); an unnamed group
with neither fails the structure. Choice notation (< X | Y >) is not modelled yet (P8b-6): a
structure that prints one is reported and skipped. Only the v2.4 to v2.6 caption form is read
here; ERAS_PENDING names the eras P8b-3 wires.
"""
import argparse
import difflib
import glob
import importlib.util
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
STRUCTURES = os.path.join(REPO, "Resources", "structures")
OVERRIDES = os.path.join(STRUCTURES, "overrides.json")


def _script(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_")[:-3], os.path.join(HERE, name))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_examples = _script("extract-example-messages.py")
CHAPTERS = _examples.CHAPTERS          # single source of the chapter globs (pre-flight A17)
FURN = _examples.FURN                  # page furniture, incl. the v2.7.1 second footer (B3)

# (chapter glob, caption form) per version, for the version-map agreement self-check
# (check-audit-schemas.py). Only the "caret" form is read in P8b-2a.
ERAS = {v: (CHAPTERS[v], era) for v, era in {
    "v2.3": "section-title", "v2.3.1": "table-0354", "v2.4": "caret", "v2.5.1": "caret",
    "v2.6": "caret", "v2.7.1": "caret-colon", "v2.8.2": "caret-colon",
}.items()}
ERAS_PENDING = {
    "v2.3": "P8b-3: no structure IDs; events come from section titles",
    "v2.3.1": "P8b-3: structure IDs come from Table 0354, captions print CODE^EVENT only",
    "v2.7.1": "P8b-3: caption on its own line with a column header that repeats",
    "v2.8.2": "P8b-3: caption on its own line with a column header that repeats",
}

_DASHES = str.maketrans({"‐": "-", "‑": "-", "–": "-"})
CAPTION = re.compile(r"^(\s*)([A-Z][A-Z0-9]{2})\^([A-Za-z0-9]+)\^([A-Z][A-Z0-9]{2}(?:_[A-Za-z0-9]{3})?)"
                     r"\s+(\S.*)$")   # a caption carries a title; a bare CODE^EVT^STRUCT is a table cell
HEADING = re.compile(r"^(\d+[A-Z]?(?:\.\d+)+)\s+(\S.*\S)\s*$")
PAGE = re.compile(r"\bPage\s+(\d+[A-Z]?-\d+)\b")
GROUP_MARK = re.compile(r"^---\s*([A-Z][A-Z0-9_]*)\s+(begin|end)\b")
TOKEN = re.compile(r"\s+|[\[\]{}<>|]|[A-Z][A-Z0-9]{2}(?![A-Za-z0-9_])|\.\.\.|…|.")
TRIGGER = re.compile(r"^[A-Z][A-Z0-9]{2}\^([A-Z0-9]{3}|\*)$")


class UnknownNotation(Exception):
    """Notation the model cannot represent: placeholder text, unbalanced brackets, a stray
    group mark."""


class ChoiceNotation(UnknownNotation):
    """< X | Y > choice notation, not modelled until P8b-6."""


class UnnamedGroup(Exception):
    """A group the print leaves unnamed and overrides.json does not name."""


class OverridesError(Exception):
    pass


@dataclass
class Caption:
    code: str
    event: str
    structure: str
    title: str
    line: int
    chapter: str
    section: str
    section_title: str
    page: str
    code_col: int
    desc_col: int
    source: str = ""
    end_page: str = ""
    repeats: list = field(default_factory=list)

    @property
    def key(self):
        return (self.code, self.event, self.structure)


@dataclass
class Row:
    left: str
    desc: str
    line: int
    page: str


def page_labels(lines):
    """The printed page label of every line: the "Page N-M" footer of its physical page."""
    phys, labels = [], {}
    page = 0
    for line in lines:
        page += line.count("\f")       # pdftotext starts each new page's first line with \f
        phys.append(page)
        m = PAGE.search(line)
        if m and FURN.search(line) and page not in labels:
            labels[page] = m.group(1)
    return [labels.get(p, "") for p in phys]


def split_row(line, desc_col):
    """(left, description) of a table line, or None when text crosses the description column
    (prose, not a table row)."""
    s = line.replace("\f", "").rstrip()
    if not s.strip():
        return ("", "")
    indent = len(s) - len(s.lstrip())
    if indent >= desc_col - 2:
        return ("", s.strip())
    if len(s) <= desc_col:
        return (s.strip(), "")
    best = None
    for m in re.finditer(r" {2,}", s):
        if m.start() > indent and abs(m.end() - desc_col) <= 8:
            if best is None or abs(m.end() - desc_col) < abs(best.end() - desc_col):
                best = m
    if best is None:
        return None
    return (s[:best.start()].strip(), s[best.end():].strip())


def _title(text):
    return " ".join(text.translate(_DASHES).split())


def captions(lines, era="caret", source=""):
    """Every caption occurrence, with its section, chapter and page. A caption repeated after a
    page break inside its own table is still listed here; syntax_rows records it as a repeat."""
    if era != "caret":
        raise NotImplementedError(f"caption era {era!r} is wired in P8b-3")
    pages = page_labels(lines)
    found, section, section_title = [], "", ""
    for i, raw in enumerate(lines):
        line = raw.replace("\f", "")
        if FURN.search(line):
            continue
        h = HEADING.match(line)
        if h and not re.search(r"\.{5,}", line):
            section, section_title = h.group(1), _title(h.group(2))
            continue
        m = CAPTION.match(line)
        if not m:
            continue
        rest, desc_col = m.group(5), m.start(5)
        title = re.sub(r"\s+(Status|Chapter)$", "", re.split(r"\s{2,}", rest)[0])
        for j in range(i + 1, min(i + 4, len(lines))):
            nxt = split_row(lines[j], desc_col)
            if nxt is None or FURN.search(lines[j]) or not "".join(nxt):
                continue
            if not nxt[0] and nxt[1]:
                title = (title + " " + re.split(r"\s{2,}", nxt[1])[0]).strip()
            break
        found.append(Caption(m.group(2), m.group(3), m.group(4), title, i, section.split(".")[0], section,
                             section_title, pages[i], len(m.group(1)), desc_col, source))
    return found


def syntax_rows(lines, caption):
    """The syntax rows of caption's table, in order. Records page-break repeats of the caption
    and the page of the last row on the caption."""
    pages = page_labels(lines)
    rows, depth = [], 0
    code_col, desc_col = caption.code_col, caption.desc_col
    caption.end_page = caption.page
    for i in range(caption.line + 1, len(lines)):
        line = lines[i].replace("\f", "")
        if FURN.search(line) or not line.strip():
            continue
        m = CAPTION.match(line)
        if m:
            if (m.group(2), m.group(3), m.group(4)) != caption.key:
                break
            caption.repeats.append(i)
            code_col = len(m.group(1))
            desc_col = m.start(5)
            continue
        if HEADING.match(line):
            break
        indent = len(line) - len(line.lstrip())
        if indent < code_col - 3:
            break
        cells = split_row(line, desc_col)
        if cells is None:
            if depth == 0:
                break
            raise UnknownNotation(f"line {i + 1}: prose inside an open group: {line.strip()[:60]!r}")
        left, desc = cells
        if not left:
            continue
        depth += sum(left.count(c) for c in "[{<") - sum(left.count(c) for c in "]}>")
        rows.append(Row(left, desc, i, pages[i]))
        caption.end_page = pages[i]
    return rows


def parse(rows):
    """Elements from syntax rows, by bracket balance. A group the print leaves unnamed has
    "group": None until name_groups resolves it."""
    root = {"kind": "root", "children": [], "name": None}
    stack = [root]
    for row in rows:
        opened, closed = [], []
        for tok in (t.group(0) for t in TOKEN.finditer(row.left)):
            if tok.isspace():
                continue
            if tok in "[{":
                node = {"kind": tok, "children": [], "name": None}
                stack[-1]["children"].append(node)
                stack.append(node)
                opened.append(node)
            elif tok in "]}":
                if len(stack) == 1 or stack[-1]["kind"] != {"]": "[", "}": "{"}[tok]:
                    raise UnknownNotation(f"unbalanced {tok!r} in {row.left!r}")
                closed.append(stack.pop())
            elif tok in "<|>":
                raise ChoiceNotation(f"choice notation {tok!r} in {row.left!r}")
            elif re.fullmatch(r"[A-Z][A-Z0-9]{2}", tok):
                stack[-1]["children"].append({"kind": "seg", "id": tok})
            else:
                raise UnknownNotation(f"not notation: {row.left!r}")
        mark = GROUP_MARK.match(row.desc)
        if mark and mark.group(2) == "begin":
            if not opened:
                raise UnknownNotation(f"--- {mark.group(1)} begin on a row that opens no group")
            opened[0]["name"] = mark.group(1)
        elif mark:
            if not any(n["name"] == mark.group(1) for n in closed):
                raise UnknownNotation(f"--- {mark.group(1)} end closes no group of that name")
    if len(stack) != 1:
        raise UnknownNotation("unbalanced brackets: a group is never closed")
    return [_element(child) for child in root["children"]]


def _element(node):
    if node["kind"] == "seg":
        return {"segment": node["id"], "min": 1, "max": 1}
    # Nested brackets around one child are one element: [{X}], {[X]} and [ { A B } ] (ADR-019:
    # min 0 if any [ ], max null if any { }).
    kinds, names = set(), []
    while True:
        kinds.add(node["kind"])
        if node["name"]:
            names.append(node["name"])
        only = node["children"][0] if len(node["children"]) == 1 else None
        # Two printed names are two groups, nested: never merge them.
        if only is not None and only["kind"] != "seg" and not (names and only["name"]):
            node = only
            continue
        break
    if not node["children"]:
        raise UnknownNotation("an empty group")
    bounds = {"min": 0 if "[" in kinds else 1, "max": None if "{" in kinds else 1}
    if len(node["children"]) == 1 and not names:
        return {"segment": node["children"][0]["id"], **bounds}
    return {"group": names[0] if names else None, "nameSource": "printed" if names else None,
            **bounds, "elements": [_element(c) for c in node["children"]]}


def name_groups(elements, version, structure, overrides, used=None, path=()):
    """Resolve every unnamed group through overrides groupNames (nameSource override), or
    raise UnnamedGroup naming the structure and the group's path."""
    for index, element in enumerate(elements):
        if "group" not in element:
            continue
        if element["group"] is None:
            where = list(path) + [index]
            hit = [g for g in overrides["groupNames"]
                   if g["version"] == version and g["structure"] == structure and g["path"] == where]
            if not hit:
                first = element["elements"][0].get("segment") or "a group"
                raise UnnamedGroup(f"{structure} (v{version}): unnamed group at path {where} (first member "
                                   f"{first}); name it in Resources/structures/overrides.json groupNames")
            element["group"], element["nameSource"] = hit[0]["name"], "override"
            if used is not None:
                used.add((version, structure, tuple(where)))
        name_groups(element["elements"], version, structure, overrides, used, tuple(path) + (element["group"],))
    return elements


def _join(items):
    return items[0] if len(items) == 1 else ", ".join(items[:-1]) + " and " + items[-1]


def citation(version, primary, others, overrides, structure):
    pages = (f"p {primary.page}" if primary.page == primary.end_page
             else f"pp {primary.page} to {primary.end_page}")
    text = f"HL7 v{version} Chapter {primary.chapter}, section {primary.section} {primary.section_title}, {pages}"
    if others:
        text += "; the same structure is printed for " + _join([f"{c.code}^{c.event} ({c.section})" for c in others])
    notes = [n["note"] for n in overrides["citationNotes"]
             if n["version"] == version and n["structure"] == structure]
    return text + (notes[0] if notes else ".")


def render_element(element, indent):
    if "segment" in element:
        return (f'{indent}{{ "segment": "{element["segment"]}", "min": {element["min"]}, '
                f'"max": {json.dumps(element["max"])} }}')
    head = (f'{indent}{{ "group": "{element["group"]}", "nameSource": "{element["nameSource"]}", '
            f'"min": {element["min"]}, "max": {json.dumps(element["max"])}, "elements": [')
    body = ",\n".join(render_element(e, indent + "  ") for e in element["elements"])
    return f"{head}\n{body}\n{indent}]}}"


def render(structure):
    """The pilot's exact JSON layout."""
    body = ",\n".join(render_element(e, "    ") for e in structure["elements"])
    triggers = ", ".join(json.dumps(t) for t in structure["triggers"])
    return ("{\n"
            f'  "structure": "{structure["structure"]}",\n'
            f'  "version": "{structure["version"]}",\n'
            f'  "citation": {json.dumps(structure["citation"], ensure_ascii=False)},\n'
            f'  "triggers": [{triggers}],\n'
            f'  "elements": [\n{body}\n  ]\n'
            "}\n")


_OVERRIDE_KEYS = {
    "groupNames": {"version", "structure", "path", "name", "citation"},
    "citationNotes": {"version", "structure", "note"},
    "triggerFolds": {"version", "structure", "trigger", "primary", "citation"},
    "exclusions": {"version", "section", "citation"},
    "errata": set(), "sharedTriggers": set(),
}


def validate_overrides(data):
    if set(data) != set(_OVERRIDE_KEYS):
        raise OverridesError(f"top-level keys {sorted(data)}, expected {sorted(_OVERRIDE_KEYS)}")
    for kind, keys in _OVERRIDE_KEYS.items():
        if not keys and data[kind]:
            raise OverridesError(f"{kind} entries are not read before P8b-3")
        for entry in data[kind]:
            if set(entry) != keys:
                raise OverridesError(f"{kind} entry keys {sorted(entry)}, expected {sorted(keys)}")
            text = entry.get("citation", entry.get("note", ""))
            if not text.strip() or "\n" in text:
                raise OverridesError(f"{kind} entry for {entry.get('structure', entry.get('section'))} "
                                     "needs a one-line citation")
            if kind == "groupNames" and not re.fullmatch(r"[A-Z][A-Z0-9_]*", entry["name"]):
                raise OverridesError(f"bad group name {entry['name']!r}")
    return data


def load_overrides(path=OVERRIDES):
    with open(path, encoding="utf-8") as f:
        return validate_overrides(json.load(f))


def extract_version(version, texts, overrides, only=None):
    """Read every caption of one version. texts: [(source, lines)]. Returns (structures by ID,
    report rows, caption count). A report row is (structure, status, reason)."""
    ver = version.lstrip("v")
    prints, count, early = {}, 0, []
    excluded ={x["section"] for x in overrides["exclusions"] if x["version"] == ver}
    for source, lines in texts:
        consumed = set()
        for cap in captions(lines, ERAS[f"v{ver}"][1], source):
            if cap.line in consumed:
                continue
            count += 1
            try:
                rows, error = syntax_rows(lines, cap), None
            except UnknownNotation as exc:
                rows, error = None, exc
            consumed.update(cap.repeats)
            if cap.section in excluded:     # a non-normative print (ruling G7), cited in overrides
                early.append((cap.structure, "excluded", f"{cap.code}^{cap.event}^{cap.structure} in section {cap.section}"))
                continue
            prints.setdefault(cap.structure, []).append((cap, rows, error))
    folds = {f["structure"]: f for f in overrides["triggerFolds"] if f["version"] == ver}
    structures, report, used, owner = {}, early, set(), {}
    for sid in sorted(prints):
        entries = prints[sid]
        fold = folds.get(sid)
        if fold:
            entries = sorted(entries, key=lambda e: f"{e[0].code}^{e[0].event}" != fold["primary"])
        cap, rows, error = entries[0]
        try:
            if error:
                raise error
            if not TRIGGER.match(f"{cap.code}^{cap.event}") and not fold:
                raise UnknownNotation(f"trigger event {cap.event!r} is not CODE^EVT")
            if not (cap.page and cap.end_page and cap.section):
                raise UnknownNotation("no page footer or section heading found for the caption")
            elements = name_groups(parse(rows), ver, sid, overrides, used)
        except ChoiceNotation as exc:
            report.append((sid, "skipped", f"choice: {exc}"))
            continue
        except UnnamedGroup as exc:
            report.append((sid, "skipped", f"unnamed-group: {exc}"))
            continue
        except UnknownNotation as exc:
            report.append((sid, "skipped", f"unreadable: {cap.source} line {cap.line + 1}: {exc}"))
            continue
        others, triggers = [], []
        for c, r, e in entries:
            trig = f"{c.code}^{c.event}"
            if c is not cap and not fold and trig not in triggers:
                others.append(c)
            if trig not in triggers:
                triggers.append(trig)
            if c is not cap:
                try:
                    same = e is None and name_groups(parse(r), ver, sid, overrides) == elements
                except (UnknownNotation, UnnamedGroup):
                    same = False
                if not same:
                    report.append((sid, "note", f"{trig} print ({c.source} line {c.line + 1}) differs from {cap.code}^{cap.event}"))
        triggers = [fold["trigger"]] if fold else triggers
        for trig in triggers:
            if trig in owner:
                report.append((sid, "note", f"trigger {trig} also claimed by {owner[trig]}"))
            owner.setdefault(trig, sid)
        structures[sid] = {"structure": sid, "version": ver, "triggers": triggers, "elements": elements,
                           "citation": citation(ver, cap, others, overrides, sid)}
        report.append((sid, "parsed", f"{len(entries)} caption(s)"))
    for g in overrides["groupNames"]:
        key = (g["version"], g["structure"], tuple(g["path"]))
        if g["version"] == ver and key not in used and (only is None or g["structure"] in only):
            report.append((g["structure"], "error", f"unused groupNames entry at path {g['path']}"))
    return structures, report, count


def summary(version, structures, report, count):
    skipped = [r for r in report if r[1] == "skipped"]
    reasons = {k: sum(1 for r in skipped if r[2].startswith(k)) for k in ("choice", "unnamed-group", "unreadable")}
    distinct = len({r[0] for r in report if r[1] in ("parsed", "skipped")})
    excluded = sum(1 for r in report if r[1] == "excluded")
    return (f"v{version.lstrip('v')}: {count} captions ({excluded} excluded), {distinct} structures, {len(structures)} parsed, "
            f"{len(skipped)} skipped (choice {reasons['choice']}, unnamed-group {reasons['unnamed-group']}, "
            f"unreadable {reasons['unreadable']})")


def pdf_texts(version):
    out = []
    for pdf in sorted(glob.glob(os.path.join(REPO, "docs/standards", CHAPTERS[version]))):
        text = subprocess.run(["pdftotext", "-layout", "-enc", "UTF-8", pdf, "-"],
                              capture_output=True, text=True).stdout
        out.append((f"{version}/{os.path.basename(pdf)}", text.split("\n")))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description="Extract message structures from the chapter PDFs (ADR-019).")
    ap.add_argument("--version", action="append", help="e.g. 2.5.1; repeatable; default every wired version")
    ap.add_argument("--only", help="comma-separated structure IDs for --check / --write")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    ap.add_argument("--report", help="write a TSV report (version, structure, status, reason)")
    args = ap.parse_args(argv)
    versions = [f"v{v.lstrip('v')}" for v in (args.version or [v for v in ERAS if v not in ERAS_PENDING])]
    overrides = load_overrides()
    failed, tsv = False, []
    for version in versions:
        if version not in ERAS:
            ap.error(f"unknown version {version}")
        if version in ERAS_PENDING:
            print(f"{version}: not read yet ({ERAS_PENDING[version]})")
            failed |= bool(args.check or args.write)
            continue
        texts = pdf_texts(version)
        if not texts:
            print(f"{version}: no PDFs under docs/standards/{CHAPTERS[version]}")
            failed = True
            continue
        target = os.path.join(STRUCTURES, version)
        only = (set(args.only.split(",")) if args.only else None if not (args.check or args.write) else
                {f[:-5] for f in os.listdir(target) if f.endswith(".json")} if os.path.isdir(target) else set())
        structures, report, count = extract_version(version, texts, overrides, only)
        print(summary(version, structures, report, count))
        tsv += [(version[1:],) + r for r in report]
        for sid, status, reason in report:
            if status == "error":
                print(f"  {sid}: {reason}")
                failed = True
        if not (args.check or args.write):
            continue
        for sid in sorted(only):
            if sid not in structures:
                why = next((r[2] for r in report if r[0] == sid and r[1] == "skipped"), "no caption found")
                print(f"  {sid}: not extracted: {why}")
                failed = True
                continue
            path = os.path.join(target, f"{sid}.json")
            text = render(structures[sid])
            old = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
            if args.write and old != text:
                os.makedirs(target, exist_ok=True)
                with open(path, "w", encoding="utf-8") as f:
                    f.write(text)
                print(f"  wrote {os.path.relpath(path, REPO)}")
            elif args.check and old != text:
                failed = True
                print(f"  {sid}: differs from {os.path.relpath(path, REPO)}")
                diff = difflib.unified_diff(old.splitlines(), text.splitlines(), "committed", "extracted", n=0, lineterm="")
                for line in list(diff)[2:10]:
                    print(f"    {line[:160]}")
            elif args.check:
                print(f"  {sid}: identical")
    if args.report:
        with open(args.report, "w", encoding="utf-8") as f:
            f.writelines("\t".join(r) + "\n" for r in tsv)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
