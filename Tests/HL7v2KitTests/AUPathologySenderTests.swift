import Testing
@testable import HL7v2Kit

/// M29 — HL7au:00050.1.5: OBX-6.3 must be UCUM, scoped by the ADRM to pathology
/// senders on Results. The wire does not say who sent it; the caller asserts it.
@Suite("AU pathology-sender assertion")
struct AUPathologySenderTests {
    private func issues(_ obx: String, pathology: Bool, locale: HL7Locale = .auLocalisation) throws -> [ValidationIssue] {
        var options = ValidationOptions()
        options.auPathologySender = pathology
        let message = try Parser(locale: locale).parse(TestWires.oru(obx))
        return Validator(options: options, locale: locale).validate(message).issues
            .filter { $0.message.contains("00050.1.5") }
    }

    @Test("Asserted: a numeric result with a non-UCUM units coding system fires at OBX-6.3")
    func fires() throws {
        let found = try issues("OBX|1|NM|718-7^Haemoglobin^LN||140|g/L^gram per litre^ISO+|||||F", pathology: true)
        #expect(found.count == 1 && found.first?.location.componentIndex == 3)
    }

    @Test("Asserted: UCUM passes; units with no coding system are not UCUM; no units at all is silent")
    func passes() throws {
        #expect(try issues("OBX|1|NM|718-7^Haemoglobin^LN||140|g/L^gram per litre^UCUM|||||F", pathology: true).isEmpty)
        // Bare units also draw HL7au:00044.4.1 (CE-3 when CE-1 is set); this rule adds its own.
        #expect(try issues("OBX|1|NM|718-7^Haemoglobin^LN||140|g/L|||||F", pathology: true).count == 1)
        #expect(try issues("OBX|1|CWE|5778-6^Colour^LN||371244009^Yellow^SCT||||||F", pathology: true).isEmpty)
    }

    @Test("Unasserted, or outside the AU locale, the rule is silent")
    func silent() throws {
        let wire = "OBX|1|NM|718-7^Haemoglobin^LN||140|g/L^gram per litre^ISO+|||||F"
        #expect(try issues(wire, pathology: false).isEmpty)
        #expect(try issues(wire, pathology: true, locale: .international).isEmpty)
    }
}
