// SegmentGrammar.swift
// Per-segment field-level grammar used by `Validator`. The
// `SegmentGrammar+Generated.swift` extension (emitted by `HL7v2KitCodegen`)
// populates the `v2_5_1` table from the same `Resources/schemas/` files
// that drive the typed-segment generation.

import Foundation

/// HL7 v2 field optionality. `R` required, `O` optional, `C` conditional,
/// `X` not supported, `B` backward-compatibility (deprecated but accepted),
/// `W` withdrawn (removed from the standard — the sequence position is
/// retained but the field carries no meaning). `W` first appears in the
/// v2.6 attribute tables (e.g. the DG1 DRG/outlier fields moved to the DRG
/// segment); it is distinct from `B`, which is retained for compatibility.
public enum FieldOptionality: String, Sendable, Equatable, Hashable {
    case required = "R"
    case optional = "O"
    case conditional = "C"
    case notSupported = "X"
    case backwardCompat = "B"
    case withdrawn = "W"
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
    /// Predicate that controls when a `.conditional` field becomes required.
    /// Same-segment only in v0.2.
    ///
    /// Grammar: `<segmentID>-<index> <predicate>` where `<predicate>` is one
    /// of `populated`, `empty`, `= <value>`, or `!= <value>`. Examples:
    /// `"PID-35 populated"`, `"ORC-1 = NW"`. Cross-segment references or
    /// malformed predicates evaluate to "condition does not trigger" — the
    /// field is treated as optional. `nil` for fields with no condition;
    /// `.conditional` fields with no condition also fall through as
    /// effectively `.optional`. v0.2-V1.
    public let condition: String?

    public init(
        index: Int,
        name: String,
        dataType: String,
        optionality: FieldOptionality,
        repeatability: FieldRepeatability,
        condition: String? = nil
    ) {
        self.index = index
        self.name = name
        self.dataType = dataType
        self.optionality = optionality
        self.repeatability = repeatability
        self.condition = condition
    }
}

/// The group boundary a `SegmentCardinalityRule` scopes its check to.
/// v0.11-S3 (ADR-010 Extension 2) initial cases; extend when a rule
/// surfaces that needs a different boundary. Internal-facing — external
/// consumers see the resolved `ValidationIssue` only.
enum GroupScope: String, Sendable, Equatable, Hashable {
    /// ORC-headed group: back-walk to nearest ORC, forward-walk to next
    /// ORC. Matches the ADR-008 `Message.associatedSegment` semantic.
    case orcObxGroup
    /// OBR-headed group: back-walk to nearest OBR, forward-walk to next
    /// OBR OR ORC (OBR sub-groups can't cross ORC boundaries). Used for
    /// HL7au:000008-shape rules.
    case obrObxGroup
    /// Entire message as one degenerate group.
    case messageWide
}

/// A group-scope cardinality rule attached to a `SegmentGrammar`.
/// v0.11-S3 (ADR-010 Extension 2). Evaluates the `predicate` (a v0.7
/// DSL atom) against each candidate segment in the resolved group; if
/// the count of matches is below `minCount`, fires
/// `.segmentCardinalityBelowMinimum`; if it is above `maxCount` (when
/// set), fires `.segmentCardinalityAboveMaximum`.
///
/// Convention: the rule attaches to the grammar of the head segment
/// for its scope (`orcObxGroup` → ORC, `obrObxGroup` → OBR,
/// `messageWide` → MSH). The group-scan pass in `Validator.validate`
/// deduplicates by (scope, groupHeadIndex) so a rule fires once per
/// distinct group.
///
/// `applicableWhen` is an optional message-context predicate (v0.7
/// DSL, evaluated against the message). When set, the whole rule is
/// gated: if `applicableWhen` is false the rule is skipped entirely
/// for this message. Mirrors ADR-009's `ComponentValueSet.condition`
/// pattern; lets a spec-narrowing like HL7au:000008 fire only on
/// Results / Referrals messages without polluting other traffic.
struct SegmentCardinalityRule: Sendable, Equatable, Hashable {
    /// Segment ID being counted (used for the fired issue's user-facing
    /// segment identifier). The `predicate` will naturally filter to
    /// segments of this ID via same-segment field-ref semantics (e.g.
    /// `OBX-3.3 = AUSPDI` only resolves against OBX segments; other
    /// segments fail safe to false). Setting this field explicitly
    /// avoids parsing the predicate to reconstruct the target.
    ///
    /// A trailing `*` makes it a prefix pattern: `"Z*"` counts every
    /// segment whose ID begins with `Z` — needed for HL7au:000023.1's
    /// blanket Z-segment prohibition, where no single ID exists to
    /// count. M6-B-2.
    let countedSegmentID: String
    let scope: GroupScope
    let minCount: Int

    /// Upper bound on matches. `nil` (default) means unbounded — the
    /// pre-M6 behaviour. `0` expresses a prohibition: ADRM-2021's
    /// HL7au:000023 ("the NTE segment must NOT be used") and
    /// HL7au:000021 ("data type TX must NOT be used in OBX-2") are both
    /// "count of matching segments must be zero" rules, which the
    /// minimum-only model of v0.11 could not state. M6-A-3.
    let maxCount: Int?

    /// Predicate a candidate must satisfy to be counted. An empty
    /// string counts **every** segment whose ID is `countedSegmentID`
    /// — needed for whole-segment prohibitions like HL7au:000023,
    /// where there is no field to test.
    let predicate: String
    let applicableWhen: String?
    let specCitation: String?

    init(
        countedSegmentID: String,
        scope: GroupScope,
        minCount: Int,
        maxCount: Int? = nil,
        predicate: String,
        applicableWhen: String? = nil,
        specCitation: String? = nil
    ) {
        self.countedSegmentID = countedSegmentID
        self.scope = scope
        self.minCount = minCount
        self.maxCount = maxCount
        self.predicate = predicate
        self.applicableWhen = applicableWhen
        self.specCitation = specCitation
    }
}

/// Grammar for one segment within an HL7 v2.x version.
public struct SegmentGrammar: Sendable, Equatable, Hashable {
    public let segmentID: String
    public let version: String
    public let fields: [FieldGrammar]

    /// Group-scope cardinality rules that fire when this segment's
    /// grammar is being applied. v0.11-S3 (ADR-010 Extension 2). Empty
    /// by default; codegen emits the array from the schema JSON's
    /// optional `segmentCardinalityRules` key. Locale-specific rules
    /// live on `Profile.cardinalityExtensions` instead (see ADR-007).
    let segmentCardinalityRules: [SegmentCardinalityRule]

    public init(segmentID: String, version: String, fields: [FieldGrammar]) {
        self.segmentID = segmentID
        self.version = version
        self.fields = fields
        self.segmentCardinalityRules = []
    }

    /// Internal initializer that carries `segmentCardinalityRules`. Used
    /// by codegen-emitted tables. The public initializer defaults the
    /// axis to empty so external callers (and existing tests) don't
    /// need to know about it.
    init(
        segmentID: String,
        version: String,
        fields: [FieldGrammar],
        segmentCardinalityRules: [SegmentCardinalityRule]
    ) {
        self.segmentID = segmentID
        self.version = version
        self.fields = fields
        self.segmentCardinalityRules = segmentCardinalityRules
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
