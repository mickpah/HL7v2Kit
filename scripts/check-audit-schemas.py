#!/usr/bin/env python3
"""Self-check for the scripts/audit-schemas.py predicates. No PDFs, no pytest.

    python3 scripts/check-audit-schemas.py

Each check is a plain function of asserts. The script exits 1 when any check fails, so CI
can run it in the fixture-safety job (Python is on the runner; nothing else is needed).
"""
import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("audit_schemas", os.path.join(HERE, "audit-schemas.py"))
audit = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(audit)


def check_c_is_compared():
    # X-C10 / V26-C07: the M19 predicate used to skip any slot where either side was C.
    assert audit.optionality_finding("C", {"O"}), "schema C against a printed O must be a finding"
    assert audit.optionality_finding("O", {"C"}), "schema O against a printed C must be a finding"
    assert audit.optionality_finding("R", {"C"}), "schema R against a printed C must be a finding"
    assert not audit.optionality_finding("C", {"C"}), "C modelled as printed is not a finding"
    assert not audit.optionality_finding("B", {"B"}), "B modelled as printed is not a finding"
    assert not audit.optionality_finding("O", set()), "an unextracted slot has nothing to compare"


def check_defining_table_wins():
    # V23-C13: v2.3 OBX. CH7 Figure 7-5 (normative) prints OBX-1 LEN 10 and OBX-3 LEN 590;
    # the later "Observational Simple" variant and the CH9 table print 4 and 80.
    normative = [{"index": 1, "len": "10", "optionality": "O"},
                 {"index": 3, "len": "590", "optionality": "R"},
                 {"index": 17, "len": "60", "optionality": "O"}]
    variant = [{"index": 1, "len": "4", "optionality": "O"},
               {"index": 3, "len": "80", "optionality": "R"}]
    later_full = [{"index": 1, "len": "4", "optionality": "O"},
                  {"index": 3, "len": "80", "optionality": "R"},
                  {"index": 17, "len": "80", "optionality": "O"}]
    union = {("OBX", 1): {"10", "4"}, ("OBX", 3): {"590", "80"}, ("OBX", 17): {"60", "80"}}
    defining = audit.defining_rows([("OBX", normative), ("OBX", variant), ("OBX", later_full)])
    assert audit.printed_for(defining, union, "OBX", 1, "len") == {"10"}
    assert audit.printed_for(defining, union, "OBX", 3, "len") == {"590"}
    assert audit.printed_for(defining, union, "OBX", 17, "len") == {"60"}
    # A shallower variant printed first does not become the defining table.
    first_variant = audit.defining_rows([("OBX", variant), ("OBX", normative)])
    assert audit.printed_for(first_variant, union, "OBX", 1, "len") == {"10"}


def check_blank_defining_cell_falls_back():
    defining = audit.defining_rows([("PID", [{"index": 1, "len": "", "optionality": "O"}])])
    union = {("PID", 1): {"4"}}
    assert audit.printed_for(defining, union, "PID", 1, "len") == {"4"}
    assert audit.printed_for(defining, union, "NTE", 1, "len") == set()


def check_whitelists_cite():
    for name in ("OPTIONALITY_WHITELIST", "REPEATABILITY_WHITELIST",
                 "LENGTH_WHITELIST", "DATATYPE_WHITELIST", "UNREADABLE_WHITELIST"):
        wl = getattr(audit, name)
        assert isinstance(wl, dict), f"{name} must map each entry to its spec citation"
        for key, why in wl.items():
            assert isinstance(why, str) and len(why.strip()) >= 20, f"{name}{key} carries no citation"
    for key in (("v2.6", "ORC", 8), ("v2.6", "OBR", 29)):
        assert key in audit.OPTIONALITY_WHITELIST, f"{key} is the prose-backed C V26-C13 records"


def check_no_deferred_versions():
    # M5 closed 2026-09-16: every version is swept, so an absent segment is a PRESENCE defect.
    assert audit.DEFERRED_VERSIONS == set(), f"stale deferral: {sorted(audit.DEFERRED_VERSIONS)}"


def check_natural_chapter_order():
    got = sorted(["CH10.pdf", "CH2.pdf", "CH7.pdf"], key=audit.natural_key)
    assert got == ["CH2.pdf", "CH7.pdf", "CH10.pdf"], got


def check_table_open():
    # P2-15: a per-field `tableOpen` must be a boolean on a field with a table binding, and
    # must carry the cited prose that opens the table; a citation needs the flag.
    base = {"index": 31, "dataType": "ID", "table": "0136", "tables": ["0136"]}
    cite = 'v2.4 Chapter 3 section 3.4.2.31 PID-31: "... for suggested values."'
    good = dict(base, tableOpen=True, tableOpenCitation=cite)
    assert audit.table_open_findings(good) == [], "a well-formed entry is not a finding"
    assert audit.table_open_findings(dict(base)) == [], "an unmarked field is not a finding"
    cases = {
        "missing citation": dict(base, tableOpen=True),
        "blank citation": dict(base, tableOpen=True, tableOpenCitation="  "),
        "non-bool flag": dict(base, tableOpen="yes", tableOpenCitation=cite),
        "flag without tables": {"index": 1, "dataType": "ST", "tableOpen": True, "tableOpenCitation": cite},
        "citation without flag": dict(base, tableOpenCitation=cite),
    }
    for name, field in cases.items():
        assert audit.table_open_findings(field), f"{name} must be a finding"


