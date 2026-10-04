#!/usr/bin/env bash
# check-structure-codegen.sh
# P8b-1 (G8): prove that HL7v2KitCodegen rejects bad message-structure input
# (ADR-019). Each case copies Resources/structures to a scratch directory,
# applies one defect, runs the real codegen against the copy with every
# output in scratch, and asserts a failing exit status and the expected
# stderr text; an accept case applies an allowed change and asserts success
# (P8b-2a). A final good run must reproduce the committed Generated/
# directories byte for byte. Nothing is written into the repository (the
# build products under .build/ aside).
#
# Usage: bash scripts/check-structure-codegen.sh
# Prints one line per case and "N cases, M failures"; exits 1 on a failure.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES="$REPO_ROOT/Resources"
if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/check-structure-codegen.XXXXXX")" || exit 1
trap 'rm -rf "$SCRATCH"' EXIT

if ! xcrun swift build --package-path "$REPO_ROOT" --product HL7v2KitCodegen > "$SCRATCH/build.log" 2>&1; then
  tail -20 "$SCRATCH/build.log"
  echo "check-structure-codegen: the codegen did not build"
  exit 1
fi
CODEGEN="$(xcrun swift build --package-path "$REPO_ROOT" --show-bin-path)/HL7v2KitCodegen"

OUTPUTS="Segment Tables DataTypes Locale Composite Structures"
cases=0
failures=0

# run_codegen <structures dir> <output root>: the regenerate script's 13
# arguments, with the structures input and every output redirected.
run_codegen() {
  local structures="$1" out="$2" name
  for name in $OUTPUTS; do mkdir -p "$out/$name/Generated"; done
  "$CODEGEN" "$RES/schemas" "$out/Segment/Generated" \
    "$RES/tables" "$out/Tables/Generated" \
    "$RES/datatypes" "$out/DataTypes/Generated" \
    "$RES/profiles" "$out/Locale/Generated" \
    "$RES/composites/composite-views.json" "$out/Composite/Generated" \
    "$structures" "$out/Structures/Generated" \
    "$RES/struct-bases.json"
}

# reject <label> <expected stderr substring> <python defect, run with S set to the copy>
reject() {
  local label="$1" expected="$2" defect="$3"
  local dir="$SCRATCH/case$cases"
  cases=$((cases + 1))
  mkdir -p "$dir"
  cp -R "$RES/structures" "$dir/structures"
  if ! S="$dir/structures" python3 -c "$defect"; then
    echo "FAIL $label: the defect did not apply"
    failures=$((failures + 1)); return
  fi
  run_codegen "$dir/structures" "$dir/out" > "$dir/stdout" 2> "$dir/stderr"
  local status=$?
  if [[ $status -eq 0 ]]; then
    echo "FAIL $label: the codegen accepted it"
    failures=$((failures + 1))
  elif ! grep -qF -- "$expected" "$dir/stderr"; then
    echo "FAIL $label: exit $status without \"$expected\": $(head -c 300 "$dir/stderr")"
    failures=$((failures + 1))
  else
    echo "ok   $label"
  fi
}

# accept <label> <python change, run with S set to the copy>: the codegen must succeed.
accept() {
  local label="$1" change="$2"
  local dir="$SCRATCH/case$cases"
  cases=$((cases + 1))
  mkdir -p "$dir"
  cp -R "$RES/structures" "$dir/structures"
  if ! S="$dir/structures" python3 -c "$change"; then
    echo "FAIL $label: the change did not apply"
    failures=$((failures + 1)); return
  fi
  run_codegen "$dir/structures" "$dir/out" > "$dir/stdout" 2> "$dir/stderr"
  local status=$?
  if [[ $status -ne 0 ]]; then
    echo "FAIL $label: exit status $status: $(head -c 300 "$dir/stderr")"
    failures=$((failures + 1))
  else
    echo "ok   $label"
  fi
}

# Shared Python helpers for the defects.
PRE='import json, os
S = os.environ["S"]
def load(p): return json.load(open(os.path.join(S, p)))
def save(p, d): json.dump(d, open(os.path.join(S, p), "w"), indent=2)
def first_group(elements):
    for e in elements:
        if "group" in e: return e
        g = first_group(e.get("elements", []))
        if g: return g
