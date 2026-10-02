// ValidationIssue.swift
// One issue emitted by `Validator.validate(_:)`. Issues collect into a
// `ValidationReport`; validation is non-fatal (it returns a report, never
// throws — per ADR-002).

import Foundation

/// Severity of a single validation issue.
public enum IssueSeverity: Sendable, Equatable, Hashable {
    /// Informational — observed but not a grammar violation
    /// (e.g. Z-segment presence under `.warnPresence`).
    case info
    /// Worth flagging but message is still usable
    /// (e.g. deprecated field populated).
    case warning
    /// Grammar violation that makes the message non-conformant
    /// (e.g. required field missing).
    case error
}

/// Where in a message an issue occurred.
public struct IssueLocation: Sendable, Equatable, Hashable {
    /// 3-character segment identifier (`"PID"`, `"ZAU"`, ...).
    public let segmentID: String
    /// 1-based segment occurrence (1 for the first MSH, etc.). Helps
    /// distinguish e.g. `OBX[1]` from `OBX[2]`.
    public let segmentIndex: Int
    /// 1-based v2 field index, or nil for a segment-level issue.
    public let fieldIndex: Int?
    /// 1-based component index within a composite-typed field, or nil for
    /// a field-level issue. Set by ``IssueCode/requiredComponentMissing``
    /// when a composite is populated but a required sub-component is
    /// missing — e.g. PID-3 (CX) populated with no CX-1 ID number
    /// renders as `"PID[1]-3.1"`. v0.2-V2.
    public let componentIndex: Int?
    /// 1-based subcomponent index within a component that is itself a
    /// composite, or nil. Set by ``IssueCode/valueNotInTable(table:)`` when
    /// the offending value is one level further down — `PID[1]-3.4.3` is the
    /// universal ID type (`HD.3`) of the assigning authority in `CX.4`. M11.
    public let subcomponentIndex: Int?

    public init(
        segmentID: String,
        segmentIndex: Int,
        fieldIndex: Int? = nil,
        componentIndex: Int? = nil,
        subcomponentIndex: Int? = nil
    ) {
        self.segmentID = segmentID
        self.segmentIndex = segmentIndex
        self.fieldIndex = fieldIndex
        self.componentIndex = componentIndex
        self.subcomponentIndex = subcomponentIndex
    }

    /// Human-readable v2 path (e.g. `"PID[1]-3"`, `"PID[1]-5.1"`, `"ZAU[1]"`).
    public var pathDescription: String {
        var s = "\(segmentID)[\(segmentIndex)]"
        if let fieldIndex { s += "-\(fieldIndex)" }
        if let componentIndex { s += ".\(componentIndex)" }
        if componentIndex != nil, let subcomponentIndex { s += ".\(subcomponentIndex)" }
        return s
    }
}

