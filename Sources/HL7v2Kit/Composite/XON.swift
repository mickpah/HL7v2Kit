// XON.swift
// Extended Composite Name and Identification Number for Organizations
// composite (HL7 v2.5.1 §2.A.86).
//
// Value-type view over a Field that exposes named accessors for the
// four most-commonly-populated XON components. XON has 10 spec
// components; the v0.3-C4 cut promotes XON-1 / 2 / 7 / 10 — name plus
// type code plus identifier metadata, the realistic AU traffic
// subset. v0.3-C4.

/// Extended Composite Name and Identification Number for Organizations
/// (XON) composite.
///
/// Exposed by typed segment accessors that wrap XON-typed fields. XON
/// is the standard "organization with ID" composite used by NK1-13
/// (organization name — next of kin) and ORC-21 (ordering facility
/// name).
///
/// XON component layout (HL7 v2.5.1; the commonly-populated subset
/// is exposed via named accessors):
/// 1. Organization Name (ST) → ``XON/organizationName``. The
///    organization's display name.
/// 2. Organization Name Type Code (IS) → ``XON/organizationNameTypeCode``.
///    Type of the name (e.g. `"L"` legal, `"A"` alias).
/// 7. Identifier Type Code (IS) → ``XON/identifierTypeCode``. The
///    schema XON-10 conforms to (e.g. `"NPI"`, `"FI"`).
/// 10. Organization Identifier (ST) → ``XON/organizationIdentifier``.
///     The unique identifier value.
///
/// XON-3 (ID Number, deprecated), XON-4 (check digit), XON-5 (check
/// digit scheme), XON-6 (assigning authority, nested HD), XON-8
/// (assigning facility, nested HD), and XON-9 (name representation
/// code) remain accessible via ``XON/field``.
public struct XON: Sendable, Equatable, Hashable {
    /// Required components for the XON composite per HL7 v2.5.1
    /// §2.A.86.
    public static let requiredComponents: [RequiredComponent] = [
        RequiredComponent(index: 1, name: "Organization Name"),
    ]

    /// The underlying ``Field``.
    public let field: Field

    /// Wrap an entire ``Field``.
    public init(field: Field) {
        self.field = field
    }

    /// Wrap a single ``Repetition``.
    public init(repetition: Repetition) {
        self.field = Field(repetitions: [repetition])
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

    private func componentValue(_ index: Int) -> String? {
        guard let rep = field.repetitions.first,
              rep.components.indices.contains(index - 1) else {
            return nil
        }
        return rep.components[index - 1].subcomponents.first?.value
    }
}
