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
its HL7 v2.xml bundle name (scripts/read-v2xml-bundles.py: nameSource v2xml; v2.3.1 from its own
bundle first, then v2xml-v2.4 through the v2.4 bundle, v2.3's only source), else a cited groupNames entry in Resources/structures/overrides.json (nameSource
override), else <FIRSTSEG>_GROUP (nameSource synthesised, a no-bundle-name report row). Each
non-printed name is cited in the structure citation. The bundle's element tree is compared with
the print, report only (bundle-differs rows); the print stays normative. Choice notation
(< X | Y >, P8b-6) is read in every row layout into a choice element, named when the print
names it. The open order detail (S3-2, ADR-019 S3-1 amendment) is a slot element {"slot": name,
"min", "max": null, "citation"}, read in three printed forms: the CH04 row "Order Detail Segment
OBR, etc." (v2.3, v2.3.1; on its own line, wrapped, or in the description column), the CH12 cell
"[OBR, etc" / "OBR, etc." / "OBR, etc..." (v2.3 to v2.4), and a choice whose last alternative is a
placeholder ("< OBR | etc. >", "..." or "Hxx" described "etc."; v2.5.1 to v2.8.2), which becomes
one slot in place of the whole choice, its listed alternatives named in the citation. The slot
takes the print's place in the parsed sequence, so the brackets around it keep their meaning: the
slot is min 1 (required once its group is present) unless the print brackets the placeholder
alone ("[Order Detail Segment] OBR, etc.", or "[ < OBR | etc. > ]"), then min 0; max is always
null. Its name is the description column's ("Order Detail Segment", ", etc." dropped), else null;
its citation is the structure's (version, chapter, section, title) at the page of the slot's row,
with the print quoted. Every other placeholder stays unreadable under ruling G6 (placeholder
(G6)): an ellipsis row, "[...]", a lone "...", a second placeholder in a choice, or one that is
not the choice's last alternative. Every caption form is read (P8b-3a, see
captions()); exclusions, errata and shared triggers are cited overrides entries; the report
adds duplicate-differs, needs-structure-id, needs-event, shared-trigger and the Table 0354
reconciliation (0354-missing-row, 0354-missing-caption). On a version that prints its own Table
0354 (v2.3.1, P8b-14), a caption the table cannot resolve fails a full read unless a cited
erratum, a declared shared trigger, a captionStructures entry or an unresolvedCaptions entry
settles it.
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

# Table 0354 resolves a v2.3.1 caption that prints no structure ID (CODE^EVT). v2.3 prints no Table
# 0354 and its MSH-9 has no third component (ADR-019 lookup rule 3): its IDs are synthesised CODE_EVT
# from the caption's code and the first event of its section title, and no table is consulted
# (P8b-15; v2.3 borrowed v2.3.1's table, and with it that table's errata, until then).

_DASHES = str.maketrans({"‐": "-", "‑": "-", "–": "-"})
# A01, C01-C08, PCG,PCH,PCJ, S12-S24,S26,S27, varies; "S12-S24, S26" (v2.5.1 CH10's ACK caption)
_EVT = r"[A-Za-z0-9]+(?:(?:-|, ?)[A-Za-z0-9]+)*"
_SID = r"[A-Z][A-Z0-9]{2}(?:_[A-Za-z0-9]{3})?"
CAPTION = re.compile(r"^(\s*)([A-Z][A-Z0-9]{2})\^(" + _EVT + r")\^(" + _SID + r")"
                     r"\s+(\S.*)$")   # a caption carries a title; a bare CODE^EVT^STRUCT is a table cell
# CODE^EVT with a title two or more spaces away (v2.3.1; v2.4's two-part captions): the structure
# ID comes from Table 0354. A line holding "|" or "<cr>" is an example message, never a caption.
# CH05 5.10.3.1 (v2.3.1, v2.4, v2.5.1, v2.6) puts a direction one space after CODE^EVT, then the
# title: "QRY^Q02 (A to B)  Query Message", "QCK^Q02 (B to A)  Query General Acknowledgment".
# The direction is read past, never into the title (P8b-13 fix round 1).
# One space before the caret is a typesetting slip read as the caption (v2.3.1 CH08 8.8.1 "MFN ^M05").
TWO_PART = re.compile(r"^(\s*)([A-Z][A-Z0-9]{2}) ?\^(" + _EVT + r")(?: \([A-Z] to [A-Z]\))?(\s{2,})(\S.*)$")
DIRECTION = re.compile(r"^\s*[A-Z][A-Z0-9]{2} ?\^" + _EVT + r" \([A-Z] to [A-Z]\)\s")
# v2.7.1 and v2.8.2: "CODE^EVT^STRUCT: title" on its own line, then a "Segments Description" row;
# v2.8.2 CH07 prints "ACK^R01^ACK : title" with a space before the colon (P8b-11: read as a caption,
# so the ORU_R01 and ORU_R30 rows end there instead of running on into the acknowledgment).
COLON = re.compile(r"^(\s*)([A-Z][A-Z0-9]{2})\^(" + _EVT + r")\^(" + _SID + r") ?:\s+(\S.*)$")
# "Descriptions" in v2.8.2 CH04 4.16.6 and 4.16.7 (QBP_O33, RSP_O33; P8b-11).
COLUMNS = re.compile(r"^(\s*)Segments\s{2,}(Descriptions?)\b")
# v2.7.1 CH07 7.17.1 prints the caption's own CODE^EVT^STRUCT in place of "Segments" in the header
# row ("OSM^R26^OSM_R26  Unsolicited Specimen Shipment Manifest  Status  Chapter"; P8b-16): the
# same column row, recognised only when the cell is the caption it follows.
COLUMNS_CAPTION = re.compile(r"^(\s*)([A-Z][A-Z0-9]{2}\^\S+)\s{2,}(\S.*?)\s{2,}Status\s+Chap")
# v2.3: the message code alone, a title and "Chapter"; the event is in the section title.
CODE_ONLY = re.compile(r"^(\s*)([A-Z][A-Z0-9]{2})(\s{3,})(\S.*?)\s{2,}Chapter\s*$")
# v2.3 (section-title era) also prints, P8b-15: a direction tag after the code, no caret ("QRY (A to
# B)", CH02 2.18.1 and 2.18.2, p 2-75); and, read only when the next row is the MSH row, a code one
# space from a long title ("RRE Pharmacy/Treatment Encoded Order Acknowledgment Message  Chapter",
# CH04 4.8.6, p 4-73; RRA, 4.8.13) or a code with no Chapter column ("R0R  Pharmacy /Treatment Order
# Response", CH04 4.8.17 to 4.8.21, pp 4-105 to 4-107).
CODE_ONLY_TAG = re.compile(r"^(\s*)([A-Z][A-Z0-9]{2}) \([A-Z] to [A-Z]\)(\s{3,})(\S.*?)\s{2,}Chapter\s*$")
CODE_LAX = re.compile(r"^(\s*)([A-Z][A-Z0-9]{2})(\s+)([A-Za-z][^|]*?)(?:\s{2,}Chapter)?\s*$")
MSH_ROW = re.compile(r"^(\s*)MSH\s{2,}(?=Message Header\b)", re.I)
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
    parts = h.group(2).split(".") if h else []
    # CH02C numbers its sections 2.C.x: the chapter is the first part, or the first two joined.
    if not h or not chapter or chapter.group(1).lstrip("0") not in (parts[0], "".join(parts[:2])):
        return None
    return h.group(2), h.group(3)
PAGE = re.compile(r"\bPage\s+(\d+[A-Z]?-\d+|\d+)\b")   # v2.7.1 and v2.8.2 number pages per chapter
GROUP_MARK = re.compile(r"^---\s*([A-Z][A-Z0-9_]*)\s+((?i:begin|end))\b")   # "--- VISIT End" (v2.5.1 CSU_C09)
# A mark as printed, misprints included ("--- INVOICE INFORMATION end", v2.6 EHC_E01): parse reads
# it through GROUP_MARK after any cited group-mark erratum, and an unreadable one is an error.
MARK_LIKE = re.compile(r"^---\s*[A-Z][A-Za-z0-9_ /+-]*?\s+(?i:begin|end)\b")
# S3-2: the open order detail. SLOT_CELL is the placeholder in a syntax cell ("[OBR, etc", "OBR,
# etc.", "OBR, etc..."; CH04 and CH12); ETC_ALT and "Hxx" are a choice's placeholder alternative
# ("< OBR | etc. >", v2.5.1 to v2.8.2 CH12); ORDER_DETAIL is the CH04 row "Order Detail Segment OBR,
# etc.", its spaces collapsed, with or without brackets around "Order Detail Segment" alone.
SLOT_CELL = r"OBR,?\s*etc\b\.*"
ETC_ALT = r"etc\b\.?"
ORDER_DETAIL = re.compile(r"(\[?)Order Detail Segment(\]?) OBR,? etc\b\.*")
TOKEN = re.compile(r"\s+|" + SLOT_CELL + "|" + ETC_ALT + r"|Hxx(?![A-Za-z0-9_])|[\[\]{}<>|]|[A-Z][A-Z0-9]{2}(?![A-Za-z0-9_])"
                   r"|\.\.\.|…|.")
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
    events_from: str = ""     # v2.3: the overrides.json eventsFromTitle citation that gave the events

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
    printed: str = ""      # S3-2: the order detail placeholder as printed, when the cell is rewritten


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


_CELL = re.compile(r"[\[\]{}<>| ]*[A-Z][A-Z0-9]{2}[\[\]{}<>| ]*")


