// PORTABLE KERNEL — keep this file Foundation-free and byte/character-level.
// A future Rust/Go port translates this file directly. No NSRegularExpression,
// NSString, DateFormatter, CharacterSet, locale-aware ops, protocols, or
// generics in the parse path. `Data` only at the edges (to/from [UInt8]).
// See docs/design/ADR-006-portable-core-boundary.md

// EncodingCharacters.swift
// The five v2 encoding characters from MSH-1 (field separator) and MSH-2
// (component, repetition, escape, subcomponent). The default `|^~\&` is used
// by virtually every AU sender, but the standard allows custom delimiters
// and we preserve them through round-trip.

import Foundation

/// The five encoding characters used to delimit fields, components, repetitions,
/// escape sequences, and subcomponents in an HL7 v2 message.
///
/// Default value matches the HL7 standard recommendation `|^~\&`.
public struct EncodingCharacters: Sendable, Equatable, Hashable {
    public let fieldSeparator: Character        // MSH-1; default "|"
    public let componentSeparator: Character    // MSH-2[0]; default "^"
    public let repetitionSeparator: Character   // MSH-2[1]; default "~"
    public let escapeCharacter: Character       // MSH-2[2]; default "\"
    public let subcomponentSeparator: Character // MSH-2[3]; default "&"

    public init(
        fieldSeparator: Character,
        componentSeparator: Character,
        repetitionSeparator: Character,
        escapeCharacter: Character,
        subcomponentSeparator: Character
    ) {
        self.fieldSeparator = fieldSeparator
        self.componentSeparator = componentSeparator
        self.repetitionSeparator = repetitionSeparator
        self.escapeCharacter = escapeCharacter
        self.subcomponentSeparator = subcomponentSeparator
    }

    /// The standard HL7 default: `|^~\&`
    public static let `default` = EncodingCharacters(
        fieldSeparator: "|",
        componentSeparator: "^",
        repetitionSeparator: "~",
        escapeCharacter: "\\",
        subcomponentSeparator: "&"
    )

    /// The four-character MSH-2 string (component, repetition, escape, subcomponent)
    /// in the order required by the HL7 standard.
    public var msh2String: String {
        String([componentSeparator, repetitionSeparator, escapeCharacter, subcomponentSeparator])
    }

    /// Returns true if all five characters are distinct (required by the standard).
    public var isValid: Bool {
        let set: Set<Character> = [
            fieldSeparator, componentSeparator, repetitionSeparator,
            escapeCharacter, subcomponentSeparator,
        ]
        return set.count == 5
    }
}
