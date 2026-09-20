#!/usr/bin/env python3
"""A5 — set each schema field's enforced `table` link from its verified `tables` binding.

    python3 scripts/backfill-schema-tables.py 2.5.1

`tables` (M9-A) is the hand-verified record of the spec's TBL# cell and is the only
input: nothing is re-extracted from a PDF here. A field gets `"table": "NNNN"` when

  * its dataType is ID or IS         (the only types `integrity()` allows a link on),
  * `tables` binds exactly one table (several tables means a composite-style cell;
                                      reported as MULTI and left unlinked), and
  * Resources/tables/v<version>/NNNN.json exists (otherwise UNRESOLVED).

An existing, different `table` is never overwritten (CONFLICT). The key is inserted as
text right after the field's "dataType" token: the schemas are hand-formatted in two
styles and do not survive a json round-trip byte for byte.
"""
import glob, json, os, re, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def plan(version):
    """path -> {index: table}, plus the conflict / unresolved / multi reports."""
    todo, conflicts, unresolved, multi = {}, [], [], []
    for path in sorted(glob.glob(f"{REPO}/Resources/schemas/v{version}/*.json")):
        seg = os.path.basename(path)[:-5]
        for f in json.load(open(path))["fields"]:
            if f.get("dataType") not in ("ID", "IS") or not f.get("tables"):
                continue
            where = f"v{version} {seg}-{f['index']}"
            if len(f["tables"]) > 1:
                multi.append(f"{where} {f['tables']}")
                continue
            number = f["tables"][0]
            if not os.path.exists(f"{REPO}/Resources/tables/v{version}/{number}.json"):
                unresolved.append(f"{where} {number}")
            elif f.get("table") not in (None, number):
                conflicts.append(f"{where} has {f['table']}, spec binds {number}")
            elif f.get("table") is None:
                todo.setdefault(path, {})[f["index"]] = number
    return todo, conflicts, unresolved, multi


def insert(path, wanted):
    text, out, pos, index = open(path, encoding="utf-8").read(), [], 0, None
    for m in re.finditer(r'"index"\s*:\s*(\d+)|"dataType"\s*:\s*"[^"]*"', text):
        if m.group(1):
            index = int(m.group(1))
        elif index in wanted:
            out.append(text[pos:m.end()] + f', "table": "{wanted.pop(index)}"')
            pos = m.end()
    open(path, "w", encoding="utf-8").write("".join(out) + text[pos:])
    assert not wanted, f"{path}: no dataType token found for fields {sorted(wanted)}"


def main():
    version = sys.argv[1].lstrip("v")
    todo, conflicts, unresolved, multi = plan(version)
    added = sum(len(wanted) for wanted in todo.values())
    for path, wanted in todo.items():
        expected = dict(wanted)
        insert(path, wanted)
        got = {f["index"]: f.get("table") for f in json.load(open(path))["fields"]}
        assert all(got[i] == t for i, t in expected.items()), f"{path}: write did not verify"
    for label, rows in (("CONFLICT", conflicts), ("UNRESOLVED", unresolved), ("MULTI", multi)):
        for row in rows:
            print(f"{label} {row}")
    print(f"v{version}: added {added} / conflicts {len(conflicts)} / "
          f"unresolved {len(unresolved)} / multi {len(multi)}")
    return 1 if conflicts else 0


if __name__ == "__main__":
    sys.exit(main())
