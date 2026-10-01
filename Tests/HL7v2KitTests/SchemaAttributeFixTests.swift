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
}
