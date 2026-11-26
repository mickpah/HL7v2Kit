// AttributeUsageTableTests.swift
// The generated ADRM attribute-table rows are the extracted JSON's rows (R1, #34).

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("ADRM attribute usage table")
struct AttributeUsageTableTests {
    private struct File: Decodable {
        struct Table: Decodable {
            struct Row: Decodable {
                let seq: Int
                let optCode: String
                let page: Int
            }
            let segment: String
            let fields: [Row]
        }
        let tables: [Table]
    }

    private static func extracted() throws -> File {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HL7v2KitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("Resources/profiles/au-adrm-2021/attribute-tables.json")
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
    }

    @Test("Every extracted row is generated, with its code and page")
    func rowsMatchTheExtraction() throws {
        let file = try Self.extracted()
        let expected = file.tables.flatMap { table in
            table.fields.map { AttributeUsageRow(segment: table.segment, field: $0.seq, code: $0.optCode, page: $0.page) }
        }
        #expect(expected.count == 397)
        #expect(AttributeUsageTable.au_adrm_2021 == expected)
    }

    @Test("The ADRM prints R, O, C, B and X, six blank cells, and no RE or CE")
    func codesPrinted() {
        let counts = Dictionary(grouping: AttributeUsageTable.au_adrm_2021, by: \.code).mapValues(\.count)
        #expect(counts == ["O": 296, "R": 52, "C": 29, "B": 12, "X": 2, "": 6])
    }

    @Test("A row is found by segment and field")
    func lookup() {
        let rows = AttributeUsageTable.au_adrm_2021
        #expect(AttributeUsageTable.row(segment: "MSH", field: 15, in: rows) == AttributeUsageRow(segment: "MSH", field: 15, code: "R", page: 37))
        #expect(AttributeUsageTable.row(segment: "MSH", field: 28, in: rows) == nil)
        #expect(AttributeUsageTable.row(segment: "ZZZ", field: 1, in: rows) == nil)
    }
}
