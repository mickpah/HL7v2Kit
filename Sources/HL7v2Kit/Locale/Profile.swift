// Profile.swift
// Internal value type representing a loaded localisation profile. Not
// public API — consumers interact with the locale through `HL7Locale`
// and let the framework dispatch internally. See ADR-007.
//
// v0.4-S5-A ships the type with empty contents for the AU profile.
// v0.4-S5-B and later fill in the actual fieldOverrides / required
// component narrowings / code-system constraints from the AU ADRM
// spec text.

import Foundation

/// A loaded localisation profile. Internal value type used by the
/// Validator to layer profile-specific narrowings on top of base
/// HL7 v2 grammar.
///
/// Profile carries two narrowing tracks:
///
/// 1. **`fieldOverrides`** — per-(segmentID, fieldIndex) rules. Used
///    for field-specific HL7au conformance points like HL7au:000003
///    (OBR-2 EI completeness). v0.5-S5-B-1.
/// 2. **`compositeOverrides`** — per-HL7-datatype rules. Used for
///    datatype-level conformance points like HL7au:00044.4.1 (every
///    populated CE field must have CE-3 set when CE-1 is set). v0.5-
///    S5-B-2.
struct Profile: Sendable, Equatable, Hashable {
    /// The locale this profile corresponds to.
    let locale: HL7Locale

    /// Per-segment field-attribute overrides. Each override identifies
    /// (segmentID, fieldIndex) and carries the profile's narrowing of
    /// optionality / value-set / required-components for that field.
    let fieldOverrides: [FieldOverride]

    /// Per-HL7-datatype overrides. Apply to every populated field of
    /// the named dataType across the entire message. Used for CE / CWE
    /// / CNE / EI / HD conformance points that the AU spec states at
    /// the datatype level (HL7au:00044.* series).
    let compositeOverrides: [CompositeOverride]

    /// Per-segment grammar extensions. Each entry's `[FieldGrammar]`
    /// is appended to the base-spec grammar for that segment when the
    /// profile is loaded (merging over any base field of the same
    /// index) — the mechanism for a locale to carry fields or
    /// narrowings the base version grammar does not state. v0.5-S5-D
    /// introduced it to pre-adopt v2.5+ PID-35..38 on v2.4 wires; P4-16
    /// (2026-10) removed that use once P4-17 confirmed the base v2.4
    /// PID grammar already carried those fields (see
    /// `Profile+au_adrm_2021.swift` for the history). The AU profile's
    /// own `grammarExtensions` is `[:]` today — currently unused, kept
    /// for the next locale-specific grammar addition.
    let grammarExtensions: [String: [FieldGrammar]]

    /// Per-segment group-scope cardinality rules layered on top of the
    /// base grammar's `segmentCardinalityRules`. v0.11-S3 (ADR-010
    /// Extension 2). Mirrors `grammarExtensions` in shape: keyed by
    /// segment ID, valued by `[SegmentCardinalityRule]` merged into
    /// the effective grammar at Validator dispatch time. Locale-scoped
    /// rules like HL7au:000008 live here rather than in the base
    /// grammar so they only fire under the relevant locale.
    let cardinalityExtensions: [String: [SegmentCardinalityRule]]

    /// Message-wide field-uniqueness rules (M6-B-9). Used for
    /// HL7au:000028 / 000028.2 — "OBR-3 Filler order number must be
    /// unique within messages."
    let uniquenessRules: [FieldUniquenessRule]

    /// Prohibited escape-sequence classes (M7-P3). The AU ADRM narrows
    /// the base-spec escape repertoire as a variance to HL7
    /// International; the Validator scans every populated subcomponent
    /// value for `\<lead>...\` occurrences.
    let escapeProhibitions: [EscapeProhibition]

    /// OBX-4 sub-ID tree rules (M12). A header OBX declares a dotted-decimal
    /// root; every observation of the same group under that root must
    /// instantiate a row of the rule's element table.
    let subIDTrees: [SubIDTreeRule]

    /// The "C must not be valued when its predicate is false" rule
    /// (HL7au:00060.4 route C, ADR-021), or `nil` when the profile has
    /// none. Applies only to fields whose stored condition is marked as
    /// a full predicate. P4-31.
    let fullPredicateRule: FullPredicateRule?

    /// In-group ordering rules (P12 S2-2). Used for HL7au:000008.1.5 —
    /// display OBX segments last in each OBR/OBX group, signatures aside.
    let groupOrderingRules: [GroupOrderingRule]

