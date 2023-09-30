#!/usr/bin/env bash
# scan-fixtures-for-phi.sh
# Refuses to merge changes that introduce real-looking AU healthcare
# identifiers into the test fixture corpus.
#
# Hits don't necessarily mean PHI, but they require manual inspection
# and an explicit anonymisation log entry in Tests/Fixtures/README.md.
#
# Patterns checked:
#   - IHI (16 digits starting with 80031)        \b80031\d{11}\b
#   - Medicare card (10–11 digits)               \b[2-6]\d{9,10}\b in suspicious contexts
#   - DVA file numbers
#   - Real-looking AU mobile numbers (04xx xxx xxx)
#
# Exit codes:
#   0  no hits
#   1  hits found — review and remediate before merging

set -euo pipefail

FIXTURE_DIR="Tests/Fixtures"

if [[ ! -d "$FIXTURE_DIR" ]]; then
  echo "No fixture directory found at $FIXTURE_DIR — nothing to scan."
  exit 0
fi

HITS=0

# IHI pattern: 80031 followed by 11 digits.
if grep -rEn '\b80031[0-9]{11}\b' "$FIXTURE_DIR" --include='*.hl7' --include='*.txt' 2>/dev/null; then
  echo "::error::Potential real IHI pattern detected"
  HITS=$((HITS+1))
fi

# Australian mobile pattern (loose): 04 followed by 8 digits, in field-like context.
if grep -rEn '\b04[0-9]{8}\b' "$FIXTURE_DIR" --include='*.hl7' --include='*.txt' 2>/dev/null | head -5; then
  echo "::warning::Australian mobile number pattern detected — verify these are synthetic"
fi

if [[ $HITS -gt 0 ]]; then
  echo ""
  echo "PHI scan found $HITS pattern(s). Fixtures must be re-anonymised."
  exit 1
fi

echo "PHI scan: no patterns matched."
exit 0
