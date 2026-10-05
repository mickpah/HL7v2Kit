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
          arguments: [("2.4", Version.v2_4), ("2.5.1", .v2_5_1), ("2.6", .v2_6), ("2.7.1", .v2_7_1), ("2.8.2", .v2_8_2)])
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

    // MARK: - One criterion for open HL7 tables (ADR-016)

    /// A table the governing field prose opens ("for suggested values") or re-kinds
    /// ("User-defined Table"), the versions where it does, and a wire that puts an
    /// out-of-table value in that field on the first of them.
    struct Change: Sendable, CustomTestStringConvertible {
        let table: String
        let versions: Set<Version>
        let becomesUser: Bool
        let wire: String
        var testDescription: String { "Table \(table)" }
    }

    static let changes: [Change] = [
        // v2.8.2 CH08 sec 8.8.12.16 OM4-16: "Refer to HL7 Table 0920 ... for suggested values."
        Change(table: "0920", versions: [.v2_8_2], becomesUser: false,
               wire: "MSH|^~\\&|HIS|FAC|LAB|FAC|||MFN^M08^MFN_M08|MSG00001|P|2.8.2\r"
                + "MFI|OMA^Numeric^HL70175||UPD|||NE\r"
                + "MFE|MAD|CTL1||1234^Glucose^L|CWE\r"
                + "OM1|1|1234^Glucose^L\r"
                + "OM4|1" + String(repeating: "|", count: 15) + "Z\r"),
        // v2.8.2 CH02A sec 2.A.87.18 XAD.18: "Refer to User-defined Table 0617 - Address Usage";
        // v2.7.1 CH02A sec 2.A.86.18 (p92) prints the same sentence.
        Change(table: "0617", versions: [.v2_7_1, .v2_8_2], becomesUser: true,
               wire: "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01^ADT_A01|MSG00001|P|2.8.2\r"
                + "PID|1||123^^^AUTH^MR||DOE^JOHN||||||1 MAIN ST" + String(repeating: "^", count: 17) + "Z\r"),
        // P2-14: NTE-2, the table's only governing field on every version, reads "This table
        // may be extended locally during implementation" unchanged from v2.3 to v2.8.2
        // (v2.7.1 CH02 sec 2.14.10.2 p65).
        Change(table: "0105", versions: [.v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_7_1, .v2_8_2], becomesUser: false,
               wire: "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01^ADT_A01|MSG00001|P|2.4\r"
                + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
                + "NTE|1|Z\r"),
        // P2-14: QRD-9 ("...may be extended locally during implementation") and URD-4 ("...may
        // be extended by local agreement during implementation") both say so on every version
        // that carries them (v2.3 to v2.6; QRD/URD are dropped from v2.8.2). QRD-9 and URD-4 are
        // CE, whose identifier component is ST, not ID (ADR-016: "tables ... recorded ... but not
        // enforced"), so the field-level and component-level checks never reach this table either
        // way; the wire assertion documents the (unchanged) absence of a false error.
        Change(table: "0048", versions: [.v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6], becomesUser: false,
               wire: "MSH|^~\\&|HIS|FAC|LAB|FAC|||QRY^A19^QRY_A19|MSG00001|P|2.4\r"
                + "QRD|20260101000000|R|I|Q001|||10|DOE^JOHN|Z\r"),
        // P2-14: MFI-1, the table's only governing field on every version, reads "This table may
        // be extended by local agreement during implementation to cover site-specific master
        // files (z-master files)" unchanged from v2.3 to v2.8.2 (v2.7.1 CH08 sec 8.5.1.1 p7).
        // MFI-1 is CE (see the 0048 note above for why the check never fires either way).
        Change(table: "0175", versions: [.v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_7_1, .v2_8_2], becomesUser: false,
               wire: "MSH|^~\\&|HIS|FAC|LAB|FAC|||MFN^M01|MSG00001|P|2.4\r"
                + "MFI|ZZZ^Bogus^HL70175||UPD|||NE\r"),
        // P2-14: OM4-7 and SAC-27, the only two fields citing the table on v2.4 (SPM does not
        // exist until v2.5.1), both read "...The value set can be extended with user specific
        // values." On v2.5.1, v2.6 and v2.8.2 a third field, SPM-6, also cites the table but only
        // "for valid values" with no extension clause: mixed, stays closed there (register row).
        // OM4-7/SAC-27 are CE/CWE (see the 0048 note above for why the check never fires either way).
        Change(table: "0371", versions: [.v2_4], becomesUser: false,
               wire: "MSH|^~\\&|HIS|FAC|LAB|FAC|||MFN^M08^MFN_M08|MSG00001|P|2.4\r"
                + "MFI|OMA^Numeric^HL70175||UPD|||NE\r"
                + "OM4|1" + String(repeating: "|", count: 6) + "Z\r"),
    ]

    @Test("A table the governing field prose opens or calls User-defined is open or User on exactly those versions",
          arguments: changes)
    func criterionChanges(change: Change) throws {
        #expect(try issues(change.wire, table: change.table).isEmpty)
        for version in Version.allCases {
            guard let t = HL7TableRegistry.table(change.table, version: version) else { continue }
            let changed = change.versions.contains(version)
            if change.becomesUser {
                #expect((t.kind == .userDefined) == changed, "v\(version.rawValue)")
            } else {
                #expect(t.permitsLocalExtensions == changed, "v\(version.rawValue)")
            }
            if changed { #expect(!t.isClosed, "v\(version.rawValue)") }
        }
    }

    @Test("A candidate the prose leaves mixed stays closed: v2.4 PID-24 = X under Table 0136 (PID-31 cites it for suggested values, PID-24 for valid values)")
    func mixedCandidateStaysClosed() throws {
        let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01^ADT_A01|MSG00001|P|2.4\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN" + String(repeating: "|", count: 19) + "X\r"
        #expect(try issues(wire, table: "0136").count == 1)
        #expect(try #require(HL7TableRegistry.table("0136", version: .v2_4)).isClosed)
    }

    @Test("Table 0371 stays closed on v2.5.1, v2.6, v2.7.1 and v2.8.2: SPM-6 cites it only 'for valid values' while OM4-7/SAC-27 say it may be extended",
          arguments: [("2.5.1", Version.v2_5_1), ("2.6", .v2_6), ("2.7.1", .v2_7_1), ("2.8.2", .v2_8_2)])
    func mixedTable0371StaysClosed(wireVersion: String, version: Version) throws {
        let wire = "MSH|^~\\&|HIS|FAC|LAB|FAC|||MFN^M08^MFN_M08|MSG00001|P|\(wireVersion)\r"
            + "MFI|OMA^Numeric^HL70175||UPD|||NE\r"
            + "OM4|1" + String(repeating: "|", count: 6) + "Z\r"
        #expect(try issues(wire, table: "0371").isEmpty, "v\(wireVersion)")
        #expect(try #require(HL7TableRegistry.table("0371", version: version)).isClosed, "v\(wireVersion)")
    }
}
