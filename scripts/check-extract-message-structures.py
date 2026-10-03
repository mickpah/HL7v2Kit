#!/usr/bin/env python3
"""Self-check for scripts/extract-message-structures.py (P8b-2a). No PDFs, no pytest.

    python3 scripts/check-extract-message-structures.py

Each check is a plain function of asserts; the script exits 1 when any check fails, so CI runs
it in the fixture-safety job beside the other extractor self-checks. The three golden checks
embed short excerpts of the v2.5.1 prints as `pdftotext -layout` emits them (blank lines
dropped) and assert that the extractor renders the committed pilot files byte for byte; the
other checks use short synthetic tables.
"""
import copy
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
STRUCTURES = os.path.join(os.path.dirname(HERE), "Resources", "structures")


def _load(name, rel):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, rel))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ext = _load("extract_message_structures", "extract-message-structures.py")
OVERRIDES = ext.load_overrides()
EMPTY = {"groupNames": [], "citationNotes": [], "errata": [], "exclusions": [], "sharedTriggers": [],
         "triggerFolds": []}

# v2.5.1 CH02 section 2.14.1 (p 2-61), CH03 section 3.3.1 (pp 3-4 to 3-5, across a page break
# with the caption repeated) and CH07 section 7.3.1 (the four traps: wrapped title, wrapped
# descriptions, a continuation after the footer and the repeated caption, bare bracket rows).
ACK_CH02 = [
    'Page 2-60                                                         Health Level Seven, Version 2.5.1 © 2007. All rights reserved.',
    'April 2007.                                                                                                     Final Standard.',
    '\x0c                                                                                                    Chapter 2: Control',
    '2.14.1           ACK - general acknowledgment',
    '                ACK^varies^ACK            General Acknowledgment               Status          Chapter',
    '                MSH                       Message Header                                             2',
    '                [{ SFT }]                 Software segment                                           2',
    '                MSA                       Message Acknowledgment                                     2',
    '                [{ ERR }]                 Error                                                      2',
    '                Note: For the general acknowledgment (ACK) message, the value of MSH-9-2-Trigger event is equal to',
    '2.14.2           MCF - delayed acknowledgment',
    'Health Level Seven, Version 2.5.1 © 2007. All rights reserved                                                      Page 2-61',
    'Final Standard.                                                                                                 April 2007.',
    '\x0cChapter 2: Control',
]
ADT_CH03 = [
    'Health Level Seven, Version 2.5.1 © 2007. All rights reserved                                                                                          Page 3-3',
    'Final Standard.                                                                                                                                      April 2007.',
    '\x0cChapter 3: Patient Administration',
    '3.3.1           ADT/ACK - Admit/Visit Notification (Event A01)',
    '    ADT^A01^ADT_A01              ADT Message                                               Status              Chapter',
    '    MSH                          Message Header                                                                      2',
    '    [{ SFT }]                    Software Segment                                                                    2',
    '    EVN                          Event Type                                                                          3',
    '    PID                          Patient Identification                                                              3',
    '    [     PD1   ]                Additional Demographics                                                             3',
    '    [{ ROL }]                    Role                                                                               15',
    '    [{ NK1 }]                    Next of Kin / Associated Parties                                                    3',
    '          PV1                    Patient Visit                                                                       3',
    '    [     PV2   ]                Patient Visit - Additional Info.                                                    3',
    'Page 3-4                                                          Health Level Seven, Version 2.5.1 © 2007. All rights reserved.',
    'April 2007.                                                                                                     Final Standard.',
    '\x0c                                                                                   Chapter 3: Patient Administration',
    '    ADT^A01^ADT_A01                 ADT Message                                            Status            Chapter',
    '    [{ ROL }]                       Role                                                                          15',
    '    [{ DB1 }]                       Disability Information                                                        3',
    '    [{ OBX }]                       Observation/Result                                                            7',
    '    [{ AL1 }]                       Allergy Information                                                           3',
    '    [{ DG1 }]                       Diagnosis Information                                                         6',
    '    [        DRG     ]              Diagnosis Related Group                                                       6',
    '    [{                              --- PROCEDURE begin',
    '               PR1                  Procedures                                                                    6',
    '         [{ ROL }]                  Role                                                                          15',
    '    }]                              --- PROCEDURE end',
    '    [{ GT1 }]                       Guarantor                                                                     6',
    '    [{                              --- INSURANCE begin',
    '               IN1                  Insurance                                                                     6',
    '         [     IN2       ]          Insurance Additional Info.                                                    6',
    '         [{ IN3 }]                  Insurance Additional Info - Cert.                                             6',
    '         [{ ROL }]                  Role                                                                          15',
    '    }]                              --- INSURANCE end',
    '    [        ACC     ]              Accident Information                                                          6',
    '    [        UB1     ]              Universal Bill Information                                                    6',
    '    [        UB2     ]              Universal Bill 92 Information                                                 6',
    '    [        PDA     ]              Patient Death and Autopsy                                                     3',
    '    ACK^A01^ACK                     General Acknowledgment                                     Status         Chapter',
    '    MSH                             Message Header                                                                2',
    '    [{ SFT }]                       Software Segment                                                              2',
    '    MSA                             Message Acknowledgment                                                        2',
    '    [{ ERR }]                       Error                                                                         2',
    '3.3.2              ADT/ACK - Transfer a Patient (Event A02)',
    'Health Level Seven, Version 2.5.1 © 2007. All rights reserved                                                         Page 3-5',
    'Final Standard.                                                                                                   April 2007.',
    '\x0cChapter 3: Patient Administration',
]
ORU_CH07 = [
    'Health Level Seven, Version 2.5.1 © 2007. All rights reserved.                                                 Page 7-11',
    'Final Standard.                                                                                                April 2007.',
    '\x0cChapter 7: Observation Reporting',
    '7.3.1 ORU – Unsolicited Observation Message (Event R01)',
    'Page 7-12                                                       Health Level Seven, Version 2.5.1 © 2007. All rights reserved.',
    'April 2007.                                                                                                   Final Standard.',
    '\x0c                                                                               Chapter 7: Observation Reporting',
    '                  ORU^R01^ORU_R01                 Unsolicited Observation        Status   Chapter',
    '                                                  Message',
    '                  MSH                             Message Header                              2',
    '                  [{ SFT }]                       Software Segment                            2',
    '                  {                               --- PATIENT_RESULT begin',
    '                      [                           --- PATIENT begin',
    '                              PID                 Patient Identification                      3',
    '                              [PD1]               Additional Demographics                     3',
    '                              [{NTE}]             Notes and Comments                          2',
    '                              [{NK1}]             Next of Kin/Associated                      3',
    '                                                  Parties',
    '                              [',
    '                                   PV1            Patient Visit                               3',
    '                                   [PV2]          Patient Visit - Additional                  3',
    '                                                  Info',
    '                              ]',
    '                          ]',
    '                          {',
    '                                  [ORC]           Order common                                4',
    '                                  OBR             Observations Request                        7',
    '                                  {[NTE]}         Notes and comments                          2',
    '                                  [{',
    '                                        TQ1       Timing/Quantity                             4',
    '                                        [{TQ2}]   Timing/Quantity Order                       4',
    '                                                  Sequence',
    '                                  }]',
    '                                  [CTD]           Contact Data                                11',
    '                                  [{',
    '                                       OBX        Observation related to OBR              7',
    '                                       {[NTE]}    Notes and comments                      2',
    '                                  }]',
    '                                  [{FT1}]         Financial Transaction                   6',
    '                                  {[CTI]}         Clinical Trial                          7',
    '                                                  Identification',
    '                                  [{',
    '                                       SPM        Specimen',
    '                                       [{OBX}]    Observation related to',
    'Health Level Seven, Version 2.5.1 © 2007. All rights reserved.                                         Page 7-13',
    'Final Standard.                                                                                        April 2007.',
    '\x0cChapter 7: Observation Reporting',
    '                  ORU^R01^ORU_R01            Unsolicited Observation                Status      Chapter',
    '                                             Message',
    '                                             Specimen',
    '                            }]',
    '                        }',
    '                  }',
    '                  [DSC]                      Continuation Pointer                              2',
    '                  ACK^R01^ACK                Acknowledgment                         Status      Chapter',
    '                  MSH                        Message header                                         2',
    '                  [{ SFT }]                  Software segment                                       2',
    '                  MSA                        Message acknowledgment                                 2',
    '                  [{ ERR }]                  Error                                                  2',
    'Note: The ORC is permitted but not required in this message. Any information that could be included in either the',
    'Page 7-14                                                       Health Level Seven, Version 2.5.1 © 2007. All rights reserved.',
    'April 2007.                                                                                                   Final Standard.',
    '\x0c                                                                              Chapter 7: Observation Reporting',
]


