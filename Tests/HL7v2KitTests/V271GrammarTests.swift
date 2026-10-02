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
        // 5,155 entries plus four pattern rows (0203 NNxxx; 0141 E1... E9, O1 ... O9, W1 ... W4).
        #expect(tables.values.reduce(0) { $0 + $1.entries.count } == 5155)
        #expect(tables.values.reduce(0) { $0 + $1.patterns.count } == 4)
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
        // The print's en dash is kept, as on v2.8.2.
        #expect(clinical.entries.first { $0.code == "NG" }?.description.contains("\u{2013}") == true)
        // Both prints carry the row "?? Inappropriate due to ..." (Appendix A p151; Chapter 2C p157,
        // where the table continues over the page break).
        #expect(try table("0492").contains("??"))
        // Chapter 2C sec 2.C.2.22 (p28) prints 2.7.1; Appendix A stops at 2.7.
        #expect(try table("0104").contains("2.7.1"))
        // CH07 sec 7.15.4 (p141): "OBX-2 Value Type should be valued to CD"; MA and NA are printed.
        let valueType = try table("0125")
        #expect(valueType.contains("CD") && valueType.contains("MA") && valueType.contains("NA"))
        // CH07 sec 7.3.2.2 OBX-2 (p46): CQ, SI and ID are invalid; the tables print ID regardless.
        #expect(!valueType.contains("ID") && !valueType.contains("CQ") && !valueType.contains("SI"))
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

    // MARK: - P10-2: datatype component grammar

    private var grammars: [String: DataTypeGrammar] { DataTypeGrammarTable.v2_7_1 }

    @Test("v2.7.1 component tables: 72 composites, 469 components, 72 printed C")
    func dataTypeInventory() throws {
        #expect(grammars.count == 72)
        let components = grammars.values.flatMap(\.components)
        #expect(components.count == 469)
        #expect(components.filter { $0.optionalityCode == "C" }.count == 72)
        #expect(components.filter { !$0.tables.isEmpty }.count == 151)
        #expect(grammars.values.allSatisfy { $0.version == "2.7.1" })
        // Chapter 2A 2.A.38 (p50) and 2.A.39 (p51): retained for backward compatibility.
        #expect(grammars["LA1"]?.components.count == 9)
        #expect(grammars["LA2"]?.components.count == 16)
        // OG is first printed in v2.8.
        #expect(grammars["OG"] == nil)
        // Primitives print no component table.
        for code in ["DT", "DTM", "FT", "GTS", "ID", "IS", "NM", "SI", "SNM", "ST", "TM", "TX"] {
            #expect(grammars[code] == nil, "\(code) is primitive")
        }
        // Withdrawn stubs: CE 2.A.6 (p7) and TS 2.A.78 (p85) "as of v 2.6"; ELD 2.A.27 (p42),
        // OSD 2.A.50 (p60), SPS 2.A.73 (p82) and TQ 2.A.77 (p84) "as of v 2.7".
        for code in ["CE", "ELD", "OSD", "SPS", "TQ", "TS"] {
            #expect(grammars[code] == nil, "\(code) is withdrawn")
        }
        let xad = try #require(grammars["XAD"])
        #expect(xad.component(18)?.tables == ["0617"])           // 2.A.86 (p89)
        #expect(xad.component(7)?.optionalityCode == "C")
    }

    @Test("Every component table the page footer used to cut is read whole")
    func footerTruncation() {
        // The second footer line ("2.7.1.  July 2012.") ended these 14 tables at a page break.
        let printed = ["CF": 22, "CNE": 22, "CNN": 11, "CSU": 23, "DLD": 2, "FN": 5, "LA2": 16, "PL": 11,
                       "PPN": 26, "RFR": 7, "SPD": 4, "XCN": 25, "XPN": 15, "XTN": 18]
        for (code, count) in printed {
            #expect(grammars[code]?.components.count == count, "\(code)")
            #expect(grammars[code]?.components.map(\.index) == Array(1...count), "\(code) is contiguous")
        }
    }

    @Test("Where v2.7.1 differs from v2.8.2, the v2.7.1 print wins")
    func differencesFromV282() throws {
        // 2.A.56 PRL (p68): PRL.2 is ST; v2.8.2 types it OG.
        #expect(grammars["PRL"]?.component(2)?.dataType == "ST")
        #expect(DataTypeGrammarTable.v2_8_2["PRL"]?.component(2)?.dataType == "OG")
        // 2.A.88 XON (p97): only XON.3 is withdrawn; v2.8.2 also withdraws XON.4 and XON.5.
        let xon = try #require(grammars["XON"])
        #expect(xon.component(3)?.optionalityCode == "W")
        #expect(xon.component(4).map { [$0.dataType, $0.optionalityCode] } == ["NM", "O"])
        #expect(xon.component(5).map { [$0.dataType, $0.optionalityCode] } == ["ID", "O"])
        #expect(xon.component(5)?.tables == ["0061"])
        // Every other shared datatype prints the same components (lengths aside).
        let shape = { (g: DataTypeGrammar) in g.components.map { [$0.name, $0.dataType, $0.optionalityCode] + $0.tables } }
        let differ = Set(grammars.keys).intersection(DataTypeGrammarTable.v2_8_2.keys).filter { code in
            shape(grammars[code]!) != shape(DataTypeGrammarTable.v2_8_2[code]!)
        }
        #expect(differ == ["PRL", "XON"])
    }

    @Test("Component conditions: v2.8.2's rules, each re-cited to the identical v2.7.1 sentence")
    func componentConditions() {
        let components = grammars.values.flatMap { g in g.components.map { (g.dataType, $0) } }
        let rules = components.filter { $0.1.condition != nil }
        let conformance = components.filter { $0.1.conformanceCondition != nil }
        #expect(rules.count == 23)
        #expect(conformance.count == 30)
        for (code, c) in rules + conformance {
            #expect(c.optionalityCode == "C", "\(code).\(c.index)")
            for expression in [c.condition, c.conformanceCondition].compactMap({ $0 }) {
                #expect(ComponentCondition.parses(expression), "\(code).\(c.index): \(expression)")
            }
            let v282 = DataTypeGrammarTable.v2_8_2[code]?.component(c.index)
            #expect(v282?.condition == c.condition && v282?.conformanceCondition == c.conformanceCondition,
                    "\(code).\(c.index)")
        }
        // 2.A.66.6 RPT.6 (p78): "required if RPT.5 - Period Quantity is populated".
        #expect(grammars["RPT"]?.component(6)?.condition == "5 populated")
        // 2.A.86.7 XAD.7 (p90): "required if there are multiple occurrences of XAD in a field".
        #expect(grammars["XAD"]?.component(7)?.condition == "repeated")
        // 2.A.13.3 CWE.3 (p28): the "as of v2.7" family stays opt-in.
        #expect(grammars["CWE"]?.component(3)?.condition == nil)
        #expect(grammars["CWE"]?.component(3)?.conformanceCondition == "1 populated AND 14 empty")
        // 19 stay bare, as on v2.8.2 (conditions.json `_about`; register section D).
        #expect(components.filter { $0.1.optionalityCode == "C" && $0.1.condition == nil
            && $0.1.conformanceCondition == nil }.count == 19)
    }

    // MARK: - P10-4a: segment schemas, chapters 2 to 4A

    private var segments: [String: SegmentGrammar] { SegmentGrammarTable.v2_7_1 }

    /// Field count of each segment first defined in CH02, CH03, CH04 and CH04A, from the
    /// defining attribute table (re-measured by the P10-4a extraction; ADD is `1-n`, one field).
    static let chapterFieldCounts: [String: [String: Int]] = [
        "CH02": ["ADD": 1, "BHS": 14, "BTS": 3, "DSC": 2, "ERR": 12, "FHS": 14, "FTS": 2,
                 "MSA": 8, "MSH": 25, "NTE": 8, "OVR": 5, "SFT": 6, "UAC": 2],
        "CH03": ["AL1": 6, "ARV": 6, "DB1": 8, "EVN": 7, "IAM": 30, "IAR": 4, "MRG": 7,
                 "NK1": 41, "NPU": 2, "PD1": 22, "PDA": 9, "PID": 40, "PV1": 54, "PV2": 50],
        "CH04": ["BLG": 4, "BPO": 14, "BPX": 21, "BTX": 19, "IPC": 9, "OBR": 54, "ODS": 4,
                 "ODT": 3, "ORC": 33, "RQ1": 7, "RQD": 10, "TQ1": 14, "TQ2": 10],
        "CH04A": ["RXA": 28, "RXC": 9, "RXD": 34, "RXE": 45, "RXG": 30, "RXO": 36, "RXR": 6],
    ]

    @Test("CH02 to CH04A: 47 segments (46 extracted plus ADD), 778 fields")
    func chapterSegments() throws {
        let counts = Self.chapterFieldCounts.values.reduce(into: [String: Int]()) { $0.merge($1) { a, _ in a } }
        #expect(counts.count == 47)
        #expect(counts.values.reduce(0, +) == 778)
        for (segment, count) in counts {
            let grammar = try #require(segments[segment], "\(segment)")
            #expect(grammar.version == "2.7.1")
            #expect(grammar.fields.count == count, "\(segment)")
            #expect(grammar.fields.map(\.index) == Array(1...count), "\(segment)")
            // Conditions are P10-5a/5b's: nothing is copied from another version here.
            #expect(grammar.fields.allSatisfy { $0.condition == nil && $0.prohibitedWhen == nil }, "\(segment)")
        }
        // CH02 section 2.14.1 (p. 47): ADD prints SEQ `1-n`.
        #expect(segments["ADD"]?.field(1)?.variableColumns == true)
    }

    @Test("Fields read by hand against the v2.7.1 attribute tables")
    func printedFields() throws {
        func field(_ segment: String, _ index: Int) throws -> FieldGrammar {
            try #require(segments[segment]?.field(index), "\(segment)-\(index)")
        }
        // CH02 2.14.9 MSH (p. 57): `9  MSG R 00009`, `12  VID R 00012`.
        #expect(try field("MSH", 9).dataType == "MSG")
        #expect(try field("MSH", 9).optionality == .required)
        #expect(try field("MSH", 12).dataType == "VID")
        // CH03 3.4.2 PID (p. 59): `3  CX R Y 00106`; `35  CWE C 0446 Species Code`.
        #expect(try field("PID", 3).repeatability == .multiple)
        #expect(try field("PID", 3).optionality == .required)
        #expect(try field("PID", 35).name == "Species Code")
        #expect(try field("PID", 35).optionality == .conditional)
        // CH03 3.4.3 PV1 (p. 76): `2  CWE R 0004 00132 Patient Class`.
        #expect(try field("PV1", 2).dataType == "CWE")
        #expect(try field("PV1", 2).optionality == .required)
        // CH04 4.5.1 ORC (p. 32): `1  2..2  ID R 0119 00215`; ORC-4 is EI (v2.8.2 prints EIP).
        #expect(try field("ORC", 1).length == "2..2")
        #expect(try field("ORC", 1).table == "0119")
        #expect(try field("ORC", 4).dataType == "EI")
        // CH04 4.5.3 OBR (p. 54): `4  CWE R 9999 00238 Universal Service Identifier`.
        #expect(try field("OBR", 4).dataType == "CWE")
        #expect(try field("OBR", 4).optionality == .required)
        // CH04A 4A.4.7 RXA (p. 88): `5  CWE R 0292 00347`; `11  LA2 B` (W from v2.8).
        #expect(try field("RXA", 5).optionality == .required)
        #expect(try field("RXA", 11).dataType == "LA2")
        #expect(try field("RXA", 11).optionality == .backwardCompat)
    }
}