def check_additional_prohibitions():
    # P4-21: `additionalProhibitions` is a non-empty list of {when, severity, citation}
    # rules; each needs a '<referent> <predicate>' condition, a known severity and a citation.
    cite = 'v2.5.1 Chapter 4 section 4.14.2.6 RXR-6: "... then RXR-6 should not be populated."'
    rule = {"when": "RXR-2.3 = HL70163 OR RXR-2.6 = HL70163", "severity": "warning", "citation": cite}
    base = {"index": 6, "dataType": "CWE", "prohibitedWhen": "RXR-2 empty"}
    assert audit.additional_prohibition_findings(dict(base, additionalProhibitions=[rule])) == [], \
        "a well-formed rule is not a finding"
    assert audit.additional_prohibition_findings(dict(base)) == [], "a field without the key is not a finding"
    cases = {
        "not a list": dict(base, additionalProhibitions=rule),
        "empty list": dict(base, additionalProhibitions=[]),
        "missing citation": dict(base, additionalProhibitions=[dict(rule, citation=None)]),
        "blank citation": dict(base, additionalProhibitions=[dict(rule, citation="  ")]),
        "unknown severity": dict(base, additionalProhibitions=[dict(rule, severity="fatal")]),
        "one-token when": dict(base, additionalProhibitions=[dict(rule, when="RXR-2")]),
        "tab in when": dict(base, additionalProhibitions=[dict(rule, when="RXR-2.3\t= HL70163")]),
        "newline in when": dict(base, additionalProhibitions=[dict(rule, when="RXR-2.3 =\nHL70163")]),
        "leading space": dict(base, additionalProhibitions=[dict(rule, when=" RXR-2.3 = HL70163")]),
        "unknown key": dict(base, additionalProhibitions=[dict(rule, note="x")]),
    }
    for name, field in cases.items():
        assert audit.additional_prohibition_findings(field), f"{name} must be a finding"


def check_optionality_citation():
    # P4-30: a field's `optionalityCitation` is its optionality whitelist entry. A departure
    # from the print needs it (or an OPTIONALITY_WHITELIST entry); a citation on a slot that
    # matches the print is stale.
    cite = "v2.5.1 CH08 section 8.5.1.6: 'Required for MFN-Master File Notification message'"
    f = audit.optionality_citation_finding
    assert f("C", {"R"}, cite, False) is None, "a cited departure is not a finding"
    assert f("C", {"R"}, None, False) == "uncited", "an uncited departure is a finding"
    assert f("C", {"R"}, "  ", False) == "uncited", "a blank citation does not cite"
    assert f("C", {"R"}, None, True) is None, "an OPTIONALITY_WHITELIST entry still cites"
    assert f("R", {"R"}, cite, False) == "stale", "a citation on a printed match is stale"
    assert f("R", set(), cite, False) is None, "an unextracted slot has nothing to compare"
    assert f("R", {"R"}, None, False) is None, "a printed match without a citation is clean"
    assert not any(k[1:] in {("MFI", 6), ("CSR", 8), ("ROL", 4)} for k in audit.OPTIONALITY_WHITELIST), \
        "P4-30 slots cite through optionalityCitation, not the whitelist"


def check_condition_predicate():
    # P4-31 (ADR-021): `conditionIsPredicate` marks a stored condition as the full C
    # predicate. It needs a cited `predicateCitation`, a C field and a condition; a
    # citation without the marker is stale.
    cite = "v2.4 Chapter 7 section 7.4.2.2: 'It must be valued if OBX-11 is not valued with an X.'"
    base = {"index": 2, "optionality": "C", "condition": "OBX-11 != X"}
    f = audit.condition_predicate_findings
    assert f(base) == [], "an unmarked field is clean"
    assert f(dict(base, conditionIsPredicate=True, predicateCitation=cite)) == [], "a cited marker is clean"
    cases = {
        "uncited": dict(base, conditionIsPredicate=True),
        "blank citation": dict(base, conditionIsPredicate=True, predicateCitation="   "),
        "short citation": dict(base, conditionIsPredicate=True, predicateCitation="see spec"),
        "not C": dict(base, optionality="O", conditionIsPredicate=True, predicateCitation=cite),
        "no condition": dict({"index": 2, "optionality": "C"}, conditionIsPredicate=True, predicateCitation=cite),
        "false marker": dict(base, conditionIsPredicate=False, predicateCitation=cite),
        "string marker": dict(base, conditionIsPredicate="true", predicateCitation=cite),
        "citation alone": dict(base, predicateCitation=cite),
    }
    for name, field in cases.items():
        assert f(field), f"{name} must be a finding"


