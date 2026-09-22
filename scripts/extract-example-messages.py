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
        line = raw.strip()
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
        if all(SEG.match(s) for s in segs): clean.append(segs)
    return clean


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
