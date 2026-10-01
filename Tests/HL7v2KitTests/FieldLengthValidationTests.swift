// FieldLengthValidationTests.swift
// P6-6 (V231-C15): LEN is checked. Pre-v2.7 maximum lengths are site-negotiable
// (v2.5.1 §2.5.3.2); v2.7+ normative lengths are binding (v2.8.2 §2.5.5.0). Both are
// reported as warnings by default (owner gate G4) and switched off with nil.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Field length")
struct FieldLengthValidationTests {

    func lengthIssues(_ wire: String, _ options: ValidationOptions = .default) throws -> [ValidationIssue] {
        try Validator(options: options).validate(Parser().parse(wire)).issues.filter {
            if case .fieldLengthOutOfRange = $0.code { return true } else { return false }
        }
    }

    func msh231(controlID: String = "M1") -> String {
        "MSH|^~\\&|A|B|C|D|20240101120000||ADT^A01|\(controlID)|P|2.3.1\r"
    }

    let msh282 = "MSH|^~\\&|A|B|C|D|20240101120000||ADT^A01^ADT_A01|M1|P|2.8.2\r"

    // MARK: - LEN cell grammar

    @Test("PrintedLength reads every printed LEN / C.LEN form")
    func printedForms() {
        #expect(PrintedLength("20") == .number(20))
        #expect(PrintedLength("64K") == .kilo(64))
        #expect(PrintedLength("64k") == .kilo(64))
        #expect(PrintedLength("*") == .variable)
        #expect(PrintedLength("1..4") == .range(min: 1, max: 4))
        #expect(PrintedLength("2..") == .range(min: 2, max: nil))
        #expect(PrintedLength("2,4") == .list([2, 4]))
        #expect(PrintedLength("40=") == .conformance(40, truncatable: false))
        #expect(PrintedLength("250#") == .conformance(250, truncatable: true))
    }

    @Test("PrintedLength rejects malformed cells", arguments: [
        "", " ", "0", "007", "655362", "=", "#", "0..4", "4..2", "..4", "1...4", "1,", ",2",
        "1,,2", "0,2", "12x", "K", "0K", "abc", "1..4=", "-1",
    ])
    func malformed(_ cell: String) {
        #expect(PrintedLength(cell) == nil, "\(cell) must not parse")
    }

    @Test("FieldLengthRule reads each era's LEN cell")
    func parse() {
        #expect(FieldLengthRule.parse("20", version: .v2_3_1) == .maximum(20))
        #expect(FieldLengthRule.parse("64k", version: .v2_5_1) == nil)
        #expect(FieldLengthRule.parse("*", version: .v2_5_1) == nil)
        #expect(FieldLengthRule.parse("1..4", version: .v2_8_2) == .range(min: 1, max: 4))
        #expect(FieldLengthRule.parse("1..", version: .v2_8_2) == .range(min: 1, max: nil))
        #expect(FieldLengthRule.parse("2,4", version: .v2_8_2) == .oneOf([2, 4]))
        #expect(FieldLengthRule.parse("40=", version: .v2_8_2) == nil)
        #expect(FieldLengthRule.parse("250#", version: .v2_8_2) == nil)
        #expect(FieldLengthRule.parse("20", version: .v2_8_2) == nil, "a bare v2.7+ integer is not a normative form")
        #expect(FieldLengthRule.parse("1..4", version: .v2_8) == .range(min: 1, max: 4))
    }

    @Test("FieldLengthRule.admits honours inclusive and open bounds")
    func admits() {
        #expect(FieldLengthRule.maximum(20).admits(20))
        #expect(!FieldLengthRule.maximum(20).admits(21))
        #expect(FieldLengthRule.range(min: 2, max: nil).admits(400))
        #expect(!FieldLengthRule.range(min: 2, max: nil).admits(1))
        #expect(FieldLengthRule.range(min: 1, max: 2).admits(1))
        #expect(!FieldLengthRule.range(min: 1, max: 2).admits(3))
        #expect(FieldLengthRule.oneOf([2, 4]).admits(4))
        #expect(!FieldLengthRule.oneOf([2, 4]).admits(3))
    }

    @Test("Every stored schema length is a well-formed print for its era", arguments: Version.allCases)
    func schemaWide(_ version: Version) {
        var malformed: [String] = []
        for (segmentID, grammar) in Validator.grammarTable(for: version) {
            for field in grammar.fields {
                guard let cell = field.length else { continue }
                let slot = "\(version.rawValue) \(segmentID)-\(field.index) '\(cell)'"
                guard let printed = PrintedLength(cell) else { malformed.append(slot); continue }
                switch (version.grammarVersion.printsMaximumLength, printed) {
                case (true, .number), (true, .kilo), (true, .variable): break
                case (false, .number), (false, .range), (false, .list), (false, .conformance): break
                default: malformed.append(slot + " (wrong era)")
                }
            }
        }
        #expect(malformed.isEmpty, "\(malformed.sorted().prefix(20))")
    }

