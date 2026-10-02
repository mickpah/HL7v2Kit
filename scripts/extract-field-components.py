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
  tables      bound to a coded component (IS, ID, or CE / CNE / CWE) only, under M13's three
              tests (judge), from one of two kinds of evidence:
              - ordinal: a chunk that opens "The <ordinal> component", as a word ("first") or a
                number ("7th": v2.4 OBR-15.7, SAC-6.7, TCC-3.7, Table 0369), or a bullet that
                opens with the component's name;
              - single coded component: any other sentence naming exactly one table, when the
                field has exactly one coded component. The table can only be that component's:
                v2.4 PV1-37 "Refer to User-defined Table 0113 - Discharged to location", whose
                other component is a TS.
              A sentence naming two or more tables never binds (v2.4 IN2-28 "Table 0145 - Room
              type and User-defined Table 0146"), nor does a mention on a field with several
              coded components and no ordinal. Every unbound mention is listed by --report with
              its reason: an absent check, never a wrong one

A field is emitted only when neither its printed datatype nor its schema datatype has a
grammar of its own for the version, and the schema does not type it as a scalar (the
attribute table wins, bar enumerated, cited exceptions in audit-schemas.DATATYPE_WHITELIST:
v2.3 QRD-11 is printed CM with a Components line in its heading and ST in the table, and the
schema types it CM, so the Components line is emitted). A field
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
_ORD = r"(?:%s|\d{1,2}(?:st|nd|rd|th))" % "|".join(ORDINALS)
OPENER = re.compile(r"(?=\b[Tt]he\s+%s\s+component\b)|(?=•)" % _ORD)
ORDINAL = re.compile(r"[Tt]he\s+(%s)\s+component\b" % _ORD)
# A table mention in a field body. Wider than extract-datatype-prose.TABLE: field prose also
# prints "Userdefined Table 0113" (v2.4 PV1-37) and a bare "(Table 0338)" (v2.4 PRA-6).
_TABLE_KEY = r"(?:HL7\s+(?:[Tt]able\s+)?|[Uu]ser-?\s*defined\s+[Tt]able\s+|\b[Tt]able\s+)(\d{4})"
MENTION = re.compile(_TABLE_KEY + r"(?:\s*[-–]\s*([A-Za-z][A-Za-z /'’-]*))?")
NUMBER = re.compile(_TABLE_KEY)


def mentions_in(text):
    """[(table number, stated name)]. The stated name is greedy ("Room type and User-defined
    Table 0146 ..." reads as one name), so every number NUMBER finds is kept, unnamed when
    MENTION swallowed it: a sentence naming two tables must count two."""
    pairs = MENTION.findall(text)
    seen = {n for n, _ in pairs}
    return pairs + [(n, "") for n in NUMBER.findall(text) if n not in seen]
SENTENCE = re.compile(r"(?<=\.)\s+(?=[A-Z])")
CODED = {"IS", "ID", "CE", "CNE", "CWE"}


def ordinal_index(word):
    return ORDINALS.index(word) + 1 if word in ORDINALS else int(re.match(r"\d+", word).group())


def attribute(definition, names):
    """({component index: [(table number, stated name)]}, [[mentions] per free sentence]).

    A chunk that opens "The <ordinal> component" (a word or "7th") or a bullet that opens with a
    component's name attributes its mentions to that component. The rest of the text is split
    into sentences, kept for the single-coded-component rule in `extract`. A paragraph ends at a
    blank line, so a table figure printed after the bullets (v2.4 IN3-20's Table 0150) is never
    attributed to the last bullet."""
    found, free = collections.defaultdict(list), []
    for paragraph in re.split(r"\n\s*\n", definition):
        text = " ".join(dtp.unhyphenate(paragraph).split())
        for chunk in OPENER.split(text):
            chunk = chunk.strip()
            m = ORDINAL.match(chunk)
            if m:
                index = ordinal_index(m.group(1))
            elif chunk.startswith("•"):
                head = chunk[1:].strip().lower()
                hits = [i for i, n in enumerate(names, 1) if head.startswith(n.lower())]
                index = max(hits, key=lambda i: len(names[i - 1])) if hits else None
            else:
                free += [mentions_in(s) for s in SENTENCE.split(chunk) if NUMBER.search(s)]
                continue
            if index and index <= len(names):
                found[index] += mentions_in(chunk)
    return found, free


SUBCOMPONENTS_FOR = re.compile(r"Subcomponents\s+for\s+([^:]+):", re.I)


def promote_misprinted_ampersands(text, body):
    """The Components line with an "&" read as "^" where every piece after it is a component
    the field's own "Subcomponents for <name>:" lines describe: a piece with subcomponents of
    its own is a component, never a subcomponent. v2.3.1 and v2.4 PRA-7 print "<privilege
    (CE)> & <privilege class (CE)> ^ <expiration date (DT)> ^ ...", then "Subcomponents for
    privilege:" and "Subcomponents for privilege class:", and the v2.4 CH15 example carries
    "ADMIT&&ADT^MED&&L2^19941231" (privilege class at component 2, the date at 3). Any other
    "&" is left to parse_components_line (v2.3.1 CD's channel number & channel name)."""
    described = {" ".join(n.split()).lower()
                 for n in SUBCOMPONENTS_FOR.findall(" ".join(dtp.unhyphenate("\n".join(body)).split()))}
    pieces = []
    for piece in " ".join(dtp.unhyphenate(text).split()).split("^"):
        parts = piece.split("&")
        later = [dtp.PIECE.match(p.strip().lstrip("<").rstrip(">").strip()) for p in parts[1:]]
        if later and all(m and m.group(1).strip().lower() in described for m in later):
            pieces += parts
        else:
            pieces.append(piece)
    return "^".join(pieces)


def schema_fields(version):
    out = {}
    for path in glob.glob(os.path.join(REPO, f"Resources/schemas/v{version}/*.json")):
        doc = json.load(open(path))
        for f in doc.get("fields", []):
            out[(doc["segmentID"], f["index"])] = f
    return out


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
                comps = dtp.parse_components_line(promote_misprinted_ampersands(text, body))
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
                text = "\n".join(body)
                mentions, free = attribute(text, [n for n, _ in comps])
                coded = [i for i, (_, dt) in enumerate(comps, 1) if dt in CODED]
                notes = []                             # (component, table, why) for unattributable mentions
                for sentence in free:
                    numbers = sorted({n for n, _ in sentence})
                    if len(numbers) > 1:               # fail-safe: never split a sentence between tables
                        notes += [(None, n, f"one sentence names several tables {numbers}") for n in numbers]
                    elif len(coded) == 1:              # the single-coded-component rule
                        mentions[coded[0]] += sentence
                    else:
                        notes.append((None, numbers[0], "no ordinal or bullet names its component, and the "
                                                        f"field has {len(coded)} coded components"))
                components = []
                for index, (cname, dt) in enumerate(comps, 1):
                    # A table binds coded values only. A figure caption can trail the last
                    # ordinal chunk ("Table 0100 - When to charge" after v2.3.1 BLG-1.2, a TS).
                    if dt in CODED:
                        tables, rejected = dtp.judge(version, mentions.get(index, []))
                    else:
                        tables = []
                        rejected = [f"the component is {dt or 'untyped'}, not a coded type"] if mentions.get(index) else []
                    components.append({"index": index, "name": cname, "dataType": dt,
                                       "tables": tables, "rejected": rejected})
                    notes += [(index, n, why) for why in rejected for n in sorted({n for n, _ in mentions[index]})]
                bound = {n for c in components for n in c["tables"]}
                named = set(NUMBER.findall(" ".join(dtp.unhyphenate(text).split())))
                unbound = []
                for number in sorted(named - bound):
                    why = [(i, w) for i, n, w in notes if n == number]
                    unbound += [(i, number, w) for i, w in dict.fromkeys(why)] or \
                               [(None, number, "named outside any sentence a rule reads (a figure or cross-reference)")]
                found[key] = {"field": key, "dataType": printed, "version": version, "name": name,
                              "components": components, "unbound": unbound}
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
    unbound = sorted({(key, number) for key, t in found.items() for _, number, _ in t["unbound"]})
    print(f"v{version}: {len(found)} field-local composites, {len(comps)} components, "
          f"{sum(1 for c in comps if c['tables'])} bound, {len(skipped)} skipped, "
          f"{len(unbound)} unbound table mention(s)")
    if "--report" in sys.argv:
        for key, name, why in skipped:
            print(f"   SKIPPED {key} {name!r}: {why}")
        for key, t in sorted(found.items()):
            for index, number, why in t["unbound"]:
                where = f"{key}.{index} ({t['components'][index - 1]['dataType'] or '-'})" if index else key
                print(f"   UNBOUND {where} table {number}: {why}")
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
