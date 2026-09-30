// OrderConditionTests.swift
// P4: timing (TQ1/TQ2) and blood-product (BPX/BTX) conditionals moved
// out of the permanent-limitations register. Synthetic wires only.

import Testing
import Foundation
@testable import HL7v2Kit

private let orderVersions = ["2.5.1", "2.6", "2.8.2"]

@Suite("Order conditions (P4)")
struct OrderConditionTests {

    private func missing(_ wire: String, _ seg: String, _ idx: Int) throws -> [ValidationIssue] {
        Validator().validate(try Parser().parse(wire)).errors.filter {
            $0.code == .conditionalFieldMissing
                && $0.location.segmentID == seg && $0.location.fieldIndex == idx
        }
    }

    // MARK: - Timing (V251-C03, V251-C15)

    private func tq2(_ version: String, _ fields: [Int: String]) -> String {
        TestWires.wire("OMG^O19^OMG_O19", version, "ORC|NW|PL1", "TQ1|1",
                       TestWires.segment("TQ2", fields.merging([1: "1"]) { current, _ in current }))
    }

    @Test("TQ2-3/4/5: at least one related order number must be valued", arguments: orderVersions)
    func tq2RelatedNumbers(version: String) throws {
        let none = tq2(version, [6: "ES"])
        for idx in [3, 4, 5] {
            #expect(try missing(none, "TQ2", idx).count == 1, "v\(version) TQ2-\(idx)")
        }
        let placer = tq2(version, [3: "PL2^SYS", 6: "ES"])
        for idx in [3, 4, 5] {
            #expect(try missing(placer, "TQ2", idx).isEmpty, "v\(version) TQ2-\(idx)")
        }
    }

    @Test("TQ2-6 / TQ2-10: either must be present", arguments: orderVersions)
    func tq2SequenceOrService(version: String) throws {
        let neither = tq2(version, [3: "PL2^SYS"])
        #expect(try missing(neither, "TQ2", 6).count == 1, "v\(version)")
        #expect(try missing(neither, "TQ2", 10).count == 1, "v\(version)")
        let sequence = tq2(version, [3: "PL2^SYS", 6: "ES"])
        #expect(try missing(sequence, "TQ2", 6).isEmpty, "v\(version)")
        #expect(try missing(sequence, "TQ2", 10).isEmpty, "v\(version)")
    }

    @Test("TQ1-12 must be valued on a TQ1 that another TQ1 follows", arguments: orderVersions)
    func tq1Conjunction(version: String) throws {
        let chained = TestWires.wire("OMG^O19^OMG_O19", version, "ORC|NW|PL1", "TQ1|1",
                                     TestWires.segment("TQ2", [1: "1", 2: "S", 3: "PL2^SYS", 10: "S"]),
                                     "TQ1|2", "OBR|1|PL1")
        let hits = try missing(chained, "TQ1", 12)
        #expect(hits.count == 1, "v\(version)")
        #expect(hits.first?.location.pathDescription == "TQ1[1]-12", "v\(version)")
        let single = TestWires.wire("OMG^O19^OMG_O19", version, "ORC|NW|PL1", "TQ1|1", "OBR|1|PL1")
        #expect(try missing(single, "TQ1", 12).isEmpty, "v\(version)")
    }
}
