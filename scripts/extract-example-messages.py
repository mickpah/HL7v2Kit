#!/usr/bin/env python3
"""M18 — extract the complete example MESSAGES the specification prints, for an end-to-end
run through the Swift Validator.

    python3 scripts/extract-example-messages.py /tmp/spec-examples.json
    SPEC_EXAMPLE_MESSAGES=/tmp/spec-examples.json SPEC_EXAMPLE_REPORT=/tmp/report.tsv \\
        DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter SpecExampleMessageTests
    python3 scripts/extract-example-messages.py --triage /tmp/spec-examples.json /tmp/report.tsv

The output is specification text and, like the PDFs, stays OUT of the repository: write it
to a scratch path. A message starts at "MSH|^~\\&" and runs while lines are segments; a
segment ends at "<cr>" and may wrap over several printed lines.

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
# P4-22 fix round 1: a numbered section/subsection heading ("4.8  PHARMACY/TREATMENT
# ORDERS", "2.11  LOCAL EXTENSION"), the marker that a segment whose own <cr> the PDF
# dropped has run off the end of its figure and into ordinary prose.
_SECTION_HEADING = re.compile(r"^\s*\d+(\.\d+){1,3}\s+[A-Z]")
# No printed segment in this corpus, even wrapped over several lines, gets within an order
# of magnitude of this; a real missing <cr> that runs a continuation into unrelated prose
# (a swallowed worked example, a swallowed component table) reaches 100K+ characters.
_MAX_SEGMENT_LEN = 3000


def _continuation_runs_into_prose(seg, line):
    """P4-22 fix round 1: true when an open, un-terminated segment (the PDF dropped its
    <cr>) has run off the end of its figure into ordinary document text — a numbered
    section heading, or (heading or not) a segment that has grown far past any real
    printed example's length."""
    return bool(_SECTION_HEADING.match(line)) or len(seg) > _MAX_SEGMENT_LEN


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
    out, cur, seg = [], None, None
    def close():
        nonlocal cur, seg
        if cur is not None:
            if seg: cur.append(seg)
            if len(cur) >= 2: out.append(cur)
        cur, seg = None, None
    for raw in text:
        if FURN.search(raw): continue
        for line in _split_literal_cr(raw.strip()):
            if line.startswith("MSH|^~\\&"):
                close(); cur, seg = [], line; continue
            if cur is None: continue
            if not line:
                if seg and seg.endswith("<cr>"): cur.append(seg); seg = None
                continue
            m = SEG.match(line)
            if seg is None:
                if m: seg = line
                else: close()
            elif seg.endswith("<cr>"):
                cur.append(seg); seg = line if m else None
                if not m: close()
            elif _continuation_runs_into_prose(seg, line):
                # P4-22 fix round 1: the PDF dropped this segment's own <cr>, so the
                # "wrapped continuation" branch below would otherwise keep absorbing raw
                # lines past the end of the figure — into a section heading, or (if a
                # heading never arrives, e.g. a table of component rows) indefinitely.
                # Close what has genuinely accumulated rather than let it run on; the
                # triggering line itself (heading or otherwise) is not segment content and
                # is dropped, same as page furniture.
                cur.append(seg); seg = None
            else:
                seg += line          # a wrapped continuation of the open segment
    close()
    clean = []
    for msg in out:
        segs = [re.sub(r"\s*<cr>\s*$", "", s) for s in msg]
        dropped = [_drop_elision(s) for s in segs]
        cleaned = [d[0] for d in dropped]
        if all(SEG.match(s) for s in cleaned):
            clean.append(_elision_metadata(cleaned, dropped))
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
# count against a real report, via `--check-registry <report.tsv>` — that needs the
# author-local PDFs to regenerate a report, so (like `audit-schemas.py --examples`) it
# cannot run in CI and is interactive-only; CI instead runs only the synthetic-fixture
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
_RXO_INVISIBLE_REASON = (
    "Fix round 1: v2.3.1 index 36 IS a splice (RQD|5's own <cr> is missing in the PDF, so "
    "before the round-1 heading/length guard it absorbed ~2,300 lines of section 4.8 prose, "
    "ending at the glued-on ORC/RXO text of this worked example, which the giant RQD-5 "
    "string's own eventual <cr> terminator cut loose as its own, separate RXO segment, "
    "eight lines into a message where it does not belong) — v2.3 CH4 index 1 is the same "
    "worked example, same splice. The round-1 guard now correctly truncates RQD-5 and stops "
    "before reaching the glued-on content at all, so this example is no longer extracted: "
    "its own MSH is fully elided (\"MSH|...\", no encoding characters), which this "
    "extractor's message-boundary detection (a literal \"MSH|^~\\&\" prefix) does not "
    "recognise as a new message. Both things were true before the fix — it was a splice, "
    "AND the RXO line it carried had the genuine free-text defect above — the fix removes "
    "the line, not the underlying defect, which is simply no longer visible to this sweep.\n"
    "Fix round 2 correction: the v2.4+ CH04/CH04A \"E-mail only\" and custom-IV examples the "
    "original brief cited are invisible for a DIFFERENT reason, not the same \"MSH|...\" "
    "elision as v2.3.1 — their printed MSH header transposes two encoding characters, "
    "\"MSH|^&~\\|...\" instead of \"MSH|^~\\&...\" (confirmed directly in the PDF text: "
    "v2.4 CH04.PDF 20 occurrences, v2.5.1 V251_CH04.pdf 22, v2.6 V26_CH04_Orders.pdf 22, "
    "v2.8.2 V282_CH04_Orders.pdf 4, v2.8.2 V282_CH04A_Orders.pdf 12 — roughly 80 messages "
    "total), so the literal \"MSH|^~\\&\" prefix check simply does not match and these "
    "examples are never recognised as message starts at all. Both causes are named,"
    " deliberate limitations of the message-boundary heuristic, not silently-dropped "
    "findings; neither is fixed in this round — the controller scoped bringing the ~80 "
    "swapped-header messages into the sweep as a separate task, P4-28.")
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
    {"source_glob": "v2.3.1/Hl7V231.pdf", "index": 84, "code": "conditionalFieldMissing",
     "location_pattern": r"^RXO\[\d+\]-[12]$", "count": 2, "reason": _RXO_FREE_TEXT_REASON},
    *[{"source_glob": src, "index": 2, "code": "conditionalFieldMissing",
       "location_pattern": r"^RXO\[\d+\]-[12]$", "count": 2, "reason": _RXO_FREE_TEXT_REASON}
      for src in _RXO_CH12_SOURCES],
    # Documentation/regression-guard entries: these should match NOTHING (count 0). Fix
    # round 2: keyed to "all" indices, not literally index 36 / index 1 — those specific
    # indices can never match RXO again regardless of what the extractor does (the message
    # is gone, not relocated), which made the original index-keyed guard pass trivially no
    # matter what changed. Keying "all" instead means this runs against whatever RXO lines
    # remain in the whole source after the real registered RXO entries above have already
    # claimed theirs (entries are consumed in order, see check_registry), so if the E-mail
    # example ever starts being extracted again — at index 36, or at any other index a
    # future extractor change gives it — its RXO lines are what trips this to a mismatch.
    {"source_glob": "v2.3.1/Hl7V231.pdf", "index": "all", "code": "*", "location_pattern": r"^RXO",
     "count": 0, "reason": _RXO_INVISIBLE_REASON},
    {"source_glob": "v2.3/CH4.pdf", "index": "all", "code": "*", "location_pattern": r"^RXO",
     "count": 0, "reason": _RXO_INVISIBLE_REASON},
]


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
        print(f"{len(KNOWN_SPEC_EXAMPLE_ERRORS)} registry entries, {len(mismatches)} mismatched, "
              f"{len(unmatched)} SPECEX lines unclaimed by any entry")
        sys.exit(1 if mismatches else 0)
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
