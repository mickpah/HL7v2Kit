// CE.swift
// Coded Element composite (HL7 v2.5.1 §2.A.13).
//
// Value-type view over a Field that exposes named accessors for each
// CE component. Round-trip byte-identity is preserved because the
// struct doesn't own the data — the segment still owns the underlying
// `Field`. v0.3-C2.

/// Coded Element (CE) composite.
///
/// Exposed by typed segment accessors that wrap CE-typed fields. CE is
/// the most-frequent composite in HL7 v2.5.1 typed segments — race,
/// language, marital status, religion, allergens, observation
/// identifier, observation method, and many ORC / OBR coded slots all
/// use this layout.
///
/// Reads from the **first repetition** of the underlying field; for
/// multi-repetition fields (e.g. PID-10 race, PID-22 ethnic group,
/// PID-26 citizenship) use ``CE/field`` to walk the rest, or wrap an
/// individual ``Repetition`` via ``CE/init(repetition:)``.
///
/// CE component layout (HL7 v2.5.1):
/// 1. Identifier (ID) → ``CE/identifier``. The primary coded value (e.g.
///    `"L1"` for human species, `"2106-3"` for "White" race).
/// 2. Text (ST) → ``CE/text``. Human-readable description of CE-1.
/// 3. Name of Coding System (ID) → ``CE/nameOfCodingSystem`` (e.g.
///    `"HL70447"`).
/// 4. Alternate Identifier (ID) → ``CE/altIdentifier``.
/// 5. Alternate Text (ST) → ``CE/altText``.
/// 6. Name of Alternate Coding System (ID) → ``CE/nameOfAltCodingSystem``.
public struct CE: CompositeView {
    /// The components HL7 v2.5.1 PRINTS as required (`R`) in the CE component
    /// table (none: every CE component is optional there). Informational, for the canonical
    /// version only: the ``Validator`` does not read this list. It takes required
    /// components from ``DataTypeGrammarTable`` for the MESSAGE's own version, because
    /// they differ between versions (M14, ADR-017).
    public static let requiredComponents: [RequiredComponent] = []

    /// The underlying ``Field``. Use this when you need access to
    /// repetitions beyond the first.
    public let field: Field

    /// Wrap an entire ``Field``. Accessors read from `.first` repetition.
    public init(field: Field) {
        self.field = field
    }

    /// CE-1 identifier (the primary coded value).
    public var identifier: String? {
        componentValue(1)
    }

    /// CE-2 text — the human-readable description of CE-1.
    public var text: String? {
        componentValue(2)
    }

    /// CE-3 name of coding system (e.g. `"HL70005"` for the HL7 race
    /// table).
    public var nameOfCodingSystem: String? {
        componentValue(3)
    }

    /// CE-4 alternate identifier.
    public var altIdentifier: String? {
        componentValue(4)
    }

    /// CE-5 alternate text — human-readable description of CE-4.
    public var altText: String? {
        componentValue(5)
    }

    /// CE-6 name of alternate coding system.
    public var nameOfAltCodingSystem: String? {
        componentValue(6)
    }
}