def oru(source, fragment, version="2.5.1"):
    # ORU_R01 with PATIENT_RESULT renamed from the given source and cited by the fragment; on
    # another version the bundle names become v2.4-derived ones.
    d = load("v2.5.1/ORU_R01.json"); d["version"] = version
    if version != "2.5.1":
        d["citation"] = d["citation"].replace("HL7-xml v2.5.1/", "HL7-xml v2.4/")
        def derive(es):
            for e in es:
                if e.get("nameSource") == "v2xml": e["nameSource"] = "v2xml-v2.4"
                derive(e.get("elements", []))
        derive(d["elements"])
        os.makedirs(os.path.join(S, "v" + version), exist_ok=True)
    first_group(d["elements"])["nameSource"] = source
    d["citation"] += " " + fragment
    save("v%s/ORU_R01.json" % version, d)
'

reject "unknown key in a structure file" 'unknown key(s) ["comment"]' "$PRE
d = load('v2.5.1/ADT_A01.json'); d['comment'] = 'x'; save('v2.5.1/ADT_A01.json', d)"

reject "unknown key in an element" 'unknown key(s) ["repeat"]' "$PRE
d = load('v2.5.1/ADT_A01.json'); d['elements'][1]['repeat'] = True; save('v2.5.1/ADT_A01.json', d)"

reject "missing max" 'missing key "max"' "$PRE
d = load('v2.5.1/ACK.json'); del d['elements'][0]['max']; save('v2.5.1/ACK.json', d)"

reject "nameSource outside the accepted set" 'needs nameSource' "$PRE
d = load('v2.5.1/ORU_R01.json'); first_group(d['elements'])['nameSource'] = 'guessed'; save('v2.5.1/ORU_R01.json', d)"

reject "group without nameSource" 'needs nameSource' "$PRE
d = load('v2.5.1/ORU_R01.json'); del first_group(d['elements'])['nameSource']; save('v2.5.1/ORU_R01.json', d)"

# P8b-2b: the five nameSource values; every non-printed name is cited in the structure citation.
accept "nameSource v2xml cited by bundle file and element" "$PRE
oru('v2xml', 'PATIENT_RESULT (HL7-xml v2.5.1/ORU_R01.xsd, ORU_R01.PATIENT_RESULT.CONTENT).')"

accept "nameSource v2xml-v2.4 on v2.3, cited through the v2.4 bundle" "$PRE
oru('v2xml-v2.4', 'PATIENT_RESULT (HL7-xml v2.4/ORU_R01.xsd, ORU_R01.PATIENT_RESULT.CONTENT, derived for v2.3 ORU_R01).', '2.3')"

accept "nameSource synthesised, cited as synthesised" "$PRE
oru('synthesised', 'PATIENT_RESULT (synthesised: no HL7-xml group matches).')"

accept "nameSource override, cited to overrides.json" "$PRE
oru('override', 'PATIENT_RESULT (overrides.json: a cited name).')"

reject "a non-printed name the citation does not cite" 'is not cited' "$PRE
d = load('v2.5.1/ORU_R01.json'); d['citation'] = d['citation'].split(' Unprinted group names')[0]; save('v2.5.1/ORU_R01.json', d)"

reject "nameSource v2xml on v2.3 (no bundle)" 'for v2.3 and v2.3.1 only' "$PRE
oru('v2xml', 'PATIENT_RESULT (HL7-xml v2.3/ORU_R01.xsd, ORU_R01.PATIENT_RESULT.CONTENT).', '2.3')"

reject "nameSource v2xml-v2.4 outside v2.3 and v2.3.1" 'for v2.3 and v2.3.1 only' "$PRE
oru('v2xml-v2.4', 'PATIENT_RESULT (HL7-xml v2.4/ORU_R01.xsd, ORU_R01.PATIENT_RESULT.CONTENT).')"

reject "max below min" 'bad occurrence bounds' "$PRE
d = load('v2.5.1/ACK.json'); d['elements'][0]['min'] = 2; save('v2.5.1/ACK.json', d)"

