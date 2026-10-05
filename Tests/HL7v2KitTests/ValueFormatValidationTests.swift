// ValueFormatValidationTests.swift
// P6-7 (V251-C10): primitive values must match the format their datatype section prints.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Primitive value format")
struct ValueFormatValidationTests {

    func line(_ id: String, _ fields: [Int: String]) -> String {
        let last = fields.keys.max() ?? 1
        return ([id] + (1...last).map { fields[$0] ?? "" }).joined(separator: "|") + "\r"
    }

    func formatIssues(_ wire: String, _ options: ValidationOptions = .default) throws -> [ValidationIssue] {
        try Validator(options: options).validate(Parser().parse(wire)).issues.filter {
            if case .valueFormatInvalid = $0.code { return true } else { return false }
        }
    }

    let msh251 = "MSH|^~\\&|A|B|C|D|20240101120000||ORU^R01^ORU_R01|M1|P|2.5.1\r"

    // The examples the datatype sections print (v2.5.1 §2.A.21, 2.A.22, 2.A.47, 2.A.69,
    // 2.A.75; v2.8.2 §2.A.21, 2.A.22, 2.A.47, 2.A.77), and the edges the definitions allow.
    @Test("Spec examples and allowed edges are well formed", arguments: [
        // NM: optional leading sign, digits, optional decimal point; leading zeros and
        // trailing zeros after the point are not significant.
        ("NM", "999"), ("NM", "-123.792"), ("NM", "01.20"), ("NM", "1.2"), ("NM", "0.1"),
        ("NM", "+.5"), ("NM", "5."), ("NM", "007"), ("NM", "-0.0"), ("NM", "+12"),
        // SI: a non-negative integer in the form of an NM, 0 to 9999.
        ("SI", "1"), ("SI", "0"), ("SI", "9999"), ("SI", "+5"), ("SI", "1.0"), ("SI", "-0"),
        // DT: YYYY[MM[DD]], a real calendar date.
        ("DT", "19880704"), ("DT", "199503"), ("DT", "1988"), ("DT", "19880229"), ("DT", "20000229"),
        ("DT", "19881231"),
        // TM: HH[MM[SS[.S[S[S[S]]]]]][+/-ZZZZ].
        ("TM", "0630"), ("TM", "0000"), ("TM", "235959+1100"), ("TM", "0800"), ("TM", "093544.2312"),
        ("TM", "13"), ("TM", "235959.1234+1000"), ("TM", "13-0000"), ("TM", "235960"),
        // DTM: YYYY[MM[DD[HH[MM[SS[.S[S[S[S]]]]]]]]][+/-ZZZZ], precision by length.
        ("DTM", "199904"), ("DTM", "19760704010159-0500"), ("DTM", "19760704010159-0400"),
        ("DTM", "198807050000"), ("DTM", "19880705"), ("DTM", "19981004010159+0100"),
        ("DTM", "1999010112"), ("DTM", "1999"), ("DTM", "1976070401-0500"), ("DTM", "1976+1000"),
        ("DTM", "19760704010159.1"), ("DTM", "19760704010159.1234+1000"),
    ])
    func specExamples(dataType: String, value: String) {
        #expect(PrimitiveFormat.isValid(value, dataType: dataType, version: .v2_5_1) == true)
        #expect(PrimitiveFormat.isValid(value, dataType: dataType, version: .v2_8_2) == true)
    }

