// ExactMatcherExpectedTests.swift
// P8b-final (F-I3): an exact-matched structure reports a segment no live parse
// consumes as `messageStructureSegmentUnexpected`; when the segment before it
// is the absent one (BAR_P01 or DFT_P03 without EVN), the finding's text also
// names the segments the structure accepts at that point, so the reader sees
// EVN was expected. Code, severity, location and the number of findings are
// those of the bare finding.

import Testing
@testable import HL7v2Kit

@Suite("Exact matcher names what it expected")
struct ExactMatcherExpectedTests {

    private func structureIssues(_ msh9: String, _ body: [String], version: String = "2.5.1") throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let wire = (["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||\(msh9)|MSG00001|P|\(version)"] + body).joined(separator: "\r")
        return Validator(options: options).validate(try Parser().parse(wire)).issues.filter {
            switch $0.code {
            case .messageStructureSegmentMissing, .messageStructureSegmentUnexpected,
                 .messageStructureMismatch, .messageStructureNotModelled: true
            default: false
            }
        }
    }

    @Test("BAR_P01 and DFT_P03 without EVN: one unexpected PID whose text names EVN",
          arguments: [("BAR^P01^BAR_P01", "BAR_P01", ["PID|1", "PV1|1"]),
                      ("DFT^P03^DFT_P03", "DFT_P03", ["PID|1", "FT1|1"])])
    func missingEVN(_ c: (String, String, [String])) throws {
        let structure = try #require(MessageStructureTable.structure(c.1, version: .v2_5_1))
        #expect(structure.requiresExactMatch, "\(c.1) is exact-matched on v2.5.1")
        let issues = try structureIssues(c.0, c.2)
        #expect(issues.count == 1, "\(issues.map(\.message))")
        let issue = try #require(issues.first)
        #expect(issue.code == .messageStructureSegmentUnexpected(structure: c.1, segmentID: "PID"))
        #expect(issue.severity == .error)
        #expect(issue.location.segmentID == "PID" && issue.location.segmentIndex == 1)
        #expect(issue.message.hasPrefix("PID has no place in \(c.1) at this point"), "\(issue.message)")
        #expect(issue.message.contains("expected here: SFT or EVN"), "\(issue.message)")
    }

    @Test("A segment past the last one the structure allows names the end of the message")
    func endExpected() {
        let elements: [StructureElement] = [.segment("MSH", min: 1, max: 1), .segment("A", min: 1, max: 1)]
        let exact = ExactStructureMatcher(structure: MessageStructure(id: "T", version: "2.5.1", triggers: [],
                                                                      citation: "test", elements: elements))
        let match = exact.match(["MSH", "A", "B"])
        #expect(match.findings == [StructureFinding(kind: .unexpected, segmentID: "B", group: nil, index: 2)])
        #expect(match.expectedHere == [])
        #expect(match.endExpectedHere)
    }

    @Test("The list is in structure order, without repeats, and bounded")
    func bounded() {
        let names = (0..<12).map { "S\($0)" }
        let elements: [StructureElement] = [.segment("MSH", min: 1, max: 1)]
            + names.map { .segment($0, min: 0, max: 1) } + [.segment("S0", min: 0, max: 1), .segment("END", min: 1, max: 1)]
        let exact = ExactStructureMatcher(structure: MessageStructure(id: "T", version: "2.5.1", triggers: [],
                                                                      citation: "test", elements: elements))
        let match = exact.match(["MSH", "X"])
        #expect(match.expectedHere == names + ["END"])
        #expect(!match.endExpectedHere)
        #expect(Validator.expectedText(match) == "; expected here: S0, S1, S2, S3, S4, S5, S6, S7 and 5 more")
    }
}
