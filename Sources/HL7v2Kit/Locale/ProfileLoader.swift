// ProfileLoader.swift
// Maps an `HL7Locale` to the corresponding `Profile` (or `nil` for
// `.international` which is a no-op base-only locale). Internal —
// consumers see only the locale enum.
//
// v0.4-S5-A landed empty-Profile plumbing. v0.5-S5-B-1 returns the
// hand-curated `Profile.auADRM2021` (see Profile+au_adrm_2021.swift)
// with the EI-completeness rules for OBR-2 / OBR-3 / ORC-2 / ORC-3 /
// ORC-4. JSON-driven codegen support is deferred until more profiles
// need this pattern.

import Foundation

/// Loads localisation profiles by locale. Internal value type.
enum ProfileLoader {
    /// Look up the profile for a given locale.
    ///
    /// Returns `nil` for `.international` (no overlay applied —
    /// validation runs only base-spec checks). Returns a `Profile`
    /// for any localisation; the Validator layers the profile's
    /// `fieldOverrides` on top of the base grammar.
    static func load(for locale: HL7Locale) -> Profile? {
        switch locale {
        case .international:
            return nil
        case .auLocalisation:
            return Profile.auADRM2021
        }
    }
}
