// VersionIDConditionTests.swift
// Coding-system version ID task 2: the 18 opt-in rules that require a version ID when the
// coding system is not an HL7 table (or, in the newer wording, names a user-defined one),
// v2.5.1 to v2.8.2. CNE keeps the older usage note in every version.

import Testing
@testable import HL7v2Kit

@Suite("Coding-system version ID")
struct VersionIDConditionTests {
    static func newer(_ s: Int) -> String { "\(s) populated AND (NOT \(s) hl7Table OR \(s) userTable)" }
    static func older(_ s: Int) -> String { "\(s) populated AND NOT \(s) hl7Table" }

    /// Every rule position: (version, datatype, component, condition).
    static let rules: [(Version, String, Int, String)] = [
        (.v2_5_1, "CNE", 7, older(3)), (.v2_5_1, "CWE", 7, older(3)),
        (.v2_6, "CNE", 7, older(3)), (.v2_6, "CWE", 7, newer(3)),
    ] + [Version.v2_7_1, .v2_8_2].flatMap { v -> [(Version, String, Int, String)] in
        [(v, "CF", 7, newer(3)), (v, "CNE", 7, older(3)), (v, "CWE", 7, newer(3)), (v, "CSU", 8, newer(4)),
         (v, "CF", 13, newer(12)), (v, "CNE", 13, older(12)), (v, "CSU", 14, newer(13))]
    }

    @Test("The 18 positions carry their condition in the opt-in tier, and nothing else changes")
    func coverage() {
        #expect(Self.rules.count == 18)
        for (version, type, index, condition) in Self.rules {
            let component = DataTypeGrammarTable.grammar(type, version: version)?.component(index)
            #expect(component?.conformanceCondition == condition, "\(type).\(index) \(version)")
            #expect(component?.condition == nil, "\(type).\(index) \(version)")
            #expect(ComponentCondition.parses(condition))
        }
        for (version, type, index) in [(Version.v2_7_1, "CWE", 13), (.v2_8_2, "CWE", 13), (.v2_5_1, "CWE", 8), (.v2_8_2, "CNE", 8)] {
            #expect(DataTypeGrammarTable.grammar(type, version: version)?.component(index)?.conformanceCondition == nil)
        }
    }

    static func table(_ kind: HL7Table.Kind, _ version: Version) -> String {
        HL7TableRegistry.tables(for: version).values.filter { $0.kind == kind }.map(\.number).sorted().first!
    }

    static func versionIDIssues(_ segments: String, version: String, severity: IssueSeverity? = .warning) throws -> [ValidationIssue] {
        var options = ValidationOptions()
        options.conformanceConditionSeverity = severity
        let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01^ADT_A01|MSG00001|P|\(version)\r" + segments + "\r"
        return Validator(options: options).validate(try Parser().parse(wire)).issues
            .filter { $0.code == .conformanceConditionMissing }
    }

    @Test("v2.7.1 CWE (PID-8): a non-HL7 coding system needs .7; an HL7 table does not; a user table does")
    func cweNewerWording() throws {
        let user = Self.table(.userDefined, .v2_7_1), hl7 = Self.table(.hl7, .v2_7_1)
        func at7(_ pid8: String) throws -> [String] {
            try Self.versionIDIssues("PID|1||1^^^H^MR||DOE^J|||\(pid8)", version: "2.7.1")
                .filter { $0.location.fieldIndex == 8 && $0.location.componentIndex == 7 }.map(\.location.pathDescription)
        }
        #expect(try at7("F^Female^LN") == ["PID[1]-8.7"])
        #expect(try at7("F^Female^HL7\(user)") == ["PID[1]-8.7"])
        #expect(try at7("F^Female^HL7\(hl7)").isEmpty)
        #expect(try at7("F^Female^HL79999").isEmpty)
        #expect(try at7("F^Female").isEmpty)
        #expect(try at7("F^Female^LN^^^^2.0").isEmpty)
    }

    @Test("v2.5.1 CWE (PID-39), older wording: a user-defined HL7 table does not need .7")
    func cweOlderWording() throws {
        let user = Self.table(.userDefined, .v2_5_1)
        func at7(_ pid39: String) throws -> Bool {
            try Self.versionIDIssues("PID|1||1^^^H^MR||DOE^J" + String(repeating: "|", count: 34) + pid39, version: "2.5.1")
                .contains { $0.location.fieldIndex == 39 && $0.location.componentIndex == 7 }
        }
        #expect(try at7("T1^Tribe^LN"))
        #expect(try !at7("T1^Tribe^HL7\(user)"))
    }

    @Test("Off by default and in every preset")
    func offByDefault() throws {
        for options in [ValidationOptions(), .strict, .lenient] {
            let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01^ADT_A01|M1|P|2.7.1\rPID|1||1^^^H^MR||DOE^J|||F^Female^LN\r"
            #expect(!Validator(options: options).validate(try Parser().parse(wire)).issues
                .contains { $0.code == .conformanceConditionMissing && $0.location.componentIndex == 7 })
        }
    }

    @Test("A nested CWE (OBR-9 CQ.2 on v2.7.1) is checked one level down")
    func nestedCWE() throws {
        let issues = try Self.versionIDIssues("PID|1||1^^^H^MR||DOE^J\rOBR|1||||||||10^ml&millilitre&LN", version: "2.7.1")
        #expect(issues.contains { $0.location.fieldIndex == 9 && $0.location.componentIndex == 2 && $0.location.subcomponentIndex == 7 })
    }

    @Test("CF, CSU and CNE rules evaluate as written (no v2.7.1 or v2.8.2 field carries CF or CSU)")
    func atTheGrammar() {
        let user = Self.table(.userDefined, .v2_8_2)
        let kind = { (n: String) in HL7TableRegistry.table(n, version: .v2_8_2)?.kind }
        // (type, version ID, coding system, a user-defined HL7 table needs a version ID)
        for (type, index, system, userNeeds) in [("CF", 7, 3, true), ("CF", 13, 12, true), ("CSU", 8, 4, true),
                                                 ("CSU", 14, 13, true), ("CNE", 7, 3, false), ("CNE", 13, 12, false)] {
            let condition = DataTypeGrammarTable.grammar(type, version: .v2_8_2)?.component(index)?.conformanceCondition ?? ""
            for (value, expected) in [("LN", true), ("HL7\(user)", userNeeds), ("", false)] {
                let held = ComponentCondition.holds(condition, populated: { $0 == system && !value.isEmpty },
                                                    value: { $0 == system ? value : nil }, tableKind: kind)
                #expect(held == expected, "\(type).\(index) with \(system) = \(value)")
            }
        }
    }
}
