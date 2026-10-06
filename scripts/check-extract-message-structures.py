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
         "triggerFolds": [], "primaryPrints": [], "unionPrints": [], "unresolvedCaptions": [],
         "captionStructures": [], "eventsFromTitle": [], "referencedTriggers": [], "withdrawnSegments": [],
         "keyedChoices": [], "aliases": [], "errorResponses": []}

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
    # "etc." in place of the last alternative (CH12's "< OBR | etc. >") is the open order detail:
    # one slot in place of the whole choice (S3-2; check_slot_choice_with_placeholder).
    s, report = _structure([("MSH", "Header"), ("<", ""), ("OBR", "Order Detail Segment"), ("|", ""),
                            ("", "etc."), (">", "")])
    assert s and "slot" in s["elements"][1], (s, report)
    assert not [r for r in report if r[1] == "skipped"], report
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
    assert "1 v2xml, 0 v2xml-v2.3.1, 0 v2xml-v2.4, 0 synthesised, 0 override; 1 bundle-differs" in ext.name_summary("2.5.1", report), \
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
    # P8b-15: v2.3 derives through the v2.3.1 bundle, then v2.4; the citation names both misses.
    elements, log = _named(rows, "2.3", "XYZ_X01", ext.Bundles({"2.3.1": {}, "2.4": {}}))
    assert [(e["name"], e["source"]) for e in log] == [("PV1_GROUP", "synthesised"), ("PV1_GROUP2", "synthesised")], log
    assert log[0]["cite"] == ("synthesised: HL7-xml 2.3.1 has no XYZ_X01.xsd and no XYZ_*.xsd group matches; "
                              "HL7-xml v2.4 has no XYZ_X01.xsd and no XYZ_*.xsd group matches"), log[0]
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
    assert ext.NAME_SOURCES == ("printed", "override", "v2xml", "v2xml-v2.3.1", "v2xml-v2.4", "synthesised")


def check_bundle_maps():
    # P8b-14: v2.3.1 has its own bundle (folder "HL7-xml 2.3.1", no "v") and keeps the v2.4
    # derivation as its fallback; v2.3 has no bundle.
    assert set(ext.BUNDLES) == {"v2.3.1", "v2.4", "v2.5.1", "v2.6", "v2.7.1", "v2.8.2"}, ext.BUNDLES
    assert ext.BUNDLES["v2.3.1"] == "HL7-xml 2.3.1", ext.BUNDLES
    # P8b-15: v2.3 derives through the v2.3.1 bundle first, then v2.4 (controller carry-in).
    assert ext.BUNDLES_DERIVED == {"v2.3": ("v2.3.1", "v2.4"), "v2.3.1": ("v2.4",)}, ext.BUNDLES_DERIVED
    assert set(ext.BUNDLES) | set(ext.BUNDLES_DERIVED) == set(ext.ERAS)


def _xsd_encoder(sid, spec):
    """A SYNTHETIC structure schema in the style of the v2.3.1 bundle's encoder-generated files
    (urn:com.sun:encoder-hl7-1.0): one element per line, an encoder appinfo annotation on the
    schema and on the message element. Same spec grammar as _xsd. Never bundle text (ruling D4)."""
    out = ['<?xml version ="1.0" encoding="UTF-8"?>', f"<!-- synthetic fragment for {sid}, encoder style -->",
           '<xsd:schema', '    xmlns:xsd="http://www.w3.org/2001/XMLSchema"', '    xmlns="urn:hl7-org:v2xml"',
           '    xmlns:hl7="urn:com.sun:encoder-hl7-1.0"',
           '    targetNamespace="urn:hl7-org:v2xml" xmlns:jaxb="http://java.sun.com/xml/ns/jaxb" jaxb:version="2.0">',
           '    <xsd:include schemaLocation="segments.xsd"/>',
           '    <xsd:annotation><xsd:appinfo source="urn:com.sun:encoder">',
           '        <encoding xmlns="urn:com.sun:encoder" name="synthetic" namespace="urn:com.sun:encoder-hl7-1.0"/>',
           '    </xsd:appinfo></xsd:annotation>']
    for part in reversed(spec.split(";")):     # groups first, the message type last, as the encoder writes
        head, refs = part.split(":", 1)
        name, _, kind = head.strip().partition(" ")
        tag = "choice" if kind == "choice" else "sequence"
        out += [f'    <xsd:complexType name="{name}.CONTENT">', f"        <xsd:{tag}>"]
        out += [f'            <xsd:element ref="{r}" minOccurs="{lo}" maxOccurs="{hi}"/>'
                for r, lo, hi in (item.split() for item in refs.split(","))]
        out += [f"        </xsd:{tag}>", "    </xsd:complexType>"]
        if name == sid:
            out += [f'    <xsd:element name="{name}" type="{name}.CONTENT">',
                    '        <xsd:annotation><xsd:appinfo source="urn:com.sun:encoder">',
                    '            <top xmlns="urn:com.sun:encoder">true</top>',
                    '        </xsd:appinfo></xsd:annotation>', "    </xsd:element>"]
        else:
            out.append(f'    <xsd:element name="{name}" type="{name}.CONTENT"/>')
    return "\n".join(out + ["</xsd:schema>"])


def check_v231_bundle_encoder_style():
    # P8b-14 (owner ruling 2026-10-04): the v2.3.1 bundle mixes two generators. The reader parses the
    # encoder style to the same tree as the HL7-Database style, and names each file's generator.
    spec = "XYZ_X01: MSH 1 1, XYZ_X01.VISIT 0 1, XYZ_X01.CHOICE 1 unbounded;" \
           "XYZ_X01.VISIT: PV1 1 1, PV2 0 1; XYZ_X01.CHOICE choice: OBR 1 1, RQD 1 1"
    assert ext.read_bundle(_xsd_encoder("XYZ_X01", spec), "XYZ_X01") == ext.read_bundle(_xsd("XYZ_X01", spec), "XYZ_X01")
    gen = ext._v2xml.generator
    assert gen(_xsd_encoder("XYZ_X01", spec)) == "urn:com.sun:encoder-hl7-1.0", gen(_xsd_encoder("XYZ_X01", spec))
    database = _xsd("XYZ_X01", spec).replace("?>", "?><!-- synthetic, generated by HL7-Database -->", 1)
    assert gen(database) == "HL7-Database", gen(database)
    assert gen(_xsd("XYZ_X01", spec)) == "an unnamed generator", gen(_xsd("XYZ_X01", spec))


def check_v231_names_bundle_then_v24_then_synthesised():
    # P8b-14 ruling: a v2.3.1 group takes its own bundle's name (v2xml, the citation naming the file
    # and its generator), else the D2 derivation through v2.4 (v2xml-v2.4), else <SEG>_GROUP. The
    # v2.3.1 bundle's CHOICE is refused without a cited override: the derivation (or an override)
    # names that group, and the citation says why. ENCODING is a genuine group name there (RXE
    # {RXR} [{RXC}], as in every later bundle) and is taken (fix round 1: refusal withdrawn).
    rows = ["MSH", "[", "PV1", "[PV2]", "]", "[", "{", "IN1", "[IN2]", "}", "]", "[", "RXE", "{RXR}", "]",
            "[", "NK1", "AL1", "]"]
    own = _xsd_encoder("XYZ_X01", "XYZ_X01: MSH 1 1, XYZ_X01.VISIT 0 1, XYZ_X01.ENCODING 0 1, XYZ_X01.CHOICE 0 1;"
                                  "XYZ_X01.VISIT: PV1 1 1, PV2 0 1; XYZ_X01.ENCODING: RXE 1 1, RXR 1 unbounded;"
                                  "XYZ_X01.CHOICE: NK1 1 1, AL1 1 1")
    v24 = _xsd("XYZ_X01", "XYZ_X01: MSH 1 1, XYZ_X01.VISIT 0 1; XYZ_X01.VISIT: PV1 1 1, PV2 0 1")
    b = ext.Bundles({"2.3.1": {"XYZ_X01.xsd": own}, "2.4": {"XYZ_X01.xsd": v24}})
    elements, log = _named(rows, "2.3.1", "XYZ_X01", b)
    assert [(e["name"], e["source"]) for e in log] == [("VISIT", "v2xml"), ("IN1_GROUP", "synthesised"),
                                                      ("ENCODING", "v2xml"), ("NK1_GROUP", "synthesised")], log
    assert log[0]["cite"] == ("HL7-xml 2.3.1/XYZ_X01.xsd, XYZ_X01.VISIT.CONTENT, generator "
                              "urn:com.sun:encoder-hl7-1.0"), log[0]
    assert log[2]["cite"] == ("HL7-xml 2.3.1/XYZ_X01.xsd, XYZ_X01.ENCODING.CONTENT, generator "
                              "urn:com.sun:encoder-hl7-1.0"), log[2]
    assert "refused" in log[3]["cite"] and "CHOICE" in log[3]["cite"], log[3]
    assert ext._v2xml.REFUSED == {"2.3.1": ("CHOICE",)}, ext._v2xml.REFUSED
    # The v2.4 bundle names the insurance group and the refused CHOICE group (same first segment
    # and member set); the derived citation records the refusal.
    v24 = _xsd("XYZ_X01", "XYZ_X01: MSH 1 1, XYZ_X01.INSURANCE 0 unbounded, XYZ_X01.NOK_ALLERGY 0 1;"
                          "XYZ_X01.INSURANCE: IN1 1 1, IN2 0 1; XYZ_X01.NOK_ALLERGY: NK1 1 1, AL1 1 1")
    b = ext.Bundles({"2.3.1": {"XYZ_X01.xsd": own}, "2.4": {"XYZ_X01.xsd": v24}})
    _, log = _named(rows, "2.3.1", "XYZ_X01", b)
    assert [(e["name"], e["source"]) for e in log] == [("VISIT", "v2xml"), ("INSURANCE", "v2xml-v2.4"),
                                                      ("ENCODING", "v2xml"), ("NOK_ALLERGY", "v2xml-v2.4")], log
    assert log[3]["cite"].endswith("; HL7-xml 2.3.1/XYZ_X01.xsd names it CHOICE (XYZ_X01.CHOICE.CONTENT), a name "
                                   "refused without a cited override (P8b-14 ruling)"), log[3]
    # A cited override names a refused group no bundle names otherwise.
    v24 = _xsd("XYZ_X01", "XYZ_X01: MSH 1 1, XYZ_X01.VISIT 0 1; XYZ_X01.VISIT: PV1 1 1, PV2 0 1")
    b = ext.Bundles({"2.3.1": {"XYZ_X01.xsd": own}, "2.4": {"XYZ_X01.xsd": v24}})
    named = copy.deepcopy(EMPTY)
    named["groupNames"].append({"version": "2.3.1", "structure": "XYZ_X01", "path": [4], "name": "NOK_ALLERGY",
                                "citation": "x"})
    log = []
    ext.name_groups(ext.parse([ext.Row(left, "", i, "") for i, left in enumerate(rows)]), "2.3.1", "XYZ_X01", named,
                    bundles=b, log=log)
    assert (log[3]["name"], log[3]["source"]) == ("NOK_ALLERGY", "override"), log
    # Another version's bundle never refuses a name (v2.4 to v2.8.2 name ENCODING groups).
    other = _bundles("2.5.1", {"XYZ_X01": _xsd("XYZ_X01", "XYZ_X01: MSH 1 1, XYZ_X01.ENCODING 0 1;"
                                                          "XYZ_X01.ENCODING: RXE 1 1, RXR 1 unbounded")})
    _, log = _named(["MSH", "[", "RXE", "{RXR}", "]"], "2.5.1", "XYZ_X01", other)
    assert [(e["name"], e["source"]) for e in log] == [("ENCODING", "v2xml")], log


