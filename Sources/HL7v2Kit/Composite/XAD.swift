// XAD.swift
// Extended Address composite (HL7 v2.5.1 §2.A.79).
//
// Value-type view over a Field that exposes named accessors for the most
// common XAD components. Round-trip byte-identity is preserved because the
// struct doesn't own the data — the segment still owns the underlying
// `Field`. v0.2-C1.

/// Extended Address (XAD) composite.
///
/// Exposed by typed segment accessors that wrap XAD-typed fields (e.g.
/// ``PID/patientAddress``, ``NK1/address``, ``ORC/orderingFacilityAddress``,
/// ``ORC/orderingProviderAddress``). Reads from the **first repetition**
/// of the underlying field; for multi-repetition fields use ``XAD/field``
/// to walk the rest, or wrap an individual ``Repetition`` via
/// ``XAD/init(repetition:)``.
///
/// XAD component layout (HL7 v2.5.1):
/// 1. Street Address (SAD) — sub-composite; ``XAD/streetAddress`` returns
///    SAD.1 (the actual street line).
/// 2. Other Designation (ST) → ``XAD/otherDesignation`` (apartment, unit).
/// 3. City (ST) → ``XAD/city``.
/// 4. State or Province (ST) → ``XAD/state``.
/// 5. Zip or Postal Code (ST) → ``XAD/zip``.
/// 6. Country (ID) → ``XAD/country``.
/// 7. Address Type (ID) → ``XAD/addressType`` (e.g. `"H"` home, `"B"` business).
///
/// Components 8–14 (other geographic designation, county/parish, census
/// tract, representation code, validity range, dates) are reachable via
/// ``XAD/field`` but not exposed as named accessors in v0.2.
public struct XAD: CompositeView {
    /// The components HL7 v2.5.1 PRINTS as required (`R`) in the XAD component
    /// table (none: every XAD component is optional there). Informational, for the canonical
    /// version only: the ``Validator`` does not read this list. It takes required
    /// components from ``DataTypeGrammarTable`` for the MESSAGE's own version, because
    /// they differ between versions (M14, ADR-017).
    public static let requiredComponents: [RequiredComponent] = []

    /// The underlying ``Field``. Use this when you need access to
    /// repetitions beyond the first, or to components not exposed as
    /// named accessors.
    public let field: Field

    /// Wrap an entire ``Field``. Accessors read from `.first` repetition.
    public init(field: Field) {
        self.field = field
    }

    /// XAD-1.1 — the street address line (first subcomponent of the SAD
    /// sub-composite).
    public var streetAddress: String? {
        componentValue(1)
    }

    /// XAD-2 other designation (apartment, unit, suite).
    public var otherDesignation: String? {
        componentValue(2)
    }

    /// XAD-3 city.
    public var city: String? {
        componentValue(3)
    }

    /// XAD-4 state or province.
    public var state: String? {
        componentValue(4)
    }

    /// XAD-5 zip or postal code.
    public var zip: String? {
        componentValue(5)
    }

    /// XAD-6 country.
    public var country: String? {
        componentValue(6)
    }

    /// XAD-7 address type (e.g. `"H"` home, `"B"` business, `"M"` mailing).
    public var addressType: String? {
        componentValue(7)
    }
}
