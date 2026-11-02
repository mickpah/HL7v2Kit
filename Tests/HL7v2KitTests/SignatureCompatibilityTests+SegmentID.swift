// SignatureCompatibilityTests+SegmentID.swift
// ADR-014 pin for the segment ID finding (#11). Changing the case stops this file compiling.

import Testing
import HL7v2Kit

extension SignatureCompatibilityTests {
    @Test("Segment ID: the issue code keeps its signature and number")
    func segmentIDSignatures() {
        let code: IssueCode = .segmentIDMalformed
        #expect(code.number == 1014)
    }
}
