#!/usr/bin/env python3
"""M18 — extract the complete example MESSAGES the specification prints, for an end-to-end
run through the Swift Validator.

    python3 scripts/extract-example-messages.py /tmp/spec-examples.json
    SPEC_EXAMPLE_MESSAGES=/tmp/spec-examples.json SPEC_EXAMPLE_REPORT=/tmp/report.tsv \\
        DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter SpecExampleMessageTests
    python3 scripts/extract-example-messages.py --triage /tmp/spec-examples.json /tmp/report.tsv
    python3 scripts/extract-example-messages.py --check-registry /tmp/report.tsv

The output is specification text and, like the PDFs, stays OUT of the repository: write it
to a scratch path. A message starts at "MSH|^~\\&" (or at a recognised variant of that
header — see _message_start) and runs while lines are segments; a segment ends at "<cr>", at
the next line led by a real segment ID (P4-29, see messages_from_lines), at a "// comment" or
elision-only line, or where the print's indentation returns to the body text, and may wrap
over several printed lines.

These examples are a TRIAGE source, not a must-pass oracle. Unlike the datatype examples
(audit-schemas.py --examples), the printed messages are informative and frequently wrong in
their own right: truncated with "...", fields shifted by one, required fields missing, and
half of the v2.5.1 examples omit MSH-9.3, which the MSG component table prints as R.
"""
import re, sys, json, glob, subprocess, os, fnmatch

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHAPTERS = {
    "v2.3": "HL7_v23_PDF/CH*.pdf", "v2.3.1": "HL7_v231_PDF/Hl7V231.pdf", "v2.4": "HL7_v24_PDF/CH*.PDF",
    "v2.5.1": "HL7_v251_PDF/V251_CH*.pdf", "v2.6": "HL7_v26_PDF/V26_CH*.pdf",
    "v2.8.2": "HL7_V2.8.2_PDF/PDF/V282_CH*.pdf",
}
FURN = re.compile(r"Health Level Seven|All rights reserved|Final Standard|^\s*Page \d|^\s*Chapter \d+A?:|^\f")
SEG = re.compile(r"^\s*([A-Z][A-Z0-9]{2})\|")
_LITERAL_CR = re.compile(r"<cr>", re.IGNORECASE)
# P4-22 fix round 1 / P4-28 fix rounds 2-3: a numbered section/subsection heading ("4.8
# PHARMACY/TREATMENT ORDERS", "2.11 CHAPTER FORMATS...", "7.4.2 Unsolicited", "4.5.4 TQ1 -
# Timing"), the marker that a segment whose own <cr> the PDF dropped has run off the end of
# its figure and into ordinary prose. Needs heading SHAPE, not just a number followed by any
# capital letter — the original pattern also matched an ordinary wrapped continuation that
# happens to start with a number and a capitalised unit, e.g. "2.5 MG q4h...". Fix round 2's
# "[A-Z]{3,}" (a capitalised WORD of three or more letters) ruled that out, but also missed
# two real heading shapes: sentence case ("Unsolicited", one capital) and a segment ID
# leading the title ("TQ1 - Timing", capital+capital+digit, not three letters).
#
# Two separate patterns, split on how many dots the section number has:
#   - Two or three dots ("7.4.2", "4.5.4") is always a genuine subsection reference in this
#     corpus — no printed dosage or other quantity ever carries two decimal points — so the
#     title word only needs heading SHAPE: a capital letter plus one more letter or digit
#     (covers "Un[solicited]" and "TQ[1]" alike).
#   - Exactly one dot ("4.8", "2.11") is shape-identical to a decimal quantity ("2.5"), so
#     the title word must be a real one: four or more letters/digits after the capital,
#     which every genuine one-dot heading in this corpus clears ("PHARMACY", "CHAPTER") and
#     every printed unit abbreviation ("MG", "ML", "TAB") does not.
_SECTION_HEADING_MULTI_DOT = re.compile(r"^\s*\d+(\.\d+){2,3}\s+[A-Z][A-Za-z0-9]")
_SECTION_HEADING_ONE_DOT = re.compile(r"^\s*\d+\.\d+\s+[A-Z][A-Za-z0-9]{3,}")
# No printed segment in this corpus, even wrapped over several lines, gets within an order
# of magnitude of this; a real missing <cr> that runs a continuation into unrelated prose
# (a swallowed worked example, a swallowed component table) reaches 100K+ characters.
_MAX_SEGMENT_LEN = 3000
# P4-29: the print indents every example message; pdftotext -layout keeps that indentation.
# A genuine wrapped continuation line is never more than this many columns left of its
# segment's first printed line, while the prose after a figure resumes at the body margin, 4
# to 34 columns further left. Measured over the continuation lines only (lines NOT led by a
# segment ID): the furthest-left real continuation is 3 columns left, "0<cr>" in v2.3 CH4,
# and none further left contains a "|". A line led by a segment ID is exempt (fix round 1):
# after a page break the layout can shift by more than this, and four real segments sit
# further left than the segment before them.
_MAX_OUTDENT = 3


def _strip_comment(line):
    """P4-28 fix round 1 (task review): an inline "// comment" annotation ends whatever
    segment content precedes it on the same printed line — both on its own line ("// Other
    parts of message might follow") and trailing real content on the same line
    ("OBR|...|...                       // 1ST child OBR.", v2.3/CH4.pdf's child-OBR worked
    example) — the PDF's own <cr> is missing in both shapes, so without this the comment (and,
    via that same gap, the next segment's content right after it) gets glued on, corrupting
    later field positions. Confirmed as the cause of spurious OBR-8.2/OBR-11 valueNotInTable
    findings (v2.3/CH4.pdf, v2.3/CH7.pdf, v2.3.1/Hl7V231.pdf — now fixed).

    Normalises to an explicit "<cr>" terminator (the same marker a printed one uses) right
    where the comment starts, so the existing <cr>-splitting machinery in _split_literal_cr
    treats it identically to a printed terminator: real content before the comment is kept
    and closed, the comment itself is dropped. A comment with nothing real before it (the
    whole line is the comment) becomes an empty line, the same as a blank line in the print."""
    idx = line.find("//")
    if idx == -1:
        return line
    before = line[:idx].rstrip()
    return before + "<cr>" if before else ""


def _continuation_runs_into_prose(seg, line, outdent=0):
    """P4-22 fix round 1 / P4-28 fix round 2: true when an open, un-terminated segment (the
    PDF dropped its <cr>) has run off the end of its figure into ordinary document text — a
    numbered section heading (heading shape AND no "|" anywhere on the line — segment data
    always has one, prose heading never does), or (heading or not) a segment that has grown
    far past any real printed example's length. ("// comment" annotations are handled
    earlier, by _strip_comment, before a line ever reaches this check.)

    P4-29: also true when the line sits more than _MAX_OUTDENT columns left of the open
    segment's first printed line (`outdent`, in columns) -- the body text resuming after the
    figure. Without a "<cr>" requirement for a segment to end, the last segment of every
    message printed without one would otherwise run on into the explanation that follows it
    ("Note that MSA-1 ...", "Requesting a Chip card", "5.9.2.1.1 Associated dispense ...")."""
    looks_like_heading = (bool(_SECTION_HEADING_MULTI_DOT.match(line))
                          or bool(_SECTION_HEADING_ONE_DOT.match(line))) and "|" not in line
    return looks_like_heading or len(seg) > _MAX_SEGMENT_LEN or outdent > _MAX_OUTDENT