    init(
        locale: HL7Locale,
        fieldOverrides: [FieldOverride] = [],
        grammarExtensions: [String: [FieldGrammar]] = [:],
        compositeOverrides: [CompositeOverride] = [],
        cardinalityExtensions: [String: [SegmentCardinalityRule]] = [:],
        uniquenessRules: [FieldUniquenessRule] = [],
        escapeProhibitions: [EscapeProhibition] = [],
        subIDTrees: [SubIDTreeRule] = [],
        fullPredicateRule: FullPredicateRule? = nil,
        groupOrderingRules: [GroupOrderingRule] = []
    ) {
        self.locale = locale
        self.fieldOverrides = fieldOverrides
        self.grammarExtensions = grammarExtensions
        self.compositeOverrides = compositeOverrides
        self.cardinalityExtensions = cardinalityExtensions
        self.uniquenessRules = uniquenessRules
        self.escapeProhibitions = escapeProhibitions
        self.subIDTrees = subIDTrees
        self.fullPredicateRule = fullPredicateRule
        self.groupOrderingRules = groupOrderingRules
    }

    /// Look up the profile for a given locale.
    ///
    /// Returns `nil` for `.international` (no overlay applied —
    /// validation runs only base-spec checks). Returns the hand-curated
    /// AU ADRM-2021 profile (see `Profile+au_adrm_2021.swift`, the
    /// single source of truth) for `.auLocalisation`; the Validator
    /// layers its overrides on top of the base grammar. A JSON-driven
    /// codegen path stays deferred until a second localisation profile
    /// needs shared tooling (ADR-007; v0.14 retired the stale JSON files).
    static func load(for locale: HL7Locale) -> Profile? {
        switch locale {
        case .international:
            return nil
        case .auLocalisation:
            return Profile.auADRM2021
        }
    }
}

/// A datatype-level override. Applies to every populated field whose
/// HL7 dataType code matches `dataType`. v0.5-S5-B-2 / v0.5-S5-B-3.
struct CompositeOverride: Sendable, Equatable, Hashable {
    /// The HL7 dataType code this override applies to (e.g. `"CE"`).
    let dataType: String

    /// Message-context predicate gating every rule in this override.
    /// When `nil` (default) the override applies to every message the
    /// locale is used on.
    ///
    /// Same grammar and fail-safe semantics as
    /// `FieldOverride.condition`. `valueConditionals` may narrow further
    /// with their own `condition`; both must hold.
    ///
    /// Added by M6-D4 (2026-09-04), the composite-track twin of M6-D3:
    /// every HL7au:00044.* datatype point is scoped to a named set of
    /// message types, but the overrides applied to all of them, so an
    /// ADT with a two-component CX failed AU validation citing a point
    /// that does not reach ADT. See
    /// `docs/design/m6-adrm-2021-localisation-audit.md`.
    let condition: String?

    /// Profile-required components that NARROW the base spec. When a
    /// field of this dataType is populated, each listed component must
    /// be populated; otherwise `.profileConstraintViolation` fires.
    ///
    /// Used to express HL7au:00044.1.2 (CX-4 must be valued) and
    /// HL7au:00044.1.3 (CX-5 must be valued). v0.5-S5-B-3.
    let requiredComponents: [ComponentRequirement]

    /// Pair-conditional rules: "if component A satisfies condition X,
    /// then component B must satisfy requirement Y". Used to express
    /// HL7au:00044.4.1, 00044.4.2, 00044.4.5, 00044.4.6 and the
    /// equivalent CWE / CNE series. v0.5-S5-B-2.
    let pairRules: [PairConditional]

    /// Component-value inequality rules: "components A and B must carry
    /// different values when both are populated". Used to express
    /// HL7au:00044.4.8 (CE alternate coding system must differ from the
    /// primary coding system). v0.13 (ADR-011).
    let componentInequalities: [ComponentInequality]

    /// Value-conditional rules: "component N must not carry a denied
    /// value" (optionally message-type-gated via the v0.7 DSL). Used to
    /// express HL7au:00044.4.4 (LOINC must not appear as the alternate
    /// coding system on Orders/Results). v0.13 (ADR-011).
    let valueConditionals: [ComponentValueConditional]

    /// Per-component value-set narrowings (ALLOW lists), the composite
    /// twin of `FieldOverride.componentValueSets`. M6-B-5 (2026-09-16):
    /// added so datatype-level table-membership points (HL7au:00044.7.3
    /// XCN-10 / table 0200, 00044.7.4 XCN-13 / table 0203) can express
    /// the membership half that held them at PARTIAL.
    ///
    /// **Populated-only semantics** — unlike the field-level track, an
    /// EMPTY component does not fire: presence is `requiredComponents`'
    /// job here, and firing on empty would double-report every missing
    /// component as both "must be populated" and "not in the table".
    let componentValueSets: [ComponentValueSet]

    /// Literal-shape restrictions on components of this composite. M33.
    let componentPatterns: [ComponentPattern]

