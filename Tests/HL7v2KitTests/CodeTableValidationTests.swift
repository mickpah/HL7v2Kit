// CodeTableValidationTests.swift
// Base-spec closed-set enforcement for ID-typed fields (M6-O6).

import Testing
@testable import HL7v2Kit

@Suite("Code-table validation")
struct CodeTableValidationTests {

    private func oru(obr24: String, version: String = "2.5.1") -> String {
        "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00001|P|\(version)\r"
        + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
        + "OBR|1|A|B|C^D||||||||||||||||||||\(obr24)\r"
    }

    private func tableIssues(_ wire: String, options: ValidationOptions = ValidationOptions()) throws -> [ValidationIssue] {
        let report = Validator(options: options).validate(try Parser().parse(wire))
        return report.issues.filter { if case .valueNotInTable = $0.code { return true } else { return false } }
    }

    @Test("OBR-24 outside HL7 Table 0074 is an error at OBR-24 on v2.5.1")
    func obr24Rejected() throws {
        let issues = try tableIssues(oru(obr24: "XX"))
        let issue = try #require(issues.first)
        #expect(issue.code == .valueNotInTable(table: "0074"))
        #expect(issue.severity == .error)
        #expect(issue.location.segmentID == "OBR")
        #expect(issue.location.fieldIndex == 24)
        #expect(issue.message.contains("0074") && issue.message.contains("XX"))
    }

    @Test("OBR-24 inside Table 0074 is silent")
    func obr24Accepted() throws {
        #expect(try tableIssues(oru(obr24: "CH")).isEmpty)
    }

    @Test("Empty and HL7-null values are never checked")
    func nullSkipped() throws {
        #expect(try tableIssues(oru(obr24: "")).isEmpty)
        #expect(try tableIssues(oru(obr24: "\"\"")).isEmpty)
    }

