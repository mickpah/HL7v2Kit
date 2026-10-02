// Segment.swift
// Type-erased segment representation. Every segment in a parsed Message is
// either a typed segment (PID, MSH, OBR, ...) hydrated from the dictionary,
// or an UnknownSegment fallback (Z-segments, segments unknown to the loaded
// grammar).

import Foundation

/// Marker protocol implemented by all code-generated typed segment structs.
///
/// Conformers expose strongly-typed accessors for the named fields of a segment
/// (e.g. `PID.patientName`) while still preserving the raw `Field` array for
/// round-trip serialisation.
public protocol TypedSegment: Sendable, Equatable, Hashable {
    /// The 3-character segment identifier (e.g. "PID", "MSH").
    static var segmentID: String { get }

    /// The raw fields, indexed by 1-based v2 field number.
    /// Index 0 in the array is the segment ID; index 1 is field 1; and so on.
    /// (For MSH, index 1 is the field separator — see the parser docs.)
    var fields: [Field] { get }

    /// Construct from raw fields (used by the parser).
    init(fields: [Field])
}

extension TypedSegment {
    /// Access a field by 1-based v2 index. Returns nil if out of bounds.
    /// Generated typed accessors call this rather than indexing `fields`
    /// directly so the bounds policy lives in one place.
    public func field(_ index: Int) -> Field? {
        guard index >= 1, index < fields.count else { return nil }
        return fields[index]
    }

    /// Every repetition of the 1-based field `index`, each wrapped as a
    /// single-repetition ``Field``, in wire order. Empty when the field is
    /// absent. The generated `All` accessors call this.
    public func repetitions(_ index: Int) -> [Field] {
        guard let field = field(index) else { return [] }
        return field.repetitions.map { Field(repetitions: [$0]) }
    }
}

/// A parsed segment. One of:
///
/// - `.typed`: hydrated from the dictionary into a concrete `TypedSegment`.
/// - `.unknown`: a Z-segment or segment not present in the loaded grammar.
public enum Segment: Sendable, Equatable, Hashable {
    case typed(AnyTypedSegment)
    case unknown(UnknownSegment)

    /// The 3-character segment identifier.
    public var segmentID: String {
        switch self {
        case .typed(let s): return s.segmentID
        case .unknown(let s): return s.segmentID
        }
    }

    /// The raw fields, in document order.
    public var fields: [Field] {
        switch self {
        case .typed(let s): return s.fields
        case .unknown(let s): return s.fields
        }
    }

    /// Access a field by 1-based v2 index. Returns nil if out of bounds.
    public func field(_ index: Int) -> Field? {
        guard index >= 1, index < fields.count else { return nil }
        return fields[index]
    }
}

/// Existential wrapper around `TypedSegment`. Needed because Swift's
/// type-erased existentials don't support `Equatable`/`Hashable` directly
/// without help.
public struct AnyTypedSegment: Sendable, Equatable, Hashable {
    public let segmentID: String
    public let fields: [Field]

    public init<S: TypedSegment>(_ segment: S) {
        self.segmentID = S.segmentID
        self.fields = segment.fields
    }

    /// Attempt to cast back to a concrete typed segment.
    public func cast<S: TypedSegment>(to: S.Type) -> S? {
        guard segmentID == S.segmentID else { return nil }
        return S(fields: fields)
    }
}

/// Fallback segment representation for segments not present in the loaded
/// grammar (typically Z-segments like ZAU, ZPI, ZMH).
///
/// Fields are split structurally by the encoding characters but not validated
/// against any dictionary.
public struct UnknownSegment: Sendable, Equatable, Hashable {
    public let segmentID: String
    public let fields: [Field]

    public init(segmentID: String, fields: [Field]) {
        self.segmentID = segmentID
        self.fields = fields
    }
}