def check_swift_name():
    # P6-9: the extractor let definition prose bleed into swiftName (v2.5.1 TQ2-10 shipped at
    # 873 characters; QPD-2 absorbed the next row's "User Parameters (in successive fields)")
    # and cut others short (v2.8.2 RXA-2 "nistrationSubIdCounter", v2.4 RXE-6 "field4").
    f = audit.swift_name_findings
    clean = {
        "plain": ("administrationSubIdCounter", "Administration Sub-ID Counter", None),
        "set id": ("setIdTq2", "Set ID - TQ2", None),
        "digits glued": ("hl7ErrorCode", "HL7 Error Code", None),
        "initials": ("ruDateTime", "R/U Date/Time", None),
        "hyphen joined": ("readmissionIndicator", "Re-Admission Indicator", None),
        "longest printed": ("observationIdentifierAssociatedWithProducerServiceTestObservationId",
                            "Observation/Identifier associated with Producer's Service/Test/Observation ID", None),
        "inherited canonical": ("administrativeSex", "Sex", "administrativeSex"),
    }
    for name, (swift, element, canonical) in clean.items():
        assert f({"swiftName": swift, "name": element}, canonical) == [], f"{name} must be clean"
    bad = {
        "truncated head": ("nistrationSubIdCounter", "Administration Sub-ID Counter", None),
        "placeholder": ("field4", "Give Dosage Form", None),
        "next row glued on": ("queryTagUserParametersInSuccessiveFields", "Query Tag", None),
        "prose bleed": ("bpUniqueIdOrCommerciallyPreparedBloodProductThatIsTributePertainsToAny",
                        "BP Unique ID", None),
        "over the bound": ("a" + "b" * audit.SWIFT_NAME_MAX, "A" + "b" * audit.SWIFT_NAME_MAX, None),
        "underscore": ("query_tag", "Query Tag", None),
        "upper first": ("QueryTag", "Query Tag", None),
        "empty": ("", "Query Tag", None),
        "inherited but differs": ("nistrationSubIdCounter", "Administration Sub-ID Counter",
                                  "administrationSubIdCounter"),
    }
    for name, (swift, element, canonical) in bad.items():
        assert f({"swiftName": swift, "name": element}, canonical), f"{name} must be a finding"
    # The deprecated alias key: a non-empty list of distinct identifiers, never the new name.
    base = {"swiftName": "queryTag", "name": "Query Tag"}
    assert f(dict(base, deprecatedSwiftNames=["queryTagUserParametersInSuccessiveFields"]), None) == [], \
        "a well-formed alias list is clean (old names are exempt from the length bound)"
    for name, aliases in {"empty list": [], "not a list": "queryTagOld", "same as new": ["queryTag"],
                          "duplicate": ["oldName", "oldName"], "not an identifier": ["old name"],
                          "not a string": [3]}.items():
        assert f(dict(base, deprecatedSwiftNames=aliases), None), f"alias {name} must be a finding"
    # Fix 1: a non-canonical slot whose element matches the canonical element takes the
    # canonical name. "minimum" passes the anchor rule alone (it starts a word of the name),
    # so only the canonical-name rule catches the dropped leading words (v2.3.1 RXE-3).
    rxe3 = {"swiftName": "minimum", "name": "Give Amount - Minimum"}
    assert f(rxe3, "giveAmountMinimum", "Give Amount - Minimum"), "dropped leading words must be a finding"
    assert f(dict(rxe3, swiftName="giveAmountMinimum"), "giveAmountMinimum", "Give Amount - Minimum") == [], \
        "the canonical name is clean"
    assert f({"swiftName": "totalOccurrenceS", "name": "Total Occurrences"},
             "totalOccurrenceS", "Total Occurrence's") == [], "the canonical possessive S is kept"
    assert f({"swiftName": "totalOccurrences", "name": "Total Occurrences"},
             "totalOccurrenceS", "Total Occurrence's"), "dropping the canonical possessive S is a finding"
    assert f({"swiftName": "networkChangeType", "name": "Network Change Type"},
             "applicationChangeType", "Application Change Type") == [], \
        "a renamed element may take its own derived name"
    # P9 final review: a stranded possessive "S" ([a-z]S[A-Z]) is the canonical spelling only.
    # A new name that is neither released at v3.13.0 nor canonical-inherited takes
    # `deriveSwiftName`, which drops the lone "s" (v2.8.2 ROL-13 "Person's Location").
    rol13 = {"swiftName": "personSLocation", "name": "Person's Location"}
    assert f(rol13, None, None), "a new stranded possessive S must be a finding"
    assert f(dict(rol13, swiftName="personLocation"), None, None) == [], "the derived name is clean"
    assert f(rol13, None, None, frozenset({"personSLocation"})) == [], \
        "a name released at v3.13.0 is exempt"
    assert f({"swiftName": "patientSRelationshipToInsured", "name": "Patient's Relationship to Insured"},
             "cmsPatientSRelationshipToInsured", "CMS Patient's Relationship to Insured"), \
        "a renamed element does not inherit the canonical possessive S"


def check_swift_name_uniqueness():
    # Fix 1 (Minor 2): two fields, or a field and an alias, with one accessor name.
    d = audit.duplicate_swift_names
    assert d([{"swiftName": "giveCode"}, {"swiftName": "giveUnits"}]) == [], "distinct names are clean"
    assert d([{"swiftName": "giveCode"}, {"swiftName": "giveCode"}]) == [("giveCode", 2)], \
        "a repeated swiftName must be a finding"
    assert d([{"swiftName": "queryTag"}, {"swiftName": "other", "deprecatedSwiftNames": ["queryTag"]}]), \
        "an alias that repeats another field's name must be a finding"


