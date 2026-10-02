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
import argparse, collections, functools, glob, json, os, re, shutil, subprocess, sys, tempfile

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


def whitelisted_ids(version):
    """The DEPTH_WHITELIST segment IDs that apply to `version` (a bare ID applies everywhere)."""
    return {w.split("/")[-1] for w in DEPTH_WHITELIST if "/" not in w or w.startswith(version + "/")}


@functools.lru_cache(maxsize=None)
def _pdf_text(path):
    return subprocess.run(["pdftotext", "-layout", "-enc", "UTF-8", path, "-"],
                          capture_output=True, text=True, timeout=30).stdout


def caption_present(version, seg):
    """True when a chapter of `version` prints `seg`'s attribute-table caption:
    "HL7 Attribute Table - ADD" (v2.4 on) or "Figure 2-8. ADD attributes" (v2.3, v2.3.1)."""
    pattern = re.compile(rf"HL7 Attribute Table\s*[-–]\s*{seg}\b|\b{seg} attributes\b")
    return any(pattern.search(_pdf_text(pdf))
               for glob_pattern in CHAPTER_GLOBS[version]
               for pdf in sorted(glob.glob(os.path.join(STANDARDS, glob_pattern))))


# Owner-deferred versions. The 2026-08-23 deferral of v2.6 / v2.8.2 closed with M5 on
# 2026-09-16 (docs/design/deferred-coverage-backlog.md, closure header), so the set is empty:
# on every version a segment modelled elsewhere but absent here is a PRESENCE defect.
# Re-adding a version needs an owner decision recorded in that backlog.
DEFERRED_VERSIONS = set()

# M6-O5 dataType predicate knobs.
#
# Pre-v2.5 attribute tables type most composites as the placeholder `CM`
# ("composite, defined in the field definition"). A schema may carry the
# v2.5-era NAME instead only where that name's structure is the field's own,
# because grammar-level composite dispatch keys on it — e.g. the HL7au:00049.1
# overlay rule reaches v2.4 MSH-9 only because it is typed MSG. A spec `CM`
# therefore accepts only a name in the enumerated CM_REFINEMENTS set below;
# any other name against a spec `CM`, scalar or composite, flags. Scalar set
# mirrors `scalarDataTypes` in Codegen.swift.
SCALAR_DATATYPES = {"SI", "ID", "IS", "ST", "NM", "DT", "TM", "TS", "FT", "TX", "DTM"}

# P5 (V24-C08): the exception class is enumerated. A spec `CM` may carry a v2.5-era name
# only when that name's structure is the field's own: MSG (v2.3 MSH-9 prints the first two
# of its three components; v2.5 appended message structure), MOC (OBR-23 <dollar amount (MO)>
# ^ <charge code (CE)>), PRL (OBR-26 <OBX-3 (CE)> ^ <OBX-4 (ST)> ^ <part of OBX-5 (TX)>),
# EIP (OBR-29 / ORC-8 <placer (EI)> ^ <filler (EI)>). SPS and NDL are not (v2.4 OBR-15.2
# additives TX vs SPS.2 CWE; OBR-32.1 CN vs NDL.1 CNN): those fields stay CM, and their
# components come from the field grammar (DataTypeGrammarTable.grammar(segment:field:version:)).
CM_REFINEMENTS = {"MSG", "MOC", "PRL", "EIP"}