    @Test("Malformed values are rejected", arguments: [
        ("NM", "<5"), ("NM", "1,000"), ("NM", "1.2.3"), ("NM", "."), ("NM", "12 "), ("NM", " 12"),
        ("NM", "-"), ("NM", "+"), ("NM", "+-1"), ("NM", "1e3"), ("NM", "1-"), ("NM", "1\u{301}"),
        ("NM", "\u{FF11}"),
        ("SI", "-1"), ("SI", "1.5"), ("SI", "10000"), ("SI", "abc"), ("SI", "."),
        ("DT", "1988-07-04"), ("DT", "1988070"), ("DT", "19881304"), ("DT", "19880732"),
        ("DT", "19870229"), ("DT", "19000229"), ("DT", "19880431"), ("DT", "198800"), ("DT", "19880100"),
        ("DT", "19880704+1000"), ("DT", "198"),
        ("TM", "2460"), ("TM", "2400"), ("TM", "063"), ("TM", "0630+05"), ("TM", "0660"),
        ("TM", "12.5"), ("TM", "1230.5"), ("TM", "123045.12345"), ("TM", "123045."),
        ("TM", "0630+"), ("TM", "+1000"), ("TM", "0630+05000"), ("TM", "123061"),
        ("DTM", "1976070401015"), ("DTM", "19760704010159.12345"), ("DTM", "hello"), ("DTM", "1976-07-04"),
        ("DTM", "19981004010159+010"), ("DTM", "19990101.5"), ("DTM", "199913"), ("DTM", "19990230"),
        ("DTM", "199901012460"),
    ])
    func malformed(dataType: String, value: String) {
        #expect(PrimitiveFormat.isValid(value, dataType: dataType, version: .v2_5_1) == false)
    }

    // v2.3 §2.8.42, v2.3.1 §2.8.44, v2.4 §2.9.47: the TS format line prints HHMM, but the
    // same section's prose says "YYYYMMDDHH is used to specify a precision of 'hour'" and
    // "the time portion follows the rules of a time field" (HH[MM...]). The spec allows the
    // hour on its own, so it is never flagged (Requirement 4).
    @Test("Before v2.5 a TS may stop at the hour, as the TS prose allows")
    func preV25HourPrecision() {
        for version in [Version.v2_3, .v2_3_1, .v2_4] {
            #expect(PrimitiveFormat.isValid("1999010112", dataType: "TS", version: version) == true)
            #expect(PrimitiveFormat.isValid("199901011230", dataType: "TS", version: version) == true)
            #expect(PrimitiveFormat.isValid("1999-01-01", dataType: "TS", version: version) == false)
        }
    }

    // The 0..9999 bound is printed from v2.5.1 (§2.A.69 "This allows for a number between
    // 0 and 9999"); v2.3 to v2.4 print only "a non-negative integer".
    @Test("SI range 0 to 9999 applies where the SI section prints it")
    func sequenceIDRange() {
        for version in [Version.v2_5_1, .v2_6, .v2_7_1, .v2_8_2, .v2_8] {
            #expect(PrimitiveFormat.isValid("10000", dataType: "SI", version: version) == false)
            #expect(PrimitiveFormat.isValid("09999", dataType: "SI", version: version) == true)
        }
        for version in [Version.v2_3, .v2_3_1, .v2_4] {
            #expect(PrimitiveFormat.isValid("10000", dataType: "SI", version: version) == true)
            #expect(PrimitiveFormat.isValid("-1", dataType: "SI", version: version) == false)
        }
    }

    @Test("Types without a lexical rule are not checked")
    func unchecked() {
        #expect(PrimitiveFormat.isValid("anything", dataType: "ST", version: .v2_5_1) == nil)
        #expect(PrimitiveFormat.isValid("anything", dataType: "ID", version: .v2_5_1) == nil)
        #expect(PrimitiveFormat.isValid("anything", dataType: "IS", version: .v2_5_1) == nil)
    }

    @Test("v2.5.1 OBX-5 typed NM by OBX-2: '<5' is a warning by default, '12.5' passes")
    func obx5Numeric() throws {
        let bad = try formatIssues(msh251 + line("OBX", [1: "1", 2: "NM", 3: "GLU^Glucose^L", 5: "<5"]))
        let issue = try #require(bad.first)
        #expect(bad.count == 1)
        #expect(issue.code == .valueFormatInvalid(dataType: "NM"))
        #expect(issue.severity == .warning)
        #expect(issue.location.segmentID == "OBX")
        #expect(issue.location.fieldIndex == 5)
        #expect(try formatIssues(msh251 + line("OBX", [1: "1", 2: "NM", 3: "GLU^Glucose^L", 5: "12.5"])).isEmpty)
    }

    @Test("Each repetition is checked")
    func repetitions() throws {
        let issues = try formatIssues(msh251 + line("OBX", [1: "1", 2: "NM", 3: "GLU^Glucose^L", 5: "1~x~3~y"]))
        #expect(issues.count == 2)
    }

