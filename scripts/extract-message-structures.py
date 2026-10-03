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
indentation. Group names come from "--- NAME begin" (nameSource printed); an unnamed group takes
its HL7 v2.xml bundle name (scripts/read-v2xml-bundles.py: nameSource v2xml, or v2xml-v2.4 for
v2.3 and v2.3.1), else a cited groupNames entry in Resources/structures/overrides.json (nameSource
override), else <FIRSTSEG>_GROUP (nameSource synthesised, a no-bundle-name report row). Each
non-printed name is cited in the structure citation. The bundle's element tree is compared with
the print, report only (bundle-differs rows); the print stays normative. Choice notation (< X | Y >) is not modelled yet (P8b-6): a
structure that prints one is reported and skipped. Every caption form is read (P8b-3a, see
captions()); exclusions, errata and shared triggers are cited overrides entries; the report
adds duplicate-differs, needs-structure-id, needs-event, shared-trigger and the Table 0354
reconciliation (0354-missing-row, 0354-missing-caption).
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
_v2xml = _script("read-v2xml-bundles.py")   # P8b-2b: HL7 v2.xml bundle names (ADR-019 decision 3)
Bundles, read_bundle, NAME_SOURCES = _v2xml.Bundles, _v2xml.read_bundle, _v2xml.NAME_SOURCES
BUNDLES, BUNDLES_DERIVED = _v2xml.BUNDLES, _v2xml.BUNDLES_DERIVED

# (chapter glob, caption form) per version, for the version-map agreement self-check
# (check-audit-schemas.py).
ERAS = {v: (CHAPTERS[v], era) for v, era in {
    "v2.3": "section-title", "v2.3.1": "table-0354", "v2.4": "caret", "v2.5.1": "caret",
    "v2.6": "caret", "v2.7.1": "caret-colon", "v2.8.2": "caret-colon",
}.items()}
ERAS_PENDING = {}   # P8b-3a wired the last four eras

# Table 0354 that resolves a caption printing no structure ID (CODE^EVT, or v2.3's CODE alone).
# v2.3 prints no Table 0354; its IDs resolve through v2.3.1's, the nearest later table (cited).
TABLE_0354 = {"2.3": "2.3.1"}

_DASHES = str.maketrans({"‐": "-", "‑": "-", "–": "-"})
_EVT = r"[A-Za-z0-9]+(?:[-,][A-Za-z0-9]+)*"     # A01, C01-C08, PCG,PCH,PCJ, S12-S24,S26,S27, varies
_SID = r"[A-Z][A-Z0-9]{2}(?:_[A-Za-z0-9]{3})?"
CAPTION = re.compile(r"^(\s*)([A-Z][A-Z0-9]{2})\^(" + _EVT + r")\^(" + _SID + r")"
                     r"\s+(\S.*)$")   # a caption carries a title; a bare CODE^EVT^STRUCT is a table cell
# CODE^EVT with a title two or more spaces away (v2.3.1; v2.4's two-part captions): the structure
# ID comes from Table 0354. A line holding "|" or "<cr>" is an example message, never a caption.
TWO_PART = re.compile(r"^(\s*)([A-Z][A-Z0-9]{2})\^(" + _EVT + r")(\s{2,})(\S.*)$")
# v2.7.1 and v2.8.2: "CODE^EVT^STRUCT: title" on its own line, then a "Segments Description" row.
COLON = re.compile(r"^(\s*)([A-Z][A-Z0-9]{2})\^(" + _EVT + r")\^(" + _SID + r"):\s+(\S.*)$")
COLUMNS = re.compile(r"^(\s*)Segments\s{2,}(Description)\b")
# v2.3: the message code alone, a title and "Chapter"; the event is in the section title.
CODE_ONLY = re.compile(r"^(\s*)([A-Z][A-Z0-9]{2})(\s{3,})(\S.*?)\s{2,}Chapter\s*$")
TITLE_EVENTS = re.compile(r"\(\s*events?\s+([A-Z0-9]{3}(?:\s*(?:,|and|&|-|to)\s*[A-Z0-9]{3})*)\s*\)", re.I)
FOOTNOTE = re.compile(r"^\s*\d{1,2}\s*$")      # a footnote digit on a line of its own (P8b-2a review)
HEADING = re.compile(r"^(\d+[A-Z]?(?:\.[A-Z])?(?:\.\d+)+)\s+(\S.*\S)\s*$")   # 3.3.1, 4A.3.20, 2.B.7.5
PAGE = re.compile(r"\bPage\s+(\d+[A-Z]?-\d+|\d+)\b")   # v2.7.1 and v2.8.2 number pages per chapter
GROUP_MARK = re.compile(r"^---\s*([A-Z][A-Z0-9_]*)\s+((?i:begin|end))\b")   # "--- VISIT End" (v2.5.1 CSU_C09)
TOKEN = re.compile(r"\s+|[\[\]{}<>|]|[A-Z][A-Z0-9]{2}(?![A-Za-z0-9_])|\.\.\.|…|.")
TRIGGER = re.compile(r"^[A-Z][A-Z0-9]{2}\^([A-Z0-9]{3}|\*)$")


