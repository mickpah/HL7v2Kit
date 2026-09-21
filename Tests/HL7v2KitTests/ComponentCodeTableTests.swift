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

    @Test("CX.5 outside HL7 Table 0203 is an error located at the component")
    func cx5OutsideTable() throws {
        let issues = try tableIssues(wire(pid3: "123^^^AUTH^ZZZZ"))
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.code == .valueNotInTable(table: "0203"))
        #expect(issue.severity == .error)
        #expect(issue.location.pathDescription == "PID[1]-3.5")
    }

    @Test("A printed code, an empty component and the HL7 null are all silent")
    func silentCases() throws {
        #expect(try tableIssues(wire(pid3: "123^^^AUTH^MR")).isEmpty)
        #expect(try tableIssues(wire(pid3: "123^^^AUTH")).isEmpty)
        #expect(try tableIssues(wire(pid3: "123^^^AUTH^\"\"")).isEmpty)
    }

    @Test("Each repetition is checked independently")
    func repetitions() throws {
        let issues = try tableIssues(wire(pid3: "1^^^A^MR~2^^^A^QQQ~3^^^A^WWW"))
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

    @Test("Versions that print no component tables are silent")
    func noGrammarNoCheck() throws {
        for version in ["2.3", "2.3.1", "2.4"] {
            #expect(try tableIssues(wire(version: version, pid3: "123^^^AUTH^ZZZZ")).isEmpty, "v\(version)")
        }
        #expect(try tableIssues(wire(version: "2.6", pid3: "123^^^AUTH^ZZZZ")).count == 1)
        #expect(try tableIssues(wire(version: "2.8.2", pid3: "123^^^AUTH^ZZZZ")).count == 1)
    }

    @Test("checkCodeTables = false and the lenient preset suppress the component check")
    func optionOff() throws {
        var options = ValidationOptions()
        options.checkCodeTables = false
        #expect(try tableIssues(wire(pid3: "123^^^AUTH^ZZZZ"), options: options).isEmpty)
        #expect(try tableIssues(wire(pid3: "123^^^AUTH^ZZZZ"), options: .lenient).isEmpty)
    }

    @Test("A locale's rendering of the table widens the component check too")
    func localeWidens() throws {
        // NOI is printed by AU ADRM-2021 Table 0203 (NOI**) and by no base version before v2.9.
        #expect(try tableIssues(wire(pid3: "123^^^AUTH^NOI")).count == 1)
        #expect(try tableIssues(wire(pid3: "123^^^AUTH^NOI"), locale: .auLocalisation).isEmpty)
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

    @Test("Both levels report independently on one field")
    func bothLevels() throws {
        let issues = try tableIssues(wire(pid3: "123^^^AUTH&1.2.3&QQQ^ZZZZ"))
        #expect(Set(issues.map(\.location.pathDescription)) == ["PID[1]-3.4.3", "PID[1]-3.5"])
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
}
