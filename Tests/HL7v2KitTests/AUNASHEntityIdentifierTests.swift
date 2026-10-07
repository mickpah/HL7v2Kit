import Testing
@testable import HL7v2Kit

/// M33 — the EI twins of what M32 shipped for HD.
///
/// `HL7au:00044.3.4` (the EI Universal ID must be `"1.2.36.1.2001.1003.0."`
/// concatenated with the HPI-O) and `HL7au:00044.3.3` (the EI Universal ID
/// Type must be `"ISO"`), datatype-wide as the ADRM's "EI datatype
/// conformance points" grouper states, under the same NASH assertion.
///
/// The sentence constrains the SHAPE of the universal ID, not whose HPI-O it
/// is — an identifier echoed from another organisation carries that
/// organisation's HPI-O and satisfies the rule unchanged.
@Suite("AU NASH entity-identifier rules")
struct AUNASHEntityIdentifierTests {
    private let goodEI = "12123-1^Good Hospital^1.2.36.1.2001.1003.0.0000000000002002^ISO"

    private func issues(_ orc: String, nash: Bool, locale: HL7Locale = .auLocalisation) throws -> [ValidationIssue] {
        let wire = "MSH|^~\\&|LAB|FAC|APP|FAC|20240101120000||ORU^R01^ORU_R01|MSG00001|P|2.5.1\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN\r" + orc + "\r"
        var options = ValidationOptions()
        options.auNASHTransport = nash
        let message = try Parser(locale: locale).parse(wire)
        return Validator(options: options, locale: locale).validate(message).issues
            .filter { $0.message.contains("00044.3.3") || $0.message.contains("00044.3.4") }
    }

    @Test("Asserted: the ADRM's own ORC-3 shape passes")
    func specShapePasses() throws {
        #expect(try issues("ORC|RE|\(goodEI)|\(goodEI)|\(goodEI)", nash: true).isEmpty)
    }

    @Test("Asserted: a universal ID that is not the HPI-O OID fires 00044.3.4 at EI-3")
    func wrongRoot() throws {
        let bad = "12123-1^Good Hospital^2.16.840.1.113883.3.1^ISO"
        let found = try issues("ORC|RE|\(goodEI)|\(bad)|\(goodEI)", nash: true)
        #expect(found.count == 1 && found.first?.location.fieldIndex == 3)
        #expect(found.first?.location.componentIndex == 3)
        #expect(found.first?.message.contains("00044.3.4") == true)
    }

    @Test("Asserted: a universal ID type other than ISO fires 00044.3.3 at EI-4")
    func wrongIDType() throws {
        let bad = "12123-1^Good Hospital^1.2.36.1.2001.1003.0.0000000000002002^L"
        let found = try issues("ORC|RE|\(goodEI)|\(bad)|\(goodEI)", nash: true)
        #expect(found.count == 1 && found.first?.location.componentIndex == 4)
        #expect(found.first?.message.contains("00044.3.3") == true)
    }

    @Test("Asserted: the rule is datatype-wide — OBR-3 carries it too")
    func obrFillerOrderNumber() throws {
        let bad = "12123-1^Good Hospital^1.2.36.1.2001.1003.0.123^ISO"
        let wire = "MSH|^~\\&|LAB|FAC|APP|FAC|20240101120000||ORU^R01^ORU_R01|MSG00001|P|2.5.1\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
            + "OBR|1|\(goodEI)|\(bad)|26604-1^FBC^LN\r"
        var options = ValidationOptions(); options.auNASHTransport = true
        let found = Validator(options: options, locale: .auLocalisation)
            .validate(try Parser(locale: .auLocalisation).parse(wire)).issues
            .filter { $0.message.contains("00044.3.4") }
        #expect(found.count == 1 && found.first?.location.segmentID == "OBR")
    }

    @Test("Asserted: an echoed identifier carrying another organisation's HPI-O still passes")
    func echoedIdentifier() throws {
        let otherOrg = "P9-1^Referring Practice^1.2.36.1.2001.1003.0.0000000000001001^ISO"
        #expect(try issues("ORC|RE|\(otherOrg)|\(goodEI)|\(goodEI)", nash: true).isEmpty)
    }

    @Test("Asserted: an empty universal ID is the completeness rule's job, not this one's")
    func emptyUniversalID() throws {
        // HL7au:000006 / 000007 already require all four EI components on
        // ORC-2/-3/-4 and OBR-2/-3, so firing here would double-report.
        #expect(try issues("ORC|RE|12123-1^Good Hospital|\(goodEI)|\(goodEI)", nash: true).isEmpty)
    }

    @Test("Unasserted, or outside the AU locale, nothing fires")
    func silent() throws {
        let bad = "12123-1^Good Hospital^2.16.840.1.113883.3.1^L"
        #expect(try issues("ORC|RE|\(goodEI)|\(bad)|\(goodEI)", nash: false).isEmpty)
        #expect(try issues("ORC|RE|\(goodEI)|\(bad)|\(goodEI)", nash: true, locale: .international).isEmpty)
    }
}
