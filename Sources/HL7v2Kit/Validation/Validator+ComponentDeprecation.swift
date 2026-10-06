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
    /// non-empty subcomponent, the HL7 null `""` included). Subcomponents are not
    /// checked: the legend speaks of data type components only.
    func checkComponentDeprecation(
        field: Field,
        version: Version,
        dataType: String,
        location: IssueLocation,
        issues: inout [ValidationIssue]
    ) {
        guard let keys = Self.componentDeprecationKeys[version.grammarVersion],
              Self.mayResolve(into: keys, segment: location.segmentID, field: location.fieldIndex,
                              dataType: dataType, version: version.grammarVersion),
              let composite = Self.fieldGrammar(segment: location.segmentID, field: location.fieldIndex,
                                                dataType: dataType, version: version.grammarVersion) else { return }
        for entry in composite.components {
            let code = entry.optionalityCode
            guard let state = Self.componentDeprecationState(optionality: code) else { continue }
            for (offset, repetition) in field.repetitions.enumerated()
            where repetition.components.count >= entry.index
                && repetition.components[entry.index - 1].subcomponents.contains(where: { !$0.value.isEmpty }) {
                let at = IssueLocation(segmentID: location.segmentID, segmentIndex: location.segmentIndex,
                                       fieldIndex: location.fieldIndex, componentIndex: entry.index,
                                       subcomponentIndex: nil)
                issues.append(ValidationIssue(
                    severity: .warning,
                    code: .componentNotSupported(optionality: code),
                    location: at,
                    message: "Component \(at.pathDescription) ('\(entry.name)') repetition \(offset + 1) is \(state) "
                        + "in v\(version.grammarVersion.rawValue) but populated"
                ))
            }
        }
    }

    /// The grammar keys of each grammar version with a component printed `B`, `X` or `W`.
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
