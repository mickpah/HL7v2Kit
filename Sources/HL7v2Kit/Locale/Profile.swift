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
    /// profile is loaded. Used for AU pre-adoption of v2.5+ fields on
    /// v2.4 wires (e.g. PID-35..38 species/breed/strain/production-
    /// class), so the Validator sees them under `.auLocalisation`
    /// even though the base v2.4 PID grammar caps at 32. v0.5-S5-D.
    let grammarExtensions: [String: [FieldGrammar]]

    /// Per-segment group-scope cardinality rules layered on top of the
    /// base grammar's `segmentCardinalityRules`. v0.11-S3 (ADR-010
    /// Extension 2). Mirrors `grammarExtensions` in shape: keyed by
    /// segment ID, valued by `[SegmentCardinalityRule]` merged into
    /// the effective grammar at Validator dispatch time. Locale-scoped
    /// rules like HL7au:000008 live here rather than in the base
    /// grammar so they only fire under the relevant locale.
    let cardinalityExtensions: [String: [SegmentCardinalityRule]]

    init(
        locale: HL7Locale,
        fieldOverrides: [FieldOverride] = [],
        grammarExtensions: [String: [FieldGrammar]] = [:],
        compositeOverrides: [CompositeOverride] = [],
        cardinalityExtensions: [String: [SegmentCardinalityRule]] = [:]
    ) {
        self.locale = locale
        self.fieldOverrides = fieldOverrides
        self.grammarExtensions = grammarExtensions
        self.compositeOverrides = compositeOverrides
        self.cardinalityExtensions = cardinalityExtensions
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

    /// Per-repetition key⇒value correspondences (M6-B-8). Used for the
    /// ED/RP subtype⇒type points (HL7au:00044.10.1.5/.6, .11.1.5/.6).
    let componentCorrespondences: [ComponentCorrespondence]

    init(
        dataType: String,
        condition: String? = nil,
        requiredComponents: [ComponentRequirement] = [],
        pairRules: [PairConditional] = [],
        componentInequalities: [ComponentInequality] = [],
        valueConditionals: [ComponentValueConditional] = [],
        componentValueSets: [ComponentValueSet] = [],
        componentCorrespondences: [ComponentCorrespondence] = []
    ) {
        self.dataType = dataType
        self.condition = condition
        self.requiredComponents = requiredComponents
        self.pairRules = pairRules
        self.componentInequalities = componentInequalities
        self.valueConditionals = valueConditionals
        self.componentValueSets = componentValueSets
        self.componentCorrespondences = componentCorrespondences
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

    init(component: Int, subcomponent: Int? = nil, specCitation: String? = nil) {
        self.component = component
        self.subcomponent = subcomponent
        self.specCitation = specCitation
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

    /// Per-repetition key⇒value correspondences (M6-B-8). Used for the
    /// PRD-7 authority⇒qualifier pairs (HL7au:00104.7.1.4) — PRD-7
    /// repeats, so each repetition pairs its own key and value.
    let componentCorrespondences: [ComponentCorrespondence]

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
        componentCorrespondences: [ComponentCorrespondence] = [],
        specCitation: String? = nil
    ) {
        self.segmentID = segmentID
        self.fieldIndex = fieldIndex
        self.profileUsage = profileUsage
        self.condition = condition
        self.requiredComponents = requiredComponents
        self.componentValueSets = componentValueSets
        self.componentCorrespondences = componentCorrespondences
        self.specCitation = specCitation
    }
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

    init(
        component: Int,
        subcomponent: Int? = nil,
        allowedValues: [String],
        condition: String? = nil,
        specCitation: String? = nil
    ) {
        self.component = component
        self.subcomponent = subcomponent
        self.allowedValues = allowedValues
        self.condition = condition
        self.specCitation = specCitation
    }
}

/// A per-repetition value-correspondence rule: "when `keyComponent`
/// carries a value the `map` knows, `valueComponent` (of the SAME
/// repetition) must carry one of the mapped values." M6-B-8.
///
/// - Keys the map does not know SKIP (fail-safe): the spec tables that
///   feed these maps state correspondences for enumerated keys only
///   (ADRM §3.20.5 type-subtype combinations; the PRD-7 matches table),
///   and an unstated key is not a violation.
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

    init(
        keyComponent: Int,
        valueComponent: Int,
        map: [String: [String]],
        condition: String? = nil,
        specCitation: String? = nil
    ) {
        self.keyComponent = keyComponent
        self.valueComponent = valueComponent
        self.map = map
        self.condition = condition
        self.specCitation = specCitation
    }
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