    @Test("Each repetition is checked independently")
    func repetitions() throws {
        let issues = try tableIssues(oru(obr24: "CH~XX"))
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("repetition 2") == true)
    }

    @Test("checkCodeTables = false suppresses the check")
    func optionOff() throws {
        var options = ValidationOptions()
        options.checkCodeTables = false
        #expect(try tableIssues(oru(obr24: "XX"), options: options).isEmpty)
    }

    @Test("The lenient preset is structural only: it never runs the code-table check")
    func lenientSkipsCodeTables() throws {
        #expect(try !tableIssues(oru(obr24: "XX")).isEmpty, "the default options do flag it")
        #expect(try tableIssues(oru(obr24: "XX"), options: .lenient).isEmpty)
        #expect(!ValidationOptions.lenient.checkCodeTables)
    }

    @Test("A version with no table for the field is silent")
    func versionWithoutTable() throws {
        // v2.8 is grammar-less (ADR-013); nothing to look up.
        #expect(try tableIssues(oru(obr24: "XX", version: "2.8")).isEmpty)
    }

    @Test("IS-typed fields are never enforced even when their table is linked")
    func userDefinedNeverEnforced() throws {
        // PID-8 Administrative Sex is IS / user-defined table 0001 on v2.5.1.
        let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.5.1\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN||19700101|ZZZ\r"
        #expect(try tableIssues(wire).isEmpty)
        #expect(SegmentGrammarTable.v2_5_1["PID"]?.field(8)?.table == "0001", "the link exists; only enforcement is gated")
    }

    @Test("A locale's rendering of a table widens the check: UNICODE UTF-8 in MSH-18 on v2.4")
    func localeRenderingWidensTheCheck() throws {
        // Base v2.4 Table 0211 has no UNICODE UTF-8; AU ADRM-2021 back-ports it (p. 55 footnote).
        let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.4|||AL|NE|AU|UNICODE UTF-8\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
        let message = try Parser().parse(wire)
        func tableIssues(_ locale: HL7Locale) -> [ValidationIssue] {
            Validator(locale: locale).validate(message).issues
                .filter { if case .valueNotInTable = $0.code { return true } else { return false } }
        }
        let base = tableIssues(.international)
        #expect(base.count == 1)
        #expect(base.first?.code == .valueNotInTable(table: "0211"))
        #expect(tableIssues(.auLocalisation).isEmpty)
        // The widening is a union by construction: the locale rendering is only consulted
        // after the message's own version table has rejected the value, so it can never
        // reject what that version prints. (Not expressible as a wire here: the Parser
        // accepts only ASCII, 8859/1 and UNICODE UTF-8 as declared character sets.)
    }

    @Test("v2.4 OBX-2 of CWE, DR, CNE or EI is valid on the base spec (sec 7.4.2.2 prose) and under the AU locale")
    func auValueTypes() throws {
        func oru(_ obx2: String) -> String {
            "MSH|^~\\&|LAB|FAC|HIS|FAC|||ORU^R01|MSG1|P|2.4\r"
                + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
                + "OBR|1|||GLU^Glucose^L\r"
                + "OBX|1|\(obx2)|GLU^Glucose^L||x||||||F\r"
        }
        func issues(_ wire: String, _ locale: HL7Locale) throws -> [ValidationIssue] {
            Validator(locale: locale).validate(try Parser(locale: locale).parse(wire)).issues
                .filter { if case .valueNotInTable(let t) = $0.code { return t == "0125" } else { return false } }
        }
        for type in ["CWE", "DR", "CNE", "EI"] {
            #expect(try issues(oru(type), .auLocalisation).isEmpty, "OBX-2 = \(type) under the AU locale")
            #expect(try issues(oru(type), .international).isEmpty, "base v2.4 sec 7.4.2.2 admits \(type)")
        }
        #expect(try issues(oru("QQ"), .auLocalisation).count == 1, "the widening is a union, not a free pass")
        #expect(try issues(oru("QQ"), .international).count == 1)
    }

    @Test("OBX-2 admits every data type but CM, CQ, SI and ID on v2.3, v2.3.1, v2.4 and v2.6 too")
    func obx2AllDataTypesOtherVersions() throws {
        let admitted: [(version: String, types: [String])] = [
            ("2.3", ["IS", "HD", "EI", "PL", "DR", "TQ"]),
            ("2.3.1", ["CWE", "CNE", "IS", "HD", "EI", "DR", "VID"]),
            ("2.4", ["CWE", "CNE", "IS", "HD", "EI", "DR", "SRT"]),
            ("2.6", ["CNE", "CE", "TS", "IS", "HD", "EI", "DR", "MSG"]),
        ]
        for (version, types) in admitted {
            for type in types {
                #expect(try obx2Issues(type, version: version).isEmpty, "v\(version) OBX-2 = \(type)")
            }
            // v2.3 Appendix A prints ID in Table 0125 (a spec-internal conflict with the prose);
            // it is left as printed, so ID is only asserted rejected from v2.3.1 on.
            for type in ["CM", "CQ", "SI", "QQ"] + (version == "2.3" ? [] : ["ID"]) {
                #expect(try obx2Issues(type, version: version).count == 1, "v\(version) OBX-2 = \(type)")
            }
        }
    }

    @Test("Waveform value types the spec's Chapter 7 directs into OBX-2 are valid: NA, MA, CD")
    func waveformValueTypes() throws {
        // v2.5.1 sec 7.x: "The data type of the WAV category result segment can be NA (Numeric
        // Array) or MA (Multiplexed Array)"; "for the CHN category, OBX-2 should be valued to CD".
        // Table 0125 omitted all three until v2.8.2 printed them.
        for version in ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.8.2"] {
            for type in ["NA", "MA", "CD"] {
                let wire = "MSH|^~\\&|LAB|FAC|HIS|FAC|||ORU^R01^ORU_R01|MSG1|P|\(version)\r"
                    + "PID|1||123^^^AUTH^MR||DOE^JOHN\rOBR|1|||93000^EKG^C4\r"
                    + "OBX|1|\(type)|5&WAV^^99SVL|1|0^1^2||||||F\r"
                let issues = Validator().validate(try Parser().parse(wire)).issues
                    .filter { if case .valueNotInTable(let t) = $0.code { return t == "0125" } else { return false } }
                #expect(issues.isEmpty, "OBX-2 = \(type) on v\(version)")
            }
        }
    }

    private func obx2Issues(_ obx2: String, version: String) throws -> [ValidationIssue] {
        let wire = "MSH|^~\\&|LAB|FAC|HIS|FAC|||ORU^R01^ORU_R01|MSG1|P|\(version)\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
            + "OBR|1|||GLU^Glucose^L\r"
            + "OBX|1|\(obx2)|GLU^Glucose^L||x||||||F\r"
        return try tableIssues(wire).filter { $0.code == .valueNotInTable(table: "0125") }
    }

    @Test("v2.5.1 OBX-2: every HL7 data type except CM, CQ, SI and ID is valid (sec 7.4.2.2)")
    func obx2AllDataTypesV251() throws {
        for type in ["CWE", "CNE", "DTM", "IS", "DR", "EI", "HD", "PL", "TQ", "XAD", "CE"] {
            #expect(try obx2Issues(type, version: "2.5.1").isEmpty, "OBX-2 = \(type)")
        }
        for type in ["CM", "CQ", "SI", "ID", "QQ"] {
            #expect(try obx2Issues(type, version: "2.5.1").count == 1, "OBX-2 = \(type)")
        }
    }

    @Test("v2.5.1 sec 2.A.13 CWE example: OBX-2 = CWE raises no Table 0125 error")
    func cweExampleV251() throws {
        let wire = "MSH|^~\\&|LAB|FAC|HIS|FAC|||ORU^R01^ORU_R01|MSG1|P|2.5.1\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
            + "OBR|1|||883-9^ABO Group^LN\r"
            + "OBX|1|CWE|883-9^ABO Group^LN|1|F-D1250^Type O^SNM3||||||F\r"
        #expect(try tableIssues(wire).filter { $0.code == .valueNotInTable(table: "0125") }.isEmpty)
    }

    @Test("v2.3.1 MSH-20 = 2.3 is in Table 0356: Chapter 2 prints the row Appendix A omits")
    func msh20HL723Scheme() throws {
        func wire(_ msh20: String) -> String {
            "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|2.3.1||||||||\(msh20)\r"
                + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
        }
        #expect(try tableIssues(wire("2.3")).isEmpty)
        #expect(try tableIssues(wire("ISO 2022-1994")).isEmpty)
        #expect(try tableIssues(wire("2.4")).map(\.code) == [.valueNotInTable(table: "0356")])
        let t = try #require(HL7TableRegistry.table("0356", version: .v2_3_1))
        #expect(t.codes.contains("2.3") && t.isClosed)
    }

    @Test("v2.4 ORC-1 is checked against HL7 Table 0119 as CH04 sec 4.20.1 prints it")
    func orc1V24() throws {
        func wire(_ orc1: String) -> String {
            "MSH|^~\\&|HIS|FAC|LAB|FAC|||ORM^O01|MSG00001|P|2.4\r"
                + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
                + "ORC|\(orc1)|1\r"
        }
        #expect(try tableIssues(wire("NW")).isEmpty)
        #expect(try tableIssues(wire("PR")).isEmpty, "PR is printed from v2.4 on")
        #expect(try tableIssues(wire("ZZ")).map(\.code) == [.valueNotInTable(table: "0119")])
        let t = try #require(HL7TableRegistry.table("0119", version: .v2_4))
        #expect(t.kind == .hl7 && t.isClosed && t.entries.count == 48)
        #expect(!t.contains("OP") && !t.contains("PY"), "OP and PY are v2.5 additions")
    }

    @Test("v2.5.1 TQ1-12 is checked against HL7 Table 0472, as sec 4.5.4.12 prints it")
    func tq1ConjunctionV251() throws {
        func wire(_ conjunction: String) -> String {
            "MSH|^~\\&|HIS|FAC|LAB|FAC|||OML^O21^OML_O21|MSG00001|P|2.5.1\r"
                + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
                + "ORC|NW|1\r"
                + "TQ1|1" + String(repeating: "|", count: 11) + conjunction + "\r"
        }
        #expect(try tableIssues(wire("S")).isEmpty)
        #expect(try tableIssues(wire("A")).isEmpty)
        #expect(try tableIssues(wire("X")).map(\.code) == [.valueNotInTable(table: "0472")])
    }

    @Test("RCP-7 links Table 0391, which the spec leaves open: a conformance-defined group is never an error")
    func rcp7SegmentGroups() throws {
        for (wireVersion, version) in [("2.4", Version.v2_4), ("2.5.1", .v2_5_1)] {
            let wire = "MSH|^~\\&|HIS|FAC|LAB|FAC|||QBP^Q11^QBP_Q11|MSG00001|P|\(wireVersion)\r"
                + "QPD|Q1^Query^HL70471|T1\r"
                + "RCP|I||||||PIDG~ZZZG\r"
            #expect(try tableIssues(wire).isEmpty, "v\(wireVersion)")
            let t = try #require(HL7TableRegistry.table("0391", version: version))
            #expect(t.permitsLocalExtensions && !t.isClosed, "v\(wireVersion)")
            #expect(t.contains("PIDG") && !t.codes.contains("etc"), "v\(wireVersion)")
        }
    }

    // MARK: - P2-13: caller-declared local table extensions (owner gate G5)

    private func pid5NameType(_ nameTypeCode: String, version: String = "2.5.1") -> String {
        "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG00001|P|\(version)\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN^^^^^\(nameTypeCode)\r"
    }

    @Test("A declared local extension silences the field-level check: v2.5.1 OBR-24 = ZZ under Table 0074")
    func localExtensionSilencesFieldLevelCheck() throws {
        #expect(try tableIssues(oru(obr24: "ZZ")).map(\.code) == [.valueNotInTable(table: "0074")])
        var options = ValidationOptions()
        options.localTableExtensions = ["0074": ["ZZ"]]
        #expect(try tableIssues(oru(obr24: "ZZ"), options: options).isEmpty)
        #expect(try tableIssues(oru(obr24: "QQ"), options: options).map(\.code) == [.valueNotInTable(table: "0074")],
                "a code outside the declared extension is still an error")
    }

    @Test("A declared local extension silences the component-level check: v2.5.1 PID-5.7 (XPN.7, Table 0200)")
    func localExtensionSilencesComponentLevelCheck() throws {
        #expect(try tableIssues(pid5NameType("Z")).map(\.code) == [.valueNotInTable(table: "0200")])
        var options = ValidationOptions()
        options.localTableExtensions = ["0200": ["Z"]]
        #expect(try tableIssues(pid5NameType("Z"), options: options).isEmpty)
    }

    @Test("A declared local extension does not widen any other table")
    func localExtensionDoesNotAffectOtherTables() throws {
        var options = ValidationOptions()
        options.localTableExtensions = ["0074": ["ZZ"]]
        #expect(try tableIssues(pid5NameType("Z"), options: options).map(\.code) == [.valueNotInTable(table: "0200")])
    }
}
