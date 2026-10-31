// AUPreAdoptedFieldTests.swift
// P00 S4-2: ADRM 2021 pre-adopts MSH-27 Security Handling Instructions from v2.9 onto v2.4
// (MSH attribute table p. 38: CWE, O, RP Y, LEN 250, footnote †††††; definition §2.1.9.27).
// MSH-22 to 26 print only "Reserved" and are not modelled. Under the international locale
// v2.4 has no MSH-27, so nothing checks it.

import Testing
@testable import HL7v2Kit

@Suite("AU ADRM pre-adopted MSH-27")
struct AUPreAdoptedFieldTests {
    /// An AU v2.4 ORU header whose MSH-27 is `msh27` (MSH-13 to 26 empty).
    static func wire(_ msh27: String) -> String {
        "MSH|^~\\&|LAB|FAC|GP|FAC|20240101||ORU^R01^ORU_R01|MSG|P|2.4"
            + String(repeating: "|", count: 15) + msh27 + "\r"
    }

    static func msh27Issues(_ msh27: String, _ locale: HL7Locale) throws -> [ValidationIssue] {
        let message = try Parser(locale: locale).parse(wire(msh27))
        return Validator(options: .default, locale: locale).validate(message).issues.filter {
            $0.location.segmentID == "MSH" && $0.location.fieldIndex == 27
        }
    }

    @Test("The wire puts the value in MSH-27")
    func wireShape() throws {
        #expect(try Parser().parse(Self.wire("SH1"))["MSH-27"] == "SH1")
    }

    /// A CWE carrying only its text (CWE.2), `length` characters long with the separator.
    /// It meets the AU CWE rules for an ORU (HL7au:00044.6: text valued; identifier and
    /// coding system both empty) and touches no table.
    static func textOnly(_ length: Int) -> String { "^" + String(repeating: "x", count: length - 1) }

    @Test("Under the AU locale a 251-character MSH-27 draws the ADRM LEN, citing it")
    func pastADRMLength() throws {
        let found = try Self.msh27Issues(Self.textOnly(251), .auLocalisation)
        #expect(found.map(\.code) == [.fieldLengthOutOfRange(length: "250", actual: 251)])
        #expect(found.first?.severity == .warning)
        #expect(found.first?.message.contains("AU ADRM-2021") == true)
    }

    @Test("Under the AU locale 250 characters, and two repetitions, are clean")
    func withinADRM() throws {
        #expect(try Self.msh27Issues(Self.textOnly(250), .auLocalisation).isEmpty)
        #expect(try Self.msh27Issues("^Restricted~^Confidential", .auLocalisation).isEmpty)
    }

    @Test("Under the AU locale the AU CWE rules reach MSH-27 on an ORU (HL7au:00044.6)")
    func auCWERulesApply() throws {
        // An identifier with no text and no coding system breaks 00044.6.3 and 00044.6.1.
        let found = try Self.msh27Issues("SH1", .auLocalisation)
        #expect(found.contains { if case .profileConstraintViolation = $0.code { return true } else { return false } })
    }

    @Test("Under the international locale v2.4 has no MSH-27, so nothing checks it")
    func internationalUnchecked() throws {
        #expect(try Self.msh27Issues(Self.textOnly(251), .international).isEmpty)
        #expect(try Self.msh27Issues("SH1", .international).isEmpty)
    }

    @Test("The AU extension carries MSH-27 alone, as ADRM prints it")
    func extensionShape() {
        let fields = Profile.auADRM2021.grammarExtensions["MSH"] ?? []
        #expect(fields.map(\.index) == [27])
        #expect(fields.first?.dataType == "CWE")
        #expect(fields.first?.optionality == .optional)
        #expect(fields.first?.repeatability == .multiple)
        #expect(fields.first?.table == nil)
    }
}
