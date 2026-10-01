// PrimitiveComponentTests.swift
// P6-13: a multi-component value in an ID or IS field. The component separator separates
// components "of data fields where allowed" (v2.5.1 section 2.5.4), and a recipient ignores
// components that were not expected (v2.5.1 / v2.8.2 section 2.6.2 a), so the primitive value
// is component 1: it is checked against the field's table, and the extras are reported.

import Testing
@testable import HL7v2Kit

@Suite("Components in primitive code fields (P6-13)")
struct PrimitiveComponentTests {

    private func tq2(_ tq210: String) -> String {
        "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||OML^O21^OML_O21|MSG00001|P|2.5.1\r"
        + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
        + "ORC|NW|A1\r"
        + "TQ1|1\r"
        + "TQ2|1|||||||||\(tq210)\r"
    }

    private func pv1(_ pv110: String) -> String {
        "MSH|^~\\&|ADT|FAC|HOSPITAL|FAC|||ADT^A01^ADT_A01|MSG00001|P|2.5.1\r"
        + "EVN|A01|20260101\r"
        + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
        + "PV1|1|I||||||||\(pv110)\r"
    }

    private func ecd(_ ecd3: String) -> String {
        "MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|20260101||EAC^U07^EAC_U07|MSG00001|P|2.8.2\r"
        + "EQU|1^EQ|20260101\r"
        + "ECD|1|LO^Load^HL70368|\(ecd3)\r"
    }

    private func issues(_ wire: String, at segmentID: String, _ field: Int,
                        options: ValidationOptions = ValidationOptions()) throws -> [ValidationIssue] {
        Validator(options: options).validate(try Parser().parse(wire)).issues
            .filter { $0.location.segmentID == segmentID && $0.location.fieldIndex == field }
    }

    private func isTable(_ issue: ValidationIssue) -> Bool {
        if case .valueNotInTable = issue.code { return true } else { return false }
    }

    private func isLength(_ issue: ValidationIssue) -> Bool {
        if case .fieldLengthOutOfRange = issue.code { return true } else { return false }
    }

    @Test("TQ2-10 RR2^SYS: component 1 is checked against Table 0506 and the extra component is reported")
    func tq2MultiComponent() throws {
        let found = try issues(tq2("RR2^SYS"), at: "TQ2", 10)
        let table = try #require(found.first(where: isTable))
        #expect(table.code == .valueNotInTable(table: "0506"))
        #expect(table.severity == .error)
        #expect(table.location.componentIndex == 1)
        #expect(table.message.contains("\"RR2\""))
        let extra = try #require(found.first { $0.code == .extraComponentsInPrimitiveField })
        #expect(extra.severity == .warning)
        #expect(extra.location.componentIndex == nil)
        #expect(extra.message.contains("SYS"))
    }

    @Test("A valid component 1 with an extra component reports only the extra component")
    func validFirstComponent() throws {
        let found = try issues(tq2("C^SYS"), at: "TQ2", 10)
        #expect(!found.contains(where: isTable))
        #expect(found.filter { $0.code == .extraComponentsInPrimitiveField }.count == 1)
    }

    @Test("An escaped component separator (\\S\\) is one component and stays silent")
    func escapedSeparatorSilent() throws {
        let found = try issues(tq2("C\\S\\"), at: "TQ2", 10)
        #expect(!found.contains { $0.code == .extraComponentsInPrimitiveField })
        // The value "C^" is one primitive value; it is not in Table 0506.
        #expect(found.contains(where: isTable))
    }

    @Test("A single-component valid code stays silent")
    func singleValidSilent() throws {
        #expect(try issues(tq2("C"), at: "TQ2", 10).isEmpty)
    }

    @Test("A subcomponent separator in a primitive field is also an extra part")
    func subcomponentExtra() throws {
        let found = try issues(tq2("RR2&SYS"), at: "TQ2", 10)
        #expect(found.contains { $0.code == .valueNotInTable(table: "0506") })
        #expect(found.contains { $0.code == .extraComponentsInPrimitiveField })
    }

    @Test("Trailing empty components are not extra content")
    func trailingEmptySilent() throws {
        let found = try issues(tq2("C^"), at: "TQ2", 10)
        #expect(!found.contains { $0.code == .extraComponentsInPrimitiveField })
        #expect(!found.contains(where: isTable))
    }

    @Test("IS field with an open user table: unknown codes stay silent on the table check")
    func isOpenTable() throws {
        #expect(try issues(pv1("XYZ"), at: "PV1", 10).isEmpty)
        let found = try issues(pv1("XYZ^ABC"), at: "PV1", 10)
        #expect(!found.contains(where: isTable))
        #expect(found.filter { $0.code == .extraComponentsInPrimitiveField }.count == 1)
    }

