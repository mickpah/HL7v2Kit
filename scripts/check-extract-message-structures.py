#!/usr/bin/env python3
"""Self-check for scripts/extract-message-structures.py (P8b-2a). No PDFs, no pytest.

    python3 scripts/check-extract-message-structures.py

Each check is a plain function of asserts; the script exits 1 when any check fails, so CI runs
it in the fixture-safety job beside the other extractor self-checks. The three golden checks
embed short excerpts of the v2.5.1 prints as `pdftotext -layout` emits them (blank lines
dropped) and assert that the extractor renders the committed pilot files byte for byte; the
other checks use short synthetic tables. The P8b-2b bundle checks use SYNTHETIC schemas in the
HL7 v2.xml bundle style (_xsd), never bundle text (ruling D4).
"""
import copy
import importlib.util
import json
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
         "triggerFolds": [], "primaryPrints": [], "unionPrints": []}

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
    structures, report, _ = ext.extract_version("2.5.1", [("syn", text)], overrides, tables=[])
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
    # The five unprinted names come from the bundle; the synthetic schema stands in for
    # HL7-xml v2.5.1/ORU_R01.xsd with the committed file's own groups (ruling D4).
    schema = _xsd_from_json(json.loads(_committed("2.5.1", "ORU_R01")))
    structures, report, _ = ext.extract_version("2.5.1", [("CH07", ORU_CH07)], OVERRIDES,
                                                bundles=_bundles("2.5.1", {"ORU_R01": schema}))
    got = ext.render(structures["ORU_R01"])
    assert got == _committed("2.5.1", "ORU_R01"), got
    assert [r[2].split(" at ")[0] for r in report if r[1] == "name"] == \
        ["v2xml VISIT", "v2xml ORDER_OBSERVATION", "v2xml TIMING_QTY", "v2xml OBSERVATION", "v2xml SPECIMEN"], report
    assert not [r for r in report if r[1] in ("bundle-differs", "no-bundle-name", "error")], report


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


def check_unnamed_group_override_or_synthesised():
    # No bundle and no override: the name is synthesised and the miss is a report row.
    s, report = _structure(VISIT_ROWS)
    assert (s["elements"][1]["group"], s["elements"][1]["nameSource"]) == ("PV1_GROUP", "synthesised"), s["elements"][1]
    [miss] = [r for r in report if r[1] == "no-bundle-name"]
    assert miss[2] == "PV1_GROUP at [1]: synthesised: no HL7-xml bundle for v2.5.1", miss
    named = copy.deepcopy(EMPTY)
    named["groupNames"].append({"version": "2.5.1", "structure": "XYZ_X01", "path": [1], "name": "VISIT",
                                "citation": "a cited name"})
    s, _ = _structure(VISIT_ROWS, overrides=named)
    assert (s["elements"][1]["group"], s["elements"][1]["nameSource"]) == ("VISIT", "override"), s["elements"][1]
    assert s["citation"].endswith("VISIT (overrides.json: a cited name)."), s["citation"]


def _seg(sid, lo=1, hi=1):
    return {"segment": sid, "min": lo, "max": hi}


def _choice(alternatives, name=None, lo=1, hi=1):
    return {"choice": name, "nameSource": "printed" if name else None, "min": lo, "max": hi,
            "alternatives": alternatives}


def check_choice_inline():
    # P8b-6 layout 1: the whole choice on one row (v2.4 CH04 ORM_O01 style).
    s, _ = _structure([("MSH", "Header"), ("ORC", "Order"), ("<OBR|RQD|RXO>", "Order Detail Segment OBR, etc."),
                       ("[{NTE}]", "Notes")])
    assert s["elements"][2] == _choice([_seg("OBR"), _seg("RQD"), _seg("RXO")]), s["elements"][2]
    text = ext.render(s)
    assert '{ "choice": null, "min": 1, "max": 1, "alternatives": [' in text, text
    assert '      { "segment": "RQD", "min": 1, "max": 1 },' in text, text
    assert ext.compact(s["elements"][2:]) == "<OBR | RQD | RXO> [{NTE}]", ext.compact(s["elements"][2:])


def check_choice_one_per_row():
    # Layout 2: one alternative per row, "|" trailing (v2.5.1 CH04 ORM_O01), inside a group,
    # and an optional choice "[ <A|B> ]" folds its bracket into the choice's bounds.
    s, _ = _structure([("MSH", "Header"), ("[", "--- ORDER_DETAIL begin"), ("<OBR|", "Order Detail Segment OBR, etc."),
                       ("RQD|", ""), ("RQ1|", ""), ("RXO|", ""), ("ODS|", ""), ("ODT>", ""), ("[{ NTE }]", "Notes"),
                       ("]", "--- ORDER_DETAIL end"), ("[", ""), ("<OBX|", "Result"), ("SPM>", "Specimen"), ("]", "")])
    detail = s["elements"][1]
    assert (detail["group"], detail["min"]) == ("ORDER_DETAIL", 0), detail
    assert detail["elements"] == [_choice([_seg(x) for x in ("OBR", "RQD", "RQ1", "RXO", "ODS", "ODT")]),
                                  _seg("NTE", 0, None)], detail["elements"]
    assert s["elements"][2] == _choice([_seg("OBX"), _seg("SPM")], lo=0), s["elements"][2]


def check_choice_separate_rows_and_placeholder():
    # Layout 3: "<", each alternative, "|" and ">" on rows of their own (v2.5.1 CH12).
    s, _ = _structure([("MSH", "Header"), ("<", ""), ("OBR", "Order Detail Segment"), ("|", ""),
                       ("{RXO}", "Pharmacy order"), (">", ""), ("[{NTE}]", "Notes")])
    assert s["elements"][1] == _choice([_seg("OBR"), _seg("RXO", 1, None)]), s["elements"][1]
    # "etc." in place of the alternatives (CH12's "< OBR | etc. >") is a G6 placeholder: skipped.
    s, report = _structure([("MSH", "Header"), ("<", ""), ("OBR", "Order Detail Segment"), ("|", ""),
                            ("", "etc."), (">", "")])
    assert s is None, s
    [line] = [r for r in report if r[1] == "skipped"]
    assert "placeholder (G6): 'etc.' among a choice's alternatives" in line[2], line
    assert "of which placeholder (G6) 1" in ext.summary("2.5.1", {}, report, 1), ext.summary("2.5.1", {}, report, 1)
    # "etc." in the description column outside a choice is ordinary description text.
    s, _ = _structure([("MSH", "Header"), ("OBR", "Order"), ("", "etc."), ("NTE", "Notes")])
    assert [e["segment"] for e in s["elements"]] == ["MSH", "OBR", "NTE"], s


def check_choice_named():
    # Layout 4 (v2.7.1 on): "--- NAME begin" on the "<" row and "--- NAME end" on the ">" row.
    rows = [("MSH", "Header"), ("[{", "--- RESOURCE_DETAIL begin"), ("<", "--- RESOURCE_OBJECT begin"),
            ("AIS|", "Service"), ("AIG|", "General Resource"), ("AIP", "Personnel"), (">", "--- RESOURCE_OBJECT end"),
            ("[{NTE}]", "Notes"), ("}]", "--- RESOURCE_DETAIL end"), ("[{", "--- G begin"), ("<AIL|", "Location"),
            ("AIP>", "Personnel"), ("}]", "--- G end")]
    s, _ = _structure(rows)
    detail = s["elements"][1]
    assert detail["elements"][0] == _choice([_seg("AIS"), _seg("AIG"), _seg("AIP")], "RESOURCE_OBJECT"), detail
    text = ext.render(s)
    assert '{ "choice": "RESOURCE_OBJECT", "nameSource": "printed", "min": 1, "max": 1, "alternatives": [' in text
    # A named group whose only member is a choice stays a group: the name is the group's.
    g = s["elements"][2]
    assert (g["group"], g["min"], g["max"]) == ("G", 0, None), g
    assert g["elements"] == [_choice([_seg("AIL"), _seg("AIP")])], g["elements"]
    assert ext.compact([g]) == "[{G: <AIL | AIP>}]", ext.compact([g])


def check_choice_of_segment_groups():
    # CH02 2.12.1: "<OBR [{NTE}] |RQD|RQ1 [{ROL [{NTE}] }] |RXO|ODS|ODT>": an alternative of
    # several elements is an unnamed group, named like any other (here synthesised, cited).
    s, report = _structure([("MSH", "Header"), ("<OBR [{NTE}] |", "Detail"), ("RQD|", ""), ("RQ1 [{ROL [{NTE}] }] |", ""),
                            ("RXO|ODS|ODT>", "")])
    alts = s["elements"][1]["alternatives"]
    assert [a.get("segment") or a["group"] for a in alts] == ["OBR_GROUP", "RQD", "RQ1_GROUP", "RXO", "ODS", "ODT"], alts
    assert alts[0]["elements"] == [_seg("OBR"), _seg("NTE", 0, None)] and alts[0]["nameSource"] == "synthesised", alts[0]
    rol = alts[2]["elements"][1]
    assert (rol["min"], rol["max"]) == (0, None) and rol["elements"] == [_seg("ROL"), _seg("NTE", 0, None)], rol
    assert "OBR_GROUP (synthesised" in s["citation"], s["citation"]
    # "< QPD RCP >" with no "|" (v2.8.2 CH16) is not a choice of one: under the P8b-6 ruling it
    # is a named required group (check_no_bar_choice_is_named_required_group).
    s, report = _structure([("MSH", "Header"), ("<", "--- QUERY_INFORMATION begin"), ("QPD", "Query"),
                            ("RCP", "Control"), (">", "--- QUERY_INFORMATION end")])
    g = s["elements"][1]
    assert (g["group"], g["min"], g["max"]) == ("QUERY_INFORMATION", 1, 1) and "alternatives" not in g, g


