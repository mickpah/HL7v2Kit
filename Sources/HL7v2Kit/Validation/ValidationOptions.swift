// ValidationOptions.swift
// Knobs for `Validator`. Defaults match the AU integration use case:
// grammar checks on, Z-segments tolerated silently.

import Foundation

/// What the validator should do when it encounters a Z-segment (or any
/// segment outside the loaded grammar).
public enum ZSegmentPolicy: Sendable, Equatable, Hashable {
    /// Pass silently. No issue is recorded.
    case ignore
    /// Emit an `.info` issue per Z-segment. Useful for AU compliance audits.
    case warnPresence
    /// Emit an `.error` issue per Z-segment. Equivalent to "this grammar
    /// must be complete" — usually too strict for AU clinical traffic.
    case reject
}

/// Tunable validator behaviour.
public struct ValidationOptions: Sendable {
    /// What to do when a segment isn't in the loaded grammar.
    public var zSegmentPolicy: ZSegmentPolicy

    /// If true (default), check that fields with optionality `R` are populated.
    public var checkRequiredFields: Bool

    /// If true (default), evaluate the predicate on `.conditional` fields
    /// and emit `.conditionalFieldMissing` when the predicate is satisfied
    /// but the field is empty. Conditional fields with no predicate fall
    /// through as effectively `.optional`. v0.2-V1.
    public var checkConditionalFields: Bool

    /// If true (default), check component-level required-component rules
    /// on populated composite-typed fields (XPN / CX / XAD). When a
    /// composite is populated but one of its `requiredComponents` is
    /// empty (e.g. PID-5 XPN populated without an XPN-1 family name), the
    /// validator emits ``IssueCode/requiredComponentMissing``. Other
    /// composites (CE / CWE / EI / XCN / ...) carry no required-component
    /// metadata yet — they're skipped. v0.2-V2.
    public var checkComponentGrammar: Bool

    /// If true (default), check that single-cardinality fields don't carry
    /// multiple repetitions.
    public var checkCardinality: Bool

    /// If true (default), emit a `.warning` when a deprecated (`B`) or
    /// not-supported (`X`) field is populated.
    public var warnDeprecatedFields: Bool

    /// If true (default), check populated `ID`-typed fields against the
    /// closed HL7 table their grammar names (``FieldGrammar/table``) and
    /// emit ``IssueCode/valueNotInTable(table:)`` on a miss. Not an init
    /// parameter: set it by mutation. M6-O6.
    public var checkCodeTables: Bool = true

    public init(
        zSegmentPolicy: ZSegmentPolicy = .ignore,
        checkRequiredFields: Bool = true,
        checkConditionalFields: Bool = true,
        checkComponentGrammar: Bool = true,
        checkCardinality: Bool = true,
        warnDeprecatedFields: Bool = true
    ) {
        self.zSegmentPolicy = zSegmentPolicy
        self.checkRequiredFields = checkRequiredFields
        self.checkConditionalFields = checkConditionalFields
        self.checkComponentGrammar = checkComponentGrammar
        self.checkCardinality = checkCardinality
        self.warnDeprecatedFields = warnDeprecatedFields
    }

    /// Grammar checks on; Z-segments silently tolerated. Suitable for
    /// general AU clinical traffic where Z-segments are routine.
    public static let `default` = ValidationOptions()

    /// All checks on; Z-segments rejected. Useful for sender-side outgoing
    /// message validation where the senders shouldn't be emitting custom
    /// Z-segments.
    public static let strict = ValidationOptions(
        zSegmentPolicy: .reject,
        checkRequiredFields: true,
        checkConditionalFields: true,
        checkComponentGrammar: true,
        checkCardinality: true,
        warnDeprecatedFields: true
    )

    /// Only structural / grammar-required checks. No Z-segment chatter,
    /// no deprecated-field warnings, no conditional-field evaluation, no
    /// component-grammar enforcement. Useful when you just want a yes/no
    /// "would HL7v2Kit be happy parsing this round-trip?" answer.
    public static let lenient = ValidationOptions(
        zSegmentPolicy: .ignore,
        checkRequiredFields: true,
        checkConditionalFields: false,
        checkComponentGrammar: false,
        checkCardinality: false,
        warnDeprecatedFields: false
    )
}
