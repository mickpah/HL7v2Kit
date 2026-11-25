// IssueRepetitionTests.swift
// An issue about one repetition names it in its location (P01 R6).

import Testing
@testable import HL7v2Kit

@Suite("Issue repetition")
struct IssueRepetitionTests {
    /// Three PID-3 repetitions; the second has no CX.1 (a required component) and a
    /// universal ID type (CX.4.3, HD.3) outside Table 0301. v2.5.1 Table 0203 (CX.5) is
    /// user-defined, so it draws no table issue.
    static let wire = TestWires.adt("PID|1||MRN12345^^^HOSP^MR~^^^HOSP&1.2.36&QQQQ^MR~MRN67890^^^HOSP^MR||MARKER^ONE")

    static func issues() throws -> [ValidationIssue] {
        Validator().validate(try Parser().parse(wire)).issues.filter {
            $0.location.segmentID == "PID" && $0.location.fieldIndex == 3
        }
    }

    @Test("A value-level issue on the second repetition names repetition 2")
    func valueIssuesNameTheRepetition() throws {
        let issues = try Self.issues()
        let missing = issues.first { $0.code == .requiredComponentMissing }
        #expect(missing?.location.repetitionIndex == 2)
        #expect(missing?.location.pathDescription == "PID[1]-3~2.1")
        let table = issues.first { $0.code == .valueNotInTable(table: "0301") }
        #expect(table?.location.pathDescription == "PID[1]-3~2.4.3")
        #expect(!issues.isEmpty)
        for issue in issues {
            #expect(issue.location.repetitionIndex == 2, "\(issue.code)")
        }
    }

    @Test("A format fault and a length fault on the second repetition name repetition 2")
    func formatAndLengthNameTheRepetition() throws {
        // Repetition 2: 271 characters against PID-3's LEN 250, and CX.7 (DT) not a date.
        let long = String(repeating: "A", count: 251)
        let wire = TestWires.adt("PID|1||MRN12345^^^HOSP^MR~\(long)^^^HOSP^MR^^NOTADATE||MARKER^ONE")
        let issues = Validator().validate(try Parser().parse(wire)).issues
        let format = issues.first { $0.code == .valueFormatInvalid(dataType: "DT") }
        #expect(format?.location.repetitionIndex == 2)
        #expect(format?.location.pathDescription == "PID[1]-3~2.7")
        let length = issues.first { $0.code == .fieldLengthOutOfRange(length: "250", actual: 271) }
        #expect(length?.location.repetitionIndex == 2)
        #expect(length?.location.pathDescription == "PID[1]-3~2")
    }

    @Test("A field-level issue names no repetition")
    func fieldIssuesNameNone() throws {
        let message = try Parser().parse(TestWires.adt("PID|1||||MARKER^ONE"))
        let missing = Validator().validate(message).issues.first {
            $0.code == .requiredFieldMissing && $0.location.fieldIndex == 3
        }
        #expect(missing != nil)
        #expect(missing?.location.repetitionIndex == nil)
        #expect(missing?.location.pathDescription == "PID[1]-3")
    }

    @Test("The older initialiser names no repetition; the path form is the package's own")
    func pathForm() throws {
        #expect(IssueLocation(segmentID: "PID", segmentIndex: 1, fieldIndex: 3, componentIndex: 4).repetitionIndex == nil)
        let named = IssueLocation(segmentID: "OBX", segmentIndex: 2, fieldIndex: 5, repetitionIndex: 1,
                                  componentIndex: 3, subcomponentIndex: nil)
        #expect(named.pathDescription == "OBX[2]-5~1.3")
        let parsed = try Path(named.pathDescription)
        #expect(parsed.description == named.pathDescription)
    }
}
