import Testing
@testable import HL7v2Kit

/// M32 — the wire-decidable half of the ADRM's NASH/SMD addressing family.
///
/// `HL7au:00044.2.2` (HD Universal ID = `"1.2.36.1.2001.1003.0."` + the HPI-O)
/// and `HL7au:00044.2.3` (HD Universal ID Type = `"ISO"`) on MSH-4 and MSH-6,
/// with the 16-digit HPI-O figure from `HL7au:000043.1`. All three are gated
/// "when using SMD with NASH certificates" — a transport fact the wire does
/// not carry, so the caller asserts it.
@Suite("AU NASH transport assertion")
struct AUNASHTransportTests {
    private let validOID = "1.2.36.1.2001.1003.0.8003621566684455"

    private func issues(sending: String, receiving: String = "HOSPITAL^1.2.36.1.2001.1003.0.8003629900024197^ISO",
                        nash: Bool, locale: HL7Locale = .auLocalisation) throws -> [ValidationIssue] {
        let wire = "MSH|^~\\&|LAB|\(sending)|APP|\(receiving)|20240101120000||ORU^R01^ORU_R01|MSG00001|P|2.5.1\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
        var options = ValidationOptions()
        options.auNASHTransport = nash
        let message = try Parser(locale: locale).parse(wire)
        return Validator(options: options, locale: locale).validate(message).issues
            .filter { $0.message.contains("00044.2.2") || $0.message.contains("00044.2.3") }
    }

    @Test("Asserted: the ADRM's own MSH-4 shape passes")
    func specShapePasses() throws {
        #expect(try issues(sending: "ACME Pathology^\(validOID)^ISO", nash: true).isEmpty)
    }

    @Test("Asserted: a universal ID that is not the HPI-O OID fires 00044.2.2 at MSH-4.2")
    func wrongRoot() throws {
        let found = try issues(sending: "ACME Pathology^2.16.840.1.113883.3.1^ISO", nash: true)
        #expect(found.count == 1 && found.first?.location.fieldIndex == 4)
        #expect(found.first?.location.componentIndex == 2)
        #expect(found.first?.message.contains("00044.2.2") == true)
    }

    @Test("Asserted: the right root with the wrong HPI-O digit count fires")
    func wrongDigitCount() throws {
        // 15 digits, and 17 digits: HL7au:000043.1 says the HPI-O is a 16-digit number.
        #expect(try issues(sending: "ACME^1.2.36.1.2001.1003.0.800362156668445^ISO", nash: true).count == 1)
        #expect(try issues(sending: "ACME^1.2.36.1.2001.1003.0.80036215666844551^ISO", nash: true).count == 1)
        // Right length, but not digits.
        #expect(try issues(sending: "ACME^1.2.36.1.2001.1003.0.80036215666844X5^ISO", nash: true).count == 1)
    }

    @Test("Asserted: a universal ID type other than ISO fires 00044.2.3")
    func wrongIDType() throws {
        let found = try issues(sending: "ACME^\(validOID)^AUSNATA", nash: true)
        #expect(found.count == 1 && found.first?.location.componentIndex == 3)
        #expect(found.first?.message.contains("00044.2.3") == true)
    }

    @Test("Asserted: MSH-6 carries the same two rules")
    func receivingFacility() throws {
        let found = try issues(sending: "ACME^\(validOID)^ISO",
                               receiving: "Good Hospital^1.2.36.1.2001.1003.0.123^ISO", nash: true)
        #expect(found.count == 1 && found.first?.location.fieldIndex == 6)
    }

    @Test("Asserted: a bare namespace fails both points — HL7au:000043.1 requires the full form")
    func bareNamespace() throws {
        // "The format must be 'registered organisation name in HI
        // service^1.2.36.1.2001.1003.0.<hpio>^ISO'" — a missing identifier
        // violates .2.2 and .2.3 exactly as a malformed one does.
        let found = try issues(sending: "ACME Pathology", nash: true)
        #expect(found.count == 2)
        #expect(Set(found.map { $0.location.componentIndex }) == [2, 3])
    }

    @Test("An unpopulated MSH-4 does not reach the rule at all")
    func fieldNotPopulated() throws {
        #expect(try issues(sending: "", nash: true).isEmpty)
    }

    @Test("Unasserted, or outside the AU locale, nothing fires")
    func silent() throws {
        let bad = "ACME^2.16.840.1.113883.3.1^AUSNATA"
        #expect(try issues(sending: bad, nash: false).isEmpty)
        #expect(try issues(sending: bad, nash: true, locale: .international).isEmpty)
    }
}
