// PORTABLE KERNEL — keep this file Foundation-free and byte/character-level.
// A future Rust/Go port translates this file directly. No NSRegularExpression,
// NSString, DateFormatter, CharacterSet, locale-aware ops, protocols, or
// generics in the parse path. `Data` only at the edges (to/from [UInt8]).
// See docs/design/ADR-006-portable-core-boundary.md

// ParseError.swift
// Public error type for the parser.

import Foundation

/// Errors thrown while parsing an HL7 v2 message.
///
/// - Note: **Open** enum per ADR-014 — may gain cases in a minor release as
///   new failure modes are surfaced; switch with `@unknown default`.
public enum ParseError: Error, Equatable, Sendable, CustomStringConvertible {
    case emptyInput
    case missingMSH
    case invalidMSH(reason: String)
    case unsupportedVersion(found: String)
    case unknownSegment(id: String, position: Int)
    case malformedField(segment: String, fieldIndex: Int, reason: String)
    case unsupportedCharacterEncoding(declared: String)
    case truncatedMessage(atByte: Int)

    public var description: String {
        switch self {
        case .emptyInput:
            return "Input is empty"
        case .missingMSH:
            return "Message does not start with MSH segment"
        case .invalidMSH(let reason):
            return "Invalid MSH segment: \(reason)"
        case .unsupportedVersion(let v):
            return "Unsupported HL7 version: '\(v)'"
        case .unknownSegment(let id, let position):
            return "Unknown segment '\(id)' at position \(position) (allowUnknownSegments=false)"
        case .malformedField(let seg, let idx, let reason):
            return "Malformed field \(seg)-\(idx): \(reason)"
        case .unsupportedCharacterEncoding(let enc):
            return "Unsupported declared character encoding: '\(enc)'"
        case .truncatedMessage(let byte):
            return "Message truncated at byte \(byte)"
        }
    }
}

/// Tunable parser behaviour.
public struct ParserOptions: Sendable {
    /// If true (default), segments not in the codegen-emitted typed-segment
    /// registry parse as `UnknownSegment` (Z-segment tolerance — see
    /// architecture invariant 5). If false, an unrecognised segment ID
    /// raises `ParseError.unknownSegment(id:position:)`.
    public var allowUnknownSegments: Bool

    /// HL7 version to use for typed segment hydration. If `nil`, taken from MSH-12.
    public var versionOverride: Version?

    /// If true (default), segment field counts beyond the dictionary are
    /// preserved as anonymous fields.
    ///
    /// **Deferred to v0.2.0.** v0.1.x has no per-segment field-count dictionary
    /// to check against (Task 6 work), so this flag is currently a no-op:
    /// excess fields are always preserved. The flag is kept on the v0.1.x API
    /// so consumers don't see a breaking change when the dictionary-driven
    /// behaviour lands.
    public var preserveExcessFields: Bool

    /// Whitespace tolerance at segment boundaries.
    public var lineTerminator: LineTerminatorPolicy

    /// If true, an MSH-12 value that doesn't map to a known `Version`
    /// raises `ParseError.unsupportedVersion(found:)`. If false (default),
    /// the parser silently falls back to v2.5.1 — useful for older
    /// fixtures with non-canonical MSH-12. Empty MSH-12 always falls
    /// back regardless of this flag; that's a Validator concern (MSH-12
    /// is required).
    ///
    /// `.strict` sets this to `true`; `.default` and `.lenient` keep it
    /// `false`. v0.2-P3.
    public var rejectUnknownVersion: Bool

    public init(
        allowUnknownSegments: Bool = true,
        versionOverride: Version? = nil,
        preserveExcessFields: Bool = true,
        lineTerminator: LineTerminatorPolicy = .lenient,
        rejectUnknownVersion: Bool = false
    ) {
        self.allowUnknownSegments = allowUnknownSegments
        self.versionOverride = versionOverride
        self.preserveExcessFields = preserveExcessFields
        self.lineTerminator = lineTerminator
        self.rejectUnknownVersion = rejectUnknownVersion
    }

    public static let `default` = ParserOptions()
    public static let lenient = ParserOptions(allowUnknownSegments: true, lineTerminator: .lenient)
    public static let strict = ParserOptions(
        allowUnknownSegments: false,
        lineTerminator: .strict,
        rejectUnknownVersion: true
    )
}

public enum LineTerminatorPolicy: Sendable, Equatable, Hashable {
    case strict          // \r only (per HL7 standard)
    case lenient         // any of \r, \n, \r\n accepted on parse
}
