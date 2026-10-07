// AUNASHScopeTests.swift
// P12 S2-2 item 11 (controller ruling on S2-2a concern 4): the NASH HD rules
// on MSH-4 and MSH-6 are scoped as the print scopes them. AU ADRM-2021.1
// Appendix 5: HL7au:000043.1 (p 447) and 00044.2.1, .2.2, .2.3 (p 449) each
// read "Senders | Orders, Results, Referrals". An asserted NASH transport
// therefore checks ORM, ORU and REF, not every message (the EI twins
// 00044.3.3 / .3.4 already sit under the EI override's same gate).

import Testing
@testable import HL7v2Kit

@Suite("AU NASH HD rules scoped to Orders, Results and Referrals")
struct AUNASHScopeTests {
    private func findings(messageType: String) throws -> [ValidationIssue] {
        let wire = "MSH|^~\\&|LAB|^1.2.36.1.2001.1003.0.123^L|APP|^1.2.36.99^L|20240101120000||\(messageType)|MSG00001|P|2.4\r"
            + "EVN|A01|20240101120000\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
        var options = ValidationOptions()
        options.auNASHTransport = true
        let message = try Parser(locale: .auLocalisation).parse(wire)
        return Validator(options: options, locale: .auLocalisation).validate(message).issues.filter {
            if case .profileConstraintViolation(let rule) = $0.code {
                return rule.hasPrefix("HL7au:000043.1") || rule.hasPrefix("HL7au:00044.2")
            }
            return false
        }
    }

    @Test("Asserted: an ADT with non-NASH MSH-4 and MSH-6 is silent")
    func admissionSilent() throws {
        #expect(try findings(messageType: "ADT^A01^ADT_A01").isEmpty)
    }

    @Test("Asserted: the same MSH-4 and MSH-6 on an ORU fire (name, OID and type, on both)")
    func resultFires() throws {
        let issues = try findings(messageType: "ORU^R01^ORU_R01")
        #expect(issues.count == 6, "got \(issues.map(\.message))")
    }
}
