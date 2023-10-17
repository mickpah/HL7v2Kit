// RequiredComponentSet.swift
// Disjunctive / grouped required-component metadata for composite data
// types whose v2.5.1 spec conformance is "at least one of these components
// must be populated" rather than the flat "all of these must be populated"
// rule `RequiredComponent` carries. v0.4-S4.
//
// Per the working notes project requirements (feature-complete over AU-specific;
// integrator primary-reference tool), composites with OR-rule conformance
// must enforce the OR-rule — not silently skip. The five v2.5.1 composites
// with OR-rule conformance — CWE, XTN, HD, PL, EIP — publish a
// `requiredComponentSet` reflecting their spec rule.

import Foundation

/// OR-rule / grouped-disjunction conformance metadata for a composite
/// data type. Companion to `RequiredComponent` — that type carries flat
/// "all-of" requirements; this type carries disjunctive ones.
///
/// A composite may publish either or both of `requiredComponents` and
/// `requiredComponentSet`. The Validator dispatches both: flat
/// requirements first, then the set's semantics. The two are
/// independent — flat requirements fire `requiredComponentMissing` per
/// missing flat component; the set fires one issue per violated
/// disjunction.
public struct RequiredComponentSet: Sendable, Equatable, Hashable {

    /// How the `components` list combines for conformance:
    ///
    /// - `.atLeastOneOf` — at least one component in the list must be
    ///   populated. Used by composites like `CWE` (CWE-1 OR CWE-9
    ///   must be populated), `XTN` (XTN-1 / XTN-4 / XTN-12), `PL`
    ///   (PL-1 / PL-4), `EIP` (EIP-1 / EIP-2).
    /// - `.allOfGroupOrAtLeastOne(group:)` — either every component in
    ///   the `group` sub-list is populated, OR at least one of the
    ///   non-group components is. Used by `HD` to express "HD-1
    ///   populated OR (HD-2 AND HD-3 populated)" — the `group` is
    ///   `[2, 3]`, the non-group fallback is `[1]`.
    public enum Semantics: Sendable, Equatable, Hashable {
        case atLeastOneOf
        case allOfGroupOrAtLeastOne(group: [Int])
    }

    /// 1-based component indices participating in the disjunction, with
    /// their human-readable names for `ValidationIssue.message`
    /// rendering.
    public let components: [RequiredComponent]

    /// How `components` combines for conformance.
    public let semantics: Semantics

    /// A short human-readable description used in `ValidationIssue.message`
    /// when the set's rule is violated. Defaults to a generated string
    /// from `components` + `semantics`, but composites can override for
    /// clarity (e.g. `"CWE-1 (Identifier) OR CWE-9 (Original Text)"`).
    public let description: String

    public init(
        components: [RequiredComponent],
        semantics: Semantics,
        description: String? = nil
    ) {
        self.components = components
        self.semantics = semantics
        self.description = description ?? Self.defaultDescription(
            components: components,
            semantics: semantics
        )
    }

    /// Returns true if the populated-component indices satisfy the
    /// rule. `populatedIndices` is the set of 1-based component indices
    /// that are non-empty in the field being validated.
    public func isSatisfied(populatedIndices: Set<Int>) -> Bool {
        switch semantics {
        case .atLeastOneOf:
            return components.contains { populatedIndices.contains($0.index) }
        case .allOfGroupOrAtLeastOne(let group):
            let groupSet = Set(group)
            let groupSatisfied = group.allSatisfy { populatedIndices.contains($0) }
            if groupSatisfied { return true }
            let nonGroupIndices = components
                .map(\.index)
                .filter { !groupSet.contains($0) }
            return nonGroupIndices.contains { populatedIndices.contains($0) }
        }
    }

    private static func defaultDescription(
        components: [RequiredComponent],
        semantics: Semantics
    ) -> String {
        switch semantics {
        case .atLeastOneOf:
            let parts = components.map { "C-\($0.index) (\($0.name))" }
            return parts.joined(separator: " OR ")
        case .allOfGroupOrAtLeastOne(let group):
            let groupSet = Set(group)
            let groupParts = components
                .filter { groupSet.contains($0.index) }
                .map { "C-\($0.index) (\($0.name))" }
            let altParts = components
                .filter { !groupSet.contains($0.index) }
                .map { "C-\($0.index) (\($0.name))" }
            let groupClause = groupParts.joined(separator: " AND ")
            let altClause = altParts.joined(separator: " OR ")
            return "\(altClause) OR (\(groupClause))"
        }
    }
}
