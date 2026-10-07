// ValidationOptions.swift
// Knobs for `Validator`. Defaults match the AU integration use case:
// grammar checks on, Z-segments tolerated silently.

import Foundation

/// What the validator should do when it encounters a Z-segment: a segment
/// whose ID begins with `Z` and has no entry in the loaded grammar. Any
/// other ID outside the loaded grammar is not a Z-segment (ADR-018) and is
/// unaffected by this policy — it always produces
/// ``IssueCode/segmentNotInVersionGrammar``.
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
    /// What to do when a `Z`-prefixed segment isn't in the loaded grammar.
    /// A non-Z segment ID outside the loaded grammar always produces
    /// ``IssueCode/segmentNotInVersionGrammar`` instead, whatever this is
    /// set to (ADR-018).
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
    /// multiple repetitions. On v2.3 and v2.3.1 a single-repeat `TQ` field's
    /// repetitions 2 to n are read as its TQ.6 Priority repeat (section 4.4.6,
    /// "Priority component"), not reported, and not otherwise checked; v2.4
    /// (section 4.3.6) separates repeated priorities with a space instead.
    public var checkCardinality: Bool

    /// If true (default), emit a `.warning` when a deprecated (`B`),
    /// not-supported (`X`) or withdrawn (`W`) field is populated
    /// (``IssueCode/fieldNotSupported``), and, from v2.5, when a `B` or `W`
    /// component of any other field is populated
    /// (``IssueCode/componentNotSupported(optionality:)``, since v3.15.0).
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

    /// Severity for the abstract-message-syntax check (ADR-019): segment
    /// order, required segments and groups, and repetition for the message's
    /// structure, plus an MSH-9.3 that names a structure its MSH-9.1^9.2 is
    /// not printed under. `.warning` in ``default`` (and for a memberwise
    /// `ValidationOptions()`), `.error` in ``strict`` and `nil`, the check
    /// off, in ``lenient`` (owner decision G2 (b), P8b-18; before P8b-18 it
    /// was `nil` in every preset). Only the structures generated from `Resources/structures/`
    /// are modelled; a message with no structure applied (unmodelled
    /// structure or version, an MSH-12 that does not resolve or differs from
    /// ``Message/version``, a fragment) gets one
    /// ``IssueCode/messageStructureNotModelled(structure:)`` info issue
    /// instead of a silent pass. Receivers ignore unexpected segments
    /// (v2.5.1 CH02 2.6.2), so `.warning` suits receiver-side use and
    /// `.error` sender-side use. Under ``HL7Locale/auLocalisation`` a v2.4
    /// ORU^R01, ORM^O01, REF^I12, RRI^I12 or OSR^Q06 is also matched against the
    /// ADRM-2021 structure: a segment that structure requires and the message
    /// lacks is reported as `profileConstraintViolation(localeRule:
    /// "HL7au:00060.1")` at this severity (P8b-4), and a base structure
    /// finding the ADRM structure accepts at that point is dropped (P8b-4a).
    /// Not an init parameter. P8-5.
    public var messageStructureSeverity: IssueSeverity? = .warning

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

    /// The caller asserts that the message travels by Secure Message
    /// Delivery secured with NASH certificates. ADRM-2021 gates its HD
    /// addressing points on exactly that — HL7au:00044.2.2 (the MSH-4 /
    /// MSH-6 Universal ID must be `"1.2.36.1.2001.1003.0."` followed by
    /// the 16-digit HPI-O, per HL7au:000043.1) and HL7au:00044.2.3 (the
    /// Universal ID Type must be `"ISO"`) — and the transport is not on
    /// the wire. `false`, the default, leaves them unchecked; `true`
    /// applies them under ``HL7Locale/auLocalisation``. Since P12 S2-2 it
    /// also requires the HD Namespace ID (MSH-4.1, MSH-6.1) to be valued,
    /// the presence half of HL7au:000043.1 and 00044.2.1; whether the name
    /// is the one the HPOS/HI service registers, and the points that name
    /// a vendor X.509 certificate, need a directory and stay out of scope.
    /// The checks run on ORM, ORU and REF only, the "Orders, Results,
    /// Referrals" scope the points print (P12 S2-2), whose values Appendix 5
    /// p 416 defines as ORM, ORU and all REF messages. Not an init
    /// parameter. M32.
    public var auNASHTransport: Bool = false

    /// The caller asserts that its PRD-7 assigning authorities come from
    /// User-defined Table 0363 as ADRM-2021 prints it (p. 310), extended by
    /// the secure messaging vendor authorities it lists in
    /// ``localTableExtensions`` under `"0363"`. HL7au:00104.7.2.1 requires
    /// PRD-7 `<type of ID number (IS)>` to be "valued from User-defined Table
    /// 0363", and the ADRM lets the table "be extended to allow for secure
    /// messaging vendor assigning authorities" (p. 334); which vendors a site
    /// has agreed is not on the wire. `false`, the default, leaves the rule
    /// unchecked (the ADRM's own `Medical-Objects` and `Argus` rows lie
    /// outside the printed table); `true` checks PRD-7.2 on Referrals under
    /// ``HL7Locale/auLocalisation``. Not an init parameter. P12 S2-2.
    public var auAssigningAuthorityTable: Bool = false

    /// Severity for ``IssueCode/fieldLengthOutOfRange(length:actual:)`` against a
    /// pre-v2.7 maximum length (v2.3 to v2.6, a plain-integer LEN cell), measured
    /// per repetition with component and subcomponent separators counted (v2.3.1
    /// section 2.6.2). `.warning` by default; `nil` leaves it unchecked. The spec
    /// lets a site agreement change the length, "such as a conformance profile ...
    /// it shall not render the implementation non-conformant" (v2.5.1 section
    /// 2.5.3.2; v2.3.1 section 2.6.2 "often negotiated on a site-specific basis"),
    /// and the agreement is not on the wire. `*`, `64K` and the v2.4 to v2.6 symbols
    /// 65536 (very large number) and 99999 (variable) are not checked.
    /// Not an init parameter. P6-6.
    public var fieldLengthSeverity: IssueSeverity? = .warning

    /// Severity for ``IssueCode/fieldLengthOutOfRange(length:actual:)`` against a
    /// v2.7+ normative length (`m..n`, `m..`, `x,y,z`) on a primitive-typed field:
    /// "conformant messages SHALL have a length that lies within the boundaries
    /// specified" (v2.8.2 section 2.5.5.0), and for
    /// ``IssueCode/componentLengthOutOfRange(length:actual:)`` against the same
    /// forms printed on a primitive component (section 2.5.5.4; S1-1, v3.15.0).
    /// `.warning` by default; `nil` turns both off. Conformance lengths (`40=`, `250#`, a bare integer) bound what a
    /// receiver stores, not what a message carries (section 2.5.5.3), and are
    /// never checked. Not an init parameter. P6-6.
    public var normativeLengthSeverity: IssueSeverity? = .warning

    /// Severity for ``IssueCode/extraComponentsInPrimitiveField``: a primitive
    /// field repetition with content after its value, or a primitive component
    /// with a subcomponent after its value (every primitive since P6-14).
    /// `.warning` by default (owner gate G4): the spec has the recipient ignore
    /// the unexpected components (v2.5.1 and v2.8.2 section 2.6.2 a), and a field
    /// whose data type a later version widened (an `IS` to a `CE`, v2.5.1 section
    /// 2.8.2) may legitimately arrive with them. Whatever the setting, the
    /// code-table check reads the first component as the primitive value. While
    /// this is at least as severe as the length severity that applies
    /// (``normativeLengthSeverity`` for a v2.7+ normative length,
    /// ``fieldLengthSeverity`` otherwise; error > warning > info), the length
    /// check measures that first component only, so the extra components are
    /// reported once, here. Below it, or `nil` (this check off), the length check
    /// measures the whole occurrence, so a binding length rule is never hidden.
    /// Also the severity for ``IssueCode/extraComponentsInCompositeField``: a
    /// composite field or component carrying more components than its
    /// datatype's table defines (P6-15); the length check is not affected there.
    /// Not an init parameter. P6-13, widened to every primitive in P6-14.
    public var extraComponentsSeverity: IssueSeverity? = .warning

    /// Severity for ``IssueCode/valueFormatInvalid(dataType:)``: a populated NM,
    /// SI, DT, TM, DTM or TS value that does not match the format its datatype
    /// section prints ("no non-numeric ASCII characters are allowed", v2.5.1
    /// §2.A.47). `.warning` by default (owner gate G4), as are the length checks;
    /// set `.error` to make a malformed value fail validation, or `nil` to turn
    /// the check off. Not an init parameter. P6-7.
    public var valueFormatSeverity: IssueSeverity? = .warning

    /// Severity for the ``IssueCode/cardinalityExceeded`` bound check: a `.multiple`
    /// field carrying more `~`-repetitions than its printed RP/# bound
    /// (``FieldGrammar/maxRepetitions``). `.warning` by default (owner gate G4): the
    /// bound is a new check, so it does not fail validation by default. Set `.error`
    /// to make an over-bound field fail validation, or `nil` to turn the bound check
    /// off. The single-cardinality check (a `.single` field carrying more than one
    /// repetition) is unaffected — it stays an `.error` gated by `checkCardinality`,
    /// never by this property. Not an init parameter. P6-4.
    public var repetitionBoundSeverity: IssueSeverity? = .warning

    /// Codes the caller has added locally to HL7 tables, keyed by four-digit table number.
    ///
    /// Every supported version allows an HL7 table to be extended locally: v2.3 and v2.3.1
    /// CH2 sec 2.6.6 ("Additions may be included on a site-specific basis"), v2.4 CH02
    /// sec 2.7.6, v2.5.1 and v2.6 CH02 sec 2.5.3.6 ("the table itself may be extended to
    /// accommodate locally defined values") and v2.8.2 CH02C 2.C.1.2. A value listed here
    /// for a table is accepted wherever the base-spec code-table check reads that table,
    /// at field or component level; every other value outside the table is still reported.
    /// AU profile value-set rules are not affected: a value a profile rule rejects is
    /// still rejected. The exceptions are the AU profile's Table 0203 value sets (CX-5,
    /// XCN-13, PRD-7.3), which accept the values listed under `"0203"` (P12 S2-3), and
    /// `"0363"` under ``auAssigningAuthorityTable``, whose listed codes are the caller's
    /// secure messaging vendor authorities (P12 S2-2).
    /// Empty by default, so HL7 tables stay closed.
    ///
    /// Keys are four-digit table numbers (`"0074"`), matched against the table number the
    /// field or component is bound to; any other key (`"74"`, `"HL70074"`) is ignored.
    /// Matching of values is exact and case-sensitive, as ``HL7Table/contains(_:)`` is.
    /// Not an init parameter. P2-13.
    public var localTableExtensions: [String: Set<String>] = [:]

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
    /// Message-structure findings are warnings (receiver-side use, v2.5.1
    /// CH02 2.6.2; owner decision G2 (b), P8b-18).
    public static let `default` = ValidationOptions()

    /// All checks on; Z-segments rejected. Useful for sender-side outgoing
    /// message validation where the senders shouldn't be emitting custom
    /// Z-segments. The length severities (`fieldLengthSeverity`,
    /// `normativeLengthSeverity`), `valueFormatSeverity` and
    /// `repetitionBoundSeverity` stay `.warning` here as in `default` (owner gate G4).
    /// Message-structure findings (`messageStructureSeverity`) are `.error`
    /// here, sender-side conformance (owner decision G2 (b), P8b-18).
    public static let strict: ValidationOptions = {
        var options = ValidationOptions(
            zSegmentPolicy: .reject,
            checkRequiredFields: true,
            checkConditionalFields: true,
            checkComponentGrammar: true,
            checkCardinality: true,
            warnDeprecatedFields: true
        )
        options.messageStructureSeverity = .error
        return options
    }()

    /// Only structural / grammar-required checks. No Z-segment chatter,
    /// no deprecated-field warnings, no conditional-field evaluation, no
    /// component-grammar enforcement. Useful when you just want a yes/no
    /// "would HL7v2Kit be happy parsing this round-trip?" answer. The
    /// code-table membership check (`checkCodeTables`) is a content rule,
    /// not a structural one, so this preset turns it off too, as it does the
    /// field length checks (`fieldLengthSeverity`, `normativeLengthSeverity`),
    /// the extra-component check (`extraComponentsSeverity`), the value-format
    /// check (`valueFormatSeverity`) and the repetition-bound check
    /// (`repetitionBoundSeverity`), and it sets `messageStructureSeverity`
    /// to `nil` explicitly (`.warning` in `default`, `.error` in `strict`). `checkCardinality`
    /// is already `false` here, which also silences the single-cardinality
    /// error.
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
        options.fieldLengthSeverity = nil
        options.normativeLengthSeverity = nil
        options.extraComponentsSeverity = nil
        options.valueFormatSeverity = nil
        options.repetitionBoundSeverity = nil
        options.messageStructureSeverity = nil
        return options
    }()
}
