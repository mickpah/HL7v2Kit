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
        // P10-8: v2.4 (CH07 7.14.1.1 prose line) and v2.7.1 (2.A.45) print four NA values
        // and an ellipsis; the stored four entries are not a maximum on either.
        for version in ["2.4", "2.7.1"] {
            let wire = obx("NA", "125^34^-22^-234^569^442^-212^6")
                .replacingOccurrences(of: "|P|2.5.1\r", with: "|P|\(version)\r")
            #expect(try extras(wire, at: "OBX", 5).isEmpty, "v\(version)")
        }
    }

    @Test("A v2.3 CM field (PV1-37) is bounded by the two components its field definition prints (P5-6)")
    func cmOnV23IsFieldLocal() throws {
        let pv1 = "PV1|1|I" + String(repeating: "|", count: 35) + "a^b^c^d^e^f^g^h"
        #expect(try extras(adt(pv1: pv1, version: "2.3"), at: "PV1", 37).count == 1)
        let two = "PV1|1|I" + String(repeating: "|", count: 35) + "a^19990101"
        #expect(try extras(adt(pv1: two, version: "2.3"), at: "PV1", 37).isEmpty)
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

    @Test("P5-2: CD and CF on v2.3 to v2.4 take their six-component printed line: a 7th warns")
    func cdCfPreV25Width() throws {
        for version in ["2.3", "2.3.1", "2.4"] {
            for type in ["CD", "CF"] {
                let six = obx(type, "a^b^c^d^1^f").replacingOccurrences(of: "|P|2.5.1\r", with: "|P|\(version)\r")
                let seven = obx(type, "a^b^c^d^1^f^g").replacingOccurrences(of: "|P|2.5.1\r", with: "|P|\(version)\r")
                #expect(try extras(six, at: "OBX", 5).isEmpty, "\(version) \(type)")
                #expect(try extras(seven, at: "OBX", 5).count == 1, "\(version) \(type)")
            }
        }
    }

    // P5-3: TQ on v2.3 to v2.4 takes its CH4 component headings (v2.3 4.4.1-4.4.10, v2.3.1
    // 4.4.1-4.4.12, v2.4 4.3.1-4.3.12). No TQ component is open-ended, so the width is fixed.
    @Test("P5-3: TQ (ORC-7) on v2.3 to v2.4 takes its CH4 width: one more populated component warns")
    func tqPreV25Width() throws {
        for (version, width) in [("2.3", 10), ("2.3.1", 12), ("2.4", 12)] {
            func orc(_ tq: String) -> String {
                "MSH|^~\\&|A|B|C|D|20260101||ORM^O01|M1|P|\(version)\rORC|NW|1|||||\(tq)\r"
            }
            let full = (1...width).map { $0 == 1 ? "1" : $0 == 4 ? "19991231" : "" }.joined(separator: "^")
            #expect(try extras(orc(full + "Z"), at: "ORC", 7).isEmpty, "\(version)")
            #expect(try extras(orc(full + "^Z"), at: "ORC", 7).count == 1, "\(version)")
        }
    }

    // TQ.1 Quantity (CQ): "When units are required, they can be added, specified by a
    // subcomponent delimiter" (v2.3 / v2.3.1 4.4.1, v2.4 4.3.1); TQ.4 Start date/time (TS)
    // carries its degree of precision as a subcomponent.
    @Test("P5-3: the CQ units and TS precision subcomponents inside TQ are silent")
    func tqSubcomponentsAreSanctioned() throws {
        for version in ["2.3", "2.3.1", "2.4"] {
            let wire = "MSH|^~\\&|A|B|C|D|20260101||ORM^O01|M1|P|\(version)\r"
                + "ORC|NW|1|||||1&ML^Q1H^X3^19991231&D^20000101&D^S\r"
            let found = Validator().validate(try Parser().parse(wire)).issues.filter {
                $0.location.segmentID == "ORC" && $0.location.fieldIndex == 7
            }
            #expect(found.isEmpty, "\(version): \(found.map(\.message))")
        }
    }

    // P7-5: the extension rule is cited by version, as the recipient rule is. v2.3 to v2.4
    // print only the version compatibility rule c ("new components may be added at the end
    // of a field": v2.3 and v2.3.1 section 2.10.2, p. 2-58 and p. 2-70; v2.4 section 2.11.2,
    // p. 2-88) and no local extension clause. From v2.5.1, section 2.8.1 ("New components may
    // be added at the end of a data type", rule h from v2.6) and section 2.11.5 c ("Data types
    // may be locally extended by adding new components at the end").
    @Test("The extension rule cited names each version's own sections (P7-5)")
    func extensionRuleCitedPerVersion() {
        let expected: [(Version, String)] = [
            (.v2_3, "a later version may add components at the end of a field (v2.3 section 2.10.2 c)"),
            (.v2_3_1, "a later version may add components at the end of a field (v2.3.1 section 2.10.2 c)"),
            (.v2_4, "a later version may add components at the end of a field (v2.4 section 2.11.2 c)"),
            (.v2_5_1, "a later version or a local extension may add components at the end of a data type (v2.5.1 sections 2.8.1 and 2.11.5 c)"),
            (.v2_6, "a later version or a local extension may add components at the end of a data type (v2.6 sections 2.8.1 h and 2.11.5 c)"),
            (.v2_7_1, "a later version or a local extension may add components at the end of a data type (v2.7.1 sections 2.8.1 h and 2.11.5 c)"),
            (.v2_8_2, "a later version or a local extension may add components at the end of a data type (v2.8.2 sections 2.8.1 h and 2.11.5 c)"),
        ]
        for (version, clause) in expected {
            #expect(Validator.componentExtensionRule(version) == clause, "\(version)")
        }
    }

    @Test("The composite warning carries the versioned extension rule (P7-5)")
    func compositeMessageCitesVersionedRule() throws {
        let v251 = try extras(adt(pid5: Self.fifteen), at: "PID", 5).first?.message ?? ""
        #expect(v251.contains("(v2.5.1 sections 2.8.1 and 2.11.5 c)"))
        let v23 = try extras(adt(pid5: "DOE^JOHN^^^^^L^A^X", version: "2.3"), at: "PID", 5).first?.message ?? ""
        #expect(v23.contains("(v2.3 section 2.10.2 c)"))
        #expect(!v23.contains("local extension"))
    }
}
