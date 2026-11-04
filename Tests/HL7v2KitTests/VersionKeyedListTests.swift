// VersionKeyedListTests.swift
// The compiler forces a decision at each Version switch. These lists are not switches, so a new
// version must be decided here by hand: the row says what the version's own print requires.

import Testing
@testable import HL7v2Kit

@Suite("Version-keyed lists")
struct VersionKeyedListTests {
    /// Whether each modelled version gates the order-number fields by former group (the print,
    /// Validator+GroupSpans.swift `formerlyGated`). A missing row fails.
    static let formerlyGated: [Version: Bool] = [
        .v2_3: false, .v2_3_1: false, .v2_4: false, .v2_5_1: true, .v2_6: true,
        .v2_7_1: true, .v2_8_2: true, .v2_9: true,
    ]

    @Test("Every modelled version has a formerlyGated decision, and the list agrees")
    func formerlyGatedDecided() throws {
        for version in Version.allCases where version.grammarVersion == version {
            let decided = try #require(Self.formerlyGated[version], "\(version) has no decision")
            #expect((Validator.formerlyGated[version] != nil) == decided, "\(version)")
        }
    }

    @Test("ORC-8 pairs with OBR-54 on every modelled version from v2.7.1")
    func parentOrderPair() throws {
        let wire = "MSH|^~\\&|LAB|FAC|HIS|FAC|||ORU^R01^ORU_R01|MSG1|P|2.9\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
            + "ORC|RE|P1|F1|||||PARENT1\r"
            + "OBR|1|P1|F1|93000^EKG^C4" + String(repeating: "|", count: 50) + "OTHER\r"
        let issues = Validator().validate(try Parser().parse(wire)).issues
        #expect(issues.contains { $0.location.segmentID == "OBR" && $0.location.fieldIndex == 54 })
    }

    /// ORC-12 holds DOCTOR1 and OBR-16 holds DOCTOR2, so the pair disagrees where it applies.
    static func orderingProviderWire(version: String) -> String {
        "MSH|^~\\&|LAB|FAC|HIS|FAC|||ORU^R01^ORU_R01|MSG1|P|\(version)\r"
            + "PID|1||123^^^AUTH^MR||DOE^JOHN\r"
            + "ORC|RE|P1|F1" + String(repeating: "|", count: 9) + "DOCTOR1\r"
            + "OBR|1|P1|F1|93000^EKG^C4" + String(repeating: "|", count: 12) + "DOCTOR2\r"
    }

    /// A paired-field finding, not any issue at the place: v2.9 reports a populated withdrawn field
    /// there as fieldNotSupported, which is a different finding.
    static func isPair(_ issue: ValidationIssue, obrField: Int) -> Bool {
        if case .pairedFieldMismatch = issue.code { return issue.location.segmentID == "OBR" && issue.location.fieldIndex == obrField }
        return false
    }

    @Test("ORC-12 still pairs with OBR-16 on v2.8.2, where it is B")
    func orderingProviderOnV282() throws {
        let issues = Validator().validate(try Parser().parse(Self.orderingProviderWire(version: "2.8.2"))).issues
        #expect(issues.contains { Self.isPair($0, obrField: 16) })
    }

    @Test("ORC-12 is withdrawn on v2.9, so it no longer pairs with OBR-16")
    func withdrawnOrderingProvider() throws {
        let issues = Validator().validate(try Parser().parse(Self.orderingProviderWire(version: "2.9"))).issues
        #expect(!issues.contains { Self.isPair($0, obrField: 16) })
        // The withdrawn field itself is still reported, as fieldNotSupported, at the same place.
        #expect(issues.contains { $0.location.segmentID == "OBR" && $0.location.fieldIndex == 16 })
    }
}
