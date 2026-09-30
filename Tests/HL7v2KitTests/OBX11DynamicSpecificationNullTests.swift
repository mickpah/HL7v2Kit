// OBX11DynamicSpecificationNullTests.swift
// P4-26 — base rule: OBX-11 = O means OBX-2 and OBX-5 are valued with null.
//
// HL7 v2.3.1 §7.3.2.11, and §7.4.2.11 in v2.4, v2.5.1, v2.6 and v2.8.2
// (OBX-11): "The status of O shall be used to indicate that the OBX segment
// is used for a dynamic specification of the required result. An OBX used for
// a dynamic specification must contain the detailed examination code, units,
// etc., with OBX-11 valued with O, and OBX-2 and OBX-5 valued with null."
// v2.3 prints neither the sentence nor an O row in Table 0085.
//
// The null is the explicit HL7 null `""` (Chapter 2 "Fields"). So the only
// conformant wire is OBX-2 = `""` and OBX-5 = `""`: any other value is
// prohibited, and an empty OBX-2 still misses the base OBX-2 condition
// `OBX-11 != X`, because `""` counts as populated for the required check.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Base OBX-11 = O dynamic-specification null rule (P4-26)")
struct OBX11DynamicSpecificationNullTests {

    static let printingVersions = ["2.3.1", "2.4", "2.5.1", "2.6", "2.8.2"]

    private static func wire(_ version: String, obx: String) -> String {
        TestWires.msh("ORU^R01", version)
            + "PID|1||123^^^HOSP^MR||DOE^JOHN\r"
            + "OBR|1|PLACER123^HOSP||GLU^Glucose^L\r"
            + obx + "\r"
    }

    private static func issues(_ version: String, obx: String) throws -> [ValidationIssue] {
        let message = try Parser().parse(wire(version, obx: obx))
        return Validator().validate(message).issues.filter { $0.location.segmentID == "OBX" }
    }

    private static func prohibited(_ issues: [ValidationIssue], field: Int) -> [ValidationIssue] {
        issues.filter { $0.code == .conditionalFieldProhibited && $0.location.fieldIndex == field }
    }

