#!/usr/bin/env python3
"""Self-check for the scripts/extract-example-messages.py extraction rules (P4-22). No
PDFs, no pytest.

    python3 scripts/check-extract-example-messages.py

Each check is a plain function of asserts. The script exits 1 when any check fails, so CI
can run it in the fixture-safety job, the same way check-audit-schemas.py does.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "extract_example_messages", os.path.join(HERE, "extract-example-messages.py"))
extract = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(extract)


def check_literal_cr_splits_mid_line():
    # P4-22 rule 1: a literal <CR>/<cr> embedded mid-line is a segment separator, not just a
    # line-terminal marker — pdftotext sometimes joins two printed segment lines into one.
    got = extract._split_literal_cr("PID|1||123^^^MRN||DOE^JOHN<CR>ORC|NW|4521<CR>OBR|1|4521")
    assert got == ["PID|1||123^^^MRN||DOE^JOHN<cr>", "ORC|NW|4521<cr>", "OBR|1|4521"], got
    # case-insensitive, and an ordinary single-marker line is unaffected in shape.
    assert extract._split_literal_cr("PID|1||X<cr>") == ["PID|1||X<cr>"]
    assert extract._split_literal_cr("PID|1||X<CR>") == ["PID|1||X<cr>"]
    # a line with no marker at all passes through unchanged.
    assert extract._split_literal_cr("PID|1||X") == ["PID|1||X"]
    # trailing page marginalia after the marker (a footnote, a running header) is not a new
    # segment, so it is dropped rather than fed to the state machine as a fake next line.
    assert extract._split_literal_cr("PID|1||X<cr>          [note:anonymous]") == ["PID|1||X<cr>"]
    # a duplicated marker ("<cr><cr>") collapses to one terminator for the content before it.
    assert extract._split_literal_cr("PRD|RT|WSIC<cr><cr>") == ["PRD|RT|WSIC<cr>"]
    # a line that is ONLY the marker (a long segment's closing "<cr>" wrapped onto its own
    # row) must still come through as a single fragment — it is what terminates whatever
    # segment has been accumulating across the previous lines, not marginalia to drop.
    assert extract._split_literal_cr("<cr>") == ["<cr>"]


def check_elision_field_drops_rest_of_segment():
    # P4-22 rule 2: a field whose whole content is "..." means omitted content — that field
    # and every later field in the segment are not present, not the literal value "...".
    assert extract._drop_elision("PID|1||123^^^MRN||DOE^JOHN|...|19800101") == "PID|1||123^^^MRN||DOE^JOHN"
    # a trailing "..." after the last delimiter means the same.
    assert extract._drop_elision("OBR|1|4521||...") == "OBR|1|4521|"
    # "..." embedded inside a larger field value is not whole-field elision.
    assert extract._drop_elision("NTE|1||see notes... continued") == "NTE|1||see notes... continued"
    # elision on the very first field still leaves a segment SEG.match can see (a trailing pipe).
    assert extract._drop_elision("PID|...") == "PID|"
    # a segment with no elision at all is returned unchanged.
    assert extract._drop_elision("PID|1||123") == "PID|1||123"


def check_elided_msh12_keeps_message_but_drops_version():
    # P4-22 rule 3: rule 2 applied to MSH is what keeps a message whose MSH-12 is elided —
    # the field is absent afterwards (not the literal "..."), so the Validator falls back to
    # the default grammar rather than a version implied by garbage text.
    msh = "MSH|^~\\&|APP|FAC|APP2|FAC2|20200101||ADT^A01|MSG1|P|...|"
    out = extract._drop_elision(msh)
    fields = out.split("|")
    assert len(fields) <= 11, f"MSH-12 (index 11) must be absent, got {fields}"
    assert extract.SEG.match(out), "the truncated MSH must still be a recognisable segment"
    # a message whose MSH-12 field is genuinely present and un-elided is untouched.
    clean_msh = "MSH|^~\\&|APP|FAC|APP2|FAC2|20200101||ADT^A01|MSG1|P|2.4|"
    assert extract._drop_elision(clean_msh) == clean_msh


def check_known_spec_example_errors_cite():
    # P4-22 Part 3: every registered exception names where it applies and cites the spec
    # text (or the earlier task's verification) that makes the example, not the rule, the
    # one at fault.
    entries = extract.KNOWN_SPEC_EXAMPLE_ERRORS
    assert entries, "the registry must not be empty once P4-22 findings are recorded"
    for e in entries:
        for key in ("version", "location", "index", "finding", "reason"):
            assert key in e and isinstance(e[key], str) and e[key].strip(), \
                f"entry missing or blank {key!r}: {e}"
        assert len(e["reason"]) >= 20, f"reason too short to be a real citation: {e}"


CHECKS = [check_literal_cr_splits_mid_line, check_elision_field_drops_rest_of_segment,
          check_elided_msh12_keeps_message_but_drops_version,
          check_known_spec_example_errors_cite]


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
