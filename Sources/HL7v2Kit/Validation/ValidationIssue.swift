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
    /// A field exceeded its declared cardinality (`1` but multiple
    /// repetitions populated).
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