    /// Per-repetition key⇒value correspondences (M6-B-8). Used for the
    /// ED/RP subtype⇒type points (HL7au:00044.10.1.5/.6, .11.1.5/.6).
    let componentCorrespondences: [ComponentCorrespondence]

    /// When set (M6-B-9, HL7au:00044.8.1): every populated value of
    /// this datatype with HOUR-or-greater precision (≥10 leading
    /// digits per the TS format) must carry a `+/-ZZZZ` timezone
    /// offset; the string is the citation. Date-only values skip —
    /// the TS section conditions the offset on time being transmitted.
    /// PARTIAL by nature: offset *presence* is checkable, offset
    /// *correctness* is not.
    let timezoneRequiredCitation: String?

    init(
        dataType: String,
        condition: String? = nil,
        requiredComponents: [ComponentRequirement] = [],
        pairRules: [PairConditional] = [],
        componentInequalities: [ComponentInequality] = [],
        valueConditionals: [ComponentValueConditional] = [],
        componentValueSets: [ComponentValueSet] = [],
        componentPatterns: [ComponentPattern] = [],
        componentCorrespondences: [ComponentCorrespondence] = [],
        timezoneRequiredCitation: String? = nil
    ) {
        self.dataType = dataType
        self.condition = condition
        self.requiredComponents = requiredComponents
        self.pairRules = pairRules
        self.componentInequalities = componentInequalities
        self.valueConditionals = valueConditionals
        self.componentValueSets = componentValueSets
        self.componentPatterns = componentPatterns
        self.componentCorrespondences = componentCorrespondences
        self.timezoneRequiredCitation = timezoneRequiredCitation
    }
}

/// A component-value inequality rule on a composite. "When the field is
/// populated and both `componentA` and `componentB` are populated,
/// their (first-subcomponent) values must differ." Fires
/// `.profileConstraintViolation` when the two values are equal.
/// Fail-safe: when either component is empty there is nothing to
/// compare, so the rule does not fire. v0.13 (ADR-011).
struct ComponentInequality: Sendable, Equatable, Hashable {
    /// First 1-based component index (e.g. CE-3, primary coding system).
    let componentA: Int
    /// Second 1-based component index (e.g. CE-6, alt coding system).
    let componentB: Int
    /// Spec citation surfaced in `.profileConstraintViolation`.
    let specCitation: String?
}

/// A value-conditional rule on a composite. "When the field is
/// populated and (`condition` is nil OR evaluates true), the named
/// `component`'s (first-subcomponent) value must NOT be one of
/// `deniedValues`." Fires `.profileConstraintViolation` on a denied
/// value. Fail-safe: an empty component doesn't match any denied value;
/// an unparseable `condition` gates the rule off. v0.13 (ADR-011).
struct ComponentValueConditional: Sendable, Equatable, Hashable {
    /// The 1-based component index whose value is denied-listed.
    let component: Int
    /// Values the component must NOT carry (e.g. `["LN"]`).
    let deniedValues: [String]
    /// Optional v0.7-DSL message-context gate. `nil` → always applies.
    let condition: String?
    /// Spec citation surfaced in `.profileConstraintViolation`.
    let specCitation: String?
}

/// A single component-required rule on a composite. "When the field
/// is populated, `component` must be populated." Each rule carries
/// its own spec citation so the Validator can attribute the failure
/// per-rule. v0.5-S5-B-3.
struct ComponentRequirement: Sendable, Equatable, Hashable {
    /// The 1-based component index that must be populated.
    let component: Int

    /// The 1-based subcomponent index within `component` that must be
    /// populated. When `nil` (default), any populated subcomponent
    /// satisfies the requirement — the pre-M6 behaviour.
    ///
    /// Needed because ADRM-2021 names subcomponents directly:
    /// HL7au:00044.7.5 requires the *surname* subcomponent of XCN-2
    /// (family name, FN), not merely a populated XCN-2. A `^&PREFIX`
    /// family name is populated but carries no surname.
    let subcomponent: Int?

    /// Spec citation for this rule. Surfaced in
    /// `ValidationIssue.code.profileConstraintViolation(localeRule:)`.
    let specCitation: String?

    /// Optional gate in the conditional-field DSL, evaluated against the
    /// segment carrying the field; the rule is skipped when it does not
    /// hold. Lets one requirement inside a composite's rule set carry a
    /// scope the others do not (HL7au:00044.4.3's caller assertion). M30.
    let condition: String?

