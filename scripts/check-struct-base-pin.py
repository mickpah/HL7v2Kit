#!/usr/bin/env python3
"""Self-check for the codegen's pinned struct bases (P10-3, ADR-020 amendment). No pytest.

    python3 scripts/check-struct-base-pin.py

The codegen has no test target, so this check runs the real HL7v2KitCodegen executable
against a scratch copy of Resources/schemas with a synthetic earlier version, `v2.7.1`, added.
That version defines PRT (pinned to v2.8.2 in Resources/struct-bases.json) with a renamed
and retyped first field, plus a segment, `ZZP`, that no other version defines and that has no
pin. Before the pin, "the earliest definer" made v2.7.1 the base of PRT and renamed its
released accessors. The check asserts:

- PRT is still based on v2.8.2 and declares every public signature the committed PRT.swift
  declares (no released accessor renamed or retyped);
- ZZP, unpinned, takes the normal rule (its earliest definer, v2.7.1);
- a pin naming a version that does not define the segment fails the run.

Every output goes to a scratch directory; nothing under the repository is written. The script
exits 1 when any check fails. CI runs it in the codegen-drift job, which has the toolchain.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
OUTPUTS = ["Segment", "Tables", "DataTypes", "Locale", "Composite", "Structures"]


def run_codegen(scratch, pins_file):
    """Run the codegen with `scratch/schemas` and every output under `scratch/out/<X>/Generated`.
    Returns the completed process."""
    out = {name: os.path.join(scratch, "out", name, "Generated") for name in OUTPUTS}
    res = os.path.join(REPO, "Resources")
    args = [
        os.path.join(scratch, "schemas"), out["Segment"],
        os.path.join(res, "tables"), out["Tables"],
        os.path.join(res, "datatypes"), out["DataTypes"],
        os.path.join(res, "profiles"), out["Locale"],
        os.path.join(res, "composites", "composite-views.json"), out["Composite"],
        os.path.join(res, "structures"), out["Structures"],
        pins_file,
    ]
    env = dict(os.environ)
    if os.path.isdir("/Applications/Xcode.app/Contents/Developer"):
        env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    return subprocess.run(
        ["xcrun", "swift", "run", "--package-path", REPO, "HL7v2KitCodegen"] + args,
        capture_output=True, text=True, env=env)


def public_signatures(path):
    """The trimmed `public ...` lines of a generated file, with bodies and defaults cut."""
    sigs = set()
    with open(path, encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if not s.startswith("public "):
                continue
            s = s.split(" {")[0].split(" = ")[0].strip()
            sigs.add(s)
    return sigs


def source_schema(path):
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("// Source schema: "):
                return line.strip()[len("// Source schema: "):]
    return None


def make_scratch_schemas(scratch):
    """Copy Resources/schemas and add the synthetic v2.7.1 PRT and ZZP."""
    schemas = os.path.join(scratch, "schemas")
    shutil.copytree(os.path.join(REPO, "Resources", "schemas"), schemas)
    fake = os.path.join(schemas, "v2.7.1")
    os.makedirs(fake)
    with open(os.path.join(schemas, "v2.8.2", "PRT.json"), encoding="utf-8") as f:
        prt = json.load(f)
    prt["version"] = "2.7.1"
    prt["fields"][0].update(swiftName="earlierDefinerName", name="Earlier Definer Name", dataType="ST")
    with open(os.path.join(fake, "PRT.json"), "w", encoding="utf-8") as f:
        json.dump(prt, f, indent=2)
    zzp = dict(prt, segmentID="ZZP", description="Synthetic unpinned segment")
    with open(os.path.join(fake, "ZZP.json"), "w", encoding="utf-8") as f:
        json.dump(zzp, f, indent=2)


def check_pinned_base_does_not_move(scratch):
    make_scratch_schemas(scratch)
    proc = run_codegen(scratch, os.path.join(REPO, "Resources", "struct-bases.json"))
    assert proc.returncode == 0, proc.stderr[-2000:]
    seg = os.path.join(scratch, "out", "Segment", "Generated")
    prt = os.path.join(seg, "PRT.swift")
    got = source_schema(prt)
    assert got == "Resources/schemas/v2.8.2/PRT.json", got
    committed = public_signatures(os.path.join(REPO, "Sources", "HL7v2Kit", "Segment", "Generated", "PRT.swift"))
    missing = committed - public_signatures(prt)
    assert not missing, "released PRT accessors changed: %s" % sorted(missing)[:5]
    # An unpinned segment takes the normal rule: its earliest definer.
    got = source_schema(os.path.join(seg, "ZZP.swift"))
    assert got == "Resources/schemas/v2.7.1/ZZP.json", got


def check_pin_to_undefined_version_fails(scratch):
    make_scratch_schemas(scratch)
    pins = os.path.join(scratch, "pins.json")
    with open(os.path.join(REPO, "Resources", "struct-bases.json"), encoding="utf-8") as f:
        data = json.load(f)
    data["bases"]["PRT"] = "2.3"
    with open(pins, "w", encoding="utf-8") as f:
        json.dump(data, f)
    proc = run_codegen(scratch, pins)
    assert proc.returncode != 0, "a pin to a version without the segment must fail the run"
    assert "PRT" in proc.stderr, proc.stderr[-500:]


def main():
    checks = [check_pinned_base_does_not_move, check_pin_to_undefined_version_fails]
    failed = 0
    for check in checks:
        scratch = tempfile.mkdtemp(prefix="struct-base-pin-")
        try:
            check(scratch)
            print("ok   %s" % check.__name__)
        except AssertionError as e:
            failed += 1
            print("FAIL %s: %s" % (check.__name__, e))
        finally:
            shutil.rmtree(scratch, ignore_errors=True)
    print("%d of %d checks passed" % (len(checks) - failed, len(checks)))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
