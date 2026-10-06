// WithdrawnSegmentTests.swift
// S2-2 (ADR-019 S2-1 amendment, register section E F-I2 rows closed): v2.7.1 and v2.8.2
// print structures naming QRD, QRF, URD and URS, which their Appendix A lists as withdrawn
// (v2.7.1) or deprecated (v2.8.2) with no definition. The structures are modelled and
// matched by segment ID; each such segment draws one information issue at field level.

import Testing
@testable import HL7v2Kit

@Suite("Segments a version withdrew")
struct WithdrawnSegmentTests {

    private func issues(_ msh9: String, _ body: [String], version: String = "2.7.1") throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let wire = (["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||\(msh9)|MSG00001|P|\(version)"] + body).joined(separator: "\r")
        return Validator(options: options).validate(try Parser().parse(wire)).issues
    }

    private static func isStructure(_ code: IssueCode) -> Bool {
        switch code {
        case .messageStructureSegmentMissing, .messageStructureSegmentUnexpected,
             .messageStructureMismatch, .messageStructureNotModelled: true
        default: false
        }
    }

    private static func describe(_ code: IssueCode) -> String {
        switch code {
        case .messageStructureSegmentMissing(_, let segment, _): "missing \(segment)"
        case .messageStructureSegmentUnexpected(_, let segment): "unexpected \(segment)"
        default: "\(code)"
        }
    }

    private func structureFindings(_ msh9: String, _ body: [String], version: String = "2.7.1") throws -> [String] {
        try issues(msh9, body, version: version).filter { Self.isStructure($0.code) }.map { Self.describe($0.code) }
    }

    static let modelled: [String] = ["2.7.1 QRY_PC4", "2.7.1 RCI_I05", "2.7.1 RQC_I05", "2.7.1 RCL_I06",
                                     "2.7.1 UDM_Q05", "2.8.2 UDM_Q05"]

    @Test("The six structures are modelled and no longer registered", arguments: modelled)
    func modelledNotRegistered(_ key: String) throws {
        let parts = key.split(separator: " ").map(String.init)
        let version = try #require(Version(rawValue: parts[0]))
        #expect(MessageStructureTable.structure(parts[1], version: version) != nil, "\(key) is not modelled")
        #expect(MessageStructureTable.registration(parts[1], version: version) == nil, "\(key) is still registered")
    }

    // CH12 12.3.5 (QRY^PC4, p 15): MSH [{SFT}] [UAC] QRD [QRF].
    @Test("A conformant QRY^PC4 on v2.7.1 draws no structure finding")
    func qryPC4Conformant() throws {
        #expect(try structureFindings("QRY^PC4^QRY_PC4", ["QRD|20240101|R|I|Q1", "QRF|ICU"]) == [])
        #expect(try structureFindings("QRY^PC4^QRY_PC4", ["QRD|20240101|R|I|Q1"]) == [])
    }

    @Test("A QRY^PC4 missing QRD draws messageStructureSegmentMissing")
    func qryPC4MissingQRD() throws {
        let all = try issues("QRY^PC4^QRY_PC4", ["QRF|ICU"])
        #expect(all.contains { if case .messageStructureSegmentMissing(_, "QRD", _) = $0.code { $0.severity == .error } else { false } },
                "\(all.map(\.message))")
    }

    @Test("A bare QRY^PC9 resolves to QRY_PC4")
    func bareTrigger() throws {
        #expect(try structureFindings("QRY^PC9", ["QRD|20240101|R|I|Q1"]) == [])
        #expect(try structureFindings("QRY^PC9", ["QRF|ICU"]).contains("missing QRD"))
    }

    // CH11 11.3.5 (RCI^I05, p 14) and 11.3.6 (RCL^I06, p 15; RQC^I05/I06, pp 13 to 15).
    @Test("RCI_I05, RCL_I06 and RQC_I05 match their v2.7.1 prints")
    func referralQueries() throws {
        #expect(try structureFindings("RCI^I05^RCI_I05", ["MSA|AA|1", "QRD|20240101|R|I|Q1", "PRD|RP", "PID|1"]) == [])
        // RCI_I05 is exact-matched (its OBSERVATION and trailing NTE overlap): one finding,
        // at the furthest position, where the PRD stands in place of the required QRD.
        let rci = try structureFindings("RCI^I05^RCI_I05", ["MSA|AA|1", "PRD|RP", "PID|1"])
        #expect(rci == ["unexpected PRD"], "\(rci)")
        #expect(try structureFindings("RCL^I06^RCL_I06", ["MSA|AA|1", "QRD|20240101|R|I|Q1", "PRD|RP", "PID|1", "DSP|1"]) == [])
        // RQC_I05 keeps its primaryPrints entry: the looser 11.3.5 print [{GT1}] is primary.
        #expect(try structureFindings("RQC^I06^RQC_I05", ["QRD|20240101|R|I|Q1", "PRD|RP", "PID|1", "GT1|1", "GT1|2"]) == [])
        #expect(try structureFindings("RQC^I05^RQC_I05", ["QRD|20240101|R|I|Q1", "PID|1"]).contains("missing PRD"))
    }

    // CH05 5.10.1.2: MSH [{SFT}] [UAC] URD [URS] {DSP} [DSC] (v2.7.1 p 106, v2.8.2 pp 102 to 103).
    @Test("UDM_Q05 matches its print on v2.7.1 and v2.8.2", arguments: ["2.7.1", "2.8.2"])
    func udmQ05(_ version: String) throws {
        #expect(try structureFindings("UDM^Q05^UDM_Q05", ["URD||R", "URS|1", "DSP|1"], version: version) == [])
        #expect(try structureFindings("UDM^Q05^UDM_Q05", ["DSP|1"], version: version).contains("missing URD"))
    }

    @Test("A withdrawn segment draws one information issue and no segmentNotInVersionGrammar",
          arguments: [("2.7.1", "QRD"), ("2.7.1", "QRF"), ("2.7", "QRD"), ("2.7.1", "URD"), ("2.8.2", "URS"), ("2.8", "URD")])
    func fieldLevel(_ version: String, _ segment: String) throws {
        let all = try issues("QRY^PC4^QRY_PC4", ["\(segment)|1"], version: version)
        #expect(!all.contains { $0.code == .segmentNotInVersionGrammar }, "\(all.map(\.message))")
        let hits = all.filter { $0.code == .segmentWithdrawnInVersion }
        #expect(hits.count == 1 && hits.first?.severity == .info && hits.first?.location.segmentID == segment,
                "\(all.map(\.message))")
        #expect(hits.first?.message.contains("v2.6") == true, "\(hits.map(\.message))")
    }

    // The matcher passes over a segment the version does not define; a withdrawn one it
    // matches by ID, so a QRD where the structure names none is a structure finding.
    @Test("A QRD in an ADT^A01 on v2.7.1 is unexpected")
    func withdrawnSegmentOutOfPlace() throws {
        let findings = try structureFindings("ADT^A01^ADT_A01", ["EVN|A01", "PID|1", "QRD|20240101|R|I|Q1", "PV1|1"])
        #expect(findings.contains("unexpected QRD"), "\(findings)")
    }

    @Test("The withdrawn list is QRD, QRF, URD and URS on v2.7.1 and v2.8.2 only, each defined by v2.6")
    func withdrawnList() {
        for version in Version.allCases where version.grammarVersion == version {
            let listed = MessageStructureTable.withdrawnSegments(for: version)
            let expected: Set<String> = [.v2_7_1, .v2_8_2].contains(version) ? ["QRD", "QRF", "URD", "URS"] : []
            #expect(Set(listed.keys) == expected, "v\(version.rawValue)")
            for (id, entry) in listed {
                #expect(Validator.grammarTable(for: version)[id] == nil && Validator.grammarTable(for: .v2_6)[id] != nil)
                #expect(entry.definedThrough == "2.6" && entry.citation.contains("Appendix A"))
                #expect(entry.printed == (version == .v2_7_1 ? "withdrawn" : "deprecated"))
            }
        }
    }

    @Test("A segment v2.6 defines draws no withdrawn issue on v2.6")
    func definedOnV26() throws {
        let all = try issues("QRY^PC4^QRY_PC4", ["QRD|20240101|R|I|Q1"], version: "2.6")
        #expect(!all.contains { $0.code == .segmentWithdrawnInVersion || $0.code == .segmentNotInVersionGrammar })
    }
}
