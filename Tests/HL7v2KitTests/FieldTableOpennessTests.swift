// FieldTableOpennessTests.swift
// Per-field table openness (P2-15, ADR-016): a field whose own prose cites a closed HL7
// table "for suggested values" (or calls it User-defined, or says it can be extended) is
// marked `tableOpen` in its schema entry, and the field-level closed-table check skips it.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Per-field table openness")
struct FieldTableOpennessTests {

    /// A minimal message carrying `value` at `segment-index`.
    private func wire(_ version: String, _ segment: String, _ index: Int, _ value: String) -> String {
        "MSH|^~\\&|HIS|FAC|LAB|FAC|||ADT^A01|MSG00001|P|\(version)\r"
            + segment + String(repeating: "|", count: index) + value + "\r"
    }

    /// The generated grammar table the Validator reads for `version`.
    private func grammars(_ version: Version) -> [String: SegmentGrammar] {
        switch version {
        case .v2_3: SegmentGrammarTable.v2_3
        case .v2_3_1: SegmentGrammarTable.v2_3_1
        case .v2_4: SegmentGrammarTable.v2_4
        case .v2_5_1: SegmentGrammarTable.v2_5_1
        case .v2_6: SegmentGrammarTable.v2_6
        case .v2_8_2, .v2_8: SegmentGrammarTable.v2_8_2
        }
    }

    private func tableIssues(_ wire: String, table: String) throws -> [ValidationIssue] {
        Validator().validate(try Parser().parse(wire)).issues.filter { $0.code == .valueNotInTable(table: table) }
    }

    @Test("The same table still raises at a field that cites it for valid values",
          arguments: [("2.4", "PID", 24, "0136"), ("2.6", "PID", 24, "0136"), ("2.8.2", "PID", 24, "0136"),
                      ("2.3", "RXE", 9, "0167"), ("2.5.1", "RXE", 9, "0167"), ("2.8.2", "RXE", 9, "0167")])
    func validValuesFieldStillClosed(version: String, segment: String, index: Int, table: String) throws {
        let v = try #require(Version(rawValue: version))
        #expect(grammars(v)[segment]?.field(index)?.tableOpen == false)
        #expect(try tableIssues(wire(version, segment, index, "Z"), table: table).count == 1)
    }

    // MARK: - Schema to grammar

    private struct Schema: Decodable {
        struct Field: Decodable {
            let index: Int
            let tableOpen: Bool?
            let tableOpenCitation: String?
        }
        let segmentID: String
        let fields: [Field]
    }

    @Test("tableOpen round-trips from every schema entry to the generated grammar, with a citation")
    func schemaRoundTrip() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/schemas")
        for version in Version.allCases {
            let dir = root.appendingPathComponent("v\(version.rawValue)")
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for file in files where file.hasSuffix(".json") {
                let schema = try JSONDecoder().decode(Schema.self, from: Data(contentsOf: dir.appendingPathComponent(file)))
                for field in schema.fields {
                    let open = field.tableOpen ?? false
                    let generated = grammars(version)[schema.segmentID]?.field(field.index)
                    #expect(generated?.tableOpen == open, "v\(version.rawValue) \(schema.segmentID)-\(field.index)")
                    if open {
                        #expect(field.tableOpenCitation?.contains("suggested") == true
                                    || field.tableOpenCitation?.contains("extended") == true,
                                "v\(version.rawValue) \(schema.segmentID)-\(field.index) cites no prose")
                    }
                }
            }
        }
    }

    @Test("A field that is not marked defaults to a closed reading of its table")
    func defaultIsFalse() {
        let grammar = FieldGrammar(index: 1, name: "X", dataType: "ID", optionality: .optional,
                                   repeatability: .single, table: "0136")
        #expect(!grammar.tableOpen)
        let open = FieldGrammar(index: 1, name: "X", dataType: "ID", optionality: .optional,
                                repeatability: .single, table: "0136", tableOpen: true)
        #expect(open.tableOpen && open != grammar)
    }
}
