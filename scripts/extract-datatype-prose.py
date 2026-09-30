#!/usr/bin/env python3
"""M13-A — recover the datatype component grammar of v2.3, v2.3.1 and v2.4 from prose.

    python3 scripts/extract-datatype-prose.py 2.4            # summary
    python3 scripts/extract-datatype-prose.py 2.4 --write    # emit Resources/datatypes/v2.4/*.json

These versions print no "HL7 Component Table" figures (ADR-017). They do define every
composite in a numbered section ("2.9.12 CX - extended composite ID with check digit")
whose components each get a numbered subsection ("2.9.12.5 Identifier type code (ID)").
That numbering is the evidence, not the free-text "Components:" line:

  index      the last number of the subsection heading
  name       the heading text
  datatype   the code in parentheses at the end of the heading ("" when none is printed)
  tables     ONLY when the subsection names exactly ONE table, as "HL7 Table NNNN",
             "HL7 NNNN" (v2.4 XPN.11 drops the word) or "User-defined Table NNNN".
             A subsection naming none, or more than one (v2.4 ED.4 names 0290 and 0299,
             CX.4 names 0300 and 0363), is left UNBOUND: an absent check, never a wrong one.

The standard of evidence was measured before this was adopted: on v2.4, 67 of 73 ID/IS
bindings recovered this way equal the v2.5.1 printed component table for the same
component, and the other six are all none-or-several cases that stay unbound.
"""
import json, os, re, subprocess, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STANDARDS = os.path.join(REPO, "docs/standards")
SOURCES = {   # version -> (pdf, datatype section number)
    "2.3":   ("HL7_v23_PDF/CH2.pdf", "2.8"),
    "2.3.1": ("HL7_v231_PDF/Hl7V231.pdf", "2.8"),
    "2.4":   ("HL7_v24_PDF/CH02.PDF", "2.9"),
}
FURNITURE = re.compile(r"Health Level Seven|All rights reserved|Final Standard|^\s*Page \d|^\s*Chapter \d+:|^\f|\.{6,}"
                       r"|^\s*\d{1,2}/\d{4}\s*$|^\s*(January|February|March|April|May|June|July|August|September|October|November|December) \d{4}")
TABLE = re.compile(r"(?:HL7\s+(?:[Tt]able\s+)?|[Uu]ser-\s*defined\s+[Tt]able\s+)(\d{4})(?:\s*[-–]\s*([A-Za-z][A-Za-z /'’-]*))?")
STOP = {"for", "valid", "values", "suggested", "is", "used", "as", "the", "of", "a", "an", "and", "or", "to", "in", "code", "codes", "id", "type"}


def dehyphenate(text):
    """Rejoin 'table' hyphenated across a line break. v2.3.1 sec 2.8.31.2 prints 'Refer to HL7
    ta-' / 'ble 0207', and sec 2.8.28.6 'User-defined ta-' / 'ble 0305'; the joined component text
    reads 'ta- ble', which TABLE cannot match. Only this word is rejoined: 'user- defined' is
    already handled by TABLE's own '-\\s*'."""
    return re.sub(r"\b([Tt]a)-\s+(ble)\b", r"\1\2", text)


def words(text):
    return {w for w in re.findall(r"[a-z]+", (text or "").lower()) if w not in STOP}


def registry_name(version, number):
    path = os.path.join(REPO, f"Resources/tables/v{version}/{number}.json")
    return json.load(open(path))["name"] if os.path.exists(path) else None


def judge(version, mentions):
    """(tables, reasons) for one component's table mentions [(number, stated name)].

    Three tests, all of which must pass before a prose mention becomes a binding:
      one       exactly one distinct table number is named in the subsection;
      resolves  that number is a table of this version's own registry;
      same name when the prose states the table's name, it shares a word with the registry's
                name. v2.3 sec 2.8.31.4 says "HL7 table 0102 - Relation conjunction", but
                v2.3's 0102 is Delayed Acknowledgment Type (closed: D, F): a misprint for
                0210 that would have rejected AND / OR."""
    numbers = sorted({n for n, _ in mentions})
    if len(numbers) != 1:
        return [], ([f"names several tables {numbers}"] if numbers else [])
    number = numbers[0]
    actual = registry_name(version, number)
    if actual is None:
        return [], [f"table {number} is not in the v{version} registry"]
    stated = [name for n, name in mentions if name]
    if stated and not any(words(name) & words(actual) for name in stated):
        return [], [f"names table {number} as {stated[0].strip()!r}, but v{version} {number} is {actual!r}"]
    return [number], []


