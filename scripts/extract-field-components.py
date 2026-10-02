#!/usr/bin/env python3
"""P5 — field-local composite grammar of v2.3, v2.3.1 and v2.4, recovered from prose.

    python3 scripts/extract-field-components.py 2.4            # summary
    python3 scripts/extract-field-components.py 2.4 --report   # plus skipped fields and unbound mentions
    python3 scripts/extract-field-components.py 2.4 --write    # emit Resources/datatypes/v2.4/fields/<SEG>-<N>.json

Before v2.5 most composite fields are typed CM: "The specific components of CM fields are
defined within the field descriptions" (v2.3 sec 2.8.6, v2.4 sec 2.9.6). Each such field
heading ("6.4.8.20 Pre-certification req/window (CM) 00521"; v2.4 adds the "IN3-20"
prefix and CH05 runs it on: "5.10.5.3.11QRD-11") is followed by a "Components:" line.
That line is the evidence:

  field       SEG-N from the v2.4 prefix, else the enclosing segment heading and the
              heading's last number; kept when the schema types that position CM (or the
              printed code), or its name agrees (audit-schemas.name_agrees)
  components  the Components line (extract-datatype-prose.parse_components_line)
  tables      only from a chunk that opens "The <ordinal> component" or a bullet that opens
              with the component's name, under M13's three tests (judge); anything else
              stays unbound: an absent check, never a wrong one

A field is emitted only when neither its printed datatype nor its schema datatype has a
grammar of its own for the version, and the schema does not type it as a scalar (the
attribute table wins: v2.3 QRD-11 is printed CM in its heading and ST in the table). A field
printed twice (v2.4 OBR-15 in CH04 and CH07) keeps the copy that extends the other; copies
that disagree otherwise are dropped and reported.
"""
import collections, glob, importlib.util, json, os, re, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _load(name, rel):
    spec = importlib.util.spec_from_file_location(name, os.path.join(REPO, rel))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


dtp = _load("dtp", "scripts/extract-datatype-prose.py")
audit = _load("audit", "scripts/audit-schemas.py")

FIELD = re.compile(r"^\s*(\d+(?:\.\d+){3,4})\s*(?:([A-Z][A-Z0-9]{2})-(\d+)\s+)?(.+?)\s*\(\s*([A-Z][A-Z0-9]{1,2})\s*\)\s+(\d{5})\s*$")
SEGMENT = re.compile(r"^\s*\d+\.\d+\.\d+\s+([A-Z][A-Z0-9]{2})\s*[-–]\s*\S")
HEADING = re.compile(r"^\s*\d+(?:\.\d+){2,}\s*[A-Z]")
ARRAYS = {"MA", "NA"}
ORDINALS = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
            "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth"]
OPENER = re.compile(r"(?=\b[Tt]he\s+(?:%s)\s+component\b)|(?=•)" % "|".join(ORDINALS))
ORDINAL = re.compile(r"[Tt]he\s+(%s)\s+component\b" % "|".join(ORDINALS))


def schema_fields(version):
    out = {}
    for path in glob.glob(os.path.join(REPO, f"Resources/schemas/v{version}/*.json")):
        doc = json.load(open(path))
        for f in doc.get("fields", []):
            out[(doc["segmentID"], f["index"])] = f
    return out


def attribute(definition, names):
    """{component index: [(table number, stated name)]} from the definition's paragraphs. A
    paragraph ends at a blank line, so a table figure printed after the bullets (v2.4 IN3-20's
    Table 0150) is never attributed to the last bullet."""
    found = collections.defaultdict(list)
    for paragraph in re.split(r"\n\s*\n", definition):
        text = " ".join(dtp.unhyphenate(paragraph).split())
        for chunk in OPENER.split(text):
            chunk = chunk.strip()
            m = ORDINAL.match(chunk)
            if m:
                index = ORDINALS.index(m.group(1)) + 1
            elif chunk.startswith("•"):
                head = chunk[1:].strip().lower()
                hits = [i for i, n in enumerate(names, 1) if head.startswith(n.lower())]
                index = max(hits, key=lambda i: len(names[i - 1])) if hits else None
            else:
                continue
            if index and index <= len(names):
                found[index] += dtp.TABLE.findall(chunk)
    return found


