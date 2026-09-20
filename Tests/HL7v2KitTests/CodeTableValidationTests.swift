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
}