def split_row(line, desc_col):
    """(left, description) of a table line, or None when text crosses the description column
    (prose, not a table row)."""
    s = line.replace("\f", "").rstrip()
    if not s.strip():
        return ("", "")
    indent = len(s) - len(s.lstrip())
    if indent >= desc_col - 2:
        # A cell of brackets alone drifted right into the description column (v2.4 CH11 RQA_I08,
        # REF_I12 and RRI_I12 print a group's closing ']' there; P8b-13) is syntax, not description.
        if re.fullmatch(r"[\[\]{}]+", s.strip().replace(" ", "")):
            return (s.strip(), "")
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
        # A syntax cell (brackets and one segment ID) one space from its description at the column
        # (v2.3 CH03 3.2.19 ADR, p 3-17: "[{ROL}] Role"; CH07 7.6.2 CSU, p 7-64: "{RXA Pharmacy
        # Administration"; P8b-15).
        for m in re.finditer(r"(?<=\S) (?=[A-Z][a-z])", s):
            if m.start() > indent and abs(m.end() - desc_col) <= 8 and _CELL.fullmatch(s[:m.start()].strip()):
                return (s[:m.start()].strip(), s[m.end():].strip())
        # A page set further right than the caption's (v2.3 CH04 4.8.19 RDR, p 4-106: the rows after
        # the page break start six columns on, and "{[RXC]}" ends where the description column was):
        # a row whose cell ends at the description column, its other text past it (P8b-15).
        for m in re.finditer(r" {2,}", s):
            if indent < m.start() == desc_col and m.end() > desc_col + 8 and _CELL.fullmatch(s[:m.start()].strip()):
                return (s[:m.start()].strip(), "")
        return None
    left, desc = s[:best.start()].strip(), s[best.end():].strip()
    # A closing bracket printed one space before the description, past the split (v2.3 CH02 2.14.2
    # UDM, p 2-69: "{   DSP   } Display Data"; P8b-15), belongs to the syntax cell.
    tail = re.match(r"([\]}>]+) (\S.*)$", desc)
    if tail and left:
        return (f"{left} {tail.group(1)}", tail.group(2))
    return (left, desc)


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
        m = CODE_ONLY.match(line) or CODE_ONLY_TAG.match(line)
        return m and (len(m.group(1)), m.group(2), "", "", m.start(4), m.group(4))
    m = CAPTION.match(line)
    if m:
        return (len(m.group(1)), m.group(2), m.group(3), m.group(4), m.start(5), m.group(5))
    m = TWO_PART.match(line)
    # A "title" that is itself CODE^EVT is a grid row (v2.5.1 CH05 5.10.3's query/response
    # pairs, "EQQ^Q04   TBR^R08   Tabular"), not a caption.
    # A direction caption is a column header: all twelve printed (v2.3.1 to v2.6) end in "Chapter";
    # "CODE^EVT (A to B)  text" in running prose does not, and is no caption (P8b-18).
    if m and DIRECTION.search(line) and not re.search(r"\s{2,}Chapter\s*$", line):
        return None
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
    if era == "section-title":
        nxt = next((x.replace("\f", "") for x in lines[i + 1:i + 4] if x.strip() and not FURN.search(x)), "")
        row = MSH_ROW.match(nxt)
        if m:
            # The rows' description column is the MSH row's, which v2.3 sets apart from a title that
            # starts nearer the code (CH04 4.8.9 RRD, p 4-80: the title at column 30, the rows' at 44).
            return ((m[0], m[1], m[2], m[3], row.end(), m[5]) if row else m), 0
        lax = CODE_LAX.match(line.translate(_DASHES))
        row = lax and lax.group(2) != "MSH" and row
        # The title column is the MSH row's description column (the caption's own may sit one space on).
        return (row and (len(lax.group(1)), lax.group(2), "", "", row.end(), lax.group(4))) or None, 0
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


# A segment ID followed by a caret is the next message's caption, never notation (v2.4 CH05 5.10.3.2
# DSR^Q03 then "ACK^Q03 (A to B)" with no page heading between; P8b-13): it ends the table.
_NOTATION = re.compile(r"^(?:[\[\]{}<>|]|[A-Z][A-Z0-9]{2}(?![A-Za-z0-9_^])|\.\.\.|…)")
# A segment ID then a word in prose; a depth-0 line after the table that starts with a segment ID but
# goes on in prose ("QPD Input Parameter Specification", v2.8.2 CH04A RSP_K31) ends the table (P8b-11).
_PROSE = re.compile(r"^[A-Z][A-Z0-9]{2}\s+[A-Z]?[a-z]+\b")


def _no_chapter(text):
    return re.sub(r"\s+\d{1,2}\s*$", "", text.replace("\f", "")).strip()


def _order_detail(text):
    """(cell, printed) when text prints the CH04 order detail row (S3-2): the cell rewritten in
    the CH12 notation ("OBR, etc.", bracketed when the print brackets "Order Detail Segment"
    alone), printed the row as the print gives it, spaces collapsed."""
    printed = " ".join(_no_chapter(text).split())
    m = ORDER_DETAIL.fullmatch(printed)
    if not m or bool(m[1]) != bool(m[2]):
        return None
    return f"{m[1]}OBR, etc.{m[2]}", printed


def syntax_rows(lines, caption, claimed=False):
    """The syntax rows of caption's table, in order. Records page-break repeats of the caption
    and the page of the last row on the caption. A repeated Segments/Description row (v2.7.1,
    v2.8.2) resets the columns; a footnote digit on a line of its own is furniture, and one at
    the left margin opens the page-foot footnotes, read as furniture up to the page footer.
    claimed: an overrides.json keyedChoices entry names the caption (S4-1), so a run of ellipsis
    rows in the description column is one "..." row, which parse reads through that entry."""
    pages = page_labels(lines)
    rows, depth, choices, foot, placeholder, ellipsis = [], 0, 0, False, None, None
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
        cols = caption.era == "caret-colon" and COLUMNS_CAPTION.match(line)
        if cols and cols.group(2) == caption.printed:
            code_col, desc_col = len(cols.group(1)), cols.start(3)
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
        # S3-2: the CH04 order detail row "Order Detail Segment OBR, etc." crosses the description
        # column (v2.3 CH04 4.2.1, p 4-4), or wraps "Order Detail" / "Segment OBR, etc." onto a
        # line further left (v2.3.1 CH04 4.2.1, p 4-4): one row, its cell in the CH12 notation.
        printed, detail = "", rows and _order_detail(line)
        if rows and not detail and re.fullmatch(r"\[?Order Detail", _no_chapter(line)):
            j = next((k for k in range(i + 1, min(i + 3, len(lines))) if lines[k].strip()), None)
            detail = j is not None and _order_detail(_no_chapter(line) + " " + lines[j])
            skip = j - i if detail else 0
        cells = (detail[0], "Order Detail Segment") if detail else split_row(line, desc_col)
        printed = detail[1] if detail else ""
        if cells is None and rows:
            # The CH12 cell one space from its description (v2.3 CH12 12.3.3 PPP^PCB, p 12-11:
            # "[OBR, etc Order Detail Segment, etc."; S3-2).
            m = re.fullmatch(r"([\[{]*" + SLOT_CELL + r")\s+(\S.*)", _no_chapter(line))
            cells = (m[1], m[2]) if m else None
        if cells is None:
            if depth == 0:
                break
            raise UnknownNotation(f"line {i + 1}: prose inside an open group: {line.strip()[:60]!r}")
        left, desc = cells
        if not left and choices > 0 and re.fullmatch(ETC_ALT, desc.strip()):
            # "etc." alone in place of an alternative (v2.5.1 to v2.7.1 CH12 "< OBR | etc. >"): the
            # open order detail, read by parse as the choice's placeholder alternative (S3-2).
            left, desc = desc.strip(), ""
        elif not left and choices > 0 and PLACEHOLDER.match(desc.strip()):
            # Any other placeholder among the alternatives: ruling G6, never guessed. Read on to the
            # end of the table first, so its page-break repeats of the caption are consumed.
            placeholder = placeholder or f"line {i + 1}: placeholder (G6): {desc.strip()!r} among a choice's alternatives"
            continue
        if not left and rows and depth > 0 and _order_detail(desc):
            # The order detail row in the description column with an empty syntax cell (v2.3.1 CH04
            # 4.2.3 OSR^Q06, p 4-5: "[Order Detail Segment] OBR, etc."): the slot (S3-2).
            (left, printed), desc = _order_detail(desc), "Order Detail Segment"
        elif not left and rows and depth > 0 and (re.match(r"[\[{<]", desc.strip()) or re.search(r"\bOBR,? etc\b", desc)):
            # Other notation printed in the description column inside an open group: read as
            # description it would vanish from the structure; a placeholder, ruling G6 (P8b-14).
            placeholder = placeholder or f"line {i + 1}: placeholder (G6): {desc.strip()[:60]!r} in the description column"
            continue
        if not left and rows and claimed and re.fullmatch(r"(?:\.\s*){3}|…", desc.strip()):
            # S4-1: the ellipsis a keyedChoices entry reads (the body ERQ-2 names); one row per run.
            if rows[-1].left != "...":
                rows.append(Row("...", "", i, pages[i]))
                caption.end_page = pages[i]
            continue
        if not left and rows and re.fullmatch(r"(?:\.\s*){3}|…", desc.strip()):
            # An ellipsis alone in the description column between syntax rows stands for segments
            # the print does not enumerate (v2.4 and v2.5.1 CH05 5.10.4.2 ERP^R09: 'the segments
            # indicated by the ellipsis (...)' are those of another message; P8b-13): ruling G6,
            # unreadable once a later syntax row shows the ellipsis is inside the table.
            ellipsis = ellipsis or f"line {i + 1}: placeholder (G6): an ellipsis row stands for unlisted segments"
            continue
        if not left:
            # "--- NAME" with "begin" or "end" wrapped onto the description's next line, or with
            # the name's last word wrapped too (v2.7.1 CH07 7.17.1 "--- SUBJECT POPULATION/LOCATION"
            # then "IDENTIFICATION begin"; P8b-16).
            if rows and re.fullmatch(r"---\s*[A-Z][A-Za-z0-9_ /]*", rows[-1].desc) and re.match(
                    r"(?:[A-Z][A-Z0-9_/]*\s+)?(?i:begin|end)\b", desc):
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
        rows.append(Row(left, desc, i, pages[i], printed))
        caption.end_page = pages[i]
        placeholder = placeholder or ellipsis
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