reject "malformed trigger" 'triggers must be' "$PRE
d = load('v2.5.1/ADT_A01.json'); d['triggers'][0] = 'ADT-A01'; save('v2.5.1/ADT_A01.json', d)"

reject "version not matching the directory" 'do not match the path' "$PRE
d = load('v2.5.1/ACK.json'); d['version'] = '2.6'; save('v2.5.1/ACK.json', d)"

reject "completeness entry for an unmodelled version" 'not modelled ["2.9"]' "$PRE
d = load('completeness.json'); d['versions']['2.9'] = {'complete': False, 'citation': 'x'}; save('completeness.json', d)"

reject "completeness missing a modelled version" 'missing ["2.6"]' "$PRE
d = load('completeness.json'); del d['versions']['2.6']; save('completeness.json', d)"

reject "unknown key in a completeness entry" 'unknown key(s) ["since"]' "$PRE
d = load('completeness.json'); d['versions']['2.4']['since'] = 'x'; save('completeness.json', d)"

reject "empty completeness citation" 'one non-empty line' "$PRE
d = load('completeness.json'); d['versions']['2.4']['citation'] = ' '; save('completeness.json', d)"

# v2.3 is the last version the rollout fills (P8b-15); that task moves this case to a scratch-only
# version directory before flipping v2.3 (P8b-16 moved it off v2.7.1).
reject "complete version with no structures" 'marked complete but has no structures' "$PRE
d = load('completeness.json'); d['versions']['2.3']['complete'] = True; save('completeness.json', d)"

reject "missing completeness file" 'couldn’t be opened because there is no such file' "$PRE
os.remove(os.path.join(S, 'completeness.json'))"

reject "stray file under Resources/structures (versions.json, B5)" 'unexpected entry' "$PRE
save('versions.json', {'versions': {}})"

reject "stray directory under Resources/structures" 'unexpected entry' "$PRE
os.mkdir(os.path.join(S, 'drafts'))"

reject "structure directory for an unlisted version" 'unlisted versions ["2.9"]' "$PRE
os.mkdir(os.path.join(S, 'v2.9'))"

# P8b-2a: the extractor's overrides.json and the G9 profiles directory are allowed, and only
# in that form.
accept "overrides.json under Resources/structures (P8b-2a)" "$PRE
save('overrides.json', {'groupNames': [], 'sharedTriggers': load('overrides.json')['sharedTriggers']})"

accept "an empty profile directory under Resources/structures/profiles (G9)" "$PRE
os.makedirs(os.path.join(S, 'profiles', 'au-test'))"

reject "overrides.json as a directory" 'unexpected entry' "$PRE
os.remove(os.path.join(S, 'overrides.json')) if os.path.exists(os.path.join(S, 'overrides.json')) else None
os.mkdir(os.path.join(S, 'overrides.json'))"

reject "profiles as a file" 'unexpected entry' "$PRE
import shutil; shutil.rmtree(os.path.join(S, 'profiles'))
save('profiles', {})"

# P8b-4: a profile structure (ADR-019 data model, ruling G9). The profile keys are accepted only
# under profiles/<profile>/, all three are required, and the structure must constrain a loaded
# base structure of the same ID and version, printing only triggers the base prints.
AU='
def au(change):
    d = load("profiles/au-adrm-2021/ORU_R01.json"); change(d); save("profiles/au-adrm-2021/ORU_R01.json", d)
'
reject "profile key in a version file" 'unknown key(s) ["profile"]' "$PRE
d = load('v2.4/ORU_R01.json'); d['profile'] = 'au-adrm-2021'; save('v2.4/ORU_R01.json', d)"

reject "profile structure without a rule" 'needs "profile", "baseVersion" and "rule"' "$PRE$AU
au(lambda d: d.pop('rule'))"

reject "profile tag differs from its directory" 'does not match its directory au-adrm-2021' "$PRE$AU
au(lambda d: d.update(profile='au-other'))"

reject "baseVersion differs from version" 'baseVersion 2.5.1 differs from version 2.4' "$PRE$AU
au(lambda d: d.update(baseVersion='2.5.1'))"

