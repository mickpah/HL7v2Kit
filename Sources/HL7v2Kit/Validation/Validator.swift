// Validator.swift
// Structural + cardinality + Z-segment-policy validation. Reads the
// codegen-emitted `SegmentGrammarTable.v2_5_1` table (Path C from STATUS
// decisions log 2026-06-13). Non-fatal: returns a `ValidationReport`,
// never throws.

import Foundation

/// Validate a parsed `Message` against the loaded segment grammars.
public struct Validator: Sendable {
    public let options: ValidationOptions

    /// The locale this validator was configured with. Default `.international`.
    /// Propagates onto every `ValidationReport.locale` produced by
    /// `validate(_:)`. See ADR-007.
    public let locale: HL7Locale

    public init(options: ValidationOptions = .default, locale: HL7Locale = .international) {
        self.options = options
        self.locale = locale
    }

    /// Validate a message. Returns a non-empty report only when at least
    /// one check produced an issue.
    public func validate(_ message: Message) -> ValidationReport {
        var issues: [ValidationIssue] = []
        var segmentOccurrence: [String: Int] = [:]

        let grammar = grammarTable(for: message.version)
        // v0.4-S5-A / v0.5-S5-B: load the profile once per `validate(_:)`
        // call. nil for `.international`; for `.auLocalisation` returns
        // the AU ADRM-2021 profile with field-override narrowings layered
        // on top of base v2.4 / v2.5.1 grammar. See ADR-007.
        let profile = ProfileLoader.load(for: locale)

        for segment in message.segments {
            let id = segment.segmentID
            let occurrence = (segmentOccurrence[id] ?? 0) + 1
            segmentOccurrence[id] = occurrence

            guard let baseGrammar = grammar[id] else {
                // No grammar entry — treat as a Z-segment / unknown.
                appendZSegmentIssue(
                    id: id,
                    occurrence: occurrence,
                    issues: &issues
                )
                continue
            }

            // v0.5-S5-D: merge the profile's grammar extensions for
            // this segment (if any) onto the base grammar. Used for
            // AU pre-adoption of v2.5+ PID-35..38 on v2.4 wires under
            // `.auLocalisation`.
            let segGrammar = mergeGrammarExtension(
                base: baseGrammar,
                profileExtension: profile?.grammarExtensions[id]
            )

            checkSegment(
                segment,
                grammar: segGrammar,
                occurrence: occurrence,
                profile: profile,
                issues: &issues
            )
        }

        return ValidationReport(issues: issues, locale: locale)
    }

    // MARK: - Internals

    /// Merge a profile's grammar extension into a base segment
    /// grammar. The extension's fields APPEND to the base when their
    /// index doesn't already exist; they REPLACE the base field when
    /// the index does exist. v0.5-S5-D.
    ///
    /// The replacement semantic lets a profile both add new fields
    /// (typical case — AU PID-35..38 on v2.4) AND override an
    /// existing field's optionality / condition if needed in the
    /// future. Today only the additive case is exercised.
    private func mergeGrammarExtension(
        base: SegmentGrammar,
        profileExtension: [FieldGrammar]?
    ) -> SegmentGrammar {
        guard let profileExtension, !profileExtension.isEmpty else { return base }
        let extensionByIndex = Dictionary(
            uniqueKeysWithValues: profileExtension.map { ($0.index, $0) }
        )
        var mergedFields = base.fields.map { extensionByIndex[$0.index] ?? $0 }
        let baseIndices = Set(base.fields.map(\.index))
        let added = profileExtension
            .filter { !baseIndices.contains($0.index) }
            .sorted(by: { $0.index < $1.index })
        mergedFields.append(contentsOf: added)
        return SegmentGrammar(
            segmentID: base.segmentID,
            version: base.version,
            fields: mergedFields
        )
    }

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
        profile: Profile?,
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

