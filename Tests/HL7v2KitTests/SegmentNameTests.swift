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

    static let printed: [(String, String)] = [
        ("MSH", "Message Header"), ("PID", "Patient Identification"), ("PV1", "Patient Visit"),
        ("OBR", "Observation Request"), ("OBX", "Observation/Result"),
    ]

    @Test("Names match the v2.5.1 print (chapters 2, 3, 4 and 7)")
    func sampleNames() {
        for (segmentID, name) in Self.printed {
            #expect(SegmentGrammarTable.grammar(segmentID, version: .v2_5_1)?.name == name)
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
