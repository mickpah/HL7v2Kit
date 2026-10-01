// SchemaAttributeFixTests.swift
// P6: schema attributes corrected to what the attribute tables print.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Schema attribute fixes")
struct SchemaAttributeFixTests {

    /// One segment line with `fields[i]` at position `i` and every other position empty.
    func line(_ id: String, _ fields: [Int: String]) -> String {
        let last = fields.keys.max() ?? 1
        return ([id] + (1...last).map { fields[$0] ?? "" }).joined(separator: "|") + "\r"
    }

    // V282-C11: v2.8.2 CH11 prints RF1-18 as "M0" in the attribute table but "(MO)" in the
    // field heading (§11.8.1.18) and for the same element at AUT-22 (§11.8.2.22).
    @Test("v2.8.2 RF1-18 is typed MO and dispatches to the MO component grammar")
    func rf1RemainingBenefitAmountIsMO() throws {
        let field = try #require(SegmentGrammarTable.v2_8_2["RF1"]?.field(18))
        #expect(field.dataType == "MO")
        let grammar = try #require(DataTypeGrammarTable.grammar(field.dataType, version: .v2_8_2))
        #expect(grammar.components.map(\.name) == ["Quantity", "Denomination"])
    }

    // V231-C14: OBX lengths come from the base attribute figure (Figure 7-5), not from the
    // Chapter 7 waveform category tables (Figures 7-26/7-27), which constrain one category.
    @Test("v2.3 / v2.3.1 OBX-2 and OBX-16 lengths follow the base Figure 7-5")
    func obxBaseFigureLengths() {
        #expect(SegmentGrammarTable.v2_3_1["OBX"]?.field(2)?.length == "3")
        #expect(SegmentGrammarTable.v2_3_1["OBX"]?.field(16)?.length == "80")
        #expect(SegmentGrammarTable.v2_3["OBX"]?.field(2)?.length == "2")
        #expect(SegmentGrammarTable.v2_3["OBX"]?.field(16)?.length == "80")
    }

    // V231-C16: Appendix C Figure C-3 prints NSC-1 as 4 and NSC-2..9 as 30.
    @Test("v2.3.1 NSC lengths follow Appendix C Figure C-3")
    func nscLengths() {
        let nsc = SegmentGrammarTable.v2_3_1["NSC"]
        #expect(nsc?.field(1)?.length == "4")
        for index in 2...9 {
            #expect(nsc?.field(index)?.length == "30", "NSC-\(index)")
        }
    }

    // Pre-flight ruling d4 (P7-1 length intake, OBR/OBX rows for v2.3 and v2.3.1): OBR's
    // defining chapter is Chapter 4 (Order Entry) — its Figure 4-8 prints OBR-16 as 120 on
    // v2.3.1, while Chapter 7's reproduction (Figure 7-4) still prints the stale 80.
    @Test("v2.3.1 OBR-16 length follows the Chapter 4 defining Figure 4-8")
    func obrOrderingProviderLengthV231() {
        #expect(SegmentGrammarTable.v2_3_1["OBR"]?.field(16)?.length == "120")
    }

    // v2.3 Figure 4-8 (Chapter 4, the defining table) prints OBR-2 and OBR-3 as 75; Chapter
    // 7's reproduction (Figure 7-4) still prints the stale 22.
    @Test("v2.3 OBR-2 and OBR-3 lengths follow the Chapter 4 defining Figure 4-8")
    func obrOrderNumberLengthsV23() {
        #expect(SegmentGrammarTable.v2_3["OBR"]?.field(2)?.length == "75")
        #expect(SegmentGrammarTable.v2_3["OBR"]?.field(3)?.length == "75")
    }

    // v2.3 Figure 7-5 prints OBX-1 as 10 and OBX-3 as 590.
    @Test("v2.3 OBX-1 and OBX-3 lengths follow Figure 7-5")
    func obxSetIdAndIdentifierLengthsV23() {
        #expect(SegmentGrammarTable.v2_3["OBX"]?.field(1)?.length == "10")
        #expect(SegmentGrammarTable.v2_3["OBX"]?.field(3)?.length == "590")
    }

    // OBX-5's own footnote (v2.3 Figure 7-5 footnote 2 / v2.3.1 Figure 7-5 footnote 3)
    // states the field's length is variable, depending on OBX-2's value type, overriding the
    // LEN column's printed numeric cap (65536, OCR-glued to its footnote marker as
    // "655362"/"65536" + "4"). The schema keeps the variable-length placeholder `*` on both
    // versions; a cited LENGTH_WHITELIST entry records the printed-vs-modelled divergence.
    @Test("v2.3 / v2.3.1 OBX-5 keeps the variable-length placeholder per its own footnote")
    func obxObservationValueStaysVariableLength() {
        #expect(SegmentGrammarTable.v2_3["OBX"]?.field(5)?.length == "*")
        #expect(SegmentGrammarTable.v2_3["OBX"]?.field(5)?.dataType == "*")
        #expect(SegmentGrammarTable.v2_3_1["OBX"]?.field(5)?.length == "*")
        #expect(SegmentGrammarTable.v2_3_1["OBX"]?.field(5)?.dataType == "*")
    }

