import Testing
@testable import HL7v2Kit

@Suite("Component-level code-table validation")
struct ComponentCodeTableTests {
    private func wire(version: String = "2.5.1", pid3: String = "123^^^AUTH^MR", pid5: String = "DOE^JOHN") -> String {
        "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01^ADT_A01|MSG00001|P|\(version)\r"
            + "PID|1||\(pid3)||\(pid5)\r"
    }

    private func tableIssues(_ wire: String, options: ValidationOptions = ValidationOptions(),
                             locale: HL7Locale = .international) throws -> [ValidationIssue] {
        Validator(options: options, locale: locale).validate(try Parser().parse(wire)).issues
            .filter { if case .valueNotInTable = $0.code { return true } else { return false } }
    }

    @Test("CX.5 outside the printed Table 0203 is silent: CX.5 cites the table 'for suggested values'")
    func cx5OutsideTable() throws {
        for (wireVersion, version) in [("2.4", Version.v2_4), ("2.5.1", .v2_5_1), ("2.6", .v2_6), ("2.8.2", .v2_8_2)] {
            #expect(try tableIssues(wire(version: wireVersion, pid3: "123^^^AUTH^ZZZZ")).isEmpty, "v\(wireVersion)")
            let t = try #require(HL7TableRegistry.table("0203", version: version))
            #expect(t.kind == .hl7 && t.permitsLocalExtensions && !t.isClosed, "v\(wireVersion)")
        }
    }

