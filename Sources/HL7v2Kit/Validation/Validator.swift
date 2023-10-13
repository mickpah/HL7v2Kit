// Validator.swift
// Structural + cardinality + Z-segment-policy validation. Reads the
// codegen-emitted `SegmentGrammarTable.v2_5_1` table (Path C from STATUS
// decisions log 2026-06-13). Non-fatal: returns a `ValidationReport`,
// never throws.

import Foundation

/// Validate a parsed `Message` against the loaded segment grammars.
public struct Validator: Sendable {
    public let options: ValidationOptions

    public init(options: ValidationOptions = .default) {
        self.options = options
    }

    /// Validate a message. Returns a non-empty report only when at least
    /// one check produced an issue.
    public func validate(_ message: Message) -> ValidationReport {
        var issues: [ValidationIssue] = []
        var segmentOccurrence: [String: Int] = [:]

        let grammar = grammarTable(for: message.version)

        for segment in message.segments {
            let id = segment.segmentID
            let occurrence = (segmentOccurrence[id] ?? 0) + 1
            segmentOccurrence[id] = occurrence

            guard let segGrammar = grammar[id] else {
                // No grammar entry — treat as a Z-segment / unknown.
                appendZSegmentIssue(
                    id: id,
                    occurrence: occurrence,
                    issues: &issues
                )
                continue
            }

            checkSegment(
                segment,
                grammar: segGrammar,
                occurrence: occurrence,
                issues: &issues
            )
        }

        return ValidationReport(issues: issues)
    }

    // MARK: - Internals

    private func grammarTable(for version: Version) -> [String: SegmentGrammar] {
        switch version {
        case .v2_5_1: return SegmentGrammarTable.v2_5_1
        default:      return [:]   // Other versions unsupported by v0.1.0 grammar.
        }
    }

    private func appendZSegmentIssue(
        id: String,
        occurrence: Int,
        issues: inout [ValidationIssue]
    ) {
        let location = IssueLocation(segmentID: id, segmentIndex: occurrence)
        switch options.zSegmentPolicy {
        case .ignore:
            return
        case .warnPresence:
            issues.append(ValidationIssue(
                severity: .info,
                code: .zSegmentPresent,
                location: location,
                message: "Z-segment '\(id)' present at occurrence \(occurrence)"
            ))
        case .reject:
            issues.append(ValidationIssue(
                severity: .error,
                code: .zSegmentPresent,
                location: location,
                message: "Z-segment '\(id)' rejected under .reject policy"
            ))
        }
    }

    private func checkSegment(
        _ segment: Segment,
        grammar: SegmentGrammar,
        occurrence: Int,
        issues: inout [ValidationIssue]
    ) {
        for fieldGrammar in grammar.fields {
            let location = IssueLocation(
                segmentID: grammar.segmentID,
                segmentIndex: occurrence,
                fieldIndex: fieldGrammar.index
            )

            let field = segment.field(fieldGrammar.index)
            let isPopulated = field.map { isFieldPopulated($0) } ?? false

            if options.checkRequiredFields {
                checkRequired(
                    fieldGrammar,
                    isPopulated: isPopulated,
                    location: location,
                    issues: &issues
                )
            }

            if options.warnDeprecatedFields, isPopulated {
                checkDeprecation(
                    fieldGrammar,
                    location: location,
                    issues: &issues
                )
            }

            if options.checkCardinality, let field, isPopulated {
                checkCardinality(
                    fieldGrammar,
                    field: field,
                    location: location,
                    issues: &issues
                )
            }
        }
    }

    private func checkRequired(
        _ grammar: FieldGrammar,
        isPopulated: Bool,
        location: IssueLocation,
        issues: inout [ValidationIssue]
    ) {
        guard grammar.optionality == .required, !isPopulated else { return }
        issues.append(ValidationIssue(
            severity: .error,
            code: .requiredFieldMissing,
            location: location,
            message: "Required field \(location.pathDescription) ('\(grammar.name)') is missing"
        ))
    }

    private func checkDeprecation(
        _ grammar: FieldGrammar,
        location: IssueLocation,
        issues: inout [ValidationIssue]
    ) {
        switch grammar.optionality {
        case .backwardCompat:
            issues.append(ValidationIssue(
                severity: .warning,
                code: .fieldNotSupported,
                location: location,
                message: "Field \(location.pathDescription) ('\(grammar.name)') is deprecated (B) but populated"
            ))
        case .notSupported:
            issues.append(ValidationIssue(
                severity: .warning,
                code: .fieldNotSupported,
                location: location,
                message: "Field \(location.pathDescription) ('\(grammar.name)') is not supported (X) but populated"
            ))
        default:
            return
        }
    }

    private func checkCardinality(
        _ grammar: FieldGrammar,
        field: Field,
        location: IssueLocation,
        issues: inout [ValidationIssue]
    ) {
        guard grammar.repeatability == .single else { return }
        guard field.repetitions.count > 1 else { return }
        issues.append(ValidationIssue(
            severity: .error,
            code: .cardinalityExceeded,
            location: location,
            message: "Field \(location.pathDescription) ('\(grammar.name)') is single-cardinality but has \(field.repetitions.count) repetitions"
        ))
    }

    /// A field is "populated" if at least one repetition has at least one
    /// component with a non-empty subcomponent value. Distinguishes the
    /// "present but empty" wire shape from genuinely absent fields.
    private func isFieldPopulated(_ field: Field) -> Bool {
        for repetition in field.repetitions {
            for component in repetition.components {
                for subcomponent in component.subcomponents {
                    if !subcomponent.value.isEmpty { return true }
                }
            }
        }
        return false
    }
}
