// ExpressibleConditionTests.swift
// P4: conditional predicates the permanent-limitations register called
// inexpressible although the condition DSL already states them. One
// firing and one non-firing synthetic wire per shipped predicate.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Expressible conditions (P4)")
struct ExpressibleConditionTests {

    private func missing(_ wire: String, _ seg: String, _ idx: Int) throws -> [ValidationIssue] {
        Validator().validate(try Parser().parse(wire)).errors.filter {
            $0.code == .conditionalFieldMissing
                && $0.location.segmentID == seg && $0.location.fieldIndex == idx
        }
    }

    // MARK: - Mis-scoped same-segment peers (V26-C02..C04, V26-C06, V282-C05)

    @Test("v2.6 PD1-15 is required when PD1-22 is valued")
    func pd115OnV26() throws {
        let fires = TestWires.wire("ADT^A01^ADT_A01", "2.6", TestWires.segment("PD1", [22: "20260101"]))
        #expect(try missing(fires, "PD1", 15).count == 1)
        let silent = TestWires.wire("ADT^A01^ADT_A01", "2.6", TestWires.segment("PD1", [1: "A"]))
        #expect(try missing(silent, "PD1", 15).isEmpty)
    }

    @Test("ORC-26 is required when ORC-20 is 3 or 4", arguments: ["2.5.1", "2.6"])
    func orc26(version: String) throws {
        let fires = TestWires.wire("OMG^O19^OMG_O19", version,
                                   TestWires.segment("ORC", [1: "NW", 2: "PL1", 20: "3"]))
        #expect(try missing(fires, "ORC", 26).count == 1, "v\(version)")
        let silent = TestWires.wire("OMG^O19^OMG_O19", version,
                                    TestWires.segment("ORC", [1: "NW", 2: "PL1", 20: "1"]))
        #expect(try missing(silent, "ORC", 26).isEmpty, "v\(version)")
    }

    @Test("PV2-45 is required when PV2-50 is valued", arguments: ["2.6", "2.8.2"])
    func pv245(version: String) throws {
        let fires = TestWires.wire("ADT^A01^ADT_A01", version, TestWires.segment("PV2", [50: "20260101"]))
        #expect(try missing(fires, "PV2", 45).count == 1, "v\(version)")
        let silent = TestWires.wire("ADT^A01^ADT_A01", version, TestWires.segment("PV2", [3: "RSN^Reason"]))
        #expect(try missing(silent, "PV2", 45).isEmpty, "v\(version)")
    }

    @Test("v2.8.2 OBR-22 is required whenever OBR-25 is valued")
    func obr22OnV282() throws {
        func oru(_ reported: String) -> String {
            TestWires.wire("ORU^R01^ORU_R01", "2.8.2", "ORC|RE|PON1|FON1",
                TestWires.segment("OBR", [1: "1", 2: "PON1", 3: "FON1", 4: "GLU^Glucose^L",
                                          7: "20260101100000", 22: reported, 25: "F"]))
        }
        #expect(try missing(oru(""), "OBR", 22).count == 1)
        #expect(try missing(oru("20260101110000"), "OBR", 22).isEmpty)
    }

    @Test("v2.6 OBR-48 and DG1-22 carry the printed bare C")
    func v26PrintedBareC() {
        let table = SegmentGrammarTable.v2_6
        #expect(table["OBR"]?.field(48)?.optionality == .conditional)
        #expect(table["OBR"]?.field(48)?.condition == nil)
        #expect(table["DG1"]?.field(22)?.optionality == .conditional)
        #expect(table["DG1"]?.field(22)?.condition == nil)
    }

    // MARK: - Placer-or-filler order identifier (X-C12, P4-7)

    /// The six versions carry OBR-2/3 and ORC-2/3 as C.
    static let orderVersions = ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.8.2"]

    /// An order message for `version` (ORM is withdrawn on v2.8.2).
    private func orderType(_ version: String) -> String {
        version == "2.8.2" ? "OML^O21^OML_O21" : "ORM^O01"
    }

