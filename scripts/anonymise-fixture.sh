#!/usr/bin/env bash
# anonymise-fixture.sh
# PHI-scrub a v2 message file per spec § 10. The actual logic lives in the
# HL7v2KitAnonymise executable target; this wrapper handles the toolchain
# environment + path resolution.
#
# Run from the repo root:
#   bash scripts/anonymise-fixture.sh <input.hl7> [output.hl7]
#
# If output is omitted, writes to stdout — useful for piping into diff or
# scan-fixtures-for-phi.sh before committing.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: bash scripts/anonymise-fixture.sh <input.hl7> [output.hl7]" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Swift Testing ships with full Xcode, not Command Line Tools. The
# anonymise target itself only depends on HL7v2Kit (which is CLT-compatible),
# but `swift run` plans the whole package — so use the Xcode toolchain if
# available.
if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

xcrun swift run --package-path "$REPO_ROOT" HL7v2KitAnonymise "$@"
