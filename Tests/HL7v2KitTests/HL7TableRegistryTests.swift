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

    @Test("Coded OBR fields carry their table on v2.5.1; composite-typed fields never do")
    func obr24TableRef() throws {
        let obr = try #require(SegmentGrammarTable.v2_5_1["OBR"])
        #expect(obr.field(24)?.table == "0074")
        #expect(obr.field(24)?.dataType == "ID")
        #expect(obr.field(25)?.table == "0123", "A5 backfill: Result Status")
        // OBR-23 Charge to Practice is MOC: a link is only ever set on ID / IS fields.
        #expect(obr.field(23)?.table == nil)
    }

    @Test("0074 and 0155 are closed HL7 tables on every grammar version")
    func closedTablesEverywhere() throws {
        for version in [Version.v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_8_2] {
            for number in ["0074", "0155"] {
                let t = try #require(HL7TableRegistry.table(number, version: version), "\(version) \(number)")
                #expect(t.isClosed, "\(version) \(number)")
            }
        }
    }

    @Test("Tables the spec opens to local codes are HL7-owned but never closed")
    func openHL7Tables() throws {
        for number in ["0003", "0076", "0396", "0399", "0104"] {
            let t = try #require(HL7TableRegistry.table(number, version: .v2_5_1), "\(number)")
            #expect(t.kind == .hl7, "\(number)")
            #expect(!t.isClosed, "\(number)")
        }
    }

    @Test("An externally-defined table still resolves: v2.8.2 0399 Country code")
    func externallyDefinedTableResolves() throws {
        // v2.8.2 Chapter 2C heads the section with the code system's name
        // (`2.C.2.565 ISO-3166-1`) instead of the table number, and prints no
        // rows. The registry must still carry it — HL7-owned, and never a
        // closed set because ISO 3166 supplies the values.
        let t = try #require(HL7TableRegistry.table("0399", version: .v2_8_2))
        #expect(t.kind == .hl7)
        #expect(!t.isClosed)
        #expect(t.entries.isEmpty)
    }

    @Test("Extraction sanity: v2.5.1 0003 has 286 rows, 0155 has 4, 0125 has 90")
    func extractionSanity() throws {
        #expect(HL7TableRegistry.table("0003", version: .v2_5_1)?.entries.count == 286)
        #expect(HL7TableRegistry.table("0155", version: .v2_5_1)?.entries.count == 4)
        let t0125 = try #require(HL7TableRegistry.table("0125", version: .v2_5_1))
        // 25 printed rows, CD / MA / NA restored from Chapter 7's waveform text (M18), and the
        // 62 further Table 0440 data types sec 7.4.2.2 admits: "All HL7 data types are valid,
        // and are included in Table 0125 except CM, CQ, SI, and ID" (V251-C01).
        #expect(t0125.entries.count == 90)
        #expect(t0125.contains("NA") && t0125.contains("MA") && t0125.contains("CD"))
        #expect(t0125.contains("CWE") && t0125.contains("DTM"))
        #expect(!t0125.contains("CM") && !t0125.contains("CQ") && !t0125.contains("SI") && !t0125.contains("ID"))
    }

    @Test("A printed \"...\" row is never a code, and leaves an HL7 table open unless the row means null")
    func ellipsisRows() throws {
        // v2.6 0418 Procedure priority prints 0, 1, 2 and "...": ranks continue, so not closed.
        let ranks = try #require(HL7TableRegistry.table("0418", version: .v2_6))
        #expect(!ranks.contains("..."))
        #expect(ranks.contains("2"))
        #expect(!ranks.isClosed, "an open-ended rank must never drive valueNotInTable (req #4)")
        // v2.6 0365 Equipment state prints "..." for "(null) No state change": the rest IS the set.
        let state = try #require(HL7TableRegistry.table("0365", version: .v2_6))
        #expect(!state.contains("..."))
        #expect(state.isClosed)
        // v2.6 0153 prints only "... See NUBC codes": external, empty, never closed.
        let nubc = try #require(HL7TableRegistry.table("0153", version: .v2_6))
        #expect(nubc.codes.isEmpty && !nubc.isClosed)
    }

    @Test("Rows that denote an absent field, and prose bled into the Value column, are not codes")
    func absenceAndBleedRows() throws {
        for version in [Version.v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_8_2] {
            let mode = try #require(HL7TableRegistry.table("0207", version: version))
            #expect(mode.codes.allSatisfy { $0.lowercased() != "not present" }, "0207 on \(version)")
            // v2.3 has no T; its Appendix A misprints a / r / i, corrected to Chapter 2's A / R / I.
            #expect(mode.contains("A") && mode.contains("R") && mode.contains("I"), "0207 on \(version)")
        }
        let commands = try #require(HL7TableRegistry.table("0368", version: .v2_8_2))
        #expect(commands.codes.last == "AT", "the example EAC^U07 message after the table is not part of it")
        let systems = try #require(HL7TableRegistry.table("0396", version: .v2_8_2))
        for code in ["CDCEDACUITY", "CE", "NCPDPnnnnsss", "PHINQUESTION"] { #expect(systems.contains(code)) }
        #expect(systems.codes.allSatisfy { !$0.contains("(") && !$0.contains("[") })
        // UCUM units are printed in square brackets and are genuine codes.
        #expect(try #require(HL7TableRegistry.table("0567", version: .v2_8_2)).contains("[lb_av]"))
    }

    @Test("A locale can print its own rendering of a table: AU ADRM-2021 back-ports UNICODE UTF-8 into 0211")
    func auLocaleTable0211() throws {
        let au = try #require(HL7TableRegistry.table("0211", locale: .auLocalisation))
        #expect(au.contains("UNICODE UTF-8"), "ADRM-2021.1 p. 55 footnote")
        #expect(au.isClosed)
        let base = try #require(HL7TableRegistry.table("0211", version: .v2_4))
        #expect(!base.contains("UNICODE UTF-8"), "base v2.4 does not print it")
        #expect(Set(au.codes) == Set(base.codes).union(["UNICODE UTF-8"]))
        #expect(HL7TableRegistry.table("0211", locale: .international) == nil, "the base locale adds nothing")
    }

    @Test("AU locale tables exist with descriptions and back the profile seed unchanged")
    func auLocaleTables() throws {
        let t0203 = try #require(HL7TableRegistry.table("0203", locale: .auLocalisation))
        #expect(t0203.contains("MR") && t0203.contains("UPIN") && t0203.contains("NOI"))
        #expect(t0203.entries.allSatisfy { !$0.description.isEmpty })
        #expect(HL7CodeTables.table0203 == t0203.codes)
        #expect(HL7CodeTables.table0074.count == 40, "the ADRM printed rendering, not the base-spec 39")
        #expect(HL7CodeTables.table0200.count == 13 && HL7CodeTables.table0363.count == 6)
        for number in ["0074", "0200", "0203", "0363"] {
            let t = try #require(HL7TableRegistry.table(number, locale: .auLocalisation), "\(number)")
            #expect(t.entries.allSatisfy { !$0.description.isEmpty }, "\(number)")
        }
        #expect(HL7TableRegistry.table("0203", locale: .international) == nil)
    }

    @Test("Table 0354 is never closed: every version's chapters use structures it does not print")
    func messageStructureTableIsOpen() throws {
        for version in [Version.v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_8_2] {
            let t = try #require(HL7TableRegistry.table("0354", version: version), "\(version)")
            #expect(t.contains("ADT_A01"))
            #expect(!t.isClosed, "0354 on \(version): v2.5.1 CH15 defines RSP_K25, which Appendix A omits")
        }
    }

    @Test("v2.8.2 tables with non-standard column headers extract whole, across page breaks")
    func nonStandardHeaders() throws {
        let structures = try #require(HL7TableRegistry.table("0354", version: .v2_8_2))
        #expect(structures.codes.count > 200, "was 0, then 26 when rows stopped at the first page break")
        #expect(structures.contains("ORU_W01"))
        let types = try #require(HL7TableRegistry.table("0440", version: .v2_8_2))
        #expect(types.contains("XTN") && types.contains("AD"))
        let operators = try #require(HL7TableRegistry.table("0209", version: .v2_8_2))
        #expect(operators.codes.count == 8 && operators.isClosed)
    }

    @Test("A row the appendix drops is restored from the defining chapter: v2.5.1 0210 OR")
    func restoredRow() throws {
        for version in [Version.v2_4, .v2_5_1, .v2_6, .v2_8_2] {
            let t = try #require(HL7TableRegistry.table("0210", version: version))
            #expect(Set(t.codes) == ["AND", "OR"], "0210 on \(version)")
        }
    }

    @Test("No code carries mis-decoded characters: v2.6 0550 CHEST and KIDN")
    func noCorruptCodes() throws {
        let parts = try #require(HL7TableRegistry.table("0550", version: .v2_6))
        #expect(parts.contains("CHEST") && parts.contains("KIDN"))
        #expect(parts.codes.allSatisfy { !$0.isEmpty && $0.unicodeScalars.allSatisfy { $0.value < 128 } })
    }

    @Test("v2.3 tables printed only in the chapters carry their rows: 0254, 0255, 0256, 0290")
    func v23ChapterPrintedRows() throws {
        for (number, count) in [("0254", 102), ("0255", 26), ("0256", 44), ("0290", 65)] {
            let t = try #require(HL7TableRegistry.table(number, version: .v2_3))
            #expect(t.entries.count == count, "v2.3 \(number)")
        }
        #expect(HL7TableRegistry.table("0255", version: .v2_3)?.kind == .userDefined, "CH8 prints User-defined Table 0255")
        let t0256 = try #require(HL7TableRegistry.table("0256", version: .v2_3))
        #expect(t0256.contains("30M") && t0256.contains("8H SHIFT"))
        let t0290 = try #require(HL7TableRegistry.table("0290", version: .v2_3_1))
        #expect(t0290.entries.count == 65)
        #expect(t0290.entries.first { $0.code == "63" }?.description == "/")
    }

    @Test("A pattern row matches the family of codes it names, and is not itself a code")
    func patternRow() {
        let t = HL7Table(
            number: "9999", name: "Test", kind: .hl7,
            entries: [HL7Table.Entry(code: "MR", description: "Medical record number")],
            patterns: [HL7Table.CodePattern(code: "NNxxx", description: "National Person Identifier", regex: "^NN[A-Z]{3}$")]
        )
        #expect(t.contains("MR") && t.contains("NNAUS") && t.contains("NNCAN"))
        #expect(!t.contains("NNAU") && !t.contains("NNAUST") && !t.contains("XNNAUS") && !t.contains("NNaus"))
        #expect(!t.contains("NNxxx"))
        #expect(t.codes == ["MR"])
        #expect(t.isClosed)
    }
}
