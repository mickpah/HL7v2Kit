// ConditionNotEvaluatedTests.swift
// S1-4 (owner decision 9, 2026-10-06): when the P8b-17 fallback gates the
// order-number predicates off an OUL, OPU or OPL message with no group spans
// (ADR-019), the message carries one information issue saying so.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Condition not evaluated (fallback gate)")
struct ConditionNotEvaluatedTests {

    private static let oul = ["PID|1", "SPM|1", "OBR|1|P1|F1|X", "ORC|SC|P1|F1"]

    private static func notEvaluated(_ message: Message) -> [ValidationIssue] {
        Validator().validate(message).issues.filter {
            if case .conditionNotEvaluated = $0.code { return true }
            return false
        }
    }

    @Test("A gated v2.6 OUL^R22 with one structure finding gets exactly one info issue")
    func gatedV26() throws {
        let message = try GroupSpanScopeTests.message("OUL^R22^OUL_R22", "2.6", Self.oul + ["NK1|1"])
        #expect(GroupSpanSeamTests.describe(Validator().groupScoping(for: message)).hasPrefix("gated"))
        let found = Self.notEvaluated(message)
        try #require(found.count == 1)
        let issue = found[0]
        #expect(issue.severity == .info)
        #expect(issue.code == .conditionNotEvaluated(fields: ["OBR-2", "OBR-3", "OBR-29", "ORC-2", "ORC-3", "ORC-8"]))
        #expect(issue.location == IssueLocation(segmentID: "OBR", segmentIndex: 1, fieldIndex: 2))
        for name in ["OBR-2", "OBR-3", "OBR-29", "ORC-2", "ORC-3", "ORC-8", "NK1", "OUL_R22"] {
            #expect(issue.message.contains(name), "\(name) not in: \(issue.message)")
        }
        #expect(issue.message.contains("because NK1 at segment 6 has no place in OUL_R22; without spans the v2.6 gate "
                                       + "applies to OUL, so these order-number conditions are not evaluated"),
                "\(issue.message)")
        // S1-4 review: the text makes no structural claim about where the OBR is printed,
        // which would be untrue of OUL_R21 (`[ORC] OBR`) and of an empty MSH-9.1.
        #expect(!issue.message.contains("printed before"), "\(issue.message)")
    }

    @Test("The issue sits at the first gated segment occurrence when an OBR precedes the ORC")
    func firstOccurrenceObrFirst() throws {
        let body = ["PID|1", "SPM|1", "OBR|1|P1|F1|X", "OBR|2|P2|F2|X", "ORC|SC|P1|F1", "NK1|1"]
        let message = try GroupSpanScopeTests.message("OUL^R22^OUL_R22", "2.6", body)
        let found = Self.notEvaluated(message)
        try #require(found.count == 1)
        #expect(found[0].location == IssueLocation(segmentID: "OBR", segmentIndex: 1, fieldIndex: 2))
    }

    @Test("An empty MSH-9.1 on v2.6 carrying ORC gets one info issue naming the empty MSH-9.1")
    func emptyMessageCodeV26() throws {
        let message = try GroupSpanScopeTests.message("", "2.6", ["PID|1", "ORC|NW|P1"])
        let found = Self.notEvaluated(message)
        try #require(found.count == 1)
        #expect(found[0].severity == .info)
        #expect(found[0].location == IssueLocation(segmentID: "ORC", segmentIndex: 1, fieldIndex: 2))
        #expect(found[0].message.contains("the v2.6 gate applies to an empty MSH-9.1"), "\(found[0].message)")
    }

    @Test("v2.4 has no gate, so an empty MSH-9.1 there gets none")
    func noGateV24() throws {
        let message = try GroupSpanScopeTests.message("", "2.4", ["PID|1", "ORC|NW|P1", "OBR|1|P1|F1|X"])
        #expect(Self.notEvaluated(message).isEmpty)
    }

    @Test("v2.8.2 and v2.7.1 name only the order-number fields")
    func gatedV282() throws {
        for version in ["2.7.1", "2.8.2"] {
            let message = try GroupSpanScopeTests.message("OUL^R22^OUL_R22", version, Self.oul + ["NK1|1"])
            let found = Self.notEvaluated(message)
            #expect(found.map(\.code) == [.conditionNotEvaluated(fields: ["OBR-2", "OBR-3", "ORC-2", "ORC-3"])], "\(version)")
        }
    }

    @Test("The same message with a clean structure gets none")
    func cleanStructure() throws {
        let message = try GroupSpanScopeTests.message("OUL^R22^OUL_R22", "2.6", Self.oul)
        #expect(GroupSpanSeamTests.describe(Validator().groupScoping(for: message)) == "spans")
        #expect(Self.notEvaluated(message).isEmpty)
    }

    @Test("A message code outside the gate (ORU^R01) gets none")
    func notListed() throws {
        let message = try GroupSpanScopeTests.message("ORU^R01^ORU_R01", "2.6",
                                                      ["PID|1", "ORC|RE|P1|F1", "OBR|1|P1|F1|X", "NK1|1"])
        #expect(GroupSpanSeamTests.describe(Validator().groupScoping(for: message)) == "walk")
        #expect(Self.notEvaluated(message).isEmpty)
    }

    @Test("An empty MSH-9.1 keeps the gate (P8b-17), so an elided header with ORC and OBR gets the issue")
    func emptyMessageCode() throws {
        let message = try Parser().parse("MSH|^~\\&|\rPID|1\rORC|NW|P1\rOBR|1|P1|F1|X\r")
        let found = Self.notEvaluated(message)
        try #require(found.count == 1)
        #expect(found[0].location == IssueLocation(segmentID: "ORC", segmentIndex: 1, fieldIndex: 2))
        #expect(found[0].message.contains("MSH-9 is empty"), "\(found[0].message)")
        #expect(found[0].message.contains("an empty MSH-9.1"), "\(found[0].message)")
    }

    @Test("A gated message without ORC or OBR skips no predicate and gets none")
    func noGatedSegment() throws {
        let message = try GroupSpanScopeTests.message("OUL^R22^OUL_R22", "2.6", ["PID|1", "SPM|1"])
        #expect(GroupSpanSeamTests.describe(Validator().groupScoping(for: message)).hasPrefix("gated"))
        #expect(Self.notEvaluated(message).isEmpty)
    }
}
