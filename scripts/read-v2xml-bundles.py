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
  v2.3.1 (P8b-14 owner ruling, 2026-10-04): its own bundle first, as above (nameSource v2xml; the
      citation names the file's generator, since that bundle mixes two); the bundle's CHOICE is
      refused there (never taken without a cited override), and any miss falls
      through to the v2.4 derivation below.
  v2.3 (no bundle) and v2.3.1's misses (ruling D2), derived through a later bundle: in <STRUCT>.xsd,
      the group with the same first segment and member set (the parent path breaks a tie); where
      that bundle has no <STRUCT>.xsd, every <CODE>_*.xsd of the same message code (the ID differs
      only by trigger, OMD_O01 against OMD_O03), cited with both IDs. v2.3 derives through the
      v2.3.1 bundle first (nameSource v2xml-v2.3.1, P8b-15 controller carry-in; its CHOICE refused
      as for v2.3.1), then the v2.4 bundle; v2.3.1 through the v2.4 bundle (nameSource v2xml-v2.4).
  otherwise: an overrides.json groupNames entry (nameSource override), else <FIRSTSEG>_GROUP,
      numbered 2, 3, ... on a clash within the structure (nameSource synthesised). Every
      synthesised name is a report row (no-bundle-name).
"""
import difflib
import os
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(os.path.dirname(HERE), "docs", "XML-schemas")

# The bundle folder per version as it is on disk (the version-map agreement self-check,
# check-audit-schemas.py). The v2.3.1 folder name has no "v" (owner addition, 2026-10-04).
BUNDLES = {"v2.3.1": "HL7-xml 2.3.1", "v2.4": "HL7-xml v2.4", "v2.5.1": "HL7-xml v2.5.1", "v2.6": "HL7-xml v2.6",
           "v2.7.1": "HL7-xml v2.7.1", "v2.8.2": "HL7-xml v2.8.2"}
# Names derived through later bundles (ruling D2), in order: every v2.3 name (no bundle) through
# the v2.3.1 bundle, then the v2.4 bundle (P8b-15 controller carry-in); each v2.3.1 group its own
# bundle does not name through the v2.4 bundle (P8b-14 ruling: v2.3.1 bundle first, then D2, then
# synthesised).
BUNDLES_DERIVED = {"v2.3": ("v2.3.1", "v2.4"), "v2.3.1": ("v2.4",)}
# Bundle names never taken without a cited override (P8b-14 ruling): in the v2.3.1 bundle, CHOICE
# is the generator's name for an unnamed choice, so it is not read as a printed group's name; the
# derivation or an override names that group. ENCODING, first refused with it, is a genuine group
# name there (RXE {RXR} [{RXC}], as in every later bundle): refusal withdrawn in fix round 1.
REFUSED = {"2.3.1": ("CHOICE",)}
# The generators a bundle file can come from: the v2.3.1 bundle mixes the HL7-Database generator
# of the other five bundles with an encoder generator (namespace urn:com.sun:encoder-hl7-1.0), so
# a v2.3.1 citation names the generator of the file it reads.
CITE_GENERATOR = ("2.3.1",)
NAME_SOURCES = ("printed", "override", "v2xml", "v2xml-v2.3.1", "v2xml-v2.4", "synthesised")
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


def generator(text):
    """The generator a bundle file names: the encoder namespace, the HL7-Database comment, or
    neither."""
    if "urn:com.sun:encoder-hl7-1.0" in text:
        return "urn:com.sun:encoder-hl7-1.0"
    return "HL7-Database" if "by HL7-Database" in text else "an unnamed generator"


class Bundles:
    """Bundle schemas by version ("2.5.1"): from in-memory texts {version: {file: text}} (the
    self-check), or from docs/XML-schemas (from_disk)."""

    def __init__(self, files=None, root=None):
        self._files, self._root, self._trees, self.defects, self.generators = files or {}, root, {}, {}, {}

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
            if text:
                self.generators[key] = generator(text)
            try:
                self._trees[key] = read_bundle(text, sid) if text else None
            except BundleDefect as exc:
                self._trees[key], self.defects[key] = None, str(exc)
        return self._trees[key]


def _members(e):
    """A group's elements, or a printed choice's alternatives (P8b-6)."""
    return e["elements"] if "elements" in e else e["alternatives"]


OPEN = "*"      # a printed open slot in a signature (S3-2): no segment ID is spelt so


def leaves(elements):
    """Segment IDs in order; a printed open slot (S3-2) yields OPEN, standing for the segments
    the print does not enumerate."""
    for e in elements:
        if "segment" in e:
            yield e["segment"]
        elif "slot" in e:
            yield OPEN
        else:
            yield from leaves(_members(e))


def signature(elements):
    segs = list(leaves(elements))
    return (segs[0] if segs else None, frozenset(segs))


def matches(sig, elements):
    """A bundle group's elements against a printed signature. Equal signatures match. A print
    holding an open slot (S3-2; the bundle gives the slot's place as a choice of OBR, RXO, ... or
    anyHL7Segment) matches when the bundle group has every printed segment and at least one
    more (the slot's fillers), and its first segment is the printed first one, or, when the slot
    heads the print, one of those fillers."""
    theirs = signature(elements)
    if theirs == sig or OPEN not in sig[1]:
        return theirs == sig
    known = sig[1] - {OPEN}
    if not known <= theirs[1] or not theirs[1] - known:
        return False
    return theirs[0] not in known if sig[0] == OPEN else theirs[0] == sig[0]


def groups(elements, path=()):
    """(parent path, group) for every group, depth first. A printed choice is not a group but
    its alternatives are searched, under its name or CHOICE (the bundle's name for an unnamed one)."""
    for e in elements:
        if "group" in e:
            yield path, e
            yield from groups(e["elements"], path + (e["group"],))
        elif "alternatives" in e:
            yield from groups(e["alternatives"], path + (e["choice"] or "CHOICE",))


def folder(version):
    """The bundle folder of a version, as on disk ("HL7-xml 2.3.1", "HL7-xml v2.4")."""
    return BUNDLES.get(f"v{version}", f"HL7-xml v{version}")


def _cite(version, sid, group, bundles=None):
    cite = f"{folder(version)}/{sid}.xsd, {group['type']}"
    if version in CITE_GENERATOR and bundles is not None:
        cite += f", generator {bundles.generators.get((version, sid), 'an unnamed generator')}"
    return cite


def resolve(bundles, version, sid, path, elements):
    """(name, nameSource, citation) for an unnamed printed group from the bundles, or
    (None, None, why) on a miss."""
    sig = signature(elements)
    want = f"first segment {sig[0]} and members {{{', '.join(sorted(sig[1]))}}}"
    where = f"under [{', '.join(path)}]" if path else "at the root"
    own_miss = None
    if bundles.available(version):
        tree = bundles.tree(version, sid)
        if tree is None and (version, sid) in bundles.defects:
            own_miss = f"{folder(version)}/{sid}.xsd is unreadable: {bundles.defects[(version, sid)]}"
        elif tree is None and f"v{version}" in BUNDLES_DERIVED:
            # v2.3.1 (P8b-14): a file of the same message code, as the D2 derivation matches.
            name, cite = _by_code(bundles, version, sid, path, sig)
            if name and name not in REFUSED.get(version, ()):
                return name, "v2xml", cite
            own_miss = (f"{folder(version)} has no {sid}.xsd and no {sid.split('_')[0]}_*.xsd group matches" if not name
                        else f"{cite} names it {name}, a name refused without a cited override (P8b-14 ruling)")
        elif tree is None:
            own_miss = f"{folder(version)} has no {sid}.xsd"
        else:
            hits = [g for p, g in groups(tree) if p == tuple(path) and matches(sig, g["elements"])]
            if len(hits) == 1 and hits[0]["group"] in REFUSED.get(version, ()):
                own_miss = (f"{folder(version)}/{sid}.xsd names it {hits[0]['group']} ({hits[0]['type']}), a name "
                            "refused without a cited override (P8b-14 ruling)")
            elif len(hits) == 1:
                return hits[0]["group"], "v2xml", _cite(version, sid, hits[0], bundles)
            else:
                own_miss = f"no {folder(version)}/{sid}.xsd group {where} has {want}"
    if f"v{version}" not in BUNDLES_DERIVED:
        return None, None, own_miss or f"no HL7-xml bundle for v{version}"
    misses = [own_miss] if own_miss else []
    for base in BUNDLES_DERIVED[f"v{version}"]:
        name, source, cite = _derive(bundles, version, base[1:], sid, path, sig, want)
        if name is not None:
            # say why an earlier bundle's name was not taken
            refused = [m for m in misses if "refused" in m]
            return name, source, "; ".join([cite] + refused)
        misses.append(cite)
    return None, None, "; ".join(misses)


def _by_code(bundles, version, sid, path, sig):
    """(name, citation) of the one group, in a bundle file of the same message code as sid, with
    sig's first segment and member set (the parent path breaks a tie), else (None, None)."""
    code = sid.split("_")[0]
    hits = [(s, p, g) for s in bundles.structures(version) if s.split("_")[0] == code and s != sid
            for p, g in groups(bundles.tree(version, s) or []) if matches(sig, g["elements"])]
    if len({g["group"] for _, _, g in hits}) > 1 or OPEN in sig[1]:
        hits = [h for h in hits if h[1] == tuple(path)]
    if not hits or len({g["group"] for _, _, g in hits}) != 1:
        return None, None
    s, _, g = hits[0]
    return g["group"], f"{_cite(version, s, g, bundles)}, for v{version} {sid}, which differs from {s} only by trigger"


def _derive(bundles, version, base, sid, path, sig, want):
    """The D2 derivation through the base bundle (v2.3 through v2.3.1, then v2.4; v2.3.1's misses
    through v2.4): nameSource v2xml-v<base>. A name the base bundle's generator gives an unnamed
    construct (REFUSED) is a miss whose citation says so."""
    if not bundles.available(base):
        return None, None, f"no HL7-xml bundle for v{base}"
    own = bundles.tree(base, sid)
    candidates = [sid] if own is not None else \
        [s for s in bundles.structures(base) if s.split("_")[0] == sid.split("_")[0] and s != sid]
    hits = [(s, p, g) for s in candidates for p, g in groups(bundles.tree(base, s) or [])
            if matches(sig, g["elements"])]
    if len({g["group"] for _, _, g in hits}) > 1 or OPEN in sig[1]:
        hits = [h for h in hits if h[1] == tuple(path)]
    if hits and len({g["group"] for _, _, g in hits}) == 1:
        s, _, g = hits[0]
        cite = f"{_cite(base, s, g, bundles)}, derived for v{version} {sid}"
        if s != sid:
            cite += f", which differs from {s} only by trigger"
        if g["group"] in REFUSED.get(base, ()):
            return None, None, (f"{cite} names it {g['group']}, a name refused without a cited override "
                                "(P8b-14 ruling)")
        return g["group"], f"v2xml-v{base}", cite
    if own is None:
        code = sid.split("_")[0]
        return None, None, f"{folder(base)} has no {sid}.xsd and no {code}_*.xsd group matches"
    return None, None, f"no unique {folder(base)}/{sid}.xsd group has {want}"


def _bounds(e):
    return f"{e['min']}..{'*' if e['max'] is None else e['max']}"


def differences(printed, bundle, where="root"):
    """REPORT-ONLY disagreements between the print and the bundle (ruling D3): the member list
    of each group (labels: segment ID or group name), then the bounds of the members both
    list in the same order, recursively. A printed choice is compared with the bundle group of
    the same label (its name, or CHOICE when unnamed), which must be an xsd:choice (P8b-6)."""
    def label(e):
        if "slot" in e:     # S3-2: the bundle prints a choice (or anyHL7Segment) in its place
            return f"slot {e['slot'] or 'open slot'}"
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
            if "segment" not in p and "slot" not in p and "group" in q:
                inner = label(p) if where == "root" else f"{where}/{label(p)}"
                if ("alternatives" in p) != q["choice"]:
                    out.append(f"{inner}: print {'choice' if 'alternatives' in p else 'sequence'}, "
                               f"bundle {'choice' if q['choice'] else 'sequence'}")
                out += differences(_members(p), q["elements"], inner)
    return out


def required_citation(name, source, version):
    """The text a structure citation must contain for a group named from a non-printed source
    (StructureCodegen enforces the same rule)."""
    marker = {"override": "overrides.json", "v2xml": f"{folder(version)}/", "v2xml-v2.3.1": "HL7-xml 2.3.1/",
              "v2xml-v2.4": "HL7-xml v2.4/",
              "synthesised": "synthesised"}[source]
    return f"{name} ({marker}"