def check_v231_own_bundle_other_trigger():
    # P8b-14 (v2.3.1 ORF_R02, whose v2.3.1 bundle file is ORF_R04.xsd): where the v2.3.1 bundle has
    # no file for the structure ID, a file of the same message code is matched on first segment
    # and member set, as the D2 derivation does through v2.4, citing both IDs (nameSource v2xml).
    rows = ["MSH", "[", "PV1", "[PV2]", "]"]
    own = _xsd_encoder("XYZ_X04", "XYZ_X04: MSH 1 1, XYZ_X04.VISIT 0 1; XYZ_X04.VISIT: PV1 1 1, PV2 0 1")
    b = ext.Bundles({"2.3.1": {"XYZ_X04.xsd": own}, "2.4": {}})
    _, log = _named(rows, "2.3.1", "XYZ_X01", b)
    assert [(e["name"], e["source"]) for e in log] == [("VISIT", "v2xml")], log
    assert log[0]["cite"] == ("HL7-xml 2.3.1/XYZ_X04.xsd, XYZ_X04.VISIT.CONTENT, generator urn:com.sun:encoder-hl7-1.0, "
                              "for v2.3.1 XYZ_X01, which differs from XYZ_X04 only by trigger"), log[0]
    # Another version's bundle keeps the exact-file rule: no match by message code.
    other = _bundles("2.5.1", {"XYZ_X04": _xsd("XYZ_X04", "XYZ_X04: MSH 1 1, XYZ_X04.VISIT 0 1;"
                                                          "XYZ_X04.VISIT: PV1 1 1, PV2 0 1")})
    _, log = _named(rows, "2.5.1", "XYZ_X01", other)
    assert [(e["name"], e["source"]) for e in log] == [("PV1_GROUP", "synthesised")], log


def check_two_structure_match_needs_declaration():
    # P8b-14 (v2.3.1 ADT^A28 and ADT^A31: Table 0354 lists them under ADT_A01 and ADT_A28): a
    # caption whose events two rows list fails a full read unless the triggers are declared shared;
    # declared, the print is the print of every structure the table names.
    table = [("XYZ_X01", ["X01", "X28"], "X01, X28"), ("XYZ_X28", ["X28"], "X28")]
    rows = [("MSH", "Header"), ("PID", "Patient")]
    text = _page(1, ["    XYZ^X01                   Synthetic Message                     Chapter"]
                 + _table("XYZ^X01", rows)[1:] + [""]
                 + ["    XYZ^X28                   Synthetic Message                     Chapter"]
                 + _table("XYZ^X28", rows)[1:], heading="9.1.1           XYZ - synthetic (Event X28)")
    structures, report, _ = _run("2.3.1", [("syn", text)], tables=table, full=True)
    assert "XYZ_X28" not in structures, structures
    [miss] = [r for r in report if r[1] == "needs-structure-id"]
    assert miss[0] == "XYZ^X28" and "maps it to XYZ_X01, XYZ_X28" in miss[2], miss
    assert any(r[1] == "error" and r[0] == "XYZ^X28" and "needs-structure-id" in r[2] for r in report), report
    declared = {**EMPTY, "sharedTriggers": [{"version": "2.3.1", "trigger": "XYZ^X28",
                                             "structures": ["XYZ_X01", "XYZ_X28"], "citation": "x"}]}
    structures, report, _ = _run("2.3.1", [("syn", text)], declared, tables=table, full=True)
    assert structures["XYZ_X01"]["triggers"] == ["XYZ^X01", "XYZ^X28"], structures["XYZ_X01"]
    assert structures["XYZ_X28"]["triggers"] == ["XYZ^X28"], structures["XYZ_X28"]
    assert structures["XYZ_X28"]["elements"] == structures["XYZ_X01"]["elements"]
    assert ("XYZ^X28", "shared-trigger", "XYZ_X01, XYZ_X28 (declared)") in report, report
    assert not [r for r in report if r[1] in ("error", "needs-structure-id", "0354-missing-caption")], report
    # A declaration naming other structures does not resolve the caption.
    other = {**EMPTY, "sharedTriggers": [{**declared["sharedTriggers"][0], "structures": ["XYZ_X01", "XYZ_X99"]}]}
    _, report, _ = _run("2.3.1", [("syn", text)], other, tables=table, full=True)
    assert any(r[1] == "needs-structure-id" for r in report), report


def check_unresolved_caption_declared():
    # P8b-14: on a version that prints its own Table 0354, a caption whose events no row lists fails
    # a full read (needs-structure-id) unless a cited unresolvedCaptions entry declares it; a stale
    # entry is an error. A borrowed table (v2.3 reads v2.3.1's) reports the caption only.
    text = _page(1, ["    XYZ^X09                   Synthetic Message                     Chapter"]
                 + _table("XYZ^X09", [("MSH", "Header"), ("PID", "Patient")])[1:],
                 heading="9.1.4           XYZ - synthetic (Event X09)")
    _, report, _ = _run("2.3.1", [("syn", text)], tables=TABLE, full=True)
    assert any(r[1] == "needs-structure-id" and r[0] == "XYZ^X09" for r in report), report
    assert any(r[1] == "error" and r[0] == "XYZ^X09" and "needs-structure-id" in r[2] for r in report), report
    rule = {**EMPTY, "unresolvedCaptions": [{"version": "2.3.1", "section": "9.1.4", "caption": "XYZ^X09",
                                             "citation": "Table 0354 lists no row for X09"}]}
    ext.validate_overrides(rule)
    structures, report, _ = _run("2.3.1", [("syn", text)], rule, tables=TABLE, full=True)
    assert not [r for r in report if r[1] == "error"], report
    [miss] = [r for r in report if r[1] == "needs-structure-id"]
    assert miss[0] == "XYZ^X09" and "declared" in miss[2] and "Table 0354 lists no row for X09" in miss[2], miss
    stale = {**EMPTY, "unresolvedCaptions": [{**rule["unresolvedCaptions"][0], "section": "9.1.5"}]}
    _, report, _ = _run("2.3.1", [("syn", text)], stale, tables=TABLE, full=True)
    assert any(r[1] == "error" and "unresolvedCaptions" in r[2] for r in report), report
    for bad in ({"version": "2.3.1", "section": "9.1.4", "citation": "x"},
                {"version": "2.3.1", "section": "9.1.4", "caption": "XYZ^X09", "citation": " "}):
        try:
            ext.validate_overrides({**EMPTY, "unresolvedCaptions": [bad]})
        except ext.OverridesError:
            continue
        raise AssertionError(f"unresolvedCaptions entry {bad} must be rejected")


def check_v231_name_source_validation():
    # P8b-14: v2xml is valid on v2.3.1, cited by the bundle folder as it is on disk ("HL7-xml 2.3.1/");
    # v2xml-v2.4 stays valid there as the fallback; v2.3 still has no v2xml.
    def names(source, citation, version="2.3.1"):
        return {"structure": "XYZ_X01", "version": version, "citation": f"c. Unprinted group names: {citation}.",
                "elements": [{"group": "G", "nameSource": source, "min": 0, "max": 1, "elements": []}]}
    ext.validate_names(names("v2xml", "G (HL7-xml 2.3.1/XYZ_X01.xsd, XYZ_X01.G.CONTENT, generator HL7-Database)"))
    ext.validate_names(names("v2xml-v2.4", "G (HL7-xml v2.4/XYZ_X01.xsd, XYZ_X01.G.CONTENT, derived for v2.3.1 XYZ_X01)"))
    for bad in (names("v2xml", "G (HL7-xml v2.3.1/XYZ_X01.xsd, XYZ_X01.G.CONTENT)"),
                names("v2xml", "G (HL7-xml 2.3.1/XYZ_X01.xsd, XYZ_X01.G.CONTENT)", "2.3")):
        try:
            ext.validate_names(bad)
        except ext.NameSourceError:
            continue
        raise AssertionError(f"{bad} must be rejected")


def check_caption_erratum_occurrence():
    # P8b-14 (v2.3.1 CH08 8.10.1, p 8-67: the clinical study without phases, Table 0003 event M07,
    # printed a second time under MFN^M06 and MFK^M06): "occurrence" narrows a caption erratum to
    # the n-th caption printed so, in reading order; the first print keeps its caption.
    rows = [("MSH", "Header"), ("PID", "Patient")]
    other = [("MSH", "Header"), ("PV1", "Visit")]
    text = _page(1, ["    XYZ^X06                   Synthetic Message                     Chapter"]
                 + _table("XYZ^X06", rows)[1:] + ["", "    Case 2: the second print, after prose, as on p 8-67.", ""]
                 + ["    XYZ^X06                   Synthetic Message                     Chapter"]
                 + _table("XYZ^X06", other)[1:], heading="9.1.6           XYZ - synthetic (Event X06)")
    table = [("XYZ_X06", ["X06"], "X06"), ("XYZ_X07", ["X07"], "X07")]
    entry = {"version": "2.3.1", "where": "caption", "structure": "XYZ_X07", "printed": "XYZ^X06",
             "intended": "XYZ^X07", "occurrence": 2, "citation": "x"}
    fix = {**EMPTY, "errata": [entry]}
    ext.validate_overrides(fix)
    structures, report, _ = _run("2.3.1", [("syn", text)], fix, tables=table, full=True)
    assert [e["segment"] for e in structures["XYZ_X06"]["elements"]] == ["MSH", "PID"], structures
    assert [e["segment"] for e in structures["XYZ_X07"]["elements"]] == ["MSH", "PV1"], structures
    assert structures["XYZ_X07"]["triggers"] == ["XYZ^X07"], structures["XYZ_X07"]
    assert not [r for r in report if r[1] in ("error", "duplicate-differs")], report
    # An occurrence past the last caption printed so matches nothing: a stale entry.
    stale = {**EMPTY, "errata": [{**entry, "occurrence": 3}]}
    _, report, _ = _run("2.3.1", [("syn", text)], stale, tables=table, full=True)
    assert any(r[1] == "error" and "matches nothing" in r[2] for r in report), report


