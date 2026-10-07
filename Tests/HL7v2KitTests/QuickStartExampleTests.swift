// QuickStartExampleTests.swift
// P13 S3-1: runs the steps of Examples/QuickStart/main.swift against the same message, so the
// example program cannot rot silently. The program is an executable target the test target does
// not depend on, so its source is read from disk and checked to hold this suite's message.

import Foundation
import Testing
import HL7v2Kit

@Suite("QuickStart example")
struct QuickStartExampleTests {
    /// The segments of the example's synthetic ORU^R01, exactly as the program spells them.
    static let segments = [
        #"MSH|^~\&|SYNTH_LAB|SYNTH_PATH|SYNTH_EMR|SYNTH_CLINIC|20260101120000+1000||ORU^R01^ORU_R01|SYN-MSG-0001|P|2.4"#,
        #"PID|1||SYN-000123^^^SYNTH_PATH^MR||Synthetic^Alex^^^^^L||1980-01-01|F|||1 Example Street^^Sydney^NSW^2000^AUS||(02) 5550 1234^PRN^PH"#,
        #"PV1|1|O"#,
        #"OBR|1|SYN-ORD-0001|SYN-FIL-0001|2951-2^Sodium^LN|||20260101100000+1000|||||||||||||||20260101115000+1000||CH|F"#,
        #"OBX|1|NM|2951-2^Sodium^LN||140|mmol/L^mmol/L^UCUM|135-145|N|||F"#,
    ]

    static var wire: String { segments.joined(separator: "\r") + "\r" }

    private static var mainSource: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // HL7v2KitTests
                .deletingLastPathComponent()   // Tests
                .deletingLastPathComponent()   // repository root
                .appendingPathComponent("Examples/QuickStart/main.swift")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    @Test("the example program builds the message this suite checks")
    func sameMessage() throws {
        let source = try Self.mainSource
        for segment in Self.segments {
            #expect(source.contains("#\"\(segment)\"#"), "main.swift lacks \(segment.prefix(3))")
        }
    }

    @Test("the example's path lookups and typed accessor read the message")
    func lookups() throws {
        let message = try Parser().parse(Data(Self.wire.utf8))
        #expect(message["PID-5.1"] == "Synthetic")
        #expect(message["OBX-5"] == "140")
        #expect(message.firstSegment(PID.self)?.patientName?.givenName == "Alex")
    }

    @Test("the example's validations run and the strict AU pass reports at least as much")
    func validations() throws {
        let message = try Parser().parse(Data(Self.wire.utf8))
        let base = Validator().validate(message)
        let stricter = Validator(options: .strict, locale: .auLocalisation).validate(message)
        // The deliberate PID-7 slip is the one finding, a warning, so the report stays valid.
        #expect(base.isValid)
        #expect(base.issues.map(\.code) == [.valueFormatInvalid(dataType: "TS")])
        #expect(stricter.issues.count > base.issues.count)
    }

    @Test("the example round-trips byte for byte and its ACK carries MSA-1 AA")
    func roundTripAndAcknowledgment() throws {
        let bytes = Data(Self.wire.utf8)
        let message = try Parser().parse(bytes)
        #expect(message.serialize() == bytes)
        let ack = try MessageBuilder.acknowledgment(to: message, code: .applicationAccept,
                                                    messageControlID: "SYN-ACK-0001",
                                                    dateTime: "20260101120005+1000")
        #expect(ack["MSA-1"] == "AA")
        #expect(ack["MSA-2"] == "SYN-MSG-0001")
    }
}