# (version, segment, index) -> citation: slots where the schema deliberately diverges from
# the extracted attribute-table value. Every entry names its source (check-audit-schemas.py
# fails an entry without one).
#   v2.8.2/RF1/18 — the CH11 attribute table prints `M0` (zero), a misprint:
#                 the field heading (§11.8.1.18) and the same element at
#                 AUT-22 (table row and §11.8.2.22) print `MO`. `M0` is no
#                 datatype, so following it would skip the MO grammar.
DATATYPE_WHITELIST = {
    ("v2.4", "AL1", 1): "v2.4 CH3 AL1 attribute table and heading print CE for Set ID - AL1, a "
                        "spec typo (SI in v2.3 and v2.5+); registered in segment-coverage-extraction.md",
    ("v2.3", "QRD", 11): "v2.3 CH2 sec 2.24.4.11 heading prints QRD-11 (CM) with Components: "
                         "<first data code value (ST)> ^ <last data code value (ST)>; the attribute "
                         "table prints ST. The printed Components line wins (P5 final review), as "
                         "v2.3.1 and v2.4 type it CM in both places",
    ("v2.5.1", "OBX", 5): "v2.5.1 CH7 OBX-5 variable-type row defeats the extractor (candidates *, "
                          "'NA or', 'varie'); schema `varies` hand-verified in M6-D5",
    ("v2.8.2", "RF1", 18): "v2.8.2 CH11 RF1-18 attribute table prints `M0` (zero), a misprint; "
                           "field heading §11.8.1.18 and AUT-22 (table row and §11.8.2.22) print `MO`",
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
# from the printed OPT column that the spec text itself backs. P4-30: a schema field may instead
# carry the citation itself as "optionalityCitation" (the single source for new divergences, as
# "tableOpenCitation" is for openness); see optionality_citation_finding. Anything else is a
# finding.
OPTIONALITY_WHITELIST = {
    ("v2.3", "DG1", 2): "v2.3 CH6 DG1 attribute table prints '(B) R' in one OPT cell; the "
                        "extractor reads B, the schema keeps R",
    ("v2.3.1", "DG1", 2): "v2.3.1 CH6 DG1 attribute table prints '(B) R' in one OPT cell; the "
                          "extractor reads B, the schema keeps R",
    ("v2.6", "ORC", 8): "v2.6 CH04 section 4.5.1.8: 'If the parent is not present in the ORC, it "
                        "must be present in the associated OBR'; printed O, modelled C (V26-C13)",
    ("v2.6", "OBR", 29): "v2.6 CH04 section 4.5.3.29: required when the order is a child; printed "
                         "O, modelled C (V26-C13)",
    ("v2.3", "ORC", 8): "v2.3 CH04 section 4.3.1.1.1 'i) PA, CH': 'Whenever a child order is "
                       "transmitted in a message the ORC segment's ORC-8-parent is valued with "
                       "the parent's filler order number ... and with the parent's placer order "
                       "number'; printed O, modelled C (P4-18)",
    ("v2.3", "OBR", 29): "v2.3 CH04 section 4.5.1.29: 'It is required when the order is a child.'; "
                        "printed O, modelled C (P4-18)",
    ("v2.3.1", "ORC", 8): "v2.3.1 CH04 section 4.3.1.1.1 'i) PA, CH': 'Whenever a child order is "
                         "transmitted in a message the ORC segment's ORC-8-parent is valued with "
                         "the parent's filler order number ... and with the parent's placer order "
                         "number'; printed O, modelled C (P4-18)",
    ("v2.3.1", "OBR", 29): "v2.3.1 CH04 section 4.5.1.29: 'It is required when the order is a "
                          "child.'; printed O, modelled C (P4-18)",
    ("v2.4", "ORC", 8): "v2.4 CH04 section 4.5.1.8: 'If the parent is not present in the ORC, it "
                       "must be present in the associated OBR'; printed O, modelled C (P4-18)",
    ("v2.4", "OBR", 29): "v2.4 CH04 section 4.5.3.29: 'It is required when the order is a child.'; "
                        "printed O, modelled C (P4-18)",
    ("v2.5.1", "ORC", 8): "v2.5.1 CH04 section 4.5.1.8: 'If the parent is not present in the ORC, "
                         "it must be present in the associated OBR'; printed O, modelled C (P4-18)",
    ("v2.5.1", "OBR", 29): "v2.5.1 CH04 section 4.5.3.29: 'It is required when the order is a "
                          "child.'; printed O, modelled C (P4-18)",
}
# The schema `repeatability` vocabulary: "1", "*", or a decimal RP/# bound of 2 or more (P6-4).
REPEATABILITY_TOKEN = re.compile(r"1|\*|[2-9]|[1-9]\d{1,2}")
REPEATABILITY_WHITELIST = {
    ("v2.6", "OBX", 5): "v2.6 CH07 section 7.4.2 OBX attribute table prints RP/# 'Y' wrapped under a "
                       "superscript footnote marker '2', which the extractor reads as a bound; the "
                       "CH09 constrained OBX prints a blank. 7.4.2.5 'may repeat for multipart, single "
                       "answer results'; schema '*' (P6-4)",
}
# v2.3/v2.3.1 OBX-5: the LEN cell prints a numeric cap (v2.3 Figure 7-5 "655362", v2.3.1
# Figure 7-5 "65536" + footnote marker, both extraction-glued footnote digits onto 65536) but the
# field's own footnote overrides it: v2.3 CH7 (p. 7-30) footnote 2 and v2.3.1 CH7 (p. 7-35)
# footnote 3 both read "The length of the observation value field is variable, depending
# upon value type. See OBX-2-value type." The schema keeps the variable-length placeholder
# `*`, matching the DT column's own printed `*` (P6-2 / pre-flight ruling d4). v2.4 to v2.6 print
# the same footnote over 65536 / 99999 (P6-12). v2.3's "655362" fails LENGTH_TOKEN, so its entry
# lives in UNREADABLE_WHITELIST.
LENGTH_WHITELIST = {
    ("v2.3.1", "OBX", 5): "v2.3.1 Figure 7-5 (p. 7-35) footnote 3: 'The length of the "
                         "observation value field is variable, depending upon value type. "
                         "See OBX-2-value type.' LEN cell prints 65536 (footnote marker "
                         "glued on); schema keeps the variable-length `*`",
    ("v2.4", "OBX", 5): "v2.4 CH07 section 7.4.2 OBX attribute table footnote 1: 'The length of "
                       "the observation field is variable, depending upon value type. See OBX-2 "
                       "value type.' LEN cell prints 65536; schema keeps the variable-length `*` "
                       "(P6-12)",
    ("v2.5.1", "OBX", 5): "v2.5.1 CH07 section 7.4.2 OBX attribute table (p. 7-42) footnote 1: 'The "
                         "length of the observation field is variable, depending upon value type. "
                         "See OBX-2 value type.' LEN cell prints 99999 (wrapped as 9999 / 9), the "
                         "section 2.5.3.2 symbol for a variable length; schema keeps `*` (P6-12)",
    ("v2.6", "OBX", 5): "v2.6 CH07 section 7.4.2 OBX attribute table footnote 1: 'The length of the "
                       "observation field is variable, depending upon value type. See OBX-2 value "
                       "type.' LEN cell prints 99999, the section 2.5.3.2 c) symbol for a variable "
                       "length; schema keeps `*` (P6-12; the M25 sweep had written 24)",
    ("v2.3", "MSH", 18): 'G10 (P6-6 fix 1): LEN cell prints 6, shorter than values the spec defines as valid; '
                         'section 2.24.1.18 binds the field to HL7 Table 0211 - Alternate character sets, whose '
                         "longest code is 'JIS X 0202' (10). Schema stores 10, the smallest length that admits "
                         'them (limitations register, section C)',
    ("v2.3", "OBX", 2): 'G10 (P6-6 fix 1): LEN cell prints 2 (Figure 7-5), shorter than values the spec defines '
                        'as valid; section 7.3.2.2 binds the field to HL7 Table 0125 - Value type, whose codes '
                        'are three letters (XAD, XCN). Schema stores 3, the smallest length that admits them '
                        '(limitations register, section C)',
    ("v2.3", "PEO", 25): 'G10 (P6-6 fix 1): LEN cell prints 1, shorter than values the spec defines as valid; '
                         'section 7.11.2.25 binds the field to HL7 Table 0243 - Identity may be divulged, which '
                         "includes 'NA'. Schema stores 2, the smallest length that admits them (limitations "
                         'register, section C)',
    ("v2.3.1", "MSH", 9): 'G10 (P6-6 fix 1): LEN cell prints 7, shorter than values the spec defines as valid; '
                          'section 2.24.1.9 defines three components <message type (ID)> ^ <trigger event (ID)> ^ '
                          '<message structure (ID)>; Tables 0076 and 0003 codes are 3 characters and Table 0354 '
                          "codes at most 7 (e.g. ADT_A01); Table 0354 also prints 'SIIU_S12', a misprint of the "
                          'SIU_S12 structure Chapter 10 defines, not counted, so ADT^A01^ADT_A01 is 15. Schema '
                          'stores 15, the smallest length that admits them (limitations register, section C)',
    ("v2.3.1", "PEO", 25): 'G10 (P6-6 fix 1): LEN cell prints 1, shorter than values the spec defines as valid; '
                           'section 7.11.2.25 binds the field to HL7 Table 0243 - Identity may be divulged, which '
                           "includes 'NA'. Schema stores 2, the smallest length that admits them (limitations "
                           'register, section C)',
    ("v2.3.1", "TXA", 3): 'G10 (P6-6 fix 1): LEN cell prints 2, shorter than values the spec defines as valid; '
                          'section 9.5.1.3 binds the field to HL7 Table 0191 - Type of referenced data, whose '
                          "longest code is 'Application' (section 2.8.36 prints it). Schema stores 11, the smallest"
                          ' length that admits them (limitations register, section C)',
    ("v2.4", "MSH", 9): 'G10 (P6-6 fix 1): LEN cell prints 13, shorter than values the spec defines as valid; '
                        'section 2.16.9.9 defines three components <message type (ID)> ^ <trigger event (ID)> ^ '
                        '<message structure (ID)>; Tables 0076 and 0003 codes are 3 characters and Table 0354 '
                        'codes at most 7 (e.g. ADT_A01), so ADT^A01^ADT_A01 is 15; v2.5.1 prints 15. Schema '
                        'stores 15, the smallest length that admits them (limitations register, section C)',
    ("v2.4", "OBX", 2): 'G10 (P6-6 fix 1): LEN cell prints 2, shorter than values the spec defines as valid; '
                        'section 7.4.2.2 binds the field to HL7 Table 0125 - Value type, whose codes are three '
                        'letters (XAD, CWE). Schema stores 3, the smallest length that admits them (limitations '
                        'register, section C)',
    ("v2.4", "OM3", 7): 'G10 (P6-6 fix 1): LEN cell prints 2, shorter than values the spec defines as valid; '
                        'section 8.8.5.7 binds the field to HL7 Table 0125 - Value type, whose codes are three '
                        'letters (XAD, CWE). Schema stores 3, the smallest length that admits them (limitations '
                        'register, section C)',
    ("v2.4", "PEO", 25): 'G10 (P6-6 fix 1): LEN cell prints 1, shorter than values the spec defines as valid; '
                         'section 7.12.2.25 binds the field to HL7 Table 0243 - Identity may be divulged, which '
                         "includes 'NA'. Schema stores 2, the smallest length that admits them (limitations "
                         'register, section C)',
    ("v2.4", "TXA", 3): 'G10 (P6-6 fix 1): LEN cell prints 2, shorter than values the spec defines as valid; '
                        'section 9.6.1.3 binds the field to HL7 Table 0191 - Type of referenced data, whose '
                        "longest code is 'multipart'. Schema stores 9, the smallest length that admits them "
                        '(limitations register, section C)',
    ("v2.5.1", "OBX", 2): 'G10 (P6-6 fix 1): LEN cell prints 2, shorter than values the spec defines as valid; '
                          'section 7.4.2.2 binds the field to HL7 Table 0125 - Value type, whose codes are three '
                          'letters (XAD, CWE); v2.6 prints 3. Schema stores 3, the smallest length that admits them'
                          ' (limitations register, section C)',
    ("v2.5.1", "OM3", 7): 'G10 (P6-6 fix 1): LEN cell prints 2, shorter than values the spec defines as valid; '
                          'section 8.8.10.7 binds the field to HL7 Table 0125 - Value type, whose codes are three '
                          'letters (XAD, CWE). Schema stores 3, the smallest length that admits them (limitations '
                          'register, section C)',
    ("v2.5.1", "PEO", 25): 'G10 (P6-6 fix 1): LEN cell prints 1, shorter than values the spec defines as valid; '
                           'section 7.12.2.25 binds the field to HL7 Table 0243 - Identity may be divulged, which '
                           "includes 'NA'. Schema stores 2, the smallest length that admits them (limitations "
                           'register, section C)',
    ("v2.5.1", "TXA", 3): 'G10 (P6-6 fix 1): LEN cell prints 2, shorter than values the spec defines as valid; '
                          'section 9.6.1.3 binds the field to HL7 Table 0191 - Type of referenced data, whose '
                          "longest code is 'multipart'. Schema stores 9, the smallest length that admits them "
                          '(limitations register, section C)',
    ("v2.6", "PEO", 25): 'G10 (P6-6 fix 1): LEN cell prints 1, shorter than values the spec defines as valid; '
                         'section 7.12.2.25 binds the field to HL7 Table 0243 - Identity may be divulged, which '
                         "includes 'NA'. Schema stores 2, the smallest length that admits them (limitations "
                         'register, section C)',
    ("v2.6", "PSL", 21): 'G10 (P6-6 fix 1): LEN cell prints 2, shorter than values the spec defines as valid; '
                         'section 16.4.6.21 binds the field to HL7 Table 0532 - Expanded yes/no indicator, which '
                         "includes 'ASKU' and 'NASK'. Schema stores 4, the smallest length that admits them "
                         '(limitations register, section C)',
    ("v2.6", "TXA", 3): 'G10 (P6-6 fix 1): LEN cell prints 2, shorter than values the spec defines as valid; '
                        'section 9.6.1.3 binds the field to HL7 Table 0191 - Type of referenced data, whose '
                        "longest code is 'multipart'. Schema stores 9, the smallest length that admits them "
                        '(limitations register, section C)',
}

# P6-12: slots M19 / M22 / M25 cannot compare (see read_slot) are reported unless listed here,
# keyed (audit, version, segment, first index, last index, reason) -> the spec citation. The
# reason is the read_slot reason the region is cited for ("blank cell" or "malformed print"),
# so a region cited for blanks cannot hide a malformed print or a missing row. A cited blank is
# a print: the slot is then compared against "" like any other value, so the schema must store
# the blank verbatim (fix 1 ruling; a blank OPT is treated as optional, see the limitations
# register, addendum to section A).
BLANK_OPT = ("the spec defines no blank OPT code (v2.6 section 2.5.3.4); the schema stores the "
             "blank verbatim")
UNREADABLE_WHITELIST = {
    ("M19", "v2.3", "AIG", 2, 2, "blank cell"): "v2.3 CH10 section 10.5.5 Figure 10-7 AIG attributes (p. 10-42) "
                                 "prints the R/O/C cell of Segment Action Code blank; %s "
                                 "(settles the P6-10 'no optionality value' intake row)",
    ("M19", "v2.3.1", "NST", 2, 15, "blank cell"): "v2.3.1 Appendix C section C.2.2 Figure C-2 NST attributes prints "
                                    "OPT blank for every field after NST-1; %s",
    ("M19", "v2.4", "EDU", 2, 2, "blank cell"): "v2.4 CH15 section 15.4.2 EDU attribute table (p. 15-10) prints "
                                 "OPT blank for Academic Degree; %s",
    ("M19", "v2.4", "NSC", 2, 9, "blank cell"): "v2.4 CH14 section 14.4.2 NSC attribute table (p. 14-5) prints OPT "
                                 "blank for NSC-2 to NSC-9; %s",
    ("M19", "v2.4", "NST", 2, 15, "blank cell"): "v2.4 CH14 section 14.4.3 NST attribute table (p. 14-7) prints OPT "
                                  "blank for NST-2 to NST-15; %s",
    ("M19", "v2.4", "RCP", 7, 7, "blank cell"): "v2.4 CH05 section 5.5.5 RCP attribute table (p. 5-51) prints OPT "
                                 "(and TBL#) blank for Segment group inclusion; %s"
                                 " (see the v2.4/RCP-7 table repair)",
    ("M19", "v2.5.1", "NSC", 2, 9, "blank cell"): "v2.5.1 CH14 section 14.4.2 NSC attribute table (p. 14-5) prints "
                                   "OPT blank for NSC-2 to NSC-9; %s",
    ("M19", "v2.5.1", "NST", 2, 15, "blank cell"): "v2.5.1 CH14 section 14.4.3 NST attribute table (p. 14-7) prints "
                                    "OPT blank for NST-2 to NST-15; %s",
    ("M19", "v2.5.1", "OBX", 20, 22, "blank cell"): "v2.5.1 CH07 section 7.4.2 OBX attribute table (p. 7-42) prints "
                                     "OBX-20 to OBX-22 'Reserved for harmonization with V2.6' with "
                                     "every column blank, and 7.4.2.20 to 7.4.2.22 print the "
                                     "heading alone (no X anywhere); %s",
    ("M25", "v2.5.1", "OBX", 20, 22, "blank cell"): "v2.5.1 CH07 section 7.4.2 OBX attribute table (p. 7-42) prints "
                                     "OBX-20 to OBX-22 'Reserved for harmonization with V2.6' with "
                                     "every column blank; schema carries no length",
    ("M19", "v2.5.1", "RCP", 7, 7, "blank cell"): "v2.5.1 CH05 section 5.5.6 RCP attribute table (p. 5-48) prints "
                                   "OPT (and TBL#) blank for Segment group inclusion; %s"
                                   " (see the v2.5.1/RCP-7 table repair)",
    ("M19", "v2.6", "NSC", 2, 9, "blank cell"): "v2.6 CH14 section 14.4.2 NSC attribute table (p. 14-4) prints OPT "
                                 "blank for NSC-2 to NSC-9; %s",
    ("M19", "v2.6", "NST", 2, 15, "blank cell"): "v2.6 CH14 section 14.4.3 NST attribute table (p. 14-6) prints OPT "
                                  "blank for NST-2 to NST-15; %s",
    ("M19", "v2.6", "RCP", 7, 7, "blank cell"): "v2.6 CH05 section 5.5.6 RCP attribute table (p. 40) prints OPT "
                                 "(and TBL#) blank for Segment group inclusion; %s",
    ("M19", "v2.6", "PKG", 4, 4, "blank cell"): "v2.6 CH17 section 17.4.5 PKG attribute table (p. 17-17) prints OPT "
                                 "blank for Package Quantity; %s",
    ("M19", "v2.6", "STZ", 1, 4, "blank cell"): "v2.6 CH17 section 17.4.3 STZ attribute table (p. 17-15) prints OPT "
                                 "blank for every field; %s",
    ("M19", "v2.6", "SCP", 1, 8, "blank cell"): "v2.6 CH17 section 17.7.1 SCP attribute table (p. 17-30) prints "
                                 "R/O/C blank for every field; %s",
    ("M19", "v2.6", "SLT", 1, 5, "blank cell"): "v2.6 CH17 section 17.7.2 SLT attribute table (p. 17-32) prints "
                                 "R/O/C blank for every field; %s",
    ("M19", "v2.6", "SDD", 1, 7, "blank cell"): "v2.6 CH17 section 17.7.3 SDD attribute table (p. 17-33) prints "
                                 "R/O/C blank for every field; %s",
    ("M19", "v2.6", "SCD", 1, 37, "blank cell"): "v2.6 CH17 section 17.7.4 SCD attribute table (p. 17-34) prints "
                                  "R/O/C blank for every field; %s",
    ("M22", "v2.8.2", "BUI", 12, 12, "malformed print"): "v2.8.2 CH04 section 4.17.2 BUI attribute table prints RP/# 'R' "
                                     "for Transport Temperature Units (every other row prints N); R "
                                     "is not an RP/# value (section 2.5.3.5) and 4.17.2.12 says "
                                     "nothing of repetition; schema '1'",
    ("M25", "v2.3", "OBX", 5, 5, "malformed print"): "v2.3 CH7 Figure 7-5 (p. 7-30) footnote 2: 'The length of the "
                                 "observation value field is variable, depending upon value type. "
                                 "See OBX-2-value type.' LEN cell prints 65536, read as 655362 "
                                 "with the footnote marker glued on; schema keeps the "
                                 "variable-length `*`",
    ("M25", "v2.8.2", "TQ2", 6, 6, "malformed print"): "v2.8.2 CH04 section 4.5.5 TQ2 attribute table prints LEN '2..' "
                                   "for Sequence Condition Code, a range with no maximum (section "
                                   "2.5.5 prints min..max); schema keeps '2..' verbatim, and how it "
                                   "validates is P6-6's to decide",
    ("M25", "v2.7.1", "TQ2", 6, 6, "malformed print"): "v2.7.1 CH04 section 4.5.5 TQ2 attribute table (p. 80) prints "
                                   "LEN '2..' for Sequence Condition Code, a range with no maximum, "
                                   "as v2.8.2 does; schema keeps '2..' verbatim",
    ("M25", "v2.7.1", "RXG", 13, 13, "malformed print"): "v2.7.1 CH04A section 4A.4.6 RXG attribute table (p. 78) prints "
                                   "LEN '(1..250)' in parentheses for the CWE RXG-13, a shape section "
                                   "2.5.5 does not define; schema keeps the range '1..250' that the "
                                   "v2.8.2 table prints for the same element",
    ("M19", "v2.7.1", "RCP", 7, 7, "blank cell"): "v2.7.1 CH05 section 5.5.6 RCP attribute table (p. 46) prints "
                                   "OPT blank for Segment group inclusion (TBL# 0391 is printed); %s",
    ("M19", "v2.7.1", "ACC", 12, 12, "blank cell"): "v2.7.1 CH06 section 6.5.9 ACC attribute table (p. 126) prints "
                                    "OPT blank for Degree of patient liability; %s",
    ("M19", "v2.7.1", "NSC", 2, 9, "blank cell"): "v2.7.1 CH14 section 14.4.2 NSC attribute table (p. 3) prints R/O "
                                 "blank for NSC-2 to NSC-9; %s",
    ("M19", "v2.7.1", "NST", 2, 15, "blank cell"): "v2.7.1 CH14 section 14.4.3 NST attribute table (p. 6) prints R/O "
                                  "blank for NST-2 to NST-15; %s",
    ("M19", "v2.7.1", "STF", 41, 41, "blank cell"): "v2.7.1 CH15 section 15.4.8 STF attribute table (pp. 41 to 42) "
                                   "prints OPT blank for Signature; %s",
    ("M19", "v2.7.1", "STZ", 1, 4, "blank cell"): "v2.7.1 CH17 section 17.4.3 STZ attribute table (p. 19) prints OPT "
                                 "blank for every field; %s",
    ("M19", "v2.7.1", "PKG", 4, 4, "blank cell"): "v2.7.1 CH17 section 17.4.5 PKG attribute table (p. 22) prints OPT "
                                 "blank for Package Quantity; %s",
    ("M19", "v2.7.1", "SCP", 1, 8, "blank cell"): "v2.7.1 CH17 section 17.7.1 SCP attribute table (p. 40) prints "
                                 "R/O/C blank for every field; %s",
    ("M19", "v2.7.1", "SLT", 1, 5, "blank cell"): "v2.7.1 CH17 section 17.7.2 SLT attribute table (p. 42) prints "
                                 "R/O/C blank for every field; %s",
    ("M19", "v2.7.1", "SDD", 1, 7, "blank cell"): "v2.7.1 CH17 section 17.7.3 SDD attribute table (p. 43) prints "
                                 "R/O/C blank for every field; %s",
    ("M19", "v2.7.1", "SCD", 1, 37, "blank cell"): "v2.7.1 CH17 section 17.7.4 SCD attribute table (p. 44) prints "
                                  "R/O/C blank for every field; %s",
}
UNREADABLE_WHITELIST = {k: (v % BLANK_OPT if "%s" in v else v) for k, v in UNREADABLE_WHITELIST.items()}

# M9-A tables predicate. A TBL# cell is well-formed when it is one or more
# 4-digit table numbers joined by "/" (a field may bind more than one table:
# NK1-11 is 0327/0328). Anything else is the TOOL failing — a cell cut at a
# line wrap ("0327/") or a neighbouring column bleeding in ("01107") — and the
# slot must carry a hand-verified entry in scripts/table-repairs.json, keyed
# "<version>/<SEG>-<index>", with the citation it was verified against.
#
# Despite its name, the file carries hand-verified repairs for three columns: TBL# ("tables",
# required), RP/# ("repeatability", P6-5) and LEN ("length", P6-12). Keys starting "_" (the
# file's "_comment") are documentation, not slots.
TABLE_REPAIRS_PATH = os.path.join(REPO, "scripts/table-repairs.json")
_REPAIR_ENTRIES = ({k: v for k, v in json.load(open(TABLE_REPAIRS_PATH)).items() if not k.startswith("_")}
                   if os.path.exists(TABLE_REPAIRS_PATH) else {})
TABLE_REPAIRS = {k: v["tables"] for k, v in _REPAIR_ENTRIES.items()}
# P6-5: an entry's optional "repeatability" pins the printed RP/# cell where the same column
# shift defeats the extractor (v2.3.1 PCR, p. 7-96). M22 compares against it instead.
REPEATABILITY_REPAIRS = {k: v["repeatability"] for k, v in _REPAIR_ENTRIES.items() if "repeatability" in v}
# P6-12: an entry's optional "length" pins the printed LEN cell where the print itself defeats
# pdftotext (v2.6 UAC-1 "705" renders as "7 05"). M25 compares against it instead.
LENGTH_REPAIRS = {k: v["length"] for k, v in _REPAIR_ENTRIES.items() if "length" in v}


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
    "v2.7.1": ["HL7_V271_PDF/PDF/V271_CH*.pdf"],
}