    /// When `true`, the requirement restates a base rule that only some
    /// versions carry, and is skipped wherever the base composite for the
    /// message's grammar version already requires this component, so the
    /// finding is reported once (by the base check). Needed for a conformance
    /// point like HL7au:00049.1 (MSG-1 must be valued): v2.5.1 and later
    /// require MSG.1, v2.4 types MSH-9 as CM with no component optionality
    /// (HL7 v2.4 Chapter 2, 2.16.9.9). P3-4.
    ///
    /// On a version where it yields, the finding is the base
    /// `requiredComponentMissing` (at `ValidationOptions.requiredComponentSeverity`),
    /// not this rule's `profileConstraintViolation` (always `.error`), so the
    /// same defect's code and severity can differ between versions.
    ///
    /// The deferral check looks up the base composite by the field's
    /// **statically-declared** datatype (`FieldGrammar.dataType`), the same
    /// type `Validator.checkComponents` — the base check this defers to —
    /// keys on, not the field's runtime-resolved `effectiveDataType`
    /// (e.g. OBX-5's runtime type from OBX-2). This override applies by
    /// effective datatype (so it reaches OBX-5 at all), but the deferral
    /// must match what the base check actually looks up, or a composite
    /// override on a variable-type field could defer to a base check that
    /// never runs — on OBX-5 the static type is always the "varies"
    /// placeholder, which has no component grammar, so `checkComponents`
    /// never fires there regardless of the effective type (P3-5 fix
    /// round 1). The deferral also only fires when
    /// `ValidationOptions.checkComponentGrammar` is true, because that flag
    /// gates whether the base check runs at all — under `.lenient` it
    /// doesn't, so yielding here would drop the finding rather than move
    /// it (P3-5).
    let yieldsToBase: Bool

    init(component: Int, subcomponent: Int? = nil, specCitation: String? = nil, condition: String? = nil,
         yieldsToBase: Bool = false) {
        self.component = component
        self.subcomponent = subcomponent
        self.specCitation = specCitation
        self.condition = condition
        self.yieldsToBase = yieldsToBase
    }
}

/// A single pair-conditional rule on a composite. "If component A
/// satisfies `condition`, then component B must satisfy `requirement`."
struct PairConditional: Sendable, Equatable, Hashable {
    /// The 1-based component index whose population state triggers the
    /// rule (e.g. CE-1).
    let ifComponent: Int

    /// The population state that triggers the rule.
    let condition: PairCondition

    /// The 1-based component index whose population state is required
    /// when the trigger fires (e.g. CE-3).
    let thenComponent: Int

    /// What the `thenComponent`'s population state must be.
    let requirement: PairRequirement

    /// Spec citation for this rule. Surfaced in
    /// `ValidationIssue.code.profileConstraintViolation(localeRule:)`.
    let specCitation: String?
}

/// Trigger states for `PairConditional`.
enum PairCondition: Sendable, Equatable, Hashable {
    /// Fire the rule when the `ifComponent` is populated.
    case populated
    /// Fire the rule when the `ifComponent` is empty.
    case empty
}

/// Required outcomes for `PairConditional`.
enum PairRequirement: Sendable, Equatable, Hashable {
    /// When the trigger fires, `thenComponent` must be populated.
    case mustBePopulated
    /// When the trigger fires, `thenComponent` must be empty.
    case mustBeEmpty
}

/// A single field-level override published by a localisation profile.
/// Internal — consumers see profile effects through `ValidationIssue`
/// rather than reading overrides directly.
///
/// Empty/skeletal in S5-A; S5-B/C/D populate the AU narrowings. A
/// future S5-B-N substage will introduce a sibling `CompositeOverride`
/// type keyed by HL7 dataType code (e.g. "CE") for datatype-level
/// rules that apply to every populated field of that type — needed for
/// the HL7au:00044.* conformance points which are datatype-level, not
/// field-level.
struct FieldOverride: Sendable, Equatable, Hashable {
    /// The segment this override applies to (e.g. "PID").
    let segmentID: String

    /// The 1-based field index this override applies to.
    let fieldIndex: Int

    /// Optional override of the field's profile usage code. nil means
    /// "use the base spec's optionality unchanged".
    ///
    /// AU profile supports `R` / `RE` / `O` / `C` / `CE` / `X`. See
    /// ADR-007 for the extended-usage semantics.
    let profileUsage: ProfileUsage?

    /// Message-context predicate gating this override's `profileUsage`
    /// and `requiredComponents` narrowings. When set, they apply only to
    /// messages the predicate matches; when `nil` (default) they apply
    /// to every message the locale is used on.
    ///
    /// `componentValueSets` are NOT gated by this — each carries its own
    /// `condition`, because a single field's value sets can be scoped to
    /// different message-type sets (ADRM-2021 scopes MSH-2's component
    /// separator to Orders/Results/Referrals but its sub-component,
    /// repeat and escape characters to Orders/Results only).
    ///
    /// Uses the same grammar as `ComponentValueSet.condition` (ADR-009),
    /// e.g. `"messageCode in (ORM, ORU, REF, RRI, ACK)"`, and the same
    /// fail-safe semantics: an unparseable predicate evaluates false, so
    /// a malformed gate silences the rule rather than over-firing it.
    ///
    /// Added by M6-D3 (2026-09-04). ADRM-2021 states nearly every
    /// conformance point for a named set of message types; without a
    /// gate here, `profileUsage = .required` fired on message types the
    /// spec never addressed — see
    /// `docs/design/m6-adrm-2021-localisation-audit.md`.
    let condition: String?

