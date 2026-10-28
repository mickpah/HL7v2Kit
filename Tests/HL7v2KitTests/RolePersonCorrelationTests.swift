// RolePersonCorrelationTests.swift
// ROL-4 task 1: "If this field is populated, then it must be populated with the same values as
// the correlated field" (CH15 sec 15.4.7.4, v2.6 to v2.8.2, v2.6 first), STF-2 (CX) and STF-3
// (XPN), a default warning: every component ROL-4 values, through a cited mapping, must equal one
// repetition of the correlated field.

import Testing
@testable import HL7v2Kit

@Suite("ROL-4 against STF-2 and STF-3")
struct RolePersonCorrelationTests {
    /// Components 1..n with only `values` set, joined with ^.
    static func composite(_ values: [Int: String]) -> String {
        (1...(values.keys.max() ?? 1)).map { values[$0] ?? "" }.joined(separator: "^")
    }

    static let stf2 = "1234^^^HOSP&1.2.3&ISO^EI"
    static let stf3 = "SMITH^JOHN^^^DR"
    static let rol4: [Int: String] = [1: "1234", 2: "SMITH", 3: "JOHN", 6: "DR", 9: "HOSP&1.2.3&ISO", 13: "EI"]

    static func pmu(_ stf2: String, _ stf3: String, _ rol4: String, version: String = "2.8.2") -> String {
        let event = version == "2.6" ? "B07" : "B01"
        let certificate = version == "2.6" ? "CER|1|C1\r" : ""
        return "MSH|^~\\&|HIS|FAC|HR|FAC|20240101120000||PMU^\(event)^PMU_\(event)|M1|P|\(version)\r"
            + "EVN|\(event)|20240101\rSTF|S1|\(stf2)|\(stf3)\r" + certificate + "ROL|1|AD|PP^Primary^HL70443|\(rol4)\r"
    }

    static func findings(_ wire: String, options: ValidationOptions = ValidationOptions()) throws -> [ValidationIssue] {
        Validator(options: options).validate(try Parser().parse(wire)).issues
            .filter { $0.code == .correlatedValueMismatch }
    }

    static let versions = ["2.6", "2.7.1", "2.8.2"]   // v2.6 first (owner decision R6)

    @Test("A ROL-4 with STF's values, from any repetitions, matches", arguments: versions)
    func matches(_ version: String) throws {
        #expect(try Self.findings(Self.pmu(Self.stf2, Self.stf3, Self.composite(Self.rol4), version: version)).isEmpty)
        let stf2 = "9999^^^OTHER&2.2&ISO^EI~" + Self.stf2, stf3 = Self.stf3 + "~JONES^MARY"
        #expect(try Self.findings(Self.pmu(stf2, stf3, Self.composite(Self.rol4), version: version)).isEmpty)
    }

