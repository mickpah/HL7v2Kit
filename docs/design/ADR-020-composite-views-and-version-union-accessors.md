# ADR-020 — Composite views to full spec depth, and version-union typed accessors

**Status:** Accepted 2026-10-02 -- Option B (owner, gate G3, answered "Generate them" on
2026-09-30; remediation plan P9).

**Context:** Two review findings share one cause. The typed API was shaped by
"what common traffic populates" and by a single canonical version.

- **V251-C11.** The composite views expose only part of v2.5.1: CX 6 of 10
  components, XPN 6 of 14, XAD 7 of 14, XCN 6 of 23, XTN 8 of 12 and PL 4 of 11.
  The XCN header justifies this with "the six commonly-populated components", a
  consumer-profile argument that project requirement 1 rejects. Typed accessors
  on repeating fields (PID-3) return the first repetition only, and the DocC does
  not say the field repeats.
- **V282-C10.** Typed segment structs are generated from v2.5.1 only
  (`canonicalVersion`). So there are no accessors for PID-40, ORC-32..34,
  OBR-51..54 or OBX-26..30. OBX-8 is still `abnormalFlags: String?`, but v2.8.2
  makes it "Interpretation Codes", a repeating CWE. CWE exposes 9 of v2.8.2's 22
  components. No wire data is lost, because `field` is retained, but an
  integrator cannot reach the later surface through the typed API.

The composite views are hand-written (16 view files, 1169 lines). The per-version
component tables they would need already exist as extractor output under
`Resources/datatypes/v*/` (ADR-017), and so do the per-version segment schemas.
The package is on the 3.x line, where ADR-014 permits additive changes only.

**State of the code this ADR starts from** (as of v3.13.0 plus remediation workstreams
P5 and P6):

- **Per-version component tables.** `DataTypeGrammarTable.grammar(_:version:)` carries a
  complete table for every supported version, v2.3 to v2.8.2. P5 completed the v2.3 to
  v2.4 grammars (CE, CNE, CD, CF, TS and TQ among them). MA and NA are open arrays.
  Field-local `CM` composites, where each field defines its own components, are served by
  the public `DataTypeGrammarTable.grammar(segment:field:version:)`, whose extractor output
  lives under `Resources/datatypes/v2.3/fields/`, `v2.3.1/fields/` and `v2.4/fields/`; from v2.5
  every composite has its own table. Across the supported versions the
  hand-written views cover CX 6 of 12, XPN 6 of 15, XAD 7 of 23, XCN 6 of 25, XTN 8 of
  18, PL 4 of 11, CWE 9 of 22, CNE 6 of 22 and XON 4 of 10.
- **Segment schemas.** Typed structs are generated from the v2.5.1 schema
  (`canonicalVersion` in `Sources/HL7v2KitCodegen/Codegen.swift`), or, for a segment v2.5.1
  does not define, from the earliest version that does. Each other version's schema feeds only
  its `SegmentGrammar+vX_Y_Z.swift`. Since P6-9 the schema naming rule is fixed: a slot whose
  element name matches the canonical v2.5.1 element at the same index takes the canonical
  `swiftName`, and any other slot takes `deriveSwiftName` of its printed name. A released
  name that a correction changes is kept as a deprecated alias through
  `deprecatedSwiftNames` (TQ2-10 and QPD-2 so far). This ADR relies on that rule: a
  released name never changes. A later-version name for an index the base defines is the
  same element renamed; it gets its own accessor only when its Swift type differs from the
  base accessor's (P9-5 ruling 1), otherwise a DocC note on the base accessor.
- **Cardinality and extra components.** `FieldGrammar.maxRepetitions` (P6-4) records a
  printed repetition bound, and the validator checks it. The validator also checks extra
  components on primitive and composite fields (P6-13 to P6-15). Those checks read the
  grammar, not the typed views, so completing the views does not change validation.

## Options

### Option A — Hand-complete the views and hand-add later-version accessors
Write the missing components into each of the 16 view files (about 115 accessors),
and hand-add later-version accessors to the segment structs.
- **Cost:** the segment structs are generated, so hand additions are impossible
  there without a second hand-curated layer. Nothing stops the views drifting
  from the component tables when P5 or a new version (P3) adds components.
- **Verdict:** rejected. It repeats the drift that produced V251-C11.

