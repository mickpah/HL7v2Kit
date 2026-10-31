// SignatureCompatibilityTests+P00.swift
// ADR-014 pins for the P00 additions. Changing any of them stops this file compiling.

import Testing
import HL7v2Kit

extension SignatureCompatibilityTests {
    @Test("P00 S1-1: Message.trailingSegmentTerminator keeps its signature")
    func trailingSegmentTerminatorSignature() {
        let flag: WritableKeyPath<Message, Bool> = \.trailingSegmentTerminator
        _ = flag
    }
}
