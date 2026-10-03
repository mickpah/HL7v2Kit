#!/usr/bin/env bash
# check-structure-codegen.sh
# P8b-1 (G8): prove that HL7v2KitCodegen rejects bad message-structure input
# (ADR-019). Each case copies Resources/structures to a scratch directory,
# applies one defect, runs the real codegen against the copy with every
# output in scratch, and asserts a failing exit status and the expected
# stderr text. A final good run must reproduce the committed Generated/
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

reject "complete version with no structures" 'marked complete but has no structures' "$PRE
d = load('completeness.json'); d['versions']['2.6']['complete'] = True; save('completeness.json', d)"

reject "missing completeness file" 'completeness.json' "$PRE
os.remove(os.path.join(S, 'completeness.json'))"

reject "stray file under Resources/structures (versions.json, B5)" 'unexpected entry' "$PRE
save('versions.json', {'versions': {}})"

reject "stray directory under Resources/structures" 'unexpected entry' "$PRE
os.mkdir(os.path.join(S, 'drafts'))"

reject "structure directory for an unlisted version" 'unlisted versions ["2.9"]' "$PRE
os.mkdir(os.path.join(S, 'v2.9'))"

# The good run: the unmodified copy reproduces every committed Generated/ directory.
cases=$((cases + 1))
good="$SCRATCH/good"
mkdir -p "$good"
cp -R "$RES/structures" "$good/structures"
if ! run_codegen "$good/structures" "$good/out" > "$good/stdout" 2> "$good/stderr"; then
  echo "FAIL good run: exit status $?: $(head -c 300 "$good/stderr")"
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
