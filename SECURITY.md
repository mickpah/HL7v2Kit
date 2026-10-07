# Security Policy

## Supported versions

| Version | Security fixes |
|---|---|
| Latest minor release | Yes, best effort |
| Everything else | No |

A fix ships in a new release of the latest minor line; nothing is backported. `SUPPORT.md`
sets out what "best effort" means.

## Reporting a vulnerability

Report it privately through GitHub's private vulnerability reporting:
<https://github.com/mickpah/HL7v2Kit/security/advisories/new> (the repository's Security tab).
Do not open a public issue. A report will be acknowledged within 14 days.

Include:

- the HL7v2Kit version and the platform and Swift version;
- the HL7 version (MSH-12) and the locale or validation preset, if they matter;
- a minimal reproduction: the input, the call, and what happened;
- why you consider it a security issue, and the impact you expect.

**No patient data in a report, ever.** Not real, not "anonymised", not partial. Build the
reproduction from synthetic data, following the conventions in `Tests/Fixtures/README.md`. A
report that carries real patient data will be deleted unread and the reporter asked to resend.

## Scope

In scope:

- a crash, hang or unbounded memory or time use in the parser, builder or validator on hostile
  or malformed input;
- a validator bypass: a message that breaks a rule the package claims to check is reported as
  valid;
- patient data leaking through log output, error text, issue messages or descriptions in a
  way the documentation does not state.

Out of scope:

- a gap already recorded in `docs/design/permanent-limitations-register.md`: those are known
  limitations of the model, reported openly, and welcome as ordinary issues if you think one is
  wrong;
- a spec-reading disagreement, which belongs in an ordinary issue citing the version, chapter,
  section and page;
- anything that needs a modified copy of the package, or a caller's own handling of the data
  the package returns.

## Disclosure

Disclosure is coordinated. Once a fix is ready it ships in a release, with an entry in
`CHANGELOG.md` and a GitHub security advisory crediting the reporter unless they prefer
otherwise. Please keep the details private until that release is out. There is no bug bounty.
