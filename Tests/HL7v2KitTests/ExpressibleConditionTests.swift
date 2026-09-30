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
}
