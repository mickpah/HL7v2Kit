// EIP.swift
// Entity Identifier Pair composite (HL7 v2.5.1 §2.A.29).
//
// Value-type view over a Field that exposes named accessors for each
// EIP component. EIP is a pair of nested EI composites — placer and
// filler order numbers in the order-linking slots of ORC-8 and
// OBR-29. The named accessors return the first subcomponent of each
// nested EI (the entityIdentifier). v0.3-C4.

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
public struct EIP: CompositeView {
    /// OR-rule conformance per HL7 v2.5.1 §2.A.29: a populated EIP field
    /// must have at least one of EIP-1 (Placer Assigned Identifier) OR
    /// EIP-2 (Filler Assigned Identifier) populated. v0.4-S4 supersedes
    /// the empty `requiredComponents` v0.3-C4 shipped — the spec's
    /// actual conformance is the OR-rule, not "no constraint".

    /// No either-or rule (M15). "EIP-1 OR EIP-2" was vacuous: EIP has two components, so
    /// any populated EIP already satisfied it. Both are printed `O`.
    public static let requiredComponentSet: RequiredComponentSet? = nil

    /// The underlying ``Field``.
    public let field: Field

    /// Wrap an entire ``Field``.
    public init(field: Field) {
        self.field = field
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
}