# P10-4a: a version whose CHAPTER_GLOBS entry covers only some chapters while its segment
# schemas are authored in stages, with the task that widens it. Not a deferral (that needs an
# owner decision, see DEFERRED_VERSIONS): every swept chapter gets the full presence check.
# check-audit-schemas.py fails once Version.swift declares a staged version, so the entry
# cannot outlive the rollout.
CHAPTER_GLOBS_STAGED = {}   # P10-4c widened v2.7.1 to every chapter

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
    "v2.7.1": "HL7_V271_PDF/PDF/V271_Appendix_A.pdf",
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
#   bare "..."       an ellipsis row: the list continues or the row means null — never a code;
#                    also its U+2026 form (v2.7.1 Appendix A, and v2.8.2 Chapter 2C 0359 / 0418)
#   a comma           several codes printed in one Value cell (0301 "L,M,N"): as one code the
#                    closed table rejects each of them
SUSPECT_CODE = re.compile(r"[\[\]|(),]|^.{31,}$|[-_:]$|^[A-Z][a-z]{2,}\s\S|^(?!.*\.\.\.)\S+(\s+\S+){2,}$|^(\.\.\.|\u2026)$")

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


def table_open_findings(f):
    """P2-15 per-field openness. `tableOpen` is a boolean, only on a field with a table
    binding, and always carries the cited prose that opens the table; a
    `tableOpenCitation` needs `tableOpen: true`. Returns the finding messages for one field."""
    out = []
    if "tableOpen" not in f and "tableOpenCitation" not in f:
        return out
    flag, cite = f.get("tableOpen"), f.get("tableOpenCitation")
    if "tableOpen" in f and not isinstance(flag, bool):
        out.append(f"tableOpen {flag!r} is not a boolean")
    elif flag and not f.get("tables"):
        out.append("tableOpen on a field with no table binding")
    if flag is True and not (isinstance(cite, str) and cite.strip()):
        out.append("tableOpen without a tableOpenCitation")
    if cite is not None and flag is not True:
        out.append("tableOpenCitation without tableOpen: true")
    return out