/// Categorical reason for an issue.
///
/// - Note: **Open** enum per ADR-014 — may gain cases in a minor release as
///   new validation checks are added (e.g. `.segmentCardinalityBelowMinimum`,
///   v0.11); switch with `@unknown default`.
public enum IssueCode: Sendable, Equatable, Hashable {
    /// A required field (optionality `R`) is missing or empty.
    case requiredFieldMissing
    /// A conditional field's condition is satisfied but the field is missing.
    /// (Reserved — v0.1.0 doesn't evaluate conditions.)
    case conditionalFieldMissing
    /// A composite field is populated but a required component within it
    /// is empty (e.g. PID-3 CX populated with no CX-1 ID number). Required means
    /// printed `R` in the component table of the message's own HL7 version.
    /// Set on issues emitted by the component-grammar check. v0.2-V2.
    case requiredComponentMissing
    /// A deprecated (`B`) or unsupported (`X`) field was populated.
    case fieldNotSupported
    /// A field exceeded its declared cardinality: a `1` field carries more
    /// than one repetition (`.error`), or a bounded field
    /// (``FieldGrammar/maxRepetitions``) carries more than its printed bound
    /// (`.warning`).
    case cardinalityExceeded
    /// A Z-segment (or any segment outside the loaded grammar) is present
    /// and the validator's Z-segment policy is `.warnPresence` or `.reject`.
    case zSegmentPresent
    /// A localisation profile constraint was violated. The associated
    /// `localeRule` identifies the specific profile rule (e.g.
    /// `"au-adrm-2021:PID-3.4 R"`) so consumers can attribute the
    /// failure to the loaded locale. Scaffolded in v0.4-S5-A; fired
    /// once profile overrides ship in S5-B and later. See ADR-007.
    case profileConstraintViolation(localeRule: String)
    /// A component the spec prints as conditional is empty while the condition
    /// its prose states holds (v2.5.1 RPT.6 "required if RPT-5 is populated").
    /// Located at the component; severity follows
    /// ``ValidationOptions/requiredComponentSeverity``. M26.
    case conditionalComponentMissing
    /// A component whose ``ComponentGrammar/conformanceCondition`` holds is
    /// empty. Reported only when
    /// ``ValidationOptions/conformanceConditionSeverity`` is set. M27.
    case conformanceConditionMissing
    /// A group-scope cardinality rule matched fewer segments than its
    /// declared minimum. `segmentID` is the ID being counted (e.g.
    /// `"OBX"` for HL7au:000008 which requires ≥1 AUSPDI display OBX
    /// per OBR/OBX group); `minCount` is the rule's declared minimum;
    /// `actual` is the count observed in the group; `groupScope` is
    /// the scope identifier (`"obrObxGroup"`, etc.). Additive case
    /// introduced in v0.11-S3 (ADR-010 Extension 2). Non-`@frozen`
    /// enum, so this is a minor bump.
    case segmentCardinalityBelowMinimum(segmentID: String, minCount: Int, actual: Int, groupScope: String)
    /// A group-scope cardinality rule matched more segments than its
    /// declared maximum. A `maxCount` of 0 expresses a prohibition —
    /// HL7au:000023 forbids NTE outright, HL7au:000021 forbids an OBX
    /// whose OBX-2 is `TX`. Additive case introduced in M6-A-3; the
    /// enum is open per ADR-014, so this is a minor bump.
    case segmentCardinalityAboveMaximum(segmentID: String, maxCount: Int, actual: Int, groupScope: String)
    /// A field is populated while its `prohibitedWhen` predicate holds
    /// — the inverse of `conditionalFieldMissing`. The spec pattern is
    /// "may only be valued if X is valued" (e.g. v2.8.2 PRT-6/PRT-7),
    /// which is a PROHIBITION, not a requirement: encoding it as a
    /// required-when condition would wrongly demand the field whenever
    /// its subject is present. Additive case introduced in M8-D; the
    /// enum is open per ADR-014, so this is a minor bump.
    case conditionalFieldProhibited
    /// Two field positions that the base spec declares to be the SAME
    /// data element (they share an HL7 ITEM number — e.g. ORC-2 and
    /// OBR-2 are both item 00216, Placer Order Number) carry different
    /// values in the same ORC/OBR group. v2.4 §4.5.1.2: "If both
    /// fields ... are valued, they must contain the same value";
    /// v2.8.2 §4.5.3.2: "This field is identical to ORC-2-Placer Order
    /// Number." Fires only when BOTH sides are populated. Additive
    /// case introduced in M8-B1; the enum is open per ADR-014, so this
    /// is a minor bump.
    case pairedFieldMismatch(item: String)

    /// An `ID`-typed field carries a value that is not in the HL7-defined
    /// table its spec `TBL#` column names, for the message's version.
    /// Fires only for closed tables (``HL7Table/isClosed``): `IS` fields,
    /// user-defined tables, tables the spec opens to local codes, and
    /// tables with no printed rows are never enforced (req #4). The
    /// payload is the four-digit table number. Additive case introduced
    /// in M6-O6; the enum is open per ADR-014, so this is a minor bump.
    case valueNotInTable(table: String)

