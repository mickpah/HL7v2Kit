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

    @Test("P00 S1-3: ParseError.lineFeedAfterSegmentTerminator keeps its signature")
    func lineFeedErrorSignature() {
        let error: ParseError = .lineFeedAfterSegmentTerminator(position: 2)
        #expect(error == .lineFeedAfterSegmentTerminator(position: 2))
        #expect(error.description.contains("2"))
    }
}
