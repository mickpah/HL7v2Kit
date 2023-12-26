// XCN.swift
// Extended Composite ID Number and Name for Persons (HL7 v2.5.1 §2.A.85).
//
// Value-type view over a Field that exposes named accessors for the
// six commonly-populated XCN components. The full XCN composite has
// 23 components; per the v0.3-C3 plan only the first six (ID + name
// parts) are exposed via named accessors. Callers needing any of XCN-7
// through XCN-23 can drill in via ``XCN/field``. Round-trip byte-identity
// is preserved because the struct doesn't own the data — the segment
// still owns the underlying `Field`. v0.3-C3.

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
/// XCN component layout (HL7 v2.5.1; first six exposed via named
/// accessors):
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
/// XCN-7 through XCN-23 (degree, source table, assigning authority,
/// name type code, identifier check digit, check digit scheme, identifier
/// type code, assigning facility, name representation code, name
/// context, name validity range, name assembly order, effective date,
/// expiration date, professional suffix, assigning jurisdiction, assigning
/// agency or department) remain accessible via ``XCN/field``.
public struct XCN: Sendable, Equatable, Hashable {
    /// Required components for the XCN composite per HL7 v2.5.1 §2.A.85.
    /// ``Validator`` consults this when the `checkComponentGrammar`
    /// toggle is on: if XCN is populated but XCN-1 is empty, the
    /// validator emits ``IssueCode/requiredComponentMissing``. v0.2-V2.
    public static let requiredComponents: [RequiredComponent] = [
        RequiredComponent(index: 1, name: "ID Number"),
    ]

    /// The underlying ``Field``. Use this when you need access to
    /// repetitions beyond the first, or to XCN components beyond
    /// XCN-6 (degree, source table, assigning authority, etc.).
    public let field: Field

    /// Wrap an entire ``Field``. Accessors read from `.first` repetition.
    public init(field: Field) {
        self.field = field
    }

    /// Wrap a single ``Repetition``. Convenient when iterating
    /// `field.repetitions` and you want typed access to each provider
    /// in turn.
    public init(repetition: Repetition) {
        self.field = Field(repetitions: [repetition])
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

    private func componentValue(_ index: Int) -> String? {
        guard let rep = field.repetitions.first,
              rep.components.indices.contains(index - 1) else {
            return nil
        }
        return rep.components[index - 1].subcomponents.first?.value
    }
}
