import Testing
@testable import HL7v2Kit

/// M26 — components the spec prints as C, with the condition its prose states.
@Suite("Conditional components")
struct ConditionalComponentTests {
    private func issues(_ segments: String, version: String = "2.5.1", options: ValidationOptions = ValidationOptions()) throws -> [ValidationIssue] {
        let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01^ADT_A01|MSG00001|P|\(version)\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN\r" + segments + "\r"
        return Validator(options: options).validate(try Parser().parse(wire)).issues
            .filter { $0.code == .conditionalComponentMissing }
    }

    @Test("RPT.6 Period Units is required when RPT.5 Period Quantity is populated (v2.5.1 sec 2.A.66)")
    func rptPeriodUnits() throws {
        // TQ2-... no: RPT appears in TQ1-3 Repeat Pattern (v2.5.1).
        let bad = try issues("TQ1|1||Q1H^^^^1")           // RPT.5 = 1, RPT.6 empty
        #expect(bad.map(\.location.pathDescription) == ["TQ1[1]-3.6"])
        #expect(bad.first?.message.contains("Period Units") == true)
        #expect(try issues("TQ1|1||Q1H^^^^1^h").isEmpty)  // RPT.6 = h
        #expect(try issues("TQ1|1||Q1H").isEmpty, "the condition does not hold: RPT.5 empty")
    }

    @Test("The spec's own RPT examples are silent")
    func rptExamples() throws {
        for example in ["Q1H&Every 1 Hour&HL7xxx^^^^1^h", "Q2J2&Every second Tuesday&HL7xxx^DW^2^^2^wk",
                        "BID&Twice a day at institution specified times&HL7xxx^^^^12^h^Y",
                        "QHS&Every day before the hours of sleep&HL7xxx^^^^1^d^^AHS", "ACM&Before Breakfast&HL7xxx^^^^^^^ACM"] {
            #expect(try issues("TQ1|1||\(example)").isEmpty, Comment(rawValue: example))
        }
    }

    @Test("Disjunction: CNN.8 'either component 8, or 9, or both 10 and 11' when component 1 is valued")
    func cnnDisjunction() throws {
        // OBR-32 is NDL on v2.5.1; NDL.1 is a CNN, so its components are SUBcomponents here.
        let obr = "OBR|1|||GLU^Glucose^L" + String(repeating: "|", count: 28)   // next value lands in OBR-32
        let got = try issues(obr + "1234&Smith")
        #expect(got.map(\.location.pathDescription) == ["OBR[1]-32.1.8"], Comment(rawValue: got.map(\.message).joined(separator: " // ")))
        #expect(try issues(obr + "1234&Smith&&&&&&&AUTH").isEmpty, "CNN.9 satisfies it")
        #expect(try issues(obr + "1234&Smith&&&&&&&&1.2.3&ISO").isEmpty, "CNN.10 and 11 satisfy it")
        #expect(try issues(obr + "1234&Smith&&&&&&&&1.2.3").map(\.location.pathDescription) == ["OBR[1]-32.1.8", "OBR[1]-32.1.11"], "10 without 11 satisfies neither")
        #expect(try issues(obr + "&Smith").isEmpty, "component 1 empty: the rule does not apply")
    }

    @Test("The 'as of v2.7' family is registered, not modelled: a bare code in a v2.8.2 CWE is not an error")
    func asOfV27FamilyRegistered() throws {
        // The spec's own v2.7+ examples violate CWE.3 / CWE.14 in 529 of 549 values (conditions.json).
        #expect(DataTypeGrammarTable.grammar("CWE", version: .v2_8_2)?.component(3)?.condition == nil)
        #expect(DataTypeGrammarTable.grammar("CX", version: .v2_8_2)?.component(4)?.condition == nil)
        #expect(DataTypeGrammarTable.grammar("XTN", version: .v2_8_2)?.component(4)?.condition == nil)
        let report = Validator().validate(try Parser().parse("MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01^ADT_A01|MSG00001|P|2.8.2\rPID|1||123^^^^MR||DOE^JOHN||19800101|F\r"))
        #expect(!report.issues.contains { $0.code == .conditionalComponentMissing })
        // The value-set-version rules of the same datatypes ARE modelled: every example honours them.
        #expect(DataTypeGrammarTable.grammar("CWE", version: .v2_8_2)?.component(16)?.condition == "15 populated")
    }

    @Test("Severity follows requiredComponentSeverity, and checkComponentGrammar = false suppresses the check")
    func severityAndSwitch() throws {
        var warn = ValidationOptions(); warn.requiredComponentSeverity = .warning
        let issues = try issues("TQ1|1||Q1H^^^^1", options: warn)
        #expect(issues.count == 1 && issues.first?.severity == .warning)
        var off = ValidationOptions(); off.checkComponentGrammar = false
        #expect(try self.issues("TQ1|1||Q1H^^^^1", options: off).isEmpty)
    }

    @Test("Components printed C with no stated condition carry none")
    func unstatedStayNil() {
        #expect(DataTypeGrammarTable.grammar("XCN", version: .v2_5_1)?.component(8)?.condition == nil)
        #expect(DataTypeGrammarTable.grammar("XAD", version: .v2_8_2)?.component(7)?.condition == nil, "a repetition-count condition")
        #expect(DataTypeGrammarTable.grammar("CWE", version: .v2_8_2)?.component(7)?.condition == nil, "coding-system aware")
        #expect(DataTypeGrammarTable.grammar("XCN", version: .v2_8_2)?.component(1)?.condition == "2 empty", "'XCN.1 is required if XCN.2 is not populated'")
    }
}