def _split_literal_cr(line):
    """P4-22 rule 1: a literal <CR>/<cr> embedded mid-line is itself a segment separator —
    pdftotext sometimes joins two printed segment lines onto one extracted line. Split on
    every marker (case-insensitive), normalising each terminated fragment's marker to a
    lowercase "<cr>". A run of duplicated markers with nothing new between them (pdftotext
    occasionally doubles the glyph, "<cr><cr>") collapses to one, so it terminates the
    currently-open segment exactly once rather than manufacturing a spurious empty "next
    line" — a bare "<cr>" line (the sole content of the row, the marker for a segment that
    wrapped onto a line of its own) is still its own one-fragment result, unaffected. A
    trailing fragment with no marker after it is kept only when it itself looks like a new
    segment — trailing page marginalia (a footnote, a running header) is dropped instead of
    being treated as the next real line. A trailing fragment that IS a new segment carries
    on open, exactly as an ordinary un-split line would."""
    normalised = _LITERAL_CR.sub("<cr>", line)
    if "<cr>" not in normalised:
        return [normalised]
    normalised = re.sub(r"(?:<cr>\s*){2,}", "<cr>", normalised)
    parts = normalised.split("<cr>")
    out = [p + "<cr>" for p in parts[:-1]]
    trailer = parts[-1].strip()
    if trailer and SEG.match(trailer):
        out.append(trailer)
    return out


# P4-28: standard HL7 encoding characters (component ^, repetition ~, escape \, subcomponent
# &) and the transposed order a number of CH03/CH04/CH04A/CH05 examples across v2.4-v2.8.2
# print instead (component ^, subcomponent &, repetition ~, escape \). Verified directly
# against the PDF text: the body of every affected example consistently uses the characters
# in their STANDARD roles, not the role the printed header's own position would declare —
# e.g. CH04's FT1 composite price "125.43&USD" uses & as a subcomponent separator (amount &
# currency code), and the PID-3 assigning authority "MPI&GenHosp&L" is the same HD
# subcomponent use — so the printed header is a transposition of two characters, not a
# distinct, self-consistent encoding, and is normalised to the standard order for parsing.
# Per-source counts, verified directly against the PDF text: see KNOWN_SWAPPED_HEADER_SOURCES
# below (the authoritative, --check-registry-pinned count — 138 occurrences across nine
# sources; do not restate a total here, it drifts out of sync with the registry).
_STD_ENC = "^~\\&"
_SWAPPED_ENC = "^&~\\"
# P4-28: the whole header — encoding characters and everything after them — replaced with
# the elision marker. A message start under the default encoding characters.
_BARE_MSH_HEADER = re.compile(r"^MSH\|\.\.\.(?:<cr>)?$")
# P4-28: a segment consisting of only its three-character ID and the elision marker, e.g.
# "PID|...". Recognising "MSH|..." as a message start (above) surfaces a common abbreviated-
# example convention this corpus otherwise never exposed: a run of these shown back-to-back
# with no literal "<cr>" between them at all ("MSH|...", "PID|...", "ORC|NW|...<cr>" —
# confirmed directly in the PDF text, e.g. Hl7V231.pdf's "E-mail only version of the order"
# example), which the ordinary wrapped-continuation rule would otherwise glue into one
# unparseable blob. A bare-elided segment is complete by construction — nothing can follow
# "SEG|..." — so it is always its own, immediately self-terminating segment, with or without
# a printed "<cr>".
_BARE_ELIDED_SEGMENT = re.compile(r"^[A-Z][A-Z0-9]{2}\|\.\.\.(?:<cr>)?$")


def _message_start(line):
    """P4-28: recognise every printed form of a message start this corpus uses, normalising
    the text where the printed header and the body disagree, so the rest of the pipeline —
    and the Swift Validator, which reads its own encoding characters from MSH-2 and cannot
    parse a message at all without them — sees a message it can parse correctly.

    Returns (normalised_line, swapped, bare) where swapped is True only for the transposed-
    header case and bare is True only for the fully-elided "MSH|..." case (its encoding
    characters are fabricated as the default "^~\\&" — the brief's "message start with
    default encoding characters" — since the Validator cannot parse ANY field, not just the
    version, without some value there), or None when the line is not a recognised message
    start at all."""
    if line.startswith("MSH|" + _STD_ENC):
        return line, False, False
    if line.startswith("MSH|" + _SWAPPED_ENC):
        return "MSH|" + _STD_ENC + line[len("MSH|" + _SWAPPED_ENC):], True, False
    if _BARE_MSH_HEADER.match(line):
        # The Parser requires MSH-2 to be immediately followed by another field separator
        # (it reads encoding characters as a fixed 4-character window, not a delimited
        # field) — the trailing "|" is required, not merely cosmetic. P4-28 fix round 1
        # (task review): a printed "MSH|...<cr>" terminator must survive the fabrication —
        # dropping it left the fabricated "MSH|^~\&|" looking un-terminated to the state
        # machine below, so a genuine next segment (not itself bare-elided) got glued onto
        # it as more "wrapped continuation" text instead of opening its own segment.
        terminator = "<cr>" if line.endswith("<cr>") else ""
        return "MSH|" + _STD_ENC + "|" + terminator, False, True
    return None


_FUSED_ELISION = re.compile(r"(?:\.{3,}|\u2026)\s*$")


def _drop_elision(seg):
    """P4-22 rules 2 and 3: a field whose whole content is the HL7 elision marker "..."
    means omitted content, not the literal value "...". Truncate the segment there: that
    field and every later field (including a trailing "..." after the last delimiter) are
    treated as not present. Applied uniformly to every segment, this is also what keeps a
    message whose MSH-12 sits past an elided field — MSH-12 comes out absent rather than
    the literal "...", so the Validator falls back to the default grammar instead of a
    version implied by garbage text.

    Returns (possibly-truncated segment, the 1-based HL7 field number the elision started
    at, or None if nothing was elided) — fix round 1 (brief Part 1 rule 3, "mark it") needs
    that field number to record which fields a message's report lines can only be missing
    because of elision, not a genuine finding."""
    fields = seg.split("|")
    for i, f in enumerate(fields):
        # P4-29: "\u2026" is the same marker set as one ellipsis character (v2.5.1 CH05).
        if i > 0 and f.strip() in ("...", "\u2026"):
            kept = fields[:i]
            if len(kept) == 1:
                kept.append("")
            return "|".join(kept), i
    # P4-29 fix round 1: the marker fused onto the LAST printed field with no separator before
    # it ("OBX||ST...", "ORC|RE...", v2.3 CH7 / v2.3.1) elides everything from the next field
    # on; the printed value keeps its own text. A last field of dots only ("....") is
    # whole-field elision. Only the last field: "see notes... continued|X" is content.
    last = len(fields) - 1
    m = _FUSED_ELISION.search(fields[last]) if last > 0 else None
    if m:
        value = fields[last][:m.start()].rstrip()
        if not value:
            kept = fields[:last] + ([""] if last == 1 else [])
            return "|".join(kept), last
        return "|".join(fields[:last] + [value]), last + 1
    return seg, None


# P4-29: every segment ID any supported version defines (the hand-curated schemas under
# Resources/schemas/<version>/<ID>.json), plus the locally defined Z-segments HL7 reserves
# the Z prefix for. Used by the one-segment-per-printed-line rule in messages_from_lines():
# a wrapped continuation line in this corpus can itself begin with three capitals and a
# "|" ("LAB||Everyman", "TAL|...", "SUR|||", "GAS||", "DAC|", "NES|", "AND|@RXD.3"), but
# never with a real segment ID, so the vocabulary is what tells the two apart.
_SEGMENT_IDS = frozenset(
    os.path.splitext(os.path.basename(p))[0]
    for p in glob.glob(os.path.join(REPO, "Resources/schemas/*/*.json"))
    if re.fullmatch(r"[A-Z][A-Z0-9]{2}", os.path.splitext(os.path.basename(p))[0]))


def _is_segment_id(seg_id):
    return seg_id in _SEGMENT_IDS or seg_id.startswith("Z")


