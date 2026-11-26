// FieldGrammarTablesTests.swift
// FieldGrammar.tables carries the TBL# column of every field as the schemas record it,
// coded types included; FieldGrammar.table keeps its narrower meaning.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Field grammar tables")
struct FieldGrammarTablesTests {
    private struct Schema: Decodable {
        struct Field: Decodable {
            let index: Int
            let tables: [String]?
        }
        let segmentID: String
        let fields: [Field]
    }

    private static let schemasRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // HL7v2KitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repository root
        .appendingPathComponent("Resources/schemas")

    @Test("A coded field names its table")
    func codedFieldsNameTheirTable() {
        #expect(SegmentGrammarTable.grammar("PID", version: .v2_7_1)?.field(10)?.tables == ["0005"])
        #expect(SegmentGrammarTable.grammar("PID", version: .v2_7_1)?.field(10)?.table == nil)   // CWE: unchanged
        #expect(SegmentGrammarTable.grammar("PID", version: .v2_7_1)?.field(8)?.tables == ["0001"])
        #expect(SegmentGrammarTable.grammar("PID", version: .v2_3)?.field(8)?.tables == ["0001"])
        #expect(SegmentGrammarTable.grammar("PID", version: .v2_3)?.field(8)?.table == "0001")
        #expect(SegmentGrammarTable.grammar("PID", version: .v2_3_1)?.field(10)?.tables == ["0005"])
        #expect(SegmentGrammarTable.grammar("PV1", version: .v2_7)?.field(2)?.tables.isEmpty == false)
        #expect(SegmentGrammarTable.grammar("PID", version: .v2_5_1)?.field(5)?.tables == [])
    }

    @Test("More than one table is carried in the order recorded")
    func severalTables() {
        #expect(SegmentGrammarTable.grammar("RXE", version: .v2_7_1)?.field(2)?.tables == ["0292", "0479"])
        #expect(SegmentGrammarTable.grammar("CON", version: .v2_5_1)?.field(18)?.tables == ["0296", "0545"])
    }

    @Test("Every field's tables are the schema's list, and hold its table", arguments: Version.allCases)
    func tablesMatchTheSchemas(_ version: Version) throws {
        guard version.grammarVersion == version else { return }
        let directory = Self.schemasRoot.appendingPathComponent("v\(version.rawValue)")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        #expect(!files.isEmpty)
        var coded = 0
        for file in files {
            let schema = try JSONDecoder().decode(Schema.self, from: Data(contentsOf: file))
            let grammar = try #require(SegmentGrammarTable.grammar(schema.segmentID, version: version))
            for field in schema.fields {
                let generated = try #require(grammar.field(field.index), "\(schema.segmentID)-\(field.index)")
                #expect(generated.tables == field.tables ?? [], "\(version) \(schema.segmentID)-\(field.index)")
                if let table = generated.table {
                    #expect(generated.tables.contains(table), "\(version) \(schema.segmentID)-\(field.index)")
                }
                if !generated.tables.isEmpty { coded += 1 }
            }
        }
        #expect(coded > 0)
    }

    @Test("TS.1 carries the format line as its name where the version prints no component table")
    func timeStampComponentName() {
        let formatLine = "YYYY[MM[DD[HHMM[SS[.S[S[S[S]]]]]]]][+/-ZZZZ]"
        for version in [Version.v2_3, .v2_3_1, .v2_4] {
            #expect(DataTypeGrammarTable.grammar("TS", version: version)?.component(1)?.name == formatLine, "\(version)")
        }
        #expect(DataTypeGrammarTable.grammar("TS", version: .v2_5_1)?.component(1)?.name == "Time")
        #expect(DataTypeGrammarTable.grammar("TS", version: .v2_6)?.component(1)?.name == "Time")
    }
}
