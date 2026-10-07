#!/usr/bin/env python3
"""Check that CHANGELOG.md's version headings and link references agree.

Every `## [X]` heading must have a `[X]: <url>` link reference, and every link
reference must name a heading. Each URL must point at this repository's compare
or release-tag pages. Standard library only; exits non-zero on any finding.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO = "https://github.com/mickpah/HL7v2Kit/"


def main() -> int:
    text = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    headings = re.findall(r"^## \[([^\]]+)\]", text, re.MULTILINE)
    links = dict(re.findall(r"^\[([^\]]+)\]: (\S+)$", text, re.MULTILINE))
    findings = []
    for name in headings:
        if headings.count(name) > 1:
            findings.append(f"heading [{name}] appears more than once")
        if name not in links:
            findings.append(f"heading [{name}] has no link reference")
    for name, url in links.items():
        if name not in headings:
            findings.append(f"link [{name}] has no heading")
        if not url.startswith(REPO + "compare/") and not url.startswith(REPO + "releases/tag/"):
            findings.append(f"link [{name}] points outside the repository: {url}")
        elif name != "Unreleased" and not url.endswith("v" + name):
            findings.append(f"link [{name}] does not end at tag v{name}: {url}")
    for line in sorted(set(findings)):
        print(f"check-changelog-links: {line}")
    print(f"check-changelog-links: {len(headings)} heading(s), {len(links)} link(s), "
          f"{len(set(findings))} finding(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