def check_choice_malformed():
    for rows in (["<OBR|>"], ["<OBR>"], ["OBR|RXO"], ["<|OBR>"], ["<OBR|", "RXO"], ["[<OBR|RXO]>"]):
        try:
            ext.parse([ext.Row(left, "", 0, "") for left in rows])
        except ext.UnknownNotation:
            continue
        raise AssertionError(f"{rows!r} must raise UnknownNotation")


def check_choice_bundle_cross_check():
    # The bundle names an unnamed choice CHOICE: a print choice is compared with it, member by
    # member; a group inside an alternative resolves under the CHOICE path; a choice the
    # bundle models as a sequence (or the reverse) is a bundle-differs row.
    rows = [("MSH", "Header"), ("<", ""), ("OBR", "Order"), ("|", ""), ("[", ""), ("RXO", "Pharmacy"),
            ("RXR", "Route"), ("]", ""), (">", "")]
    good = _xsd("XYZ_X01", "XYZ_X01: MSH 1 1, XYZ_X01.CHOICE 1 1;XYZ_X01.CHOICE choice: OBR 1 1, XYZ_X01.PHARM 0 1;"
                           "XYZ_X01.PHARM: RXO 1 1, RXR 1 1")
    text = _page(1, _table("XYZ^X01^XYZ_X01", rows), heading="9.1.1           XYZ - synthetic (Event X01)")
    structures, report, _ = ext.extract_version("2.5.1", [("syn", text)], EMPTY, bundles=_bundles("2.5.1", {"XYZ_X01": good}))
    choice = structures["XYZ_X01"]["elements"][1]
    assert choice["alternatives"][1]["group"] == "PHARM" and choice["alternatives"][1]["nameSource"] == "v2xml", choice
    assert not [r for r in report if r[1] == "bundle-differs"], report
    seq = good.replace('<xsd:choice><xsd:element ref="OBR"', '<xsd:sequence><xsd:element ref="OBR"')
    seq = seq.replace('maxOccurs="1"/></xsd:choice></xsd:complexType><xsd:element name="XYZ_X01.CHOICE"',
                      'maxOccurs="1"/></xsd:sequence></xsd:complexType><xsd:element name="XYZ_X01.CHOICE"')
    _, report, _ = ext.extract_version("2.5.1", [("syn", text)], EMPTY, bundles=_bundles("2.5.1", {"XYZ_X01": seq}))
    assert ("XYZ_X01", "bundle-differs", "CHOICE: print choice, bundle sequence") in report, report


def check_unknown_notation():
    for left in ("<OBR|", "Order Detail Segment OBR, etc.", "[PD1", "{ SEG 1}", "..."):
        try:
            ext.parse([ext.Row(left, "", 0, "")])
        except ext.UnknownNotation:
            continue
        raise AssertionError(f"{left!r} must raise UnknownNotation")


def check_overrides_validation():
    bad = copy.deepcopy(OVERRIDES)
    bad["groupNames"] = [{"version": "2.5.1", "structure": "XYZ_X01", "path": [1], "name": "VISIT", "citation": " "}]
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


def _xsd(sid, spec):
    """A SYNTHETIC structure schema written in the HL7 v2.xml bundle style (single line, one
    complexType NAME.CONTENT and one element NAME per group). spec: "TYPE: REF MIN MAX, ...;
    ..." where TYPE is the structure ID or STRUCT.GROUP, and "TYPE choice:" makes a choice.
    Never bundle text (ruling D4)."""
    out = ['<?xml version="1.0" encoding="UTF-8"?><xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema" '
           'xmlns="urn:hl7-org:v2xml" targetNamespace="urn:hl7-org:v2xml" elementFormDefault="qualified">'
           '<xsd:include schemaLocation="segments.xsd"/>']
    for part in spec.split(";"):
        head, refs = part.split(":", 1)
        name, _, kind = head.strip().partition(" ")
        tag = "choice" if kind == "choice" else "sequence"
        body = "".join(f'<xsd:element ref="{r}" minOccurs="{lo}" maxOccurs="{hi}"/>'
                       for r, lo, hi in (item.split() for item in refs.split(",")))
        out.append(f'<xsd:complexType name="{name}.CONTENT"><xsd:{tag}>{body}</xsd:{tag}></xsd:complexType>'
                   f'<xsd:element name="{name}" type="{name}.CONTENT"/>')
    return "".join(out) + "</xsd:schema>"


def _xsd_from_json(structure):
    """The synthetic schema of a committed structure file: its own groups, by name."""
    sid, parts = structure["structure"], []

    def walk(name, elements):
        refs = []
        for e in elements:
            hi = "unbounded" if e["max"] is None else e["max"]
            if "segment" in e:
                refs.append(f'{e["segment"]} {e["min"]} {hi}')
            else:
                refs.append(f'{sid}.{e["group"]} {e["min"]} {hi}')
                walk(f'{sid}.{e["group"]}', e["elements"])
        parts.insert(0, f"{name}: " + ", ".join(refs))
    walk(sid, structure["elements"])
    return _xsd(sid, ";".join(parts))


def _bundles(version, files):
    return ext.Bundles({version: {f"{sid}.xsd": text for sid, text in files.items()}})


VISIT_ROWS = [("MSH", "Header"), ("[", ""), ("PV1", "Visit"), ("[PV2]", "Visit 2"), ("]", "")]


def check_bundle_reader_tree():
    tree = ext.read_bundle(_xsd("XYZ_X01", "XYZ_X01: MSH 1 1, XYZ_X01.VISIT 0 1, XYZ_X01.CHOICE 1 unbounded;"
                                "XYZ_X01.VISIT: PV1 1 1, PV2 0 1; XYZ_X01.CHOICE choice: OBR 1 1, RQD 1 1"), "XYZ_X01")
    assert tree[0] == {"segment": "MSH", "min": 1, "max": 1}, tree[0]
    visit = tree[1]
    assert (visit["group"], visit["type"], visit["min"], visit["max"], visit["choice"]) == \
        ("VISIT", "XYZ_X01.VISIT.CONTENT", 0, 1, False), visit
    assert visit["elements"][1] == {"segment": "PV2", "min": 0, "max": 1}, visit
    choice = tree[2]
    assert (choice["group"], choice["max"], choice["choice"]) == ("CHOICE", None, True), choice
    assert [e["segment"] for e in choice["elements"]] == ["OBR", "RQD"], choice


def check_bundle_names_group_by_path_and_members():
    # The bundle orders its groups differently from the print: the name follows path and members.
    b = _bundles("2.5.1", {"XYZ_X01": _xsd("XYZ_X01", "XYZ_X01: MSH 1 1, XYZ_X01.OTHER 0 1, XYZ_X01.VISIT 0 1;"
                                                      "XYZ_X01.OTHER: NK1 1 1; XYZ_X01.VISIT: PV1 1 1, PV2 0 1")})
    text =_page(1, _table("XYZ^X01^XYZ_X01", VISIT_ROWS), heading="9.1.1           XYZ - synthetic (Event X01)")
    structures, report, _ = ext.extract_version("2.5.1", [("syn", text)], EMPTY, bundles=b)
    s = structures["XYZ_X01"]
    assert (s["elements"][1]["group"], s["elements"][1]["nameSource"]) == ("VISIT", "v2xml"), s["elements"][1]
    assert s["citation"].endswith(" Unprinted group names (ADR-019 decision 3): VISIT "
                                  "(HL7-xml v2.5.1/XYZ_X01.xsd, XYZ_X01.VISIT.CONTENT)."), s["citation"]
    assert ("XYZ_X01", "name", "v2xml VISIT at [1]: HL7-xml v2.5.1/XYZ_X01.xsd, XYZ_X01.VISIT.CONTENT") in report, report
    assert "1 v2xml, 0 v2xml-v2.4, 0 synthesised, 0 override; 1 bundle-differs" in ext.name_summary("2.5.1", report), \
        ext.name_summary("2.5.1", report)
    ext.validate_names(s)


def check_bundle_mismatch_not_resolved_by_position():
    # Same position, different members: never named by position. Same members under a different
    # parent: never named either.
    for spec in ("XYZ_X01: MSH 1 1, XYZ_X01.VISIT 0 1; XYZ_X01.VISIT: PV1 1 1, PV2 0 1, DB1 0 1",
                 "XYZ_X01: MSH 1 1, XYZ_X01.OUTER 0 1; XYZ_X01.OUTER: NK1 0 1, XYZ_X01.VISIT 1 1;"
                 "XYZ_X01.VISIT: PV1 1 1, PV2 0 1"):
        text = _page(1, _table("XYZ^X01^XYZ_X01", VISIT_ROWS), heading="9.1.1           XYZ - synthetic (Event X01)")
        structures, report, _ = ext.extract_version("2.5.1", [("syn", text)], EMPTY,
                                                    bundles=_bundles("2.5.1", {"XYZ_X01": _xsd("XYZ_X01", spec)}))
        g = structures["XYZ_X01"]["elements"][1]
        assert (g["group"], g["nameSource"]) == ("PV1_GROUP", "synthesised"), g
        misses = [r for r in report if r[1] == "no-bundle-name"]
        assert len(misses) == 1 and "first segment PV1" in misses[0][2], report
        assert "PV1_GROUP (synthesised: " in structures["XYZ_X01"]["citation"], structures["XYZ_X01"]["citation"]


def _named(rows, version, sid, bundles):
    log = []
    elements = ext.name_groups(ext.parse([ext.Row(left, "", i, "") for i, left in enumerate(rows)]),
                               version, sid, EMPTY, bundles=bundles, log=log)
    return elements, log