def condition_predicate_findings(f):
    """P4-31 (ADR-021). `conditionIsPredicate: true` marks the stored `condition` as the
    spec's complete C predicate (must not be sent when false). It is a boolean `true`, only
    on a field printed C with a non-empty `condition`, and always carries a
    `predicateCitation` of at least 20 characters; a `predicateCitation` needs the marker.
    Returns the finding messages for one field (the `optionalityCitation` pattern, P4-30)."""
    out = []
    if "conditionIsPredicate" not in f and "predicateCitation" not in f:
        return out
    flag, cite = f.get("conditionIsPredicate"), f.get("predicateCitation")
    if "conditionIsPredicate" in f and flag is not True:
        out.append(f"conditionIsPredicate {flag!r} is not true (omit the key instead)")
    if flag is True:
        if not (isinstance(cite, str) and len(cite.strip()) >= 20):
            out.append("conditionIsPredicate without a predicateCitation")
        if f.get("optionality") != "C":
            out.append("conditionIsPredicate on a field not printed C")
        if not (f.get("condition") or "").strip():
            out.append("conditionIsPredicate on a field with no condition")
    if cite is not None and flag is not True:
        out.append("predicateCitation without conditionIsPredicate: true")
    return out


# P6-9: swiftName shape. The longest legitimate name is 66 characters (v2.8.2 OM1-56,
# "Observation/Identifier associated with Producer's Service/Test/Observation ID"); every prose
# bleed the sweep found was 94 or more (v2.8.2 ITM-16), so 70 leaves headroom for a longer
# printed name without admitting a bleed. Bleeds shorter than the bound are caught by the
# foreign-word rule instead (QPD-2 "queryTagUserParametersInSuccessiveFields", 40 characters).
SWIFT_NAME_MAX = 70
SWIFT_NAME_FOREIGN_MAX = 2
SWIFT_IDENTIFIER = re.compile(r"[a-z][A-Za-z0-9]*")


