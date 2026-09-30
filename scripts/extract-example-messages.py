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
import re, sys, json, glob, subprocess, os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHAPTERS = {
    "v2.3": "HL7_v23_PDF/CH*.pdf", "v2.3.1": "HL7_v231_PDF/Hl7V231.pdf", "v2.4": "HL7_v24_PDF/CH*.PDF",
    "v2.5.1": "HL7_v251_PDF/V251_CH*.pdf", "v2.6": "HL7_v26_PDF/V26_CH*.pdf",
    "v2.8.2": "HL7_V2.8.2_PDF/PDF/V282_CH*.pdf",
}
FURN = re.compile(r"Health Level Seven|All rights reserved|Final Standard|^\s*Page \d|^\s*Chapter \d+A?:|^\f")
SEG = re.compile(r"^\s*([A-Z][A-Z0-9]{2})\|")
_LITERAL_CR = re.compile(r"<cr>", re.IGNORECASE)


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
    normalised = re.sub(r"(?:<cr>){2,}", "<cr>", normalised)
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
    version implied by garbage text."""
    fields = seg.split("|")
    for i, f in enumerate(fields):
        if i > 0 and f.strip() == "...":
            kept = fields[:i]
            if len(kept) == 1:
                kept.append("")
            return "|".join(kept)
    return seg


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
            else:
                seg += line          # a wrapped continuation of the open segment
    close()
    clean = []
    for msg in out:
        segs = [re.sub(r"\s*<cr>\s*$", "", s) for s in msg]
        segs = [_drop_elision(s) for s in segs]
        if all(SEG.match(s) for s in segs): clean.append(segs)
    return clean


# P4-22 — registered exceptions for the message-level sweep: genuine HL7 spec-example
# errors, not extraction artefacts. Each entry records version, chapter/section, the
# example index(es) in the extracted JSON, the finding(s) it produces in the SPECEX report,
# and a one-line reason the EXAMPLE is at fault, not the rule — the same discipline as
# audit-schemas.py's EXPECTED_EXAMPLE_REJECTIONS (M17, "registered exceptions"), adapted for
# this sweep, which (per the module docstring above) is a triage source with no automated
# pass/fail gate to wire these into; they are recorded here for the next diff against
# spec-example-baseline.txt to check against, not enforced.
KNOWN_SPEC_EXAMPLE_ERRORS = [
    {
        "version": "v2.3, v2.3.1, v2.4, v2.5.1, v2.6, v2.8.2",
        "location": "CH10 (Scheduling), AIS/AIG/AIL/AIP examples",
        "index": "every AIS/AIG/AIL/AIP example message in each version's CH10",
        "finding": "conditionalFieldMissing on AIx-6 (start) and AIx-7 (offset): 120 lines",
        "reason": ("v2.5.1 CH10 sec 10.6.4.4: \"To specify that there is no difference "
                   "between the appointment's start date/time and the resource's start "
                   "date/time either replicate the appointment's start date/time into this "
                   "field, or specify an offset of zero.\" Every printed example leaves both "
                   "start and offset empty, satisfying neither option (verified P4-17)."),
    },
    {
        "version": "v2.3, v2.3.1, v2.4, v2.5.1, v2.6, v2.8.2",
        "location": "CH10 (Scheduling), AIS/AIG/AIL/AIP examples",
        "index": "every AIS/AIG/AIL/AIP example message in each version's CH10",
        "finding": "conditionalFieldMissing on AIx-11 (substitution) and AIx-12 (filler status): 57 lines",
        "reason": ("Every printed example except the v2.5.1+ SRM AIP omits the empty "
                   "Segment Action Code slot (field 2), so the substitution and filler-"
                   "status codes the example does carry land one field early (verified "
                   "P4-12/P4-17)."),
    },
    {
        "version": "v2.3, v2.3.1, v2.4",
        "location": "CH10 (Scheduling), AIL/AIP examples",
        "index": "every AIL/AIP example message in each version's CH10",
        "finding": "requiredFieldMissing on AIL-4/AIP-4: 30 lines",
        "reason": ("Same cause as the field-2 omission above: AIL-3/AIP-3 (the resource "
                   "identifier) is R on these three versions (C only from v2.5.1) and the "
                   "examples leave it blank too, so AIL-4/AIP-4 (Location/Resource Type) "
                   "report missing under the plain R rule rather than a condition."),
    },
    {
        "version": "v2.3.1, v2.4, v2.5.1, v2.6, v2.8.2",
        "location": "CH04/CH04A sec 4.14.1.1/.2/.4 (v2.3.1: monolithic PDF equivalent), CH12 worked examples",
        "index": "v2.3.1 index 36 and 84; v2.4/v2.5.1/v2.6/v2.8.2 CH12 index 2",
        "finding": "conditionalFieldMissing on RXO-1/RXO-2 (index 84: RXO-1/2 only; all others: RXO-1/2/4): 16 lines total",
        "reason": ("v2.5.1 CH04 sec 4.14.1.1/.2/.4 (identical wording all six): \"RXO-1, "
                   "RXO-2 and RXO-4 are mandatory unless the prescription/treatment is "
                   "transmitted as free text using RXO-6, then RXO-1, RXO-2 and RXO-4 may "
                   "be blank and the first subcomponent of RXO-6 must be blank.\" Every "
                   "cited example carries plain free text in RXO-6 with no leading \"^\", "
                   "so RXO-6.1 is non-empty and the carve-out does not apply, even though "
                   "Chapter 4 elsewhere states the convention is \"place a null in the "
                   "first component and the text in the second\" (verified P4-17)."),
    },
    {
        "version": "v2.3",
        "location": "CH4 sec 4.8.2.1/.2/.4",
        "index": "CH4 index 1 (the same worked example v2.3.1 prints at index 36)",
        "finding": "requiredFieldMissing on RXO-1/RXO-2/RXO-4: 3 lines",
        "reason": ("RXO-1/2/4 are plain R on v2.3 (no free-text carve-out modelled there), "
                   "so the same free-text-without-null-component example that trips the "
                   "conditional rule from v2.3.1 onward trips the flat R rule here instead. "
                   "NOT a splice artefact: the extractor fix (P4-22 Part 1) leaves the RXO "
                   "segment for this example byte-for-byte unchanged; a neighbouring ORC "
                   "field was truncated by the elision fix, but that does not touch this "
                   "finding."),
    },
]


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
    out = []
    for version, pattern in CHAPTERS.items():
        n = 0
        for pdf in sorted(glob.glob(os.path.join(REPO, "docs/standards", pattern))):
            for i, segments in enumerate(messages(pdf)):
                out.append({"source": f"{version}/{os.path.basename(pdf)}", "index": i, "segments": segments})
                n += 1
        print(f"{version}: {n} example messages")
    with open(sys.argv[1], "w", encoding="utf-8") as f:
        json.dump(out, f)
    print(f"{len(out)} messages written to {sys.argv[1]}")


if __name__ == "__main__":
    main()