def check_table_0354_provenance():
    # P8b-14 fix round 1: on v2.3.1 (the table-0354 caption era) every structure whose ID was read
    # from Table 0354 says so in its citation, naming any erratum (printed and corrected row) and
    # any declaration that resolved it; a caption printing its ID adds nothing. Since P8b-18 the
    # caret era (v2.4's two-part captions) says so too.
    rows = [("MSH", "Header"), ("PID", "Patient")]
    text = _page(1, ["    XYZ^X02                   Synthetic Message                     Chapter"]
                 + _table("XYZ^X02", rows)[1:] + [""]
                 + _table("ABC^X05^ABC_X05", rows), heading="9.1.2           XYZ - synthetic (Event X02)")
    table = [("XYZ__X01", ["X01", "X09"], "X01, X09"), ("ABC_X05", ["X05"], "X05")]
    fix = {**EMPTY, "errata": [
        {"version": "2.3.1", "where": "table-0354", "structure": "XYZ_X01", "printed": "XYZ__X01",
         "intended": "XYZ_X01", "citation": "x"},
        {"version": "2.3.1", "where": "table-0354", "structure": "XYZ_X01", "printed": "X09", "intended": "X02",
         "citation": "x"}]}
    structures, report, _ = _run("2.3.1", [("syn", text)], fix, tables=table, full=True)
    cite = structures["XYZ_X01"]["citation"]
    assert " Structure ID from Table 0354 v2.3.1" in cite, cite
    assert "XYZ__X01 read as XYZ_X01" in cite and "event X09 read as X02" in cite, cite
    assert "Structure ID from Table 0354" not in structures["ABC_X05"]["citation"], structures["ABC_X05"]["citation"]
    assert not [r for r in report if r[1] == "error"], report
    structures, _, _ = _run("2.4", [("syn", text)], fix | {"errata": [{**e, "version": "2.4"} for e in fix["errata"]]},
                            tables=table)
    assert " Structure ID from Table 0354 v2.4" in structures["XYZ_X01"]["citation"], structures["XYZ_X01"]["citation"]
    assert "Structure ID from Table 0354" not in structures["ABC_X05"]["citation"], structures["ABC_X05"]["citation"]
    # A declared shared trigger names the rows that list it.
    two = [("XYZ_X01", ["X01", "X28"], "X01, X28"), ("XYZ_X28", ["X28"], "X28")]
    text = _page(1, ["    XYZ^X28                   Synthetic Message                     Chapter"] + _table("XYZ^X28", rows)[1:],
                 heading="9.1.1           XYZ - synthetic (Event X28)")
    shared = {**EMPTY, "sharedTriggers": [{"version": "2.3.1", "trigger": "XYZ^X28",
                                           "structures": ["XYZ_X01", "XYZ_X28"], "citation": "x"}]}
    structures, _, _ = _run("2.3.1", [("syn", text)], shared, tables=two)
    assert "declared shared" in structures["XYZ_X28"]["citation"], structures["XYZ_X28"]["citation"]


def check_table_0354_event_erratum_union():
    # P8b-14 fix round 1 (v2.3.1 PPG_PCG lists 'PCC, PCH, PCJ'; every later table lists 'PCC, PCG,
    # PCH, PCJ'): an event erratum whose intended text is a list keeps the printed event and adds
    # the others, so the row still maps PCC to the structure.
    table = [("PPG_PCG", ["PCC", "PCH", "PCJ"], "PCC, PCH, PCJ")]
    e = {"version": "2.3.1", "where": "table-0354", "structure": "PPG_PCG", "printed": "PCC",
         "intended": "PCC, PCG", "citation": "x"}
    ext.validate_overrides({**EMPTY, "errata": [e]})
    used = set()
    assert ext.apply_table_errata(table, [e], used) == [("PPG_PCG", ["PCC", "PCG", "PCH", "PCJ"], "PCC, PCH, PCJ")]
    assert id(e) in used


def check_caption_structure_declared():
    # P8b-14 (v2.3.1 MFK^M01-M06 and MFK^M04: Table 0354's one MFK row, MFK_M01, omits M02 and M04):
    # a cited captionStructures entry names the Table 0354 row a caption's print belongs to when no
    # row lists all its events. The structure must be a row of the version's table; the entry's
    # citation joins the structure's; a stale entry is an error.
    rows = [("MSH", "Header"), ("PID", "Patient")]
    text = _page(1, ["    XYZ^X01-X03               Synthetic Message                     Chapter"]
                 + _table("XYZ^X01-X03", rows)[1:], heading="9.1.7           XYZ - synthetic (Events X01-X03)")
    table = [("XYZ_X01", ["X01", "X03", "X05"], "X01, X03, X05")]
    _, report, _ = _run("2.3.1", [("syn", text)], tables=table, full=True)
    assert any(r[1] == "error" and r[0] == "XYZ^X01-X03" for r in report), report
    entry = {"version": "2.3.1", "section": "9.1.7", "caption": "XYZ^X01-X03", "structure": "XYZ_X01",
             "citation": "the one XYZ row of Table 0354 omits X02."}
    rule = {**EMPTY, "captionStructures": [entry]}
    ext.validate_overrides(rule)
    structures, report, _ = _run("2.3.1", [("syn", text)], rule, tables=table, full=True)
    s = structures["XYZ_X01"]
    assert s["triggers"] == ["XYZ^X01", "XYZ^X02", "XYZ^X03", "XYZ^X05"], s["triggers"]
    assert "the one XYZ row of Table 0354 omits X02." in s["citation"], s["citation"]
    assert not [r for r in report if r[1] in ("error", "needs-structure-id")], report
    # The named row must be of the caption's message code (a print is never filed under another
    # message's structure ID).
    other = table + [("ABC_X01", ["X02"], "X02")]
    _, report, _ = _run("2.3.1", [("syn", text)], {**EMPTY, "captionStructures": [{**entry, "structure": "ABC_X01"}]},
                        tables=other, full=True)
    assert any(r[1] == "error" and "another message code" in r[2] for r in report), report
    # P8b-18: the message code compared is the Table 0354 row's own, so the entry is first looked
    # up as a row: a structure that is no row is reported as no row, never as "a row of another
    # message code" because of its ID prefix.
    _, report, _ = _run("2.3.1", [("syn", text)], {**EMPTY, "captionStructures": [{**entry, "structure": "ABC_X09"}]},
                        tables=table, full=True)
    errors = [r[2] for r in report if r[1] == "error" and "captionStructures" in r[2]]
    assert errors and all("is not a Table 0354 v2.3.1 row" in e for e in errors), report
    for bad, why in (({**entry, "structure": "XYZ_X09"}, "not a Table 0354 row"), ({**entry, "section": "9.1.8"}, "stale")):
        _, report, _ = _run("2.3.1", [("syn", text)], {**EMPTY, "captionStructures": [bad]}, tables=table, full=True)
        assert any(r[1] == "error" and "captionStructures" in r[2] for r in report), (why, report)
    try:
        ext.validate_overrides({**EMPTY, "captionStructures": [{**entry, "structure": "xyz"}]})
    except ext.OverridesError:
        pass
    else:
        raise AssertionError("a captionStructures entry with a malformed structure ID must be rejected")


def check_space_before_caret_caption():
    # P8b-14 (v2.3.1 CH08 8.8.1: "MFN ^M05" and "MFK ^M05"): a space between the message code and
    # the caret is a typesetting slip; the caption is read as CODE^EVT.
    line = "    XYZ ^X02                  Synthetic Message                     Chapter"
    m = ext.match_caption(line, "table-0354")
    assert m and m[1:4] == ("XYZ", "X02", ""), m
    text = _page(1, [line] + _table("XYZ^X02", [("MSH", "Header"), ("PID", "Patient")])[1:],
                 heading="9.1.2           XYZ - synthetic (Event X02)")
    structures, _, count = _run("2.3.1", [("syn", text)], tables=TABLE)
    assert count == 1 and structures["XYZ_X01"]["triggers"][0] == "XYZ^X02", structures
    # Two spaces, or a space after the caret, is not a caption.
    for bad in ("    XYZ  ^X02                 Synthetic Message                     Chapter",
                "    XYZ^ X02                  Synthetic Message                     Chapter"):
        assert not ext.match_caption(bad, "table-0354"), bad


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


def check_two_part_caption_with_direction():
    # v2.3.1, v2.4, v2.5.1 and v2.6 CH05 5.10.3.1 print "QRY^Q02 (A to B)  Query Message" and
    # "QCK^Q02 (B to A)  Query General Acknowledgment": one space, then the direction, then the
    # title. The direction is not the title; both structures share the event, told apart by MSH-9.1.
    table = TABLE + [("ABC_X02", ["X02"], "X02")]
    for version in ("2.3.1", "2.4", "2.5.1", "2.6"):
        line = "    XYZ^X02 (A to B)          Synthetic Message                     Chapter"
        m = ext.match_caption(line, ext.ERAS[f"v{version}"][1])
        assert m and m[1:4] == ("XYZ", "X02", "") and m[5].startswith("Synthetic Message"), (version, m)
        text = _page(1, [line] + _table("XYZ^X02", [("MSH", "Header"), ("PID", "Patient")])[1:] + [""]
                     + ["    ABC^X02 (B to A)          Synthetic Acknowledgment              Chapter"]
                     + _table("ABC^X02", [("MSH", "Header"), ("MSA", "Ack")])[1:] + [""]
                     + ["    ACK^X02 (A to B)          General Acknowledgment                Chapter"]
                     + _table("ACK^X02", [("MSH", "Header"), ("MSA", "Ack")])[1:],
                     heading="9.1.3           XYZ/ABC - synthetic (Event X02)")
        structures, report, count = _run(version, [("syn", text)], tables=table)
        assert count == 3, (version, count, report)
        assert structures["XYZ_X01"]["triggers"] == ["XYZ^X02", "XYZ^X01"], structures
        assert structures["ABC_X02"]["triggers"] == ["ABC^X02"], structures
        assert [e["segment"] for e in structures["ABC_X02"]["elements"]] == ["MSH", "MSA"], structures
        assert structures["ACK"]["triggers"] == ["ACK^X02"], structures
        # XYZ_X03 is the shared TABLE's row with no caption here; the two read rows are not "missing".
        assert [r[0] for r in report if r[1] in ("needs-structure-id", "0354-missing-caption")] == ["XYZ_X03"], report
        # P8b-18 (negative case): every printed direction caption is a column header ending in
        # "Chapter" (all twelve in the v2.3.1 to v2.6 prints); a line of running prose that starts
        # "CODE^EVT (A to B)" and goes on two spaces later is not a caption, and reads nothing.
        prose = "    XYZ^X02 (A to B)  is sent first, and the response follows later in the session."
        assert ext.match_caption(prose, ext.ERAS[f"v{version}"][1]) is None, (version, prose)
        text = _page(1, ["The deferred query is sent by the initiating system:", prose, "and then acknowledged."],
                     heading="9.1.3           XYZ/ABC - synthetic (Event X02)")
        structures, report, count = _run(version, [("syn", text)], tables=table)
        assert count == 0 and not [r for r in report if r[1] == "skipped"], (version, count, report)


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