def _ends_mid_field(seg):
    """P4-29: true when an open segment's printed line stops visibly inside a field -- on a
    component, repetition, subcomponent or escape character (a composite broken across two
    lines, e.g. CH05's "...^AND|@ORC.1^EQ^RE^" / "AND|@RXD.3...") or on a hyphenated word
    break ("GOOD HEALTH HOSPI-" / "TAL|..."). The next line then continues that field, even
    if it happens to begin with a segment ID.

    Justified only synthetically: in this corpus no line led by a segment ID follows a line
    ending this way (the two examples above are led by non-segment words, which stay
    continuations anyway), so the guard changes no extracted message today. It is kept as
    the brief's "visibly mid-field" exception, pinned by the self-check."""
    return seg.rstrip().endswith(("^", "~", "&", "\\", "-"))


# P4-29: a whole printed line that is only the elision marker ("...", "......") between
# segments stands for omitted segments (v2.3 CH7's "OBX||ST...", "...", "OBX||FT..."). A
# line that merely STARTS with it ("... ^^^^198901130500^<cr>") is real continuation text.
_ELISION_ONLY_LINE = re.compile(r"^(?:\.{3,}|\u2026)(?:<cr>)?$")


def _segment_break(raw, seg=None):
    """P4-29 (P4-28 re-review carry-ins): true for a printed line that is not segment content
    but ends whatever segment is open -- a "// comment" alone on its line (v2.3/v2.3.1 CH4's
    "// 1ST child OBR", printed after an OBR that has no "<cr>") or an elision-only line. The
    message stays open: what follows may be more of it. An elision-only line carrying a
    trailing comment ("...   // Other parts of message might") is an elision-only line.

    `seg` is the open segment, if any. An elision-only line straight after an open segment
    that stops on a field separator is NOT a break: it is that segment's own elided remainder
    (v2.5.1 CH04's "MSH|...||OMS^O05^OMS_O05|" / "...<cr>"), so it stays a wrapped
    continuation and _drop_elision still records the elision (there, MSH-12)."""
    line = raw.strip()
    if line.startswith("//"):
        return True
    if not _ELISION_ONLY_LINE.match(_strip_comment(line)):
        return False
    return not (seg and not seg.endswith("<cr>") and seg.endswith("|"))


def messages(pdf):
    text = subprocess.run(["pdftotext", "-layout", "-enc", "UTF-8", pdf, "-"], capture_output=True, text=True).stdout.split("\n")
    return messages_from_lines(text)


def messages_from_lines(text):
    """Extract the example messages from the printed lines of one source (pdftotext -layout
    output, or synthetic lines in the self-check)."""
    out, out_swapped, out_bare = [], [], []
    cur, seg, cur_swapped, cur_bare = None, None, False, False
    seg_indent = 0      # P4-29: printed indentation of the open segment's first line
    def close():
        nonlocal cur, seg, cur_swapped, cur_bare
        if cur is not None:
            if seg: cur.append(seg)
            if len(cur) >= 2:
                out.append(cur); out_swapped.append(cur_swapped); out_bare.append(cur_bare)
        cur, seg, cur_swapped, cur_bare = None, None, False, False
    for raw in text:
        # P4-29 fix round 1: pdftotext opens each page with a form feed, which FURN treats as
        # furniture -- but four pages (all v2.8.2 CH04) open with a printed segment.
        if raw.startswith("\f") and SEG.match(raw[1:]):
            raw = raw[1:]
        if FURN.search(raw): continue
        if _segment_break(raw, seg):
            if cur is not None and seg:
                cur.append(seg); seg = None
            continue
        indent = len(raw) - len(raw.lstrip())
        for line in _split_literal_cr(_strip_comment(raw.strip())):
            start = _message_start(line)
            if start is not None:
                close(); cur, seg, cur_swapped, cur_bare = [], start[0], start[1], start[2]
                seg_indent = indent; continue
            if cur is None: continue
            if not line:
                if seg and seg.endswith("<cr>"): cur.append(seg); seg = None
                continue
            m = SEG.match(line)
            if seg is None:
                # P4-28 fix round 1 (task review): a bare-elided line is self-terminating in
                # every state, including here — nothing can follow "SEG|...", so it goes
                # straight to `cur` rather than being opened as `seg` and left waiting for a
                # terminator it will never carry.
                if m and _BARE_ELIDED_SEGMENT.match(line):
                    cur.append(line)
                elif m:
                    seg, seg_indent = line, indent
                else:
                    close()
            elif seg.endswith("<cr>"):
                cur.append(seg)
                if m and _BARE_ELIDED_SEGMENT.match(line):
                    cur.append(line); seg = None
                elif m:
                    seg, seg_indent = line, indent
                else:
                    seg = None; close()
            elif _continuation_runs_into_prose(
                    seg, line, 0 if (m and _is_segment_id(m.group(1))) else seg_indent - indent):
                # (P4-29 fix round 1: a line led by a real segment ID is never treated as
                # outdented prose -- page breaks shift the layout, and the guard dropped four
                # real segments: v2.5.1 CH05 QBP^Z75 QPD, v2.4 CH08 MFK MFA, v2.4 CH05 RXD,
                # v2.8.2 CH04 RTB RDT.)
                # P4-22 fix round 1: the PDF dropped this segment's own <cr>, so the
                # "wrapped continuation" branch below would otherwise keep absorbing raw
                # lines past the end of the figure — into a section heading, or (if a
                # heading never arrives, e.g. a table of component rows) indefinitely.
                # Close what has genuinely accumulated rather than let it run on; the
                # triggering line itself (heading or otherwise) is not segment content and
                # is dropped, same as page furniture.
                cur.append(seg); seg = None
            elif m and _BARE_ELIDED_SEGMENT.match(line):
                # P4-28: the open segment lacks its own "<cr>" in the print, but this line is
                # a complete, self-terminating bare-elided segment on its own — see
                # _BARE_ELIDED_SEGMENT — so it closes the open one and is immediately closed
                # itself, rather than being glued on as more "wrapped continuation" text.
                cur.append(seg); cur.append(line); seg = None
            elif m and _is_segment_id(m.group(1)) and not _ends_mid_field(seg):
                # P4-29: one segment per printed line with no "<cr>" at all (the QBP/RSP
                # query family and others): a line led by a real segment ID starts a new
                # segment unless the open one stops visibly mid-field (_ends_mid_field).
                cur.append(seg); seg, seg_indent = line, indent
            else:
                seg += line          # a wrapped continuation of the open segment
    close()
    clean = []
    for msg, swapped, bare in zip(out, out_swapped, out_bare):
        segs = [re.sub(r"\s*<cr>\s*$", "", s) for s in msg]
        dropped = [_drop_elision(s) for s in segs]
        cleaned = [d[0] for d in dropped]
        if all(SEG.match(s) for s in cleaned):
            meta = _elision_metadata(cleaned, dropped)
            meta["swappedHeader"] = swapped
            if bare:
                # P4-28: the fabricated default encoding characters leave no "..." for
                # _drop_elision to see, so _elision_metadata never sets this on its own —
                # but the whole header beyond those four characters is unknown, same as the
                # elided-MSH-12 case P4-22 already falls back to the default grammar for.
                # Likewise record it as a truncated segment from field 3 on (field 1 is the
                # separator, field 2 the fabricated encoding characters — both "present"),
                # the same convention _elision_metadata uses, so the report's existing ELIDED
                # tagging (SpecExampleMessageTests.isElisionOnly) recognises every MSH field
                # this fabricates a value for as elision, not a genuine finding.
                meta["mshVersionElided"] = True
                meta["truncatedSegments"].insert(0, {"segment": "MSH", "repetition": 1, "fromField": 3})
            clean.append(meta)
    return clean


