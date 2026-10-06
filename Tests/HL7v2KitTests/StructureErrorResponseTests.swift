// StructureErrorResponseTests.swift
// S4-3 (requirement 4 evidence): the query error response (CH05 5.6.5 on v2.4 to v2.8.2). A
// query response whose MSA-1 is AE or AR "contains the MSH, MSA, ERR, QAK and the query defining
// segment if available" and "The rest of the message is absent" (v2.5.1 p 5-61), so it is matched
// against that head, in the structure's printed order, instead of the full structure. v2.3 and
// v2.3.1 print no such sentence (CH02 2.22), so their responses keep the full structure. Segment
// content is minimal; only structure issues are read.

import Testing
@testable import HL7v2Kit

@Suite("Query error response probes")
struct StructureErrorResponseTests {

    typealias Probe = StructureSlotProbeTests.Probe

    static let probes: [Probe] = [
        // v2.5.1 CH05 5.10.6.2.12 (p 5-143): the event replay error response example, MSH MSA ERR QAK.
        Probe(version: "2.5.1", msh9: "ERP^R09^ERP_R09", structure: "ERP_R09",
              body: ["MSA|AE|MSG00004||||^NOT SUPPORTED", "ERR|MSH^^9^201&&HL70357", "QAK|TAG0002|AE"],
              findings: [], note: "the 5.10.6.2.12 error response"),
        Probe(version: "2.5.1", msh9: "ERP^R09^ERP_R09", structure: "ERP_R09",
              body: ["MSA|AE|MSG00004", "ERR|MSH^^9^201&&HL70357", "QAK|TAG0002|AE", "DSP|1||TEXT"],
              findings: ["unexpected DSP at DSP[1]"], note: "the rest of the message is absent"),
        Probe(version: "2.5.1", msh9: "ERP^R09^ERP_R09", structure: "ERP_R09",
              body: ["MSA|AE|MSG00004", "ERR|MSH^^9^201&&HL70357", "QAK|TAG0002|AE", "ERQ|TAG0002|A04", "DSC|"],
              findings: [], note: "the query defining segment and a DSC without a pointer"),
        Probe(version: "2.5.1", msh9: "ERP^R09^ERP_R09", structure: "ERP_R09",
              body: ["MSA|AE|MSG00004", "QAK|TAG0002|AE", "ERQ|TAG0002|A04", "EVN|A04", "PID|1"],
              findings: ["unexpected EVN at EVN[1]", "unexpected PID at PID[1]"],
              note: "an event replay body in an error response"),
        // v2.4 CH05 5.10.6.2.11 example (TBR^R08 error response, MSH-12 2.4): MSH MSA ERR QAK.
        Probe(version: "2.4", msh9: "TBR^R08^TBR_R08", structure: "TBR_R08",
              body: ["MSA|AE|MSG00001|", "ERR|EQL^^4^207&&HL70357", "QAK|TAG0001|AE"],
              findings: [], note: "the TBR error response"),
        Probe(version: "2.4", msh9: "TBR^R08^TBR_R08", structure: "TBR_R08",
              body: ["MSA|AR|MSG00001", "ERR|MSH^^9^201&&HL70357"],
              findings: [], note: "an application reject: MSH, MSA and ERR only"),
        // AA keeps the full structure: a response without its body draws the missing segments.
        Probe(version: "2.4", msh9: "TBR^R08^TBR_R08", structure: "TBR_R08",
              body: ["MSA|AA|MSG00001", "QAK|TAG0001|OK"],
              findings: ["missing RDF at the end", "missing RDT at the end"], note: "MSA-1 AA, body missing"),
        // The head follows the structure's printed order: ORF_R04 prints ERR and QAK after the body.
        Probe(version: "2.4", msh9: "ORF^R04^ORF_R04", structure: "ORF_R04",
              body: ["MSA|AE|1", "QRD|200401011200|R|I|Q1", "ERR|QRD^^1^207&&HL70357", "QAK|Q1|AE"],
              findings: [], note: "ORF error response in printed order"),
        Probe(version: "2.4", msh9: "ORF^R04^ORF_R04", structure: "ORF_R04",
              body: ["MSA|AE|1", "QRD|200401011200|R|I|Q1", "PID|1", "ERR|QRD^^1^207&&HL70357"],
              findings: ["unexpected PID at PID[1]"], note: "ORF error response with a patient"),
        // v2.6 to v2.8.2: SFT (and UAC from v2.6) as the structure prints them after MSH; QPD the query.
        Probe(version: "2.6", msh9: "RSP^K21^RSP_K21", structure: "RSP_K21",
              body: ["SFT|VENDOR|1.0|PRODUCT|1", "MSA|AE|1", "ERR||QPD^1^3^1&&HL70357|207^Application internal error^HL70357|E",
                     "QAK|Q1|AE", "QPD|Q22^Find Candidates^HL70471|Q1"],
              findings: [], note: "RSP_K21 error response with SFT and QPD"),
        Probe(version: "2.8.2", msh9: "RSP^K21^RSP_K21", structure: "RSP_K21",
              body: ["MSA|AE|1", "ERR||QPD^1^3^1&&HL70357|207^Application internal error^HL70357|E",
                     "QAK|Q1|AE", "QPD|Q22^Find Candidates^HL70471|Q1", "PID|1"],
              findings: ["unexpected PID at PID[1]"], note: "RSP_K21 error response with a patient"),
        // v2.3 and v2.3.1 print no "rest of the message is absent" sentence (CH02 2.22): unchanged.
        Probe(version: "2.3", msh9: "ERP^R09", structure: "ERP",
              body: ["MSA|AE|MSG00004", "ERR|MSH^^9^201", "QAK|TAG0002|AE"],
              findings: ["missing ERQ at the end"], note: "v2.3 keeps the full structure"),
        Probe(version: "2.3.1", msh9: "TBR^R08^TBR_R08", structure: "TBR_R08",
              body: ["MSA|AE|MSG00001", "QAK|TAG0001|AE"],
              findings: ["missing RDF at the end", "missing RDT at the end"], note: "v2.3.1 keeps the full structure"),
    ]