    /// A segment whose ID does not begin with `Z` has no entry in the
    /// grammar of the version being applied, so none of its fields was
    /// validated. Raised as a warning under every `zSegmentPolicy`: the
    /// Z-segment policy governs site-defined `Z` segments only (ADR-003,
    /// ADR-018). Additive case; the enum is open per ADR-014.
    case segmentNotInVersionGrammar

    /// The message declares `declared` in MSH-12, which HL7v2Kit validates
    /// against the grammar of `validatedAs` (``Version/grammarVersion``).
    /// Info severity: the differences between the two releases are not
    /// verified, so a finding may reflect `validatedAs` only (ADR-018).
    /// Additive case; the enum is open per ADR-014.
    case versionGrammarSubstituted(declared: Version, validatedAs: Version)

    /// MSH-12 is populated but no ``Version`` case resolves from its version
    /// ID (VID.1): an unmodelled version, or a VID.1 that is empty,
    /// whitespace only or subdivided. The message was validated against a
    /// fallback grammar (v2.5.1, or the caller's
    /// `ParserOptions.versionOverride`), named in the message. Warning
    /// severity: the findings may not reflect the declared release. The
    /// payload is VID.1 as rendered, trimmed, with subcomponents joined by
    /// the message's subcomponent separator; it is empty when VID.1 is
    /// empty. An empty MSH-12 is not reported here: MSH-12 is required, so
    /// the required-field check reports it. Excluded versions are listed in the
    /// permanent-limitations register, section F (ADR-018). Additive case;
    /// the enum is open per ADR-014.
    case versionNotRecognised(wireValue: String)

    /// A populated field repetition's length falls outside the LEN that its
    /// version's attribute table prints. `length` is the printed cell (`"20"`,
    /// `"1..4"`); `actual` is the measured length of that repetition, with
    /// component and subcomponent separators counted and the repetition
    /// separator not. An escape sequence counts the characters between its
    /// escape delimiters (`\F\` is 1, `\.br\` is 3; v2.8.2 section 2.7). Pre-v2.7 maximum lengths follow
    /// ``ValidationOptions/fieldLengthSeverity``; v2.7+ normative lengths on
    /// primitive fields follow ``ValidationOptions/normativeLengthSeverity``.
    /// Additive case introduced in P6-6; the enum is open per ADR-014.
    case fieldLengthOutOfRange(length: String, actual: Int)

    /// A primitive-typed field repetition carries content after its value (any
    /// primitive since P6-14, ID and IS before), or a primitive component of a
    /// composite carries a subcomponent after its value: an unescaped component or
    /// subcomponent separator inside a primitive value. The primitives are each
    /// version's (see the Validation article); TS on v2.3 to v2.4 admits its
    /// degree-of-precision component, FT its line-marking component separators,
    /// and OBX-3.1 an observation ID suffix subcomponent. The component separator "separates
    /// adjacent components of data fields where allowed" (v2.5.1 and v2.8.2
    /// section 2.5.4), a sender escapes it in data as `\S\` (section 2.7.1), and
    /// a recipient ignores components "present but ... not expected" (section
    /// 2.6.2 a). So the primitive value is the first component, and that is what
    /// the code-table and length checks read. Located at the field, or at the
    /// component for a component's subcomponents; severity
    /// follows ``ValidationOptions/extraComponentsSeverity``. Additive case
    /// introduced in P6-13; the enum is open per ADR-014.
    case extraComponentsInPrimitiveField