reject "bad rule" 'bad rule' "$PRE$AU
au(lambda d: d.update(rule='00060.1'))"

reject "profile structure with no base structure" 'no base v2.4 structure ORU_R02 to constrain' "$PRE
d = load('profiles/au-adrm-2021/ORU_R01.json'); d['structure'] = 'ORU_R02'
os.remove(os.path.join(S, 'profiles/au-adrm-2021/ORU_R01.json')); save('profiles/au-adrm-2021/ORU_R02.json', d)"

reject "profile trigger the base does not print" 'are not printed for the base v2.4 ORU_R01' "$PRE$AU
au(lambda d: d.update(triggers=['ORU^R01', 'ORU^R30']))"

reject "profile structure breaking a structure-file rule" 'is not cited' "$PRE$AU
au(lambda d: d.update(citation=d['citation'].replace('PD1_GROUP (synthesised', 'PD1_GROUP (made up')))"

reject "stray file in profiles" 'holds only profile directories' "$PRE
save('profiles/notes.json', {})"

reject "profile directory name not lower-case hyphenated" 'holds only profile directories' "$PRE
os.makedirs(os.path.join(S, 'profiles', 'AU_ADRM'))"

# P8b-6: the choice element. ACK's MSA becomes a choice; an accepted choice must render as one.
CH='
def ack_choice(**fields):
    d = load("v2.5.1/ACK.json")
    msa = d["elements"][2]
    c = {"choice": None, "min": 1, "max": 1, "alternatives": [msa, {"segment": "UAC", "min": 1, "max": 1}]}
    c.update(fields)
    for k in [k for k, v in fields.items() if v == "DROP"]: del c[k]
    d["elements"][2] = c
    save("v2.5.1/ACK.json", d)
    return d
'

# accept_rendering <label> <text the generated v2.5.1 table must contain> <change>
accept_rendering() {
  local label="$1" expected="$2" change="$3"
  local dir="$SCRATCH/case$cases"
  accept "$label" "$change"
  if [[ -d "$dir/out" ]] && ! grep -qF "$expected" "$dir/out/Structures/Generated/MessageStructureTable+v2_5_1.swift"; then
    echo "FAIL $label: the generated table lacks $expected"
    failures=$((failures + 1))
  fi
}

accept_rendering "unnamed choice renders as .choice(nil, ...)" '.choice(nil, min: 1, max: 1, alternatives: [' "$PRE$CH
ack_choice()"

accept_rendering "named choice with a printed name renders its name" '.choice("ACKNOWLEDGMENT", min: 0, max: nil, alternatives: [' "$PRE$CH
ack_choice(choice='ACKNOWLEDGMENT', nameSource='printed', min=0, max=None)"

accept "an unnamed choice as an alternative of a choice" "$PRE$CH
d = ack_choice(); c = d['elements'][2]
c['alternatives'][1] = {'choice': None, 'min': 1, 'max': 1, 'alternatives': [{'segment': 'UAC', 'min': 1, 'max': 1}, {'segment': 'ERR', 'min': 1, 'max': 1}]}
save('v2.5.1/ACK.json', d)"

reject "choice with one alternative" 'needs at least two "alternatives"' "$PRE$CH
d = ack_choice(); d['elements'][2]['alternatives'].pop(); save('v2.5.1/ACK.json', d)"

reject "choice with no alternatives" 'needs at least two "alternatives"' "$PRE$CH
ack_choice(alternatives=[])"

reject "choice with elements in place of alternatives" 'needs at least two "alternatives"' "$PRE$CH
d = ack_choice(); c = d['elements'][2]; c['elements'] = c.pop('alternatives'); save('v2.5.1/ACK.json', d)"

reject "choice with max 0" 'bad occurrence bounds' "$PRE$CH
ack_choice(min=0, max=0)"

reject "element that is both a choice and a group" 'exactly one of "segment", "group" or "choice"' "$PRE$CH
ack_choice(group='X', nameSource='printed')"

reject "unnamed choice with a nameSource" 'unnamed choice cannot have a nameSource' "$PRE$CH
ack_choice(nameSource='printed')"

