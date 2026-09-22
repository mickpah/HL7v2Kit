#!/usr/bin/env python3
"""M10-A — extract the HL7 datatype component tables (Chapter 2A) into JSON.

    python3 scripts/extract-datatype-components.py 2.5.1            # print a summary
    python3 scripts/extract-datatype-components.py 2.5.1 --write    # emit Resources/datatypes/v2.5.1/*.json

Only v2.5.1, v2.6 and v2.8.2 print "HL7 Component Table - <DT>" figures. v2.3, v2.3.1
and v2.4 define components in prose ("Components: <a> ^ <b>") and are out of scope
(registered in ADR-017).

The layout is regular, so this is a plain column reader over `pdftotext -layout`: a
caption names the datatype, a header row fixes the column starts (re-read on every page
repeat), a row begins with an integer under SEQ, and a line with no SEQ continues the
previous row's COMPONENT NAME or an open ("NNNN/") TBL# cell.
"""
import json, os, re, subprocess, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STANDARDS = os.path.join(REPO, "docs/standards")
PDFS = {
    "2.5.1": "HL7_v251_PDF/V251_CH02A.pdf",
    "2.6":   "HL7_v26_PDF/V26_CH02A_DataTypes.pdf",
    "2.8.2": "HL7_V2.8.2_PDF/PDF/V282_CH02A_DataTypes.pdf",
}
CAPTION = re.compile(r"HL7 Component Table\s*[-–]\s*([A-Z][A-Z0-9]{1,3})\s*[-–]?\s*(.*)$")
HEADER_KEYS = [("SEQ", "SEQ"), ("LEN", "LEN"), ("CLEN", "C.LEN"), ("DT", "DT"), ("OPT", "OPT"),
               ("TBL", "TBL#"), ("NAME", "COMPONENT NAME"), ("COMMENTS", "COMMENTS"), ("SECREF", "SEC.REF")]
FURNITURE = re.compile(r"Health Level Seven|All rights reserved|Final Standard|^\s*Chapter 2A?:|^\s*Page \d|^\f")
HEADING = re.compile(r"^\s*2\.?A?\.\d+(\.\d+)*\s+\S")


def columns(line):
    up, cols = line.upper(), []
    if "SEQ" not in up or "COMPONENT NAME" not in up:
        return None
    for key, pat in HEADER_KEYS:
        at = up.find(pat)
        if at >= 0 and not (key == "LEN" and up[at - 2:at] == "C."):
            cols.append((key, at))
    return sorted(cols, key=lambda c: c[1])


def cells(line, cols):
    """Assign each run of text to the column whose start is nearest at or before the run's
    start (3 columns of slack for left-shifted cells), then correct by CONTENT: the header's
    "COMPONENT NAME" is centred over a wider column, so a name can start under TBL# (v2.5.1
    AD). A TBL# cell is only ever digits and slashes; anything else there is the name."""
    out = {k: "" for k, _ in cols}
    for m in re.finditer(r"\S+(?: \S+)*", line):
        key = cols[0][0]
        for k, start in cols:
            if m.start() >= start - 3:
                key = k
        text = m.group()
        if key == "TBL":
            lead = re.match(r"(\d{3,4}(?:\s*/\s*\d{0,4})*)\s+(\D.*)$", text)   # "0399 Country"
            if lead:
                out["TBL"] = (out["TBL"] + lead.group(1)).strip()
                key, text = "NAME", lead.group(2)
            elif not re.fullmatch(r"[\d/ ]+", text):
                key = "NAME"
        out[key] = (out[key] + " " + text).strip()
    return out


def table_numbers(cell):
    """"0327/0328" -> ["0327", "0328"]. v2.6 LA2 prints 302 / 303 without the leading zero:
    HL7 table numbers are four digits, so a three-digit cell is zero-padded."""
    return sorted({t.strip().zfill(4) for t in cell.split("/") if t.strip()})