    /// Profile-defined required-component narrowings for composite
    /// fields. Empty means "use the base spec's required components
    /// unchanged".
    let requiredComponents: [Int]

    /// Profile-defined value-set narrowings on specific components.
    /// Each `ComponentValueSet` restricts the named component to a
    /// fixed list of allowed literal values. Empty means "no value-set
    /// narrowings on any component". v0.5-S5-C.
    let componentValueSets: [ComponentValueSet]

    /// Literal-shape restrictions on components of this field. M32.
    let componentPatterns: [ComponentPattern]

    /// Per-repetition key⇒value correspondences (M6-B-8). Used for the
    /// PRD-7 authority⇒qualifier pairs (HL7au:00104.7.1.4) — PRD-7
    /// repeats, so each repetition pairs its own key and value.
    let componentCorrespondences: [ComponentCorrespondence]

    /// Explicit, cited prohibitions on valuing this field (P4-24,
    /// HL7au:00060.4 route B). Each fires when the field carries a value
    /// other than the HL7 null (`""`) while its own `condition` holds.
    /// Not gated by `condition` above; each rule carries its own
    /// message-type scope.
    let prohibitions: [ProfileFieldProhibition]

    /// Spec citation for this override. Surfaced verbatim in
    /// `ValidationIssue.code.profileConstraintViolation(localeRule:)`
    /// so consumers can attribute the failure to the specific
    /// conformance point (e.g. `"HL7au:000003 (r2) — OBR-2 EI
    /// completeness"`). nil means "no specific citation" and the
    /// Validator falls back to a generic `<locale>:<seg>-<idx>.<comp>`
    /// identifier.
    let specCitation: String?

    init(
        segmentID: String,
        fieldIndex: Int,
        profileUsage: ProfileUsage? = nil,
        condition: String? = nil,
        requiredComponents: [Int] = [],
        componentValueSets: [ComponentValueSet] = [],
        componentPatterns: [ComponentPattern] = [],
        componentCorrespondences: [ComponentCorrespondence] = [],
        prohibitions: [ProfileFieldProhibition] = [],
        specCitation: String? = nil
    ) {
        self.segmentID = segmentID
        self.fieldIndex = fieldIndex
        self.profileUsage = profileUsage
        self.condition = condition
        self.requiredComponents = requiredComponents
        self.componentValueSets = componentValueSets
        self.componentPatterns = componentPatterns
        self.componentCorrespondences = componentCorrespondences
        self.prohibitions = prohibitions
        self.specCitation = specCitation
    }
}

/// A profile's "a C element must not be valued when its predicate is not
/// satisfied" rule (P4-31, ADR-021). It reports a populated field, other
/// than the HL7 null, whose stored condition is marked as the spec's full
/// predicate and evaluates definitely false, while `scope` evaluates
/// true. An unknown condition never fires, and a field that a base or
/// profile prohibition already reports is not reported again.
struct FullPredicateRule: Sendable, Equatable, Hashable {
    /// Message-context predicate the rule applies under, in the shared
    /// condition grammar, e.g. `"messageCode in (ORM, ORU, REF)"`.
    let scope: String

    /// `.error` for "must not".
    let severity: IssueSeverity

    /// Citation surfaced as the `localeRule` of the reported
    /// `.profileConstraintViolation`.
    let specCitation: String

    /// The `version|SEG-n` keys of the marked fields. Defaults to the
    /// schema marking; tests may widen it.
    let marked: Set<String>

    init(scope: String, severity: IssueSeverity, specCitation: String,
         marked: Set<String> = FullPredicateConditions.generated) {
        self.scope = scope
        self.severity = severity
        self.specCitation = specCitation
        self.marked = marked
    }
}

/// A profile-authored "must not be valued" rule on one field (P4-24).
/// Only rules whose spec text states the prohibition in so many words
/// are modelled; a base "required when" condition is never negated
/// (see the HL7au:00060.4 limitation row, P4-20).
///
/// The HL7 null (`""`) is always exempt from every rule here (P4-26's
/// `carriesNonNullValue`), unlike the base `FieldProhibition`, which
/// exempts the null only when its `permitsNull` flag is set. These
/// profile prohibitions are all "not used" rules: the cited prose asks
/// that the field carry no real content, and sending the HL7 null is a
/// delete instruction ("clear any prior value"), not a value in the
/// sense the prohibition means — so there is no profile rule, unlike
/// some base rules' mixed phrasing, where the null itself is the thing
/// the prose forbids.
struct ProfileFieldProhibition: Sendable, Equatable, Hashable {
    /// Predicate under which the field must not be valued, in the
    /// shared condition grammar (ADR-009), including the message-type
    /// scope, e.g. `"messageCode in (ORM, ORU, REF) AND OBX-11 = O"`.
    /// Evaluated by `Validator.conditionTriggers`; an unresolvable
    /// predicate fails safe and never fires.
    let condition: String

