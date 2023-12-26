// HD.swift
// Hierarchic Designator composite (HL7 v2.5.1 §2.A.32).
//
// Value-type view over a Field that exposes named accessors for each
// HD component. Round-trip byte-identity is preserved because the
// struct doesn't own the data — the segment still owns the underlying
// `Field`. v0.3-C4.

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
public struct HD: CompositeView {
    /// OR-rule conformance per HL7 v2.5.1 §2.A.32: a populated HD field
    /// must have HD-1 (Namespace ID) populated, OR both HD-2 (Universal
    /// ID) AND HD-3 (Universal ID Type) populated. v0.4-S4 supersedes
    /// the empty `requiredComponents` v0.3-C4 shipped — the spec's
    /// actual conformance is the OR-rule, not "no constraint".
    public static let requiredComponentSet: RequiredComponentSet? = RequiredComponentSet(
        components: [
            RequiredComponent(index: 1, name: "Namespace ID"),
            RequiredComponent(index: 2, name: "Universal ID"),
            RequiredComponent(index: 3, name: "Universal ID Type"),
        ],
        semantics: .allOfGroupOrAtLeastOne(group: [2, 3]),
        description: "HD-1 (Namespace ID) OR (HD-2 (Universal ID) AND HD-3 (Universal ID Type))"
    )

    /// The underlying ``Field``. Use this when you need access to
    /// repetitions beyond the first.
    public let field: Field

    /// Wrap an entire ``Field``. Accessors read from `.first` repetition.
    public init(field: Field) {
        self.field = field
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
}
