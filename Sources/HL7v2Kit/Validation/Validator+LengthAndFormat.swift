// Validator+LengthAndFormat.swift
// Field length (P6-6) and primitive value format (P6-7) checks, kept out of
// Validator.swift, which only calls them.

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
            guard Self.fieldGrammar(segment: segmentID, field: grammar.index, dataType: dataType,
                                    version: version) == nil else { return }
            severity = options.normativeLengthSeverity
        }
        guard let severity else { return }
        // P6-13 / P6-14: content after the value of a primitive field is reported once, as
        // extraComponentsInPrimitiveField, and the length is that of the value a recipient
        // reads, but only while that report is at least as severe as this length rule; a
        // length rule the caller has made more binding is never hidden behind it. Otherwise,
        // and with that check off, the whole occurrence is measured as before.
        let limit = Self.rank(options.extraComponentsSeverity) >= Self.rank(severity)
            ? Self.primitiveComponentLimit(dataType, version: version) : nil
        for (offset, whole) in field.repetitions.enumerated() {
            var repetition = whole
            if let limit, !Self.extraPrimitiveContent(whole, limit: limit).isEmpty {
                repetition = Self.acceptedPrimitiveContent(whole, limit: limit)
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

    /// The normative component lengths each grammar version prints (a range or a list),
    /// keyed by the printed cell and parsed once (S1-5: parsing each cell per component
    /// per field put the 5,000-segment ORU past its derived scaling limit). A version that
    /// prints maxima has no entry, since no component table enforces a maximum, so the
    /// check returns there before resolving a grammar.
    static let componentLengthRules: [Version: [String: FieldLengthRule]] = {
        var table: [Version: [String: FieldLengthRule]] = [:]
        for version in indexedGrammarVersions {
            var rules: [String: FieldLengthRule] = [:]
            let grammars = Array(DataTypeGrammarTable.grammars(for: version).values)
                + Array(DataTypeGrammarTable.fieldGrammars(for: version).values)
            for entry in grammars.flatMap(\.components) {
                guard let printed = entry.length, rules[printed] == nil,
                      let rule = FieldLengthRule.parse(printed, version: version) else { continue }
                if case .maximum = rule { continue }
                rules[printed] = rule
            }
            if !rules.isEmpty { table[version] = rules }
        }
        return table
    }()

    /// The grammar versions the component indexes are built over: every grammar
    /// version ``Version`` defines, once each, so a grammar version added later is
    /// indexed rather than silently skipped (S1-fix M2).
    static let indexedGrammarVersions: [Version] = Version.allCases.reduce(into: []) { versions, version in
        if !versions.contains(version.grammarVersion) { versions.append(version.grammarVersion) }
    }

    /// The grammar keys of each grammar version that print a checkable component length.
    static let componentLengthKeys: [Version: Set<String>] = grammarKeys { entry, version in
        entry.length.flatMap { componentLengthRules[version]?[$0] } != nil
    }

    /// For each grammar version, the keys of its grammars (the datatype name, or `SEG-n`
    /// for a field-local grammar) with at least one component `relevant` selects. A
    /// component pass checks ``mayResolve(into:segment:field:dataType:version:)`` first,
    /// so a field whose grammar has nothing to check costs one set lookup (S1-5).
    static func grammarKeys(_ relevant: (ComponentGrammar, Version) -> Bool) -> [Version: Set<String>] {
        var table: [Version: Set<String>] = [:]
        for version in indexedGrammarVersions {
            let grammars = DataTypeGrammarTable.grammars(for: version).merging(
                DataTypeGrammarTable.fieldGrammars(for: version)) { own, _ in own }
            let keys = grammars.filter { $0.value.components.contains { relevant($0, version) } }.keys
            if !keys.isEmpty { table[version] = Set(keys) }
        }
        return table
    }

    /// Whether field `field` of `segment`, typed `dataType`, can resolve through
    /// ``fieldGrammar(segment:field:dataType:version:)`` to a grammar whose key is in
    /// `keys`: its field-local grammar where one is printed, else its datatype's.
    static func mayResolve(into keys: Set<String>, segment: String, field: Int?, dataType: String,
                           version: Version) -> Bool {
        let locals = DataTypeGrammarTable.fieldGrammars(for: version)
        if !locals.isEmpty, let field, locals["\(segment)-\(field)"] != nil {
            return keys.contains("\(segment)-\(field)")
        }
        return keys.contains(dataType)
    }

    /// Normative length of each primitive component of a composite field (S1-1,
    /// register section G). v2.7.1 and v2.8.2 print `m..n` or `x,y,z` on components
    /// as well as fields ("they may also be specified on the components and/or fields
    /// where the data type is used", section 2.5.5.4) and conformant messages lie
    /// within them (section 2.5.5.0). Only those two forms are read, through
    /// ``FieldLengthRule/parse(_:version:)``; a pre-v2.7 component cell is a maximum
    /// no component table enforces, and conformance lengths are not limits. A
    /// component is measured as ``checkFieldLength`` measures a field
    /// (``occupiedLength(_:encoding:)``), reduced to the subcomponents its datatype
    /// admits while the extra-content report is at least as severe. Subcomponents
    /// are not checked: section 2.5.5.4 names fields and components only.
    /// The printed cells are parsed once, in ``componentLengthRules``.
    func checkComponentLength(
        field: Field,
        version: Version,
        dataType: String,
        encoding: EncodingCharacters,
        location: IssueLocation,
        issues: inout [ValidationIssue]
    ) {
        guard let severity = options.normativeLengthSeverity,
              let rules = Self.componentLengthRules[version.grammarVersion],
              let keys = Self.componentLengthKeys[version.grammarVersion],
              Self.mayResolve(into: keys, segment: location.segmentID, field: location.fieldIndex,
                              dataType: dataType, version: version.grammarVersion),
              let composite = Self.fieldGrammar(segment: location.segmentID, field: location.fieldIndex,
                                                dataType: dataType, version: version.grammarVersion) else { return }
        let reduce = Self.rank(options.extraComponentsSeverity) >= Self.rank(severity)
        for entry in composite.components {
            guard let printed = entry.length, let rule = rules[printed] else { continue }
            guard let subcomponentLimit = Self.subcomponentLimit(
                componentType: entry.dataType, component: entry.index, fieldType: dataType,
                segmentID: location.segmentID, fieldIndex: location.fieldIndex, version: version.grammarVersion
            ) else { continue }
            for (offset, repetition) in field.repetitions.enumerated()
            where repetition.components.count >= entry.index {
                var component = repetition.components[entry.index - 1]
                // As checkFieldLength: set aside only content the extra-content check reports.
                if reduce, component.subcomponents.dropFirst(subcomponentLimit).contains(where: { !$0.value.isEmpty }) {
                    component = Component(subcomponents: Array(component.subcomponents.prefix(subcomponentLimit)))
                }
                guard let length = Self.occupiedLength(Repetition(components: [component]), encoding: encoding),
                      !rule.admits(length) else { continue }
                let at = IssueLocation(segmentID: location.segmentID, segmentIndex: location.segmentIndex,
                                       fieldIndex: location.fieldIndex, componentIndex: entry.index,
                                       subcomponentIndex: nil)
                issues.append(ValidationIssue(
                    severity: severity,
                    code: .componentLengthOutOfRange(length: printed, actual: length),
                    location: at,
                    message: "Component \(at.pathDescription) ('\(entry.name)') repetition \(offset + 1) has length \(length); the v\(version.grammarVersion.rawValue) \(composite.dataType) component table prints LEN \(printed)"
                ))
            }
        }
    }

    /// Severity order for comparing two settings: error > warning > info > off (`nil`).
    static func rank(_ severity: IssueSeverity?) -> Int {
        switch severity {
        case .error: return 3
        case .warning: return 2
        case .info: return 1
        case nil: return 0
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

    /// Lexical format of populated primitive values (V251-C10, PrimitiveFormat).
    /// Where `dataType` has a component grammar on the version
    /// (``fieldGrammar(segment:field:dataType:version:)``, which keeps a primitive primitive
    /// and gives a pre-v2.5 `CM` field the components its definition prints), each component
    /// whose grammar datatype has a rule is checked, and a composite component is
    /// descended one level into its subcomponents, as the component code-table
    /// check does (TS.1 is DTM on v2.5.1). Otherwise a datatype with a rule is
    /// checked on the value a recipient reads, the first subcomponent of the
    /// first component (``primitiveValue(_:)``; v2.5.1 and v2.8.2 section 2.6.2
    /// a): a primitive, including TS on v2.3 to v2.4, whose Format-line grammar
    /// prints no datatype codes and whose second component is the degree of
    /// precision (P5-2). Empty values and
    /// the HL7 null `""` carry no value to check.
    func checkValueFormat(
        dataType: String,
        field: Field,
        version: Version,
        location: IssueLocation,
        issues: inout [ValidationIssue]
    ) {
        guard let severity = options.valueFormatSeverity else { return }
        let grammarVersion = version.grammarVersion
        func report(_ value: String?, as type: String, component: Int?, subcomponent: Int?, repetition: Int) {
            guard let value, !value.isEmpty, value != "\"\"",
                  PrimitiveFormat.isValid(value, dataType: type, version: version) == false else { return }
            let at = IssueLocation(segmentID: location.segmentID, segmentIndex: location.segmentIndex,
                                   fieldIndex: location.fieldIndex, componentIndex: component,
                                   subcomponentIndex: subcomponent)
            issues.append(ValidationIssue(
                severity: severity,
                code: .valueFormatInvalid(dataType: type),
                location: at,
                message: "\(at.pathDescription) repetition \(repetition) value \"\(value)\" does not match the v\(grammarVersion.rawValue) \(type) format"
            ))
        }
        for (offset, repetition) in field.repetitions.enumerated() {
            let n = offset + 1
            guard let grammar = Self.fieldGrammar(segment: location.segmentID, field: location.fieldIndex,
                                                  dataType: dataType, version: grammarVersion) else {
                if PrimitiveFormat.checkedTypes.contains(dataType) {
                    report(Self.primitiveValue(repetition), as: dataType, component: nil, subcomponent: nil, repetition: n)
                }
                continue
            }
            for entry in grammar.components where repetition.components.count >= entry.index {
                let component = repetition.components[entry.index - 1]
                if let nested = Self.componentGrammar(entry.dataType, version: grammarVersion) {
                    for inner in nested.components
                    where component.subcomponents.count >= inner.index
                        && PrimitiveFormat.checkedTypes.contains(inner.dataType) {
                        report(component.subcomponents[inner.index - 1].value, as: inner.dataType,
                               component: entry.index, subcomponent: inner.index, repetition: n)
                    }
                } else if PrimitiveFormat.checkedTypes.contains(entry.dataType) {
                    report(component.subcomponents.first?.value, as: entry.dataType,
                           component: entry.index, subcomponent: nil, repetition: n)
                }
            }
        }
    }
}