def check_v23_synthesised_ids_no_table():
    # P8b-15: v2.3 prints no structure ID and no Table 0354, and its MSH-9 has no third component
    # (lookup rule 3). The ID is synthesised CODE_EVT from the code and the first event of the
    # section title, flagged in the citation; no table (v2.3.1's or any other) is consulted, so
    # another version's Table 0354 errata never reach v2.3.
    assert not hasattr(ext, "TABLE_0354"), "v2.3 must not borrow v2.3.1's Table 0354"
    text = _page(1, ["    XYZ                       Synthetic Message                     Chapter"]
                 + _table("XYZ", [("MSH", "Header")])[1:], heading="9.2.1 XYZ - synthetic (events X07, X08)")
    fix = {**EMPTY, "errata": [{"version": "2.3.1", "where": "table-0354", "structure": "XYZ_X01",
                                "printed": "XYZ__X07", "intended": "XYZ_X01", "citation": "x"}]}
    structures, report, _ = _run("2.3", [("syn", text)], fix, tables=[("XYZ__X07", ["X07", "X08"], "X07, X08")])
    assert list(structures) == ["XYZ_X07"] and structures["XYZ_X07"]["triggers"] == ["XYZ^X07", "XYZ^X08"], structures
    cite = structures["XYZ_X07"]["citation"]
    assert ("Structure ID XYZ_X07 synthesised as CODE_EVT from the message code XYZ and X07, the first event "
            "the section title names (v2.3 prints no structure ID and no Table 0354)") in cite, cite
    assert "Events XYZ^X07 and XYZ^X08 read from the section title 9.2.1 'XYZ - synthetic (events X07, X08)'" in cite, cite
    assert "Table 0354" not in cite.replace("no Table 0354", ""), cite
    assert not [r for r in report if r[1].startswith("0354")], report
    # A single event: the ID and the trigger are that event's.
    one = _page(1, ["    ABC                       Synthetic Message                     Chapter"]
                + _table("ABC", [("MSH", "Header")])[1:], heading="9.2.2 ABC - synthetic (event X09)")
    structures, _, _ = _run("2.3", [("syn", one)])
    assert structures["ABC_X09"]["triggers"] == ["ABC^X09"], structures


def check_v23_events_from_title():
    # P8b-15: a code-alone caption whose section title names no event (v2.3 CH04 4.6 "DIET
    # ORDERS", CH10 10.2) takes its events from a cited overrides.json eventsFromTitle entry,
    # keyed by section and caption (and the n-th such caption of the section); the citation says
    # where the print gives them. Without one it stays needs-event. A stale entry fails a full read.
    body = (["    XYZ                       Synthetic Message                     Chapter"]
            + _table("XYZ", [("MSH", "Header"), ("PID", "Patient")])[1:] + [""]
            + ["The second synthetic message replaces the patient with a visit as follows:", ""]
            + ["    XYZ                       Synthetic Message                     Chapter"]
            + _table("XYZ", [("MSH", "Header"), ("PV1", "Visit")])[1:])
    text = _page(1, body, heading="9.3 XYZ TRIGGER EVENTS")
    _, report, _ = _run("2.3", [("syn", text)])
    assert [r[0] for r in report if r[1] == "needs-event"] == ["XYZ^?", "XYZ^?"], report
    entries = {**EMPTY, "eventsFromTitle": [
        {"version": "2.3", "section": "9.3", "caption": "XYZ", "events": ["X05", "X06"], "citation": "9.3 lists X05, X06"},
        {"version": "2.3", "section": "9.3", "caption": "XYZ", "occurrence": 2, "events": ["X10"], "citation": "c2"}]}
    ext.validate_overrides({**EMPTY, **entries})
    structures, report, _ = _run("2.3", [("syn", text)], entries, full=True)
    assert structures["XYZ_X05"]["triggers"] == ["XYZ^X05", "XYZ^X06"], structures
    assert [e["segment"] for e in structures["XYZ_X05"]["elements"]] == ["MSH", "PID"], structures
    assert [e["segment"] for e in structures["XYZ_X10"]["elements"]] == ["MSH", "PV1"], structures
    assert ("Events XYZ^X05 and XYZ^X06 from overrides.json eventsFromTitle (section 9.3 'XYZ TRIGGER EVENTS' "
            "names no event): 9.3 lists X05, X06") in structures["XYZ_X05"]["citation"], structures["XYZ_X05"]["citation"]
    assert not [r for r in report if r[1] in ("error", "needs-event")], report
    # Stale: an entry for a caption whose title names its events, or for no caption at all.
    titled = _page(1, body[:4], heading="9.4.1 XYZ - synthetic (event X01)")
    stale = {**EMPTY, "eventsFromTitle": [
        {"version": "2.3", "section": "9.4.1", "caption": "XYZ", "events": ["X02"], "citation": "x"},
        {"version": "2.3", "section": "9.9", "caption": "XYZ", "events": ["X02"], "citation": "x"}]}
    structures, report, _ = _run("2.3", [("syn", titled)], stale, full=True)
    assert structures["XYZ_X01"]["triggers"] == ["XYZ^X01"], structures
    errors = [r for r in report if r[1] == "error"]
    assert len(errors) == 2 and all("eventsFromTitle entry" in r[2] for r in errors), errors
    for bad in ({"version": "2.3", "section": "9.3", "caption": "XYZ", "events": [], "citation": "x"},
                {"version": "2.3", "section": "9.3", "caption": "XYZ", "events": ["X1"], "citation": "x"},
                {"version": "2.3", "section": "9.3", "caption": "XYZ", "events": ["X01"], "occurrence": 0, "citation": "x"}):
        try:
            ext.validate_overrides({**EMPTY, "eventsFromTitle": [bad]})
        except ext.OverridesError:
            continue
        raise AssertionError(f"{bad} must be rejected")


def check_v23_caption_forms():
    # P8b-15 reader fixes, v2.3 only (the section-title era): CH02 2.18.1 prints "QRY (A to B)"
    # (a direction tag and no caret); CH04 4.8.6 prints "RRE Pharmacy/Treatment Encoded Order
    # Acknowledgment Message  Chapter" (one space after the code), whose rows split at the MSH
    # row's description column; CH04 4.8.17 prints "R0R   Pharmacy /Treatment Order Response"
    # with no Chapter column, read only when the next row is MSH (a segment row inside a table
    # never is a caption).
    text = _page(1, ["    QRY (A to B)              Synthetic Query                       Chapter"]
                 + _table("QRY", [("MSH", "Header"), ("QRD", "Query")])[1:] + [""]
                 + ["    QCK (B to A)              Synthetic Ack                         Chapter"]
                 + _table("QCK", [("MSH", "Header"), ("MSA", "Ack")])[1:], heading="2.18.1 QRY/QCK - deferred (event Q02)")
    structures, report, count = _run("2.3", [("syn", text)])
    assert count == 2 and set(structures) == {"QRY_Q02", "QCK_Q02"}, (count, structures, report)
    assert [e["segment"] for e in structures["QCK_Q02"]["elements"]] == ["MSH", "MSA"], structures
    narrow = _page(2, ["    RRE Synthetic Encoded Order Acknowledgment Message         Chapter",
                       "    MSH                       Message Header                        2",
                       "    [ ERR ]                   Error                                 2",
                       "    [{NTE}]                   Notes                                 2"],
                   heading="4.8.6 RDE/RRE - synthetic (event X02)")
    bare = _page(3, ["    R0R                       Synthetic Response",
                     "    MSH                       Message Header",
                     "    RXO                       Order",
                     "    {RXR}                     Route"], heading="4.8.17 R0R - synthetic (event X03)")
    structures, report, count = _run("2.3", [("syn", narrow + bare)])
    assert count == 2, (count, report)
    assert [(e["segment"], e["min"], e["max"]) for e in structures["RRE_X02"]["elements"]] == [
        ("MSH", 1, 1), ("ERR", 0, 1), ("NTE", 0, None)], structures
    assert [e["segment"] for e in structures["R0R_X03"]["elements"]] == ["MSH", "RXO", "RXR"], structures
    # The relaxed forms are the section-title era's only.
    for era in ("caret", "table-0354"):
        assert ext.match_caption("    QRY (A to B)              Synthetic Query        Chapter", era) is None, era
    # P7-8 (negative case for the v2.3 direction tag): the tag form is a column header ending in
    # "Chapter"; running prose that starts "QRY (A to B)" is no caption, even with a segment
    # table right below it, and reads nothing.
    prose = "    QRY (A to B)  is sent first, and the response follows later in the session."
    assert ext.match_caption(prose, ext.ERAS["v2.3"][1]) is None, prose
    text = _page(4, [prose] + _table("QRY", [("MSH", "Header"), ("QRD", "Query")])[1:],
                 heading="2.18.1 QRY/QCK - deferred (event Q02)")
    structures, report, count = _run("2.3", [("syn", text)])
    assert count == 0 and not structures, (count, structures, report)


def check_closing_bracket_in_description_column():
    # v2.3 CH02 2.14.2 UDM (p 2-69) prints "{   DSP   } Display Data": the closing brace sits one
    # space before the description, past the column split. It belongs to the syntax cell.
    s, report = _structure([("MSH", "Header"), ("URD", "Definition"), ("          {   DSP   } Display Data", ""),
                            ("[ DSC ]", "Continuation")])
    assert s and [(e["segment"], e["min"], e["max"]) for e in s["elements"]] == [
        ("MSH", 1, 1), ("URD", 1, 1), ("DSP", 1, None), ("DSC", 0, 1)], (s, report)


def check_single_space_cell_and_shifted_page():
    # v2.3 CH03 3.2.19 ADR (p 3-17) prints "[{ROL}] Role" with one space before the description at
    # the column, and CH07 7.6.2 CSU (p 7-64) "{RXA Pharmacy Administration": rows, not prose. CH04
    # 4.8.19 RDR (p 4-106) sets the page after the break further right, so "{[RXC]}" ends at the
    # description column: a row. A prose line inside an open group stays unreadable.
    s, report = _structure([("MSH", "Header"), ("[ {PR1", "Procedures"),
                            ("                      [{ROL}] Role", ""), ("}]", ""), ("[DSC]", "Continuation")])
    assert s and [e.get("segment") or e["group"] for e in s["elements"]] == ["MSH", "PR1_GROUP", "DSC"], (s, report)
    assert [(e["segment"], e["min"], e["max"]) for e in s["elements"][1]["elements"]] == [
        ("PR1", 1, 1), ("ROL", 0, None)], s
    s, report = _structure([("MSH", "Header"), ("{", ""), ("  RXE", ""), ("                   {[RXC]}            Component", ""),
                            ("}", "")])
    assert s and [(e["segment"], e["min"], e["max"]) for e in s["elements"][1]["elements"]] == [
        ("RXE", 1, 1), ("RXC", 0, None)], (s, report)
    s, report = _structure([("MSH", "Header"), ("{", ""), ("PID", "Patient"),
                            ("The PID segment carries the patient for every group", ""), ("}", "")])
    assert s is None and any("prose inside an open group" in r[2] for r in report), report


