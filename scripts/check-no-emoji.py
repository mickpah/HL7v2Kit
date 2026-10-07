#!/usr/bin/env python3
"""Guard: no emoji or icon characters in tracked text files (owner rule).

    python3 scripts/check-no-emoji.py             scan every tracked text file
    python3 scripts/check-no-emoji.py --self-test run the synthetic-string checks

Scans `git ls-files`, skipping docs/archive (snapshots are never edited). Exits 1 and prints
file:line for each hit. Typographic arrows (U+2190-U+21FF), box drawing and ordinary
symbols are allowed; dingbats, pictographs and emoji presentation characters are not.
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

RANGES = [
    (0x2600, 0x27BF),    # miscellaneous symbols and dingbats
    (0x2B1B, 0x2B1C), (0x2B50, 0x2B50), (0x2B55, 0x2B55),
    (0x231A, 0x231B), (0x23E9, 0x23FA),
    (0x25AA, 0x25AB), (0x25B6, 0x25B6), (0x25C0, 0x25C0), (0x25FB, 0x25FE),
    (0x1F000, 0x1FAFF),  # pictographs, emoticons, transport, supplemental symbols
    (0xFE0F, 0xFE0F),    # emoji variation selector
    (0x200D, 0x200D),    # zero width joiner (emoji sequences)
]

SKIP_PREFIXES = ("docs/archive/",)


def is_icon(ch):
    cp = ord(ch)
    return any(lo <= cp <= hi for lo, hi in RANGES)


def scan_text(text):
    """Return (line_number, character) for each icon character in text."""
    hits = []
    for n, line in enumerate(text.split("\n"), 1):
        hits.extend((n, ch) for ch in line if is_icon(ch))
    return hits


def tracked_files():
    out = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, check=True,
                         capture_output=True).stdout.decode("utf-8")
    return [p for p in out.split("\0") if p and not p.startswith(SKIP_PREFIXES)]


def scan_repo():
    found = []
    for rel in tracked_files():
        try:
            with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
                text = fh.read()
        except (UnicodeDecodeError, OSError):
            continue  # binary or unreadable
        found.extend((rel, n, ch) for n, ch in scan_text(text))
    return found


def self_test():
    flagged = ["\u2705", "\u274c", "\u2714", "\u2716", "\u2728", "\u26a0", "\u2b50",
               "\U0001F600", "\U0001F680", "\u2718", "\u279c"]
    for ch in flagged:
        assert scan_text("a " + ch + " b"), "should flag U+%04X" % ord(ch)
    assert scan_text("x\ny \u26a0\ufe0f") == [(2, "\u26a0"), (2, "\ufe0f")]
    clean = ["plain text", "→ ← ⇒ arrows", "café µs — dash",
             "box ─│┌", "math ≤ ≠ ×", "… ellipsis §"]
    for s in clean:
        assert not scan_text(s), "should allow %r" % s
    assert scan_text('grep -E "Test run with|\u2718"')
    assert "docs/archive/x.md".startswith(SKIP_PREFIXES)
    print("check-no-emoji self-test: ok")


def main():
    if "--self-test" in sys.argv:
        self_test()
        return 0
    found = scan_repo()
    for rel, n, ch in found:
        print("%s:%d: U+%04X" % (rel, n, ord(ch)))
    print("check-no-emoji: %d hit(s)" % len(found))
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