def check_derivation_through_v24():
    rows = ["MSH", "{", "PID", "[", "PV1", "[PV2]", "]", "}"]
    same = _bundles("2.4", {"ADT_A99": _xsd("ADT_A99", "ADT_A99: MSH 1 1, ADT_A99.PATIENT 1 unbounded;"
                                                      "ADT_A99.PATIENT: PID 1 1, ADT_A99.VISIT 0 1;"
                                                      "ADT_A99.VISIT: PV1 1 1, PV2 0 1")})
    elements, log = _named(rows, "2.3", "ADT_A99", same)
    assert [(e["name"], e["source"]) for e in log] == [("PATIENT", "v2xml-v2.4"), ("VISIT", "v2xml-v2.4")], log
    assert log[1]["cite"] == "HL7-xml v2.4/ADT_A99.xsd, ADT_A99.VISIT.CONTENT, derived for v2.3 ADT_A99", log[1]
    assert elements[1]["elements"][1]["nameSource"] == "v2xml-v2.4", elements
    # The structure ID differs only by trigger: match on message code, cite both IDs.
    other = _bundles("2.4", {"OMD_O03": _xsd("OMD_O03", "OMD_O03: MSH 1 1, OMD_O03.DIET 1 unbounded;"
                                                        "OMD_O03.DIET: PID 1 1, OMD_O03.VISIT 0 1;"
                                                        "OMD_O03.VISIT: PV1 1 1, PV2 0 1"),
                             "ORM_O01": _xsd("ORM_O01", "ORM_O01: MSH 1 1, ORM_O01.X 0 1; ORM_O01.X: PID 1 1, "
                                                        "PV1 0 1, PV2 0 1")})
    elements, log = _named(rows, "2.3.1", "OMD_O01", other)
    assert [(e["name"], e["source"]) for e in log] == [("DIET", "v2xml-v2.4"), ("VISIT", "v2xml-v2.4")], log
    assert log[0]["cite"] == ("HL7-xml v2.4/OMD_O03.xsd, OMD_O03.DIET.CONTENT, derived for v2.3.1 OMD_O01, "
                              "which differs from OMD_O03 only by trigger"), log[0]


def check_synthesised_fallback():
    rows = ["MSH", "[", "PV1", "[PV2]", "]", "{", "PV1", "DB1", "}"]
    elements, log = _named(rows, "2.3", "XYZ_X01", _bundles("2.4", {}))
    assert [(e["name"], e["source"]) for e in log] == [("PV1_GROUP", "synthesised"), ("PV1_GROUP2", "synthesised")], log
    assert log[0]["cite"] == "synthesised: HL7-xml v2.4 has no XYZ_X01.xsd and no XYZ_*.xsd group matches", log[0]
    assert log[0]["miss"], log[0]
    assert [e.get("group") for e in elements] == [None, "PV1_GROUP", "PV1_GROUP2"], elements


def check_bundle_differs_report_only():
    rows = [("MSH", "Header"), ("[{NTE}]", "Notes"), ("PID", "Patient"), ("[", "--- VISIT begin"), ("PV1", "Visit"),
            ("]", "--- VISIT end")]
    b = _bundles("2.5.1", {"XYZ_X01": _xsd("XYZ_X01", "XYZ_X01: MSH 1 1, NTE 0 1, PID 1 1, XYZ_X01.VISIT 0 1, DSC 0 1;"
                                                      "XYZ_X01.VISIT: PV1 1 1, PV2 0 1")})
    text = _page(1, _table("XYZ^X01^XYZ_X01", rows), heading="9.1.1           XYZ - synthetic (Event X01)")
    structures, report, _ = ext.extract_version("2.5.1", [("syn", text)], EMPTY, bundles=b)
    plain, _ = _structure(rows)
    assert structures["XYZ_X01"] == plain, "the bundle changes nothing but names"
    differs = sorted(r[2] for r in report if r[1] == "bundle-differs")
    assert differs == ["NTE at root: print 0..*, bundle 0..1",
                       "VISIT: print [PV1], bundle [PV1, PV2]",
                       "root: print [MSH, NTE, PID, VISIT], bundle [MSH, NTE, PID, VISIT, DSC]"], differs


def check_override_shadowed_by_bundle():
    named = copy.deepcopy(EMPTY)
    named["groupNames"].append({"version": "2.5.1", "structure": "XYZ_X01", "path": [1], "name": "VISIT", "citation": "x"})
    b = _bundles("2.5.1", {"XYZ_X01": _xsd("XYZ_X01", "XYZ_X01: MSH 1 1, XYZ_X01.VISIT 0 1; XYZ_X01.VISIT: PV1 1 1, PV2 0 1")})
    text = _page(1, _table("XYZ^X01^XYZ_X01", VISIT_ROWS), heading="9.1.1           XYZ - synthetic (Event X01)")
    structures, report, _ = ext.extract_version("2.5.1", [("syn", text)], named, bundles=b)
    assert structures["XYZ_X01"]["elements"][1]["nameSource"] == "v2xml"
    assert ("XYZ_X01", "error", "groupNames entry at path [1] shadows the bundle name VISIT") in report, report


def check_name_source_validation():
    s = {"structure": "XYZ_X01", "version": "2.5.1", "citation": "c. Unprinted group names: G (synthesised: x).",
         "elements": [{"group": "G", "nameSource": "synthesised", "min": 0, "max": 1, "elements": []}]}
    ext.validate_names(s)
    for source, citation in (("guessed", s["citation"]), ("v2xml", s["citation"]), ("override", "c."),
                             ("v2xml-v2.4", "G (HL7-xml v2.4/XYZ_X01.xsd, XYZ_X01.G.CONTENT, derived for v2.5.1 XYZ_X01)")):
        bad = copy.deepcopy(s)
        bad["elements"][0]["nameSource"], bad["citation"] = source, citation
        try:
            ext.validate_names(bad)
        except ext.NameSourceError:
            continue
        raise AssertionError(f"nameSource {source} with citation {citation!r} must be rejected")
    assert ext.NAME_SOURCES == ("printed", "override", "v2xml", "v2xml-v2.4", "synthesised")


def check_bundle_maps():
    assert set(ext.BUNDLES) == {"v2.4", "v2.5.1", "v2.6", "v2.7.1", "v2.8.2"}, ext.BUNDLES
    assert ext.BUNDLES_DERIVED == {"v2.3": "v2.4", "v2.3.1": "v2.4"}, ext.BUNDLES_DERIVED
    assert set(ext.BUNDLES) | set(ext.BUNDLES_DERIVED) == set(ext.ERAS)


def check_eras_cover_chapters():
    assert set(ext.ERAS) == set(ext.CHAPTERS), sorted(set(ext.ERAS) ^ set(ext.CHAPTERS))
    assert not ext.ERAS_PENDING, ext.ERAS_PENDING      # P8b-3a: every era is read
    assert all(ext.ERAS[v] == (ext.CHAPTERS[v], "caret") for v in ("v2.4", "v2.5.1", "v2.6"))
    assert {v: e for v, (_, e) in ext.ERAS.items() if e != "caret"} == {
        "v2.3": "section-title", "v2.3.1": "table-0354", "v2.7.1": "caret-colon", "v2.8.2": "caret-colon"}


def _run(version, texts, overrides=EMPTY, tables=(), full=False):
    return ext.extract_version(version, texts, overrides, tables=list(tables), full=full)


def check_caret_colon_caption():
    # v2.7.1 / v2.8.2: the caption on its own line, a Segments/Description row that repeats after
    # the page break at other columns, and chapter-local page numbers.
    text = ["\fChapter 9: Synthetic", "9.1.1 XYZ - synthetic (Event X01)",
            "                         XYZ^X01^XYZ_X01: Synthetic Message",
            "   Segments                    Description                 Status   Chapter",
            "   MSH                         Message Header                         2",
            "   [{                          --- G begin",
            "      PID                      Patient                                3",
            "Page 1                                     Health Level Seven, Version 2.8.2",
            "\fChapter 9: Synthetic",
            "     Segments                      Description               Status   Chapter",
            "        [PD1]                      Demographics                         3",
            "     }]                            --- G end",
            "     EVN                           Event                                3",
            "This message is followed by prose that sits left of the column.",
            "Page 2                                     Health Level Seven, Version 2.8.2"]
    structures, report, count = _run("2.8.2", [("syn", text)])
    s = structures["XYZ_X01"]
    assert count == 1, count
    assert [e.get("segment") or e["group"] for e in s["elements"]] == ["MSH", "G", "EVN"], s["elements"]
    assert s["citation"] == "HL7 v2.8.2 Chapter 9, section 9.1.1 XYZ - synthetic (Event X01), pp 1 to 2.", s["citation"]


def check_colon_caption_with_space_ends_table():
    # P8b-11 (v2.8.2 CH07 ORU_R01 and ORU_R30): the acknowledgment after the table is captioned
    # "ACK^R01^ACK : title" (a space before the colon); it is a caption, so it ends the table
    # instead of the rows running on into a second MSH.
    text = ["\fChapter 9: Synthetic", "9.1.1 XYZ - synthetic (Event X01)",
            "                         XYZ^X01^XYZ_X01: Synthetic Message",
            "   Segments                    Description                 Status   Chapter",
            "   MSH                         Message Header                         2",
            "   PID                         Patient                                3",
            "                        ACK^X01^ACK : Synthetic Message",
            "   Segments                    Description                 Status   Chapter",
            "   MSH                         Message Header                         2",
            "   MSA                         Acknowledgment                         2",
            "Page 1                                     Health Level Seven, Version 2.8.2"]
    structures, report, count = _run("2.8.2", [("syn", text)])
    assert count == 2, (count, report)
    assert [e["segment"] for e in structures["XYZ_X01"]["elements"]] == ["MSH", "PID"], report
    assert [e["segment"] for e in structures["ACK"]["elements"]] == ["MSH", "MSA"], report


