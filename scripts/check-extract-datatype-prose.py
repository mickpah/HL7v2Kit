#!/usr/bin/env python3
"""Self-check for scripts/extract-datatype-prose.py (P5-9; a P5-1 review carry-in,
P5-8). No PDFs, no pytest.

    python3 scripts/check-extract-datatype-prose.py

Each check is a plain function of asserts. The script exits 1 when any check fails, so CI
can run it in the fixture-safety job, the same way check-extract-example-messages.py does.
"""
import contextlib
import importlib.util
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, rel):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, rel))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


dtp = _load("extract_datatype_prose", "extract-datatype-prose.py")
dfc = _load("extract_field_components", "extract-field-components.py")


def check_body_heading_wins_over_contents_entry():
    # P5-9: v2.3.1's chapter 2 contents entries carry no dot leaders ("2.8.1    AD - address
    # 2-12"), unlike v2.3 / v2.4's ("2.8.1 AD - address ...... 2-12"), so FURNITURE's
    # dot-leader test does not filter them and the datatype heading pattern matches twice:
    # the contents entry, then the real body heading that precedes the definition text. The
    # fix takes the LAST match (the body heading), the same rule extract_tq already applies
    # to Chapter 4's TQ numbering. Confirmed against the real Hl7V231.pdf text (both AD and
    # TQ) before this check was written.
    lines = [
        "     2.8.1    AD - address                                                       2-12",
        "",
        "2.8.1 AD - address",
        "The mailing address of a person or institution.",
        "Components:",
        "<street address (ST)> ^ <other designation (ST)>",
        "",
        "2.8.1.1 Street address (ST)",
        "Definition: the street address.",
        "2.8.1.2 Other designation (ST)",
        "Definition: a second address line.",
        "2.9 NEXT CHAPTER SECTION",
    ]
    saved_sources, saved_pdf_text = dict(dtp.SOURCES), dtp.pdf_text
    try:
        dtp.SOURCES["test-v231"] = ("dummy.pdf", "2.8")
        dtp.pdf_text = lambda pdf: lines
        types = dtp.extract("test-v231")
        assert types["AD"]["name"] == "address", types["AD"]["name"]
        assert [c["name"] for c in types["AD"]["components"]] == ["Street address", "Other designation"]
    finally:
        dtp.SOURCES.clear()
        dtp.SOURCES.update(saved_sources)
        dtp.pdf_text = saved_pdf_text
    # v2.3 / v2.4: the contents entry is filtered by FURNITURE's dot-leader test, so the
    # heading pattern matches only once. Overwriting on every match is then a no-op — the
    # single match is both "first" and "last" — so the clean name is unaffected.
    clean_lines = lines[2:]
    saved_sources, saved_pdf_text = dict(dtp.SOURCES), dtp.pdf_text
    try:
        dtp.SOURCES["test-v24"] = ("dummy.pdf", "2.8")
        dtp.pdf_text = lambda pdf: clean_lines
        types = dtp.extract("test-v24")
        assert types["AD"]["name"] == "address", types["AD"]["name"]
    finally:
        dtp.SOURCES.clear()
        dtp.SOURCES.update(saved_sources)
        dtp.pdf_text = saved_pdf_text