STRANDED_POSSESSIVE_S = re.compile(r"[a-z]S[A-Z]")


def swift_name_findings(f, canonical=None, canonical_name=None, released=frozenset()):
    """P6-9. `swiftName` is a lowerCamelCase identifier of at most SWIFT_NAME_MAX characters,
    rendered from the field's printed element name. The naming convention (AddingASegment.md):
    a non-canonical slot whose element name normalises equal to the canonical v2.5.1 element
    at the same index (`canonical_name`) must carry the canonical swiftName (`canonical`),
    possessive "S" included; any other slot takes `deriveSwiftName` of its printed name.
    A slot whose name IS the canonical one is exempt from the next two rules (non-canonical
    versions inherit it by index even where the element was later renamed). Otherwise its
    first four letters must start some run of
    the element name's words (a truncated head such as "nistrationSubIdCounter" or a
    placeholder "field4" fails), and at most SWIFT_NAME_FOREIGN_MAX of its camel-case words may
    be absent from the element name (prose bleed). `deprecatedSwiftNames`, the released names
    a renamed accessor keeps as deprecated aliases (ADR-014), is a non-empty list of distinct
    identifiers, none equal to `swiftName`; the old names are exempt from the length bound.
    A stranded possessive "S" (`[a-z]S[A-Z]`, as in "personSLocation") is allowed only on a
    name `released` at v3.13.0 or inherited from the canonical slot: `deriveSwiftName` drops
    the lone "s", and the foreign-word rule cannot see it (an "s" is in every element name).
    Returns the finding messages for one field."""
    out = []
    swift, element = f.get("swiftName") or "", f.get("name") or ""
    if not SWIFT_IDENTIFIER.fullmatch(swift):
        out.append(f"swiftName {swift[:60]!r} is not a lowerCamelCase identifier")
    if len(swift) > SWIFT_NAME_MAX:
        out.append(f"swiftName {len(swift)} chars (bound {SWIFT_NAME_MAX}) — prose bleed?")
    if (canonical and canonical_name is not None and swift != canonical
            and normalised_name(element).replace(" ", "") == normalised_name(canonical_name).replace(" ", "")):
        out.append(f"swiftName {swift[:60]!r} differs from the canonical {canonical!r} for the same element"
                   " — dropped words?")
    if swift != canonical and swift not in released and STRANDED_POSSESSIVE_S.search(swift):
        out.append(f"swiftName {swift[:60]!r} has a stranded possessive S; not released at v3.13.0"
                   " nor canonical-inherited, so it takes deriveSwiftName")
    if swift and swift != canonical:
        words = [w for w in re.split(r"[^a-z0-9]+", element.lower()) if w]
        head = swift.lower()
        if re.match(r"f[0-9]", head):
            head = head[1:]   # the extractor prefixes "f" to a name that starts with a digit
        if not any("".join(words[i:]).startswith(head[:4]) for i in range(len(words))):
            out.append(f"swiftName {swift[:60]!r} does not start a word of {element[:60]!r} — truncated?")
        joined = "".join(words)
        foreign = [w for w in re.findall(r"[A-Z]+(?![a-z])|[A-Z]?[a-z]+|[0-9]+", swift)
                   if w.lower() not in joined]
        if len(foreign) > SWIFT_NAME_FOREIGN_MAX:
            out.append(f"swiftName has {len(foreign)} words absent from {element[:60]!r} — prose bleed?")
    if "deprecatedSwiftNames" in f:
        old = f["deprecatedSwiftNames"]
        if not isinstance(old, list) or not old:
            out.append("deprecatedSwiftNames must be a non-empty list")
        else:
            if any(not (isinstance(o, str) and SWIFT_IDENTIFIER.fullmatch(o)) for o in old):
                out.append("deprecatedSwiftNames holds a non-identifier")
            if swift in old:
                out.append("deprecatedSwiftNames repeats the swiftName")
            if len(set(map(str, old))) != len(old):
                out.append("deprecatedSwiftNames has a duplicate")
    return out


def released_swift_names():
    """`SEG` -> the accessor names its typed struct declared at v3.13.0, from the released
    surface snapshot (`SEG|public var name: Type` lines). Released names never change."""
    names = collections.defaultdict(set)
    path = os.path.join(REPO, "Tests/Fixtures/APISurface/segment-structs-v3.13.0.txt")
    for line in open(path):
        m = re.match(r"([A-Z0-9]{3})\|public var ([A-Za-z0-9_]+):", line)
        if m:
            names[m.group(1)].add(m.group(2))
    return names


def canonical_swift_names():
    """`SEG-n` -> (swiftName, element name) for every canonical (v2.5.1) schema field."""
    names = {}
    for path in glob.glob(f"{SCHEMAS}/v2.5.1/*.json"):
        doc = json.load(open(path))
        for f in doc["fields"]:
            names[f"{doc['segmentID']}-{f['index']}"] = (f.get("swiftName"), f.get("name", ""))
    return names


def duplicate_swift_names(fields):
    """P6-9. The accessor names (aliases included) used more than once in one segment, as
    (name, count) pairs. Codegen would emit two properties with the same name."""
    counts = collections.Counter()
    for f in fields:
        counts.update([f.get("swiftName")] + list(f.get("deprecatedSwiftNames") or []))
    return [(name, n) for name, n in counts.items() if n > 1]


# P6-9 fix 1: element-name shape. Over the corrected corpus (11,999 fields) element names run
# to 10 words at most (OM1-21 "Date/Time Stamp for any change in Definition for the
# Observation") and the longest run of consecutive lowercase-led words is 4 (OM1-21 "for any
# change in", v2.3 DB1-7/8 "return to work date", STF-39 "resource type or category"). The
# prose bleeds found were 12 words with a 10-word lowercase run (v2.8.2 RQ1-7 "Substitute
# Allowed e requisition unit of measure that is known to the") and 17 words (v2.8.2 ITM-16).
# The bounds keep one step of headroom over the corpus maximum. Limit: a bleed of at most 11
# words whose lowercase runs stay at 5 or fewer looks like a long element name and passes;
# the M20 depth audit (`--depth`) is the check that compares names with the print.
ELEMENT_NAME_WORDS_MAX = 11
ELEMENT_NAME_LOWER_RUN_MAX = 5


def element_name_findings(name):
    """P6-9 fix 1. An element name is a title, not prose: at most ELEMENT_NAME_WORDS_MAX
    words, and no run of more than ELEMENT_NAME_LOWER_RUN_MAX consecutive lowercase-led words.
    Returns the finding messages for one name."""
    out = []
    words = (name or "").split()
    if len(words) > ELEMENT_NAME_WORDS_MAX:
        out.append(f"element name has {len(words)} words (bound {ELEMENT_NAME_WORDS_MAX}) — prose bleed?")
    run = best = 0
    for w in words:
        run = run + 1 if re.match(r"[a-z]", w) else 0
        best = max(best, run)
    if best > ELEMENT_NAME_LOWER_RUN_MAX:
        out.append(f"element name has a run of {best} lowercase words — prose bleed?")
    return out