def check_v282_reader_layouts():
    # P8b-11 (v2.8.2): a caption title wrapped onto the line before the Segments row (CH04 4.4.11.1
    # ORL^O36^ORL_O36 "(Patient Required)"); a "Segments Descriptions" header (CH04 4.16.6
    # QBP^Q33^QBP_O33); a depth-0 line after the table that starts with a segment ID but is prose
    # ("QPD Input Parameter Specification", CH04A RSP^K31^RSP_K31) ends the table.
    text = ["\fChapter 9: Synthetic", "9.1.1 XYZ - synthetic (Event X01)",
            " XYZ^X01^XYZ_X01: Synthetic Message - Multiple Order Per Container of Specimen",
            "                                        (Patient Required)",
            "   Segments                    Descriptions                Status   Chapter",
            "   MSH                         Message Header                         2",
            "   PID                         Patient                                3",
            "    QPD Input Parameter Specification",
            "Page 1                                     Health Level Seven, Version 2.8.2"]
    structures, report, _ = _run("2.8.2", [("syn", text)])
    assert [e["segment"] for e in structures["XYZ_X01"]["elements"]] == ["MSH", "PID"], report
    # An indented section heading (v2.8.2 CH04A 4A.3.13, CH16 16.3.9, CH08) is a heading: the
    # caption cites it, not the last flush-left heading.
    # The number must open with the file's chapter (CH09 here), so numbered prose is no heading.
    text[2:2] = ["    9.1.2        XYZ - indented heading (Event X01)", "      2.5   Prose that is numbered"]
    structures, report, _ = _run("2.8.2", [("v2.8.2/V282_CH09_Synthetic.pdf", text)])
    assert "section 9.1.2 XYZ - indented heading (Event X01)" in structures["XYZ_X01"]["citation"], \
        structures["XYZ_X01"]["citation"]


def check_v271_reader_layouts():
    # P8b-16 (v2.7.1 CH07 7.17.1 OSM^R26^OSM_R26): the header row prints the caption's own
    # CODE^EVT^STRUCT in place of "Segments", with the title wrapped onto the next line, and repeats
    # so after the page break; a group mark whose name's last word wraps with "begin" or "end"
    # ("--- SUBJECT POPULATION/LOCATION" then "IDENTIFICATION begin") is one mark.
    text = ["\fChapter 9: Synthetic", "9.1.1 XYZ - synthetic (Event X01)",
            "                         XYZ^X01^XYZ_X01: Synthetic Message",
            "   XYZ^X01^XYZ_X01             Synthetic Shipment Manifest   Status   Chapter",
            "                               Message",
            "   MSH                         Message Header                         2",
            "   [                           --- WRAPPED NAME",
            "                               PART begin",
            "      PID                      Patient                                3",
            "Page 1                                     Health Level Seven, Version 2.7.1",
            "\fChapter 9: Synthetic",
            "     XYZ^X01^XYZ_X01               Synthetic Shipment Manifest  Status   Chapter",
            "                                   Message",
            "        [PD1]                      Demographics                         3",
            "     ]                             --- WRAPPED NAME",
            "                                   PART end",
            "Page 2                                     Health Level Seven, Version 2.7.1"]
    fix = {**EMPTY, "errata": [{"version": "2.7.1", "where": "group-mark", "structure": "XYZ_X01",
                                "printed": "WRAPPED NAME PART", "intended": "WRAPPED_NAME_PART", "citation": "c"}]}
    structures, report, _ = _run("2.7.1", [("syn", text)], fix)
    s = structures.get("XYZ_X01")
    assert s, report
    assert [e.get("segment") or e["group"] for e in s["elements"]] == ["MSH", "WRAPPED_NAME_PART"], s["elements"]
    assert [e["segment"] for e in s["elements"][1]["elements"]] == ["PID", "PD1"], s["elements"]
    # The header form is read only when its cell is the caption it follows: another ID is prose.
    text[3] = text[3].replace("XYZ^X01^XYZ_X01", "XYZ^X02^XYZ_X02")
    structures, report, _ = _run("2.7.1", [("syn", text)], fix)
    assert "XYZ_X01" not in structures, structures.get("XYZ_X01")


def check_event_ranges():
    assert ext.expand_events("C01-C08") == [f"C0{n}" for n in range(1, 9)]
    assert ext.expand_events("PCG,PCH,PCJ") == ["PCG", "PCH", "PCJ"]
    assert ext.expand_events("PCB-PCD") == ["PCB", "PCC", "PCD"]
    assert len(ext.expand_events("S12-S24,S26,S27")) == 15
    assert ext.expand_events("A01-B02") is None and ext.expand_events("varies") == ["varies"]
    text = _page(1, _table("CRM^C01-C08^CRM_C01", [("MSH", "Header"), ("PID", "Patient")]),
                 heading="9.1.1           CRM - synthetic (Events C01-C08)")
    structures, _, _ = _run("2.5.1", [("syn", text)])
    assert structures["CRM_C01"]["triggers"] == [f"CRM^C0{n}" for n in range(1, 9)], structures["CRM_C01"]["triggers"]


TABLE = [("XYZ_X01", ["X01", "X02"], "X01, X02"), ("XYZ_X03", ["X03", "X04"], "X03, X04"), ("ACK", None, "Varies")]


def check_two_part_caption_through_0354():
    # v2.3.1 (and v2.4's two-part captions): CODE^EVT, the structure ID from Table 0354.
    rows = [("MSH", "Header"), ("PID", "Patient")]
    for version in ("2.3.1", "2.4"):
        text = _page(1, ["    XYZ^X02                   Synthetic Message                     Chapter"]
                     + _table("XYZ^X02", rows)[1:]
                     + ["    XYZ^X02|1|example message, not a caption", ""]
                     + ["    ACK^X02                   General Acknowledgment                Chapter"]
                     + _table("ACK^X02", [("MSH", "Header"), ("MSA", "Ack")])[1:]
                     + ["    XYZ^X09                   Synthetic Message                     Chapter"]
                     + _table("XYZ^X09", rows)[1:], heading="9.1.2           XYZ - synthetic (Event X02)")
        structures, report, count = _run(version, [("syn", text)], tables=TABLE)
        assert count == 3, (version, count)
        # X01 is added from the Table 0354 row (P8b-11 fix-round ruling).
        assert structures["XYZ_X01"]["triggers"] == ["XYZ^X02", "XYZ^X01"], structures
        assert structures["ACK"]["triggers"] == ["ACK^X02"], structures
        [miss] = [r for r in report if r[1] == "needs-structure-id"]
        assert miss[0] == "XYZ^X09" and "has no row for it" in miss[2], miss


def check_section_title_caption():
    # v2.3: the message code alone; the events from the section title, wrapped over two lines.
    text = _page(1, ["    XYZ                       Synthetic Message                     Chapter"]
                 + _table("XYZ", [("MSH", "Header"), ("PID", "Patient")])[1:], heading="9.2.1 XYZ - synthetic (events X03,")
    text.insert(2, "X04)")
    other = _page(2, ["    XYZ                       Synthetic Message                     Chapter"]
                  + _table("XYZ", [("MSH", "Header")])[1:], heading="9.3 XYZ TRIGGER EVENTS")
    structures, report, _ = _run("2.3", [("syn", text + other)], tables=TABLE)
    assert structures["XYZ_X03"]["triggers"] == ["XYZ^X03", "XYZ^X04"], structures
    [miss] = [r for r in report if r[1] == "needs-event"]
    assert miss[0] == "XYZ^?" and "9.3" in miss[2], miss


def check_primary_print_and_duplicates():
    # A chapter that only reuses ADT_A01 (ADT^A04 here) prints it first and differently; the
    # defining caption ADT^A01^ADT_A01 is the primary, the other print a duplicate-differs row.
    reuse = _page(1, _table("ADT^A04^ADT_A01", [("MSH", "Header"), ("[ERR]", "Error")]), heading="5.1.1 Reuse")
    define = _page(2, _table("ADT^A01^ADT_A01", [("MSH", "Header"), ("[{ERR}]", "Error")]), heading="3.3.1 Define")
    same = _page(3, _table("ADT^A08^ADT_A01", [("MSH", "Header"), ("[{ERR}]", "Error")]), heading="3.3.8 Same")
    structures, report, _ = _run("2.5.1", [("CH05", reuse), ("CH03", define), ("CH03b", same)])
    s = structures["ADT_A01"]
    assert s["elements"][1] == {"segment": "ERR", "min": 0, "max": None}, s["elements"]
    assert s["triggers"] == ["ADT^A01", "ADT^A04", "ADT^A08"], s["triggers"]
    assert s["citation"].startswith("HL7 v2.5.1 Chapter 3, section 3.3.1 Define"), s["citation"]
    differs = [r for r in report if r[1] == "duplicate-differs"]
    assert len(differs) == 1 and differs[0][2].startswith("ADT^A04^ADT_A01 (section 5.1.1) prints 'MSH [ERR]'"), differs


def check_excluded_print_never_primary():
    # The excluded print is first and carries the defining caption: it is never the primary and
    # never a duplicate-differs row. A stale exclusion is an error on a full read.
    example = _page(1, _table("ORU^R01^ORU_R01", [("MSH", "Header"), ("OBR", "Request")]), heading="5.7.3.1 Example")
    normative = _page(2, _table("ORU^R01^ORU_R01", [("MSH", "Header"), ("PID", "Patient")]), heading="7.3.1 ORU")
    rule = {**EMPTY, "exclusions": [{"version": "2.5.1", "section": "5.7.3.1", "citation": "x"},
                                    {"version": "2.5.1", "section": "5.9.9", "citation": "x"}]}
    structures, report, _ = _run("2.5.1", [("CH05", example), ("CH07", normative)], rule, full=True)
    assert [e["segment"] for e in structures["ORU_R01"]["elements"]] == ["MSH", "PID"]
    assert not [r for r in report if r[1] == "duplicate-differs"], report
    assert ("5.9.9", "error", "exclusions entry for section 5.9.9 matches no caption") in report, report
    # v2.4 prints grammar examples with a title but no Status/Chapter header: still a caption.
    caps = ext.captions(_page(1, ["    QBP^Z73^QBP_Z73             QBP Message", "    MSH            Header"]))
    assert [c.structure for c in caps] == ["QBP_Z73"], caps


