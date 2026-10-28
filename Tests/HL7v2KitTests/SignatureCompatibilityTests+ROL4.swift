// SignatureCompatibilityTests+ROL4.swift
// ADR-014 pins for the ROL-4 correlation additions, the issue code and the option. Changing either
// stops this file compiling.

import Testing
import HL7v2Kit

extension SignatureCompatibilityTests {
    @Test("ROL-4 correlation: the issue code and the option keep their signatures")
    func correlationSignatures() {
        let severity: WritableKeyPath<ValidationOptions, IssueSeverity?> = \.correlationSeverity
        let code: IssueCode = .correlatedValueMismatch
        _ = severity
        #expect(code.number == 3005)
    }
}
