// AcknowledgmentBuilderTests.swift
// ADR-019 decision 9: the general acknowledgment (v2.5.1 CH02 2.14.1) with the
// original-mode response rules of 2.9.2.2. Builder only: no protocol logic.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Acknowledgment builder")
struct AcknowledgmentBuilderTests {

    static let supported = ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.7.1", "2.8.2"]

    static func original(version: String = "2.5.1", msh9: String = "ADT^A01^ADT_A01",
                         controlID: String = "MSG00001", msh18: String? = nil,
                         sender: String = "SND_APP") -> String {
        let tail = msh18.map { "||||||\($0)" } ?? ""
        return [
            "MSH|^~\\&|\(sender)|SND_FAC|RCV_APP|RCV_FAC|20240101120000||\(msh9)|\(controlID)|P|\(version)\(tail)",
            "EVN|A01|20240101120000",
            "PID|1||123456^^^HOSP^MR||Smith^John",
            "PV1|1|I",
        ].joined(separator: "\r")
    }

    static func ack(_ wire: String, code: AcknowledgmentCode = .applicationAccept) throws -> Message {
        try MessageBuilder.acknowledgment(to: Parser().parse(wire), code: code,
                                          messageControlID: "ACK00001", dateTime: "20240101120001")
    }

    static func structureIssues(_ report: ValidationReport) -> [ValidationIssue] {
        report.issues.filter {
            switch $0.code {
            case .messageStructureSegmentMissing, .messageStructureSegmentUnexpected,
                 .messageStructureMismatch, .messageStructureNotModelled:
                return true
            default:
                return false
            }
        }
    }

    @Test("MSA-2 echoes MSH-10; sender and receiver swap; MSH-9 is ACK^<event>^ACK")
    func echoRules() throws {
        let ack = try Self.ack(Self.original())
        #expect(ack["MSH-3"] == "RCV_APP")
        #expect(ack["MSH-4"] == "RCV_FAC")
        #expect(ack["MSH-5"] == "SND_APP")
        #expect(ack["MSH-6"] == "SND_FAC")
        #expect(ack["MSH-7"] == "20240101120001")
        #expect(ack["MSH-9.1"] == "ACK")
        #expect(ack["MSH-9.2"] == "A01")
        #expect(ack["MSH-9.3"] == "ACK")
        #expect(ack["MSH-10"] == "ACK00001")
        #expect(ack["MSH-11"] == "P")
        #expect(ack["MSH-12"] == "2.5.1")
        #expect(ack["MSA-1"] == "AA")
        #expect(ack["MSA-2"] == "MSG00001")
        #expect((ack["MSA-3"] ?? "").isEmpty)
        #expect(ack.segments.map(\.segmentID) == ["MSH", "MSA"])
        #expect(ack.version == .v2_5_1)
    }

    @Test("The built v2.5.1 ACK round-trips and raises no issue, structure check included")
    func conforms() throws {
        let ack = try Self.ack(Self.original(), code: .applicationError)
        let reparsed = try Parser().parse(Data(ack.serialize()))
        #expect(reparsed["MSA-2"] == "MSG00001")
        #expect(reparsed.serialize() == ack.serialize())
        for severity in [IssueSeverity.warning, .error] {
            var options = ValidationOptions.default
            options.messageStructureSeverity = severity
            let report = Validator(options: options).validate(reparsed)
            #expect(report.issues.isEmpty, "\(report.issues.map(\.message))")
            #expect(Self.structureIssues(report).isEmpty)
        }
    }

    @Test("Every supported version: the ACK keeps the original's version and validates clean under .default",
          arguments: supported)
    func everyVersion(version: String) throws {
        let msh9 = version == "2.3" ? "ADT^A01" : "ADT^A01^ADT_A01"
        let ack = try Self.ack(Self.original(version: version, msh9: msh9))
        #expect(ack["MSH-12"] == version)
        #expect(ack.version.rawValue == version)
        #expect(ack["MSH-9.1"] == "ACK")
        #expect(ack["MSH-9.2"] == "A01")
        #expect(ack["MSH-9.3"] == (version == "2.3" ? nil : "ACK"))
        let reparsed = try Parser().parse(Data(ack.serialize()))
        let report = Validator().validate(reparsed)
        #expect(report.issues.isEmpty, "\(version): \(report.issues.map(\.message))")
    }

