// XCN.swift
// Extended Composite ID Number and Name for Persons (HL7 v2.5.1 §2.A.85).
//
// Value-type view over a Field. XCN-1..6 are hand-written below; XCN-7..25
// are generated into Composite/Generated/XCN+Components.swift from the
// datatype component tables (ADR-020). The struct does not own the data,
// so round-trip byte-identity is preserved.

/// Extended Composite ID Number and Name for Persons (XCN) composite.
///
/// Exposed by typed segment accessors that wrap XCN-typed fields. XCN
/// is the standard "person with ID" composite used by ORC-10 (entered
/// by), ORC-11 (verified by), ORC-12 (ordering provider), ORC-19
/// (action by), OBR-10 (collector identifier), OBR-16 (ordering
/// provider), OBR-28 (result copies to), OBX-16 (responsible observer),
/// and the PV1 doctor fields (attending / referring / consulting /
/// admitting).
///
/// Reads from the **first repetition** of the underlying field; for
/// multi-repetition fields (e.g. ORC-12 ordering provider, PV1-9
/// consulting doctor) use ``XCN/field`` to walk the rest, or wrap an
/// individual ``Repetition`` via ``XCN/init(repetition:)``.
///
/// XCN component layout (hand-written accessors; XCN-7..25 are generated):
/// 1. ID Number (ST) → ``XCN/idNumber``. Provider / staff identifier
///    (e.g. `"DR123"`).
/// 2. Family Name (FN) → ``XCN/familyName``.
/// 3. Given Name (ST) → ``XCN/givenName``.
/// 4. Second and Further Given Names or Initials Thereof (ST) →
///    ``XCN/middleName``.
/// 5. Suffix (ST) → ``XCN/suffix`` (e.g. `"Jr"`, `"III"`).
/// 6. Prefix (ST) → ``XCN/prefix_`` (e.g. `"Dr"`). Backticked because
///    `prefix` collides with `Sequence.prefix(_:)` on call sites that
///    chain off a string view.
///
/// XCN-7 through XCN-25 are generated accessors (``XCN/degree`` through
/// ``XCN/securityCheckScheme``); see `XCN+Components.swift`.
public struct XCN: CompositeView {
    /// The components HL7 v2.5.1 PRINTS as required (`R`) in the XCN component
    /// table (none: every XCN component is optional there). Informational, for the canonical
    /// version only: the ``Validator`` does not read this list. It takes required
    /// components from ``DataTypeGrammarTable`` for the MESSAGE's own version, because
    /// they differ between versions (M14, ADR-017).
    public static let requiredComponents: [RequiredComponent] = []

    /// The underlying ``Field``. Use this when you need access to
    /// repetitions beyond the first. Every component has a named accessor;
    /// use ``component(_:as:)`` for a sub-composite's subcomponents.
    public let field: Field

    /// Wrap an entire ``Field``. Accessors read from `.first` repetition.
    public init(field: Field) {
        self.field = field
    }

    /// XCN-1 ID Number — the provider / staff identifier.
    public var idNumber: String? {
        componentValue(1)
    }

    /// XCN-2 family name.
    public var familyName: String? {
        componentValue(2)
    }

    /// XCN-3 given name.
    public var givenName: String? {
        componentValue(3)
    }

    /// XCN-4 middle name (or initials).
    public var middleName: String? {
        componentValue(4)
    }

    /// XCN-5 suffix (e.g. `"Jr"`, `"III"`).
    public var suffix: String? {
        componentValue(5)
    }

    /// XCN-6 prefix (e.g. `"Dr"`).
    public var prefix_: String? {
        componentValue(6)
    }
}
