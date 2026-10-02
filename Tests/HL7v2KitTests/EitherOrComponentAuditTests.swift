import Testing
@testable import HL7v2Kit

/// M15 — the hand-written either-or component rules, held to the spec's own examples.
@Suite("Either-or component rules against the spec's examples")
struct EitherOrComponentAuditTests {
    private func missing(_ segment: String, version: String = "2.5.1") throws -> [String] {
        let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01^ADT_A01|MSG00001|P|\(version)\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN\r" + segment + "\r"
        return Validator().validate(try Parser().parse(wire)).issues
            .filter { $0.code == .requiredComponentMissing }
            .map(\.location.pathDescription)
    }

    @Test("XTN: the spec's own fax example (v2.5.1 sec 2.A.89) uses the delimited form and is valid")
    func xtnDelimitedForm() throws {
        // "^ORN^FX^^^734^6777777": XTN.1, XTN.4 and XTN.12 are all empty by design. The spec
        // RECOMMENDS this form as of v2.3; XTN.1 is kept "for backward compatibility only".
        #expect(try missing("NK1|1|DOE^JANE|SPO||^ORN^FX^^^734^6777777").isEmpty)
        #expect(try missing("NK1|1|DOE^JANE|SPO||^PRN^PH^^61^2^98765432").isEmpty)
    }

    @Test("PL: 'for a patient treated at home, only the person location type is valued' (v2.5.1 sec 2.A.53)")
    func plPersonLocationTypeOnly() throws {
        // PV1-3 Assigned Patient Location is PL. PL.6 alone is the spec's own example.
        #expect(try missing("PV1|1|O|^^^^^H").isEmpty)
        #expect(try missing("PV1|1|I|^101^A").isEmpty, "room and bed with no point of care")
    }

    @Test("CWE: the spec's 'Uncoded' usage case values the text and leaves the identifier empty (sec 2.A.13)")
    func cweUncodedText() throws {
        // "^Wesnerian^SNM3^^^^3.4": CWE.1 and CWE.9 are both empty in the spec's own example.
        // AL1-3 Allergen Code is CWE in its own right on v2.6 (OBX-5 is typed through OBX-2).
        #expect(try missing("AL1|1||^Wesnerian^SNM3^^^^3.4", version: "2.6").isEmpty)
    }

    @Test("HD keeps its rule: a local namespace ID, or a universal ID WITH its type (sec 2.A.33)")
    func hdRuleStands() throws {
        let base = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01^ADT_A01|MSG00001|P|2.5.1\rPID|1||123^^^AUTH^MR||DOE^JOHN\r"
        func issues(_ msh4: String) throws -> [String] {
            let wire = base.replacingOccurrences(of: "|HIS|FAC|HOSPITAL", with: "|HIS|\(msh4)|HOSPITAL")
            return Validator().validate(try Parser().parse(wire)).issues
                .filter { $0.code == .requiredComponentMissing }.map(\.location.pathDescription)
        }
        #expect(try issues("FAC").isEmpty, "local identifier: only the namespace ID valued")
        #expect(try issues("^1.2.3^ISO").isEmpty, "a UID: universal ID and type both valued")
        #expect(try !issues("^1.2.3").isEmpty, "a universal ID with neither namespace nor type is not an HD the spec describes")
    }

    @Test("The rules that contradicted the spec's examples are gone; HD's remains")
    func ruleInventory() {
        #expect(XTN.requiredComponentSet == nil)
        #expect(PL.requiredComponentSet == nil)
        #expect(CWE.requiredComponentSet == nil)
        #expect(EIP.requiredComponentSet == nil, "vacuous: a populated two-component field always satisfied it")
        #expect(HD.requiredComponentSet != nil)
    }

    @Test("Every HD example the spec prints in its HD section validates (v2.5.1 sec 2.A.33)")
    func specHDExamples() throws {
        let base = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01^ADT_A01|MSG00001|P|2.5.1\rPID|1||123^^^AUTH^MR||DOE^JOHN\r"
        for example in ["^1.2.344.24.1.1.3^ISO", "^14344.14144321.4122344.14434.654^GUID", "^falcon.iupui.edu^DNS",
                        "^40C983F09183B0295822009258A3290582^RANDOM", "^RX.PIMS.SystemB.CA.SCA^M",
                        "PathLab^PL.UCF.UC^L", "LAB1^1.2.3.3.4.6.7^ISO"] {
            let wire = base.replacingOccurrences(of: "|HIS|FAC|HOSPITAL", with: "|HIS|\(example)|HOSPITAL")
            let errors = Validator().validate(try Parser().parse(wire)).errors.filter { $0.location.fieldIndex == 4 }
            #expect(errors.isEmpty, "\(example): \(errors.map(\.message))")
        }
    }

    @Test("HD: the universal ID and its type 'must either both be valued ... or both be not valued'")
    func hdBothOrNeither() throws {
        let base = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01^ADT_A01|MSG00001|P|VERSION\rPID|1||123^^^AUTH^MR||DOE^JOHN\r"
        func issues(_ msh4: String, _ version: String) throws -> [String] {
            let wire = base.replacingOccurrences(of: "VERSION", with: version)
                .replacingOccurrences(of: "|HIS|FAC|HOSPITAL", with: "|HIS|\(msh4)|HOSPITAL")
            return Validator().validate(try Parser().parse(wire)).issues
                .filter { $0.code == .requiredComponentMissing && $0.location.fieldIndex == 4 }.map(\.location.pathDescription)
        }
        // The sentence is printed by all six versions, v2.3 to v2.8.2.
        for version in ["2.3", "2.4", "2.5.1", "2.8.2"] {
            #expect(try issues("LAB1", version).isEmpty, "v\(version): local identifier")
            #expect(try issues("LAB1^1.2.3^ISO", version).isEmpty, "v\(version): all three")
            #expect(try issues("^1.2.3^ISO", version).isEmpty, "v\(version): a UID")
            #expect(try issues("LAB1^1.2.3", version) == ["MSH[1]-4"], "v\(version): universal ID without its type")
            #expect(try issues("LAB1^^ISO", version) == ["MSH[1]-4"], "v\(version): a type without its universal ID")
        }
    }