class UnknownNotation(Exception):
    """Notation the model cannot represent: placeholder text, unbalanced brackets, a stray
    group mark."""


class ChoiceNotation(UnknownNotation):
    """< X | Y > choice notation, not modelled until P8b-6."""


class NameSourceError(Exception):
    """A group nameSource outside NAME_SOURCES, or a non-printed name the citation does not cite."""


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
    era: str = "caret"
    events: list = field(default_factory=list)
    id_source: str = "printed"

    @property
    def key(self):
        return (self.code, self.event, self.structure)

    @property
    def printed(self):
        """The caption as printed (the structure ID only when the print carries one)."""
        return f"{self.code}^{self.event}" + (f"^{self.structure}" if self.id_source == "printed" else "")


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
        # A row with an empty description whose other text sits in a later column (the Chapter
        # column with a footnote number, OUL_R23 and OUL_R24; v2.4's Group Control column,
        # RSP_K21) is still a row, not prose.
        for m in re.finditer(r" {2,}", s):
            if indent < m.start() < desc_col and m.end() > desc_col + 8:
                return (s[:m.start()].strip(), "")
        return None
    return (s[:best.start()].strip(), s[best.end():].strip())


def _title(text):
    return " ".join(text.translate(_DASHES).split())


def expand_events(text):
    """The events a caption names: "C01-C08" is eight, "PCG,PCH,PCJ" three, "S12-S24,S26,S27"
    fifteen. A range runs over the suffix after the common prefix (digits or one letter). None
    when a range cannot be read."""
    out = []
    for part in text.split(","):
        if "-" not in part:
            out.append(part)
            continue
        a, b = part.split("-", 1)
        k = 0
        while k < min(len(a), len(b)) and a[k] == b[k]:
            k += 1
        sa, sb = a[k:], b[k:]
        if len(a) != len(b) or not sa:
            return None
        if sa.isdigit() and sb.isdigit():
            run = [str(n).zfill(len(sa)) for n in range(int(sa), int(sb) + 1)]
        elif len(sa) == 1 and sa.isalpha() and sb.isalpha():
            run = [chr(c) for c in range(ord(sa), ord(sb) + 1)]
        else:
            return None
        if not run:
            return None
        out += [a[:k] + r for r in run]
    return out


def title_events(section_title):
    """v2.3: the events a section title names, "(event A01)" or "(events A01, A04)"."""
    m = TITLE_EVENTS.search(section_title)
    if not m:
        return []
    text = re.sub(r"\s*(?:and|&)\s*", ",", m.group(1), flags=re.I)
    text = re.sub(r"\s*(?:to|-)\s*", "-", text, flags=re.I).replace(" ", "")
    return expand_events(text) or []


def match_caption(line, era):
    """(indent, code, event, structure, title column, title) when line is a caption of era's
    form, else None. structure is "" when the print carries none (resolved through Table 0354)."""
    line = line.translate(_DASHES)
    if era == "caret-colon":
        m = COLON.match(line)
        return m and (len(m.group(1)), m.group(2), m.group(3), m.group(4), m.start(5), m.group(5))
    if era == "section-title":
        m = CODE_ONLY.match(line)
        return m and (len(m.group(1)), m.group(2), "", "", m.start(4), m.group(4))
    m = CAPTION.match(line)
    if m:
        return (len(m.group(1)), m.group(2), m.group(3), m.group(4), m.start(5), m.group(5))
    m = TWO_PART.match(line)
    if m and "|" not in line and "<cr>" not in line.lower():
        return (len(m.group(1)), m.group(2), m.group(3), "", m.start(5), m.group(5))
    return None


