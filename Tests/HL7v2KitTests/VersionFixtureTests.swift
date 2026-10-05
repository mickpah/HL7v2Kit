// VersionFixtureTests.swift
// V23-C14, V231-C18, V26-C15, V282-C14: one synthetic wire fixture set per thinly
// covered version. FixtureRoundTripTests already round-trips and validates every
// fixture; this suite pins what each file is FOR (its version and message type, a
// report with no issues at all under .strict, so structure, grammar and predicates all
// agree with the print) and drives fire/silent pairs off the real wires.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Per-version synthetic fixtures")
struct VersionFixtureTests {
    struct Fixture: Sendable, CustomTestStringConvertible {
        let file: String
        let version: Version
        let messageCode: String
        let triggerEvent: String
        var testDescription: String { file }
    }

    static let fixtures: [Fixture] = [
        Fixture(file: "oru_r01_v23.hl7", version: .v2_3, messageCode: "ORU", triggerEvent: "R01"),
        Fixture(file: "orf_r04_v23.hl7", version: .v2_3, messageCode: "ORF", triggerEvent: "R04"),
        Fixture(file: "ack_a01_v23.hl7", version: .v2_3, messageCode: "ACK", triggerEvent: "A01"),
        Fixture(file: "oru_r01_v231.hl7", version: .v2_3_1, messageCode: "ORU", triggerEvent: "R01"),
        Fixture(file: "adt_a01_v231.hl7", version: .v2_3_1, messageCode: "ADT", triggerEvent: "A01"),
        Fixture(file: "ack_a01_v231.hl7", version: .v2_3_1, messageCode: "ACK", triggerEvent: "A01"),
        Fixture(file: "oru_r01_v26.hl7", version: .v2_6, messageCode: "ORU", triggerEvent: "R01"),
        Fixture(file: "adt_a01_v26.hl7", version: .v2_6, messageCode: "ADT", triggerEvent: "A01"),
        Fixture(file: "oru_r01_v271.hl7", version: .v2_7_1, messageCode: "ORU", triggerEvent: "R01"),
        Fixture(file: "adt_a01_v271.hl7", version: .v2_7_1, messageCode: "ADT", triggerEvent: "A01"),
        Fixture(file: "adt_a01_v282.hl7", version: .v2_8_2, messageCode: "ADT", triggerEvent: "A01"),
        Fixture(file: "oru_r01_v282.hl7", version: .v2_8_2, messageCode: "ORU", triggerEvent: "R01"),
        Fixture(file: "oml_o21_v282.hl7", version: .v2_8_2, messageCode: "OML", triggerEvent: "O21"),
    ]

    /// The ORU^R01 fixture of every version from v2.3 on that has one.
    static let resultFixtures = ["oru_r01_v23.hl7", "oru_r01_v231.hl7", "oru_r01_v26.hl7",
                                 "oru_r01_v271.hl7", "oru_r01_v282.hl7"]

    static func load(_ file: String) throws -> String {
        let data = try Data(contentsOf: FixtureCorpus.fixtureURL(named: file))
        return try #require(String(data: data, encoding: .utf8))
    }

    /// Sets field `index` of the first `segment` in a CR-separated wire. For MSH the
    /// field separator is MSH-1, so MSH-n sits at split position n - 1.
    static func setting(_ wire: String, _ segment: String, _ index: Int, to value: String) -> String {
        var segments = wire.components(separatedBy: "\r")
        guard let i = segments.firstIndex(where: { $0.hasPrefix(segment + "|") }) else { return wire }
        var fields = segments[i].components(separatedBy: "|")
        let slot = segment == "MSH" ? index - 1 : index
        while fields.count <= slot { fields.append("") }
        fields[slot] = value
        segments[i] = fields.joined(separator: "|")
        return segments.joined(separator: "\r")
    }

    static func reports(_ wire: String, _ code: IssueCode, _ segment: String, _ field: Int) throws -> Bool {
        let report = Validator().validate(try Parser().parse(wire))
        return report.issues.contains {
            $0.code == code && $0.location.segmentID == segment && $0.location.fieldIndex == field
        }
    }

