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
the print, report only (bundle-differs rows); the print stays normative. Choice notation
(< X | Y >, P8b-6) is read in every row layout into a choice element, named when the print
names it; a choice whose alternatives are a placeholder ("etc.", "...") is skipped under ruling
G6 (unreadable: placeholder (G6)). Every caption form is read (P8b-3a, see
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
# A01, C01-C08, PCG,PCH,PCJ, S12-S24,S26,S27, varies; "S12-S24, S26" (v2.5.1 CH10's ACK caption)
_EVT = r"[A-Za-z0-9]+(?:(?:-|, ?)[A-Za-z0-9]+)*"
_SID = r"[A-Z][A-Z0-9]{2}(?:_[A-Za-z0-9]{3})?"
CAPTION = re.compile(r"^(\s*)([A-Z][A-Z0-9]{2})\^(" + _EVT + r")\^(" + _SID + r")"
                     r"\s+(\S.*)$")   # a caption carries a title; a bare CODE^EVT^STRUCT is a table cell
# CODE^EVT with a title two or more spaces away (v2.3.1; v2.4's two-part captions): the structure
# ID comes from Table 0354. A line holding "|" or "<cr>" is an example message, never a caption.
TWO_PART = re.compile(r"^(\s*)([A-Z][A-Z0-9]{2})\^(" + _EVT + r")(\s{2,})(\S.*)$")
# v2.7.1 and v2.8.2: "CODE^EVT^STRUCT: title" on its own line, then a "Segments Description" row;
# v2.8.2 CH07 prints "ACK^R01^ACK : title" with a space before the colon (P8b-11: read as a caption,
# so the ORU_R01 and ORU_R30 rows end there instead of running on into the acknowledgment).
COLON = re.compile(r"^(\s*)([A-Z][A-Z0-9]{2})\^(" + _EVT + r")\^(" + _SID + r") ?:\s+(\S.*)$")
# "Descriptions" in v2.8.2 CH04 4.16.6 and 4.16.7 (QBP_O33, RSP_O33; P8b-11).
COLUMNS = re.compile(r"^(\s*)Segments\s{2,}(Descriptions?)\b")
# v2.3: the message code alone, a title and "Chapter"; the event is in the section title.
CODE_ONLY = re.compile(r"^(\s*)([A-Z][A-Z0-9]{2})(\s{3,})(\S.*?)\s{2,}Chapter\s*$")
TITLE_EVENTS = re.compile(r"\(\s*events?\s+([A-Z0-9]{3}(?:\s*(?:,|and|&|-|to)\s*[A-Z0-9]{3})*)\s*\)", re.I)
FOOTNOTE = re.compile(r"^\s*\d{1,2}\s*$")      # a footnote digit on a line of its own (P8b-2a review)
HEADING = re.compile(r"^(\d+[A-Z]?(?:\.[A-Z])?(?:\.\d+)+)\s+(\S.*\S)\s*$")   # 3.3.1, 4A.3.20, 2.B.7.5
# v2.7.1 and v2.8.2 indent many section headings (v2.8.2 CH04A 4A.3.13, CH08, CH16 16.3.9; P8b-11).
# Indented by up to 20 columns (CH16 16.3.7 at 17); the title starts with a capital, and the number
# must open with the chapter of the file it is read from, so a numbered prose line is not a heading.
INDENTED_HEADING = re.compile(r"^(\s{1,20})(\d+[A-Z]?(?:\.[A-Z])?(?:\.\d+)+)\s+([A-Z].*\S)\s*$")


def heading(line, era, source=""):
    """The section heading match for a line, in era's layout: (number, title) or None."""
    h = HEADING.match(line)
    if h or era != "caret-colon":
        return h and (h.group(1), h.group(2))
    h = INDENTED_HEADING.match(line)
    chapter = re.search(r"_CH(\d+[A-Z]?)_", os.path.basename(source))
    if not h or not chapter or h.group(2).split(".")[0] != chapter.group(1).lstrip("0"):
        return None
    return h.group(2), h.group(3)
PAGE = re.compile(r"\bPage\s+(\d+[A-Z]?-\d+|\d+)\b")   # v2.7.1 and v2.8.2 number pages per chapter
GROUP_MARK = re.compile(r"^---\s*([A-Z][A-Z0-9_]*)\s+((?i:begin|end))\b")   # "--- VISIT End" (v2.5.1 CSU_C09)
# A mark as printed, misprints included ("--- INVOICE INFORMATION end", v2.6 EHC_E01): parse reads
# it through GROUP_MARK after any cited group-mark erratum, and an unreadable one is an error.
MARK_LIKE = re.compile(r"^---\s*[A-Z][A-Za-z0-9_ /+-]*?\s+(?i:begin|end)\b")
TOKEN = re.compile(r"\s+|[\[\]{}<>|]|[A-Z][A-Z0-9]{2}(?![A-Za-z0-9_])|\.\.\.|…|.")
TRIGGER = re.compile(r"^[A-Z][A-Z0-9]{2}\^([A-Z0-9]{3}|\*)$")


class UnknownNotation(Exception):
    """Notation the model cannot represent: placeholder text, unbalanced brackets, a stray
    group mark."""


PLACEHOLDER = re.compile(r"^(?:etc\.?|\.\.\.|…)$")   # "< OBR | etc. >" (v2.5.1 CH12): ruling G6


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
        head = f"{self.code}^{self.event}" if self.event else self.code     # v2.3's code-alone caption
        return head + (f"^{self.structure}" if self.id_source == "printed" else "")


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
    for part in (p.strip() for p in text.split(",")):
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
    # A "title" that is itself CODE^EVT is a grid row (v2.5.1 CH05 5.10.3's query/response
    # pairs, "EQQ^Q04   TBR^R08   Tabular"), not a caption.
    if m and "|" not in line and "<cr>" not in line.lower() and not re.match(r"[A-Z][A-Z0-9]{2}\^", m.group(5)):
        return (len(m.group(1)), m.group(2), m.group(3), "", m.start(5), m.group(5))
    return None


# A caret caption whose event list or structure ID wraps onto the next line, the title staying on
# the first ("SIU^S12-S24," then "S26^SIU_S12", v2.5.1 CH10 10.4.1; "PPG^PCG,PCH,PCJ^PPG_" then
# "PCG", v2.5.1 CH12 12.3.4).
WRAPPED = re.compile(r"^(\s*)([A-Z][A-Z0-9]{2}\^[A-Za-z0-9,\-^_]*[,\-^_])(\s{2,})(\S.*)$")
WRAP_TAIL = re.compile(r"^(\s*)([A-Za-z0-9,\-^_]+)\s*$")


def match_wrapped(lines, i, era):
    """(match_caption's tuple, extra lines) for the caption at line i: extra is 1 when the
    caption wraps onto line i + 1 (WRAPPED), and the title column stays the first line's."""
    line = lines[i].replace("\f", "")
    m = match_caption(line, era)
    if m or era not in ("caret", "table-0354") or i + 1 >= len(lines):
        return m, 0
    w = WRAPPED.match(line.translate(_DASHES))
    t = w and WRAP_TAIL.match(lines[i + 1].replace("\f", "").translate(_DASHES))
    if not t or abs(len(t.group(1)) - len(w.group(1))) > 2:
        return None, 0
    head = w.group(1) + w.group(2) + t.group(2)
    m = match_caption(head + "  " + w.group(4), era)
    if not m or not m[3]:
        return None, 0
    return (m[0], m[1], m[2], m[3], len(w.group(1)) + len(w.group(2)) + len(w.group(3)), m[5]), 1


def captions(lines, era="caret", source="", bare=frozenset()):
    """Every caption occurrence, with its section, chapter and page. A caption repeated after a
    page break inside its own table is still listed here; syntax_rows records it as a repeat.
    Eras (ADR-019 caption-form table): caret (v2.4 to v2.6, CODE^EVT^STRUCT with the title on
    the line, or CODE^EVT); table-0354 (v2.3.1, mostly CODE^EVT); caret-colon (v2.7.1, v2.8.2,
    "CODE^EVT^STRUCT: title" then a Segments/Description column row); section-title (v2.3, the
    code alone, the event in the section title). A caption needs no Status or Chapter header:
    v2.4 prints 34 three-part captions without one, every one a CH04/CH05 query or response
    grammar example or a Z-event, each excluded by a cited exclusions entry (ruling G7). bare:
    message codes whose code-alone caption (v2.3's form) is also read in the other eras, with no
    event: the codes a triggerFolds entry folds into one structure (v2.3.1 CH02's general ACK)."""
    if era not in ("caret", "table-0354", "caret-colon", "section-title"):
        raise ValueError(f"unknown caption era {era!r}")
    pages = page_labels(lines)
    found, section, section_title = [], "", ""
    for i, raw in enumerate(lines):
        line = raw.replace("\f", "")
        if FURN.search(line):
            continue
        h = heading(line, era, source)
        if h and not re.search(r"\.{5,}", line):
            section, section_title = h[0], _title(h[1])
            # A title that wraps inside its parentheses ("(events" / "PC1, PC2)") continues
            # on the next non-blank line.
            nxt = next((x.replace("\f", "") for x in lines[i + 1:i + 4] if x.strip() and not FURN.search(x)), "")
            if section_title.count("(") > section_title.count(")") and nxt.strip().count(")"):
                section_title = _title(section_title + " " + nxt)
            continue
        m, extra = match_wrapped(lines, i, era)
        if not m and era != "section-title" and bare:
            b = CODE_ONLY.match(line.translate(_DASHES))
            m = b and b.group(2) in bare and (len(b.group(1)), b.group(2), "", "", b.start(4), b.group(4))
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
            for j in range(i + 1 + extra, min(i + 4 + extra, len(lines))):
                nxt = split_row(lines[j], desc_col)
                if nxt is None or FURN.search(lines[j]) or not "".join(nxt):
                    continue
                if not nxt[0] and nxt[1]:
                    title = (title + " " + re.split(r"\s{2,}", nxt[1])[0]).strip()
                break
        events = (title_events(section_title) if era == "section-title" else
                  expand_events(event) or [] if event else [])
        if era == "section-title":
            event = ",".join(events)
        found.append(Caption(code, event, structure, title, i + extra, section.split(".")[0], section,
                             section_title, pages[i], code_col, desc_col, source, era=era, events=events,
                             id_source="printed" if structure else "0354"))
    return found


_NOTATION = re.compile(r"^(?:[\[\]{}<>|]|[A-Z][A-Z0-9]{2}(?![A-Za-z0-9_])|\.\.\.|…)")
# A segment ID then a word in prose; a depth-0 line after the table that starts with a segment ID but
# goes on in prose ("QPD Input Parameter Specification", v2.8.2 CH04A RSP_K31) ends the table (P8b-11).
_PROSE = re.compile(r"^[A-Z][A-Z0-9]{2}\s+[A-Z]?[a-z]+\b")


def syntax_rows(lines, caption):
    """The syntax rows of caption's table, in order. Records page-break repeats of the caption
    and the page of the last row on the caption. A repeated Segments/Description row (v2.7.1,
    v2.8.2) resets the columns; a footnote digit on a line of its own is furniture, and one at
    the left margin opens the page-foot footnotes, read as furniture up to the page footer."""
    pages = page_labels(lines)
    rows, depth, choices, foot, placeholder = [], 0, 0, False, None
    code_col, desc_col = caption.code_col, caption.desc_col
    caption.end_page = caption.page
    skip = 0
    start = caption.line + 1
    if caption.era == "caret-colon":
        # A title wrapped onto a line of its own before the Segments row (v2.8.2 CH04 4.4.11.1
        # ORL^O36^ORL_O36 "(Patient Required)"; P8b-11): the rows start after that row.
        start = next((j for j in range(start, min(start + 4, len(lines)))
                      if COLUMNS.match(lines[j].replace("\f", ""))), start)
    for i in range(start, len(lines)):
        line = lines[i].replace("\f", "")
        if skip:
            skip -= 1
            continue
        if FURN.search(line):
            foot = False
            continue
        if foot or not line.strip() or FOOTNOTE.match(line):
            foot = foot or bool(re.match(r"^\d{1,2}\s*$", line))
            continue
        m, skip = match_wrapped(lines, i, caption.era)
        if m:
            if (m[1], m[2] if caption.era != "section-title" else caption.event, m[3]) != caption.key:
                break
            caption.repeats.append(i + skip)    # the line captions() lists a wrapped caption at
            if caption.era != "caret-colon":
                # A repeat indented three or more columns past the caption keeps the caption's
                # row column (v2.5.1 ADT^A31^ADT_A05 at 3.3.31: the caption at column 5, its
                # repeat at 8, the rows after it at 4).
                code_col, desc_col = caption.code_col if m[0] - caption.code_col > 2 else m[0], m[4]
            continue
        cols = COLUMNS.match(line)
        if cols:
            code_col, desc_col = len(cols.group(1)), cols.start(2)
            continue
        if heading(line, caption.era, caption.source):
            break
        indent = len(line) - len(line.lstrip())
        if indent < code_col - 3:
            if rows or not re.match(r"MSH\b", line.strip()):
                break
            # The table's first row (MSH) left of an indented caption (v2.6 ADT^A31^ADT_A05 at
            # 3.3.31: the caption at column 7, its rows at 3): the rows set the column.
            code_col = indent
        cells = split_row(line, desc_col)
        if cells is None:
            if depth == 0:
                break
            raise UnknownNotation(f"line {i + 1}: prose inside an open group: {line.strip()[:60]!r}")
        left, desc = cells
        if not left and choices > 0 and PLACEHOLDER.match(desc.strip()):
            # The alternatives are not enumerated (v2.5.1 CH12 "< OBR | etc. >"; the bundle has
            # anyHL7Segment): expanded only by a cited G6 entry, never guessed. Read on to the end
            # of the table first, so its page-break repeats of the caption are consumed.
            placeholder = placeholder or f"line {i + 1}: placeholder (G6): {desc.strip()!r} among a choice's alternatives"
            continue
        if not left:
            # "--- NAME" with "begin" or "end" wrapped onto the description's next line.
            if rows and re.fullmatch(r"---\s*[A-Z][A-Za-z0-9_ /]*", rows[-1].desc) and re.match(r"(?i)(begin|end)\b", desc):
                rows[-1].desc += " " + desc
            elif rows and (MARK_LIKE.match(desc) if depth == 0 else GROUP_MARK.match(desc)):
                # A group mark with an empty syntax cell: inside a group (v2.5.1 MDM_T02 '---
                # COMMON_ORDER end' with no '}]') parse reads an end only through a cited
                # group-close erratum; a begin/end pair with no brackets (v2.6 CH16 '---
                # INVOICE_INFORMATION begin') is a required, non-repeating named group (P8b-10).
                rows.append(Row("", desc, i, pages[i]))
            continue
        if depth == 0 and rows and (not _NOTATION.match(left) or _PROSE.match(left)):
            break       # prose or another table's header after the table (v2.5.1 RSP_K23's QPD field table)
        depth += sum(left.count(c) for c in "[{<") - sum(left.count(c) for c in "]}>")
        choices += left.count("<") - left.count(">")
        rows.append(Row(left, desc, i, pages[i]))
        caption.end_page = pages[i]
    if placeholder:
        raise UnknownNotation(placeholder)
    return rows


def _corrected(desc, marks, used):
    """A row's description with a cited group-mark erratum applied (printed name to intended)."""
    for printed, intended in (marks or {}).items():
        if re.match(r"^---\s*" + re.escape(printed) + r"\s+(?i:begin|end)\b", desc):
            desc = desc.replace(printed, intended, 1)
            if used is not None:
                used.add(printed)
    return desc


def _cell_fixed(row, fixes, used):
    """A row with a cited syntax-cell erratum applied: printed and intended are the row's cell then
    its description, spaces collapsed; only the cell may differ."""
    printed = " ".join(f"{row.left} {row.desc}".split())
    e = fixes.get(printed)
    if not e:
        return row
    desc = " ".join(row.desc.split())
    if not e["intended"].endswith(" " + desc if desc else ""):
        raise UnknownNotation(f"syntax-cell erratum for {printed!r} changes the description")
    used.add(id(e))
    return Row(e["intended"][:len(e["intended"]) - len(desc)].strip(), row.desc, row.line, row.page)


def parse(rows, marks=None, used=None):
    """Elements from syntax rows, by bracket balance. A group the print leaves unnamed has
    "group": None until name_groups resolves it. A choice (P8b-6) is "<", alternatives split
    by "|", then ">", in any row layout (inline, one alternative per row, or each token on its
    own row); "--- NAME begin" on its "<" row names it (v2.7.1 on). marks maps a misprinted group-mark name to the
    intended one (a cited errata entry); used receives every printed name it corrected."""
    marks = marks or {}
    root = {"kind": "root", "children": [], "name": None}
    stack = [root]
    for row in rows:
        if not row.left:
            # A mark row with an empty syntax cell. "--- NAME begin" ... "--- NAME end" with no
            # brackets is a required, non-repeating named group (CH02 2.5.2: "A segment group may
            # be required or optional and might or might not repeat"; v2.6 CH16, P8b-10). An end
            # that closes no such group is skipped: a group-close erratum fills the cell (MDM_T02).
            desc = _corrected(row.desc, marks, used)
            mark = GROUP_MARK.match(desc)
            if not mark:
                raise UnknownNotation(f"group mark not read: {desc[:50]!r}")
            if mark.group(2).lower() == "begin":
                node = {"kind": "=", "children": [], "name": mark.group(1)}
                stack[-1]["children"].append(node)
                stack.append(node)
            elif stack[-1]["kind"] == "=" and stack[-1]["name"] == mark.group(1):
                stack.pop()
            continue
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
            elif tok == "<":
                node = {"kind": "<", "children": [], "alts": [], "name": None}
                stack[-1]["children"].append(node)
                stack.append(node)
                opened.append(node)
            elif tok in "|>":
                if stack[-1]["kind"] != "<":
                    raise UnknownNotation(f"{tok!r} outside a choice in {row.left!r}")
                stack[-1]["alts"].append(stack[-1]["children"])
                stack[-1]["children"] = []
                if tok == ">":
                    closed.append(stack.pop())
            elif re.fullmatch(r"[A-Z][A-Z0-9]{2}", tok):
                stack[-1]["children"].append({"kind": "seg", "id": tok})
            elif tok in ("...", "…"):
                raise UnknownNotation(f"placeholder (G6): {row.left!r}")
            else:
                raise UnknownNotation(f"not notation: {row.left!r}")
        desc = _corrected(row.desc, marks, used)
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
    if node["kind"] == "<":
        return _choice(node, {"<"}, [node["name"]] if node["name"] else [])
    # Nested brackets around one child are one element: [{X}], {[X]} and [ { A B } ] (ADR-019:
    # min 0 if any [ ], max null if any { }).
    kinds, names = set(), []
    while True:
        kinds.add(node["kind"])
        if node["name"]:
            names.append(node["name"])
        only = node["children"][0] if len(node["children"]) == 1 else None
        # Two printed names are two groups, nested: never merge them; nor a named group into
        # the choice it holds (the group, not the choice, carries the name).
        # A bracketless named group ("=", P8b-10) is required: never merged into the brackets it holds.
        if (only is not None and only["kind"] != "seg" and node["kind"] != "="
                and not (names and (only["name"] or only["kind"] == "<"))):
            node = only
            continue
        break
    if node["kind"] == "<":
        return _choice(node, kinds, names)
    if not node["children"]:
        raise UnknownNotation("an empty group")
    bounds = {"min": 0 if "[" in kinds else 1, "max": None if "{" in kinds else 1}
    if len(node["children"]) == 1 and not names:
        return {"segment": node["children"][0]["id"], **bounds}
    return {"group": names[0] if names else None, "nameSource": "printed" if names else None,
            **bounds, "elements": [_element(c) for c in node["children"]]}


def _choice(node, kinds, names):
    """A choice element: [ ] around it makes it optional, { } repeating (as for a group). An
    alternative of several elements (CH02 2.12.1's "<OBR [{NTE}] | RQD | ...>", a choice of
    segment groups) is an unnamed group, named like any unnamed printed group by name_groups."""
    if any(not alt for alt in node["alts"]):
        raise UnknownNotation("an empty alternative in a choice")
    if len(node["alts"]) < 2 and names:
        # "< QPD RCP >" named QUERY_INFORMATION (v2.8.2 CH16; v2.6 SDR_S31): CH02 defines a choice
        # by "|" between alternatives, so with none the print is a required sequence: a NAMED
        # REQUIRED GROUP (P8b-6 ruling); the bundle's one-alternative-each reading is reported.
        bounds = {"min": 0 if "[" in kinds else 1, "max": None if "{" in kinds else 1}
        return {"group": names[0], "nameSource": "printed", **bounds,
                "elements": [_element(c) for c in node["alts"][0]]}
    if len(node["alts"]) < 2:
        # Unnamed, the print gives the group no name and the bundle reads a choice. Not guessed.
        raise UnknownNotation(f"a choice with one alternative (no '|') around {len(node['alts'][0])} element(s): "
                              "the print reads as a sequence, HL7 v2.xml as a choice of each member; needs a ruling")
    bounds = {"min": 0 if "[" in kinds else 1, "max": None if "{" in kinds else 1}
    name = names[0] if names else None
    alternatives = [_element(alt[0]) if len(alt) == 1 else
                    {"group": None, "nameSource": None, "min": 1, "max": 1, "elements": [_element(c) for c in alt]}
                    for alt in node["alts"]]
    return {"choice": name, "nameSource": "printed" if name else None, **bounds, "alternatives": alternatives}


def name_groups(elements, version, structure, overrides, used=None, path=(), bundles=None, log=None, taken=None):
    """Name every unnamed group, top down (a child's parent path uses its parent's resolved
    name): the HL7 v2.xml bundle, else an overrides groupNames entry, else <FIRSTSEG>_GROUP.
    log receives one entry per resolved name: {path, name, source, cite, miss, shadowed}."""
    bundles = bundles if bundles is not None else Bundles()
    if taken is None:
        taken = {g["group"] for _, g in _v2xml.groups(elements) if g["group"]}
    for index, element in enumerate(elements):
        if "alternatives" in element:     # a choice: the bundle names it CHOICE when the print does not
            name_groups(element["alternatives"], version, structure, overrides, used,
                        tuple(path) + (element["choice"] or "CHOICE",), bundles, log, taken)
            continue
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
    if "alternatives" in element:     # P8b-6: {"choice": NAME or null, "nameSource" (named), ...}
        source = f'"nameSource": "{element["nameSource"]}", ' if element["choice"] else ""
        head = (f'{indent}{{ "choice": {json.dumps(element["choice"])}, {source}"min": {element["min"]}, '
                f'"max": {json.dumps(element["max"])}, "alternatives": [')
        body = ",\n".join(render_element(e, indent + "  ") for e in element["alternatives"])
        return f"{head}\n{body}\n{indent}]}}"
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
    # An optional "caption" (as printed) narrows an exclusion to that one caption of the section,
    # so a normative print beside a template stays read (P8b-10: CH08 8.4.3 MFK^M14^MFK_M01).
    "exclusions": {"version", "section", "citation"},
    # A print typo read as the intended text: in a caption (CODE^EVT as printed), a group mark
    # ("--- NAME begin/end"), or a Table 0354 row (its code or an event in its description); a
    # group-close erratum supplies the syntax cell ("}]") a printed "--- NAME end" row leaves empty;
    # a syntax-cell erratum corrects a printed cell, the row given as cell then description with
    # runs of spaces collapsed ("{ [ CTD } ] Contact Data"), the description unchanged (P8b-10).
    "errata": {"version", "where", "structure", "printed", "intended", "citation"},
    # A trigger printed under several structures (pre-flight B6); reported, never modelled here.
    "sharedTriggers": {"version", "trigger", "structures", "citation"},
    # Two normative prints of one structure ID that disagree: the LOOSER print (the one that
    # accepts every message the other accepts) is primary, cited to both (P8b-9 ruling; ADR-019
    # primary-print amendment). primary and stricter are the captions as printed.
    "primaryPrints": {"version", "structure", "primary", "stricter", "citation"},
    # Two normative prints of one structure ID that are incomparable (neither accepts every message
    # the other accepts): the committed structure is their UNION, aligned by segment or group name
    # (P8b-10 ruling, v2.6 RSP_K21; ADR-019 addendum). prints are the two captions as printed, the
    # first the primary (cited first); prints that do not align leave the structure unmodelled.
    "unionPrints": {"version", "structure", "prints", "citation"},
}
ERRATA_WHERE = ("caption", "group-mark", "table-0354", "group-close", "syntax-cell")


