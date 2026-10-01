// Validator+ProfileProhibitions.swift
// P4-24 — profile-authored field prohibitions (HL7au:00060.4 route B), and
// the HL7 null test that base `permitsNull` prohibitions share (P4-26).

extension Validator {
    /// Report every `ProfileFieldProhibition` on the matching field
    /// overrides whose condition holds while the field carries a value
    /// other than the HL7 null (`""`). The null is what "valued with
    /// null" asks for, so it never fires. Conditions go through the shared
    /// `conditionTriggers` evaluator, so an unresolvable predicate stays
    /// silent. Base validation is untouched.
    func checkProfileFieldProhibitions(
        profile: Profile,
        field: Field,
        segment: Segment,
        segmentArrayIndex: Int,
        message: Message,
        location: IssueLocation,
        issues: inout [ValidationIssue]
    ) {
        // Collects from every matching override (`.filter` + `.flatMap`),
        // not the `.first(where:)` the two base-grammar override lookups
        // in Validator.swift use. Today the AU profile authors at most one
        // `FieldOverride` per (segmentID, fieldIndex), so the two
        // approaches agree; `.first(where:)` would silently drop a second
        // override's prohibitions if a future profile ever split one
        // field's rules across more than one `FieldOverride` entry (P4-16).
        let rules = profile.fieldOverrides
            .filter { $0.segmentID == location.segmentID && $0.fieldIndex == location.fieldIndex }
            .flatMap(\.prohibitions)
        guard !rules.isEmpty, carriesNonNullValue(field) else { return }
        for rule in rules where conditionTriggers(
            rule.condition,
            in: segment,
            segmentIndex: segmentArrayIndex,
            message: message,
            currentSegmentID: location.segmentID
        ) {
            issues.append(ValidationIssue(
                severity: rule.severity,
                code: .profileConstraintViolation(localeRule: rule.specCitation),
                location: location,
                message: "AU profile rule violated at \(location.pathDescription): field must not be valued while '\(rule.condition)' holds (\(rule.specCitation))"
            ))
        }
    }

    /// True when some repetition holds content other than a lone HL7
    /// null (`""`). Shared by the profile prohibitions above and by the
    /// base `FieldProhibition.permitsNull` rules (P4-26), so both treat
    /// the null the same way.
    func carriesNonNullValue(_ field: Field) -> Bool {
        field.repetitions.contains { repetition in
            if repetition.stringValue == "\"\"" { return false }
            return repetition.components.contains { component in
                component.subcomponents.contains { !$0.value.isEmpty }
            }
        }
    }
}
