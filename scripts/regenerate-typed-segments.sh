#!/usr/bin/env bash
# regenerate-typed-segments.sh
# Re-runs HL7v2KitCodegen against the schema JSONs and overwrites the generated
# Swift sources under Sources/HL7v2Kit/Segment/Generated/. Commit the result.
#
# Run from the repo root:
#   bash scripts/regenerate-typed-segments.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEMAS_DIR="$REPO_ROOT/Resources/schemas"
OUTPUT_DIR="$REPO_ROOT/Sources/HL7v2Kit/Segment/Generated"

# The Testing module ships with full Xcode, not Command Line Tools. The
# codegen target itself only imports Foundation, but `swift run` plans the
# whole package — so use the Xcode toolchain if available.
if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

xcrun swift run --package-path "$REPO_ROOT" HL7v2KitCodegen "$SCHEMAS_DIR" "$OUTPUT_DIR"
