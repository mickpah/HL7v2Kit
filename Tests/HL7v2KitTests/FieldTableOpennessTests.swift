// FieldTableOpennessTests.swift
// Per-field table openness (P2-15, ADR-016): a field whose own prose cites a closed HL7
// table "for suggested values" (or calls it User-defined, or says it can be extended) is
// marked `tableOpen` in its schema entry, and the field-level closed-table check skips it.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Per-field table openness")
struct FieldTableOpennessTests {

    /// A marked field the scalar check would otherwise enforce (an `ID` field bound to a
    /// closed HL7 table), and the wire version that carries it.
    struct Marked: Sendable, CustomTestStringConvertible {
        let version: String
        let segment: String
        let index: Int
        let table: String
        var testDescription: String { "v\(version) \(segment)-\(index) (\(table))" }
    }

    static let enforced: [Marked] = [
        // v2.4 CH03 sec 3.4.2.31 PID-31: "Refer to HL7 Table 0136 - Yes/no indicator for suggested values."
        Marked(version: "2.4", segment: "PID", index: 31, table: "0136"),
        // v2.6 / v2.8.2 CH06 sec 6.5.2.24 DG1-24 and CH16 RFI-3, IVC-13, PSG-4, PSL-47: "... for suggested values."
        Marked(version: "2.6", segment: "DG1", index: 24, table: "0136"),
        Marked(version: "2.6", segment: "RFI", index: 3, table: "0136"),
        Marked(version: "2.6", segment: "IVC", index: 13, table: "0136"),
        Marked(version: "2.6", segment: "PSG", index: 4, table: "0136"),
        Marked(version: "2.6", segment: "PSL", index: 47, table: "0136"),
        Marked(version: "2.8.2", segment: "DG1", index: 24, table: "0136"),
        Marked(version: "2.8.2", segment: "RFI", index: 3, table: "0136"),
        Marked(version: "2.8.2", segment: "IVC", index: 13, table: "0136"),
        Marked(version: "2.8.2", segment: "PSG", index: 4, table: "0136"),
        Marked(version: "2.8.2", segment: "PSL", index: 47, table: "0136"),
        // RXD-11 on every version: "Refer to HL7 Table 0167 - Substitution Status for suggested values."
        Marked(version: "2.3", segment: "RXD", index: 11, table: "0167"),
        Marked(version: "2.3.1", segment: "RXD", index: 11, table: "0167"),
        Marked(version: "2.4", segment: "RXD", index: 11, table: "0167"),
        Marked(version: "2.5.1", segment: "RXD", index: 11, table: "0167"),
        Marked(version: "2.6", segment: "RXD", index: 11, table: "0167"),
        Marked(version: "2.8.2", segment: "RXD", index: 11, table: "0167"),
        // v2.6 / v2.8.2 CH16 PSL-21: "Refer to User-defined Table 0532 ... for suggested values."
        Marked(version: "2.6", segment: "PSL", index: 21, table: "0532"),
        Marked(version: "2.8.2", segment: "PSL", index: 21, table: "0532"),
    ]

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

    @Test("An out-of-table value is silent at a field that cites its table for suggested values",
          arguments: enforced)
    func markedFieldIsOpen(_ field: Marked) throws {
        let version = try #require(Version(rawValue: field.version))
        let grammar = try #require(grammars(version)[field.segment]?.field(field.index))
        #expect(grammar.tableOpen)
        #expect(grammar.dataType == "ID" && grammar.table == field.table)
        #expect(try #require(HL7TableRegistry.table(field.table, version: version)).isClosed)
        #expect(try tableIssues(wire(field.version, field.segment, field.index, "Z"), table: field.table).isEmpty)
    }

