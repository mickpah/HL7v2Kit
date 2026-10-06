import Foundation

extension Validator {
    /// Populated components that the datatype's component table prints `B` ("left in
    /// for backward compatibility"), `X` ("not used with this trigger event") or `W`
    /// ("withdrawn") (S1-2, register section G; `X` added in S1-5, as the legend defines
    /// it, though no extracted component table prints it today). The
    /// optionality legend applies to components from v2.5 ("For version 2.5 and higher,
    /// the optionality ... of data type components are supplied in component tables",
    /// v2.8.2 CH02 section 2.5.3.5); v2.3 to v2.4 grammars carry no code, so nothing is
    /// read there. The caller skips a field already reported as `fieldNotSupported`, so
    /// one finding covers the whole field. A component is populated as a field is (any
    /// non-empty subcomponent, the HL7 null `""` included).
    ///
    /// A component table binds wherever its type is used ("the optionality, table
    /// references, and lengths of data type components are supplied in component tables
    /// of the data type definition", v2.5.1 CH02 section 2.5.3.4), so a populated
    /// subcomponent of a composite component is read against the component table of the
    /// component's own type on the same version (S1-fix I1): v2.5.1 TS.2 (`B`) inside
    /// DR.1 is reported at `DR.1.2`. A component already reported is not walked, so one
    /// finding covers it.
    func checkComponentDeprecation(
        field: Field,
        version: Version,
        dataType: String,
        location: IssueLocation,
        issues: inout [ValidationIssue]
    ) {
        let grammarVersion = version.grammarVersion
        guard let keys = Self.componentDeprecationKeys[grammarVersion],
              Self.mayResolve(into: keys, segment: location.segmentID, field: location.fieldIndex,
                              dataType: dataType, version: grammarVersion),
              let composite = Self.fieldGrammar(segment: location.segmentID, field: location.fieldIndex,
                                                dataType: dataType, version: grammarVersion) else { return }
        func report(_ code: String, _ state: String, component: Int, subcomponent: Int?, _ text: String) {
            let at = IssueLocation(segmentID: location.segmentID, segmentIndex: location.segmentIndex,
                                   fieldIndex: location.fieldIndex, componentIndex: component,
                                   subcomponentIndex: subcomponent)
            issues.append(ValidationIssue(
                severity: .warning,
                code: .componentNotSupported(optionality: code),
                location: at,
                message: (subcomponent == nil ? "Component " : "Subcomponent ") + "\(at.pathDescription) " + text
                    + " is \(state) in v\(grammarVersion.rawValue) but populated"
            ))
        }
        for entry in composite.components {
            let code = entry.optionalityCode
            if let state = Self.componentDeprecationState(optionality: code) {
                for (offset, repetition) in field.repetitions.enumerated()
                where repetition.components.count >= entry.index
                    && repetition.components[entry.index - 1].subcomponents.contains(where: { !$0.value.isEmpty }) {
                    report(code, state, component: entry.index, subcomponent: nil,
                           "('\(entry.name)') repetition \(offset + 1)")
                }
                continue
            }
            guard let inner = Self.componentGrammar(entry.dataType, version: grammarVersion) else { continue }
            for sub in inner.components {
                guard let state = Self.componentDeprecationState(optionality: sub.optionalityCode) else { continue }
                for (offset, repetition) in field.repetitions.enumerated()
                where repetition.components.count >= entry.index {
                    let parts = repetition.components[entry.index - 1].subcomponents
                    guard parts.count >= sub.index, !parts[sub.index - 1].value.isEmpty else { continue }
                    report(sub.optionalityCode, state, component: entry.index, subcomponent: sub.index,
                           "('\(sub.name)') of component \(entry.index) ('\(entry.name)') repetition \(offset + 1)")
                }
            }
        }
    }

    /// The grammar keys of each grammar version with a component, or a subcomponent of a
    /// composite component, printed `B`, `X` or `W`.
    static let componentDeprecationKeys: [Version: Set<String>] = grammarKeys { entry, _ in
        componentDeprecationState(optionality: entry.optionalityCode) != nil
    }

    /// The message wording for a component optionality code the check reports, or nil
    /// for a code it does not report (`R`, `RE`, `O`, `C`, or none printed).
    static func componentDeprecationState(optionality code: String) -> String? {
        switch code {
        case "B": "kept for backward compatibility only (B)"
        case "X": "not supported (X)"
        case "W": "withdrawn from the standard (W)"
        default: nil
        }
    }
}
