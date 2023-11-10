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

    @Test("v2.3.1 SegmentGrammarTable is populated for all 15 segments")
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
        // v0.12 T-back-port additions (mirror of the v0.6 v2.4 back-port):
        #expect(table["EVN"]?.fields.count == 6)    // v2.4 has 7 (adds Event Facility)
        #expect(table["MSA"]?.fields.count == 6)
        #expect(table["ERR"]?.fields.count == 1)    // single CM field, as in v2.4
        #expect(table["PD1"]?.fields.count == 12)   // v2.4 expanded to 21
        #expect(table["DG1"]?.fields.count == 19)
        #expect(table["IN1"]?.fields.count == 25)
        // v2.3.1 errata delta vs v2.3: DG1-15 Diagnosis Priority retyped
        // NM → ID, and IN1-17 Insured's Relationship retyped IS → CE.
        #expect(table["DG1"]?.field(15)?.dataType == "ID")
        #expect(table["IN1"]?.field(17)?.dataType == "CE")
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

    @Test("v2.3 SegmentGrammarTable populated for all 15 segments with v2.3 caps")
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
        // v0.12 T-back-port additions:
        #expect(table["EVN"]?.fields.count == 6)    // no Event Facility (EVN-7) in v2.3
        #expect(table["MSA"]?.fields.count == 6)
        #expect(table["ERR"]?.fields.count == 1)
        #expect(table["PD1"]?.fields.count == 12)
        #expect(table["DG1"]?.fields.count == 19)
        #expect(table["IN1"]?.fields.count == 25)
        // v2.3 (pre-errata) divergences vs v2.3.1: DG1-15 Diagnosis
        // Priority is NM (v2.3.1 retyped to ID); IN1-17 Insured's
        // Relationship is IS (v2.3.1 retyped to CE).
        #expect(table["DG1"]?.field(15)?.dataType == "NM")
        #expect(table["IN1"]?.field(17)?.dataType == "IS")
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

    // MARK: - v0.12 T-back-port: EVN / MSA / ERR / PD1 / DG1 / IN1 on v2.3 / v2.3.1

    // A v2.3 ADT^A01 carrying EVN + PD1 + DG1 + IN1, plus an ACK-style
    // MSA/ERR pairing exercised separately. Before v0.12 these segments
    // hit the "unknown segment" (Z-segment) path on v2.3 wires; now they
    // dispatch to the v2.3 grammar. Required fields are populated so a
    // well-formed wire reports no errors.
    private let v23AdtWithBackportedSegments = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01|MSG00001|P|2.3\r\
    EVN|A01|20240301120000\r\
    PID|1||123456^^^HOSP^MR||Smith^John||19800101|M\r\
    PD1|||PRIMARY CLINIC\r\
    DG1|1|I9|486^Pneumonia^I9C|||F\r\
    IN1|1|PLAN1^Medibank^L|INS123||Medibank Private\r
    """

    @Test("v2.3 wire with EVN/PD1/DG1/IN1 dispatches to v2.3 grammar (no unknown-segment)")
    func v23BackportedSegmentsRecognised() throws {
        let message = try Parser().parse(v23AdtWithBackportedSegments)
        let report = Validator().validate(message)
        // None of the back-ported segments should surface as unknown/Z.
        let unknowns = report.issues.filter {
            $0.code == .zSegmentPresent || $0.code == .unknownSegment
        }
        #expect(unknowns.isEmpty,
                "Back-ported segments must dispatch to the v2.3 grammar; got \(unknowns.map(\.location.segmentID))")
        // Well-formed wire: no required-field errors either.
        #expect(report.errors.isEmpty,
                "v2.3 back-ported segments on a well-formed wire should report no errors; got \(report.errors.map(\.message))")
    }

    // Negative pin: DG1 with its required fields (DG1-1 Set ID, DG1-2
    // Coding Method, DG1-6 Type) empty must fire requiredFieldMissing
    // under the v2.3 grammar — proves the grammar is actually enforced,
    // not merely present. DG1-2 is R in v2.3 (vs B in v2.4).
    private let v23DG1MissingRequired = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01|MSG00001|P|2.3\r\
    PID|1||123456^^^HOSP^MR||Smith^John||19800101|M\r\
    DG1\r
    """

    @Test("v2.3 DG1 required-field misses fire under the v2.3 grammar (DG1-2 is R)")
    func v23DG1RequiredFieldsFire() throws {
        let message = try Parser().parse(v23DG1MissingRequired)
        let report = Validator().validate(message)
        let dg1Required = report.errors.filter {
            $0.code == .requiredFieldMissing && $0.location.segmentID == "DG1"
        }
        // DG1-1 (SI, R), DG1-2 (Coding Method, R — v2.3-specific), DG1-6 (Type, R).
        #expect(dg1Required.contains { $0.location.fieldIndex == 1 })
        #expect(dg1Required.contains { $0.location.fieldIndex == 2 },
                "v2.3 DG1-2 Diagnosis Coding Method is R (v2.4 downgraded it to B)")
        #expect(dg1Required.contains { $0.location.fieldIndex == 6 })
    }

    // v2.3.1 wire mirror — confirms the v2.3.1 grammar also carries the
    // back-ported segments.
    private let v231AdtWithBackportedSegments = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01|MSG00001|P|2.3.1\r\
    EVN|A01|20240301120000\r\
    PID|1||123456^^^HOSP^MR||Smith^John||19800101|M\r\
    PD1|||PRIMARY CLINIC\r\
    DG1|1|I9|486^Pneumonia^I9C|||F\r\
    IN1|1|PLAN1^Medibank^L|INS123||Medibank Private\r
    """

    @Test("v2.3.1 wire with EVN/PD1/DG1/IN1 dispatches to v2.3.1 grammar (no unknown-segment)")
    func v231BackportedSegmentsRecognised() throws {
        let message = try Parser().parse(v231AdtWithBackportedSegments)
        let report = Validator().validate(message)
        let unknowns = report.issues.filter {
            $0.code == .zSegmentPresent || $0.code == .unknownSegment
        }
        #expect(unknowns.isEmpty,
                "Back-ported segments must dispatch to the v2.3.1 grammar; got \(unknowns.map(\.location.segmentID))")
        #expect(report.errors.isEmpty,
                "v2.3.1 back-ported segments on a well-formed wire should report no errors; got \(report.errors.map(\.message))")
    }

    // MARK: - v0.14 (ADR-012): HL7 v2.6 grammar — S1 control/notes segments

    @Test("v2.6 wire parses with .version == .v2_6")
    func v26VersionDetected() throws {
        let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01|MSG00001|P|2.6\r"
        let message = try Parser().parse(wire)
        #expect(message.version == .v2_6)
    }

    @Test("v2.6 SegmentGrammarTable carries the S1 control/notes segments with v2.6 field counts")
    func v26GrammarTableS1Populated() {
        let table = SegmentGrammarTable.v2_6
        // v2.6-specific field counts (vs v2.5.1): MSH 25 (was 21; +22..25),
        // MSA 8 (was 6; +7/8 Message Waiting), NTE 8 (was 4; +5..8),
        // EVN 7, ERR 12.
        #expect(table["MSH"]?.fields.count == 25)
        #expect(table["MSA"]?.fields.count == 8)
        #expect(table["NTE"]?.fields.count == 8)
        #expect(table["EVN"]?.fields.count == 7)
        #expect(table["ERR"]?.fields.count == 12)
        // v2.6 systematically renamed TS → DTM: MSH-7 and the EVN date
        // fields are DTM (were TS in v2.5.1).
        #expect(table["MSH"]?.field(7)?.dataType == "DTM")
        #expect(table["EVN"]?.field(2)?.dataType == "DTM")
        // MSH-19 Principal Language: CE → CWE in v2.6.
        #expect(table["MSH"]?.field(19)?.dataType == "CWE")
        // v2.6 MSH additions.
        #expect(table["MSH"]?.field(22)?.name == "Sending Responsible Organization")
        #expect(table["MSH"]?.field(25)?.name == "Receiving Network Address")
        // NTE-4 Comment Type: CE → CWE in v2.6; NTE-6 Entered Date/Time is DTM.
        #expect(table["NTE"]?.field(4)?.dataType == "CWE")
        #expect(table["NTE"]?.field(6)?.dataType == "DTM")
    }

    // A v2.6 ACK-shaped wire carrying MSH + MSA + ERR dispatches to the
    // v2.6 grammar (no unknown-segment on the S1 segments). Other
    // segments (PID etc.) are not yet authored — S2+ — so this wire is
    // deliberately limited to S1 segments.
    private let v26AckWire = """
    MSH|^~\\&|LAB|FAC|HIS|FAC|20240301120000||ACK|MSG00001|P|2.6\r\
    MSA|AA|MSG00001\r\
    NTE|1||All results verified\r
    """

    @Test("v2.6 S1 wire (MSH/MSA/NTE) dispatches to v2.6 grammar, no unknown-segment")
    func v26S1SegmentsRecognised() throws {
        let message = try Parser().parse(v26AckWire)
        #expect(message.version == .v2_6)
        let report = Validator().validate(message)
        let unknowns = report.issues.filter {
            $0.code == .zSegmentPresent || $0.code == .unknownSegment
        }
        #expect(unknowns.isEmpty,
                "v2.6 S1 segments must dispatch to the v2.6 grammar; got \(unknowns.map(\.location.segmentID))")
        #expect(report.errors.isEmpty,
                "well-formed v2.6 MSH/MSA/NTE wire should report no errors; got \(report.errors.map(\.message))")
    }

    @Test("v2.6 SegmentGrammarTable carries the S2a patient-admin segments with v2.6 divergences")
    func v26GrammarTableS2aPopulated() {
        let table = SegmentGrammarTable.v2_6
        // Field counts vs v2.5.1: PD1 22 (was 21; +PD1-22 Advance Directive
        // Last Verified Date), NK1 13, PV1 20, AL1 6 (curation depths held).
        #expect(table["PD1"]?.fields.count == 22)
        #expect(table["NK1"]?.fields.count == 13)
        #expect(table["PV1"]?.fields.count == 20)
        #expect(table["AL1"]?.fields.count == 6)
        // v2.6 CE → CWE migrations (field-by-field, verified against the
        // v2.6 CH03 tables — NOT a blanket rename):
        #expect(table["PD1"]?.field(11)?.dataType == "CWE")   // Publicity Code
        #expect(table["PD1"]?.field(15)?.dataType == "CWE")   // Advance Directive Code
        #expect(table["PD1"]?.field(22)?.name == "Advance Directive Last Verified Date")
        #expect(table["NK1"]?.field(3)?.dataType == "CWE")    // Relationship
        #expect(table["NK1"]?.field(7)?.dataType == "CWE")    // Contact Role
        #expect(table["AL1"]?.field(2)?.dataType == "CWE")    // Allergen Type Code
        #expect(table["AL1"]?.field(3)?.dataType == "CWE")    // Allergen Code
        #expect(table["AL1"]?.field(4)?.dataType == "CWE")    // Allergy Severity Code
        // PV1 (curated to 20) has no CE/TS in range → identical to v2.5.1.
        #expect(table["PV1"]?.field(20)?.dataType == "FC")
    }

    @Test("v2.6 SegmentGrammarTable carries PID (S2b) with all CE→CWE / TS→DTM divergences")
    func v26GrammarTableS2bPIDPopulated() {
        let table = SegmentGrammarTable.v2_6
        let pid = table["PID"]
        #expect(pid?.fields.count == 39)
        // v2.6 renamed every PID TS field to DTM.
        for i in [7, 29, 33] {
            #expect(pid?.field(i)?.dataType == "DTM", "PID-\(i) should be DTM in v2.6")
        }
        // v2.6 migrated every PID CE field to CWE.
        for i in [10, 15, 16, 17, 22, 26, 27, 28, 35, 36, 38] {
            #expect(pid?.field(i)?.dataType == "CWE", "PID-\(i) should be CWE in v2.6")
        }
        // PID-39 Tribal Citizenship was already CWE (v2.5 addition).
        #expect(pid?.field(39)?.dataType == "CWE")
        // Same-segment species/breed conditionals carry over verbatim.
        #expect(pid?.field(35)?.condition == "PID-36 populated OR PID-38 populated")
        #expect(pid?.field(36)?.condition == "PID-37 populated")
    }

    // A v2.6 ADT with a veterinary PID (species/breed populated) exercises
    // that the carried-over PID-35 conditional fires under the v2.6 grammar.
    @Test("v2.6 PID-35 species conditional fires under the v2.6 grammar")
    func v26PIDSpeciesConditionalFires() throws {
        // PID-36 (Breed) populated but PID-35 (Species) empty → PID-35
        // conditional ("PID-36 populated OR PID-38 populated") fires.
        // The base string ends at PID-8 (F); 28 pipes advance f8→f36, so
        // "CANINE^Dog^L" lands in PID-36 (Breed). PID-35/37/38 stay empty,
        // so only PID-35 fires (PID-36's own "PID-37 populated" is false).
        let pid = "PID|1||X^^^F^MR||Doe^Jane||19800101|F" + String(repeating: "|", count: 28) + "CANINE^Dog^L"
        let wire = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240301120000||ADT^A01|MSG|P|2.6\r" + pid + "\r"
        let message = try Parser().parse(wire)
        #expect(message.version == .v2_6)
        let report = Validator().validate(message)
        let pid35 = report.errors.filter {
            $0.code == .conditionalFieldMissing && $0.location.segmentID == "PID" && $0.location.fieldIndex == 35
        }
        #expect(pid35.count == 1,
                "v2.6 PID-35 conditional should fire when PID-36 populated + PID-35 empty; got \(report.errors.map(\.message))")
    }

    @Test("v2.6 SegmentGrammarTable carries ORC (S3a) with v2.6 divergences + carried conditions")
    func v26GrammarTableS3aORCPopulated() {
        let table = SegmentGrammarTable.v2_6
        let orc = table["ORC"]
        #expect(orc?.fields.count == 31)
        // v2.6 TS → DTM on the ORC date fields.
        for i in [9, 15, 27] {
            #expect(orc?.field(i)?.dataType == "DTM", "ORC-\(i) should be DTM in v2.6")
        }
        // v2.6 CE → CWE on the four ORC CE fields (16/17/18/20). The other
        // ORC coded fields (25/26/28/29/31 CWE, 30 CNE) were already
        // CWE/CNE in v2.5.1 — unchanged.
        for i in [16, 17, 18, 20] {
            #expect(orc?.field(i)?.dataType == "CWE", "ORC-\(i) should be CWE in v2.6")
        }
        #expect(orc?.field(30)?.dataType == "CNE")
        // Cross-segment conditions carried over verbatim from v2.5.1.
        #expect(orc?.field(2)?.condition == "OBR-2 empty")
        #expect(orc?.field(8)?.condition == "ORC-1 = CH AND OBR absent OR ORC-1 = CH AND OBR-29 empty")
    }

    @Test("v2.6 SegmentGrammarTable carries OBR (S3b) — 50 fields, CE→CNE on 44/45, conditions")
    func v26GrammarTableS3bOBRPopulated() {
        let table = SegmentGrammarTable.v2_6
        let obr = table["OBR"]
        #expect(obr?.fields.count == 50)   // v2.5.1 had 47; +48/49/50
        // TS → DTM on the OBR date fields.
        for i in [6, 7, 8, 14, 22, 36] {
            #expect(obr?.field(i)?.dataType == "DTM", "OBR-\(i) should be DTM in v2.6")
        }
        // CE → CWE on most coded fields …
        for i in [4, 12, 31, 38, 39, 40, 43, 46, 47, 48, 50] {
            #expect(obr?.field(i)?.dataType == "CWE", "OBR-\(i) should be CWE in v2.6")
        }
        // … but OBR-44/45 (Procedure Code / Modifier) migrated to CNE, not CWE.
        #expect(obr?.field(44)?.dataType == "CNE")
        #expect(obr?.field(45)?.dataType == "CNE")
        // New v2.6 fields.
        #expect(obr?.field(48)?.name == "Medically Necessary Duplicate Procedure Reason")
        #expect(obr?.field(49)?.dataType == "IS")   // Result Handling
        #expect(obr?.field(50)?.name == "Parent Universal Service Identifier")
        // Carried conditions (specimen / report-message / XOR).
        #expect(obr?.field(7)?.condition == "messageCode = ORU OR SPM present OR OBR-15 populated")
        #expect(obr?.field(25)?.condition == "messageCode = ORU")
        #expect(obr?.field(29)?.condition == "ORC-1 = CH AND ORC absent OR ORC-1 = CH AND ORC-8 empty")
    }

    @Test("v2.6 SegmentGrammarTable carries OBX (S3b) — 25 fields, +18..25")
    func v26GrammarTableS3bOBXPopulated() {
        let table = SegmentGrammarTable.v2_6
        let obx = table["OBX"]
        #expect(obx?.fields.count == 25)   // v2.5.1 had 17
        #expect(obx?.field(3)?.dataType == "CWE")   // Observation Identifier CE→CWE
        #expect(obx?.field(6)?.dataType == "CWE")   // Units CE→CWE
        #expect(obx?.field(12)?.dataType == "DTM")  // Effective Date of Ref Range TS→DTM
        #expect(obx?.field(14)?.dataType == "DTM")  // Date/Time of the Observation TS→DTM
        #expect(obx?.field(15)?.dataType == "CWE")  // Producer's ID CE→CWE
        #expect(obx?.field(17)?.dataType == "CWE")  // Observation Method CE→CWE
        // New v2.6 fields 18..25.
        #expect(obx?.field(18)?.name == "Equipment Instance Identifier")
        #expect(obx?.field(22)?.name == "Mood Code")
        #expect(obx?.field(25)?.name == "Performing Organization Medical Director")
        // OBX-2 result-status condition carried.
        #expect(obx?.field(2)?.condition == "OBX-11 != X")
    }

    @Test("v2.6 SegmentGrammarTable carries DG1 (S4) — 26 fields, W on DRG/outlier block")
    func v26GrammarTableS4DG1Populated() {
        let table = SegmentGrammarTable.v2_6
        let dg1 = table["DG1"]
        #expect(dg1?.fields.count == 26)   // v2.5.1 had 21; +22..26
        // DG1-2/4 and the DRG/outlier block 7..14 were withdrawn as of v2.6.
        for i in [2, 4, 7, 8, 9, 10, 11, 12, 13, 14] {
            #expect(dg1?.field(i)?.optionality == .withdrawn, "DG1-\(i) should be W in v2.6")
        }
        #expect(dg1?.field(3)?.dataType == "CWE")   // Diagnosis Code CE→CWE
        #expect(dg1?.field(5)?.dataType == "DTM")   // Diagnosis Date/Time TS→DTM
        #expect(dg1?.field(19)?.dataType == "DTM")  // Attestation Date/Time TS→DTM
        #expect(dg1?.field(23)?.dataType == "CWE")  // DRG CCL Value Code (new)
        // New v2.6 fields 22..26.
        #expect(dg1?.field(22)?.name == "Parent Diagnosis")
        #expect(dg1?.field(26)?.name == "Present On Admission (POA) Indicator")
        // P12-conditioned fields carried from v2.5.1.
        #expect(dg1?.field(20)?.condition == "triggerEvent = P12")
        #expect(dg1?.field(21)?.condition == "triggerEvent = P12")
    }

    @Test("v2.6 SegmentGrammarTable carries IN1 (S4) — CE→CWE on 2/17, TS→DTM on 18")
    func v26GrammarTableS4IN1Populated() {
        let table = SegmentGrammarTable.v2_6
        let in1 = table["IN1"]
        #expect(in1?.fields.count == 25)   // scope mirrors the v2.5.1 IN1 schema
        #expect(in1?.field(2)?.dataType == "CWE")   // Insurance Plan ID CE→CWE
        #expect(in1?.field(17)?.dataType == "CWE")  // Insured's Relationship CE→CWE
        #expect(in1?.field(18)?.dataType == "DTM")  // Insured's DOB TS→DTM
        #expect(in1?.field(14)?.dataType == "AUI")  // Authorization Information unchanged
    }

    // A populated withdrawn (W) field warns, exercising the new .withdrawn
    // optionality end-to-end through checkDeprecation.
    @Test("v2.6 populated withdrawn field (DG1-9) emits a warning")
    func v26WithdrawnFieldWarns() throws {
        // DG1 base ends at DG1-6 (F); 2 pipes advance f6→f9 so "1" lands in
        // DG1-9 (DRG Approval Indicator), which is withdrawn in v2.6.
        let dg1 = "DG1|1||A00.0^Cholera^I10||20240301120000|F" + String(repeating: "|", count: 3) + "1"
        let wire = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240301120000||ADT^A01|MSG|P|2.6\r"
            + "EVN|A01|20240301120000\r"
            + "PID|1||X^^^F^MR||Doe^Jane||19800101|F\r"
            + dg1 + "\r"
        let message = try Parser().parse(wire)
        #expect(message.version == .v2_6)
        let report = Validator().validate(message)
        let warn = report.issues.filter {
            $0.code == .fieldNotSupported && $0.location.segmentID == "DG1" && $0.location.fieldIndex == 9
        }
        #expect(warn.count == 1,
                "populated withdrawn DG1-9 should warn; got \(report.issues.map(\.message))")
    }

    // A well-formed v2.6 ORU^R01 exercises the carried cross-segment /
    // message-context / XOR / specimen conditions end-to-end: every
    // ORU-required conditional (OBR-7, OBR-25, OBX-2) is satisfied and no
    // XOR (ORC-2/3, OBR-2/3) or specimen (OBR-14) condition misfires.
    @Test("v2.6 well-formed ORU validates with no spurious errors (S5 conditional pass)")
    func v26CleanORUHasNoErrors() throws {
        let obr = "OBR|1|PON123|FON456|GLU^Glucose^L|||20240301100000"
            + String(repeating: "|", count: 18) + "F"   // Result Status → OBR-25
        let obx = "OBX|1|NM|GLU^Glucose^L||5.5|mmol/L|||||F"   // OBX-11 (status) → F
        let wire = "MSH|^~\\&|HIS|FAC|LAB|FAC|20240301120000||ORU^R01|MSG1|P|2.6\r"
            + "PID|1||X^^^F^MR||Doe^Jane||19800101|F\r"
            + "ORC|RE|PON123|FON456\r"
            + obr + "\r"
            + obx + "\r"
        let message = try Parser().parse(wire)
        #expect(message.version == .v2_6)
        let report = Validator().validate(message)
        #expect(report.errors.isEmpty,
                "well-formed v2.6 ORU should report no errors; got \(report.errors.map(\.message))")
    }

    // MARK: - v0.15 (ADR-013): HL7 v2.8.2 grammar — S1 control/notes segments

    @Test("v2.8.2 wire parses with .version == .v2_8_2 (distinct from grammar-less .v2_8)")
    func v282VersionDetected() throws {
        let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01|MSG00001|P|2.8.2\r"
        let message = try Parser().parse(wire)
        #expect(message.version == .v2_8_2)
        // The legacy grammar-less case must still resolve for a bare "2.8" wire.
        let v28 = try Parser().parse("MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01|MSG00001|P|2.8\r")
        #expect(v28.version == .v2_8)
    }

    @Test("v2.8.2 SegmentGrammarTable carries the S1 control/notes segments (deltas vs v2.6)")
    func v282GrammarTableS1Populated() {
        let table = SegmentGrammarTable.v2_8_2
        // Field counts held vs v2.6: MSH 25, MSA 8, NTE 8, EVN 7, ERR 12.
        #expect(table["MSH"]?.fields.count == 25)
        #expect(table["MSA"]?.fields.count == 8)
        #expect(table["NTE"]?.fields.count == 8)
        #expect(table["EVN"]?.fields.count == 7)
        #expect(table["ERR"]?.fields.count == 12)
        // MSH is byte-identical to v2.6 (DTM-7, CWE-19 already migrated).
        #expect(table["MSH"]?.field(7)?.dataType == "DTM")
        #expect(table["MSH"]?.field(19)?.dataType == "CWE")
        // v2.8.2 withdrew the legacy backward-compat fields (were B in v2.6).
        #expect(table["MSA"]?.field(3)?.optionality == .withdrawn)
        #expect(table["MSA"]?.field(5)?.optionality == .withdrawn)
        #expect(table["MSA"]?.field(6)?.optionality == .withdrawn)
        #expect(table["ERR"]?.field(1)?.optionality == .withdrawn)
        #expect(table["EVN"]?.field(1)?.optionality == .withdrawn)
        // v2.8.2 IS → CWE migrations (verified per field-def header):
        #expect(table["ERR"]?.field(9)?.dataType == "CWE")   // Inform Person Indicator (was IS)
        #expect(table["EVN"]?.field(4)?.dataType == "CWE")   // Event Reason Code (was IS)
        // Required fields held.
        #expect(table["EVN"]?.field(2)?.optionality == .required)
        #expect(table["ERR"]?.field(3)?.optionality == .required)
        #expect(table["ERR"]?.field(4)?.optionality == .required)
    }

    // A v2.8.2 ACK-shaped wire (MSH/MSA/NTE) dispatches to the v2.8.2
    // grammar — S1 only; PID etc. arrive in later substages.
    private let v282AckWire = """
    MSH|^~\\&|LAB|FAC|HIS|FAC|20240301120000||ACK|MSG00001|P|2.8.2\r\
    MSA|AA|MSG00001\r\
    NTE|1||All results verified\r
    """

    @Test("v2.8.2 S1 wire (MSH/MSA/NTE) dispatches to v2.8.2 grammar, no unknown-segment")
    func v282S1SegmentsRecognised() throws {
        let message = try Parser().parse(v282AckWire)
        #expect(message.version == .v2_8_2)
        let report = Validator().validate(message)
        let unknowns = report.issues.filter {
            $0.code == .zSegmentPresent || $0.code == .unknownSegment
        }
        #expect(unknowns.isEmpty,
                "v2.8.2 S1 segments must dispatch to the v2.8.2 grammar; got \(unknowns.map(\.location.segmentID))")
        #expect(report.errors.isEmpty,
                "well-formed v2.8.2 MSH/MSA/NTE wire should report no errors; got \(report.errors.map(\.message))")
    }

    @Test("v2.8.2 SegmentGrammarTable carries the S2 patient-admin segments (deltas vs v2.6)")
    func v282GrammarTableS2Populated() {
        let table = SegmentGrammarTable.v2_8_2
        // Field counts: PID 40 (was 39; +PID-40 Telecommunication Info), PD1 22,
        // NK1 13 (curated), PV1 20 (curated), AL1 6.
        #expect(table["PID"]?.fields.count == 40)
        #expect(table["PD1"]?.fields.count == 22)
        #expect(table["NK1"]?.fields.count == 13)
        #expect(table["PV1"]?.fields.count == 20)
        #expect(table["AL1"]?.fields.count == 6)

        // PID: IS→CWE on 8/32; B→W on 2/4/9/12/19/20/28; O→B on 13/14;
        // PID-40 new (XTN); PID-3/5 stay R.
        #expect(table["PID"]?.field(8)?.dataType == "CWE")
        #expect(table["PID"]?.field(32)?.dataType == "CWE")
        for i in [2, 4, 9, 12, 19, 20, 28] {
            #expect(table["PID"]?.field(i)?.optionality == .withdrawn, "PID-\(i) should be W in v2.8.2")
        }
        #expect(table["PID"]?.field(13)?.optionality == .backwardCompat)
        #expect(table["PID"]?.field(14)?.optionality == .backwardCompat)
        #expect(table["PID"]?.field(40)?.name == "Patient Telecommunication Information")
        #expect(table["PID"]?.field(3)?.optionality == .required)
        #expect(table["PID"]?.field(5)?.optionality == .required)
        // v2.8.2 dropped the v2.6 veterinary conditionals: PID-35 (renamed
        // Taxonomic Classification Code) is O with no condition; PID-36 is B.
        #expect(table["PID"]?.field(35)?.name == "Taxonomic Classification Code")
        #expect(table["PID"]?.field(35)?.optionality == .optional)
        #expect(table["PID"]?.field(35)?.condition == nil)
        #expect(table["PID"]?.field(36)?.optionality == .backwardCompat)

        // PD1: IS→CWE wave; PD1-4 withdrawn; PD1-12/13 → B; PD1-15 → C.
        for i in [1, 2, 5, 6, 7, 8, 16, 19, 20, 21] {
            #expect(table["PD1"]?.field(i)?.dataType == "CWE", "PD1-\(i) should be CWE in v2.8.2")
        }
        #expect(table["PD1"]?.field(4)?.optionality == .withdrawn)
        #expect(table["PD1"]?.field(12)?.optionality == .backwardCompat)
        #expect(table["PD1"]?.field(15)?.optionality == .conditional)

        // PV1: IS→CWE wave; PV1-9 → B; PV1-2 stays R.
        for i in [2, 4, 10, 12, 13, 14, 15, 16, 18] {
            #expect(table["PV1"]?.field(i)?.dataType == "CWE", "PV1-\(i) should be CWE in v2.8.2")
        }
        #expect(table["PV1"]?.field(2)?.optionality == .required)
        #expect(table["PV1"]?.field(9)?.optionality == .backwardCompat)

        // AL1-6 withdrawn (was B in v2.6); AL1-1/3 stay R.
        #expect(table["AL1"]?.field(6)?.optionality == .withdrawn)
        #expect(table["AL1"]?.field(1)?.optionality == .required)
        #expect(table["AL1"]?.field(3)?.optionality == .required)

        // NK1 (curated 13) is unchanged from v2.6.
        #expect(table["NK1"]?.field(3)?.dataType == "CWE")
        #expect(table["NK1"]?.field(1)?.optionality == .required)
    }

    @Test("v2.8.2 SegmentGrammarTable carries the S3 order/observation segments (deltas vs v2.6)")
    func v282GrammarTableS3Populated() {
        let table = SegmentGrammarTable.v2_8_2
        // Field counts: ORC 34 (was 31; +32/33/34), OBR 54 (was 50; +51..54),
        // OBX 30 (was 25; +26..30).
        #expect(table["ORC"]?.fields.count == 34)
        #expect(table["OBR"]?.fields.count == 54)
        #expect(table["OBX"]?.fields.count == 30)

        // ORC: EI→EIP on 4; 7→W; 8 C→O (condition dropped); O→B wave;
        // 26 O→C; 31 O→B; carried 2/3 conditions.
        #expect(table["ORC"]?.field(4)?.dataType == "EIP")
        #expect(table["ORC"]?.field(7)?.optionality == .withdrawn)
        #expect(table["ORC"]?.field(8)?.optionality == .optional)
        #expect(table["ORC"]?.field(8)?.condition == nil)
        for i in [10, 11, 12, 17, 18, 19, 21, 22, 23, 24, 31] {
            #expect(table["ORC"]?.field(i)?.optionality == .backwardCompat, "ORC-\(i) should be B in v2.8.2")
        }
        #expect(table["ORC"]?.field(26)?.optionality == .conditional)
        #expect(table["ORC"]?.field(2)?.condition == "OBR-2 empty")
        #expect(table["ORC"]?.field(3)?.condition == "OBR-3 empty")

        // OBR: 5/6/14/15/27→W; 13 ST→CWE; 49 IS→CWE; 29 C→O (XOR dropped);
        // 10/16/28/32/33/34/35/50→B; 48 O→C; carried 2/3/7/25 conditions.
        for i in [5, 6, 14, 15, 27] {
            #expect(table["OBR"]?.field(i)?.optionality == .withdrawn, "OBR-\(i) should be W in v2.8.2")
        }
        #expect(table["OBR"]?.field(13)?.dataType == "CWE")
        #expect(table["OBR"]?.field(49)?.dataType == "CWE")
        #expect(table["OBR"]?.field(29)?.optionality == .optional)
        for i in [10, 16, 28, 32, 33, 34, 35, 50] {
            #expect(table["OBR"]?.field(i)?.optionality == .backwardCompat, "OBR-\(i) should be B in v2.8.2")
        }
        #expect(table["OBR"]?.field(48)?.optionality == .conditional)
        #expect(table["OBR"]?.field(54)?.name == "Parent Order")
        #expect(table["OBR"]?.field(25)?.condition == "messageCode = ORU")

        // OBX: 4 ST→OG; 8 IS→CWE + renamed "Interpretation Codes";
        // 15/16/18/23/24/25→B; +26..30 new; OBX-2 condition carried.
        #expect(table["OBX"]?.field(4)?.dataType == "OG")
        #expect(table["OBX"]?.field(8)?.dataType == "CWE")
        #expect(table["OBX"]?.field(8)?.name == "Interpretation Codes")
        for i in [15, 16, 18, 23, 24, 25] {
            #expect(table["OBX"]?.field(i)?.optionality == .backwardCompat, "OBX-\(i) should be B in v2.8.2")
        }
        #expect(table["OBX"]?.field(30)?.name == "Observation Sub-Type")
        #expect(table["OBX"]?.field(2)?.condition == "OBX-11 != X")
    }

    @Test("v2.8.2 SegmentGrammarTable carries the S4 financial segments (deltas vs v2.6)")
    func v282GrammarTableS4Populated() {
        let table = SegmentGrammarTable.v2_8_2
        #expect(table["DG1"]?.fields.count == 26)
        #expect(table["IN1"]?.fields.count == 25)   // curated scope mirrors v2.6

        // DG1: IS→CWE on 6/17/25/26; ID→NM on 15; DG1-22 O→C; withdrawn
        // block 2/4/7..14 held; P12 conditions on 20/21 carried.
        #expect(table["DG1"]?.field(6)?.dataType == "CWE")
        #expect(table["DG1"]?.field(15)?.dataType == "NM")
        #expect(table["DG1"]?.field(17)?.dataType == "CWE")
        #expect(table["DG1"]?.field(25)?.dataType == "CWE")
        #expect(table["DG1"]?.field(26)?.dataType == "CWE")
        #expect(table["DG1"]?.field(22)?.optionality == .conditional)
        for i in [2, 4, 7, 8, 9, 10, 11, 12, 13, 14] {
            #expect(table["DG1"]?.field(i)?.optionality == .withdrawn, "DG1-\(i) should be W in v2.8.2")
        }
        #expect(table["DG1"]?.field(20)?.condition == "triggerEvent = P12")
        #expect(table["DG1"]?.field(21)?.condition == "triggerEvent = P12")

        // IN1: IN1-2 renamed "Health Plan ID" (CWE R); IS→CWE on 15/20/21;
        // TS→DTM on 18 held.
        #expect(table["IN1"]?.field(2)?.name == "Health Plan ID")
        #expect(table["IN1"]?.field(2)?.optionality == .required)
        #expect(table["IN1"]?.field(15)?.dataType == "CWE")
        #expect(table["IN1"]?.field(20)?.dataType == "CWE")
        #expect(table["IN1"]?.field(21)?.dataType == "CWE")
        #expect(table["IN1"]?.field(18)?.dataType == "DTM")
    }

    // S5 conditional pass: a well-formed v2.8.2 ORU^R01. Every ORU-required
    // conditional (OBR-7, OBR-25, OBX-2) is satisfied; the v2.6 XOR/parent
    // conditions that v2.8.2 dropped (ORC-8, OBR-29) no longer apply, and no
    // carried condition (ORC-2/3, OBR-2/3) misfires.
    @Test("v2.8.2 well-formed ORU validates with no spurious errors (S5 conditional pass)")
    func v282CleanORUHasNoErrors() throws {
        let obr = "OBR|1|PON123|FON456|GLU^Glucose^L|||20240301100000"
            + String(repeating: "|", count: 18) + "F"   // Result Status → OBR-25
        let obx = "OBX|1|NM|GLU^Glucose^L||5.5|mmol/L|||||F"   // OBX-11 (status) → F
        let wire = "MSH|^~\\&|HIS|FAC|LAB|FAC|20240301120000||ORU^R01|MSG1|P|2.8.2\r"
            + "PID|1||X^^^F^MR||Doe^Jane||19800101|F\r"
            + "ORC|RE|PON123|FON456\r"
            + obr + "\r"
            + obx + "\r"
        let message = try Parser().parse(wire)
        #expect(message.version == .v2_8_2)
        let report = Validator().validate(message)
        #expect(report.errors.isEmpty,
                "well-formed v2.8.2 ORU should report no errors; got \(report.errors.map(\.message))")
    }
}
