// GroupScopeCountTests.swift
// S6-2 (ADR-019 S6 amendment): the `.obrObxGroup` count, which the shipped AU rules read
// (HL7au:000008 and HL7au:000008.3.x, minimum one display OBX per OBR/OBX group, applied to
// ORU and REF messages on every version under `.auLocalisation`), counts the OBR's own OBX:
// those after it in its group occurrence, not those in a nested group another segment heads
// (v2.5.1 to v2.8.2 ORU_R01 SPECIMEN { SPM [{OBX}] }; v2.8.2 COMMON_ORDER { ORC
// [ORDER_DOCUMENT { OBX TXA }] }) and not the patient OBX before it (v2.7.1 and v2.8.2
// ORU_R30, where OBR is at message level). Register section E, P8b-18 addendum rows.

import Testing
@testable import HL7v2Kit

@Suite("Group-scope count: the OBR's own OBX")
struct GroupScopeCountTests {

    static func message(_ msh9: String, _ version: String, _ body: [String]) throws -> Message {
        try Parser(locale: .auLocalisation).parse(
            (["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||\(msh9)|MSG00001|P|\(version)"] + body).joined(separator: "\r"))
    }

    static let display = "OBX|1|ED|PDF^Display format in PDF^AUSPDI||^application^pdf^Base64^AAAA||||||F"
    static let numeric = "OBX|2|NM|2345-7^Glucose^LN||5.4|mmol/L|||||F"

    /// v2.8.2 ORU_R01 (CH07 7.3.1): PID, then ORC with an ORDER_DOCUMENT OBX and TXA, the OBR,
    /// its OBSERVATION OBX, and a SPECIMEN with a SPECIMEN_OBSERVATION OBX.
    static func r01(documentOBX: String, observationOBX: String, specimenOBX: String) -> [String] {
        ["PID|1||123^^^H^MR||Citizen^Jan", "ORC|RE|P1|F1", documentOBX, "TXA|1|CN|TX", "OBR|1|P1|F1|X^Test^L",
         observationOBX, "SPM|1|S1", specimenOBX]
    }

    @Test("v2.8.2 ORU_R01: the OBR's group counts its OBSERVATION OBX only")
    func r01Group() throws {
        let message = try Self.message("ORU^R01^ORU_R01", "2.8.2", Self.r01(documentOBX: Self.numeric,
                                                                             observationOBX: Self.numeric, specimenOBX: Self.numeric))
        let ids = message.segments.map(\.segmentID)
        let spans = try #require(Validator().groupSpans(for: message), "no spans: \(ids)")
        let obr = try #require(ids.firstIndex(of: "OBR"))
        let obxs = ids.indices.filter { ids[$0] == "OBX" }
        try #require(obxs.count == 3)
        let group = try #require(spans.group(around: obr, holding: "OBR", counting: "OBX"))
        #expect(group.filter { ids[$0] == "OBX" } == [obxs[1]], "\(group)")
        #expect(group.contains(obr))
    }

    @Test("v2.8.2 ORU_R30: the message-level OBR's group counts the OBX after it, not the patient OBX")
    func r30Group() throws {
        let message = try Self.message("ORU^R30^ORU_R30", "2.8.2",
                                       ["PID|1||123^^^H^MR||Citizen^Jan", Self.numeric, "ORC|NW|P1", "OBR|1|P1||X^Test^L", Self.numeric])
        let ids = message.segments.map(\.segmentID)
        let spans = try #require(Validator().groupSpans(for: message), "no spans: \(ids)")
        let obr = try #require(ids.firstIndex(of: "OBR"))
        let group = try #require(spans.group(around: obr, holding: "OBR", counting: "OBX"))
        #expect(group.filter { ids[$0] == "OBX" } == [ids.count - 1], "\(group)")
    }

    static func auspdiFindings(_ message: Message) -> [ValidationIssue] {
        Validator(options: .default, locale: .auLocalisation).validate(message).issues.filter {
            if case .segmentCardinalityBelowMinimum = $0.code { return $0.message.contains("AUSPDI") }
            return false
        }
    }

    @Test("AU HL7au:000008 on v2.8.2 ORU^R01: a display OBX in the specimen or the order document is not the OBR's")
    func auDisplayRule() throws {
        let inSpecimen = try Self.message("ORU^R01^ORU_R01", "2.8.2", Self.r01(documentOBX: Self.numeric,
                                                                                observationOBX: Self.numeric, specimenOBX: Self.display))
        #expect(!Self.auspdiFindings(inSpecimen).isEmpty)
        let inDocument = try Self.message("ORU^R01^ORU_R01", "2.8.2", Self.r01(documentOBX: Self.display,
                                                                                observationOBX: Self.numeric, specimenOBX: Self.numeric))
        #expect(!Self.auspdiFindings(inDocument).isEmpty)
        let inObservation = try Self.message("ORU^R01^ORU_R01", "2.8.2", Self.r01(documentOBX: Self.numeric,
                                                                                   observationOBX: Self.display, specimenOBX: Self.numeric))
        #expect(Self.auspdiFindings(inObservation).isEmpty, "\(Self.auspdiFindings(inObservation).map(\.message))")
    }

    @Test("Without spans (a structure finding), the OBR walk stops at the specimen's SPM as well")
    func walkStopsAtSpecimen() throws {
        // An NTE after MSH has no place in ORU_R01 (v2.8.2 CH07 7.3.1), so the match has a
        // finding and the group-scope rules take the OBR walk.
        let body = ["NTE|1|L|misplaced"] + Self.r01(documentOBX: Self.numeric, observationOBX: Self.numeric,
                                                      specimenOBX: Self.display)
        let message = try Self.message("ORU^R01^ORU_R01", "2.8.2", body)
        #expect(Validator().groupSpans(for: message) == nil)
        #expect(!Self.auspdiFindings(message).isEmpty)
    }

    @Test("AU HL7au:000008 on v2.8.2 ORU^R30: a patient display OBX before the OBR is not the OBR's")
    func auDisplayRuleR30() throws {
        let patient = try Self.message("ORU^R30^ORU_R30", "2.8.2",
                                       ["PID|1||123^^^H^MR||Citizen^Jan", Self.display, "ORC|NW|P1", "OBR|1|P1||X^Test^L", Self.numeric])
        #expect(!Self.auspdiFindings(patient).isEmpty)
        let own = try Self.message("ORU^R30^ORU_R30", "2.8.2",
                                   ["PID|1||123^^^H^MR||Citizen^Jan", Self.numeric, "ORC|NW|P1", "OBR|1|P1||X^Test^L", Self.display])
        #expect(Self.auspdiFindings(own).isEmpty, "\(Self.auspdiFindings(own).map(\.message))")
    }
}