def _elision_metadata(cleaned_segs, dropped):
    """P4-22 fix round 1 (brief Part 1 rule 3, "mark it"): the per-message record the spec-
    example report needs to tell "this field is missing because the PDF elided it" apart
    from a genuine finding — a list of {segment, repetition, fromField} for every segment
    elision actually truncated (repetition is the 1-based count of that segment ID seen so
    far, matching how the Validator numbers repeated segments), and whether the truncation
    reached MSH-12 (repetition 1's own "fromField" <= 12), the signal that this message is
    evaluated under the default grammar rather than a version the example printed."""
    truncated, msh_version_elided = [], False
    counts = {}
    for i, (seg, (_, split_index)) in enumerate(zip(cleaned_segs, dropped)):
        seg_id = seg[:3]
        counts[seg_id] = counts.get(seg_id, 0) + 1
        if split_index is not None:
            # MSH-1 is the field separator character itself, not a split element, so split
            # index k is MSH-(k+1) there; every other segment's split index k IS field k.
            from_field = split_index + 1 if i == 0 else split_index
            truncated.append({"segment": seg_id, "repetition": counts[seg_id], "fromField": from_field})
            if i == 0 and from_field <= 12:
                msh_version_elided = True
    return {"segments": cleaned_segs, "truncatedSegments": truncated, "mshVersionElided": msh_version_elided}


# P4-22 — registered exceptions for the message-level sweep: genuine HL7 spec-example
# errors, not extraction artefacts. Each entry is keyed by (source_glob, index, code,
# location_pattern) — a fnmatch glob against "source", "all" or an exact example index, the
# exact SpecExampleMessageTests issue code, and a regex against the location column (e.g.
# "AIL[1]-6") — with the exact "count" of SPECEX lines that key must match, and a one-line
# "reason" the EXAMPLE is at fault, not the rule. `check_registry()` below verifies every
# count against a real report, via `--check-registry <report.tsv>` (P4-28: that same flag
# also verifies KNOWN_SWAPPED_HEADER_SOURCES, a separate per-source registry checked directly
# against the PDF text rather than a report row — see check_swapped_header_counts) — that
# needs the author-local PDFs to regenerate a report, so (like `audit-schemas.py --examples`)
# it cannot run in CI and is interactive-only; CI instead runs only the synthetic-fixture
# version of the same check, `check_registry_matches_a_synthetic_report` in
# check-extract-example-messages.py (no PDFs needed). Same discipline as audit-schemas.py's
# EXPECTED_EXAMPLE_REJECTIONS (M17, "registered exceptions"), adapted for this sweep (a
# triage source per the module docstring, so nothing here gates `swift test` itself) and
# deliberately NOT wired into EXPECTED_EXAMPLE_REJECTIONS, which keys a different check
# (`audit-schemas.py --examples`, the datatype-chapter composite walk) on a different tuple
# shape entirely.
_AI_START_OFFSET_REASON = (
    "v2.5.1 CH10 sec 10.6.4.4: \"To specify that there is no difference between the "
    "appointment's start date/time and the resource's start date/time either replicate "
    "the appointment's start date/time into this field, or specify an offset of zero.\" "
    "Every printed example leaves both start and offset empty, satisfying neither option "
    "(verified P4-17).")
_AI_SHIFT_REASON = (
    "Every printed example except the v2.5.1+ SRM AIP omits the empty Segment Action Code "
    "slot (field 2), so every field the example does carry after it lands one position "
    "early (verified P4-12/P4-17).")
_AI4_REASON = (
    "Same field-2 omission as the shift above, not a separately blank AIL-3/AIP-3: with "
    "field 2 never printed, the resource identifier the example does carry (AIL-3/AIP-3's "
    "intended value) reads one position early, and there is nothing left to fill the "
    "resulting last position — AIL-4/AIP-4 (Location/Resource Type) — so it reports "
    "missing. Corrected in fix round 1 (originally miswritten as \"AIL-3/AIP-3 left "
    "blank\", a different and wrong cause).")
_RXO_FREE_TEXT_REASON = (
    "v2.5.1 CH04 sec 4.14.1.1/.2/.4 (identical wording all six): \"RXO-1, RXO-2 and RXO-4 "
    "are mandatory unless the prescription/treatment is transmitted as free text using "
    "RXO-6, then RXO-1, RXO-2 and RXO-4 may be blank and the first subcomponent of RXO-6 "
    "must be blank.\" This example carries plain free text in RXO-6 with no leading \"^\", "
    "so RXO-6.1 is non-empty and the carve-out does not apply, even though Chapter 4 "
    "elsewhere states the convention is \"place a null in the first component and the text "
    "in the second\" (verified P4-17).")
# P4-28: formerly _RXO_INVISIBLE_REASON, documenting why the v2.3.1 index 36 / v2.3 CH4
# index 1 "500 mg Polycillin" example and the v2.4+ CH04/CH04A swapped-header examples were
# invisible to this sweep. This task fixes BOTH causes it named (Part 1(b) bare "MSH|..."
# recognition, Part 1(a) swapped-header recognition), so every example it described as
# invisible is now visible — see the active entries below, which replace the two
# count-0 regression guards that used to stand in for them.
_AI_SOURCES = ["v2.3/CH10.pdf", "v2.3.1/Hl7V231.pdf", "v2.4/CH10.PDF",
               "v2.5.1/V251_CH10.pdf", "v2.6/V26_CH10_Scheduling.pdf", "v2.8.2/V282_CH10_Scheduling.pdf"]
_AI_SHIFT_COUNTS = {"v2.3/CH10.pdf": 10, "v2.3.1/Hl7V231.pdf": 10, "v2.4/CH10.PDF": 10,
                    "v2.5.1/V251_CH10.pdf": 9, "v2.6/V26_CH10_Scheduling.pdf": 9,
                    "v2.8.2/V282_CH10_Scheduling.pdf": 9}
_AI4_SOURCES = ["v2.3/CH10.pdf", "v2.3.1/Hl7V231.pdf", "v2.4/CH10.PDF"]
_RXO_CH12_SOURCES = ["v2.4/CH12.PDF", "v2.5.1/V251_CH12.pdf", "v2.6/V26_CH12_PatientCare.pdf",
                     "v2.8.2/V282_CH12_PatientCare.pdf"]
# P4-29: the classes of genuine example defect the segment-ID rule newly exposes (examples
# printed one segment per line with no "<cr>", which used to be dropped), plus the RXA/RXG
# dose-series cluster P4-28 deferred. Each was read against the print (the omission is in the
# PDF text, not an extraction artefact) and against the field definition (no condition or
# "if null" wording that would make the shipped rule a misfire). The RXA-4 lines in the same
# messages were left for P4-30, which ruled that the definition's "If null" is the HL7 null
# `""`, so R stands and they are registered below (_RXA4_EMPTY_REASON).
_RXA_SERIES_CODE_REASON = (
    "v2.3 CH4 / v2.3.1 chapter 4 RAS query-response worked example prints every dose of the "
    "repeat-administration series as \"RXA|1|1|199208120800|||250<cr>\": RXA-5 "
    "(Administered Code) is blank on every RXA, the code appearing only on the RXE. RXA-5 is "
    "R in the segment table and its definition (v2.5.1 sec 4.14.7.5) carries no condition.")
_RXG_SERIES_REASON = (
    "v2.3 CH4 / v2.3.1 chapter 4 RGR give-series worked example prints \"RXG|1||199208120701||"
    "250<cr>\": RXG-4 (Give Code) and RXG-7 (Give Units) are blank on every RXG. Both are R "
    "and their definitions (v2.5.1 sec 4.14.6.4/.7) carry no condition.")