def check_withdrawn_segments():
    # S2-2 (ADR-019 S2-1 amendment): a structure may name a segment its version's withdrawnSegments
    # lists; any other segment outside the version's schemas (but ADD) is outside the grammar; a
    # structure naming a listed segment says so in its citation; an entry is validated.
    qry = {"citation": "HL7 v2.7.1 Chapter 12, section 12.3.5 QRY, p 15.",
           "elements": [_seg("MSH"), _seg("QRD"), _seg("QRF", 0, 1), _seg("ADD", 0, 1)]}
    assert ext.outside_grammar("2.7.1", qry, OVERRIDES) == [], ext.outside_grammar("2.7.1", qry, OVERRIDES)
    assert ext.outside_grammar("2.7.1", qry, EMPTY) == ["QRD", "QRF"], ext.outside_grammar("2.7.1", qry, EMPTY)
    assert ext.outside_grammar("2.6", qry, EMPTY) == [], "v2.6 defines QRD and QRF"
    noted = ext.with_withdrawn_note("2.7.1", qry, OVERRIDES)["citation"]
    assert noted.endswith(" QRD and QRF are listed as withdrawn by v2.7.1 Appendix A and defined through v2.6 "
                          "(overrides.json withdrawnSegments): matched by segment ID, fields not validated."), noted
    assert ext.with_withdrawn_note("2.6", qry, OVERRIDES) == qry
    entry = {"version": "2.7.1", "segment": "QRD", "printed": "removed", "definedThrough": "2.6", "citation": "x"}
    for broken in ({**entry}, {**entry, "printed": "withdrawn", "segment": "QR"}):
        try:
            ext.validate_overrides({**EMPTY, "withdrawnSegments": [broken]})
        except ext.OverridesError:
            continue
        raise AssertionError(f"withdrawnSegments entry {broken} must be rejected")
    ext.validate_overrides({**EMPTY, "withdrawnSegments": [{**entry, "printed": "withdrawn"}]})
    # A committed structure's registration leaves completeness.json, the dangling comma with it.
    import tempfile
    saved = (ext.COMPLETENESS, ext.STRUCTURES)
    with tempfile.TemporaryDirectory() as root:
        os.makedirs(os.path.join(root, "v2.7.1"))
        open(os.path.join(root, "v2.7.1", "UDM_Q05.json"), "w").write("{}")
        ext.STRUCTURES, ext.COMPLETENESS = root, os.path.join(root, "completeness.json")
        lines = ['{', '  "versions": {', '    "2.7.1": { "complete": true, "citation": "x",', '      "notModelled": [',
                 '        {"structure": "RDR_RDR", "triggers": [], "reason": "a"},',
                 '        {"structure": "UDM_Q05", "triggers": ["UDM^Q05"], "reason": "b"}', '      ]', '    }', '  }', '}']
        open(ext.COMPLETENESS, "w").write("\n".join(lines))
        try:
            assert ext.sync_modelled_registrations(["2.7.1"], False) == [
                "v2.7.1 UDM_Q05: registered as not modelled but committed (modelled)"]
            assert ext.sync_modelled_registrations(["2.7.1"], True)
            after = json.load(open(ext.COMPLETENESS))["versions"]["2.7.1"]["notModelled"]
            assert [e["structure"] for e in after] == ["RDR_RDR"], after
            assert ext.sync_modelled_registrations(["2.7.1"], False) == []
        finally:
            ext.COMPLETENESS, ext.STRUCTURES = saved


def _keyed_entry(**kw):
    entry = {"version": "2.5.1", "structure": "MFN_M03", "caption": "MFN^M03^MFN_M03", "printed": "...",
             "key": {"segment": "MFI", "field": 1, "component": 1},
             "alternatives": [{"value": "OMA", "structure": "MFN_M08", "group": "MF_TEST_NUMERIC", "after": "OM1", "page": "8-24"},
                              {"value": "OMB", "structure": "MFN_M09", "group": "MF_TEST_CATEGORICAL", "after": "OM1", "page": "8-25"}],
             "citation": "HL7 v2.5.1 Chapter 8, section 8.8.2, p 8-23: keyed by MFI-1."}
    entry.update(kw)
    return entry


def check_keyed_choices():
    # S4-1 (ADR-019 S4 amendment): a keyedChoices placeholder is read as one element (a run of
    # placeholder rows merged; "???" read as a whole row), the keyed choice put in its place from
    # the named groups' segments after `after`, or an open slot where the entry has no map.
    entry = _keyed_entry()
    rows = ["MSH", "MFI", "{", "MFE", "OM1", "...", "...", "}"]
    tree = ext.parse([ext.Row(left, "", i, "8-23") for i, left in enumerate(rows)], keyed=entry)
    body = tree[2]["elements"]
    assert [e.get("segment") for e in body[:2]] == ["MFE", "OM1"] and len(body) == 3 and "_keyed" in body[2], body
    try:
        ext.parse([ext.Row(left, "", i, "") for i, left in enumerate(rows)])
        raise AssertionError("an unclaimed placeholder must stay unreadable (ruling G6)")
    except ext.UnknownNotation as exc:
        assert "placeholder (G6)" in str(exc), exc
    q = ext.parse([ext.Row(left, "", i, "") for i, left in enumerate(["MSH", "MFI", "{MFE", "OM1", "???", "}"])],
                  keyed=_keyed_entry(printed="???"))
    assert "_keyed" in q[2]["elements"][2], q
    m08 = {"structure": "MFN_M08", "version": "2.5.1", "triggers": ["MFN^M08"], "citation": "c8",
           "elements": [_seg("MSH"), _seg("MFI"), {"group": "MF_TEST_NUMERIC", "nameSource": "printed", "min": 1, "max": None,
                                                   "elements": [_seg("MFE"), _seg("OM1"), _seg("OM2", 0, 1)]}]}
    m09 = {"structure": "MFN_M09", "version": "2.5.1", "triggers": ["MFN^M09"], "citation": "c9",
           "elements": [_seg("MSH"), _seg("MFI"), {"group": "MF_TEST_CATEGORICAL", "nameSource": "printed", "min": 1, "max": None,
                                                   "elements": [_seg("MFE"), _seg("OM1"), _seg("OM3", 0, 1)]}]}
    m03 = {"structure": "MFN_M03", "version": "2.5.1", "triggers": ["MFN^M03"], "citation": "c3",
           "elements": [_seg("MSH"), _seg("MFI"), {"group": "MF_TEST", "nameSource": "printed", "min": 1, "max": None,
                                                   "elements": [_seg("MFE"), _seg("OM1"), dict(body[2])]}]}
    structures = {"MFN_M03": m03, "MFN_M08": m08, "MFN_M09": m09}
    report = ext.resolve_keyed_choices("2.5.1", structures, {"MFN_M03": entry})
    assert report == [("MFN_M03", "keyed-choice", "MFI-1: OMA=MF_TEST_NUMERIC, OMB=MF_TEST_CATEGORICAL")], report
    choice = m03["elements"][2]["elements"][2]
    assert choice["key"]["values"] == {"OMA": "MF_TEST_NUMERIC", "OMB": "MF_TEST_CATEGORICAL"}, choice
    assert [a["elements"] for a in choice["alternatives"]] == [[_seg("OM2", 0, 1)], [_seg("OM3", 0, 1)]], choice
    assert "choice keyed by MFI-1 (overrides.json keyedChoices" in m03["citation"], m03["citation"]
    text = ext.render(m03)
    assert '"key": { "segment": "MFI", "field": 1, "component": 1, "values": { "OMA": "MF_TEST_NUMERIC", ' in text, text
    # A named group with nothing after `after` is an error, never an empty alternative.
    bad = {"MFN_M03": json.loads(json.dumps({**m03, "elements": [_seg("MSH"), {**body[2]}]})), "MFN_M08": m08, "MFN_M09": m09}
    report = ext.resolve_keyed_choices("2.5.1", bad, {"MFN_M03": _keyed_entry(alternatives=[
        {**entry["alternatives"][0], "after": "OM2"}, entry["alternatives"][1]])})
    assert report and report[0][1] == "error" and "no segments after OM2" in report[0][2], report
    # No map: the placeholder is an open slot, cited, with the marker dropped.
    erp = _keyed_entry(structure="ERP_R09", caption="ERP^R09", key={"segment": "ERQ", "field": 2, "component": 1},
                       slot={"name": None, "min": 0, "max": None})
    del erp["alternatives"]
    slot = ext._keyed({"entry": erp})
    s = {"structure": "ERP_R09", "version": "2.5.1", "triggers": ["ERP^R09"], "citation": "c",
         "elements": [_seg("MSH"), _seg("ERQ"), slot]}
    assert ext.resolve_keyed_choices("2.5.1", {"ERP_R09": s}, {"ERP_R09": erp}) == [("ERP_R09", "keyed-slot", "ERQ-2: open slot")]
    assert s["elements"][2] == {"slot": None, "min": 0, "max": None, "citation": erp["citation"]}, s["elements"][2]
    ext.validate_overrides({**EMPTY, "keyedChoices": [entry, erp]})
    for broken in (_keyed_entry(slot={"name": None, "min": 0, "max": None}),
                   _keyed_entry(key={"segment": "MFI", "field": 0, "component": 1}),
                   _keyed_entry(alternatives=[entry["alternatives"][0], entry["alternatives"][0]]),
                   {k: v for k, v in erp.items() if k != "slot"} | {"slot": {"name": None, "min": 0, "max": 1}}):
        try:
            ext.validate_overrides({**EMPTY, "keyedChoices": [broken]})
        except ext.OverridesError:
            continue
        raise AssertionError(f"keyedChoices entry {broken} must be rejected")


def check_aliases():
    # S4-2: an aliases entry adds a structure with its own ID, triggers and citation and the
    # target's elements, copied; rendered with "aliasOf"; never over a printed syntax, never the
    # alias of an alias or of a structure the version does not have.
    q01 = {"structure": "QRY_Q01", "version": "2.4", "triggers": ["QRY^Q01"], "citation": "Q01 print.",
           "elements": [_seg("MSH"), _seg("QRD"), _seg("QRF", 0, 1), _seg("DSC", 0, 1)]}
    entry = {"version": "2.4", "structure": "QRY_P04", "aliasOf": "QRY_Q01", "triggers": ["QRY^P04"],
             "citation": "HL7 v2.4 Chapter 6, section 6.4.4, p 6-13: see Chapter 5."}
    structures = {"QRY_Q01": q01}
    assert ext.add_aliases("2.4", structures, {**EMPTY, "aliases": [entry]}, True) == [("QRY_P04", "alias", "of QRY_Q01")]
    alias = structures["QRY_P04"]
    assert alias["elements"] == q01["elements"] and alias["elements"] is not q01["elements"], alias
    assert alias["triggers"] == ["QRY^P04"] and alias["aliasOf"] == "QRY_Q01", alias
    assert alias["citation"].startswith(entry["citation"]) and alias["citation"].endswith("Q01 print."), alias["citation"]
    assert '  "triggers": ["QRY^P04"],\n  "aliasOf": "QRY_Q01",\n  "elements": [' in ext.render(alias)
    assert '"aliasOf"' not in ext.render(q01)
    for structures, expected in (({"QRY_Q01": q01, "QRY_P04": q01}, "names a structure the print gives a syntax"),
                                 ({}, "QRY_Q01 is not a structure read"),
                                 ({"QRY_Q01": {**q01, "aliasOf": "QRY_Q02"}}, "QRY_Q01 is not a structure read")):
        report = ext.add_aliases("2.4", dict(structures), {**EMPTY, "aliases": [entry]}, True)
        assert report and report[0][1] == "error" and expected in report[0][2], report
    assert ext.add_aliases("2.4", {}, {**EMPTY, "aliases": [entry]}, False) == [], "a partial read skips it"
    ext.validate_overrides({**EMPTY, "aliases": [entry]})
    for broken in ({**entry, "aliasOf": "QRY_P04"}, {**entry, "triggers": ["DSR^P04"]}, {**entry, "triggers": []}):
        try:
            ext.validate_overrides({**EMPTY, "aliases": [broken]})
        except ext.OverridesError:
            continue
        raise AssertionError(f"aliases entry {broken} must be rejected")