    /// `.error` for must or shall not, `.warning` for should not or not
    /// applicable.
    let severity: IssueSeverity

    /// Citation surfaced as the `localeRule` of the reported
    /// `.profileConstraintViolation`.
    let specCitation: String
}

/// A value-set narrowing on a specific component of a populated
/// field. "When the field is populated, this 1-based `component`'s
/// (first-)subcomponent value must be one of `allowedValues`."
///
/// Used to express AU rules like HL7au:000041 (MSH-17 = "AUS") and
/// HL7au:000042 (MSH-19.1 = "en"). v0.5-S5-C introduced the basic
/// shape; v0.8 (ADR-009) added `subcomponent` and `condition` so the
/// AU MSH-12 Version ID rules (HL7au:000040.1-.4) can express
/// subcomponent-granular pins and message-type-dispatched gating.
struct ComponentValueSet: Sendable, Equatable, Hashable {
    /// The 1-based component index this restriction applies to.
    let component: Int

    /// The 1-based subcomponent index within `component`. When `nil`
    /// (default), the check reads the component's FIRST subcomponent
    /// — the v0.5-S5-C behaviour. When set, reads that named
    /// subcomponent specifically. ADR-009.
    let subcomponent: Int?

    /// The fixed list of allowed values. Comparison is exact string
    /// match against the resolved (sub)component value.
    let allowedValues: [String]

    /// Optional v0.7-DSL predicate (ADR-008). When `nil` (default)
    /// the check always applies on populated fields. When set, the
    /// check is gated: if the predicate evaluates `false` the
    /// value-set is skipped. Used by HL7au:000040.3/.4 to apply
    /// different VID-3 values per message-code class without
    /// duplicating the FieldOverride entry. ADR-009.
    let condition: String?

    /// Spec citation for this rule. Surfaced in
    /// `ValidationIssue.code.profileConstraintViolation(localeRule:)`.
    let specCitation: String?

    /// Printed pattern rows of the source table (P12 S2-2): a value that
    /// fully matches one is allowed too. The ADRM's Table 0203 prints
    /// `NNxxx` (p. 306), a family no list of values can hold.
    let allowedPatterns: [HL7Table.CodePattern]

    init(
        component: Int,
        subcomponent: Int? = nil,
        allowedValues: [String],
        allowedPatterns: [HL7Table.CodePattern] = [],
        condition: String? = nil,
        specCitation: String? = nil
    ) {
        self.component = component
        self.subcomponent = subcomponent
        self.allowedValues = allowedValues
        self.allowedPatterns = allowedPatterns
        self.condition = condition
        self.specCitation = specCitation
    }

    /// `true` when `value` is one of `allowedValues` or fully matches one
    /// of `allowedPatterns`.
    func allows(_ value: String) -> Bool {
        allowedValues.contains(value) || allowedPatterns.contains { $0.matches(value) }
    }
}

/// A literal-shape restriction on a component of a populated field:
/// "the value must begin with `prefix`, and what follows must be
/// exactly `digitsAfterPrefix` digits." Both parameters come from the
/// spec text — nothing is inferred, and a nil parameter is not checked.
///
/// Expresses HL7au:00044.2.2, whose sentence is a concatenation rather
/// than a value set: the HD Universal ID "must contain the HPI-O
/// formatted as `1.2.36.1.2001.1003.0.` concatenated with the HPI-O",
/// with the HPI-O's own width given by HL7au:000043.1 ("a 16-digit
/// number"). Deliberately not a regular expression: a cited prefix and
/// a cited digit count are the whole of what the ADRM states, and a
/// pattern language would invite rules the spec does not support. M32.
struct ComponentPattern: Sendable, Equatable, Hashable {
    /// The 1-based component index this restriction applies to.
    let component: Int

    /// Literal prefix the value must carry, verbatim from the spec.
    let prefix: String?

    /// Exact number of digits that must follow `prefix` (or, when
    /// `prefix` is nil, make up the whole value).
    let digitsAfterPrefix: Int?

    /// Optional v0.7-DSL gate (ADR-008/009), as on ``ComponentValueSet``.
    let condition: String?