def _committed(version, structure):
    with open(os.path.join(STRUCTURES, f"v{version}", f"{structure}.json"), encoding="utf-8") as f:
        return f.read()


def _extract(texts, overrides=OVERRIDES, version="2.5.1"):
    return ext.extract_version(version, texts, overrides)


def _page(n, body, heading=None):
    """A synthetic printed page: optional heading, body lines, then the page footer."""
    lines = ["\fChapter 9: Synthetic"]
    if heading:
        lines.append(heading)
    return lines + body + [f"Page 9-{n}            Health Level Seven, Version 2.5.1 (c) 2007. All rights reserved."]


def _table(caption, rows, col=30):
    out = [f"    {caption.ljust(col - 4)}Synthetic Message        Status    Chapter"]
    for left, desc in rows:
        out.append(f"    {left.ljust(col - 4)}{desc}".rstrip())
    return out


def _structure(rows, sid="XYZ_X01", overrides=EMPTY):
    text = _page(1, _table(f"XYZ^X01^{sid}", rows), heading="9.1.1           XYZ - synthetic (Event X01)")
    structures, report, _ = ext.extract_version("2.5.1", [("syn", text)], overrides)
    return structures.get(sid), report


def check_ack_golden():
    structures, report, _ = _extract([("CH02", ACK_CH02), ("CH03", ADT_CH03), ("CH07", ORU_CH07)])
    assert ext.render(structures["ACK"]) == _committed("2.5.1", "ACK"), ext.render(structures["ACK"])
    assert not [r for r in report if r[0] == "ACK" and r[1] == "note"], [r for r in report if r[0] == "ACK"]