def _cells_fixed(rows, fixes, used):
    """Rows with the cited syntax-cell errata applied: printed and intended are the row's cell then
    its description, spaces collapsed; only the cell may differ. An entry with "occurrence" n
    corrects only the n-th row of the print that reads so (a bare ']' recurs; v2.4 OML_O21,
    P8b-13); one without corrects every such row."""
    seen, out = {}, []
    for row in rows:
        if not row.left:
            out.append(row)
            continue
        printed = " ".join(f"{row.left} {row.desc}".split())
        n = seen[printed] = seen.get(printed, 0) + 1
        e = next((x for x in fixes.get(printed, []) if x.get("occurrence", n) == n), None)
        if not e:
            out.append(row)
            continue
        desc = " ".join(row.desc.split())
        if not e["intended"].endswith(" " + desc if desc else ""):
            raise UnknownNotation(f"syntax-cell erratum for {printed!r} changes the description")
        used.add(id(e))
        out.append(Row(e["intended"][:len(e["intended"]) - len(desc)].strip(), row.desc, row.line, row.page))
    return out


def parse(rows, marks=None, used=None, keyed=None):
    """Elements from syntax rows, by bracket balance. A group the print leaves unnamed has
    "group": None until name_groups resolves it. A choice (P8b-6) is "<", alternatives split
    by "|", then ">", in any row layout (inline, one alternative per row, or each token on its
    own row); "--- NAME begin" on its "<" row names it (v2.7.1 on). marks maps a misprinted group-mark name to the
    intended one (a cited errata entry); used receives every printed name it corrected."""
    marks = marks or {}
    # keyed: the overrides.json keyedChoices entry for this structure (S4-1); its placeholder as
    # printed ("...", "???") is read as one keyed element, consecutive placeholder rows merged.
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
        # A footnote reference fused to a bracket ('[{1', '}]3'; v2.4 CH06 DFT_P03, CH12 PTR_PCF;
        # P8b-13) is not notation: a segment ID starts with a letter, so digits after a bracket are
        # always the footnote mark.
        left = re.sub(r"(?<=[\[\]{}<>])\d{1,2}(?=\s|$)", "", row.left)
        if keyed and left.strip() == keyed["printed"]:
            # S4-1: the placeholder row a keyedChoices entry reads ("...", "???"); one per run.
            children = stack[-1]["children"]
            if not (children and children[-1]["kind"] == "keyed"):
                children.append({"kind": "keyed", "entry": keyed, "row": row})
            continue
        for tok in (t.group(0) for t in TOKEN.finditer(left)):
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
                node = {"kind": "<", "children": [], "alts": [], "name": None, "page": row.page}
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
            elif re.fullmatch(SLOT_CELL, tok):
                # S3-2: the open order detail ("[OBR, etc", "OBR, etc."), named by its description
                # ("Order Detail Segment, etc." reads "Order Detail Segment").
                stack[-1]["children"].append({"kind": "slot", "row": row, "tok": tok})
            elif stack[-1]["kind"] == "<" and (re.fullmatch(ETC_ALT, tok) or (
                    tok in ("...", "…", "Hxx") and re.fullmatch(ETC_ALT, row.desc.strip()))):
                # A choice's placeholder alternative: "etc." (v2.5.1 to v2.7.1 CH12), "..." or
                # "Hxx" with the description "etc." (v2.5.1 PRR^PC5, v2.8.2); _choice reads it.
                stack[-1]["children"].append({"kind": "etc", "tok": tok})
            elif re.fullmatch(r"[A-Z][A-Z0-9]{2}", tok):
                stack[-1]["children"].append({"kind": "seg", "id": tok, "desc": row.desc})
            elif tok in ("...", "…"):
                raise UnknownNotation(f"placeholder (G6): {row.left!r}")
            else:
                raise UnknownNotation(f"not notation: {row.left!r}")
        desc = _corrected(row.desc, marks, used)
        mark = GROUP_MARK.match(desc)
        name = mark and mark.group(1)
        if not mark and re.match(r"^---\s*\S", desc):
            # A mark with no begin or end on a choice's "<" or ">" row (v2.7.1 and v2.8.2 CH12
            # PGL^PC6 "--- CHOICE") is unread unless the choice turns out to be a slot (S3-2).
            choice = next((n for n in opened + closed if n["kind"] == "<"), None)
            if choice is None:
                raise UnknownNotation(f"group mark not read: {desc[:50]!r}")
            choice["loose"] = desc
            continue
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


def _slot(node, alone=False):
    """The slot element for a SLOT_CELL node (S3-2). min 1, max null: unbracketed within its
    group, the slot is required once the group is present, and "segment(s)" (CH04 use note b) or
    "all possible combinations" (CH12 note) admit more than one; brackets around the placeholder
    alone make it optional. "_at" carries what cite_slots needs (the print and its page)."""
    row = node["row"]
    name = re.sub(r",?\s*etc\b\.*$", "", _no_chapter(row.desc)).strip()
    name = None if not name or name.startswith("---") else name
    printed = row.printed or " ".join(f"{row.left} {row.desc}".split())
    return {"slot": name, "min": 0 if alone else 1, "max": None,
            "_at": {"page": row.page, "printed": printed, "alone": alone}}


def _keyed(node):
    """The element a keyedChoices placeholder stands for (S4-1): an open slot with the entry's
    bounds and citation where the print enumerates no body (ERP: the message ERQ-2 names), or,
    where it maps key values to printed groups (MFN_M03), a slot standing in until
    resolve_keyed_choices puts the keyed choice in its place once every structure is read."""
    entry = node["entry"]
    if "slot" in entry:
        return {"slot": entry["slot"]["name"], "min": entry["slot"]["min"], "max": entry["slot"]["max"],
                "citation": entry["citation"], "_keyed": entry}
    return {"slot": None, "min": 0, "max": None, "citation": entry["citation"], "_keyed": entry}


def _element(node):
    if node["kind"] == "seg":
        return {"segment": node["id"], "min": 1, "max": 1}
    if node["kind"] == "slot":
        return _slot(node)
    if node["kind"] == "keyed":
        return _keyed(node)
    if node["kind"] == "etc":
        raise UnknownNotation(f"placeholder (G6): {node['tok']!r} among a choice's alternatives, not the last")
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
        if (only is not None and only["kind"] not in ("seg", "slot", "keyed") and node["kind"] != "="
                and not (names and (only["name"] or only["kind"] == "<"))):
            node = only
            continue
        break
    if node["kind"] == "<":
        return _choice(node, kinds, names)
    if not node["children"]:
        raise UnknownNotation("an empty group")
    bounds = {"min": 0 if "[" in kinds else 1, "max": None if "{" in kinds else 1}
    if len(node["children"]) == 1 and not names and node["children"][0]["kind"] == "slot":
        # "[Order Detail Segment] OBR, etc." (v2.3 CH04 4.2.2 ORR^O02, p 4-5): the placeholder
        # alone in brackets is an optional slot (S3-2).
        return _slot(node["children"][0], alone="[" in kinds)
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
    last = node["alts"][-1]
    if len(node["alts"]) > 1 and len(last) == 1 and last[0]["kind"] == "etc":
        return _choice_slot(node, kinds)
    if node.get("loose"):
        raise UnknownNotation(f"group mark not read: {node['loose'][:50]!r}")
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


def _choice_slot(node, kinds):
    """A choice whose last alternative is the placeholder ("< OBR | etc. >", v2.5.1 to v2.8.2
    CH12): one slot in place of the whole choice (S3-2). A slot never sits inside a choice, and the
    print says the detail is any of the listed segments or others, which a slot covers; the listed
    alternatives go into its citation. The choice's own mark, if any, names nothing that remains.
    Named by the first listed alternative's description ("OBR  Order Detail Segment")."""
    listed = node["alts"][:-1]
    if any(n["kind"] in ("etc", "slot") for alt in listed for n in alt):
        raise UnknownNotation("placeholder (G6): a choice holding more than one placeholder")
    alts = [compact([_element(n) for n in alt]) for alt in listed]
    first = listed[0][0]
    name = _no_chapter(first.get("desc", "")) if first["kind"] == "seg" else ""
    name = None if not name or name.startswith("---") else name
    return {"slot": name, "min": 0 if "[" in kinds else 1, "max": None,
            "_at": {"page": node.get("page", ""), "printed": "< " + " | ".join(alts + [node["alts"][-1][0]["tok"]]) + " >",
                    "alone": "[" in kinds, "alternatives": alts}}


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
            # A bundle name no group name can hold (the v2.4 bundle's RCI_I05 group "c"; P8b-13)
            # is a bundle defect: only a cited groupNames override names that group.
            if name is not None and not re.fullmatch(r"[A-Z][A-Z0-9_]*", name):
                if not hit:
                    raise UnknownNotation(f"the HL7 v2.xml bundle names the group at {where} {name!r}, which no "
                                          "group name can hold: a cited groupNames override is needed")
                name = None
            entry = {"path": where, "miss": name is None, "shadowed": bool(name and hit)}
            if name is None and hit:
                name, source, cite = hit[0]["name"], "override", f"overrides.json: {hit[0]['citation']}"
            elif name is None:
                # A slot is no segment: the first printed segment names it (S3-2).
                base = f"{next((x for x in _v2xml.leaves(element['elements']) if x != _v2xml.OPEN), 'SLOT')}_GROUP"
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


def _holds_keyed(elements):
    """Whether a keyedChoices placeholder (S4-1) is among elements, at any depth."""
    return any("_keyed" in e or _holds_keyed(e.get("elements", []) + e.get("alternatives", [])) for e in elements)


def _slots(elements):
    """(parent list, element) for every element holding "_keyed", at any depth."""
    for e in elements:
        if "_keyed" in e:
            yield elements, e
        yield from _slots(e.get("elements", []) + e.get("alternatives", []))


def _find_group(elements, name):
    for e in elements:
        if e.get("group") == name:
            return e
        found = _find_group(e.get("elements", []) + e.get("alternatives", []), name)
        if found:
            return found
    return None


def _replace_keyed(elements, choice):
    """Put choice in place of the keyedChoices placeholder; True when one was replaced."""
    for i, e in enumerate(elements):
        if "_keyed" in e:
            elements[i] = choice
            return True
        if "elements" in e and _replace_keyed(e["elements"], choice):
            return True
    return False


