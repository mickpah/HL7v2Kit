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
}
