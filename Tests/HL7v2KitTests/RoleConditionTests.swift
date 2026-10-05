// RoleConditionTests.swift
// P7-2 (P10-7 intake): ROL-1 Role Instance ID on the wire. v2.4 CH12 12.4.3.1 (p. 24):
// "Conditionality Rule: This field is required when used in Patient Care messages. The
// field is optional when used in ADT and Finance messages." The Patient Care messages are
// the eight of CH12 12.3.1 to 12.3.12, every one of which carries ROL. v2.5.1 onward prints
// "Patient Care and Personnel Management messages" (CH15 15.4.7.1), so PMU differs.
// Synthetic wires only.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("ROL-1 Role Instance ID conditions (P7-2)")
struct RoleConditionTests {

    private func missing(_ wire: String) throws -> [ValidationIssue] {
        Validator().validate(try Parser().parse(wire)).errors.filter {
            $0.code == .conditionalFieldMissing
                && $0.location.segmentID == "ROL" && $0.location.fieldIndex == 1
        }
    }

    private static let bareRole = "ROL||AD|CP^Consulting Provider^HL70443|1234^Smith^John"
    private static let identifiedRole = "ROL|R1^HIS|AD|CP^Consulting Provider^HL70443|1234^Smith^John"

    @Test("v2.4: ROL-1 is required in each CH12 Patient Care message",
          arguments: ["PGL^PC6", "PPG^PCG", "PPP^PCB", "PPR^PC1", "PPT^PCL", "PPV^PCA", "PRR^PC5", "PTR^PCF"])
    func patientCareV24(messageType: String) throws {
        #expect(try missing(TestWires.wire(messageType, "2.4", Self.bareRole)).count == 1, "\(messageType)")
        #expect(try missing(TestWires.wire(messageType, "2.4", Self.identifiedRole)).isEmpty, "\(messageType)")
    }

    @Test("v2.4: ROL-1 is not required outside Patient Care messages",
          arguments: ["ADT^A01", "BAR^P01", "DFT^P03", "ESU^U01", "PMU^B01"])
    func otherMessagesV24(messageType: String) throws {
        // ADT and Finance: printed optional. ESU (CH13) and PMU: the v2.4 sentence names
        // neither, so nothing makes the field required there.
        #expect(try missing(TestWires.wire(messageType, "2.4", Self.bareRole)).isEmpty, "\(messageType)")
    }

    @Test("v2.5.1 onward also require ROL-1 in Personnel Management messages; v2.4 does not")
    func personnelManagement() throws {
        #expect(try missing(TestWires.wire("PMU^B07", "2.5.1", Self.bareRole)).count == 1)
        #expect(try missing(TestWires.wire("PMU^B07", "2.4", Self.bareRole)).isEmpty)
    }
}