    @Test("Error responses match the 5.6.5 head; AA responses and v2.3 to v2.3.1 the full structure",
          arguments: probes)
    func probe(_ p: Probe) throws {
        let version = try #require(Version(rawValue: p.version))
        #expect(MessageStructureTable.structure(p.structure, version: version) != nil,
                "\(p.structure) is not modelled on v\(p.version)")
        let issues = try StructureSlotProbeTests.structureIssues(p.msh9, p.version, p.body)
        #expect(issues.map(StructureKeyedChoiceTests.describe) == p.findings, "\(p.testDescription): \(issues.map(\.message))")
    }

    @Test("A finding in an error response says why the head was matched")
    func findingText() throws {
        let issues = try StructureSlotProbeTests.structureIssues(
            "ERP^R09^ERP_R09", "2.5.1", ["MSA|AE|MSG00004", "QAK|TAG0002|AE", "DSP|1||TEXT"])
        let issue = try #require(issues.first)
        #expect(issue.message.contains("MSA-1 is AE") && issue.message.contains("5.6.5"), "\(issue.message)")
    }

    @Test("The generated tables carry the rule on v2.4 to v2.8.2 query responses only")
    func tables() throws {
        let tbr = try #require(MessageStructureTable.structure("TBR_R08", version: .v2_4))
        #expect(tbr.errorResponse?.acknowledgmentCodes == ["AE", "AR"])
        #expect(tbr.errorResponse?.querySegments == [])
        let erp = try #require(MessageStructureTable.structure("ERP_R09", version: .v2_5_1))
        #expect(erp.errorResponse?.querySegments == ["ERQ"])
        #expect(erp.errorResponse?.citation.contains("5.6.5") == true)
        let rsp = try #require(MessageStructureTable.structure("RSP_K21", version: .v2_8_2))
        #expect(rsp.errorResponse?.querySegments == ["QPD"])
        for (id, version) in [("ERP", Version.v2_3), ("TBR_R08", .v2_3_1), ("ADT_A01", .v2_5_1), ("ACK", .v2_5_1)] {
            let s = try #require(MessageStructureTable.structure(id, version: version), "\(id) v\(version.rawValue)")
            #expect(s.errorResponse == nil, "\(id) v\(version.rawValue)")
        }
    }

    @Test("The head keeps the printed order and inserts the ERR and QAK the print omits")
    func head() throws {
        let rar = try #require(MessageStructureTable.structure("RAR_RAR", version: .v2_5_1))
        let head = try #require(rar.errorResponseHead(acknowledgmentCode: "AE"))
        #expect(head.elements == [.segment("MSH", min: 1, max: 1), .segment("MSA", min: 1, max: 1),
                                  .segment("ERR", min: 0, max: nil), .segment("QAK", min: 0, max: 1),
                                  .segment("SFT", min: 0, max: nil), .segment("QRD", min: 0, max: 1),
                                  .segment("QRF", min: 0, max: 1), .segment("DSC", min: 0, max: 1)])
        #expect(head.keySelection == "MSA-1=AE" && head.errorResponse == nil)
        #expect(rar.errorResponseHead(acknowledgmentCode: "AA") == nil)
        #expect(rar.errorResponseHead(acknowledgmentCode: nil) == nil)
    }

    @Test("Group spans of an error response come from the head")
    func spans() throws {
        let wire = ["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||TBR^R08^TBR_R08|MSG00001|P|2.4",
                    "MSA|AE|MSG00001", "ERR|EQL^^4^207&&HL70357", "QAK|TAG0001|AE"].joined(separator: "\r")
        let outcome = Validator().groupSpanOutcome(for: try Parser().parse(wire))
        #expect(outcome.spans != nil, "\(outcome.cause ?? "")")
    }
}
