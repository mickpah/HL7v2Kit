import Testing
@testable import HL7v2Kit

/// M21 — the severity of a missing required component is the consumer's choice.
@Suite("Required-component severity option")
struct ComponentSeverityTests {
    private let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01|MSG00001|P|2.5.1\r"
        + "PID|1||^^^HOSP^MR||DOE^JOHN\r"   // MSH-9.3 empty AND PID-3.1 empty: two required components

    private func report(_ options: ValidationOptions) throws -> ValidationReport {
        Validator(options: options).validate(try Parser().parse(wire))
    }

    @Test("Default: a missing required component is an error and the message is invalid")
    func defaultIsError() throws {
        let r = try report(ValidationOptions())
        let missing = r.issues.filter { $0.code == .requiredComponentMissing }
        #expect(missing.count == 2)
        #expect(missing.allSatisfy { $0.severity == .error })
        #expect(!r.isValid)
        #expect(ValidationOptions().requiredComponentSeverity == .error)
    }

    @Test("requiredComponentSeverity = .warning keeps the findings and makes the message valid")
    func warningKeepsFindings() throws {
        var options = ValidationOptions()
        options.requiredComponentSeverity = .warning
        let r = try report(options)
        let missing = r.issues.filter { $0.code == .requiredComponentMissing }
        #expect(missing.map(\.location.pathDescription) == ["MSH[1]-9.3", "PID[1]-3.1"])
        #expect(missing.allSatisfy { $0.severity == .warning })
        #expect(r.isValid, "no error-severity issue remains")
    }

    @Test("The option covers the either-or rule too (HD), and nothing else")
    func scope() throws {
        var options = ValidationOptions()
        options.requiredComponentSeverity = .warning
        let hd = "MSH|^~\\&|HIS|LAB1^1.2.3|HOSPITAL|FAC|20240101120000||ADT^A01^ADT_A01|MSG00001|P|2.5.1\rPID|1||123^^^HOSP^MR||DOE^JOHN\r"
        let r = Validator(options: options).validate(try Parser().parse(hd))
        let hdIssue = try #require(r.issues.first { $0.code == .requiredComponentMissing && $0.location.fieldIndex == 4 })
        #expect(hdIssue.severity == .warning)
        // A missing required FIELD is untouched by this option.
        let noPid5 = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01^ADT_A01|MSG00001|P|2.5.1\rPID|1||123^^^HOSP^MR\r"
        let r2 = Validator(options: options).validate(try Parser().parse(noPid5))
        #expect(r2.issues.contains { $0.code == .requiredFieldMissing && $0.severity == .error })
    }

    @Test("checkComponentGrammar = false still suppresses the findings entirely")
    func offStillOff() throws {
        var options = ValidationOptions()
        options.checkComponentGrammar = false
        options.requiredComponentSeverity = .warning
        #expect(try !report(options).issues.contains { $0.code == .requiredComponentMissing })
    }
}
