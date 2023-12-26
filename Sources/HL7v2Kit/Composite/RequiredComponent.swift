// RequiredComponent.swift
// Lightweight value type listing a required component within a composite
// data type. Consumed by ``Validator`` when the `checkComponentGrammar`
// toggle is on. Each composite struct (``XPN``, ``CX``, ``XAD``) carries
// its own `static let requiredComponents: [RequiredComponent]`. v0.2-V2.

/// One required component within a composite data type — the 1-based
/// component index plus the human-readable name used in
/// ``ValidationIssue/message`` strings.
public struct RequiredComponent: Sendable, Equatable, Hashable {
    /// 1-based component index within the composite. For XPN, `1` is the
    /// family name; for CX, `1` is the ID number; for XAD, `1` is the
    /// street address.
    public let index: Int
    /// Human-readable component name (e.g. `"Family Name"`).
    public let name: String

    public init(index: Int, name: String) {
        self.index = index
        self.name = name
    }
}
