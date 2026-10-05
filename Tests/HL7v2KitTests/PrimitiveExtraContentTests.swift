// PrimitiveExtraContentTests.swift
// P6-14: content after the value of any primitive field (not only ID / IS), extra
// subcomponents in a primitive component, and the component code-table check on the
// first subcomponent. The component separator separates "components of data fields where
// allowed" (v2.5.1 and v2.8.2 section 2.5.4); a primitive allows none, except
// the TS degree of precision on v2.3 to v2.4 and the FT line marker (section 2.7.6 /
// 2.9.6 / 2.10.6: "The component separator that marks each line").

import Testing
@testable import HL7v2Kit

@Suite("Extra content in every primitive field and component (P6-14)")
struct PrimitiveExtraContentTests {

    private func pid(_ index: Int, _ value: String, version: String = "2.5.1") -> String {
        var fields = Array(repeating: "", count: max(index, 5) + 1)
        fields[1] = "1"
        fields[3] = "123^^^AUTH^MR"
        fields[5] = "DOE^JOHN"
        fields[index] = value
        return "MSH|^~\\&|ADT|FAC|HOSPITAL|FAC|20260101||ADT^A01^ADT_A01|MSG00001|P|\(version)\r"
            + "EVN|A01|20260101\r"
            + "PID" + fields.dropFirst().reduce("") { $0 + "|" + $1 } + "\r"
            + "PV1|1|I\r"
    }

    private func pv1(_ index: Int, _ value: String, version: String = "2.5.1") -> String {
        var fields = Array(repeating: "", count: max(index, 2) + 1)
        fields[1] = "1"
        fields[2] = "I"
        fields[index] = value
        return "MSH|^~\\&|ADT|FAC|HOSPITAL|FAC|20260101||ADT^A01^ADT_A01|MSG00001|P|\(version)\r"
            + "EVN|A01|20260101\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
            + "PV1" + fields.dropFirst().reduce("") { $0 + "|" + $1 } + "\r"
    }

    private func obx(_ type: String, _ value: String) -> String {
        "MSH|^~\\&|ADT|FAC|HOSPITAL|FAC|20260101||ADT^A01^ADT_A01|MSG00001|P|2.5.1\r"
            + "EVN|A01|20260101\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
            + "PV1|1|I\r"
            + "OBX|1|\(type)|1^Test||\(value)||||||F\r"
    }

    private func issues(_ wire: String, at segmentID: String, _ field: Int,
                        options: ValidationOptions = ValidationOptions()) throws -> [ValidationIssue] {
        Validator(options: options).validate(try Parser().parse(wire)).issues
            .filter { $0.location.segmentID == segmentID && $0.location.fieldIndex == field }
    }

    private func extras(_ found: [ValidationIssue]) -> [ValidationIssue] {
        found.filter { $0.code == .extraComponentsInPrimitiveField }
    }

    private func isTable(_ issue: ValidationIssue) -> Bool {
        if case .valueNotInTable = issue.code { return true } else { return false }
    }

    private func isFormat(_ issue: ValidationIssue) -> Bool {
        if case .valueFormatInvalid = issue.code { return true } else { return false }
    }

    // MARK: Field level

    @Test("ST field PID-19 a^b reports the extra component")
    func stField() throws {
        let found = extras(try issues(pid(19, "a^b"), at: "PID", 19))
        #expect(found.count == 1)
        #expect(found.first?.severity == .warning)
        #expect(found.first?.location.componentIndex == nil)
        #expect(found.first?.message.contains("\"b\"") == true)
    }

    @Test("DT field PV1-25 20260101^x reports the extra component and no format issue")
    func dtField() throws {
        let found = try issues(pv1(25, "20260101^x"), at: "PV1", 25)
        #expect(extras(found).count == 1)
        #expect(!found.contains(where: isFormat))
    }