    @Test("An assigning authority that differs is an identifier mismatch at ROL-4, a warning by default", arguments: versions)
    func identifierMismatch(_ version: String) throws {
        var rol4 = Self.rol4; rol4[9] = "HOSP&9.9.9&ISO"
        let found = try Self.findings(Self.pmu(Self.stf2, Self.stf3, Self.composite(rol4), version: version))
        #expect(found.map(\.location.pathDescription) == ["ROL[1]-4"], "\(version)")
        #expect(found.first?.severity == .warning)
        #expect(found.first?.message.contains("identifier") == true && found.first?.message.contains("ROL-4.9") == true
                && found.first?.message.contains("STF-2.4") == true)
    }

    @Test("A family surname that differs in one subcomponent is a name mismatch", arguments: versions)
    func nameMismatch(_ version: String) throws {
        var rol4 = Self.rol4; rol4[2] = "SMITH&VAN"
        let found = try Self.findings(Self.pmu(Self.stf2, Self.stf3, Self.composite(rol4), version: version))
        #expect(found.count == 1 && found.first?.message.contains("name") == true && found.first?.message.contains("STF-3.1") == true)
    }

    @Test("Nothing to compare: ROL-4 leaves a part empty, the STF field is empty, or there is no STF", arguments: versions)
    func notCompared(_ version: String) throws {
        let idOnly = Self.composite([1: "1234", 9: "HOSP&1.2.3&ISO", 13: "EI"])
        #expect(try Self.findings(Self.pmu(Self.stf2, Self.stf3, idOnly, version: version)).isEmpty)
        var rol4 = Self.rol4; rol4[2] = "OTHER"
        #expect(try Self.findings(Self.pmu(Self.stf2, "", Self.composite(rol4), version: version)).isEmpty)
        let noSTF = "MSH|^~\\&|HIS|FAC|HR|FAC|20240101120000||PMU^B01^PMU_B01|M1|P|\(version)\rEVN|B01|20240101\r"
            + "ROL|1|AD|PP^Primary^HL70443|\(Self.composite(rol4))\r"
        #expect(try Self.findings(noSTF).isEmpty)
    }

    @Test("Each ROL-4 repetition is judged on its own", arguments: versions)
    func repetitions(_ version: String) throws {
        var other = Self.rol4; other[1] = "5678"
        let found = try Self.findings(Self.pmu(Self.stf2, Self.stf3, Self.composite(Self.rol4) + "~" + Self.composite(other), version: version))
        #expect(found.count == 1 && found.first?.message.contains("repetition 2") == true)
    }

    @Test("v2.6 PMU_B07: each CERTIFICATE group's ROL is compared with the message's one STF")
    func certificates() throws {
        var other = Self.rol4; other[1] = "5678"
        let wire = "MSH|^~\\&|HIS|FAC|HR|FAC|20240101120000||PMU^B07^PMU_B07|M1|P|2.6\rEVN|B07|20240101\r"
            + "STF|S1|\(Self.stf2)|\(Self.stf3)\r"
            + "CER|1|C1\rROL|1|AD|PP^Primary^HL70443|\(Self.composite(Self.rol4))\r"
            + "CER|2|C2\rROL|2|AD|PP^Primary^HL70443|\(Self.composite(other))\r"
        let found = try Self.findings(wire)
        #expect(found.map(\.location.pathDescription) == ["ROL[2]-4"])
    }

    @Test("RSP_K25: each STAFF group's ROL is compared with its own STF")
    func staffGroups() throws {
        func rsp(_ first: String, _ second: String) -> String {
            "MSH|^~\\&|HIS|FAC|HR|FAC|20240101120000||RSP^K25^RSP_K25|M1|P|2.8.2\rMSA|AA|Q1\rQAK|Q1|OK\r"
                + "QPD|Q25^Personnel Information by Segment^HL70471|Q1\rRCP|I\r"
                + "STF|S1|\(Self.stf2)|\(Self.stf3)\rROL|1|AD|PP^Primary^HL70443|\(first)\r"
                + "STF|S2|5678^^^HOSP&1.2.3&ISO^EI|JONES^MARY\rROL|2|AD|PP^Primary^HL70443|\(second)\r"
        }
        let jones = Self.composite([1: "5678", 2: "JONES", 3: "MARY", 9: "HOSP&1.2.3&ISO", 13: "EI"])
        #expect(try Self.findings(rsp(Self.composite(Self.rol4), jones)).isEmpty)
        #expect(try Self.findings(rsp(jones, Self.composite(Self.rol4))).count == 4)
    }

    @Test("v2.5.1 and earlier carry no correlation")
    func earlierVersions() {
        #expect(SegmentGrammarTable.v2_5_1["ROL"]?.field(4)?.correlations.isEmpty == true)
        #expect(SegmentGrammarTable.v2_4["ROL"]?.field(4)?.correlations.isEmpty == true)
    }

    @Test("A warning in default and strict, nothing in lenient or when off, an error when set so")
    func presets() throws {
        var rol4 = Self.rol4; rol4[9] = "HOSP&9.9.9&ISO"
        let wire = Self.pmu(Self.stf2, Self.stf3, Self.composite(rol4), version: "2.6")
        #expect(ValidationOptions().correlationSeverity == .warning && ValidationOptions.strict.correlationSeverity == .warning)
        #expect(ValidationOptions.lenient.correlationSeverity == nil)
        #expect(try Self.findings(wire, options: .strict).map(\.severity) == [.warning])
        #expect(try Self.findings(wire, options: .lenient).isEmpty)
        var off = ValidationOptions(); off.correlationSeverity = nil
        #expect(try Self.findings(wire, options: off).isEmpty)
        var strict = ValidationOptions(); strict.correlationSeverity = .error
        #expect(try Self.findings(wire, options: strict).map(\.severity) == [.error])
    }

    static let identifier: [Int: Int] = [1: 1, 11: 2, 12: 3, 9: 4, 13: 5, 14: 6, 22: 9, 23: 10]
    static let name: [Int: Int] = [2: 1, 3: 2, 4: 3, 5: 4, 6: 5, 7: 6, 10: 7, 15: 8, 16: 9, 17: 10, 18: 11, 19: 12, 20: 13, 21: 14]

    @Test("ROL-4's correlations on v2.6, v2.7.1 and v2.8.2, and nowhere else")
    func coverage() {
        for (version, grammars) in [("2.6", SegmentGrammarTable.v2_6), ("2.7.1", SegmentGrammarTable.v2_7_1),
                                    ("2.8.2", SegmentGrammarTable.v2_8_2)] {
            let security: [Int: Int] = version == "2.6" ? [:] : [24: 11, 25: 12]
            #expect(grammars["ROL"]?.field(4)?.correlations == [
                FieldCorrelation(segment: "STF", field: 2, part: "identifier", components: Self.identifier.merging(security) { a, _ in a }),
                FieldCorrelation(segment: "STF", field: 3, part: "name", components: Self.name),
            ], "\(version)")
            let others = grammars.flatMap { id, g in g.fields.filter { !$0.correlations.isEmpty }.map { "\(id)-\($0.index)" } }
            #expect(others == ["ROL-4"], "\(version)")
        }
    }
}
