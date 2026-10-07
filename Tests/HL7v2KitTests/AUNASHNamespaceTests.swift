// AUNASHNamespaceTests.swift
// P12 S2-2 item 5: the HD-1 presence half of HL7au:000043.1 and 00044.2.1,
// under the caller's NASH-transport assertion. AU ADRM-2021.1 Appendix 5
// p 447 (000043.1): "The format must be "registered organisation name in HI
// service^1.2.36.1.2001.1003.0.<hpio>^ISO""; p 449 (00044.2.1, under the
// grouper "HD Datatype conformance points for MSH-4, and MSH-6"): "When
// using SMD with NASH certificates the HD Namespace ID component must
// contain the registered organisation name". Whether the name is the one
// the HI service holds needs the directory; that it is present does not.

import Testing
@testable import HL7v2Kit

@Suite("AU NASH namespace ID presence (HL7au:000043.1, 00044.2.1)")
struct AUNASHNamespaceTests {
    private let oid = "1.2.36.1.2001.1003.0.0000000000001001"

    private func findings(sending: String, receiving: String = "Good Hospital^1.2.36.1.2001.1003.0.0000000000002002^ISO",
                          nash: Bool) throws -> [ValidationIssue] {
        let wire = "MSH|^~\\&|LAB|\(sending)|APP|\(receiving)|20240101120000||ORU^R01^ORU_R01|MSG00001|P|2.4\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
        var options = ValidationOptions()
        options.auNASHTransport = nash
        let message = try Parser(locale: .auLocalisation).parse(wire)
        return Validator(options: options, locale: .auLocalisation).validate(message).issues.filter {
            if case .profileConstraintViolation(let rule) = $0.code {
                return rule.hasPrefix("HL7au:000043.1") || rule.hasPrefix("HL7au:00044.2.1")
            }
            return false
        }
    }

    @Test("Asserted: MSH-4 without the organisation name fires at MSH-4.1")
    func sendingFacilityWithoutNameFires() throws {
        let issues = try findings(sending: "^\(oid)^ISO", nash: true)
        #expect(issues.count == 1, "got \(issues.map(\.message))")
        #expect(issues.first?.location == IssueLocation(segmentID: "MSH", segmentIndex: 1, fieldIndex: 4, componentIndex: 1))
    }

    @Test("Asserted: MSH-6 without the organisation name fires at MSH-6.1")
    func receivingFacilityWithoutNameFires() throws {
        let issues = try findings(sending: "ACME Pathology^\(oid)^ISO", receiving: "^\(oid)^ISO", nash: true)
        #expect(issues.count == 1, "got \(issues.map(\.message))")
        #expect(issues.first?.location == IssueLocation(segmentID: "MSH", segmentIndex: 1, fieldIndex: 6, componentIndex: 1))
    }

    @Test("Asserted: the ADRM's own shape is silent")
    func namedFacilitiesSilent() throws {
        #expect(try findings(sending: "ACME Pathology^\(oid)^ISO", nash: true).isEmpty)
    }

    @Test("Not asserted: an unnamed MSH-4 is silent")
    func unassertedSilent() throws {
        #expect(try findings(sending: "^\(oid)^ISO", receiving: "^\(oid)^ISO", nash: false).isEmpty)
    }
}
