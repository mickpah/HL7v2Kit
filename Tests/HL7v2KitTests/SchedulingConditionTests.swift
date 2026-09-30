// SchedulingConditionTests.swift
// P4: scheduling (SCH / ARQ / AIS / AIG / AIL / AIP / RGS) conditionals
// moved out of the permanent-limitations register. Synthetic wires only.

import Testing
import Foundation
@testable import HL7v2Kit

private let schedulingVersions = ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.8.2"]

@Suite("Scheduling conditions (P4)")
struct SchedulingConditionTests {

    private func missing(_ wire: String, _ seg: String, _ idx: Int) throws -> [ValidationIssue] {
        Validator().validate(try Parser().parse(wire)).errors.filter {
            $0.code == .conditionalFieldMissing
                && $0.location.segmentID == seg && $0.location.fieldIndex == idx
        }
    }

    // MARK: - SCH / ARQ identifiers (V251-C03)

    @Test("SCH-1 / SCH-2: the placer or the filler appointment ID", arguments: ["2.3.1", "2.4", "2.5.1", "2.6", "2.8.2"])
    func schAppointmentIDs(version: String) throws {
        let neither = TestWires.wire("SIU^S12", version, TestWires.segment("SCH", [5: "SCHED1"]))
        #expect(try missing(neither, "SCH", 1).count == 1, "v\(version)")
        #expect(try missing(neither, "SCH", 2).count == 1, "v\(version)")
        let placer = TestWires.wire("SIU^S12", version, TestWires.segment("SCH", [1: "PL1", 5: "SCHED1"]))
        #expect(try missing(placer, "SCH", 1).isEmpty, "v\(version)")
        #expect(try missing(placer, "SCH", 2).isEmpty, "v\(version)")
    }

    @Test("SCH-27 / ARQ-25: the filler order number when the placer order number is present",
          arguments: ["2.4", "2.5.1", "2.6", "2.8.2"])
    func fillerOrderNumbers(version: String) throws {
        let sch = TestWires.wire("SIU^S12", version, TestWires.segment("SCH", [1: "PL1", 26: "PON1"]))
        #expect(try missing(sch, "SCH", 27).count == 1, "v\(version)")
        let schNone = TestWires.wire("SIU^S12", version, TestWires.segment("SCH", [1: "PL1"]))
        #expect(try missing(schNone, "SCH", 27).isEmpty, "v\(version)")
        let arq = TestWires.wire("SRM^S01", version, TestWires.segment("ARQ", [1: "PL1", 24: "PON1"]))
        #expect(try missing(arq, "ARQ", 25).count == 1, "v\(version)")
        let arqNone = TestWires.wire("SRM^S01", version, TestWires.segment("ARQ", [1: "PL1"]))
        #expect(try missing(arqNone, "ARQ", 25).isEmpty, "v\(version)")
    }
}
