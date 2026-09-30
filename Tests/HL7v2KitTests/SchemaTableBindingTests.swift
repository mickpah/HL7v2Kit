// SchemaTableBindingTests.swift
// Pins the `tables` key of the schema JSON (the verified record of the spec's
// TBL# cell, ADR-016), which has no runtime API, against the spec text.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Schema table bindings")
struct SchemaTableBindingTests {
    private struct Schema: Decodable {
        struct Field: Decodable {
            let index: Int
            let tables: [String]?
        }
        let fields: [Field]
    }

    /// The `tables` list of field `index` in `Resources/schemas/v<version>/<segment>.json`.
    private func tables(_ version: String, _ segment: String, _ index: Int) throws -> [String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HL7v2KitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("Resources/schemas/v\(version)/\(segment).json")
        let schema = try JSONDecoder().decode(Schema.self, from: Data(contentsOf: url))
        return try #require(schema.fields.first { $0.index == index }, "\(segment)-\(index)").tables ?? []
    }

    @Test("v2.5.1 print-versus-prose conflicts bind the field's own table")
    func printVersusProse() throws {
        // TQ1-12: attribute row prints 0427; sec 4.5.4.12 and the table under it are 0472.
        #expect(try tables("2.5.1", "TQ1", 12) == ["0472"])
        #expect(SegmentGrammarTable.v2_5_1["TQ1"]?.field(12)?.table == "0472")
        // CON-18: attribute row prints 0296; sec 9.9.4.18 prints User-defined Table 0545.
        #expect(try tables("2.5.1", "CON", 18) == ["0296", "0545"])
        #expect(SegmentGrammarTable.v2_5_1["CON"]?.field(18)?.table == "0545")
        // SID-4: the prose number 0451 is the misprint; its stated name is 0385's.
        #expect(try tables("2.5.1", "SID", 4) == ["0385"])
    }

    @Test("Fields with a blank TBL# whose prose names a table are bound to it")
    func proseOnlyBindings() throws {
        #expect(try tables("2.5.1", "RCP", 7) == ["0391"])
        #expect(try tables("2.4", "RCP", 7) == ["0391"])
        #expect(SegmentGrammarTable.v2_5_1["RCP"]?.field(7)?.table == "0391")
        #expect(SegmentGrammarTable.v2_4["RCP"]?.field(7)?.table == "0391")
        #expect(try tables("2.5.1", "SAC", 28) == ["0372"])
        // Sec 7.12.3.13 is headed "PCR-16" but defines ITEM 01110, attribute row 13.
        #expect(try tables("2.5.1", "PCR", 13) == ["0246"])
        #expect(try tables("2.5.1", "PCR", 16) == [])
        // A blank printed OPT is kept verbatim and generated as optional.
        #expect(SegmentGrammarTable.v2_5_1["RCP"]?.field(7)?.optionality == .optional)
    }
}