def resolve_keyed_choices(ver, structures, keyed):
    """S4-1: each keyedChoices entry with alternatives puts a keyed choice in place of its
    placeholder: alternative k is the named group of the structure the print names for value k,
    from the segment after `after` on (MFN_M03: "Other segment(s) represents segments that follow
    the OM1 segment", the groups of MFN^M08 to MFN^M12). The group keeps its name and nameSource;
    an unprinted name is cited as the referenced structure cites it. Returns report rows."""
    report = []
    for sid, entry in sorted(keyed.items()):
        if sid not in structures:
            continue
        structure = structures[sid]
        if "slot" in entry:
            # No enumerable map (ERP: the message ERQ-2 names): the open slot stays.
            for _, e in _slots(structure["elements"]):
                e.pop("_keyed", None)
            key = entry["key"]
            structure["citation"] += (f" The placeholder {entry['printed']!r} is an open slot (overrides.json "
                                      f"keyedChoices, ADR-019 S4-1): the print fills it with the message "
                                      f"{key['segment']}-{key['field']} names and enumerates no map.")
            report.append((sid, "keyed-slot", f"{key['segment']}-{key['field']}: open slot"))
            continue
        alternatives, values, cites = [], {}, []
        try:
            for alt in entry["alternatives"]:
                ref = structures.get(alt["structure"])
                if ref is None:
                    raise UnknownNotation(f"{alt['structure']} is not read from the print")
                group = _find_group(ref["elements"], alt["group"])
                if group is None:
                    raise UnknownNotation(f"{alt['structure']} has no group {alt['group']}")
                ids = [e.get("segment") for e in group["elements"]]
                if alt["after"] not in ids or ids.index(alt["after"]) == len(ids) - 1:
                    raise UnknownNotation(f"{alt['structure']} {alt['group']} has no segments after {alt['after']}")
                tail = json.loads(json.dumps(group["elements"][ids.index(alt["after"]) + 1:]))
                alternatives.append({"group": alt["group"], "nameSource": group["nameSource"], "min": 1, "max": 1,
                                     "elements": tail})
                values[alt["value"]] = alt["group"]
                for _, inner in _v2xml.groups([alternatives[-1]]):
                    if inner["nameSource"] != "printed":
                        m = re.search(re.escape(inner["group"]) + r" \([^()]*\)", ref["citation"])
                        if not m:
                            raise UnknownNotation(f"{alt['structure']} does not cite the name {inner['group']}")
                        cites.append(m.group(0))
        except UnknownNotation as exc:
            report.append((sid, "error", f"keyedChoices: {exc}"))
            continue
        key = entry["key"]
        choice = {"choice": None, "min": 1, "max": 1,
                  "key": {"segment": key["segment"], "field": key["field"], "component": key["component"],
                          "values": values, "citation": entry["citation"]},
                  "alternatives": alternatives}
        if not _replace_keyed(structure["elements"], choice):
            report.append((sid, "error", "keyedChoices: the placeholder is not in the structure"))
            continue
        field_name = f"{key['segment']}-{key['field']}"
        structure["citation"] += (f" The placeholder {entry['printed']!r} is a choice keyed by {field_name} "
                                  f"(overrides.json keyedChoices, ADR-019 S4-1): {_join(sorted(values))} select "
                                  f"{_join([a['group'] for a in alternatives])}.")
        if cites:
            structure["citation"] += f" Unprinted group names of the alternatives: {', '.join(dict.fromkeys(cites))}."
        validate_names(structure)
        report.append((sid, "keyed-choice", f"{field_name}: {', '.join(f'{v}={g}' for v, g in sorted(values.items()))}"))
    return report


def add_aliases(ver, structures, overrides, full):
    """S4-2: each aliases entry of the version adds a structure whose print gives an ID and a
    trigger of its own and refers its syntax to another printed structure: its elements are the
    target's, copied; its triggers and citation are its own. Returns report rows; a target not
    read is an error on a full read only (a partial read may not reach it)."""
    report = []
    for e in overrides["aliases"]:
        if e["version"] != ver:
            continue
        sid, target = e["structure"], e["aliasOf"]
        if sid in structures:
            report.append((sid, "error", "aliases entry names a structure the print gives a syntax"))
        elif target not in structures and not full:
            continue
        elif target not in structures or "aliasOf" in structures[target]:
            report.append((sid, "error", f"aliases entry: {target} is not a structure read from the v{ver} print"))
        else:
            original = structures[target]
            structures[sid] = validate_names({
                "structure": sid, "version": ver, "triggers": list(e["triggers"]), "aliasOf": target,
                "elements": json.loads(json.dumps(original["elements"])),
                "citation": (f"{e['citation']} The syntax is that of {target} (overrides.json aliases, ADR-019 S4-2), "
                             f"as cited there: {original['citation']}")})
            report.append((sid, "alias", f"of {target}"))
    return report


def table_citation(ver, sid, triggers, where, withdrawn):
    """The sentence citing the triggers Table 0354 adds to a structure (P8b-11 fix round), and any
    section that marks one of their events withdrawn."""
    if not triggers:
        return ""
    loc = where.get(sid)
    # v2.3.1 is one PDF with no chapter in its file name: the chapter is the section's first part.
    at = f" (Chapter {loc[0] or loc[1].split('.')[0]}, section {loc[1]}, p {loc[2]})" if loc else ""
    text = (f" Triggers Table 0354 v{ver}{at} maps to {sid} that no caption prints, accepted with the printed ones "
            f"(P8b-11 ruling): {_join(triggers)}.")
    for trigger in triggers:
        if trigger in withdrawn:
            chapter, section = withdrawn[trigger]
            text += f" Chapter {chapter} section {section} marks {trigger} withdrawn."
    return text


def table_provenance(ver, table_ver, era, sid, how, errata, where):
    """The sentence a structure citation carries when its ID was read from Table 0354 (P8b-14
    fix round 1, v2.3.1; every version since P8b-18: the v2.4 two-part captions, QRY_Q02 and
    QCK_Q02 on v2.4 to v2.6): the table's place, any erratum the row was read through (printed
    and corrected), and any declaration that resolved a caption. v2.3 has no table and
    synthesises its IDs; v2.7.1 and v2.8.2 captions print every ID."""
    if not how:
        return ""
    printed = next((e["printed"] for e in errata or [] if "_" in e["printed"]), sid)
    loc = where.get(printed) or where.get(sid)
    at = f" (Chapter {loc[0] or loc[1].split('.')[0]}, section {loc[1]}, p {loc[2]})" if loc else ""
    text = f" Structure ID from Table 0354 v{table_ver}{at}"
    if errata:
        fixes = [f"{e['printed']} read as {e['intended']}" if "_" in e["printed"]
                 else f"event {e['printed']} read as {e['intended']}" for e in errata]
        text += f", its row read through cited overrides.json errata ({_join(fixes)})"
    shared = sorted({f"{h[2]} (listed under {', '.join(h[1])})" for h in how if h[0] == "shared"})
    assigned = sorted({h[1] for h in how if h[0] == "assigned"})
    if shared:
        text += f"; declared shared triggers: {_join(shared)}"
    if assigned:
        text += f"; the row named for {_join(assigned)} by overrides.json captionStructures"
    return text + "."


def synthesised_provenance(era, sid, entries, fold):
    """The sentences a v2.3 structure citation carries (P8b-15): v2.3 prints no structure ID and no
    Table 0354, so the ID is synthesised (CODE_EVT from the primary print's code and first event,
    or the code alone for a triggerFolds entry onto CODE^*), and each print's events come from its
    section title or, where the title names none, a cited overrides.json eventsFromTitle entry.
    entries: (caption, rows, error), the primary print first. Other eras: empty."""
    if era == "table-0354" and fold and fold["trigger"] == f"{sid}^*":
        # v2.3.1: the general acknowledgment and MCF print no ID and have no Table 0354 row (fix round 2).
        return (f" Structure ID {sid} is the message code alone (overrides.json triggerFolds): the caption prints "
                f"the code alone and Table 0354 has no {sid} row.")
    if era != "section-title":
        return ""
    why = "(v2.3 prints no structure ID and no Table 0354)"
    if fold:
        return f" Structure ID {sid} synthesised as the message code alone (overrides.json triggerFolds) {why}."
    cap = entries[0][0]
    whence = ("the first event overrides.json eventsFromTitle gives it" if cap.events_from
              else "the first event the section title names")
    text = f" Structure ID {sid} synthesised as CODE_EVT from the message code {cap.code} and {cap.events[0]}, {whence} {why}."
    seen = []
    for c, _, _ in entries:
        trigs = _join([f"{c.code}^{v}" for v in c.events])
        if c.events_from:
            line = (f"Events {trigs} from overrides.json eventsFromTitle (section {c.section} "
                    f"'{c.section_title}' names no event): {c.events_from}")
        else:
            line = f"Events {trigs} read from the section title {c.section} '{c.section_title}'"
        if line not in seen:
            seen.append(line)
    return text + "".join(f" {line}." for line in seen)


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
        # v2xml-v2.4 is for v2.3 and v2.3.1 only, v2xml-v2.3.1 for v2.3 only (P8b-15); v2.3 has no
        # bundle, so no v2xml (P8b-14: v2.3.1 has one).
        if (source == "v2xml-v2.4" and structure["version"] not in ("2.3", "2.3.1")) or \
                (source == "v2xml-v2.3.1" and structure["version"] != "2.3") or \
                (source == "v2xml" and structure["version"] == "2.3"):
            raise NameSourceError(f"group {group['group']}: nameSource {source} on v{structure['version']}; "
                                  "v2xml-v2.4 is for v2.3 and v2.3.1 only, v2xml-v2.3.1 for v2.3 only, and v2.3 "
                                  "has no v2xml bundle")
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


