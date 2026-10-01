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
}
