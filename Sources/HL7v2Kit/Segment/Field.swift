// PORTABLE KERNEL — keep this file Foundation-free and byte/character-level.
// A future Rust/Go port translates this file directly. No NSRegularExpression,
// NSString, DateFormatter, CharacterSet, locale-aware ops, protocols, or
// generics in the parse path. `Data` only at the edges (to/from [UInt8]).
// See docs/design/architecture-decisions.md#adr-006-portable-core-boundary

// Field.swift
// The lossless AST node hierarchy for HL7 v2 field content.
//
// Every layer of nesting that exists on the wire is represented as a distinct
// node, even if most fields only use one layer. This is what makes round-trip
// byte-identity possible.
//
//   Field        — one or more Repetitions, separated by ~
//     Repetition — one or more Components, separated by ^
//       Component — one or more Subcomponents, separated by &
//         Subcomponent — the leaf scalar value (escape sequences decoded)

import Foundation

/// A single HL7 v2 field. May contain one or more repetitions.
public struct Field: Sendable, Equatable, Hashable {
    public let repetitions: [Repetition]

    public init(repetitions: [Repetition]) {
        self.repetitions = repetitions
    }

    /// Convenience: the first repetition (most fields are single-valued).
    public var first: Repetition? { repetitions.first }

    /// Convenience: returns the rendered scalar value if this field has a single
    /// repetition containing a single component containing a single subcomponent.
    /// Returns `nil` for structured fields — use the typed accessors there.
    public var stringValue: String? { first?.stringValue }
}

/// One repetition of a field. Contains one or more components.
public struct Repetition: Sendable, Equatable, Hashable {
    public let components: [Component]

    public init(components: [Component]) {
        self.components = components
    }

    /// Convenience: returns the rendered value if this repetition is a single
    /// scalar (one component, one subcomponent).
    public var stringValue: String? {
        guard components.count == 1 else { return nil }
        return components[0].stringValue
    }
}

/// One component. Contains one or more subcomponents.
public struct Component: Sendable, Equatable, Hashable {
    public let subcomponents: [Subcomponent]

    public init(subcomponents: [Subcomponent]) {
        self.subcomponents = subcomponents
    }

    /// Convenience: returns the value if this component has a single subcomponent.
    public var stringValue: String? {
        guard subcomponents.count == 1 else { return nil }
        return subcomponents[0].value
    }
}

/// A leaf scalar value. The string is stored decoded — any escape sequences
/// (`\F\`, `\S\`, etc.) in the original wire bytes have been resolved. A parsed
/// value is written back as it was read; a value built in code is encoded
/// (see <doc:EscapeSequences>).
public struct Subcomponent: Sendable, Equatable, Hashable {
    public let value: String

    /// The wire text a parsed value was read from, kept only when it holds the escape
    /// character, so the serialiser and the escape and length checks see escapes as they
    /// were sent (#13). Not part of equality: values that decode alike are equal.
    let wire: String?

    public init(_ value: String) {
        self.value = value
        self.wire = nil
    }

    init(_ value: String, wire: String?) {
        self.value = value
        self.wire = wire
    }

    // `wire` takes no part (see its doc).
    public static func == (lhs: Subcomponent, rhs: Subcomponent) -> Bool {
        lhs.value == rhs.value
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

// MARK: - Convenience constructors

extension Field {
    /// Build a single-value field from a plain string.
    public static func scalar(_ value: String) -> Field {
        Field(repetitions: [.scalar(value)])
    }

    /// Build a field from an array of component strings (single repetition).
    /// Example: `Field.components(["Smith", "John", "A"])` for an XPN.
    public static func components(_ values: [String]) -> Field {
        Field(repetitions: [.components(values)])
    }
}

extension Repetition {
    public static func scalar(_ value: String) -> Repetition {
        Repetition(components: [.scalar(value)])
    }

    public static func components(_ values: [String]) -> Repetition {
        Repetition(components: values.map { .scalar($0) })
    }
}

extension Component {
    public static func scalar(_ value: String) -> Component {
        Component(subcomponents: [Subcomponent(value)])
    }
}
