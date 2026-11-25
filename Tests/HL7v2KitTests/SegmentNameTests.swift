// SegmentNameTests.swift
// Every modelled segment carries the name its version prints (P01 R3).

import Testing
@testable import HL7v2Kit

@Suite("Segment names")
struct SegmentNameTests {
    @Test("Every generated grammar has a name that is not its ID", arguments: Version.allCases)
    func everySegmentIsNamed(_ version: Version) {
        for (segmentID, grammar) in SegmentGrammarTable.table(for: version) {
            #expect(!grammar.name.isEmpty, "\(version.rawValue) \(segmentID)")
            #expect(grammar.name != segmentID, "\(version.rawValue) \(segmentID)")
        }
    }

    static let printed: [(Version, String, String)] = [
        (.v2_5_1, "MSH", "Message Header"), (.v2_5_1, "PID", "Patient Identification"),
        (.v2_5_1, "PV1", "Patient Visit"), (.v2_5_1, "OBR", "Observation Request"),
        (.v2_5_1, "OBX", "Observation/Result"), (.v2_3, "PID", "Patient identification"),
        (.v2_4, "OM1", "General Segment"), (.v2_4, "RXA", "pharmacy/treatment administration"),
        (.v2_8_2, "UB1", "Uniform Billing 1"), (.v2_9_1, "GSP", "Person Gender and Sex"),
    ]

    @Test("Names match the print, across versions")
    func sampleNames() {
        for (version, segmentID, name) in Self.printed {
            #expect(SegmentGrammarTable.grammar(segmentID, version: version)?.name == name,
                    "\(version.rawValue) \(segmentID)")
        }
    }

    @Test("A grammar built with the older initialiser has an empty name")
    func callerBuiltGrammar() {
        #expect(SegmentGrammar(segmentID: "ZAU", version: "2.5.1", fields: []).name == "")
        #expect(SegmentGrammar(segmentID: "ZAU", name: "AU extension", version: "2.5.1", fields: []).name == "AU extension")
    }

    @Test("A grammar merged with a profile extension keeps its name")
    func mergedGrammarKeepsName() {
        let base = SegmentGrammar(segmentID: "ZAU", name: "AU extension", version: "2.5.1", fields: [])
        let added = FieldGrammar(index: 1, name: "Set ID", dataType: "SI", optionality: .optional, repeatability: .single)
        let merged = Validator().mergeGrammarExtension(base: base, profileExtension: [added])
        #expect(merged.fields == [added])
        #expect(merged.name == "AU extension")
    }
}
