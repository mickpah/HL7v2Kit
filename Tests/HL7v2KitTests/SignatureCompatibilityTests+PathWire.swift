// SignatureCompatibilityTests+PathWire.swift
// ADR-014 pins for the segment-only path (P01 R12) and the wire text of a value (P01 R13).
// Changing any of them stops this file compiling.

import Foundation
import Testing
import HL7v2Kit

extension SignatureCompatibilityTests {
    @Test("R12: Path.isSegmentOnly, Path(segmentID:segmentIndex:) and Message.segment(at:) keep their signatures")
    func segmentOnlyPathSignatures() {
        let only: KeyPath<Path, Bool> = \.isSegmentOnly
        let make: (String, Int?) -> Path = Path.init(segmentID:segmentIndex:)
        let segment: (Message) -> (Path) -> Segment? = Message.segment(at:)
        _ = (only, make, segment)
    }

    @Test("R13: Message.wireText(at:) keeps its signature")
    func wireTextSignature() {
        let text: (Message) -> (Path) -> String? = Message.wireText(at:)
        _ = text
    }
}