PROHIBITION_KEYS = {"when", "severity", "citation", "permitsNull"}


def when_is_well_formed(when):
    """A prohibition `when` is '<referent> <predicate>': plain spaces only (no tab, newline
    or other whitespace), none leading or trailing, and at least two space-separated tokens.
    Same rule as the codegen precondition in `renderAdditionalProhibitions`."""
    return (isinstance(when, str) and not re.search(r"[^\S ]", when)
            and when == when.strip(" ") and len([t for t in when.split(" ") if t]) >= 2)


def additional_prohibition_findings(f):
    """P4-21 extra prohibitions. `additionalProhibitions` is a non-empty list of rules,
    each {when, severity, citation} plus an optional boolean `permitsNull` (P4-26):
    `when` a '<referent> <predicate>' condition, `severity` error/warning/info,
    `citation` the quoted spec text. Mirrors the codegen preconditions so the audit
    reports what codegen would refuse."""
    if "additionalProhibitions" not in f:
        return []
    rules = f["additionalProhibitions"]
    if not isinstance(rules, list) or not rules:
        return ["additionalProhibitions must be a non-empty list"]
    out = []
    for i, rule in enumerate(rules):
        if not isinstance(rule, dict):
            out.append(f"additionalProhibitions[{i}] is not an object")
            continue
        extra = set(rule) - PROHIBITION_KEYS
        if extra:
            out.append(f"additionalProhibitions[{i}] has unknown keys {sorted(extra)}")
        when = rule.get("when")
        if not when_is_well_formed(when):
            out.append(f"additionalProhibitions[{i}] when {when!r} is not '<referent> <predicate>'")
        if rule.get("severity") not in ("error", "warning", "info"):
            out.append(f"additionalProhibitions[{i}] severity {rule.get('severity')!r} is not error/warning/info")
        cite = rule.get("citation")
        if not (isinstance(cite, str) and cite.strip()):
            out.append(f"additionalProhibitions[{i}] has no citation")
        if "permitsNull" in rule and not isinstance(rule["permitsNull"], bool):
            out.append(f"additionalProhibitions[{i}] permitsNull {rule['permitsNull']!r} is not a boolean")
    return out


def integrity():
    """Shape predicates over every committed schema. Returns a list of findings."""
    findings = []
    canonical = canonical_swift_names()
    released = released_swift_names()
    for path in sorted(glob.glob(f"{SCHEMAS}/*/*.json")):
        rel = os.path.relpath(path, REPO)
        doc = json.load(open(path))
        is_canonical = os.path.basename(os.path.dirname(path)) == "v2.5.1"
        seen = collections.Counter()
        for f in doc["fields"]:
            seen[f["index"]] += 1
            name, dt, opt = f.get("name", ""), f.get("dataType", ""), f.get("optionality", "")
            if not name and not dt:
                findings.append((rel, f["index"], "phantom row (no name, no dataType)"))
            elif not dt and opt not in ("W", "X") and not (
                    opt == "" and unreadable_whitelisted(
                        "M19", rel.split(os.sep)[-2], os.path.basename(rel)[:-5].upper(), f["index"], "blank cell")):
                # empty dataType is spec-CORRECT for withdrawn/reserved fields only, and for a
                # reserved row printed entirely blank (v2.5.1 OBX-20..22, a cited blank region)
                findings.append((rel, f["index"], f"empty dataType with optionality {opt!r}"))
            rp = f.get("repeatability", "")
            if not REPEATABILITY_TOKEN.fullmatch(rp):
                findings.append((rel, f["index"], f"repeatability {rp!r} is not 1, *, or a bound of 2 or more"))
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
            findings.extend((rel, f["index"], msg) for msg in table_open_findings(f))
            findings.extend((rel, f["index"], msg) for msg in additional_prohibition_findings(f))
            findings.extend((rel, f["index"], msg) for msg in condition_predicate_findings(f))
            inherited, inherited_name = (None, None) if is_canonical else \
                canonical.get(f"{doc['segmentID']}-{f['index']}", (None, None))
            findings.extend((rel, f["index"], msg) for msg in swift_name_findings(
                f, inherited, inherited_name, released[doc["segmentID"]]))
            findings.extend((rel, f["index"], msg) for msg in element_name_findings(name))
        for idx, n in seen.items():
            if n > 1:
                findings.append((rel, idx, f"duplicate field index ({n}x)"))
        for ident, n in duplicate_swift_names(doc["fields"]):
            findings.append((rel, 0, f"swiftName {str(ident)[:60]!r} used {n}x in the segment"))
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


# P6-12: the printed shapes each audited column may take. A defining-table cell that is not one
# of these is a misread (a neighbouring column bled in, a footnote marker glued on), and must
# never count as a match: the slot is reported as UNREADABLE instead. OPT: v2.6 section 2.5.3.4
# (the extractor reduces "(B) R" and v2.7+ "C(a/b)" to B and C). LEN: a number (v2.6 section
# 2.5.3.2), the "64K" abbreviation used before v2.4, or the v2.7+ range "m..n" and conformance
# length "n=" / "n#" (v2.8.2 sections 2.5.5.1 to 2.5.5.3). Section 2.5.5.0 also allows a list of
# lengths "x,y,z", and "The minimum length is always 1 or more", so a range from 0 is malformed.
OPTIONALITY_TOKEN = re.compile(r"[ROCXBW]")
LENGTH_TOKEN = re.compile(r"[1-9]\d{0,4}|[1-9]\d?[kK]|[1-9]\d*\.\.[1-9]\d*|[1-9]\d*[=#]|[1-9]\d*(?:,[1-9]\d*)+")
AUDIT_TOKENS = {"M19": ("optionality", OPTIONALITY_TOKEN), "M22": ("repeatability", None),
                "M25": ("len", LENGTH_TOKEN)}


def blank_length_is_print(version, row):
    """M25. True where a blank LEN cell in a parsed row is itself the print. v2.7.1 and v2.8.2:
    LEN and C.LEN are printed only "If applicable" (sections 2.5.3.2 and 2.5.3.3; v2.7.1 CH02
    p. 8), and a field without them takes its data type's (2.5.5.4); composite types carry
    none. Every version: a withdrawn field (OPT W, v2.6 section 2.5.3.4) prints no length and
    no data type."""
    return version in ("v2.7.1", "v2.8.2") or (row.get("optionality") or "").strip() == "W"


def read_slot(defining, union, seg, index, audit, version):
    """P6-12. (printed, unreadable): the values a schema attribute is compared against, or the
    reason the slot cannot be compared. Nothing is skipped silently: a slot with no defining
    row, a blank defining cell that is not itself a print, or a print outside the column's
    shape (AUDIT_TOKENS; REPEATABILITY_TOKEN for M22) comes back unreadable."""
    key, token = AUDIT_TOKENS[audit]
    token = token or REPEATABILITY_TOKEN
    printed = printed_for(defining, union, seg, index, key)
    if printed:
        bad = sorted(p for p in printed if not token.fullmatch(p))
        return (set(), f"malformed print {bad}") if bad else (printed, None)
    row = defining.get(seg, {}).get(index)
    if row is None:
        return set(), "no extracted row"
    if audit == "M25" and blank_length_is_print(version, row):
        return {""}, None
    return set(), "blank cell"


def length_to_write(printed):
    """--write-lengths: the value to write for a disagreeing slot, or None to report it. A blank
    read never removes a length (P6-12 fix 1): the disagreement is reported instead."""
    values = sorted((p for p in printed if p), key=lambda x: (len(x), x))
    return values[0] if values else None


def unreadable_whitelisted(audit, version, seg, index, why):
    """True when a cited region covers the slot FOR THIS REASON (see UNREADABLE_WHITELIST)."""
    return any(a == audit and v == version and s == seg and lo <= index <= hi and why.startswith(r)
               for (a, v, s, lo, hi, r) in UNREADABLE_WHITELIST)