def check_footnotes_inside_table():
    # A footnote digit on a line of its own, and a row with no description whose right column
    # holds the chapter and a footnote number, are not prose (P8b-2a review: DFT_P03, OUL_R23).
    rows = [("MSH", "Header"), ("[{", "--- G begin"), ("PID", "Patient")]
    text = _page(1, _table("XYZ^X01^XYZ_X01", rows) + ["                  1",
                 "        [{ OBX }]                                                            7  2",
                 "    }]                        --- G end"], heading="9.1.1           XYZ - synthetic (Event X01)")
    structures, report, _ = _run("2.5.1", [("syn", text)])
    g = structures["XYZ_X01"]["elements"][1]
    assert [e["segment"] for e in g["elements"]] == ["PID", "OBX"], (g, report)


def check_group_mark_errata():
    rows = [("MSH", "Header"), ("{", "--- OBSERVATION begin"), ("OBX", "Obs"), ("}", "--- OMSERVATION end")]
    s, report = _structure(rows)
    assert s is None and "OMSERVATION end closes no group" in [r for r in report if r[1] == "skipped"][0][2], report
    fix = {**EMPTY, "errata": [{"version": "2.5.1", "where": "group-mark", "structure": "XYZ_X01",
                                "printed": "OMSERVATION", "intended": "OBSERVATION", "citation": "x"},
                               {"version": "2.5.1", "where": "group-mark", "structure": "XYZ_X01",
                                "printed": "NOWHERE", "intended": "SOMEWHERE", "citation": "x"}]}
    ext.validate_overrides(fix)
    text = _page(1, _table("XYZ^X01^XYZ_X01", rows), heading="9.1.1           XYZ - synthetic (Event X01)")
    structures, report, _ = _run("2.5.1", [("syn", text)], fix, full=True)
    assert structures["XYZ_X01"]["elements"][1]["group"] == "OBSERVATION", structures
    errors = [r[2] for r in report if r[1] == "error"]
    assert errors == ["errata entry (group-mark) 'NOWHERE' matches nothing"], errors


def check_bracket_split_and_group_of_a_group():
    # "[" and "{" on two lines open one optional repeating group; an unnamed bracket whose only
    # member is a printed group is that group, optional (P8b-2a review minors).
    s, _ = _structure([("MSH", "Header"), ("[", ""), ("{", "--- G begin"), ("PID", "Patient"), ("[PD1]", "Demo"),
                       ("}", "--- G end"), ("]", "")])
    g = s["elements"][1]
    assert (g["group"], g["min"], g["max"], len(g["elements"])) == ("G", 0, None, 2), g
    s, _ = _structure([("MSH", "Header"), ("[", ""), ("{", "--- OUTER begin"), ("[", "--- INNER begin"),
                       ("PID", "Patient"), ("[PD1]", "Demo"), ("]", "--- INNER end"), ("}", "--- OUTER end"), ("]", "")])
    outer = s["elements"][1]
    assert (outer["group"], outer["min"], outer["max"]) == ("OUTER", 0, None), outer
    assert [(e["group"], e["min"], e["max"]) for e in outer["elements"]] == [("INNER", 0, 1)], outer


def check_shared_triggers():
    one = _page(1, _table("ORM^O01^ORM_O01", [("MSH", "Header"), ("ORC", "Order")]), heading="4.1.1 ORM")
    two = _page(2, _table("ORM^O01^OMD_O01", [("MSH", "Header"), ("ODS", "Diet")]), heading="4.2.1 OMD")
    structures, report, _ = _run("2.3.1", [("syn", one + two)])
    assert ("ORM^O01", "shared-trigger", "OMD_O01, ORM_O01 (undeclared)") in report, report
    declared = {**EMPTY, "sharedTriggers": [
        {"version": "2.3.1", "trigger": "ORM^O01", "structures": ["ORM_O01", "OMD_O01"], "citation": "x"},
        {"version": "2.3.1", "trigger": "ORR^O02", "structures": ["ORR_O02", "ORD_O02"], "citation": "x"}]}
    _, report, _ = _run("2.3.1", [("syn", one + two)], declared, full=True)
    assert ("ORM^O01", "shared-trigger", "OMD_O01, ORM_O01 (declared)") in report, report
    assert ("ORR^O02", "error", "sharedTriggers entry no longer occurs") in report, report
    for bad in ({"version": "2.3.1", "trigger": "ORM^O01", "structures": ["ORM_O01"], "citation": "x"},):
        try:
            ext.validate_overrides({**EMPTY, "sharedTriggers": [bad]})
        except ext.OverridesError:
            continue
        raise AssertionError("a sharedTriggers entry with one structure must be rejected")


def check_0354_reconciliation():
    text = _page(1, _table("XYZ^X01^XYZ_X01", [("MSH", "Header")]) + _table("XYZ^X05^XYZ_X05", [("MSH", "Header")]),
                 heading="9.1.1           XYZ - synthetic (Event X01)")
    table = TABLE + [("XYZ_X09", [], "Deprecated and removed as of V2.7")]
    _, report, _ = _run("2.5.1", [("syn", text)], tables=table)
    rows = sorted((r[0], r[1]) for r in report if r[1].startswith("0354"))
    assert rows == [("ACK", "0354-missing-caption"), ("XYZ_X03", "0354-missing-caption"), ("XYZ_X05", "0354-missing-row"),
                    ("XYZ_X09", "0354-missing-caption")], rows
    assert [r for r in report if r[0] == "XYZ_X09"][0][2].endswith("(deprecated)"), report
    # A misprinted Table 0354 row is read through a cited table-0354 erratum.
    fix = {**EMPTY, "errata": [{"version": "2.5.1", "where": "table-0354", "structure": "XYZ_X05",
                                "printed": "XYZ__X05", "intended": "XYZ_X05", "citation": "x"}]}
    _, report, _ = _run("2.5.1", [("syn", text)], fix, tables=TABLE + [("XYZ__X05", ["X05"], "X05")], full=True)
    assert not [r for r in report if r[0] == "XYZ_X05" and r[1].startswith("0354")], report
    assert not [r for r in report if r[1] == "error"], report


def check_0354_triggers_merged():
    # P8b-11 fix-round ruling: a structure accepts every trigger Table 0354 of its version maps to
    # it, as well as the triggers its captions print; the added triggers are cited to Table 0354
    # and, where a section heading marks the event withdrawn, to that section. A "Varies" row adds
    # nothing; a borrowed table (v2.3 reads v2.3.1's) adds nothing.
    text = (_page(1, _table("XYZ^X01^XYZ_X01", [("MSH", "Header"), ("PID", "Patient")]),
                  heading="9.1.1           XYZ - synthetic (Event X01)")
            + _page(2, ["9.1.2           XYZ/ACK - synthetic [WITHDRAWN] (Event X02)"]))
    table = [("XYZ_X01", ["X01", "X02"], "X01, X02"), ("ACK", None, "Varies")]
    structures, report, _ = _run("2.5.1", [("syn", text)], tables=table, full=True)
    s = structures["XYZ_X01"]
    assert s["triggers"] == ["XYZ^X01", "XYZ^X02"], s["triggers"]
    assert "Table 0354 v2.5.1" in s["citation"] and "XYZ^X02" in s["citation"], s["citation"]
    assert "9.1.2" in s["citation"] and "withdrawn" in s["citation"], s["citation"]
    assert not [r for r in report if r[1] == "error"], report


def check_caption_errata():
    text = _page(1, ["    R0R^R0R                   Pharmacy Response                     Chapter"]
                 + _table("R0R^R0R", [("MSH", "Header")])[1:], heading="4.9.9 ROR - synthetic (Event ROR)")
    fix = {**EMPTY, "errata": [{"version": "2.3.1", "where": "caption", "structure": "ROR_ROR",
                                "printed": "R0R^R0R", "intended": "ROR^ROR", "citation": "x"}]}
    structures, report, _ = _run("2.3.1", [("syn", text)], fix, tables=[("ROR_ROR", ["ROR"], "ROR")], full=True)
    assert structures["ROR_ROR"]["triggers"] == ["ROR^ROR"], (structures, report)
    for broken in ({**fix["errata"][0], "where": "anywhere"}, {**fix["errata"][0], "intended": "R0R^R0R"}):
        try:
            ext.validate_overrides({**EMPTY, "errata": [broken]})
        except ext.OverridesError:
            continue
        raise AssertionError(f"errata entry {broken} must be rejected")