    /// Marked fields the scalar check never enforces: `IS` fields and composite (CE / CWE /
    /// CNE) fields, whose table binding is recorded but not wire-checked (ADR-016). The mark
    /// keeps the metadata faithful to each field's own prose.
    static let metadataOnly: [Marked] = [
        // 0185: PRD-6, CTD-6 on every version, PRD-14 from v2.6 ("User-defined Table 0185 ... for suggested values").
        Marked(version: "2.3", segment: "PRD", index: 6, table: "0185"),
        Marked(version: "2.3", segment: "CTD", index: 6, table: "0185"),
        Marked(version: "2.3.1", segment: "PRD", index: 6, table: "0185"),
        Marked(version: "2.3.1", segment: "CTD", index: 6, table: "0185"),
        Marked(version: "2.4", segment: "PRD", index: 6, table: "0185"),
        Marked(version: "2.4", segment: "CTD", index: 6, table: "0185"),
        Marked(version: "2.5.1", segment: "PRD", index: 6, table: "0185"),
        Marked(version: "2.5.1", segment: "CTD", index: 6, table: "0185"),
        Marked(version: "2.6", segment: "PRD", index: 6, table: "0185"),
        Marked(version: "2.6", segment: "CTD", index: 6, table: "0185"),
        Marked(version: "2.6", segment: "PRD", index: 14, table: "0185"),
        Marked(version: "2.8.2", segment: "PRD", index: 6, table: "0185"),
        Marked(version: "2.8.2", segment: "CTD", index: 6, table: "0185"),
        Marked(version: "2.8.2", segment: "PRD", index: 14, table: "0185"),
        // 0206: IAM-6, ARV-2 on v2.6 and v2.8.2 ("... for suggested values").
        Marked(version: "2.6", segment: "IAM", index: 6, table: "0206"),
        Marked(version: "2.6", segment: "ARV", index: 2, table: "0206"),
        Marked(version: "2.8.2", segment: "IAM", index: 6, table: "0206"),
        Marked(version: "2.8.2", segment: "ARV", index: 2, table: "0206"),
        // 0239: v2.3 PCR-2, PCR-9, PCR-11, PCR-13 ("user-defined table 0239 ... for suggested values").
        Marked(version: "2.3", segment: "PCR", index: 2, table: "0239"),
        Marked(version: "2.3", segment: "PCR", index: 9, table: "0239"),
        Marked(version: "2.3", segment: "PCR", index: 11, table: "0239"),
        Marked(version: "2.3", segment: "PCR", index: 13, table: "0239"),
        // 0323: IAM-6 on v2.4 and v2.5.1 ("... for suggested values").
        Marked(version: "2.4", segment: "IAM", index: 6, table: "0323"),
        Marked(version: "2.5.1", segment: "IAM", index: 6, table: "0323"),
        // 0371: OM4-7, SAC-27 on v2.5.1, v2.6, v2.8.2 ("The value set can be extended with user specific values.").
        Marked(version: "2.5.1", segment: "OM4", index: 7, table: "0371"),
        Marked(version: "2.5.1", segment: "SAC", index: 27, table: "0371"),
        Marked(version: "2.6", segment: "OM4", index: 7, table: "0371"),
        Marked(version: "2.6", segment: "SAC", index: 27, table: "0371"),
        Marked(version: "2.8.2", segment: "OM4", index: 7, table: "0371"),
        Marked(version: "2.8.2", segment: "SAC", index: 27, table: "0371"),
    ]

    @Test("A composite or IS field whose prose opens its table carries the mark", arguments: metadataOnly)
    func metadataFieldIsMarked(_ field: Marked) throws {
        let version = try #require(Version(rawValue: field.version))
        let grammar = try #require(grammars(version)[field.segment]?.field(field.index))
        #expect(grammar.tableOpen)
        #expect(grammar.dataType != "ID")
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
        var marked = 0
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
                        marked += 1
                        #expect(field.tableOpenCitation?.contains("suggested") == true
                                    || field.tableOpenCitation?.contains("extended") == true,
                                "v\(version.rawValue) \(schema.segmentID)-\(field.index) cites no prose")
                    }
                }
            }
        }
        #expect(marked > 0)
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
