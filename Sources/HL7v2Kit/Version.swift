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
}