def check_reader_layouts():
    # Page-foot footnotes (a left-margin digit, then text, up to the footer) are furniture
    # (v2.5.1 DFT_P03); a wrapped "--- NAME" / "begin" mark is one mark (SQM_S25); "End" is
    # "end" (CSU_C09); a v2.4 Group Control column entry leaves the row a row (RSP_K21); a
    # non-notation row at depth 0 ends the table (RSP_K23's QPD field table follows it).
    first = _page(1, _table("XYZ^X01^XYZ_X01", [("MSH", "Header"), ("[{", "--- G begin"), ("PID", "Patient")])
                  + ["1", "     If included here, the data is global to the message, and this note runs on."],
                  heading="9.1.1           XYZ - synthetic (Event X01)")
    second = _page(2, _table("XYZ^X01^XYZ_X01", [("}]", "--- G End"), ("{", "--- RESPONSE"), ("", "begin"),
                                                 ("PV1", "Visit")])
                   + ["    [                                                         Query Result",
                      "      [PV2]                     Visit 2",
                      "    ]                                                         End Query",
                      "    }                         --- RESPONSE end",
                      "    Field      Field Name       Key/       Sort    LEN"])
    structures, report, _ = _run("2.5.1", [("syn", first + second)])
    s = structures.get("XYZ_X01")
    assert s, report
    assert [e.get("segment") or e["group"] for e in s["elements"]] == ["MSH", "G", "RESPONSE"], s["elements"]
    assert [e.get("segment") or e["group"] for e in s["elements"][2]["elements"]] == ["PV1", "PV2"], s["elements"]
    # A group mark whose name holds a space is never silently dropped: unreadable without an erratum.
    s, report = _structure([("MSH", "Header"), ("[", "--- PATIENT VISIT begin"), ("PV1", "Visit"),
                            ("]", "--- PATIENT VISIT end")])
    assert s is None and "group mark not read" in [r for r in report if r[1] == "skipped"][0][2], report


def check_borrowed_table_errata():
    # v2.3 resolves through v2.3.1's Table 0354, so that table's own errata apply to it.
    text = _page(1, ["    XYZ                       Synthetic Message                     Chapter"]
                 + _table("XYZ", [("MSH", "Header")])[1:], heading="9.2.1 XYZ - synthetic (event X07)")
    fix = {**EMPTY, "errata": [{"version": "2.3.1", "where": "table-0354", "structure": "XYZ_X07",
                                "printed": "XYZ__X07", "intended": "XYZ_X07", "citation": "x"}]}
    structures, report, _ = _run("2.3", [("syn", text)], fix, tables=[("XYZ__X07", ["X07"], "X07")])
    assert structures["XYZ_X07"]["triggers"] == ["XYZ^X07"], (structures, report)


def check_conformance_print_never_primary():
    # P8b-3b: a CH02B (2.B.x) message-profile print is never primary, even when it carries the
    # defining caption and comes first; with only CH02B prints the structure is an error.
    profile = _page(1, _table("ADT^A01^ADT_A01", [("MSH", "Header"), ("PV1", "Visit")]), heading="2.B.8 Static definition")
    normative = _page(2, _table("ADT^A01^ADT_A01", [("MSH", "Header"), ("PID", "Patient")]), heading="3.3.1 ADT")
    structures, report, _ = _run("2.5.1", [("V271_CH02B_Conformance.pdf", profile), ("CH03", normative)])
    assert [e["segment"] for e in structures["ADT_A01"]["elements"]] == ["MSH", "PID"], structures
    assert structures["ADT_A01"]["citation"].startswith("HL7 v2.5.1 Chapter 3, section 3.3.1"), structures
    structures, report, _ = _run("2.5.1", [("V271_CH02B_Conformance.pdf", profile)])
    assert "ADT_A01" not in structures and ("ADT_A01", "error",
                                            "only Conformance-chapter (CH02B) prints: exclude them (ruling G7)") in report, report


def check_general_ack_fold_code_alone():
    # v2.3.1 (and v2.3): CH02 prints the general acknowledgment under the code ACK alone and
    # Table 0354 has no ACK row; a triggerFolds entry onto ACK^* reads it and every ACK^<event>
    # caption as structure ACK. A fold that matches no caption is stale on a full read.
    fold = {**EMPTY, "triggerFolds": [{"version": v, "structure": "ACK", "trigger": "ACK^*", "primary": "ACK",
                                       "citation": "x"} for v in ("2.3", "2.3.1")]}
    general = _page(1, ["    ACK                       General Acknowledgement               Chapter"]
                    + _table("ACK", [("MSH", "Header"), ("MSA", "Ack"), ("[ ERR ]", "Error")])[1:],
                    heading="2.13.1 ACK - general acknowledgment")
    other = _page(2, ["    ACK^X02                   General Acknowledgment                Chapter"]
                  + _table("ACK^X02", [("MSH", "Header"), ("MSA", "Ack")])[1:], heading="9.1.2 XYZ (Event X02)")
    for version in ("2.3.1", "2.3"):
        structures, report, count = _run(version, [("CH02", general), ("CH09", other)], fold, tables=TABLE[:2], full=True)
        s = structures["ACK"]
        assert s["triggers"] == ["ACK^*"] and [e["segment"] for e in s["elements"]] == ["MSH", "MSA", "ERR"], (version, s)
        assert s["citation"].startswith(f"HL7 v{version} Chapter 2, section 2.13.1"), s["citation"]
        assert not [r for r in report if r[1] in ("needs-event", "needs-structure-id", "error")], (version, report)
    _, report, _ = _run("2.3.1", [("CH09", _page(1, ["x"]))], fold, tables=TABLE[:2], full=True)
    assert ("ACK", "error", "triggerFolds entry matches no caption") in report, report
    # Without the fold the code-alone caption is not read on v2.3.1 (no event, no 0354 row).
    _, report, count = _run("2.3.1", [("CH02", general)], tables=TABLE[:2])
    assert count == 0, report


def check_empty_or_run_on_print_unreadable():
    # P8b-3b: a caption with no syntax rows, or rows that run on into the next table (a second
    # MSH at top level), is skipped as unreadable, never a parsed structure.
    s, report = _structure([("MSH", "Header"), ("PID", "Patient"), ("MSH", "Header"), ("MSA", "Ack")])
    assert s is None and "second top-level MSH" in [r for r in report if r[1] == "skipped"][0][2], report
    text = _page(1, _table("XYZ^X01^XYZ_X01", []) + ["", "Prose that follows the caption."],
                 heading="9.1.1           XYZ - synthetic (Event X01)")
    structures, report, _ = ext.extract_version("2.5.1", [("syn", text)], EMPTY, tables=[])
    assert "XYZ_X01" not in structures and [r for r in report if r[1] == "skipped"], report


def check_caption_wrapping_its_id():
    # P8b-9: the event list or structure ID wraps onto the next line, the title staying on the
    # first (v2.5.1 SIU^S12-S24, / S26^SIU_S12; PPG^PCG,PCH,PCJ^PPG_ / PCG), and the page-break
    # repeat wraps the same way; a "S12-S24, S26" event list (comma and space) is one caption.
    body = ["    XYZ^X01-X03,              Synthetic Message        Status    Chapter",
            "    X05^XYZ_X01",
            "    MSH                       Header",
            "    [{                        --- G begin",
            "        PID                   Patient"]
    more = ["    XYZ^X01-X03,              Synthetic Message        Status    Chapter",
            "    X05^XYZ_X01",
            "    }]                        --- G end",
            "    ACK^X01-X03, X05^ACK      General Acknowledgment   Status    Chapter",
            "    MSH                       Header"]
    text = _page(1, body, heading="9.1.1           XYZ - synthetic (Events X01-X03, X05)") + _page(2, more)
    caps = ext.captions(text)
    assert [(c.structure, c.events) for c in caps] == [("XYZ_X01", ["X01", "X02", "X03", "X05"]),
                                                       ("XYZ_X01", ["X01", "X02", "X03", "X05"]),
                                                       ("ACK", ["X01", "X02", "X03", "X05"])], caps
    rows = ext.syntax_rows(text, caps[0])
    assert [r.left for r in rows] == ["MSH", "[{", "PID", "}]"], [r.left for r in rows]
    assert caps[0].repeats == [caps[1].line], (caps[0].repeats, caps[1].line)
    text = _page(1, ["    XYZ^X01^XYZ_              Synthetic Message        Status    Chapter",
                     "    X01", "    MSH                       Header"])
    assert [c.structure for c in ext.captions(text)] == ["XYZ_X01"], ext.captions(text)


def check_grid_row_not_a_caption():
    # P8b-9: v2.5.1 CH05 5.10.3 prints a query/response grid ("EQQ^Q04   TBR^R08   Tabular");
    # a two-part "caption" whose title is itself CODE^EVT is a grid row, never a caption.
    text = _page(1, ["        XYZ^X01         ABC^X02           Tabular        valid"])
    assert ext.captions(text) == [], ext.captions(text)


def check_repeat_indented_past_caption():
    # P8b-9: v2.5.1 ADT^A31^ADT_A05 prints its page-break repeat three columns right of the
    # caption and the rows after it left of both; the rows still belong to the table.
    text = _page(1, ["     XYZ^X01^XYZ_X01          Synthetic Message        Status    Chapter",
                     "    MSH                       Header"]) + \
        _page(2, ["        XYZ^X01^XYZ_X01      Synthetic Message        Status    Chapter",
                  "    PID                       Patient"])
    caps = ext.captions(text)
    rows = ext.syntax_rows(text, caps[0])
    assert [r.left for r in rows] == ["MSH", "PID"], [r.left for r in rows]


def check_group_close_erratum():
    # P8b-9: v2.5.1 MDM_T02 prints "--- COMMON_ORDER end" with no "}]"; unreadable unless a
    # cited group-close erratum supplies the cell, and a stale one is an error.
    rows = [("MSH", "Header"), ("[{", "--- G begin"), ("ORC", "Order"), ("", "--- G end"), ("TXA", "Doc")]
    s, report = _structure(rows)
    assert s is None and "never closed" in [r for r in report if r[1] == "skipped"][0][2], report
    fix = {**EMPTY, "errata": [{"version": "2.5.1", "where": "group-close", "structure": "XYZ_X01",
                                "printed": "--- G end", "intended": "}]", "citation": "x"},
                               {"version": "2.5.1", "where": "group-close", "structure": "XYZ_X01",
                                "printed": "--- H end", "intended": "}]", "citation": "x"}]}
    ext.validate_overrides(fix)
    text = _page(1, _table("XYZ^X01^XYZ_X01", rows), heading="9.1.1           XYZ - synthetic (Event X01)")
    structures, report, _ = _run("2.5.1", [("syn", text)], fix, full=True)
    els = structures["XYZ_X01"]["elements"]
    assert [(e.get("segment") or e.get("group"), e["min"], e["max"]) for e in els] == \
        [("MSH", 1, 1), ("G", 0, None), ("TXA", 1, 1)], els
    errors = [r[2] for r in report if r[1] == "error"]
    assert errors == ["errata entry (group-close) '--- H end' matches nothing"], errors


