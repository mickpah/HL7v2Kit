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

    @Test("P5: TQ comes from the CH4 quantity/timing definition on v2.3 to v2.4")
    func tqFromChapter4() throws {
        for (version, count) in [(Version.v2_3, 10), (.v2_3_1, 12), (.v2_4, 12)] {
            let tq = try #require(DataTypeGrammarTable.grammar("TQ", version: version), "\(version)")
            #expect(tq.components.count == count, "\(version)")
            #expect(tq.component(1)?.dataType == "CQ", "\(version)")
            #expect(tq.component(4)?.dataType == "TS", "\(version)")
        }
        let tq24 = try #require(DataTypeGrammarTable.grammar("TQ", version: .v2_4))
        #expect(tq24.component(9)?.dataType == "ID")
        #expect(tq24.component(9)?.tables == ["0472"])
        #expect(tq24.component(12)?.dataType == "NM", "the stray ')' after 4.3.12 is layout")
        #expect(SegmentGrammarTable.v2_3["ORC"]?.field(7)?.dataType == "TQ")
        #expect(SegmentGrammarTable.v2_3["OBR"]?.field(27)?.dataType == "TQ")
    }

    // P5-3: the code-table check reaches TQ through Validator.componentGrammar. v2.4 TQ.9
    // Conjunction is ID bound to Table 0472 (CH04 4.3.9); v2.3 prints it as ST.
    @Test("P5-3: v2.4 ORC-7 TQ.9 outside Table 0472 is reported; v2.3 TQ.9 (ST) is not")
    func tqConjunctionTable() throws {
        func tableIssues(_ tq: String, _ version: String) throws -> [ValidationIssue] {
            let wire = "MSH|^~\\&|A|B|C|D|20260101||ORM^O01|M1|P|\(version)\rORC|NW|1|||||\(tq)\r"
            return Validator().validate(try Parser().parse(wire)).issues.filter {
                $0.location.segmentID == "ORC" && $0.location.fieldIndex == 7
                    && $0.code == .valueNotInTable(table: "0472")
            }
        }
        let bad = try tableIssues("1^Q1H^^^^^^^X", "2.4")
        #expect(bad.count == 1)
        #expect(bad.first?.location.componentIndex == 9)
        #expect(try tableIssues("1^Q1H^^^^^^^S", "2.4").isEmpty)
        #expect(try tableIssues("1^Q1H^^^^^^^X", "2.3").isEmpty)
    }

    @Test("P5: MA and NA print no fixed component list before v2.5, so they have no grammar")
    func arraysHaveNoFixedList() {
        for version in [Version.v2_3, .v2_3_1, .v2_4] {
            #expect(DataTypeGrammarTable.grammar("MA", version: version) == nil, "\(version)")
            #expect(DataTypeGrammarTable.grammar("NA", version: version) == nil, "\(version)")
        }
        #expect(DataTypeGrammarTable.grammar("NA", version: .v2_5_1) != nil, "v2.5.1 prints a component table")
    }

    @Test("P5: a field-local CM composite carries its own component grammar")
    func fieldLocalGrammar() throws {
        for version in [Version.v2_3, .v2_3_1, .v2_4] {
            let in3 = try #require(DataTypeGrammarTable.grammar(segment: "IN3", field: 20, version: version), "\(version)")
            #expect(in3.dataType == "CM", "\(version)")
            #expect(in3.components.map(\.dataType) == ["IS", "ID", "TS"], "\(version)")
            #expect(in3.component(2)?.tables == ["0136"], "\(version)")
        }
        let msh9 = try #require(DataTypeGrammarTable.grammar(segment: "MSH", field: 9, version: .v2_3_1))
        #expect(msh9.components.map(\.tables) == [["0076"], ["0003"], ["0354"]])
        #expect(DataTypeGrammarTable.grammar(segment: "MSH", field: 9, version: .v2_3)?.components.count == 2)
        let err1 = try #require(DataTypeGrammarTable.grammar(segment: "ERR", field: 1, version: .v2_4))
        #expect(err1.component(4)?.dataType == "CE")
        #expect(err1.component(4)?.tables == ["0357"])
        #expect(DataTypeGrammarTable.grammar(segment: "OBR", field: 15, version: .v2_4)?.components.count == 7,
                "CH04 sec 4.5.3.15 adds specimen role; CH07 repeats the older six")
        #expect(DataTypeGrammarTable.grammar(segment: "OBR", field: 15, version: .v2_4)?.component(2)?.dataType == "TX")
        #expect(DataTypeGrammarTable.grammar(segment: "PID", field: 3, version: .v2_4) == nil, "CX has its own grammar")
        #expect(DataTypeGrammarTable.grammar(segment: "IN3", field: 20, version: .v2_5_1) == nil, "v2.5 prints tables")
    }

    @Test("P5-5: field-local table bindings, from word and numeric ordinals and a single coded component")
    func fieldLocalBindings() {
        func tables(_ segment: String, _ field: Int, _ component: Int, _ version: Version) -> [String]? {
            DataTypeGrammarTable.grammar(segment: segment, field: field, version: version)?.component(component)?.tables
        }
        for version in [Version.v2_3, .v2_3_1, .v2_4] {
            #expect(tables("OBR", 15, 1, version) == ["0070"], "\(version)")
            #expect(tables("OBR", 15, 4, version) == ["0163"], "\(version)")
            #expect(tables("BLG", 1, 1, version) == ["0100"], "\(version)")
            #expect(tables("BLG", 1, 2, version) == [], "\(version): the trailing Table 0100 figure is not the TS's")
            #expect(tables("PV1", 37, 1, version) == ["0113"], "\(version): the field's one coded component")
        }
        for (segment, field) in [("SAC", 6), ("TCC", 3), ("OBR", 15)] {
            #expect(tables(segment, field, 1, .v2_4) == ["0070"], "\(segment)-\(field)")
            #expect(tables(segment, field, 4, .v2_4) == ["0163"], "\(segment)-\(field)")
            #expect(tables(segment, field, 7, .v2_4) == ["0369"], "\(segment)-\(field): \"The 7th component\"")
        }
        #expect(tables("UB2", 7, 1, .v2_4) == ["0350"])
        #expect(tables("IN2", 28, 1, .v2_4) == [], "one sentence names 0145 and 0146: fail-safe")
        #expect(tables("MSH", 9, 1, .v2_3) == [], "v2.3 names 0076 and 0003 in one sentence")
    }

    @Test("P5: the field-local lookup resolves the version's grammar version")
    func fieldLocalGrammarVersion() {
        // `2.8` validates against the v2.8.2 grammar (ADR-018); the lookup reaches v2.8.2's table
        // through Version.grammarVersion alone. v2.8.2 prints no CM, so that table is empty today.
        let keys = Set([Version.v2_3, .v2_3_1, .v2_4].flatMap { DataTypeGrammarTable.fieldGrammars(for: $0).keys })
        for key in keys {
            let parts = key.split(separator: "-")
            let (segment, field) = (String(parts[0]), Int(parts[1])!)
            for version in Version.allCases {
                #expect(DataTypeGrammarTable.grammar(segment: segment, field: field, version: version)
                        == DataTypeGrammarTable.grammar(segment: segment, field: field, version: version.grammarVersion),
                        "\(key) \(version)")
            }
            #expect(DataTypeGrammarTable.grammar(segment: segment, field: field, version: .v2_8)
                    == DataTypeGrammarTable.grammar(segment: segment, field: field, version: .v2_8_2), "\(key)")
        }
        #expect(DataTypeGrammarTable.grammar(segment: "IN3", field: 20, version: .v2_8) == nil, "v2.8.2 prints tables")
        #expect(DataTypeGrammarTable.fieldGrammars(for: .v2_4).count == 43)
        #expect(DataTypeGrammarTable.fieldGrammars(for: .v2_3_1).count == 41)
        #expect(DataTypeGrammarTable.fieldGrammars(for: .v2_3).count == 45)
    }

    @Test("P5: every pre-v2.5 field-local composite has a grammar or a registered reason")
    func fieldLocalCoverage() {
        // The enumerated v2.5-era names on pre-v2.5 CM fields (audit-schemas.py CM_REFINEMENTS;
        // SPS and NDL are not among them, P5-7), and v2.3's field-printed names.
        let fieldLocal: Set<String> = ["CM", "MSG", "MOC", "PRL", "EIP", "PTS", "SVC"]
        // ADR-017 P5 addendum: OM2-6 prints its structure as a narrative repetition list.
        let registered: Set<String> = ["2.3/OM2-6", "2.3.1/OM2-6", "2.4/OM2-6"]
        let versions: [(Version, [String: SegmentGrammar])] = [
            (.v2_3, SegmentGrammarTable.v2_3), (.v2_3_1, SegmentGrammarTable.v2_3_1), (.v2_4, SegmentGrammarTable.v2_4),
        ]
        for (version, segments) in versions {
            for (id, segment) in segments {
                for field in segment.fields where fieldLocal.contains(field.dataType) {
                    guard DataTypeGrammarTable.grammar(field.dataType, version: version) == nil else { continue }
                    let key = "\(version.rawValue)/\(id)-\(field.index)"
                    let modelled = DataTypeGrammarTable.grammar(segment: id, field: field.index, version: version) != nil
                    #expect(modelled != registered.contains(key), "\(key): modelled \(modelled)")
                }
            }
        }
    }

    @Test("P5: pre-v2.5 OBR-15 and OBR-32..35 stay CM; v2.5's SPS and NDL are different structures")
    func cmRefinementsHonest() throws {
        let versions: [(Version, [String: SegmentGrammar])] = [
            (.v2_3, SegmentGrammarTable.v2_3), (.v2_3_1, SegmentGrammarTable.v2_3_1), (.v2_4, SegmentGrammarTable.v2_4),
        ]
        for (version, segments) in versions {
            let obr = try #require(segments["OBR"], "\(version)")
            #expect(obr.field(15)?.dataType == "CM", "\(version) OBR-15")
            for index in 32...35 {
                #expect(obr.field(index)?.dataType == "CM", "\(version) OBR-\(index)")
            }
            #expect(obr.field(26)?.dataType == "PRL", "\(version): identical structure keeps the v2.5 name")
            #expect(DataTypeGrammarTable.grammar(segment: "OBR", field: 15, version: version)?.component(2)?.dataType == "TX",
                    "\(version): additives (TX); v2.5.1 SPS.2 is CWE")
            #expect(DataTypeGrammarTable.grammar(segment: "OBR", field: 32, version: version)?.component(1)?.dataType == "CN",
                    "\(version): name (CN); v2.5.1 NDL.1 is CNN")
        }
        #expect(SegmentGrammarTable.v2_4["MSH"]?.field(9)?.dataType == "MSG", "HL7au:00049.1 dispatch")
    }
}
