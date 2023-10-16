// PL.swift
// Person Location composite (HL7 v2.5.1 §2.A.53).
//
// Value-type view over a Field that exposes named accessors for the
// most-commonly-populated PL components. PL has 12 spec components;
// the v0.3-C4 cut promotes the first four (the ward / room / bed /
// facility cluster that AU clinical traffic universally populates).
// v0.3-C4.

import Foundation

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
public struct PL: Sendable, Equatable, Hashable {
    /// Required components for the PL composite per HL7 v2.5.1
    /// §2.A.53.
    ///
    /// Empty by design: the v2.5.1 spec marks every PL sub-component
    /// as optional individually. AU clinical traffic typically
    /// populates either PL-1 (point of care) or PL-4 (facility), but
    /// neither is strictly required by the spec — modelling the
    /// "at least one of" disjunction is a future `RequiredComponentSet`
    /// refactor that v0.3-C4 explicitly avoids (same call as HD / XTN /
    /// CWE).
    public static let requiredComponents: [RequiredComponent] = []

    /// The underlying ``Field``. Use this when you need access to
    /// repetitions beyond the first or to PL components beyond PL-4.
    public let field: Field

    /// Wrap an entire ``Field``.
    public init(field: Field) {
        self.field = field
    }

    /// Wrap a single ``Repetition``.
    public init(repetition: Repetition) {
        self.field = Field(repetitions: [repetition])
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

    private func componentValue(_ index: Int) -> String? {
        guard let rep = field.repetitions.first,
              rep.components.indices.contains(index - 1) else {
            return nil
        }
        return rep.components[index - 1].subcomponents.first?.value
    }
}
