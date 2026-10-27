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
}
