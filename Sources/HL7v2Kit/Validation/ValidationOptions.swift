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
    /// on populated composite-typed fields. When a composite is populated
    /// but a component its version's component table prints as `R` is
    /// empty (e.g. PID-3 CX populated without a CX-1 ID number), the
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

    /// Severity of ``IssueCode/requiredComponentMissing`` findings: `.error`
    /// (default) or `.warning`. The finding itself is unchanged; only its
    /// severity, and so ``ValidationReport/isValid``, moves. Use `.warning`
    /// when a feed omits a component the spec prints as required but whose
    /// value carries no information the message lacks — the usual case is
    /// `MSH-9.3`, the message structure, which v2.5+ prints as `R` and which
    /// is derivable from the message code and trigger event through HL7
    /// Table 0354. Half of the specification's own v2.5.1 example messages
    /// omit it. The default stays faithful to the printed table. Not an
    /// init parameter: set it by mutation. M21.
    public var requiredComponentSeverity: IssueSeverity = .error

    /// Severity for ``IssueCode/conformanceConditionMissing``, the "as of
    /// v2.7" conditional-component rules (``ComponentGrammar/conformanceCondition``).
    /// `nil`, the default, leaves them unchecked: the specification's own
    /// v2.7+ example messages violate them in 62 to 100 percent of values.
    /// Set it to report them as advisories. Not an init parameter. M27.
    public var conformanceConditionSeverity: IssueSeverity? = nil

    /// The caller asserts that the message comes from a pathology sender.
    /// ADRM-2021 scopes HL7au:00050.1.5 (OBX-6.3 Units coding system must
    /// be `UCUM` on Results) to "Senders (Pathology only)", a fact the wire
    /// does not carry. `false`, the default, leaves the rule unchecked;
    /// `true` applies it under ``HL7Locale/auLocalisation``. Not an init
    /// parameter. M29.
    public var auPathologySender: Bool = false

    /// The caller asserts that the message's coded elements are intended
    /// for display to a user. ADRM-2021 HL7au:00044.4.3 requires the CE
    /// `<text>` component to be valued "as what is intended for display",
    /// with the carve-out that "in some locations user display is not
    /// intended and the text may be blank"; the locations are not on the
    /// wire. `false`, the default, leaves the rule unchecked; `true` applies
    /// it under ``HL7Locale/auLocalisation``. Not an init parameter. M30.
    public var auDisplayIntended: Bool = false

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
    /// "would HL7v2Kit be happy parsing this round-trip?" answer. The
    /// code-table membership check (`checkCodeTables`) is a content rule,
    /// not a structural one, so this preset turns it off too.
    public static let lenient: ValidationOptions = {
        var options = ValidationOptions(
            zSegmentPolicy: .ignore,
            checkRequiredFields: true,
            checkConditionalFields: false,
            checkComponentGrammar: false,
            checkCardinality: false,
            warnDeprecatedFields: false
        )
        options.checkCodeTables = false
        return options
    }()
}