_RXA_FOR_RXG_REASON = (
    "The fourth line of the same RGR give series is printed as an RXA, not an RXG "
    "(\"RXA|4||199208131912||250\" in v2.3/v2.3.1; \"RXA|4||^^^199208131912|10986^AMPICILLIN|"
    "250\" in v2.4-v2.6), so RXG-shaped content sits in RXA positions: RXA-2 blank and RXA-6 "
    "blank (v2.3/v2.3.1); RXA-2 blank, the TQ-shaped give time in RXA-3 (RXA-3.1 empty) and "
    "the give code in RXA-4 (RXA-4.2 \"AMPICILLIN\" against Table 0529) in v2.4-v2.6.")
_RXA_CH12_SHIFT_REASON = (
    "CH12 PPP^PCB pathway example prints \"RXA|1|199505011200|||0047-0402-30^Ampicillin...\": "
    "RXA-2 (Administration Sub-ID Counter) is omitted, so the start time lands in RXA-2 and "
    "RXA-3 (Date/Time Start of Administration, R, no condition) reads blank. (The RXA-4 line "
    "of the same message is registered under _RXA4_EMPTY_REASON.)")
_RXA4_EMPTY_REASON = (
    "P4-30: the CH4/CH04/CH04A pharmacy and immunisation examples and the CH12 pathway example "
    "leave RXA-4 (Date/Time End of Administration) empty, RXA-3 valued. RXA-4 is R in every "
    "version's attribute table; its definition, \"If null, the date/time of RXA-3 ... is "
    "assumed\" (v2.3 sec 4.8.14.4, v2.5.1 sec 4.14.7.4, v2.8.2 sec 4A.4.7.4), names the HL7 "
    "null, which Chapter 2 defines as the two double quotes \"\" and distinguishes from an "
    "omitted field (v2.3 sec 2.6; v2.6/v2.8.2 \"Null\" against \"Not populated\"; v2.8.2 "
    "Chapter 2B: \"A required element can have a null value\"). A conformant print sends "
    "RXA-4 as \"\" or repeats RXA-3.")
_CSR_SHIFT_REASON = (
    "v2.3 CH7 / v2.3.1 chapter 7 CRM^C01 example prints \"CSR|1|DM94-004^MDACC||MDACC|3||"
    "19941013||342^^^^^^^PDMS|\": a leading \"1\" (CSR has no Set ID) shifts every field one "
    "place right, so the registration date lands in CSR-7 and the authorising provider in "
    "CSR-9, leaving CSR-6 (R) and CSR-8 (required on C01, P4-30) blank.")
_MF_KEY_TYPE_REASON = (
    "The CH2/CH02, CH8/CH08 and CH17 MFN/MFK master-file examples end MFE after MFE-4 and MFA "
    "after MFA-5: MFE-5 / MFA-6 (Primary Key Value Type) are never printed, though R in every "
    "version that defines them (v2.3.1 onwards). Registered only on messages whose declared "
    "MSH-12 is such a version.")
_MFI_SHIFT_REASON = (
    "The same master-file examples omit or misplace MFI fields: \"MFI|LABxxx^Lab Test "
    "Dictionary^L|UPD|||AL\" drops MFI-2, so the File-Level Event Code lands in MFI-2 and the "
    "Response Level Code in MFI-5; \"MFI|0006^RELIGION^HL7||UPD||AL\" and \"MFI|INV|MATERIALSYS|"
    "UPD|200408121100|SU|\" print the Response Level Code one field early. MFI-3 is R in every "
    "version; MFI-6 is registered only on MFN messages, for which its definition requires it.")
_DSP_SHIFT_REASON = (
    "v2.4/v2.5.1 CH05 display-response examples print the display text one field early, "
    "\"DSP||555444222111 Everyman,Adam ...\" (DSP-2 Display Level holds the line, DSP-3 Data "
    "Line, R, is blank). v2.6 and v2.8.2 correct the same examples to \"DSP|||...\".")
_RDF_REASON = (
    "CH05 tabular-response examples print \"RDF|PatientList^CX^20~PatientName^XPN^48~...\": "
    "RDF-1 (Number of Columns per Row, NM, single) is omitted, so the repeating column "
    "descriptions land in RDF-1 (cardinality exceeded) and RDF-2 (Column Description, R) "
    "reads blank.")
_PRA12_REASON = (
    "CH15 PMU^B01 example prints PRA without PRA-12. v2.4 sec 15.4.5.12: \"For all messages "
    "except the Staff/Practitioner Master File Notification, this field is required\"; this "
    "is a PMU, not an MFN.")
_TXA7_REASON = (
    "v2.8.2 CH09 MDM^T01 example leaves TXA-7 (Transcription Date/Time) blank with TXA-17 "
    "\"DO\". v2.8.2 sec 9.7.3.7: \"conditional based upon the presence of a value in "
    "TXA-17-Document Completion Status of anything except 'dictated'\".")
_HD_PAIR_REASON = (
    "CH05 subscription examples carry \"PS^LAB\" in MSH-3/MSH-5: HD-2 valued without HD-3. "
    "HD (every version from v2.3): \"The second and third components must either both be "
    "valued (both non-null), or both be not valued (both null).\"")