reject "named choice without nameSource" 'choice ACKNOWLEDGMENT needs nameSource' "$PRE$CH
ack_choice(choice='ACKNOWLEDGMENT')"

reject "named choice with a bad name" 'bad choice name' "$PRE$CH
ack_choice(choice='ack-x', nameSource='printed')"

reject "named choice from a bundle the citation does not cite" 'choice ACKNOWLEDGMENT (nameSource v2xml) is not cited' "$PRE$CH
ack_choice(choice='ACKNOWLEDGMENT', nameSource='v2xml')"

reject "a bad segment inside an alternative" 'bad segment ID' "$PRE$CH
d = ack_choice(); d['elements'][2]['alternatives'][1]['segment'] = 'uac'; save('v2.5.1/ACK.json', d)"

reject "segment with alternatives" 'cannot have elements, alternatives or a nameSource' "$PRE
d = load('v2.5.1/ACK.json'); d['elements'][2]['alternatives'] = []; save('v2.5.1/ACK.json', d)"

# P8b-12: the codegen lints each structure and renders requiresExactMatch. ACK's elements are
# replaced by a synthetic shape (StructureShapes in the test target); the v2.5.1 table must hold
# exactly <count> more "requiresExactMatch: true" lines than the committed table (ACK passes
# the lint, so 0 or 1 more; P8b-9 commits lint-failing v2.5.1 structures).
SH='
def seg(i, mn, mx): return {"segment": i, "min": mn, "max": mx}
def grp(n, mn, mx, es): return {"group": n, "nameSource": "printed", "min": mn, "max": mx, "elements": es}
def alt(mn, mx, es): return {"choice": None, "min": mn, "max": mx, "alternatives": es}
def ack_shape(*es):
    d = load("v2.5.1/ACK.json"); d["elements"] = [seg("MSH", 1, 1)] + list(es); save("v2.5.1/ACK.json", d)
'

# flagged <label> <count> <change>
flagged() {
  local label="$1" count="$2" change="$3"
  local dir="$SCRATCH/case$cases"
  accept "$label" "$change"
  local found
  local base
  base=$(grep -c "requiresExactMatch: true" "$REPO_ROOT/Sources/HL7v2Kit/Structures/Generated/MessageStructureTable+v2_5_1.swift")
  found=$(( $(grep -c "requiresExactMatch: true" "$dir/out/Structures/Generated/MessageStructureTable+v2_5_1.swift" 2>/dev/null) - base ))
  if [[ -d "$dir/out" && "$found" != "$count" ]]; then
    echo "FAIL $label: $found more structure(s) flagged, expected $count"
    failures=$((failures + 1))
  fi
}

flagged "lint-failing pre-v2.5 ORU shape is flagged for exact matching" 1 "$PRE$SH
ack_shape(seg('OBR', 1, 1), seg('NTE', 0, None), grp('OBSERVATION', 0, None, [seg('OBX', 0, 1), seg('NTE', 0, None)]))"

flagged "lint-failing counter-example {G: X {Q: X Y}} is flagged" 1 "$PRE$SH
ack_shape(grp('G', 1, None, [seg('XXA', 1, 1), grp('Q', 1, None, [seg('XXA', 1, 1), seg('YYB', 1, 1)])]))"

flagged "exempt shape {G: [X] [{N}]} passes the lint and is not flagged" 0 "$PRE$SH
ack_shape(grp('G', 1, None, [seg('XXA', 0, 1), seg('NTE', 0, None)]))"

flagged "exempt nullable prefix {G: [A] [X] [{N}]} is not flagged" 0 "$PRE$SH
ack_shape(grp('G', 1, None, [seg('AAA', 0, 1), seg('XXA', 0, 1), seg('NTE', 0, None)]))"

flagged "choice with optional alternatives is flagged" 1 "$PRE$SH
ack_shape(alt(1, None, [seg('AAA', 0, 1), seg('BBB', 0, None)]), seg('CCC', 1, 1))"

flagged "choice with overlapping alternatives is flagged" 1 "$PRE$SH
ack_shape(alt(1, 1, [seg('AAA', 1, 1), grp('G', 1, 1, [seg('AAA', 1, 1), seg('BBB', 1, 1)])]), seg('CCC', 1, 1))"

