// OrderConditionTests.swift
// P4: timing (TQ1/TQ2) and blood-product (BPX/BTX) conditionals moved
// out of the permanent-limitations register. Synthetic wires only.

import Testing
import Foundation
@testable import HL7v2Kit

private let orderVersions = ["2.5.1", "2.6", "2.8.2"]
private let pharmacyVersions = ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.8.2"]

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

    // MARK: - Blood product (V251-C13)

    private func bpx(_ version: String, _ fields: [Int: String]) -> String {
        TestWires.wire("BPS^O29^BPS_O29", version,
                       TestWires.segment("BPX", fields.merging([1: "1"]) { current, _ in current }))
    }

    private func btx(_ version: String, _ fields: [Int: String]) -> String {
        TestWires.wire("BTS^O31^BTS_O31", version,
                       TestWires.segment("BTX", fields.merging([1: "1"]) { current, _ in current }))
    }

    private func notApplicable(_ wire: String, _ seg: String) throws -> [ValidationIssue] {
        Validator().validate(try Parser().parse(wire)).issues.filter {
            $0.code == .conditionalFieldProhibited && $0.location.segmentID == seg
        }
    }

    @Test("BPX component fields pair up; commercial-product fields pair up", arguments: orderVersions)
    func bpxRequired(version: String) throws {
        let componentOnly = bpx(version, [6: "E0791V00^RBC^ISBT128"])
        #expect(try missing(componentOnly, "BPX", 5).count == 1, "v\(version)")
        let component = bpx(version, [5: "W0000 26 123456", 6: "E0791V00^RBC^ISBT128"])
        for idx in [5, 6, 8, 9, 10] {
            #expect(try missing(component, "BPX", idx).isEmpty, "v\(version) BPX-\(idx)")
        }
        let lotOnly = bpx(version, [10: "LOT1"])
        #expect(try missing(lotOnly, "BPX", 8).count == 1, "v\(version)")
        #expect(try missing(lotOnly, "BPX", 9).count == 1, "v\(version)")
        let product = bpx(version, [8: "RHIG^Rh immune globulin", 9: "Maker Inc", 10: "LOT1"])
        for idx in [5, 6, 8, 9, 10] {
            #expect(try missing(product, "BPX", idx).isEmpty, "v\(version) BPX-\(idx)")
        }
    }

    @Test("BPX component and commercial fields are not applicable to each other (warning)", arguments: orderVersions)
    func bpxNotApplicable(version: String) throws {
        let mixed = bpx(version, [5: "W0000 26 123456", 6: "E0791V00", 8: "RHIG", 9: "Maker Inc", 10: "LOT1"])
        let hits = try notApplicable(mixed, "BPX")
        #expect(Set(hits.compactMap(\.location.fieldIndex)) == [5, 6, 8, 9, 10], "v\(version)")
        #expect(hits.allSatisfy { $0.severity == .warning }, "v\(version)")
        let component = bpx(version, [5: "W0000 26 123456", 6: "E0791V00"])
        #expect(try notApplicable(component, "BPX").isEmpty, "v\(version)")
    }

    @Test("BTX component, blood-group and commercial-product fields", arguments: orderVersions)
    func btxRules(version: String) throws {
        let componentOnly = btx(version, [3: "E0791V00"])
        #expect(try missing(componentOnly, "BTX", 2).count == 1, "v\(version)")
        #expect(try missing(componentOnly, "BTX", 4).count == 1, "v\(version)")
        let component = btx(version, [2: "W0000 26 123456", 3: "E0791V00", 4: "5100^O Pos^ISBT128"])
        for idx in [2, 3, 4, 5, 6, 7] {
            #expect(try missing(component, "BTX", idx).isEmpty, "v\(version) BTX-\(idx)")
        }
        #expect(try notApplicable(component, "BTX").isEmpty, "v\(version)")
        let productPartial = btx(version, [5: "RHIG"])
        #expect(try missing(productPartial, "BTX", 6).count == 1, "v\(version)")
        #expect(try missing(productPartial, "BTX", 7).count == 1, "v\(version)")
        let mixed = btx(version, [2: "W0000 26 123456", 3: "E0791V00", 4: "5100", 5: "RHIG", 6: "Maker Inc", 7: "LOT1"])
        #expect(Set(try notApplicable(mixed, "BTX").compactMap(\.location.fieldIndex)) == [2, 3, 5, 6, 7], "v\(version)")
    }

    // MARK: - Pharmacy give/dispense positions (P4-17)
    //
    // Every RXO/RXE/RXD/RXG/RXC field whose prose mentions give or
    // dispense amount, units or strength was read against its own
    // version's field-definition text.
    // - RXO-1/2/4's free-text exception ships (fix round 1): the
    //   `noRepeat(<fieldref>) <predicate>` atom reads a PER-REPETITION
    //   component slot (Validator.resolveRepetitionSlots), unlike the
    //   plain field-atom's whole-field `populated`/`empty`
    //   (Validator.readField). `RXO-6 empty OR noRepeat(RXO-6.1) empty`
    //   states "RXO-6 not used at all, or used but never as free text
    //   (no repetition has its first component blank)" — see
    //   `rxo124FreeTextCarveOut` below.
    // - RXO-17 / RXE-22 / RXG-14's "administered continuously at a
    //   prescribed rate" (RXG-14: "when relevant") is a clinical
    //   judgement, not a peer-field value.
    // - RXE-11 / RXD-5 / RXG-33 / RXC-11's "required if the units are
    //   not implied by the actual dispense code" needs a terminology
    //   service (req #3/#4, docs/design/permanent-limitations-register.md §C).
    // - RXE-10 / RXE-19 / RXG-32 / RXC-10 state no conditionality
    //   clause at all.
    // See docs/design/conditional-completeness-audit.md, "Order/pharmacy
    // & timing family", for the quoted citations.

    private func expectBareC(_ seg: String, _ idx: Int, versions: [String]) {
        let tables: [String: [String: SegmentGrammar]] = [
            "2.3": SegmentGrammarTable.v2_3, "2.3.1": SegmentGrammarTable.v2_3_1,
            "2.4": SegmentGrammarTable.v2_4, "2.5.1": SegmentGrammarTable.v2_5_1,
            "2.6": SegmentGrammarTable.v2_6, "2.8.2": SegmentGrammarTable.v2_8_2,
        ]
        for version in versions {
            #expect(tables[version]?[seg]?.field(idx)?.optionality == .conditional, "\(seg)-\(idx) v\(version)")
            #expect(tables[version]?[seg]?.field(idx)?.condition == nil, "\(seg)-\(idx) v\(version)")
        }
    }

    // RXO-1/2/4 are `R` on v2.3 (no rule to ship there); `C` from
    // v2.3.1 with the same "mandatory unless free text" sentence
    // through v2.8.2.
    private static let rxo124Versions = ["2.3.1", "2.4", "2.5.1", "2.6", "2.8.2"]

    private func rxo(_ version: String, _ rxo6: String?) -> String {
        var fields: [Int: String] = [:]
        if let rxo6 { fields[6] = rxo6 }
        return TestWires.wire("RDE^O11^RDE_O11", version, TestWires.segment("RXO", fields))
    }

    @Test("RXO-1/2/4 required unless RXO-6 carries the order as free text", arguments: rxo124Versions)
    func rxo124FreeTextCarveOut(version: String) throws {
        // RXO-6 absent entirely: required (no free text used at all).
        for idx in [1, 2, 4] {
            #expect(try missing(rxo(version, nil), "RXO", idx).count == 1, "v\(version) RXO-\(idx) RXO-6 absent")
        }
        // RXO-6 carries a coded value (component 1 populated): required.
        for idx in [1, 2, 4] {
            #expect(try missing(rxo(version, "CODE^text"), "RXO", idx).count == 1, "v\(version) RXO-\(idx) coded")
        }
        // RXO-6 is free text (component 1 blank, text in component 2): silent.
        for idx in [1, 2, 4] {
            #expect(try missing(rxo(version, "^free text"), "RXO", idx).isEmpty, "v\(version) RXO-\(idx) free text")
        }
        // RXO-6 repeats, one repetition free text: silent (noRepeat fails
        // on the populated repetition).
        for idx in [1, 2, 4] {
            #expect(try missing(rxo(version, "CODE^x~^free"), "RXO", idx).isEmpty, "v\(version) RXO-\(idx) mixed repetitions")
        }
    }

    @Test("RXO-17 / RXE-22 / RXG-14 stay bare: continuous administration at a prescribed rate is not wire-decidable")
    func continuousRateStillBare() {
        expectBareC("RXO", 17, versions: pharmacyVersions)
        expectBareC("RXE", 22, versions: pharmacyVersions)
        expectBareC("RXG", 14, versions: pharmacyVersions)
    }

    @Test("RXE-11 / RXD-5 / RXG-33 / RXC-11 stay bare: units implied by the dispense code needs a terminology service")
    func dispenseUnitsImpliedStillBare() {
        expectBareC("RXE", 11, versions: pharmacyVersions)
        expectBareC("RXD", 5, versions: pharmacyVersions)
        expectBareC("RXG", 33, versions: ["2.8.2"])
        expectBareC("RXC", 11, versions: ["2.8.2"])
    }

    @Test("RXE-10 / RXE-19 / RXG-32 / RXC-10 print C with no stated conditionality clause")
    func dispenseAmountBareC() {
        expectBareC("RXE", 10, versions: pharmacyVersions)
        expectBareC("RXE", 19, versions: pharmacyVersions)
        expectBareC("RXG", 32, versions: ["2.8.2"])
        expectBareC("RXC", 10, versions: ["2.8.2"])
    }
}
