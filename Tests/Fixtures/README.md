# Test fixtures

Every fixture in this directory must be synthetic, anonymised v2 data with no real PHI.

See `docs/design/HL7v2Kit-Spec.md` §10 for the anonymisation policy.

## Provenance

| File | Source | Licence | Anonymisation |
|---|---|---|---|
| _(none yet — sprint 3 work)_ | | | |

## Adding a fixture

1. Run it through `scripts/anonymise-fixture.swift` (not yet implemented).
2. Add a row to the table above.
3. Add a corresponding test in `Tests/HL7v2KitTests/`.
