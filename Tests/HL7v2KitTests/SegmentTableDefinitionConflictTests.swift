// SegmentTableDefinitionConflictTests.swift
// P4-30 — fields whose segment attribute table prints R while the field
// definition makes them conditional or nullable (Requirement 4).
//
// RXA-4: the table prints R in all six versions; the definition reads "If
// null, the date/time of RXA-3 ... is assumed". Chapter 2 defines the null
// value as the two double quotes `""`, distinct from an omitted field (v2.3
// sec 2.6; v2.6 / v2.8.2 sec 2.5.3 "Null ... |""|" against "Not populated
// ... empty, not present"), and v2.8.2 Chapter 2B adds "A required element
// can have a null value". So R stands: `""` satisfies it, an empty RXA-4
// does not.
//
// MFI-6: "Required for MFN-Master File Notification message" (all six), so
// it is C with `messageCode = MFN`. CSR-8: "This field is required for the
// patient registration trigger event (C01)" (all six), the sentence CSR-9
// and CSR-10 carry as C, so `triggerEvent = C01`. ROL-4 (v2.6, v2.8.2):
// "If both STF and ROL are present in the same message, populating this
// field is optional", so `STF absent`; v2.3 to v2.5.1 print no such
// sentence and keep R. Synthetic wires only.

import Testing
import Foundation
@testable import HL7v2Kit

private let allVersions = ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.8.2"]

private let grammarTables: [String: [String: SegmentGrammar]] = [
    "2.3": SegmentGrammarTable.v2_3, "2.3.1": SegmentGrammarTable.v2_3_1,
    "2.4": SegmentGrammarTable.v2_4, "2.5.1": SegmentGrammarTable.v2_5_1,
    "2.6": SegmentGrammarTable.v2_6, "2.8.2": SegmentGrammarTable.v2_8_2,
]

@Suite("Segment table R against a restricting field definition (P4-30)")
struct SegmentTableDefinitionConflictTests {

    private func issues(_ wire: String, _ seg: String, _ idx: Int) throws -> [ValidationIssue] {
        Validator().validate(try Parser().parse(wire)).issues.filter {
            $0.location.segmentID == seg && $0.location.fieldIndex == idx
                && ($0.code == .requiredFieldMissing || $0.code == .conditionalFieldMissing)
        }
    }

    // MARK: - RXA-4

    private func ras(_ version: String, rxa4: String) -> String {
        TestWires.wire("RAS^O17", version,
                       "PID|1||123^^^HOSP^MR||DOE^JOHN",
                       "ORC|RE|PLACER1",
                       "RXA|0|1|200612100615|\(rxa4)|0047-0402-30^Ampicillin 250 MG TAB^NDC|2|TAB")
    }

    @Test("RXA-4 valued with the HL7 null satisfies R", arguments: allVersions)
    func rxa4ExplicitNull(version: String) throws {
        #expect(try issues(ras(version, rxa4: "\"\""), "RXA", 4).isEmpty, "v\(version)")
    }

    @Test("An empty RXA-4 still misses R", arguments: allVersions)
    func rxa4EmptyFires(version: String) throws {
        let hits = try issues(ras(version, rxa4: ""), "RXA", 4)
        #expect(hits.count == 1, "v\(version)")
        #expect(hits.first?.code == .requiredFieldMissing, "v\(version)")
        #expect(grammarTables[version]?["RXA"]?.field(4)?.optionality == .required, "v\(version)")
    }

    // MARK: - MFI-6

    private let mfiNoLevel = "MFI|PRA^Practitioner^HL70175||UPD|||"

