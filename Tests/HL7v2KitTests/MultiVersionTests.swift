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
    private static let v231Wire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01|MSG00001|P|2.3.1\r\
    PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M||2106-3^White^HL70005|10 Main St^^Sydney^NSW^2000^AU||(02)555-1234\r
    """

    // R9/F10: the per-version detected / round-trip / validator triple was
    // duplicated verbatim for v2.3 / v2.3.1 / v2.4 (and the detected leg
    // again for v2.6 / v2.8.2 / bare-2.8) — folded into three parameterized
    // tests over shared row tables. Grammar-table PIN tests stay
    // per-version below: their assertions are spec data, not mechanics.

    private static let detectedRows: [(wire: String, version: Version)] = [
        (v231Wire, .v2_3_1),
        (v24Wire, .v2_4),
        (v23Wire, .v2_3),
        ("MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01^ADT_A01|MSG00001|P|2.6\r", .v2_6),
        ("MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01^ADT_A01|MSG00001|P|2.8.2\r", .v2_8_2),
        // A bare "2.8" wire still resolves to .v2_8 (validated as v2.8.2, ADR-018).
        ("MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01|MSG00001|P|2.8\r", .v2_8),
    ]

    private static let tripleRows: [(wire: String, version: Version)] = [
        (v231Wire, .v2_3_1),
        (v24Wire, .v2_4),
        (v23Wire, .v2_3),
    ]

    @Test("wire parses with its own declared version", arguments: detectedRows)
    func versionDetected(_ row: (wire: String, version: Version)) throws {
        let message = try Parser().parse(row.wire)
        #expect(message.version == row.version)
    }

    @Test("wire round-trips byte-perfectly", arguments: tripleRows)
    func versionRoundTrip(_ row: (wire: String, version: Version)) throws {
        let message = try Parser().parse(row.wire)
        let rebuilt = String(data: message.serialize(), encoding: .utf8)
        #expect(rebuilt == row.wire)
    }

    @Test("validation runs against the wire's own grammar table", arguments: tripleRows)
    func validatorUsesOwnGrammar(_ row: (wire: String, version: Version)) throws {
        let message = try Parser().parse(row.wire)
        let report = Validator().validate(message)
        // No required-field misses on these well-formed wires — each
        // version's grammar table marks the same PID-1 / PID-3 / PID-5
        // fields as required as the v2.5.1 grammar does.
        #expect(report.errors.isEmpty,
                "\(row.version) message validated against its own grammar should report no errors, got: \(report.errors.map(\.message))")
    }

    @Test("v2.3.1 path accessors agree with typed accessors (shared v2.5.1 struct)")
    func pathAndTypedAgree() throws {
        let message = try Parser().parse(Self.v231Wire)
        let pid = try #require(message.firstSegment(PID.self))
        #expect(pid.setID == message["PID-1"])
        #expect(pid.patientName?.familyName == "Smith")
        #expect(pid.patientName?.familyName == message["PID-5.1"])
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
        // ORC v2.3.1 has 24 fields (vs 31 in v2.5.1). v1.6 depth audit: was pinned at 17,
        // which was the authored depth, not the spec's (ORC-18..24 were never authored).
        #expect(table["ORC"]?.fields.count == 24)
        // v0.12 T-back-port additions (mirror of the v0.6 v2.4 back-port):
        #expect(table["EVN"]?.fields.count == 6)    // v2.4 has 7 (adds Event Facility)
        #expect(table["MSA"]?.fields.count == 6)
        #expect(table["ERR"]?.fields.count == 1)    // single CM field, as in v2.4
        #expect(table["PD1"]?.fields.count == 12)   // v2.4 expanded to 21
        #expect(table["DG1"]?.fields.count == 19)
        #expect(table["IN1"]?.fields.count == 49)   // v1.2: full per-version depth (was curated 25)
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
        let message = try Parser().parse(Self.v231Wire)
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
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01^ADT_A01|MSG00001|P|2.5.1\r\
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
    private static let v24Wire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01|MSG00001|P|2.4|||AL|NE|AU|ASCII\r\
    PID|1||123456^^^HOSP^MR||Smith^John^A||19800101|M|||||||||||||||||||||||N|US\r
    """

    // v0.7-S4: the v2.4 ORC/OBR grammar carries the same four cross-
    // segment / message-context conditions as v2.5.1. Wire shape is a
    // minimal v2.4 ORU^R01 with both placer orders empty and a filler id
    // in OBR-3. Since P4-7 the order-number rule is placer-or-filler, so
    // the filler id satisfies it (v2.4 CH04 §4.5.1.1 SN table notes print
    // a null ORC-2 beside a valued filler number); OBR-25 still fires.
    private let v24ORUBothPlacersEmpty = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|20260619120000||ORU^R01|MSG|P|2.4\r\
    PID|1||X^^^F^MR||Doe^Jane||19800101|F\r\
    ORC|RE|||GROUP|CM\r\
    OBR|1||FIL|GLUC^Glucose\r
    """

    @Test("v2.4 filler id satisfies ORC-2 / OBR-2; OBR-25 fires under v2.4 grammar")
    func v24FillerIDSatisfiesPlacerAndOBR25Fires() throws {
        let message = try Parser().parse(v24ORUBothPlacersEmpty)
        let report = Validator().validate(message)
        let codes = report.errors.map { ($0.location.segmentID, $0.location.fieldIndex) }
        // Placer-or-filler: OBR-3 carries the filler id, so neither placer field fires.
        #expect(!codes.contains { $0.0 == "ORC" && $0.1 == 2 })
        #expect(!codes.contains { $0.0 == "OBR" && $0.1 == 2 })
        // OBR-25 fires (messageCode in (ORU, ORF, OUL)).
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
        // v1.6 depth audit: MSH/PID/ORC/OBX/NTE were pinned at their authored depth, not
        // the spec's. Corrected against the v2.4 attribute tables.
        #expect(table["MSH"]?.fields.count == 21)   // was 20; MSH-21 Conformance Statement ID
        #expect(table["PID"]?.fields.count == 38)   // was 32; PID-33..38
        #expect(table["ORC"]?.fields.count == 25)   // was 19; ORC-20..25
        #expect(table["OBX"]?.fields.count == 19)   // was 16; OBX-17..19
        #expect(table["OBR"]?.fields.count == 47)   // matches v2.5.1
        #expect(table["NK1"]?.fields.count == 37)   // v1.2: full per-version depth (was curated 13)
        #expect(table["PV1"]?.fields.count == 52)   // v1.2: full per-version depth (was curated 20)
        #expect(table["NTE"]?.fields.count == 4)    // was 3; NTE-4 Comment Type exists in v2.4
        #expect(table["AL1"]?.fields.count == 6)
        // v0.6 T-back-port additions:
        #expect(table["EVN"]?.fields.count == 7)
        #expect(table["MSA"]?.fields.count == 6)
        #expect(table["ERR"]?.fields.count == 1)    // v2.4 had only ERR-1 (CM); v2.5+ expanded to 12
        #expect(table["PD1"]?.fields.count == 21)
        #expect(table["DG1"]?.fields.count == 19)   // v2.5.1 added DG1-20/21
        #expect(table["IN1"]?.fields.count == 49)   // v1.2: full per-version depth (was curated 25)
    }

    @Test("v2.4 typed accessors for v2.5-only PID fields return nil on a v2.4 wire")
    func v24ExtendedFieldsReturnNilForV25Additions() throws {
        let message = try Parser().parse(Self.v24Wire)
        let pid = try #require(message.firstSegment(PID.self))
        // v2.4 PID reaches 38, so PID-31 + PID-32 ARE populated.
        #expect(pid.identityUnknownIndicator == "N")
        #expect(pid.identityReliabilityCode == "US")
        // PID-33..38 exist in v2.4 but are absent from this wire; PID-39 is v2.5-only.
        // Either way the accessors read the wire, so all three stay nil.
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
        #expect(pid24  == 38)   // v1.6: was 32 (authored depth)
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
    private static let v23Wire = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01|MSG00001|P|2.3\r\
    PID|1||123456^^^HOSP^MR||Smith^John||19800101|M\r
    """

    @Test("v2.3 SegmentGrammarTable populated for all 15 segments with v2.3 caps")
    func v23GrammarTablePopulated() {
        let table = SegmentGrammarTable.v2_3
        // v1.6 depth audit: MSH/ORC/OBX were pinned at their authored depth, not the
        // spec's. Corrected against the v2.3 attribute tables (CH2 / CH4 / CH7).
        #expect(table["MSH"]?.fields.count == 19)   // was 15; MSH-16..19
        #expect(table["PID"]?.fields.count == 30)   // same as v2.3.1
        #expect(table["ORC"]?.fields.count == 19)   // was 17; ORC-18/19
        #expect(table["OBX"]?.fields.count == 17)   // was 11; OBX-12..17
        #expect(table["OBR"]?.fields.count == 43)   // same as v2.3.1
        #expect(table["NK1"]?.fields.count == 37)   // v1.2: full per-version depth (was curated 13)
        #expect(table["PV1"]?.fields.count == 52)   // v1.2: full per-version depth (was curated 20)
        #expect(table["NTE"]?.fields.count == 3)
        #expect(table["AL1"]?.fields.count == 6)
        // v0.12 T-back-port additions:
        #expect(table["EVN"]?.fields.count == 6)    // no Event Facility (EVN-7) in v2.3
        #expect(table["MSA"]?.fields.count == 6)
        #expect(table["ERR"]?.fields.count == 1)
        #expect(table["PD1"]?.fields.count == 12)
        #expect(table["DG1"]?.fields.count == 19)
        #expect(table["IN1"]?.fields.count == 49)   // v1.2: full per-version depth (was curated 25)
        // v2.3 (pre-errata) divergences vs v2.3.1: DG1-15 Diagnosis
        // Priority is NM (v2.3.1 retyped to ID); IN1-17 Insured's
        // Relationship is IS (v2.3.1 retyped to CE).
        #expect(table["DG1"]?.field(15)?.dataType == "NM")
        #expect(table["IN1"]?.field(17)?.dataType == "IS")
    }

    @Test("Four-way grammar dispatch: MSH grows 19 → 20 → 21 → 21 across dialects")
    func fourWayGrammarDispatch() {
        let msh23  = SegmentGrammarTable.v2_3["MSH"]?.fields.count
        let msh231 = SegmentGrammarTable.v2_3_1["MSH"]?.fields.count
        let msh24  = SegmentGrammarTable.v2_4["MSH"]?.fields.count
        let msh251 = SegmentGrammarTable.v2_5_1["MSH"]?.fields.count
        // v1.6 depth audit corrected v2.3 (15 → 19), v2.3.1 (17 → 20) and v2.4 (20 → 21).
        // Growth is non-decreasing, not strictly increasing: v2.4 and v2.5.1 both carry 21
        // fields (v2.5 renamed MSH-21 Conformance Statement ID → Message Profile Identifier
        // and retyped it ID → EI, but added no field).
        #expect(msh23  == 19)
        #expect(msh231 == 20)
        #expect(msh24  == 21)
        #expect(msh251 == 21)
        #expect(msh23! < msh231!)
        #expect(msh231! < msh24!)
        #expect(msh24!  <= msh251!)
    }

    // v1.6 per-version depth audit. Every committed schema's depth was diffed against its
    // own version's attribute table; 46 fields across 14 (version, segment) pairs had never
    // been authored. These pins guard the fills, and the element-name assertions guard the
    // per-version *naming* divergences that the fill work uncovered — a field can be
    // renamed between versions, so a name must never be copied from the canonical schema.
    @Test("v1.6: per-version depth fills + per-version element-name divergences")
    func v1_6DepthAuditFills() {
        // Depths that were short before the audit.
        #expect(SegmentGrammarTable.v2_3["MSH"]?.fields.count == 19)
        #expect(SegmentGrammarTable.v2_3["OBX"]?.fields.count == 17)
        #expect(SegmentGrammarTable.v2_3["ORC"]?.fields.count == 19)
        #expect(SegmentGrammarTable.v2_3_1["MSH"]?.fields.count == 20)
        #expect(SegmentGrammarTable.v2_3_1["OBR"]?.fields.count == 45)
        #expect(SegmentGrammarTable.v2_3_1["OBX"]?.fields.count == 17)
        #expect(SegmentGrammarTable.v2_3_1["ORC"]?.fields.count == 24)
        #expect(SegmentGrammarTable.v2_3_1["NTE"]?.fields.count == 4)
        #expect(SegmentGrammarTable.v2_4["OBX"]?.fields.count == 19)
        #expect(SegmentGrammarTable.v2_5_1["OBX"]?.fields.count == 25)

        // OBX-12 is renamed twice across the standard — the schemas must not converge.
        #expect(SegmentGrammarTable.v2_3["OBX"]?.field(12)?.name == "Date Last Obs Normal Values")
        #expect(SegmentGrammarTable.v2_3_1["OBX"]?.field(12)?.name == "Date Last Obs Normal Values")
        #expect(SegmentGrammarTable.v2_4["OBX"]?.field(12)?.name == "Date Last Observation Normal Value")
        #expect(SegmentGrammarTable.v2_5_1["OBX"]?.field(12)?.name == "Effective Date of Reference Range Values")
        #expect(SegmentGrammarTable.v2_6["OBX"]?.field(12)?.name == "Effective Date of Reference Range")

        // OBX-15: v2.5.1 alone says "Producer's Reference"; the neighbours say "Producer's ID".
        #expect(SegmentGrammarTable.v2_4["OBX"]?.field(15)?.name == "Producer's ID")
        #expect(SegmentGrammarTable.v2_5_1["OBX"]?.field(15)?.name == "Producer's Reference")
        #expect(SegmentGrammarTable.v2_6["OBX"]?.field(15)?.name == "Producer's ID")

        // MSH-21: renamed AND retyped in v2.5 (ID → EI) without changing the field count.
        #expect(SegmentGrammarTable.v2_4["MSH"]?.field(21)?.name == "Conformance Statement ID")
        #expect(SegmentGrammarTable.v2_4["MSH"]?.field(21)?.dataType == "ID")
        #expect(SegmentGrammarTable.v2_5_1["MSH"]?.field(21)?.name == "Message Profile Identifier")
        #expect(SegmentGrammarTable.v2_5_1["MSH"]?.field(21)?.dataType == "EI")

        // Per-version datatype divergence on a filled field: v2.4 PID-35 Species Code is CE,
        // v2.6 promoted it to CWE. Fills take DT from their own version's table.
        #expect(SegmentGrammarTable.v2_4["PID"]?.field(35)?.dataType == "CE")
        #expect(SegmentGrammarTable.v2_4["PID"]?.fields.count == 38)
    }

    @Test("v2.3 typed accessors for fields beyond v2.3 cap return nil on a v2.3 wire")
    func v23ExtendedFieldAccessorsReturnNilOnV23() throws {
        let message = try Parser().parse(Self.v23Wire)
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
            $0.code == .zSegmentPresent
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
            $0.code == .zSegmentPresent
        }
        #expect(unknowns.isEmpty,
                "Back-ported segments must dispatch to the v2.3.1 grammar; got \(unknowns.map(\.location.segmentID))")
        #expect(report.errors.isEmpty,
                "v2.3.1 back-ported segments on a well-formed wire should report no errors; got \(report.errors.map(\.message))")
    }

    // MARK: - v0.14 (ADR-012): HL7 v2.6 grammar — S1 control/notes segments

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
    MSH|^~\\&|LAB|FAC|HIS|FAC|20240301120000||ACK^A01^ACK|MSG00001|P|2.6\r\
    MSA|AA|MSG00001\r\
    NTE|1||All results verified\r
    """

    @Test("v2.6 S1 wire (MSH/MSA/NTE) dispatches to v2.6 grammar, no unknown-segment")
    func v26S1SegmentsRecognised() throws {
        let message = try Parser().parse(v26AckWire)
        #expect(message.version == .v2_6)
        let report = Validator().validate(message)
        let unknowns = report.issues.filter {
            $0.code == .zSegmentPresent
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
        // Last Verified Date), NK1 39, PV1 52 (v1.2 full per-version depth), AL1 6.
        #expect(table["PD1"]?.fields.count == 22)
        #expect(table["NK1"]?.fields.count == 39)   // v1.2: full per-version depth (was curated 13)
        #expect(table["PV1"]?.fields.count == 52)   // v1.2: full per-version depth (was curated 20)
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
        let wire = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240301120000||ADT^A01^ADT_A01|MSG|P|2.6\r" + pid + "\r"
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
        // P4-7: placer-or-filler; every ORC/OBR-peer leg gated off the OBR-before-ORC
        // structures (OUL, OPU, OPL) until P8 group ranges (G2-6 and fix round 1).
        #expect(orc?.field(2)?.condition
            == "ORC-3 empty AND OBR-2 empty AND OBR-3 empty AND messageCode not in (OUL, OPU, OPL) OR ORC-3 empty AND OBR absent AND messageCode not in (OUL, OPU, OPL)")
        #expect(orc?.field(8)?.condition
            == "ORC-1 = CH AND OBR absent AND messageCode not in (OUL, OPU, OPL) OR ORC-1 = CH AND OBR-29 empty AND messageCode not in (OUL, OPU, OPL)")
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
        #expect(obr?.field(7)?.condition == "messageCode in (ORU, ORF, OUL, OPU)")
        #expect(obr?.field(14)?.optionality == .backwardCompat)
        #expect(obr?.field(14)?.condition == nil)
        #expect(obr?.field(25)?.condition == "messageCode in (ORU, ORF, OUL, OPU)")
        #expect(obr?.field(29)?.condition == "ORC-1 = CH AND ORC-8 empty AND messageCode not in (OUL, OPU, OPL)")
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
        #expect(in1?.fields.count == 53)   // v1.2: full per-version depth (was curated 25)
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
        let wire = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240301120000||ADT^A01^ADT_A01|MSG|P|2.6\r"
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
        let wire = "MSH|^~\\&|HIS|FAC|LAB|FAC|20240301120000||ORU^R01^ORU_R01|MSG1|P|2.6\r"
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
    MSH|^~\\&|LAB|FAC|HIS|FAC|20240301120000||ACK^A01^ACK|MSG00001|P|2.8.2\r\
    MSA|AA|MSG00001\r\
    NTE|1||All results verified\r
    """

    @Test("v2.8.2 S1 wire (MSH/MSA/NTE) dispatches to v2.8.2 grammar, no unknown-segment")
    func v282S1SegmentsRecognised() throws {
        let message = try Parser().parse(v282AckWire)
        #expect(message.version == .v2_8_2)
        let report = Validator().validate(message)
        let unknowns = report.issues.filter {
            $0.code == .zSegmentPresent
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
        // NK1 41 (+40/41 telecom info), PV1 54 (v1.2 full per-version depth), AL1 6.
        #expect(table["PID"]?.fields.count == 40)
        #expect(table["PD1"]?.fields.count == 22)
        #expect(table["NK1"]?.fields.count == 41)   // v1.2: full per-version depth (was curated 13)
        #expect(table["PV1"]?.fields.count == 54)   // v1.2: full per-version depth (was curated 20)
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
        // P4-7 (X-C12): placer-or-filler over both segments, Send Number exempt.
        #expect(table["ORC"]?.field(2)?.condition
            == "ORC-3 empty AND ORC-1 != SN AND OBR-2 empty AND OBR-3 empty AND messageCode not in (OUL, OPU, OPL) OR ORC-3 empty AND ORC-1 != SN AND OBR absent AND messageCode not in (OUL, OPU, OPL)")
        #expect(table["ORC"]?.field(3)?.condition
            == "ORC-2 empty AND ORC-1 != SN AND OBR-2 empty AND OBR-3 empty AND messageCode not in (OUL, OPU, OPL) OR ORC-2 empty AND ORC-1 != SN AND OBR absent AND messageCode not in (OUL, OPU, OPL)")
        #expect(table["OBR"]?.field(2)?.condition
            == "OBR-3 empty AND ORC-2 empty AND ORC-3 empty AND ORC-1 != SN AND messageCode not in (OUL, OPU, OPL) OR OBR-3 empty AND ORC absent AND messageCode in (ORU, ORF)")
        #expect(table["OBR"]?.field(3)?.condition
            == "OBR-2 empty AND ORC-2 empty AND ORC-3 empty AND ORC-1 != SN AND messageCode not in (OUL, OPU, OPL) OR OBR-2 empty AND ORC absent AND messageCode in (ORU, ORF)")

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
        #expect(table["OBR"]?.field(25)?.condition == "messageCode in (ORU, OUL, OPU)")

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
        #expect(table["IN1"]?.fields.count == 55)   // v1.2: full per-version depth (was curated 25)

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
    // conditional (OBR-7, OBR-22, OBR-25, OBX-2) is satisfied; the v2.6
    // XOR/parent conditions that v2.8.2 dropped (ORC-8, OBR-29) no longer
    // apply, and no carried condition (ORC-2/3, OBR-2/3) misfires.
    @Test("v2.8.2 well-formed ORU validates with no spurious errors (S5 conditional pass)")
    func v282CleanORUHasNoErrors() throws {
        let obr = "OBR|1|PON123|FON456|GLU^Glucose^L|||20240301100000"
            + String(repeating: "|", count: 15) + "20240301110000"   // OBR-22, required when OBR-25 is valued (§4.5.3.22)
            + String(repeating: "|", count: 3) + "F"                  // Result Status → OBR-25
        let obx = "OBX|1|NM|GLU^Glucose^L||5.5|mmol/L|||||F"   // OBX-11 (status) → F
        let wire = "MSH|^~\\&|HIS|FAC|LAB|FAC|20240301120000||ORU^R01^ORU_R01|MSG1|P|2.8.2\r"
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

    // MARK: - v0.16 (ROADMAP M2): conditional-completeness — shipped predicates

    @Test("v0.16 M2: PD1-15 and ORC-26 carry the shipped v2.8.2 conditions")
    func v282M2ConditionsPresent() {
        let table = SegmentGrammarTable.v2_8_2
        #expect(table["PD1"]?.field(15)?.condition == "PD1-22 populated")
        #expect(table["ORC"]?.field(26)?.condition == "ORC-20 in (3, 4)")
    }

    // PD1-15 (Advance Directive Code) is required when PD1-22 (Advance
    // Directive Last Verified Date) is valued (v2.8.2 §3.3.11.15).
    @Test("v0.16 M2: PD1-15 conditional fires when PD1-22 populated + PD1-15 empty")
    func v282PD1_15ConditionalFires() throws {
        // PD1-22 populated (a date), PD1-15 empty: 22 pipes after PD1 land
        // the date in PD1-22 (field index = pipe count); PD1-15 stays empty.
        let pd1 = "PD1" + String(repeating: "|", count: 22) + "20240101"
        let wire = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240301120000||ADT^A01^ADT_A01|MSG|P|2.8.2\r"
            + "PID|1||X^^^F^MR||Doe^Jane||19800101|F\r"
            + pd1 + "\r"
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        let hits = report.errors.filter {
            $0.code == .conditionalFieldMissing && $0.location.segmentID == "PD1" && $0.location.fieldIndex == 15
        }
        #expect(hits.count == 1,
                "PD1-15 should fire when PD1-22 populated + PD1-15 empty; got \(report.errors.map(\.message))")
    }

    // ORC-26 (ABN Override Reason) is required when ORC-20 (ABN Code)
    // signals not-signed — HL7 Table 0339 values 3/4 (v2.8.2 §4.5.1.26).
    @Test("v0.16 M2: ORC-26 conditional fires when ORC-20 = 3 + ORC-26 empty")
    func v282ORC_26ConditionalFires() throws {
        // ORC-1=RE, ORC-2/3 populated (so their XOR does not fire), ORC-20=3;
        // ORC-26 empty. From ORC-3, 17 pipes reach ORC-20.
        let orc = "ORC|RE|PON|FON" + String(repeating: "|", count: 17) + "3"
        let wire = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240301120000||ORU^R01^ORU_R01|MSG|P|2.8.2\r"
            + "PID|1||X^^^F^MR||Doe^Jane||19800101|F\r"
            + orc + "\r"
        let message = try Parser().parse(wire)
        let report = Validator().validate(message)
        let hits = report.errors.filter {
            $0.code == .conditionalFieldMissing && $0.location.segmentID == "ORC" && $0.location.fieldIndex == 26
        }
        #expect(hits.count == 1,
                "ORC-26 should fire when ORC-20 in (3,4) + ORC-26 empty; got \(report.errors.map(\.message))")
        // And it must NOT fire when ORC-20 is a signed value (e.g. "1").
        let orcSigned = "ORC|RE|PON|FON" + String(repeating: "|", count: 17) + "1"
        let signed = try Parser().parse("MSH|^~\\&|HIS|FAC|HOSP|FAC|20240301120000||ORU^R01^ORU_R01|MSG|P|2.8.2\r"
            + "PID|1||X^^^F^MR||Doe^Jane||19800101|F\r" + orcSigned + "\r")
        let noHit = Validator().validate(signed).errors.filter {
            $0.code == .conditionalFieldMissing && $0.location.segmentID == "ORC" && $0.location.fieldIndex == 26
        }
        #expect(noHit.isEmpty, "ORC-26 must not fire when ORC-20 is signed (1)")
    }

    // Guard: the documented v2.8.2 permanent-limitation set stays
    // C-without-condition. If a future edit adds a bare-C field or drops
    // one of these, this fails — keeping the conditional-completeness
    // register (docs/design/conditional-completeness-audit.md) honest.
    @Test("v0.16 M2: v2.8.2 permanent-limitation set stays C-without-condition")
    func v282M2PermanentLimitationsGuard() {
        let table = SegmentGrammarTable.v2_8_2
        // Every remaining C-without-condition (seg, index) in v2.8.2.
        let expected: Set<String> = [
            "OBR-48", "OBX-4", "OBX-22", "DG1-22",
            // OBX-5 left this set in P4-26: it carries `OBX-11 = O` (the
            // dynamic-specification "valued with null" rule, CH07 §7.4.2.11).
            // v1.2: order/pharmacy family — RXO/RXE/RXD/RXG/RXC give-amount &
            // dispense fields are conditional on
            // data-nature / cross-segment context, not a same-segment predicate
            // (bulk-documented in conditional-completeness-audit.md).
            "RXO-5", "RXO-15", "RXO-17", "RXO-31",
            "RXE-10", "RXE-11", "RXE-15", "RXE-16", "RXE-17", "RXE-18", "RXE-19", "RXE-22",
            "RXD-5", "RXD-8", "RXG-14", "RXG-32", "RXG-33", "RXC-10", "RXC-11",
            "RXA-7", "RXA-12",
            // v1.3: scheduling family (SCH/RGS/AIS/AIG/AIL/AIP/ARQ) — filler/placer
            // and resource fields conditional on the appointment message intent;
            // ROL-1 role-instance (SPM-13 carries a prohibition since P4-4). All
            // fail-safe, grouped in conditional-completeness-audit.md.
            "SCH-3", "SCH-24", "SCH-26",
            "RGS-2", "ARQ-2", "ARQ-3", "ARQ-24",
            "AIS-2", "AIS-5", "AIG-2", "AIL-2", "AIP-2",
            "ROL-1",
            // v1.3 (master-files / referral batch): master-file entry/ack keys and
            // OM7 / AUT fields conditional on the master-file event or auth context.
            "AUT-6",
            // v1.4 (query / lab-automation batch): query-tag/response and specimen-
            // container / equipment fields conditional on the query or lab-automation
            // event context (fail-safe; documented in the register).
            "QPD-2", "QAK-1", "RCP-4", "EQU-3", "SAC-3", "SAC-4",
            // v1.4 (master-file locations / patient-care / med-records batch):
            // location-relationship, pricing, goal/problem/pathway and transcription-
            // document fields conditional on the master-file / care / document event.
            "GOL-22", "PRB-28", "PTH-6", "PTH-7",
            "TXA-11", "TXA-22",
            // v1.7 (CH13 lab-automation completion): the whole SID segment is
            // conditional — §13.4.11 defines all four fields with no condition text at
            // all, so which of them is required depends on what the substance/container
            // is being identified BY, not on any same-segment or cross-segment field.
            // Fail-safe (documented in conditional-completeness-audit.md). The other
            // five segments in this batch (ISD/NDS/CNS/ECD/ECR) carry no C fields.
            "SID-1", "SID-2", "SID-3", "SID-4",
            // v1.8 (CH07 product-experience + clinical-trials completion): CSP-4 Study
            // Phase Evaluability is the ONLY bare C in the nine-segment batch. §7.8.2.4
            // says what the field holds and states no trigger. Its five CSR siblings and
            // CTI-2 all carry spec-cited predicates instead — see
            // v1_8ClinicalTrialConditionsShipped() below.
            "CSP-4",
            // v3-C3 (deferred CH15 personnel on v2.8.2): CER-12 Subject ID is
            // conditional on the certificate being "expressed as a X.509
            // document" (§15.4.2.12) — a payload format no field states, so it
            // stays bare on every version it exists on (registered in
            // conditional-completeness-audit.md at v3 cycle 1). STF-1 / PRA-1 /
            // PRA-12 carry their MFN predicates here just as on the AU-priority
            // versions (identical prose, verified).
            "CER-12",
            // v3-C4 (deferred batch C): IAM-7 Allergy Unique Identifier is a
            // receiving-system-capability condition (registered at the Sprint 0
            // close-out) — bare on every version it exists on. RQ1-2..5 and
            // RQD-2..4 carry the same either-pair / one-of-three predicates as
            // the AU-priority versions (identical prose, verified on both
            // chapters).
            "IAM-7",
            // v3-C5 (never-authored backlog): the new-segment bare-C surface,
            // triaged per field in conditional-completeness-audit.md. Shipped
            // instead of registered: PYE-3..6 (payee-type gates), MCP-5,
            // OMC-2/3 (mutual presence), PRT-5/8/9/10/22 (the one-of-five
            // rotation the shared Condition sentence states). M8-D closed
            // two more classes: PAC-2 carries "SHP-8 > 1" (the numeric
            // ordering comparison landed) and PRT-6/7 carry prohibitedWhen
            // (the conditional-prohibition model landed) — all three left
            // this set. The rest have no field-expressible trigger:
            // financial/DRG context (ADJ-7, IVC-23, PSL-10/12..16,
            // DMI-2..5, REL-1), usage-pattern exceptions (DON-1/2),
            // required-when-known (PRT-1), no stated trigger (RXV-20/21).
            "ADJ-7", "IVC-23", "PSL-10", "PSL-12", "PSL-13", "PSL-14",
            "PSL-15", "PSL-16", "DMI-2", "DMI-3", "DMI-4", "DMI-5", "REL-1",
            "DON-1", "DON-2", "PRT-1",
            "RXV-20", "RXV-21",
        ]
        // A field whose conditionality is modelled by EITHER axis
        // (required-when `condition` or the M8-D `prohibitedWhen`
        // prohibition) is not bare. Shared with BareConditionalGuardTests
        // (TestSupport.swift bareConditionals) so the two guards cannot drift.
        let actual = bareConditionals(table)
        #expect(actual == expected,
                "v2.8.2 C-without-condition set drifted from the audit register; got \(actual.sorted())")
    }

    // v1.8: six conditional fields in the clinical-trials family carry spec-cited,
    // DSL-expressible predicates rather than joining the permanent-limitation register.
    // CSR-9/10 cite the patient-registration trigger event (C01); CSR-14/15/16 cite the
    // off-study trigger event (C04); CTI-2's requirement is stated in CTI-3's own prose
    // ("CTI-2 ... must be valued if CTI-3 ... is valued"). Each was verified against every
    // version's field-definition text by ITEM number, since the heading format differs
    // between the v2.3-era and v2.5+-era chapters.
    @Test("v1.8: clinical-trial conditional predicates ship on all six versions")
    func v1_8ClinicalTrialConditionsShipped() {
        let tables: [(String, [String: SegmentGrammar])] = [
            ("2.3", SegmentGrammarTable.v2_3),
            ("2.3.1", SegmentGrammarTable.v2_3_1),
            ("2.4", SegmentGrammarTable.v2_4),
            ("2.5.1", SegmentGrammarTable.v2_5_1),
            ("2.6", SegmentGrammarTable.v2_6),
            ("2.8.2", SegmentGrammarTable.v2_8_2),
        ]
        for (version, table) in tables {
            #expect(table["CSR"]?.field(9)?.condition == "triggerEvent = C01", "CSR-9 on \(version)")
            #expect(table["CSR"]?.field(10)?.condition == "triggerEvent = C01", "CSR-10 on \(version)")
            #expect(table["CSR"]?.field(14)?.condition == "triggerEvent = C04", "CSR-14 on \(version)")
            #expect(table["CSR"]?.field(15)?.condition == "triggerEvent = C04", "CSR-15 on \(version)")
            #expect(table["CSR"]?.field(16)?.condition == "triggerEvent = C04", "CSR-16 on \(version)")
            #expect(table["CTI"]?.field(2)?.condition == "CTI-3 populated", "CTI-2 on \(version)")
            // CSP-4 has no expressible trigger — it must stay bare so the register's
            // guard test keeps describing reality.
            #expect(table["CSP"]?.field(4)?.optionality == .conditional, "CSP-4 opt on \(version)")
            #expect(table["CSP"]?.field(4)?.condition == nil, "CSP-4 stays bare on \(version)")
        }
    }

    // v1.2 (M5 sweep): NK1/PV1/IN1 extended from curated (13/20/25) to full
    // per-version depth on every non-canonical version, extractor-seeded +
    // spec-verified. These pins lock the newly-exposed depth + divergences.
    @Test("v1.2: per-version NK1/PV1/IN1 reach full depth with correct version divergences")
    func v1_2PerVersionFullDepth() {
        // Full depths per version (grow across the standard).
        #expect(SegmentGrammarTable.v2_3["NK1"]?.fields.count == 37)
        #expect(SegmentGrammarTable.v2_3["IN1"]?.fields.count == 49)
        #expect(SegmentGrammarTable.v2_6["NK1"]?.fields.count == 39)
        #expect(SegmentGrammarTable.v2_8_2["NK1"]?.fields.count == 41)
        #expect(SegmentGrammarTable.v2_8_2["PV1"]?.fields.count == 54)
        #expect(SegmentGrammarTable.v2_8_2["IN1"]?.fields.count == 55)

        // v2.3: coded fields are still IS (pre CE→CWE era).
        #expect(SegmentGrammarTable.v2_3["NK1"]?.field(35)?.dataType == "IS")   // Race

        // v2.6: CE→CWE + TS→DTM wave reaches the newly-exposed NK1 tail.
        #expect(SegmentGrammarTable.v2_6["NK1"]?.field(16)?.dataType == "DTM")  // Date/Time of Birth
        #expect(SegmentGrammarTable.v2_6["NK1"]?.field(35)?.dataType == "CWE")  // Race

        // v2.8.2: NK1 gains the telecom-info fields (40/41, XTN); the legacy
        // phone fields (5/6) demote to backward-compat B.
        #expect(SegmentGrammarTable.v2_8_2["NK1"]?.field(40)?.dataType == "XTN")
        #expect(SegmentGrammarTable.v2_8_2["NK1"]?.field(41)?.dataType == "XTN")
        #expect(SegmentGrammarTable.v2_8_2["NK1"]?.field(5)?.optionality == .backwardCompat)
        #expect(SegmentGrammarTable.v2_8_2["NK1"]?.field(6)?.optionality == .backwardCompat)
    }
}
