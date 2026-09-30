#!/usr/bin/env python3
"""Self-check for the scripts/extract-example-messages.py extraction rules (P4-22). No
PDFs, no pytest.

    python3 scripts/check-extract-example-messages.py

Each check is a plain function of asserts. The script exits 1 when any check fails, so CI
can run it in the fixture-safety job, the same way check-audit-schemas.py does.
"""
import importlib.util
import os
import re
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
    # fix round 1 minor: duplicate markers separated by whitespace (not just back-to-back)
    # collapse the same way as "<cr><cr>".
    assert extract._split_literal_cr("PRD|RT|WSIC<cr>  <cr>") == ["PRD|RT|WSIC<cr>"]


def check_elision_field_drops_rest_of_segment():
    # P4-22 rule 2: a field whose whole content is "..." means omitted content — that field
    # and every later field in the segment are not present, not the literal value "...".
    # _drop_elision returns (truncated segment, 1-based field elision started at, or None).
    assert extract._drop_elision("PID|1||123^^^MRN||DOE^JOHN|...|19800101") == ("PID|1||123^^^MRN||DOE^JOHN", 6)
    # a trailing "..." after the last delimiter means the same.
    assert extract._drop_elision("OBR|1|4521||...") == ("OBR|1|4521|", 4)
    # "..." embedded inside a larger field value is not whole-field elision.
    assert extract._drop_elision("NTE|1||see notes... continued") == ("NTE|1||see notes... continued", None)
    # elision on the very first field still leaves a segment SEG.match can see (a trailing pipe).
    assert extract._drop_elision("PID|...") == ("PID|", 1)
    # a segment with no elision at all is returned unchanged.
    assert extract._drop_elision("PID|1||123") == ("PID|1||123", None)


def check_elided_msh12_keeps_message_but_drops_version():
    # P4-22 rule 3: rule 2 applied to MSH is what keeps a message whose MSH-12 is elided —
    # the field is absent afterwards (not the literal "..."), so the Validator falls back to
    # the default grammar rather than a version implied by garbage text.
    msh = "MSH|^~\\&|APP|FAC|APP2|FAC2|20200101||ADT^A01|MSG1|P|...|"
    out, from_field = extract._drop_elision(msh)
    fields = out.split("|")
    assert len(fields) <= 11, f"MSH-12 (index 11) must be absent, got {fields}"
    # _drop_elision is segment-agnostic and returns the raw split index (11): MSH-1 is the
    # field separator character, not a split element, so split index 11 is MSH-12 — the
    # +1 adjustment for MSH lives in _elision_metadata, checked separately below.
    assert from_field == 11, f"elision started at split index 11 (MSH-12), got {from_field}"
    assert extract.SEG.match(out), "the truncated MSH must still be a recognisable segment"
    # a message whose MSH-12 field is genuinely present and un-elided is untouched.
    clean_msh = "MSH|^~\\&|APP|FAC|APP2|FAC2|20200101||ADT^A01|MSG1|P|2.4|"
    assert extract._drop_elision(clean_msh) == (clean_msh, None)


def check_elision_metadata_marks_truncated_segments_and_msh_version():
    # P4-22 fix round 1 (brief Part 1 rule 3, "mark it"): per-message metadata records
    # which segments elision truncated (with the repeat count and first-absent field, so
    # the report can tell a genuine finding apart from one that only exists because the
    # PDF elided the rest of the segment), and whether MSH-12 itself is one of them.
    cleaned = ["MSH|^~\\&|APP|FAC|APP2|FAC2|20200101||ADT^A01|MSG1|P",
               "PID|1||123", "OBX|1|ST|1^A", "OBX|2|ST|2^B"]
    dropped = [(cleaned[0], 11), (cleaned[1], None), (cleaned[2], 4), (cleaned[3], None)]
    meta = extract._elision_metadata(cleaned, dropped)
    assert meta["segments"] == cleaned
    assert meta["mshVersionElided"] is True
    # MSH-1 is the field separator, not a split element, so split index 11 is MSH-12.
    assert {"segment": "MSH", "repetition": 1, "fromField": 12} in meta["truncatedSegments"]
    assert {"segment": "OBX", "repetition": 1, "fromField": 4} in meta["truncatedSegments"]
    assert len(meta["truncatedSegments"]) == 2, meta["truncatedSegments"]
    # a message whose MSH is untouched is not marked mshVersionElided even if something
    # else later was truncated.
    cleaned2 = ["MSH|^~\\&|APP|FAC|APP2|FAC2|20200101||ADT^A01|MSG1|P|2.4",
                "PID|1", "OBX|1|ST|1^A"]
    dropped2 = [(cleaned2[0], None), (cleaned2[1], None), (cleaned2[2], 4)]
    meta2 = extract._elision_metadata(cleaned2, dropped2)
    assert meta2["mshVersionElided"] is False


