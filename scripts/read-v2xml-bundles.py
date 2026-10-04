#!/usr/bin/env python3
"""P8b-2b (ADR-019 decision 3) -- read the HL7 v2.xml schema bundles under docs/XML-schemas
(gitignored; never committed, ruling D4) for the names of the message-structure groups the
printed standard leaves unnamed, and cross-check the bundle's element tree against the print.

Imported by scripts/extract-message-structures.py. A bundle holds one <STRUCTURE>.xsd per
structure: complexType STRUCT.CONTENT is the root, each group is complexType
STRUCT.GROUP.CONTENT (an xsd:sequence, or an xsd:choice) with an element STRUCT.GROUP, and
members are <xsd:element ref=... minOccurs=... maxOccurs=...>. The bundles are names-only
(ruling D3): the print stays normative for segments, groups, cardinality and choices.

Resolution of an unnamed printed group (never by position):
  same-version bundle: the one bundle group with the same parent path (the names of its
      enclosing groups), the same first segment and the same member segment set (every segment
      the group holds, at any depth). nameSource v2xml.
  v2.3 and v2.3.1 (no bundle; ruling D2), through the v2.4 bundle: in <STRUCT>.xsd, the group
      with the same first segment and member set (the parent path breaks a tie); where v2.4 has
      no <STRUCT>.xsd, every v2.4 <CODE>_*.xsd of the same message code (the ID differs only by
      trigger, OMD_O01 against OMD_O03), cited with both IDs. nameSource v2xml-v2.4.
  otherwise: an overrides.json groupNames entry (nameSource override), else <FIRSTSEG>_GROUP,
      numbered 2, 3, ... on a clash within the structure (nameSource synthesised). Every
      synthesised name is a report row (no-bundle-name).
"""
import difflib
import os
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(os.path.dirname(HERE), "docs", "XML-schemas")

# The bundle folder per version (the version-map agreement self-check, check-audit-schemas.py).
BUNDLES = {"v2.4": "HL7-xml v2.4", "v2.5.1": "HL7-xml v2.5.1", "v2.6": "HL7-xml v2.6",
           "v2.7.1": "HL7-xml v2.7.1", "v2.8.2": "HL7-xml v2.8.2"}
# No bundle exists for these; their names are derived through the v2.4 bundle (ruling D2).
BUNDLES_DERIVED = {"v2.3": "v2.4", "v2.3.1": "v2.4"}
NAME_SOURCES = ("printed", "override", "v2xml", "v2xml-v2.4", "synthesised")
_SHARED = {"datatypes", "fields", "messages", "segments"}   # not structures
_XS = "{http://www.w3.org/2001/XMLSchema}"


class BundleDefect(Exception):
    """A structure schema that does not describe a finite tree."""


def read_bundle(text, sid):
    """The element tree of one structure schema: segments {segment, min, max} and groups
    {group, type, choice, min, max, elements}."""
    types = {}
    for node in ET.fromstring(text):
        if node.tag == f"{_XS}complexType":
            types[node.get("name")] = node

    def bound(value):
        return None if value == "unbounded" else int(value)

    def content(type_name, stack=()):
        if type_name in stack:     # e.g. v2.5.1 ORL_O34: a group nested inside itself
            raise BundleDefect(f"{type_name[:-8]} contains itself")
        out = []
        for model in types[type_name]:
            for ref in model.iter(f"{_XS}element"):
                name, lo, hi = ref.get("ref"), int(ref.get("minOccurs", "1")), bound(ref.get("maxOccurs", "1"))
                if f"{name}.CONTENT" in types:
                    kind = next(iter(types[f"{name}.CONTENT"]), None)
                    out.append({"group": name.split(".", 1)[1], "type": f"{name}.CONTENT",
                                "choice": kind is not None and kind.tag == f"{_XS}choice",
                                "min": lo, "max": hi, "elements": content(f"{name}.CONTENT", stack + (type_name,))})
                else:
                    out.append({"segment": name, "min": lo, "max": hi})
        return out
    return content(f"{sid}.CONTENT")


class Bundles:
    """Bundle schemas by version ("2.5.1"): from in-memory texts {version: {file: text}} (the
    self-check), or from docs/XML-schemas (from_disk)."""

    def __init__(self, files=None, root=None):
        self._files, self._root, self._trees, self.defects = files or {}, root, {}, {}

    @classmethod
    def from_disk(cls, root=ROOT):
        return cls(root=root)

    def available(self, version):
        if version in self._files:
            return True
        folder = BUNDLES.get(f"v{version}")
        return bool(self._root and folder and os.path.isdir(os.path.join(self._root, folder)))

    def structures(self, version):
        if version in self._files:
            return sorted(f[:-4] for f in self._files[version] if f.endswith(".xsd"))
        if not self.available(version):
            return []
        return sorted(f[:-4] for f in os.listdir(os.path.join(self._root, BUNDLES[f"v{version}"]))
                      if f.endswith(".xsd") and f[:-4] not in _SHARED)

    def tree(self, version, sid):
        key = (version, sid)
        if key not in self._trees:
            text = None
            if version in self._files:
                text = self._files[version].get(f"{sid}.xsd")
            elif self.available(version):
                path = os.path.join(self._root, BUNDLES[f"v{version}"], f"{sid}.xsd")
                if os.path.exists(path):
                    with open(path, encoding="utf-8") as f:
                        text = f.read()
            try:
                self._trees[key] = read_bundle(text, sid) if text else None
            except BundleDefect as exc:
                self._trees[key], self.defects[key] = None, str(exc)
        return self._trees[key]


