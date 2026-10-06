// PrintedStructureIDTests.swift
// P8b-final (F-I1, M4): a structure ID that the version's own print gives for a
// trigger is never reported as a mismatch. Table 0354 IDs that a version prints
// literally but that name no printed syntax (v2.3.1 misprints, v2.4 CH02 rows
// Appendix A lacks, v2.5.1 rows one listing lacks) are registered as not
// modelled: information, with a reason naming the row and the structure the
// chapters give; the corrected or caption IDs keep matching. A Deprecated
// Table 0354 row's registration carries the events the row prints (M4).

import Testing
@testable import HL7v2Kit

@Suite("Printed structure IDs are never a mismatch")
struct PrintedStructureIDTests {

    private func structureIssues(_ msh9: String, version: String, _ body: [String] = ["MSA|AA|1"]) throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let wire = (["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||\(msh9)|MSG00001|P|\(version)"] + body).joined(separator: "\r")
        return Validator(options: options).validate(try Parser().parse(wire)).issues.filter {
            switch $0.code {
            case .messageStructureSegmentMissing, .messageStructureSegmentUnexpected,
                 .messageStructureMismatch, .messageStructureNotModelled: true
            default: false
            }
        }
    }

    private func resolved(_ msh9: String, version: String) throws -> String? {
        let wire = "MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||\(msh9)|MSG00001|P|\(version)\rMSA|AA|1"
        return Validator().resolveStructure(try Parser().parse(wire), severity: .error).structure?.id
    }

    /// (MSH-9, version, the registered ID, text the reason must hold)
    static let literal: [(String, String, String, String)] = [
        // v2.3.1 Table 0354 (Chapter 2 section 2.24.1.9, pp 2-103 to 2-106, repeated in Appendix A):
        // the trigger from the chapter with the printed ID, and the row's own event with it.
        ("TBR^R08^TBR_R09", "2.3.1", "TBR_R09", "TBR_R08"), ("TBR^R09^TBR_R09", "2.3.1", "TBR_R09", "TBR_R08"),
        ("RRE^O02^RRE_O01", "2.3.1", "RRE_O01", "RRE_O02"), ("RRE^O01^RRE_O01", "2.3.1", "RRE_O01", "RRE_O02"),
        ("MFD^MFA^MFD_P09", "2.3.1", "MFD_P09", "MFD_MFA"), ("MFD^P09^MFD_P09", "2.3.1", "MFD_P09", "MFD_MFA"),
        ("PIN^I07^PIN_107", "2.3.1", "PIN_107", "PIN_I07"), ("RPI^I01^RPI_I0I", "2.3.1", "RPI_I0I", "RPI_I01"),
        ("RPI^I04^RPI_I0I", "2.3.1", "RPI_I0I", "RPI_I01"), ("RQI^I01^RQI_I0I", "2.3.1", "RQI_I0I", "RQI_I01"),
        ("ADR^A19^ARD_A19", "2.3.1", "ARD_A19", "ADR_A19"), ("SIU^S12^SIIU_S12", "2.3.1", "SIIU_S12", "SIU_S12"),
        ("ROR^ROR^RROR_ROR", "2.3.1", "RROR_ROR", "ROR_ROR"), ("ORM^O01^ORM__O01", "2.3.1", "ORM__O01", "ORM_O01"),
        // v2.4 CH02 Table 0354 (section 2.17.3, pp 2-138 to 2-141) rows Appendix A does not print.
        ("QRY^Q26^QRY_Q26", "2.4", "QRY_Q26", "QRY^Q26^QRY_Q01"), ("QRY^Q27^QRY_Q27", "2.4", "QRY_Q27", "QRY^Q27^QRY_Q01"),
        ("QRY^Q28^QRY_Q28", "2.4", "QRY_Q28", "QRY^Q28^QRY_Q01"), ("QRY^Q29^QRY_Q29", "2.4", "QRY_Q29", "QRY^Q29^QRY_Q01"),
        ("QRY^Q30^QRY_Q30", "2.4", "QRY_Q30", "QRY^Q30^QRY_Q01"), ("RPI^I01^RPI_I0I", "2.4", "RPI_I0I", "RPI_I01"),
        ("RQI^I07^RQI_I0I", "2.4", "RQI_I0I", "RQI_I01"), ("TBR^R09^TBR_R09", "2.4", "TBR_R09", "Appendix A"),
        ("ORN^O08^ORN_008", "2.4", "ORN_008", "ORN_O08"), ("RDE^O01^RDE_O01", "2.4", "RDE_O01", "RDE_O11"),
        // v2.5.1: a row one listing of Table 0354 prints and the other does not.
        ("BRP^O30^BRP_030", "2.5.1", "BRP_030", "BRP_O30"), ("RSP^Q11^RSP_Q11", "2.5.1", "RSP_Q11", "Appendix A"),
    ]

    @Test("A literally printed Table 0354 ID is information naming the structure the chapters give", arguments: literal)
    func literalID(_ c: (String, String, String, String)) throws {
        let issues = try structureIssues(c.0, version: c.1)
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: c.2)], "\(c.0) v\(c.1): \(issues.map(\.message))")
        #expect(issues.first?.severity == .info)
        #expect(issues.first?.message.contains(c.3) == true, "\(c.0) v\(c.1): \(issues.map(\.message))")
        #expect(issues.first?.message.contains("not structure-checked") == true, "\(c.0) v\(c.1): \(issues.map(\.message))")
    }

    @Test("The corrected and caption IDs, and the bare triggers, keep resolving to the modelled structure",
          arguments: [("TBR^R08^TBR_R08", "2.3.1", "TBR_R08"), ("TBR^R08", "2.3.1", "TBR_R08"),
                      ("RRE^O02^RRE_O02", "2.3.1", "RRE_O02"), ("MFD^MFA^MFD_MFA", "2.3.1", "MFD_MFA"),
                      ("PIN^I07^PIN_I07", "2.3.1", "PIN_I07"), ("RPI^I04^RPI_I01", "2.3.1", "RPI_I01"),
                      ("RQI^I02^RQI_I01", "2.3.1", "RQI_I01"), ("ADR^A19^ADR_A19", "2.3.1", "ADR_A19"),
                      ("SIU^S12^SIU_S12", "2.3.1", "SIU_S12"), ("SIU^S12", "2.3.1", "SIU_S12"),
                      ("ROR^ROR^ROR_ROR", "2.3.1", "ROR_ROR"),
                      ("QRY^Q26^QRY_Q01", "2.4", "QRY_Q01"), ("QRY^Q30", "2.4", "QRY_Q01"),
                      ("RPI^I01^RPI_I01", "2.4", "RPI_I01"), ("ORN^O08^ORN_O08", "2.4", "ORN_O08"),
                      ("TBR^R08^TBR_R08", "2.4", "TBR_R08"), ("BRP^O30^BRP_O30", "2.5.1", "BRP_O30")])
    func correctedIDs(_ c: (String, String, String)) throws {
        #expect(try resolved(c.0, version: c.1) == c.2, "\(c.0) v\(c.1)")
    }

    // v2.5.1 IDs the two listings of Table 0354 disagree on, or a caption contradicts: info.
    @Test("v2.5.1 IDs the listings or a caption contradict are information",
          arguments: ["ORU^R31^ORU_R31", "ORU^R32^ORU_R32", "RDE^O01^RDE_O01", "RRA^O02^RRA_O02",
                      "QRY^T12^QRY_T12", "RSP^K22^RSP_K22", "TBR^R09^TBR_R09"])
    func v251Listings(_ msh9: String) throws {
        let issues = try structureIssues(msh9, version: "2.5.1")
        #expect(issues.count == 1 && issues.first?.severity == .info, "\(msh9): \(issues.map(\.message))")
    }

    // Table 0354 lists PCC under PPG_PCG on every version from v2.5.1 (CH02 / CH02C), as on
    // v2.3.1, v2.4 and v2.7.1; since S3-3 PPG_PCG is modelled (open slot) and takes PCC among
    // its triggers from the table, so PPG^PCC^PPG_PCG is matched: no mismatch, no information.
    @Test("PPG^PCC^PPG_PCG is matched against PPG_PCG wherever Table 0354 lists PCC under it",
          arguments: ["2.3.1", "2.4", "2.5.1", "2.6", "2.7.1", "2.8.2"])
    func goalPathwayPCC(_ version: String) throws {
        let grammar = try #require(Version(rawValue: version))
        let structure = try #require(MessageStructureTable.structure("PPG_PCG", version: grammar))
        #expect(structure.triggers.contains("PPG^PCC"), "v\(version)")
        #expect(try structureIssues("PPG^PCC^PPG_PCG", version: version, ["PID|1", "PTH|1"]).isEmpty, "v\(version)")
        let issues = try structureIssues("PPG^PCC^PPG_PCG", version: version, ["PID|1"])
        #expect(issues.map(\.code) == [.messageStructureSegmentMissing(structure: "PPG_PCG", segmentID: "PTH", group: "PATHWAY")],
                "v\(version): \(issues.map(\.message))")
    }

    // F-I1 (c): each version's CH07 W01 section says the waveform trigger "identifies ORU
    // messages" (v2.3.1 7.19.1 p 7-117; v2.4 7.15.1 p 7-117; v2.5.1 7.15.1 p 7-130; v2.6 7.15.1
    // p 7-110; v2.7.1 7.14.1 p 140; v2.8.2 7.15.1 p 153) and v2.6 to v2.8.2's examples send
    // ORU^W01^ORU_R01, so W01 is folded onto ORU_R01; Table 0354's ORU_W01 stays registered.
    static let waveformVersions = ["2.3.1", "2.4", "2.5.1", "2.6", "2.7.1", "2.8.2"]
    static let waveformBody = ["PID|1||12345", "OBR|1", "OBX|1|NM|1^A||1"]

    @Test("ORU^W01^ORU_R01 is matched against ORU_R01", arguments: waveformVersions)
    func waveformAsR01(_ version: String) throws {
        #expect(try resolved("ORU^W01^ORU_R01", version: version) == "ORU_R01", "v\(version)")
        let issues = try structureIssues("ORU^W01^ORU_R01", version: version, Self.waveformBody)
        #expect(issues.isEmpty, "v\(version): \(issues.map(\.message))")
    }

    @Test("ORU^W01^ORU_W01, the Table 0354 ID, is still information", arguments: waveformVersions)
    func waveformTableID(_ version: String) throws {
        let issues = try structureIssues("ORU^W01^ORU_W01", version: version, Self.waveformBody)
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: "ORU_W01")], "v\(version): \(issues.map(\.message))")
        #expect(issues.first?.severity == .info)
    }

    @Test("A bare ORU^W01 is never an error or a warning", arguments: waveformVersions)
    func waveformBare(_ version: String) throws {
        let issues = try structureIssues("ORU^W01", version: version, Self.waveformBody)
        #expect(issues.allSatisfy { $0.severity == .info }, "v\(version): \(issues.map(\.message))")
        #expect(!issues.contains { if case .messageStructureMismatch = $0.code { true } else { false } })
    }

    // F-I1 (d): v2.4 CH02 2.14.2 (p 2-97) prints MCF^varies^ACK, the delayed acknowledgment,
    // with the ACK syntax; MCF^<event>^ACK is matched against ACK, not a mismatch.
    @Test("v2.4 MCF^<event>^ACK is matched against ACK", arguments: ["MCF^A01^ACK", "MCF^R01^ACK", "MCF^A01"])
    func delayedAcknowledgment(_ msh9: String) throws {
        #expect(try resolved(msh9, version: "2.4") == "ACK", "\(msh9)")
        #expect(try structureIssues(msh9, version: "2.4").isEmpty)
    }

    // F-I1 (d): query profile rows print an ID the captions do not: v2.8.2 CH04 4.16.6 and
    // 4.16.8 (pp 157 to 158) 'Query Trigger: QBP^Q33^QBP_Q33' (caption QBP^Q33^QBP_O33) and so
    // on; v2.7.1 CH03 3.3.63 (p 53) and v2.8.2 CH03 3.2.63 (p 55) 'Response Trigger:
    // RSP^K32^RSP_K25' (the profile's grammar and Table 0354 give RSP_K32; RSP_K25 is modelled
    // for RSP^K25). Each is information naming the structure the caption gives.
    @Test("A query profile's printed ID is information naming the caption's structure",
          arguments: [("QBP^Q33^QBP_Q33", "2.8.2", "QBP_Q33", "QBP_O33"), ("RSP^K33^RSP_K33", "2.8.2", "RSP_K33", "RSP_O33"),
                      ("QBP^Q34^QBP_Q34", "2.8.2", "QBP_Q34", "QBP_O34"), ("RSP^K34^RSP_K34", "2.8.2", "RSP_K34", "RSP_O34"),
                      ("RSP^K32^RSP_K25", "2.7.1", "RSP_K25", "RSP_K32"), ("RSP^K32^RSP_K25", "2.8.2", "RSP_K25", "RSP_K32")])
    func queryProfileID(_ c: (String, String, String, String)) throws {
        let issues = try structureIssues(c.0, version: c.1)
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: c.2)], "\(c.0) v\(c.1): \(issues.map(\.message))")
        #expect(issues.first?.severity == .info)
        #expect(issues.first?.message.contains(c.3) == true, "\(c.0) v\(c.1): \(issues.map(\.message))")
    }

    @Test("The printed pair is information for that trigger only; the modelled structures still resolve",
          arguments: [("RSP^K25^RSP_K25", "2.8.2", "RSP_K25"), ("RSP^K32^RSP_K32", "2.8.2", "RSP_K32"),
                      ("RSP^K32", "2.7.1", "RSP_K32"), ("QBP^Q33^QBP_O33", "2.8.2", "QBP_O33")])
    func queryProfileOthers(_ c: (String, String, String)) throws {
        #expect(try resolved(c.0, version: c.1) == c.2, "\(c.0) v\(c.1)")
    }

    // M4: v2.7.1 CH02C 2.C.2.175 (p 104) and v2.8.2 CH02C 2.C.2.279 (p 152) print the row
    // 'ORM_O01  O01  Deprecated'; a bare ORM^O01 resolves to that registration and its reason.
    @Test("A bare trigger of a Deprecated Table 0354 row gets the Deprecated reason (M4)",
          arguments: [("ORM^O01", "2.7.1", "ORM_O01"), ("ORM^O01", "2.8.2", "ORM_O01"),
                      ("VXQ^V01", "2.7.1", "VXQ_V01"), ("RSP^Q11", "2.8.2", "RSP_Q11")])
    func deprecatedRow(_ c: (String, String, String)) throws {
        let issues = try structureIssues(c.0, version: c.1)
        #expect(issues.map(\.code) == [.messageStructureNotModelled(structure: c.0)], "\(c.0) v\(c.1): \(issues.map(\.message))")
        #expect(issues.first?.message.contains("under \(c.2)") == true, "\(issues.map(\.message))")
        #expect(issues.first?.message.contains("Deprecated") == true, "\(issues.map(\.message))")
    }
}