    /// A composite-typed field repetition carries a populated component beyond
    /// the components its datatype's component table defines on the message's
    /// version, or a composite component of a composite carries a populated
    /// subcomponent beyond the components of its own datatype. The component
    /// separator "separates adjacent components of data fields where allowed"
    /// (v2.5.1 and v2.8.2 section 2.5.4), and a recipient ignores components and
    /// subcomponents "that are present but were not expected" (section 2.6.2 a).
    /// A warning by default, not an error: "New components may be added at the
    /// end of a data type" (v2.5.1 section 2.8.1, v2.8.2 section 2.8.1 h), and
    /// "Data types may be locally extended by adding new components at the end"
    /// (section 2.11.5 c), so a value shaped by a later version or a local Z data
    /// type may carry them. Trailing empty components and escaped separators are
    /// never reported. Not checked: a datatype the version gives no component
    /// table (CM on v2.3 to v2.4, `varies` with no OBX-2), and the open-ended
    /// arrays NA (its tables end in an ellipsis) and MA (its prose: "channels
    /// within a sample are separated by component delimiters"; the v2.6 and
    /// v2.8.2 tables end in an ellipsis). Located at
    /// the field, or at the component for a component's subcomponents; severity
    /// follows ``ValidationOptions/extraComponentsSeverity``. Additive case
    /// introduced in P6-15; the enum is open per ADR-014.
    case extraComponentsInCompositeField

    /// A populated primitive value does not match the format its datatype
    /// section prints: NM, SI, DT, TM, DTM, and TS (v2.5.1 §2.A.21, 2.A.22,
    /// 2.A.47, 2.A.69, 2.A.75; v2.8.2 §2A; v2.3 to v2.4 section 2.8 / 2.9). On a
    /// composite, the components (and one level of subcomponents) whose grammar
    /// datatype has a rule are checked; a primitive field is read as its first
    /// value. `dataType` names the rule applied. Located at the field, or at the
    /// component and subcomponent checked. Severity follows
    /// ``ValidationOptions/valueFormatSeverity``. Additive case introduced in
    /// P6-7; the enum is open per ADR-014.
    case valueFormatInvalid(dataType: String)

    /// A segment the message's structure requires is absent: a required
    /// segment, or the head segment of a required group (`group` names the
    /// group; nil at the top level). Located at the segment it was expected
    /// before, or at the last segment when expected at the end. Severity
    /// follows ``ValidationOptions/messageStructureSeverity`` (off by
    /// default). ADR-019; additive case introduced in P8-5 per ADR-014.
    case messageStructureSegmentMissing(structure: String, segmentID: String, group: String?)
    /// A segment has no place in the message's structure at that point: out
    /// of order, an extra repetition of a non-repeating segment or group, or
    /// a non-Z segment the structure does not contain. Z-segments, ADD
    /// continuations and segments the version grammar does not define are
    /// never reported here. Located at the segment. ADR-019; additive case
    /// introduced in P8-5.
    case messageStructureSegmentUnexpected(structure: String, segmentID: String)
    /// MSH-9.3 names a structure whose caption lines do not print
    /// MSH-9.1^9.2 (`trigger`, as `CODE^EVENT`). The mismatch is reported
    /// alone: the body is not matched against either structure. Located at
    /// MSH-9.3. ADR-019; additive case introduced in P8-5.
    case messageStructureMismatch(declared: String, trigger: String)
    /// No abstract message syntax was applied to this message, so segment
    /// order and groups were not checked: the structure (`structure`, the
    /// MSH-9.3 value or `CODE^EVENT`) is not modelled for the version, the
    /// version is not resolved from MSH-12, the message is a fragment
    /// (MSH-14 populated, a trailing DSC with DSC-1 populated, or a trailing
    /// DSC the structure does not define), or the structure fails the
    /// determinism lint; an empty MSH-9 gives an empty `structure`. Always
    /// `.info`; emitted only
    /// when ``ValidationOptions/messageStructureSeverity`` is set. Located at
    /// MSH-9. ADR-019; additive case introduced in P8-5.
    case messageStructureNotModelled(structure: String)
}

/// One observation from validation. Always non-fatal: collected into a
/// `ValidationReport`, never thrown.
public struct ValidationIssue: Sendable, Equatable, Hashable {
    public let severity: IssueSeverity
    public let code: IssueCode
    public let location: IssueLocation
    public let message: String

    public init(
        severity: IssueSeverity,
        code: IssueCode,
        location: IssueLocation,
        message: String
    ) {
        self.severity = severity
        self.code = code
        self.location = location
        self.message = message
    }
}
