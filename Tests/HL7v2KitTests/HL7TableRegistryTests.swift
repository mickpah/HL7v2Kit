// HL7TableRegistryTests.swift
// The per-version HL7 code-table registry (M6-O6): lookup, closed-set
// semantics, and the generated tables' internal consistency.

import Testing
@testable import HL7v2Kit

@Suite("HL7TableRegistry")
struct HL7TableRegistryTests {

    @Test("Table 0074 resolves on v2.5.1 with the 39 printed entries and is closed")
    func table0074v251() throws {
        let t = try #require(HL7TableRegistry.table("0074", version: .v2_5_1))
        #expect(t.number == "0074")
        #expect(t.name == "Diagnostic Service Section ID")
        #expect(t.kind == .hl7)
        #expect(t.entries.count == 39)
        #expect(t.contains("AU"))
        #expect(t.entries.first { $0.code == "AU" }?.description == "Audiology")
        #expect(!t.contains("au"), "codes are case-sensitive")
        #expect(!t.contains("ZZ"))
        #expect(t.isClosed)
    }

    @Test("Unknown table and the grammar-less v2.8 resolve to nil")
    func missingLookups() {
        #expect(HL7TableRegistry.table("9999", version: .v2_5_1) == nil)
        #expect(HL7TableRegistry.table("0074", version: .v2_8) == nil)
    }

    @Test("isClosed is false for user-defined, locally-extensible, or empty tables")
    func closedSetRule() {
        let e = [HL7Table.Entry(code: "A", description: "a")]
        #expect(HL7Table(number: "0001", name: "n", kind: .hl7, entries: e).isClosed)
        #expect(!HL7Table(number: "0001", name: "n", kind: .userDefined, entries: e).isClosed)
        #expect(!HL7Table(number: "0001", name: "n", kind: .hl7, permitsLocalExtensions: true, entries: e).isClosed)
        #expect(!HL7Table(number: "0001", name: "n", kind: .hl7, entries: []).isClosed)
    }

    @Test("Every generated table is keyed by its own number and has unique codes")
    func generatedConsistency() {
        for version in Version.allCases {
            for (key, table) in HL7TableRegistry.tables(for: version) {
                #expect(key == table.number, "\(version) \(key)")
                #expect(Set(table.entries.map(\.code)).count == table.entries.count, "\(version) \(key) duplicate codes")
            }
        }
    }

    @Test("OBR-24 grammar carries table 0074 on v2.5.1; neighbours carry nil until backfill")
    func obr24TableRef() throws {
        let obr = try #require(SegmentGrammarTable.v2_5_1["OBR"])
        #expect(obr.field(24)?.table == "0074")
        #expect(obr.field(24)?.dataType == "ID")
        #expect(obr.field(25)?.table == nil)
    }
}