def check_error_responses():
    # S4-3: an errorResponses entry (CH05 5.6.5, v2.4 to v2.8.2) copies its MSA-1 codes, the query
    # defining segments each listed structure prints, and its citation into that structure, rendered
    # as "errorResponse" after the triggers; a listed segment the structure does not print, a
    # structure that is not a query response, a printed query defining segment left out, and (on a
    # full read) an unread structure or an unlisted query response are errors; malformed entries
    # are rejected; another version's structures are untouched.
    tbr = {"structure": "TBR_R08", "version": "2.4", "triggers": ["TBR^R08"], "citation": "TBR print.",
           "elements": [_seg("MSH"), _seg("MSA"), _seg("ERR", 0, 1), _seg("QAK"), _seg("RDF"),
                        _seg("RDT", 1, None), _seg("DSC", 0, 1)]}
    dsr = {"structure": "DSR_Q01", "version": "2.4", "triggers": ["DSR^Q01"], "citation": "DSR print.",
           "elements": [_seg("MSH"), _seg("MSA"), _seg("ERR", 0, 1), _seg("QAK", 0, 1), _seg("QRD"),
                        _seg("QRF", 0, 1), _seg("DSP", 1, None), _seg("DSC", 0, 1)]}
    adt = {"structure": "ADT_A01", "version": "2.4", "triggers": ["ADT^A01"], "citation": "ADT print.",
           "elements": [_seg("MSH"), _seg("EVN"), _seg("PID")]}
    entry = {"version": "2.4", "acknowledgmentCodes": ["AE", "AR"], "structures": {"TBR_R08": [], "DSR_Q01": ["QRD", "QRF"]},
             "citation": "HL7 v2.4 Chapter 5, section 5.6.5 Query error response, p 5-62: the rest is absent."}
    overrides = {**EMPTY, "errorResponses": [entry]}
    ext.validate_overrides(overrides)
    structures = {"TBR_R08": dict(tbr), "DSR_Q01": dict(dsr), "ADT_A01": dict(adt)}
    report = ext.add_error_responses("2.4", structures, overrides, True)
    assert [r[1] for r in report] == ["error-response", "error-response"], report
    assert structures["TBR_R08"]["errorResponse"] == {"acknowledgmentCodes": ["AE", "AR"], "querySegments": [],
                                                      "citation": entry["citation"]}, structures["TBR_R08"]
    assert structures["DSR_Q01"]["errorResponse"]["querySegments"] == ["QRD", "QRF"]
    assert "errorResponse" not in structures["ADT_A01"]
    rendered = ext.render(structures["DSR_Q01"])
    assert '  "triggers": ["DSR^Q01"],\n  "errorResponse": {"acknowledgmentCodes": ["AE", "AR"], "querySegments": ["QRD", "QRF"], ' in rendered
    assert '"errorResponse"' not in ext.render(adt)
    assert ext.add_error_responses("2.5.1", {"TBR_R08": dict(tbr)}, overrides, True) == [], "another version"
    for listed, structures, expected in (
            ({"TBR_R08": ["QRD"]}, {"TBR_R08": dict(tbr)}, "the structure prints []"),
            ({"DSR_Q01": ["QRD"]}, {"DSR_Q01": dict(dsr)}, "the structure prints ['QRD', 'QRF']"),
            ({"ADT_A01": []}, {"ADT_A01": dict(adt)}, "not a query response"),
            ({"TBR_R08": []}, {}, "not read from the print"),
            ({"TBR_R08": []}, {"TBR_R08": dict(tbr), "DSR_Q01": dict(dsr)}, "does not list")):
        report = ext.add_error_responses("2.4", structures, {**EMPTY, "errorResponses": [{**entry, "structures": listed}]}, True)
        errors = [r for r in report if r[1] == "error"]
        assert errors and expected in errors[0][2], (listed, report)
    partial = ext.add_error_responses("2.4", {}, {**EMPTY, "errorResponses": [{**entry, "structures": {"TBR_R08": []}}]}, False)
    assert partial == [], "a partial read skips an unread structure"
    for broken in ({**entry, "acknowledgmentCodes": []}, {**entry, "acknowledgmentCodes": ["AE", "AE"]},
                   {**entry, "acknowledgmentCodes": ["ae"]}, {**entry, "structures": {}},
                   {**entry, "structures": {"TBR_R08": ["RDF"]}}, {**entry, "structures": {"DSR_Q01": ["QRD", "QRD"]}},
                   {**entry, "citation": ""}):
        try:
            ext.validate_overrides({**EMPTY, "errorResponses": [broken]})
        except ext.OverridesError:
            continue
        raise AssertionError(f"errorResponses entry {broken} must be rejected")


def check_referenced_triggers():
    # P8b-15 fix round 2: a trigger the print defines only in prose that names an already printed
    # structure without ambiguity (v2.3 CH07 7.19.1: W01 "identifies ORU messages") is added to that
    # structure's triggers by a cited referencedTriggers entry, which the citation records; an entry
    # naming no read structure fails a full read; malformed entries are rejected.
    text = _page(1, ["    XYZ                       Synthetic Message                     Chapter"]
                 + _table("XYZ", [("MSH", "Header"), ("PID", "Patient")])[1:], heading="9.2.1 XYZ - synthetic (event X01)")
    entries = {**EMPTY, "referencedTriggers": [
        {"version": "2.3", "structure": "XYZ_X01", "triggers": ["XYZ^X09"], "citation": "9.4 says X09 uses the XYZ message"}]}
    ext.validate_overrides(entries)
    structures, report, _ = _run("2.3", [("syn", text)], entries, full=True)
    s = structures["XYZ_X01"]
    assert s["triggers"] == ["XYZ^X01", "XYZ^X09"], s
    assert ("Triggers XYZ^X09 added by overrides.json referencedTriggers (the print names this structure for "
            "them in prose): 9.4 says X09 uses the XYZ message.") in s["citation"], s["citation"]
    assert not [r for r in report if r[1] == "error"], report
    stale = {**EMPTY, "referencedTriggers": [
        {"version": "2.3", "structure": "XYZ_X07", "triggers": ["XYZ^X09"], "citation": "x"}]}
    _, report, _ = _run("2.3", [("syn", text)], stale, full=True)
    assert ("XYZ_X07", "error", "referencedTriggers entry names no structure read from the print") in report, report
    # P8b-18: a referenced trigger of another message code is an error; a referenced trigger enters
    # the shared-trigger check (here XYZ^X09 is also printed as XYZ_X09, undeclared).
    other = {**EMPTY, "referencedTriggers": [
        {"version": "2.3", "structure": "XYZ_X01", "triggers": ["ABC^X09"], "citation": "x"}]}
    _, report, _ = _run("2.3", [("syn", text)], other, full=True)
    assert ("XYZ_X01", "error", "referencedTriggers entry adds ABC^X09, whose message code is not XYZ") in report, report
    two = _page(1, ["    XYZ                       Synthetic Message                     Chapter"]
                + _table("XYZ", [("MSH", "Header"), ("PID", "Patient")])[1:], heading="9.2.1 XYZ - synthetic (event X01)") \
        + _page(2, ["    XYZ                       Synthetic Message                     Chapter"]
                + _table("XYZ", [("MSH", "Header"), ("PV1", "Visit")])[1:], heading="9.2.2 XYZ - synthetic (event X09)")
    _, report, _ = _run("2.3", [("syn", two)], entries, full=True)
    assert any(r[0] == "XYZ^X09" and r[1] == "shared-trigger" and "XYZ_X01" in r[2] and "XYZ_X09" in r[2]
               for r in report), report
    for bad in ({"version": "2.3", "structure": "XYZ_X01", "triggers": [], "citation": "x"},
                {"version": "2.3", "structure": "XYZ_X01", "triggers": ["XYZ-X09"], "citation": "x"}):
        try:
            ext.validate_overrides({**EMPTY, "referencedTriggers": [bad]})
        except ext.OverridesError:
            continue
        raise AssertionError(f"{bad} must be rejected")


def check_v23_names_through_v231_then_v24():
    # Controller carry-in (P8b-15): v2.3 group names are derived through the v2.3.1 bundle first
    # (nameSource v2xml-v2.3.1, cited "HL7-xml 2.3.1/" with the file's generator), then the v2.4
    # bundle (v2xml-v2.4), matching on (structure ID or message code, first segment, member set),
    # never by position; else synthesised. The v2.3.1 bundle's CHOICE stays refused there too.
    rows = ["MSH", "[", "PV1", "[PV2]", "]", "[", "{", "IN1", "[IN2]", "}", "]", "[", "NK1", "AL1", "]"]
    own = _xsd_encoder("XYZ_X01", "XYZ_X01: MSH 1 1, XYZ_X01.VISIT 0 1, XYZ_X01.CHOICE 0 1;"
                                  "XYZ_X01.VISIT: PV1 1 1, PV2 0 1; XYZ_X01.CHOICE: NK1 1 1, AL1 1 1")
    v24 = _xsd("XYZ_X01", "XYZ_X01: MSH 1 1, XYZ_X01.INSURANCE 0 unbounded, XYZ_X01.NOK_ALLERGY 0 1;"
                          "XYZ_X01.INSURANCE: IN1 1 1, IN2 0 1; XYZ_X01.NOK_ALLERGY: NK1 1 1, AL1 1 1")
    b = ext.Bundles({"2.3.1": {"XYZ_X01.xsd": own}, "2.4": {"XYZ_X01.xsd": v24}})
    _, log = _named(rows, "2.3", "XYZ_X01", b)
    assert [(e["name"], e["source"]) for e in log] == [("VISIT", "v2xml-v2.3.1"), ("INSURANCE", "v2xml-v2.4"),
                                                      ("NOK_ALLERGY", "v2xml-v2.4")], log
    assert log[0]["cite"] == ("HL7-xml 2.3.1/XYZ_X01.xsd, XYZ_X01.VISIT.CONTENT, generator "
                              "urn:com.sun:encoder-hl7-1.0, derived for v2.3 XYZ_X01"), log[0]
    assert log[1]["cite"].startswith("HL7-xml v2.4/XYZ_X01.xsd, XYZ_X01.INSURANCE.CONTENT, derived for v2.3 XYZ_X01"), log[1]
    assert "CHOICE" in log[2]["cite"] and "refused" in log[2]["cite"], log[2]
    # A synthesised v2.3 ID (XYZ_X03) matches a v2.3.1 file of the same message code, cited with both IDs.
    _, log = _named(rows[:5], "2.3", "XYZ_X03", b)
    assert [(e["name"], e["source"]) for e in log] == [("VISIT", "v2xml-v2.3.1")], log
    assert log[0]["cite"].endswith("derived for v2.3 XYZ_X03, which differs from XYZ_X01 only by trigger"), log[0]
    # Neither bundle: synthesised, the citation naming both misses.
    _, log = _named(["MSH", "[", "OBR", "NTE", "]"], "2.3", "XYZ_X01", b)
    assert log[0]["source"] == "synthesised" and "HL7-xml 2.3.1" in log[0]["cite"] and "v2.4" in log[0]["cite"], log
    # v2.3.1 itself still never derives through its own bundle under the derived source.
    _, log = _named(rows[:5], "2.3.1", "XYZ_X01", b)
    assert [(e["name"], e["source"]) for e in log] == [("VISIT", "v2xml")], log
    # nameSource validation: v2xml-v2.3.1 on v2.3 only, cited by the folder as on disk.
    def names(source, citation, version="2.3"):
        return {"structure": "XYZ_X01", "version": version, "citation": f"c. Unprinted group names: {citation}.",
                "elements": [{"group": "G", "nameSource": source, "min": 0, "max": 1, "elements": []}]}
    ext.validate_names(names("v2xml-v2.3.1", "G (HL7-xml 2.3.1/XYZ_X01.xsd, XYZ_X01.G.CONTENT, derived for v2.3 XYZ_X01)"))
    for bad in (names("v2xml-v2.3.1", "G (HL7-xml 2.3.1/XYZ_X01.xsd, XYZ_X01.G.CONTENT)", "2.3.1"),
                names("v2xml-v2.3.1", "G (HL7-xml 2.3.1/XYZ_X01.xsd, XYZ_X01.G.CONTENT)", "2.4"),
                names("v2xml-v2.3.1", "G (HL7-xml v2.3.1/XYZ_X01.xsd, XYZ_X01.G.CONTENT)")):
        try:
            ext.validate_names(bad)
        except ext.NameSourceError:
            continue
        raise AssertionError(f"{bad} must be rejected")


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