    // V282-C04: CH02 §2.14.1 prints the ADD attribute table on v2.6 and v2.8.2 (SEQ 1-n, ST, O).
    @Test("ADD is modelled on v2.6 and v2.8.2 and is not treated as a Z-segment")
    func addOnV26AndV282() throws {
        let cases: [([String: SegmentGrammar], String)] = [
            (SegmentGrammarTable.v2_6, "2.6"),
            (SegmentGrammarTable.v2_8_2, "2.8.2"),
        ]
        var options = ValidationOptions.default
        options.zSegmentPolicy = .reject
        for (table, version) in cases {
            let add = try #require(table["ADD"], "v\(version)")
            #expect(add.fields.count == 1)
            #expect(add.field(1)?.dataType == "ST")
            #expect(add.field(1)?.optionality == .optional)
            #expect(add.field(1)?.variableColumns == true)
            let wire = "MSH|^~\\&|A|B|C|D|20240101120000||ADT^A01|M1|P|\(version)\r"
                + "ADD|more text|and more\r"
            let report = Validator(options: options).validate(try Parser().parse(wire))
            #expect(!report.issues.contains { $0.code == .zSegmentPresent }, "v\(version)")
        }
        #expect(SegmentGrammarTable.v2_6["ADD"]?.field(1)?.length == "65536")
        #expect(SegmentGrammarTable.v2_8_2["ADD"]?.field(1)?.length == nil, "v2.8.2 prints neither LEN nor C.LEN")
    }

    // V231-C05: v2.3.1 §7.11.3 Figure 7-22. RP/# is blank for PCR-5..11 and 13..20; the
    // p. 7-96 column shift put the TBL# number where the extractor read RP.
    @Test("v2.3.1 PCR repeatability follows the printed rows")
    func pcrRepeatability() {
        let pcr = SegmentGrammarTable.v2_3_1["PCR"]
        for index in [9, 11, 13, 15, 17, 19, 20] {
            #expect(pcr?.field(index)?.repeatability == .single, "PCR-\(index)")
        }
        #expect(pcr?.field(12)?.maxRepetitions == 3)
        #expect(pcr?.field(21)?.maxRepetitions == 6)
        #expect(pcr?.field(22)?.maxRepetitions == 6)
        #expect(pcr?.field(23)?.maxRepetitions == 3)
    }

    @Test("v2.3.1 PCR-9 with two repetitions raises cardinalityExceeded")
    func pcr9Repeated() throws {
        let wire = "MSH|^~\\&|A|B|C|D|20240101120000||PEX^P07|M1|P|2.3.1\r"
            + line("PCR", [1: "D1^Device", 9: "Y~N"])
        let issues = try Validator().validate(Parser().parse(wire)).issues
        #expect(issues.contains { $0.code == .cardinalityExceeded && $0.location.segmentID == "PCR" && $0.location.fieldIndex == 9 })
    }

    // P6-12: lengths the extractor now reads where a right-aligned LEN cell sat nearer the DT
    // header (v2.6 STF, GOL), a "C_LEN" header (v2.8.2 DG1), or where the M25 sweep had
    // recorded a wrong value (v2.6 OBX-5 "24", v2.5.1 OBX-6 "6", v2.8.2 OBX-2 "2..2", and
    // v2.6 UAC-1 "7 05", the 705 that pdftotext splits).
    @Test("P6-12 lengths follow the printed LEN and C.LEN cells")
    func p612PrintedLengths() {
        #expect(SegmentGrammarTable.v2_6["STF"]?.field(4)?.length == "2")
        #expect(SegmentGrammarTable.v2_6["STF"]?.field(31)?.length == "8")
        #expect(SegmentGrammarTable.v2_6["GOL"]?.field(1)?.length == "2")
        #expect(SegmentGrammarTable.v2_6["UAC"]?.field(1)?.length == "705")
        #expect(SegmentGrammarTable.v2_6["OBX"]?.field(5)?.length == "*")
        #expect(SegmentGrammarTable.v2_5_1["OBX"]?.field(6)?.length == "250")
        #expect(SegmentGrammarTable.v2_8_2["OBX"]?.field(2)?.length == "2..3")
        #expect(SegmentGrammarTable.v2_8_2["DG1"]?.field(15)?.length == "2=")
    }
}