def check_parse_components_line():
    # The numbered example from the module docstring.
    got = dtp.parse_components_line(
        "<ID (ST)> ^ <check digit (ST)> ^ <code identifying the check digit scheme (ID)>")
    assert got == [("ID", "ST"), ("Check digit", "ST"), ("Code identifying the check digit scheme", "ID")], got
    # an array format ("...", "~") prints no fixed list.
    assert dtp.parse_components_line("...") is None
    assert dtp.parse_components_line("a ~ repeating ~ value") is None
    # a single piece (a primitive's own format, e.g. TS.1) is not a components list.
    assert dtp.parse_components_line("<time (TS)>") is None
    assert dtp.parse_components_line(None) is None
    # an "&" list after the first piece is the previous component's subcomponents, not a new
    # component (v2.3.1 CD's channel number & channel name): it is dropped, not promoted.
    got = dtp.parse_components_line(
        "<channel identifier (*)> ^ <channel number (NM)> & <channel name (ST)> ^ <other (ST)>")
    assert got == [("Channel identifier", ""), ("Other", "ST")], got
    # a piece with "(*)" (no real datatype code) keeps "" as its datatype.
    assert got[0] == ("Channel identifier", "")
    # a first piece carrying its own "&" names the component before its "(".
    got = dtp.parse_components_line("<privilege (CE)> & <privilege class (CE)> ^ <expiration date (DT)>")
    assert got == [("Privilege", ""), ("Expiration date", "DT")], got


def check_reconcile_warns_and_keeps_subsections():
    # The WARN-and-keep path: a Components line shorter than the typed subsections is not
    # trusted (v2.3 XTN prints its whole format as one piece); the subsections are returned
    # unchanged, and a WARN is printed to stderr so the gap is visible, not silent.
    comps = [{"index": 1, "name": "A", "dataType": "ST", "text": ""},
             {"index": 2, "name": "B", "dataType": "ST", "text": ""}]
    printed = [("X", "ST")]
    buf = io.StringIO()
    with contextlib.redirect_stderr(buf):
        out = dtp.reconcile("ZZ", comps, printed)
    assert out is comps, "the WARN path must return the subsections untouched, not a rebuilt list"
    assert "WARN ZZ" in buf.getvalue() and "line ignored" in buf.getvalue(), buf.getvalue()
    # the non-WARN path: a subsection with no printed datatype is completed from the line
    # (v2.3.1 CNE.9 "Original text"; v2.3 CE.4 "Alternate components").
    comps2 = [{"index": 1, "name": "A", "dataType": "", "text": ""}]
    printed2 = [("Alpha", "ST"), ("Beta", "NM")]
    buf2 = io.StringIO()
    with contextlib.redirect_stderr(buf2):
        out2 = dtp.reconcile("ZZ", comps2, printed2)
    assert buf2.getvalue() == "", "no WARN when the line reaches at least as far as the subsections"
    assert out2 == [{"index": 1, "name": "Alpha", "dataType": "ST", "text": ""},
                     {"index": 2, "name": "Beta", "dataType": "NM", "text": ""}], out2


def check_promote_misprinted_ampersands():
    # P5 / P5-9: a Components line's "&" is read as "^" only when every piece after it is a
    # component the field's own "Subcomponents for <name>:" lines describe separately
    # (v2.3.1 / v2.4 PRA-7 "privilege" / "privilege class").
    text = "<privilege (CE)> & <privilege class (CE)> ^ <expiration date (DT)> ^ <something (ST)>"
    body = ["Subcomponents for privilege:", "blah", "Subcomponents for privilege class:", "blah"]
    got = dfc.promote_misprinted_ampersands(text, body)
    assert got == "<privilege (CE)> ^ <privilege class (CE)> ^ <expiration date (DT)> ^ <something (ST)>", got
    # an "&" with no matching "Subcomponents for" line is left alone — it is a genuine
    # subcomponent list (v2.3.1 CD's channel number & channel name), not a misprint.
    text2 = "<channel identifier (*)> ^ <channel number (NM)> & <channel name (ST)>"
    got2 = dfc.promote_misprinted_ampersands(text2, ["nothing relevant here"])
    assert got2 == text2, got2


CHECKS = [check_body_heading_wins_over_contents_entry, check_parse_components_line,
          check_reconcile_warns_and_keeps_subsections, check_promote_misprinted_ampersands]


def main():
    failed = 0
    for check in CHECKS:
        try:
            check()
            print(f"ok   {check.__name__}")
        except Exception as exc:
            failed += 1
            print(f"FAIL {check.__name__}: {type(exc).__name__}: {exc}")
    print(f"{len(CHECKS) - failed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
