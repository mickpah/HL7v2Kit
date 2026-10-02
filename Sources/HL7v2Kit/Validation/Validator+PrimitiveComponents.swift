// Validator+PrimitiveComponents.swift
// P6-13 / P6-14: content after the value of a primitive field or component. Kept out of
// Validator.swift, which only calls it.

import Foundation

extension Validator {

    /// The primitive data types each version defines: a datatype section in the
    /// version's CH02 that prints no components. CD, CF, CM, MA, NA and TQ are not
    /// primitives: their sections define components (CD and CF have no component
    /// grammar on v2.3 to v2.4, but do from v2.5.1). TS is listed only where it prints no component table;
    /// v2.5.1 onward define it as a composite (TS.1 DTM, TS.2 ID).
    ///
    /// - v2.3 CH2 2.8 (DT 2.8.13, FT 2.8.17, ID 2.8.19, IS 2.8.20, NM 2.8.25, SI 2.8.36,
    ///   ST 2.8.38, TM 2.8.39, TN 2.8.40, TS 2.8.42, TX 2.8.43)
    /// - v2.3.1 CH2 2.8 (DT 2.8.15, FT 2.8.19, ID 2.8.21, IS 2.8.22, NM 2.8.27, SI 2.8.38,
    ///   ST 2.8.40, TM 2.8.41, TN 2.8.42, TS 2.8.44, TX 2.8.45)
    /// - v2.4 CH02 2.9 (DT 2.9.15, FT 2.9.20, ID 2.9.22, IS 2.9.23, NM 2.9.28, SI 2.9.40,
    ///   ST 2.9.43, TM 2.9.44, TN 2.9.45, TS 2.9.47, TX 2.9.48)
    /// - v2.5.1 and v2.6 CH02A (DT 2.A.21, DTM 2.A.22, FT 2.A.31, GTS 2.A.32, ID 2.A.35,
    ///   IS 2.A.36, NM 2.A.47, SI 2.A.69, ST 2.A.74, TM 2.A.75, TX 2.A.78)
    /// - v2.8.2 CH02A (DT 2.A.21, DTM 2.A.22, FT 2.A.31, GTS 2.A.32, ID 2.A.35, IS 2.A.36,
    ///   NM 2.A.47, SI 2.A.70, SNM 2.A.72, ST 2.A.76, TM 2.A.77, TX 2.A.80)
    static func primitiveTypes(_ version: Version) -> Set<String> {
        switch version.grammarVersion {
        case .v2_3, .v2_3_1, .v2_4:
            return ["DT", "FT", "ID", "IS", "NM", "SI", "ST", "TM", "TN", "TS", "TX"]
        case .v2_5_1, .v2_6:
            return ["DT", "DTM", "FT", "GTS", "ID", "IS", "NM", "SI", "ST", "TM", "TX"]
        case .v2_8_2, .v2_8:
            return ["DT", "DTM", "FT", "GTS", "ID", "IS", "NM", "SI", "SNM", "ST", "TM", "TX"]
        }
    }

    /// How many parts one level down a primitive `dataType` admits on `version`, or
    /// `nil` when it is not a primitive there. One for every primitive, except:
    /// - TS on v2.3 to v2.4: two, the time and the degree of precision ("Format:
    ///   YYYY[MM[DD[HHMM[SS[.S[S[S[S]]]]]]]][+/-ZZZZ]^<degree of precision>", v2.3 2.8.42,
    ///   v2.3.1 2.8.44, v2.4 2.9.47).
    /// - FT: unbounded. "The component separator that marks each line defines the extent
    ///   of the temporary indent command (.ti), and the beginning of each line in the
    ///   no-wrap mode (.nf)", and "“^\.sp\” is equivalent to “\.br\.”" (v2.3 / v2.3.1
    ///   2.9.6, v2.4 2.10.6, v2.5.1 2.7.6, v2.8.2 2.7.7). Its subcomponents still count.
    static func primitiveComponentLimit(_ dataType: String, version: Version) -> Int? {
        guard primitiveTypes(version).contains(dataType) else { return nil }
        switch dataType {
        case "FT": return .max
        case "TS": return 2
        default:   return 1
        }
    }

