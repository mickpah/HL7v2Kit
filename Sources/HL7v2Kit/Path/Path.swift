// PORTABLE KERNEL — keep this file Foundation-free and byte/character-level.
// A future Rust/Go port translates this file directly. No NSRegularExpression,
// NSString, DateFormatter, CharacterSet, locale-aware ops, protocols, or
// generics in the parse path. `Data` only at the edges (to/from [UInt8]).
// See docs/design/architecture-decisions.md#adr-006-portable-core-boundary

// Path.swift
// Parses HL7 v2 path strings into a structural representation.
//
// Grammar (P00 S2-1 adds the bracketed repetition and the wildcard):
//
//   path        := segment-ref "-" field-spec
//   segment-ref := SEGMENT-ID ( "[" index "]" )?
//   field-spec  := INT ( "[" index "]" | "~" INT )? ( "." INT ( "." INT )? )?
//   index       := INT (1 or more) | "*"
//   SEGMENT-ID  := 2 to 4 letters/digits (uppercase by convention)
//
// "~" INT is the native repetition; "[" index "]" after the field is the alternative
// syntax. A path uses one or the other. "*" means every occurrence or every repetition.
//
// Examples:
//   "PID-5"            → segment=PID, field=5
//   "PID-5.1"          → segment=PID, field=5, component=1
//   "PID-5.1.2"        → segment=PID, field=5, component=1, subcomponent=2
//   "PID-3~2"          → segment=PID, field=3, repetition=2
//   "PID-3~2.4"        → segment=PID, field=3, repetition=2, component=4
//   "PID-3[2].1"       → segment=PID, field=3, repetition=2, component=1
//   "OBX[*]-5[*]"      → every OBX, field 5, every repetition
//   "OBX[2]-5"         → segment=OBX (2nd), field=5
//   "ZAU-3"            → segment=ZAU, field=3

import Foundation

/// A parsed, structurally validated HL7 v2 path.
public struct Path: Sendable, Equatable, Hashable {
    /// The 3-character segment identifier (e.g. "PID").
    public let segmentID: String

    /// 1-based index when multiple segments of the same type exist.
    /// `nil` means "the first occurrence" (default).
    public let segmentIndex: Int?

    /// 1-based field index. Always present.
    public let field: Int

    /// 1-based repetition. `nil` means "the first repetition" (default).
    public let repetition: Int?

    /// 1-based component. `nil` means "the whole field/repetition".
    public let component: Int?

    /// 1-based subcomponent. `nil` means "the whole component".
    public let subcomponent: Int?

    /// True when the path names every occurrence of the segment (`OBX[*]-5`). Read such a
    /// path with ``Message/values(at:)``; the path subscript returns `nil` for it.
    public let segmentWildcard: Bool

    /// True when the path names every repetition of the field (`PID-3[*].1`), written in
    /// the alternative syntax only. Read it with ``Message/values(at:)``.
    public let repetitionWildcard: Bool

    public init(
        segmentID: String,
        segmentIndex: Int? = nil,
        field: Int,
        repetition: Int? = nil,
        component: Int? = nil,
        subcomponent: Int? = nil
    ) {
        self.init(segmentID: segmentID, segmentIndex: segmentIndex, segmentWildcard: false,
                  field: field, repetition: repetition, repetitionWildcard: false,
                  component: component, subcomponent: subcomponent)
    }

    private init(
        segmentID: String,
        segmentIndex: Int?,
        segmentWildcard: Bool,
        field: Int,
        repetition: Int?,
        repetitionWildcard: Bool,
        component: Int?,
        subcomponent: Int?
    ) {
        self.segmentID = segmentID
        self.segmentIndex = segmentIndex
        self.segmentWildcard = segmentWildcard
        self.field = field
        self.repetition = repetition
        self.repetitionWildcard = repetitionWildcard
        self.component = component
        self.subcomponent = subcomponent
    }

    /// Parse a path string. Throws on malformed input.
    public init(_ string: String) throws {
        let parsed = try Path.parse(string)
        self = parsed
    }

    // MARK: - Parser