_P4_29_ENTRIES = [
    *[{"source_glob": src, "index": idx, "code": "requiredFieldMissing",
       "location_pattern": r"^RXA\[\d+\]-5$", "count": 10, "reason": _RXA_SERIES_CODE_REASON}
      for src, idx in {"v2.3/CH4.pdf": 29, "v2.3.1/Hl7V231.pdf": 76}.items()],
    *[{"source_glob": src, "index": idx, "code": "requiredFieldMissing",
       "location_pattern": r"^RXG\[\d+\]-[47]$", "count": 18, "reason": _RXG_SERIES_REASON}
      for src, idx in {"v2.3/CH4.pdf": 31, "v2.3.1/Hl7V231.pdf": 78}.items()],
    *[{"source_glob": src, "index": idx, "code": "requiredFieldMissing",
       "location_pattern": r"^RXA\[\d+\]-[26]$", "count": 2, "reason": _RXA_FOR_RXG_REASON}
      for src, idx in {"v2.3/CH4.pdf": 31, "v2.3.1/Hl7V231.pdf": 78}.items()],
    *[{"source_glob": src, "index": idx, "code": "*",
       "location_pattern": r"^RXA\[\d+\]-(2|3\.1|4\.2)$", "count": 3, "reason": _RXA_FOR_RXG_REASON}
      for src, idx in {"v2.4/CH04.PDF": 37, "v2.5.1/V251_CH04.pdf": 40,
                        "v2.6/V26_CH04_Orders.pdf": 39}.items()],
    *[{"source_glob": src, "index": idx, "code": "requiredFieldMissing",
       "location_pattern": r"^RXA\[\d+\]-3$", "count": 1, "reason": _RXA_CH12_SHIFT_REASON}
      for src, idx in {"v2.3.1/Hl7V231.pdf": 146, "v2.4/CH12.PDF": 2, "v2.5.1/V251_CH12.pdf": 2,
                        "v2.6/V26_CH12_PatientCare.pdf": 2,
                        "v2.8.2/V282_CH12_PatientCare.pdf": 2}.items()],
    # Fix round 1 (I-2): only messages whose declared MSH-12 defines MFE-5/MFA-6 (v2.3.1
    # onwards). The 71 lines on "2.2"-declared copies of the same examples are validated
    # under the default v2.5.1 grammar and stay in that already-accepted class, unregistered.
    *[{"source_glob": src, "index": idx, "code": "requiredFieldMissing",
       "location_pattern": r"^(MFE\[\d+\]-5|MFA\[\d+\]-6)$", "count": n, "reason": _MF_KEY_TYPE_REASON}
      for src, by_index in {
          "v2.3.1/Hl7V231.pdf": {112: 2, 114: 2, 116: 1, 117: 1, 118: 1},
          "v2.4/CH08.PDF": {6: 2, 8: 2, 10: 1, 11: 1, 12: 1, 21: 3},
          "v2.5.1/V251_CH02.pdf": {3: 2, 4: 2},
          "v2.5.1/V251_CH08.pdf": {8: 1, 9: 1, 10: 1, 11: 2, 12: 2, 13: 2, 15: 2, 17: 2, 19: 3},
          "v2.6/V26_CH02_Control.pdf": {0: 1, 1: 1, 8: 2, 9: 2},
          "v2.6/V26_CH08_MasterFiles.pdf": {12: 2, 15: 2},
          "v2.6/V26_CH17_MatMngmt.pdf": {0: 1},
          "v2.8.2/V282_CH02_Control.pdf": {8: 2, 9: 2, 10: 2, 12: 2},
          "v2.8.2/V282_CH17_MaterialsMngmt.pdf": {0: 1},
      }.items() for idx, n in by_index.items()],
    *[{"source_glob": src, "index": "all", "code": "requiredFieldMissing",
       "location_pattern": r"^MFI\[\d+\]-3$", "count": n, "reason": _MFI_SHIFT_REASON}
      for src, n in {"v2.3/CH2.pdf": 6, "v2.3/CH8.pdf": 9, "v2.3.1/Hl7V231.pdf": 6,
                     "v2.4/CH02.PDF": 6, "v2.4/CH08.PDF": 6, "v2.5.1/V251_CH02.pdf": 4,
                     "v2.5.1/V251_CH08.pdf": 6, "v2.6/V26_CH02_Control.pdf": 4,
                     "v2.8.2/V282_CH02_Control.pdf": 2}.items()],
    # Fix round 1 (C-1): MFI-6 is registered on MFN messages only. Its definition reads
    # "Required for MFN-Master File Notification message" (v2.3 CH8, v2.4 CH08, v2.5.1 CH08,
    # v2.8.2 CH08), against an unconditional R in the segment table. P4-30 models MFI-6 as C
    # with `messageCode = MFN`: the 27 lines on MFK/MFD messages are gone, and these MFN lines
    # now read conditionalFieldMissing.
    *[{"source_glob": src, "index": idx, "code": "conditionalFieldMissing",
       "location_pattern": r"^MFI\[\d+\]-6$", "count": 1, "reason": _MFI_SHIFT_REASON}
      for src, indices in {
          "v2.3.1/Hl7V231.pdf": [7, 9, 13],
          "v2.3/CH2.pdf": [7, 9, 13],
          "v2.3/CH8.pdf": [0, 2, 6, 10, 11, 12],
          "v2.4/CH02.PDF": [3, 5, 9],
          "v2.4/CH08.PDF": [13, 15, 19],
          "v2.5.1/V251_CH02.pdf": [3, 5],
          "v2.5.1/V251_CH08.pdf": [11, 13, 17],
          "v2.6/V26_CH02_Control.pdf": [8, 10],
          "v2.6/V26_CH17_MatMngmt.pdf": [0],
          "v2.8.2/V282_CH02_Control.pdf": [8],
          "v2.8.2/V282_CH17_MaterialsMngmt.pdf": [0],
      }.items() for idx in indices],
    *[{"source_glob": src, "index": "all", "code": "requiredFieldMissing",
       "location_pattern": r"^DSP\[\d+\]-3$", "count": 29, "reason": _DSP_SHIFT_REASON}
      for src in ["v2.4/CH05.PDF", "v2.5.1/V251_CH05.pdf"]],
    *[{"source_glob": src, "index": "all", "code": "*",
       "location_pattern": r"^RDF\[\d+\]-[12]$", "count": n, "reason": _RDF_REASON}
      for src, n in {"v2.4/CH05.PDF": 16, "v2.5.1/V251_CH05.pdf": 16,
                     "v2.6/V26_CH05_Queries.pdf": 16, "v2.8.2/V282_CH05_Queries.pdf": 12}.items()],
    *[{"source_glob": src, "index": "all", "code": "conditionalFieldMissing",
       "location_pattern": r"^PRA\[\d+\]-12$", "count": 1, "reason": _PRA12_REASON}
      for src in ["v2.4/CH15.PDF", "v2.5.1/V251_CH15.pdf", "v2.6/V26_CH15_PersMngmt.pdf",
                  "v2.8.2/V282_CH15_PersMngmt.pdf"]],
    {"source_glob": "v2.8.2/V282_CH09_MedRecords.pdf", "index": "all", "code": "conditionalFieldMissing",
     "location_pattern": r"^TXA\[\d+\]-7$", "count": 1, "reason": _TXA7_REASON},
    *[{"source_glob": src, "index": "all", "code": "requiredComponentMissing",
       "location_pattern": r"^MSH\[\d+\]-[35]$", "count": 3, "reason": _HD_PAIR_REASON}
      for src in ["v2.5.1/V251_CH05.pdf", "v2.6/V26_CH05_Queries.pdf", "v2.8.2/V282_CH05_Queries.pdf"]],
]
# P4-30: per-source totals over every message ("all"), so later renumbering cannot strand them.
# v2.3 CH4 16 = 1 (RAS) + 10 (RAS query-response series) + 1 (RGR give series) + 4 (VXU);
# v2.3.1 17 = the same 16 plus the CH12 pathway example.
_P4_30_ENTRIES = [
    *[{"source_glob": src, "index": "all", "code": "requiredFieldMissing",
       "location_pattern": r"^RXA\[\d+\]-4$", "count": n, "reason": _RXA4_EMPTY_REASON}
      for src, n in {"v2.3/CH4.pdf": 16, "v2.3.1/Hl7V231.pdf": 17,
                     "v2.4/CH04.PDF": 1, "v2.4/CH12.PDF": 1,
                     "v2.5.1/V251_CH04.pdf": 1, "v2.5.1/V251_CH12.pdf": 1,
                     "v2.6/V26_CH04_Orders.pdf": 1, "v2.6/V26_CH12_PatientCare.pdf": 1,
                     "v2.8.2/V282_CH04A_Orders.pdf": 1, "v2.8.2/V282_CH12_PatientCare.pdf": 1}.items()],
    *[{"source_glob": src, "index": idx, "code": "*",
       "location_pattern": r"^CSR\[\d+\]-[68]$", "count": 2, "reason": _CSR_SHIFT_REASON}
      for src, idx in {"v2.3/CH7.pdf": 11, "v2.3.1/Hl7V231.pdf": 99}.items()],
]
KNOWN_SPEC_EXAMPLE_ERRORS = [
    *[{"source_glob": src, "index": "all", "code": "conditionalFieldMissing",
       "location_pattern": r"^AI[LP]\[\d+\]-[67]$", "count": 20, "reason": _AI_START_OFFSET_REASON}
      for src in _AI_SOURCES],
    *[{"source_glob": src, "index": "all", "code": "conditionalFieldMissing",
       "location_pattern": r"^AI[LP]\[\d+\]-(11|12)$", "count": _AI_SHIFT_COUNTS[src], "reason": _AI_SHIFT_REASON}
      for src in _AI_SOURCES],
    *[{"source_glob": src, "index": "all", "code": "requiredFieldMissing",
       "location_pattern": r"^AI[LP]\[\d+\]-4$", "count": 10, "reason": _AI4_REASON}
      for src in _AI4_SOURCES],
    # P4-28: bringing bare-elided "MSH|..." headers into the sweep (Part 1(b)) makes three
    # previously-invisible v2.3.1 messages visible (P4-22's "index 36" is one of these — the
    # sequential index shifts every time an earlier message is added, so it is no longer
    # literally 36 or even one single index; "all" aggregates all three), each the same
    # "free text in RXO-6, no leading caret" defect: index 54 ("500 mg Polycillin...", RXO-1,
    # 2 AND 4 blank), index 62 and 128 (a custom IV order, "D5W WITH 1/2 NS...", RXO-4
    # populated with the unit "L" so only RXO-1/2 are blank). Confirmed directly in the
    # extracted text. (P4-29: now indices 61, 69 and 146, renumbered by the messages it
    # recovers; "all" is unaffected.)
    {"source_glob": "v2.3.1/Hl7V231.pdf", "index": "all", "code": "conditionalFieldMissing",
     "location_pattern": r"^RXO\[\d+\]-[12]$", "count": 6, "reason": _RXO_FREE_TEXT_REASON},
    {"source_glob": "v2.3.1/Hl7V231.pdf", "index": "all", "code": "conditionalFieldMissing",
     "location_pattern": r"^RXO\[\d+\]-4$", "count": 1, "reason": _RXO_FREE_TEXT_REASON},
    # Same defect, same bare-"MSH|..." fix, in the standalone v2.3 CH4 PDF (index 16 is "500
    # mg Polycillin...", RXO-1/2/4 blank; index 24 is the "D5W..." custom IV, RXO-1/2 only).
    {"source_glob": "v2.3/CH4.pdf", "index": "all", "code": "conditionalFieldMissing",
     "location_pattern": r"^RXO\[\d+\]-[12]$", "count": 4, "reason": _RXO_FREE_TEXT_REASON},
    {"source_glob": "v2.3/CH4.pdf", "index": "all", "code": "conditionalFieldMissing",
     "location_pattern": r"^RXO\[\d+\]-4$", "count": 1, "reason": _RXO_FREE_TEXT_REASON},
    *[{"source_glob": src, "index": 2, "code": "conditionalFieldMissing",
       "location_pattern": r"^RXO\[\d+\]-[12]$", "count": 2, "reason": _RXO_FREE_TEXT_REASON}
      for src in _RXO_CH12_SOURCES],
    # P4-28: the same "500 mg Polycillin" worked example also appears directly in the CH04/
    # CH04A chapters themselves (not just the CH12 copy above) in every version whose swapped
    # header Part 1(a) now recognises — confirmed index 19 (v2.4, v2.6), 20 (v2.5.1) and 2
    # (v2.8.2 CH04A); P4-29 renumbered them to 23 (v2.4), 26 (v2.5.1), 25 (v2.6) and 4 (v2.8.2
    # CH04A), the earlier query examples it recovers coming first (same three lines each). v2.8.2 CH04 (not CH04A) is NOT among these: all four of its swapped
    # headers belong to the "Query the accumulated list..." QBP/RTB family, which prints no
    # RXO at all.
    *[{"source_glob": src, "index": idx, "code": "conditionalFieldMissing",
       "location_pattern": r"^RXO\[\d+\]-[124]$", "count": 3, "reason": _RXO_FREE_TEXT_REASON}
      for src, idx in {"v2.4/CH04.PDF": 23, "v2.5.1/V251_CH04.pdf": 26,
                        "v2.6/V26_CH04_Orders.pdf": 25, "v2.8.2/V282_CH04A_Orders.pdf": 4}.items()],
    *_P4_29_ENTRIES,
    *_P4_30_ENTRIES,
]

