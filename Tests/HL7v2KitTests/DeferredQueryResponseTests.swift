// DeferredQueryResponseTests.swift
// CH05 "Immediate vs. deferred response" (5.6.1, 5.5.1 on 2.9.1): in immediate mode "The acknowledgement
// of the query is contained within the response message"; in deferred mode "the query is acknowledged
// immediately by an ACK", and the deferred example prints RTB^K42^RTB_K13 as MSH then QAK, with no MSA
// (v2.4 p 5-56 to 2.9.1 p 58). The client picks the mode in RCP-1 of the query, and both printed responses
// carry the same MSH-9, so nothing on a response tells the two apart. RTB_K13 reads MSA as optional on
// v2.4 to 2.9.1: the deferred example draws nothing, and so does an immediate response without MSA.

import Testing
@testable import HL7v2Kit

@Suite("The deferred query response")
struct DeferredQueryResponseTests {
    /// The wire versions whose CH05 prints the deferred example; `2.7` and `2.8` read v2.7.1 and v2.8.2.
    static let printing = ["2.4", "2.5.1", "2.6", "2.7", "2.7.1", "2.8", "2.8.2", "2.9", "2.9.1"]

    // 2.9.1 p 58, with the first of its four RDT rows; the same segments on all seven versions.
    static let body = [
        "QAK|Q010|OK|Q42^Tabular Dispense History^HL7nnn|4",
        "QPD|Q42^Tabular Dispense History^HL7nnn|Q0010|555444222111^^^MPI^MR||19980531|19990531|",
        "RDF|7|PatientId^CX^20~PatientName^XPN^48~OrderControlCode^ID^2~MedicationDispensed^CWE^100~DispenseDate^DTM^24~QuantityDispensed^NM^20~OrderingProvider^XCN^120",
        "RDT|555444222111^^^MPI^MR|Everyman^Adam|RE|525440345^Verapamil Hydrochloride 120 mg TAB^NDC |199805291115-0700|100|77^Hippocrates^Harold^H^III^DR^MD",
    ]
    static let msa = "MSA|AA|8699|"

    private static func codes(_ msh9: String, _ control: String, _ version: String, _ body: [String]) throws -> [IssueCode] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let wire = (["MSH|^~\\&|PIMS|Gen Hosp|PCR||199811210300-0800||\(msh9)|\(control)|P|\(version)"] + body).joined(separator: "\r")
        return Validator(options: options).validate(try Parser().parse(wire)).issues.map(\.code).filter(\.isMessageStructure)
    }

    @Test("The printed deferred response, with no MSA, draws no structure finding", arguments: printing)
    func deferredExample(version: String) throws {
        let found = try Self.codes("RTB^K42^RTB_K13", "9950", version, Self.body)
        #expect(found == [])
    }

    // The under-report: an immediate response must carry the acknowledgement, but only the query says which mode it answers.
    @Test("An immediate response without MSA draws nothing, since the wire cannot tell it from a deferred one",
          arguments: printing)
    func immediateWithoutMSA(version: String) throws {
        for msh9 in ["RTB^K42^RTB_K13", "RTB^K42", "RTB^K13^RTB_K13", "RTB^Z99^RTB_K13"] {
            let found = try Self.codes(msh9, "8858", version, Self.body)
            #expect(found == [], "\(msh9)")
        }
    }

    @Test("With MSA, the immediate and the deferred response are both accepted", arguments: printing)
    func withMSA(version: String) throws {
        #expect(try Self.codes("RTB^K42^RTB_K13", "8858", version, [Self.msa] + Self.body) == [])
        #expect(try Self.codes("RTB^K42^RTB_K13", "9950", version, [Self.msa] + Self.body) == [])
    }

    // The table still places MSA after MSH and before QAK, and QAK and QPD stay required.
    @Test("MSA keeps its place, and the rest of the body is matched as before", arguments: printing)
    func bodyStillMatched(version: String) throws {
        let missing = { (id: String) in IssueCode.messageStructureSegmentMissing(structure: "RTB_K13", segmentID: id, group: nil) }
        let late = try Self.codes("RTB^K42^RTB_K13", "9950", version, [Self.body[0], Self.msa] + Self.body.dropFirst())
        #expect(late == [.messageStructureSegmentUnexpected(structure: "RTB_K13", segmentID: "MSA")])
        let noQAK = try Self.codes("RTB^K42^RTB_K13", "9950", version, Array(Self.body.dropFirst()))
        #expect(noQAK == [missing("QAK")])
        let noQPD = try Self.codes("RTB^K42^RTB_K13", "9950", version, [Self.body[0]])
        #expect(noQPD == [missing("QPD")])
    }

    @Test("RTB_K13 holds MSA as [MSA] from v2.4; RDY_K15 keeps it required")
    func structureData() throws {
        for version in [Version.v2_4, .v2_5_1, .v2_6, .v2_7_1, .v2_8_2, .v2_9, .v2_9_1] {
            let rtb = try #require(MessageStructureTable.structure("RTB_K13", version: version))
            #expect(rtb.elements.first { $0.label == "MSA" } == .segment("MSA", min: 0, max: 1), "v\(version.rawValue)")
            #expect(rtb.elements.filter { ["MSH", "QAK", "QPD"].contains($0.label) }.allSatisfy {
                if case .segment(_, let min, let max) = $0 { return min == 1 && max == 1 }
                return false
            }, "v\(version.rawValue)")
            let rdy = try #require(MessageStructureTable.structure("RDY_K15", version: version))
            #expect(rdy.elements.first { $0.label == "MSA" } == .segment("MSA", min: 1, max: 1), "v\(version.rawValue)")
        }
    }
}