def check_element_name():
    # Fix 1 (Important 2): an element name is a title, not definition prose.
    e = audit.element_name_findings
    for name in ["Date/Time Stamp for any change in Definition for the Observation",   # 10 words, run 4
                 "Disability return to work date", "Generic resource type or category",
                 "Factors that may Affect Affect the Observation", "Set ID - TQ2"]:
        assert e(name) == [], f"{name!r} must be clean"
    for name in ["Substitute Allowed e requisition unit of measure that is known to the",   # old RQ1-7
                 "Approving Regulatory Agency I being CPT-4 modifiers, II CDT-2 and genuine HCPCS n "
                 "Service (NTIS, www.ntis.gov) and NTIS"]:                                  # old ITM-16
        assert e(name), f"{name[:40]!r} must be a finding"


def check_repeatability_defining_table():
    # P6-4 fix 1: M22 compares the defining table's RP/# cell. v2.5.1 OBX-8: the CH07 OBX
    # table prints 5, a constrained copy misreads the cell as Y; the union {'*', '5'} used to
    # accept a schema '*' and so hide the bound.
    defining = audit.defining_rows([("OBX", [{"index": 8, "repeatability": "5"},
                                             {"index": 9, "repeatability": "1"}]),
                                    ("OBX", [{"index": 8, "repeatability": "*"}])])
    union = {("OBX", 8): {"*", "5"}, ("OBX", 9): {"1", "5"}}
    assert audit.printed_for(defining, union, "OBX", 8, "repeatability") == {"5"}
    assert audit.printed_for(defining, union, "OBX", 9, "repeatability") == {"1"}


def check_repeatability_token_rule():
    # P6-4: integrity() accepts 1, * or a decimal bound of 2 or more, and nothing else.
    ok = audit.REPEATABILITY_TOKEN
    for good in ("1", "*", "2", "20", "200"):
        assert ok.fullmatch(good), good
    for bad in ("", "0", "Y", "Y/3", "0-5", "1000", "02"):
        assert not ok.fullmatch(bad), bad


def check_unreadable_is_reported():
    # P6-12: M19 / M22 / M25 used to `continue` silently when printed_for() came back empty
    # (152 M19 slots, 2088 M25 slots), and M22 counted any extracted token as a print.
    rows = audit.defining_rows([("NST", [{"index": 1, "optionality": "R", "len": "1",
                                          "repeatability": "1"},
                                         {"index": 2, "optionality": "", "len": "30",
                                          "repeatability": "?0244"},
                                         {"index": 3, "optionality": "60", "len": "7 05",
                                          "repeatability": "1"},
                                         {"index": 4, "optionality": "W", "len": "",
                                          "repeatability": "1"}])])
    read = lambda i, a, v="v2.4": audit.read_slot(rows, {}, "NST", i, a, v)
    assert read(1, "M19") == ({"R"}, None)
    assert read(2, "M19") == (set(), "blank cell"), "a blank OPT cell is not a print"
    assert read(9, "M19") == (set(), "no extracted row")
    assert read(3, "M19")[1].startswith("malformed"), "a number under OPT is a misread"
    assert read(3, "M25")[1].startswith("malformed"), "'7 05' is not a length"
    assert read(2, "M22")[1].startswith("malformed"), "a TBL# bleed must never match '*'"
    assert read(4, "M25") == ({""}, None), "a withdrawn field prints no length"
    assert read(2, "M25", "v2.8.2") == ({"30"}, None)
    blank = audit.defining_rows([("EVN", [{"index": 2, "optionality": "R", "len": ""}])])
    assert audit.read_slot(blank, {}, "EVN", 2, "M25", "v2.8.2") == ({""}, None), \
        "v2.8.2 prints LEN and C.LEN only if applicable (2.5.3.2)"
    assert audit.read_slot(blank, {}, "EVN", 2, "M25", "v2.7.1") == ({""}, None), \
        "v2.7.1 prints LEN and C.LEN only if applicable (2.5.3.2, CH02 p. 8; scan A19)"
    assert audit.read_slot(blank, {}, "EVN", 2, "M25", "v2.6")[1] == "blank cell"
    assert audit.unreadable_whitelisted("M19", "v2.6", "SCD", 37, "blank cell")
    assert not audit.unreadable_whitelisted("M19", "v2.6", "SCD", 38, "blank cell")
    assert not audit.unreadable_whitelisted("M25", "v2.6", "SCD", 1, "blank cell")
    # Fix 1: the reason is part of the key. A region cited for blanks hides neither a
    # malformed print nor a missing row, and one cited for a malformed print hides no blank.
    assert not audit.unreadable_whitelisted("M19", "v2.6", "SCD", 1, "malformed print ['60']")
    assert not audit.unreadable_whitelisted("M19", "v2.6", "SCD", 1, "no extracted row")
    assert audit.unreadable_whitelisted("M22", "v2.8.2", "BUI", 12, "malformed print ['?R']")
    assert not audit.unreadable_whitelisted("M22", "v2.8.2", "BUI", 12, "blank cell")
    # A cited blank is compared as "" (the schema must store it verbatim); a cited malformed
    # print is exempt; an uncited one is reported.
    seen = []
    assert audit.resolve_unreadable("M19", "v2.6", "SCD", 1, "blank cell", "", seen) == {""}
    assert audit.resolve_unreadable("M22", "v2.8.2", "BUI", 12, "malformed print ['?R']", "1", seen) is None
    assert not seen
    assert audit.resolve_unreadable("M19", "v2.6", "SCD", 1, "no extracted row", "", seen) is None
    assert seen == [("M19", "v2.6", "SCD", 1, "", "no extracted row")]
    assert audit.optionality_finding("O", {""}), "a cited blank OPT modelled O is a finding"


