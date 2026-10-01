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
header — see _message_start) and runs while lines are segments; a segment ends at "<cr>" and
may wrap over several printed lines.

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


def _continuation_runs_into_prose(seg, line):
    """P4-22 fix round 1 / P4-28 fix round 2: true when an open, un-terminated segment (the
    PDF dropped its <cr>) has run off the end of its figure into ordinary document text — a
    numbered section heading (heading shape AND no "|" anywhere on the line — segment data
    always has one, prose heading never does), or (heading or not) a segment that has grown
    far past any real printed example's length. ("// comment" annotations are handled
    earlier, by _strip_comment, before a line ever reaches this check.)"""
    looks_like_heading = (bool(_SECTION_HEADING_MULTI_DOT.match(line))
                          or bool(_SECTION_HEADING_ONE_DOT.match(line))) and "|" not in line
    return looks_like_heading or len(seg) > _MAX_SEGMENT_LEN


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
        if i > 0 and f.strip() == "...":
            kept = fields[:i]
            if len(kept) == 1:
                kept.append("")
            return "|".join(kept), i
    return seg, None


def messages(pdf):
    text = subprocess.run(["pdftotext", "-layout", "-enc", "UTF-8", pdf, "-"], capture_output=True, text=True).stdout.split("\n")
    out, out_swapped, out_bare = [], [], []
    cur, seg, cur_swapped, cur_bare = None, None, False, False
    def close():
        nonlocal cur, seg, cur_swapped, cur_bare
        if cur is not None:
            if seg: cur.append(seg)
            if len(cur) >= 2:
                out.append(cur); out_swapped.append(cur_swapped); out_bare.append(cur_bare)
        cur, seg, cur_swapped, cur_bare = None, None, False, False
    for raw in text:
        if FURN.search(raw): continue
        for line in _split_literal_cr(_strip_comment(raw.strip())):
            start = _message_start(line)
            if start is not None:
                close(); cur, seg, cur_swapped, cur_bare = [], start[0], start[1], start[2]; continue
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
                    seg = line
                else:
                    close()
            elif seg.endswith("<cr>"):
                cur.append(seg)
                if m and _BARE_ELIDED_SEGMENT.match(line):
                    cur.append(line); seg = None
                elif m:
                    seg = line
                else:
                    seg = None; close()
            elif _continuation_runs_into_prose(seg, line):
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
    # extracted text.
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
    # (v2.8.2 CH04A). v2.8.2 CH04 (not CH04A) is NOT among these: all four of its swapped
    # headers belong to the "Query the accumulated list..." QBP/RTB family, which the
    # separate, pre-existing no-"<cr>" segment-merge limitation (see the comment above
    # KNOWN_SWAPPED_HEADER_SOURCES) still drops before a message is ever produced.
    *[{"source_glob": src, "index": idx, "code": "conditionalFieldMissing",
       "location_pattern": r"^RXO\[\d+\]-[124]$", "count": 3, "reason": _RXO_FREE_TEXT_REASON}
      for src, idx in {"v2.4/CH04.PDF": 19, "v2.5.1/V251_CH04.pdf": 20,
                        "v2.6/V26_CH04_Orders.pdf": 19, "v2.8.2/V282_CH04A_Orders.pdf": 2}.items()],
]

# P4-28: the swapped header itself, per source, counted directly in the PDF text (the exact
# transposed four-character substring, not a downstream Validator finding — see _SWAPPED_ENC
# above for the transposition and the PDF-text evidence it rests on). This is deliberately
# NOT folded into KNOWN_SPEC_EXAMPLE_ERRORS / check_registry: that machinery matches SPECEX
# report rows (Validator findings on a successfully-extracted, segment-split message), and
# a good number of these occurrences belong to example families (e.g. the "Query the
# accumulated list..." QBP^Z73/RTB^Z74 family, and several CH03/CH05 query/response pairs)
# that the PDF prints with plain line-per-segment layout and no literal "<cr>" marker at
# all — a separate, pre-existing limitation in messages()'s wrapped-continuation handling (an
# open, unterminated segment unconditionally absorbs the next physical line as more of
# itself, even when that line is itself a new segment), well outside this task's scope, that
# still silently drops those messages (len(cur) < 2) even though their header is now
# correctly recognised and normalised. Counting occurrences directly, independent of that
# gap, is what "verified" means here and is checked on every --check-registry run regardless.
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
# the messages that actually come out of messages() flagged swappedHeader=True — only the
# four sources whose messages survive the separate, documented no-"<cr>" segment-merge
# limitation have any (the other five sources' occurrences never form a complete message at
# all, swapped-header handling or not). Verified: deleting the swapped-header `if` branch in
# _message_start drops every one of these four counts to 0, which --check-registry catches.
KNOWN_SWAPPED_HEADER_EXTRACTED_COUNTS = {
    "v2.4/CH04.PDF": 16,
    "v2.5.1/V251_CH04.pdf": 16,
    "v2.6/V26_CH04_Orders.pdf": 16,
    "v2.8.2/V282_CH04A_Orders.pdf": 10,
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
