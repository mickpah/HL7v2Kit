// AuthenticationPersonTimeTests.swift
// TXA-22 tasks 2 and 3: the authentication person and its time stamp (PPN), both or neither,
// on every repetition. Newer wording (v2.5.1 to v2.8.2): Chapter 2A PPN.15 and Chapter 9 TXA-22,
// on PPN. Older wording (v2.3 to v2.4): Chapter 9 TXA-22 only.

import Testing
@testable import HL7v2Kit

@Suite("TXA-22 authentication person and time stamp")
struct AuthenticationPersonTimeTests {
    static let time = "20240101"

    /// The conditional-component findings on TXA-22 for one TXA-22 value.
    static func issues(_ txa22: String, version: String, options: ValidationOptions = ValidationOptions()) throws -> [ValidationIssue] {
        let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||MDM^T02^MDM_T02|M1|P|\(version)\r"
            + "EVN|T02|20240101\rPID|1||1^^^H^MR||DOE^J\rPV1|1|I\r"
            + "TXA|1|CN|TX" + String(repeating: "|", count: 19) + txa22 + "\r"
        return Validator(options: options).validate(try Parser().parse(wire)).issues
            .filter { $0.code == .conditionalComponentMissing && $0.location.segmentID == "TXA" && $0.location.fieldIndex == 22 }
    }

    static func paths(_ txa22: String, version: String) throws -> [String] {
        try issues(txa22, version: version).map(\.location.pathDescription)
    }

    /// One PPN repetition with only `values` set.
    static func ppn(_ values: [Int: String]) -> String {
        (1...(values.keys.max() ?? 1)).map { values[$0] ?? "" }.joined(separator: "^")
    }

    static let newer: [(Version, Int)] = [(.v2_5_1, 24), (.v2_6, 24), (.v2_7_1, 26), (.v2_8_2, 26)]

    @Test("v2.8.2: a person without a time stamp, or a time stamp without a person, is reported")
    func newerWording() throws {
        #expect(try Self.paths(Self.ppn([1: "1", 2: "DOE", 3: "J"]), version: "2.8.2") == ["TXA[1]-22.15"])
        #expect(try Self.paths(Self.ppn([15: Self.time]), version: "2.8.2") == ["TXA[1]-22"])
        #expect(try Self.paths(Self.ppn([1: "1", 2: "DOE", 15: Self.time]), version: "2.8.2").isEmpty)
        #expect(try Self.paths(Self.ppn([16: "A"]), version: "2.8.2") == ["TXA[1]-22.15"])
        #expect(try Self.paths(Self.ppn([1: "1", 15: "\"\""]), version: "2.8.2") == ["TXA[1]-22.15"])
    }

    @Test("Every repetition is checked; the group's message names the repetition")
    func repetitions() throws {
        let found = try Self.issues(Self.ppn([1: "1", 15: Self.time]) + "~" + Self.ppn([15: Self.time]), version: "2.8.2")
        #expect(found.map(\.location.pathDescription) == ["TXA[1]-22"])
        #expect(found.first?.message == "Conditional component group 'Performing person' (PPN 1-14, 16-26) in TXA[1]-22 repetition 2 is empty while its condition holds: 15 populated.")
        #expect(try Self.paths("~" + Self.ppn([1: "1"]), version: "2.8.2") == ["TXA[1]-22.15"])
    }

    @Test("Each newer version carries the rule over its own PPN",
          arguments: [("2.5.1", 24), ("2.6", 24), ("2.7.1", 26), ("2.8.2", 26)] as [(version: String, last: Int)])
    func newerVersions(_ row: (version: String, last: Int)) throws {
        #expect(try Self.paths(Self.ppn([row.last: "X"]), version: row.version) == ["TXA[1]-22.15"])
        #expect(try Self.paths(Self.ppn([15: Self.time]), version: row.version) == ["TXA[1]-22"])
    }

    @Test("Default tier: reported at requiredComponentSeverity wherever component grammar is checked (not .lenient)")
    func presets() throws {
        for options in [ValidationOptions(), .strict, .lenient] {
            let found = try Self.issues(Self.ppn([1: "1"]), version: "2.8.2", options: options)
            #expect(found.map(\.severity) == (options.checkComponentGrammar ? [options.requiredComponentSeverity] : []))
        }
    }

    @Test("PPN.15 is C with the cited condition, and the person group, on v2.5.1 to v2.8.2")
    func newerCoverage() {
        for (version, last) in Self.newer {
            let ppn = DataTypeGrammarTable.grammar("PPN", version: version)
            #expect(ppn?.component(15)?.optionalityCode == "C", "\(version)")
            #expect(ppn?.component(15)?.condition == "1-14 populated OR 16-\(last) populated", "\(version)")
            #expect(ppn?.groupRequirements == [ComponentGroupRequirement(name: "Performing person", components: "1-14,16-\(last)",
                                                                         condition: "15 populated")], "\(version)")
            #expect(ppn?.groupRequirements.first?.members == Array(1...14) + Array(16...last))
        }
    }

    @Test("No other grammar carries a group requirement")
    func onlyHere() {
        let expected: [Version: [String]] = [.v2_3: [], .v2_3_1: [], .v2_4: [],
                                             .v2_5_1: ["PPN"], .v2_6: ["PPN"], .v2_7_1: ["PPN"], .v2_8_2: ["PPN"]]
        for (version, carriers) in expected {
            let found = (DataTypeGrammarTable.grammars(for: version).merging(DataTypeGrammarTable.fieldGrammars(for: version)) { a, _ in a })
                .filter { !$0.value.groupRequirements.isEmpty }.keys.sorted()
            #expect(found == carriers, "\(version)")
        }
    }

    @Test("A group's member list reads ranges and single components; a malformed list never fires")
    func members() {
        #expect(ComponentGroupRequirement(name: "", components: "1-14,16", condition: "").members == Array(1...14) + [16])
        #expect(ComponentGroupRequirement(name: "", components: "1-,3", condition: "").members == nil)
        #expect(ComponentGroupRequirement(name: "", components: "", condition: "").members == nil)
    }
}