    @Test("Each fixture carries its version and message type, round-trips, and validates with no issues under .strict",
          arguments: fixtures)
    func fixtureIsVersionedAndClean(_ fixture: Fixture) throws {
        let data = try Data(contentsOf: FixtureCorpus.fixtureURL(named: fixture.file))
        let message = try Parser().parse(data)
        #expect(message.version == fixture.version)
        #expect(message["MSH-9.1"] == fixture.messageCode)
        #expect(message["MSH-9.2"] == fixture.triggerEvent)
        #expect(message.serialize() == data)
        let lenient = Validator(options: .default).validate(message)
        #expect(lenient.errors.isEmpty, "\(fixture.file): \(lenient.errors.map(\.message))")
        let strict = Validator(options: .strict).validate(message)
        #expect(strict.issues.isEmpty, "\(fixture.file): \(strict.issues.map(\.message))")
    }

    @Test("OBX-2 is silent as shipped and fires when emptied (OBX-11 != X)",
          arguments: resultFixtures + ["orf_r04_v23.hl7"])
    func obx2Pair(_ file: String) throws {
        let wire = try Self.load(file)
        #expect(try Self.reports(wire, .conditionalFieldMissing, "OBX", 2) == false)
        #expect(try Self.reports(Self.setting(wire, "OBX", 2, to: ""), .conditionalFieldMissing, "OBX", 2))
    }

    @Test("OBR-25 is silent as shipped and fires when emptied on an ORU",
          arguments: resultFixtures)
    func obr25Pair(_ file: String) throws {
        let wire = try Self.load(file)
        #expect(try Self.reports(wire, .conditionalFieldMissing, "OBR", 25) == false)
        #expect(try Self.reports(Self.setting(wire, "OBR", 25, to: ""), .conditionalFieldMissing, "OBR", 25))
    }

    @Test("v2.3 ORU without ORC: OBR-3 fires when emptied; OBR-2 only when OBR-3 is empty too")
    func v23OrcAbsentOrderNumbers() throws {
        let wire = try Self.load("oru_r01_v23.hl7")
        #expect(try Self.reports(wire, .conditionalFieldMissing, "OBR", 2) == false)
        #expect(try Self.reports(wire, .conditionalFieldMissing, "OBR", 3) == false)
        // ORC absent on an ORU: the filler number must ride OBR-3.
        #expect(try Self.reports(Self.setting(wire, "OBR", 3, to: ""), .conditionalFieldMissing, "OBR", 3))
        // OBR-2 alone emptied: OBR-3 still identifies the order, so OBR-2 stays silent.
        let noPlacer = Self.setting(wire, "OBR", 2, to: "")
        #expect(try Self.reports(noPlacer, .conditionalFieldMissing, "OBR", 2) == false)
        // Both emptied: no order number anywhere, so OBR-2 fires as well.
        let noNumbers = Self.setting(noPlacer, "OBR", 3, to: "")
        #expect(try Self.reports(noNumbers, .conditionalFieldMissing, "OBR", 2))
    }

    @Test("v2.3.1 ACK carries MSA-1 AE and an ERR pointing at PID-3")
    func v231AckWithErr() throws {
        let message = try Parser().parse(try Self.load("ack_a01_v231.hl7"))
        #expect(message["MSA-1"] == "AE")
        #expect(message["MSA-2"] == "SYN-2312")
        #expect(message["ERR-1.4.1"] == "101")
        #expect(message["ERR-1.1"] == "PID")
        #expect(message["ERR-1.3"] == "3")
    }

    @Test("OBR-7 is silent as shipped and fires when emptied on an ORU",
          arguments: ["oru_r01_v26.hl7", "oru_r01_v271.hl7", "oru_r01_v282.hl7"])
    func obr7Pair(_ file: String) throws {
        let wire = try Self.load(file)
        #expect(try Self.reports(wire, .conditionalFieldMissing, "OBR", 7) == false)
        #expect(try Self.reports(Self.setting(wire, "OBR", 7, to: ""), .conditionalFieldMissing, "OBR", 7))
    }

