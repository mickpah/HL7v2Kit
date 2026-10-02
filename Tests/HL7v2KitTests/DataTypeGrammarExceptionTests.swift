import Testing
@testable import HL7v2Kit

// P5 final review: the two cited exceptions to the datatype grammar's ordinary reading.
@Suite("Datatype grammar: cited exceptions")
struct DataTypeGrammarExceptionTests {
    private func issues(_ segments: [String], at segmentID: String, field: Int) throws -> [ValidationIssue] {
        let wire = segments.joined(separator: "\r") + "\r"
        return Validator().validate(try Parser().parse(wire)).issues.filter {
            $0.location.segmentID == segmentID && $0.location.fieldIndex == field
        }
    }

    private func order(_ tq: String, _ version: String) -> [String] {
        ["MSH|^~\\&|A|B|C|D|200001011200||ORM^O01|1|P|\(version)", "PID|||123||DOE^JOHN", "ORC|NW|1|||||\(tq)|"]
    }

    // v2.3 / v2.3.1 section 4.4.6: the Priority component may repeat, through the repeat
    // delimiter. The parser reads that delimiter as a field repetition.
    @Test("TQ.6 priority repeat is silent on v2.3 and v2.3.1", arguments: ["2.3", "2.3.1"])
    func tqPriorityRepeatSilent(version: String) throws {
        let found = try issues(order("1^Q6H^^200001011200^^S~A^^^S", version), at: "ORC", field: 7)
        #expect(found.isEmpty, "\(found.map(\.message))")
    }

    @Test("TQ.6 priority repeat still reports on v2.4, which repeats priority with a space (4.3.6)")
    func tqPriorityRepeatV24() throws {
        let found = try issues(order("1^Q6H^^200001011200^^S~A^^^S", "2.4"), at: "ORC", field: 7)
        // v2.4 ORC-7 repeats, so no cardinality error: repetition 2 is a TQ of its own.
        #expect(found.contains { $0.code == .valueFormatInvalid(dataType: "TS") && $0.message.contains("repetition 2") })
    }

    @Test("A malformed TS in repetition 1 still warns under the priority repeat", arguments: ["2.3", "2.3.1"])
    func tqPriorityRepeatFirstRepetitionChecked(version: String) throws {
        let found = try issues(order("1^Q6H^^2000XX01^^S~A^^^S", version), at: "ORC", field: 7)
        #expect(found.contains { if case .valueFormatInvalid = $0.code { return true } else { return false } })
        #expect(!found.contains { $0.code == .cardinalityExceeded })
    }

    // v2.3 section 2.24.4.11 prints QRD-11 as (CM) with Components: <first data code value (ST)>
    // ^ <last data code value (ST)>; its attribute table prints ST. The Components line wins.
    @Test("v2.3 QRD-11 takes its printed two-component grammar")
    func qrd11PrintedComponents() throws {
        #expect(SegmentGrammarTable.v2_3["QRD"]?.field(11)?.dataType == "CM")
        let grammar = try #require(DataTypeGrammarTable.grammar(segment: "QRD", field: 11, version: .v2_3))
        #expect(grammar.components.map(\.dataType) == ["ST", "ST"])
        func query(_ value: String) -> [String] {
            ["MSH|^~\\&|A|B|C|D|200001011200||QRY^A19|1|P|2.3", "QRD|200001011200|R|I|Q1|||1^RD|123|DEM|ALL|\(value)|"]
        }
        let silent = try issues(query("A^Z"), at: "QRD", field: 11)
        #expect(silent.isEmpty, "\(silent.map(\.message))")
        let wide = try issues(query("A^Z^Q"), at: "QRD", field: 11)
        #expect(wide.contains { $0.code == .extraComponentsInCompositeField && $0.severity == .warning })
    }
}