    @Test("MFI-6 is required on MFN", arguments: allVersions)
    func mfi6RequiredOnMFN(version: String) throws {
        let hits = try issues(TestWires.wire("MFN^M02", version, mfiNoLevel, "MFE|MAD|||KEY1"), "MFI", 6)
        #expect(hits.count == 1, "v\(version)")
        #expect(hits.first?.code == .conditionalFieldMissing, "v\(version)")
        #expect(try issues(TestWires.wire("MFN^M02", version, mfiNoLevel + "NE", "MFE|MAD|||KEY1"), "MFI", 6).isEmpty,
                "v\(version)")
    }

    @Test("An empty MFI-6 on MFK is compliant", arguments: allVersions)
    func mfi6SilentOnMFK(version: String) throws {
        let wire = TestWires.wire("MFK^M02", version, "MSA|AA|MSG1", mfiNoLevel)
        #expect(try issues(wire, "MFI", 6).isEmpty, "v\(version)")
    }

    // MARK: - CSR-8

    private func crm(_ version: String, _ event: String) -> String {
        TestWires.wire("CRM^\(event)", version,
                       "PID|1||123^^^HOSP^MR||DOE^JOHN",
                       TestWires.segment("CSR", [1: "STUDY1", 4: "P1", 6: "200601010800"]))
    }

    @Test("CSR-8 is required on the C01 registration event", arguments: allVersions)
    func csr8RequiredOnC01(version: String) throws {
        let hits = try issues(crm(version, "C01"), "CSR", 8)
        #expect(hits.count == 1, "v\(version)")
        #expect(hits.first?.code == .conditionalFieldMissing, "v\(version)")
    }

    @Test("An empty CSR-8 on another CRM event is compliant", arguments: allVersions)
    func csr8SilentOffC01(version: String) throws {
        #expect(try issues(crm(version, "C04"), "CSR", 8).isEmpty, "v\(version)")
    }

    // MARK: - ROL-4

    private let rolNoPerson = "ROL|R1^^^F|AD|AT^Attending^HL70443"

    // PMU events that carry both STF and ROL: v2.5.1 and v2.6 define ROL only in PMU^B07
    // (Grant Certificate/Permission); v2.8.2 adds it to PMU^B01.
    private static let staffWithRole = ["2.5.1": ("PMU^B07", "B07"), "2.6": ("PMU^B07", "B07"),
                                        "2.8.2": ("PMU^B01", "B01")]

    private func staffWire(_ version: String) -> String {
        let (type, event) = Self.staffWithRole[version] ?? ("PMU^B07", "B07")
        return TestWires.wire(type, version, "EVN|\(event)|200601010800", "STF|S1|S1^^^HOSP", rolNoPerson)
    }

    @Test("ROL-4 is optional beside STF and required without it", arguments: ["2.6", "2.8.2"])
    func rol4ConditionalOnSTF(version: String) throws {
        let withStaff = staffWire(version)
        #expect(try issues(withStaff, "ROL", 4).isEmpty, "v\(version)")
        let withoutStaff = TestWires.wire("ADT^A01", version, "EVN|A01|200601010800",
                                          "PID|1||123^^^HOSP^MR||DOE^JOHN", "PV1|1|I", rolNoPerson)
        let hits = try issues(withoutStaff, "ROL", 4)
        #expect(hits.count == 1, "v\(version)")
        #expect(hits.first?.code == .conditionalFieldMissing, "v\(version)")
    }

    @Test("ROL-4 stays R where the definition prints no STF sentence", arguments: ["2.3", "2.3.1", "2.4", "2.5.1"])
    func rol4RequiredBefore26(version: String) throws {
        let rol4 = grammarTables[version]?["ROL"]?.field(4)
        #expect(rol4?.optionality == .required, "v\(version)")
        #expect(rol4?.condition == nil, "v\(version)")
    }

    @Test("v2.5.1 PMU^B07 with STF still misses an empty ROL-4")
    func rol4RequiredBesideSTFOn251() throws {
        let hits = try issues(staffWire("2.5.1"), "ROL", 4)
        #expect(hits.count == 1)
        #expect(hits.first?.code == .requiredFieldMissing)
    }
}