    // MARK: - Pre-v2.7 maximum length

    @Test("v2.3.1 MSH-10 (LEN 20): 21 characters is a warning by default, 20 is silent")
    func preV27WarningByDefault() throws {
        let issue = try #require(try lengthIssues(msh231(controlID: String(repeating: "X", count: 21))).first)
        #expect(issue.severity == .warning)
        #expect(issue.code == .fieldLengthOutOfRange(length: "20", actual: 21))
        #expect(issue.location.segmentID == "MSH")
        #expect(issue.location.fieldIndex == 10)
        #expect(try lengthIssues(msh231(controlID: String(repeating: "X", count: 20))).isEmpty)
    }

    @Test("v2.3.1 maximum length follows fieldLengthSeverity; nil turns it off")
    func preV27Severity() throws {
        let wire = msh231(controlID: String(repeating: "X", count: 21))
        var options = ValidationOptions.default
        options.fieldLengthSeverity = .error
        #expect(try lengthIssues(wire, options).map(\.severity) == [.error])
        options.fieldLengthSeverity = nil
        #expect(try lengthIssues(wire, options).isEmpty)
        #expect(try lengthIssues(wire, .lenient).isEmpty)
    }

    @Test("v2.3.1 PID-5 (XPN, LEN 48): component separators count, repetition separators do not")
    func separators() throws {
        let a24 = String(repeating: "A", count: 24)
        let fits = msh231() + "PID|1||123||\(a24)^\(String(repeating: "B", count: 23))\r"
        let over = msh231() + "PID|1||123||\(a24)^\(a24)\r"
        let twoFull = msh231() + "PID|1||123||\(a24)^\(String(repeating: "B", count: 23))~\(a24)^\(String(repeating: "C", count: 23))\r"
        #expect(try lengthIssues(fits).isEmpty)
        #expect(try lengthIssues(over).map(\.location.fieldIndex) == [5])
        #expect(try lengthIssues(twoFull).isEmpty)
    }

    @Test("occupiedLength counts component and subcomponent separators, and no null")
    func occupied() throws {
        let message = try Parser().parse(msh231() + "PID|1||A&B^C~\\T\\X||\"\"\r")
        let pid = try #require(message.segments.first { $0.segmentID == "PID" })
        let reps = try #require(pid.field(3)).repetitions
        let encoding = message.encodingCharacters
        #expect(Validator.occupiedLength(reps[0], encoding: encoding) == 5, "A & B ^ C")
        #expect(Validator.occupiedLength(reps[1], encoding: encoding) == 2, "T inside the escape, then X")
        #expect(Validator.occupiedLength(try #require(pid.field(5)).repetitions[0], encoding: encoding) == nil)
    }

    // v2.8.2 section 2.7: "all the characters inside the escape (all between the opening and
    // closing \, not including the \ symbols themselves) count towards the length. This applies
    // to all the escape sequences, including the formatting ones." The pre-v2.7 texts say nothing
    // on escapes and length, so the same rule applies to every version.
    @Test("An escape counts the characters between its delimiters", arguments: zip(
        ["\\F\\", "\\H\\", "\\.br\\", "\\X0D0A\\", "A\\E\\B", "\\H\\bold\\N\\"],
        [1, 1, 3, 5, 3, 6]))
    func escapes(_ wire: String, _ expected: Int) throws {
        let message = try Parser().parse(msh231() + "NTE|1||\(wire)\r")
        let nte = try #require(message.segments.first { $0.segmentID == "NTE" })
        let repetition = try #require(nte.field(3)?.repetitions.first)
        #expect(Validator.occupiedLength(repetition, encoding: message.encodingCharacters) == expected, "\(wire)")
    }

    @Test("v2.3.1 MSH-10 (LEN 20): an escape is measured by its body, not its decoded character")
    func escapeAgainstMaximum() throws {
        let fits = msh231(controlID: String(repeating: "X", count: 19) + "\\F\\")
        let over = msh231(controlID: String(repeating: "X", count: 18) + "\\.br\\")
        #expect(try lengthIssues(fits).isEmpty)
        #expect(try lengthIssues(over).map(\.code) == [.fieldLengthOutOfRange(length: "20", actual: 21)])
    }

