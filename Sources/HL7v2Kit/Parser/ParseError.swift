// PORTABLE KERNEL — keep this file Foundation-free and byte/character-level.
// A future Rust/Go port translates this file directly. No NSRegularExpression,
// NSString, DateFormatter, CharacterSet, locale-aware ops, protocols, or
// generics in the parse path. `Data` only at the edges (to/from [UInt8]).
// See docs/design/ADR-006-portable-core-boundary.md

// ParseError.swift
// Public error type for the parser.

import Foundation

public enum ParseError: Error, Equatable, Sendable, CustomStringConvertible {
    case emptyInput
    case missingMSH
    case invalidMSH(reason: String)
    case unsupportedVersion(found: String)
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
    /// If true (default), segments not in the loaded grammar parse as
    /// `UnknownSegment`. If false, an error is thrown.
    public var allowUnknownSegments: Bool

    /// HL7 version to use for typed segment hydration. If `nil`, taken from MSH-12.
    public var versionOverride: Version?

    /// If true (default), segment field counts beyond the dictionary are
    /// preserved as anonymous fields.
    public var preserveExcessFields: Bool

    /// Whitespace tolerance at segment boundaries.
    public var lineTerminator: LineTerminatorPolicy

    public init(
        allowUnknownSegments: Bool = true,
        versionOverride: Version? = nil,
        preserveExcessFields: Bool = true,
        lineTerminator: LineTerminatorPolicy = .lenient
    ) {
        self.allowUnknownSegments = allowUnknownSegments
        self.versionOverride = versionOverride
        self.preserveExcessFields = preserveExcessFields
        self.lineTerminator = lineTerminator
    }

    public static let `default` = ParserOptions()
    public static let lenient = ParserOptions(allowUnknownSegments: true, lineTerminator: .lenient)
    public static let strict = ParserOptions(allowUnknownSegments: false, lineTerminator: .strict)
}

public enum LineTerminatorPolicy: Sendable, Equatable, Hashable {
    case strict          // \r only (per HL7 standard)
    case lenient         // any of \r, \n, \r\n accepted on parse
}
