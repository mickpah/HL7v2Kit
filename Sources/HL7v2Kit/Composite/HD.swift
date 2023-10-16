// HD.swift
// Hierarchic Designator composite (HL7 v2.5.1 §2.A.32).
//
// Value-type view over a Field that exposes named accessors for each
// HD component. Round-trip byte-identity is preserved because the
// struct doesn't own the data — the segment still owns the underlying
// `Field`. v0.3-C4.

import Foundation

/// Hierarchic Designator (HD) composite.
///
/// Exposed by typed segment accessors that wrap HD-typed fields. HD is
/// the standard "application / facility identifier" composite used by
/// MSH-3 / MSH-4 / MSH-5 / MSH-6 (sending / receiving app / facility)
/// and PID-34 (last update facility). HD also appears as a nested
/// component inside several other composites (XCN-9 assigning
/// authority, PL-4 facility, etc.) — those nested cases stay accessible
/// via the outer composite's `.field`.
///
/// Reads from the **first repetition** of the underlying field; use
/// ``HD/field`` to walk multi-rep cases.
///
/// HD component layout (HL7 v2.5.1):
/// 1. Namespace ID (IS) → ``HD/namespaceID``. The locally-administered
///    identifier (e.g. `"HOSPITAL"`, `"LAB"`).
/// 2. Universal ID (ST) → ``HD/universalID``. A globally-unique
///    identifier (e.g. an ISO OID).
/// 3. Universal ID Type (ID) → ``HD/universalIDType``. The form of
///    HD-2 (`"ISO"`, `"UUID"`, `"DNS"`, …).
public struct HD: Sendable, Equatable, Hashable {
    /// Required components for the HD composite per HL7 v2.5.1 §2.A.32.
    ///
    /// Empty by design: the spec phrases HD's conformance as
    /// "HD-1 OR (HD-2 AND HD-3)" — the same OR-rule shape v0.3-C2
    /// documented for CWE and v0.3-C3 for XTN. Modelling disjunctive
    /// required-component sets is a future `RequiredComponentSet`
    /// refactor that v0.3-C4 explicitly avoids; HD ships with an empty
    /// list and HD-validating consumers can layer their own
    /// application-level rule atop the parsed view.
    public static let requiredComponents: [RequiredComponent] = []

    /// The underlying ``Field``. Use this when you need access to
    /// repetitions beyond the first.
    public let field: Field

    /// Wrap an entire ``Field``. Accessors read from `.first` repetition.
    public init(field: Field) {
        self.field = field
    }

    /// Wrap a single ``Repetition``.
    public init(repetition: Repetition) {
        self.field = Field(repetitions: [repetition])
    }

    /// HD-1 namespace ID — the locally-administered identifier.
    public var namespaceID: String? {
        componentValue(1)
    }

    /// HD-2 universal ID — a globally-unique authority identifier.
    public var universalID: String? {
        componentValue(2)
    }

    /// HD-3 universal ID type — the form of HD-2 (`"ISO"`, `"UUID"`, …).
    public var universalIDType: String? {
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
