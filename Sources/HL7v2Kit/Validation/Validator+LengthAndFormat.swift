// Validator+LengthAndFormat.swift
// Field length check (P6-6), kept out of Validator.swift, which only calls it.

import Foundation

extension Validator {

    /// LEN check for one populated field (V231-C15). Pre-v2.7 maximum lengths
    /// apply to the whole occurrence; v2.7+ normative lengths apply only where
    /// the field's datatype is primitive (v2.8.2 §2.5.5.0: "Normative lengths are
    /// only specified for primitive data types"). A range printed against a
    /// composite field is registered, not enforced.
    func checkFieldLength(
        _ grammar: FieldGrammar,
        field: Field,
        segmentID: String,
        version: Version,
        dataType: String,
        location: IssueLocation,
        issues: inout [ValidationIssue]
    ) {
        // MSH-1 / MSH-2 (and the batch and file headers') are the delimiters, not data.
        if ["MSH", "BHS", "FHS"].contains(segmentID), grammar.index <= 2 { return }
        guard let printed = grammar.length,
              let rule = FieldLengthRule.parse(printed, version: version) else { return }
        let severity: IssueSeverity?
        switch rule {
        case .maximum:
            severity = options.fieldLengthSeverity
        case .range, .oneOf:
            guard DataTypeGrammarTable.grammar(dataType, version: version.grammarVersion) == nil else { return }
            severity = options.normativeLengthSeverity
        }
        guard let severity else { return }
        for (offset, repetition) in field.repetitions.enumerated() {
            guard let length = Self.occupiedLength(repetition), !rule.admits(length) else { continue }
            issues.append(ValidationIssue(
                severity: severity,
                code: .fieldLengthOutOfRange(length: printed, actual: length),
                location: location,
                message: "Field \(location.pathDescription) ('\(grammar.name)') repetition \(offset + 1) has length \(length); the v\(version.grammarVersion.rawValue) attribute table prints LEN \(printed)"
            ))
        }
    }

    /// Characters one repetition occupies: every decoded subcomponent value plus
    /// the component and subcomponent separators between them (v2.3.1 §2.6.2).
    /// `nil` for an empty repetition or the HL7 null `""`, which has no length
    /// (v2.8.2 §2.5.5.0 note); a `""` subcomponent inside a composite counts as
    /// empty, so the measure can only under-count against the wire.
    static func occupiedLength(_ repetition: Repetition) -> Int? {
        let null = "\"\""
        let characters = repetition.components.reduce(0) { total, component in
            total + component.subcomponents.reduce(0) { $0 + ($1.value == null ? 0 : $1.value.count) }
        }
        guard characters > 0 else { return nil }
        let separators = max(repetition.components.count - 1, 0)
            + repetition.components.reduce(0) { $0 + max($1.subcomponents.count - 1, 0) }
        return characters + separators
    }
}