def check_adt_a01_golden():
    # The same structure is printed for A04, A08 and A13; reuse the A01 print under those captions.
    text = list(ADT_CH03)
    for event, section, title in (("A04", "3.3.4", "Register a Patient"), ("A08", "3.3.8", "Update Patient Information"),
                                  ("A13", "3.3.13", "Cancel Discharge / End Visit")):
        text += [line.replace("ADT^A01^ADT_A01", f"ADT^{event}^ADT_A01").replace("ACK^A01^ACK", f"ACK^{event}^ACK")
                 .replace("3.3.1  ", f"{section} ").replace("Admit/Visit Notification (Event A01)", f"{title} (Event {event})")
                 for line in ADT_CH03]
    structures, report, _ = _extract([("CH03", text)])
    got = ext.render(structures["ADT_A01"])
    assert got == _committed("2.5.1", "ADT_A01"), got
    assert not [r for r in report if r[0] == "ADT_A01" and r[1] != "parsed"], report


def check_oru_r01_golden():
    structures, report, _ = _extract([("CH07", ORU_CH07)])
    got = ext.render(structures["ORU_R01"])
    assert got == _committed("2.5.1", "ORU_R01"), got


def check_brace_bracket_normalisation():
    s, _ = _structure([("MSH", "Header"), ("{[NTE]}", "Notes"), ("[ { PR1", "--- PROCEDURE begin"),
                       ("[{ ROL }]", "Role"), ("} ]", "--- PROCEDURE end"), ("[", "--- VISIT begin"),
                       ("PV1", "Visit"), ("[PV2]]", "Visit 2")])
    assert s["elements"][1] == {"segment": "NTE", "min": 0, "max": None}, s["elements"][1]
    # "[ { PR1" opens two levels, one group.
    group = s["elements"][2]
    assert (group["group"], group["min"], group["max"]) == ("PROCEDURE", 0, None), group
    assert group["elements"] == [{"segment": "PR1", "min": 1, "max": 1}, {"segment": "ROL", "min": 0, "max": None}]
    # "[PV2]]" closes PV2's bracket and the VISIT group.
    visit = s["elements"][3]
    assert (visit["group"], visit["min"], visit["max"]) == ("VISIT", 0, 1), visit
    assert visit["elements"] == [{"segment": "PV1", "min": 1, "max": 1}, {"segment": "PV2", "min": 0, "max": 1}]
    assert len(s["elements"]) == 4, s["elements"]


