#!/usr/bin/env python3
"""Self-check for the scripts/audit-schemas.py predicates. No PDFs, no pytest.

    python3 scripts/check-audit-schemas.py

Each check is a plain function of asserts. The script exits 1 when any check fails, so CI
can run it in the fixture-safety job (Python is on the runner; nothing else is needed).
"""
import importlib.util
import os
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
                 "LENGTH_WHITELIST", "DATATYPE_WHITELIST"):
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


CHECKS = [check_c_is_compared, check_defining_table_wins, check_blank_defining_cell_falls_back,
          check_whitelists_cite, check_no_deferred_versions, check_natural_chapter_order,
          check_table_open, check_additional_prohibitions, check_optionality_citation,
          check_condition_predicate]


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
