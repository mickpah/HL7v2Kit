#!/usr/bin/env python3
"""Guard: a printed (trigger, structure ID) pair is never a message-structure mismatch.

LOCAL / MANUAL GUARD, NOT A CI JOB. It reads the licensed HL7 PDFs under docs/standards
(not in the repository), so it runs only on a host that has them, like
`audit-schemas.py --examples` and `extract-example-messages.py --check-registry`.

    python3 scripts/check-printed-structure-ids.py            # sweep, digest run, verdict
    python3 scripts/check-printed-structure-ids.py --work DIR # keep the intermediate files

Method (P8b final fix wave, Stage 4 and Stage 6; committed by P7-8). Every pair a version
prints is collected: each Table 0354 listing (the CH02 / CH02C layout and the Appendix A
"0354 ID events" layout), each printed caption, each caption erratum's printed form and each
query profile "Query Trigger" / "Response Trigger" row. One MSH-only message per pair is
validated with the message-structure check at `.error` through the env-gated
ValidationDigestTests (SPEC_EXAMPLE_MESSAGES, VALIDATION_DIGEST_OUT,
VALIDATION_DIGEST_STRUCTURE_SEVERITY=error). A Table 0354 row prints events, not message
codes, so each event is tried under the ID's code, an erratum's corrected code and every code
a caption prints for that event; the row is reported only when every try is a mismatch. A
caption or profile pair is reported as it is.

Exit status: 0 when the reported rows are exactly ALLOWED; 1 when any other row is reported
or an ALLOWED row is no longer reported (stale allow-list); 2 on a setup failure. The output
is two lines at most per row, ending in one result line.
"""
import argparse, glob, importlib.util, json, os, re, subprocess, sys, tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STANDARDS = os.path.join(REPO, "docs/standards")

# The six rows the sweep reports that are the print's own doing (P8b final fix report, Stage
# 4): each is a Table 0354 event printed with a digit for a letter. None is a trigger event
# (Table 0003 prints A36, I11, O07 and O22, and the chapters print those), so no message can
# carry it as MSH-9.2 from the print; the corrected pairs (ADT^A36^ADT_A30, RPA^I11^RPA_I08,
# OMN^O07^OMN_O07, ORL^O22^ORL_O22) are in the sweep and draw no mismatch.
ALLOWED = {
    ("2.3.1", "136", "ADT_A30"): "v2.3.1 CH02 Table 0354 (p 2-103) prints 'ADT_A30 A30, A34, A35, 136, ...' for A36",
    ("2.3.1", "1II", "RPA_I08"): "v2.3.1 CH02 Table 0354 (p 2-104) prints 'RPA_I08 I08, I09. I10, 1II' for I11",
    ("2.4", "007", "OMN_O07"): "v2.4 CH02 Table 0354 (p 2-138) prints 'OMN_O07 007' for O07",
    ("2.4", "022", "ORL_O22"): "v2.4 CH02 Table 0354 (p 2-138) prints 'ORL_O22 022' for O22",
    ("2.5.1", "007", "OMN_O07"): "v2.5.1 CH02 and Appendix A Table 0354 print 'OMN_O07 007' for O07",
    ("2.5.1", "022", "ORL_O22"): "v2.5.1 CH02 and Appendix A Table 0354 print 'ORL_O22 022' for O22",
}

ROW = re.compile(r"^\s*([A-Z][A-Z0-9]{2,3}_{1,2}[A-Z0-9]{3})\b(.*)$")
APPROW = re.compile(r"^\s*0354\s+([A-Z][A-Z0-9]{2,3}_{1,2}[A-Z0-9]{3})\b(.*)$")
PROFILE = re.compile(r"(Query|Response) Trigger[^:]*:\s+([A-Z][A-Z0-9]{2})\^([A-Z0-9]{3})\^([A-Z][A-Z0-9]{2}_[A-Z0-9]{3})\b")
EVT = re.compile(r"(?<![A-Za-z0-9])[A-Z0-9]{3}(?![A-Za-z0-9])")
# Table 0354 text sources per version beyond the extractor's chapter globs (Appendix A).
APPENDIX = {"v2.3": [], "v2.3.1": [], "v2.4": ["HL7_v24_PDF/AppendixA.PDF"],
            "v2.5.1": ["HL7_v251_PDF/V251_Appendix_A.pdf"], "v2.6": ["HL7_v26_PDF/V26_Appendix_A.pdf"],
            "v2.7.1": ["HL7_V271_PDF/PDF/V271_Appendix_A.pdf"],
            "v2.8.2": ["HL7_V2.8.2_PDF/PDF/V282_Appendix_A.pdf"]}
