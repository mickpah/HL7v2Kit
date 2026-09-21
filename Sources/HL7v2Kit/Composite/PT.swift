// PT.swift
// Processing Type composite (HL7 v2.5.1 §2.A.55).
//
// Value-type view over a Field that exposes named accessors for each
// PT component. v0.3-C4.

/// Processing Type (PT) composite.
///
/// Exposed by the typed accessor `msh.processingID` (MSH-11). Declares
/// whether a message is production / training / debug, and whether the
/// processing mode is archive / restore / etc.
///
/// PT component layout (HL7 v2.5.1):
/// 1. Processing ID (ID) → ``PT/processingID``. Required.
///    `"P"` production, `"T"` training, `"D"` debug.
/// 2. Processing Mode (ID) → ``PT/processingMode``. `"A"` archive,
///    `"R"` restore, `"I"` initial load, `"T"` current processing.
public struct PT: CompositeView {
    /// The components HL7 v2.5.1 PRINTS as required (`R`) in the PT component
    /// table (none: every PT component is optional there). Informational, for the canonical
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

    /// PT-1 processing ID (`"P"`, `"T"`, `"D"`).
    public var processingID: String? {
        componentValue(1)
    }

    /// PT-2 processing mode (`"A"`, `"R"`, `"I"`, `"T"`).
    public var processingMode: String? {
        componentValue(2)
    }
}
