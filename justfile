# Maintenance tasks. `just` lists them; `just <task>` runs one.
# Needs: just, Xcode (Swift 6.2 for the test suite), python3 (the scripts are standard library
# only), uv for the optional virtual environment, Docker for the Linux step of the rehearsal.

set shell := ["bash", "-euo", "pipefail", "-c"]

export DEVELOPER_DIR := env("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")

# The scripts run under the uv environment when it exists, otherwise the system python3.
python := if path_exists(".venv/bin/python") == "true" { ".venv/bin/python" } else { "python3" }

# List the tasks.
default:
    @just --list --unsorted

# Build every target (the MessageViewer example is macOS only).
build:
    xcrun swift build

# The whole suite, behind a time limit; the summary line only.
test:
    timeout 900 xcrun swift test 2>&1 | grep -E "error:|warning:|Test run with|recorded an issue"

# One suite or test, by name: `just test-only PathTests`.
test-only pattern:
    timeout 900 xcrun swift test --filter "{{pattern}}" 2>&1 | grep -E "error:|warning:|Test run with|recorded an issue"

# The console example.
quickstart:
    xcrun swift run QuickStart

# The SwiftUI example.
viewer:
    xcrun swift run MessageViewer

# Regenerate the Generated/ outputs after a schema or override edit (codegen-drift checks this).
regenerate:
    bash scripts/regenerate-typed-segments.sh

# The CI checks that need no display: the PHI scan and the codegen guard.
check:
    bash scripts/scan-fixtures-for-phi.sh
    bash scripts/check-structure-codegen.sh

# Build the DocC catalogue from a scratch copy and fail on any warning, as the docc CI job does.
docc:
    #!/usr/bin/env bash
    set -euo pipefail
    scratch="$(mktemp -d)"
    trap 'rm -rf "$scratch"' EXIT
    rsync -a --exclude HL7v2Kit.xcworkspace --exclude .build --exclude .swiftpm --exclude .venv ./ "$scratch/src/"
    cd "$scratch/src"
    xcodebuild docbuild -scheme HL7v2Kit -destination 'generic/platform=macOS' -derivedDataPath "$scratch/dd" > "$scratch/docc.log" 2>&1 || { tail -20 "$scratch/docc.log"; exit 1; }
    if grep -E '^[^ ]+\.(swift|md):[0-9]+(:[0-9]+)?: warning:|^warning: ' "$scratch/docc.log" | grep -vE "^warning: '[^']+': "; then echo "docc: warnings"; exit 1; fi
    echo "docc: 0 warnings"

# Every CI step on a clean clone of HEAD (committed work only; Linux through Docker).
rehearsal:
    bash scripts/ci-rehearsal.sh --hide-tmp-binaries

# A uv-managed virtual environment for the python utilities (standard library only; a pinned interpreter).
venv:
    uv venv .venv
    @echo "activate with: source .venv/bin/activate"

# Remove the virtual environment and python caches.
venv-clean:
    rm -rf .venv scripts/__pycache__ .ruff_cache .mypy_cache
    find . -name "*.pyc" -not -path "./.build/*" -delete

# Remove build products, DocC output and python caches (not the virtual environment).
clean:
    rm -rf .build .swiftpm site *.doccarchive scripts/__pycache__
    find . -name ".DS_Store" -not -path "./.build/*" -delete

# Everything `clean` and `venv-clean` remove, plus the uv cache for this project.
distclean: clean venv-clean
    uv cache clean --quiet

# Where things stand: branch, tags, worktrees, the tree.
status:
    @git log --oneline -1
    @echo "tags: $(git tag | wc -l | tr -d ' '), newest $(git tag --sort=-v:refname | head -1)"
    @git worktree list
    @git status --short | head -20