def captions(lines, era="caret", source=""):
    """Every caption occurrence, with its section, chapter and page. A caption repeated after a
    page break inside its own table is still listed here; syntax_rows records it as a repeat.
    Eras (ADR-019 caption-form table): caret (v2.4 to v2.6, CODE^EVT^STRUCT with the title on
    the line, or CODE^EVT); table-0354 (v2.3.1, mostly CODE^EVT); caret-colon (v2.7.1, v2.8.2,
    "CODE^EVT^STRUCT: title" then a Segments/Description column row); section-title (v2.3, the
    code alone, the event in the section title). A caption needs no Status or Chapter header:
    v2.4 prints 34 three-part captions without one, every one a CH04/CH05 query or response
    grammar example or a Z-event, each excluded by a cited exclusions entry (ruling G7)."""
    if era not in ("caret", "table-0354", "caret-colon", "section-title"):
        raise ValueError(f"unknown caption era {era!r}")
    pages = page_labels(lines)
    found, section, section_title = [], "", ""
    for i, raw in enumerate(lines):
        line = raw.replace("\f", "")
        if FURN.search(line):
            continue
        h = HEADING.match(line)
        if h and not re.search(r"\.{5,}", line):
            section, section_title = h.group(1), _title(h.group(2))
            # A title that wraps inside its parentheses ("(events" / "PC1, PC2)") continues
            # on the next non-blank line.
            nxt = next((x.replace("\f", "") for x in lines[i + 1:i + 4] if x.strip() and not FURN.search(x)), "")
            if section_title.count("(") > section_title.count(")") and nxt.strip().count(")"):
                section_title = _title(section_title + " " + nxt)
            continue
        m = match_caption(line, era)
        if not m:
            continue
        indent, code, event, structure, desc_col, rest = m
        title = re.sub(r"\s+(Status|Chapter)$", "", re.split(r"\s{2,}", rest)[0])
        code_col = indent
        if era == "caret-colon":
            title = _title(rest)
            for j in range(i + 1, min(i + 5, len(lines))):
                cols = COLUMNS.match(lines[j].replace("\f", ""))
                if cols:
                    code_col, desc_col = len(cols.group(1)), cols.start(2)
                    break
        else:
            for j in range(i + 1, min(i + 4, len(lines))):
                nxt = split_row(lines[j], desc_col)
                if nxt is None or FURN.search(lines[j]) or not "".join(nxt):
                    continue
                if not nxt[0] and nxt[1]:
                    title = (title + " " + re.split(r"\s{2,}", nxt[1])[0]).strip()
                break
        events = title_events(section_title) if era == "section-title" else expand_events(event) or []
        if era == "section-title":
            event = ",".join(events)
        found.append(Caption(code, event, structure, title, i, section.split(".")[0], section,
                             section_title, pages[i], code_col, desc_col, source, era=era, events=events,
                             id_source="printed" if structure else "0354"))
    return found


_NOTATION = re.compile(r"^(?:[\[\]{}<>|]|[A-Z][A-Z0-9]{2}(?![A-Za-z0-9_])|\.\.\.|…)")


def syntax_rows(lines, caption):
    """The syntax rows of caption's table, in order. Records page-break repeats of the caption
    and the page of the last row on the caption. A repeated Segments/Description row (v2.7.1,
    v2.8.2) resets the columns; a footnote digit on a line of its own is furniture, and one at
    the left margin opens the page-foot footnotes, read as furniture up to the page footer."""
    pages = page_labels(lines)
    rows, depth, foot = [], 0, False
    code_col, desc_col = caption.code_col, caption.desc_col
    caption.end_page = caption.page
    for i in range(caption.line + 1, len(lines)):
        line = lines[i].replace("\f", "")
        if FURN.search(line):
            foot = False
            continue
        if foot or not line.strip() or FOOTNOTE.match(line):
            foot = foot or bool(re.match(r"^\d{1,2}\s*$", line))
            continue
        m = match_caption(line, caption.era)
        if m:
            if (m[1], m[2] if caption.era != "section-title" else caption.event, m[3]) != caption.key:
                break
            caption.repeats.append(i)
            if caption.era != "caret-colon":
                code_col, desc_col = m[0], m[4]
            continue
        cols = COLUMNS.match(line)
        if cols:
            code_col, desc_col = len(cols.group(1)), cols.start(2)
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
            # "--- NAME" with "begin" or "end" wrapped onto the description's next line.
            if rows and re.fullmatch(r"---\s*[A-Z][A-Za-z0-9_ /]*", rows[-1].desc) and re.match(r"(?i)(begin|end)\b", desc):
                rows[-1].desc += " " + desc
            continue
        if depth == 0 and rows and not _NOTATION.match(left):
            break       # prose or another table's header after the table (v2.5.1 RSP_K23's QPD field table)
        depth += sum(left.count(c) for c in "[{<") - sum(left.count(c) for c in "]}>")
        rows.append(Row(left, desc, i, pages[i]))
        caption.end_page = pages[i]
    return rows


