// XTN.swift
// Extended Telecommunication Number composite (HL7 v2.5.1 §2.A.84).
//
// Value-type view over a Field that exposes named accessors for the
// most-commonly-populated XTN components. Round-trip byte-identity is
// preserved because the struct doesn't own the data — the segment
// still owns the underlying `Field`. v0.3-C3.

import Foundation

/// Extended Telecommunication Number (XTN) composite.
///
/// Exposed by typed segment accessors that wrap XTN-typed fields. XTN
/// is the standard "phone / email / fax" composite used by PID-13 /
/// PID-14 (home / business phone), NK1-5 / NK1-6 (next-of-kin home /
/// business phone), ORC-14 (call-back phone), ORC-23 (ordering-facility
/// phone), and OBR-17 (order callback phone).
///
/// Reads from the **first repetition** of the underlying field; XTN
/// fields are commonly multi-rep (one repetition per phone, email,
/// fax) — use ``XTN/field`` to walk the rest, or wrap an individual
/// ``Repetition`` via ``XTN/init(repetition:)``.
///
/// XTN component layout (HL7 v2.5.1; the commonly-populated subset
/// is exposed via named accessors):
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
/// XTN-8 through XTN-11 (extension, any text, extension prefix, speed
/// dial code) and XTN-13 / XTN-14 remain accessible via ``XTN/field``.
public struct XTN: Sendable, Equatable, Hashable {
    /// Required components for the XTN composite per HL7 v2.5.1 §2.A.84.
    ///
    /// Empty by design: XTN-1 (telephone number) is deprecated and
    /// XTN-12 (unformatted) is the modern primary, but neither is
    /// strictly required by the v2.5.1 spec — a populated XTN field
    /// may carry only an email address (XTN-4) with no phone components
    /// at all. The "at least one of XTN-1 / XTN-4 / XTN-12" pattern
    /// is the same OR-rule shape v0.3-C2 documented for CWE; modelling
    /// disjunctive required-component sets is a future RequiredComponentSet
    /// refactor that v0.3-C3 explicitly avoids.
    public static let requiredComponents: [RequiredComponent] = []

    /// The underlying ``Field``. Use this when you need access to
    /// repetitions beyond the first or to XTN components beyond
    /// the exposed named accessors.
    public let field: Field

    /// Wrap an entire ``Field``. Accessors read from `.first` repetition.
    public init(field: Field) {
        self.field = field
    }

    /// Wrap a single ``Repetition``. Convenient when iterating
    /// `field.repetitions` and you want typed access to each phone /
    /// email / fax in turn.
    public init(repetition: Repetition) {
        self.field = Field(repetitions: [repetition])
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

    private func componentValue(_ index: Int) -> String? {
        guard let rep = field.repetitions.first,
              rep.components.indices.contains(index - 1) else {
            return nil
        }
        return rep.components[index - 1].subcomponents.first?.value
    }
}
