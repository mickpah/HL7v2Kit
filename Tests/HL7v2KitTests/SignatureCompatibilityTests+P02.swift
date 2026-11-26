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

    @Test("Version.MSH12Reading and Message.msh12Reading keep their signatures")
    func msh12ReadingSignature() {
        let reading: KeyPath<Message, Version.MSH12Reading> = \.msh12Reading
        let cases: [Version.MSH12Reading] = [.empty, .recognised(.v2_5_1), .unresolved(vid1: "")]
        let sendable: any Sendable = cases
        _ = (reading, sendable)
    }
}