    @Test("NM fields 1^2 and 12^abc report the extra component (P6-7 limitation closed)")
    func nmField() throws {
        #expect(extras(try issues(pv1(26, "1^2"), at: "PV1", 26)).count == 1)
        let found = try issues(pv1(26, "12^abc"), at: "PV1", 26)
        #expect(extras(found).count == 1)
        #expect(extras(found).first?.message.contains("abc") == true)
    }

    @Test("A subcomponent in an SI field is extra content")
    func siSubcomponent() throws {
        #expect(extras(try issues(pv1(1, "1&2"), at: "PV1", 1)).count == 1)
    }

    @Test("An escaped component separator \\S\\ in an ST field is silent")
    func escapedComponentSilent() throws {
        #expect(extras(try issues(pid(19, "a\\S\\b"), at: "PID", 19)).isEmpty)
    }

    @Test("Trailing empty components on an ST field are silent")
    func trailingEmptySilent() throws {
        #expect(extras(try issues(pid(19, "abc^^"), at: "PID", 19)).isEmpty)
    }

    @Test("TS on v2.3 carries a degree-of-precision component: 20260101^D is silent, a third component is extra")
    func tsVersion23() throws {
        #expect(extras(try issues(pv1(44, "20260101^D", version: "2.3"), at: "PV1", 44)).isEmpty)
        let found = extras(try issues(pv1(44, "20260101^D^x", version: "2.3"), at: "PV1", 44))
        #expect(found.count == 1)
        #expect(found.first?.message.contains("\"x\"") == true)
        #expect(extras(try issues(pv1(44, "20260101&x", version: "2.3"), at: "PV1", 44)).count == 1)
    }

    @Test("TS on v2.5.1 is a composite (TS.1 DTM, TS.2 ID): 20260101^D is silent here")
    func tsVersion251() throws {
        #expect(extras(try issues(pv1(44, "20260101^D"), at: "PV1", 44)).isEmpty)
    }

    @Test("FT allows the component separator as a line marker; TX does not")
    func ftAndTx() throws {
        #expect(extras(try issues(obx("FT", "line one^line two"), at: "OBX", 5)).isEmpty)
        #expect(extras(try issues(obx("FT", "a&b"), at: "OBX", 5)).count == 1)
        #expect(extras(try issues(obx("TX", "a^b"), at: "OBX", 5)).count == 1)
        #expect(extras(try issues(obx("TX", "a\\S\\b \\.br\\ c"), at: "OBX", 5)).isEmpty)
    }

    @Test("Length of an ST field with extras measures the first value while the warning is at least as severe")
    func lengthCollapse() throws {
        var options = ValidationOptions()
        options.fieldLengthSeverity = .warning
        let long = String(repeating: "x", count: 20)
        // PID-19 LEN 16: "abc^" + 20 x's is 24 long, the first value 3.
        let found = try issues(pid(19, "abc^\(long)"), at: "PID", 19, options: options)
        #expect(extras(found).count == 1)
        #expect(!found.contains { if case .fieldLengthOutOfRange = $0.code { return true } else { return false } })
    }

    @Test("The primitive list follows each version's CH02")
    func primitiveList() {
        #expect(Validator.primitiveComponentLimit("ST", version: .v2_5_1) == 1)
        #expect(Validator.primitiveComponentLimit("GTS", version: .v2_5_1) == 1)
        #expect(Validator.primitiveComponentLimit("DTM", version: .v2_3) == nil)
        #expect(Validator.primitiveComponentLimit("TS", version: .v2_3) == 2)
        #expect(Validator.primitiveComponentLimit("TS", version: .v2_4) == 2)
        #expect(Validator.primitiveComponentLimit("TS", version: .v2_5_1) == nil)
        #expect(Validator.primitiveComponentLimit("TN", version: .v2_3_1) == 1)
        #expect(Validator.primitiveComponentLimit("SNM", version: .v2_8_2) == 1)
        #expect(Validator.primitiveComponentLimit("SNM", version: .v2_8) == 1)
        #expect(Validator.primitiveComponentLimit("SNM", version: .v2_7_1) == 1)
        #expect(Validator.primitiveComponentLimit("SNM", version: .v2_7) == 1)
        #expect(Validator.primitiveComponentLimit("FT", version: .v2_6) == .max)
        #expect(Validator.primitiveComponentLimit("NA", version: .v2_3) == nil)
        #expect(Validator.primitiveComponentLimit("CM", version: .v2_3) == nil)
        #expect(Validator.primitiveComponentLimit("XPN", version: .v2_5_1) == nil)
    }

