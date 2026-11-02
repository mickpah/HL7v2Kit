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
}
