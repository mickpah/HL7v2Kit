// SignatureCompatibilityTests+EngineeringGaps.swift
// ADR-014 pins for the 3.31.0 additions. Each binds a public signature, so changing it stops this
// file compiling.

import Testing
import HL7v2Kit

extension SignatureCompatibilityTests {
    @Test("EG: the escape issue code and its option keep their signatures")
    func escapeSequenceSignatures() {
        let code: IssueCode = .escapeSequenceUndefined
        #expect(code.number == 3007)
        let severity: WritableKeyPath<ValidationOptions, IssueSeverity?> = \.escapeSequenceSeverity
        #expect(ValidationOptions.default[keyPath: severity] == .warning)
    }

    @Test("EG: the condition lint keeps its signatures")
    func conditionIssueSignatures() {
        let lint: (SegmentGrammar) -> () -> [ConditionIssue] = SegmentGrammar.conditionIssues
        let make: (Int, ConditionIssue.Source, String, ConditionIssue.Reason) -> ConditionIssue =
            ConditionIssue.init(fieldIndex:source:atom:reason:)
        let fieldIndex: KeyPath<ConditionIssue, Int> = \.fieldIndex
        let source: KeyPath<ConditionIssue, ConditionIssue.Source> = \.source
        let atom: KeyPath<ConditionIssue, String> = \.atom
        let reason: KeyPath<ConditionIssue, ConditionIssue.Reason> = \.reason
        let sources: [ConditionIssue.Source] = [.condition, .prohibitedWhen, .additionalProhibition(index: 0)]
        let reasons: [ConditionIssue.Reason] = [.missingPredicate, .malformedPredicate, .malformedFieldReference,
                                                .unknownReferent]
        _ = (lint, make, fieldIndex, source, atom, reason)
        #expect(Set(sources).count == 3 && Set(reasons).count == 4)
    }
}
