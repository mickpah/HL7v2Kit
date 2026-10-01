// Validator+PrimitiveComponents.swift
// P6-13: components in a primitive code field (ID, IS). Kept out of Validator.swift,
// which only calls it.

import Foundation

extension Validator {

    /// The data types whose fields carry a code from a table as one primitive value.
    static let primitiveCodeTypes: Set<String> = ["ID", "IS"]

    /// The value a recipient reads from a repetition of a primitive field: the first
    /// subcomponent of the first component. A recipient ignores components and
    /// subcomponents "that are present but were not expected" (v2.5.1 and v2.8.2
    /// section 2.6.2 a), and a primitive field expects one value. `nil` for a
    /// repetition with no components.
    static func primitiveValue(_ repetition: Repetition) -> String? {
        repetition.components.first?.subcomponents.first?.value
    }

    /// True when a repetition carries content after its first subcomponent of its
    /// first component. Trailing empty parts carry nothing and are not counted.
    static func hasExtraPrimitiveContent(_ repetition: Repetition) -> Bool {
        repetition.components.enumerated().contains { index, component in
            component.subcomponents.enumerated().contains { sub, value in
                (index > 0 || sub > 0) && !value.value.isEmpty
            }
        }
    }

    /// Reports ``IssueCode/extraComponentsInPrimitiveField`` once per repetition of an
    /// `ID` or `IS` field that carries content after its first value. The component
    /// separator separates "components of data fields where allowed" (v2.5.1 and
    /// v2.8.2 section 2.5.4), and a sender escapes it in data as `\S\` (section 2.6.1);
    /// an escaped separator is decoded into the value and never reaches here.
    func checkExtraPrimitiveComponents(
        _ grammar: FieldGrammar,
        field: Field,
        dataType: String,
        location: IssueLocation,
        issues: inout [ValidationIssue]
    ) {
        guard let severity = options.extraComponentsSeverity,
              Self.primitiveCodeTypes.contains(dataType) else { return }
        for (offset, repetition) in field.repetitions.enumerated() where Self.hasExtraPrimitiveContent(repetition) {
            let extras = repetition.components.enumerated().flatMap { index, component in
                component.subcomponents.enumerated().compactMap { sub, value in
                    (index > 0 || sub > 0) && !value.value.isEmpty ? "\"\(value.value)\"" : nil
                }
            }
            let first = Self.primitiveValue(repetition) ?? ""
            issues.append(ValidationIssue(
                severity: severity,
                code: .extraComponentsInPrimitiveField,
                location: location,
                message: "Field \(location.pathDescription) ('\(grammar.name)') repetition \(offset + 1) is \(dataType), a primitive data type, but carries \(extras.joined(separator: ", ")) after its first value \"\(first)\"; a recipient reads only the first (v2.5.1 and v2.8.2 section 2.6.2 a), and a component separator inside a value is escaped as \\S\\"
            ))
        }
    }
}
