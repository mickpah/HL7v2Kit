// ARVPlacementTests.swift
// The HL7 CTO's letter of 29 March 2021 corrects v2.9: in any message definition containing PID,
// ARV SHALL immediately follow MSH as [{ARV}], or MSA when present; placement anywhere else is
// not permitted. The printed v2.9 structures do not all carry it.

import Testing
@testable import HL7v2Kit

@Suite("ARV placement")
struct ARVPlacementTests {
    static func msh(_ type: String) -> String { "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||\(type)|MSG00001|P|2.9" }
    static let header = msh("ADT^A01^ADT_A01")
    static let arv = "ARV|1|A^Add^HL70206|ALL^All^HL70717||||R^Restricted^HL70952"
    static let evn = "EVN||20240301120000"
    static let pid = "PID|1||123456^^^HOSP^MR||Smith^John"
    static let pv1 = "PV1|1|I"

    /// Segment IDs in printed order. `StructureElement.segmentIDs` is a set, so it cannot say what follows what.
    static func ordered(_ elements: [StructureElement]) -> [String] {
        elements.flatMap { element -> [String] in
            if case .segment(let id, _, _) = element { return [id] }
            return ordered(element.children)
        }
    }

    private func structureIssues(_ lines: [String]) throws -> [ValidationIssue] {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let wire = lines.joined(separator: "\r") + "\r"
        return Validator(options: options).validate(try Parser().parse(wire)).issues.filter(\.code.isMessageStructure)
    }

    @Test("An ARV directly after MSH draws no structure finding")
    func afterHeader() throws {
        #expect(try structureIssues([Self.header, Self.arv, Self.evn, Self.pid, Self.pv1]).isEmpty)
    }

    @Test("An ARV in the body draws the misplaced-segment finding")
    func inBody() throws {
        let found = try structureIssues([Self.header, Self.evn, Self.pid, Self.arv, Self.pv1])
        #expect(found.map(\.code).contains(.messageStructureSegmentUnexpected(structure: "ADT_A01", segmentID: "ARV")))
    }

