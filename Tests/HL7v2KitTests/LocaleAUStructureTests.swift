// LocaleAUStructureTests.swift
// P8b-4 (ADR-019 "HL7au:00060.1", decisions 7 and 8): under the AU locale, with
// messageStructureSeverity set, a v2.4 message whose trigger the ADRM-2021 prints a
// constrained structure for is matched against that structure as well as the base v2.4
// one. A segment the ADRM structure requires and the message lacks is reported as
// profileConstraintViolation(localeRule: "HL7au:00060.1") at the configured severity;
// a base segment the ADRM removed is not a finding (decision 7); a segment the base
// match already reports missing is not reported twice. P8b-4a: a base finding is dropped where
// the ADRM structure accepts the message at that point, and RRI_I12 is added. The structures live in
// Resources/structures/profiles/au-adrm-2021/ (ruling G9), each cited to the print.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("AU HL7au:00060.1: required segments through the ADRM-2021 structures (P8b-4)")
struct LocaleAUStructureTests {

    static let rule = "HL7au:00060.1"

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/structures/profiles/au-adrm-2021")

    private func issues(_ msh9: String, _ body: [String], version: String = "2.4",
                        locale: HL7Locale = .auLocalisation,
                        severity: IssueSeverity? = .warning) throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = severity
        let wire = TestWires.msh(msh9, version) + body.map { $0 + "\r" }.joined()
        return Validator(options: options, locale: locale).validate(try Parser(locale: locale).parse(wire)).issues
    }

    /// The HL7au:00060.1 findings among `issues`.
    private func au(_ issues: [ValidationIssue]) -> [ValidationIssue] {
        issues.filter { $0.code == .profileConstraintViolation(localeRule: Self.rule) }
    }

    /// The base structure findings (missing, unexpected, mismatch) among `issues`.
    private func base(_ issues: [ValidationIssue]) -> [ValidationIssue] {
        issues.filter {
            switch $0.code {
            case .messageStructureSegmentMissing, .messageStructureSegmentUnexpected, .messageStructureMismatch: return true
            default: return false
            }
        }
    }

    // MARK: - ORU^R01 (ADRM-2021 section 4.3, pp 205 to 206; section 1, pp 17 to 18)

    @Test("AU ORU^R01 without PID: PID is required in each PATIENT_RESULT, so 00060.1 fires; the base allows it")
    func oruWithoutPID() throws {
        let all = try issues("ORU^R01^ORU_R01", ["ORC|RE", "OBR|1", "OBX|1"])
        #expect(base(all).isEmpty, "base v2.4 ORU_R01 makes the patient group optional: \(base(all).map(\.message))")
        let found = au(all)
        try #require(found.count == 1, "\(found.map(\.message))")
        #expect(found[0].severity == .warning)
        #expect(found[0].location.segmentID == "ORC")
        #expect(found[0].message.contains("requires PID "))
        #expect(found[0].message.hasPrefix("HL7au:00060.1: the ORU_R01 structure of the au-adrm-2021 profile requires PID in group PATIENT_RESULT before ORC[1]"))
    }

    @Test("AU ORU^R01 with PD1 and no PV1: PV1 is required in the printed optional group")
    func oruWithoutPV1InGroup() throws {
        let all = try issues("ORU^R01^ORU_R01", ["PID|1", "PD1|", "OBR|1", "OBX|1"])
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
        let found = au(all)
        try #require(found.count == 1, "\(found.map(\.message))")
        #expect(found[0].message.contains("requires PV1 "))
        #expect(found[0].location.segmentID == "OBR")
    }

    @Test("AU ORU^R01 with PID and no visit group draws nothing: the print puts PV1 inside an optional group")
    func oruWithoutVisitGroup() throws {
        // Registered: the prose on pp 17 and 205 calls PV1 mandatory, but both prints place it
        // inside [ ]; only the print's reading is enforced (never a finding the print denies).
        let all = try issues("ORU^R01^ORU_R01", ["PID|1", "OBR|1", "OBX|1"])
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
    }

    @Test("A compliant AU ORU^R01 draws no structure finding of either kind")
    func oruCompliant() throws {
        let all = try issues("ORU^R01^ORU_R01", ["PID|1", "PD1|", "PV1|1", "PV2|", "ORC|RE", "OBR|1", "CTD|", "OBX|1", "OBX|2"])
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
    }

    @Test("Base segments the ADRM removed (NTE, FT1, CTI) are not findings (decision 7)")
    func removedSegmentsAreNotFindings() throws {
        let all = try issues("ORU^R01^ORU_R01",
                             ["PID|1", "NTE|1", "PV1|1", "OBR|1", "NTE|2", "OBX|1", "NTE|3", "FT1|1", "CTI|1"])
        #expect(base(all).isEmpty, "the message conforms to base v2.4 ORU_R01: \(base(all).map(\.message))")
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
    }

    @Test("The same message under the international locale draws no 00060.1")
    func internationalLocaleIsSilent() throws {
        let all = try issues("ORU^R01^ORU_R01", ["ORC|RE", "OBR|1", "OBX|1"], locale: .international)
        #expect(au(all).isEmpty)
        #expect(base(all).isEmpty)
    }

    @Test("With messageStructureSeverity nil the AU structures are not matched")
    func severityNilIsSilent() throws {
        let all = try issues("ORU^R01^ORU_R01", ["ORC|RE", "OBR|1", "OBX|1"], severity: nil)
        #expect(au(all).isEmpty)
    }

    @Test("The configured severity is carried", arguments: [IssueSeverity.error, .warning, .info])
    func severityIsCarried(_ severity: IssueSeverity) throws {
        let found = au(try issues("ORU^R01^ORU_R01", ["ORC|RE", "OBR|1", "OBX|1"], severity: severity))
        #expect(found.map(\.severity) == [severity])
    }

    @Test("A segment the base match already reports missing is not reported again")
    func noDuplicateOfBaseFinding() throws {
        let all = try issues("ORU^R01^ORU_R01", ["PID|1", "PV1|1", "ORC|RE"])
        #expect(base(all).contains { $0.code == .messageStructureSegmentMissing(structure: "ORU_R01", segmentID: "OBR", group: "ORDER_OBSERVATION") },
                "\(base(all).map(\.message))")
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
    }

    @Test("ADRM-2021 localises v2.4 only: a v2.5.1 AU ORU^R01 without PID draws no 00060.1")
    func otherVersionsAreNotMatched() throws {
        #expect(au(try issues("ORU^R01^ORU_R01", ["ORC|RE", "OBR|1", "OBX|1"], version: "2.5.1")).isEmpty)
    }

    @Test("A legacy two-component MSH-9 resolves through the trigger as the base does")
    func twoComponentMSH9() throws {
        let found = au(try issues("ORU^R01", ["ORC|RE", "OBR|1", "OBX|1"]))
        #expect(found.count == 1, "\(found.map(\.message))")
    }

    // MARK: - ORM^O01 (ADRM-2021 section 5.2, pp 279 to 280)

    @Test("AU ORM^O01 with an ORC and no order detail segment: 00060.1 fires naming OBR")
    func ormWithoutOrderDetail() throws {
        let all = try issues("ORM^O01^ORM_O01", ["PID|1", "ORC|NW"])
        #expect(base(all).isEmpty, "base v2.4 ORDER_DETAIL is optional: \(base(all).map(\.message))")
        let found = au(all)
        try #require(found.count == 1, "\(found.map(\.message))")
        #expect(found[0].message.contains("requires OBR "))
        #expect(found[0].message.contains(" at the end of the message "), "\(found[0].message)")
        #expect(found[0].location.pathDescription == "ORC[1]")
    }

    @Test("AU ORM^O01 with RXO in place of OBR draws nothing (p 280: OBR is replaced by another order detail segment)")
    func ormWithOtherOrderDetail() throws {
        let all = try issues("ORM^O01^ORM_O01", ["PID|1", "ORC|NW", "RXO|1"])
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
    }

    @Test("AU ORM^O01 with a diet order detail segment (ODS, ODT) draws nothing (p 280: diet orders)",
          arguments: ["ODS|D", "ODT|1"])
    func ormDietOrderDetail(_ detail: String) throws {
        let all = try issues("ORM^O01^ORM_O01", ["PID|1", "ORC|NW", detail])
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
    }

    @Test("AU ORM^O01 with RQD or RQ1 in place of OBR: 00060.1 fires (p 280 replaces OBR only for medication and diet orders)",
          arguments: ["RQD|1", "RQ1|1"], [false, true])
    func ormRequisitionDetail(_ detail: String, _ trailingZ: Bool) throws {
        let all = try issues("ORM^O01^ORM_O01", ["PID|1", "ORC|NW", detail] + (trailingZ ? ["ZXX|1"] : []))
        #expect(base(all).isEmpty, "base v2.4 accepts the requisition detail: \(base(all).map(\.message))")
        let found = au(all)
        try #require(found.count == 1, "\(found.map(\.message))")
        #expect(found[0].message.contains("requires OBR "))
        // P8b-18: the profile passes the requisition detail over (it is transparent
        // to the profile match), so the matcher reaches the end; OBR belongs after
        // the last segment the profile matched, ORC[1], wherever the passed-over
        // segments stand (fix round 2: "no later than the last segment" was false,
        // as `ormRequisitionDetailOBRAppended` shows). The location is unchanged.
        let id = String(detail.prefix(3))
        #expect(found[0].message.contains("requires OBR in group ORDER after ORC[1] "), "\(found[0].message)")
        #expect(!found[0].message.contains("no later than"), "\(found[0].message)")
        #expect(!found[0].message.contains("in place of"), "\(found[0].message)")
        #expect(!found[0].message.contains("at the end of the message"), "\(found[0].message)")
        #expect(found[0].location.pathDescription == (trailingZ ? "ZXX[1]" : "\(id)[1]"))
    }

    @Test("AU ORM^O01: OBR appended after the passed-over requisition detail and a trailing Z-segment satisfies the profile",
          arguments: ["RQD|1", "RQ1|1"], [false, true])
    func ormRequisitionDetailOBRAppended(_ detail: String, _ trailingZ: Bool) throws {
        let all = try issues("ORM^O01^ORM_O01", ["PID|1", "ORC|NW", detail] + (trailingZ ? ["ZXX|1"] : []) + ["OBR|1"])
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
    }

    @Test("A compliant AU ORM^O01, with the removed NTE segments, draws no finding")
    func ormCompliant() throws {
        let all = try issues("ORM^O01^ORM_O01", ["NTE|1", "PID|1", "PV1|1", "IN1|1", "ORC|NW", "OBR|1", "NTE|2", "DG1|1", "OBX|1", "BLG|"])
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
    }

    // MARK: - REF^I12 (ADRM-2021 section 7.2.1, pp 324 to 325)

    @Test("AU REF^I12 without PV1: PV1 is required (the base makes the visit optional)")
    func refWithoutPV1() throws {
        let all = try issues("REF^I12^REF_I12", ["RF1|A", "PRD|RP", "PID|1"])
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
        let found = au(all)
        try #require(found.count == 1, "\(found.map(\.message))")
        #expect(found[0].message.contains("requires PV1 "))
    }

    @Test("AU REF^I12 without RF1: RF1 is required (the base makes it optional)")
    func refWithoutRF1() throws {
        let all = try issues("REF^I12^REF_I12", ["PRD|RP", "PID|1", "PV1|1"])
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
        let found = au(all)
        try #require(found.count == 1, "\(found.map(\.message))")
        #expect(found[0].message.contains("requires RF1 "))
        #expect(found[0].location.segmentID == "PRD")
    }

    @Test("A compliant AU REF^I12 draws no 00060.1")
    func refCompliant() throws {
        let all = try issues("REF^I12^REF_I12", ["RF1|A", "PRD|RP", "PID|1", "PD1|", "OBR|1", "OBX|1", "PV1|1"])
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
    }

    // MARK: - Base findings the profile structure accepts (P8b-4a)

    @Test("AU REF^I12 with PD1 (p 324 places it after PID): the base PD1 unexpected is dropped under AU only")
    func refPD1BaseFindingIsGoverned() throws {
        let body = ["RF1|A", "PRD|RP", "PID|1", "PD1|", "PV1|1"]
        let all = try issues("REF^I12^REF_I12", body)
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
        let intl = base(try issues("REF^I12^REF_I12", body, locale: .international))
        #expect(intl.map(\.code) == [.messageStructureSegmentUnexpected(structure: "REF_I12", segmentID: "PD1")],
                "\(intl.map(\.message))")
    }

    @Test("AU REF^I12 with a segment neither structure places there keeps the base finding")
    func refBaseFindingNeitherPlacesIsKept() throws {
        // EVN is in the v2.4 grammar and in neither REF_I12; the profile passes it over
        // (decision 7) but does not place it, so the base finding stands.
        let stray = base(try issues("REF^I12^REF_I12", ["RF1|A", "PRD|RP", "PID|1", "EVN|", "PV1|1"]))
        #expect(stray.map(\.code) == [.messageStructureSegmentUnexpected(structure: "REF_I12", segmentID: "EVN")],
                "\(stray.map(\.message))")
        // PD1 after PV1: the profile names PD1 but not there, so the base finding stands.
        let misplaced = base(try issues("REF^I12^REF_I12", ["RF1|A", "PRD|RP", "PID|1", "PV1|1", "PD1|"]))
        #expect(misplaced.map(\.code) == [.messageStructureSegmentUnexpected(structure: "REF_I12", segmentID: "PD1")],
                "\(misplaced.map(\.message))")
    }

    // MARK: - RRI^I12 (ADRM-2021 section 7.2.2, p 325)

    @Test("AU RRI^I12 MSH MSA (p 325: the RF1, PRD, PID group is optional): the base PRD and PID missing are dropped under AU only")
    func rriBareBaseFindingsAreGoverned() throws {
        let all = try issues("RRI^I12^RRI_I12", ["MSA|AA|1"])
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
        // Base v2.4 RRI_I12 fails the determinism lint, so it is matched exactly and reports
        // its first divergence only (P8b-12).
        let intl = base(try issues("RRI^I12^RRI_I12", ["MSA|AA|1"], locale: .international))
        #expect(intl.map(\.code) == [
            .messageStructureSegmentMissing(structure: "RRI_I12", segmentID: "PRD", group: "PROVIDER_CONTACT"),
        ], "\(intl.map(\.message))")
    }

    @Test("AU RRI^I12 with ERR (p 325 prints [ERR]; the base has none): the base ERR unexpected is dropped")
    func rriERRIsPlaced() throws {
        let all = try issues("RRI^I12^RRI_I12", ["MSA|AA|1", "ERR|", "RF1|A", "PRD|RP", "PID|1"])
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
    }

    @Test("AU RRI^I12 without MSA: MSA is required (p 325; the base makes it optional), so 00060.1 fires")
    func rriWithoutMSA() throws {
        let all = try issues("RRI^I12^RRI_I12", ["RF1|A", "PRD|RP", "PID|1"])
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
        let found = au(all)
        try #require(found.count == 1, "\(found.map(\.message))")
        #expect(found[0].message.contains("requires MSA "), "\(found[0].message)")
        #expect(found[0].location.segmentID == "RF1")
    }

    @Test("AU RRI^I12 with RF1 and no PRD: the profile does not accept the message at PID, so the base finding there stands")
    func rriGroupMissingPRDIsKept() throws {
        // The profile places PID but reports PRD missing before it: the base PID unexpected
        // (the exact matcher's first divergence) is kept, and 00060.1 names PRD.
        let all = try issues("RRI^I12^RRI_I12", ["MSA|AA|1", "RF1|A", "PID|1"])
        #expect(base(all).map(\.code) == [.messageStructureSegmentUnexpected(structure: "RRI_I12", segmentID: "PID")],
                "\(base(all).map(\.message))")
        let found = au(all)
        try #require(found.count == 1, "\(found.map(\.message))")
        #expect(found[0].message.contains("requires PRD in group RF1_GROUP before PID[1]"), "\(found[0].message)")
    }

    // MARK: - Re-matching an exact-matched base after a governed finding (P8b-4a fix round 1)

    // Base v2.4 REF_I12, RRI_I12 and ORU_R01 fail the determinism lint and are matched
    // exactly, with one finding and no recovery. When that finding is dropped, the base is
    // matched again with the dropped occurrence passed over, so a later divergence is found.

    @Test("AU REF^I12 with PD1 then EVN: PD1 is dropped and the base still reports EVN, which neither structure places")
    func refDroppedThenNeitherPlaces() throws {
        let found = base(try issues("REF^I12^REF_I12", ["RF1|A", "PRD|RP", "PID|1", "PD1|", "EVN|", "PV1|1"]))
        #expect(found.map(\.code) == [.messageStructureSegmentUnexpected(structure: "REF_I12", segmentID: "EVN")],
                "\(found.map(\.message))")
    }

    @Test("AU REF^I12 with PD1 then a second PV1: no finding, one information issue for the narrowed maximum")
    func refDroppedThenSecondPV1() throws {
        // Base v2.4 REF_I12 (CH11 pp 11-16 to 11-17) prints [ PV1 [PV2] ] twice, so the base
        // accepts PV1 PV1 once PD1 is passed over; only the ADRM (p 324, PV1 once) rejects the
        // second, as a beyond-maximum finding, which decision 7 as amended in S6 reports at
        // information (owner ruling 2026-10-06; LocaleAUMaximumTests).
        let all = try issues("REF^I12^REF_I12", ["RF1|A", "PRD|RP", "PID|1", "PD1|", "PV1|1", "PV1|2"])
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
        let info = all.filter { $0.code == .profileMaximumExceeded(localeRule: Self.rule) }
        #expect(info.count == 1 && info.first?.severity == .info && info.first?.location.segmentIndex == 2)
    }

    // MARK: - OSR^Q06 order status response (ADRM-2021 section 5.3, p 281)

    static let osrHead = ["MSA|AA|1", "QRD|20240101|R|I|Q1|||1^RD|ALL|OS|"]

    @Test("A conformant AU order status response with OBX (p 281) is clean under AU; the international locale reports OBX")
    func osrWithOBX() throws {
        let body = Self.osrHead + ["PID|1", "ORC|SC", "OBR|1", "OBX|1", "CTI|1"]
        let all = try issues("OSR^Q06^OSR_Q06", body)
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
        let intl = base(try issues("OSR^Q06^OSR_Q06", body, locale: .international))
        #expect(intl.map(\.code) == [.messageStructureSegmentUnexpected(structure: "OSR_Q06", segmentID: "OBX")],
                "\(intl.map(\.message))")
    }

    @Test("An AU order status response with RXO in place of OBR raises no 00060.1 (the base choice is kept)")
    func osrWithRXO() throws {
        let all = try issues("OSR^Q06^OSR_Q06", Self.osrHead + ["ORC|SC", "RXO|1"])
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
    }

    @Test("An AU order status response without MSA: MSA is required in both structures, reported once by the base")
    func osrWithoutMSA() throws {
        let all = try issues("OSR^Q06^OSR_Q06", ["QRD|20240101|R|I|Q1|||1^RD|ALL|OS|", "ORC|SC", "OBR|1"])
        #expect(base(all).contains { $0.code == .messageStructureSegmentMissing(structure: "OSR_Q06", segmentID: "MSA", group: nil) },
                "\(base(all).map(\.message))")
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
    }

    @Test("AU RRI^I12 with ERR then a second PID: ERR is dropped and the base reports the second PID")
    func rriDroppedThenSecondPID() throws {
        let found = base(try issues("RRI^I12^RRI_I12", ["MSA|AA|1", "ERR|", "RF1|A", "PRD|RP", "PID|1", "PID|2"]))
        #expect(found.map(\.code) == [.messageStructureSegmentUnexpected(structure: "RRI_I12", segmentID: "PID")],
                "\(found.map(\.message))")
        #expect(found.first?.location.pathDescription == "PID[2]")
    }

    @Test("AU ORU^R01 with NK1 after a removed NTE, then EVN: NK1 is dropped and the base reports EVN")
    func oruDroppedThenNeitherPlaces() throws {
        // Base v2.4 PATIENT prints NK1 before NTE; the ADRM removed NTE (decision 7) and places
        // NK1 after PD1 (p 205), so the base NK1 finding is dropped.
        let body = ["PID|1", "PD1|", "NTE|1", "NK1|1", "PV1|1", "OBR|1", "OBX|1"]
        #expect(base(try issues("ORU^R01^ORU_R01", body)).isEmpty)
        let intl = base(try issues("ORU^R01^ORU_R01", body, locale: .international))
        #expect(intl.map(\.code) == [.messageStructureSegmentUnexpected(structure: "ORU_R01", segmentID: "NK1")],
                "\(intl.map(\.message))")
        let found = base(try issues("ORU^R01^ORU_R01", body + ["EVN|"]))
        #expect(found.map(\.code) == [.messageStructureSegmentUnexpected(structure: "ORU_R01", segmentID: "EVN")],
                "\(found.map(\.message))")
    }

    @Test("A conformant AU REF^I12 with several base findings to drop stays clean (the re-match terminates)")
    func refManyDropsStayClean() throws {
        let all = try issues("REF^I12^REF_I12", ["RF1|A", "PRD|RP", "PID|1", "PD1|", "IAM|1", "OBR|1", "OBX|1", "PV1|1",
                                                 "ORC|NW", "RXO|1", "RXR|1", "PRB|AD", "GOL|AD", "PTH|AD", "ROL|1"])
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
        let intl = base(try issues("REF^I12^REF_I12", ["RF1|A", "PRD|RP", "PID|1", "PD1|", "IAM|1", "PV1|1"], locale: .international))
        #expect(!intl.isEmpty)
    }

    @Test("REF^I13 shares the base REF_I12 structure but the ADRM prints only I12: no 00060.1")
    func refOtherTriggerIsNotMatched() throws {
        let all = try issues("REF^I13^REF_I12", ["RF1|A", "PRD|RP", "PID|1"])
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
    }

    // MARK: - Data

    @Test("The ADRM-2021 structures are ORM_O01, ORR_O02, ORU_R01, OSR_Q06, REF_I12 and RRI_I12, each tagged with the profile, base version and rule")
    func dataTags() throws {
        let table = MessageStructureTable.auADRM2021
        #expect(Set(table.keys) == ["ORM_O01", "ORR_O02", "ORU_R01", "OSR_Q06", "REF_I12", "RRI_I12"])
        for (id, structure) in table {
            #expect(structure.id == id)
            #expect(structure.profile == "au-adrm-2021", "\(id)")
            #expect(structure.baseVersion == "2.4", "\(id)")
            #expect(structure.rule == Self.rule, "\(id)")
            #expect(structure.citation.contains("HL7AUSD-STD-OO-ADRM-2021.1"), "\(id)")
            // The overlay applies only where the base structure resolves: every AU trigger is a
            // trigger of the base v2.4 structure with the same ID.
            let baseStructure = try #require(MessageStructureTable.structure(id, version: .v2_4), "\(id)")
            #expect(Set(structure.triggers).isSubset(of: Set(baseStructure.triggers)), "\(id)")
            #expect(structure.requiresExactMatch == !StructureMatcher.lint(structure.elements).isDeterministic, "\(id)")
        }
        // Base structures carry no profile tag.
        #expect(MessageStructureTable.structure("ORU_R01", version: .v2_4)?.profile == nil)
    }

    @Test("Each profile file decodes to exactly the generated structure", arguments: ["ORM_O01", "ORR_O02", "ORU_R01", "OSR_Q06", "REF_I12", "RRI_I12"])
    func fileParity(_ id: String) throws {
        var object = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: Self.root.appendingPathComponent("\(id).json"))) as? [String: Any])
        #expect(object.removeValue(forKey: "profile") as? String == "au-adrm-2021")
        #expect(object.removeValue(forKey: "baseVersion") as? String == "2.4")
        #expect(object.removeValue(forKey: "rule") as? String == Self.rule)
        let decoded = try StructureJSONDecoder.decode(try JSONSerialization.data(withJSONObject: object), id: id, version: "2.4",
                                                      profile: true)
        let generated = try #require(MessageStructureTable.auADRM2021[id])
        #expect(decoded.id == generated.id)
        #expect(decoded.version == generated.version)
        #expect(decoded.triggers == generated.triggers)
        #expect(decoded.citation == generated.citation)
        #expect(decoded.elements == generated.elements)
        #expect(decoded.variants == generated.variants)
    }
}
