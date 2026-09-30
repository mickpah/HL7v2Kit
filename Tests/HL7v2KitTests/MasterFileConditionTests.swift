// MasterFileConditionTests.swift
// P4: master-file (MFE / MFA / LRL / OM7) conditionals moved out of the
// permanent-limitations register. Synthetic wires only.

import Testing
import Foundation
@testable import HL7v2Kit

private let masterFileVersions = ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.8.2"]

@Suite("Master-file conditions (P4)")
struct MasterFileConditionTests {

    private func missing(_ wire: String, _ seg: String, _ idx: Int) throws -> [ValidationIssue] {
        Validator().validate(try Parser().parse(wire)).errors.filter {
            $0.code == .conditionalFieldMissing
                && $0.location.segmentID == seg && $0.location.fieldIndex == idx
        }
    }

    @Test("MFE-2 / MFA-2 are required when MFI-6 asks for record-level responses", arguments: masterFileVersions)
    func mfnControlID(version: String) throws {
        func mfi(_ level: String) -> String { "MFI|PRA^Practitioner^HL70175||UPD|||\(level)" }
        #expect(try missing(TestWires.wire("MFN^M02", version, mfi("AL"), "MFE|MAD"), "MFE", 2).count == 1, "v\(version)")
        #expect(try missing(TestWires.wire("MFN^M02", version, mfi("NE"), "MFE|MAD"), "MFE", 2).isEmpty, "v\(version)")
        #expect(try missing(TestWires.wire("MFK^M02", version, "MSA|AA|MSG1", mfi("AL"), "MFA|MAD"), "MFA", 2).count == 1, "v\(version)")
        #expect(try missing(TestWires.wire("MFK^M02", version, "MSA|AA|MSG1", mfi("NE"), "MFA|MAD"), "MFA", 2).isEmpty, "v\(version)")
    }

    @Test("LRL-5 for organisation relationships; LRL-6 for alias or parent", arguments: masterFileVersions)
    func locationRelationship(version: String) throws {
        func lrl(_ relationship: String) -> String {
            TestWires.wire("MFN^M05", version, "MFI|LOC^Location^HL70175||UPD|||NE",
                           TestWires.segment("LRL", [1: "WARD1^101", 4: relationship]))
        }
        let pharmacy = lrl("RX^Nearest pharmacy^HL70325")
        #expect(try missing(pharmacy, "LRL", 5).count == 1, "v\(version)")
        #expect(try missing(pharmacy, "LRL", 6).isEmpty, "v\(version)")
        let parent = lrl("PAR^Parent location^HL70325")
        #expect(try missing(parent, "LRL", 6).count == 1, "v\(version)")
        #expect(try missing(parent, "LRL", 5).isEmpty, "v\(version)")
    }

    @Test("OM7-16 / OM7-18 units are required with their quantities", arguments: ["2.4", "2.5.1", "2.6", "2.8.2"])
    func om7Units(version: String) throws {
        func om7(_ fields: [Int: String]) -> String {
            TestWires.wire("MFN^M08", version, "MFI|OMA^Numerical^HL70175||UPD|||NE",
                           TestWires.segment("OM7", fields.merging([1: "1", 2: "SVC^Service"]) { current, _ in current }))
        }
        #expect(try missing(om7([15: "7"]), "OM7", 16).count == 1, "v\(version)")
        #expect(try missing(om7([17: "2"]), "OM7", 18).count == 1, "v\(version)")
        let none = om7([:])
        #expect(try missing(none, "OM7", 16).isEmpty, "v\(version)")
        #expect(try missing(none, "OM7", 18).isEmpty, "v\(version)")
    }
}
