// TranscriptionOBRProhibitionTests.swift
// ROL-4 sprint task 2: v2.8.2 CH09 TXA-22 and TXA-11 "Condition" paragraphs: "If TXA-22 [TXA-11]
// is valued and the corresponding OBR segment is present in the message OBR-32 [OBR-35] must be
// blank". A warning: the print tells receivers to ignore the OBR field (owner decision R3, R5).

import Testing
@testable import HL7v2Kit

@Suite("OBR-32 and OBR-35 when TXA-22 or TXA-11 is valued")
struct TranscriptionOBRProhibitionTests {
    static func fields(_ id: String, _ values: [Int: String]) -> String {
        id + "|" + (1...(values.keys.max() ?? 1)).map { values[$0] ?? "" }.joined(separator: "|")
    }

    static func prohibited(obr: [Int: String], txa: [Int: String], version: String = "2.8.2") throws -> [ValidationIssue] {
        let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||MDM^T02^MDM_T02|M1|P|\(version)\r"
            + "EVN|T02|20240101\rPID|1||1^^^H^MR||DOE^J\rPV1|1|I\rORC|RE\r"
            + fields("OBR", obr.merging([1: "1"]) { a, _ in a }) + "\r"
            + fields("TXA", txa.merging([1: "1", 2: "CN", 3: "TX"]) { a, _ in a }) + "\rOBX|1|TX|1^Note||text\r"
        return Validator().validate(try Parser().parse(wire)).issues
            .filter { $0.code == .conditionalFieldProhibited && $0.location.segmentID == "OBR"
                      && [32, 35].contains($0.location.fieldIndex ?? 0) }
    }

    static let person = "1^DOE^J^^^^^^^^^^^^20240101"

    @Test("v2.8.2: OBR-32 with TXA-22 valued, and OBR-35 with TXA-11 valued, are warnings")
    func prohibited() throws {
        let p32 = try Self.prohibited(obr: [32: "1^DOE"], txa: [22: Self.person])
        #expect(p32.map(\.location.pathDescription) == ["OBR[1]-32"] && p32.first?.severity == .warning)
        let p35 = try Self.prohibited(obr: [35: "1^DOE"], txa: [11: "1^DOE^J"])
        #expect(p35.map(\.location.pathDescription) == ["OBR[1]-35"] && p35.first?.severity == .warning)
    }

    @Test("Nothing when the TXA field is empty, or on v2.7.1")
    func notProhibited() throws {
        #expect(try Self.prohibited(obr: [32: "1^DOE", 35: "1^DOE"], txa: [:]).isEmpty)
        #expect(try Self.prohibited(obr: [32: "1^DOE", 35: "1^DOE"], txa: [11: "1^DOE^J", 22: Self.person], version: "2.7.1").isEmpty)
    }

    @Test("The two rules are v2.8.2 data")
    func coverage() {
        #expect(SegmentGrammarTable.v2_8_2["OBR"]?.field(32)?.prohibitedWhen == "TXA-22 populated")
        #expect(SegmentGrammarTable.v2_8_2["OBR"]?.field(35)?.prohibitedWhen == "TXA-11 populated")
        #expect(SegmentGrammarTable.v2_8_2["OBR"]?.field(32)?.prohibitedSeverity == .warning)
        #expect(SegmentGrammarTable.v2_7_1["OBR"]?.field(32)?.prohibitedWhen == nil)
    }
}
