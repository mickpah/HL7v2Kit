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

    // MARK: - P10-4b: segment schemas, chapters 5 to 10

    /// Field count of each segment first defined in CH05 to CH10, from the defining attribute
    /// table (re-measured by the P10-4b extraction). RDT is `1-n`, one field. OBR (CH07) is
    /// CH04's; the CH07 OBX example tables and the CH09 OBX usage table are not definitions.
    static let laterChapterFieldCounts: [String: [String: Int]] = [
        "CH05": ["DSP": 5, "QAK": 6, "QID": 2, "QPD": 2, "QRI": 3, "RCP": 7, "RDF": 2, "RDT": 1],
        "CH06": ["ABS": 14, "ACC": 12, "BLC": 2, "DG1": 26, "DRG": 33, "FT1": 43, "GP1": 5,
                 "GP2": 14, "GT1": 57, "IN1": 54, "IN2": 72, "IN3": 25, "PR1": 25, "RMI": 3,
                 "UB1": 23, "UB2": 17],
        "CH07": ["CSP": 4, "CSR": 16, "CSS": 3, "CTI": 3, "FAC": 12, "OBX": 26, "PAC": 8,
                 "PCR": 23, "PDC": 15, "PEO": 25, "PES": 13, "PRT": 15, "PSH": 14, "SHP": 11,
                 "SPM": 32],
        "CH08": ["CDM": 13, "CM0": 11, "CM1": 3, "CM2": 4, "DMI": 5, "LCC": 4, "LCH": 5,
                 "LDP": 12, "LOC": 9, "LRL": 6, "MFA": 6, "MFE": 7, "MFI": 6, "OM1": 47,
                 "OM2": 10, "OM3": 7, "OM4": 14, "OM5": 3, "OM6": 2, "OM7": 24, "PRC": 18],
        "CH09": ["CON": 25, "TXA": 26],
        "CH10": ["AIG": 14, "AIL": 12, "AIP": 12, "AIS": 12, "APR": 5, "ARQ": 25, "RGS": 3,
                 "SCH": 27],
    ]

    @Test("CH05 to CH10: 70 segments (69 extracted plus RDT), 1050 fields")
    func laterChapterSegments() throws {
        let counts = Self.laterChapterFieldCounts.values.reduce(into: [String: Int]()) { $0.merge($1) { a, _ in a } }
        #expect(Self.laterChapterFieldCounts.mapValues(\.count)
                == ["CH05": 8, "CH06": 16, "CH07": 15, "CH08": 21, "CH09": 2, "CH10": 8])
        #expect(counts.count == 70)
        #expect(counts.values.reduce(0, +) == 1050)
        for (segment, count) in counts {
            let grammar = try #require(segments[segment], "\(segment)")
            #expect(grammar.version == "2.7.1")
            #expect(grammar.fields.count == count, "\(segment)")
            #expect(grammar.fields.map(\.index) == Array(1...count), "\(segment)")
            // Conditions are P10-5a/5b's: nothing is copied from another version here.
            #expect(grammar.fields.allSatisfy { $0.condition == nil && $0.prohibitedWhen == nil }, "\(segment)")
        }
        // CH05 section 5.5.8 (p. 48): RDT prints SEQ `1-n`, `varies`, R, 00703 Column Value.
        #expect(segments["RDT"]?.field(1)?.variableColumns == true)
        #expect(segments["RDT"]?.field(1)?.optionality == .required)
    }

    @Test("CH05 to CH10 fields read by hand against the v2.7.1 attribute tables")
    func laterPrintedFields() throws {
        func field(_ segment: String, _ index: Int) throws -> FieldGrammar {
            try #require(segments[segment]?.field(index), "\(segment)-\(index)")
        }
        // CH07 7.3.2 OBX (p. 46): `2  2..3  ID C 0125 00570 Value Type`;
        // `5  varies C Y 00573`; `11  1..1  ID R 0085 00579`; `26  1..10  ID O N 0909 02313`.
        #expect(try field("OBX", 2).dataType == "ID")
        #expect(try field("OBX", 2).optionality == .conditional)
        #expect(try field("OBX", 2).length == "2..3")
        #expect(try field("OBX", 2).table == "0125")
        #expect(try field("OBX", 5).dataType == "varies")
        #expect(try field("OBX", 5).optionality == .conditional)
        #expect(try field("OBX", 5).repeatability == .multiple)
        #expect(try field("OBX", 11).optionality == .required)
        #expect(try field("OBX", 11).table == "0085")
        #expect(try field("OBX", 26).name == "Patient Results Release Category")
        #expect(try field("OBX", 26).length == "1..10")
        // CH07 7.3.3 SPM (p. 60): `4  CWE R 0487 01900 Specimen Type`.
        #expect(try field("SPM", 4).dataType == "CWE")
        #expect(try field("SPM", 4).optionality == .required)
        // CH07 7.3.4 PRT (p. 69): `4  CWE R 0912 02381 Participation`; 15 fields (v2.8.2 has 22).
        #expect(try field("PRT", 4).dataType == "CWE")
        #expect(try field("PRT", 4).optionality == .required)
        // CH06 6.5.2 DG1 (p. 31, header prints C_LEN): `3  CWE R 0051 00377`; DG1-24 0136 is
        // "for suggested values" (6.5.2.24, p. 36).
        #expect(try field("DG1", 3).dataType == "CWE")
        #expect(try field("DG1", 3).optionality == .required)
        #expect(try field("DG1", 24).tableOpen)
        // CH06 IN1 (p. 73): `2  CWE R 0072 00368 Health Plan ID`.
        #expect(try field("IN1", 2).name == "Health Plan ID")
        #expect(try field("IN1", 2).optionality == .required)
        // CH08 MFE (p. 8, no C.LEN column): `4  Varies R Y 9999 00667`.
        #expect(try field("MFE", 4).dataType == "Varies")
        #expect(try field("MFE", 4).repeatability == .multiple)
        // CH06 GT1 (p. 52): `3  XPN R Y 00407 Guarantor Name`.
        #expect(try field("GT1", 3).dataType == "XPN")
        #expect(try field("GT1", 3).repeatability == .multiple)
        // CH06 FT1 (p. 15): `4  DR R 00358 Transaction Date`.
        #expect(try field("FT1", 4).dataType == "DR")
        #expect(try field("FT1", 4).optionality == .required)
        // CH06 UB2 (p. 132): `13  1..4  ST O Y/23 00565`; UB1 (p. 130): `2  W 00531`.
        #expect(try field("UB2", 13).maxRepetitions == 23)
        #expect(try field("UB1", 2).optionality == .withdrawn)
        // Where v2.7.1 differs from v2.8.2: ARQ-4 is EI (v2.8.2 EIP, CH10 p. 22); OM1-7 does
        // not repeat (CH08 p. 21); MFI-2 prints RP/# `y` (CH08 p. 7).
        #expect(try field("ARQ", 4).dataType == "EI")
        #expect(try field("OM1", 7).repeatability == .single)
        #expect(try field("MFI", 2).repeatability == .multiple)
        // CH08 8.8.11.7 OM4-7 (p. 41): 0371 "can be extended with user specific values".
        #expect(try field("OM4", 7).tableOpen)
    }

    // MARK: - P10-4c: segment schemas, chapters 11 to 17, and the full segment set

    /// Field count of each segment first defined in CH11 to CH17, from the defining attribute
    /// table (re-measured by the P10-4c extraction). ITM is 29: the page-foot footnote on
    /// p. 10 of CH17 is no longer read as a second ITM-2.
    static let finalChapterFieldCounts: [String: [String: Int]] = [
        "CH11": ["AUT": 12, "CTD": 7, "PRD": 14, "RF1": 12],
        "CH12": ["GOL": 22, "PRB": 28, "PTH": 7, "REL": 16, "VAR": 6],
        "CH13": ["CNS": 6, "ECD": 5, "ECR": 3, "EQP": 5, "EQU": 5, "INV": 20, "ISD": 3,
                 "NDS": 4, "SAC": 44, "SID": 4, "TCC": 14, "TCD": 8],
        "CH14": ["NCK": 1, "NSC": 9, "NST": 15],
        "CH15": ["AFF": 5, "CER": 31, "EDU": 9, "LAN": 4, "ORG": 13, "PRA": 12, "ROL": 14,
                 "STF": 41],
        "CH16": ["ADJ": 15, "IPR": 8, "IVC": 30, "PMT": 12, "PSG": 6, "PSL": 48, "PSS": 5,
                 "PYE": 7, "RFI": 4],
        "CH17": ["IIM": 15, "ILT": 10, "ITM": 29, "IVT": 26, "PCE": 4, "PKG": 7, "SCD": 37,
                 "SCP": 8, "SDD": 7, "SLT": 5, "STZ": 4, "VND": 5],
    ]

    @Test("CH11 to CH17: 53 segments, 691 fields")
    func finalChapterSegments() throws {
        let counts = Self.finalChapterFieldCounts.values.reduce(into: [String: Int]()) { $0.merge($1) { a, _ in a } }
        #expect(Self.finalChapterFieldCounts.mapValues(\.count)
                == ["CH11": 4, "CH12": 5, "CH13": 12, "CH14": 3, "CH15": 8, "CH16": 9, "CH17": 12])
        #expect(counts.count == 53)
        #expect(counts.values.reduce(0, +) == 691)
        for (segment, count) in counts {
            let grammar = try #require(segments[segment], "\(segment)")
            #expect(grammar.version == "2.7.1")
            #expect(grammar.fields.count == count, "\(segment)")
            #expect(grammar.fields.map(\.index) == Array(1...count), "\(segment)")
            // Conditions are P10-5a/5b's: nothing is copied from another version here.
            #expect(grammar.fields.allSatisfy { $0.condition == nil && $0.prohibitedWhen == nil }, "\(segment)")
        }
    }

    @Test("The full v2.7.1 segment set: 170 segments, 2519 fields")
    func segmentSet() {
        let pinned = [Self.chapterFieldCounts, Self.laterChapterFieldCounts, Self.finalChapterFieldCounts]
            .flatMap(\.values).reduce(into: [String: Int]()) { $0.merge($1) { a, _ in a } }
        #expect(pinned.count == 170)
        #expect(Set(segments.keys) == Set(pinned.keys))
        #expect(segments.values.map(\.fields.count).reduce(0, +) == 2519)
        // Against the neighbours: v2.7.1 adds IAR, PAC, PRT and SHP to v2.6 and drops the
        // withdrawn query and summary segments; v2.8.2 adds ten segments v2.7.1 lacks.
        let v26 = Set(SegmentGrammarTable.v2_6.keys), v282 = Set(SegmentGrammarTable.v2_8_2.keys)
        let mine = Set(segments.keys)
        #expect(mine.subtracting(v26) == ["IAR", "PAC", "PRT", "SHP"])
        #expect(v26.subtracting(mine) == ["QRD", "QRF", "URD", "URS"])
        #expect(mine.subtracting(v282).isEmpty)
        #expect(v282.subtracting(mine)
                == ["BUI", "CDO", "DON", "DPS", "MCP", "OMC", "PM1", "RXV", "SGH", "SGT"])
    }

    @Test("CH11 to CH17 fields read by hand against the v2.7.1 attribute tables")
    func finalPrintedFields() throws {
        func field(_ segment: String, _ index: Int) throws -> FieldGrammar {
            try #require(segments[segment]?.field(index), "\(segment)-\(index)")
        }
        // CH11 11.8.1 RF1 (p. 45): `1  CWE O 0283 01137 Referral Status`.
        #expect(try field("RF1", 1).dataType == "CWE")
        #expect(try field("RF1", 1).optionality == .optional)
        // CH11 11.8.3 PRD (p. 52): `1  CWE R Y 0286 01155 Provider Role`; PRD-6 and PRD-14
        // 0185 "for suggested values" (11.8.3.6, p. 57; 11.8.3.14, p. 62).
        #expect(try field("PRD", 1).optionality == .required)
        #expect(try field("PRD", 1).repeatability == .multiple)
        #expect(try field("PRD", 6).tableOpen)
        #expect(try field("PRD", 14).tableOpen)
        // CH11 11.8.4 CTD (p. 62): `1  CWE R Y 0131 00196 Contact Role`.
        #expect(try field("CTD", 1).name == "Contact Role")
        #expect(try field("CTD", 1).repeatability == .multiple)
        #expect(try field("CTD", 6).tableOpen)
        // CH12 GOL (p. 24) and PTH (p. 35): `1  2..2  ID R 0287 00816 Action Code`.
        #expect(try field("GOL", 1).length == "2..2")
        #expect(try field("GOL", 1).table == "0287")
        #expect(try field("PTH", 1).dataType == "ID")
        #expect(try field("PTH", 1).optionality == .required)
        // CH13 NDS (p. 42): `1  10=  NM R 01398 Notification Reference Number`; EQU-1 prints
        // no RP/# (v2.8.2 Y), CH13 p. 20.
        #expect(try field("NDS", 1).length == "10=")
        #expect(try field("NDS", 1).dataType == "NM")
        #expect(try field("EQU", 1).repeatability == .single)
        // CH13 13.4.3.27 SAC-27 (p. 29): 0371 "can be extended with user specific values".
        #expect(try field("SAC", 27).tableOpen)
        // CH14 NSC (p. 3): R/O printed blank for NSC-2 to NSC-9, stored as optional.
        #expect(try field("NSC", 1).optionality == .required)
        #expect(try field("NSC", 2).optionality == .optional)
        // CH15 STF (p. 41): `2  CX O Y 0061/0203/0363 00672 Staff Identifier List`.
        #expect(try field("STF", 2).dataType == "CX")
        #expect(try field("STF", 2).repeatability == .multiple)
        // CH15 PRA (p. 28): `1  CWE C 9999 00685 Primary Key Value - PRA`, bare (P10-5).
        #expect(try field("PRA", 1).optionality == .conditional)
        // CH15 LAN (p. 23, header prints C.LEN before LEN): `1  1..4  SI R`; `2  CWE R 0296`.
        #expect(try field("LAN", 1).length == "1..4")
        #expect(try field("LAN", 2).name == "Language Code")
        #expect(try field("LAN", 2).optionality == .required)
        // CH15 ROL (p. 32): `4  XCN R Y 01198 Role Person` (v2.8.2 prints C).
        #expect(try field("ROL", 4).optionality == .required)
        // CH16 RFI (p. 26, header in mixed case): `3  1..1  ID O 0136`, "for suggested values".
        #expect(try field("RFI", 3).length == "1..1")
        #expect(try field("RFI", 3).tableOpen)
        // CH17 IIM (p. 7): `1  CWE R 01897 Primary Key Value - IIM`.
        #expect(try field("IIM", 1).dataType == "CWE")
        #expect(try field("IIM", 1).optionality == .required)
        // CH17 ITM (p. 10): `1  EI R 02186 Item Identifier`; `2  999#  ST O 02274`, read once.
        #expect(try field("ITM", 1).dataType == "EI")
        #expect(try field("ITM", 2).name == "Item Description")
        #expect(try field("ITM", 2).length == "999#")
        // CH17 SCD (p. 44): `1  TM 02104 Cycle Start Time`, R/O/C printed blank.
        #expect(try field("SCD", 1).dataType == "TM")
        #expect(try field("SCD", 1).optionality == .optional)
    }

    @Test("A withdrawn field carries only the data type its attribute table prints")
    func withdrawnFieldsAsPrinted() throws {
        // CH02 section 2.8.4 (p. 24): a withdrawn field's narrative is removed and its detail
        // lives in an earlier version; the tables print its DT cell blank. Only UB1-1 prints
        // one (CH06 section 6.5.10, p. 130: `1  SI  W  00530  Set ID - UB1`).
        let withdrawn = segments.values.flatMap { grammar in
            grammar.fields.filter { $0.optionality == .withdrawn }.map { (grammar.segmentID, $0) }
        }
        #expect(withdrawn.count == 77)
        let typed = withdrawn.filter { !$0.1.dataType.isEmpty }.map { "\($0.0)-\($0.1.index)" }
        #expect(typed == ["UB1-1"])
        #expect(segments["UB1"]?.field(1)?.dataType == "SI")
        // No type is carried from an earlier version (v2.6 and v2.8.2 type PID-2 CX).
        #expect(try #require(segments["PID"]?.field(2)).dataType == "")
        #expect(try #require(segments["DG1"]?.field(7)).dataType == "")
    }
}