    @Test("DG1-20 is silent on A01 and fires when the same DG1 rides a P12",
          arguments: ["adt_a01_v26.hl7", "adt_a01_v271.hl7"])
    func dg1TriggerGate(_ file: String) throws {
        let wire = try Self.load(file)
        #expect(try Self.reports(wire, .conditionalFieldMissing, "DG1", 20) == false)
        let p12 = Self.setting(wire, "MSH", 9, to: "BAR^P12^BAR_P12")
        #expect(try Self.reports(p12, .conditionalFieldMissing, "DG1", 20))
    }

    @Test("PRT one-of rule and PRT-7 prohibition on the wire (PRT-7 may only be valued with PRT-5)",
          arguments: ["oru_r01_v271.hl7", "oru_r01_v282.hl7"])
    func prtRules(_ file: String) throws {
        let wire = try Self.load(file)
        // Shipped: PRT-5 valued; PRT-7..10 empty. Nothing fires.
        #expect(try Self.reports(wire, .conditionalFieldMissing, "PRT", 5) == false)
        #expect(try Self.reports(wire, .conditionalFieldProhibited, "PRT", 7) == false)
        // PRT-7 valued alongside PRT-5: allowed.
        let withUnit = Self.setting(wire, "PRT", 7, to: "SYN-UNIT^Synthetic unit^L")
        #expect(try Self.reports(withUnit, .conditionalFieldProhibited, "PRT", 7) == false)
        // PRT-5 emptied with no organisation, location or device: the one-of rule fires on PRT-5.
        let noPerson = Self.setting(wire, "PRT", 5, to: "")
        #expect(try Self.reports(noPerson, .conditionalFieldMissing, "PRT", 5))
        // An organisation in place of the person, PRT-7 still valued: PRT-7 is prohibited.
        let organisation = Self.setting(Self.setting(withUnit, "PRT", 5, to: ""), "PRT", 8, to: "SYNTH_LAB")
        #expect(try Self.reports(organisation, .conditionalFieldMissing, "PRT", 5) == false)
        #expect(try Self.reports(organisation, .conditionalFieldProhibited, "PRT", 7))
    }

    @Test("v2.8.2 fields added in v2.7 and later read back from the fixtures together")
    func v282LaterFields() throws {
        let adt = try Parser().parse(try Self.load("adt_a01_v282.hl7"))
        #expect(adt["PID-40.1"] == nil || adt["PID-40.1"] == "")
        #expect(adt["PID-40.2"] == "PRN")
        #expect(adt["PID-40.3"] == "PH")
        let oru = try Parser().parse(try Self.load("oru_r01_v282.hl7"))
        #expect(oru["PRT-4.1"] == "OP")
        #expect(oru["OBX-26"] == "SIMM")
        #expect(oru["OBX-27.1"] == "SYN-RC1")
        #expect(oru["OBX-28.1"] == "SYN-LPC1")
        #expect(oru["OBX-29"] == "RSLT")
        #expect(oru["OBX-30"] == "UNSP")
        #expect(oru["SPM-4.1"] == "BLD")
        #expect(oru["TQ1-7"] == "20240404080000")
    }

    @Test("v2.8.2 OML: OBR-7 valued; its request leg is registered as not wire-decidable, so emptying it stays silent")
    func v282OmlObservationDateTime() throws {
        // conditional-completeness-audit.md, "OBR-7 request leg" (P1-1): the predicate is
        // the report-message leg, messageCode in (ORU, OUL, OPU) (v2.8.2 CH04 4.5.3.7).
        // If the request leg is ever modelled, this pin flips and the register row goes.
        let wire = try Self.load("oml_o21_v282.hl7")
        let message = try Parser().parse(wire)
        #expect(message["OBR-7"] == "20240405072000")
        #expect(message["SPM-4.1"] == "BLD")
        #expect(try Self.reports(Self.setting(wire, "OBR", 7, to: ""), .conditionalFieldMissing, "OBR", 7) == false)
    }
}