def check_primary_print_override():
    # P8b-9 ruling: two normative prints of one structure ID that disagree; a cited
    # primaryPrints entry makes the looser one primary (cited), and a stale entry is an error.
    strict = [("MSH", "Header"), ("[", "--- R begin"), ("PID", "Patient"), ("QRI", "Q"), ("]", "--- R end")]
    loose = [("MSH", "Header"), ("[{", "--- R begin"), ("PID", "Patient"), ("[QRI]", "Q"), ("}]", "--- R end")]
    text = (_page(1, _table("XYZ^X01^XYZ_X01", strict), heading="9.1.1           XYZ - synthetic (Event X01)")
            + _page(2, _table("XYZ^X02^XYZ_X01", loose), heading="9.1.2           XYZ - synthetic (Event X02)"))
    structures, report, _ = _run("2.5.1", [("syn", text)], full=True)
    assert structures["XYZ_X01"]["elements"][1]["max"] == 1, structures
    fix = {**EMPTY, "primaryPrints": [{"version": "2.5.1", "structure": "XYZ_X01", "primary": "XYZ^X02^XYZ_X01",
                                       "stricter": "XYZ^X01^XYZ_X01", "citation": "Looser print primary (synthetic)."}]}
    ext.validate_overrides(fix)
    structures, report, _ = _run("2.5.1", [("syn", text)], fix, full=True)
    s = structures["XYZ_X01"]
    assert (s["elements"][1]["min"], s["elements"][1]["max"]) == (0, None), s
    assert "Looser print primary (synthetic)." in s["citation"] and "9.1.2" in s["citation"], s["citation"]
    assert any(r[1] == "duplicate-differs" for r in report), report
    stale = {**EMPTY, "primaryPrints": [{**fix["primaryPrints"][0], "primary": "XYZ^X09^XYZ_X01"}]}
    _, report, _ = _run("2.5.1", [("syn", text)], stale, full=True)
    assert [r[2] for r in report if r[1] == "error"] == ["primaryPrints entry 'XYZ^X09^XYZ_X01' / 'XYZ^X01^XYZ_X01' "
                                                         "matches no print"], report


def check_union_prints():
    # P8b-10 ruling (v2.6 RSP_K21): two incomparable normative prints of one ID; a cited
    # unionPrints entry aligns them by segment or group name: per element the lesser min and the
    # greater max; an element in one print only is optional. Prints that do not align are an error
    # and the structure stays unmodelled; a stale entry is an error.
    k21 = [("MSH", "Header"), ("[", "--- R begin"), ("PID", "Patient"), ("[{ARV}]", "Access"), ("QRI", "Q"),
           ("]", "--- R end"), ("[DSC]", "Continuation")]
    k22 = [("MSH", "Header"), ("[{", "--- R begin"), ("PID", "Patient"), ("[QRI]", "Q"), ("}]", "--- R end"),
           ("[DSC]", "Continuation")]
    text = (_page(1, _table("XYZ^X01^XYZ_X01", k21), heading="9.1.1           XYZ - synthetic (Event X01)")
            + _page(2, _table("XYZ^X02^XYZ_X01", k22), heading="9.1.2           XYZ - synthetic (Event X02)"))
    fix = {**EMPTY, "unionPrints": [{"version": "2.5.1", "structure": "XYZ_X01",
                                     "prints": ["XYZ^X01^XYZ_X01", "XYZ^X02^XYZ_X01"],
                                     "citation": "Union of two incomparable prints (synthetic)."}]}
    ext.validate_overrides(fix)
    structures, report, _ = _run("2.5.1", [("syn", text)], fix, full=True)
    s = structures["XYZ_X01"]
    assert ext.compact(s["elements"]) == "MSH [{R: PID [{ARV}] [QRI]}] [DSC]", ext.compact(s["elements"])
    assert s["triggers"] == ["XYZ^X01", "XYZ^X02"] and "Union of two" in s["citation"], s
    assert not any(r[1] in ("duplicate-differs", "error") for r in report), report
    assert any(r[1] == "union" for r in report), report
    # A group in one print where the other prints a segment, or a different order: not aligned.
    swapped = [("MSH", "Header"), ("[{", "--- R begin"), ("[QRI]", "Q"), ("PID", "Patient"), ("}]", "--- R end")]
    text2 = (_page(1, _table("XYZ^X01^XYZ_X01", k21), heading="9.1.1           XYZ - synthetic (Event X01)")
             + _page(2, _table("XYZ^X02^XYZ_X01", swapped), heading="9.1.2           XYZ - synthetic (Event X02)"))
    structures, report, _ = _run("2.5.1", [("syn", text2)], fix, full=True)
    assert "XYZ_X01" not in structures, structures
    assert any(r[1] == "error" and "do not align" in r[2] for r in report), report
    stale = {**EMPTY, "unionPrints": [{**fix["unionPrints"][0], "prints": ["XYZ^X01^XYZ_X01", "XYZ^X09^XYZ_X01"]}]}
    _, report, _ = _run("2.5.1", [("syn", text)], stale, full=True)
    assert any(r[1] == "error" and "unionPrints entry" in r[2] for r in report), report
    bad = {**EMPTY, "unionPrints": [{**fix["unionPrints"][0], "prints": ["XYZ^X01^XYZ_X01"]}]}
    try:
        ext.validate_overrides(bad)
        raise AssertionError("a unionPrints entry with one print validated")
    except ext.OverridesError:
        pass


def check_bracketless_named_group():
    # P8b-10 (v2.6 CH16 EHC_E01): "--- NAME begin" ... "--- NAME end" on rows with an empty syntax
    # cell is a required, non-repeating named group (CH02 2.5.2), not merged into the brackets it
    # holds; a misprinted end mark is read only through a cited group-mark erratum.
    rows = [("MSH", "Header"), ("", "--- INFO begin"), ("IVC", "Invoice"), ("[ { CTD } ]", "Contact"),
            ("", "--- INFO end"), ("[ NTE ]", "Note")]
    s, report = _structure(rows)
    els = s["elements"]
    assert [(e.get("segment") or e.get("group"), e["min"], e["max"]) for e in els] == \
        [("MSH", 1, 1), ("INFO", 1, 1), ("NTE", 0, 1)], els
    assert els[1]["nameSource"] == "printed" and [e["segment"] for e in els[1]["elements"]] == ["IVC", "CTD"], els
    only = [("MSH", "Header"), ("", "--- INFO begin"), ("[ {", "--- INNER begin"), ("CTD", "Contact"),
            ("} ]", "--- INNER end"), ("", "--- INFO end")]
    s, _ = _structure(only)
    assert (s["elements"][1]["group"], s["elements"][1]["min"]) == ("INFO", 1), s["elements"]
    assert s["elements"][1]["elements"][0]["group"] == "INNER", s["elements"]
    bad = [("MSH", "Header"), ("", "--- INFO begin"), ("IVC", "Invoice"), ("", "--- INFO X end")]
    s, report = _structure(bad)
    assert s is None and "group mark not read" in [r for r in report if r[1] == "skipped"][0][2], report
    fix = {**EMPTY, "errata": [{"version": "2.5.1", "where": "group-mark", "structure": "XYZ_X01",
                                "printed": "INFO X", "intended": "INFO", "citation": "x"}]}
    s, _ = _structure(bad, overrides=fix)
    assert s["elements"][1]["group"] == "INFO", s


def check_no_bar_choice_is_named_required_group():
    # P8b-6 ruling, applied in P8b-10: "< SDD [{SCD}] >" with a name and no "|" is a NAMED REQUIRED
    # GROUP (min 1, max 1); unnamed, it stays unreadable (no name and no choice to read).
    rows = [("MSH", "Header"), ("<", "--- DEVICE begin"), ("SDD", "Device"), ("[{SCD}]", "Cycle"),
            (">", "--- DEVICE end")]
    s, _ = _structure(rows)
    g = s["elements"][1]
    assert (g["group"], g["nameSource"], g["min"], g["max"]) == ("DEVICE", "printed", 1, 1), g
    assert "alternatives" not in g and [e["segment"] for e in g["elements"]] == ["SDD", "SCD"], g
    s, report = _structure([("MSH", "Header"), ("<", ""), ("SDD", "Device"), (">", "")])
    assert s is None and "needs a ruling" in [r for r in report if r[1] == "skipped"][0][2], report


