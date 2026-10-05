// V23TableCheckValidationTests.swift
// Validator-level pins for the three v2.3 table checks (QAK-2, PD1-12, PCR-22).

import Testing
@testable import HL7v2Kit

@Suite("v2.3 table checks at the validator")
struct V23TableCheckValidationTests {

    private func issues(segment: String, field: Int, value: String, table: String) throws -> [ValidationIssue] {
        let fields = (1..<field).map { _ in "" } + [value]
        let wire = "MSH|^~\\&|A|B|C|D|||ADT^A01|1|P|2.3\r" + segment + "|" + fields.joined(separator: "|") + "\r"
        return Validator().validate(try Parser().parse(wire)).issues.filter {
            $0.code == .valueNotInTable(table: table)
                && $0.location.segmentID == segment && $0.location.fieldIndex == field
        }
    }

    private func expectRejected(_ segment: String, _ field: Int, _ table: String) throws {
        let found = try issues(segment: segment, field: field, value: "ZZ", table: table)
        let issue = try #require(found.first)
        #expect(found.count == 1)
        #expect(issue.code == .valueNotInTable(table: table))
        #expect(issue.location.segmentID == segment && issue.location.fieldIndex == field)
    }

    @Test("QAK-2 outside Table 0208 is flagged; AE is silent")
    func qak2() throws {
        try expectRejected("QAK", 2, "0208")
        #expect(try issues(segment: "QAK", field: 2, value: "AE", table: "0208").isEmpty)
    }

    @Test("PD1-12 outside Table 0136 is flagged; Y is silent")
    func pd1_12() throws {
        try expectRejected("PD1", 12, "0136")
        #expect(try issues(segment: "PD1", field: 12, value: "Y", table: "0136").isEmpty)
    }

    @Test("PCR-22 outside Table 0252 is flagged; AW is silent")
    func pcr22() throws {
        try expectRejected("PCR", 22, "0252")
        #expect(try issues(segment: "PCR", field: 22, value: "AW", table: "0252").isEmpty)
    }
}
