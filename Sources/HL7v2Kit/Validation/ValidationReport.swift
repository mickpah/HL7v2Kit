// ValidationReport.swift
// Collected results of one `Validator.validate(_:)` call. Validation is
// non-fatal: a report can carry zero or many issues. `isValid` is true iff
// no `.error`-severity issues are present (warnings + infos are OK).

import Foundation

/// The result of validating a `Message`. Returned, never thrown — per ADR-002
/// (parsing throws fatally, validation reports non-fatally).
public struct ValidationReport: Sendable, Equatable, Hashable {
    /// All issues in the order they were observed (segment scan order).
    public let issues: [ValidationIssue]

    /// The locale the validator was configured with. Default `.international`.
    /// `.auLocalisation` indicates AU profile narrowings were layered on top
    /// of base-spec checks. See ADR-007.
    public let locale: HL7Locale

    public init(issues: [ValidationIssue], locale: HL7Locale = .international) {
        self.issues = issues
        self.locale = locale
    }

    /// True iff there are no `.error`-severity issues. Warnings and infos
    /// don't make a report invalid.
    public var isValid: Bool {
        !issues.contains(where: { $0.severity == .error })
    }

    /// Only the `.error`-severity issues.
    public var errors: [ValidationIssue] {
        issues.filter { $0.severity == .error }
    }

    /// Only the `.warning`-severity issues.
    public var warnings: [ValidationIssue] {
        issues.filter { $0.severity == .warning }
    }

    /// Only the `.info`-severity issues.
    public var infos: [ValidationIssue] {
        issues.filter { $0.severity == .info }
    }

}
