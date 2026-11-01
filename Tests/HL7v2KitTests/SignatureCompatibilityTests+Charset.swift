// SignatureCompatibilityTests+Charset.swift
// ADR-014 pin for the character-set finding (#16). Changing the case stops this file compiling.

import Testing
import HL7v2Kit

extension SignatureCompatibilityTests {
    @Test("Character set: the issue code keeps its signature and number")
    func characterSetSignatures() {
        let code: IssueCode = .characterNotEncodable(declared: "ASCII")
        #expect(code.number == 3006)
    }
}