def check_syntax_cell_erratum():
    # P8b-10 (v2.6 EHC_E12 '{ [ CTD } ]', BRP_O30 '] --- RESPONSE end' closing one of two open
    # groups): a cited syntax-cell erratum corrects the cell; the description may not change, and a
    # stale entry is an error.
    rows = [("MSH", "Header"), ("{ [ CTD } ]", "Contact Data"), ("IVC", "Invoice")]
    s, report = _structure(rows)
    assert s is None and "unbalanced" in [r for r in report if r[1] == "skipped"][0][2], report
    fix = {**EMPTY, "errata": [{"version": "2.5.1", "where": "syntax-cell", "structure": "XYZ_X01",
                                "printed": "{ [ CTD } ] Contact Data", "intended": "[ { CTD } ] Contact Data",
                                "citation": "x"},
                               {"version": "2.5.1", "where": "syntax-cell", "structure": "XYZ_X01",
                                "printed": "] Gone", "intended": "] ] Gone", "citation": "x"}]}
    ext.validate_overrides(fix)
    text = _page(1, _table("XYZ^X01^XYZ_X01", rows), heading="9.1.1           XYZ - synthetic (Event X01)")
    structures, report, _ = _run("2.5.1", [("syn", text)], fix, full=True)
    ctd = structures["XYZ_X01"]["elements"][1]
    assert (ctd["segment"], ctd["min"], ctd["max"]) == ("CTD", 0, None), ctd
    assert [r[2] for r in report if r[1] == "error"] == ["errata entry (syntax-cell) '] Gone' matches nothing"], report
    renamed = {**EMPTY, "errata": [{**fix["errata"][0], "intended": "[ { CTD } ] Contact"}]}
    s, report = _structure(rows, overrides=renamed)
    assert s is None and "changes the description" in [r for r in report if r[1] == "skipped"][0][2], report


def check_v24_reader_layouts():
    # P8b-13 (v2.4): a footnote mark fused to a bracket ('[{1', '}]3'; CH06 DFT_P03) is dropped; a
    # bracket-only cell drifted into the description column (CH11 RQA_I08 ']') is syntax; a
    # 'CODE^EVT' row at depth 0 (CH05 DSR^Q03 then 'ACK^Q03 (A to B)') ends the table.
    s, report = _structure([("MSH", "Header"), ("[{1", ""), ("OBR", "Order"), ("[{ NTE }]", "Notes"), ("}]3", ""), ("[{ DG1 }]6", "Diagnosis")])
    assert s, report
    assert [e.get("segment") or e["group"] for e in s["elements"]] == ["MSH", "OBR_GROUP", "DG1"], s["elements"]
    assert (s["elements"][1]["min"], s["elements"][1]["max"]) == (0, None), s["elements"][1]
    s, report = _structure([("MSH", "Header"), ("[", ""), ("PV1", "Visit"), ("[PV2]", "Visit 2"), ("", "]"),
                            ("EVN", "Event")])
    assert s, report
    assert [e.get("segment") or e["group"] for e in s["elements"]] == ["MSH", "PV1_GROUP", "EVN"], s["elements"]
    s, report = _structure([("MSH", "Header"), ("PID", "Patient"), ("ACK^X01 (A to B)", "General Acknowledgment"),
                            ("MSH", "Header"), ("MSA", "Ack")])
    assert s, report
    assert [e["segment"] for e in s["elements"]] == ["MSH", "PID"], s["elements"]


def check_syntax_cell_erratum_occurrence():
    # P8b-13 (v2.4 CH04 OML_O21): the print closes a '{' group with ']', and ']' recurs in the
    # print; "occurrence" narrows the erratum to the n-th such row. It is valid on syntax-cell
    # errata only.
    rows = [("MSH", "Header"), ("[", ""), ("PID", "Patient"), ("[PD1]", "Demographics"), ("]", ""), ("{", ""),
            ("PV1", "Visit"), ("[PV2]", "Visit 2"), ("]", "")]
    s, report = _structure(rows)
    assert s is None and "unbalanced" in [r for r in report if r[1] == "skipped"][0][2], report
    entry = {"version": "2.5.1", "where": "syntax-cell", "structure": "XYZ_X01", "printed": "]", "intended": "}",
             "occurrence": 2, "citation": "x"}
    fix = {**EMPTY, "errata": [entry]}
    ext.validate_overrides(fix)
    s, report = _structure(rows, overrides=fix)
    assert s, report
    assert [(e["group"], e["min"], e["max"]) for e in s["elements"][1:]] == \
        [("PID_GROUP", 0, 1), ("PV1_GROUP", 1, None)], s["elements"]
    for bad in ({**entry, "occurrence": 0}, {**entry, "where": "caption"}):
        try:
            ext.validate_overrides({**EMPTY, "errata": [bad]})
        except ext.OverridesError:
            continue
        raise AssertionError(f"accepted {bad}")


def check_bundle_name_no_group_can_hold():
    # P8b-13 (HL7-xml v2.4/RCI_I05.xsd names a group 'c'): a bundle name that is no valid group name
    # is a bundle defect; without a cited groupNames override the print is unreadable, with one the
    # override names the group (nameSource override).
    b = _bundles("2.5.1", {"XYZ_X01": _xsd("XYZ_X01", "XYZ_X01: MSH 1 1, XYZ_X01.c 0 1; XYZ_X01.c: PV1 1 1, PV2 0 1")})
    text = _page(1, _table("XYZ^X01^XYZ_X01", VISIT_ROWS), heading="9.1.1           XYZ - synthetic (Event X01)")
    structures, report, _ = ext.extract_version("2.5.1", [("syn", text)], EMPTY, bundles=b)
    assert "XYZ_X01" not in structures, structures
    assert any(r[1] == "skipped" and "no group name can hold" in r[2] for r in report), report
    named = copy.deepcopy(EMPTY)
    named["groupNames"].append({"version": "2.5.1", "structure": "XYZ_X01", "path": [1], "name": "VISIT", "citation": "x"})
    structures, report, _ = ext.extract_version("2.5.1", [("syn", text)], named, bundles=b)
    g = structures["XYZ_X01"]["elements"][1]
    assert (g["group"], g["nameSource"]) == ("VISIT", "override"), g
    assert not [r for r in report if r[1] == "error"], report


def check_caption_scoped_exclusion():
    # P8b-10 (CH08 8.4.3): an exclusion with "caption" drops only that caption of the section (the
    # MFN_Znn template); the section's normative acknowledgment stays read; a caption never seen
    # is a stale entry.
    body = (_table("XYZ^X99^XYZ_Znn", [("MSH", "Header"), ("PID", "Patient")])
            + _table("ACK^X99^ACK", [("MSH", "Header"), ("MSA", "Ack")]))
    text = _page(1, body, heading="9.1.3           XYZ - site defined (Event X99)")
    rule = {**EMPTY, "exclusions": [{"version": "2.5.1", "section": "9.1.3", "caption": "XYZ^X99^XYZ_Znn",
                                     "citation": "x"}]}
    ext.validate_overrides(rule)
    structures, report, _ = _run("2.5.1", [("syn", text)], rule)
    assert "ACK" in structures and not any(k.startswith("XYZ") for k in structures), sorted(structures)
    assert any(r[1] == "excluded" and "XYZ^X99^XYZ_Znn" in r[2] for r in report), report
    stale = {**EMPTY, "exclusions": [{**rule["exclusions"][0], "caption": "XYZ^X98^XYZ_Znn"}]}
    _, report, _ = _run("2.5.1", [("syn", text)], stale, full=True)
    assert any(r[1] == "error" and "9.1.3" in r[0] for r in report), report


def check_first_row_left_of_caption():
    # P8b-10 (v2.6 ADT^A31^ADT_A05 at 3.3.31): the caption at column 7, its rows from column 3; the
    # MSH row sets the column. Any other row that far left still ends the table.
    lines = ["\fChapter 9: Synthetic", "9.1.1           XYZ - synthetic (Event X01)",
             "          XYZ^X01^XYZ_X01             Synthetic Message        Status    Chapter",
             "   MSH                                Header", "   PID                                Patient",
             "Page 9-1            Health Level Seven, Version 2.5.1 (c) 2007. All rights reserved."]
    structures, report, _ = _run("2.5.1", [("syn", lines)])
    assert [e["segment"] for e in structures["XYZ_X01"]["elements"]] == ["MSH", "PID"], report
    lines[3] = "   PID                                Patient"
    structures, report, _ = _run("2.5.1", [("syn", lines)])
    assert "XYZ_X01" not in structures, structures


CHECKS = [check_ack_golden, check_adt_a01_golden, check_oru_r01_golden, check_brace_bracket_normalisation,
          check_two_level_group, check_optional_repeating_group, check_page_break_footer_inside_table,
          check_wrapped_caption, check_unnamed_group_override_or_synthesised, check_choice_inline,
          check_choice_one_per_row, check_choice_separate_rows_and_placeholder, check_choice_named,
          check_choice_of_segment_groups, check_choice_malformed, check_choice_bundle_cross_check,
          check_unknown_notation, check_overrides_validation, check_excluded_section, check_eras_cover_chapters,
          check_bundle_reader_tree, check_bundle_names_group_by_path_and_members,
          check_bundle_mismatch_not_resolved_by_position, check_derivation_through_v24, check_synthesised_fallback,
          check_bundle_differs_report_only, check_override_shadowed_by_bundle, check_name_source_validation,
          check_bundle_maps, check_caret_colon_caption, check_event_ranges,
          check_two_part_caption_through_0354, check_section_title_caption, check_primary_print_and_duplicates,
          check_excluded_print_never_primary, check_footnotes_inside_table, check_group_mark_errata,
          check_bracket_split_and_group_of_a_group, check_shared_triggers, check_0354_reconciliation,
          check_caption_errata, check_reader_layouts,
          check_borrowed_table_errata, check_conformance_print_never_primary, check_general_ack_fold_code_alone,
          check_empty_or_run_on_print_unreadable, check_caption_wrapping_its_id, check_grid_row_not_a_caption,
          check_repeat_indented_past_caption, check_group_close_erratum, check_primary_print_override,
          check_bracketless_named_group, check_no_bar_choice_is_named_required_group, check_syntax_cell_erratum,
          check_first_row_left_of_caption, check_caption_scoped_exclusion, check_union_prints,
          check_colon_caption_with_space_ends_table, check_v282_reader_layouts, check_v271_reader_layouts,
          check_0354_triggers_merged, check_v24_reader_layouts, check_syntax_cell_erratum_occurrence,
          check_bundle_name_no_group_can_hold]


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