def validate_overrides(data):
    if set(data) != set(_OVERRIDE_KEYS):
        raise OverridesError(f"top-level keys {sorted(data)}, expected {sorted(_OVERRIDE_KEYS)}")
    for kind, keys in _OVERRIDE_KEYS.items():
        for entry in data[kind]:
            if kind == "errata" and entry.get("where") not in ERRATA_WHERE:
                raise OverridesError(f"errata entry where {entry.get('where')!r}, expected one of {ERRATA_WHERE}")
            if kind == "errata" and entry.get("printed") == entry.get("intended"):
                raise OverridesError(f"errata entry for {entry.get('structure')}: printed equals intended")
            if kind == "unionPrints" and len(set(entry.get("prints", []))) != 2:
                raise OverridesError(f"unionPrints entry for {entry.get('structure')} needs two distinct prints")
            if kind == "sharedTriggers" and len(set(entry.get("structures", []))) < 2:
                raise OverridesError(f"sharedTriggers entry {entry.get('trigger')} names fewer than two structures")
            if set(entry) != keys and not (kind == "exclusions" and set(entry) == keys | {"caption"}):
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
        if "alternatives" in e:
            inner = (f"{e['choice']}: " if e["choice"] else "") + "<" + " | ".join(compact([a]) for a in e["alternatives"]) + ">"
        else:
            inner = e["segment"] if "segment" in e else f"{e['group']}: " + compact(e["elements"])
        if e["max"] is None:
            inner = "{" + inner + "}"
        if e["min"] == 0:
            inner = "[" + inner + "]"
        out.append(inner)
    return " ".join(out)


