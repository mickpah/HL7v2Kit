// EI.swift
// Entity Identifier composite (HL7 v2.5.1 §2.A.28).
//
// Value-type view over a Field that exposes named accessors for each
// EI component. Round-trip byte-identity is preserved because the
// struct doesn't own the data — the segment still owns the underlying
// `Field`. v0.3-C3.

/// Entity Identifier (EI) composite.
///
/// Exposed by typed segment accessors that wrap EI-typed fields. EI is
/// the standard "order number" / "message identifier" composite used by
/// MSH-21 (message profile identifier), ORC-2 / ORC-3 / ORC-4 (placer /
/// filler / placer-group order numbers), and OBR-2 / OBR-3 (placer /
/// filler order numbers).
///
/// Reads from the **first repetition** of the underlying field; for
/// multi-repetition fields (e.g. MSH-21) use ``EI/field`` to walk the
/// rest, or wrap an individual ``Repetition`` via ``EI/init(repetition:)``.
///
/// EI component layout (HL7 v2.5.1):
/// 1. Entity Identifier (ST) → ``EI/entityIdentifier``. The unique value
///    within the namespace defined by EI-2 / EI-3.
/// 2. Namespace ID (IS) → ``EI/namespaceID``. The locally-administered
///    namespace this ID lives in (e.g. `"HOSP"`, `"LAB"`).
/// 3. Universal ID (ST) → ``EI/universalID``. A globally-unique ID for
///    the issuing authority (e.g. an ISO OID).
/// 4. Universal ID Type (ID) → ``EI/universalIDType``. The form of EI-3
///    (e.g. `"ISO"`, `"UUID"`, `"DNS"`).
public struct EI: Sendable, Equatable, Hashable {
    /// Required components for the EI composite per HL7 v2.5.1 §2.A.28.
    /// ``Validator`` consults this when the `checkComponentGrammar`
    /// toggle is on: if EI is populated but EI-1 is empty, the
    /// validator emits ``IssueCode/requiredComponentMissing``. v0.2-V2.
    public static let requiredComponents: [RequiredComponent] = [
        RequiredComponent(index: 1, name: "Entity Identifier"),
    ]

    /// The underlying ``Field``. Use this when you need access to
    /// repetitions beyond the first.
    public let field: Field

    /// Wrap an entire ``Field``. Accessors read from `.first` repetition.
    public init(field: Field) {
        self.field = field
    }

    /// Wrap a single ``Repetition``. Convenient when iterating
    /// `field.repetitions` and you want typed access to each identifier
    /// in turn.
    public init(repetition: Repetition) {
        self.field = Field(repetitions: [repetition])
    }

    /// EI-1 entity identifier — the unique value within the namespace.
    public var entityIdentifier: String? {
        componentValue(1)
    }

    /// EI-2 namespace ID — the locally-administered namespace.
    public var namespaceID: String? {
        componentValue(2)
    }

    /// EI-3 universal ID — a globally-unique authority identifier.
    public var universalID: String? {
        componentValue(3)
    }

    /// EI-4 universal ID type — the form of EI-3 (`"ISO"`, `"UUID"`, …).
    public var universalIDType: String? {
        componentValue(4)
    }

    private func componentValue(_ index: Int) -> String? {
        guard let rep = field.repetitions.first,
              rep.components.indices.contains(index - 1) else {
            return nil
        }
        return rep.components[index - 1].subcomponents.first?.value
    }
}