def cite_slots(elements, version, cap):
    """Every slot's citation (S3-2), in place of its "_at": the structure's own citation form
    (version, chapter, section, title) at the page of the slot's row, the print quoted, and why
    it is a slot. Returns elements."""
    for e in elements:
        if "slot" in e and "_at" in e:
            at = e.pop("_at")
            text = (f"HL7 v{version} Chapter {cap.chapter}, section {cap.section} {cap.section_title}, p {at['page']}: ")
            if "alternatives" in at:
                text += (f"the print gives the order detail as the choice {at['printed']!r}, whose last alternative is "
                         "a placeholder for segments it does not enumerate: one open slot in place of the choice "
                         f"(ADR-019 S3-1, S3-2), the listed alternative{'s' if len(at['alternatives']) > 1 else ''} "
                         f"{_join(at['alternatives'])} among its fillers")
            else:
                text += (f"the print gives the order detail as {at['printed']!r}, segments it names by example and "
                         "does not enumerate: an open slot (ADR-019 S3-1, S3-2)")
            if at["alone"]:
                text += ("; the print brackets the placeholder alone, so the slot is optional" if "alternatives" not in at
                         else "; the print brackets the choice, so the slot is optional")
            e["citation"] = text + "."
        for key in ("elements", "alternatives"):
            cite_slots(e.get(key, []), version, cap)
    return elements


def uncited(elements):
    """elements with each slot's "_at" or citation dropped, to compare two prints (S3-2)."""
    return [{k: v for k, v in e.items() if k not in ("_at", "citation")} if "slot" in e else
            {**e, "elements": uncited(e["elements"])} if "elements" in e else
            {**e, "alternatives": uncited(e["alternatives"])} if "alternatives" in e else e for e in elements]


def render_element(element, indent):
    if "slot" in element:     # S3-2: the S3-1 open-slot form
        return (f'{indent}{{ "slot": {json.dumps(element["slot"])}, "min": {element["min"]}, '
                f'"max": {json.dumps(element["max"])}, "citation": {json.dumps(element["citation"], ensure_ascii=False)} }}')
    if "segment" in element:
        return (f'{indent}{{ "segment": "{element["segment"]}", "min": {element["min"]}, '
                f'"max": {json.dumps(element["max"])} }}')
    if "alternatives" in element:     # P8b-6: {"choice": NAME or null, "nameSource" (named), ...}
        source = f'"nameSource": "{element["nameSource"]}", ' if element["choice"] else ""
        key = ""
        if "key" in element:     # S4-1: a keyed choice
            k = element["key"]
            values = ", ".join(f"{json.dumps(v)}: {json.dumps(k['values'][v])}" for v in sorted(k["values"]))
            key = (f'"key": {{ "segment": "{k["segment"]}", "field": {k["field"]}, "component": {k["component"]}, '
                   f'"values": {{ {values} }}, "citation": {json.dumps(k["citation"], ensure_ascii=False)} }}, ')
        head = (f'{indent}{{ "choice": {json.dumps(element["choice"])}, {source}"min": {element["min"]}, '
                f'"max": {json.dumps(element["max"])}, {key}"alternatives": [')
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
            + (f'  "aliasOf": "{structure["aliasOf"]}",\n' if "aliasOf" in structure else "")
            + f'  "elements": [\n{body}\n  ]\n'
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
    # runs of spaces collapsed ("{ [ CTD } ] Contact Data"), the description unchanged (P8b-10); an
    # optional "occurrence" (1-based) narrows it to the n-th row that reads so (P8b-13).
    "errata": {"version", "where", "structure", "printed", "intended", "citation"},
    # A trigger printed under several structures (pre-flight B6); reported, never modelled here.
    "sharedTriggers": {"version", "trigger", "structures", "citation"},
    # Two normative prints of one structure ID that disagree: the LOOSER print (the one that
    # accepts every message the other accepts) is primary, cited to both (P8b-9 ruling; ADR-019
    # primary-print amendment). primary and stricter are the captions as printed, or "CAPTION
    # (section N)" where prints share a caption; stricter may list several prints (S3-3).
    "primaryPrints": {"version", "structure", "primary", "stricter", "citation"},
    # Two normative prints of one structure ID that are incomparable (neither accepts every message
    # the other accepts): the committed structure is their UNION, aligned by segment or group name
    # (P8b-10 ruling, v2.6 RSP_K21; ADR-019 addendum). prints are the two captions as printed, the
    # first the primary (cited first); prints that do not align leave the structure unmodelled.
    "unionPrints": {"version", "structure", "prints", "citation"},
    # A caption (as printed, in its section) whose events no Table 0354 row of the version lists,
    # or that no declared shared trigger resolves: its print names no structure, so it is reported
    # and not modelled (P8b-14, v2.3.1). Undeclared, such a caption fails a full read on a version
    # that prints its own Table 0354.
    "unresolvedCaptions": {"version", "section", "caption", "citation"},
    # The Table 0354 row a caption's print belongs to when no row lists all the caption's events
    # (P8b-14, v2.3.1: the one MFK row, MFK_M01, omits M02 and M04). The structure must be a row
    # of the version's table; the citation joins the structure's.
    "captionStructures": {"version", "section", "caption", "structure", "citation"},
    # v2.3 (P8b-15): the events of a code-alone caption whose section title names none, or names
    # them in a form the title reader does not read ("(event O01/O02)"), with the citation of where
    # the print gives them (section text, Table 0003). Keyed by section and caption (the code as
    # printed); an optional "occurrence" (1-based) narrows it to the n-th such caption of the section.
    "eventsFromTitle": {"version", "section", "caption", "events", "citation"},
    # Triggers the print defines only in prose that names an already printed structure for them
    # without ambiguity (v2.3 CH07 7.19.1: W01 "identifies ORU messages"; P8b-15 fix round 2):
    # added to that structure's triggers, cited. An entry naming no read structure fails a full read.
    "referencedTriggers": {"version", "structure", "triggers", "citation"},
    # A segment the version's Appendix A lists as withdrawn or deprecated with no definition, which
    # a structure of the version still prints (v2.7.1, v2.8.2: QRD, QRF, URD, URS; S2-1). A
    # structure may name it beside the version's segments; it is matched by ID and not field-checked.
    # printed is the Appendix A status as printed; definedThrough the last version that defines it.
    "withdrawnSegments": {"version", "segment", "printed", "definedThrough", "citation"},
    # S4-1: a placeholder (printed, under the caption as printed) that stands for a body a field
    # value of the message chooses. With "alternatives" the print maps each value to a printed
    # group ({"value", "structure", "group", "after", "page"}: the group's segments after `after`),
    # read as a keyed choice; with "slot" ({"name", "min", "max"}) it enumerates no map and the
    # placeholder is an open slot. key is {"segment", "field", "component"}.
    "keyedChoices": {"version", "structure", "caption", "printed", "key", "citation"},
    # S4-2: a structure ID the print gives a trigger of its own (a caption or a Table 0354 row)
    # whose syntax it refers to another printed structure of the version: the alias keeps its ID,
    # triggers and citation and takes aliasOf's elements.
    "aliases": {"version", "structure", "aliasOf", "triggers", "citation"},
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
            if kind == "primaryPrints" and not (
                    isinstance(entry.get("stricter"), str) or (
                        isinstance(entry.get("stricter"), list) and entry["stricter"]
                        and all(isinstance(s, str) for s in entry["stricter"])
                        and entry.get("primary") not in entry["stricter"])):
                raise OverridesError(f"primaryPrints entry for {entry.get('structure')}: stricter must be a print "
                                     "name or a non-empty list of them without the primary")
            if kind == "sharedTriggers" and len(set(entry.get("structures", []))) < 2:
                raise OverridesError(f"sharedTriggers entry {entry.get('trigger')} names fewer than two structures")
            if "occurrence" in entry and not ((kind == "eventsFromTitle" or (kind == "errata" and entry.get("where") in
                                                                             ("syntax-cell", "caption")))
                                              and isinstance(entry["occurrence"], int) and entry["occurrence"] >= 1):
                raise OverridesError(f"{kind} entry for {entry.get('structure', entry.get('caption'))}: 'occurrence' is "
                                     "a positive integer on a syntax-cell or caption erratum or an eventsFromTitle entry only")
            if kind == "referencedTriggers" and not (isinstance(entry.get("triggers"), list) and entry["triggers"]
                                                     and all(isinstance(t, str) and TRIGGER.match(t) for t in entry["triggers"])):
                raise OverridesError(f"referencedTriggers entry for {entry.get('structure')}: triggers must be a "
                                     "non-empty list of CODE^EVT")
            if kind == "eventsFromTitle" and not (isinstance(entry.get("events"), list) and entry["events"] and all(
                    isinstance(v, str) and re.fullmatch(r"[A-Z0-9]{3}", v) for v in entry["events"])):
                raise OverridesError(f"eventsFromTitle entry for {entry.get('caption')} in section "
                                     f"{entry.get('section')}: events must be a non-empty list of three-character events")
            if kind == "withdrawnSegments" and not (re.fullmatch(r"[A-Z][A-Z0-9]{2}", entry.get("segment", ""))
                                                    and entry.get("printed") in ("withdrawn", "deprecated")):
                raise OverridesError(f"withdrawnSegments entry {entry.get('segment')!r}: needs a segment ID and "
                                     "printed 'withdrawn' or 'deprecated'")
            if kind == "captionStructures" and not re.fullmatch(_SID, entry.get("structure", "")):
                raise OverridesError(f"captionStructures entry for {entry.get('caption')}: bad structure ID "
                                     f"{entry.get('structure')!r}")
            if kind == "keyedChoices":
                validate_keyed_entry(entry)
            if kind == "aliases" and not (re.fullmatch(_SID, entry.get("structure", "")) and re.fullmatch(
                    _SID, entry.get("aliasOf", "")) and entry["structure"] != entry["aliasOf"]
                    and isinstance(entry.get("triggers"), list) and entry["triggers"]
                    and all(isinstance(t, str) and TRIGGER.match(t) and t.split("^")[0] == entry["structure"].split("_")[0]
                            for t in entry["triggers"])):
                raise OverridesError(f"aliases entry for {entry.get('structure')}: needs two distinct structure IDs and "
                                     "a non-empty list of CODE^EVT triggers with the alias's message code")
            optional = {"exclusions": {"caption"}, "errata": {"occurrence"}, "eventsFromTitle": {"occurrence"},
                        "keyedChoices": {"alternatives", "slot"}}.get(kind, set())
            if not keys <= set(entry) <= keys | optional:
                raise OverridesError(f"{kind} entry keys {sorted(entry)}, expected {sorted(keys)}")
            text = entry.get("citation", entry.get("note", ""))
            if not text.strip() or "\n" in text:
                raise OverridesError(f"{kind} entry for {entry.get('structure', entry.get('section'))} "
                                     "needs a one-line citation")
            if kind == "groupNames" and not re.fullmatch(r"[A-Z][A-Z0-9_]*", entry["name"]):
                raise OverridesError(f"bad group name {entry['name']!r}")
    return data