    @Test("An ID component outside a closed table is an error located at the component")
    func componentOutsideClosedTable() throws {
        // XPN.7 Name Type Code is ID / closed HL7 Table 0200.
        let issues = try tableIssues(wire(pid5: "DOE^JOHN^^^^^QQQ"))
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.code == .valueNotInTable(table: "0200"))
        #expect(issue.severity == .error)
        #expect(issue.location.pathDescription == "PID[1]-5.7")
    }

    @Test("A printed code, an empty component and the HL7 null are all silent")
    func silentCases() throws {
        #expect(try tableIssues(wire(pid3: "123^^^AUTH^MR")).isEmpty)
        #expect(try tableIssues(wire(pid3: "123^^^AUTH")).isEmpty)
        #expect(try tableIssues(wire(pid3: "123^^^AUTH^\"\"")).isEmpty)
    }

    @Test("Each repetition is checked independently")
    func repetitions() throws {
        let issues = try tableIssues(wire(pid5: "DOE^JOHN^^^^^QQQ~DOE^J^^^^^L~ROE^R^^^^^WWW"))
        #expect(issues.count == 2)
    }

    @Test("Only ID components on closed tables are enforced: IS and open tables never are")
    func neverEnforced() throws {
        // XPN.7 Name Type Code is ID / 0200 (closed): enforced. XPN.6 Degree is IS / 0360: never.
        #expect(try tableIssues(wire(pid5: "DOE^JOHN^^^^QQQ^L")).isEmpty, "IS component, user-defined table")
        #expect(try tableIssues(wire(pid5: "DOE^JOHN^^^^^QQQ")).count == 1, "ID component, closed table 0200")
        // MSG.3 is ID / 0354, which is never closed (the chapters use structures it omits).
        let odd = wire().replacingOccurrences(of: "ADT^A01^ADT_A01", with: "ADT^A01^ADT_Q99")
        #expect(try tableIssues(odd).isEmpty)
    }

    @Test("Every version is checked under ITS OWN component grammar")
    func perVersionGrammar() throws {
        // Table 0203 Identifier type is never a closed set: user-defined until v2.5 (CX.5 is IS in
        // v2.3 and v2.3.1), and an HL7 table cited "for suggested values" from v2.4 on (P2-7).
        for version in ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.8.2"] {
            #expect(try tableIssues(wire(version: version, pid3: "123^^^AUTH^ZZZZ")).isEmpty, "v\(version)")
        }
        // XPN.7 Name type code is ID / 0200 on every version, v2.3 included (prose-derived grammar).
        #expect(try tableIssues(wire(version: "2.3", pid5: "DOE^JOHN^^^^^QQQ")).count == 1)
        #expect(try tableIssues(wire(version: "2.4", pid5: "DOE^JOHN^^^^^L")).isEmpty)
        // A 2.8 message is checked against the v2.8.2 component grammar (ADR-018): XPN.7 is
        // closed there too, same as v2.3 above (table 0203 is open, so it cannot demonstrate this).
        let v28Issues = try tableIssues(wire(version: "2.8", pid5: "DOE^JOHN^^^^^QQQ"))
        #expect(v28Issues.map(\.code) == [.valueNotInTable(table: "0200")])
        #expect(v28Issues == (try tableIssues(wire(version: "2.8.2", pid5: "DOE^JOHN^^^^^QQQ"))))
    }

    @Test("A prose misprint never becomes a rule: v2.3 QSC.4 names table 0102 for Relational conjunction")
    func proseMisprintStaysUnbound() throws {
        let qsc = try #require(DataTypeGrammarTable.grammar("QSC", version: .v2_3))
        #expect(qsc.component(4)?.tables.isEmpty == true, "v2.3 0102 is Delayed Acknowledgment Type")
        #expect(DataTypeGrammarTable.grammar("QSC", version: .v2_4)?.component(4)?.tables == ["0210"])
    }

    @Test("checkCodeTables = false and the lenient preset suppress the component check")
    func optionOff() throws {
        var options = ValidationOptions()
        options.checkCodeTables = false
        #expect(try tableIssues(wire(pid5: "DOE^JOHN^^^^^QQQ")).count == 1, "the default options do flag it")
        #expect(try tableIssues(wire(pid5: "DOE^JOHN^^^^^QQQ"), options: options).isEmpty)
        #expect(try tableIssues(wire(pid5: "DOE^JOHN^^^^^QQQ"), options: .lenient).isEmpty)
    }

    @Test("A locale's rendering of the table widens the component check too")
    func localeWidens() throws {
        // AUSNATA is printed by AU ADRM-2021 Table 0301 (p. 161) and by no base version.
        let w = wire().replacingOccurrences(of: "|HIS|FAC|", with: "|HIS|QML^2184^AUSNATA|")
        #expect(try tableIssues(w).count == 1)
        #expect(try tableIssues(w, locale: .auLocalisation).isEmpty)
    }

    @Test("Table 0301 prints L,M,N in one row: they are three codes, and each is valid in HD.3")
    func localUniversalIDTypes() throws {
        for version in [Version.v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_8_2] {
            let t = try #require(HL7TableRegistry.table("0301", version: version))
            #expect(t.contains("L") && t.contains("M") && t.contains("N"), "0301 on \(version)")
            #expect(!t.contains("L,M,N"))
        }
        for type in ["L", "M", "N", "ISO"] {
            let w = wire().replacingOccurrences(of: "|HIS|FAC|", with: "|HIS^1.2.3^\(type)|FAC|")
            #expect(try tableIssues(w).isEmpty, "MSH-3 HD.3 = \(type)")
        }
        let bad = wire().replacingOccurrences(of: "|HIS|FAC|", with: "|HIS^1.2.3^QQQ|FAC|")
        #expect(try tableIssues(bad).first?.location.pathDescription == "MSH[1]-3.3")
    }

    @Test("A component that is itself composite is descended into: CX.4 is an HD, so CX.4.3 is checked")
    func nestedSubcomponent() throws {
        let issues = try tableIssues(wire(pid3: "123^^^AUTH&1.2.3&QQQ^MR"))
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.code == .valueNotInTable(table: "0301"))
        #expect(issue.location.componentIndex == 4)
        #expect(issue.location.subcomponentIndex == 3)
        #expect(issue.location.pathDescription == "PID[1]-3.4.3")
        #expect(try tableIssues(wire(pid3: "123^^^AUTH&1.2.3&ISO^MR")).isEmpty)
        #expect(try tableIssues(wire(pid3: "123^^^AUTH&1.2.3^MR")).isEmpty, "absent subcomponent")
        #expect(try tableIssues(wire(pid3: "123^^^AUTH&1.2.3&\"\"^MR")).isEmpty, "HL7 null")
    }

    @Test("Component and subcomponent levels report independently")
    func bothLevels() throws {
        let issues = try tableIssues(wire(pid3: "123^^^AUTH&1.2.3&QQQ^MR", pid5: "DOE^JOHN^^^^^QQQ"))
        #expect(Set(issues.map(\.location.pathDescription)) == ["PID[1]-3.4.3", "PID[1]-5.7"])
    }

    @Test("OBX-5 is checked under the datatype OBX-2 declares")
    func obx5UnderObx2() throws {
        func oru(_ obx2: String, _ obx5: String) -> String {
            "MSH|^~\\&|LAB|FAC|HIS|FAC|||ORU^R01^ORU_R01|MSG1|P|2.5.1\r"
                + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
                + "OBR|1|||GLU^Glucose^L\r"
                + "OBX|1|\(obx2)|GLU^Glucose^L||\(obx5)||||||F\r"
        }
        // XTN.2 Telecommunication Use Code is ID / 0201 (closed).
        let bad = try tableIssues(oru("XTN", "^QQQ^PH"))
        #expect(bad.map(\.location.pathDescription) == ["OBX[1]-5.2"])
        #expect(try tableIssues(oru("XTN", "^PRN^PH")).isEmpty)
        #expect(try tableIssues(oru("ST", "QQQ")).isEmpty, "a primitive OBX-2 has no component grammar")
        #expect(try tableIssues(oru("", "^QQQ^PH")).isEmpty, "no OBX-2, no datatype, no check")
    }

    @Test("AU v2.4 traffic: AUSNATA is a universal ID type under the AU locale, and not under base v2.4")
    func auUniversalIDTypes() throws {
        // MSH-4 Sending Facility as Australian pathology labs send it: QML^2184^AUSNATA.
        let au = wire(version: "2.4").replacingOccurrences(of: "|HIS|FAC|", with: "|HIS|QML^2184^AUSNATA|")
        #expect(try tableIssues(au, locale: .auLocalisation).isEmpty, "ADRM-2021 Table 0301 p. 161 prints AUSNATA")
        let base = try tableIssues(au)
        #expect(base.map(\.location.pathDescription) == ["MSH[1]-4.3"], "base v2.4 Table 0301 does not print it")
        let t = try #require(HL7TableRegistry.table("0301", locale: .auLocalisation))
        for code in ["AUSHICPR", "AUSHIC", "AUSDVA", "AUSNATA", "AUSLSPN", "L", "M", "N", "ISO"] { #expect(t.contains(code)) }
    }

    @Test("v2.3 tables printed only in the chapters are in the registry: HD.3 is checked on v2.3 too")
    func v23ChapterTables() throws {
        for number in ["0298", "0299", "0301", "0336"] {
            #expect(HL7TableRegistry.table(number, version: .v2_3) != nil, "v2.3 Appendix A omits \(number)")
        }
        let t = try #require(HL7TableRegistry.table("0301", version: .v2_3))
        #expect(t.contains("L") && t.contains("ISO") && t.isClosed)
        #expect(DataTypeGrammarTable.grammar("HD", version: .v2_3)?.component(3)?.tables == ["0301"])
        let bad = wire(version: "2.3").replacingOccurrences(of: "|HIS|FAC|", with: "|HIS^1.2.3^QQQ|FAC|")
        #expect(try tableIssues(bad).first?.location.pathDescription == "MSH[1]-3.3")
        #expect(try tableIssues(wire(version: "2.3").replacingOccurrences(of: "|HIS|FAC|", with: "|HIS^1.2.3^ISO|FAC|")).isEmpty)
    }

    @Test("Table 0203 NNxxx is a pattern: NN plus an ISO 3166 alpha-3 country code")
    func nationalPersonIdentifierPattern() throws {
        for version in ["2.5.1", "2.6", "2.8.2"] {
            #expect(try tableIssues(wire(version: version, pid3: "123^^^AUTH^NNAUS")).isEmpty, "v\(version) NNAUS")
            #expect(try tableIssues(wire(version: version, pid3: "123^^^AUTH^NNCAN")).isEmpty, "v\(version) NNCAN")
            #expect(try tableIssues(wire(version: version, pid3: "123^^^AUTH^NNAU1")).isEmpty, "v\(version): 0203 is open (P2-7)")
        }
        for version in [Version.v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_8_2] {
            let t = try #require(HL7TableRegistry.table("0203", version: version))
            #expect(t.patterns.map(\.code) == ["NNxxx"], "\(version)")
            #expect(t.contains("NNAUS"), "\(version)")
            #expect(!t.contains("NNAU1") && !t.contains("NNaus") && !t.contains("NNAUST"), "\(version)")
            #expect(!t.codes.contains("NNxxx"), "\(version): the printed placeholder is not a code")
        }
        #expect(HL7TableRegistry.table("0203", version: .v2_3)?.patterns.isEmpty == true, "v2.3 prints no NNxxx row")
    }

    @Test("A table reference hyphenated across a line break still binds: PT.2 0207, PL.6 0305")
    func hyphenatedTableReference() throws {
        #expect(DataTypeGrammarTable.grammar("PT", version: .v2_3_1)?.component(2)?.tables == ["0207"])
        #expect(DataTypeGrammarTable.grammar("PT", version: .v2_4)?.component(2)?.tables == ["0207"])
        #expect(DataTypeGrammarTable.grammar("PL", version: .v2_3_1)?.component(6)?.tables == ["0305"])
        let bad = wire(version: "2.3.1").replacingOccurrences(of: "|P|2.3.1", with: "|P^X|2.3.1")
        #expect(try tableIssues(bad).map(\.location.pathDescription) == ["MSH[1]-11.2"])
        let good = wire(version: "2.3.1").replacingOccurrences(of: "|P|2.3.1", with: "|P^T|2.3.1")
        #expect(try tableIssues(good).isEmpty)
    }

    private func in3Wire(version: String, in3_20: String) -> String {
        "MSH|^~\\&|HIS|FAC|PAYER|FAC|||BAR^P01|MSG00001|P|\(version)\r"
            + "IN3|1" + String(repeating: "|", count: 19) + in3_20 + "\r"
    }

    @Test("P5: a CM component bound to a closed HL7 table is checked on v2.3 to v2.4",
          arguments: ["2.3", "2.3.1", "2.4"])
    func fieldLocalClosedTable(version: String) throws {
        let issues = try tableIssues(in3Wire(version: version, in3_20: "ER^X"))
        #expect(issues.map(\.code) == [.valueNotInTable(table: "0136")], "IN3-20.2 is HL7 Table 0136 (Y, N)")
        #expect(issues.first?.location.pathDescription == "IN3[1]-20.2")
        #expect(try tableIssues(in3Wire(version: version, in3_20: "ER^Y")).isEmpty)
        #expect(try tableIssues(in3Wire(version: version, in3_20: "ZZ^N")).isEmpty, "IN3-20.1 is IS: never enforced")
    }

    @Test("P5: MSH-9 components bind open tables on v2.3.1, so a local trigger event is silent")
    func msh9OpenTablesSilent() throws {
        #expect(HL7TableRegistry.table("0003", version: .v2_3_1)?.isClosed == false)
        let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^Z99^ADT_A01|MSG00001|P|2.3.1\r"
        #expect(try tableIssues(wire).isEmpty)
    }
}