    @Test("v2.8.2 ECD-3 Y^YES: one extra-component warning, no table or length issue for the same cause")
    func ecdLengthNotDoubleReported() throws {
        let found = try issues(ecd("Y^YES"), at: "ECD", 3)
        #expect(found.map(\.code) == [.extraComponentsInPrimitiveField])
    }

    @Test("Component 1 that is itself too long still gets a length issue")
    func componentOneLength() throws {
        let found = try issues(ecd("YY^YES"), at: "ECD", 3)
        #expect(found.contains(where: isLength))
    }

    @Test("With the extra-component check off, length measures the whole occurrence as before")
    func offRestoresWholeLength() throws {
        var options = ValidationOptions()
        options.extraComponentsSeverity = nil
        let found = try issues(ecd("Y^YES"), at: "ECD", 3, options: options)
        #expect(!found.contains { $0.code == .extraComponentsInPrimitiveField })
        #expect(found.contains { $0.code == .fieldLengthOutOfRange(length: "1..1", actual: 5) })
    }

    @Test("Local table extensions and the HL7 null apply to component 1")
    func extensionsAndNull() throws {
        var options = ValidationOptions()
        options.localTableExtensions = ["0506": ["RR2"]]
        #expect(!(try issues(tq2("RR2^SYS"), at: "TQ2", 10, options: options)).contains(where: isTable))
        #expect(!(try issues(tq2("\"\"^SYS"), at: "TQ2", 10)).contains(where: isTable))
    }

    @Test("The lenient preset turns the extra-component check off")
    func lenientOff() throws {
        let found = try issues(tq2("C^SYS"), at: "TQ2", 10, options: .lenient)
        #expect(!found.contains { $0.code == .extraComponentsInPrimitiveField })
    }

    // P6-13 fix 1: the length is collapsed to the first value only when the extra-component
    // severity is at least the applicable length severity, so a binding length rule is
    // never hidden behind a lower-severity warning.

    @Test("v2.8.2 ECD-3 Y^YES with a binding normative length gives a length error")
    func normativeErrorNotHidden() throws {
        var options = ValidationOptions()
        options.normativeLengthSeverity = .error
        let found = try issues(ecd("Y^YES"), at: "ECD", 3, options: options)
        let length = try #require(found.first(where: isLength))
        #expect(length.code == .fieldLengthOutOfRange(length: "1..1", actual: 5))
        #expect(length.severity == .error)
        #expect(found.contains { $0.code == .extraComponentsInPrimitiveField })
    }

    @Test("Pre-v2.7 TQ2-10 C^SYS with a binding maximum length gives a length error")
    func maximumErrorNotHidden() throws {
        var options = ValidationOptions()
        options.fieldLengthSeverity = .error
        let found = try issues(tq2("C^SYS"), at: "TQ2", 10, options: options)
        let length = try #require(found.first(where: isLength))
        #expect(length.code == .fieldLengthOutOfRange(length: "1", actual: 5))
        #expect(length.severity == .error)
    }

    @Test("With default severities the pre-v2.7 case is one warning and no length issue")
    func defaultsCollapse() throws {
        let found = try issues(tq2("C^SYS"), at: "TQ2", 10)
        #expect(found.map(\.code) == [.extraComponentsInPrimitiveField])
    }

    @Test("An extra-component error at least as high as the length error still collapses")
    func equalSeverityCollapses() throws {
        var options = ValidationOptions()
        options.fieldLengthSeverity = .error
        options.extraComponentsSeverity = .error
        let found = try issues(tq2("C^SYS"), at: "TQ2", 10, options: options)
        #expect(found.map(\.code) == [.extraComponentsInPrimitiveField])
    }

    @Test("Under version substitution (MSH-12 2.7, validated as v2.5.1) a later-version CWE value in an IS field warns")
    func substitutionWarns() throws {
        let wire = pv1("ABC^Text^HL70069").replacingOccurrences(of: "|P|2.5.1\r", with: "|P|2.7\r")
        let message = try Parser().parse(wire)
        let all = Validator().validate(message).issues
        #expect(all.contains { if case .versionNotRecognised = $0.code { return true } else { return false } })
        let found = all.filter { $0.location.segmentID == "PV1" && $0.location.fieldIndex == 10 }
        #expect(found.map(\.code) == [.extraComponentsInPrimitiveField])
        #expect(found.first?.severity == .warning)
    }
}
