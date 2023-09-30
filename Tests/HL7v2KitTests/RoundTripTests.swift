// RoundTripTests.swift
// The single most important property test: parse → serialise == input bytes.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Round-trip parsing")
struct RoundTripTests {

    @Test("Minimal MSH-only message round-trips")
    func minimalMSH() throws {
        let wire = "MSH|^~\\&|SENDAPP|SENDFAC|RECVAPP|RECVFAC|||ADT^A01|MSG00001|P|2.5.1\r"
        let message = try Parser().parse(wire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == wire)
    }

    @Test("ADT^A01 with PID round-trips")
    func adtA01WithPID() throws {
        let wire = """
        MSH|^~\\&|SENDAPP|SENDFAC|RECVAPP|RECVFAC|||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||12345^^^HOSPITAL^MR||SMITH^JOHN^A||19700101|M\r
        """
        let message = try Parser().parse(wire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == wire)
    }

    @Test("Message with Z-segment round-trips structurally")
    func zSegmentRoundTrip() throws {
        let wire = """
        MSH|^~\\&|LAB|FAC|HOSPITAL|FAC|||ORU^R01|MSG00002|P|2.5.1\r\
        PID|1||12345||DOE^JANE||19850515|F\r\
        ZAU|1|CUSTOM_FIELD|EXTRA_DATA\r
        """
        let message = try Parser().parse(wire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == wire)
    }

    @Test("Builder → serialise round-trips through parser")
    func builderRoundTrip() throws {
        var b = MessageBuilder(version: .v2_5_1)
        _ = b.msh(
            messageType: (code: "ADT", triggerEvent: "A01"),
            sendingApplication: "SENDAPP",
            sendingFacility: "SENDFAC",
            receivingApplication: "RECVAPP",
            receivingFacility: "RECVFAC",
            messageControlID: "MSG00001"
        )
        let original = try b.build()
        let bytes = original.serialize()

        let reparsed = try Parser().parse(bytes)
        let bytesAgain = reparsed.serialize()
        #expect(bytes == bytesAgain)
    }
}
