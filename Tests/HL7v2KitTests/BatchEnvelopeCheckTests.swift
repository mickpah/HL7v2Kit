// BatchEnvelopeCheckTests.swift
// Batch envelopes task 3: BatchValidator compares BTS-1 with the messages in its batch and
// FTS-1 with the batches in the file, and reports an envelope out of the grammar's order or
// with unreadable delimiters, under ValidationOptions.batchEnvelopeSeverity.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Batch envelope counts and order")
struct BatchEnvelopeCheckTests {
    static func msh(_ id: String) -> String {
        "MSH|^~\\&|SYNTH_HIS|SYNTH_FAC|SYNTH_HOSP|SYNTH_FAC|20240101120000||ADT^A01^ADT_A01|\(id)|P|2.5.1\rPID|1"
    }

    static func issues(_ lines: [String], options: ValidationOptions = .default,
                       locale: HL7Locale = .international) throws -> [ValidationIssue] {
        let file = try BatchParser().parse(lines.joined(separator: "\r") + "\r")
        return BatchValidator(options: options, locale: locale).validate(file).batchIssues
            .filter { [1013, 2009].contains($0.code.number) }
    }

    static func fixture(_ name: String) throws -> BatchFile {
        try BatchParser().parse(Data(contentsOf: FixtureCorpus.batchFixtureURL(named: name)))
    }

    @Test("Both counts wrong: BTS-1 at BTS 1, FTS-1 at FTS 1, as errors")
    func countMismatchFixture() throws {
        let report = BatchValidator().validate(try Self.fixture("batch_count_mismatch.hl7"))
        let issues = report.batchIssues.filter { $0.code.number == 2009 }
        #expect(issues.map(\.location.pathDescription) == ["BTS[1]-1", "FTS[1]-1"])
        #expect(issues.map(\.code) == [.batchCountMismatch(declared: "3", actual: 2), .batchCountMismatch(declared: "2", actual: 1)])
        #expect(issues.allSatisfy { $0.severity == .error })
        #expect(!report.isValid)
    }

    @Test("BTS-1 rules", arguments: [
        ("2", 2, nil), ("3", 2, "3"), ("02", 2, nil), ("two", 2, "two"), ("", 2, nil), ("0", 0, nil), ("1", 0, "1"),
    ] as [(declared: String, messages: Int, reported: String?)])
    func batchMessageCount(_ row: (declared: String, messages: Int, reported: String?)) throws {
        let body = (0..<row.messages).map { Self.msh("C\($0)") }
        let issues = try Self.issues(["BHS|^~\\&|APP"] + body + ["BTS|\(row.declared)"])
        let expected: [IssueCode] = row.reported.map { [IssueCode.batchCountMismatch(declared: $0, actual: row.messages)] } ?? []
        #expect(issues.map(\.code) == expected)
    }

    @Test("FTS-1 counts batch groups, a group without BHS included")
    func fileBatchCount() throws {
        #expect(try Self.issues(["FHS|^~\\&|APP", Self.msh("D1"), Self.msh("D2"), "FTS|1"]).isEmpty)
        #expect(try Self.issues(["FHS|^~\\&|APP", Self.msh("D1"), "FTS|2"]).map(\.code)
                == [.batchCountMismatch(declared: "2", actual: 1)])
        let notANumber = try BatchParser().parse(["FHS|^~\\&|APP", Self.msh("D1"), "FTS|x"].joined(separator: "\r") + "\r")
        let all = BatchValidator().validate(notANumber).batchIssues
        #expect(all.contains { $0.code == .batchCountMismatch(declared: "x", actual: 1) })
        #expect(all.contains { $0.code.number == 3004 && $0.location.segmentID == "FTS" })
    }

    @Test("Absent BTS and FTS are not checked")
    func absentCountsNotChecked() throws {
        #expect(try Self.issues(["FHS|^~\\&|APP", "BHS|^~\\&|APP", Self.msh("E1")]).isEmpty)
    }

    @Test("Out-of-order fixture: FHS 1 not first, FTS 2 after the trailer")
    func outOfOrderFixture() throws {
        let issues = BatchValidator().validate(try Self.fixture("batch_envelope_out_of_order.hl7")).batchIssues
            .filter { $0.code.number == 1013 }
        #expect(issues.map(\.location.pathDescription) == ["FHS[1]", "FTS[2]"])
        #expect(issues.map(\.code) == [.batchEnvelopeMalformed(segmentID: "FHS"), .batchEnvelopeMalformed(segmentID: "FTS")])
        #expect(issues.first?.message.contains("not the first segment") == true)
    }

    @Test("A header whose delimiters cannot be read is malformed at field 2")
    func unreadableDelimiters() throws {
        let issues = try Self.issues(["BHS|^^\\&|APP", Self.msh("G1"), "BTS|1"])
        #expect(issues.map(\.location.pathDescription) == ["BHS[1]-2"])
        #expect(issues.map(\.code) == [.batchEnvelopeMalformed(segmentID: "BHS")])
    }

    @Test("Presets: error in default and strict, off in lenient")
    func presets() throws {
        let lines = ["BHS|^~\\&|APP", Self.msh("H1"), "BTS|5", "FTS|1", "FTS|1"]
        #expect(try Self.issues(lines).map(\.severity) == [.error, .error])
        #expect(try Self.issues(lines, options: .strict).map(\.severity) == [.error, .error])
        #expect(try Self.issues(lines, options: .lenient).isEmpty)
        #expect(ValidationOptions.default.batchEnvelopeSeverity == .error)
    }

    @Test("valueExcerpts off withholds the declared count")
    func excerptsOff() throws {
        var options = ValidationOptions.default
        options.valueExcerpts = false
        let issue = try #require(try Self.issues(["BHS|^~\\&|APP", Self.msh("I1"), "BTS|7"], options: options).first)
        #expect(issue.message.contains("[value]") && !issue.message.contains("\"7\""))
    }

    @Test("Envelope findings come before the AU batch rules")
    func beforeTheAURules() throws {
        let file = try BatchParser().parse(["BHS|^~\\&|APP", Self.msh("J1"), "BTS|2", "BHS|^~\\&|APP", Self.msh("J2"), "BTS|1"]
            .joined(separator: "\r") + "\r")
        let numbers = BatchValidator(locale: .auLocalisation).validate(file).batchIssues.map(\.code.number)
        let count = try #require(numbers.firstIndex(of: 2009))
        let au = try #require(numbers.firstIndex(of: 1003))
        #expect(count < au)
    }
}