    @Test("v2.5.1 OBX-1 SI '-1' is flagged")
    func setIDNegative() throws {
        let issues = try formatIssues(msh251 + line("OBX", [1: "-1", 2: "ST", 3: "X^Y^L", 5: "text"]))
        #expect(issues.map(\.code) == [.valueFormatInvalid(dataType: "SI")])
    }

    @Test("v2.5.1 PID-7 (TS): component 1 is checked as DTM")
    func pid7Component() throws {
        let issue = try #require(try formatIssues(msh251 + line("PID", [1: "1", 3: "123", 7: "1980-01-01"])).first)
        #expect(issue.code == .valueFormatInvalid(dataType: "DTM"))
        #expect(issue.location.fieldIndex == 7)
        #expect(issue.location.componentIndex == 1)
        #expect(issue.location.subcomponentIndex == nil)
        #expect(try formatIssues(msh251 + line("PID", [1: "1", 3: "123", 7: "19800101"])).isEmpty)
    }

    @Test("v2.5.1 PID-5 XPN.12 (TS): its DTM subcomponent is checked one level down")
    func nestedTimestamp() throws {
        let wire = msh251 + line("PID", [1: "1", 3: "123", 5: "DOE^JOHN^^^^^L^^^^^1980-01-01"])
        let issue = try #require(try formatIssues(wire).first)
        #expect(issue.code == .valueFormatInvalid(dataType: "DTM"))
        #expect(issue.location.componentIndex == 12)
        #expect(issue.location.subcomponentIndex == 1)
        #expect(try formatIssues(msh251 + line("PID", [1: "1", 3: "123", 5: "DOE^JOHN^^^^^L^^^^^19800101"])).isEmpty)
    }

    @Test("v2.3.1 OBX-14 (TS, a primitive on v2.3 to v2.4): component 1 is checked as TS")
    func preV25Timestamp() throws {
        let msh = "MSH|^~\\&|A|B|C|D|20240101120000||ORU^R01|M1|P|2.3.1\r"
        let bad = try formatIssues(msh + line("OBX", [1: "1", 2: "ST", 3: "X^Y^L", 5: "t", 14: "1999-01-01"]))
        #expect(bad.map(\.code) == [.valueFormatInvalid(dataType: "TS")])
        // The hour alone (TS prose) and the degree-of-precision component are both allowed.
        let good = try formatIssues(msh + line("OBX", [1: "1", 2: "ST", 3: "X^Y^L", 5: "t", 14: "1999010112^H"]))
        #expect(good.isEmpty)
    }

