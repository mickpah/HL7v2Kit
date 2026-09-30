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

    /// Predicate that controls when a field is PROHIBITED: if the field
    /// is populated while this predicate is true, the Validator fires
    /// `.conditionalFieldProhibited`. The inverse of `condition` —
    /// "may only be valued if X is valued" encodes as
    /// `prohibitedWhen: "X empty"`. Encoding it as a required-when
    /// condition would wrongly demand the field whenever its subject is
    /// present (the PRT-6/PRT-7 lesson,
    /// `conditional-completeness-audit.md`). Same fail-safe semantics
    /// as `condition`: an unresolvable predicate never fires. M8-D.
    public let prohibitedWhen: String?

    /// `true` when the spec's SEQ cell for this field is `1-n`: the field
    /// *position* recurs, so every `|`-separated position from `index`
    /// upward is this same data element (RDT-1 Column Value, ADD-1
    /// Addendum Continuation Pointer). This is not `~`-repetition — the
    /// spec's RP cell is blank, so `repeatability` stays `.single` and a
    /// `~` inside any column is a cardinality error. The Validator applies
    /// this grammar to each populated column; column 1 keeps the row's
    /// optionality, later columns are individually optional (the spec
    /// bounds the count, never a minimum). v3.3 Track B.
    public let variableColumns: Bool

    /// The HL7 code table this coded field draws from, as the spec's
    /// `TBL#` column prints it (`"0074"`), or `nil` for uncoded fields.
    /// Resolve it with ``HL7TableRegistry/table(_:version:)``. Only an
    /// `ID`-typed field whose table ``HL7Table/isClosed`` is enforced;
    /// `IS` fields and open tables are informational (req #4). M6-O6.
    public let table: String?
    /// The LEN cell the version's attribute table prints, verbatim, or `nil`
    /// when the table prints none. Before v2.7 it is a stated maximum the
    /// spec itself calls "not of conceptual importance"; from v2.7 it is a
    /// normative range with truncation semantics (`"2..2"`, `"32="`, `"250#"`).
    /// Recorded for reference and never enforced (M25).
    public let length: String?
    /// `true` when this field's own prose leaves its bound ``table`` open, whatever the
    /// table's own kind: it cites the table "for suggested values", calls it User-defined,
    /// or says the value set can be extended. Some HL7 tables are cited that way by one field
    /// and "for valid values" by another (v2.4 PID-31 against PID-24 for Table 0136), so
    /// openness is per field as well as per table. The Validator's closed-table check skips
    /// a field with `tableOpen` set; other fields bound to the same table are unaffected.
    /// The schema entry carries the citation (`tableOpenCitation`). `false` by default. P2-15.
    public let tableOpen: Bool
    /// Severity of the `.conditionalFieldProhibited` issue raised when
    /// this field is populated while `prohibitedWhen` holds. `.error`
    /// (the default) for normative text ("may only be", "not
    /// permitted"); `.warning` for SHOULD-level or "not applicable"
    /// text, so advisory spec wording never produces an error (req #4).
    /// Ignored when `prohibitedWhen` is `nil`. P4.
    public let prohibitedSeverity: IssueSeverity
    /// Further prohibitions on this field beyond ``prohibitedWhen``, each with its own
    /// severity. The Validator evaluates every rule exactly as it does `prohibitedWhen` and
    /// raises one `.conditionalFieldProhibited` per rule that holds, so a field the spec
    /// restricts twice (v2.5.1 / v2.6 RXR-6: an error when RXR-2 is empty, a warning when
    /// RXR-2 is coded from Table 0163) reports each rule on its own. Not set by the released
    /// initialisers; empty by default. P4-21.
    public let additionalProhibitions: [FieldProhibition]

    public init(
        index: Int,
        name: String,
        dataType: String,
        optionality: FieldOptionality,
        repeatability: FieldRepeatability,
        condition: String? = nil,
        prohibitedWhen: String? = nil,
        variableColumns: Bool = false,
        table: String? = nil,
        length: String? = nil
    ) {
        self.init(index: index, name: name, dataType: dataType, optionality: optionality,
                  repeatability: repeatability, condition: condition, prohibitedWhen: prohibitedWhen,
                  variableColumns: variableColumns, table: table, length: length, tableOpen: false)
    }

    /// Creates a field grammar that also states whether the field's own prose leaves its
    /// bound table open (see ``tableOpen``). A separate overload so the released
    /// initialiser keeps its signature (ADR-014). P2-15.
    public init(
        index: Int,
        name: String,
        dataType: String,
        optionality: FieldOptionality,
        repeatability: FieldRepeatability,
        condition: String? = nil,
        prohibitedWhen: String? = nil,
        variableColumns: Bool = false,
        table: String? = nil,
        length: String? = nil,
        tableOpen: Bool
    ) {
        self.init(index: index, name: name, dataType: dataType, optionality: optionality,
                  repeatability: repeatability, condition: condition, prohibitedWhen: prohibitedWhen,
                  variableColumns: variableColumns, table: table, length: length, tableOpen: tableOpen,
                  prohibitedSeverity: .error)
    }

    /// Creates a field grammar that also states the severity of its prohibition (see
    /// ``prohibitedSeverity``). A separate overload so the released initialisers keep
    /// their signatures (ADR-014). P4.
    public init(
        index: Int,
        name: String,
        dataType: String,
        optionality: FieldOptionality,
        repeatability: FieldRepeatability,
        condition: String? = nil,
        prohibitedWhen: String? = nil,
        variableColumns: Bool = false,
        table: String? = nil,
        length: String? = nil,
        tableOpen: Bool = false,
        prohibitedSeverity: IssueSeverity
    ) {
        self.init(index: index, name: name, dataType: dataType, optionality: optionality,
                  repeatability: repeatability, condition: condition, prohibitedWhen: prohibitedWhen,
                  variableColumns: variableColumns, table: table, length: length, tableOpen: tableOpen,
                  prohibitedSeverity: prohibitedSeverity, additionalProhibitions: [])
    }

    /// Creates a field grammar that carries more than one prohibition (see
    /// ``additionalProhibitions``). A separate overload so the released initialisers keep
    /// their signatures (ADR-014). P4-21.
    public init(
        index: Int,
        name: String,
        dataType: String,
        optionality: FieldOptionality,
        repeatability: FieldRepeatability,
        condition: String? = nil,
        prohibitedWhen: String? = nil,
        variableColumns: Bool = false,
        table: String? = nil,
        length: String? = nil,
        tableOpen: Bool = false,
        prohibitedSeverity: IssueSeverity = .error,
        additionalProhibitions: [FieldProhibition]
    ) {
        self.index = index
        self.name = name
        self.dataType = dataType
        self.optionality = optionality
        self.repeatability = repeatability
        self.condition = condition
        self.prohibitedWhen = prohibitedWhen
        self.variableColumns = variableColumns
        self.table = table
        self.length = length
        self.tableOpen = tableOpen
        self.prohibitedSeverity = prohibitedSeverity
        self.additionalProhibitions = additionalProhibitions
    }
}