def parse(rows, marks=None, used=None):
    """Elements from syntax rows, by bracket balance. A group the print leaves unnamed has
    "group": None until name_groups resolves it. marks maps a misprinted group-mark name to the
    intended one (a cited errata entry); used receives every printed name it corrected."""
    marks = marks or {}
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
        desc = row.desc
        for printed, intended in marks.items():
            if re.match(r"^---\s*" + re.escape(printed) + r"\s+(begin|end)\b", desc):
                desc = desc.replace(printed, intended, 1)
                if used is not None:
                    used.add(printed)
        mark = GROUP_MARK.match(desc)
        name = mark and mark.group(1)
        if not mark and re.match(r"^---\s*\S", desc):
            raise UnknownNotation(f"group mark not read: {desc[:50]!r}")
        if mark and mark.group(2).lower() == "begin":
            if not opened:
                raise UnknownNotation(f"--- {name} begin on a row that opens no group")
            opened[0]["name"] = name
        elif mark:
            if not any(n["name"] == name for n in closed):
                raise UnknownNotation(f"--- {name} end closes no group of that name")
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


def name_groups(elements, version, structure, overrides, used=None, path=(), bundles=None, log=None, taken=None):
    """Name every unnamed group, top down (a child's parent path uses its parent's resolved
    name): the HL7 v2.xml bundle, else an overrides groupNames entry, else <FIRSTSEG>_GROUP.
    log receives one entry per resolved name: {path, name, source, cite, miss, shadowed}."""
    bundles = bundles if bundles is not None else Bundles()
    if taken is None:
        taken = {g["group"] for _, g in _v2xml.groups(elements) if g["group"]}
    for index, element in enumerate(elements):
        if "group" not in element:
            continue
        if element["group"] is None:
            where = list(path) + [index]
            hit = [g for g in overrides["groupNames"]
                   if g["version"] == version and g["structure"] == structure and g["path"] == where]
            name, source, cite = _v2xml.resolve(bundles, version, structure, path, element["elements"])
            entry = {"path": where, "miss": name is None, "shadowed": bool(name and hit)}
            if name is None and hit:
                name, source, cite = hit[0]["name"], "override", f"overrides.json: {hit[0]['citation']}"
            elif name is None:
                base = f"{_v2xml.signature(element['elements'])[0]}_GROUP"
                name = next(n for n in [base] + [f"{base}{k}" for k in range(2, 100)] if n not in taken)
                source, cite = "synthesised", f"synthesised: {cite}"
            if hit and used is not None:
                used.add((version, structure, tuple(where)))
            taken.add(name)
            element["group"], element["nameSource"] = name, source
            if log is not None:
                log.append({**entry, "name": name, "source": source, "cite": cite})
        name_groups(element["elements"], version, structure, overrides, used, tuple(path) + (element["group"],),
                    bundles, log, taken)
    return elements


def name_citation(log):
    """The sentence that cites every non-printed group name, in document order."""
    if not log:
        return ""
    return " Unprinted group names (ADR-019 decision 3): " + _join([f"{e['name']} ({e['cite']})" for e in log]) + "."