def resolve_unreadable(audit, version, seg, index, why, have, unreadable):
    """P6-12. The printed set for an unreadable slot, or None to stop comparing it. A cited
    blank becomes the print {""}; a cited malformed print is exempt; anything else is reported."""
    if not unreadable_whitelisted(audit, version, seg, index, why):
        unreadable.append((audit, version, seg, index, have, why))
        return None
    return {""} if why == "blank cell" else None


def optionality_finding(have, printed):
    """M19. True when the schema's OPT is none of the printed codes. C is compared like every
    other code (X-C10 / V26-C07): a printed C modelled O, or a printed O modelled C, is a
    finding unless OPTIONALITY_WHITELIST names it with a citation."""
    return bool(printed) and have not in printed


def optionality_citation_finding(have, printed, cite, whitelisted):
    """P4-30. A field's `optionalityCitation` is its whitelist entry. Returns None when the
    slot is clean: OPT matches the print, or departs from it with a citation (the field's own
    `optionalityCitation` of at least 20 characters, or an OPTIONALITY_WHITELIST entry).
    Returns "uncited" when OPT departs with neither, and "stale" when a field carries an
    `optionalityCitation` although its OPT matches the extracted print."""
    cited = isinstance(cite, str) and len(cite.strip()) >= 20
    if optionality_finding(have, printed):
        return None if (cited or whitelisted) else "uncited"
    if cite is not None and printed:
        return "stale"
    return None


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
    """Set each listed field's `length` right after its `dataType`, textually; an empty wanted
    value removes it (a blank print, P6-12). Fields not listed keep theirs: the old version
    stripped every `length` in the file first, so a partial sweep dropped the rest. A field's
    span runs from its `"index"` key to the next one, so one-line and multi-line schemas both
    work."""
    text = open(path, encoding="utf-8").read()
    starts = [m for m in re.finditer(r'"index"\s*:\s*(\d+)', text)]
    out, pos = [], 0
    for n, m in enumerate(starts):
        if int(m.group(1)) not in wanted:
            continue
        end = starts[n + 1].start() if n + 1 < len(starts) else len(text)
        span = re.sub(r',\s*"length"\s*:\s*"[^"]*"', "", text[m.start():end])
        value = wanted.pop(int(m.group(1)))
        if value:
            span = re.sub(r'("dataType"\s*:\s*"[^"]*")',
                          lambda d: d.group(1) + f', "length": {json.dumps(value)}', span, count=1)
        out.append(text[pos:m.start()] + span)
        pos = end
    open(path, "w", encoding="utf-8").write("".join(out) + text[pos:])


def datatype_disagrees(version, seg, index, schema_dt, candidates):
    """M6-O5: True when the schema's dataType is a finding against the extracted candidates
    for that slot. A spec `CM` accepts only an enumerated CM_REFINEMENTS name (P5-7)."""
    if not candidates or not schema_dt or schema_dt in candidates:
        return False
    if (version, seg, index) in DATATYPE_WHITELIST:
        return False
    if "CM" in candidates and schema_dt in CM_REFINEMENTS:
        return False  # enumerated refinement of the CM placeholder (identical structure)
    return True


def write_repeatability(path, wanted):
    """Replace each listed field's `repeatability` value in place, textually (see write_tables)."""
    text = open(path, encoding="utf-8").read()
    out, pos, index = [], 0, None
    for m in re.finditer(r'"index"\s*:\s*(\d+)|"repeatability"\s*:\s*"[^"]*"', text):
        if m.group(1):
            index = int(m.group(1))
        elif index in wanted:
            out.append(text[pos:m.start()] + f'"repeatability": {json.dumps(wanted.pop(index))}')
            pos = m.end()
    open(path, "w", encoding="utf-8").write("".join(out) + text[pos:])


def depth(write=False, correct_names=False, record_lengths=False, record_repeatability=False, versions=None):
    if not os.path.exists(EXTRACTOR):
        sys.exit(f"depth pass needs a compiled extractor at {EXTRACTOR}\n"
                 "  xcrun swiftc -O scripts/extract-segment-tables.swift -o /tmp/extractbin")
    if not os.path.isdir(STANDARDS):
        print("docs/standards/ absent — skipping the depth pass (author-local PDFs).")
        return [], [], 0, [], {}, [], [], [], [], [], [], [], []
    gaps, suspects, exact, presence, backlog, deferred = [], [], 0, [], {}, []
    unreadable = []   # P6-12: (audit, version, seg, index, schema value, why) for M19/M22/M25
    datatype_findings, table_findings, optionality_findings, name_findings, rp_findings, len_findings = [], [], [], [], [], []
    authored = {v: {os.path.basename(p)[:-5].upper() for p in glob.glob(f"{SCHEMAS}/{v}/*.json")}
                for v in CHAPTER_GLOBS}
    modelled_anywhere = set().union(*authored.values())
    wanted_names, wanted_lengths, wanted_reps = {}, {}, {}
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
        # V282-C04: a DEPTH_WHITELIST segment's `1-n` row never parses, so it never enters
        # `found` and the loop above cannot see it missing. Check its caption instead. A miss
        # is always a PRESENCE defect (never DEFERRED): these schemas are hand-authored.
        for seg in sorted(whitelisted_ids(version) - authored[version]):
            if caption_present(version, seg):
                presence.append((version, seg, "(caption)"))
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
                if not datatype_disagrees(version, seg, f["index"], schema_dt, candidates):
                    continue
                datatype_findings.append(
                    (version, seg, f["index"], schema_dt, sorted(candidates)))
            # M25: the LEN column, recorded VERBATIM. Up to v2.6 the cell is a maximum length,
            # and v2.6 section 2.5.3.2 states "The length of a field is normative"; from v2.7
            # it prints a normative range ("2..2", "32=" truncation-allowed, "250#"
            # truncation-not-allowed) and a separate conformance length. A schema's `length`
            # must be what the version's DEFINING attribute table prints (V23-C13), not any
            # chapter's variant print.
            for f in schema_fields:
                have = (f.get("length") or "").strip()
                key = f"{version}/{seg}-{f['index']}"
                if key in LENGTH_REPAIRS:
                    printed, why = {LENGTH_REPAIRS[key]}, None
                else:
                    printed, why = read_slot(spec_def, spec_lens, seg, f["index"], "M25", version)
                if why:
                    printed = resolve_unreadable("M25", version, seg, f["index"], why, have, unreadable)
                    if printed is None:
                        continue
                if have in printed or (version, seg, f["index"]) in LENGTH_WHITELIST:
                    continue
                value = length_to_write(printed) if record_lengths else None
                if value is not None:
                    wanted_lengths.setdefault(path, {})[f["index"]] = value
                    continue
                len_findings.append((version, seg, f["index"], have, sorted(printed)))
            # M22: the RP/# column, which drives cardinalityExceeded. The extractor renders a
            # printed Y as "*", a blank as "1", and a printed bound ("Y/3", "3") as the bound
            # itself; the schema carries the same token (P6-4). A slot whose printed token is
            # unambiguous is written by --write-repeatability. Compared against the DEFINING
            # table's cell (as M19/M21 do), not the union of every chapter's print: a
            # constrained copy that misreads a cell no longer hides a bound (P6-4 fix 1).
            for f in schema_fields:
                key = f"{version}/{seg}-{f['index']}"
                have = (f.get("repeatability") or "").strip()
                if key in REPEATABILITY_REPAIRS:
                    printed, why = {REPEATABILITY_REPAIRS[key]}, None
                else:
                    printed, why = read_slot(spec_def, spec_reps, seg, f["index"], "M22", version)
                if why:
                    printed = resolve_unreadable("M22", version, seg, f["index"], why, have, unreadable)
                    if printed is None:
                        continue
                if have in printed or (version, seg, f["index"]) in REPEATABILITY_WHITELIST:
                    continue
                if record_repeatability and len(printed) == 1:
                    wanted_reps.setdefault(path, {})[f["index"]] = next(iter(printed))
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
            # C / non-C disagreement with the print stays a finding until the field's own
            # `optionalityCitation` or an OPTIONALITY_WHITELIST entry cites the spec; a
            # citation on a slot that matches the print is a finding too (P4-30).
            for f in schema_fields:
                have = (f.get("optionality") or "").strip()
                printed, why = read_slot(spec_def, spec_opts, seg, f["index"], "M19", version)
                if why:
                    printed = resolve_unreadable("M19", version, seg, f["index"], why, have, unreadable)
                    if printed is None:
                        continue
                problem = optionality_citation_finding(
                    have, printed, f.get("optionalityCitation"),
                    (version, seg, f["index"]) in OPTIONALITY_WHITELIST)
                if problem is None:
                    continue
                label = have if problem == "uncited" else f"{have} (optionalityCitation on a printed match)"
                optionality_findings.append((version, seg, f["index"], label, sorted(printed)))
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
    for path, wanted in wanted_reps.items():
        write_repeatability(path, dict(wanted))
    if wanted_reps:
        print(f"  repeatability written in {len(wanted_reps)} schemas", file=sys.stderr)
    return gaps, suspects, exact, presence, backlog, deferred, datatype_findings, table_findings, optionality_findings, name_findings, rp_findings, len_findings, unreadable


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