# P4-28: the swapped header itself, per source, counted directly in the PDF text (the exact
# transposed four-character substring, not a downstream Validator finding — see _SWAPPED_ENC
# above for the transposition and the PDF-text evidence it rests on). This is deliberately
# NOT folded into KNOWN_SPEC_EXAMPLE_ERRORS / check_registry: that machinery matches SPECEX
# report rows (Validator findings on a successfully-extracted, segment-split message), so
# it would not notice a header that never formed a message at all. Counting occurrences
# directly, independent of the extractor, is what "verified" means here and is checked on
# every --check-registry run. (P4-28 found 80 of the 138 in example families printed one
# segment per line with no "<cr>" -- the "Query the accumulated list..." QBP^Z73/RTB^Z74
# family and several CH03/CH05 query/response pairs -- which the wrapped-continuation rule
# glued into a one-segment MSH and dropped. P4-29's segment-ID rule recovers all of them;
# KNOWN_SWAPPED_HEADER_EXTRACTED_COUNTS below now equals this registry.)
#
# The brief named "about 80 CH04/CH04A examples" — the count P4-22 found while investigating
# a different (RXO) defect specifically in CH04. Confirming directly against the PDF text, as
# this task's brief instructs, surfaced the same transposed header in CH03 and CH05 as well
# (same defect, not confined to the chapters an earlier, narrower investigation happened to
# be looking at — see project requirement 1, feature-complete over AU-specific scoping): 138
# occurrences across nine sources, not ~80 across five.
KNOWN_SWAPPED_HEADER_SOURCES = {
    "v2.4/CH03.PDF": 10,
    "v2.4/CH04.PDF": 20,
    "v2.4/CH05.PDF": 36,
    "v2.5.1/V251_CH03.pdf": 10,
    "v2.5.1/V251_CH04.pdf": 22,
    "v2.6/V26_CH04_Orders.pdf": 22,
    "v2.8.2/V282_CH03_PatientAdmin.pdf": 2,
    "v2.8.2/V282_CH04_Orders.pdf": 4,
    "v2.8.2/V282_CH04A_Orders.pdf": 12,
}


def check_swapped_header_counts():
    """P4-28: count every occurrence of the transposed header (see _SWAPPED_ENC) directly in
    each source PDF's text, via the same pdftotext pass messages() uses. Returns {source:
    count} for every source with at least one occurrence. Needs the author-local PDFs, so
    (like check_registry) this is interactive-only, run via --check-registry."""
    counts = {}
    for version, pattern in CHAPTERS.items():
        for pdf in sorted(glob.glob(os.path.join(REPO, "docs/standards", pattern))):
            textout = subprocess.run(["pdftotext", "-layout", "-enc", "UTF-8", pdf, "-"],
                                      capture_output=True, text=True).stdout
            n = textout.count("MSH|" + _SWAPPED_ENC)
            if n:
                counts[f"{version}/{os.path.basename(pdf)}"] = n
    return counts


def _swapped_header_mismatches(actual=None):
    """P4-28: compare KNOWN_SWAPPED_HEADER_SOURCES against the real counts (or, for the
    synthetic self-check, an `actual` dict passed in directly so this runs without PDFs).
    Returns [(source, expected, got)] for every source where the two disagree, including a
    source present in only one side (the other side's count is then 0)."""
    if actual is None:
        actual = check_swapped_header_counts()
    mismatches = []
    for source in sorted(set(KNOWN_SWAPPED_HEADER_SOURCES) | set(actual)):
        expected = KNOWN_SWAPPED_HEADER_SOURCES.get(source, 0)
        got = actual.get(source, 0)
        if expected != got:
            mismatches.append((source, expected, got))
    return mismatches


# P4-28 fix round 1 (task review): KNOWN_SWAPPED_HEADER_SOURCES alone doesn't pin the
# EXTRACTOR — it re-derives its own count independently of messages()/_message_start, via a
# raw pdftotext substring search, so it would keep passing unchanged even if
# _message_start's swapped-header branch were deleted outright. This second registry counts
# the messages that actually come out of messages() flagged swappedHeader=True. Verified:
# deleting the swapped-header `if` branch in _message_start drops every count to 0, which
# --check-registry catches.
#
# P4-29: P4-28 extracted only 58 of the 138 (four sources), because the QBP/RSP/RTB
# examples print one segment per line with no "<cr>" and the whole message glued into a
# one-segment MSH that was then dropped. With the segment-ID rule in messages_from_lines()
# every printed swapped header now forms a message, so each source's extracted count equals
# its PDF-text count above; no source falls short.
KNOWN_SWAPPED_HEADER_EXTRACTED_COUNTS = {
    "v2.4/CH03.PDF": 10,
    "v2.4/CH04.PDF": 20,
    "v2.4/CH05.PDF": 36,
    "v2.5.1/V251_CH03.pdf": 10,
    "v2.5.1/V251_CH04.pdf": 22,
    "v2.6/V26_CH04_Orders.pdf": 22,
    "v2.8.2/V282_CH03_PatientAdmin.pdf": 2,
    "v2.8.2/V282_CH04_Orders.pdf": 4,
    "v2.8.2/V282_CH04A_Orders.pdf": 12,
}