def validate_names(structure):
    """Every group's nameSource is one of NAME_SOURCES, and every non-printed name is cited
    (the rule StructureCodegen enforces)."""
    for _, group in _v2xml.groups(structure["elements"]):
        source = group.get("nameSource")
        if source not in NAME_SOURCES:
            raise NameSourceError(f"group {group['group']}: nameSource {source!r} is not one of {NAME_SOURCES}")
        if (source == "v2xml-v2.4") != (source.startswith("v2xml") and structure["version"] in ("2.3", "2.3.1")):
            raise NameSourceError(f"group {group['group']}: nameSource {source} on v{structure['version']}; "
                                  "v2xml-v2.4 is for v2.3 and v2.3.1 only, which have no v2xml")
        if source != "printed":
            need = _v2xml.required_citation(group["group"], source, structure["version"])
            if need not in structure["citation"]:
                raise NameSourceError(f"group {group['group']} ({source}): the citation lacks {need!r}")
    return structure


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
    # A print typo read as the intended text: in a caption (CODE^EVT as printed), a group mark
    # ("--- NAME begin/end"), or a Table 0354 row (its code or an event in its description).
    "errata": {"version", "where", "structure", "printed", "intended", "citation"},
    # A trigger printed under several structures (pre-flight B6); reported, never modelled here.
    "sharedTriggers": {"version", "trigger", "structures", "citation"},
}
ERRATA_WHERE = ("caption", "group-mark", "table-0354")


def validate_overrides(data):
    if set(data) != set(_OVERRIDE_KEYS):
        raise OverridesError(f"top-level keys {sorted(data)}, expected {sorted(_OVERRIDE_KEYS)}")
    for kind, keys in _OVERRIDE_KEYS.items():
        for entry in data[kind]:
            if kind == "errata" and entry.get("where") not in ERRATA_WHERE:
                raise OverridesError(f"errata entry where {entry.get('where')!r}, expected one of {ERRATA_WHERE}")
            if kind == "errata" and entry.get("printed") == entry.get("intended"):
                raise OverridesError(f"errata entry for {entry.get('structure')}: printed equals intended")
            if kind == "sharedTriggers" and len(set(entry.get("structures", []))) < 2:
                raise OverridesError(f"sharedTriggers entry {entry.get('trigger')} names fewer than two structures")
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


def load_0354(version):
    """Table 0354 rows of a version as [(code, events, description)]; events is None for a row
    that applies to every event ("Varies"). [] when the version prints no Table 0354."""
    path = os.path.join(REPO, "Resources", "tables", f"v{version}", "0354.json")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        entries = json.load(f)["entries"]
    return [(e["code"], None if e["description"].strip().lower() == "varies" else
             re.findall(r"\b[A-Z0-9]{3,4}\b", e["description"]), e["description"]) for e in entries]


def apply_table_errata(table, errata, used):
    """Table 0354 rows with each cited table-0354 erratum applied (a misprinted row code, or a
    misprinted event in the row's description)."""
    out = []
    for code, events, desc in table:
        for e in errata:
            if e["where"] != "table-0354":
                continue
            if code == e["printed"]:
                code = e["intended"]
                used.add(id(e))
            elif code == e["structure"] and events and e["printed"] in events:
                events = [e["intended"] if x == e["printed"] else x for x in events]
                used.add(id(e))
        out.append((code, events, desc))
    return out


def resolve_structure(table, code, events):
    """The Table 0354 structure IDs a CODE^EVT caption can name: the row whose code is the
    message code itself (ACK), or a CODE_xxx row listing every one of the caption's events."""
    hits = []
    for row, row_events, _ in table:
        if row == code or (row.startswith(code + "_") and row_events is not None
                           and events and all(e in row_events for e in events)):
            hits.append(row)
    return sorted(set(hits))


def compact(elements):
    """A one-line rendering of elements in print notation, for report rows."""
    out = []
    for e in elements:
        inner = e["segment"] if "segment" in e else f"{e['group']}: " + compact(e["elements"])
        if e["max"] is None:
            inner = "{" + inner + "}"
        if e["min"] == 0:
            inner = "[" + inner + "]"
        out.append(inner)
    return " ".join(out)


def _primary(sid, entries, fold):
    """The primary print (ADR-019 addendum, P8b-3a): exclusions are already gone; a triggerFolds
    entry names it; else the first print in reading order whose caption is the defining trigger
    (CODE_EVT equals the structure ID: the chapter that defines the message, not one that only
    reuses it); else the first print in reading order."""
    if fold:
        return next((k for k, e in enumerate(entries) if fold["primary"] in (e[0].printed, f"{e[0].code}^{e[0].event}")), 0)
    return next((k for k, e in enumerate(entries) if any(f"{e[0].code}_{v}" == sid for v in e[0].events)), 0)


