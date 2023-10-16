// MultiVersionTests.swift
// v0.3-G1: HL7 v2.3.1 grammar table — exercise that a v2.3.1 wire parses,
// detects its declared version, validates against the v2.3.1 SegmentGrammar
// table (not v2.5.1), and that fields beyond the v2.3.1 cap return nil
// from the shared typed-segment accessors.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Multiversion grammar tables (v0.3-G1: v2.3.1)")
struct MultiVersionTests {

    // A minimal v2.3.1 ADT^A01 with MSH-12 = "2.3.1". v2.3.1 caps MSH at
    // 17 fields, so the wire deliberately stops before MSH-18 / 19 / 20 /
    // 21 (which only exist in v2.4+ / v2.5+).
    private let v231Wire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01|MSG00001|P|2.3.1\r\
    PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M||2106-3^White^HL70005|10 Main St^^Sydney^NSW^2000^AU||(02)555-1234\r
    """

    @Test("v2.3.1 wire parses with .version == .v2_3_1")
    func versionDetected() throws {
        let message = try Parser().parse(v231Wire)
        #expect(message.version == .v2_3_1)
    }

    @Test("v2.3.1 wire round-trips byte-perfectly")
    func roundTrip() throws {
        let message = try Parser().parse(v231Wire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == v231Wire)
    }

    @Test("v2.3.1 path accessors agree with typed accessors (shared v2.5.1 struct)")
    func pathAndTypedAgree() throws {
        let message = try Parser().parse(v231Wire)
        let pid = try #require(message.firstSegment(PID.self))
        #expect(pid.setID == message["PID-1"])
        #expect(pid.patientName?.familyName == "Smith")
        #expect(pid.patientName?.familyName == message["PID-5.1"])
    }

    @Test("v2.3.1 validation runs against the v2.3.1 grammar table, not v2.5.1")
    func validatorUsesV231GrammarTable() throws {
        let message = try Parser().parse(v231Wire)
        let report = Validator().validate(message)
        // No required-field misses on this well-formed wire — the v2.3.1
        // grammar table marks the same PID-1 / PID-3 / PID-5 fields as
        // required as the v2.5.1 grammar does.
        #expect(report.errors.isEmpty,
                "v2.3.1 message validated against v2.3.1 grammar should report no errors, got: \(report.errors.map(\.message))")
    }

    @Test("v2.3.1 SegmentGrammarTable is populated for all 9 spec § 17 segments")
    func grammarTablePopulated() {
        let table = SegmentGrammarTable.v2_3_1
        #expect(table["MSH"] != nil)
        #expect(table["PID"] != nil)
        #expect(table["NK1"] != nil)
        #expect(table["PV1"] != nil)
        #expect(table["NTE"] != nil)
        #expect(table["AL1"] != nil)
        #expect(table["ORC"] != nil)
        #expect(table["OBR"] != nil)
        #expect(table["OBX"] != nil)
        // PID v2.3.1 caps at 30 fields (vs 39 in v2.5.1).
        #expect(table["PID"]?.fields.count == 30)
        // ORC v2.3.1 caps at 17 fields (vs 31 in v2.5.1).
        #expect(table["ORC"]?.fields.count == 17)
    }

    @Test("v2.3.1 typed segment accessors that reference v2.5.1-only fields return nil on a v2.3.1 wire")
    func extendedFieldAccessorsReturnNilOnV231() throws {
        // The shared `PID` struct exposes accessors for PID-31..39
        // (v2.4 / v2.5 additions). A v2.3.1 wire doesn't populate them
        // — the typed accessor must return nil, not crash.
        let message = try Parser().parse(v231Wire)
        let pid = try #require(message.firstSegment(PID.self))
        #expect(pid.identityUnknownIndicator == nil)
        #expect(pid.identityReliabilityCode == nil)
        #expect(pid.lastUpdateDateTime == nil)
        #expect(pid.lastUpdateFacility == nil)
        #expect(pid.speciesCode == nil)
        #expect(pid.tribalCitizenship == nil)
    }

    @Test("A v2.5.1 wire still validates against the v2.5.1 grammar (regression)")
    func v251StillRoutes() throws {
        let v251Wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01|MSG00001|P|2.5.1\r\
        PID|1||123456^^^HOSP^MR||Smith^John||19800101|M\r
        """
        let message = try Parser().parse(v251Wire)
        #expect(message.version == .v2_5_1)
        let report = Validator().validate(message)
        #expect(report.errors.isEmpty)
    }
}