PAGE_REFERENCE = re.compile(r"\d+-\d+$")
MULTIPLE_SPACES = re.compile(r"   +")


def datatype_name_findings(name):
    """P5-9: a datatype `name` is the body heading text, never the table-of-contents entry it
    was extracted alongside (v2.3.1's contents lines carry no dot leaders, so a regression could
    recapture one). Two tells of contents residue: a trailing page reference ("address  2-12")
    and the run of padding spaces before it ("timing quantity      2-52")."""
    out = []
    if PAGE_REFERENCE.search(name or ""):
        out.append(f"name {name!r} ends in what looks like a page reference — contents-line residue?")
    if MULTIPLE_SPACES.search(name or ""):
        out.append(f"name {name!r} has a run of 3+ spaces — contents-line residue?")
    return out


def field_grammar_findings(stem, version, doc):
    """P5 — shape of one field-local composite file, `Resources/datatypes/<version>/fields/<stem>.json`:
    field / version / source match the path, the key is SEG-N, components are contiguous from 1,
    carry no optionality (prose prints none) and a plausible datatype, and every table resolves
    under Resources/tables/<version>."""
    out = []
    if doc.get("field") != stem or doc.get("version") != version[1:] or doc.get("source") != "prose-field":
        out.append("field / version / source do not match the path")
    if not re.fullmatch(r"[A-Z][A-Z0-9]{2}-[1-9]\d*", stem):
        out.append(f"{stem!r} is not SEG-N")
    comps = doc.get("components", [])
    if not comps or [c.get("index") for c in comps] != list(range(1, len(comps) + 1)):
        out.append(f"component indexes are not 1..n: {[c.get('index') for c in comps]}")
    for c in comps:
        where = f"{stem}.{c.get('index')}"
        if c.get("optionality") != "":
            out.append(f"{where}: a prose-derived component cannot carry an optionality")
        if c.get("dataType") and not re.fullmatch(r"[A-Z][A-Z0-9]{1,3}", c["dataType"]):
            out.append(f"{where}: implausible datatype {c['dataType']!r}")
        if not c.get("name") or len(c["name"]) > 70:
            out.append(f"{where}: empty or over-long name — prose bleed?")
        for number in c.get("tables", []):
            if not re.fullmatch(r"\d{4}", number):
                out.append(f"{where}: malformed table number {number!r}")
            elif not os.path.exists(f"{TABLES}/{version}/{number}.json"):
                out.append(f"{where}: table {number} has no file under Resources/tables/{version}")
    return out


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
        findings += [(rel, why) for why in datatype_name_findings(doc.get("name"))]
        comps = doc.get("components", [])
        if [c.get("index") for c in comps] != list(range(1, len(comps) + 1)) or not comps:
            findings.append((rel, f"component indexes are not 1..n: {[c.get('index') for c in comps]}"))
        # M13: v2.3 to v2.4 files are recovered from prose (`"source": "prose"`). Prose gives
        # no optionality, and a heading can print no datatype code (XTN.1), so those two
        # checks apply to the printed component tables only. A trailing component with no
        # datatype would be a note the extractor failed to drop.
        # P5: "prose-line" files come from a printed Components / Format line; every entry is a
        # printed component by construction, and TS prints no datatype code at all.
        prose = doc.get("source") in ("prose", "prose-line")
        if doc.get("source") == "prose" and comps and not comps[-1].get("dataType"):
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
    # P5: field-local composites, Resources/datatypes/v<X>/fields/<SEG>-<N>.json.
    fields_by_version = collections.defaultdict(dict)
    for path in sorted(glob.glob(f"{DATATYPES}/v*/fields/*.json")):
        files += 1
        rel, stem = os.path.relpath(path, REPO), os.path.basename(path)[:-5]
        version = os.path.basename(os.path.dirname(os.path.dirname(path)))
        try:
            doc = json.load(open(path))
        except ValueError as exc:
            findings.append((rel, f"malformed JSON: {exc}"))
            continue
        fields_by_version[version][stem] = doc
        findings += [(rel, why) for why in field_grammar_findings(stem, version, doc)]
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
        # P5: the field-local composites are re-extracted too; the extractor is their only author.
        spec = importlib.util.spec_from_file_location("dfc", os.path.join(REPO, "scripts/extract-field-components.py"))
        dfc = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(dfc)
        for version in sorted(f"v{v}" for v in dtp.SOURCES):
            if not any(glob.glob(os.path.join(STANDARDS, p)) for p in CHAPTER_GLOBS[version]):
                findings.append((f"Resources/datatypes/{version}/fields", "cannot re-extract (missing PDF)"))
                continue
            fresh = {key: dfc.document(t) for key, t in dfc.extract(version[1:])[0].items()}
            committed = fields_by_version.get(version, {})
            for key in sorted(set(fresh) | set(committed)):
                if fresh.get(key) != committed.get(key):
                    findings.append((f"Resources/datatypes/{version}/fields/{key}.json", "DRIFT against a fresh field extraction"))
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
    "v2.7.1": ("HL7_V271_PDF/PDF/V271_CH02A_DataTypes.pdf", r"2\.A"),
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
    # v2.7.1 prints the same two fragments (Chapter 2A 2.A.90.9 and 2.A.90.12, p107) and
    # XTN.3 as R (component table, 2.A.90, p104).
    ("v2.7.1", "XTN", "^^^^^^^^Do not use after 5PM", "XTN.3"),
    ("v2.7.1", "XTN", "^^^^^^^^^^^1-800-Dentist", "XTN.3"),
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
        text = subprocess.run(["pdftotext", "-layout", "-enc", "UTF-8", path, "-"], capture_output=True, text=True, timeout=30).stdout
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
    ap.add_argument("--write-repeatability", action="store_true",
                    help="with --depth: write the printed RP/# token (1, *, or a bound) into the schemas (P6-4)")
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
        gaps, suspects, exact, presence, backlog, deferred, dt_findings, tbl_findings, opt_findings, name_findings, rp_findings, len_findings, unreadable = depth(
            write=args.write_tables, correct_names=args.write_names, record_lengths=args.write_lengths,
            record_repeatability=args.write_repeatability, versions=args.only_version)
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
        print(f"\n== unreadable prints (M19/M22/M25): {len(unreadable)} findings "
              f"({len(UNREADABLE_WHITELIST)} cited regions)")
        for audit_id, v, seg, idx, got, why in unreadable[:cap]:
            print(f"   UNREAD   {audit_id} {v} {seg}-{idx}: schema {got!r}, {why}")
        print(f"\n== length (M25): {len(len_findings)} findings")
        for v, seg, idx, got, want in len_findings[:cap]:
            print(f"   LEN      {v} {seg}-{idx}: schema {got!r}, spec prints {want}")
        if gaps or suspects or presence or dt_findings or tbl_findings or opt_findings or name_findings or rp_findings or len_findings or unreadable:
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