def _key(e):
    return e["segment"] if "segment" in e else ("choice", e["choice"]) if "alternatives" in e else ("group", e["group"])


def _segments(e):
    if "segment" in e:
        return {e["segment"]}
    return set().union(*(_segments(x) for x in e.get("elements", e.get("alternatives", []))))


def union(a, b, path="top level"):
    """The union of two prints' elements (unionPrints, P8b-10 ruling): aligned by segment or group
    name in order, each aligned element takes the lesser min and the greater max; an element in one
    print only becomes optional. UnknownNotation when the prints do not align: a different order, a
    repeated name at a level where they differ, a group in one where the other has a segment, or two
    choices whose alternatives differ."""
    ka, kb = [_key(e) for e in a], [_key(e) for e in b]
    if ka != kb and (len(set(ka)) < len(ka) or len(set(kb)) < len(kb)):
        raise UnknownNotation(f"the prints do not align at {path}: a name repeats at that level")
    out, only_a, only_b, i, j = [], [], [], 0, 0
    while i < len(a) or j < len(b):
        if i < len(a) and j < len(b) and ka[i] == kb[j]:
            x, y = a[i], b[j]
            merged = {**x, "min": min(x["min"], y["min"]),
                      "max": None if None in (x["max"], y["max"]) else max(x["max"], y["max"])}
            if "elements" in x:
                merged["elements"] = union(x["elements"], y["elements"], f"group {x['group']}")
            elif "alternatives" in x and x["alternatives"] != y["alternatives"]:
                raise UnknownNotation(f"the prints do not align at {path}: choice {x['choice']} differs")
            out.append(merged)
            i, j = i + 1, j + 1
        elif i < len(a) and ka[i] not in kb[j:]:
            out.append({**a[i], "min": 0})
            only_a.append(a[i])
            i += 1
        elif j < len(b) and kb[j] not in ka[i:]:
            out.append({**b[j], "min": 0})
            only_b.append(b[j])
            j += 1
        else:
            raise UnknownNotation(f"the prints do not align at {path}: the order differs")
    if any(_segments(x) & _segments(y) for x in only_a for y in only_b):
        raise UnknownNotation(f"the prints do not align at {path}: a group in one where the other prints its segments")
    return out


