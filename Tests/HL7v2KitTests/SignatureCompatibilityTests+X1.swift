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

    @Test("X1: ValidationOptions.valueExcerpts keeps its signature and defaults on")
    func valueExcerptsSignature() {
        let excerpts: WritableKeyPath<ValidationOptions, Bool> = \.valueExcerpts
        #expect(ValidationOptions.default[keyPath: excerpts])
    }

    @Test("X1: Anonymiser keeps its signatures")
    func anonymiserSignatures() {
        let make: (UInt64, (@Sendable (Anonymiser.Identifier) -> String)?) -> Anonymiser = Anonymiser.init(key:replacingIdentifier:)
        let anonymise: (Anonymiser) -> (Message) -> Message = Anonymiser.anonymise
        let value: KeyPath<Anonymiser.Identifier, String> = \.value
        let typeCode: KeyPath<Anonymiser.Identifier, String?> = \.typeCode
        let authority: KeyPath<Anonymiser.Identifier, String?> = \.assigningAuthority
        let seed: KeyPath<Anonymiser.Identifier, UInt64> = \.seed
        _ = (make, anonymise, value, typeCode, authority, seed)
    }
}
