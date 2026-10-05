// XTN.swift
// Extended Telecommunication Number composite (HL7 v2.5.1 §2.A.84).
//
// Value-type view over a Field. Hand-written XTN components; the rest are
// generated (ADR-020). Round-trip byte-identity is
// preserved because the struct doesn't own the data — the segment
// still owns the underlying `Field`. v0.3-C3.

/// Extended Telecommunication Number (XTN) composite.
///
/// Exposed by typed segment accessors that wrap XTN-typed fields. XTN
/// is the standard "phone / email / fax" composite used by PID-13 /
/// PID-14 (home / business phone), NK1-5 / NK1-6 (next-of-kin home /
/// business phone), ORC-14 (call-back phone), ORC-23 (ordering-facility
/// phone), and OBR-17 (order callback phone).
///
/// Reads from the **first repetition** of the underlying field; XTN
/// fields often repeat (one repetition per phone, email,
/// fax) — use ``XTN/field`` to walk the rest, or wrap an individual
/// ``Repetition`` via ``XTN/init(repetition:)``.
///
/// XTN component layout (hand-written accessors; the rest are generated):
/// 1. Telephone Number (deprecated, ST) → ``XTN/telephoneNumber``. The
///    legacy "free-form phone string" slot (e.g. `"(02)555-1234"`).
///    Deprecated by HL7 v2.5; modern senders populate XTN-12 instead,
///    but real AU traffic still routinely sets XTN-1.
/// 2. Telecommunication Use Code (ID) → ``XTN/telecommunicationUseCode``
///    (`"PRN"` primary residence, `"WPN"` work, `"EMR"` emergency, …).
/// 3. Telecommunication Equipment Type (ID) →
///    ``XTN/telecommunicationEquipmentType`` (`"PH"` phone, `"FX"` fax,
///    `"CP"` mobile, `"Internet"` email, …).
/// 4. Email Address (ST) → ``XTN/emailAddress``.
/// 5. Country Code (NM) → ``XTN/countryCode``.
/// 6. Area / City Code (NM) → ``XTN/areaCityCode``.
/// 7. Local Number (NM) → ``XTN/localNumber``.
/// 12. Unformatted Telephone Number (ST) → ``XTN/unformattedTelephoneNumber``.
///     The modern primary; carries the full number in
///     `+CC-AAA-NNNNNNN` shape.
///
/// XTN-8..11 and XTN-13..18 are generated accessors; see `XTN+Components.swift`.
public struct XTN: CompositeView {
    /// OR-rule conformance per HL7 v2.5.1 §2.A.84: a populated XTN field
    /// must have at least one of XTN-1 (Telephone Number — deprecated),
    /// XTN-4 (Email Address), or XTN-12 (Unformatted Telephone Number —
    /// modern primary) populated. v0.4-S4 supersedes the empty
    /// `requiredComponents` v0.3-C3 shipped — the spec's actual
    /// conformance is the OR-rule, not "no constraint".

    /// No either-or rule (M15). The hand-written "XTN-1 OR XTN-4 OR XTN-12" rejected the
    /// spec's own example: v2.5.1 sec 2.A.89 prints the fax number `^ORN^FX^^^734^6777777`
    /// and RECOMMENDS that delimited form (components 5 to 9) as of v2.3, keeping XTN-1
    /// "for backward compatibility only". Required components come from the version's
    /// printed component table (``DataTypeGrammarTable``): none before v2.8.2, XTN-3 from it.
    public static let requiredComponentSet: RequiredComponentSet? = nil

    /// The underlying ``Field``. Use this when you need access to
    /// repetitions beyond the first. Every component has a named accessor;
    /// use ``component(_:as:)`` for a sub-composite's subcomponents.
    public let field: Field

    /// Wrap an entire ``Field``. Accessors read from `.first` repetition.
    public init(field: Field) {
        self.field = field
    }

    /// XTN-1 telephone number (deprecated free-form slot).
    public var telephoneNumber: String? {
        componentValue(1)
    }

    /// XTN-2 telecommunication use code (`"PRN"`, `"WPN"`, …).
    public var telecommunicationUseCode: String? {
        componentValue(2)
    }

    /// XTN-3 telecommunication equipment type (`"PH"`, `"FX"`, …).
    public var telecommunicationEquipmentType: String? {
        componentValue(3)
    }

    /// XTN-4 email address.
    public var emailAddress: String? {
        componentValue(4)
    }

    /// XTN-5 country code.
    public var countryCode: String? {
        componentValue(5)
    }

    /// XTN-6 area / city code.
    public var areaCityCode: String? {
        componentValue(6)
    }

    /// XTN-7 local number.
    public var localNumber: String? {
        componentValue(7)
    }

    /// XTN-12 unformatted telephone number — the modern primary slot.
    public var unformattedTelephoneNumber: String? {
        componentValue(12)
    }
}
