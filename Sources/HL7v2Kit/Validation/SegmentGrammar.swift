// SegmentGrammar.swift
// Per-segment field-level grammar used by `Validator`. The
// `SegmentGrammar+Generated.swift` extension (emitted by `HL7v2KitCodegen`)
// populates the `v2_5_1` table from the same `Resources/schemas/` files
// that drive the typed-segment generation.

import Foundation

/// HL7 v2 field optionality. `R` required, `O` optional, `C` conditional,
/// `X` not supported, `B` backward-compatibility (deprecated but accepted).
public enum FieldOptionality: String, Sendable, Equatable, Hashable {
    case required = "R"
    case optional = "O"
    case conditional = "C"
    case notSupported = "X"
    case backwardCompat = "B"
}

/// Field repeatability. `single` for `1`, `multiple` for `*`.
public enum FieldRepeatability: Sendable, Equatable, Hashable {
    case single
    case multiple

    /// Parse the wire-form repeatability string (`"1"` → `.single`, `"*"` → `.multiple`).
    public init(wireValue raw: String) {
        switch raw {
        case "*": self = .multiple
        default:  self = .single
        }
    }
}

/// One field's grammar within a segment.
public struct FieldGrammar: Sendable, Equatable, Hashable {
    public let index: Int
    public let name: String
    public let dataType: String
    public let optionality: FieldOptionality
    public let repeatability: FieldRepeatability

    public init(
        index: Int,
        name: String,
        dataType: String,
        optionality: FieldOptionality,
        repeatability: FieldRepeatability
    ) {
        self.index = index
        self.name = name
        self.dataType = dataType
        self.optionality = optionality
        self.repeatability = repeatability
    }
}

/// Grammar for one segment within an HL7 v2.x version.
public struct SegmentGrammar: Sendable, Equatable, Hashable {
    public let segmentID: String
    public let version: String
    public let fields: [FieldGrammar]

    public init(segmentID: String, version: String, fields: [FieldGrammar]) {
        self.segmentID = segmentID
        self.version = version
        self.fields = fields
    }

    /// Look up a field grammar by 1-based v2 index. Returns nil if the
    /// segment doesn't define that field (i.e. the field is "excess" — see
    /// `ParserOptions.preserveExcessFields`).
    public func field(_ index: Int) -> FieldGrammar? {
        fields.first(where: { $0.index == index })
    }
}

/// Versioned lookup table mapping segment ID → `SegmentGrammar`.
/// Populated by the codegen-emitted `SegmentGrammar+Generated.swift`.
public enum SegmentGrammarTable {}
