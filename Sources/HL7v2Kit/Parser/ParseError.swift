// PORTABLE KERNEL — keep this file Foundation-free and byte/character-level.
// A future Rust/Go port translates this file directly. No NSRegularExpression,
// NSString, DateFormatter, CharacterSet, locale-aware ops, protocols, or
// generics in the parse path. `Data` only at the edges (to/from [UInt8]).
// See docs/design/architecture-decisions.md#adr-006-portable-core-boundary

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

    /// Whitespace tolerance at segment boundaries.
    public var lineTerminator: LineTerminatorPolicy

    /// If true, a populated MSH-12 from which no known `Version` resolves
    /// raises `ParseError.unsupportedVersion(found:)`, with VID.1 as
    /// rendered (trimmed; empty when VID.1 is empty). That covers an
    /// unmodelled version ID and a VID.1 that is empty, whitespace only or
    /// subdivided (`^AUS...`, `2.4&X`). If false (default), the parser falls
    /// back to v2.5.1 and the ``Validator`` reports
    /// ``IssueCode/versionNotRecognised(wireValue:)`` (warning) naming the
    /// fallback (ADR-018). An empty MSH-12 falls back to v2.5.1 regardless of
    /// this flag: MSH-12 is required, so the Validator's required-field check
    /// reports it.
    ///
    /// `.strict` sets this to `true`; `.default` keeps it `false`. v0.2-P3.
    public var rejectUnknownVersion: Bool

    public init(
        allowUnknownSegments: Bool = true,
        versionOverride: Version? = nil,
        lineTerminator: LineTerminatorPolicy = .lenient,
        rejectUnknownVersion: Bool = false
    ) {
        self.allowUnknownSegments = allowUnknownSegments
        self.versionOverride = versionOverride
        self.lineTerminator = lineTerminator
        self.rejectUnknownVersion = rejectUnknownVersion
    }

    public static let `default` = ParserOptions()
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
