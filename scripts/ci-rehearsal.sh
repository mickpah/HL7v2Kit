#!/usr/bin/env bash
# CI rehearsal: runs the shell steps of .github/workflows/ci.yml on a clean clone of HEAD, job
# by job and step by step, as the hosted runners would. Run it before pushing.
#
#   bash scripts/ci-rehearsal.sh [--hide-tmp-binaries] [--keep]
#
# - Each job gets its own clean clone of HEAD (committed work only) in a scratch directory, with
#   HOME, TMPDIR and RUNNER_TEMP pointing into it and a minimal environment. The `uses:` steps
#   (the checkout) are replaced by that clone.
# - macOS jobs: DEVELOPER_DIR is set to the newest /Applications/Xcode*.app, which is what each
#   job's "Select the newest Xcode" step does on the runner; that step needs sudo, so it is
#   skipped. On a host that is not macOS the macOS jobs are skipped.
# - A job with a `container:` (test-linux) runs each step in that image through Docker; without
#   a running Docker it is skipped with a message.
# - --hide-tmp-binaries moves /tmp/extractbin and /tmp/tablesbin (the author's local extractor
#   builds) aside for the run and restores them on exit, proving no step relies on them.
# - --keep leaves the scratch directory, with each step's log, in place.
#
# Prints one line per step, then a summary per job; exits 1 if any step failed.
set -uo pipefail

hide_bins=0
keep=0
for arg in "$@"; do
    case "$arg" in
        --hide-tmp-binaries) hide_bins=1 ;;
        --keep) keep=1 ;;
        *) echo "usage: ci-rehearsal.sh [--hide-tmp-binaries] [--keep]" >&2; exit 2 ;;
    esac
done

repo="$(git rev-parse --show-toplevel)" || exit 2
head="$(git -C "$repo" rev-parse HEAD)" || exit 2
scratch="$(mktemp -d "${TMPDIR:-/tmp}/ci-rehearsal.XXXXXX")" || exit 2
hidden=()

