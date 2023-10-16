// PT.swift
// Processing Type composite (HL7 v2.5.1 §2.A.55).
//
// Value-type view over a Field that exposes named accessors for each
// PT component. v0.3-C4.

import Foundation

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
public struct PT: Sendable, Equatable, Hashable {
    /// Required components for the PT composite per HL7 v2.5.1
    /// §2.A.55.
    public static let requiredComponents: [RequiredComponent] = [
        RequiredComponent(index: 1, name: "Processing ID"),
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

    /// PT-1 processing ID (`"P"`, `"T"`, `"D"`).
    public var processingID: String? {
        componentValue(1)
    }

    /// PT-2 processing mode (`"A"`, `"R"`, `"I"`, `"T"`).
    public var processingMode: String? {
        componentValue(2)
    }

    private func componentValue(_ index: Int) -> String? {
        guard let rep = field.repetitions.first,
              rep.components.indices.contains(index - 1) else {
            return nil
        }
        return rep.components[index - 1].subcomponents.first?.value
    }
}