def check_primary_print_by_section():
    # S3-3 (v2.3 ORM^O01, four prints under one caption): a primaryPrints print may be named
    # "CAPTION (section N)" to tell apart prints under one caption, and stricter may list several.
    strict = [("MSH", "Header"), ("[", "--- R begin"), ("PID", "Patient"), ("QRI", "Q"), ("]", "--- R end")]
    loose = [("MSH", "Header"), ("[{", "--- R begin"), ("PID", "Patient"), ("[QRI]", "Q"), ("}]", "--- R end")]
    other = [("MSH", "Header"), ("PID", "Patient"), ("[QRI]", "Q"), ("[NTE]", "Notes")]
    text = (_page(1, _table("XYZ^X01^XYZ_X01", strict), heading="9.1.1           XYZ - synthetic (Event X01)")
            + _page(2, _table("XYZ^X01^XYZ_X01", loose), heading="9.1.2           XYZ - synthetic (Event X01)")
            + _page(3, _table("XYZ^X01^XYZ_X01", other), heading="9.1.3           XYZ - synthetic (Event X01)"))
    structures, _, _ = _run("2.5.1", [("syn", text)], full=True)
    assert structures["XYZ_X01"]["elements"][1]["max"] == 1, structures
    entry = {"version": "2.5.1", "structure": "XYZ_X01", "primary": "XYZ^X01^XYZ_X01 (section 9.1.2)",
             "stricter": ["XYZ^X01^XYZ_X01 (section 9.1.1)", "XYZ^X01^XYZ_X01 (section 9.1.3)"],
             "citation": "Looser of three prints primary (synthetic)."}
    fix = {**EMPTY, "primaryPrints": [entry]}
    ext.validate_overrides(fix)
    structures, report, _ = _run("2.5.1", [("syn", text)], fix, full=True)
    s = structures["XYZ_X01"]
    assert (s["elements"][1]["min"], s["elements"][1]["max"]) == (0, None), s
    assert "Looser of three prints primary (synthetic)." in s["citation"] and "9.1.2" in s["citation"], s["citation"]
    assert not [r for r in report if r[1] == "error"], report
    stale = {**EMPTY, "primaryPrints": [{**entry, "stricter": ["XYZ^X01^XYZ_X01 (section 9.1.9)"]}]}
    _, report, _ = _run("2.5.1", [("syn", text)], stale, full=True)
    assert [r[2] for r in report if r[1] == "error"] == [
        "primaryPrints entry 'XYZ^X01^XYZ_X01 (section 9.1.2)' / ['XYZ^X01^XYZ_X01 (section 9.1.9)'] "
        "matches no print"], report
    for bad in ({**entry, "stricter": []}, {**entry, "stricter": [entry["primary"]]}):
        try:
            ext.validate_overrides({**EMPTY, "primaryPrints": [bad]})
        except ext.OverridesError:
            continue
        raise AssertionError(f"accepted {bad['stricter']!r}")


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
    # An ellipsis alone in the description column between syntax rows (v2.4 and v2.5.1 CH05
    # ERP^R09) stands for unlisted segments: ruling G6, unreadable.
    for dots in ("...", ". . ."):
        s, report = _structure([("MSH", "Header"), ("ERQ", "Query"), ("", dots), ("[ DSC ]", "Continuation")])
        assert s is None and "placeholder (G6)" in [r for r in report if r[1] == "skipped"][0][2], report


def check_syntax_cell_erratum_occurrence():
    # P8b-13 (v2.4 CH04 OML_O21): the print closes a '{' group with ']', and ']' recurs in the
    # print; "occurrence" narrows the erratum to the n-th such row. It is valid on syntax-cell
    # and (P8b-14) caption errata only.
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
    for bad in ({**entry, "occurrence": 0}, {**entry, "where": "group-mark"}):
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


def _raw_structure(body, sid="XYZ_X01", bundles=None):
    """A synthetic print whose rows are raw lines (columns: syntax at 4, description at 30)."""
    caption = f"XYZ^X01^{sid}".ljust(26)
    text = _page(1, [f"    {caption}Synthetic Message        Status    Chapter"] + body,
                 heading="9.1.1           XYZ - synthetic (Event X01)")
    structures, report, _ = ext.extract_version("2.5.1", [("syn", text)], EMPTY, tables=[], bundles=bundles)
    return structures.get(sid), report


def _row(left, desc="", chapter=""):
    return f"    {left.ljust(26)}{desc}".ljust(70) + chapter if chapter else f"    {left.ljust(26)}{desc}".rstrip()


def _slot(name="Order Detail Segment", lo=1):
    return {"slot": name, "min": lo, "max": None}


def _uncited(e):
    """An element tree with each slot's citation dropped (asserted separately)."""
    if "slot" in e:
        return {k: v for k, v in e.items() if k != "citation"}
    if "elements" in e:
        return {**e, "elements": [_uncited(x) for x in e["elements"]]}
    if "alternatives" in e:
        return {**e, "alternatives": [_uncited(x) for x in e["alternatives"]]}
    return e


def _order_group(s):
    """The repeating ORC group's elements (index 2 after MSH and PID)."""
    group = s["elements"][2]
    assert (group["min"], group["max"]) in ((0, None), (1, None)), group
    return [_uncited(e) for e in group["elements"]]


ORDER_HEAD = [_row("MSH", "Header"), _row("PID", "Patient"), _row("{", ""), _row("ORC", "Common Order", "4")]


def check_slot_ch04_own_line():
    # S3-2, v2.3 CH04 4.2.1 ORM^O01 (p 4-4): "[" on its own line, then "Order Detail Segment OBR,
    # etc." crossing the description column, then the detail's segments and "]". The slot heads
    # the optional inner group: ORC [ slot [{NTE}] [{DG1}] ], never ORC slot [{NTE}] (a bare ORC
    # is compliant).
    body = ORDER_HEAD + [_row("["), "    Order Detail Segment OBR, etc.".ljust(70) + "4",
                         _row("[{NTE}]", "Notes", "2"), _row("[{DG1}]", "Diagnosis", "6"), _row("]"), _row("}")]
    s, report = _raw_structure(body)
    assert s, report
    detail = _order_group(s)
    assert detail[0] == _seg("ORC"), detail
    inner = detail[1]
    assert (inner["min"], inner["max"]) == (0, 1), inner
    assert inner["elements"] == [_slot(), _seg("NTE", 0, None), _seg("DG1", 0, None)], inner["elements"]
    assert len(detail) == 2, detail
    # v2.3.1 CH04 4.2.1 (p 4-4) wraps it: "Order Detail" then "Segment OBR, etc." further left.
    body = ORDER_HEAD + [_row("["), _row("Order Detail", "", "4"), "  Segment OBR, etc.",
                         _row("[{NTE}]", "Notes", "2"), _row("]"), _row("}")]
    s, report = _raw_structure(body)
    assert s, report
    assert _order_group(s)[1]["elements"] == [_slot(), _seg("NTE", 0, None)], _order_group(s)


def check_slot_ch04_bracketed_alone():
    # S3-2, v2.3 CH04 4.2.2 ORR^O02 (p 4-5) and 4.2.3 OSR^Q06: "[Order Detail Segment] OBR, etc."
    # brackets the placeholder alone: the slot is optional (min 0) and the citation says why.
    body = ORDER_HEAD + ["    [Order Detail Segment] OBR, etc.".ljust(70) + "4", _row("[{NTE}]", "Notes", "2"),
                         _row("}")]
    s, report = _raw_structure(body)
    assert s, report
    detail = _order_group(s)
    assert detail == [_seg("ORC"), _slot(lo=0), _seg("NTE", 0, None)], detail
    slot = s["elements"][2]["elements"][1]
    assert "brackets the placeholder alone" in slot["citation"], slot["citation"]
    # Wrapped (v2.3.1 ORR^O02): "[Order Detail" then "Segment] OBR, etc.".
    body = ORDER_HEAD + [_row("[Order Detail", "", "4"), "  Segment] OBR, etc.", _row("[{NTE}]", "Notes", "2"),
                         _row("}")]
    s, report = _raw_structure(body)
    assert s and _order_group(s)[1] == _slot(lo=0), (s, report)
    # In the description column with an empty syntax cell (v2.3.1 OSR^Q06, p 4-5).
    body = ORDER_HEAD + [" " * 30 + "[Order Detail Segment] OBR, etc.".ljust(36) + "4", _row("[{NTE}]", "Notes", "2"),
                         _row("}")]
    s, report = _raw_structure(body)
    assert s and _order_group(s)[1] == _slot(lo=0), (s, report)


def check_slot_ch12_bracket_form():
    # S3-2, v2.4 CH12 12.3.2 PPR^PC1 (p 12-11): [{ORC [OBR, etc [{NTE}] [{VAR}] [{OBX [{NTE}]}] ] }].
    # "[OBR, etc" opens the inner group with the slot as its head: slot min 1 inside an optional
    # group; the repeating ORC group keeps its brackets. Every printed spelling reads the same.
    for cell in ("[OBR, etc", "[OBR, etc.", "[OBR, etc..."):
        body = [_row("MSH", "Header"), _row("PID", "Patient"), _row("[{ORC", "Common Order", "4"),
                _row(cell, "Order Detail Segment, etc.", "4"), _row("[{NTE}]", "Notes", "2"),
                _row("[{VAR}]", "Variance", "12"), _row("[{OBX", "Observation", "7"), _row("[{NTE}]", "Notes", "2"),
                _row("}]"), _row("]"), _row("}]")]
        s, report = _raw_structure(body)
        assert s, (cell, report)
        group = s["elements"][2]
        assert (group["min"], group["max"]) == (0, None), group
        detail = _order_group(s)
        assert detail[0] == _seg("ORC") and len(detail) == 2, detail
        inner = detail[1]
        assert (inner["min"], inner["max"]) == (0, 1), inner
        assert inner["elements"][:3] == [_slot(), _seg("NTE", 0, None), _seg("VAR", 0, None)], inner["elements"]
    # One space between the cell and the description (v2.3 CH12 12.3.3 PPP^PCB, p 12-11).
    body = [_row("MSH", "Header"), _row("PID", "Patient"), _row("[{ORC", "Common Order", "4"),
            "    [OBR, etc Order Detail Segment, etc.".ljust(70) + "4", _row("[{NTE}]", "Notes", "2"), _row("]"),
            _row("}]")]
    s, report = _raw_structure(body)
    assert s, report
    assert _order_group(s)[1]["elements"] == [_slot(), _seg("NTE", 0, None)], _order_group(s)