def _primary(sid, entries, fold):
    """The primary print (ADR-019 addendum, P8b-3a): exclusions are already gone; a triggerFolds
    entry names it; else the first print in reading order whose caption is the defining trigger
    (CODE_EVT equals the structure ID: the chapter that defines the message, not one that only
    reuses it); else the first print in reading order. A Conformance-chapter (CH02B) print is a
    message-profile example and is never primary (P8b-3b). None when no print qualifies: a fold
    whose primary matches no print (stale), or only CH02B prints (exclude them, ruling G7)."""
    if fold:
        return next((k for k, e in enumerate(entries) if not _profile(e[0])
                     and fold["primary"] in (e[0].printed, f"{e[0].code}^{e[0].event}")), None)
    normative = [k for k, e in enumerate(entries) if not _profile(e[0])]
    return next((k for k in normative if any(f"{entries[k][0].code}_{v}" == sid for v in entries[k][0].events)),
                normative[0] if normative else None)


def _profile(cap):
    """Whether a caption sits in the Conformance chapter (CH02B, sections 2.B.x)."""
    return cap.section.startswith("2.B.") or "CH02B" in os.path.basename(cap.source).upper()


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
    folds = {f["structure"]: f for f in overrides["triggerFolds"] if f["version"] == ver}
    # A fold onto CODE^* whose structure ID is the code itself (ACK): every caption of that code
    # is the one structure, so it needs no event and no Table 0354 row (v2.3 and v2.3.1 print no
    # ACK row; their general acknowledgment caption prints the code alone).
    general = {sid for sid, f in folds.items() if f["trigger"] == f"{sid}^*"}
    prints, count, report = {}, 0, []
    for source, lines in texts:
        consumed = set()
        for cap in captions(lines, era, source, bare=general):
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
            scope = excluded.get(cap.section, {}).get("caption")
            if cap.section in excluded and scope in (None, cap.printed):     # a non-normative print (ruling G7)
                used_exclusions.add(cap.section)
                report.append((cap.structure or f"{cap.code}^{cap.event}", "excluded", where))
                continue
            if cap.code in general and not cap.structure:
                cap.structure = cap.code
            if not cap.events and cap.code not in general:
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
    marks = {}
    for e in errata:
        if e["where"] == "group-mark":
            marks.setdefault(e["structure"], {})[e["printed"]] = e
    closes = {}
    for e in errata:
        if e["where"] == "group-close":
            closes.setdefault(e["structure"], {})[e["printed"]] = e
    cells = {}
    for e in errata:
        if e["where"] == "syntax-cell":
            cells.setdefault(e["structure"], {})[e["printed"]] = e
    structures, used, owner, bundle_rows = {}, set(), {}, []

    def read(sid, rows, error, log=None, names_used=None):
        if error:
            raise error
        rows = [Row(closes[sid][r.desc]["intended"], r.desc, r.line, r.page) if not r.left and r.desc in closes.get(sid, {})
                else r for r in rows]
        used_errata.update(id(closes[sid][r.desc]) for r in rows if r.desc in closes.get(sid, {}))
        rows = [_cell_fixed(r, cells[sid], used_errata) if r.left and sid in cells else r for r in rows]
        seen = set()
        tree = parse(rows, {k: v["intended"] for k, v in marks.get(sid, {}).items()}, seen)
        # P8b-3b: an empty print, or rows that run on into the next table (a second top-level
        # MSH, e.g. the acknowledgment printed after it), is a reader gap, never a structure.
        if not tree:
            raise UnknownNotation("no syntax rows read under the caption")
        if sum(1 for e in tree if e.get("segment") == "MSH") > 1:
            raise UnknownNotation("a second top-level MSH: the rows run on into the next table")
        for printed in seen:
            used_errata.add(id(marks[sid][printed]))
        return name_groups(tree, ver, sid, overrides, names_used, bundles=bundles, log=log)

    primaries = {e["structure"]: e for e in overrides["primaryPrints"] if e["version"] == ver}
    unions = {e["structure"]: e for e in overrides["unionPrints"] if e["version"] == ver}
    for sid in sorted(prints):
        entries = prints[sid]
        fold = folds.get(sid)
        k = _primary(sid, entries, fold)
        chosen = primaries.get(sid)
        joined = unions.get(sid)
        if joined:
            # The cited union of two incomparable prints; the first listed is the primary.
            k = next((j for j, e in enumerate(entries) if e[0].printed == joined["prints"][0]), None)
            if k is None or not any(e[0].printed == joined["prints"][1] for e in entries):
                report.append((sid, "error", f"unionPrints entry {joined['prints']!r} matches no print"))
                continue
        if chosen:
            # The cited looser print overrides the primary-print rule; both prints must exist.
            k = next((j for j, e in enumerate(entries) if e[0].printed == chosen["primary"]), None)
            if k is None or not any(e[0].printed == chosen["stricter"] for e in entries):
                report.append((sid, "error", f"primaryPrints entry {chosen['primary']!r} / {chosen['stricter']!r} "
                                             "matches no print"))
                continue
        if k is None and fold and not full:     # a partial read may lack the fold's primary print
            k = next((j for j, e in enumerate(entries) if not _profile(e[0])), None)
        if k is None:
            report.append((sid, "error", f"triggerFolds primary {fold['primary']!r} matches no normative print" if fold
                           else "only Conformance-chapter (CH02B) prints: exclude them (ruling G7)"))
            continue
        entries = [entries[k]] + entries[:k] + entries[k + 1:]
        cap, rows, error = entries[0]
        try:
            if not all(TRIGGER.match(f"{cap.code}^{v}") for v in cap.events) and not fold:
                raise UnknownNotation(f"trigger event {cap.event!r} is not CODE^EVT")
            if not (cap.page and cap.end_page and cap.section):
                raise UnknownNotation("no page footer or section heading found for the caption")
            log = []
            elements = read(sid, rows, error, log, used)
        except UnknownNotation as exc:
            report.append((sid, "skipped", f"unreadable: {cap.source} line {cap.line + 1}: {exc}"))
            continue
        partner = None
        if joined:
            partner = next(e for e in entries if e[0].printed == joined["prints"][1])
            try:
                theirs = read(sid, partner[1], partner[2])
                before = compact(elements)
                elements = union(elements, theirs)
            except UnknownNotation as exc:
                report.append((sid, "error", f"unionPrints entry {joined['prints']!r}: {exc}; not modelled"))
                continue
            report.append((sid, "union", f"{partner[0].printed} (section {partner[0].section}) prints "
                           f"{compact(theirs)[:160]!r}; {cap.printed} (section {cap.section}) prints "
                           f"{before[:160]!r}; union {compact(elements)[:160]!r}"))
        others, triggers = [], []
        for c, r, e in entries:
            trigs = [f"{c.code}^{v}" for v in c.events]
            if c is not cap and not fold and not set(trigs) <= set(triggers):
                others.append(c)
            triggers += [t for t in trigs if t not in triggers]
            if c is cap or (partner and c is partner[0]):
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
                                          "citation": citation(ver, cap, others, overrides, sid)
                                          + (f" {primaries[sid]['citation']}" if sid in primaries else "")
                                          + (f" {joined['citation']}" if joined else "")
                                          + name_citation(log)})
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
        report += [(sid, "error", "triggerFolds entry matches no caption") for sid in sorted(folds) if sid not in prints]
        report += [(sid, "error", "primaryPrints entry matches no caption") for sid in sorted(primaries) if sid not in prints]
        report += [(sid, "error", "unionPrints entry matches no caption") for sid in sorted(unions) if sid not in prints]
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
    reasons = {"unreadable": sum(1 for r in skipped if r[2].startswith("unreadable")),
               "placeholder": sum(1 for r in skipped if "placeholder (G6)" in r[2])}
    with_choice = sum(1 for s in structures.values() if '"alternatives"' in json.dumps(s))
    distinct = len({r[0] for r in report if r[1] in ("parsed", "skipped")})
    return (f"v{version.lstrip('v')}: {count} captions ({n('excluded')} excluded), {distinct} structures, "
            f"{len(structures)} parsed, {len(skipped) + n('needs-structure-id') + n('needs-event')} skipped "
            f"(unreadable {reasons['unreadable']}, of which placeholder (G6) {reasons['placeholder']}, "
            f"needs-structure-id {n('needs-structure-id')}, needs-event {n('needs-event')}); "
            f"duplicate-differs {n('duplicate-differs')}, duplicate-unreadable {n('duplicate-unreadable')}; "
            f"0354-missing-row {n('0354-missing-row')}, 0354-missing-caption {n('0354-missing-caption')}; "
            f"shared-trigger {n('shared-trigger')}; with a choice {with_choice}")


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
    ap.add_argument("--dump", metavar="DIR", help="write every parsed structure to DIR/v<ver>/<ID>.json, for the "
                    "env-gated lint harness (StructureLintCorpusTests); never under Resources/")
    args = ap.parse_args(argv)
    if args.dump and os.path.realpath(args.dump).startswith(os.path.realpath(os.path.join(REPO, "Resources"))):
        ap.error("--dump must not write under Resources/ (no structure JSON is committed this way)")
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
        if args.dump:
            out = os.path.join(args.dump, version)
            os.makedirs(out, exist_ok=True)
            for sid, structure in structures.items():
                with open(os.path.join(out, f"{sid}.json"), "w", encoding="utf-8") as f:
                    f.write(render(structure))
            print(f"  dumped {len(structures)} structure(s) to {out}")
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
