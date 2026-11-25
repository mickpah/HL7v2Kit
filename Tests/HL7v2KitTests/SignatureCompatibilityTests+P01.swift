// SignatureCompatibilityTests+P01.swift
// ADR-014 pins for the P01 additions. Changing any of them stops this file compiling.

import Foundation
import Testing
import HL7v2Kit

extension SignatureCompatibilityTests {
    @Test("P01 R2: the segment grammar lookups keep their signatures")
    func segmentGrammarLookupSignatures() {
        let table: (Version) -> [String: SegmentGrammar] = SegmentGrammarTable.table(for:)
        let grammar: (String, Version) -> SegmentGrammar? = SegmentGrammarTable.grammar(_:version:)
        _ = (table, grammar)
    }
}