def extract(version):
    text = subprocess.run(["pdftotext", "-layout", "-enc", "UTF-8", os.path.join(STANDARDS, PDFS[version]), "-"],
                          capture_output=True, text=True).stdout.split("\n")
    types, cur, cols = {}, None, None
    for line in text:
        cap = CAPTION.search(line)
        if cap:
            cur = types.setdefault(cap.group(1), {"dataType": cap.group(1), "version": version,
                                                  "name": cap.group(2).strip(), "components": []})
            cols = None
            continue
        if cur is None or FURNITURE.search(line):
            continue
        hdr = columns(line)
        if hdr:
            cols = hdr
            continue
        if cols is None or not line.strip():
            continue
        start = dict(cols)
        first = len(line) - len(line.lstrip())
        c = cells(line, cols)
        # A row has an OPT cell and either a SEQ number or (SEQ blank) a DT. A withdrawn
        # component prints SEQ + "W" + name and NO datatype (v2.6 XTN.1, v2.8.2 XCN.7).
        seq_cell = c.get("SEQ", "")
        is_row = bool(c.get("OPT")) and (re.fullmatch(r"\d+", seq_cell) is not None
                                         or (seq_cell == "" and bool(c.get("DT"))))
        if is_row:
            # v2.5.1 MA prints its first row with a blank SEQ cell: take the next index.
            seq = int(c["SEQ"]) if c.get("SEQ") else len(cur["components"]) + 1
            if any(x["index"] == seq for x in cur["components"]):
                continue  # a reprint of the table later in the chapter
            cur["components"].append({"index": seq, "name": c.get("NAME", ""), "dataType": c.get("DT", ""),
                                      "optionality": c.get("OPT", ""), "len": c.get("LEN", "") or c.get("CLEN", ""),
                                      "tbl": c.get("TBL", "")})
        elif first < start.get("DT", 0) - 3 and not re.fullmatch(r"\s*\d+\s*", line):
            cur = None   # text at the left margin that is not a row: the table is over
        elif cur["components"]:
            last = cur["components"][-1]
            if c.get("TBL") and last["tbl"].rstrip().endswith("/"):
                last["tbl"] += c["TBL"]
            # a wrapped name sits wholly inside the NAME column, left of COMMENTS
            end = len(line.rstrip())
            if c.get("NAME") and first >= start.get("TBL", 0) and end <= start.get("COMMENTS", 10**6) + 2 \
                    and not c.get("COMMENTS") and not c.get("SECREF"):
                last["name"] = (last["name"] + " " + c["NAME"]).strip()
    types = {k: v for k, v in types.items() if v["components"]}   # primitives print no rows
    # Resources/datatypes/overrides.json: hand-verified, cited corrections for the rare
    # component whose printed optionality the same section's prose and example contradict
    # ({"<version>": {"<DT>": {"<index>": {"optionality": "O", "note": "..."}}}}).
    path = os.path.join(REPO, "Resources/datatypes/overrides.json")
    overrides = json.load(open(path)).get(version, {}) if os.path.exists(path) else {}
    for code, comps in overrides.items():
        for index, change in comps.items():
            for c in types.get(code, {}).get("components", []):
                if c["index"] == int(index):
                    c["optionality"] = change["optionality"]
    # Resources/datatypes/conditions.json (M26): hand-authored, cited predicates for components
    # printed C. Only a component printed C may carry one, so a rule on a component the table
    # prints otherwise is a build-content error, not a silent no-op.
    # The "as of v2.7" rules (M27) ride the same assertion but land on "conformanceCondition",
    # checked only on opt-in: the spec's own examples violate them.
    path = os.path.join(REPO, "Resources/datatypes/conditions.json")
    conditions = json.load(open(path)) if os.path.exists(path) else {}
    for key, source in (("condition", conditions.get("rules", {})),
                        ("conformanceCondition", conditions.get("conformanceRules", {}).get("rules", {}))):
        for code, comps in source.get(version, {}).items():
            for index, rule in comps.items():
                target = [c for c in types.get(code, {}).get("components", []) if c["index"] == int(index)]
                assert target and target[0]["optionality"] == "C", f"v{version} {code}.{index}: condition on a component not printed C"
                target[0][key] = rule["condition"]
    return types


def main():
    version = sys.argv[1].lstrip("v")
    types = extract(version)
    bound = sum(1 for t in types.values() for c in t["components"] if c["tbl"])
    print(f"v{version}: {len(types)} datatypes, {sum(len(t['components']) for t in types.values())} components, {bound} with a TBL#")
    if "--write" in sys.argv:
        out = os.path.join(REPO, f"Resources/datatypes/v{version}")
        os.makedirs(out, exist_ok=True)
        for code, t in sorted(types.items()):
            doc = {"dataType": code, "version": version, "name": t["name"], "components": [
                {k: v for k, v in (("index", c["index"]), ("name", c["name"]), ("dataType", c["dataType"]),
                                   ("optionality", c["optionality"]), ("length", c["len"]),
                                   ("condition", c.get("condition", "")),
                                   ("conformanceCondition", c.get("conformanceCondition", "")),
                                   ("tables", table_numbers(c["tbl"])))
                 if not (k in ("tables", "length", "condition", "conformanceCondition") and not v)} for c in t["components"]]}
            with open(os.path.join(out, f"{code}.json"), "w", encoding="utf-8") as f:
                json.dump(doc, f, indent=2, ensure_ascii=False)
                f.write("\n")
    return types


if __name__ == "__main__":
    main()