flagged "optional choice then a sibling of its FIRST set is flagged" 1 "$PRE$SH
ack_shape(alt(0, 1, [seg('AAA', 1, 1), seg('BBB', 1, 1)]), seg('AAA', 0, None))"

flagged "deterministic repeating choice is not flagged" 0 "$PRE$SH
ack_shape(alt(0, None, [seg('AAA', 1, 1), seg('BBB', 1, None)]), seg('CCC', 1, 1))"

# P8b-9: a trigger under two structures (loaded, or registered as not modelled in
# completeness.json) must be a declared sharedTriggers entry (ADR-019 lookup rule 2); the
# notModelled entries are checked.
SHARED='
def share(declare):
    d = load("v2.5.1/ADT_A01.json"); d["structure"] = "ADT_A99"; d["triggers"] = ["ADT^A01"]; save("v2.5.1/ADT_A99.json", d)
    if declare:
        o = load("overrides.json")
        o["sharedTriggers"].append({"version": "2.5.1", "trigger": "ADT^A01", "structures": ["ADT_A01", "ADT_A99"], "citation": "x"})
        save("overrides.json", o)
def gap(**fields):
    c = load("completeness.json")
    e = {"structure": "ZZZ_Z01", "triggers": ["ZZZ^Z01"], "reason": "synthetic"}
    e.update(fields)
    c["versions"]["2.5.1"].setdefault("notModelled", []).append(e)
    save("completeness.json", c)
'

reject "a trigger under two loaded structures, undeclared" 'trigger ADT^A01 is printed under ["ADT_A01", "ADT_A99"]' "$PRE$SHARED
share(False)"

accept "a trigger under two loaded structures, declared in sharedTriggers" "$PRE$SHARED
share(True)"

reject "a trigger shared with a registered not-modelled structure, undeclared" 'trigger ADT^A08 is printed under' "$PRE$SHARED
gap(structure='ADT_A98', triggers=['ADT^A08'])"

reject "a notModelled entry that is a loaded structure" 'notModelled ACK: it is a loaded structure' "$PRE$SHARED
gap(structure='ACK', triggers=[])"

reject "a notModelled entry with a bad trigger" 'triggers must be CODE^EVT' "$PRE$SHARED
gap(triggers=['ZZZ-Z01'])"

reject "a notModelled entry with an empty reason" 'the reason must be one non-empty line' "$PRE$SHARED
gap(reason=' ')"

reject "a notModelled entry with an unknown key" 'unknown key(s) ["page"]' "$PRE$SHARED
gap(page='x')"

accept "a notModelled entry renders in the versions switch" "$PRE$SHARED
gap()"
if ! grep -qF '"ZZZ_Z01": NotModelledStructure(' "$SCRATCH/case$((cases - 1))/out/Structures/Generated/MessageStructureTable+Versions.swift"; then
  echo "FAIL a notModelled entry renders: the generated versions file lacks it"
  failures=$((failures + 1))
fi

# The good run: the unmodified copy reproduces every committed Generated/ directory.
cases=$((cases + 1))
good="$SCRATCH/good"
mkdir -p "$good"
cp -R "$RES/structures" "$good/structures"
run_codegen "$good/structures" "$good/out" > "$good/stdout" 2> "$good/stderr"
good_status=$?
if [[ $good_status -ne 0 ]]; then
  echo "FAIL good run: exit status $good_status: $(head -c 300 "$good/stderr")"
  failures=$((failures + 1))
else
  drift=""
  for name in $OUTPUTS; do
    if ! diff -r -q "$good/out/$name/Generated" "$REPO_ROOT/Sources/HL7v2Kit/$name/Generated" > "$good/diff-$name" 2>&1; then
      drift="$drift $name"
    fi
  done
  if [[ -n "$drift" ]]; then
    echo "FAIL good run: differs from the committed Generated/ in:$drift"
    failures=$((failures + 1))
  else
    echo "ok   good run reproduces the committed Generated/ byte for byte"
  fi
fi

echo "$cases cases, $failures failures"
[[ $failures -eq 0 ]]
