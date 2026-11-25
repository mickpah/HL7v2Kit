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

    @Test("P01 R3: SegmentGrammar.name and the naming initialiser keep their signatures")
    func segmentNameSignatures() {
        let name: KeyPath<SegmentGrammar, String> = \.name
        let make: (String, String, String, [FieldGrammar]) -> SegmentGrammar = SegmentGrammar.init(segmentID:name:version:fields:)
        _ = (name, make)
    }

    @Test("P01 R9: Parser.wire(fromCarried:) keeps both signatures")
    func carriedTextSignatures() {
        let bytes: (Data) -> Data = Parser.wire(fromCarried:)
        let text: (String) -> String = Parser.wire(fromCarried:)
        _ = (bytes, text)
    }
}
