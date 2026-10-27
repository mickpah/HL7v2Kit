// SignatureCompatibilityTests+X1.swift
// ADR-014 pins for the X1 additions, apart from SignatureCompatibilityTests.swift, which is
// past 300 lines. Each binds a public signature, so changing it stops this file compiling.

import Testing
import HL7v2Kit

extension SignatureCompatibilityTests {
    @Test("X1: IssueCode.number keeps its signature")
    func issueCodeNumberSignature() {
        let number: KeyPath<IssueCode, Int> = \.number
        #expect(IssueCode.requiredFieldMissing[keyPath: number] == 2001)
    }
}
