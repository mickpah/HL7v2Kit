// XON.swift
// Extended Composite Name and Identification Number for Organizations
// composite (HL7 v2.5.1 §2.A.86).
//
// Value-type view over a Field. XON-1, 2, 7 and 10 hand-written; the rest
// generated (ADR-020). v0.3-C4.

/// Extended Composite Name and Identification Number for Organizations
/// (XON) composite.
///
/// Exposed by typed segment accessors that wrap XON-typed fields. XON
/// is the standard "organization with ID" composite used by NK1-13
/// (organization name — next of kin) and ORC-21 (ordering facility
/// name).
///
/// XON component layout (hand-written accessors; the rest are generated):
/// 1. Organization Name (ST) → ``XON/organizationName``. The
///    organization's display name.
/// 2. Organization Name Type Code (IS) → ``XON/organizationNameTypeCode``.
///    Type of the name (e.g. `"L"` legal, `"A"` alias).
/// 7. Identifier Type Code (IS) → ``XON/identifierTypeCode``. The
///    schema XON-10 conforms to (e.g. `"NPI"`, `"FI"`).
/// 10. Organization Identifier (ST) → ``XON/organizationIdentifier``.
///     The unique identifier value.
///
/// XON-3..6, 8 and 9 are generated accessors; see `XON+Components.swift`.
public struct XON: CompositeView {
    /// The components HL7 v2.5.1 PRINTS as required (`R`) in the XON component
    /// table (none: every XON component is optional there). Informational, for the canonical
    /// version only: the ``Validator`` does not read this list. It takes required
    /// components from ``DataTypeGrammarTable`` for the MESSAGE's own version, because
    /// they differ between versions (M14, ADR-017).
    public static let requiredComponents: [RequiredComponent] = []

    /// The underlying ``Field``.
    public let field: Field

    /// Wrap an entire ``Field``.
    public init(field: Field) {
        self.field = field
    }

    /// XON-1 organization name.
    public var organizationName: String? {
        componentValue(1)
    }

    /// XON-2 organization name type code (`"L"` legal, `"A"` alias, …).
    public var organizationNameTypeCode: String? {
        componentValue(2)
    }

    /// XON-7 identifier type code (`"NPI"`, `"FI"`, …).
    public var identifierTypeCode: String? {
        componentValue(7)
    }

    /// XON-10 organization identifier — the unique ID value.
    public var organizationIdentifier: String? {
        componentValue(10)
    }
}
