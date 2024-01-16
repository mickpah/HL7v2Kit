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
    /// missing — e.g. PID-5 (XPN) populated with no XPN-1 family name
    /// renders as `"PID[1]-5.1"`. v0.2-V2.
    public let componentIndex: Int?

    public init(
        segmentID: String,
        segmentIndex: Int,
        fieldIndex: Int? = nil,
        componentIndex: Int? = nil
    ) {
        self.segmentID = segmentID
        self.segmentIndex = segmentIndex
        self.fieldIndex = fieldIndex
        self.componentIndex = componentIndex
    }

    /// Human-readable v2 path (e.g. `"PID[1]-3"`, `"PID[1]-5.1"`, `"ZAU[1]"`).
    public var pathDescription: String {
        var s = "\(segmentID)[\(segmentIndex)]"
        if let fieldIndex { s += "-\(fieldIndex)" }
        if let componentIndex { s += ".\(componentIndex)" }
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
    /// is empty (e.g. PID-5 XPN populated with no XPN-1 family name).
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
