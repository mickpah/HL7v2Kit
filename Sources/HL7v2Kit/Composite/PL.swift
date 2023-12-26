// PL.swift
// Person Location composite (HL7 v2.5.1 §2.A.53).
//
// Value-type view over a Field that exposes named accessors for the
// most-commonly-populated PL components. PL has 12 spec components;
// the v0.3-C4 cut promotes the first four (the ward / room / bed /
// facility cluster that AU clinical traffic universally populates).
// v0.3-C4.

/// Person Location (PL) composite.
///
/// Exposed by typed segment accessors that wrap PL-typed fields. PL is
/// the standard "where is the patient" composite used by PV1-3
/// (assigned location), PV1-6 (prior location), PV1-11 (temporary
/// location), and ORC-13 (enterer's location).
///
/// PL component layout (HL7 v2.5.1; the first four are exposed via
/// named accessors):
/// 1. Point of Care (IS) → ``PL/pointOfCare`` (e.g. `"WARD1"`).
/// 2. Room (IS) → ``PL/room`` (e.g. `"ROOM2"`).
/// 3. Bed (IS) → ``PL/bed`` (e.g. `"BED3"`).
/// 4. Facility (HD) → ``PL/facility`` — first subcomponent of the
///    nested HD composite (HD-1 namespace ID, e.g. `"HOSPITAL"`).
///
/// PL-5 (location status) through PL-12 (assigning authority for
/// location) remain accessible via ``PL/field``.
public struct PL: CompositeView {
    /// OR-rule conformance per HL7 v2.5.1 §2.A.53 (informal): a populated
    /// PL field must have at least one of PL-1 (Point of Care) OR PL-4
    /// (Facility, nested HD) populated. v0.4-S4 supersedes the empty
    /// `requiredComponents` v0.3-C4 shipped — the spec's actual
    /// conformance is the OR-rule, not "no constraint".
    public static let requiredComponentSet: RequiredComponentSet? = RequiredComponentSet(
        components: [
            RequiredComponent(index: 1, name: "Point of Care"),
            RequiredComponent(index: 4, name: "Facility"),
        ],
        semantics: .atLeastOneOf,
        description: "PL-1 (Point of Care) OR PL-4 (Facility)"
    )

    /// The underlying ``Field``. Use this when you need access to
    /// repetitions beyond the first or to PL components beyond PL-4.
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