    // MARK: Component level

    @Test("An ST component with a subcomponent (CX.1 12&3) is reported at the component")
    func stComponent() throws {
        let found = extras(try issues(pid(3, "12&3^^^AUTH^MR"), at: "PID", 3))
        #expect(found.count == 1)
        #expect(found.first?.location.componentIndex == 1)
        #expect(found.first?.location.subcomponentIndex == nil)
    }

    @Test("OBX-3.1 carries an observation ID suffix (71020&IMP, CH07): one suffix is silent, a second is extra")
    func observationSuffix() throws {
        #expect(extras(try issues(obx("ST", "x").replacingOccurrences(of: "1^Test", with: "71020&IMP^Impression^C4"),
                                  at: "OBX", 3)).isEmpty)
        let found = extras(try issues(obx("ST", "x").replacingOccurrences(of: "1^Test", with: "71020&IMP&X^Impression^C4"),
                                      at: "OBX", 3))
        #expect(found.count == 1)
        #expect(found.first?.location.componentIndex == 1)
    }

    @Test("An escaped subcomponent separator \\T\\ in a component is silent")
    func escapedSubcomponentSilent() throws {
        #expect(extras(try issues(pid(3, "12\\T\\3^^^AUTH^MR"), at: "PID", 3)).isEmpty)
    }

    @Test("An ID component Q&B: the first subcomponent is table-checked at the subcomponent, the rest reported")
    func idComponentInvalid() throws {
        let found = try issues(pid(5, "DOE^JOHN^^^^^Q&B"), at: "PID", 5)
        let table = try #require(found.first(where: isTable))
        #expect(table.location.componentIndex == 7)
        #expect(table.location.subcomponentIndex == 1)
        #expect(table.message.contains("\"Q\""))
        let extra = extras(found)
        #expect(extra.count == 1)
        #expect(extra.first?.location.componentIndex == 7)
    }

    @Test("An ID component L&B: valid first subcomponent, only the extra is reported")
    func idComponentValid() throws {
        let found = try issues(pid(5, "DOE^JOHN^^^^^L&B"), at: "PID", 5)
        #expect(!found.contains(where: isTable))
        #expect(extras(found).count == 1)
    }

    @Test("A plain invalid ID component keeps its component-level location")
    func idComponentPlain() throws {
        let table = try #require(try issues(pid(5, "DOE^JOHN^^^^^Q"), at: "PID", 5).first(where: isTable))
        #expect(table.location.componentIndex == 7)
        #expect(table.location.subcomponentIndex == nil)
    }

    // MARK: Fix round 1

    private func withVersion(_ wire: String, _ version: String) -> String {
        wire.replacingOccurrences(of: "|P|2.5.1\r", with: "|P|\(version)\r")
    }

    @Test("QIP.2 carries a subcomponent list (<value1 & value2 & ...>): SPR-4 and ERQ-3 stay silent")
    func qipValueList() throws {
        for version in ["2.3", "2.4", "2.5.1"] {
            let spr = "MSH|^~\\&|A|F|B|F|20260101||SPQ^Q08|M1|P|\(version)\r"
                + "SPR|Q1|T|SEL|@PID.3^123&456\r"
            #expect(extras(try issues(spr, at: "SPR", 4)).isEmpty, "SPR-4 v\(version)")
            let erq = "MSH|^~\\&|A|F|B|F|20260101||ERP^R09|M1|P|\(version)\r"
                + "ERQ|Q1|EVT|@PID.3^123&456\r"
            #expect(extras(try issues(erq, at: "ERQ", 3)).isEmpty, "ERQ-3 v\(version)")
        }
    }

    @Test("A raw & inside an FT component of a CF (CF.2) warns: line markers are field-level only")
    func ftComponent() throws {
        let found = extras(try issues(obx("CF", "C1^line a&line b^L"), at: "OBX", 5))
        #expect(found.count == 1)
        #expect(found.first?.location.componentIndex == 2)
        #expect(extras(try issues(withVersion(obx("CF", "C1^line a&line b^L"), "2.8.2"), at: "OBX", 5)).count == 1)
    }

    @Test("The observation ID suffix applies to the alternate identifier OBX-3.4 and v2.8.2 CWE.10")
    func suffixOnAlternateIdentifiers() throws {
        let alt = obx("ST", "x").replacingOccurrences(of: "1^Test", with: "71020^Chest^C4^X1&IMP^Alt^99L")
        #expect(extras(try issues(alt, at: "OBX", 3)).isEmpty)
        let second = withVersion(obx("ST", "x").replacingOccurrences(
            of: "1^Test", with: "71020^Chest^C4^^^^^^^X1&IMP"), "2.8.2")
        #expect(extras(try issues(second, at: "OBX", 3)).isEmpty)
        let twice = obx("ST", "x").replacingOccurrences(of: "1^Test", with: "71020^Chest^C4^X1&IMP&Z^Alt^99L")
        #expect(extras(try issues(twice, at: "OBX", 3)).count == 1)
    }

    @Test("With the extra-component check off, component extras are silent")
    func componentCheckOff() throws {
        var options = ValidationOptions()
        options.extraComponentsSeverity = nil
        #expect(extras(try issues(pid(3, "12&3^^^AUTH^MR"), at: "PID", 3, options: options)).isEmpty)
    }

    @Test("A 2.8 message runs the component table check (validated as v2.8.2)")
    func version28ComponentTables() throws {
        let found = try issues(pid(5, "DOE^JOHN^^^^^Q", version: "2.8"), at: "PID", 5)
        let table = try #require(found.first(where: isTable))
        #expect(table.location.componentIndex == 7)
    }

    // MARK: P5-2

    @Test("P5-2: TS on v2.3 to v2.4 has a grammar but is still walked as a primitive")
    func componentGrammarHelper() {
        for version in [Version.v2_3, .v2_3_1, .v2_4] {
            #expect(DataTypeGrammarTable.grammar("TS", version: version)?.components.count == 2)
            #expect(Validator.componentGrammar("TS", version: version) == nil)
            #expect(Validator.closedComposite("TS", version: version) == nil)
            #expect(Validator.componentGrammar("CF", version: version)?.components.count == 6)
            #expect(Validator.closedComposite("CD", version: version)?.components.count == 6)
        }
        #expect(Validator.componentGrammar("TS", version: .v2_5_1)?.components.count == 2)
        #expect(Validator.componentGrammar("ST", version: .v2_5_1) == nil)
    }

    @Test("P5-2: a three-component TS on v2.3 to v2.4 PID-7 is reported once, as primitive content")
    func tsThreeComponentsOnce() throws {
        for version in ["2.3", "2.3.1", "2.4"] {
            let found = try issues(pid(7, "19990101^D^x", version: version), at: "PID", 7)
            #expect(found.filter { $0.code == .extraComponentsInPrimitiveField }.count == 1, "\(version)")
            #expect(found.filter { $0.code == .extraComponentsInCompositeField }.isEmpty, "\(version)")
            #expect(try issues(pid(7, "19990101^D", version: version), at: "PID", 7).isEmpty, "\(version)")
        }
    }

    @Test("P5-2: a raw & inside CF.2 (FT) on v2.3 to v2.4 warns at component 2")
    func ftComponentPreV25() throws {
        for version in ["2.3", "2.3.1", "2.4"] {
            let found = extras(try issues(withVersion(obx("CF", "C1^line a&line b^L"), version), at: "OBX", 5))
            #expect(found.count == 1, "\(version)")
            #expect(found.first?.location.componentIndex == 2, "\(version)")
        }
    }
}