def extract_version(version, texts, overrides, only=None, bundles=None, tables=None, full=False):
    """Read every caption of one version. texts: [(source, lines)] in reading order. Returns
    (structures by ID, report rows, caption count). A report row is (structure, status, reason).
    bundles: the HL7 v2.xml bundles (default none, so every unprinted name is an override or
    synthesised). tables: Table 0354 rows (default: the version's, see TABLE_0354). full: the
    texts are the whole print, so an exclusion or erratum that matches nothing is an error."""
    ver = version.lstrip("v")
    era = ERAS[f"v{ver}"][1]
    bundles = bundles if bundles is not None else Bundles()
    errata = [e for e in overrides["errata"] if e["version"] == ver]
    used_errata = set()
    table_ver = TABLE_0354.get(ver, ver)     # the table's own errata apply where it is borrowed (v2.3)
    table = apply_table_errata(tables if tables is not None else load_0354(table_ver),
                               [e for e in overrides["errata"] if e["version"] == table_ver], used_errata)
    excluded = {x["section"]: x for x in overrides["exclusions"] if x["version"] == ver}
    used_exclusions = set()
    caption_errata = {e["printed"]: e for e in errata if e["where"] == "caption"}
    prints, count, report = {}, 0, []
    for source, lines in texts:
        consumed = set()
        for cap in captions(lines, era, source):
            if cap.line in consumed:
                continue
            count += 1
            fix = caption_errata.get(f"{cap.code}^{cap.event}")
            try:
                rows, error = syntax_rows(lines, cap), None
            except UnknownNotation as exc:
                rows, error = None, exc
            consumed.update(cap.repeats)
            if fix:
                used_errata.add(id(fix))
                cap.code, cap.event = fix["intended"].split("^", 1)
                cap.events = expand_events(cap.event) or []
            where = f"{cap.printed} in section {cap.section}"
            if cap.section in excluded:     # a non-normative print (ruling G7), cited in overrides
                used_exclusions.add(cap.section)
                report.append((cap.structure or f"{cap.code}^{cap.event}", "excluded", where))
                continue
            if not cap.events:
                report.append((f"{cap.code}^{cap.event or '?'}", "needs-event",
                               f"{cap.source} line {cap.line + 1}: section {cap.section} {cap.section_title[:60]!r} "
                               "names no event"))
                continue
            if not cap.structure:
                hits = resolve_structure(table, cap.code, cap.events)
                if len(hits) != 1:
                    why = (f"Table 0354 (v{table_ver}) has no row for it" if not hits else
                           f"Table 0354 (v{table_ver}) maps it to {', '.join(hits)}" if table else
                           "no Table 0354")
                    report.append((f"{cap.code}^{cap.event}", "needs-structure-id",
                                   f"{cap.source} line {cap.line + 1} (section {cap.section}): {why}"))
                    continue
                cap.structure = hits[0]
            prints.setdefault(cap.structure, []).append((cap, rows, error))
    for e in errata:     # a group-mark erratum is used when any print of its structure carries the mark
        if e["where"] == "group-mark" and any(
                re.match(r"^---\s*" + re.escape(e["printed"]) + r"\s+(?i:begin|end)\b", row.desc)
                for _, rows, _ in prints.get(e["structure"], []) for row in rows or []):
            used_errata.add(id(e))
    folds = {f["structure"]: f for f in overrides["triggerFolds"] if f["version"] == ver}
    marks = {}
    for e in errata:
        if e["where"] == "group-mark":
            marks.setdefault(e["structure"], {})[e["printed"]] = e
    structures, used, owner, bundle_rows = {}, set(), {}, []

    def read(sid, rows, error, log=None, names_used=None):
        if error:
            raise error
        seen = set()
        tree = parse(rows, {k: v["intended"] for k, v in marks.get(sid, {}).items()}, seen)
        for printed in seen:
            used_errata.add(id(marks[sid][printed]))
        return name_groups(tree, ver, sid, overrides, names_used, bundles=bundles, log=log)

    for sid in sorted(prints):
        entries = prints[sid]
        fold = folds.get(sid)
        k = _primary(sid, entries, fold)
        entries = [entries[k]] + entries[:k] + entries[k + 1:]
        cap, rows, error = entries[0]
        try:
            if not all(TRIGGER.match(f"{cap.code}^{v}") for v in cap.events) and not fold:
                raise UnknownNotation(f"trigger event {cap.event!r} is not CODE^EVT")
            if not (cap.page and cap.end_page and cap.section):
                raise UnknownNotation("no page footer or section heading found for the caption")
            log = []
            elements = read(sid, rows, error, log, used)
        except ChoiceNotation as exc:
            report.append((sid, "skipped", f"choice: {exc}"))
            continue
        except UnknownNotation as exc:
            report.append((sid, "skipped", f"unreadable: {cap.source} line {cap.line + 1}: {exc}"))
            continue
        others, triggers = [], []
        for c, r, e in entries:
            trigs = [f"{c.code}^{v}" for v in c.events]
            if c is not cap and not fold and not set(trigs) <= set(triggers):
                others.append(c)
            triggers += [t for t in trigs if t not in triggers]
            if c is cap:
                continue
            try:
                theirs = read(sid, r, e)
            except UnknownNotation as exc:
                report.append((sid, "duplicate-unreadable", f"{c.printed} ({c.source} line {c.line + 1}, section "
                                                            f"{c.section}): {str(exc)[:120]}"))
                continue
            if theirs != elements:
                report.append((sid, "duplicate-differs", f"{c.printed} (section {c.section}) prints "
                               f"{compact(theirs)[:160]!r}; primary {cap.printed} (section {cap.section}) prints "
                               f"{compact(elements)[:160]!r}"))
        triggers = [fold["trigger"]] if fold else triggers
        structures[sid] = validate_names({"structure": sid, "version": ver, "triggers": triggers, "elements": elements,
                                          "citation": citation(ver, cap, others, overrides, sid) + name_citation(log)})
        for entry in log:
            where = f"[{', '.join(str(p) for p in entry['path'])}]"
            if entry["source"] == "synthesised":
                report.append((sid, "no-bundle-name", f"{entry['name']} at {where}: {entry['cite']}"))
            else:
                report.append((sid, "name", f"{entry['source']} {entry['name']} at {where}: {entry['cite']}"))
            if entry["shadowed"]:
                report.append((sid, "error", f"groupNames entry at path {where} shadows the bundle name {entry['name']}"))
        tree = bundles.tree(ver, sid) if bundles.available(ver) else None
        report += [(sid, "bundle-differs", d) for d in (_v2xml.differences(elements, tree) if tree else [])]
        if (ver, sid) in bundles.defects:
            report.append((sid, "bundle-differs", f"HL7-xml v{ver}/{sid}.xsd is unreadable: {bundles.defects[(ver, sid)]}"))
        report.append((sid, "parsed", f"{len(entries)} caption(s)"))
    for sid in sorted(prints):     # every printed structure, parsed or not, claims its triggers
        fold = folds.get(sid)
        for trig in [fold["trigger"]] if fold else dict.fromkeys(
                f"{c.code}^{v}" for c, _, _ in prints[sid] for v in c.events):
            owner.setdefault(trig, []).append(sid)
    report += shared_triggers(ver, owner, overrides, full)
    report += reconcile_0354(ver, table_ver, table, prints)
    for g in overrides["groupNames"]:
        key = (g["version"], g["structure"], tuple(g["path"]))
        if g["version"] == ver and key not in used and (only is None or g["structure"] in only):
            report.append((g["structure"], "error", f"unused groupNames entry at path {g['path']}"))
    if full:
        report += [(x, "error", f"exclusions entry for section {x} matches no caption")
                   for x in sorted(set(excluded) - used_exclusions)]
        report += [(e["structure"], "error", f"errata entry ({e['where']}) {e['printed']!r} matches nothing")
                   for e in errata if id(e) not in used_errata]
    return structures, report, count