    // P5-2: TS on v2.3 to v2.4 now has a component grammar from its Format line (TS.1 and
    // TS.2 print no datatype code). The format check still reads it as a primitive
    // (Validator.componentGrammar), so the time is checked and the precision accepted.
    @Test("P5-2: a malformed TS on v2.3 to v2.4 PID-7 still warns; a ^-precision TS is accepted")
    func preV25TimestampWithGrammar() throws {
        for version in ["2.3", "2.3.1", "2.4"] {
            let msh = "MSH|^~\\&|A|B|C|D|20240101120000||ADT^A01|M1|P|\(version)\r"
            #expect(DataTypeGrammarTable.grammar("TS", version: try #require(Version(rawValue: version))) != nil)
            let bad = try formatIssues(msh + line("PID", [1: "1", 3: "123", 5: "DOE^JOHN", 7: "19991301"]))
            #expect(bad.map(\.code) == [.valueFormatInvalid(dataType: "TS")], "\(version)")
            #expect(bad.first?.location.componentIndex == nil, "\(version)")
            #expect(try formatIssues(msh + line("PID", [1: "1", 3: "123", 5: "DOE^JOHN", 7: "19991231^D"])).isEmpty,
                    "\(version)")
        }
    }

    @Test("P5-2: a TS component (v2.3 ARQ-11 DR.1) and a TS OBX-5 are still checked as TS")
    func preV25TimestampNestedAndVaries() throws {
        let msh = "MSH|^~\\&|A|B|C|D|20240101120000||ORU^R01|M1|P|2.3\r"
        let nested = try formatIssues(msh + line("ARQ", [11: "19991301^20000101"]))
        #expect(nested.map(\.code) == [.valueFormatInvalid(dataType: "TS")])
        #expect(nested.first?.location.componentIndex == 1)
        #expect(try formatIssues(msh + line("ARQ", [11: "19991201^20000101"])).isEmpty)
        let obx = try formatIssues(msh + line("OBX", [1: "1", 2: "TS", 3: "X^Y^L", 5: "19991301^S", 11: "F"]))
        #expect(obx.map(\.code) == [.valueFormatInvalid(dataType: "TS")])
    }

    // P5-3: TQ on v2.3 to v2.4 now has a component grammar (CH4 4.4 / 4.3). Its TS
    // components (TQ.4 start, TQ.5 end) are still checked as TS, and the degree of
    // precision, demoted to a subcomponent inside TQ, is accepted.
    @Test("P5-3: a malformed TS in ORC-7.4 (TQ) on v2.3 to v2.4 warns; a &-precision TS is accepted")
    func preV25TimestampInsideTQ() throws {
        for version in ["2.3", "2.3.1", "2.4"] {
            let msh = "MSH|^~\\&|A|B|C|D|20240101120000||ORM^O01|M1|P|\(version)\r"
            let bad = try formatIssues(msh + line("ORC", [1: "NW", 2: "1", 7: "1^Q1H^^19991301"]))
            #expect(bad.map(\.code) == [.valueFormatInvalid(dataType: "TS")], "\(version)")
            #expect(bad.first?.location.componentIndex == 4, "\(version)")
            #expect(try formatIssues(msh + line("ORC", [1: "NW", 2: "1", 7: "1^Q1H^^19991231&D^20000101"])).isEmpty,
                    "\(version)")
        }
    }

    @Test("v2.8.2 RF1-18 (MO): MO.1 Quantity is checked as NM")
    func rf1MoneyQuantity() throws {
        let msh = "MSH|^~\\&|A|B|C|D|20240101120000||REF^I12^REF_I12|M1|P|2.8.2\r"
        let issue = try #require(try formatIssues(msh + line("RF1", [18: "abc^AUD"])).first)
        #expect(issue.code == .valueFormatInvalid(dataType: "NM"))
        #expect(issue.location.componentIndex == 1)
        #expect(try formatIssues(msh + line("RF1", [18: "12.50^AUD"])).isEmpty)
    }

    @Test("A 2.8 message is checked against the v2.8.2 component grammar")
    func v28UsesV282Grammar() throws {
        let msh = "MSH|^~\\&|A|B|C|D|20240101120000||REF^I12^REF_I12|M1|P|2.8\r"
        let issues = try formatIssues(msh + line("RF1", [18: "abc^AUD"]))
        #expect(issues.map(\.code) == [.valueFormatInvalid(dataType: "NM")])
    }

    @Test("A primitive field is read as its first value, as a recipient reads it")
    func primitiveFirstValue() throws {
        #expect(try formatIssues(msh251 + line("OBX", [1: "1", 2: "NM", 3: "GLU^Glucose^L", 5: "12^abc"])).isEmpty)
    }

    @Test("The HL7 null, lenient and a nil severity are silent; strict keeps warning; error is opt-in")
    func severities() throws {
        #expect(try formatIssues(msh251 + line("OBX", [1: "1", 2: "NM", 3: "GLU^Glucose^L", 5: "\"\""])).isEmpty)
        let bad = msh251 + line("OBX", [1: "1", 2: "NM", 3: "GLU^Glucose^L", 5: "<5"])
        #expect(try formatIssues(bad, .lenient).isEmpty)
        #expect(try formatIssues(bad, .strict).map(\.severity) == [.warning])
        var off = ValidationOptions.default
        off.valueFormatSeverity = nil
        #expect(try formatIssues(bad, off).isEmpty)
        var error = ValidationOptions.default
        error.valueFormatSeverity = .error
        #expect(try formatIssues(bad, error).map(\.severity) == [.error])
    }
}
