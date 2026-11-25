// SegmentGrammarLookupTests.swift
// The public segment grammar lookup (P01 R2) is the one the validator uses.

import Testing
@testable import HL7v2Kit

@Suite("Segment grammar lookup")
struct SegmentGrammarLookupTests {
    @Test("Every version's public table is the validator's table", arguments: Version.allCases)
    func tableMatchesValidator(_ version: Version) {
        let table = SegmentGrammarTable.table(for: version)
        #expect(!table.isEmpty)
        #expect(table == Validator.grammarTable(for: version))
        for (segmentID, grammar) in table {
            #expect(SegmentGrammarTable.grammar(segmentID, version: version) == grammar)
        }
    }

    @Test("v2.7 and v2.8 read the next point release's table (ADR-018)")
    func substitutedVersions() {
        #expect(SegmentGrammarTable.table(for: .v2_7) == SegmentGrammarTable.v2_7_1)
        #expect(SegmentGrammarTable.table(for: .v2_8) == SegmentGrammarTable.v2_8_2)
        #expect(SegmentGrammarTable.grammar("PID", version: .v2_8)?.version == "2.8.2")
    }

    @Test("An unknown segment ID has no grammar")
    func unknownSegment() {
        #expect(SegmentGrammarTable.grammar("ZZZ", version: .v2_5_1) == nil)
    }
}