cleanup() {
    for path in "${hidden[@]+"${hidden[@]}"}"; do
        /bin/mv -f "$scratch/hidden/$(basename "$path")" "$path"
    done
    if [ "$keep" = 1 ]; then
        echo "Scratch directory kept: $scratch"
    else
        /bin/rm -rf "$scratch"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

if [ "$hide_bins" = 1 ]; then
    mkdir -p "$scratch/hidden"
    for path in /tmp/extractbin /tmp/tablesbin; do
        if [ -e "$path" ]; then
            /bin/mv -f "$path" "$scratch/hidden/" && hidden+=("$path")
        fi
    done
fi

# One script per `run:` step, plus a manifest: job, runner, container, step number, name, script.
mkdir -p "$scratch/steps" "$scratch/logs"
git -C "$repo" show "$head:.github/workflows/ci.yml" > "$scratch/ci.yml" || exit 2
python3 - "$scratch/ci.yml" "$scratch/steps" > "$scratch/manifest.tsv" <<'PY' || exit 2
import os, re, sys

workflow, out = sys.argv[1], sys.argv[2]
lines = open(workflow).read().split("\n")
jobs, job, step, in_jobs, block = [], None, None, False, None

def finish_step():
    global step
    if job is not None and step is not None and step.get("run") is not None:
        job["steps"].append(step)
    step = None

for line in lines:
    indent = len(line) - len(line.lstrip(" "))
    text = line.strip()
    if block is not None:
        if text == "" or indent >= block:
            step["run"] += line[block:] + "\n"
            continue
        block = None
    if not text or text.startswith("#"):
        continue
    if indent == 0:
        in_jobs = text == "jobs:"
        continue
    if not in_jobs:
        continue
    if indent == 2 and text.endswith(":"):
        finish_step()
        job = {"id": text[:-1], "runner": "-", "container": "-", "steps": []}
        jobs.append(job)
        continue
    if indent == 4 and text.startswith("runs-on:"):
        job["runner"] = text.split(":", 1)[1].strip()
        continue
    if indent == 4 and text.startswith("container:"):
        job["container"] = text.split(":", 1)[1].strip()
        continue
    if indent == 6 and text.startswith("- "):
        finish_step()
        step = {"name": None, "run": None}
        text, indent = text[2:], 8
    if step is None or indent != 8:
        continue
    key, _, value = text.partition(":")
    value = value.strip()
    if key == "name":
        step["name"] = value
    elif key == "run":
        if value in ("|", ">"):
            step["run"], block = "", 10
        else:
            step["run"] = value + "\n"
finish_step()

for j in jobs:
    for n, s in enumerate(j["steps"], 1):
        path = os.path.join(out, f"{j['id']}-{n:02d}.sh")
        with open(path, "w") as f:
            f.write(s["run"])
        name = s["name"] or s["run"].split("\n")[0]
        print("\t".join([j["id"], j["runner"], j["container"], str(n), name, path]))
PY

newest_xcode() {
    local app
    app="$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V | tail -1)"
    [ -n "$app" ] && echo "$app/Contents/Developer"
}

developer_dir=""
if [ "$(uname)" = Darwin ]; then
    developer_dir="$(newest_xcode)"
fi
docker_ok=0
if command -v docker > /dev/null 2>&1 && docker info > /dev/null 2>&1; then
    docker_ok=1
fi

echo "CI rehearsal of $(git -C "$repo" log -1 --format='%h %s' "$head" | cut -c1-72)"
[ -n "$developer_dir" ] && echo "Xcode: $developer_dir"

passed=0; failed=0; skipped=0
summary=()
current=""; job_skip=""; job_failed=0; job_line=""; job_start=0; job_counts=""

close_job() {
    [ -z "$current" ] && return
    summary+=("$(printf '%-4s %-15s %s (%ss)' "$job_line" "$current" "$job_counts" "$(( $(date +%s) - job_start ))")")
}

while IFS=$'\t' read -r job runner container number name script; do
    if [ "$job" != "$current" ]; then
        close_job
        current="$job"; job_failed=0; job_line="PASS"; job_skip=""; job_start=$(date +%s)
        jp=0; jf=0; js=0
        workdir="$scratch/$job"
        git clone -q --no-hardlinks "$repo" "$workdir/src" && git -C "$workdir/src" checkout -q --detach "$head" \
            || job_skip="the clone failed"
        mkdir -p "$workdir/home" "$workdir/tmp" "$workdir/runner-temp"
        if [ "$container" != "-" ] && [ "$docker_ok" = 0 ]; then
            job_skip="Docker is not available for the $container container"
        elif [ "${runner#macos}" != "$runner" ] && [ -z "$developer_dir" ]; then
            job_skip="a macOS job needs macOS with Xcode"
        fi
    fi
    label="$job / $name"
    if [ -n "$job_skip" ]; then
        echo "SKIP $label ($job_skip)"; skipped=$((skipped + 1)); js=$((js + 1)); job_line="SKIP"
    elif [ "$job_failed" = 1 ]; then
        echo "SKIP $label (an earlier step failed)"; skipped=$((skipped + 1)); js=$((js + 1))
    elif grep -q "sudo " "$script"; then
        echo "SKIP $label (needs sudo; DEVELOPER_DIR stands in for it)"; skipped=$((skipped + 1)); js=$((js + 1))
    else
        log="$scratch/logs/$(basename "$script" .sh).log"
        start=$(date +%s)
        if [ "$container" != "-" ]; then
            docker run --rm --name "ci-rehearsal-$$-$job-$number" \
                -v "$workdir/src":/src -v "$scratch/steps":/steps:ro -w /src \
                "$container" bash -e "/steps/$(basename "$script")" > "$log" 2>&1
        else
            (cd "$workdir/src" && env -i HOME="$workdir/home" TMPDIR="$workdir/tmp/" \
                RUNNER_TEMP="$workdir/runner-temp" CI=true LANG=en_US.UTF-8 \
                PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
                ${developer_dir:+DEVELOPER_DIR="$developer_dir"} \
                bash -e "$script") > "$log" 2>&1
        fi
        rc=$?
        took=$(( $(date +%s) - start ))
        if [ "$rc" = 0 ]; then
            echo "PASS $label (${took}s)"; passed=$((passed + 1)); jp=$((jp + 1))
        else
            echo "FAIL $label (rc $rc, ${took}s; last line: $(tail -1 "$log" | cut -c1-80))"
            failed=$((failed + 1)); jf=$((jf + 1)); job_failed=1; job_line="FAIL"
        fi
    fi
    job_counts="$jp passed, $jf failed, $js skipped"
done < "$scratch/manifest.tsv"
close_job

echo "Summary"
printf '%s\n' "${summary[@]}"
[ "${#hidden[@]}" -gt 0 ] && echo "Hidden for the run: ${hidden[*]}"
echo "Steps: $passed passed, $failed failed, $skipped skipped"
[ "$failed" = 0 ]
