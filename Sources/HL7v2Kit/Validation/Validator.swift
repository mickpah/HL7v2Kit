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
        case .v2_3:   return SegmentGrammarTable.v2_3
        case .v2_3_1: return SegmentGrammarTable.v2_3_1
        case .v2_4:   return SegmentGrammarTable.v2_4
        case .v2_5_1: return SegmentGrammarTable.v2_5_1
        default:      return [:]   // v2.8 grammar table is out of scope for v0.3.
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

            if options.checkConditionalFields {
                checkConditional(
                    fieldGrammar,
                    segment: segment,
                    isPopulated: isPopulated,
                    location: location,
                    issues: &issues
                )
            }

            if options.checkComponentGrammar, let field, isPopulated {
                checkComponents(
                    fieldGrammar,
                    field: field,
                    segmentID: grammar.segmentID,
                    segmentIndex: occurrence,
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

    /// Component-level grammar check (v0.2-V2). When a composite-typed
    /// field is populated, walks every repetition and confirms that each
    /// component listed in the composite's `requiredComponents` carries
    /// a non-empty value. Emits one ``IssueCode/requiredComponentMissing``
    /// per missing required component. Composite types HL7v2Kit doesn't
    /// have typed metadata for (CE / CWE / EI / XCN / ...) skip silently.
    private func checkComponents(
        _ grammar: FieldGrammar,
        field: Field,
        segmentID: String,
        segmentIndex: Int,
        issues: inout [ValidationIssue]
    ) {
        let required = requiredComponents(forCompositeCode: grammar.dataType)
        guard !required.isEmpty else { return }
        for repetition in field.repetitions where isRepetitionPopulated(repetition) {
            for spec in required {
                if !isComponentPopulated(repetition, componentIndex: spec.index) {
                    let location = IssueLocation(
                        segmentID: segmentID,
                        segmentIndex: segmentIndex,
                        fieldIndex: grammar.index,
                        componentIndex: spec.index
                    )
                    issues.append(ValidationIssue(
                        severity: .error,
                        code: .requiredComponentMissing,
                        location: location,
                        message: "Required component \(location.pathDescription) ('\(spec.name)') in \(grammar.dataType) field '\(grammar.name)' is missing"
                    ))
                }
            }
        }
    }

    /// Map an HL7 composite data-type code (e.g. `"XPN"`) to the type's
    /// `requiredComponents` metadata. Unknown codes return an empty list
    /// so the check is a no-op for composites HL7v2Kit hasn't typed yet.
    private func requiredComponents(forCompositeCode code: String) -> [RequiredComponent] {
        switch code {
        case "XPN": return XPN.requiredComponents
        case "CX":  return CX.requiredComponents
        case "XAD": return XAD.requiredComponents
        case "CE":  return CE.requiredComponents
        case "CWE": return CWE.requiredComponents
        case "EI":  return EI.requiredComponents
        case "XCN": return XCN.requiredComponents
        case "XTN": return XTN.requiredComponents
        case "HD":  return HD.requiredComponents
        case "MSG": return MSG.requiredComponents
        case "PT":  return PT.requiredComponents
        case "VID": return VID.requiredComponents
        case "PL":  return PL.requiredComponents
        case "CNE": return CNE.requiredComponents
        case "XON": return XON.requiredComponents
        case "EIP": return EIP.requiredComponents
        default:    return []
        }
    }

    /// True if the repetition has at least one component with at least
    /// one non-empty subcomponent. Used to skip empty repetitions on
    /// multi-rep composite fields.
    private func isRepetitionPopulated(_ repetition: Repetition) -> Bool {
        for component in repetition.components {
            for subcomponent in component.subcomponents {
                if !subcomponent.value.isEmpty { return true }
            }
        }
        return false
    }

    /// True if the 1-based `componentIndex`-th component of `repetition`
    /// has at least one non-empty subcomponent value. Returns false for
    /// out-of-bounds component indices, which is the correct semantic for
    /// "required component is missing".
    private func isComponentPopulated(_ repetition: Repetition, componentIndex: Int) -> Bool {
        guard repetition.components.indices.contains(componentIndex - 1) else { return false }
        for subcomponent in repetition.components[componentIndex - 1].subcomponents {
            if !subcomponent.value.isEmpty { return true }
        }
        return false
    }

    /// `.conditional` field check (v0.2-V1). Fires `.conditionalFieldMissing`
    /// when the field's `grammar.condition` predicate evaluates to true and
    /// the field is empty. Same-segment predicates only; cross-segment or
    /// malformed predicates skip silently (treated as no-trigger).
    private func checkConditional(
        _ grammar: FieldGrammar,
        segment: Segment,
        isPopulated: Bool,
        location: IssueLocation,
        issues: inout [ValidationIssue]
    ) {
        guard grammar.optionality == .conditional,
              !isPopulated,
              let condition = grammar.condition,
              !condition.isEmpty,
              conditionTriggers(condition, in: segment, currentSegmentID: location.segmentID)
        else { return }
        issues.append(ValidationIssue(
            severity: .error,
            code: .conditionalFieldMissing,
            location: location,
            message: "Conditional field \(location.pathDescription) ('\(grammar.name)') is required by condition '\(condition)' but missing"
        ))
    }

    /// Evaluate a v0.2-V1 condition predicate against a single segment.
    ///
    /// Grammar:
    /// ```
    /// <segmentID>-<index> <predicate>
    /// <predicate> := "populated" | "empty" | "= <value>" | "!= <value>"
    /// ```
    /// Cross-segment references (segmentID ≠ currentSegmentID) and any
    /// malformed predicate fail safe — return `false` so the field is
    /// treated as `.optional`. This is deliberate: a malformed schema
    /// should never make a previously-accepted message non-conformant.
    ///
    /// "Populated" / "empty" use the same any-subcomponent-non-empty
    /// check as `isFieldPopulated`. The `=` / `!=` value comparison
    /// reads the first subcomponent of the first component of the first
    /// repetition (the "scalar view" of the field) — sufficient for the
    /// common case of comparing against an ID/IS/ST scalar.
    private func conditionTriggers(
        _ condition: String,
        in segment: Segment,
        currentSegmentID: String
    ) -> Bool {
        let parts = condition.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                              .map(String.init)
        guard parts.count == 2 else { return false }
        let fieldRef = parts[0]
        let predicate = parts[1]

        let refParts = fieldRef.split(separator: "-", maxSplits: 1)
                                .map(String.init)
        guard refParts.count == 2,
              refParts[0] == currentSegmentID,
              let fieldIndex = Int(refParts[1])
        else { return false }

        let field = segment.field(fieldIndex)
        let isReferentPopulated = field.map { isFieldPopulated($0) } ?? false

        if predicate == "populated" { return isReferentPopulated }
        if predicate == "empty"     { return !isReferentPopulated }

        let raw = field?.repetitions.first?.components.first?.subcomponents.first?.value ?? ""
        if predicate.hasPrefix("= ") {
            return raw == String(predicate.dropFirst(2))
        }
        if predicate.hasPrefix("!= ") {
            return raw != String(predicate.dropFirst(3))
        }
        return false
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
