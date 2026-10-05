#!/usr/bin/env bash
# regenerate-typed-segments.sh
# Re-runs HL7v2KitCodegen against the schema JSONs and overwrites the generated
# Swift sources under Sources/HL7v2Kit/Segment/Generated/, and against the code
# tables under Resources/tables/ (output: Sources/HL7v2Kit/Tables/Generated/),
# and the datatype component tables under Resources/datatypes/ (output:
# Sources/HL7v2Kit/DataTypes/Generated/),
# and the message structures under Resources/structures/ (output:
# Sources/HL7v2Kit/Structures/Generated/, ADR-019). Resources/struct-bases.json
# pins the union base of each released segment struct (P10-3, ADR-020).
# Commit the result.
#
# Run from the repo root:
#   bash scripts/regenerate-typed-segments.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEMAS_DIR="$REPO_ROOT/Resources/schemas"
OUTPUT_DIR="$REPO_ROOT/Sources/HL7v2Kit/Segment/Generated"
TABLES_DIR="$REPO_ROOT/Resources/tables"
TABLES_OUTPUT_DIR="$REPO_ROOT/Sources/HL7v2Kit/Tables/Generated"
DATATYPES_DIR="$REPO_ROOT/Resources/datatypes"
DATATYPES_OUTPUT_DIR="$REPO_ROOT/Sources/HL7v2Kit/DataTypes/Generated"
PROFILES_DIR="$REPO_ROOT/Resources/profiles"
PROFILES_OUTPUT_DIR="$REPO_ROOT/Sources/HL7v2Kit/Locale/Generated"
COMPOSITES_FILE="$REPO_ROOT/Resources/composites/composite-views.json"
COMPOSITES_OUTPUT_DIR="$REPO_ROOT/Sources/HL7v2Kit/Composite/Generated"
STRUCTURES_DIR="$REPO_ROOT/Resources/structures"
STRUCTURES_OUTPUT_DIR="$REPO_ROOT/Sources/HL7v2Kit/Structures/Generated"
STRUCT_BASES_FILE="$REPO_ROOT/Resources/struct-bases.json"

# The Testing module ships with full Xcode, not Command Line Tools. The
# codegen target itself only imports Foundation, but `swift run` plans the
# whole package — so use the Xcode toolchain if available.
if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

xcrun swift run --package-path "$REPO_ROOT" HL7v2KitCodegen "$SCHEMAS_DIR" "$OUTPUT_DIR" "$TABLES_DIR" "$TABLES_OUTPUT_DIR" "$DATATYPES_DIR" "$DATATYPES_OUTPUT_DIR" "$PROFILES_DIR" "$PROFILES_OUTPUT_DIR" "$COMPOSITES_FILE" "$COMPOSITES_OUTPUT_DIR" "$STRUCTURES_DIR" "$STRUCTURES_OUTPUT_DIR" "$STRUCT_BASES_FILE"
