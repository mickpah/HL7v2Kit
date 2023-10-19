#!/usr/bin/env bash
# add-kernel-headers.sh
# Prepends the portable-kernel boundary marker to each Stratum-1 (kernel) file,
# but only if it isn't already present. Safe to run more than once.
#
# Run from the repo root:
#   bash scripts/add-kernel-headers.sh
#
# See docs/design/ADR-006-portable-core-boundary.md for what "kernel" means.

set -euo pipefail

MARKER="// PORTABLE KERNEL"

HEADER='// PORTABLE KERNEL — keep this file Foundation-free and byte/character-level.
// A future Rust/Go port translates this file directly. No NSRegularExpression,
// NSString, DateFormatter, CharacterSet, locale-aware ops, protocols, or
// generics in the parse path. `Data` only at the edges (to/from [UInt8]).
// See docs/design/ADR-006-portable-core-boundary.md
'

KERNEL_FILES=(
  "Sources/HL7v2Kit/Parser/Parser.swift"
  "Sources/HL7v2Kit/Parser/ParseError.swift"
  "Sources/HL7v2Kit/Builder/Serializer.swift"
  "Sources/HL7v2Kit/Segment/Field.swift"
  "Sources/HL7v2Kit/Path/Path.swift"
  "Sources/HL7v2Kit/Encoding/EncodingCharacters.swift"
  "Sources/HL7v2Kit/Encoding/EscapeSequences.swift"
  "Sources/HL7v2Kit/Version.swift"
  "Sources/HL7v2Kit/Locale/HL7Locale.swift"
)

added=0
skipped=0
missing=0

for f in "${KERNEL_FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "  MISSING: $f (skipping)"
    missing=$((missing+1))
    continue
  fi
  if head -1 "$f" | grep -q "$MARKER"; then
    echo "  already marked: $f"
    skipped=$((skipped+1))
    continue
  fi
  # Prepend header + blank line, preserving the original content.
  tmp="$(mktemp)"
  printf '%s\n' "$HEADER" > "$tmp"
  cat "$f" >> "$tmp"
  mv "$tmp" "$f"
  echo "  marked: $f"
  added=$((added+1))
done

echo ""
echo "Done. Added: $added, already marked: $skipped, missing: $missing"
echo ""
echo "Now run: xcrun swift build   (headers are comments; build must stay green)"
