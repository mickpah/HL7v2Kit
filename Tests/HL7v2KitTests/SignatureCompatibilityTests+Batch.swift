// SignatureCompatibilityTests+Batch.swift
// ADR-014 pins for the batch envelope additions. Each binds a public signature, so changing it
// stops this file compiling.

import Testing
import HL7v2Kit

extension SignatureCompatibilityTests {
    @Test("Batch envelopes: the parsed envelope properties keep their signatures")
    func batchEnvelopeSegmentSignatures() {
        let fileHeader: KeyPath<BatchFile, Segment?> = \.fileHeaderSegment
        let fileTrailer: KeyPath<BatchFile, Segment?> = \.fileTrailerSegment
        let header: KeyPath<BatchGroup, Segment?> = \.headerSegment
        let trailer: KeyPath<BatchGroup, Segment?> = \.trailerSegment
        _ = (fileHeader, fileTrailer, header, trailer)
    }

    @Test("Batch envelopes: the codes and the option keep their signatures")
    func batchEnvelopeCheckSignatures() {
        let severity: WritableKeyPath<ValidationOptions, IssueSeverity?> = \.batchEnvelopeSeverity
        let count: (String, Int) -> IssueCode = IssueCode.batchCountMismatch(declared:actual:)
        let malformed: (String) -> IssueCode = IssueCode.batchEnvelopeMalformed(segmentID:)
        _ = (severity, count, malformed)
        #expect(IssueCode.batchCountMismatch(declared: "", actual: 0).number == 2009)
        #expect(IssueCode.batchEnvelopeMalformed(segmentID: "").number == 1013)
    }
}
