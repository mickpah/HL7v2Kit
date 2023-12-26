// CNE.swift
// Coded with No Exceptions composite (HL7 v2.5.1 §2.A.14).
//
// Value-type view over a Field that exposes named accessors for each
// CNE component. CNE has the same component layout as CE but signals
// a stricter conformance contract (the receiving system MUST recognise
// every populated CNE-1 code, no free-text-fallback allowed). v0.3-C4.

/// Coded with No Exceptions (CNE) composite.
///
/// Exposed by typed segment accessors that wrap CNE-typed fields. CNE
/// shares its component layout with CE but signals a stricter
/// conformance contract — every CNE-1 code must be drawn from a
/// pre-agreed code system; ad-hoc free text in CNE-2 with an unknown
/// CNE-1 is non-conformant. The v2.5.1 typed-segment surface uses CNE
/// for ORC-30 (enterer authorization mode).
///
/// CNE component layout (HL7 v2.5.1; identical to CE):
/// 1. Identifier (ST) → ``CNE/identifier``. Required. The coded value.
/// 2. Text (ST) → ``CNE/text``. Human-readable description.
/// 3. Name of Coding System (ID) → ``CNE/nameOfCodingSystem``.
/// 4. Alternate Identifier (ST) → ``CNE/altIdentifier``.
/// 5. Alternate Text (ST) → ``CNE/altText``.
/// 6. Name of Alternate Coding System (ID) → ``CNE/nameOfAltCodingSystem``.
public struct CNE: Sendable, Equatable, Hashable {
    /// Required components for the CNE composite per HL7 v2.5.1
    /// §2.A.14.
    public static let requiredComponents: [RequiredComponent] = [
        RequiredComponent(index: 1, name: "Identifier"),
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

    /// CNE-1 identifier — the coded value.
    public var identifier: String? {
        componentValue(1)
    }

    /// CNE-2 text — human-readable description of CNE-1.
    public var text: String? {
        componentValue(2)
    }

    /// CNE-3 name of coding system.
    public var nameOfCodingSystem: String? {
        componentValue(3)
    }

    /// CNE-4 alternate identifier.
    public var altIdentifier: String? {
        componentValue(4)
    }

    /// CNE-5 alternate text.
    public var altText: String? {
        componentValue(5)
    }

    /// CNE-6 name of alternate coding system.
    public var nameOfAltCodingSystem: String? {
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
