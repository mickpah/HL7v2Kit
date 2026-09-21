// MSG.swift
// Message Type composite (HL7 v2.5.1 §2.A.46).
//
// Value-type view over a Field that exposes named accessors for each
// MSG component. v0.3-C4.

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
public struct MSG: CompositeView {
    /// The components HL7 v2.5.1 PRINTS as required (`R`) in the MSG component
    /// table (MSG.1, MSG.2, MSG.3). Informational, for the canonical
    /// version only: the ``Validator`` does not read this list. It takes required
    /// components from ``DataTypeGrammarTable`` for the MESSAGE's own version, because
    /// they differ between versions (M14, ADR-017).
    public static let requiredComponents: [RequiredComponent] = [
        RequiredComponent(index: 1, name: "Message Code"),
        RequiredComponent(index: 2, name: "Trigger Event"),
        RequiredComponent(index: 3, name: "Message Structure"),
    ]

    /// The underlying ``Field``.
    public let field: Field

    /// Wrap an entire ``Field``.
    public init(field: Field) {
        self.field = field
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
}
