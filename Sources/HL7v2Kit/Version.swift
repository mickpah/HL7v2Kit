// PORTABLE KERNEL — keep this file Foundation-free and byte/character-level.
// A future Rust/Go port translates this file directly. No NSRegularExpression,
// NSString, DateFormatter, CharacterSet, locale-aware ops, protocols, or
// generics in the parse path. `Data` only at the edges (to/from [UInt8]).
// See docs/design/architecture-decisions.md#adr-006-portable-core-boundary

// Version.swift
// Supported HL7 v2 dialects. The AST itself is version-agnostic; this enum
// drives dictionary selection for the validator and typed segment accessors.

/// HL7 v2 message versions supported by HL7v2Kit.
///
/// The raw value matches the on-wire string found in `MSH-12`.
///
/// - Note: This is an **open** enum per the v1.0 API evolution policy
///   (ADR-014): it may gain cases in a minor release as HL7 publishes
///   further versions. Exhaustive `switch` over it must include
///   `@unknown default`.
public enum Version: String, Sendable, CaseIterable, Equatable, Hashable {
    case v2_3   = "2.3"
    case v2_3_1 = "2.3.1"
    case v2_4   = "2.4"
    case v2_5_1 = "2.5.1"
    case v2_6   = "2.6"
    /// HL7 v2.7.1, modelled from its own text (plan P10, ADR-018).
    case v2_7_1 = "2.7.1"
    /// HL7 v2.7. HL7v2Kit has no v2.7 text and validates a `2.7` message against
    /// the v2.7.1 grammar (``grammarVersion``; owner decision G11, ADR-018).
    case v2_7   = "2.7"
    case v2_8_2 = "2.8.2"
    case v2_8   = "2.8"

    /// Parse a wire-format MSH-12 string into a `Version`, if recognised.
    public init?(wireValue: String) {
        // Lenient on surrounding whitespace, strict on the canonical form.
        self.init(rawValue: Version.trimmingWhitespace(wireValue))
    }

    /// The version whose segment grammar, code tables and datatype grammar
    /// the ``Validator`` applies to a message declaring this version.
    ///
    /// Every case maps to itself except ``v2_8`` and ``v2_7``: HL7v2Kit has no
    /// v2.8 or v2.7 text and validates a `2.8` message against the v2.8.2
    /// grammar and a `2.7` message against the v2.7.1 grammar, the nearest
    /// modelled release in each case, reporting the substitution as
    /// ``IssueCode/versionGrammarSubstituted(declared:validatedAs:)`` (ADR-018).
    public var grammarVersion: Version {
        switch self {
        case .v2_8: return .v2_8_2
        case .v2_7: return .v2_7_1
        default:    return self
        }
    }
}

extension Version {
    /// How an MSH-12 field names the message's version (ADR-018).
    enum MSH12Reading: Equatable {
        /// MSH-12 is absent or carries no content at all. MSH-12 is
        /// required, so the Validator's required-field check reports it.
        case empty
        /// VID.1 names a modelled version.
        case recognised(Version)
        /// MSH-12 carries content but no modelled version resolves from
        /// VID.1. The payload is VID.1 as rendered (subcomponents joined by
        /// the message's subcomponent separator, trimmed); it is empty when
        /// VID.1 is empty or whitespace only.
        case unresolved(vid1: String)
    }

    /// Read the version from an MSH-12 field. MSH-12 is a VID composite
    /// (`2.4^AUS&Australia&ISO3166_1^...`); only VID.1 of the first
    /// repetition names the version (HL7 v2.8.2 Chapter 2A, VID; ADR-018).
    static func reading(msh12 field: Field?, subcomponentSeparator: Character) -> MSH12Reading {
        let populated = field?.repetitions.contains { repetition in
            repetition.components.contains { component in
                component.subcomponents.contains { !$0.value.isEmpty }
            }
        } ?? false
        guard let field, populated else { return .empty }
        let vid1 = field.first?.components.first?.subcomponents.map(\.value) ?? []
        let rendered = trimmingWhitespace(vid1.joined(separator: String(subcomponentSeparator)))
        if vid1.count == 1, let version = Version(rawValue: rendered) {
            return .recognised(version)
        }
        return .unresolved(vid1: rendered)
    }

    /// Character-level whitespace trim; keeps this file Foundation-free (ADR-006).
    private static func trimmingWhitespace(_ value: String) -> String {
        var trimmed = Substring(value)
        while trimmed.first?.isWhitespace == true { trimmed.removeFirst() }
        while trimmed.last?.isWhitespace == true { trimmed.removeLast() }
        return String(trimmed)
    }
}
