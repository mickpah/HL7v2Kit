// CompositeExtraContentTests.swift
// P6-15: a composite field repetition with more components than its datatype's component
// table defines, and a composite component with more subcomponents than its own datatype
// has components. A recipient ignores them ("present but were not expected", v2.5.1 and
// v2.8.2 section 2.6.2 a), and a later version may add components at the end of a data
// type (section 2.8.1), so the default severity is a warning.

import Testing
@testable import HL7v2Kit

@Suite("Extra components in composite fields and components (P6-15)")
struct CompositeExtraContentTests {

    private func adt(pid5: String = "DOE^JOHN", pv1: String = "PV1|1|I", version: String = "2.5.1") -> String {
        "MSH|^~\\&|ADT|FAC|HOSPITAL|FAC|20260101||ADT^A01^ADT_A01|MSG00001|P|\(version)\r"
            + "EVN|A01|20260101\r"
            + "PID|1||123^^^AUTH^MR||\(pid5)\r"
            + "\(pv1)\r"
    }

    private func obx(_ type: String, _ value: String) -> String {
        "MSH|^~\\&|ADT|FAC|HOSPITAL|FAC|20260101||ADT^A01^ADT_A01|MSG00001|P|2.5.1\r"
            + "EVN|A01|20260101\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
            + "PV1|1|I\r"
            + "OBX|1|\(type)|1^Test||\(value)||||||F\r"
    }

    private func extras(_ wire: String, at segmentID: String, _ field: Int,
                        options: ValidationOptions = ValidationOptions()) throws -> [ValidationIssue] {
        Validator(options: options).validate(try Parser().parse(wire)).issues
            .filter { $0.location.segmentID == segmentID && $0.location.fieldIndex == field }
            .filter { $0.code == .extraComponentsInCompositeField }
    }

    private static let fifteen = "DOE^JOHN^Q^JR^DR^MD^L^A^^^^^^^EXTRA"

    @Test("XPN with a populated 15th component on v2.5.1 warns at the field")
    func xpnFifteenComponents() throws {
        let found = try extras(adt(pid5: Self.fifteen), at: "PID", 5)
        #expect(found.count == 1)
        #expect(found.first?.severity == .warning)
        #expect(found.first?.location.componentIndex == nil)
        #expect(found.first?.message.contains("\"EXTRA\"") == true)
        #expect(found.first?.message.contains("14") == true)
    }

    @Test("XPN on v2.8.2 defines 15 components, so the same value is silent")
    func xpnFifteenOnV282() throws {
        #expect(try extras(adt(pid5: Self.fifteen, version: "2.8.2"), at: "PID", 5).isEmpty)
    }

    @Test("XPN on v2.3 defines 8 components: a populated 9th warns")
    func xpnNinthOnV23() throws {
        #expect(try extras(adt(pid5: "DOE^JOHN^^^^^L^A", version: "2.3"), at: "PID", 5).isEmpty)
        #expect(try extras(adt(pid5: "DOE^JOHN^^^^^L^A^X", version: "2.3"), at: "PID", 5).count == 1)
    }

    @Test("Each repetition is reported on its own")
    func perRepetition() throws {
        let found = try extras(adt(pid5: "DOE^JOHN~\(Self.fifteen)~\(Self.fifteen)"), at: "PID", 5)
        #expect(found.count == 2)
    }

    @Test("XPN with trailing empty components and escaped separators is silent")
    func trailingEmptyIsSilent() throws {
        #expect(try extras(adt(pid5: "DOE^JOHN^^^^^^^^^^^^^^^^^^"), at: "PID", 5).isEmpty)
        #expect(try extras(adt(pid5: "DOE^JOHN^^^^^^^^^^^^^&&&^^"), at: "PID", 5).isEmpty)
        #expect(try extras(adt(pid5: "DOE\\S\\X\\T\\Y^JOHN\\S\\Z"), at: "PID", 5).isEmpty)
    }

    @Test("FN in XPN.1 with a populated 6th subcomponent warns at component 1")
    func fnSubcomponentOverflow() throws {
        let found = try extras(adt(pid5: "DOE&VAN&DER&BERG&SMITH&EXTRA^JOHN"), at: "PID", 5)
        #expect(found.count == 1)
        #expect(found.first?.location.componentIndex == 1)
        #expect(found.first?.message.contains("\"EXTRA\"") == true)
        let primitive = Validator().validate(try Parser().parse(adt(pid5: "DOE&VAN&DER&BERG&SMITH&EXTRA^JOHN"))).issues
            .filter { $0.location.segmentID == "PID" && $0.location.fieldIndex == 5 }
            .filter { $0.code == .extraComponentsInPrimitiveField }
        #expect(primitive.isEmpty)
        #expect(try extras(adt(pid5: "DOE&VAN&DER&BERG&SMITH&&^JOHN"), at: "PID", 5).isEmpty)
    }

    @Test("HD in CX.4 with a populated 4th subcomponent warns at component 4")
    func hdInCx() throws {
        let wire = adt().replacingOccurrences(of: "123^^^AUTH^MR", with: "123^^^AUTH&1.2.3&ISO&X^MR")
        let found = try extras(wire, at: "PID", 3)
        #expect(found.count == 1)
        #expect(found.first?.location.componentIndex == 4)
    }

    @Test("OBX-5 varies with no OBX-2 is silent")
    func variesIsSilent() throws {
        #expect(try extras(obx("", "a^b^c^d^e^f^g^h^i^j^k^l^m^n^o^p"), at: "OBX", 5).isEmpty)
    }

    @Test("OBX-5 declared CE takes the CE table: a 7th component warns")
    func obx5DeclaredCE() throws {
        #expect(try extras(obx("CE", "a^b^c^d^e^f"), at: "OBX", 5).isEmpty)
        #expect(try extras(obx("CE", "a^b^c^d^e^f^g"), at: "OBX", 5).count == 1)
    }

    @Test("Open-ended arrays NA and MA are silent at any width")
    func openArraysAreSilent() throws {
        #expect(try extras(obx("NA", "125^34^-22^-234^569^442^-212^6"), at: "OBX", 5).isEmpty)
        #expect(try extras(obx("MA", "0^0^0^0^0^0^0^0~1^1^1^1^1^1^1^1"), at: "OBX", 5).isEmpty)
    }

    @Test("A v2.3 CM field (PV1-37) has no component table and is silent")
    func cmOnV23IsSilent() throws {
        let pv1 = "PV1|1|I" + String(repeating: "|", count: 35) + "a^b^c^d^e^f^g^h"
        #expect(try extras(adt(pv1: pv1, version: "2.3"), at: "PV1", 37).isEmpty)
    }

    @Test(".lenient turns the check off")
    func lenientIsSilent() throws {
        #expect(try extras(adt(pid5: Self.fifteen), at: "PID", 5, options: .lenient).isEmpty)
        #expect(try extras(adt(pid5: "DOE&VAN&DER&BERG&SMITH&EXTRA^JOHN"), at: "PID", 5,
                           options: .lenient).isEmpty)
    }

    @Test("extraComponentsSeverity sets the severity")
    func severityFollowsOption() throws {
        var options = ValidationOptions()
        options.extraComponentsSeverity = .error
        #expect(try extras(adt(pid5: Self.fifteen), at: "PID", 5, options: options).first?.severity == .error)
    }
}