    private static func parse(_ input: String) throws -> Path {
        guard !input.isEmpty else {
            throw PathError.malformed(input: input, position: 0)
        }

        var scanner = Scanner(input: input)

        // Segment ID: 3 alphanumeric characters.
        guard let segID = scanner.takeWhile({ $0.isLetter || $0.isNumber }),
              segID.count >= 2, segID.count <= 4
        else {
            throw PathError.invalidSegmentID(String(input.prefix(4)))
        }

        // Optional [N] or [*] segment occurrence (the same in both syntaxes).
        var segIndex: Int? = nil
        var segWildcard = false
        if scanner.peek() == "[" {
            scanner.advance()
            segIndex = try bracketIndex(&scanner, input: input)
            segWildcard = segIndex == nil
        }

        // "-" separator.
        guard scanner.peek() == "-" else {
            throw PathError.malformed(input: input, position: scanner.position)
        }
        scanner.advance()

        // Field number.
        guard let fieldStr = scanner.takeWhile({ $0.isNumber }),
              let field = Int(fieldStr), field >= 1
        else {
            throw PathError.invalidIndex(input)
        }

        // Optional repetition: "[N]" or "[*]" (the alternative syntax) or "~N" (native).
        var repetition: Int? = nil
        var repWildcard = false
        if scanner.peek() == "[" {
            scanner.advance()
            repetition = try bracketIndex(&scanner, input: input)
            repWildcard = repetition == nil
        } else if scanner.peek() == "~" {
            scanner.advance()
            guard let repStr = scanner.takeWhile({ $0.isNumber }),
                  let r = Int(repStr), r >= 1
            else {
                throw PathError.malformed(input: input, position: scanner.position)
            }
            repetition = r
        }

        // Optional .component.
        var component: Int? = nil
        if scanner.peek() == "." {
            scanner.advance()
            guard let compStr = scanner.takeWhile({ $0.isNumber }),
                  let c = Int(compStr), c >= 1
            else {
                throw PathError.malformed(input: input, position: scanner.position)
            }
            component = c
        }

        // Optional .subcomponent.
        var subcomponent: Int? = nil
        if scanner.peek() == "." {
            scanner.advance()
            guard let subStr = scanner.takeWhile({ $0.isNumber }),
                  let s = Int(subStr), s >= 1
            else {
                throw PathError.malformed(input: input, position: scanner.position)
            }
            subcomponent = s
        }

        guard scanner.isAtEnd else {
            throw PathError.malformed(input: input, position: scanner.position)
        }

        return Path(
            segmentID: segID,
            segmentIndex: segIndex,
            segmentWildcard: segWildcard,
            field: field,
            repetition: repetition,
            repetitionWildcard: repWildcard,
            component: component,
            subcomponent: subcomponent
        )
    }

    /// Reads `N]` or `*]` after a consumed `[`. Returns the index, or `nil` for `*`.
    private static func bracketIndex(_ scanner: inout Scanner, input: String) throws -> Int? {
        var index: Int? = nil
        if scanner.peek() == "*" {
            scanner.advance()
        } else {
            guard let digits = scanner.takeWhile({ $0.isNumber }), let n = Int(digits), n >= 1 else {
                throw PathError.malformed(input: input, position: scanner.position)
            }
            index = n
        }
        guard scanner.peek() == "]" else {
            throw PathError.malformed(input: input, position: scanner.position)
        }
        scanner.advance()
        return index
    }
}

// MARK: - PathError

/// Errors thrown while parsing an HL7 path expression.
///
/// - Note: **Open** enum per ADR-014 — may gain cases in a minor release;
///   switch with `@unknown default`.
public enum PathError: Error, Equatable, Sendable, CustomStringConvertible {
    case malformed(input: String, position: Int)
    case invalidSegmentID(String)
    case invalidIndex(String)

    public var description: String {
        switch self {
        case .malformed(let input, let pos):
            return "Malformed path '\(input)' at position \(pos)"
        case .invalidSegmentID(let id):
            return "Invalid segment ID '\(id)'"
        case .invalidIndex(let s):
            return "Invalid index in path '\(s)'"
        }
    }
}

// MARK: - Internal scanner

private struct Scanner {
    let chars: [Character]
    var position: Int = 0

    init(input: String) {
        self.chars = Array(input)
    }

    var isAtEnd: Bool { position >= chars.count }

    func peek() -> Character? {
        guard position < chars.count else { return nil }
        return chars[position]
    }

    mutating func advance() {
        position += 1
    }

    mutating func takeWhile(_ predicate: (Character) -> Bool) -> String? {
        let start = position
        while position < chars.count, predicate(chars[position]) {
            position += 1
        }
        guard position > start else { return nil }
        return String(chars[start..<position])
    }
}
