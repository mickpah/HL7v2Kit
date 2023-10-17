// EIP.swift
// Entity Identifier Pair composite (HL7 v2.5.1 §2.A.29).
//
// Value-type view over a Field that exposes named accessors for each
// EIP component. EIP is a pair of nested EI composites — placer and
// filler order numbers in the order-linking slots of ORC-8 and
// OBR-29. The named accessors return the first subcomponent of each
// nested EI (the entityIdentifier). v0.3-C4.

import Foundation

/// Entity Identifier Pair (EIP) composite.
///
/// Exposed by typed segment accessors that wrap EIP-typed fields. EIP
/// links a placer's order to a filler's order — used by ORC-8 (parent)
/// and OBR-29 (parent result). Each EIP slot is a nested EI composite;
/// the named accessors return the first subcomponent of each nested
/// EI (the entityIdentifier). For the full nested EI structure (e.g.
/// to read the namespace ID via EI-2), drill into
/// `.field.first?.components[N]` directly.
///
/// EIP component layout (HL7 v2.5.1):
/// 1. Placer Assigned Identifier (EI) → ``EIP/placerAssignedIdentifier``
///    — first subcomponent of the nested EI (EI-1 entityIdentifier).
/// 2. Filler Assigned Identifier (EI) → ``EIP/fillerAssignedIdentifier``
///    — same shape as EIP-1.
public struct EIP: Sendable, Equatable, Hashable {
    /// Required components for the EIP composite per HL7 v2.5.1
    /// §2.A.29.
    ///
    /// Empty by design: the spec marks both EIP-1 and EIP-2 as
    /// individually optional. AU clinical traffic uses EIP for
    /// order-pair linkage; an order with no parent populates neither
    /// component, and a child order may populate only one of the
    /// pair. Modelling the "if EIP is populated at all, at least one
    /// of the two slots must carry an identifier" pattern is the same
    /// disjunctive-required-component refactor v0.3-C4 explicitly
    /// avoids for HD / XTN / PL / CWE.
    public static let requiredComponents: [RequiredComponent] = []

    /// OR-rule conformance per HL7 v2.5.1 §2.A.29: a populated EIP field
    /// must have at least one of EIP-1 (Placer Assigned Identifier) OR
    /// EIP-2 (Filler Assigned Identifier) populated. v0.4-S4 supersedes
    /// the empty `requiredComponents` v0.3-C4 shipped — the spec's
    /// actual conformance is the OR-rule, not "no constraint".
    public static let requiredComponentSet: RequiredComponentSet? = RequiredComponentSet(
        components: [
            RequiredComponent(index: 1, name: "Placer Assigned Identifier"),
            RequiredComponent(index: 2, name: "Filler Assigned Identifier"),
        ],
        semantics: .atLeastOneOf,
        description: "EIP-1 (Placer Assigned Identifier) OR EIP-2 (Filler Assigned Identifier)"
    )

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

    /// EIP-1 placer assigned identifier — first subcomponent of the
    /// nested EI (its entityIdentifier).
    public var placerAssignedIdentifier: String? {
        componentValue(1)
    }

    /// EIP-2 filler assigned identifier — first subcomponent of the
    /// nested EI (its entityIdentifier).
    public var fillerAssignedIdentifier: String? {
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