def _members(e):
    """A group's elements, or a printed choice's alternatives (P8b-6)."""
    return e["elements"] if "elements" in e else e["alternatives"]


def leaves(elements):
    for e in elements:
        if "segment" in e:
            yield e["segment"]
        else:
            yield from leaves(_members(e))


def signature(elements):
    segs = list(leaves(elements))
    return (segs[0] if segs else None, frozenset(segs))


def groups(elements, path=()):
    """(parent path, group) for every group, depth first. A printed choice is not a group but
    its alternatives are searched, under its name or CHOICE (the bundle's name for an unnamed one)."""
    for e in elements:
        if "group" in e:
            yield path, e
            yield from groups(e["elements"], path + (e["group"],))
        elif "alternatives" in e:
            yield from groups(e["alternatives"], path + (e["choice"] or "CHOICE",))


def _cite(version, sid, group):
    return f"HL7-xml v{version}/{sid}.xsd, {group['type']}"


def resolve(bundles, version, sid, path, elements):
    """(name, nameSource, citation) for an unnamed printed group from the bundles, or
    (None, None, why) on a miss."""
    sig = signature(elements)
    want = f"first segment {sig[0]} and members {{{', '.join(sorted(sig[1]))}}}"
    where = f"under [{', '.join(path)}]" if path else "at the root"
    if bundles.available(version):
        tree = bundles.tree(version, sid)
        if tree is None and (version, sid) in bundles.defects:
            return None, None, f"HL7-xml v{version}/{sid}.xsd is unreadable: {bundles.defects[(version, sid)]}"
        if tree is None:
            return None, None, f"HL7-xml v{version} has no {sid}.xsd"
        hits = [g for p, g in groups(tree) if p == tuple(path) and signature(g["elements"]) == sig]
        if len(hits) == 1:
            return hits[0]["group"], "v2xml", _cite(version, sid, hits[0])
        return None, None, f"no HL7-xml v{version}/{sid}.xsd group {where} has {want}"
    base = BUNDLES_DERIVED.get(f"v{version}", "")[1:]
    if not base or not bundles.available(base):
        return None, None, f"no HL7-xml bundle for v{version}"
    own = bundles.tree(base, sid)
    candidates = [sid] if own is not None else \
        [s for s in bundles.structures(base) if s.split("_")[0] == sid.split("_")[0] and s != sid]
    hits = [(s, p, g) for s in candidates for p, g in groups(bundles.tree(base, s) or [])
            if signature(g["elements"]) == sig]
    if len({g["group"] for _, _, g in hits}) > 1:
        hits = [h for h in hits if h[1] == tuple(path)]
    if hits and len({g["group"] for _, _, g in hits}) == 1:
        s, _, g = hits[0]
        cite = f"{_cite(base, s, g)}, derived for v{version} {sid}"
        if s != sid:
            cite += f", which differs from {s} only by trigger"
        return g["group"], "v2xml-v2.4", cite
    if own is None:
        code = sid.split("_")[0]
        return None, None, f"HL7-xml v{base} has no {sid}.xsd and no {code}_*.xsd group matches"
    return None, None, f"no unique HL7-xml v{base}/{sid}.xsd group has {want}"


def _bounds(e):
    return f"{e['min']}..{'*' if e['max'] is None else e['max']}"


def differences(printed, bundle, where="root"):
    """REPORT-ONLY disagreements between the print and the bundle (ruling D3): the member list
    of each group (labels: segment ID or group name), then the bounds of the members both
    list in the same order, recursively. A printed choice is compared with the bundle group of
    the same label (its name, or CHOICE when unnamed), which must be an xsd:choice (P8b-6)."""
    def label(e):
        return e.get("segment") or e.get("group") or e.get("choice") or "CHOICE"
    a, b = [label(e) for e in printed], [label(e) for e in bundle]
    out = []
    if a != b:
        out.append(f"{where}: print [{', '.join(a)}], bundle [{', '.join(b)}]")
    for block in difflib.SequenceMatcher(a=a, b=b, autojunk=False).get_matching_blocks():
        for i in range(block.size):
            p, q = printed[block.a + i], bundle[block.b + i]
            if _bounds(p) != _bounds(q):
                out.append(f"{label(p)} at {where}: print {_bounds(p)}, bundle {_bounds(q)}")
            if "segment" not in p and "group" in q:
                inner = label(p) if where == "root" else f"{where}/{label(p)}"
                if ("alternatives" in p) != q["choice"]:
                    out.append(f"{inner}: print {'choice' if 'alternatives' in p else 'sequence'}, "
                               f"bundle {'choice' if q['choice'] else 'sequence'}")
                out += differences(_members(p), q["elements"], inner)
    return out


def required_citation(name, source, version):
    """The text a structure citation must contain for a group named from a non-printed source
    (StructureCodegen enforces the same rule)."""
    marker = {"override": "overrides.json", "v2xml": f"HL7-xml v{version}/", "v2xml-v2.4": "HL7-xml v2.4/",
              "synthesised": "synthesised"}[source]
    return f"{name} ({marker}"