VERSIONS = ["v2.3", "v2.3.1", "v2.4", "v2.5.1", "v2.6", "v2.7.1", "v2.8.2"]


def load_extractor():
    spec = importlib.util.spec_from_file_location("ems", os.path.join(REPO, "scripts/extract-message-structures.py"))
    ems = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(ems)
    return ems


def table_rows(lines):
    """Rows of every printed Table 0354 in `lines`: (ID, [events]). A region opens at a line
    naming table 0354 with 'structure' and closes at the next line naming another table."""
    rows, inside, last = [], False, None
    for line in lines:
        if re.search(r"0354\b", line) and re.search(r"[Ss]tructure", line):
            inside, last = True, None
            continue
        if inside and re.search(r"\b(?:HL7 )?[Tt]able 0(?!354)\d{3}\b", line):
            inside, last = False, None
            continue
        a = APPROW.match(line)
        if a:     # Appendix A layout: "0354   ID   events" on every row
            last = [a.group(1), EVT.findall(a.group(2).split("  Deprecated")[0])]
            rows.append(last)
            continue
        if not inside:
            if last is not None and line.strip() and re.fullmatch(r"[\sA-Z0-9,]+", line):
                last[1] += EVT.findall(line)
            else:
                last = None
            continue
        m = ROW.match(line)
        if m:
            last = [m.group(1), EVT.findall(m.group(2).split("  Deprecated")[0])]
            rows.append(last)
        elif last is not None and line.strip() and re.fullmatch(r"[\sA-Z0-9,]+", line):
            last[1] += EVT.findall(line)
        elif not line.strip():
            last = None
    return [(i, e) for i, e in rows if e]


def pairs(ems, overrides, ver):
    """{(CODE^EVT, structure ID): {where printed}} for one version."""
    v = ver[1:]
    chapters = ems.pdf_texts(ver)
    texts = list(chapters)
    for rel in APPENDIX.get(ver, []):
        text = subprocess.run(["pdftotext", "-layout", "-enc", "UTF-8", os.path.join(STANDARDS, rel), "-"],
                              capture_output=True, text=True).stdout
        texts.append((rel, text.split("\n")))
    errata = [e for e in overrides["errata"] if e["version"] == v and e["where"] == "table-0354"]
    folds = [f for f in overrides["triggerFolds"] if f["version"] == v]
    general = {f["structure"] for f in folds if f["trigger"] == f"{f['structure']}^*"}
    era = ems.ERAS[ver][1]
    out, codes_of = {}, {}
    for source, lines in chapters:
        for cap in ems.captions(lines, era, source, bare=general):
            for ev in (cap.events or [cap.event]):
                codes_of.setdefault(ev, set()).add(cap.code)     # the message code the chapters print for ev
                if cap.id_source == "printed" and cap.structure:
                    out.setdefault((f"{cap.code}^{ev}", cap.structure), set()).add(
                        f"caption {cap.printed} {os.path.basename(source)} {cap.section}")
    for source, lines in texts:
        for sid, events in table_rows(lines):
            codes = {sid.split("_")[0]} | {e["structure"].split("_")[0] for e in errata if e["printed"] == sid}
            evs = set(events)
            for e in errata:
                if e["structure"] == sid or e["printed"] == sid:
                    evs |= set() if "_" in e["intended"] else set(EVT.findall(e["intended"]))
            for ev in evs:
                for c in codes | codes_of.get(ev, set()):
                    out.setdefault((f"{c}^{ev}", sid), set()).add(f"row {ev} {sid} Table 0354 {os.path.basename(source)}")
    for source, lines in chapters:
        for line in lines:
            m = PROFILE.search(line)
            if m:
                out.setdefault((f"{m.group(2)}^{m.group(3)}", m.group(4)), set()).add(
                    f"profile {m.group(1)} Trigger {os.path.basename(source)}")
    for e in overrides["errata"]:
        if e["version"] == v and e["where"] == "caption" and e["printed"].count("^") == 2:
            c, ev, sid = e["printed"].split("^")
            out.setdefault((f"{c}^{ev}", sid), set()).add(f"caption erratum {e['printed']}")
    return out


