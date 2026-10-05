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
    ///   populated. No shipped composite uses it any more: the `CWE`,
    ///   `XTN` and `PL` rules built on it rejected examples the spec itself
    ///   prints, and `EIP`'s was vacuous (M15).
    /// - `.allOfGroupOrAtLeastOne(group:)` — either every component in
    ///   the `group` sub-list is populated, OR at least one of the
    ///   non-group components is. Used by `HD` to express "HD-1
    ///   populated OR (HD-2 AND HD-3 populated)" — the `group` is
    ///   `[2, 3]`, the non-group fallback is `[1]`. The group stands or
    ///   falls together: a PARTIALLY populated group never satisfies the
    ///   rule, because the HD definition says components 2 and 3 "must
    ///   either both be valued ... or both be not valued" (M16).
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
    /// when the set's rule is violated
    /// (e.g. `"CWE-1 (Identifier) OR CWE-9 (Original Text)"`). Required
    /// as of 2.0 — every shipped set spells its rule out explicitly.
    public let description: String

    public init(
        components: [RequiredComponent],
        semantics: Semantics,
        description: String
    ) {
        self.components = components
        self.semantics = semantics
        self.description = description
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
            // The group stands or falls together: a partially populated group never
            // satisfies the rule, whatever else is valued. HD is the case in point, on every
            // version from v2.3: "The second and third components must either both be valued
            // (both non-null), or both be not valued (both null)."
            if !groupSatisfied && group.contains(where: { populatedIndices.contains($0) }) { return false }
            if groupSatisfied { return true }
            let nonGroupIndices = components
                .map(\.index)
                .filter { !groupSet.contains($0) }
            return nonGroupIndices.contains { populatedIndices.contains($0) }
        }
    }

    /// The `ValidationIssue.message` clause naming the sub-rule that actually failed, for a
    /// `populatedIndices` that fails `isSatisfied(populatedIndices:)`. `compositeCode` is the
    /// composite's HL7 data-type code (e.g. `"HD"`), prefixed onto component indices the same
    /// way `description` does (P6-11).
    ///
    /// Under `.allOfGroupOrAtLeastOne(group:)`, a *partially* populated group is its own
    /// sub-rule — "these must both be valued or both be empty" — independent of whether the
    /// non-group alternative is already satisfied. Naming the full OR (`description`) in that
    /// case is misleading: e.g. for HD with HD-1 valued and only HD-2 of the HD-2/HD-3 pair
    /// valued, the OR's non-group side (HD-1) already holds, so printing "expected HD-1 OR
    /// (HD-2 AND HD-3) populated" reads as if HD-1 were also missing. The group's "both or
    /// neither" rule is the one that fired, so that's what's named.
    ///
    /// Every other case — nothing in the field satisfies either side, or `.atLeastOneOf`
    /// (which has no group and so no partial-pair reading) — names the OR alternatives via
    /// `description`, unchanged from before this task.
    ///
    /// Internal: `ValidationIssue.message` carries no stability guarantee (ADR-014), so this
    /// renderer has no public need. The Validator is the only caller; tests reach it via
    /// `@testable import`.
    func violationMessage(populatedIndices: Set<Int>, compositeCode: String) -> String {
        if case .allOfGroupOrAtLeastOne(let group) = semantics,
           !group.allSatisfy({ populatedIndices.contains($0) }),
           group.contains(where: { populatedIndices.contains($0) }) {
            let labels = group.map { "\(compositeCode)-\($0)" }
            let quantifier = labels.count == 2 ? "both" : "all"
            let joined: String
            switch labels.count {
            case 0: joined = ""
            case 1: joined = labels[0]
            case 2: joined = "\(labels[0]) and \(labels[1])"
            default: joined = labels.dropLast().joined(separator: ", ") + ", and \(labels.last!)"
            }
            return "\(joined) must \(quantifier) be valued or \(quantifier) be empty"
        }
        return "expected \(description) populated"
    }

}
