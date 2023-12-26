// VID.swift
// Version Identifier composite (HL7 v2.5.1 §2.A.79).
//
// Value-type view over a Field that exposes named accessors for each
// VID component. v0.3-C4.

/// Version Identifier (VID) composite.
///
/// Exposed by the typed accessor `msh.versionID` (MSH-12). Carries the
/// HL7 version string and optional internationalization metadata.
///
/// VID component layout (HL7 v2.5.1):
/// 1. Version ID (ID) → ``VID/versionID``. Required. The HL7 version
///    string (`"2.5.1"`, `"2.4"`, `"2.3.1"`, `"2.3"`).
/// 2. Internationalization Code (CE) → ``VID/internationalizationCode``.
///    A nested CE composite; the named accessor returns CE-1 of the
///    nested composite (the identifier subcomponent). For the full
///    nested structure, use `.field.first?.components[1]` and inspect
///    its subcomponents directly.
/// 3. International Version ID (CE) → ``VID/internationalVersionID``.
///    Same nested-CE shape as VID-2; returns CE-1 of the nested
///    composite.
public struct VID: Sendable, Equatable, Hashable {
    /// Required components for the VID composite per HL7 v2.5.1
    /// §2.A.79.
    public static let requiredComponents: [RequiredComponent] = [
        RequiredComponent(index: 1, name: "Version ID"),
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

    /// VID-1 version ID (e.g. `"2.5.1"`).
    public var versionID: String? {
        componentValue(1)
    }

    /// VID-2 internationalization code — first subcomponent of the
    /// nested CE composite.
    public var internationalizationCode: String? {
        componentValue(2)
    }

    /// VID-3 international version ID — first subcomponent of the
    /// nested CE composite.
    public var internationalVersionID: String? {
        componentValue(3)
    }

    private func componentValue(_ index: Int) -> String? {
        guard let rep = field.repetitions.first,
              rep.components.indices.contains(index - 1) else {
            return nil
        }
        return rep.components[index - 1].subcomponents.first?.value
    }
}