    @Test("With the structure check on, v2.5.1, v2.6, v2.7.1 and v2.8.2 are modelled: the others get the info issue alone",
          arguments: supported)
    func structureCheckPerVersion(version: String) throws {
        let msh9 = version == "2.3" ? "ADT^A01" : "ADT^A01^ADT_A01"
        let ack = try Self.ack(Self.original(version: version, msh9: msh9))
        var options = ValidationOptions.default
        options.messageStructureSeverity = .warning
        let report = Validator(options: options).validate(try Parser().parse(Data(ack.serialize())))
        if version == "2.5.1" || version == "2.6" || version == "2.7.1" || version == "2.8.2" || version == "2.8" {
            #expect(report.issues.isEmpty, "\(report.issues.map(\.message))")
        } else {
            // v2.3 has no MSH-9.3, so the issue names the trigger (P8-5 rule).
            let named = version == "2.3" ? "ACK^A01" : "ACK"
            #expect(report.issues.map(\.code) == [.messageStructureNotModelled(structure: named)],
                    "\(version): \(report.issues.map(\.message))")
            #expect(report.issues.allSatisfy { $0.severity == .info })
        }
    }

    @Test("v2.3 has no MSH-9.3: the ACK carries ACK^<event> only")
    func v23TwoComponents() throws {
        let ack = try Self.ack(Self.original(version: "2.3", msh9: "ADT^A01"))
        #expect(ack["MSH-9.2"] == "A01")
        #expect((ack["MSH-9.3"] ?? "").isEmpty)
        #expect(ack["MSH-12"] == "2.3")
        #expect(String(decoding: ack.serialize(), as: UTF8.self).contains("|ACK^A01|"))
    }

    @Test("An empty original MSH-9.2 gives ACK^^ACK: a required-MSG.2 error where the version prints it, as on the original",
          arguments: ["2.3.1", "2.4", "2.5.1", "2.6", "2.7.1", "2.8.2"])
    func emptyEvent(version: String) throws {
        let original = try Parser().parse(Self.original(version: version, msh9: "ADT"))
        let ack = try Self.ack(Self.original(version: version, msh9: "ADT"))
        #expect(String(decoding: ack.serialize(), as: UTF8.self).contains("|ACK^^ACK|"))
        let reparsed = try Parser().parse(Data(ack.serialize()))
        let atMSG2 = { (report: ValidationReport) in
            report.issues.filter {
                $0.code == .requiredComponentMissing && $0.location.segmentID == "MSH"
                    && $0.location.fieldIndex == 9 && $0.location.componentIndex == 2
            }
        }
        let ackIssues = atMSG2(Validator().validate(reparsed))
        let originalIssues = atMSG2(Validator().validate(original))
        if ["2.5.1", "2.6", "2.7.1", "2.8.2"].contains(version) {
            #expect(ackIssues.count == 1 && ackIssues.allSatisfy { $0.severity == .error },
                    "\(version): \(ackIssues.map(\.message))")
            #expect(originalIssues.count == 1, "\(version): the original fails MSG.2 the same way")
        } else {
            // v2.3.1 and v2.4 print no component optionality.
            #expect(Validator().validate(reparsed).issues.isEmpty, "\(version)")
            #expect(originalIssues.isEmpty)
        }
    }

    @Test("Every Table 0008 code builds, and the enum is exactly Table 0008 on every supported version")
    func table0008() throws {
        let original = try Parser().parse(Self.original())
        for code in AcknowledgmentCode.allCases {
            let ack = try MessageBuilder.acknowledgment(to: original, code: code, messageControlID: "C1",
                                                        dateTime: "20240101120001")
            #expect(ack["MSA-1"] == code.rawValue)
        }
        let codes = Set(AcknowledgmentCode.allCases.map(\.rawValue))
        for version in Version.allCases {
            let table = try #require(HL7TableRegistry.table("0008", version: version.grammarVersion))
            #expect(Set(table.entries.map(\.code)) == codes, "\(version)")
        }
    }

    @Test("An original without MSH-10 cannot be acknowledged")
    func missingControlID() throws {
        let original = try Parser().parse(Self.original(controlID: ""))
        #expect(throws: BuilderError.acknowledgedMessageControlIDMissing) {
            try MessageBuilder.acknowledgment(to: original, code: .applicationReject,
                                              messageControlID: "X", dateTime: "20240101120001")
        }
        let headerless = Message(version: .v2_5_1, encodingCharacters: .default, segments: [])
        #expect(throws: BuilderError.acknowledgedMessageControlIDMissing) {
            try MessageBuilder.acknowledgment(to: headerless, code: .applicationReject,
                                              messageControlID: "X", dateTime: "20240101120001")
        }
    }

    @Test("MSA-2 copies the MSH-10 field, so an escape sequence round-trips")
    func escapedControlID() throws {
        let ack = try Self.ack(Self.original(controlID: "MSG\\F\\01\\T\\2"))
        #expect(ack["MSA-2"] == "MSG|01&2")
        let wire = String(decoding: ack.serialize(), as: UTF8.self)
        #expect(wire.contains("\rMSA|AA|MSG\\F\\01\\T\\2"))
        #expect(try Parser().parse(Data(ack.serialize()))["MSA-2"] == "MSG|01&2")
    }

    @Test("MSH-18 is echoed with the character set, so a Latin-1 ACK round-trips")
    func characterSet() throws {
        let wire = Self.original(msh18: "8859/1", sender: "LABOR\u{00C9}")
        let original = try Parser().parse(try #require(wire.data(using: .isoLatin1)))
        #expect(original.characterEncoding == .iso8859_1)
        let ack = try MessageBuilder.acknowledgment(to: original, code: .applicationAccept,
                                                    messageControlID: "ACK00001", dateTime: "20240101120001")
        #expect(ack["MSH-18"] == "8859/1")
        #expect(ack.characterEncoding == .iso8859_1)
        let reparsed = try Parser().parse(Data(ack.serialize()))
        #expect(reparsed["MSH-5"] == "LABOR\u{00C9}")
        #expect(Validator().validate(reparsed).issues.isEmpty)
    }

    @Test("An unrecognised MSH-12 is echoed as received; the Validator reports it, as on the original")
    func unrecognisedVersion() throws {
        let ack = try Self.ack(Self.original(version: "2.9"))
        #expect(ack["MSH-12"] == "2.9")
        #expect(ack.version == .v2_5_1)
        #expect(ack["MSH-9.3"] == "ACK")
        let codes = Validator().validate(try Parser().parse(Data(ack.serialize()))).issues.map(\.code)
        #expect(codes == [.versionNotRecognised(wireValue: "2.9")])
    }

    @Test("An empty MSH-12 is echoed empty; the required-field check reports it, as on the original")
    func emptyVersion() throws {
        let ack = try Self.ack(Self.original(version: ""))
        #expect((ack["MSH-12"] ?? "").isEmpty)
        let issues = Validator().validate(try Parser().parse(Data(ack.serialize()))).issues
        #expect(issues.count == 1)
        #expect(issues.first?.location.fieldIndex == 12)
    }

    @Test("The caller adds error detail: an ERR after MSA keeps the ACK clean")
    func callerAddsERR() throws {
        let ack = try Self.ack(Self.original(), code: .applicationError)
        let err = Segment.unknown(UnknownSegment(segmentID: "ERR", fields: [
            Field(repetitions: []), .scalar(""), .scalar(""),
            .components(["207", "Application internal error", "HL70357"]), .scalar("E"),
        ]))
        let withERR = Message(version: ack.version, encodingCharacters: ack.encodingCharacters,
                              segments: ack.segments + [err], characterEncoding: ack.characterEncoding)
        var options = ValidationOptions.default
        options.messageStructureSeverity = .warning
        let report = Validator(options: options).validate(try Parser().parse(Data(withERR.serialize())))
        #expect(Self.structureIssues(report).isEmpty, "\(report.issues.map(\.message))")
    }
}
