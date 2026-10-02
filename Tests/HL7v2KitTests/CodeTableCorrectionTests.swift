// CodeTableCorrectionTests.swift
// Shipped table data corrected by the P10-1 fix round (P2 intake): v2.8.2 0359, 0418, 0544,
// 0088, 0343, 0396, and the 0141 range rows on every version that prints them.

import Testing
@testable import HL7v2Kit

@Suite("Code-table data corrections (P10-1 fix round)")
struct CodeTableCorrectionTests {

    private func table(_ number: String, _ version: Version) throws -> HL7Table {
        try #require(HL7TableRegistry.table(number, version: version), "\(version) \(number)")
    }

    @Test("No version stores an ellipsis row as a code")
    func noEllipsisCodes() {
        let all = Version.allCases.map { HL7TableRegistry.tables(for: $0) } + [HL7TableRegistry.v2_7_1]
        for tables in all {
            for t in tables.values {
                #expect(!t.codes.contains("\u{2026}") && !t.codes.contains("..."), "Table \(t.number)")
            }
        }
    }

    @Test("v2.8.2 0359 and 0418: rows 0, 1, 2 and open (CH06 DG1-15 / PR1-14: 'Values 2-99 convey ranked secondary')")
    func priorities() throws {
        let diagnosis = try table("0359", .v2_8_2)
        #expect(diagnosis.kind == .userDefined && diagnosis.codes == ["0", "1", "2"] && diagnosis.permitsLocalExtensions)
        let procedure = try table("0418", .v2_8_2)
        #expect(procedure.kind == .hl7 && procedure.codes == ["0", "1", "2"] && !procedure.isClosed)
    }

    @Test("v2.8.2 0544 is open ('for suggested values') and carries no wrapped-description fragment")
    func containerCondition() throws {
        let t = try table("0544", .v2_8_2)
        #expect(!t.isClosed && !t.contains("temperature"))
        #expect(t.entries.first { $0.code == "XCAMB" }?.description == "Not Critical ambient temperature")
        #expect(t.entries.first { $0.code == "XAMB" }?.description == "Not Ambient temperature")
    }

    @Test("v2.8.2 wrapped prose is not a code: 0088 and 0343 'contractors.', 0396 'codes'")
    func proseFragments() throws {
        #expect(!(try table("0088", .v2_8_2)).contains("contractors."))
        #expect(!(try table("0343", .v2_8_2)).contains("contractors."))
        #expect(!(try table("0396", .v2_8_2)).codes.contains("codes"))
    }

    @Test("0141 range rows ('E1 ... E9', 'O1 ... O9', 'W1 ... W4') admit exactly the codes they name")
    func militaryRanges() throws {
        let printed: [(String, [String: HL7Table], Int)] = [
            ("2.3.1", HL7TableRegistry.v2_3_1, 10), ("2.4", HL7TableRegistry.v2_4, 10),
            ("2.5.1", HL7TableRegistry.v2_5_1, 9), ("2.6", HL7TableRegistry.v2_6, 9),
            ("2.7.1", HL7TableRegistry.v2_7_1, 9), ("2.8.2", HL7TableRegistry.v2_8_2, 9),
        ]
        for (version, tables, officers) in printed {
            let t = try #require(tables["0141"], "v\(version)")
            #expect(t.entries.isEmpty, "v\(version): no literal range code")
            #expect(t.contains("E1") && t.contains("E9") && !t.contains("E10"), "v\(version)")
            #expect(t.contains("O\(officers)") && !t.contains("O\(officers + 1)"), "v\(version)")
            #expect(t.contains("W4") && !t.contains("W5"), "v\(version)")
        }
    }
}
