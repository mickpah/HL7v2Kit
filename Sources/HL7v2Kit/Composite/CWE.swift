// CWE.swift
// Coded with Exceptions composite (HL7 v2.5.1 §2.A.16).
//
// Value-type view over a Field that exposes named accessors for each
// CWE component. CWE is a v2.5+ extension of ``CE`` that adds version
// IDs and an original-text component to allow senders to communicate
// free-text codes alongside the primary identifier. v0.3-C2.

/// Coded with Exceptions (CWE) composite.
///
/// Exposed by typed segment accessors that wrap CWE-typed fields —
/// `PID-39` tribal citizenship, `ORC-25` order status modifier, `ORC-26`
/// advanced beneficiary notice override reason, `ORC-28` confidentiality
/// code, `ORC-29` order type, `ORC-31` parent universal service
/// identifier.
///
/// Reads from the **first repetition** of the underlying field; for
/// multi-repetition fields (e.g. PID-39 tribal citizenship can carry
/// multiple) use ``CWE/field`` to walk the rest, or wrap an individual
/// ``Repetition`` via ``CWE/init(repetition:)``.
///
/// CWE component layout (HL7 v2.5.1):
/// 1. Identifier (ID) → ``CWE/identifier``.
/// 2. Text (ST) → ``CWE/text``.
/// 3. Name of Coding System (ID) → ``CWE/nameOfCodingSystem``.
/// 4. Alternate Identifier (ID) → ``CWE/altIdentifier``.
/// 5. Alternate Text (ST) → ``CWE/altText``.
/// 6. Name of Alternate Coding System (ID) → ``CWE/nameOfAltCodingSystem``.
/// 7. Coding System Version ID (ST) → ``CWE/codingSystemVersionID``.
/// 8. Alternate Coding System Version ID (ST) → ``CWE/altCodingSystemVersionID``.
/// 9. Original Text (ST) → ``CWE/originalText``. The free-text form the
///    sender saw before mapping to CWE-1; useful when CWE-1 can't be
///    resolved.
///
/// **Required components.** The v2.5.1 spec says "at least one of CWE-1
/// or CWE-9 must be populated". For v0.3 the ``Validator`` only enforces
/// **CWE-1**; the OR-rule with CWE-9 is documented but not implemented
/// because the conditional-field DSL doesn't yet support disjunctive
/// component conditions. Senders that populate CWE-9 alone will trip
/// the CWE-1 check today — flag as known divergence.
public struct CWE: CompositeView {
    /// OR-rule conformance per HL7 v2.5.1 §2.A.16: a populated CWE field
    /// must have at least one of CWE-1 (Identifier) OR CWE-9 (Original
    /// Text) populated. v0.4-S4 supersedes the earlier v0.3-C2 flat
    /// `requiredComponents = [CWE-1]` which false-positive'd on
    /// legitimate CWE-9-only payloads.
    public static let requiredComponentSet: RequiredComponentSet? = RequiredComponentSet(
        components: [
            RequiredComponent(index: 1, name: "Identifier"),
            RequiredComponent(index: 9, name: "Original Text"),
        ],
        semantics: .atLeastOneOf,
        description: "CWE-1 (Identifier) OR CWE-9 (Original Text)"
    )

    /// The underlying ``Field``. Use this when you need access to
    /// repetitions beyond the first.
    public let field: Field

    /// Wrap an entire ``Field``. Accessors read from `.first` repetition.
    public init(field: Field) {
        self.field = field
    }

    /// CWE-1 identifier.
    public var identifier: String? {
        componentValue(1)
    }

    /// CWE-2 text.
    public var text: String? {
        componentValue(2)
    }

    /// CWE-3 name of coding system.
    public var nameOfCodingSystem: String? {
        componentValue(3)
    }

    /// CWE-4 alternate identifier.
    public var altIdentifier: String? {
        componentValue(4)
    }

    /// CWE-5 alternate text.
    public var altText: String? {
        componentValue(5)
    }

    /// CWE-6 name of alternate coding system.
    public var nameOfAltCodingSystem: String? {
        componentValue(6)
    }

    /// CWE-7 coding system version ID.
    public var codingSystemVersionID: String? {
        componentValue(7)
    }

    /// CWE-8 alternate coding system version ID.
    public var altCodingSystemVersionID: String? {
        componentValue(8)
    }

    /// CWE-9 original text — the free-text form the sender saw before
    /// mapping to CWE-1.
    public var originalText: String? {
        componentValue(9)
    }
}
