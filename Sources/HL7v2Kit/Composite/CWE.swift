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
/// CWE-10..22 are generated accessors (``CWE/secondAltIdentifier`` through
/// ``CWE/secondAltValueSetVersionID``); see `CWE+Components.swift`.
///
/// CWE-10 through CWE-22 (the second alternate triplet, and the OID and
/// value-set components) are defined in v2.8.2 only. Their generated accessors
/// are not version-gated: they return `nil` when the component is absent and
/// otherwise read whatever it holds on the wire, on a message of any version.
///
/// **Required components.** None: v2.5.1 prints every CWE component as `O`, and its usage
/// notes include an "Uncoded" case with only the text (CWE-2) valued.
public struct CWE: CompositeView {
    /// No either-or rule (M15). The hand-written "CWE-1 OR CWE-9" rejected the spec's own
    /// usage case b) "Uncoded: Text is valued, the identifier has no value", whose example is
    /// `^Wesnerian^SNM3^^^^3.4` (v2.5.1 sec 2.A.13). Every CWE component is printed `O`.
    public static let requiredComponentSet: RequiredComponentSet? = nil

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