def extract(version):
    pdf, section = SOURCES[version]
    text = subprocess.run(["pdftotext", "-layout", "-enc", "UTF-8", os.path.join(STANDARDS, pdf), "-"],
                          capture_output=True, text=True).stdout.split("\n")
    sec = re.escape(section)
    datatype = re.compile(rf"^\s*{sec}\.(\d+)\s+([A-Z][A-Z0-9]{{1,2}})\s*[-–]\s*(\S.*)$")
    component = re.compile(rf"^\s*{sec}\.(\d+)\.(\d+)\s+(.*?)(?:\s*\(\s*([A-Z][A-Z0-9]{{1,2}})\s*\))?\s*$")
    deeper = re.compile(rf"^\s*{sec}\.\d+\.\d+\.\d+")
    chapter = re.compile(r"^\s*2\.\d+\s+[A-Z]")
    types, cur, comp, inside = {}, None, None, False
    for line in text:
        if FURNITURE.search(line):
            continue
        m = datatype.match(line)
        if m:
            inside = True
            cur = types.setdefault(m.group(2), {"n": m.group(1), "name": m.group(3).strip(), "components": []})
            comp = None
            continue
        if not inside:
            continue
        if chapter.match(line) and not line.strip().startswith(section + "."):
            inside, cur, comp = False, None, None      # the next chapter-level section: datatypes are over
            continue
        if deeper.match(line):
            continue                                   # a sub-subsection belongs to the current component
        m = component.match(line)
        if m and cur is not None and m.group(1) == cur["n"]:
            # v2.3 sec 2.8.1.2 prints AD.1's description run into the AD.2 heading ("The street
            # or mailing address of a person or institution. Other designation (ST)"): the
            # component's name is what follows the last sentence break.
            name = m.group(3).strip().rsplit(". ", 1)[-1].strip()
            comp = {"index": int(m.group(2)), "name": name, "dataType": m.group(4) or "", "text": ""}
            if not any(c["index"] == comp["index"] for c in cur["components"]):
                cur["components"].append(comp)
            continue
        if comp is not None:
            comp["text"] += " " + line.strip()
    out = {}
    for code, t in types.items():
        comps = sorted(t["components"], key=lambda c: c["index"])
        # A trailing subsection with no datatype code is a note, not a component ("Usage
        # notes:", "References for internationalization", "Type-subtype combinations").
        while comps and not comps[-1]["dataType"]:
            comps.pop()
        if not comps:
            continue                                   # a primitive: no component subsections
        for c in comps:
            c["tables"], c["rejected"] = judge(version, TABLE.findall(dehyphenate(c.pop("text"))))
        out[code] = {"dataType": code, "version": version, "name": t["name"], "components": comps}
    return out


def document(t):
    return {"dataType": t["dataType"], "version": t["version"], "name": t["name"], "source": "prose",
            "components": [{k: v for k, v in (("index", c["index"]), ("name", c["name"]), ("dataType", c["dataType"]),
                                              ("optionality", ""), ("tables", c["tables"]))
                            if not (k == "tables" and not v)} for c in t["components"]]}


def main():
    version = sys.argv[1].lstrip("v")
    types = extract(version)
    comps = [c for t in types.values() for c in t["components"]]
    print(f"v{version}: {len(types)} composite datatypes, {len(comps)} components, "
          f"{sum(1 for c in comps if c['tables'])} bound, {sum(1 for c in comps if c['rejected'])} mentions rejected")
    if "--report" in sys.argv:
        for code, t in sorted(types.items()):
            for c in t["components"]:
                for why in c["rejected"]:
                    print(f"   UNBOUND {code}.{c['index']} ({c['dataType'] or '-'}) {why}")
    if "--write" in sys.argv:
        out = os.path.join(REPO, f"Resources/datatypes/v{version}")
        os.makedirs(out, exist_ok=True)
        for code, t in sorted(types.items()):
            with open(os.path.join(out, f"{code}.json"), "w", encoding="utf-8") as f:
                json.dump(document(t), f, indent=2, ensure_ascii=False)
                f.write("\n")
    return types


if __name__ == "__main__":
    main()
