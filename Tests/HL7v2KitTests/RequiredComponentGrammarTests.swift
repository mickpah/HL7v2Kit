import Testing
@testable import HL7v2Kit

/// M14 — required components come from each version's PRINTED component table, not from
/// hand-written lists. Eight hand-written requirements contradicted the spec they cited.
@Suite("Required components from the datatype grammar")
struct RequiredComponentGrammarTests {
    private func wire(version: String = "2.5.1", msh9: String = "ADT^A01^ADT_A01",
                      pid3: String = "123^^^AUTH^MR", pid5: String = "DOE^JOHN", pid11: String = "") -> String {
        "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||\(msh9)|MSG00001|P|\(version)\r"
            + "PID|1||\(pid3)||\(pid5)||||||\(pid11)\r"
    }

    private func missing(_ wire: String) throws -> [String] {
        Validator().validate(try Parser().parse(wire)).issues
            .filter { $0.code == .requiredComponentMissing }
            .map(\.location.pathDescription)
    }

    @Test("Components the spec prints as OPTIONAL are never 'required': XAD.1, XPN.1, CE.1")
    func printedOptionalIsOptional() throws {
        // v2.5.1 prints XAD.1 Street Address as O: an address with no street line is valid.
        #expect(try missing(wire(pid11: "^^Sydney^NSW^2000")).isEmpty)
        // v2.5.1 prints XPN.1 Family Name as O: a given name alone is valid.
        #expect(try missing(wire(pid5: "^JOHN")).isEmpty)
        for version in ["2.5.1", "2.6", "2.7.1", "2.8.2"] {
            #expect(try missing(wire(version: version, pid5: "^JOHN", pid11: "^^Sydney")).isEmpty, "v\(version)")
        }
    }

    @Test("Components the spec prints as R are required: CX.1 everywhere, CX.5 from v2.8.2")
    func printedRequiredIsRequired() throws {
        #expect(try missing(wire(pid3: "^^^AUTH^MR")) == ["PID[1]-3.1"])
        #expect(try missing(wire(version: "2.5.1", pid3: "123^^^AUTH")).isEmpty, "CX.5 is O in v2.5.1")
        #expect(try missing(wire(version: "2.8.2", pid3: "123^^^AUTH")) == ["PID[1]-3.5"], "CX.5 is R in v2.8.2")
    }

    @Test("The grammar, not a fixed list, decides per version")
    func grammarDecides() throws {
        let cx251 = try #require(DataTypeGrammarTable.grammar("CX", version: .v2_5_1))
        let cx282 = try #require(DataTypeGrammarTable.grammar("CX", version: .v2_8_2))
        #expect(cx251.components.filter { $0.optionalityCode == "R" }.map(\.index) == [1])
        #expect(cx282.components.filter { $0.optionalityCode == "R" }.map(\.index) == [1, 5])
        let xad = try #require(DataTypeGrammarTable.grammar("XAD", version: .v2_5_1))
        #expect(xad.components.allSatisfy { $0.optionalityCode != "R" })
    }

    @Test("v2.3 to v2.4 print no component optionality, so nothing is required of them")
    func proseVersionsRequireNothing() throws {
        for version in ["2.3", "2.3.1", "2.4"] {
            #expect(try missing(wire(version: version, msh9: "ADT^A01", pid3: "^^^AUTH^MR", pid5: "^JOHN")).isEmpty, "v\(version)")
        }
    }

    @Test("checkComponentGrammar = false still suppresses the check")
    func optionOff() throws {
        var options = ValidationOptions()
        options.checkComponentGrammar = false
        let issues = Validator(options: options).validate(try Parser().parse(wire(pid3: "^^^AUTH^MR"))).issues
        #expect(!issues.contains { $0.code == .requiredComponentMissing })
    }
}