    /// Whether an empty component satisfies the rule. `false` (the default)
    /// is for a spec sentence that states a whole required form, so a
    /// missing value violates it: HL7au:000043.1 spells MSH-4 out as
    /// `"name^1.2.36.1.2001.1003.0.<hpio>^ISO"`, and MSH-4 carries no
    /// separate completeness rule. `true` is for a sentence that constrains
    /// only the shape of a value that some other rule requires to be
    /// present: the EI twins (HL7au:00044.3.4) sit on fields where
    /// HL7au:000006 / 000007 already require all four components, so
    /// firing on empty would report one defect twice. M33.
    let allowEmpty: Bool

    /// Spec citation for this rule. Surfaced in
    /// `ValidationIssue.code.profileConstraintViolation(localeRule:)`.
    let specCitation: String?

    init(
        component: Int,
        prefix: String? = nil,
        digitsAfterPrefix: Int? = nil,
        condition: String? = nil,
        allowEmpty: Bool = false,
        specCitation: String? = nil
    ) {
        self.component = component
        self.prefix = prefix
        self.digitsAfterPrefix = digitsAfterPrefix
        self.condition = condition
        self.allowEmpty = allowEmpty
        self.specCitation = specCitation
    }

    /// Why `value` fails this rule, or `nil` when it satisfies it. An
    /// empty value fails unless ``allowEmpty``; scope *when* the rule
    /// applies with `condition`.
    /// Pure, so the Validator and its tests read the same logic.
    func failure(for value: String) -> String? {
        if value.isEmpty { return allowEmpty ? nil : "expected a value" }
        var rest = Substring(value)
        if let prefix, !prefix.isEmpty {
            guard rest.hasPrefix(prefix) else { return "expected it to begin with \"\(prefix)\"" }
            rest = rest.dropFirst(prefix.count)
        }
        if let digitsAfterPrefix {
            guard rest.count == digitsAfterPrefix, rest.allSatisfy(\.isNumber) else {
                return "expected \(digitsAfterPrefix) digits after \"\(prefix ?? "")\", found \"\(rest)\""
            }
        }
        return nil
    }
}

/// A message-wide field-uniqueness rule (M6-B-9): every populated
/// occurrence of `segmentID`-`fieldIndex` (component `component`) must
/// carry a distinct value across the message. HL7au:000028 / 000028.2:
/// "the OBR-3 Filler order number must be unique within messages."
/// Empty fields skip (presence is a separate concern); the comparison
/// key is the named component's first-repetition scalar.
struct FieldUniquenessRule: Sendable, Equatable, Hashable {
    let segmentID: String
    let fieldIndex: Int
    /// 1-based component the uniqueness key is read from.
    let component: Int
    /// Optional v0.7-DSL message-context gate.
    let applicableWhen: String?
    let specCitation: String?
}

/// A prohibited escape-sequence class (M7-P3). The AU ADRM removes
/// three base-spec escape families as variances to HL7 International:
/// "The hexadecimal escape sequence (\Xdddd...\) must not be used"
/// (§3.1.1.5) and "The single-byte character escape sequence \Cxxyy\
/// and multi-byte character escape sequence \Mxxyyzz\ must not be
/// used" (§3.1.1.6), both p. 136 (reiterated p. 159: "The HL7 escape
/// sequences \M and \C shall not be used").
///
/// The Validator scans every populated subcomponent value for a
/// `\<lead>` opening followed by a closing `\` in the same value —
/// i.e. a complete escape sequence of the prohibited family. An
/// unterminated `\<lead>` skips (fail-safe: a malformed escape is a
/// different defect, not this rule's). Matching is case-sensitive —
/// HL7 escape-sequence codes are uppercase by definition. MSH-1 and
/// MSH-2 are exempt: they carry the delimiter literals themselves.
struct EscapeProhibition: Sendable, Equatable, Hashable {
    /// The character(s) after the escape delimiter identifying the
    /// family: "X" prohibits `\X...\`, "C" prohibits `\C...\`, "M"
    /// prohibits `\M...\`.
    let lead: String
    /// Optional v0.7-DSL message-context gate; `nil` → always applies.
    let applicableWhen: String?
    let specCitation: String?

    init(lead: String, applicableWhen: String? = nil, specCitation: String? = nil) {
        self.lead = lead
        self.applicableWhen = applicableWhen
        self.specCitation = specCitation
    }
}

