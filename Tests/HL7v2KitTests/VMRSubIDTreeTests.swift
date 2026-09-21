import Testing
@testable import HL7v2Kit

/// AU ADRM-2021 Appendix 9 (Normative): the HL7v2 VMR OBX-4 sub-ID tree.
@Suite("AU VMR sub-ID tree")
struct VMRSubIDTreeTests {
    private static let header =
        "OBX|1|RP|74028-2^Report template ID^LN|ROOT|HL7V2-VMR.v1^HL7V2 VMR&99A-9AAC5A649D18B6F2&L^TX^Octet-stream||||||F\r"

    private func referral(root: String = "1", _ obx: [String], messageType: String = "REF^I12^REF_I12") -> String {
        "MSH|^~\\&|APP|FAC|APP|FAC|20240301120000||\(messageType)|MSG1|P|2.4|||AL|NE|AUS|ASCII\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
            + "OBR|1|||REF^Referral^L\r"
            + Self.header.replacingOccurrences(of: "ROOT", with: root)
            + obx.map { $0 + "\r" }.joined()
    }

    private func vmrIssues(_ wire: String, locale: HL7Locale = .auLocalisation) throws -> [ValidationIssue] {
        let message = try Parser(locale: locale).parse(wire)
        return Validator(locale: locale).validate(message).issues.filter {
            if case .profileConstraintViolation(let rule) = $0.code {
                return ["ADRM-prose:P-8", "ADRM-prose:P-9", "ADRM-prose:P-10"].contains { rule.hasPrefix($0) }
            }
            return false
        }
    }

    // The appendix's own worked example (p. 516): two past illnesses.
    private let specExample = [
        "OBX|6|CE|70949-3^^LN|1.2|11348-0^History of Past Illness^LN||||||F",
        "OBX|7|CE|11349-8^Past Illness^LN|1.2.1.1.1|50711007^Viral hepatitis C^SCT||||||F",
        "OBX|8|CE|408731000^Temporal Context^SCT|1.2.1.1.2|410584005^Current - specified^SCT||||||F",
        "OBX|9|DR|11368-8^Illness Dates^LN|1.2.1.1.3|20090107||||||F",
        "OBX|10|CE|11349-8^Past Illness^LN|1.2.1.2.1|6142004^Influenza^SCT||||||F",
        "OBX|11|CE|408731000^Temporal Context^SCT|1.2.1.2.2|410587003^Past - specified^SCT||||||F",
        "OBX|12|DR|11368-8^Illness Dates^LN|1.2.1.2.3|20170131^20170318||||||F",
    ]

    @Test("The appendix's own worked example is silent (req #4)")
    func specExampleIsSilent() throws {
        #expect(try vmrIssues(referral(specExample)).isEmpty)
        #expect(try vmrIssues(referral(["OBX|5|FT|8251-1^Notes^LN|1.1.3|headache||||||F"])).isEmpty, "p. 363 example")
    }

    @Test("P-8: an observation sharing the VMR root must be a VMR element")
    func unknownPathUnderRoot() throws {
        let issues = try vmrIssues(referral(["OBX|2|ST|1234-5^Something^LN|1.99.7|x||||||F"]))
        #expect(issues.count == 1)
        #expect(issues.first?.location.pathDescription == "OBX[2]-4")
        if case .profileConstraintViolation(let rule)? = issues.first?.code { #expect(rule.hasPrefix("ADRM-prose:P-8")) }
    }

    @Test("P-8: observations outside the root are not the VMR's business")
    func otherRootsAreFree() throws {
        #expect(try vmrIssues(referral(["OBX|2|ST|1234-5^Something^LN|2.99.7|x||||||F",
                                        "OBX|3|ST|1234-5^Something^LN||x||||||F",
                                        "OBX|4|ST|1234-5^Something^LN|10|x||||||F"])).isEmpty)
    }

    @Test("P-8: the root is whatever the header declares, not always 1")
    func rootFromHeader() throws {
        let moved = specExample.map { $0.replacingOccurrences(of: "|1.2", with: "|7.2") }
        #expect(try vmrIssues(referral(root: "7", moved)).isEmpty)
        #expect(try vmrIssues(referral(root: "7", ["OBX|2|ST|1^x^LN|7.99|x||||||F"])).count == 1)
        #expect(try vmrIssues(referral(root: "7", ["OBX|2|ST|1^x^LN|1.99|x||||||F"])).isEmpty, "1.x is outside root 7")
    }

    @Test("P-9: a STRUCTURAL row must not be written as an OBX")
    func structuralRowWritten() throws {
        // 1.2.1.<n> is 'Past Illness', STRUCTURAL: purely virtual in the table.
        let issues = try vmrIssues(referral(["OBX|2|CE|x^y^LN|1.2.1.1|z||||||F"]))
        #expect(issues.count == 1)
        if case .profileConstraintViolation(let rule)? = issues.first?.code { #expect(rule.hasPrefix("ADRM-prose:P-9")) }
    }

    @Test("P-10: the header's own sub-ID must be dotted decimal")
    func headerSubIDShape() throws {
        let issues = try vmrIssues(referral(root: "A1", []))
        #expect(issues.count == 1)
        #expect(issues.first?.location.pathDescription == "OBX[1]-4")
        #expect(try vmrIssues(referral(root: "3.1", [])).isEmpty)
    }

    @Test("No header, no international locale, no non-REF message: nothing fires")
    func gates() throws {
        let stray = ["OBX|2|ST|1234-5^Something^LN|1.99.7|x||||||F"]
        #expect(try vmrIssues(referral(stray), locale: .international).isEmpty)
        #expect(try vmrIssues(referral(stray, messageType: "ORU^R01^ORU_R01")).isEmpty)
        let noHeader = referral(stray).replacingOccurrences(of: "74028-2^Report template ID^LN", with: "11111-1^Other^LN")
        #expect(try vmrIssues(noHeader).isEmpty)
    }

    @Test("Each OBR group has its own VMR scope")
    func perObservationGroup() throws {
        let wire = referral(specExample) + "OBR|2|||LAB^Lab^L\r" + "OBX|1|NM|787-2^MCV^LN|1.99|90||||||F\r"
        #expect(try vmrIssues(wire).isEmpty, "the second OBR group has no VMR header, so 1.99 is its own business")
    }

    @Test("The extracted table is the appendix's: 89 rows, a root ENTRY, five STRUCTURAL rows")
    func tableShape() {
        let rows = VMRImplementationTable.au_adrm_2021
        #expect(rows.count == 89)
        #expect(rows.first?.path == "1" && rows.first?.kind == "ENTRY")
        #expect(rows.filter { $0.kind == "STRUCTURAL" }.count == 5)
        #expect(rows.allSatisfy { ($0.max == nil) == $0.path.hasSuffix("*") })
    }
}
