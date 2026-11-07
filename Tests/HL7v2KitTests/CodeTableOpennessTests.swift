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

    @Test("Table 0355 is closed on v2.9, whose MFE-5 (CH08 sec 8.5.2.5) cites it for valid values with no extension clause")
    func table0355ClosedV29() throws {
        #expect(try issues(mfn(mfe5: "ST", version: "2.9"), table: "0355").count == 1)
        let t = try #require(HL7TableRegistry.table("0355", version: .v2_9))
        #expect(!t.permitsLocalExtensions && t.isClosed)
    }

    @Test("Table 0355 is closed on v2.9.1, whose MFE-5 (CH08 8.5.2.5 p12) cites it for valid values with no extension clause")
    func table0355ClosedV291() throws {
        #expect(try issues(mfn(mfe5: "ST", version: "2.9.1"), table: "0355").count == 1)
        let t = try #require(HL7TableRegistry.table("0355", version: .v2_9_1))
        #expect(!t.permitsLocalExtensions && t.isClosed)
    }

    // MARK: - Table 0291 (RP.4, ED.3): IANA subtypes by agreement

    /// v2.9 CH02A 2A.3.66.4 p76 and v2.9.1 2A.2.66.4 p76 say "for valid values", and then: "All subtypes registered by IANA
    /// may be used by implementation agreement between cooperating parties. In addition, private, non-standard subtypes
    /// may be defined by agreement between cooperating parties." ED.3 is "Identical to "subtype" component in the
    /// reference pointer" (2A.3.24.3, 2A.2.24.3). ED.4 is a closed table on the same wire.
    private func oru(obx5 value: String, type: String, _ version: String) -> String {
        TestWires.msh("ORU^R01^ORU_R01", version) + "OBX|1|\(type)|85^Report^L||\(value)||||||F\r"
    }

    @Test("Table 0291 is open on v2.9 and v2.9.1, and its printed rows stand", arguments: [Version.v2_9, .v2_9_1])
    func table0291Open(version: Version) throws {
        let t = try #require(HL7TableRegistry.table("0291", version: version))
        #expect(t.permitsLocalExtensions && !t.isClosed)
        #expect(t.contains("Octet-stream") && t.entries.count == 15)
    }

    @Test("An IANA or private subtype draws no 0291 finding on v2.9 and v2.9.1, in ED and in RP",
          arguments: ["2.9", "2.9.1"], ["pdf", "plain", "x-local", "DICOM"])
    func subtypeOnTheWire(version: String, subtype: String) throws {
        #expect(try issues(oru(obx5: "^application^\(subtype)^Base64^JVBERi0xLjQK", type: "ED", version), table: "0291").isEmpty)
        #expect(try issues(oru(obx5: "POINTER^^application^\(subtype)", type: "RP", version), table: "0291").isEmpty)
    }

    @Test("On the same wire a closed table still raises: ED.4 draws 0299", arguments: ["2.9", "2.9.1"])
    func subtypeWireControl(version: String) throws {
        let wire = oru(obx5: "^application^pdf^NOTANENCODING^JVBERi0xLjQK", type: "ED", version)
        #expect(try issues(wire, table: "0299").map(\.location.pathDescription) == ["OBX[1]-5.4"])
        #expect(try issues(wire, table: "0291").isEmpty)
    }

    // MARK: - Table 0291 on v2.3 to v2.5.1: closed, and the print's Z subtypes admitted

    /// RP.4 says "for valid values" (v2.3 CH02 2.8.34.4 p2-39, v2.3.1 2.8.36.4 p2-46, v2.4 2.9.37.4 p2-62, v2.5.1 CH02A 2.A.65.4
    /// p2-208) and none of these prints R44's sentence, "All subtypes registered by IANA may be used". What they print next is
    /// narrower: "private, non-standard subtypes may be defined by agreement between cooperating parties ... should begin with
    /// the letter Z" (pp 2-40, 2-47, 2-62, 2-209). So the rows stand and a pattern row admits the reserved prefix (ruling R55).
    @Test("Table 0291 stays closed on v2.3 to v2.5.1, and admits the print's Z subtypes through a pattern row",
          arguments: [("2.3", Version.v2_3, 12), ("2.3.1", .v2_3_1, 14), ("2.4", .v2_4, 15), ("2.5.1", .v2_5_1, 15)])
    func table0291ClosedEarlier(wireVersion: String, version: Version, rows: Int) throws {
        let t = try #require(HL7TableRegistry.table("0291", version: version))
        #expect(t.isClosed && !t.permitsLocalExtensions && t.entries.count == rows)
        #expect(t.patterns.map(\.code) == ["Zxxx"] && !t.codes.contains("Zxxx"))
        for (subtype, count) in [("pdf", 1), ("ZLOCAL", 0), ("JPEG", 0), ("zlocal", 1), ("LOCALZ", 1)] {
            let wire = oru(obx5: "POINTER^^application^\(subtype)", type: "RP", wireVersion)
            #expect(try issues(wire, table: "0291").count == count, "\(subtype)")
        }
    }

    @Test("v2.3.1 to v2.5.1 reject ^application^pdf at ED.3 as well", arguments: ["2.3.1", "2.4", "2.5.1"])
    func edSubtypeEarlier(wireVersion: String) throws {
        let wire = oru(obx5: "^application^pdf^Base64^JVBERi0xLjQK", type: "ED", wireVersion)
        #expect(try issues(wire, table: "0291").count == 1)
    }

    // MARK: - Table 0391 (RCP-7) on v2.6, v2.7.1 and v2.8.2: the chapters print names no row holds

    /// R36, on each version's own print: chapters decide openness, Appendix A neither. CH04 prints `--- GUARANTOR begin` in OPL_O37
    /// (v2.6 p4-22, v2.7.1 p28) and `--- DONOR begin` (v2.8.2 p156), and no row holds either name. RCP-7 reads "for values for
    /// Segment Group" (5.5.6.7: v2.6 CH05 p41, v2.7.1 p47, v2.8.2 p46), and 5.11 calls the table "an itemization of the segment
    /// group names" (v2.6 p106, v2.7.1 p108, v2.8.2 p104). The cost: a bad group name passes.
    @Test("Table 0391 is open on v2.6, v2.7.1 and v2.8.2, and its rows stand",
          arguments: [(Version.v2_6, 131, "GUARANTOR"), (.v2_7_1, 132, "GUARANTOR"), (.v2_8_2, 132, "DONOR")])
    func table0391Open(version: Version, rows: Int, printedName: String) throws {
        let t = try #require(HL7TableRegistry.table("0391", version: version))
        #expect(t.permitsLocalExtensions && !t.isClosed && t.entries.count == rows)
        #expect(!t.codes.contains(printedName))
    }

    @Test("RCP-7 with a printed group name draws no 0391; RCP-1 with X still draws 0091 on the same wire",
          arguments: [("2.6", "GUARANTOR"), ("2.7", "GUARANTOR"), ("2.7.1", "GUARANTOR"), ("2.8", "DONOR"), ("2.8.2", "DONOR")])
    func segmentGroupOnTheWire(wireVersion: String, group: String) throws {
        let wire = TestWires.msh("QBP^Q11^QBP_Q11", wireVersion) + "RCP|X||||||\(group)\r"
        #expect(try issues(wire, table: "0391").isEmpty)
        #expect(try issues(wire, table: "0091").count == 1)
    }

    // MARK: - Table 0104 (VID.1): closed on v2.9 and v2.9.1

    /// A ruling. v2.9 CH02 2.14.9.12 p70 and CH02A 2A.3.83.1 p86, v2.9.1 CH02 2.13.9.12 p71 and CH02A 2A.2.83.1 p87:
    /// "Refer to HL7 Table 0104 - Version ID ... for valid values", which ADR-016 reads as closed. v2.3 to v2.8.2 stay open on
    /// the reading recorded for them. MSH-12 also selects the grammar: a first repetition naming no version reads as v2.5.1
    /// (ADR-018), so on the wire these tables see such a value only at a later repetition, or through `versionOverride`.
    private func versionIssues(_ msh12: String, under version: Version? = nil, locale: HL7Locale = .international) throws -> [ValidationIssue] {
        let wire = "MSH|^~\\&|SND|FAC|RCV|FAC|20260930120000||ADT^A01^ADT_A01|MSG1|P|\(msh12)\r"
        let message = try Parser(options: ParserOptions(versionOverride: version), locale: locale).parse(wire)
        return Validator(options: .default, locale: locale).validate(message).issues.filter { $0.code == .valueNotInTable(table: "0104") }
    }

    @Test("Table 0104 is closed on v2.9 and v2.9.1, and holds its own version and the earlier ones as printed",
          arguments: [(Version.v2_9, "2.9", 16), (.v2_9_1, "2.9.1", 17)])
    func table0104Closed(version: Version, own: String, rows: Int) throws {
        let t = try #require(HL7TableRegistry.table("0104", version: version))
        #expect(t.isClosed && !t.permitsLocalExtensions)
        #expect(t.entries.count == rows)
        for code in [own, "2.0", "2.0D", "2.3.1", "2.5.1", "2.7.1", "2.8.1", "2.8.2"] { #expect(t.contains(code), "\(code)") }
    }

    @Test("A value outside Table 0104 draws valueNotInTable on v2.9 and v2.9.1, at MSH-12.1", arguments: [Version.v2_9, .v2_9_1])
    func versionOutsideTheTable(version: Version) throws {
        let found = try versionIssues("9.9", under: version)
        #expect(found.map(\.location.pathDescription) == ["MSH[1]-12.1"])
        #expect(try versionIssues("9.9^AUS", under: version).count == 1)
    }

    @Test("A version's own value draws no 0104 finding, read from the wire", arguments: ["2.9", "2.9.1", "2.9^AUS", "2.9.1^AUS"])
    func versionOwnValue(msh12: String) throws {
        #expect(try versionIssues(msh12).isEmpty)
    }

    @Test("An earlier row of the table is a valid value under v2.9 and v2.9.1", arguments: [Version.v2_9, .v2_9_1], ["2.0D", "2.5.1", "2.8.2"])
    func versionEarlierRow(version: Version, value: String) throws {
        #expect(try versionIssues(value, under: version).isEmpty)
    }

    @Test("v2.9 prints no 2.9.1 row, and v2.9.1 prints a 2.9 row")
    func versionRowsDiffer() throws {
        #expect(try versionIssues("2.9.1", under: .v2_9).count == 1)
        #expect(try versionIssues("2.9", under: .v2_9_1).isEmpty)
    }

    @Test("Open control: v2.3 to v2.8.2 keep Table 0104 open, so the same value draws nothing",
          arguments: [Version.v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_7_1, .v2_8_2])
    func versionEarlierVersionsStayOpen(version: Version) throws {
        #expect(try versionIssues("9.9", under: version).isEmpty)
        let t = try #require(HL7TableRegistry.table("0104", version: version))
        #expect(t.permitsLocalExtensions && !t.isClosed)
    }

    @Test("On the wire alone a value naming no version reads as v2.5.1: not a 0104 finding, but versionNotRecognised")
    func versionUnknownOnTheWire() throws {
        #expect(try versionIssues("9.9").isEmpty)
        let message = try Parser().parse("MSH|^~\\&|SND|FAC|RCV|FAC|20260930120000||ADT^A01^ADT_A01|MSG1|P|9.9\r")
        #expect(message.version == .v2_5_1)
        #expect(Validator().validate(message).issues.contains { $0.code == .versionNotRecognised(wireValue: "9.9") })
    }

    @Test("A later repetition reaches the table from the wire, since only the first selects the version",
          arguments: [("2.9~9.9", 1), ("2.9.1~9.9", 1), ("2.8.2~9.9", 0)])
    func versionLaterRepetition(msh12: String, findings: Int) throws {
        #expect(try versionIssues(msh12).count == findings)
    }

    /// The ADRM's MSH-12 form, with its printed internal version ID (HL7au:000040.3).
    @Test("Under the AU locale a v2.9 or v2.9.1 MSH-12 stays clean on 0104, with the printed internal version ID",
          arguments: ["2.9", "2.9.1"], ["", "^AUS&Australia&ISO3166_1", "^AUS&Australia&ISO3166_1^HL7AU-OO-201701&&L"])
    func versionUnderAU(version: String, suffix: String) throws {
        #expect(try versionIssues(version + suffix, locale: .auLocalisation).isEmpty)
    }

    @Test("Under the AU locale a value outside the table still draws 0104 on v2.9 and v2.9.1", arguments: [Version.v2_9, .v2_9_1])
    func versionOutsideUnderAU(version: Version) throws {
        #expect(try versionIssues("9.9^AUS&Australia&ISO3166_1", under: version, locale: .auLocalisation).count == 1)
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
        // v2.9 CH08 sec 8.8.12.16 OM4-16 (p56) and v2.9.1 (p58) print the same sentence.
        Change(table: "0920", versions: [.v2_8_2, .v2_9, .v2_9_1], becomesUser: false,
               wire: "MSH|^~\\&|HIS|FAC|LAB|FAC|||MFN^M08^MFN_M08|MSG00001|P|2.8.2\r"
                + "MFI|OMA^Numeric^HL70175||UPD|||NE\r"
                + "MFE|MAD|CTL1||1234^Glucose^L|CWE\r"
                + "OM1|1|1234^Glucose^L\r"
                + "OM4|1" + String(repeating: "|", count: 15) + "Z\r"),
        // v2.8.2 CH02A sec 2.A.87.18 XAD.18: "Refer to User-defined Table 0617 - Address Usage";
        // v2.7.1 CH02A sec 2.A.86.18 (p92) prints the same sentence.
        // v2.9 CH02A sec 2A.3.87.18 (p91) and v2.9.1 sec 2A.2.87.18 (p92) print "Refer to User-defined Table 0617 - Address Usage".
        Change(table: "0617", versions: [.v2_7_1, .v2_8_2, .v2_9, .v2_9_1], becomesUser: true,
               wire: "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01^ADT_A01|MSG00001|P|2.8.2\r"
                + "PID|1||123^^^AUTH^MR||DOE^JOHN||||||1 MAIN ST" + String(repeating: "^", count: 17) + "Z\r"),
        // P2-14: NTE-2, the table's only governing field on every version, reads "This table
        // may be extended locally during implementation" unchanged from v2.3 to v2.8.2
        // (v2.7.1 CH02 sec 2.14.10.2 p65).
        // v2.9 CH02 sec 2.14.10.2 NTE-2 (p77) and v2.9.1 sec 2.13.10.2 (p78): "This table MAY be extended locally during implementation."
        Change(table: "0105", versions: [.v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_7_1, .v2_8_2, .v2_9, .v2_9_1], becomesUser: false,
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
        // v2.9 CH08 sec 8.5.1.1 MFI-1 (p9) and v2.9.1 (p10) print the same sentence.
        Change(table: "0175", versions: [.v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_7_1, .v2_8_2, .v2_9, .v2_9_1], becomesUser: false,
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