def extract(version):
    """({SEG-N: grammar}, [(SEG-N, heading name, why skipped)])."""
    fields = schema_fields(version)
    have = {os.path.basename(p)[:-5] for p in glob.glob(os.path.join(REPO, f"Resources/datatypes/v{version}/*.json"))}
    found, skipped, missing, conflicts = {}, [], {}, {}
    for pattern in audit.CHAPTER_GLOBS[f"v{version}"]:
        for pdf in sorted(glob.glob(os.path.join(audit.STANDARDS, pattern))):
            lines = [l for l in dtp.pdf_text(pdf) if not dtp.FURNITURE.search(l)]
            segment, i = None, 0
            while i < len(lines):
                s = SEGMENT.match(lines[i])
                if s:
                    segment = s.group(1)
                m = FIELD.match(lines[i])
                i += 1
                if not m:
                    continue
                body = []
                while i < len(lines) and not HEADING.match(lines[i]):
                    body.append(lines[i])
                    i += 1
                number, seg, seq, name, printed, _item = m.groups()
                if printed in have or printed in audit.SCALAR_DATATYPES:
                    continue
                seg, seq = seg or segment, int(seq or number.rsplit(".", 1)[1])
                key = f"{seg}-{seq}"
                schema = fields.get((seg, seq))
                if schema is not None and (schema["dataType"] in have or schema["dataType"] in ARRAYS):
                    continue                           # the schema's type has a grammar, or is an array
                if schema is not None and schema["dataType"] in audit.SCALAR_DATATYPES:
                    skipped.append((key, name, f"the attribute table types it {schema['dataType']}; the table wins"))
                    continue
                text = dtp.printed_line(body)
                if text is None:
                    if body:
                        missing[key] = name            # no Components line before the definition
                    continue                           # an empty body is a table-of-contents entry
                if schema is None or not (schema["dataType"] in ("CM", printed)
                                          or audit.name_agrees(schema["name"], [name])):
                    skipped.append((key, name, "no schema field of that type or name at that position"))
                    continue
                comps = dtp.parse_components_line(text)
                if not comps:
                    skipped.append((key, name, "the Components line prints no fixed list"))
                    continue
                prior = found.get(key)
                if prior is not None:
                    had = [(c["name"].lower(), c["dataType"]) for c in prior["components"]]
                    now = [(n.lower(), d) for n, d in comps]
                    if had[:len(now)] == now:
                        continue                       # the same field printed again, or a shorter copy
                    if now[:len(had)] != had:
                        conflicts[key] = name          # two chapters print different structures
                        continue
                mentions = attribute("\n".join(body), [n for n, _ in comps])
                components = []
                for index, (cname, dt) in enumerate(comps, 1):
                    tables, rejected = dtp.judge(version, mentions.get(index, []))
                    components.append({"index": index, "name": cname, "dataType": dt,
                                       "tables": tables, "rejected": rejected})
                found[key] = {"field": key, "dataType": printed, "version": version, "name": name,
                              "components": components}
    for key, name in conflicts.items():
        found.pop(key, None)
        skipped.append((key, name, "two chapters print different, non-extending Components lines"))
    skipped += [(key, name, "no Components line before the definition")
                for key, name in missing.items() if key not in found]
    return found, skipped


def document(t):
    return {"field": t["field"], "dataType": t["dataType"], "version": t["version"], "name": t["name"],
            "source": "prose-field",
            "components": [{k: v for k, v in (("index", c["index"]), ("name", c["name"]), ("dataType", c["dataType"]),
                                              ("optionality", ""), ("tables", c["tables"]))
                            if not (k == "tables" and not v)} for c in t["components"]]}


def main():
    version = sys.argv[1].lstrip("v")
    found, skipped = extract(version)
    comps = [c for t in found.values() for c in t["components"]]
    print(f"v{version}: {len(found)} field-local composites, {len(comps)} components, "
          f"{sum(1 for c in comps if c['tables'])} bound, {len(skipped)} skipped")
    if "--report" in sys.argv:
        for key, name, why in skipped:
            print(f"   SKIPPED {key} {name!r}: {why}")
        for key, t in sorted(found.items()):
            for c in t["components"]:
                for why in c["rejected"]:
                    print(f"   UNBOUND {key}.{c['index']} ({c['dataType'] or '-'}) {why}")
    if "--write" in sys.argv:
        out = os.path.join(REPO, f"Resources/datatypes/v{version}/fields")
        os.makedirs(out, exist_ok=True)
        for key, t in sorted(found.items()):
            with open(os.path.join(out, f"{key}.json"), "w", encoding="utf-8") as f:
                json.dump(document(t), f, indent=2, ensure_ascii=False)
                f.write("\n")
    return found


if __name__ == "__main__":
    main()