    /// OBR with the report fields X-C07 and P4-6 require, plus `ids`.
    private func obr(_ ids: [Int: String]) -> String {
        var fields: [Int: String] = [1: "1", 4: "GLU^Glucose^L", 7: "20260101100000",
                                     22: "20260101110000", 25: "F"]
        fields.merge(ids) { _, new in new }
        return TestWires.segment("OBR", fields)
    }

    /// The order-number positions reported missing, as `SEG-n`, sorted.
    private func idHits(_ wire: String) throws -> [String] {
        Validator().validate(try Parser().parse(wire)).errors.compactMap { issue in
            guard issue.code == .conditionalFieldMissing,
                  ["ORC", "OBR"].contains(issue.location.segmentID),
                  let field = issue.location.fieldIndex, field == 2 || field == 3 else { return nil }
            return "\(issue.location.segmentID)-\(field)"
        }.sorted()
    }

    @Test("A placer id alone or a filler id alone satisfies the order-number rule",
          arguments: orderVersions)
    func oneOrderIDIsSilent(version: String) throws {
        // Placer NW: the filler has not assigned its number yet (ORC-3 is
        // assigned by the filler; v2.4 CH04 §4.5.1.3).
        let placerNW = TestWires.wire(orderType(version), version, "ORC|NW|PON1", obr([:]))
        #expect(try idHits(placerNW).isEmpty, "v\(version) placer NW")
        let fillerOnly = TestWires.wire("ORU^R01^ORU_R01", version, "ORC|RE", obr([3: "FON1"]))
        #expect(try idHits(fillerOnly).isEmpty, "v\(version) filler only")
        // Both Send Number shapes the ORC-1 table notes print (v2.4 CH04 §4.5.1.1).
        let snNullFiller = TestWires.wire(orderType(version), version, "ORC|SN|PON1^FILL", obr([:]))
        #expect(try idHits(snNullFiller).isEmpty, "v\(version) SN, null ORC-3")
        let snNullPlacer = TestWires.wire(orderType(version), version, "ORC|SN||FON1^FILL", obr([:]))
        #expect(try idHits(snNullPlacer).isEmpty, "v\(version) SN, null ORC-2")
    }

    @Test("No placer and no filler id fires all four positions", arguments: orderVersions)
    func noOrderIDFires(version: String) throws {
        let wire = TestWires.wire("ORU^R01^ORU_R01", version, "ORC|RE", obr([:]))
        #expect(try idHits(wire) == ["OBR-2", "OBR-3", "ORC-2", "ORC-3"], "v\(version)")
    }

    @Test("Send Number with no id: exempt on v2.8.2 only", arguments: orderVersions)
    func sendNumberWithNoID(version: String) throws {
        let wire = TestWires.wire(orderType(version), version, "ORC|SN", obr([:]))
        let expected: [String] = version == "2.8.2" ? [] : ["OBR-2", "OBR-3", "ORC-2", "ORC-3"]
        #expect(try idHits(wire) == expected, "v\(version)")
    }

    @Test("An ORC with no OBR needs one of its own order numbers", arguments: orderVersions)
    func orcWithoutOBR(version: String) throws {
        let none = TestWires.wire("RDE^O11", version, "ORC|NW")
        #expect(try idHits(none) == ["ORC-2", "ORC-3"], "v\(version)")
        let filler = TestWires.wire("RDE^O11", version, "ORC|NW||FON1")
        #expect(try idHits(filler).isEmpty, "v\(version)")
    }

    @Test("ORU without ORC: per-version order-number rules", arguments: orderVersions)
    func resultWithoutORC(version: String) throws {
        let oru = { (ids: [Int: String]) in TestWires.wire("ORU^R01^ORU_R01", version, self.obr(ids)) }
        // Placer may be blank when the filler initiates the order: v2.3 and
        // v2.3.1 CH07 §7.3.1.0, v2.4 CH07 §7.4.1.0 (dropped from v2.5.1).
        let placerOptional = ["2.3", "2.3.1", "2.4", "2.8.2"].contains(version)
        #expect(try idHits(oru([3: "FON1"])) == (placerOptional ? [] : ["OBR-2"]), "v\(version) filler only")
        // v2.3 to v2.6: "the identifying filler order number must be present
        // in the OBR segments"; v2.8.2: either id suffices.
        #expect(try idHits(oru([2: "PON1"])) == (version == "2.8.2" ? [] : ["OBR-3"]), "v\(version) placer only")
        #expect(try idHits(oru([:])) == ["OBR-2", "OBR-3"], "v\(version) no id")
    }