def shared_triggers(ver, owner, overrides, full):
    """One shared-trigger row per trigger the print puts under several structures, declared or
    not; a declared sharedTriggers entry that no longer occurs is an error (on a full read)."""
    declared = {e["trigger"]: e for e in overrides["sharedTriggers"] if e["version"] == ver}
    rows = []
    for trig, sids in sorted(owner.items()):
        if len(sids) < 2:
            continue
        entry = declared.get(trig)
        state = ("declared" if entry and sorted(entry["structures"]) == sorted(sids) else
                 "declared with other structures" if entry else "undeclared")
        rows.append((trig, "shared-trigger", f"{', '.join(sids)} ({state})"))
    if full:
        rows += [(t, "error", "sharedTriggers entry no longer occurs") for t, e in sorted(declared.items())
                 if len(owner.get(t, [])) < 2]
    return rows


def reconcile_0354(ver, table_ver, table, prints):
    """Table 0354 against the captions: a printed structure ID the table lacks
    (0354-missing-row), and a table row no normative print carries (0354-missing-caption)."""
    if not table:
        return [] if ver != "2.3" else [("", "0354-note", "v2.3 prints no Table 0354; IDs resolve through v2.3.1's")]
    if table_ver != ver:
        return []
    codes = {row for row, _, _ in table}
    rows = [(sid, "0354-missing-row", f"printed as {entries[0][0].printed} (section {entries[0][0].section}); "
                                      f"Table 0354 v{ver} has no {sid} row")
            for sid, entries in sorted(prints.items()) if sid not in codes]
    rows += [(row, "0354-missing-caption", f"Table 0354 v{ver} row {row} ({desc[:60]}) has no printed syntax"
                                           + (" (deprecated)" if "eprecated" in desc else ""))
             for row, _, desc in table if row not in prints]
    return rows


