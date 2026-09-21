#!/usr/bin/env python3
"""M12-A — extract the AU ADRM-2021 HL7v2 VMR OBX implementation table (Appendix 9,
table A9.T.1, pp. 492-515) into Resources/profiles/au-adrm-2021/vmr-table.json.

    python3 scripts/extract-vmr-table.py            # summary
    python3 scripts/extract-vmr-table.py --write

What is extracted, and why only this: the element name, OBX-2, the OBX-4 sub-ID path,
OCCURRENCES and the VMR DATATYPE. The path, occurrences and datatype columns are what the
sub-ID tree rules need. OBX-3 and the suggested OBX-5 values are NOT extracted: footnote
markers are set inside the OBX-3 cell ("73983-9 117 ^^LN"), and the appendix's own worked
example (p. 516) contradicts the table on both OBX-2 (CE for CWE) and OBX-3 (70949-3 for
73983-9), so neither can back a rule (req #4).

A row starts on the line that carries its OCCURRENCES and VMR DATATYPE cells; every other
cell is top-aligned with it and may wrap onto the lines below. `RepeatOf[...]` in a path
marks a repeat index and becomes "*".
"""
import json, os, re, subprocess, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PDF = os.path.join(REPO, "docs/standards/HL7_v24_PDF",
                   "HL7AUSD-STD-OO-ADRM-2021.1 - Australian Diagnostics and Referral Messaging - Localisation of HL7 Version 2.4.pdf")
OUT = os.path.join(REPO, "Resources/profiles/au-adrm-2021/vmr-table.json")
ROW = re.compile(r"(?<![\d.])(\d+\.\.(?:\d+|\*)|1)\s+([A-Z]{3,})\s*$")
FURNITURE = re.compile(r"HL7AUSD-STD|Australian Diagnostics and Referral|^\s*\d{2,3} https?://|^\s*HL7 Version 2\.4|^\s*snomed&|^\s+https?://")
KINDS = {"ENTRY", "SECTION", "STRUCTURAL", "COLLECTION", "CODEDVALUE", "STRING", "DATETIME", "DATERANGE",
         "REAL", "BOOLEAN", "PHYSICALQUANTITY", "INTEGER"}


def extract():
    text = subprocess.run(["pdftotext", "-layout", "-enc", "UTF-8", PDF, "-"], capture_output=True, text=True).stdout.split("\n")
    start = next(i for i, l in enumerate(text) if l.strip().startswith("A9.T.1 HL7v2 VMR OBX implementation table") and "see page" not in l)
    end = next(i for i, l in enumerate(text) if l.strip().startswith("A9.2.2.2 OBX-2 DataType") and "see page" not in l)
    # The colour legend printed under the table is not part of it.
    end = next((i for i in range(start, end) if text[i].strip().startswith("Legend")), end)
    rows, cur, cols = [], None, None
    for line in text[start:end]:
        if FURNITURE.search(line) or not line.strip():
            continue
        if "OBX-4 Observation sub-ID" in line:
            cols = {"obx2": line.index("OBX-2"), "obx3": line.index("OBX-3"),
                    "sub": line.index("OBX-4 Observation sub-ID"), "value": line.index("Suggested")}
            cur = None
            continue
        if cols is None:
            continue
        cell = lambda a, b: line[max(0, cols[a] - 2):cols[b] - 1].strip() if len(line) > cols[a] - 2 else ""
        m = ROW.search(line)
        if m:
            cur = {"name": line[:cols["obx2"] - 1].strip(), "obx2": cell("obx2", "obx3"), "sub": cell("sub", "value"),
                   "occurrences": m.group(1), "kind": m.group(2)}
            rows.append(cur)
        elif cur is not None:
            name = line[:cols["obx2"] - 1].strip()
            if name and not re.match(r"^\d{2,3}$", name):
                cur["name"] += " " + name
            cur["sub"] += cell("sub", "value")
    out = []
    for r in rows:
        path = re.sub(r"RepeatOf\[[^\]]*\]", "*", re.sub(r"\s+", "", r["sub"])).rstrip(".")
        name = re.sub(r"\s*†", "", r["name"]).strip()
        low, high = (r["occurrences"], r["occurrences"]) if ".." not in r["occurrences"] else r["occurrences"].split("..")
        out.append({"path": path, "name": name, "obx2": "" if r["obx2"] == "-" else r["obx2"],
                    "min": int(low), "max": None if high == "*" else int(high), "kind": r["kind"]})
    return out


def main():
    rows = extract()
    kinds = {}
    for r in rows:
        kinds[r["kind"]] = kinds.get(r["kind"], 0) + 1
    print(f"{len(rows)} rows; kinds {kinds}")
    if "--write" in sys.argv:
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        doc = {"profile": "au-adrm-2021",
               "citation": "HL7au ADRM-2021.1 Appendix 9 (Normative), table A9.T.1 HL7v2 VMR OBX implementation table, pp. 492-515",
               "root": "1", "elements": rows}
        with open(OUT, "w", encoding="utf-8") as f:
            json.dump(doc, f, indent=2, ensure_ascii=False)
            f.write("\n")
    return rows


if __name__ == "__main__":
    main()