    @Test("v2.4 to v2.6 very-large-number symbols 65536 and 99999 are not checked; 64K before v2.4 neither")
    func veryLargeNumber() {
        for version in [Version.v2_4, .v2_5_1, .v2_6] {
            #expect(FieldLengthRule.parse("65536", version: version) == nil, "\(version)")
            #expect(FieldLengthRule.parse("99999", version: version) == nil, "\(version)")
        }
        #expect(FieldLengthRule.parse("64K", version: .v2_3) == nil)
        #expect(FieldLengthRule.parse("65535", version: .v2_6) == .maximum(65535))
        #expect(PrintedLength("65536") == .number(65536))
    }

    @Test("A Z-segment and a field beyond the grammar (v2.5.1 PID-40) carry no length rule")
    func outsideGrammar() throws {
        let msh251 = "MSH|^~\\&|A|B|C|D|20240101120000||ADT^A01^ADT_A01|M1|P|2.5.1\r"
        let long = String(repeating: "Z", count: 300)
        var pid = "PID|1||123||DOE^JOHN"
        pid += String(repeating: "|", count: 35) + long
        #expect(try lengthIssues(msh251 + "ZXX|\(long)\r").isEmpty)
        #expect(try lengthIssues(msh251 + pid + "\r").isEmpty)
    }

    @Test("MSH-1 and MSH-2 are delimiters, not data")
    func delimitersSkipped() throws {
        var options = ValidationOptions.default
        options.fieldLengthSeverity = .error
        #expect(try lengthIssues(msh231(), options).isEmpty)
    }

    // MARK: - v2.7+ normative length

    @Test("v2.8.2 PID-1 (SI, normative 1..4): 5 digits is a warning by default, 4 passes")
    func normativeDefault() throws {
        let issue = try #require(try lengthIssues(msh282 + "PID|12345\r").first)
        #expect(issue.severity == .warning)
        #expect(issue.code == .fieldLengthOutOfRange(length: "1..4", actual: 5))
        #expect(issue.location.segmentID == "PID")
        #expect(try lengthIssues(msh282 + "PID|1234\r").filter { $0.location.segmentID == "PID" }.isEmpty)
    }

    @Test("v2.8.2 normative length follows normativeLengthSeverity; nil and lenient turn it off")
    func normativeSeverity() throws {
        var options = ValidationOptions.default
        options.normativeLengthSeverity = .error
        #expect(try lengthIssues(msh282 + "PID|12345\r", options).map(\.severity) == [.error])
        options.normativeLengthSeverity = nil
        #expect(try lengthIssues(msh282 + "PID|12345\r", options).isEmpty)
        #expect(try lengthIssues(msh282 + "PID|12345\r", .lenient).isEmpty)
    }

    @Test("A v2.8 message is checked against the v2.8.2 normative lengths it is validated with")
    func v28Substitution() throws {
        let msh28 = "MSH|^~\\&|A|B|C|D|20240101120000||ADT^A01^ADT_A01|M1|P|2.8\r"
        #expect(try lengthIssues(msh28 + "PID|12345\r").map(\.code) == [.fieldLengthOutOfRange(length: "1..4", actual: 5)])
    }

    @Test("v2.8.2 conformance lengths (MSH-8 40=) are never enforced")
    func conformanceLengthNotEnforced() throws {
        var options = ValidationOptions.default
        options.fieldLengthSeverity = .error
        options.normativeLengthSeverity = .error
        let wire = "MSH|^~\\&|A|B|C|D|20240101120000|\(String(repeating: "S", count: 41))|ADT^A01^ADT_A01|M1|P|2.8.2\r"
        #expect(try lengthIssues(wire, options).isEmpty)
    }

    @Test("v2.8.2 a range printed on a composite field (QRI-2 CWE 2..2) is not enforced")
    func compositeRangeNotEnforced() throws {
        #expect(try lengthIssues(msh282 + "QRI||ABC^Some text\r").isEmpty)
    }

    @Test("v2.8.2 TQ2-6 (ID, printed 2..) checks the minimum only")
    func openRange() throws {
        #expect(try lengthIssues(msh282 + "TQ2||||||E\r").map(\.code) == [.fieldLengthOutOfRange(length: "2..", actual: 1)])
        #expect(try lengthIssues(msh282 + "TQ2||||||EE\r").isEmpty)
    }

    @Test("The HL7 null has no length")
    func nullHasNoLength() throws {
        #expect(try lengthIssues(msh282 + "PID|\"\"\r").isEmpty)
    }
}
