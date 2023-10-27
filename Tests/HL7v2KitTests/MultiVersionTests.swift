// MultiVersionTests.swift
// v0.3-G1: HL7 v2.3.1 grammar table — exercise that a v2.3.1 wire parses,
// detects its declared version, validates against the v2.3.1 SegmentGrammar
// table (not v2.5.1), and that fields beyond the v2.3.1 cap return nil
// from the shared typed-segment accessors.
// v0.3-G2: HL7 v2.4 grammar table — same shape; v2.4 sits between v2.3.1
// and v2.5.1, exposing the v2.4 additions (PID-31/32 identity flags,
// OBX-15/16, ORC-18/19, MSH-18/19/20) while still capping below v2.5.1.
// v0.3-G3: HL7 v2.3 grammar table — the oldest dialect HL7v2Kit supports;
// MSH caps at 15 (no MSH-16 application-acknowledgement / MSH-17 country
// code), OBX caps at 11 (v2.3 only had the early observation slots).

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Multiversion grammar tables (v0.3-G1/G2/G3: v2.3 / v2.3.1 / v2.4)")
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

    // MARK: - v2.4 (v0.3-G2)

    // v2.4 ADT^A01. v2.4 caps add PID-31 (identityUnknownIndicator) and
    // PID-32 (identityReliabilityCode); the wire populates those slots
    // to exercise the additions while staying below the v2.5 PID-33..39
    // cap. MSH-18 (charset) populated to exercise the v2.4 MSH addition.
    // Pipe count between PID-8 ("M") and PID-31 ("N"): 23 (= 31 - 8).
    private let v24Wire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01|MSG00001|P|2.4|||AL|NE|AU|UNICODE UTF-8\r\
    PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M|||||||||||||||||||||||N|US\r
    """

    @Test("v2.4 wire parses with .version == .v2_4")
    func v24VersionDetected() throws {
        let message = try Parser().parse(v24Wire)
        #expect(message.version == .v2_4)
    }

    @Test("v2.4 wire round-trips byte-perfectly")
    func v24RoundTrip() throws {
        let message = try Parser().parse(v24Wire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == v24Wire)
    }

    @Test("v2.4 validation runs against the v2.4 grammar table, not v2.3.1 / v2.5.1")
    func v24ValidatorUsesV24GrammarTable() throws {
        let message = try Parser().parse(v24Wire)
        let report = Validator().validate(message)
        #expect(report.errors.isEmpty,
                "v2.4 message validated against v2.4 grammar should report no errors, got: \(report.errors.map(\.message))")
    }

    // v0.7-S4: the v2.4 ORC/OBR grammar carries the same four cross-
    // segment / message-context conditions as v2.5.1. Wire shape is a
    // minimal v2.4 ORU^R01 with both placer orders empty — the XOR
    // and OBR-25 conditionals should both fire.
    private let v24ORUBothPlacersEmpty = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|20260619120000||ORU^R01|MSG|P|2.4\r\
    PID|1||X^^^F^MR||Doe^Jane||19800101|F\r\
    ORC|RE|||GROUP|CM\r\
    OBR|1||FIL|GLUC^Glucose\r
    """

    @Test("v2.4 ORC-2 / OBR-2 XOR + OBR-25 conditionals fire under v2.4 grammar")
    func v24CrossSegmentConditionalsFire() throws {
        let message = try Parser().parse(v24ORUBothPlacersEmpty)
        let report = Validator().validate(message)
        let codes = report.errors.map { ($0.location.segmentID, $0.location.fieldIndex) }
        // ORC-2 XOR fires.
        #expect(codes.contains { $0.0 == "ORC" && $0.1 == 2 })
        // OBR-2 XOR fires (symmetric).
        #expect(codes.contains { $0.0 == "OBR" && $0.1 == 2 })
        // OBR-25 fires (messageCode = ORU).
        #expect(codes.contains { $0.0 == "OBR" && $0.1 == 25 })
    }

    // v0.9+ propagation: the v2.4 CH04 cross-segment / message-context
    // conditions (ORC-2/OBR-2 XOR, ORC-3/OBR-3 XOR, ORC-8/OBR-29 child-
    // order, OBR-7/OBR-25 report-message) have verbatim wording in v2.3
    // and v2.3.1 CH04 — the conditions propagated cleanly. This pin
    // exercises the v2.3.1 grammar dispatch on a minimal wire where
    // all conditions fire to confirm the predicates compiled into the
    // v2.3.1 grammar table.
    private let v231ORUBothPlacersEmpty = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|20260619120000||ORU^R01|MSG|P|2.3.1\r\
    PID|1||X^^^F^MR||Doe^Jane||19800101|F\r\
    ORC|RE|||GROUP|CM\r\
    OBR|1|||GLUC^Glucose\r
    """

    @Test("v2.3.1 ORC/OBR cross-segment conditions fire under v2.3.1 grammar")
    func v231CrossSegmentConditionalsFire() throws {
        let message = try Parser().parse(v231ORUBothPlacersEmpty)
        let report = Validator().validate(message)
        let codes = report.errors.map { ($0.location.segmentID, $0.location.fieldIndex) }
        // ORC-2 + OBR-2 placer XOR.
        #expect(codes.contains { $0.0 == "ORC" && $0.1 == 2 })
        #expect(codes.contains { $0.0 == "OBR" && $0.1 == 2 })
        // ORC-3 + OBR-3 filler XOR.
        #expect(codes.contains { $0.0 == "ORC" && $0.1 == 3 })
        #expect(codes.contains { $0.0 == "OBR" && $0.1 == 3 })
        // OBR-7 + OBR-25 message-context.
        #expect(codes.contains { $0.0 == "OBR" && $0.1 == 7 })
        #expect(codes.contains { $0.0 == "OBR" && $0.1 == 25 })
    }

    @Test("v2.4 SegmentGrammarTable populated for all 15 segments with v2.4 caps")
    func v24GrammarTablePopulated() {
        let table = SegmentGrammarTable.v2_4
        #expect(table["MSH"]?.fields.count == 20)   // v2.3.1 was 17, v2.5.1 is 21
        #expect(table["PID"]?.fields.count == 32)   // v2.3.1 was 30, v2.5.1 is 39
        #expect(table["ORC"]?.fields.count == 19)   // v2.3.1 was 17, v2.5.1 is 31
        #expect(table["OBX"]?.fields.count == 16)   // v2.3.1 was 14, v2.5.1 is 17
        #expect(table["OBR"]?.fields.count == 47)   // matches v2.5.1
        #expect(table["NK1"]?.fields.count == 13)
        #expect(table["PV1"]?.fields.count == 20)
        #expect(table["NTE"]?.fields.count == 3)    // NTE-4 was added in v2.5
        #expect(table["AL1"]?.fields.count == 6)
        // v0.6 T-back-port additions:
        #expect(table["EVN"]?.fields.count == 7)
        #expect(table["MSA"]?.fields.count == 6)
        #expect(table["ERR"]?.fields.count == 1)    // v2.4 had only ERR-1 (CM); v2.5+ expanded to 12
        #expect(table["PD1"]?.fields.count == 21)
        #expect(table["DG1"]?.fields.count == 19)   // v2.5.1 added DG1-20/21
        #expect(table["IN1"]?.fields.count == 25)
    }

    @Test("v2.4 typed accessors for v2.5-only PID fields return nil on a v2.4 wire")
    func v24ExtendedFieldsReturnNilForV25Additions() throws {
        let message = try Parser().parse(v24Wire)
        let pid = try #require(message.firstSegment(PID.self))
        // v2.4 caps PID at 32, so PID-31 + PID-32 ARE populated.
        #expect(pid.identityUnknownIndicator == "N")
        #expect(pid.identityReliabilityCode == "US")
        // v2.5-only fields (PID-33..39) stay nil.
        #expect(pid.lastUpdateDateTime == nil)
        #expect(pid.speciesCode == nil)
        #expect(pid.tribalCitizenship == nil)
    }

    @Test("All three grammar tables (v2.3.1 / v2.4 / v2.5.1) are distinct dispatched")
    func threeWayGrammarDispatch() {
        // Same segment ID, three different field counts — the table
        // shape encodes the version progression.
        let pid231 = SegmentGrammarTable.v2_3_1["PID"]?.fields.count
        let pid24  = SegmentGrammarTable.v2_4["PID"]?.fields.count
        let pid251 = SegmentGrammarTable.v2_5_1["PID"]?.fields.count
        #expect(pid231 == 30)
        #expect(pid24  == 32)
        #expect(pid251 == 39)
        #expect(pid231! < pid24!)
        #expect(pid24!  < pid251!)
    }

    // MARK: - v2.3 (v0.3-G3)

    // v2.3 ADT^A01. v2.3 is the oldest dialect we support; MSH caps at
    // 15 (no MSH-16 application-acknowledgement, MSH-17 country code,
    // MSH-18 charset). The wire stays minimal — v2.3 traffic in the
    // AU corpus is almost entirely admin/order messages with sparse
    // PID populations.
    private let v23Wire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01|MSG00001|P|2.3\r\
    PID|1||123456^^^HOSP^MR||Smith^John||19800101|M\r
    """

    @Test("v2.3 wire parses with .version == .v2_3")
    func v23VersionDetected() throws {
        let message = try Parser().parse(v23Wire)
        #expect(message.version == .v2_3)
    }

    @Test("v2.3 wire round-trips byte-perfectly")
    func v23RoundTrip() throws {
        let message = try Parser().parse(v23Wire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == v23Wire)
    }

    @Test("v2.3 validation runs against the v2.3 grammar table")
    func v23ValidatorUsesV23GrammarTable() throws {
        let message = try Parser().parse(v23Wire)
        let report = Validator().validate(message)
        #expect(report.errors.isEmpty,
                "v2.3 message validated against v2.3 grammar should report no errors, got: \(report.errors.map(\.message))")
    }

    @Test("v2.3 SegmentGrammarTable populated for all 9 segments with v2.3 caps")
    func v23GrammarTablePopulated() {
        let table = SegmentGrammarTable.v2_3
        #expect(table["MSH"]?.fields.count == 15)   // smallest MSH surface
        #expect(table["PID"]?.fields.count == 30)   // same as v2.3.1
        #expect(table["ORC"]?.fields.count == 17)   // same as v2.3.1
        #expect(table["OBX"]?.fields.count == 11)   // smallest OBX (v2.3 added 12/13/14 later)
        #expect(table["OBR"]?.fields.count == 43)   // same as v2.3.1
        #expect(table["NK1"]?.fields.count == 13)
        #expect(table["PV1"]?.fields.count == 20)
        #expect(table["NTE"]?.fields.count == 3)
        #expect(table["AL1"]?.fields.count == 6)
    }

    @Test("Four-way grammar dispatch: MSH grows monotonically 15 → 17 → 20 → 21")
    func fourWayGrammarDispatch() {
        let msh23  = SegmentGrammarTable.v2_3["MSH"]?.fields.count
        let msh231 = SegmentGrammarTable.v2_3_1["MSH"]?.fields.count
        let msh24  = SegmentGrammarTable.v2_4["MSH"]?.fields.count
        let msh251 = SegmentGrammarTable.v2_5_1["MSH"]?.fields.count
        #expect(msh23  == 15)
        #expect(msh231 == 17)
        #expect(msh24  == 20)
        #expect(msh251 == 21)
        #expect(msh23! < msh231!)
        #expect(msh231! < msh24!)
        #expect(msh24!  < msh251!)
    }

    @Test("v2.3 typed accessors for fields beyond v2.3 cap return nil on a v2.3 wire")
    func v23ExtendedFieldAccessorsReturnNilOnV23() throws {
        let message = try Parser().parse(v23Wire)
        let pid = try #require(message.firstSegment(PID.self))
        // PID-31..39 (v2.4 / v2.5 additions) all stay nil because the
        // v2.3 wire doesn't populate them.
        #expect(pid.identityUnknownIndicator == nil)
        #expect(pid.identityReliabilityCode == nil)
        #expect(pid.lastUpdateDateTime == nil)
        #expect(pid.speciesCode == nil)
        #expect(pid.tribalCitizenship == nil)
    }
}
