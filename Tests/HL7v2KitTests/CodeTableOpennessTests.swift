// CodeTableOpennessTests.swift
// Which HL7 tables the governing field prose leaves open (P2 fix wave, ADR-016).

import Testing
@testable import HL7v2Kit

@Suite("Code-table openness")
struct CodeTableOpennessTests {

    private func issues(_ wire: String, table: String) throws -> [ValidationIssue] {
        let report = Validator().validate(try Parser().parse(wire))
        return report.issues.filter { $0.code == .valueNotInTable(table: table) }
    }

    // MARK: - Table 0355 (MFE-5): locally extensible from v2.4

    private func mfn(mfe5: String, version: String) -> String {
        "MSH|^~\\&|HIS|FAC|LAB|FAC|||MFN^M01|MSG00001|P|\(version)\r"
            + "MFI|LOC^Location^HL70175||UPD|||NE\r"
            + "MFE|MAD|CTL1||ABC|\(mfe5)\r"
    }

    @Test("Table 0355 is open where the chapter says it 'can be locally extended with other HL7 data types'",
          arguments: [("2.4", Version.v2_4), ("2.5.1", .v2_5_1), ("2.6", .v2_6), ("2.8.2", .v2_8_2)])
    func table0355Open(wireVersion: String, version: Version) throws {
        #expect(try issues(mfn(mfe5: "ST", version: wireVersion), table: "0355").isEmpty)
        let t = try #require(HL7TableRegistry.table("0355", version: version))
        #expect(t.permitsLocalExtensions && !t.isClosed)
    }

    @Test("Table 0355 stays closed on v2.3.1, which cites it 'for valid values' with no extension clause")
    func table0355ClosedV231() throws {
        #expect(try issues(mfn(mfe5: "ST", version: "2.3.1"), table: "0355").count == 1)
        #expect(try issues(mfn(mfe5: "CE", version: "2.3.1"), table: "0355").isEmpty)
    }
}