    @Test("OUL R22: an ORC after its OBR is not read as an ORC with no OBR",
          arguments: ["2.5.1", "2.6", "2.8.2"])
    func oulR22TrailingORC(version: String) throws {
        let wire = TestWires.wire("OUL^R22^OUL_R22", version, "SPM|1",
                                  obr([2: "PON1", 3: "FON1"]), "ORC|SC")
        #expect(try idHits(wire).isEmpty, "v\(version)")
    }

    /// OPL^O37 ORDER_PRIOR prints `{ OBR [ORC] ... }` (v2.6 and v2.8.2 CH04):
    /// the prior-result ORC follows the OBR that carries the numbers.
    @Test("OPL O37: a prior-result ORC after its OBR stays silent", arguments: ["2.6", "2.8.2"])
    func oplPriorResultORC(version: String) throws {
        let wire = TestWires.wire("OPL^O37^OPL_O37", version,
                                  obr([2: "PON1", 3: "FON1"]), "ORC|CH")
        #expect(try idHits(wire).isEmpty, "v\(version)")
        #expect(try missing(wire, "ORC", 8).isEmpty, "v\(version) ORC-8")
    }

    /// Two OUL R22 orders: order 1's numbers are only in its OBR, order 2's
    /// only in its ORC. The ORC-delimited group would pair order 1's ORC
    /// with order 2's OBR, and order 2's OBR with order 1's ORC.
    @Test("OUL R22 with two orders does not cross-resolve peers",
          arguments: ["2.5.1", "2.6", "2.8.2"])
    func oulR22TwoOrders(version: String) throws {
        let wire = TestWires.wire("OUL^R22^OUL_R22", version, "SPM|1",
                                  obr([2: "PON1", 3: "FON1"]), "ORC|CH",
                                  obr([1: "2"]), "ORC|SC|PON2|FON2")
        #expect(try idHits(wire).isEmpty, "v\(version)")
        #expect(try missing(wire, "ORC", 8).isEmpty, "v\(version) ORC-8")
    }

    @Test("v2.8.2: a Send Number ORC with no OBR is exempt")
    func sendNumberWithoutOBR() throws {
        let wire = TestWires.wire("OML^O21^OML_O21", "2.8.2", "ORC|SN")
        #expect(try idHits(wire).isEmpty)
    }

    // MARK: - ORC-8 child-order gate (owner decision G2-6, 2026-09-30)

    @Test("ORC-8: the OBR-absent leg is gated off OUL and OPU", arguments: ["2.5.1", "2.6"])
    func orc8Gate(version: String) throws {
        // OUL R22: the OBR precedes the ORC, outside its group.
        let oul = TestWires.wire("OUL^R22^OUL_R22", version, "SPM|1",
                                 obr([2: "PON1", 3: "FON1"]), "ORC|CH|PON1|FON1")
        #expect(try missing(oul, "ORC", 8).isEmpty, "v\(version) OUL R22")
        // ORM child order with no OBR keeps the leg.
        let child = TestWires.wire("ORM^O01", version, "ORC|CH|PON2|FON2")
        #expect(try missing(child, "ORC", 8).count == 1, "v\(version) ORM CH")
        let withParent = TestWires.wire("ORM^O01", version,
                                        TestWires.segment("ORC", [1: "CH", 2: "PON2", 3: "FON2", 8: "PON1&PL"]))
        #expect(try missing(withParent, "ORC", 8).isEmpty, "v\(version) ORM CH with parent")
    }
}
