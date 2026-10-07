# Public-release history check (P13 S1-1)

Before the repository goes public, every blob that any commit has ever held is checked for
PHI-shaped identifiers and for licensed standards content, not only the working tree. History
is not rewritten by this check; a hit is reported for the owner to decide.

## Method

`bash scripts/scan-fixtures-for-phi.sh --history` (the patterns live in
`scripts/scan-for-phi.py`; the shell script only passes its arguments on).

1. `git log --all -m --raw --no-renames --no-abbrev -z` lists every (commit, path, blob) that
   any commit reachable from any ref added, changed or deleted. `-m` diffs a merge against each
   parent, so a blob that only a conflict resolution produced is still listed. Each blob keeps
   every path it was ever stored under, with the oldest commit that introduced it there.
2. `git rev-list --all --objects` is cross-checked against that list. Any blob reachable from a
   ref but named by no commit diff (a tagged blob, say) is added under its rev-list name. On
   this repository the count is zero.
3. Each blob is read once, by hash, through a single `git cat-file --batch` process, and scanned
   at each of its paths.
4. Each hit prints the pattern, the matched value, the path, the blob and the introducing
   commit. Any hit not in `ALLOWED` makes the scan exit 1.

The working-tree mode (no argument) applies the same patterns to every file under
`Tests/Fixtures/` and the licensed-path check to `git ls-files`. `--self-test` runs 22
synthetic cases; eight of them pass under the patterns the scanner held before P13.

## Scope

| Check | Applies to |
| --- | --- |
| PHI patterns, XSD and v2.xml signatures | paths under `Tests/Fixtures/`, every `*.hl7` and `*.txt`, every licensed path |
| `%PDF-` header, pdftotext form feeds | every blob in the history |
| licensed path | every path in the history |

Swift sources, JSON resources and Markdown are outside the PHI scope: the Swift tests carry
identifier-shaped values by design (see "Outside the gated scope" below), and the scripts quote
the v2.xml namespaces they parse.

## Patterns

Before P13 the scanner grepped two patterns: an "IHI" of `80031` plus 11 digits (not a real
NASH prefix; the IHI prefix is `800360`) as an error, and `04` plus 8 digits as a warning that
never failed the scan. The Medicare and DVA lines in its header were never grepped.

| Name | Pattern |
| --- | --- |
| `ihi`, `hpi-i`, `hpi-o` | 16 digits with prefix `800360`, `800361`, `800362` |
| `nash-8003` | any other 16 digits with prefix `8003` (includes the old `80031` shape) |
| `medicare` | 10 or 11 digits, first digit 2 to 6, valid check digit (weights 1 3 7 9 1 3 7 9 on digits 1 to 8, mod 10), issue number 1 to 9; also the printed form `2123 45670 1` |
| `dva` | state letter N, V, Q, S, W or T, a war code of 1 to 3 letters, digits to an 8-character core, optional segment-link letter (`NX123456`, `VSM12345A`) |
| `au-mobile` | `04xxxxxxxx`, `04xx xxx xxx`, `+614xxxxxxxx` (now a failure, not a warning) |
| `pdf` | a blob starting `%PDF-` |
| `pdftotext` | a text blob with three or more form feeds (pdftotext page breaks) |
| `xsd` | `<xsd:schema` or `<xs:schema` |
| `v2xml` | `urn:hl7-org:v2xml`, `urn:com.sun:encoder-hl7-1.0`, or the bundle banner `v2.xml Message Definitions` |
| `licensed-path` | any path ending `.pdf`, `.xsd` or `.xml`, or under `docs/standards/` or `docs/XML-schemas/` |

The Medicare check digit keeps 10-digit timestamps and counters from tripping the pattern; a
14-digit HL7 timestamp never matches, being bounded by digits.

## Allow-list

Empty. The AU fixtures' synthetic organisation identifiers zero-fill the 16-digit OID body
(`1.2.36.1.2001.1003.0.0000000000001001`, `...0000000000002002`); with no `8003` prefix they
match no pattern, so need no exception. Synthetic patient identifiers use `SYN-NNNN`,
facilities `SYNTH_`, providers `DR########` (Tests/Fixtures/README.md); none of these is
identifier-shaped either. A future exception goes into `ALLOWED` in `scripts/scan-for-phi.py`
as (pattern, exact value) with its reason recorded here.

## Run

| Item | Value |
| --- | --- |
| Date | 2026-10-07 |
| Commit | `b5e14111` (main), rerun at `8f091f76` after the scanner commit |
| Refs walked | 81 (every branch and tag); 1075 commits reachable from them (851 on main) |
| Blobs scanned | 16,036 (209 in PHI scope), 475.7 MB in total, 0 reachable only outside a commit diff |
| Time | 1.0 s wall clock |
| Result | `history scan: ... 0 hit(s)`, exit 0 |

Positive control: in a throwaway clone, a commit adding a fixture with an IHI-shaped value and
a `%PDF-` file under `docs/`, followed by a commit deleting both, gave three hits (`ihi`,
`licensed-path`, `pdf`) naming the adding commit, and exit 1.

Independent confirmation that no licensed path ever existed, each returning 0:
`git log --all -m --name-only`, `git rev-list --all --objects`, and `git ls-tree -r` over every
commit, each grepped for `.pdf`, `.xsd`, `.xml`, `docs/standards/` and `docs/XML-schemas/`;
and every object in the object store, unreachable ones included
(`git cat-file --batch-all-objects`), grepped for a `%PDF-` line.

## Outside the gated scope

A one-off sweep with the PHI patterns applied to every blob (33 s) found five values, all in
`Tests/HL7v2KitTests/` and one in `docs/design/p12-adrm-partial-points-audit.md`. They are not
patient identifiers; they are listed for the owner's decision before publication.

| Value | Kind | Where | Note |
| --- | --- | --- | --- |
| `8003621566684455` | HPI-O | AU NASH, assigning-authority, PRD and ADRM prose tests; the P12 audit | Luhn-valid. Used as the ADRM example organisation; provenance not verified against a local copy of the ADRM |
| `8003629900024197` | HPI-O | AU NASH entity-identifier and code-table tests | Luhn-valid |
| `8003611566701234` | HPI-I | one ADRM prose test (read-ack MSH-3) | fails the Luhn check, so cannot be a real HPI-I |
| `0412345678` | mobile | `CompositeTypeTests` XTN test | sequential placeholder, not in the ACMA range reserved for fiction (0491 57x xxx) |
| `61255551234` | phone matching the Medicare shape | `CompositeTypeTests` XTN test | `+61 2 5551234`: a 7-digit subscriber number, so not a dialable AU number (they have 8) |

An HPI-O names an organisation in a public directory, not a person, so neither HPI-O is PHI;
if either is a real organisation's number, replacing it with a zero-filled body (as the
fixtures do) or an obviously synthetic Luhn-invalid value removes the question.

## CI

The history scan runs in about a second, so it runs in the `PHI scan` job of
`.github/workflows/ci.yml`, whose checkout now uses `fetch-depth: 0`. CI sees only the refs the
runner fetches (all branches and tags of the remote); local refs never pushed are covered by
running `bash scripts/scan-fixtures-for-phi.sh --history` before any push.