    /// A primitive component the spec lets carry subcomponents, keyed either by the
    /// composite datatype or by segment and field, with the subcomponent count it admits.
    struct SubcomponentAllowance: Sendable {
        let dataType: String?
        let segmentID: String?
        let fieldIndex: Int?
        let component: Int
        let limit: Int
    }

    /// Every spec-sanctioned subcomponent use in a primitive component, in one place:
    /// - QIP.2 Values, a list: "A simple list of values (i.e., a one-dimensional array)
    ///   may be passed instead of a single value by separating each value with the
    ///   subcomponent delimiter: <field name> ^ <value1 & value2 &...>" (v2.3 2.8.30.2 and
    ///   2.24.20.4, v2.3.1 2.8.32.2, v2.4 2.9.33.2, v2.5.1 / v2.6 2.A.59.2, v2.8.2 2.A.60.2).
    /// - OBX-3 observation identifier, one suffix: "the chest X-ray observation ID (if CPT4,
    ///   it would be 71020), a subcomponent delimiter, and the suffix, IMP, i.e., 71020&IMP",
    ///   and "This same combining rule applies to other coding systems" (CH07: v2.3 and
    ///   v2.3.1 7.1.2, v2.4 / v2.5.1 / v2.6 7.2.3, v2.8.2 7.2.5). So the identifier
    ///   (component 1), the alternate identifier (component 4) and, on v2.8.2 where OBX-3
    ///   is CWE, the second alternate identifier (CWE.10).
    static let subcomponentAllowances: [SubcomponentAllowance] = [
        SubcomponentAllowance(dataType: "QIP", segmentID: nil, fieldIndex: nil, component: 2, limit: .max),
        SubcomponentAllowance(dataType: nil, segmentID: "OBX", fieldIndex: 3, component: 1, limit: 2),
        SubcomponentAllowance(dataType: nil, segmentID: "OBX", fieldIndex: 3, component: 4, limit: 2),
        SubcomponentAllowance(dataType: nil, segmentID: "OBX", fieldIndex: 3, component: 10, limit: 2),
    ]