def check_swapped_header_extracted_counts():
    """P4-28 fix round 1: count, per source, how many messages messages() actually extracts
    with swappedHeader=True — exercising the full extraction pipeline (_message_start included),
    not a raw PDF-text search. Needs the author-local PDFs, interactive-only via
    --check-registry, same as check_swapped_header_counts."""
    counts = {}
    for version, pattern in CHAPTERS.items():
        for pdf in sorted(glob.glob(os.path.join(REPO, "docs/standards", pattern))):
            n = sum(1 for e in messages(pdf) if e.get("swappedHeader"))
            if n:
                counts[f"{version}/{os.path.basename(pdf)}"] = n
    return counts


def _swapped_header_extracted_mismatches(actual=None):
    """P4-28 fix round 1: compare KNOWN_SWAPPED_HEADER_EXTRACTED_COUNTS against the real
    extracted counts (or, for the synthetic self-check, an `actual` dict passed in directly).
    Same shape as _swapped_header_mismatches."""
    if actual is None:
        actual = check_swapped_header_extracted_counts()
    mismatches = []
    for source in sorted(set(KNOWN_SWAPPED_HEADER_EXTRACTED_COUNTS) | set(actual)):
        expected = KNOWN_SWAPPED_HEADER_EXTRACTED_COUNTS.get(source, 0)
        got = actual.get(source, 0)
        if expected != got:
            mismatches.append((source, expected, got))
    return mismatches


def check_registry(report_lines):
    """P4-22 fix round 1: verify every KNOWN_SPEC_EXAMPLE_ERRORS entry's recorded count
    against a real SPECEX report (a list of already tab-split rows). Each entry consumes
    the lines it matches before the next one runs, so two entries can never double-count
    the same line. Returns (mismatches, unmatched) — mismatches is [(entry, actual_count)]
    for every entry whose match count differs from `count`; unmatched is whatever SPECEX
    rows no entry claimed (not itself a pass/fail signal here — a triage aid)."""
    remaining = list(report_lines)
    mismatches = []
    for entry in KNOWN_SPEC_EXAMPLE_ERRORS:
        pattern = re.compile(entry["location_pattern"])
        matched, rest = [], []
        for row in remaining:
            if len(row) < 6 or row[0] != "SPECEX":
                rest.append(row); continue
            src, idx, code, loc = row[1], row[2], row[3], row[4]
            ok = (fnmatch.fnmatch(src, entry["source_glob"])
                  and (entry["index"] == "all" or str(entry["index"]) == idx)
                  and (entry["code"] == "*" or code == entry["code"])
                  and pattern.match(loc))
            (matched if ok else rest).append(row)
        if len(matched) != entry["count"]:
            mismatches.append((entry, len(matched)))
        remaining = rest
    return mismatches, remaining


def triage(examples_path, report_path):
    """Rank the Validator's table rejections that deserve a look.

    Only examples whose declared MSH-12 matches the chapter that prints them count: about
    half the printed messages carry a stale version header (a v2.6 chapter printing
    "|2.4|"), and those are validated, correctly, under the version they declare. Values
    that are not code-shaped ("...", shifted text, timestamps) are example damage."""
    import collections
    declared = {}
    for e in json.load(open(examples_path)):
        fields = e["segments"][0].split("|")
        declared[(e["source"], e["index"])] = fields[11].strip() if len(fields) > 11 else ""
    consistent = sum(1 for (src, _), v in declared.items() if "v" + v == src.split("/")[0])
    print(f"{consistent} of {len(declared)} examples declare the version of the chapter that prints them")
    ranked, required = collections.Counter(), collections.Counter()
    for line in open(report_path):
        f = line.rstrip("\n").split("\t")
        if len(f) < 6:
            continue
        chapter = f[1].split("/")[0]
        if "v" + declared.get((f[1], int(f[2])), "") != chapter:
            continue
        where = re.sub(r"\[\d+\]", "", f[4])
        if "requiredFieldMissing" in f[3]:
            required[(chapter, where)] += 1
        m = re.search(r'value "(.*?)" is not in HL7 Table (\d+)', f[5])
        if "valueNotInTable" in f[3] and m and re.fullmatch(r"[A-Za-z0-9_/-]{1,10}", m.group(1)) \
                and not re.fullmatch(r"\d{6,}", m.group(1)):
            ranked[(chapter, where, m.group(2), m.group(1))] += 1
    print("-- table rejections worth a look (code-shaped values only):")
    for key, n in ranked.most_common(30):
        print(f"{n:4} {key}")
    # Triaged 2026-09-22 (M23): every frequent class was read against the print and the
    # example. All were the example's fault — a value one field over (SCH-7 holding the
    # reason SCH-6 requires; PID-6 holding the name PID-5 requires), or simply omitted
    # (MSH-7 in 60 printed messages; OBX-11 in v2.3 CH12; DG1-6). The optionality audit
    # (M19) had already proved each of those fields R in its own version. Re-triage only
    # when a NEW location appears here.
    print("-- required-field misses (all triaged as example damage as of M23):")
    for key, n in required.most_common(30):
        print(f"{n:4} {key}")


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "--triage":
        return triage(sys.argv[2], sys.argv[3])
    if len(sys.argv) == 3 and sys.argv[1] == "--check-registry":
        rows = [line.split("\t") for line in open(sys.argv[2], encoding="utf-8").read().splitlines()]
        mismatches, unmatched = check_registry(rows)
        for entry, actual in mismatches:
            print(f"MISMATCH {entry['source_glob']} index={entry['index']} {entry['code']} "
                  f"{entry['location_pattern']}: expected {entry['count']}, matched {actual}")
        # P4-28: the swapped-header count is verified separately, directly against the PDF
        # text (see KNOWN_SWAPPED_HEADER_SOURCES) rather than through a SPECEX report row.
        swapped_mismatches = _swapped_header_mismatches()
        for source, expected, got in swapped_mismatches:
            print(f"MISMATCH swapped header {source}: expected {expected}, counted {got}")
        # P4-28 fix round 1 (task review): the PDF-text count above doesn't pin the extractor
        # itself — this does, by exercising messages()/_message_start directly.
        extracted_mismatches = _swapped_header_extracted_mismatches()
        for source, expected, got in extracted_mismatches:
            print(f"MISMATCH swapped header extracted {source}: expected {expected}, counted {got}")
        print(f"{len(KNOWN_SPEC_EXAMPLE_ERRORS)} registry entries, {len(mismatches)} mismatched, "
              f"{len(unmatched)} SPECEX lines unclaimed by any entry; "
              f"{len(KNOWN_SWAPPED_HEADER_SOURCES)} swapped-header sources, "
              f"{len(swapped_mismatches)} mismatched; "
              f"{len(KNOWN_SWAPPED_HEADER_EXTRACTED_COUNTS)} swapped-header extracted sources, "
              f"{len(extracted_mismatches)} mismatched")
        sys.exit(1 if (mismatches or swapped_mismatches or extracted_mismatches) else 0)
    out = []
    for version, pattern in CHAPTERS.items():
        n = 0
        for pdf in sorted(glob.glob(os.path.join(REPO, "docs/standards", pattern))):
            for i, msg in enumerate(messages(pdf)):
                out.append({"source": f"{version}/{os.path.basename(pdf)}", "index": i, **msg})
                n += 1
        print(f"{version}: {n} example messages")
    with open(sys.argv[1], "w", encoding="utf-8") as f:
        json.dump(out, f)
    print(f"{len(out)} messages written to {sys.argv[1]}")


if __name__ == "__main__":
    main()