            // v0.5-S5-B-1: layer the loaded profile's field overrides
            // on top of the base-spec checks. Only fires when locale
            // is non-international (profile != nil) AND the field has
            // an override AND the field is actually populated.
            if let profile, let field, isPopulated {
                checkProfileFieldOverrides(
                    profile: profile,
                    fieldGrammar: fieldGrammar,
                    field: field,
                    segmentID: grammar.segmentID,
                    segmentIndex: occurrence,
                    issues: &issues
                )
                // v0.5-S5-B-2: datatype-level composite overrides.
                checkProfileCompositeOverrides(
                    profile: profile,
                    fieldGrammar: fieldGrammar,
                    field: field,
                    segmentID: grammar.segmentID,
                    segmentIndex: occurrence,
                    issues: &issues
                )
            }
        }
    }

    /// Composite (datatype-keyed) override dispatch — v0.5-S5-B-2 +
    /// v0.5-S5-B-3. For every populated field whose HL7 dataType
    /// matches a `CompositeOverride` in the profile, evaluate two
    /// sub-rule tracks against each populated repetition:
    ///
    /// 1. **`requiredComponents`** (v0.5-S5-B-3) — each listed
    ///    component must be populated when the field is populated.
    ///    Used for HL7au:00044.1.2 (CX-4) / 00044.1.3 (CX-5).
    /// 2. **`pairRules`** (v0.5-S5-B-2) — pair-conditional rules.
    ///    Used for HL7au:00044.4/5/6 (CE/CNE/CWE).
    ///
    /// Both tracks emit `.profileConstraintViolation(localeRule:)`
    /// with the override's spec citation.
    private func checkProfileCompositeOverrides(
        profile: Profile,
        fieldGrammar: FieldGrammar,
        field: Field,
        segmentID: String,
        segmentIndex: Int,
        issues: inout [ValidationIssue]
    ) {
        guard let composite = profile.compositeOverrides.first(where: {
            $0.dataType == fieldGrammar.dataType
        }) else { return }

        for repetition in field.repetitions where isRepetitionPopulated(repetition) {
            // Track 1: required-components (v0.5-S5-B-3).
            for requirement in composite.requiredComponents {
                if isComponentPopulated(repetition, componentIndex: requirement.component) {
                    continue
                }
                let location = IssueLocation(
                    segmentID: segmentID,
                    segmentIndex: segmentIndex,
                    fieldIndex: fieldGrammar.index,
                    componentIndex: requirement.component
                )
                let citation = requirement.specCitation
                    ?? "\(profile.locale.rawValue):\(fieldGrammar.dataType).\(requirement.component)"
                issues.append(ValidationIssue(
                    severity: .error,
                    code: .profileConstraintViolation(localeRule: citation),
                    location: location,
                    message: "AU profile rule violated at \(location.pathDescription): \(fieldGrammar.dataType)-\(requirement.component) must be populated when \(fieldGrammar.dataType) field is populated (\(citation))"
                ))
            }
            // Track 2: pair-conditional rules (v0.5-S5-B-2).
            for rule in composite.pairRules {
                let ifPopulated = isComponentPopulated(repetition, componentIndex: rule.ifComponent)
                let triggered = (rule.condition == .populated) == ifPopulated
                guard triggered else { continue }

                let thenPopulated = isComponentPopulated(repetition, componentIndex: rule.thenComponent)
                let satisfied = (rule.requirement == .mustBePopulated) == thenPopulated
                guard !satisfied else { continue }

                let location = IssueLocation(
                    segmentID: segmentID,
                    segmentIndex: segmentIndex,
                    fieldIndex: fieldGrammar.index,
                    componentIndex: rule.thenComponent
                )
                let citation = rule.specCitation
                    ?? "\(profile.locale.rawValue):\(fieldGrammar.dataType).\(rule.thenComponent)"
                let condDesc = rule.condition == .populated ? "is populated" : "is empty"
                let reqDesc = rule.requirement == .mustBePopulated ? "must be populated" : "must be empty"
                issues.append(ValidationIssue(
                    severity: .error,
                    code: .profileConstraintViolation(localeRule: citation),
                    location: location,
                    message: "AU profile rule violated at \(location.pathDescription): \(fieldGrammar.dataType)-\(rule.thenComponent) \(reqDesc) when \(fieldGrammar.dataType)-\(rule.ifComponent) \(condDesc) (\(citation))"
                ))
            }
        }
    }

    /// AU profile override dispatch. For each populated field that has
    /// a `FieldOverride` in the loaded profile, check the override's
    /// `requiredComponents` rule: every listed 1-based component index
    /// must be populated in every populated repetition. Failures emit
    /// `.profileConstraintViolation(localeRule:)`.
    ///
    /// v0.5-S5-B-1 ships the OBR-2/3 + ORC-2/3/4 EI-completeness rules
    /// from HL7au:000003 / 000004.1 / 000005 / 000006 / 000007. The
    /// `localeRule` value carries the HL7au identifier so consumers
    /// can attribute the failure precisely. See
    /// `Sources/HL7v2Kit/Locale/Profile+au_adrm_2021.swift`.
    private func checkProfileFieldOverrides(
        profile: Profile,
        fieldGrammar: FieldGrammar,
        field: Field,
        segmentID: String,
        segmentIndex: Int,
        issues: inout [ValidationIssue]
    ) {
        guard let override = profile.fieldOverrides.first(where: {
            $0.segmentID == segmentID && $0.fieldIndex == fieldGrammar.index
        }) else { return }
        guard !override.requiredComponents.isEmpty || !override.componentValueSets.isEmpty else { return }

        for repetition in field.repetitions where isRepetitionPopulated(repetition) {
            // Track 1 (v0.5-S5-B-1): required-component narrowings.
            for componentIndex in override.requiredComponents {
                if isComponentPopulated(repetition, componentIndex: componentIndex) {
                    continue
                }
                let location = IssueLocation(
                    segmentID: segmentID,
                    segmentIndex: segmentIndex,
                    fieldIndex: fieldGrammar.index,
                    componentIndex: componentIndex
                )
                let citation = override.specCitation
                    ?? "\(profile.locale.rawValue):\(segmentID)-\(fieldGrammar.index).\(componentIndex)"
                issues.append(ValidationIssue(
                    severity: .error,
                    code: .profileConstraintViolation(localeRule: citation),
                    location: location,
                    message: "AU profile rule violated at \(location.pathDescription): \(fieldGrammar.dataType) component \(componentIndex) must be populated when \(segmentID)-\(fieldGrammar.index) ('\(fieldGrammar.name)') is populated (\(citation))"
                ))
            }
            // Track 2 (v0.5-S5-C): per-component value-set narrowings.
            for valueSet in override.componentValueSets {
                let actual = componentScalarValue(in: repetition, componentIndex: valueSet.component)
                if valueSet.allowedValues.contains(actual) { continue }
                let location = IssueLocation(
                    segmentID: segmentID,
                    segmentIndex: segmentIndex,
                    fieldIndex: fieldGrammar.index,
                    componentIndex: valueSet.component
                )
                let citation = valueSet.specCitation
                    ?? "\(profile.locale.rawValue):\(segmentID)-\(fieldGrammar.index).\(valueSet.component)"
                let allowedList = valueSet.allowedValues.map { "\"\($0)\"" }.joined(separator: ", ")
                issues.append(ValidationIssue(
                    severity: .error,
                    code: .profileConstraintViolation(localeRule: citation),
                    location: location,
                    message: "AU profile value-set rule violated at \(location.pathDescription): expected one of [\(allowedList)] but got \"\(actual)\" (\(citation))"
                ))
            }
        }
    }

    /// First-subcomponent scalar of the 1-based `componentIndex`-th
    /// component in `repetition`. Returns the empty string when the
    /// component or subcomponent is out of bounds — matches the
    /// semantic "empty / missing" for value-set comparisons. v0.5-S5-C.
    private func componentScalarValue(in repetition: Repetition, componentIndex: Int) -> String {
        guard repetition.components.indices.contains(componentIndex - 1) else { return "" }
        let component = repetition.components[componentIndex - 1]
        return component.subcomponents.first?.value ?? ""
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

    /// Component-level grammar check (v0.2-V2 + v0.4-S4). When a
    /// composite-typed field is populated, walks every repetition and
    /// dispatches two kinds of conformance check:
    ///
    /// 1. **Flat required-component check.** For each component listed
    ///    in the composite's `requiredComponents`, emits one
    ///    ``IssueCode/requiredComponentMissing`` if the component is
    ///    empty. Models simple "this component must always be populated"
    ///    rules (XPN-1 family, CX-1 ID, XAD-1 street, etc.).
    ///
    /// 2. **OR-rule check** (v0.4-S4). For composites whose v2.5.1
    ///    conformance is "at least one of these components" or "this
    ///    group OR at least one of those" — `CWE`, `XTN`, `HD`, `PL`,
    ///    `EIP` — dispatches to the composite's `requiredComponentSet`
    ///    and emits one issue when the OR-rule is violated. See
    ///    ``RequiredComponentSet`` for the semantics.
    ///
    /// Composite types HL7v2Kit doesn't have typed metadata for skip
    /// silently in both dispatches.
    private func checkComponents(
        _ grammar: FieldGrammar,
        field: Field,
        segmentID: String,
        segmentIndex: Int,
        issues: inout [ValidationIssue]
    ) {
        let required = requiredComponents(forCompositeCode: grammar.dataType)
        let requiredSet = requiredComponentSet(forCompositeCode: grammar.dataType)
        guard !required.isEmpty || requiredSet != nil else { return }
        for repetition in field.repetitions where isRepetitionPopulated(repetition) {
            // (1) Flat required-component check.
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
            // (2) OR-rule check.
            if let set = requiredSet {
                let populatedIndices = populatedComponentIndices(in: repetition)
                if !set.isSatisfied(populatedIndices: populatedIndices) {
                    let location = IssueLocation(
                        segmentID: segmentID,
                        segmentIndex: segmentIndex,
                        fieldIndex: grammar.index
                    )
                    issues.append(ValidationIssue(
                        severity: .error,
                        code: .requiredComponentMissing,
                        location: location,
                        message: "OR-rule violated in \(grammar.dataType) field \(location.pathDescription) ('\(grammar.name)'): expected \(set.description) populated"
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

    /// Map an HL7 composite data-type code to the type's OR-rule
    /// `requiredComponentSet` metadata, if it publishes one. Returns nil
    /// for composites whose spec conformance is a flat "all-of" rule
    /// (no OR-rule disjunction). v0.4-S4.
    private func requiredComponentSet(forCompositeCode code: String) -> RequiredComponentSet? {
        switch code {
        case "CWE": return CWE.requiredComponentSet
        case "XTN": return XTN.requiredComponentSet
        case "HD":  return HD.requiredComponentSet
        case "PL":  return PL.requiredComponentSet
        case "EIP": return EIP.requiredComponentSet
        default:    return nil
        }
    }

    /// Collect the 1-based component indices that are populated in a
    /// repetition. Used by the OR-rule check to evaluate
    /// `RequiredComponentSet.isSatisfied(populatedIndices:)`. v0.4-S4.
    private func populatedComponentIndices(in repetition: Repetition) -> Set<Int> {
        var indices: Set<Int> = []
        for (offset, component) in repetition.components.enumerated() {
            let oneBased = offset + 1
            for subcomponent in component.subcomponents {
                if !subcomponent.value.isEmpty {
                    indices.insert(oneBased)
                    break
                }
            }
        }
        return indices
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

    /// Evaluate a condition predicate against a single segment.
    /// v0.2-V1 introduced the single-atom DSL; v0.4-S4 extends it with
    /// compound `AND` / `OR` combinators and `in (…)` / `not in (…)`
    /// set-membership operators so the v2.5.1 spec's compound
    /// conditional rules (ORC-2 "required when ORC-1 in {NW, CA, CR,
    /// DC, …}", OBR-1 / OBR-7 / OBR-22 etc.) can be expressed
    /// faithfully.
    ///
    /// Grammar (recursive descent, precedence AND-binds-tighter-than-OR):
    /// ```
    /// <predicate>  := <or-expr>
    /// <or-expr>    := <and-expr> (" OR " <and-expr>)*
    /// <and-expr>   := <atom> (" AND " <atom>)*
    /// <atom>       := <fieldref> " " <op>
    /// <fieldref>   := <segmentID> "-" <int>
    /// <op>         := "populated"
    ///               | "empty"
    ///               | "= <value>"
    ///               | "!= <value>"
    ///               | "in (<values>)"
    ///               | "not in (<values>)"
    /// <values>     := <value> ("," " "* <value>)*
    /// ```
    /// Cross-segment references (segmentID ≠ currentSegmentID) and any
    /// malformed sub-expression fail safe — that sub-expression returns
    /// `false`. Per v0.2-V1 design: a malformed schema must never make a
    /// previously-accepted message non-conformant.
    private func conditionTriggers(
        _ condition: String,
        in segment: Segment,
        currentSegmentID: String
    ) -> Bool {
        evaluateOrExpression(condition, in: segment, currentSegmentID: currentSegmentID)
    }

    /// Top-level OR: split on `" OR "` at the topmost level. Any clause
    /// evaluating true short-circuits to true.
    private func evaluateOrExpression(
        _ expression: String,
        in segment: Segment,
        currentSegmentID: String
    ) -> Bool {
        for clause in expression.components(separatedBy: " OR ") {
            if evaluateAndExpression(clause, in: segment, currentSegmentID: currentSegmentID) {
                return true
            }
        }
        return false
    }

    /// AND: every conjunct must evaluate true.
    private func evaluateAndExpression(
        _ expression: String,
        in segment: Segment,
        currentSegmentID: String
    ) -> Bool {
        for atom in expression.components(separatedBy: " AND ") {
            if !evaluateAtom(atom, in: segment, currentSegmentID: currentSegmentID) {
                return false
            }
        }
        return true
    }

    /// Single atomic predicate: `<segmentID>-<index> <op>`.
    private func evaluateAtom(
        _ atom: String,
        in segment: Segment,
        currentSegmentID: String
    ) -> Bool {
        let trimmed = atom.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                            .map(String.init)
        guard parts.count == 2 else { return false }
        let fieldRef = parts[0]
        let predicate = parts[1]

        let refParts = fieldRef.split(separator: "-", maxSplits: 1).map(String.init)
        guard refParts.count == 2,
              refParts[0] == currentSegmentID,
              let fieldIndex = Int(refParts[1])
        else { return false }

        let field = segment.field(fieldIndex)
        let isReferentPopulated = field.map { isFieldPopulated($0) } ?? false
        let raw = field?.repetitions.first?.components.first?.subcomponents.first?.value ?? ""

        if predicate == "populated" { return isReferentPopulated }
        if predicate == "empty"     { return !isReferentPopulated }
        if predicate.hasPrefix("= ") {
            return raw == String(predicate.dropFirst(2))
        }
        if predicate.hasPrefix("!= ") {
            return raw != String(predicate.dropFirst(3))
        }
        if predicate.hasPrefix("in (") && predicate.hasSuffix(")") {
            let values = Self.parseValueList(predicate.dropFirst(4).dropLast())
            return values.contains(raw)
        }
        if predicate.hasPrefix("not in (") && predicate.hasSuffix(")") {
            let values = Self.parseValueList(predicate.dropFirst(8).dropLast())
            // not-in fires only if the referent is actually populated —
            // an empty referent isn't a member of any set but it's also
            // not a meaningful "non-member" assertion. Treat empty as
            // "not in" being false (no trigger) per the fail-safe rule:
            // the conditional check should only require the dependent
            // field when the referent carries a definite value the
            // predicate excludes.
            guard isReferentPopulated else { return false }
            return !values.contains(raw)
        }
        return false
    }

    /// Parse `"NW, CA, CR, DC"` (or `"NW,CA,CR"`) into the value list
    /// `["NW", "CA", "CR", "DC"]`. Whitespace around commas is trimmed.
    private static func parseValueList<S: StringProtocol>(_ raw: S) -> [String] {
        raw.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
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
