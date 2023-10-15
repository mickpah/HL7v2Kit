// XPN.swift
// Extended Person Name composite (HL7 v2.5.1 §2.A.81).
//
// Value-type view over a Field that exposes named accessors for the most
// common XPN components. The struct does not own the data — the segment
// still owns the underlying `Field`, so round-trip byte-identity is
// preserved. v0.2-C1.

import Foundation

/// Extended Person Name (XPN) composite.
///
/// Exposed by typed segment accessors that wrap XPN-typed fields (e.g.
/// ``PID/patientName``, ``NK1/name``). Reads from the **first repetition**
/// of the underlying field; for multi-repetition fields like PID-5 use
/// ``XPN/field`` to walk the rest yourself, or construct a new `XPN` from
/// a specific ``Repetition`` via ``XPN/init(repetition:)``.
///
/// XPN component layout (HL7 v2.5.1):
/// 1. Family Name (FN) — itself a sub-composite; the FN.1 surname is what
///    ``XPN/familyName`` returns.
/// 2. Given Name (ST)
/// 3. Second and Further Given Names or Initials Thereof (ST) → ``XPN/middleName``.
/// 4. Suffix (ST) → ``XPN/suffix``.
/// 5. Prefix (ST) → ``XPN/prefix``.
/// 6. Degree (IS) — deprecated; not exposed.
/// 7. Name Type Code (ID) → ``XPN/nameTypeCode`` (e.g. `"L"` legal, `"M"` maiden).
///
/// Components 8–14 (representation code, context, validity range, assembly
/// order, dates, professional suffix) are reachable via ``XPN/field`` but
/// not exposed as named accessors in v0.2.
public struct XPN: Sendable, Equatable, Hashable {
    /// Required components for the XPN composite per HL7 v2.5.1 §2.A.81.
    /// ``Validator`` consults this when the `checkComponentGrammar` toggle
    /// is on: if XPN is populated but one of these components is empty,
    /// the validator emits ``IssueCode/requiredComponentMissing``. v0.2-V2.
    public static let requiredComponents: [RequiredComponent] = [
        RequiredComponent(index: 1, name: "Family Name"),
    ]

    /// The underlying ``Field``. Use this when you need access to repetitions
    /// beyond the first, or to components not exposed as named accessors.
    public let field: Field

    /// Wrap an entire ``Field``. Accessors read from `.first` repetition.
    public init(field: Field) {
        self.field = field
    }

    /// Wrap a single ``Repetition``. Convenient when iterating
    /// `field.repetitions` and you want typed access to each name in turn.
    public init(repetition: Repetition) {
        self.field = Field(repetitions: [repetition])
    }

    /// XPN-1 family name (the FN sub-composite's first subcomponent — the
    /// surname text).
    public var familyName: String? {
        componentValue(1)
    }

    /// XPN-2 given name.
    public var givenName: String? {
        componentValue(2)
    }

    /// XPN-3 second and further given names or initials.
    public var middleName: String? {
        componentValue(3)
    }

    /// XPN-4 suffix (e.g. `"JR"`, `"III"`).
    public var suffix: String? {
        componentValue(4)
    }

    /// XPN-5 prefix (e.g. `"DR"`).
    public var prefix: String? {
        componentValue(5)
    }

    /// XPN-7 name type code (`"L"` legal, `"M"` maiden, `"A"` alias, etc.).
    public var nameTypeCode: String? {
        componentValue(7)
    }

    /// Read the first-subcomponent value of the 1-based `index`-th
    /// component of the field's first repetition. Returns nil if the
    /// component is absent or empty.
    private func componentValue(_ index: Int) -> String? {
        guard let rep = field.repetitions.first,
              rep.components.indices.contains(index - 1) else {
            return nil
        }
        return rep.components[index - 1].subcomponents.first?.value
    }
}
