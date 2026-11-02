#!/usr/bin/env bash
# Regression guard for the anonymiser's byte path, which no in-process test can be: it builds
# the debug HL7v2KitAnonymise binary (linked at the package's macOS floor) and runs it on a
# synthetic message declared ASCII (MSH-18) that holds byte E9. The parser refuses the byte, so
# the tool must exit 1 and write no output file (3.29.0 found Foundation's ASCII decode lenient
# in a floor-linked binary; 3.30.0 made the tool exit with a status).
#
#   bash scripts/check-anonymiser-byte-path.sh
set -euo pipefail

swift build --product HL7v2KitAnonymise
tool="$(swift build --product HL7v2KitAnonymise --show-bin-path)/HL7v2KitAnonymise"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# The MSH ends in MSH-18 "ASCII"; the NTE holds "Caf" then the byte E9 (not ASCII).
printf 'MSH|^~\\&|APP|FAC|||20260101||ADT^A01^ADT_A01|CTRL1|P|2.5.1||||||ASCII\rNTE|1||Caf\351\r' > "$work/in.hl7"

# Control: the same message with plain "Cafe" is accepted, so the refusal below is the byte's.
printf 'MSH|^~\\&|APP|FAC|||20260101||ADT^A01^ADT_A01|CTRL1|P|2.5.1||||||ASCII\rNTE|1||Cafe\r' > "$work/control.hl7"
"$tool" "$work/control.hl7" "$work/control-out.hl7" 2> /dev/null || {
    echo "::error::HL7v2KitAnonymise refused the control message with no byte above 0x7F."
    exit 1
}

status=0
"$tool" "$work/in.hl7" "$work/out.hl7" || status=$?

if [ "$status" -ne 1 ]; then
    echo "::error::HL7v2KitAnonymise exited $status on an ASCII message holding byte E9; expected 1."
    exit 1
fi
if [ -e "$work/out.hl7" ]; then
    echo "::error::HL7v2KitAnonymise wrote an output file for a message it refused."
    exit 1
fi
echo "HL7v2KitAnonymise refused the ASCII message holding byte E9 (exit 1, no output file)."