def check_slot_choice_with_placeholder():
    # S3-2, v2.5.1 to v2.8.2 CH12 "< OBR | etc. >": a choice whose last alternative is the
    # placeholder is one slot in place of the whole choice (a slot never sits inside a choice);
    # the listed alternatives are named in the citation. Spellings: "etc." alone in the
    # description column, "..." with "etc." (v2.5.1 PRR^PC5), "Hxx" with "etc." (v2.8.2), and a
    # "--- CHOICE" mark with or without begin/end (v2.7.1, v2.8.2 PGL^PC6).
    for alt, marks in ((("", "etc."), ("", "")), (("...", "etc."), ("", "")), (("Hxx", "etc."), ("", "")),
                       (("Hxx", "etc."), ("--- CHOICE begin", "--- CHOICE end")),
                       (("Hxx", "etc."), ("--- CHOICE", "--- CHOICE"))):
        body = [_row("MSH", "Header"), _row("PID", "Patient"), _row("[{", "--- ORDER begin"), _row("ORC", "Common Order"),
                _row("[", "--- ORDER_DETAIL begin"), _row("<", marks[0]), _row("OBR", "Order Detail Segment", "4"),
                _row("|"), _row(*alt), _row(">", marks[1]), _row("[{NTE}]", "Notes", "2"),
                _row("]", "--- ORDER_DETAIL end"), _row("}]", "--- ORDER end")]
        s, report = _raw_structure(body)
        assert s, (alt, marks, report)
        detail = s["elements"][2]["elements"][1]
        assert detail["group"] == "ORDER_DETAIL" and detail["min"] == 0, detail
        assert [_uncited(e) for e in detail["elements"]] == [_slot(), _seg("NTE", 0, None)], detail["elements"]
        cite = detail["elements"][0]["citation"]
        assert "< OBR | " in cite and "OBR" in cite.split("alternative")[-1], cite
    # A bare "--- CHOICE" mark on a choice that is NOT a slot is still unread.
    body = [_row("MSH", "Header"), _row("<", "--- CHOICE"), _row("OBR", "Order"), _row("|"), _row("RXO", "Pharmacy"),
            _row(">", "--- CHOICE")]
    s, report = _raw_structure(body)
    assert s is None and "group mark not read" in [r for r in report if r[1] == "skipped"][0][2], report
    # The placeholder anywhere but last, or "..." with any description but "etc.", stays unread.
    for rows in ([_row("<"), _row("", "etc."), _row("|"), _row("OBR", "Order"), _row(">")],
                 [_row("<"), _row("OBR", "Order"), _row("|"), _row("...", "more"), _row(">")]):
        s, report = _raw_structure([_row("MSH", "Header")] + rows)
        assert s is None, (rows, s)


def check_slot_citation_and_render():
    # S3-2: the slot's citation is built like the structure's (version, chapter, section, title)
    # plus the page of the slot's own row, quotes the print, and renders in the S3-1 JSON form.
    body = ORDER_HEAD + [_row("["), "    Order Detail Segment OBR, etc.".ljust(70) + "4",
                         _row("[{NTE}]", "Notes", "2"), _row("]"), _row("}")]
    s, _ = _raw_structure(body)
    slot = s["elements"][2]["elements"][1]["elements"][0]
    assert slot["citation"].startswith("HL7 v2.5.1 Chapter 9, section 9.1.1 XYZ - synthetic (Event X01), p 9-1: "), \
        slot["citation"]
    assert "'Order Detail Segment OBR, etc.'" in slot["citation"], slot["citation"]
    assert "_at" not in slot, slot
    text = ext.render(s)
    assert ('{ "slot": "Order Detail Segment", "min": 1, "max": null, "citation": "HL7 v2.5.1 Chapter 9' in text), text
    assert "Order Detail Segment" in ext.compact(s["elements"]), ext.compact(s["elements"])


def check_slot_never_from_query_template_or_prose():
    # S3-2 keeps ruling G6 for query templates and S5 for prose: an ellipsis row, "[...]", a
    # lone "..." cell and a "see section" prose row inside a group still leave the print unread.
    cases = [[_row("MSH", "Header"), _row("ERQ", "Query"), _row("", "..."), _row("[ DSC ]", "Continuation")],
             [_row("MSH", "Header"), _row("[...]", "Query results")],
             [_row("MSH", "Header"), _row("...", "Segments of the query")],
             [_row("MSH", "Header"), _row("[", ""), _row("PID", "Patient"),
              "    see section 4.2.1 for the order detail segments that may appear here", _row("]", "")]]
    for body in cases:
        s, report = _raw_structure(body)
        assert s is None and [r for r in report if r[1] == "skipped"], (body, report)
    # Nor does "OBR, etc." in a plain description (the CH04 choice's description column).
    s, _ = _structure([("MSH", "Header"), ("ORC", "Order"), ("<OBR|RQD|RXO>", "Order Detail Segment OBR, etc."),
                       ("[{NTE}]", "Notes")])
    assert not any("slot" in e for e in s["elements"]), s["elements"]


def check_slot_bundle_naming():
    # S3-2: an unnamed group holding a slot takes the bundle's name when the bundle group sits at
    # the same path, its members include every printed segment and more (the slot's fillers),
    # and its first segment is one of those fillers when the slot is the head (v2.4 PPR^PC1's
    # ORDER and ORDER_DETAIL against HL7-xml v2.4, where the slot's place is a CHOICE of OBR, RXO).
    b = _bundles("2.5.1", {"XYZ_X01": _xsd("XYZ_X01", "XYZ_X01: MSH 1 1, PID 1 1, XYZ_X01.ORDER 0 unbounded;"
                                                      "XYZ_X01.ORDER: ORC 1 1, XYZ_X01.ORDER_DETAIL 0 1;"
                                                      "XYZ_X01.ORDER_DETAIL: XYZ_X01.CHOICE 1 1, NTE 0 unbounded;"
                                                      "XYZ_X01.CHOICE choice: OBR 1 1, RXO 1 1")})
    body = [_row("MSH", "Header"), _row("PID", "Patient"), _row("[{ORC", "Common Order", "4"),
            _row("[OBR, etc", "Order Detail Segment, etc.", "4"), _row("[{NTE}]", "Notes", "2"), _row("]"), _row("}]")]
    s, report = _raw_structure(body, bundles=b)
    assert s, report
    order = s["elements"][2]
    assert (order["group"], order["nameSource"]) == ("ORDER", "v2xml"), order
    assert (order["elements"][1]["group"], order["elements"][1]["nameSource"]) == ("ORDER_DETAIL", "v2xml"), order
    # A bundle group whose first segment is a printed one is not the slot's group.
    b = _bundles("2.5.1", {"XYZ_X01": _xsd("XYZ_X01", "XYZ_X01: MSH 1 1, PID 1 1, XYZ_X01.ORDER 0 unbounded;"
                                                      "XYZ_X01.ORDER: ORC 1 1, XYZ_X01.ORDER_DETAIL 0 1;"
                                                      "XYZ_X01.ORDER_DETAIL: NTE 0 unbounded, OBR 1 1")})
    s, report = _raw_structure(body, bundles=b)
    assert s["elements"][2]["elements"][1]["nameSource"] == "synthesised", s["elements"][2]
    assert s["elements"][2]["elements"][1]["group"] == "NTE_GROUP", s["elements"][2]


def check_slot_bundle_naming_path_bound():
    # S3-4 (S3-2 review): the slot-heads rule takes any non-printed first segment, so the parent
    # path is what bounds it. The bundle's ORDER_DETAIL would match the slot's group (OBR heads it,
    # NTE and more are members) but sits under WRAP, not at the root where the print sets the
    # group, so it does not name it; the root's own group WRAP is headed by a printed segment.
    b = _bundles("2.5.1", {"XYZ_X01": _xsd("XYZ_X01", "XYZ_X01: MSH 1 1, PID 1 1, XYZ_X01.WRAP 0 1;"
                                                      "XYZ_X01.WRAP: NTE 1 1, XYZ_X01.ORDER_DETAIL 0 1;"
                                                      "XYZ_X01.ORDER_DETAIL: XYZ_X01.CHOICE 1 1, NTE 0 unbounded;"
                                                      "XYZ_X01.CHOICE choice: OBR 1 1, RXO 1 1")})
    body = [_row("MSH", "Header"), _row("PID", "Patient"),
            _row("[OBR, etc", "Order Detail Segment, etc.", "4"), _row("[{NTE}]", "Notes", "2"), _row("]")]
    s, report = _raw_structure(body, bundles=b)
    assert s, report
    assert s["elements"][2]["nameSource"] == "synthesised", s["elements"][2]


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
          check_two_part_caption_through_0354, check_two_part_caption_with_direction, check_section_title_caption, check_primary_print_and_duplicates,
          check_excluded_print_never_primary, check_footnotes_inside_table, check_group_mark_errata,
          check_bracket_split_and_group_of_a_group, check_shared_triggers, check_0354_reconciliation,
          check_caption_errata, check_reader_layouts,
          check_v23_synthesised_ids_no_table, check_conformance_print_never_primary, check_general_ack_fold_code_alone,
          check_empty_or_run_on_print_unreadable, check_caption_wrapping_its_id, check_grid_row_not_a_caption,
          check_repeat_indented_past_caption, check_group_close_erratum, check_primary_print_override, check_primary_print_by_section,
          check_bracketless_named_group, check_no_bar_choice_is_named_required_group, check_syntax_cell_erratum,
          check_first_row_left_of_caption, check_caption_scoped_exclusion, check_union_prints,
          check_colon_caption_with_space_ends_table, check_v282_reader_layouts, check_v271_reader_layouts,
          check_0354_triggers_merged, check_v24_reader_layouts, check_syntax_cell_erratum_occurrence,
          check_bundle_name_no_group_can_hold, check_v231_bundle_encoder_style,
          check_v231_names_bundle_then_v24_then_synthesised, check_two_structure_match_needs_declaration,
          check_unresolved_caption_declared, check_space_before_caret_caption, check_v231_name_source_validation,
          check_caption_erratum_occurrence, check_caption_structure_declared, check_v231_own_bundle_other_trigger,
          check_table_0354_provenance, check_table_0354_event_erratum_union, check_v23_events_from_title,
          check_v23_caption_forms, check_closing_bracket_in_description_column, check_v23_names_through_v231_then_v24,
          check_single_space_cell_and_shifted_page, check_referenced_triggers, check_withdrawn_segments,
          check_slot_ch04_own_line, check_slot_ch04_bracketed_alone, check_slot_ch12_bracket_form,
          check_slot_choice_with_placeholder, check_slot_citation_and_render,
          check_slot_never_from_query_template_or_prose, check_slot_bundle_naming,
          check_slot_bundle_naming_path_bound, check_keyed_choices, check_aliases, check_error_responses]


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