/// An OBX-4 sub-ID tree (M12): a template methodology in which a header
/// OBX declares a dotted-decimal root and every element of the template is an
/// OBX whose sub-ID is a path under that root. AU ADRM-2021 Appendix 9
/// (Normative) defines one, the HL7v2 Virtual Medical Record.
///
/// Scope is the observation group: the OBX segments that follow one OBR up
/// to the next. A group without the header is not the rule's business, so a
/// structured pathology report that happens to use `1.x` sub-IDs is never
/// touched. The element table is rooted at `tableRoot`; the header's actual
/// root is substituted before matching, because the appendix allows another
/// number ("In the example below this is 1 but may be another number").
///
/// Deliberately NOT enforced, each for a stated reason: the table's OBX-2 and
/// OBX-3 columns (the appendix's own example contradicts both) and its
/// OCCURRENCES column (HL7 lets several OBX share one sub-ID, and the
/// appendix never says which the VMR forbids).
struct SubIDTreeRule: Sendable, Equatable, Hashable {
    /// OBX-3.1 of the header OBX that puts the template in use.
    let headerObservationID: String
    /// The root the element table is written against.
    let tableRoot: String
    let elements: [VMRElement]
    /// Kind value marking rows that are purely virtual and must not be written.
    let virtualKind: String
    /// Optional v0.7-DSL message-context gate; `nil` → always applies.
    let applicableWhen: String?
    /// Citations: an unknown path under the root, a virtual row written as an
    /// OBX, and a header whose own sub-ID is not dotted decimal.
    let unknownPathCitation: String
    let virtualRowCitation: String
    let headerShapeCitation: String
}

/// A per-repetition value-correspondence rule: "when `keyComponent`
/// carries a value the `map` knows, `valueComponent` (of the SAME
/// repetition) must carry one of the mapped values." M6-B-8.
///
/// - Keys the map does not know SKIP (fail-safe): the spec tables that
///   feed these maps state correspondences for enumerated keys only
///   (ADRM §3.20.5 type-subtype combinations; the PRD-7 matches table),
///   and an unstated key is not a violation. A rule whose source states
///   what every other key needs sets `unlistedKeyValues` (P12 S2-2).
/// - Comparison is CASE-INSENSITIVE on both key and value: the ADRM's
///   own sanctioned examples mix case (`TEXT^RTF` in §4.5.2,
///   `text^html` in §4.5.3).
/// - Evaluated per repetition so repeating fields (PRD-7) pair each
///   repetition's own key and value — a message-level gate would mix
///   repetitions.
struct ComponentCorrespondence: Sendable, Equatable, Hashable {
    /// 1-based component whose value selects the mapping.
    let keyComponent: Int
    /// 1-based component that must carry a mapped value.
    let valueComponent: Int
    /// Lowercased key → allowed values (compared lowercased).
    let map: [String: [String]]
    /// Optional v0.7-DSL gate; `nil` → always applies.
    let condition: String?
    /// Spec citation surfaced in the violation.
    let specCitation: String?
    /// What the mapped values mean: allowed (the M6-B-8 default) or
    /// forbidden (P12 S2-2).
    let valueRule: CorrespondenceValueRule
    /// The values a key the `map` does not list maps to, unless it is one
    /// of `exemptKeys`; `nil` (the M6-B-8 default) lets unlisted keys skip.
    /// P12 S2-2, HL7au:00104.7.1.4: a PRD-7.2 outside the printed Table
    /// 0363 is a vendor authority, whose qualifier must be `VDI` (p 334).
    let unlistedKeyValues: [String]?
    /// Lowercased keys that skip although the `map` does not list them.
    let exemptKeys: Set<String>

    init(
        keyComponent: Int,
        valueComponent: Int,
        map: [String: [String]],
        valueRule: CorrespondenceValueRule = .allowed,
        unlistedKeyValues: [String]? = nil,
        exemptKeys: Set<String> = [],
        condition: String? = nil,
        specCitation: String? = nil
    ) {
        self.keyComponent = keyComponent
        self.valueComponent = valueComponent
        self.map = map
        self.valueRule = valueRule
        self.unlistedKeyValues = unlistedKeyValues
        self.exemptKeys = exemptKeys
        self.condition = condition
        self.specCitation = specCitation
    }
}

/// How a `ComponentCorrespondence` reads its mapped values.
///
/// - `allowed`: the value component must carry one of the mapped values.
/// - `forbidden(prefixes:)`: the value component must carry none of the
///   mapped values and must not begin with any of `prefixes`. Expresses
///   HL7au:000034.1/.2, where the ADRM prints the local side as a value
///   and a form ("99ZZZ or L", Table 0396 p 144) rather than a list of
///   public systems the primary must come from. P12 S2-2.
enum CorrespondenceValueRule: Sendable, Equatable, Hashable {
    case allowed
    case forbidden(prefixes: [String])
}

/// Profile usage codes from the AU ADRM spec. The base HL7 v2 set is
/// `R / O / C / X / B`; AU profile adds `RE` (Required, can be empty)
/// and `CE` (Conditional, may be empty). See ADR-007.
enum ProfileUsage: String, Sendable, Equatable, Hashable {
    case required        = "R"
    case requiredEmpty   = "RE"
    case optional        = "O"
    case conditional     = "C"
    case conditionalEmpty = "CE"
    case notUsed         = "X"
}
