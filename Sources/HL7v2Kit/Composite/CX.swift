// CX.swift
// Extended Composite ID with Check Digit (HL7 v2.5.1 §2.A.14).
//
// Value-type view over a Field that exposes named accessors for the most
// common CX components. Round-trip byte-identity is preserved because the
// struct doesn't own the data — the segment still owns the underlying
// `Field`. v0.2-C1.

/// Extended Composite ID with Check Digit (CX) composite.
///
/// Exposed by typed segment accessors that wrap CX-typed fields (e.g.
/// ``PID/patientIdentifierList``, ``PID/patientAccountNumber``,
/// ``PV1/visitNumber``). Reads from the **first repetition** of the
/// underlying field; for multi-repetition fields like PID-3 (where a
/// patient can carry MRN + URN + Medicare etc.) use ``CX/field`` to walk
/// the rest, or wrap an individual ``Repetition`` via ``CX/init(repetition:)``.
///
/// CX component layout (HL7 v2.5.1):
/// 1. ID Number (ST) → ``CX/id``.
/// 2. Check Digit (ST) → ``CX/checkDigit``.
/// 3. Check Digit Scheme (ID) → ``CX/checkDigitScheme``.
/// 4. Assigning Authority (HD) — sub-composite; ``CX/assigningAuthorityNamespace``
///    returns its first subcomponent (HD.1 namespace ID).
/// 5. Identifier Type Code (ID) → ``CX/identifierTypeCode``
///    (e.g. `"MR"` medical record, `"SSN"` social security).
/// 6. Assigning Facility (HD) — ``CX/assigningFacilityNamespace`` returns HD.1.
///
/// Components 7–10 (effective/expiration dates, assigning jurisdiction
/// and agency) are reachable via ``CX/field`` but not exposed as named
/// accessors in v0.2.
public struct CX: CompositeView {
    /// The components HL7 v2.5.1 PRINTS as required (`R`) in the CX component
    /// table (CX.1). Informational, for the canonical
    /// version only: the ``Validator`` does not read this list. It takes required
    /// components from ``DataTypeGrammarTable`` for the MESSAGE's own version, because
    /// they differ between versions (M14, ADR-017).
    public static let requiredComponents: [RequiredComponent] = [
        RequiredComponent(index: 1, name: "ID Number"),
    ]

    /// The underlying ``Field``. Use this when you need access to
    /// repetitions beyond the first, or to components not exposed as
    /// named accessors.
    public let field: Field

    /// Wrap an entire ``Field``. Accessors read from `.first` repetition.
    public init(field: Field) {
        self.field = field
    }

    /// CX-1 ID number.
    public var id: String? {
        componentValue(1)
    }

    /// CX-2 check digit.
    public var checkDigit: String? {
        componentValue(2)
    }

    /// CX-3 check digit scheme.
    public var checkDigitScheme: String? {
        componentValue(3)
    }

    /// CX-4.1 — the assigning authority's namespace ID (first subcomponent
    /// of the HD sub-composite).
    public var assigningAuthorityNamespace: String? {
        componentValue(4)
    }

    /// CX-5 identifier type code (e.g. `"MR"` medical record, `"SSN"`).
    public var identifierTypeCode: String? {
        componentValue(5)
    }

    /// CX-6.1 — the assigning facility's namespace ID (first subcomponent
    /// of the HD sub-composite).
    public var assigningFacilityNamespace: String? {
        componentValue(6)
    }
}
