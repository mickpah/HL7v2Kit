import Testing
@testable import HL7v2Kit

@Suite("Datatype component grammar")
struct DataTypeGrammarTests {
    @Test("CX on v2.5.1 carries its components and their table bindings")
    func cxComponents() throws {
        let cx = try #require(DataTypeGrammarTable.grammar("CX", version: .v2_5_1))
        #expect(cx.name == "Extended Composite ID with Check Digit")
        #expect(cx.components.map(\.index) == Array(1...cx.components.count))
        let type = try #require(cx.component(5))
        #expect(type.name == "Identifier Type Code")
        #expect(type.dataType == "ID")
        #expect(type.tables == ["0203"])
        #expect(cx.component(1)?.optionalityCode == "R")
        #expect(cx.component(1)?.tables.isEmpty == true)
        #expect(cx.component(99) == nil)
    }

    @Test("Grammar is per version: v2.8.2 withdrew CE; v2.3 to v2.4 come from prose")
    func perVersion() throws {
        #expect(DataTypeGrammarTable.grammar("CE", version: .v2_5_1) != nil)
        #expect(DataTypeGrammarTable.grammar("CE", version: .v2_8_2) == nil)
        let cx23 = try #require(DataTypeGrammarTable.grammar("CX", version: .v2_3))
        let cx24 = try #require(DataTypeGrammarTable.grammar("CX", version: .v2_4))
        #expect(cx23.component(5)?.dataType == "IS" && cx24.component(5)?.dataType == "ID")
        #expect(DataTypeGrammarTable.grammar("CX", version: .v2_3_1)?.component(5)?.dataType == "IS")
        #expect(HL7TableRegistry.table("0203", version: .v2_4)?.isClosed == false, "user-defined until v2.5")
        #expect(cx24.component(5)?.tables == ["0203"])
        #expect(cx24.component(5)?.optionalityCode == "", "prose gives no optionality")
        #expect(cx24.components.count == 8, "v2.4 CX has eight components; v2.5.1 added two")
        #expect(DataTypeGrammarTable.grammar("CX", version: .v2_8) == nil, "grammar-less v2.8 (ADR-013)")
    }

    @Test("The printed optionality code is kept verbatim, including RE and W")
    func optionalityVerbatim() throws {
        let xpn = try #require(DataTypeGrammarTable.grammar("XPN", version: .v2_8_2))
        #expect(xpn.component(1)?.optionalityCode == "RE")
        let xtn = try #require(DataTypeGrammarTable.grammar("XTN", version: .v2_6))
        #expect(xtn.component(1)?.optionalityCode == "W")
        #expect(xtn.component(1)?.dataType == "", "a withdrawn component prints no datatype")
    }

    @Test("Every bound component table resolves in the registry, bar the 9999 sentinel")
    func tablesResolve() {
        for version in [Version.v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_8_2] {
            for grammar in DataTypeGrammarTable.grammars(for: version).values {
                for component in grammar.components {
                    for number in component.tables where number != "9999" {
                        #expect(HL7TableRegistry.table(number, version: version) != nil,
                                "\(grammar.dataType).\(component.index) -> \(number) on \(version)")
                    }
                }
            }
        }
    }
}