    /// How many subcomponents a primitive component admits, or `nil` when the
    /// component's datatype is not a primitive on `version`. One, except TS on v2.3 to
    /// v2.4 (two, its degree of precision demoted) and an entry of
    /// ``subcomponentAllowances``. FT is one here: the component separator marks FT
    /// lines only at field level, and nothing turns a line marker into `&`.
    static func subcomponentLimit(componentType: String, component: Int, fieldType: String,
                                  segmentID: String, fieldIndex: Int?, version: Version) -> Int? {
        guard let base = primitiveComponentLimit(componentType, version: version) else { return nil }
        let allowance = subcomponentAllowances.first {
            $0.component == component
                && ($0.dataType.map { $0 == fieldType } ?? ($0.segmentID == segmentID && $0.fieldIndex == fieldIndex))
        }
        return max(componentType == "FT" ? 1 : base, allowance?.limit ?? 1)
    }

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
        !extraPrimitiveContent(repetition, limit: 1).isEmpty
    }

    /// The non-empty values a repetition carries beyond the first `limit` components,
    /// or in any subcomponent after the first. Empty parts carry nothing.
    static func extraPrimitiveContent(_ repetition: Repetition, limit: Int) -> [String] {
        repetition.components.enumerated().flatMap { index, component in
            component.subcomponents.enumerated().compactMap { sub, value in
                (index >= limit || sub > 0) && !value.value.isEmpty ? value.value : nil
            }
        }
    }

    /// The part of a repetition a recipient reads: the first `limit` components, each
    /// reduced to its first subcomponent. Used to measure length once the rest is reported.
    static func acceptedPrimitiveContent(_ repetition: Repetition, limit: Int) -> Repetition {
        Repetition(components: repetition.components.prefix(limit).map {
            Component(subcomponents: [Subcomponent($0.subcomponents.first?.value ?? "")])
        })
    }

    /// Composite datatypes that are open-ended arrays. NA: every version's table
    /// lists four values and then an ellipsis, and "A field of this type may contain a
    /// one-dimensional array (vector or row) of numbers", example
    /// "125^34^-22^-234^569^442^-212^6" (v2.5.1, v2.6 and v2.8.2 2.A.45). MA: the v2.5.1
    /// table (2.A.40) lists six rows ending "Sample N From Channel N" with no ellipsis,
    /// but its prose has "channels within a sample are separated by component
    /// delimiters", and the v2.6 and v2.8.2 tables (2.A.40) end in an ellipsis.
    static let openComposites: Set<String> = ["MA", "NA"]

    /// The component table of a composite `dataType` on `version` whose width is fixed,
    /// or `nil`: a primitive, a datatype the version prints no table for (CM on v2.3 to
    /// v2.4, `varies`), or an ``openComposites`` array.
    static func closedComposite(_ dataType: String, version: Version) -> DataTypeGrammar? {
        guard !openComposites.contains(dataType),
              primitiveComponentLimit(dataType, version: version) == nil,
              let grammar = DataTypeGrammarTable.grammar(dataType, version: version),
              !grammar.components.isEmpty else { return nil }
        return grammar
    }

    /// The populated values at 1-based positions past `limit`, each position given as
    /// the values it holds. Empty values carry nothing and are not reported.
    static func extraParts(_ parts: [[String]], limit: Int) -> [(index: Int, value: String)] {
        parts.enumerated().dropFirst(limit).flatMap { offset, values in
            values.filter { !$0.isEmpty }.map { (index: offset + 1, value: $0) }
        }
    }

    /// Reports ``IssueCode/extraComponentsInPrimitiveField`` once per repetition of a
    /// primitive field (``primitiveComponentLimit(_:version:)``) that carries content
    /// after its value, and once per primitive component of a composite field that
    /// carries a subcomponent after its value, located at that component. The component
    /// separator separates "components of data fields where allowed" (v2.5.1 and v2.8.2
    /// section 2.5.4), and a sender escapes a separator in data as `\S\`
    /// or `\T\` (section 2.7.1); an escaped separator is decoded into the value and never
    /// reaches here. P6-15: for a composite field (``closedComposite(_:version:)``), also
    /// reports ``IssueCode/extraComponentsInCompositeField`` once per repetition with a
    /// populated component past its datatype's table, and once per composite component
    /// with a populated subcomponent past its own datatype's table, located at that
    /// component.
    func checkExtraPrimitiveComponents(
        _ grammar: FieldGrammar,
        field: Field,
        dataType: String,
        version: Version,
        location: IssueLocation,
        issues: inout [ValidationIssue]
    ) {
        guard let severity = options.extraComponentsSeverity else { return }
        func quoted(_ values: [String]) -> String { values.map { "\"\($0)\"" }.joined(separator: ", ") }
        let grammarVersion = version.grammarVersion
        if let limit = Self.primitiveComponentLimit(dataType, version: grammarVersion) {
            for (offset, repetition) in field.repetitions.enumerated() {
                let extras = Self.extraPrimitiveContent(repetition, limit: limit)
                guard !extras.isEmpty else { continue }
                let first = Self.primitiveValue(repetition) ?? ""
                let shape = limit == 1 ? "after its first value \"\(first)\""
                    : limit == 2 ? "beyond the two components a v\(grammarVersion.rawValue) \(dataType) carries"
                    : "in subcomponents a \(dataType) value does not have"
                issues.append(ValidationIssue(
                    severity: severity,
                    code: .extraComponentsInPrimitiveField,
                    location: location,
                    message: "Field \(location.pathDescription) ('\(grammar.name)') repetition \(offset + 1) is \(dataType), a primitive data type, but carries \(quoted(extras)) \(shape); a recipient ignores parts it does not expect (v2.5.1 and v2.8.2 section 2.6.2 a), and a separator inside a value is escaped as \\S\\ or \\T\\"
                ))
            }
            return
        }
        guard let composite = DataTypeGrammarTable.grammar(dataType, version: grammarVersion) else { return }
        let closed = Self.closedComposite(dataType, version: grammarVersion) != nil
        for (offset, repetition) in field.repetitions.enumerated() {
            // P6-15: populated components beyond the datatype's component table.
            let beyond = !closed ? [] : Self.extraParts(repetition.components.map { $0.subcomponents.map(\.value) },
                                                        limit: composite.components.count)
            if !beyond.isEmpty {
                issues.append(ValidationIssue(
                    severity: severity,
                    code: .extraComponentsInCompositeField,
                    location: location,
                    message: "Field \(location.pathDescription) ('\(grammar.name)') repetition \(offset + 1) is \(dataType), which the v\(grammarVersion.rawValue) component table defines with \(composite.components.count) components, but carries \(beyond.map { "component \($0.index) \"\($0.value)\"" }.joined(separator: ", ")); a recipient ignores components it does not expect (v2.5.1 and v2.8.2 section 2.6.2 a), and a later version or a local extension may add components at the end of a data type (section 2.8.1, section 2.11.5)"
                ))
            }
            for entry in composite.components where repetition.components.count >= entry.index {
                // P6-15: a composite component, one level down, against its own table.
                if let nested = Self.closedComposite(entry.dataType, version: grammarVersion) {
                    let parts = repetition.components[entry.index - 1].subcomponents.map { [$0.value] }
                    let over = Self.extraParts(parts, limit: nested.components.count)
                    guard !over.isEmpty else { continue }
                    let at = IssueLocation(segmentID: location.segmentID, segmentIndex: location.segmentIndex,
                                           fieldIndex: location.fieldIndex, componentIndex: entry.index)
                    issues.append(ValidationIssue(
                        severity: severity,
                        code: .extraComponentsInCompositeField,
                        location: at,
                        message: "Component \(at.pathDescription) ('\(entry.name)') repetition \(offset + 1) is \(entry.dataType), which the v\(grammarVersion.rawValue) component table defines with \(nested.components.count) components, but carries \(over.map { "subcomponent \($0.index) \"\($0.value)\"" }.joined(separator: ", ")); a recipient ignores subcomponents it does not expect (v2.5.1 and v2.8.2 section 2.6.2 a), and a subcomponent separator inside a value is escaped as \\T\\"
                    ))
                    continue
                }
                guard let limit = Self.subcomponentLimit(
                    componentType: entry.dataType, component: entry.index, fieldType: dataType,
                    segmentID: location.segmentID, fieldIndex: location.fieldIndex, version: grammarVersion
                ) else { continue }
                let component = repetition.components[entry.index - 1]
                let extras = component.subcomponents.enumerated().compactMap { sub, value in
                    sub >= limit && !value.value.isEmpty ? value.value : nil
                }
                guard !extras.isEmpty else { continue }
                let at = IssueLocation(segmentID: location.segmentID, segmentIndex: location.segmentIndex,
                                       fieldIndex: location.fieldIndex, componentIndex: entry.index)
                let first = component.subcomponents.first?.value ?? ""
                let shape = limit == 1 ? "after its first value \"\(first)\""
                    : "beyond the \(limit) subcomponents this component allows"
                issues.append(ValidationIssue(
                    severity: severity,
                    code: .extraComponentsInPrimitiveField,
                    location: at,
                    message: "Component \(at.pathDescription) ('\(entry.name)') repetition \(offset + 1) is \(entry.dataType), a primitive data type, but carries subcomponent \(quoted(extras)) \(shape); a recipient ignores parts it does not expect (v2.5.1 and v2.8.2 section 2.6.2 a), and a subcomponent separator inside a value is escaped as \\T\\"
                ))
            }
        }
    }
}
