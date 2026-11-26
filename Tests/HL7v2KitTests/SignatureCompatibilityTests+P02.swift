// SignatureCompatibilityTests+P02.swift
// ADR-014 pins for the additions of the P02 requirements. Changing any of them stops this
// file compiling.

import Foundation
import Testing
import HL7v2Kit

extension SignatureCompatibilityTests {
    @Test("Message.indexOfSegment(at:) keeps its signature")
    func indexOfSegmentSignature() {
        let index: (Message) -> (Path) -> Int? = Message.indexOfSegment(at:)
        _ = index
    }
}