def sweep(work):
    """Write the pair messages and their metadata; return the metadata."""
    ems = load_extractor()
    overrides = ems.load_overrides()
    examples, meta, index = [], {}, 0
    for ver in VERSIONS:
        for (trig, sid), where in sorted(pairs(ems, overrides, ver).items()):
            index += 1
            meta[index] = [ver[1:], trig, sid, sorted(where)]
            examples.append({"source": f"sweep:{ver[1:]}:{trig}^{sid}", "index": index,
                             "segments": [f"MSH|^~\\&|S|SF|R|RF|20240101120000||{trig}^{sid}|{index}|P|{ver[1:]}"]})
    with open(os.path.join(work, "pairs.json"), "w", encoding="utf-8") as f:
        json.dump(examples, f)
    return meta


def run_digest(work):
    env = dict(os.environ, SPEC_EXAMPLE_MESSAGES=os.path.join(work, "pairs.json"),
               VALIDATION_DIGEST_OUT=os.path.join(work, "digest.tsv"),
               VALIDATION_DIGEST_STRUCTURE_SEVERITY="error")
    env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    with open(os.path.join(work, "swift-test.txt"), "w") as log:
        rc = subprocess.run(["xcrun", "swift", "test", "--filter", "ValidationDigestTests"], cwd=REPO, env=env,
                            stdout=log, stderr=subprocess.STDOUT, timeout=1800).returncode
    if rc != 0 or not os.path.exists(env["VALIDATION_DIGEST_OUT"]):
        sys.exit(f"setup failure: the digest run failed (see {log.name})")
    return env["VALIDATION_DIGEST_OUT"]


def reported(meta, digest):
    """{(version, event, ID) or (version, pair, where): where} the validator reports as a mismatch."""
    bad = set()
    for line in open(digest, encoding="utf-8"):
        f = line.rstrip("\n").split("\t")
        if f[0].startswith("sweep:") and len(f) > 4 and f[1] == "international" and f[2] == "0" \
                and f[4].startswith("messageStructureMismatch"):
            bad.add(int(f[0].rsplit("#", 1)[1]))
    rows, report = {}, {}
    for i, (ver, trig, sid, where) in meta.items():
        for w in where:
            if w.startswith("row "):
                _, ev, rsid = w.split()[:3]
                rows.setdefault((ver, ev, rsid), []).append((trig, i in bad, w.split(" Table 0354 ")[1]))
            elif i in bad:
                report[(ver, trig, sid)] = w
    for (ver, ev, sid), tries in rows.items():
        if all(b for _, b, _ in tries):
            report[(ver, ev, sid)] = (f"row (tried {', '.join(sorted({t for t, _, _ in tries}))}) in "
                                      + ", ".join(sorted({s for _, _, s in tries})))
    return report, len(bad), len(rows)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--work", help="directory for the intermediate files (default: a temporary one)")
    args = ap.parse_args()
    if not glob.glob(os.path.join(STANDARDS, "HL7_v251_PDF", "*.pdf")):
        sys.exit("setup failure: the licensed PDFs are not under docs/standards (local guard only)")
    work = args.work or tempfile.mkdtemp(prefix="printed-ids-")
    os.makedirs(work, exist_ok=True)
    meta = sweep(work)
    report, nbad, nrows = reported(meta, run_digest(work))
    unexpected = sorted(k for k in report if k not in ALLOWED)
    stale = sorted(k for k in ALLOWED if k not in report)
    for k in unexpected:
        print(f"UNEXPECTED {' '.join(k)}: {report[k]}")
    for k in stale:
        print(f"STALE allow-list row {' '.join(k)} is no longer reported ({ALLOWED[k]})")
    print(f"{len(meta)} printed pair messages, {nbad} draw a mismatch under some code; {nrows} Table 0354 "
          f"(event, ID) rows; {len(report)} reported, {len(report) - len(unexpected)} allowed, "
          f"{len(unexpected)} unexpected, {len(stale)} stale")
    sys.exit(1 if unexpected or stale else 0)


if __name__ == "__main__":
    main()
