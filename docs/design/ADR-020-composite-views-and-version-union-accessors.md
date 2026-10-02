# ADR-020 — Composite views to full spec depth, and version-union typed accessors

**Status:** Accepted 2026-10-02 -- Option B (owner, gate G3, answered "Generate them" on
2026-09-30; remediation plan P9).

**Context:** Two review findings share one cause. The typed API was shaped by
"what common traffic populates" and by a single canonical version.

- **V251-C11.** The composite views expose only part of v2.5.1: CX 6 of 10
  components, XPN 6 of 14, XAD 7 of 14, XCN 6 of 23, XTN 8 of 12 and PL 4 of 11.
  The XCN header justifies this with "the six commonly-populated components", a
  consumer-profile argument that the working notes requirement 1 rejects. Typed accessors
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
  later-version name for an existing index is a new accessor, never a rename.
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
2. **Repeating fields.** Every `*` field gains `<name>All: [T]` (`[String?]` for
   scalars, `[Field]` for raw fields), built on a new public
   `TypedSegment.repetitions(_:)`. The singular accessor's DocC says the field
   repeats.
3. **Version union.** Each segment struct renders from its base schema (canonical
   v2.5.1, or else the earliest definer, as today) and then adds what later versions
   contribute:
   - fields past the base maximum, under their own names and types;
   - a later name for an existing index, typed as that version prints it;
   - `<name>As<T>` where the later type is a composite view but the base type is
     scalar or raw.

   A composite-to-composite retype (CE to CWE) gets a DocC note that points at
   `viewed(as:)`, not a new symbol. A name clash stops codegen, so a curator must
   fix it. The union is computed from the schemas alone.
- **Cost:** about 1,100 new generated accessors across the segment structs, plus
  about 115 composite accessors. There are 3 new public methods. The generated
  files get larger; compile time must be measured in P9-5.
- **Per-version availability:** the accessors read the wire whatever version it
  declares, so an absent field or component returns `nil`. This is the existing
  Optional contract. Version facts live in DocC ("Defined from v2.8.2"), and the
  machine-readable form stays in `DataTypeGrammarTable` and `SegmentGrammar`.

### Option C — Record the gap as a limitation only
Add a register row and DocC, and change no code.
- **Verdict:** rejected as the end state, under the working notes requirement 3: the model
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
    properties.
  - Names used only before v2.5.1 (v2.3 to v2.4 spellings) are not surfaced; the
    index-based accessor still reads them.
  - Accessors are not gated by the message's version.

## References

- `planning/reviews/v2.5.1-review.md` V251-C11 / V251-A11.
- `planning/reviews/v2.8.2-review.md` V282-C10 / V282-A09.
- ADR-013 (v2.8.2 first-class; typed structs version-agnostic).
- ADR-014 (API evolution).
- ADR-017 (datatype component grammar).