/// One prohibition on a field: when ``condition`` holds and the field is populated, the
/// Validator raises `.conditionalFieldProhibited` at ``severity``. The condition uses the
/// same predicate grammar as ``FieldGrammar/prohibitedWhen``, with the same fail-safe
/// semantics (an unresolvable predicate never fires). See
/// ``FieldGrammar/additionalProhibitions``. P4-21.
public struct FieldProhibition: Sendable, Equatable, Hashable {
    /// The predicate under which the field must not be populated, e.g. `"RXR-2.3 = HL70163"`.
    public let condition: String
    /// Severity of the issue raised when the rule fires: `.error` for normative text,
    /// `.warning` for SHOULD-level text (req #4).
    public let severity: IssueSeverity
    /// When `true`, the HL7 null (`""`) does not count as a value for this rule: a field
    /// whose every non-empty repetition is a lone `""` never fires it. Used where the spec
    /// asks for the field to be "valued with null" while the condition holds, such as
    /// OBX-2 and OBX-5 under OBX-11 = O (dynamic specification). `false` for every rule
    /// built with ``init(condition:severity:)``. P4-26.
    public let permitsNull: Bool

    /// Creates a prohibition from its predicate and the severity it reports at.
    public init(condition: String, severity: IssueSeverity) {
        self.init(condition: condition, severity: severity, permitsNull: false)
    }

    /// Creates a prohibition that may also exempt the HL7 null (see ``permitsNull``). A
    /// separate overload so the released initialiser keeps its signature (ADR-014). P4-26.
    public init(condition: String, severity: IssueSeverity, permitsNull: Bool) {
        self.condition = condition
        self.severity = severity
        self.permitsNull = permitsNull
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

    /// When set (M6-B-9), the rule only applies if AT LEAST ONE segment
    /// in the resolved group matches this predicate — relational group
    /// cardinality. HL7au:000008.3.2: "If an RTF display segment is
    /// sent in an OBR/OBX group, then the same content must be sent in
    /// one of either HTML, PDF, or TXT" — the min-count on the
    /// HTML/PDF/TXT disjunction activates only when an RTF display
    /// exists in the group. `nil` (default) = always active.
    let activationPredicate: String?

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
        activationPredicate: String? = nil,
        predicate: String,
        applicableWhen: String? = nil,
        specCitation: String? = nil
    ) {
        self.countedSegmentID = countedSegmentID
        self.scope = scope
        self.minCount = minCount
        self.maxCount = maxCount
        self.activationPredicate = activationPredicate
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
