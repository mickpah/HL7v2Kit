// MSG.swift
// Message Type composite (HL7 v2.5.1 §2.A.46).
//
// Value-type view over a Field that exposes named accessors for each
// MSG component. v0.3-C4.

import Foundation

/// Message Type (MSG) composite.
///
/// Exposed by the typed accessor `msh.messageType` (MSH-9). Carries the
/// HL7 message code (e.g. `"ADT"`), trigger event (e.g. `"A01"`), and
/// optional message structure (e.g. `"ADT_A01"`).
///
/// MSG component layout (HL7 v2.5.1):
/// 1. Message Code (ID) → ``MSG/messageCode``. Required. E.g. `"ADT"`,
///    `"ORU"`, `"ORM"`.
/// 2. Trigger Event (ID) → ``MSG/triggerEvent``. E.g. `"A01"` admit,
///    `"R01"` unsolicited results.
/// 3. Message Structure (ID) → ``MSG/messageStructure``. The combined
///    structure name (e.g. `"ADT_A01"`); often left empty.
public struct MSG: Sendable, Equatable, Hashable {
    /// Required components for the MSG composite per HL7 v2.5.1
    /// §2.A.46.
    public static let requiredComponents: [RequiredComponent] = [
        RequiredComponent(index: 1, name: "Message Code"),
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

    /// MSG-1 message code (e.g. `"ADT"`, `"ORU"`).
    public var messageCode: String? {
        componentValue(1)
    }

    /// MSG-2 trigger event (e.g. `"A01"`, `"R01"`).
    public var triggerEvent: String? {
        componentValue(2)
    }

    /// MSG-3 message structure (e.g. `"ADT_A01"`).
    public var messageStructure: String? {
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