    @Test("OBX-2 and OBX-5 valued with the HL7 null under OBX-11 = O stay silent", arguments: printingVersions)
    func explicitNullIsSilent(version: String) throws {
        let issues = try Self.issues(version, obx: "OBX|1|\"\"|GLU-30^Glucose -30 min^L||\"\"|mmol/L|||||O")
        #expect(Self.prohibited(issues, field: 2).isEmpty, "got \(issues.map(\.message))")
        #expect(Self.prohibited(issues, field: 5).isEmpty, "got \(issues.map(\.message))")
        // `""` counts as populated for OBX-2's base condition `OBX-11 != X`.
        #expect(!issues.contains { $0.code == .conditionalFieldMissing && $0.location.fieldIndex == 2 },
                "got \(issues.map(\.message))")
    }

    @Test("OBX-5 = 5.2 under OBX-11 = O is prohibited as an error", arguments: printingVersions)
    func obx5ValueFires(version: String) throws {
        let issues = try Self.issues(version, obx: "OBX|1|\"\"|GLU-30^Glucose -30 min^L||5.2|mmol/L|||||O")
        let hits = Self.prohibited(issues, field: 5)
        #expect(hits.count == 1, "got \(issues.map(\.message))")
        #expect(hits.first?.severity == .error)
        #expect(Self.prohibited(issues, field: 2).isEmpty)
    }

    @Test("OBX-2 = NM under OBX-11 = O is prohibited as an error", arguments: printingVersions)
    func obx2ValueFires(version: String) throws {
        let issues = try Self.issues(version, obx: "OBX|1|NM|GLU-30^Glucose -30 min^L||\"\"|mmol/L|||||O")
        let hits = Self.prohibited(issues, field: 2)
        #expect(hits.count == 1, "got \(issues.map(\.message))")
        #expect(hits.first?.severity == .error)
        #expect(Self.prohibited(issues, field: 5).isEmpty)
    }

    @Test("A real value in any OBX-5 repetition beside a null is prohibited", arguments: printingVersions)
    func valueInLaterRepetitionFires(version: String) throws {
        let issues = try Self.issues(version, obx: "OBX|1|\"\"|GLU-30^Glucose -30 min^L||\"\"~5.2|mmol/L|||||O")
        #expect(Self.prohibited(issues, field: 5).count == 1, "got \(issues.map(\.message))")
    }

    @Test("OBX-2 and OBX-5 valued while OBX-11 = F stay silent", arguments: printingVersions)
    func finalStatusIsSilent(version: String) throws {
        let issues = try Self.issues(version, obx: "OBX|1|NM|GLU^Glucose^L||5.2|mmol/L|||||F")
        #expect(Self.prohibited(issues, field: 2).isEmpty, "got \(issues.map(\.message))")
        #expect(Self.prohibited(issues, field: 5).isEmpty, "got \(issues.map(\.message))")
    }

    @Test("An empty OBX-2 under OBX-11 = O misses the base OBX-2 condition", arguments: printingVersions)
    func emptyObx2IsMissing(version: String) throws {
        let issues = try Self.issues(version, obx: "OBX|1||GLU-30^Glucose -30 min^L||\"\"|mmol/L|||||O")
        #expect(issues.contains { $0.code == .conditionalFieldMissing && $0.location.fieldIndex == 2 },
                "got \(issues.map(\.message))")
    }

    @Test("An empty OBX-5 under OBX-11 = O misses the OBX-5 condition", arguments: printingVersions)
    func emptyObx5IsMissing(version: String) throws {
        let issues = try Self.issues(version, obx: "OBX|1|\"\"|GLU-30^Glucose -30 min^L|||mmol/L|||||O")
        #expect(issues.contains { $0.code == .conditionalFieldMissing && $0.location.fieldIndex == 5 },
                "got \(issues.map(\.message))")
    }

    @Test("An empty OBX-5 under OBX-11 = F is not required by the rule", arguments: printingVersions)
    func emptyObx5UnderFinalIsSilent(version: String) throws {
        let issues = try Self.issues(version, obx: "OBX|1|NM|GLU^Glucose^L|||mmol/L|||||F")
        #expect(!issues.contains { $0.code == .conditionalFieldMissing && $0.location.fieldIndex == 5 },
                "got \(issues.map(\.message))")
    }

    @Test("The rule is not scoped by message type: it fires on ADT^A01 and OML^O21", arguments: ["ADT^A01", "OML^O21"])
    func firesOutsideOrdersAndResults(messageType: String) throws {
        let wire = TestWires.msh(messageType, "2.5.1")
            + "PID|1||123^^^HOSP^MR||DOE^JOHN\r"
            + "OBX|1|NM|GLU-30^Glucose -30 min^L||5.2|mmol/L|||||O\r"
        let issues = try Validator().validate(Parser().parse(wire)).issues
        #expect(Self.prohibited(issues, field: 2).count == 1, "got \(issues.map(\.message))")
        #expect(Self.prohibited(issues, field: 5).count == 1, "got \(issues.map(\.message))")
    }

    @Test("v2.3 prints no O status and no dynamic-specification rule, so it stays silent")
    func v23IsSilent() throws {
        let issues = try Self.issues("2.3", obx: "OBX|1|NM|GLU-30^Glucose -30 min^L||5.2|mmol/L|||||O")
        #expect(Self.prohibited(issues, field: 2).isEmpty, "got \(issues.map(\.message))")
        #expect(Self.prohibited(issues, field: 5).isEmpty, "got \(issues.map(\.message))")
    }

    @Test("A permitsNull prohibition ignores a lone null; a plain prohibition still fires on it")
    func permitsNullIsPerRule() throws {
        let message = try Parser().parse(Self.wire("2.4", obx: "OBX|1|\"\"|GLU^Glucose^L||\"\"|mmol/L|||||O"))
        let index = try #require(message.segments.firstIndex { $0.segmentID == "OBX" })
        let grammar = FieldGrammar(index: 5, name: "Observation Value", dataType: "varies",
                                   optionality: .conditional, repeatability: .multiple,
                                   additionalProhibitions: [
                                       FieldProhibition(condition: "OBX-11 = O", severity: .error, permitsNull: true),
                                       FieldProhibition(condition: "OBX-11 = O", severity: .warning),
                                   ])
        var issues: [ValidationIssue] = []
        Validator().checkProhibition(grammar, segment: message.segments[index], segmentIndex: index,
                                     message: message, isPopulated: true, field: message.segments[index].field(5),
                                     location: IssueLocation(segmentID: "OBX", segmentIndex: index, fieldIndex: 5),
                                     issues: &issues)
        #expect(issues.map(\.severity) == [.warning])
    }
}