    @Test("Where MSA is present, ARV follows MSA and not MSH")
    func afterAcknowledgment() throws {
        // CH03 3.3.56 p 89 prints MSH [{ARV}] [{SFT}] [UAC] MSA; the letter's "unless MSA is present" moves it.
        let header = Self.msh("RSP^K21^RSP_K21")
        let msa = "MSA|AA|MSG00001"
        let query = ["QAK|1|OK", "QPD|Q21"]
        #expect(try structureIssues([header, msa, Self.arv] + query).isEmpty)
        // The matcher reads this ARV as the one after MSA, so the finding names MSA, missing and then misplaced.
        #expect(try structureIssues([header, Self.arv, msa] + query).map(\.code) == [
            .messageStructureSegmentMissing(structure: "RSP_K21", segmentID: "MSA", group: nil),
            .messageStructureSegmentUnexpected(structure: "RSP_K21", segmentID: "MSA"),
        ])
    }

    @Test("Every v2.9 print holding PID has one ARV, directly after MSA or else MSH")
    func everyStructure() {
        for (id, structure) in MessageStructureTable.structures(for: .v2_9) {
            for elements in [structure.elements] + structure.variants.map(\.elements) {
                let ids = Self.ordered(elements)
                guard ids.contains("PID") else { continue }
                if id == "RRI_I12" {
                    // The one print with an optional MSA takes both places: see optionalMSA.
                    #expect(Array(elements.prefix(5)) == Self.bothPlaces)
                    continue
                }
                #expect(elements.contains(.segment("ARV", min: 0, max: nil)), "\(id)")
                #expect(ids.filter { $0 == "ARV" }.count == 1, "\(id)")
                guard let at = ids.firstIndex(of: "ARV"), at > 0 else { continue }
                let topLevelMSA = elements.contains {
                    if case .segment("MSA", _, _) = $0 { return true } else { return false }
                }
                #expect(ids[at - 1] == (topLevelMSA ? "MSA" : "MSH"), "\(id)")
            }
        }
    }

    @Test("A structure the print gave no ARV gains the letter's")
    func structureWithoutPrintedARV() throws {
        // RSP_K31 prints ARV only in its body; CCU_I20 prints none.
        for id in ["RSP_K31", "CCU_I20"] {
            let structure = try #require(MessageStructureTable.structures(for: .v2_9)[id], "\(id)")
            #expect(Self.ordered(structure.elements).contains("ARV"), "\(id)")
        }
    }

    @Test("[{ARV}] repeats")
    func repeats() throws {
        #expect(try structureIssues([Self.header, Self.arv, Self.arv, Self.evn, Self.pid, Self.pv1]).isEmpty)
    }

    @Test("A variant print takes the rule on the wire")
    func variantPrint() throws {
        let a13 = Self.msh("ADT^A13^ADT_A01")
        #expect(try structureIssues([a13, Self.arv, Self.evn, Self.pid, Self.pv1]).isEmpty)
        let found = try structureIssues([a13, Self.evn, Self.pid, Self.arv, Self.pv1])
        #expect(found.map(\.code) == [.messageStructureSegmentUnexpected(structure: "ADT_A01", segmentID: "ARV")])
    }

    // A query error or no-data response (CH05 5.6.5, pp 62 to 63) is matched against its head. The letter
    // covers "any message definition containing" PID and says "at the top of the messages", so the head
    // admits the structure's top-level ARV; 5.6.5's "rest of the message" is the body.
    static let err = "ERR||QPD^1^3^1&&HL70357|207^Application internal error^HL70357|E"
    static let qpd = "QPD|Q22^Find Candidates^HL70471|Q1"

    @Test("A query error response admits ARV directly after MSA", arguments: ["RSP^K21^RSP_K21", "RSP^K31^RSP_K31"])
    func errorResponse(_ type: String) throws {
        let msa = [Self.msh(type), "MSA|AE|1"]
        #expect(try structureIssues(msa + [Self.arv, Self.err, "QAK|Q1|AE", Self.qpd]).isEmpty, "\(type)")
        #expect(try structureIssues(msa + [Self.arv, Self.arv, Self.err, "QAK|Q1|AE", Self.qpd]).isEmpty, "\(type)")
    }

    @Test("A no-data query response admits ARV directly after MSA")
    func noDataResponse() throws {
        #expect(try structureIssues([Self.msh("RSP^K21^RSP_K21"), "MSA|AA|1", Self.arv, "QAK|Q1|NF", Self.qpd]).isEmpty)
    }

    @Test("A query error response still reports an ARV ahead of MSA and the rest of the message")
    func errorResponseLimits() throws {
        let k21 = Self.msh("RSP^K21^RSP_K21")
        #expect(try !structureIssues([k21, Self.arv, "MSA|AE|1", Self.err, "QAK|Q1|AE", Self.qpd]).isEmpty)
        let body = try structureIssues([k21, "MSA|AE|1", Self.arv, Self.err, "QAK|Q1|AE", Self.qpd, Self.pid])
        #expect(body.map(\.code) == [.messageStructureSegmentUnexpected(structure: "RSP_K21", segmentID: "PID")])
    }

    @Test("A body ARV stays out of a head: v2.8.2 RSP_K21 prints ARV only in its group")
    func bodyARVStaysOut() throws {
        let k21 = try #require(MessageStructureTable.structure("RSP_K21", version: .v2_8_2))
        #expect(Self.ordered(k21.elements).contains("ARV"))
        let head = try #require(k21.errorResponseHead(acknowledgmentCode: "AE"))
        #expect(head.elements == [.segment("MSH", min: 1, max: 1), .segment("SFT", min: 0, max: nil),
                                  .segment("UAC", min: 0, max: 1), .segment("MSA", min: 1, max: 1),
                                  .segment("ERR", min: 0, max: 1), .segment("QAK", min: 0, max: 1),
                                  .segment("QPD", min: 0, max: 1), .segment("DSC", min: 0, max: 1)])
    }

    @Test("An ERR the print omits goes after an ARV that follows MSA, and otherwise after MSA")
    func insertedERR() throws {
        func head(_ elements: [StructureElement]) throws -> [StructureElement] {
            let rule = StructureErrorResponse(acknowledgmentCodes: ["AE"], querySegments: ["QPD"], citation: "c")
            let structure = MessageStructure(id: "RSP_X", version: "2.9", triggers: ["RSP^X"], citation: "c",
                                             errorResponse: rule, elements: elements)
            return try #require(structure.errorResponseHead(acknowledgmentCode: "AE")).elements
        }
        let msh = StructureElement.segment("MSH", min: 1, max: 1), msa = StructureElement.segment("MSA", min: 1, max: 1)
        let arv = StructureElement.segment("ARV", min: 0, max: nil), qak = StructureElement.segment("QAK", min: 0, max: 1)
        let err = StructureElement.segment("ERR", min: 0, max: 1), qpd = StructureElement.segment("QPD", min: 0, max: 1)
        #expect(try head([msh, msa, arv, qak, qpd]) == [msh, msa, arv, err, qak, qpd])
        #expect(try head([msh, arv, msa, qak, qpd]) == [msh, arv, msa, err, qak, qpd])
    }

    // RRI_I12 prints [MSA] (CH11 11.5.1, p 22). The letter decides on the message and one position cannot,
    // so this print takes both places: [{ARV}] after MSH, and [ MSA [{ARV}] ] where MSA stood.
    static let bothPlaces: [StructureElement] = [
        .segment("MSH", min: 1, max: 1), .segment("ARV", min: 0, max: nil), .segment("SFT", min: 0, max: nil),
        .segment("UAC", min: 0, max: 1),
        .group("MSA_GROUP", min: 0, max: 1, elements: [.segment("MSA", min: 1, max: 1), .segment("ARV", min: 0, max: nil)]),
    ]
    static let rri = msh("RRI^I12^RRI_I12")
    static let referral = ["RF1|1", "PRD|1", pid]

    @Test("An optional MSA takes ARV after MSH when absent, and after MSA when present")
    func optionalMSA() throws {
        let msa = "MSA|AA|1", sft = "SFT|1"
        #expect(try structureIssues([Self.rri, Self.arv, sft] + Self.referral).isEmpty)
        #expect(try structureIssues([Self.rri, sft, msa, Self.arv] + Self.referral).isEmpty)
        #expect(try structureIssues([Self.rri, sft] + Self.referral).isEmpty)
        #expect(try structureIssues([Self.rri, sft, msa] + Self.referral).isEmpty)
        #expect(try !structureIssues([Self.rri, sft, Self.arv] + Self.referral).isEmpty)
    }

    @Test("Known limit: on RRI_I12 an ARV ahead of a present MSA passes")
    func optionalMSALimit() throws {
        // The letter forbids this, but both places are open to a structure that cannot tell whether MSA
        // will follow. A missed finding, not a false one; the register carries it.
        #expect(try structureIssues([Self.rri, Self.arv, "SFT|1", "MSA|AA|1"] + Self.referral).isEmpty)
    }

    static let header291 = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||ADT^A01^ADT_A01|MSG00001|P|2.9.1"

    @Test("2.9.1 follows its own print: an ARV after PID is accepted, printed with status B")
    func bodyARVOnV291() throws {
        #expect(try structureIssues([Self.header291, Self.evn, Self.pid, Self.arv, Self.pv1]).isEmpty)
    }

    @Test("2.9.1 keeps structures as printed: CCU_I20 gains no ARV, unlike v2.9")
    func letterNotApplied() throws {
        let tables = MessageStructureTable.structures(for: .v2_9_1)
        let adt = try #require(tables["ADT_A01"])
        #expect(Self.ordered(adt.elements).filter { $0 == "ARV" }.count > 1)
        // CH11 11.6.6 pp 38 to 40 holds PID and prints no ARV.
        let ccu = try #require(tables["CCU_I20"])
        #expect(Self.ordered(ccu.elements).contains("PID"))
        #expect(!Self.ordered(ccu.elements).contains("ARV"))
        let ccuV29 = try #require(MessageStructureTable.structures(for: .v2_9)["CCU_I20"])
        #expect(Self.ordered(ccuV29.elements).contains("ARV"))
    }

    // D4: the same wire, on both sides of the letter.
    @Test("The same body ARV draws the finding on v2.9 and none on 2.9.1")
    func sameWireEachWay() throws {
        let body = [Self.evn, Self.pid, Self.arv, Self.pv1]
        #expect(try structureIssues([Self.header291] + body).isEmpty)
        #expect(try structureIssues([Self.header] + body).map(\.code) == [.messageStructureSegmentUnexpected(structure: "ADT_A01", segmentID: "ARV")])
    }

    @Test("An ARV where 2.9.1 prints none stays a finding")
    func unprintedPlaceOnV291() throws {
        // CH03 3.3.1 pp 6 to 8 prints ARV after MSH, PD1 and PV2, not between EVN and PID. The matcher reads this
        // ARV as the one after PD1, so the finding names PID, missing and then misplaced.
        #expect(try structureIssues([Self.header291, Self.evn, Self.arv, Self.pid, Self.pv1]).map(\.code) == [
            .messageStructureSegmentMissing(structure: "ADT_A01", segmentID: "PID", group: nil),
            .messageStructureSegmentUnexpected(structure: "ADT_A01", segmentID: "PID"),
        ])
    }

    static func msh291(_ type: String) -> String { "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240301120000||\(type)|MSG00001|P|2.9.1" }

    // R27 on 2.9.1: the head takes the print's own top-level ARV, so RSP_K21's follows MSH (CH03 3.3.56 p 97).
    @Test("A 2.9.1 RSP_K21 error response takes ARV after MSH, where the print has it")
    func headFollowsThePrint() throws {
        let k21 = Self.msh291("RSP^K21^RSP_K21"), tail = [Self.err, "QAK|Q1|AE", Self.qpd]
        #expect(try structureIssues([k21, Self.arv, "MSA|AE|1"] + tail).isEmpty)
        #expect(try structureIssues([k21, Self.arv, Self.arv, "MSA|AE|1"] + tail).isEmpty)
        #expect(try !structureIssues([k21, "MSA|AE|1", Self.arv] + tail).isEmpty)
        #expect(try structureIssues([k21, Self.arv, "MSA|AA|1", "QAK|Q1|NF", Self.qpd]).isEmpty)
        let rule = try #require(MessageStructureTable.structure("RSP_K21", version: .v2_9_1))
        let head = try #require(rule.errorResponseHead(acknowledgmentCode: "AE"))
        #expect(head.elements == [.segment("MSH", min: 1, max: 1), .segment("ARV", min: 0, max: nil), .segment("SFT", min: 0, max: nil),
                                  .segment("UAC", min: 0, max: 1), .segment("MSA", min: 1, max: 1), .segment("ERR", min: 0, max: 1),
                                  .segment("QAK", min: 0, max: 1), .segment("QPD", min: 0, max: 1), .segment("DSC", min: 0, max: 1)])
    }

    // CH04A 4A.3.23 pp 29 to 30 prints RSP_K31's ARV only in its body, and 5.5.5 pp 63 to 64 says the rest of the message is absent.
    @Test("A 2.9.1 RSP_K31 error response admits no ARV: the print has none at its top")
    func k31Head() throws {
        let k31 = Self.msh291("RSP^K31^RSP_K31"), tail = [Self.err, "QAK|Q1|AE", Self.qpd]
        #expect(try structureIssues([k31, "MSA|AE|1"] + tail).isEmpty)
        let found = try structureIssues([k31, "MSA|AE|1", Self.arv] + tail)
        #expect(found.map(\.code) == [.messageStructureSegmentUnexpected(structure: "RSP_K31", segmentID: "ARV")], "\(found.map(\.message))")
    }

    // CH04 4.13.5 p 133 prints MSH MSA [{ARV}]. It is no query response, so no head cuts it short.
    @Test("A 2.9.1 BRP_O30 keeps its printed ARV after MSA, and an AE response is not cut to a head")
    func brpHead() throws {
        let brp = try #require(MessageStructureTable.structure("BRP_O30", version: .v2_9_1))
        #expect(Array(Self.ordered(brp.elements).prefix(3)) == ["MSH", "MSA", "ARV"])
        #expect(brp.errorResponseHead(acknowledgmentCode: "AE") == nil)
    }

    // The ERR-after-ARV branch of the head: no 2.9.1 query response leaves ERR out, so the print does not reach it.
    @Test("Every 2.9.1 query response prints ERR, so its head keeps the printed order")
    func noInsertedERR() throws {
        for (id, structure) in MessageStructureTable.structures(for: .v2_9_1) where structure.errorResponse != nil {
            let printed = Self.ordered(structure.elements)
            #expect(printed.contains("ERR"), "\(id)")
            let head = try #require(structure.errorResponseHead(acknowledgmentCode: "AE")).elements.map(\.label)
            #expect(head == head.sorted { printed.firstIndex(of: $0)! < printed.firstIndex(of: $1)! }, "\(id)")
        }
    }
}
