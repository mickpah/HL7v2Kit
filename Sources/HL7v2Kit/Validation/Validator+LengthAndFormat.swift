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
        encoding: EncodingCharacters,
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
        // P6-13: content after the first value of an ID / IS field is reported once, as
        // extraComponentsInPrimitiveField, and the length is that of the value a recipient
        // reads. With that check off, the whole occurrence is measured as before.
        let primitive = options.extraComponentsSeverity != nil && Self.primitiveCodeTypes.contains(dataType)
        for (offset, whole) in field.repetitions.enumerated() {
            var repetition = whole
            if primitive, Self.hasExtraPrimitiveContent(whole) {
                repetition = Repetition(components: [Component(subcomponents: [Subcomponent(Self.primitiveValue(whole) ?? "")])])
            }
            guard let length = Self.occupiedLength(repetition, encoding: encoding), !rule.admits(length) else { continue }
            issues.append(ValidationIssue(
                severity: severity,
                code: .fieldLengthOutOfRange(length: printed, actual: length),
                location: location,
                message: "Field \(location.pathDescription) ('\(grammar.name)') repetition \(offset + 1) has length \(length); the v\(version.grammarVersion.rawValue) attribute table prints LEN \(printed)"
            ))
        }
    }

    /// Characters one repetition occupies: every subcomponent value, measured in
    /// its encoded form, plus the component and subcomponent separators between
    /// them (v2.3.1 section 2.6.2; v2.5.1 section 2.5.3.2). Inside an escape
    /// sequence every character between the opening and closing escape character
    /// counts, the escape characters themselves do not: `\F\` is 1, `\.br\` 3,
    /// `\X0D0A\` 5 (v2.8.2 section 2.7, "This applies to all the escape
    /// sequences, including the formatting ones"; the pre-v2.7 texts say nothing
    /// on escapes and length, so the v2.8.2 rule applies to every version).
    /// Values are stored decoded, so the encoded form is the canonical
    /// re-encoding (`EscapeSequences.encode`); a non-canonical wire
    /// escape such as `\X41\` for `A` is measured as `A`. `nil` for an empty
    /// repetition or the HL7 null `""`, which has no length (v2.8.2 section
    /// 2.5.5.0 note); a `""` subcomponent inside a composite counts as empty.
    static func occupiedLength(_ repetition: Repetition, encoding: EncodingCharacters) -> Int? {
        let null = "\"\""
        let escape = encoding.escapeCharacter
        func measure(_ value: String) -> Int {
            if value == null { return 0 }
            let encoded = EscapeSequences.encode(value, encoding: encoding)
            return encoded.reduce(0) { $1 == escape ? $0 : $0 + 1 }
        }
        let characters = repetition.components.reduce(0) { total, component in
            total + component.subcomponents.reduce(0) { $0 + measure($1.value) }
        }
        guard characters > 0 else { return nil }
        let separators = max(repetition.components.count - 1, 0)
            + repetition.components.reduce(0) { $0 + max($1.subcomponents.count - 1, 0) }
        return characters + separators
    }
}