def summary(version, structures, report, count):
    """One line per version: captions, structures, parsed, skipped by reason and the P8b-3a
    report classes."""
    def n(status):
        return sum(1 for r in report if r[1] == status)
    skipped = [r for r in report if r[1] == "skipped"]
    reasons = {k: sum(1 for r in skipped if r[2].startswith(k)) for k in ("choice", "unreadable")}
    distinct = len({r[0] for r in report if r[1] in ("parsed", "skipped")})
    return (f"v{version.lstrip('v')}: {count} captions ({n('excluded')} excluded), {distinct} structures, "
            f"{len(structures)} parsed, {len(skipped) + n('needs-structure-id') + n('needs-event')} skipped "
            f"(choice {reasons['choice']}, unreadable {reasons['unreadable']}, "
            f"needs-structure-id {n('needs-structure-id')}, needs-event {n('needs-event')}); "
            f"duplicate-differs {n('duplicate-differs')}, duplicate-unreadable {n('duplicate-unreadable')}; "
            f"0354-missing-row {n('0354-missing-row')}, 0354-missing-caption {n('0354-missing-caption')}; "
            f"shared-trigger {n('shared-trigger')}")


def name_summary(version, report):
    """One line: unprinted names by source and the bundle-differs rows (P8b-2b)."""
    names = [r[2].split(" ")[0] for r in report if r[1] == "name"]
    misses = sum(1 for r in report if r[1] == "no-bundle-name")
    differs = sum(1 for r in report if r[1] == "bundle-differs")
    return (f"v{version.lstrip('v')} names: {names.count('v2xml')} v2xml, {names.count('v2xml-v2.4')} v2xml-v2.4, "
            f"{misses} synthesised, {names.count('override')} override; {differs} bundle-differs")


def pdf_texts(version):
    out = []
    # Reading order is chapter order: v2.3 names its files CH1 to CH12, so sort numerically.
    key = lambda p: [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", os.path.basename(p))]
    for pdf in sorted(glob.glob(os.path.join(REPO, "docs/standards", CHAPTERS[version])), key=key):
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
    bundles = Bundles.from_disk()
    failed, tsv = False, []
    for version in versions:
        if version not in ERAS:
            ap.error(f"unknown version {version}")
        if version in ERAS_PENDING:
            print(f"{version}: not read yet ({ERAS_PENDING[version]})")
            failed |= bool(args.check or args.write)
            continue
        source = BUNDLES_DERIVED.get(version, version)
        if not bundles.available(source[1:]):
            print(f"{version}: no HL7 v2.xml bundle at docs/XML-schemas/{BUNDLES[source]} (group names need it)")
            failed = True
            continue
        texts = pdf_texts(version)
        if not texts:
            print(f"{version}: no PDFs under docs/standards/{CHAPTERS[version]}")
            failed = True
            continue
        target = os.path.join(STRUCTURES, version)
        only = (set(args.only.split(",")) if args.only else None if not (args.check or args.write) else
                {f[:-5] for f in os.listdir(target) if f.endswith(".json")} if os.path.isdir(target) else set())
        structures, report, count = extract_version(version, texts, overrides, only, bundles, full=True)
        print(summary(version, structures, report, count))
        print(name_summary(version, report))
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