def check_length_token():
    ok = audit.LENGTH_TOKEN
    for good in ("4", "65536", "99999", "64K", "10k", "1..4", "250#", "20=", "2,4", "1,3,5"):
        assert ok.fullmatch(good), good
    # v2.8.2 section 2.5.5.0: "The minimum length is always 1 or more".
    for bad in ("", "0", "655362", "7 05", "2..", "=", "4..", "MRN", "1..4#", "0..1", "0,2", "2,"):
        assert not ok.fullmatch(bad), bad


def check_blank_read_never_removes_a_length():
    # Fix 1: --write-lengths used to write a blank read, removing the schema's length.
    assert audit.length_to_write({""}) is None
    assert audit.length_to_write(set()) is None
    assert audit.length_to_write({"250", "60"}) == "60"


def check_repairs_file_comment():
    # Fix 1: table-repairs.json documents itself in "_comment"; no loader treats it as a slot.
    assert not any(k.startswith("_") for k in audit.TABLE_REPAIRS)
    assert audit.LENGTH_REPAIRS.get("v2.6/UAC-1") == "705"


def check_write_lengths():
    # P6-12: write_lengths used to strip every `length` in the file before writing the listed
    # ones, so a partial sweep dropped the rest.
    import tempfile
    one = ('{ "fields": [\n    { "index": 1, "dataType": "SI", "length": "4", "optionality": "R" },\n'
           '    { "index": 2, "dataType": "ST", "length": "6", "optionality": "O" },\n'
           '    { "index": 3, "dataType": "CWE", "length": "9", "optionality": "O" }\n] }\n')
    multi = ('{ "fields": [\n    {\n      "index": 1,\n      "dataType": "CE", "length": "6",\n'
             '      "optionality": "O"\n    },\n    {\n      "index": 2,\n      "dataType": "ST",\n'
             '      "optionality": "O"\n    }\n] }\n')
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "x.json")
        open(path, "w").write(one)
        audit.write_lengths(path, {2: "250", 3: ""})
        got = {f["index"]: f.get("length") for f in audit.json.load(open(path))["fields"]}
        assert got == {1: "4", 2: "250", 3: None}, got
        open(path, "w").write(multi)
        audit.write_lengths(path, {1: "250", 2: "60"})
        got = {f["index"]: f.get("length") for f in audit.json.load(open(path))["fields"]}
        assert got == {1: "250", 2: "60"}, got


def check_field_grammar_shape():
    # P5-5: a field-local composite file (Resources/datatypes/v<X>/fields/<SEG>-<N>.json).
    good = {"field": "IN3-20", "dataType": "CM", "version": "2.4", "name": "Pre-certification req/window",
            "source": "prose-field",
            "components": [{"index": 1, "name": "Pre-certification patient type", "dataType": "IS",
                            "optionality": "", "tables": ["0150"]},
                           {"index": 2, "name": "Pre-certification window", "dataType": "TS", "optionality": ""}]}
    assert audit.field_grammar_findings("IN3-20", "v2.4", good) == []
    assert audit.field_grammar_findings("IN3-21", "v2.4", good), "field must match the path"
    assert audit.field_grammar_findings("IN3-20", "v2.3", good), "version must match the path"
    bad = dict(good, field="in3_20")
    assert any("not SEG-N" in f for f in audit.field_grammar_findings("in3_20", "v2.4", bad))
    gap = dict(good, components=[dict(good["components"][0], index=2)])
    assert any("1..n" in f for f in audit.field_grammar_findings("IN3-20", "v2.4", gap))
    opt = dict(good, components=[dict(good["components"][0], optionality="O")])
    assert any("optionality" in f for f in audit.field_grammar_findings("IN3-20", "v2.4", opt))
    table = dict(good, components=[dict(good["components"][0], tables=["0001", "8888"])])
    found = audit.field_grammar_findings("IN3-20", "v2.4", table)
    assert len(found) == 1 and "8888" in found[0], found


def check_cm_refinements():
    # P5-7 (V24-C08): a spec `CM` accepts only names whose structure is the field's own.
    assert audit.CM_REFINEMENTS == {"MSG", "MOC", "PRL", "EIP"}, audit.CM_REFINEMENTS
    assert not {"SPS", "NDL"} & audit.CM_REFINEMENTS
    for name in sorted(audit.CM_REFINEMENTS):
        assert not audit.datatype_disagrees("v2.4", "ZZZ", 1, name, {"CM"}), name
    for name in ("SPS", "NDL", "CWE", "ST"):
        assert audit.datatype_disagrees("v2.4", "ZZZ", 1, name, {"CM"}), name
    assert not audit.datatype_disagrees("v2.4", "ZZZ", 1, "CM", {"CM"})


