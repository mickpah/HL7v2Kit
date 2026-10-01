// BoundedRepetitionTests.swift
// P6-4 (V23-C08, V24-C07): a printed RP/# bound ("Y/2", "3") is kept and enforced.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Bounded repetition")
struct BoundedRepetitionTests {

    func line(_ id: String, _ fields: [Int: String]) -> String {
        let last = fields.keys.max() ?? 1
        return ([id] + (1...last).map { fields[$0] ?? "" }).joined(separator: "|") + "\r"
    }

    func cardinality(_ wire: String) throws -> [ValidationIssue] {
        try Validator().validate(Parser().parse(wire)).issues.filter { $0.code == .cardinalityExceeded }
    }

    @Test("The schema repeatability token parses a bound as .multiple")
    func wireValue() {
        #expect(FieldRepeatability(wireValue: "1") == .single)
        #expect(FieldRepeatability(wireValue: "*") == .multiple)
        #expect(FieldRepeatability(wireValue: "3") == .multiple)
        #expect(FieldRepeatability(wireValue: "2") == .multiple)
    }

    @Test("Printed bounds reach the grammar: v2.3 MSH-18 Y/3, v2.4 OBR-17 Y/2, v2.6 PID-38 2")
    func boundsInGrammar() {
        #expect(SegmentGrammarTable.v2_3["MSH"]?.field(18)?.maxRepetitions == 3)
        let obr17 = SegmentGrammarTable.v2_4["OBR"]?.field(17)
        #expect(obr17?.repeatability == .multiple)
        #expect(obr17?.maxRepetitions == 2)
        #expect(SegmentGrammarTable.v2_6["PID"]?.field(38)?.maxRepetitions == 2)
    }

    @Test("An unbounded Y field keeps maxRepetitions nil")
    func unboundedStaysNil() {
        let pid3 = SegmentGrammarTable.v2_5_1["PID"]?.field(3)
        #expect(pid3?.repeatability == .multiple)
        #expect(pid3?.maxRepetitions == nil)
    }

    @Test("Every bounded field is .multiple with a bound of at least 2")
    func boundedInvariant() {
        let tables = [SegmentGrammarTable.v2_3, SegmentGrammarTable.v2_3_1, SegmentGrammarTable.v2_4,
                      SegmentGrammarTable.v2_5_1, SegmentGrammarTable.v2_6, SegmentGrammarTable.v2_8_2]
        var bounded = 0
        for table in tables {
            for grammar in table.values {
                for field in grammar.fields {
                    guard let bound = field.maxRepetitions else { continue }
                    bounded += 1
                    #expect(field.repeatability == .multiple, "v\(grammar.version) \(grammar.segmentID)-\(field.index)")
                    #expect(bound >= 2, "v\(grammar.version) \(grammar.segmentID)-\(field.index)")
                }
            }
        }
        #expect(bounded >= 42, "v2.3 alone prints 42 Y/n rows (V23-C08)")
    }

    // G4: a new repetition-count check reports at .warning; the long-standing
    // single-cardinality check keeps .error.
    @Test("v2.4 OBR-17 (Y/2): two repetitions pass, three raise a cardinalityExceeded warning")
    func obr17Enforced() throws {
        let msh = "MSH|^~\\&|A|B|C|D|20240101120000||ORM^O01|M1|P|2.4\r"
        let two = msh + line("OBR", [1: "1", 4: "GLU^Glucose^L", 17: "5550001~5550002"])
        let three = msh + line("OBR", [1: "1", 4: "GLU^Glucose^L", 17: "5550001~5550002~5550003"])
        #expect(try cardinality(two).isEmpty)
        let issue = try #require(try cardinality(three).first)
        #expect(issue.location.segmentID == "OBR")
        #expect(issue.location.fieldIndex == 17)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("at most 2"))
    }

    @Test("A single-cardinality field keeps its existing message and error severity")
    func singleUnchanged() throws {
        let wire = "MSH|^~\\&|A|B|C|D|20240101120000||ADT^A01|M1|P|2.5.1\r"
            + line("PID", [1: "1", 3: "123", 8: "M~F"])
        let issue = try #require(try cardinality(wire).first { $0.location.fieldIndex == 8 })
        #expect(issue.message.contains("is single-cardinality but has 2 repetitions"))
        #expect(issue.severity == .error)
    }
}
