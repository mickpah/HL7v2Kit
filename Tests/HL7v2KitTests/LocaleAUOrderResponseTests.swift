// LocaleAUOrderResponseTests.swift
// P12 S1-3 and S1-2 (ADR-019 "HL7au:00060.1", amendment "P12 S1"): the order detail of the
// ADRM-2021 order status response (OSR^Q06, section 5.3, p 281) and the order response
// ORR^O02 (section 5.2, pp 280 to 281), each matched under .auLocalisation against its
// profile structure in Resources/structures/profiles/au-adrm-2021/.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("AU HL7au:00060.1: the order status response and order response structures (P12 S1)")
struct LocaleAUOrderResponseTests {

    static let rule = "HL7au:00060.1"

    private func issues(_ msh9: String, _ body: [String], locale: HL7Locale = .auLocalisation) throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .warning
        let wire = TestWires.msh(msh9, "2.4") + body.map { $0 + "\r" }.joined()
        return Validator(options: options, locale: locale).validate(try Parser(locale: locale).parse(wire)).issues
    }

    private func au(_ issues: [ValidationIssue]) -> [ValidationIssue] {
        issues.filter { $0.code == .profileConstraintViolation(localeRule: Self.rule) }
    }

    private func base(_ issues: [ValidationIssue]) -> [ValidationIssue] {
        issues.filter {
            switch $0.code {
            case .messageStructureSegmentMissing, .messageStructureSegmentUnexpected, .messageStructureMismatch: return true
            default: return false
            }
        }
    }

    // MARK: - OSR^Q06 order detail (ADRM-2021 section 5.3, p 281)

    static let osrHead = ["MSA|AA|1", "QRD|20240101|R|I|Q1|||1^RD|ALL|OS|", "PID|1", "ORC|SC"]

    @Test("AU OSR^Q06 with RQD or RQ1 in place of OBR: 00060.1 fires (no ADRM print or prose admits a requisition detail)",
          arguments: ["RQD|1", "RQ1|1"])
    func osrRequisitionDetail(_ detail: String) throws {
        let all = try issues("OSR^Q06^OSR_Q06", Self.osrHead + [detail])
        #expect(base(all).isEmpty, "base v2.4 accepts the requisition detail: \(base(all).map(\.message))")
        let found = au(all)
        try #require(found.count == 1, "\(found.map(\.message))")
        #expect(found[0].message.contains("requires OBR in group ORDER after ORC[1] "), "\(found[0].message)")
        #expect(found[0].location.pathDescription == "\(detail.prefix(3))[1]")
        #expect(au(try issues("OSR^Q06^OSR_Q06", Self.osrHead + [detail], locale: .international)).isEmpty)
    }

    @Test("AU OSR^Q06 with an OBX after a requisition detail: 00060.1 fires, OBR is required before the OBX",
          arguments: ["RQD|1", "RQ1|1"])
    func osrOBXAfterRequisitionDetail(_ detail: String) throws {
        let all = try issues("OSR^Q06^OSR_Q06", Self.osrHead + [detail, "OBX|1"])
        let found = au(all)
        try #require(found.count == 1, "\(found.map(\.message))")
        #expect(found[0].message.contains("requires OBR in group ORDER before OBX[1] "), "\(found[0].message)")
        #expect(found[0].location.pathDescription == "OBX[1]")
    }

    @Test("AU OSR^Q06 with a medication or diet detail and an OBX after it draws nothing (residual: p 281 does not settle it)",
          arguments: ["RXO|1", "ODS|D", "ODT|1"])
    func osrMedicationOrDietDetailWithOBX(_ detail: String) throws {
        let all = try issues("OSR^Q06^OSR_Q06", Self.osrHead + [detail, "OBX|1"])
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
    }

    @Test("A conformant AU OSR^Q06 (OBR, OBX, CTI, two orders) stays clean")
    func osrConformant() throws {
        let all = try issues("OSR^Q06^OSR_Q06", Self.osrHead + ["OBR|1", "OBX|1", "CTI|1", "ORC|SC", "OBR|2", "DSC|1"])
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
    }

    // MARK: - ORR^O02 order response (ADRM-2021 section 5.2, pp 280 to 281; owner ruling G-AU2)

    @Test("A conformant AU ORR^O02 (PID, ORC, OBR) is clean under AU")
    func orrConformant() throws {
        let all = try issues("ORR^O02^ORR_O02", ["MSA|AA|1", "PID|1", "ORC|OK", "OBR|1", "ORC|OK", "OBR|2"])
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
    }

    @Test("AU ORR^O02 without PID, or without the order group, is accepted (the erratum takes the base reading: PID optional)",
          arguments: [["MSA|AA|1", "ORC|OK", "OBR|1"], ["MSA|AA|1", "ERR|"], ["MSA|AA|1", "NTE|1", "ORC|OK", "OBR|1", "NTE|2", "CTI|1"]])
    func orrPIDAbsent(_ body: [String]) throws {
        let all = try issues("ORR^O02^ORR_O02", body)
        #expect(au(all).isEmpty, "\(au(all).map(\.message))")
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
    }

    @Test("AU ORR^O02 with RQD or RQ1 in place of OBR: 00060.1 fires; the international locale accepts it as the base does",
          arguments: ["RQD|1", "RQ1|1"])
    func orrRequisitionDetail(_ detail: String) throws {
        let body = ["MSA|AA|1", "PID|1", "ORC|OK", detail]
        let all = try issues("ORR^O02^ORR_O02", body)
        #expect(base(all).isEmpty, "\(base(all).map(\.message))")
        let found = au(all)
        try #require(found.count == 1, "\(found.map(\.message))")
        #expect(found[0].message.contains("requires OBR in group ORDER after ORC[1] "), "\(found[0].message)")
        #expect(found[0].message.contains("erratum"), "\(found[0].message)")
        #expect(found[0].location.pathDescription == "\(detail.prefix(3))[1]")
        let intl = try issues("ORR^O02^ORR_O02", body, locale: .international)
        #expect(au(intl).isEmpty && base(intl).isEmpty, "\(intl.map(\.message))")
    }

    @Test("AU ORR^O02 with an ORC and no order detail: the requirement is reported once, by the base")
    func orrWithoutOrderDetail() throws {
        let all = try issues("ORR^O02^ORR_O02", ["MSA|AA|1", "PID|1", "ORC|OK"])
        #expect(au(all).count + base(all).count == 1, "\(all.map(\.message))")
    }
}