def validate_keyed_entry(entry):
    """A keyedChoices entry (S4-1): exactly one of alternatives and slot, a well-formed key, and
    alternatives with distinct values and groups."""
    sid = entry.get("structure")
    if ("alternatives" in entry) == ("slot" in entry):
        raise OverridesError(f"keyedChoices entry for {sid}: exactly one of 'alternatives' and 'slot'")
    key = entry.get("key")
    if not (isinstance(key, dict) and set(key) == {"segment", "field", "component"}
            and re.fullmatch(r"[A-Z][A-Z0-9]{2}", str(key["segment"]))
            and all(isinstance(key[k], int) and key[k] >= 1 for k in ("field", "component"))):
        raise OverridesError(f"keyedChoices entry for {sid}: key is {{segment, field, component}}")
    if "slot" in entry:
        slot = entry["slot"]
        if not (isinstance(slot, dict) and set(slot) == {"name", "min", "max"}
                and isinstance(slot["min"], int) and slot["min"] >= 0 and slot["max"] is None):
            raise OverridesError(f"keyedChoices entry for {sid}: slot is {{name, min, max: null}}")
        return
    alts = entry["alternatives"]
    if not (isinstance(alts, list) and len(alts) >= 2 and all(
            isinstance(a, dict) and set(a) == {"value", "structure", "group", "after", "page"} for a in alts)):
        raise OverridesError(f"keyedChoices entry for {sid}: two or more alternatives, each "
                             "{value, structure, group, after, page}")
    for k in ("value", "group"):
        if len({a[k] for a in alts}) != len(alts):
            raise OverridesError(f"keyedChoices entry for {sid}: alternatives repeat a {k}")


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


def apply_table_errata(table, errata, used, log=None):
    """Table 0354 rows with each cited table-0354 erratum applied (a misprinted row code, or a
    misprinted event in the row's description). An event erratum whose intended text is a list
    ("PCC, PCG") puts those events in the printed one's place, so it can keep the printed event
    and add one (P8b-14 fix round 1). log, if given, receives {corrected code: [errata]}."""
    out = []
    for code, events, desc in table:
        for e in errata:
            if e["where"] != "table-0354":
                continue
            if code == e["printed"]:
                code = e["intended"]
                used.add(id(e))
            elif code == e["structure"] and events and e["printed"] in events:
                events = list(dict.fromkeys(y for x in events
                                            for y in (re.split(r",\s*", e["intended"]) if x == e["printed"] else [x])))
                used.add(id(e))
            else:
                continue
            if log is not None:
                log.setdefault(code, []).append(e)
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
        if "slot" in e:     # S3-2: unbounded by definition, so no braces
            out.append(("[" if e["min"] == 0 else "") + f"{e['slot'] or 'open slot'} etc." + ("]" if e["min"] == 0 else ""))
            continue
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
    if "slot" in e:
        return ("slot", e["slot"])
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


def fold_triggers(fold, sid, entries):
    """A fold's trigger; a general fold onto CODE^* whose structure ID is the code (ACK) also
    takes OTHER^* for each other message code a caption prints with that structure ID (v2.4
    CH02 2.14.2 prints MCF^varies^ACK: P8b-final F-I1 d), since the caption gives that code the
    structure for every event."""
    out = [fold["trigger"]]
    if fold["trigger"] == f"{sid}^*":
        out += [t for t in dict.fromkeys(f"{c.code}^*" for c, _, _ in entries if c.code != sid) if t not in out]
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


def _names_print(name, cap):
    """Whether a primaryPrints print name is this caption: the caption as printed, or, to tell
    apart prints under one caption (v2.3 ORM^O01, four prints; S3-3), "CAPTION (section N)"."""
    return name in (cap.printed, f"{cap.printed} (section {cap.section})")


def _stricter(entry):
    """A primaryPrints entry's stricter prints: one name, or a list of them (S3-3)."""
    return [entry["stricter"]] if isinstance(entry["stricter"], str) else entry["stricter"]


def _profile(cap):
    """Whether a caption sits in the Conformance chapter (CH02B, sections 2.B.x)."""
    return cap.section.startswith("2.B.") or "CH02B" in os.path.basename(cap.source).upper()


# v2.3.1 prints the heading without "HL7" (CH2 2.24.1.9, p 2-103; P8b-14 fix round 1).
TABLE_0354_HEADING = re.compile(r"^\s*(?:HL7 )?Table 0354\s*[-\u2013]\s*Message [Ss]tructure\s*$")


def table_0354_rows(texts, era):
    """Where the version prints Table 0354: {structure ID: (chapter, section, page)} for each
    row, read from the chapter text after the table's heading. {} when the texts carry no
    table (a synthetic or partial read, or a version that borrows another's table)."""
    for source, lines in texts:
        start = next((i for i, l in enumerate(lines) if TABLE_0354_HEADING.match(l.replace("\f", ""))), None)
        if start is None:
            continue
        pages = page_labels(lines)
        # The table's own heading ("2.C.2.279 0354 - Message Structure", v2.8.2 CH02C), else the
        # section the table sits in.
        own = next((m.group(1) for m in (re.match(r"^\s*(\d+[A-Z]?(?:\.[A-Z])?(?:\.\d+)+)\s+0354\b", lines[j])
                                         for j in range(start, max(start - 15, -1), -1)) if m), None)
        section = own or next((h[0] for h in (heading(lines[j].replace("\f", ""), era, source)
                                              for j in range(start, -1, -1) if not re.search(r"\.{5,}", lines[j])) if h), "")
        chapter = re.search(r"CH(\d+[A-Z]?)", os.path.basename(source).upper())
        rows = {}
        for i in range(start, len(lines)):
            m = re.match(r"^\s*([A-Z][A-Z0-9]{2}(?:_[A-Z0-9]{3})?)\s", lines[i])
            if m and m.group(1) not in rows:
                rows[m.group(1)] = (chapter.group(1).lstrip("0") if chapter else "", section, pages[i])
        return rows
    return {}


def withdrawn_events(texts, era):
    """{CODE^EVT: (chapter, section)} for every section heading that marks its message withdrawn,
    keyed by the message codes the title opens with ("8.8.2 MFN/MFK - Master File Notification -
    Test/Observation [WITHDRAWN] (Event M03)", v2.8.2 CH08, the title wrapping onto the next
    line)."""
    out = {}
    for source, lines in texts:
        for i, raw in enumerate(lines):
            h = heading(raw.replace("\f", ""), era, source)
            if not h or re.search(r"\.{5,}", raw):
                continue
            title = h[1]
            nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
            if "(" not in title and nxt.startswith("[") and "(" in nxt:
                title += " " + nxt
            if "withdrawn" not in title.lower():
                continue
            codes = re.match(r"^([A-Z][A-Z0-9]{2}(?:\s*/\s*[A-Z][A-Z0-9]{2})*)\s*[-\u2013]", title)
            for code in re.findall(r"[A-Z][A-Z0-9]{2}", codes.group(1)) if codes else []:
                for event in title_events(title):
                    out.setdefault(f"{code}^{event}", (h[0].split(".")[0], h[0]))
    return out


