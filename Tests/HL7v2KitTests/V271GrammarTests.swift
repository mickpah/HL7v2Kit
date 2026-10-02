// V271GrammarTests.swift
// HL7 v2.7.1 through the ADR-015 pipeline (plan P10). Each pin is a value printed by the
// v2.7.1 Final Standard (July 2012); the citation sits beside it. `Version.v2_7_1` does not
// exist until P10-6, so these tests read the generated registry directly.

import Testing
@testable import HL7v2Kit

@Suite("v2.7.1 grammar (P10)")
struct V271GrammarTests {

    private var tables: [String: HL7Table] { HL7TableRegistry.v2_7_1 }

    private func table(_ number: String) throws -> HL7Table {
        try #require(tables[number], "Table \(number)")
    }

    // MARK: - P10-1: code tables

    @Test("v2.7.1 tables: Appendix A's 534 plus Chapter 2C's 0916")
    func inventory() {
        #expect(tables.count == 535)
        #expect(tables.values.filter { $0.kind == .hl7 }.count == 174)
        #expect(tables.values.filter { $0.kind == .userDefined }.count == 361)
        #expect(tables.values.reduce(0) { $0 + $1.entries.count } == 5158)
        // Chapter 2C sec 2.C.2.11 (p21): "withdrawn in v2.7". Table 0048 is printed nowhere.
        #expect(tables["0070"] == nil)
        #expect(tables["0048"] == nil)
    }

    @Test("No ellipsis row survives as a code: Appendix A prints U+2026 for 'no suggested values'")
    func noEllipsisCodes() throws {
        for t in tables.values {
            #expect(!t.codes.contains("\u{2026}") && !t.codes.contains("..."), "Table \(t.number)")
        }
        // Appendix A p39: "0010  ...  no suggested values".
        #expect(try table("0010").entries.isEmpty)
        // p110: the ellipsis is "(null) No state change", an absent field: the table stays closed.
        let equipment = try table("0365")
        #expect(equipment.isClosed && equipment.codes.count == 9)
        // p90: "... Source RFC 2046" beside a real row: an open list.
        let subtype = try table("0291")
        #expect(subtype.contains("x-hl7-cda-level-one") && !subtype.isClosed)
    }

    @Test("Values pinned from the print")
    func printedValues() throws {
        // Appendix A, User-defined Table 0001.
        #expect(Set(try table("0001").codes) == ["A", "F", "M", "N", "O", "U"])
        // Chapter 2C sec 2.C.2.318 (p190); bound by OBR-13 (CH04 sec 4.5.3.13); absent from Appendix A.
        let clinical = try table("0916")
        #expect(clinical.kind == .userDefined)
        #expect(Set(clinical.codes) == ["F", "NF", "NG", "FNA"])
        // Chapter 2C sec 2.C.2.22 (p28) prints 2.7.1; Appendix A stops at 2.7.
        #expect(try table("0104").contains("2.7.1"))
        // CH07 sec 7.15.4 (p141): "OBX-2 Value Type should be valued to CD"; MA and NA are printed.
        let valueType = try table("0125")
        #expect(valueType.contains("CD") && valueType.contains("MA") && valueType.contains("NA"))
        // CH02 sec 2.5.1 (p6): "Z" events are reserved for local definition, never HL7 codes.
        #expect(try table("0003").codes.allSatisfy { !$0.hasPrefix("Z") })
        #expect(!(try table("0354")).contains("QBP_Z73"))
        // CH14 sec 14.3.2 NMD_N02 names the group CLOCK_AND_STATS_WITH_NOTES (Chapter 2C p120).
        let groups = try table("0391")
        #expect(groups.contains("CLOCK_AND_STATS_WITH_NOTES") && !groups.contains("CLOCK_AND_STATS_WITH_NOTE"))
        // Appendix A p95 prints 'L,M,N' as one Value: three codes.
        #expect(Set(["L", "M", "N"]).isSubset(of: Set(try table("0301").codes)))
        // "Not present" denotes an absent field, not a code.
        #expect(!(try table("0207")).contains("Not present"))
        // Chapter 2C sec 2.C.2.79 (p63) prints the UTF forms whole.
        #expect(try table("0211").contains("UNICODE UTF-8"))
        // NNxxx is a family (Chapter 2C p59): a pattern row.
        #expect(try table("0203").contains("NNAUS"))
    }

    @Test("Openness and kind follow the governing v2.7.1 prose")
    func openness() throws {
        for number in ["0074", "0155", "0371", "0905", "0912"] {
            #expect(try table(number).isClosed, "Table \(number) is closed")
        }
        // NTE-2 (CH02 p65), MFI-1 (CH08 p7), Chapter 2C 0355 Note (p106), MFE/NUBC/ISO references.
        for number in ["0003", "0076", "0104", "0105", "0175", "0203", "0354", "0355", "0396", "0399", "0544"] {
            let t = try table(number)
            #expect(t.kind == .hl7 && t.permitsLocalExtensions && !t.isClosed, "Table \(number) is open")
        }
        // CH02A sec 2.A.86.18 XAD.18 (p92): "Refer to User-defined Table 0617".
        #expect(try table("0617").kind == .userDefined)
        // External tables (Chapter 2C and the defining chapter): HL7-owned, never closed.
        for number in ["0055", "0088", "0118", "0910"] {
            let t = try table(number)
            #expect(t.kind == .hl7 && t.permitsLocalExtensions, "Table \(number) is external")
        }
    }
}
