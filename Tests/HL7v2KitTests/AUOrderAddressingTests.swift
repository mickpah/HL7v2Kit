// AUOrderAddressingTests.swift
// P12 S2-2 item 6: the sender half of HL7au:000001. AU ADRM-2021.1
// Appendix 5 p 417 (000001, Senders/Receivers, Orders): "Order addressing -
// Senders and receivers must ensure an order message is addressed using
// MSH-6 Receiving facility". An order message with MSH-6 empty is not
// addressed by MSH-6, so MSH-6 is required on ORM. 000001.1 (the receiver
// rejecting a foreign MSH-6) is receiver behaviour and is not checked here.

import Testing
@testable import HL7v2Kit

@Suite("AU order addressing by MSH-6 (HL7au:000001)")
struct AUOrderAddressingTests {
    private func findings(messageType: String, receiving: String) throws -> [ValidationIssue] {
        let wire = "MSH|^~\\&|GP APP|Good Practice|LAB|\(receiving)|20240101120000+1000||\(messageType)|MSG00001|P|2.4|||AL|NE|AUS|||en^English^ISO639\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
            + "ORC|NW|ORD0001^GOODPRAC\r"
            + "OBR|1|ORD0001^GOODPRAC||FBC^Full blood count^L\r"
        let message = try Parser(locale: .auLocalisation).parse(wire)
        return Validator(locale: .auLocalisation).validate(message).issues.filter {
            if case .profileConstraintViolation(let rule) = $0.code {
                return rule.hasPrefix("HL7au:000001")
            }
            return false
        }
    }

    @Test("ORM with MSH-6 empty fires at MSH-6")
    func orderWithoutReceivingFacilityFires() throws {
        let issues = try findings(messageType: "ORM^O01", receiving: "")
        #expect(issues.count == 1, "got \(issues.map(\.message))")
        #expect(issues.first?.location == IssueLocation(segmentID: "MSH", segmentIndex: 1, fieldIndex: 6))
    }

    @Test("ORM with MSH-6 valued is silent")
    func addressedOrderSilent() throws {
        #expect(try findings(messageType: "ORM^O01", receiving: "Good Pathology").isEmpty)
    }

    @Test("ORU with MSH-6 empty is silent (the point is scoped to Orders)")
    func resultWithoutReceivingFacilitySilent() throws {
        #expect(try findings(messageType: "ORU^R01", receiving: "").isEmpty)
    }
}