def check_continuation_closes_before_running_into_prose():
    # P4-22 fix round 1: a segment whose own <cr> the PDF dropped (a genuine missing
    # terminator, e.g. Hl7V231.pdf's RQD|5) must not absorb the section heading that
    # follows it, and must not grow without bound if no heading ever arrives either.
    short_seg = "RQD|5|4565^Bandage Pad|3|BX^Box"
    assert not extract._continuation_runs_into_prose(short_seg, "                  ...ORSUP^Main")
    assert extract._continuation_runs_into_prose(short_seg, "4.8       PHARMACY/TREATMENT ORDERS")
    assert extract._continuation_runs_into_prose(short_seg, "2.11          LOCAL EXTENSION")
    # an ordinary non-heading continuation line does not trip the heading half of the guard...
    assert not extract._continuation_runs_into_prose(short_seg, "more wrapped field text")
    # ...but the same line does once the accumulated segment is already absurdly long.
    assert extract._continuation_runs_into_prose("X" * (extract._MAX_SEGMENT_LEN + 1), "more wrapped field text")


def check_known_spec_example_errors_cite():
    # P4-22 Part 3 / fix round 1 item 5: every registered exception is keyed by (source
    # glob, index, code, location pattern) with an exact expected count, and cites the spec
    # text (or the earlier task's verification) that makes the example, not the rule, the
    # one at fault.
    entries = extract.KNOWN_SPEC_EXAMPLE_ERRORS
    assert entries, "the registry must not be empty once P4-22 findings are recorded"
    for e in entries:
        for key in ("source_glob", "index", "code", "location_pattern", "reason"):
            assert key in e, f"entry missing {key!r}: {e}"
        assert isinstance(e["source_glob"], str) and e["source_glob"].strip(), e
        assert e["index"] == "all" or isinstance(e["index"], int), e
        assert isinstance(e["code"], str) and e["code"].strip(), e
        re.compile(e["location_pattern"])  # must be a valid regex
        assert isinstance(e["count"], int) and e["count"] >= 0, e
        assert isinstance(e["reason"], str) and len(e["reason"]) >= 20, \
            f"reason too short to be a real citation: {e}"


def check_registry_matches_a_synthetic_report():
    # P4-22 fix round 1 item 5: the (source glob, index, code, location pattern) key
    # matches exactly the rows it should, subtracts them so a later entry can't re-claim
    # them, and a count mismatch is reported rather than silently accepted.
    saved = extract.KNOWN_SPEC_EXAMPLE_ERRORS[:]
    try:
        extract.KNOWN_SPEC_EXAMPLE_ERRORS[:] = [
            {"source_glob": "v2.3/CH10.pdf", "index": "all", "code": "conditionalFieldMissing",
             "location_pattern": r"^AI[LP]\[\d+\]-6$", "count": 2, "reason": "synthetic check entry only" * 2},
        ]
        rows = [
            ["SPECEX", "v2.3/CH10.pdf", "0", "conditionalFieldMissing", "AIL[1]-6", "msg"],
            ["SPECEX", "v2.3/CH10.pdf", "2", "conditionalFieldMissing", "AIP[1]-6", "msg"],
            ["SPECEX", "v2.3/CH10.pdf", "0", "requiredFieldMissing", "AIL[1]-4", "msg"],  # wrong code
        ]
        mismatches, unmatched = extract.check_registry(rows)
        assert mismatches == [], mismatches
        assert len(unmatched) == 1 and unmatched[0][4] == "AIL[1]-4", unmatched
        # a wrong recorded count is reported, not silently accepted.
        extract.KNOWN_SPEC_EXAMPLE_ERRORS[0]["count"] = 99
        mismatches, _ = extract.check_registry(rows)
        assert len(mismatches) == 1 and mismatches[0][1] == 2, mismatches
    finally:
        extract.KNOWN_SPEC_EXAMPLE_ERRORS[:] = saved


CHECKS = [check_literal_cr_splits_mid_line, check_elision_field_drops_rest_of_segment,
          check_elided_msh12_keeps_message_but_drops_version,
          check_elision_metadata_marks_truncated_segments_and_msh_version,
          check_continuation_closes_before_running_into_prose,
          check_known_spec_example_errors_cite,
          check_registry_matches_a_synthetic_report]


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
