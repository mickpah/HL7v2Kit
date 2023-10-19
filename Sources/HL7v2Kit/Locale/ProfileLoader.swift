// ProfileLoader.swift
// Maps an `HL7Locale` to the corresponding `Profile` (or `nil` for
// `.international` which is a no-op base-only locale). Internal —
// consumers see only the locale enum.
//
// v0.4-S5-A returns a built-in empty Profile for `.auLocalisation`
// so the dispatch plumbing exercises end-to-end without any AU
// constraints firing yet. v0.4-S5-B and later replace this with a
// JSON-driven loader that reads `Resources/profiles/au-adrm-2021/`.

import Foundation

/// Loads localisation profiles by locale. Internal value type.
enum ProfileLoader {
    /// Look up the profile for a given locale.
    ///
    /// Returns `nil` for `.international` (no overlay applied —
    /// validation runs only base-spec checks). Returns a `Profile`
    /// for any localisation. The Profile may be empty (S5-A scaffold);
    /// once it has overrides, the Validator layers them on top of the
    /// base grammar.
    static func load(for locale: HL7Locale) -> Profile? {
        switch locale {
        case .international:
            return nil
        case .auLocalisation:
            // S5-A scaffold: empty Profile so the plumbing is live but
            // no AU constraints fire. S5-B replaces this with a JSON-
            // backed loader that reads Resources/profiles/au-adrm-2021/.
            return Profile(
                locale: .auLocalisation,
                baseVersion: .v2_4,
                fieldOverrides: []
            )
        }
    }
}