def check_two_level_group():
    s, _ = _structure([("MSH", "Header"), ("{", "--- OUTER begin"), ("PID", "Patient"),
                       ("[", "--- INNER begin"), ("PV1", "Visit"), ("[PV2]", "Visit 2"), ("]", "--- INNER end"),
                       ("}", "--- OUTER end")])
    outer = s["elements"][1]
    assert (outer["group"], outer["nameSource"], outer["min"], outer["max"]) == ("OUTER", "printed", 1, None)
    inner = outer["elements"][1]
    assert (inner["group"], inner["min"], inner["max"], len(inner["elements"])) == ("INNER", 0, 1, 2), inner
    # A named group whose only member is another named group stays two groups.
    s, _ = _structure([("MSH", "Header"), ("{", "--- RESPONSE begin"), ("[", "--- PATIENT begin"), ("PID", "Patient"),
                       ("[PD1]", "Demographics"), ("]", "--- PATIENT end"), ("}", "--- RESPONSE end")])
    response = s["elements"][1]
    assert (response["group"], response["min"], response["max"]) == ("RESPONSE", 1, None), response
    assert [(e["group"], e["min"], e["max"]) for e in response["elements"]] == [("PATIENT", 0, 1)], response


def check_optional_repeating_group():
    s, _ = _structure([("MSH", "Header"), ("[{", "--- INSURANCE begin"), ("IN1", "Insurance"),
                       ("[{ IN3 }]", "Cert"), ("}]", "--- INSURANCE end")])
    g = s["elements"][1]
    assert (g["group"], g["min"], g["max"]) == ("INSURANCE", 0, None), g
    assert g["elements"][1] == {"segment": "IN3", "min": 0, "max": None}


def check_page_break_footer_inside_table():
    first = _page(1, _table("XYZ^X01^XYZ_X01", [("MSH", "Header"), ("[{", "--- G begin"), ("PID", "Patient")]),
                  heading="9.1.1           XYZ - synthetic (Event X01)")
    second = _page(2, _table("XYZ^X01^XYZ_X01", [("[PD1]", "Demographics"), ("}]", "--- G end"), ("EVN", "Event")], col=34))
    structures, report, count = ext.extract_version("2.5.1", [("syn", first + second)], EMPTY)
    s = structures["XYZ_X01"]
    assert count == 1, count                      # the repeated caption is not a second caption
    assert [e.get("segment") or e["group"] for e in s["elements"]] == ["MSH", "G", "EVN"], s["elements"]
    assert s["citation"] == "HL7 v2.5.1 Chapter 9, section 9.1.1 XYZ - synthetic (Event X01), pp 9-1 to 9-2.", s["citation"]


def check_wrapped_caption():
    text = _page(1, ["    XYZ^X01^XYZ_X01           Unsolicited Synthetic     Status   Chapter",
                     "                              Message",
                     "    MSH                       Message Header                     2",
                     "    [{NK1}]                   Next of Kin/Associated             3",
                     "                              Parties"], heading="9.1.1           XYZ - synthetic (Event X01)")
    caps = ext.captions(text)
    assert [c.title for c in caps] == ["Unsolicited Synthetic Message"], [c.title for c in caps]
    rows = ext.syntax_rows(text, caps[0])
    assert [r.left for r in rows] == ["MSH", "[{NK1}]"], [r.left for r in rows]


def check_unnamed_group_fails():
    rows = [("MSH", "Header"), ("[", ""), ("PV1", "Visit"), ("[PV2]", "Visit 2"), ("]", "")]
    s, report = _structure(rows)
    assert s is None
    [line] = [r for r in report if r[0] == "XYZ_X01"]
    assert line[1] == "skipped" and line[2].startswith("unnamed-group: XYZ_X01 (v2.5.1): unnamed group at path [1]"), line
    named = copy.deepcopy(EMPTY)
    named["groupNames"].append({"version": "2.5.1", "structure": "XYZ_X01", "path": [1], "name": "VISIT", "citation": "x"})
    s, _ = _structure(rows, overrides=named)
    assert (s["elements"][1]["group"], s["elements"][1]["nameSource"]) == ("VISIT", "override"), s["elements"][1]
    try:
        ext.name_groups(ext.parse([ext.Row("[", "", 0, ""), ext.Row("PV1", "", 1, ""), ext.Row("[PV2]", "", 2, ""),
                                   ext.Row("]", "", 3, "")]), "2.5.1", "XYZ_X01", EMPTY)
    except ext.UnnamedGroup as exc:
        assert "XYZ_X01" in str(exc) and "[0]" in str(exc), exc
    else:
        raise AssertionError("an unnamed group must fail")


