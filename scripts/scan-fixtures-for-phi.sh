#!/usr/bin/env bash
# scan-fixtures-for-phi.sh
# Refuses to merge changes that introduce real-looking AU healthcare
# identifiers into the test fixture corpus, or licensed standards content
# into the repository.
#
# Hits don't necessarily mean PHI, but they require manual inspection
# and an explicit anonymisation log entry in Tests/Fixtures/README.md
# (or a documented ALLOWED entry in scripts/scan-for-phi.py).
#
# The patterns live in scripts/scan-for-phi.py (one source for both modes):
#   - IHI / HPI-I / HPI-O (16 digits, 800360 / 800361 / 800362; any 8003 prefix)
#   - Medicare card (10-11 digits, first digit 2-6, valid check digit)
#   - DVA file numbers (state letter, war code, digits to 8 characters)
#   - AU mobile numbers (04xxxxxxxx, 04xx xxx xxx, +614xxxxxxxx)
#   - licensed content: %PDF- headers, pdftotext form feeds, XSD schemas,
#     the HL7 v2.xml bundle namespaces, and any .pdf/.xsd/.xml or
#     docs/standards/ or docs/XML-schemas/ path
#
# Usage:
#   bash scripts/scan-fixtures-for-phi.sh             working tree (Tests/Fixtures)
#   bash scripts/scan-fixtures-for-phi.sh --history   every blob in every commit
#   bash scripts/scan-fixtures-for-phi.sh --self-test synthetic-string checks
#
# History mode needs the full history (CI checks out with fetch-depth: 0).
# See docs/design/private/public-release-history-check.md.
#
# Exit codes:
#   0  no hits
#   1  hits found — review and remediate before merging

set -euo pipefail

exec python3 "$(dirname "$0")/scan-for-phi.py" "$@"
