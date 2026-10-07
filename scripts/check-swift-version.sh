#!/usr/bin/env bash
# Fails unless the active Swift toolchain is at least MAJOR.MINOR.
#
#   bash scripts/check-swift-version.sh 6.2
#
# CI runs it after selecting the runner's newest Xcode, so a runner image whose newest Xcode is
# too old fails here, by name, rather than later with a compile error in the test target.
set -euo pipefail

minimum="${1:?usage: check-swift-version.sh MAJOR.MINOR}"
reported="$(swift --version 2>&1 | grep -Eo 'Swift version [0-9]+\.[0-9]+' | head -1 || true)"
actual="${reported#Swift version }"

if [ -z "$actual" ]; then
    echo "::error::Could not read a Swift version from 'swift --version'."
    exit 1
fi

lowest="$(printf '%s\n%s\n' "$minimum" "$actual" | sort -t. -k1,1n -k2,2n | head -1)"
if [ "$lowest" != "$minimum" ]; then
    echo "::error::Swift $actual is below the required $minimum. Select a newer Xcode."
    exit 1
fi
echo "Swift $actual meets the $minimum minimum."
