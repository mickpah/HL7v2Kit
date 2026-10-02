// PL.swift
// Person Location composite (HL7 v2.5.1 §2.A.53).
//
// Value-type view over a Field. PL-1..4 hand-written components; PL-5..11
// are generated (ADR-020). v0.3-C4.

/// Person Location (PL) composite.
///
/// Exposed by typed segment accessors that wrap PL-typed fields. PL is
/// the standard "where is the patient" composite used by PV1-3
/// (assigned location), PV1-6 (prior location), PV1-11 (temporary
/// location), and ORC-13 (enterer's location).
///
/// PL component layout (hand-written accessors; the rest are generated):
/// 1. Point of Care (IS) → ``PL/pointOfCare`` (e.g. `"WARD1"`).
/// 2. Room (IS) → ``PL/room`` (e.g. `"ROOM2"`).
/// 3. Bed (IS) → ``PL/bed`` (e.g. `"BED3"`).
/// 4. Facility (HD) → ``PL/facility`` — first subcomponent of the
///    nested HD composite (HD-1 namespace ID, e.g. `"HOSPITAL"`).
///
/// PL-5 through PL-11 are generated accessors; see `PL+Components.swift`.
public struct PL: CompositeView {
    /// OR-rule conformance per HL7 v2.5.1 §2.A.53 (informal): a populated
    /// PL field must have at least one of PL-1 (Point of Care) OR PL-4
    /// (Facility, nested HD) populated. v0.4-S4 supersedes the empty
    /// `requiredComponents` v0.3-C4 shipped — the spec's actual
    /// conformance is the OR-rule, not "no constraint".

    /// No either-or rule (M15). The hand-written "PL-1 OR PL-4" contradicted the spec's
    /// definition (v2.5.1 sec 2.A.53): "Which components are valued depends on the needs of
    /// the site. For example for a patient treated at home, only the person location type
    /// is valued." Every PL component is printed `O` or `C`.
    public static let requiredComponentSet: RequiredComponentSet? = nil

    /// The underlying ``Field``. Use this when you need access to
    /// repetitions beyond the first. Every component has a named accessor;
    /// use ``component(_:as:)`` for a sub-composite's subcomponents.
    public let field: Field

    /// Wrap an entire ``Field``.
    public init(field: Field) {
        self.field = field
    }

    /// PL-1 point of care (e.g. `"WARD1"`).
    public var pointOfCare: String? {
        componentValue(1)
    }

    /// PL-2 room (e.g. `"ROOM2"`).
    public var room: String? {
        componentValue(2)
    }

    /// PL-3 bed (e.g. `"BED3"`).
    public var bed: String? {
        componentValue(3)
    }

    /// PL-4 facility — first subcomponent of the nested HD composite
    /// (HD-1 namespace ID, e.g. `"HOSPITAL"`).
    public var facility: String? {
        componentValue(4)
    }
}
