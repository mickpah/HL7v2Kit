// LocaleAUStructureTests.swift
// P8b-4 (ADR-019 "HL7au:00060.1", decisions 7 and 8): under the AU locale, with
// messageStructureSeverity set, a v2.4 message whose trigger the ADRM-2021 prints a
// constrained structure for is matched against that structure as well as the base v2.4
// one. A segment the ADRM structure requires and the message lacks is reported as
// profileConstraintViolation(localeRule: "HL7au:00060.1") at the configured severity;
// a base segment the ADRM removed is not a finding (decision 7); a segment the base
// match already reports missing is not reported twice. The structures live in
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
    }

    @Test("AU ORM^O01 with RXO in place of OBR draws nothing (p 280: OBR is replaced by another order detail segment)")
    func ormWithOtherOrderDetail() throws {
        let all = try issues("ORM^O01^ORM_O01", ["PID|1", "ORC|NW", "RXO|1"])
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
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
        let all = try issues("REF^I12^REF_I12", ["RF1|A", "PRD|RP", "PID|1", "OBR|1", "OBX|1", "PV1|1"])
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
    }

    @Test("REF^I13 shares the base REF_I12 structure but the ADRM prints only I12: no 00060.1")
    func refOtherTriggerIsNotMatched() throws {
        let all = try issues("REF^I13^REF_I12", ["RF1|A", "PRD|RP", "PID|1"])
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
    }

    // MARK: - Data

    @Test("The ADRM-2021 structures are ORM_O01, ORU_R01 and REF_I12, each tagged with the profile, base version and rule")
    func dataTags() throws {
        let table = MessageStructureTable.auADRM2021
        #expect(Set(table.keys) == ["ORM_O01", "ORU_R01", "REF_I12"])
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

    @Test("Each profile file decodes to exactly the generated structure", arguments: ["ORM_O01", "ORU_R01", "REF_I12"])
    func fileParity(_ id: String) throws {
        var object = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: Self.root.appendingPathComponent("\(id).json"))) as? [String: Any])
        #expect(object.removeValue(forKey: "profile") as? String == "au-adrm-2021")
        #expect(object.removeValue(forKey: "baseVersion") as? String == "2.4")
        #expect(object.removeValue(forKey: "rule") as? String == Self.rule)
        let decoded = try StructureJSONDecoder.decode(try JSONSerialization.data(withJSONObject: object), id: id, version: "2.4")
        let generated = try #require(MessageStructureTable.auADRM2021[id])
        #expect(decoded.id == generated.id)
        #expect(decoded.version == generated.version)
        #expect(decoded.triggers == generated.triggers)
        #expect(decoded.citation == generated.citation)
        #expect(decoded.elements == generated.elements)
    }
}
