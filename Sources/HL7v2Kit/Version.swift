// PORTABLE KERNEL — keep this file Foundation-free and byte/character-level.
// A future Rust/Go port translates this file directly. No NSRegularExpression,
// NSString, DateFormatter, CharacterSet, locale-aware ops, protocols, or
// generics in the parse path. `Data` only at the edges (to/from [UInt8]).
// See docs/design/ADR-006-portable-core-boundary.md

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
    case v2_8_2 = "2.8.2"
    case v2_8   = "2.8"

    /// Parse a wire-format MSH-12 string into a `Version`, if recognised.
    public init?(wireValue: String) {
        // HL7 sometimes ships variants like "2.5.1\\" or trailing whitespace;
        // be lenient on input but strict on the canonical form.
        let trimmed = wireValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(rawValue: trimmed)
    }

    /// The version whose segment grammar, code tables and datatype grammar
    /// the ``Validator`` applies to a message declaring this version.
    ///
    /// Every case maps to itself except ``v2_8``: HL7v2Kit has no v2.8 text
    /// and validates a `2.8` message against the v2.8.2 grammar, the nearest
    /// modelled release, reporting the substitution as
    /// ``IssueCode/versionGrammarSubstituted(declared:validatedAs:)`` (ADR-018).
    public var grammarVersion: Version {
        switch self {
        case .v2_8: return .v2_8_2
        default:    return self
        }
    }
}

extension Version {
    /// The version ID (VID.1) carried by an MSH-12 field, trimmed, or `nil`
    /// when MSH-12 is absent or its first component is empty. MSH-12 is a
    /// VID composite (`2.4^AUS&Australia&ISO3166_1^...`); only VID.1 names
    /// the version (HL7 v2.8.2 Chapter 2A, VID; ADR-018).
    static func versionID(inMSH12 field: Field?) -> String? {
        guard let raw = field?.first?.components.first?.stringValue else { return nil }
        // Character-level trim keeps this file Foundation-free (ADR-006).
        var trimmed = Substring(raw)
        while trimmed.first?.isWhitespace == true { trimmed.removeFirst() }
        while trimmed.last?.isWhitespace == true { trimmed.removeLast() }
        return trimmed.isEmpty ? nil : String(trimmed)
    }
}
