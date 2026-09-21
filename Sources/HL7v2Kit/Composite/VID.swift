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
public struct VID: CompositeView {
    /// The components HL7 v2.5.1 PRINTS as required (`R`) in the VID component
    /// table (none: every VID component is optional there). Informational, for the canonical
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
}
