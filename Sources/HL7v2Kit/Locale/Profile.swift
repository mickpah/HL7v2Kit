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
/// Profile is keyed by `locale`. The current implementation carries
/// no overrides — locale plumbing lands in S5-A; the AU constraints
/// follow in S5-B/C/D as spec citations are extracted from the AU
/// ADRM-2021 PDF.
struct Profile: Sendable, Equatable, Hashable {
    /// The locale this profile corresponds to.
    let locale: HL7Locale

    /// The base HL7 v2 version this profile layers over. AU ADRM-2021
    /// is over v2.4; future profiles may target other base versions.
    let baseVersion: Version

    /// Per-segment field-attribute overrides. Each override identifies
    /// (segmentID, fieldIndex) and carries the profile's narrowing of
    /// optionality / value-set / required-components for that field.
    ///
    /// Empty in S5-A.
    let fieldOverrides: [FieldOverride]

    /// True iff this profile carries any overrides. An empty profile
    /// is a no-op overlay.
    var isEmpty: Bool {
        fieldOverrides.isEmpty
    }

    static let none: Profile? = nil
}

/// A single field-level override published by a localisation profile.
/// Internal — consumers see profile effects through `ValidationIssue`
/// rather than reading overrides directly.
///
/// Empty/skeletal in S5-A; S5-B/C/D populate the AU narrowings.
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

    /// Optional code-system constraint (e.g. "HL7AU-0001") for CWE / CE /
    /// IS / ID fields. nil means "no profile-specific value-set bound".
    let valueSet: String?

    /// Profile-defined required-component narrowings for composite
    /// fields. Empty means "use the base spec's required components
    /// unchanged".
    let requiredComponents: [Int]
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