    /// P6-11: the OR-rule message named every alternative even when the pair rule — not the
    /// OR — was the one that actually fired, e.g. HD-1 valued with HD-2/HD-3 only partly
    /// valued. The message now names the sub-rule that failed: the pair rule when the group
    /// is partially populated, the OR alternatives only when nothing in the field satisfies
    /// either side. Issue code and location are unchanged either way.
    @Test("HD OR-rule message names the pair rule when HD-1 is valued but HD-2/HD-3 is a partial pair")
    func orRuleMessageNamesThePartialPair() throws {
        let base = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01^ADT_A01|MSG00001|P|2.5.1\rPID|1||123^^^AUTH^MR||DOE^JOHN\r"
        func orRuleIssue(_ msh4: String) throws -> ValidationIssue? {
            let wire = base.replacingOccurrences(of: "|HIS|FAC|HOSPITAL", with: "|HIS|\(msh4)|HOSPITAL")
            return Validator().validate(try Parser().parse(wire)).issues
                .first { $0.code == .requiredComponentMissing && $0.location.pathDescription == "MSH[1]-4" }
        }

        // HD-1 valued, HD-2 only: the pair rule fired, not the OR — HD-1 already satisfies
        // the non-group alternative, so naming it as missing would be misleading.
        let hd2Only = try #require(try orRuleIssue("LAB1^1.2.3"))
        #expect(hd2Only.message.contains("HD-2 and HD-3 must both be valued or both be empty"))
        #expect(!hd2Only.message.contains("Namespace ID"), "should not restate the OR alternatives once the pair rule is named")
        #expect(hd2Only.code == .requiredComponentMissing)
        #expect(hd2Only.location.pathDescription == "MSH[1]-4")

        // HD-1 valued, HD-3 only: same partial pair, same wording.
        let hd3Only = try #require(try orRuleIssue("LAB1^^ISO"))
        #expect(hd3Only.message.contains("HD-2 and HD-3 must both be valued or both be empty"))
        #expect(hd3Only.code == .requiredComponentMissing)
        #expect(hd3Only.location.pathDescription == "MSH[1]-4")
    }

    /// Direct unit coverage of the shared renderer (`RequiredComponentSet.violationMessage`),
    /// since HD is the only composite shipping a live OR-rule today (the rest were disabled
    /// by M15 for contradicting the spec's own examples). Covers: (1) HD with nothing in the
    /// field satisfying either side — the OR alternatives are named, unchanged from before
    /// this task; (2) a second, synthetic composite shape — modelled on XTN's documented but
    /// disabled `.atLeastOneOf` rule — to confirm the renderer generalises beyond HD's grouped
    /// rule rather than special-casing HD.
    @Test("RequiredComponentSet.violationMessage: OR alternatives when nothing satisfies either side")
    func violationMessageGenericCases() throws {
        let hdSet = try #require(HD.requiredComponentSet)

        // Nothing in {1, 2, 3} populated: names the OR alternatives, same text as `description`.
        #expect(hdSet.violationMessage(populatedIndices: [], compositeCode: "HD")
            == "expected \(hdSet.description) populated")

        // Second composite shape (synthetic — XTN's disabled rule had no group, only
        // alternatives): `.atLeastOneOf` never has a partial-pair reading, so it always
        // falls back to the OR-alternatives wording.
        let atLeastOneOfSet = RequiredComponentSet(
            components: [
                RequiredComponent(index: 1, name: "Telephone Number"),
                RequiredComponent(index: 4, name: "Email Address"),
                RequiredComponent(index: 12, name: "Unformatted Telephone number"),
            ],
            semantics: .atLeastOneOf,
            description: "XTN-1 (Telephone Number) OR XTN-4 (Email Address) OR XTN-12 (Unformatted Telephone number)"
        )
        #expect(atLeastOneOfSet.violationMessage(populatedIndices: [], compositeCode: "XTN")
            == "expected \(atLeastOneOfSet.description) populated")
        #expect(atLeastOneOfSet.violationMessage(populatedIndices: [4], compositeCode: "XTN")
            == "expected \(atLeastOneOfSet.description) populated", "a partially-satisfying value is still the OR wording — .atLeastOneOf has no pair rule")
    }

    @Test("NA: 'arrays that have one or more values not present may be transmitted', first value included")
    func naSparseArray() throws {
        // The spec's example (v2.5.1 sec 2.A.47 NA): |^2^3^4~5^^^8~9^10~~17^18^19^20|. The table
        // prints NA.1 as R; v2.8.2 corrects it to O.
        for version in [Version.v2_5_1, .v2_6, .v2_8_2] {
            let na = try #require(DataTypeGrammarTable.grammar("NA", version: version))
            #expect(na.component(1)?.optionalityCode == "O", "\(version)")
        }
    }

    @Test("RPT: the spec's own example uses AHS, which Table 0528 does not print")
    func rptExampleEvent() throws {
        for version in [Version.v2_5_1, .v2_6, .v2_8_2] {
            let t = try #require(HL7TableRegistry.table("0528", version: version))
            #expect(t.contains("AHS") && t.contains("HS") && t.isClosed, "\(version)")
        }
    }
}