def check_choice_skipped_with_report_line():
    s, report = _structure([("MSH", "Header"), ("<OBR|", "Order Detail Segment OBR, etc."), ("RQD>", "")])
    assert s is None
    [line] = [r for r in report if r[0] == "XYZ_X01"]
    assert line[1] == "skipped" and line[2].startswith("choice:"), line
    assert "choice 1" in ext.summary("2.5.1", {}, report, 1), ext.summary("2.5.1", {}, report, 1)


def check_unknown_notation():
    for left in ("<OBR|", "Order Detail Segment OBR, etc.", "[PD1", "{ SEG 1}", "..."):
        try:
            ext.parse([ext.Row(left, "", 0, "")])
        except ext.UnknownNotation:
            continue
        raise AssertionError(f"{left!r} must raise UnknownNotation")
    assert issubclass(ext.ChoiceNotation, ext.UnknownNotation)


def check_overrides_validation():
    bad = copy.deepcopy(OVERRIDES)
    bad["groupNames"][0]["citation"] = " "
    for broken, why in ((bad, "empty citation"), ({**EMPTY, "comment": []}, "unknown top-level key"),
                        ({**EMPTY, "errata": [{"x": 1}]}, "errata before P8b-3")):
        try:
            ext.validate_overrides(broken)
        except ext.OverridesError:
            continue
        raise AssertionError(f"{why} must be rejected")
    stale = copy.deepcopy(EMPTY)
    stale["groupNames"].append({"version": "2.5.1", "structure": "XYZ_X01", "path": [7], "name": "GONE", "citation": "x"})
    _, report = _structure([("MSH", "Header")], overrides=stale)
    assert ("XYZ_X01", "error", "unused groupNames entry at path [7]") in report, report


def check_excluded_section():
    example = _page(1, _table("ORU^R01^ORU_R01", [("MSH", "Header"), ("OBR", "Request")]),
                    heading="5.7.3.1       Example of a Conformance Statement")
    normative = _page(2, _table("ORU^R01^ORU_R01", [("MSH", "Header"), ("PID", "Patient")]),
                      heading="7.3.1 ORU - Unsolicited Observation Message (Event R01)")
    rule = {**EMPTY, "exclusions": [{"version": "2.5.1", "section": "5.7.3.1", "citation": "x"}]}
    structures, report, count = ext.extract_version("2.5.1", [("CH05", example), ("CH07", normative)], rule)
    assert [e["segment"] for e in structures["ORU_R01"]["elements"]] == ["MSH", "PID"], structures["ORU_R01"]
    assert ("ORU_R01", "excluded", "ORU^R01^ORU_R01 in section 5.7.3.1") in report, report
    assert "2 captions (1 excluded)" in ext.summary("2.5.1", structures, report, count)


def check_eras_cover_chapters():
    assert set(ext.ERAS) == set(ext.CHAPTERS), sorted(set(ext.ERAS) ^ set(ext.CHAPTERS))
    assert set(ext.ERAS_PENDING) < set(ext.ERAS)
    assert all(ext.ERAS[v] == (ext.CHAPTERS[v], "caret") for v in ("v2.4", "v2.5.1", "v2.6"))
    assert not set(ext.ERAS_PENDING) & {"v2.4", "v2.5.1", "v2.6"}


CHECKS = [check_ack_golden, check_adt_a01_golden, check_oru_r01_golden, check_brace_bracket_normalisation,
          check_two_level_group, check_optional_repeating_group, check_page_break_footer_inside_table,
          check_wrapped_caption, check_unnamed_group_fails, check_choice_skipped_with_report_line,
          check_unknown_notation, check_overrides_validation, check_excluded_section, check_eras_cover_chapters]


def main():
    failed = 0
    for check in CHECKS:
        try:
            check()
            print(f"ok   {check.__name__}")
        except Exception as exc:
            failed += 1
            print(f"FAIL {check.__name__}: {type(exc).__name__}: {str(exc)[:300]}")
    print(f"{len(CHECKS) - failed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