def extract_version(version, texts, overrides, only=None, bundles=None, tables=None, full=False):
    """Read every caption of one version. texts: [(source, lines)] in reading order. Returns
    (structures by ID, report rows, caption count). A report row is (structure, status, reason).
    bundles: the HL7 v2.xml bundles (default none, so every unprinted name is an override or
    synthesised). tables: Table 0354 rows (default: the version's own; v2.3 reads none). full: the
    texts are the whole print, so an exclusion or erratum that matches nothing is an error."""
    ver = version.lstrip("v")
    era = ERAS[f"v{ver}"][1]
    bundles = bundles if bundles is not None else Bundles()
    errata = [e for e in overrides["errata"] if e["version"] == ver]
    used_errata = set()
    table_ver = ver
    row_errata = {}
    table = [] if era == "section-title" else apply_table_errata(
        tables if tables is not None else load_0354(table_ver),
        [e for e in overrides["errata"] if e["version"] == table_ver], used_errata, row_errata)
    excluded = {x["section"]: x for x in overrides["exclusions"] if x["version"] == ver}
    used_exclusions = set()
    caption_errata = {}
    for e in errata:
        if e["where"] == "caption":
            caption_errata.setdefault(e["printed"], []).append(e)
    seen_captions = {}     # captions printed so far, per CODE^EVT as printed (a caption erratum's occurrence)
    folds = {f["structure"]: f for f in overrides["triggerFolds"] if f["version"] == ver}
    # A fold onto CODE^* whose structure ID is the code itself (ACK): every caption of that code
    # is the one structure, so it needs no event and no Table 0354 row (v2.3 and v2.3.1 print no
    # ACK row; their general acknowledgment caption prints the code alone).
    general = {sid for sid, f in folds.items() if f["trigger"] == f"{sid}^*"}
    shared = {e["trigger"]: sorted(e["structures"]) for e in overrides["sharedTriggers"] if e["version"] == ver}
    unresolved = {(u["section"], u["caption"]): u for u in overrides["unresolvedCaptions"] if u["version"] == ver}
    keyed = {e["structure"]: e for e in overrides["keyedChoices"] if e["version"] == ver}     # S4-1
    keyed_captions = {e["caption"] for e in keyed.values()}
    used_keyed = set()
    assigned = {(u["section"], u["caption"]): u for u in overrides["captionStructures"] if u["version"] == ver}
    # Table 0354 row: its message code, the code the row prints before "_" (the ACK row: ACK itself).
    rows_of_table = {row: row.split("_")[0] for row, _, _ in table}
    used_unresolved, used_assigned, assigned_cites = set(), set(), {}
    provenance = {}     # structure ID: how its Table 0354 resolutions went (P8b-14 fix round 1)
    # v2.3 (P8b-15): events for a code-alone caption whose title names none; an entry with an
    # occurrence is preferred over one without for the n-th such caption of its section.
    title_events_for = {}
    for e in sorted((e for e in overrides.get("eventsFromTitle", []) if e["version"] == ver),
                    key=lambda e: "occurrence" not in e):
        title_events_for.setdefault((e["section"], e["caption"]), []).append(e)
    seen_untitled, used_titles = {}, set()
    prints, count, report = {}, 0, []
    for source, lines in texts:
        consumed = set()
        for cap in captions(lines, era, source, bare=general):
            if cap.line in consumed:
                continue
            count += 1
            printed_as = f"{cap.code}^{cap.event}"
            seen_captions[printed_as] = seen_captions.get(printed_as, 0) + 1
            fix = next((e for e in caption_errata.get(printed_as, [])
                        if e.get("occurrence") in (None, seen_captions[printed_as])), None)
            try:
                rows, error = syntax_rows(lines, cap, claimed=cap.printed in keyed_captions), None
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
            if era == "section-title" and not cap.events and cap.code not in general:
                key = (cap.section, cap.code)
                seen_untitled[key] = seen_untitled.get(key, 0) + 1
                entry = next((e for e in title_events_for.get(key, [])
                              if e.get("occurrence") in (None, seen_untitled[key])), None)
                if entry:
                    used_titles.add(id(entry))
                    cap.events, cap.event, cap.events_from = list(entry["events"]), ",".join(entry["events"]), entry["citation"]
            if not cap.events and cap.code not in general:
                report.append((f"{cap.code}^{cap.event or '?'}", "needs-event",
                               f"{cap.source} line {cap.line + 1}: section {cap.section} {cap.section_title[:60]!r} "
                               "names no event"))
                continue
            if era == "section-title" and not cap.structure:
                # v2.3 prints no structure ID and no Table 0354 (lookup rule 3): CODE_EVT, the first event.
                cap.structure, cap.id_source = f"{cap.code}_{cap.events[0]}", "synthesised"
            owners = [cap.structure] if cap.structure else []
            if not cap.structure:
                hits = resolve_structure(table, cap.code, cap.events)
                # P8b-14: every event of a caption two rows list is a declared shared trigger of
                # exactly those structures: the print is the print of each (v2.3.1 ADT^A28, A31).
                declared_id = assigned.get((cap.section, cap.printed)) if len(hits) != 1 else None
                if len(hits) > 1 and all(shared.get(f"{cap.code}^{v}") == hits for v in cap.events):
                    owners = hits
                elif declared_id and declared_id["structure"] not in rows_of_table:
                    used_assigned.add((cap.section, cap.printed))
                    report.append((cap.printed, "error", f"captionStructures entry for section {cap.section} names "
                                   f"{declared_id['structure']}, which is not a Table 0354 v{table_ver} row"))
                    continue
                elif declared_id and rows_of_table[declared_id["structure"]] != cap.code:
                    # P8b-18: the row's own message code, looked up in the table, not the entry's ID prefix.
                    used_assigned.add((cap.section, cap.printed))
                    report.append((cap.printed, "error", f"captionStructures entry for section {cap.section} names "
                                   f"{declared_id['structure']}, a row of another message code"))
                    continue
                elif declared_id:
                    # A cited captionStructures entry: the row the print belongs to (P8b-14).
                    used_assigned.add((cap.section, cap.printed))
                    owners = [declared_id["structure"]]
                    assigned_cites.setdefault(owners[0], []).append(declared_id["citation"])
                elif len(hits) != 1:
                    why = (f"Table 0354 (v{table_ver}) has no row for it" if not hits else
                           f"Table 0354 (v{table_ver}) maps it to {', '.join(hits)}" if table else
                           "no Table 0354")
                    where = f"{cap.source} line {cap.line + 1} (section {cap.section}): {why}"
                    declared = unresolved.get((cap.section, cap.printed))
                    if declared:
                        used_unresolved.add((cap.section, cap.printed))
                        where += f"; declared, not modelled (overrides.json unresolvedCaptions): {declared['citation']}"
                    report.append((f"{cap.code}^{cap.event}", "needs-structure-id", where))
                    # With its own Table 0354, an undeclared caption is a gap to settle (P8b-14).
                    if full and table and table_ver == ver and not declared:
                        report.append((f"{cap.code}^{cap.event}", "error", f"needs-structure-id: {where}: cite a "
                                       "Table 0354 erratum, declare the shared triggers, or declare it in unresolvedCaptions"))
                    continue
                else:
                    owners = hits
                cap.structure = owners[0]
                how = ("shared", tuple(hits), cap.printed) if len(owners) > 1 else \
                      ("assigned", cap.printed) if declared_id else ("row",)
                for sid in owners:
                    provenance.setdefault(sid, []).append(how)
            for sid in owners:
                prints.setdefault(sid, []).append((cap, rows, error))
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
            cells.setdefault(e["structure"], {}).setdefault(e["printed"], []).append(e)
    structures, used, owner, bundle_rows = {}, set(), {}, []
    # P8b-11 fix-round ruling: a structure accepts every trigger Table 0354 of its own version maps
    # to it, as well as the triggers its captions print (a borrowed table, v2.3's, adds none).
    rows_0354 = {code: events for code, events, _ in table if events} if table_ver == ver else {}
    where_0354 = table_0354_rows(texts, era) if rows_0354 else {}
    withdrawn = withdrawn_events(texts, era) if rows_0354 else {}
    added = {}
    for sid, entries in prints.items():
        if sid in folds or sid not in rows_0354:
            continue
        printed = {v for c, _, _ in entries for v in c.events}
        codes = sorted({c.code for c, _, _ in entries})
        missing = [v for v in rows_0354[sid] if v not in printed]
        if missing and len(codes) != 1:
            report.append((sid, "0354-trigger-ambiguous", f"Table 0354 v{ver} maps {', '.join(missing)} to {sid}, "
                                                          f"printed under several message codes ({', '.join(codes)})"))
        elif missing:
            added[sid] = [f"{codes[0]}^{v}" for v in missing]

    def read(sid, rows, error, log=None, names_used=None):
        if error:
            raise error
        rows = [Row(closes[sid][r.desc]["intended"], r.desc, r.line, r.page) if not r.left and r.desc in closes.get(sid, {})
                else r for r in rows]
        used_errata.update(id(closes[sid][r.desc]) for r in rows if r.desc in closes.get(sid, {}))
        rows = _cells_fixed(rows, cells[sid], used_errata) if sid in cells else rows
        seen = set()
        tree = parse(rows, {k: v["intended"] for k, v in marks.get(sid, {}).items()}, seen, keyed.get(sid))
        if sid in keyed and not _holds_keyed(tree):
            raise UnknownNotation(f"keyedChoices placeholder {keyed[sid]['printed']!r} not found in the print")
        used_keyed.update([sid] if sid in keyed else [])
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
            # The cited looser print overrides the primary-print rule; every named print must exist.
            k = next((j for j, e in enumerate(entries) if _names_print(chosen["primary"], e[0])), None)
            if k is None or not all(any(_names_print(s, e[0]) for e in entries) for s in _stricter(chosen)):
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
            if uncited(theirs) != uncited(elements):
                report.append((sid, "duplicate-differs", f"{c.printed} (section {c.section}) prints "
                               f"{compact(theirs)[:160]!r}; primary {cap.printed} (section {cap.section}) prints "
                               f"{compact(elements)[:160]!r}"))
        triggers = fold_triggers(fold, sid, entries) if fold else triggers + [t for t in added.get(sid, []) if t not in triggers]
        referenced = [t for e in overrides.get("referencedTriggers", []) if e["version"] == ver and e["structure"] == sid
                      for t in e["triggers"] if t not in triggers]
        triggers += referenced
        cite_slots(elements, ver, cap)
        structures[sid] = validate_names({"structure": sid, "version": ver, "triggers": triggers, "elements": elements,
                                          "citation": citation(ver, cap, others, overrides, sid)
                                          + (f" {primaries[sid]['citation']}" if sid in primaries else "")
                                          + (f" {joined['citation']}" if joined else "")
                                          + "".join(f" {c}" for c in dict.fromkeys(assigned_cites.get(sid, [])))
                                          + table_provenance(ver, table_ver, era, sid, provenance.get(sid),
                                                             row_errata.get(sid), where_0354)
                                          + table_citation(ver, sid, added.get(sid), where_0354, withdrawn)
                                          + synthesised_provenance(era, sid, entries, fold)
                                          + "".join(f" Trigger {t} from the caption {c.printed} (section {c.section}, p {c.page})"
                                                    f", which prints this structure ID for that message code."
                                                    for t in (fold_triggers(fold, sid, entries)[1:] if fold else [])
                                                    for c in [next(c for c, _, _ in entries if f"{c.code}^*" == t)])
                                          + "".join(f" Triggers {_join(e['triggers'])} added by overrides.json referencedTriggers "
                                                    f"(the print names this structure for them in prose): {e['citation'].rstrip('.')}."
                                                    for e in overrides.get("referencedTriggers", [])
                                                    if e["version"] == ver and e["structure"] == sid)
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
            report.append((sid, "bundle-differs", f"{_v2xml.folder(ver)}/{sid}.xsd is unreadable: {bundles.defects[(ver, sid)]}"))
        report.append((sid, "parsed", f"{len(entries)} caption(s)"))
    report += resolve_keyed_choices(ver, structures, keyed)
    report += add_aliases(ver, structures, overrides, full)
    referenced_by = {}
    for e in overrides.get("referencedTriggers", []):
        if e["version"] == ver:
            referenced_by.setdefault(e["structure"], []).extend(e["triggers"])
            # P8b-18: a referenced trigger carries the structure's own message code (the prose names
            # that message for the event); another code is a different message, never a reference.
            report += [(e["structure"], "error", f"referencedTriggers entry adds {t}, whose message code is not "
                        f"{e['structure'].split('_')[0]}") for t in e["triggers"]
                       if t.split("^")[0] != e["structure"].split("_")[0]]
    for sid in sorted(prints):     # every printed structure, parsed or not, claims its triggers
        fold = folds.get(sid)
        # P8b-18: referenced triggers enter the shared-trigger check like printed ones.
        for trig in fold_triggers(fold, sid, prints[sid]) + referenced_by.get(sid, []) if fold else dict.fromkeys(
                [f"{c.code}^{v}" for c, _, _ in prints[sid] for v in c.events] + added.get(sid, [])
                + referenced_by.get(sid, [])):
            owner.setdefault(trig, []).append(sid)
    # P8b-final (F-I1 c): a registered (not modelled) structure's triggers claim the trigger too,
    # as the codegen guard counts them (a Deprecated Table 0354 row's events, M4).
    for sid, trigs in registered_triggers(ver).items():
        for trig in trigs:
            if sid not in owner.setdefault(trig, []):
                owner[trig].append(sid)
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
        report += [(sid, "error", "keyedChoices entry matches no read print") for sid in sorted(keyed) if sid not in used_keyed]
        report += [(key[1], "error", f"unresolvedCaptions entry for section {key[0]} matches no unresolved caption")
                   for key in sorted(set(unresolved) - used_unresolved)]
        report += [(key[1], "error", f"captionStructures entry for section {key[0]} matches no unresolved caption")
                   for key in sorted(set(assigned) - used_assigned)]
        report += [(e["structure"], "error", "referencedTriggers entry names no structure read from the print")
                   for e in overrides.get("referencedTriggers", []) if e["version"] == ver and e["structure"] not in structures]
        report += [(e["caption"], "error", f"eventsFromTitle entry for section {e['section']}"
                                           + (f" (occurrence {e['occurrence']})" if "occurrence" in e else "")
                                           + " matches no caption whose section title names no event")
                   for entries in title_events_for.values() for e in entries if id(e) not in used_titles]
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
        return []
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


COMPLETENESS = os.path.join(STRUCTURES, "completeness.json")
# A registered structure whose Table 0354 row the printed table's Comment column marks
# Deprecated (v2.7.1, v2.8.2); its reason says so in these words.
DEPRECATED_ROW = "Comment column marks it"


def registered_triggers(ver):
    """{structure: [CODE^EVT]} of every completeness.json notModelled entry of `ver` that
    carries triggers."""
    with open(COMPLETENESS, encoding="utf-8") as f:
        entries = json.load(f)["versions"].get(ver, {}).get("notModelled", [])
    return {e["structure"]: e["triggers"] for e in entries if e.get("triggers")}


def deprecated_row_triggers(ver, overrides):
    """{structure: [CODE^EVT]} for each completeness.json notModelled entry of `ver` whose
    Table 0354 row is marked Deprecated: the events that row prints (cited table-0354 errata
    applied), each under the message code the structure ID opens with, in row order (P8b-final,
    M4). The table prints events, never a message code; the ID's code is the code of the
    message the row's structure served. A row that lists no events ('Deprecated and removed as
    of V2.7') gives []."""
    with open(COMPLETENESS, encoding="utf-8") as f:
        entries = json.load(f)["versions"].get(ver, {}).get("notModelled", [])
    errata = [e for e in overrides["errata"] if e.get("version") == ver]
    table = {code: events for code, events, _ in apply_table_errata(load_0354(ver), errata, set())}
    return {e["structure"]: [f"{e['structure'][:3]}^{ev}" for ev in (table.get(e["structure"]) or [])]
            for e in entries if DEPRECATED_ROW in e["reason"]}


def sync_deprecated_triggers(versions, overrides, write):
    """Compare (or, with write, set) the triggers of every Deprecated-row registration in
    completeness.json with deprecated_row_triggers. Edits only the `"triggers": [...]` of those
    entries, one entry per line, so the hand-curated reasons and layout are untouched. Returns
    the entries that differ (before any write)."""
    wanted = {ver: deprecated_row_triggers(ver, overrides) for ver in versions}
    with open(COMPLETENESS, encoding="utf-8") as f:
        lines = f.read().split("\n")
    diffs, ver = [], None
    for i, line in enumerate(lines):
        head = re.match(r'^\s*"(\d+(?:\.\d+)+)": \{', line)
        if head:
            ver = head.group(1)
            continue
        m = re.match(r'^(\s*\{"structure": "([^"]+)", "triggers": )(\[[^\]]*\])(.*)$', line)
        if not m or ver not in wanted or m.group(2) not in wanted[ver]:
            continue
        new = json.dumps(wanted[ver][m.group(2)])
        if json.loads(m.group(3)) != wanted[ver][m.group(2)]:
            diffs.append(f"v{ver} {m.group(2)}: triggers {m.group(3)} should be {new} (Table 0354 row, Deprecated)")
            lines[i] = m.group(1) + new + m.group(4)
    if write and diffs:
        with open(COMPLETENESS, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
    return diffs


def withdrawn_segments(ver, overrides):
    """{segment: overrides.json withdrawnSegments entry} for `ver` (S2-1)."""
    return {e["segment"]: e for e in overrides["withdrawnSegments"] if e["version"] == ver}


def grammar_segments(ver):
    """The segment IDs the version's grammar defines: its Resources/schemas file names."""
    folder = os.path.join(REPO, "Resources", "schemas", f"v{ver}")
    return {f[:-5] for f in os.listdir(folder) if f.endswith(".json")} if os.path.isdir(folder) else set()


def outside_grammar(ver, structure, overrides):
    """The segments `structure` names that the version's grammar does not define, that are not
    ADD and that no withdrawnSegments entry of the version lists (codegen guard 3)."""
    named = set().union(*(_segments(e) for e in structure["elements"]))
    return sorted(named - grammar_segments(ver) - {"ADD"} - set(withdrawn_segments(ver, overrides)))


def with_withdrawn_note(ver, structure, overrides):
    """The structure with its citation naming the withdrawn segments it prints (S2-1)."""
    withdrawn = withdrawn_segments(ver, overrides)
    named = set().union(*(_segments(e) for e in structure["elements"]))
    hits = [s for s in sorted(named) if s in withdrawn]
    if not hits:
        return structure
    status = _join(sorted({withdrawn[s]["printed"] for s in hits}))
    through = _join(sorted({withdrawn[s]["definedThrough"] for s in hits}))
    verb = "is" if len(hits) == 1 else "are"
    note = (f" {_join(hits)} {verb} listed as {status} by v{ver} Appendix A and defined through v{through} "
            "(overrides.json withdrawnSegments): matched by segment ID, fields not validated.")
    return {**structure, "citation": structure["citation"] + note}


def sync_modelled_registrations(versions, write):
    """A structure committed under Resources/structures/v<ver> is modelled, so a completeness.json
    notModelled entry for it is stale: compare (or, with write, remove) such entries. Removes only
    the entry's own line (and the comma it leaves dangling), so the hand-curated reasons and layout
    of the others are untouched. Returns the entries that differ (before any write)."""
    with open(COMPLETENESS, encoding="utf-8") as f:
        lines = f.read().split("\n")
    diffs, ver, keep = [], None, []
    for line in lines:
        head = re.match(r'^\s*"(\d+(?:\.\d+)+)": \{', line)
        if head:
            ver = head.group(1)
        m = re.match(r'^\s*\{"structure": "([^"]+)", "triggers": ', line)
        if m and ver in versions and os.path.exists(os.path.join(STRUCTURES, f"v{ver}", f"{m.group(1)}.json")):
            diffs.append(f"v{ver} {m.group(1)}: registered as not modelled but committed (modelled)")
            if not line.rstrip().endswith(",") and keep and keep[-1].rstrip().endswith(","):
                keep[-1] = keep[-1].rstrip()[:-1]
            continue
        keep.append(line)
    if write and diffs:
        with open(COMPLETENESS, "w", encoding="utf-8") as f:
            f.write("\n".join(keep))
    return diffs


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
    return (f"v{version.lstrip('v')} names: {names.count('v2xml')} v2xml, {names.count('v2xml-v2.3.1')} v2xml-v2.3.1, "
            f"{names.count('v2xml-v2.4')} v2xml-v2.4, "
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
        # v2.3.1 needs its own bundle and the v2.4 one (its fallback, P8b-14); v2.3 the v2.3.1 and
        # v2.4 ones (P8b-15).
        needed = ([version] if version in BUNDLES else []) + list(BUNDLES_DERIVED.get(version, ()))
        if any(not bundles.available(v[1:]) for v in needed):
            print(f"{version}: no HL7 v2.xml bundle at docs/XML-schemas/"
                  f"{', '.join(BUNDLES[v] for v in needed if not bundles.available(v[1:]))} (group names need it)")
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
        structures = {sid: with_withdrawn_note(version[1:], s, overrides) for sid, s in structures.items()}
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
            outside = outside_grammar(version[1:], structures[sid], overrides)
            if outside:
                print(f"  {sid}: names segments outside the {version} grammar and not withdrawnSegments: {outside}")
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
    if args.check or args.write:
        # M4 (P8b-final): a Deprecated Table 0354 row's registration carries the row's events.
        for line in sync_deprecated_triggers([v[1:] for v in versions], overrides, args.write):
            print(f"  {line}" + (": written" if args.write else ""))
            failed |= bool(args.check)
        # S2-2: a committed structure's registration as not modelled is removed.
        for line in sync_modelled_registrations([v[1:] for v in versions], args.write):
            print(f"  {line}" + (": removed" if args.write else ""))
            failed |= bool(args.check)
    if args.report:
        with open(args.report, "w", encoding="utf-8") as f:
            f.writelines("\t".join(r) + "\n" for r in tsv)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