### Option B — Generate both from the extracted grammar (recommended)
1. **Composite views.** A curated name map (`Resources/composites/composite-views.json`)
   gives every component index an accessor name. Existing hand-written names are
   listed as `handWritten` and keep their frozen spelling and DocC. The generator
   emits a `<T>+Components.swift` extension for every other index. It fails when
   any index that any version defines lacks a name, or when a name clashes with
   another name, a Swift keyword or a `CompositeView` member. Each generated
   accessor returns the first subcomponent, like the hand-written ones. Its DocC
   lists the versions that define the component and every differing printed name.
   A new public `component(_:as:)` views a sub-composite (CX-4 as `HD`), and
   `viewed(as:)` views the same field as another composite.
2. **Repeating fields.** Every repeating field (`*` or a bound of 2 or more) gains `<name>All: [T]` (`[String?]` for
   scalars, `[Field]` for raw fields), built on a new public
   `TypedSegment.repetitions(_:)`. The singular accessor's DocC says the field
   repeats.
3. **Version union.** Each segment struct renders from its base schema (canonical
   v2.5.1, or else the earliest definer, as today; a released struct's base is pinned,
   see the P10-3 amendment) and then adds what the other
   supported versions contribute (P9-5, with the controller's rulings 1 to 3):
   - fields past the base maximum, and positions the base reserves (no data type)
     that a later version defines, under their own names and types. These are
     redefinitions: each accessor's DocC names the other elements at the position.
   - **Ruling 1, one accessor per element and type.** A position the base defines is
     the same element in every version. A later name for it gets its own accessor,
     typed as that version prints it, only when that Swift type differs from the base
     accessor's; a same-type rename is a DocC note on the base accessor ("v2.8.2
     prints this element as `Disability Indicator`").
   - **Ruling 2, renames are worded as renames.** A kept rename's DocC says "Same
     element as `<base name>`, renamed in <version>; typed as <version> prints it",
     its "Defined in" lists every version that defines the position, and the two
     accessors cross-reference each other. Every printed name of the element is
     listed with the accessor whose type matches that version. An earlier version
     never reaches a later accessor by name.
   - **Ruling 3, retypes.** A version (earlier or later) that types the position as a
     composite view where the accessor is scalar or raw gets `<name>As<T>`. Where the
     accessor is a view and another version prints a different view, the DocC points
     at `viewed(as:)` and no symbol is added, unless the element was also renamed
     (ruling 1 then applies and the DocC says so). Where the accessor is a view and
     another version prints a scalar, the DocC names the version and the scalar type.
   - `<name>All` wherever any version that prints the element repeats it, with the
     repeating versions in the DocC.

   A name clash stops codegen, so a curator must fix it. The union is computed from
   the schemas alone.
- **Cost:** about 1,100 new generated accessors across the segment structs, plus
  about 115 composite accessors. There are 3 new public methods. The generated
  files get larger; compile time must be measured in P9-5.
- **Per-version availability:** the accessors read the wire whatever version it
  declares, so an absent field or component returns `nil`. This is the existing
  Optional contract. Version facts live in DocC ("Defined from v2.8.2"), and the
  machine-readable form stays in `DataTypeGrammarTable` and `SegmentGrammar`.

### Option C — Record the gap as a limitation only
Add a register row and DocC, and change no code.
- **Verdict:** rejected as the end state, under project requirement 3: the model
  can be extended, so it must be. Its register row is written now (P9-1) and
  narrowed to the residual once Option B lands (P9-6).

### Option D — Separate typed structs per version (`PID_v2_8_2`)
- **Verdict:** rejected. About 6 times the struct count. Callers must switch on
  version to read a field. It duplicates the Optional contract that already
  covers absent fields.

## API compatibility (ADR-014)

Every change in Option B is additive:

| Change | Kind | 3.x-legal? |
|---|---|---|
| New stored-free computed properties on the 16 view structs | additive member | yes |
| `CompositeView.component(_:as:)`, `CompositeView.viewed(as:)`, `TypedSegment.repetitions(_:)` | additive protocol-extension methods | yes. They could shadow a caller's own extension method with the same signature; that is the standard additive-extension caveat, and none exists in-repo. |
| `<name>All`, later-version and `As<T>` properties on the generated structs | additive member | yes |
| Hand-written view accessors | unchanged names, types and semantics | yes |
| OBX-3 `observationIdentifier: CE?`, OBX-8 `abnormalFlags: String?` | **unchanged** (retyping would be breaking) | n/a |
| Internal `static let componentAccessorNames` | internal | n/a |

No symbol is removed, renamed or retyped. So the release is a 3.x **minor**.

## Decision

**Option B**, confirmed by the owner at gate G3 ("Generate them", 2026-09-30).

## Consequences

- The composite views reach full spec depth for every supported version.
  Completeness is enforced by codegen and by `CompositeComponentTests`.
- Adding a version (P3) or a component (P5) fails codegen until a curator names
  it. That failure is the point.
- **Residual limitation (register section H):**
  - Composite-to-composite retypes surface through `viewed(as:)`, not typed
    properties, unless the element was also renamed (ruling 1).
  - Names used only before v2.5.1 (v2.3 to v2.4 spellings), and same-type later
    renames, are DocC notes on the base accessor, not accessors (ruling 1).
  - Accessors are not gated by the message's version: each DocC names the versions
    it applies to, and on another version's message it reads whatever the position
    holds.
- P9-5 shipped 510 accessors on the segment structs: 231 later or redefined element
  names (9 of them renames whose type differs), 186 `<name>As<T>`, and 93 more
  `<name>All` (629 in all).

## Amendment (P10-3, 2026-10-02): a released struct's union base never changes

**Rule.** Once a segment struct has been released, its base version is fixed for ever. The
base of every generated struct that is not the canonical v2.5.1 is recorded in
`Resources/struct-bases.json` (`segment -> version`), and the codegen
(`structBase(segmentID:schemas:pins:)` in `Sources/HL7v2KitCodegen/StructBase.swift`) takes a
listed segment's base from there. Only an unlisted segment takes the original rule: canonical
v2.5.1, else the earliest definer. A pin to a version that does not define the segment fails
the run.

**Why.** "The earliest definer" is a property of the supported version set, not of the
segment. Adding v2.7.1 (remediation P10, ruling D2) would make v2.7.1 the earliest definer of
IAR, PAC, PRT and SHP, which v3.13.0 released based on v2.8.2. Re-basing them would rename or
retype released accessors wherever the v2.7.1 element name or type differs, a breaking change
ADR-014 forbids in 3.x. The pin is data rather than a comparison of version strings, so adding
any earlier version cannot move a base either; the added version contributes through the
union surface like any other non-base version.

**The list.** 38 bases, derived from the `// Source schema:` headers of the v3.13.0 generated
files and checked against `Tests/Fixtures/APISurface/segment-structs-v3.13.0.txt`: v2.6 for
ADJ, ARV, DMI, ILT, IPR, ITM, IVC, IVT, PCE, PKG, PMT, PSG, PSL, PSS, PYE, REL, RFI, SCD,
SCP, SDD, SLT, STZ, UAC and VND; v2.8.2 for BUI, CDO, DON, DPS, IAR, MCP, OMC, PAC, PM1,
PRT, RXV, SGH, SGT and SHP. The other 150 structs are based on v2.5.1 and need no entry.

**Guards.** `StructBasePinTests` fails when a generated struct's base differs from its pin (or
from v2.5.1 when it has none), when a pin names no generated struct, or when a v3.13.0 struct
is no longer generated. A new segment with a non-v2.5.1 base therefore has its base added to
the list in the commit that introduces it, and from then on it is pinned too.
`scripts/check-struct-base-pin.py` (CI, codegen-drift job) runs the codegen on a scratch copy
of the schemas with a synthetic earlier version defining PRT under a different name and type,
and shows PRT stays on v2.8.2 with every released declaration intact, while an unpinned
segment still takes its earliest definer.

**Outcome (P10, checked in P10-8).** With v2.7.1 added, no generated struct takes v2.7.1 as
its base: the `// Source schema:` headers name v2.5.1 for 150 structs, v2.6 for 24 and v2.8.2
for 14, and `Resources/struct-bases.json` still holds 38 pins. v2.7.1 contributes through the
union surface only. The one accessor change in P10 is unreleased: `ITM.itemNaturalAccountCode`
follows its v2.6 base (ITM-19 printed IS) as `String?`, and the CWE reading of v2.7.1 and
v2.8.2 has the companion `ITM.itemNaturalAccountCodeAsCWE` (P10-4d).

## References

- `planning/reviews/v2.5.1-review.md` V251-C11 / V251-A11.
- `planning/reviews/v2.8.2-review.md` V282-C10 / V282-A09.
- ADR-013 (v2.8.2 first-class; typed structs version-agnostic).
- ADR-014 (API evolution).
- ADR-017 (datatype component grammar).
