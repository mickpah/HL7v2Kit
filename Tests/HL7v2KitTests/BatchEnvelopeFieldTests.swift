// BatchEnvelopeFieldTests.swift
// Batch envelopes task 2: BatchValidator checks each envelope segment's fields against the
// attribute table of the version its messages declare (v2.5.1 when there are none), with
// the options that govern message fields.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Batch envelope field checks")
struct BatchEnvelopeFieldTests {
    static func msh(_ id: String, version: String = "2.5.1") -> String {
        "MSH|^~\\&|SYNTH_HIS|SYNTH_FAC|SYNTH_HOSP|SYNTH_FAC|20240101120000||ADT^A01^ADT_A01|\(id)|P|\(version)\rPID|1"
    }

    static func batchIssues(_ lines: [String], options: ValidationOptions = .default) throws -> [ValidationIssue] {
        let file = try BatchParser().parse(lines.joined(separator: "\r") + "\r")
        return BatchValidator(options: options).validate(file).batchIssues
    }

    @Test("The envelope tables have no predicate that reads another segment")
    func envelopeTablesAreSelfContained() {
        for version in [Version.v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_7_1, .v2_8_2] {
            for id in ["FHS", "BHS", "BTS", "FTS"] {
                let fields = Validator.grammarTable(for: version)[id]?.fields ?? []
                #expect(!fields.isEmpty, "\(id) \(version)")
                #expect(fields.allSatisfy { $0.condition == nil && $0.prohibitedWhen == nil && $0.additionalProhibitions.isEmpty },
                        "\(id) \(version)")
            }
        }
    }

    @Test("An over-long BHS-9 is a length finding at BHS 1 field 9")
    func overLongBatchName() throws {
        let issues = try Self.batchIssues(["BHS|^~\\&|APP||||||SYN-BATCH-NAME-LONGER-THAN-20", Self.msh("F1"), "BTS|1"])
        let length = issues.filter { $0.code.number == IssueCode.fieldLengthOutOfRange(length: "", actual: 0).number }
        #expect(length.map(\.location.pathDescription) == ["BHS[1]-9"])
        #expect(length.first?.severity == .warning)
    }

    @Test("A malformed FHS-7 date is a value-format finding")
    func badFileDate() throws {
        let issues = try Self.batchIssues(["FHS|^~\\&|APP||||2024XX01", Self.msh("F2"), "FTS|1"])
        #expect(issues.contains { $0.code.number == 3004 && $0.location.segmentID == "FHS" && $0.location.fieldIndex == 7 })
    }

    @Test("The version's own table is used: FHS-3 is ST(15) on v2.3, HD on v2.5.1")
    func versionChoosesTheTable() throws {
        let header = "FHS|^~\\&|SYNTH_HIS_APP_NAME"   // 18 characters: over ST(15), within HD-1 IS(20)
        let v23 = try Self.batchIssues([header, Self.msh("V1", version: "2.3"), "FTS|1"])
        let v251 = try Self.batchIssues([header, Self.msh("V2"), "FTS|1"])
        #expect(v23.contains { $0.location.segmentID == "FHS" && $0.location.fieldIndex == 3 })
        #expect(!v251.contains { $0.location.segmentID == "FHS" && $0.location.fieldIndex == 3 })
    }

    @Test("A batch with no messages is checked against v2.5.1")
    func emptyBatchUsesTheFallback() throws {
        let issues = try Self.batchIssues(["BHS|^~\\&|APP||||||SYN-BATCH-NAME-LONGER-THAN-20", "BTS|0"])
        #expect(issues.contains { $0.location.segmentID == "BHS" && $0.location.fieldIndex == 9 })
        #expect(BatchValidator.envelopeVersion([]) == .v2_5_1)
    }

    @Test("FHS and BHS fields 1 and 2 are never flagged on any batch fixture")
    func separatorsNeverFlagged() throws {
        for url in try FixtureCorpus.batchFixtureURLs() {
            let file = try BatchParser().parse(Data(contentsOf: url))
            for (options, locale) in [(ValidationOptions.default, HL7Locale.international), (.strict, .auLocalisation)] {
                let issues = BatchValidator(options: options, locale: locale).validate(file).batchIssues
                #expect(!issues.contains { ["FHS", "BHS"].contains($0.location.segmentID) && ($0.location.fieldIndex.map { $0 <= 2 } ?? false)
                    && $0.code.number != 1003 }, "\(url.lastPathComponent)")
            }
        }
    }

    @Test("Lenient options leave the envelope's length and format findings off")
    func lenientFollowsTheFieldOptions() throws {
        let issues = try Self.batchIssues(["BHS|^~\\&|APP||||2024XX01||SYN-BATCH-NAME-LONGER-THAN-20", Self.msh("F3"), "BTS|1"],
                                          options: .lenient)
        #expect(issues.isEmpty)
    }
}