def check_datatype_name():
    # P5-9: a datatype `name` must never carry table-of-contents residue — a trailing page
    # reference, or the run of padding spaces printed before one.
    assert audit.datatype_name_findings("address") == []
    assert audit.datatype_name_findings("extended composite ID with check digit") == []
    found = audit.datatype_name_findings("address                                         2-12")
    assert len(found) == 2, found
    assert "page reference" in found[0] and "3+ spaces" in found[1], found
    # a page reference with no padding run still trips the page-reference check alone.
    found = audit.datatype_name_findings("timing quantity 2-52")
    assert len(found) == 1 and "page reference" in found[0], found
    # a genuine hyphenated number inside a name (not at the end) is not a page reference.
    assert audit.datatype_name_findings("HL7 2-11 something") == []
    # None / empty is not a crash.
    assert audit.datatype_name_findings(None) == []
    assert audit.datatype_name_findings("") == []


def _script(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_")[:-3], os.path.join(HERE, name))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# P10 (scan rows A31, B14): a version is modelled once it has a resource tree under
# Resources/tables, Resources/schemas or Resources/datatypes. Every per-version source map in
# the audit and the extractors must name every modelled version, or an audit or extraction
# mode skips it silently. A staged rollout names here the maps it has not wired yet, each with
# the task that wires it; an entry that is no longer missing fails too, so the list empties
# as the rollout lands and never goes stale.
VERSION_MAPS_PENDING = {}   # P10-4a wired the last one (CHAPTER_GLOBS; see CHAPTER_GLOBS_STAGED)


def _modelled_versions():
    root = os.path.join(os.path.dirname(HERE), "Resources")
    found = set()
    for tree in ("tables", "schemas", "datatypes"):
        for entry in os.listdir(os.path.join(root, tree)):
            if entry.startswith("v") and os.path.isdir(os.path.join(root, tree, entry)):
                found.add(entry[1:])
    return found


def check_version_maps_agree():
    modelled = _modelled_versions()
    assert "2.7.1" in modelled, "Resources/tables/v2.7.1 is the P10-1 deliverable"
    dtx, dtp = _script("extract-datatype-components.py"), _script("extract-datatype-prose.py")
    examples = _script("extract-example-messages.py")
    structures = _script("extract-message-structures.py")
    maps = {
        "extract-message-structures.py ERAS": structures.ERAS,
        "audit-schemas.py CHAPTER_GLOBS": audit.CHAPTER_GLOBS,
        "audit-schemas.py TABLE_PDFS": audit.TABLE_PDFS,
        "audit-schemas.py EXAMPLE_SOURCES": audit.EXAMPLE_SOURCES,
        "extract-example-messages.py CHAPTERS": examples.CHAPTERS,
        "extract-datatype-components.py PDFS": dtx.PDFS,
    }
    assert set(VERSION_MAPS_PENDING) <= set(maps), sorted(set(VERSION_MAPS_PENDING) - set(maps))
    for name, table in maps.items():
        keys = {k[1:] if k.startswith("v") else k for k in table}
        pending = VERSION_MAPS_PENDING.get(name, set())
        missing = modelled - keys
        if name == "extract-datatype-components.py PDFS":
            # B14: CH02A component tables from v2.5.1 on; earlier versions are read from the
            # prose (extract-datatype-prose.py SOURCES). Together they cover each version once.
            both = keys & set(dtp.SOURCES)
            assert not both, f"read by both datatype extractors: {sorted(both)}"
            missing -= set(dtp.SOURCES)
        assert missing == pending, f"{name}: missing {sorted(missing)}, pending {sorted(pending)}"
        assert keys <= modelled, f"{name}: names unmodelled versions {sorted(keys - modelled)}"
        for key, source in table.items():
            source = source[0] if isinstance(source, tuple) else source
            for path in (source if isinstance(source, list) else [source]):
                if key.lstrip("v") == "2.7.1":
                    assert path.startswith("HL7_V271_PDF/PDF/V271_"), f"{name}: v2.7.1 source {path!r}"
    # P8b-2b (pre-flight B2): the HL7 v2.xml bundle map names every modelled version once,
    # with the explicit derived-through-v2.4 exception for 2.3 (no bundle exists) and 2.3.1
    # (its own bundle first, v2.4 as the fallback; P8b-14).
    bundled = {k[1:] for k in structures.BUNDLES}
    derived = {k[1:]: v[1:] for k, v in structures.BUNDLES_DERIVED.items()}
    assert derived == {"2.3": "2.4", "2.3.1": "2.4"}, f"bundle derivation {derived}"
    assert bundled & set(derived) == {"2.3.1"}, f"bundled and derived: {sorted(bundled & set(derived))}"
    assert bundled | set(derived) == modelled, \
        f"bundle map: missing {sorted(modelled - bundled - set(derived))}, unmodelled {sorted((bundled | set(derived)) - modelled)}"
    # The folder as on disk: the owner's v2.3.1 folder name has no "v".
    assert all(structures.BUNDLES[k] == (f"HL7-xml {k[1:]}" if k == "v2.3.1" else f"HL7-xml {k}")
               for k in structures.BUNDLES), structures.BUNDLES
    # P8b-1: the message-structure completeness data names every modelled version, and only
    # those (the codegen enforces the same against the schema directories).
    with open(os.path.join(os.path.dirname(HERE), "Resources", "structures", "completeness.json")) as f:
        completeness = set(json.load(f)["versions"])
    assert completeness == modelled, \
        f"Resources/structures/completeness.json: missing {sorted(modelled - completeness)}, " \
        f"unmodelled {sorted(completeness - modelled)}"
    # P8b-2a: the structure extractor names every version in ERAS (above) but reads some caption
    # eras only from P8b-3 on. Version.swift declares every version, so this cannot ride on
    # VERSION_MAPS_PENDING; instead a version whose era is not read yet can never be marked
    # complete, and the structure directories stay within the modelled set.
    with open(os.path.join(os.path.dirname(HERE), "Resources", "structures", "completeness.json")) as f:
        flags = json.load(f)["versions"]
    assert set(structures.ERAS_PENDING) <= set(structures.ERAS)
    unread_complete = sorted(v for v in structures.ERAS_PENDING if flags[v.lstrip("v")]["complete"])
    assert not unread_complete, f"marked complete before the extractor reads their captions: {unread_complete}"
    root = os.path.join(os.path.dirname(HERE), "Resources", "structures")
    dirs = {e[1:] for e in os.listdir(root) if e.startswith("v") and os.path.isdir(os.path.join(root, e))}
    assert dirs <= modelled, f"Resources/structures names unmodelled versions {sorted(dirs - modelled)}"


def pending_versions_released(version_source, pending=None):
    """Pending map entries whose version Version.swift already declares as a case. The staged
    chapter globs (audit CHAPTER_GLOBS_STAGED, P10-4a) count as pending CHAPTER_GLOBS."""
    if pending is None:
        pending = dict(VERSION_MAPS_PENDING)
        staged = {v.lstrip("v") for v in audit.CHAPTER_GLOBS_STAGED}
        if staged:
            pending["audit-schemas.py CHAPTER_GLOBS (staged)"] = staged
    declared = set(re.findall(r"\bcase\s+v(\d+(?:_\d+)*)\b", version_source))
    return sorted((name, v) for name, versions in pending.items()
                  for v in versions if v.replace(".", "_") in declared)


def check_pending_maps_empty_once_released():
    # P10-1 fix round 1: VERSION_MAPS_PENDING is a staging list only. Once Version.swift
    # declares the case (P10-6), every map must name the version, as DEFERRED_VERSIONS is
    # asserted empty.
    sample = {"audit-schemas.py CHAPTER_GLOBS": {"2.7.1"}}
    assert pending_versions_released("    case v2_6   = \"2.6\"\n    case v2_7_1 = \"2.7.1\"\n", sample), \
        "a declared v2_7_1 case with v2.7.1 still pending must be caught"
    assert not pending_versions_released("    case v2_6   = \"2.6\"\n", sample), "an undeclared version may stay pending"
    # P10-4a: a staged (partial) chapter glob is pending too, so it cannot outlive P10-6.
    if audit.CHAPTER_GLOBS_STAGED:
        assert pending_versions_released("    case v2_7_1 = \"2.7.1\"\n"), "a staged glob must be caught"
    assert set(audit.CHAPTER_GLOBS_STAGED) <= set(audit.CHAPTER_GLOBS)
    assert all(len(why.strip()) >= 20 for why in audit.CHAPTER_GLOBS_STAGED.values())
    source = open(os.path.join(os.path.dirname(HERE), "Sources/HL7v2Kit/Version.swift")).read()
    stale = pending_versions_released(source)
    assert not stale, f"Version.swift declares these versions but their maps are still pending: {stale}"


def check_component_table_spans_second_footer():
    # P10-2: v2.7.1 prints a second page-footer line ("2.7.1.    July 2012." on odd pages,
    # "July 2012.    2.7.1." on even pages). At the left margin it read as prose and ended
    # the component table at the page break: 14 v2.7.1 composites were truncated (CF p7 ...).
    dtx = _script("extract-datatype-components.py")
    header = "SEQ     LEN       C.LEN      DT        OPT    TBL#     COMPONENT NAME                       COMMENTS   SEC.REF."
    row = " {:<2}                 20=       ST         O              {:<33}                2.A.75"
    for footer in ("2.7.1.                                       July 2012.",
                   "July 2012.                                       2.7.1."):
        lines = ["                  HL7 Component Table - CF – Coded Element with Formatted Values", header,
                 row.format(1, "Identifier"), "",
                 "Health Level Seven, Version 2.7.1 © 2012. All rights reserved.            Page 7",
                 footer, "\f Chapter 2A: Control – Data Types", "", header,
                 row.format(2, "Alternate Identifier")]
        types = dtx.components_from_lines(lines, "2.7.1")
        got = [c["index"] for c in types["CF"]["components"]]
        assert got == [1, 2], (footer, got)
    # prose at the left margin still ends the table.
    lines = ["  HL7 Component Table - CF – Coded Element", header, row.format(1, "Identifier"),
             "Definition: This data type transmits codes.", row.format(2, "Alternate Identifier")]
    assert [c["index"] for c in dtx.components_from_lines(lines, "2.7.1")["CF"]["components"]] == [1]


def check_unicode_ellipsis_is_suspect():
    # v2.7.1 Appendix A prints the "no suggested values" row with U+2026 where the earlier
    # appendices print "..." (P10-0). Either form surviving as a code is a TOOL defect.
    assert audit.SUSPECT_CODE.search("..."), "the bare three-full-stop row"
    assert audit.SUSPECT_CODE.search("\u2026"), "the bare Unicode-ellipsis row"
    assert not audit.SUSPECT_CODE.search("2 \u2026"), "a range row is not a bare ellipsis"


def check_datatype_existence():
    # P10-4c: a field's dataType exists on its own version.
    composites = audit.composite_types()
    def found(version, dt, opt="O"):
        return audit.datatype_existence_findings(version, {"dataType": dt, "optionality": opt}, composites[version])
    assert not found("v2.7.1", "CWE") and not found("v2.7.1", "SNM") and not found("v2.7.1", "varies")
    assert not found("v2.7.1", ""), "a blank dataType is not this check's business"
    assert found("v2.7.1", "CWX"), "an unknown type is a finding"
    assert found("v2.6", "SNM"), "SNM is not a v2.6 primitive"
    assert found("v2.7.1", "CE"), "a withdrawn stub on an optional field is a finding"
    assert not found("v2.7.1", "CE", "W") and not found("v2.8.2", "TQ", "B"), "a stub on W or B is accepted"
    assert not found("v2.3", "CM") and found("v2.5.1", "CM"), "CM is field-local only before v2.5"
    assert not found("v2.4", "NA"), "v2.4 NA (CH07 sec 7.14.1.1) has its component file"
    assert all(len(why) >= 40 for why in audit.DATATYPE_EXISTENCE_EXEMPT.values())


def check_withdrawn_datatype_rule():
    # P10-4c: on a version held to the rule, a W field is typed only where its table prints a type.
    rule = audit.withdrawn_datatype_findings
    assert rule("v2.7.1", "PID", {"index": 2, "dataType": "CX", "optionality": "W"}), "a carried type"
    assert not rule("v2.7.1", "PID", {"index": 2, "dataType": "", "optionality": "W"})
    assert not rule("v2.7.1", "UB1", {"index": 1, "dataType": "SI", "optionality": "W"}), "printed SI"
    assert rule("v2.7.1", "UB1", {"index": 1, "dataType": "", "optionality": "W"}), "a printed type dropped"
    assert not rule("v2.7.1", "PID", {"index": 3, "dataType": "CX", "optionality": "R"}), "not withdrawn"
    assert rule("v2.8.2", "PID", {"index": 2, "dataType": "CX", "optionality": "W"}), "v2.8.2 held since P10-4d"
    assert not rule("v2.8.2", "UB1", {"index": 1, "dataType": "SI", "optionality": "W"}), "v2.8.2 printed SI"
    assert rule("v2.6", "MSA", {"index": 5, "dataType": "ID", "optionality": "W"}), "v2.6 held since P10-4d"
    assert not rule("v2.5.1", "MSA", {"index": 5, "dataType": "ID", "optionality": "W"}), "the v2.5.1 MSA-5 exception"
    assert rule("v2.5.1", "MSA", {"index": 5, "dataType": "", "optionality": "W"}), "an exception keeps its type"
    assert not rule("v2.4", "MSA", {"index": 5, "dataType": "ID", "optionality": "W"}), "v2.4 prints no W field"
    assert all(len(why) >= 40 for cites in audit.WITHDRAWN_TYPE_EXCEPTIONS.values() for why in cites.values())
    assert all(len(why) >= 40 for cites in audit.WITHDRAWN_TYPED_AS_PRINTED.values() for why in cites.values())


CHECKS = [check_c_is_compared, check_defining_table_wins, check_blank_defining_cell_falls_back,
          check_whitelists_cite, check_no_deferred_versions, check_natural_chapter_order,
          check_table_open, check_additional_prohibitions, check_optionality_citation,
          check_condition_predicate, check_swift_name, check_swift_name_uniqueness,
          check_element_name, check_repeatability_defining_table, check_repeatability_token_rule,
          check_unreadable_is_reported, check_length_token, check_write_lengths,
          check_blank_read_never_removes_a_length, check_repairs_file_comment,
          check_field_grammar_shape, check_cm_refinements, check_datatype_name,
          check_version_maps_agree, check_unicode_ellipsis_is_suspect,
          check_pending_maps_empty_once_released, check_component_table_spans_second_footer,
          check_datatype_existence, check_withdrawn_datatype_rule]


def main():
    failed = 0
    for check in CHECKS:
        try:
            check()
            print(f"ok   {check.__name__}")
        except Exception as exc:  # AttributeError before the fix is a failure, not a crash
            failed += 1
            print(f"FAIL {check.__name__}: {type(exc).__name__}: {exc}")
    print(f"{len(CHECKS) - failed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
