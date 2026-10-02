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
        #expect(HL7TableRegistry.table("0203", version: .v2_4)?.isClosed == false, "never closed: user-defined until v2.5, then cited for suggested values")
        #expect(cx24.component(5)?.tables == ["0203"])
        #expect(cx24.component(5)?.optionalityCode == "", "prose gives no optionality")
        #expect(cx24.components.count == 8, "v2.4 CX has eight components; v2.5.1 added two")
        #expect(DataTypeGrammarTable.grammar("CX", version: .v2_8) == nil, "the registry stays version-literal: .v2_8 owns no grammar; the Validator substitutes v2.8.2 (ADR-018)")
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

    @Test("Printed lengths are recorded verbatim on fields and components, never enforced")
    func lengthsRecorded() throws {
        #expect(SegmentGrammarTable.v2_5_1["PID"]?.field(5)?.length == "250")
        #expect(SegmentGrammarTable.v2_8_2["MSH"]?.field(10)?.length == "1..199", "v2.7+ prints a normative range")
        #expect(SegmentGrammarTable.v2_8_2["PID"]?.field(5)?.length == nil, "v2.8.2 prints only a conformance length for XPN fields")
        #expect(DataTypeGrammarTable.grammar("CX", version: .v2_5_1)?.component(1)?.length == "15")
        #expect(DataTypeGrammarTable.grammar("CX", version: .v2_4)?.component(1)?.length == nil, "prose prints none")
        // Never enforced: a 300-character name in a LEN 250 field validates.
        let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01^ADT_A01|MSG00001|P|2.5.1\rPID|1||123^^^HOSP^MR||\(String(repeating: "X", count: 300))^JOHN\r"
        #expect(Validator().validate(try Parser().parse(wire)).isValid)
    }

    @Test("P5: the printed Components line completes prose composites (CE.4-6, CNE.9)")
    func componentsLineCompletesProse() throws {
        for version in [Version.v2_3, .v2_3_1, .v2_4] {
            let ce = try #require(DataTypeGrammarTable.grammar("CE", version: version), "\(version)")
            #expect(ce.components.count == 6, "\(version): the Components line prints six")
            #expect(ce.component(4)?.name.lowercased() == "alternate identifier", "\(version)")
            #expect(ce.component(4)?.dataType == "ST", "\(version)")
            #expect(ce.component(6)?.dataType == (version == .v2_4 ? "IS" : "ST"), "\(version)")
            #expect(DataTypeGrammarTable.grammar("DLN", version: version)?.component(1)?.dataType == "ST", "\(version)")
        }
        let cne = try #require(DataTypeGrammarTable.grammar("CNE", version: .v2_3_1))
        #expect(cne.components.count == 9)
        #expect(cne.component(9)?.name.lowercased() == "original text")
        #expect(cne.component(9)?.dataType == "ST")
        #expect(DataTypeGrammarTable.grammar("CNE", version: .v2_4)?.components.count == 9)
        #expect(DataTypeGrammarTable.grammar("ED", version: .v2_3)?.component(2)?.dataType == "ID")
        #expect(DataTypeGrammarTable.grammar("ED", version: .v2_3)?.component(2)?.tables == ["0191"])
        #expect(DataTypeGrammarTable.grammar("SN", version: .v2_3)?.component(1)?.name == "Comparator")
    }

    @Test("P5: CD, CF and TS come from their printed Components / Format line on v2.3 to v2.4")
    func componentsLineOnly() throws {
        for version in [Version.v2_3, .v2_3_1, .v2_4] {
            let ts = try #require(DataTypeGrammarTable.grammar("TS", version: version), "\(version)")
            #expect(ts.components.count == 2, "\(version)")
            #expect(ts.component(2)?.name == "Degree of precision", "\(version)")
            #expect(ts.component(2)?.dataType == "", "\(version): the Format line prints no code")
            let cf = try #require(DataTypeGrammarTable.grammar("CF", version: version), "\(version)")
            let coding = version == .v2_4 ? "IS" : "ST"
            #expect(cf.components.map(\.dataType) == ["ID", "FT", coding, "ID", "FT", coding], "\(version)")
            let cd = try #require(DataTypeGrammarTable.grammar("CD", version: version), "\(version)")
            #expect(cd.components.count == 6, "\(version)")
            #expect(cd.component(5)?.dataType == "NM", "\(version)")
        }
    }
}
