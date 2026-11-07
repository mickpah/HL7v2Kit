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
// does not. v2.9 and v2.9.1 part from this, by the owner's ruling: CH02 prints
// "HL7 v2.x does not have an explicit concept for null values", so "If null"
// can only mean empty, and both model O, each citing its own print.
//
// MFI-6: "Required for MFN-Master File Notification message" (all six), so
// it is C with `messageCode = MFN`. CSR-8: "This field is required for the
// patient registration trigger event (C01)" (all six), the sentence CSR-9
// and CSR-10 carry as C, so `triggerEvent = C01`. ROL-4 (v2.6, v2.8.2):
// "If both STF and ROL are present in the same message, populating this
// field is optional", so `STF absent`; v2.3 to v2.5.1 print no such
// sentence and keep R.
//
// IPR-8 (v2.6 to v2.9.1, CH16 16.4.9.8): "Conditional, if Status = "Accepted",
// then Required, else Not Permitted". User-defined Table 0571 names no code
// Accepted. The adjudicated and paid codes (ADJ, ADJSUB, ADJZER, PAID) are
// Accepted on every reading the print supports, so they require IPR-8; REJECT
// is Accepted on none, so it prohibits IPR-8; ACK, PEND and PRED decide
// neither. DON-3 to DON-33 are in DonationConditionTests. Synthetic wires only.

import Testing
import Foundation
@testable import HL7v2Kit

private let allVersions = ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.7.1", "2.8.2"]

private let grammarTables: [String: [String: SegmentGrammar]] = [
    "2.3": SegmentGrammarTable.v2_3, "2.3.1": SegmentGrammarTable.v2_3_1,
    "2.4": SegmentGrammarTable.v2_4, "2.5.1": SegmentGrammarTable.v2_5_1,
    "2.6": SegmentGrammarTable.v2_6, "2.7.1": SegmentGrammarTable.v2_7_1,
    "2.8.2": SegmentGrammarTable.v2_8_2,
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

    /// `line` under `version`, every required-field finding at RXA.
    private func rxaRequired(_ version: String, _ line: String) throws -> [Int?] {
        let wire = TestWires.msh("RAS^O17^RAS_O17", version) + line + "\r"
        return Validator().validate(try Parser().parse(wire)).issues.filter {
            $0.code == .requiredFieldMissing && $0.location.segmentID == "RXA"
        }.map(\.location.fieldIndex)
    }

    /// The print's two lines that leave RXA-4 empty: CH04A p109 on v2.9, p111 on v2.9.1; CH12 p39 and p41, shifted one
    /// field left, so RXA-3 is empty too.
    @Test("An empty RXA-4 draws no finding on v2.9 and v2.9.1, RXA-3 still does, and v2.8.2 keeps its R",
          arguments: ["2.9", "2.9.1"])
    func rxa4OptionalFromV29(version: String) throws {
        let code = "0047-0402-30^Ampicillin 250 MG TAB^NDC|2|TAB"
        #expect(try rxaRequired(version, "RXA|1|1|200612100615||\(code)").isEmpty, "v\(version)")
        #expect(try rxaRequired(version, "RXA|1|1|||\(code)") == [3], "v\(version)")
        #expect(try rxaRequired(version, "RXA|1|199505011200|||\(code)") == [3], "v\(version)")
        #expect(try rxaRequired("2.8.2", "RXA|1|1|200612100615||\(code)") == [4])
    }

    @Test("v2.9 and v2.9.1 model RXA-4 O and RXA-3 R")
    func rxa4Grammar() {
        for table in [SegmentGrammarTable.v2_9, SegmentGrammarTable.v2_9_1] {
            #expect(table["RXA"]?.field(3)?.optionality == .required)
            #expect(table["RXA"]?.field(4)?.optionality == .optional)
        }
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

    @Test("ROL-4 is optional beside STF and required without it", arguments: ["2.6", "2.7.1", "2.8.2"])
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

    // MARK: - IPR-8

    /// Every finding at IPR-8 for an IPR whose status is `status` and whose checksum is `checksum`.
    private func ipr8(_ version: String, status: String, checksum: String) throws -> [IssueCode] {
        let ipr = TestWires.segment("IPR", [1: "IPR1", 2: "PRV1", 3: "PAY1", 4: status, 5: "20260101", 8: checksum])
        return Validator().validate(try Parser().parse(TestWires.wire("EHC^E10^EHC_E10", version, ipr))).issues
            .filter { $0.location.segmentID == "IPR" && $0.location.fieldIndex == 8 }.map(\.code)
    }

    @Test("An adjudicated or paid status requires IPR-8; ACK, PEND, PRED, REJECT and no status do not",
          arguments: ["2.6", "2.7.1", "2.8.2", "2.9", "2.9.1"])
    func ipr8RequiredWhenAdjudicated(version: String) throws {
        let release = try #require(Version(rawValue: version))
        let codes = try #require(HL7TableRegistry.table("0571", version: release)).codes
        #expect(Set(codes) == ["ACK", "REJECT", "PEND", "ADJZER", "ADJSUB", "ADJ", "PAID", "PRED"], "v\(version)")
        for code in ["ADJ", "ADJSUB", "ADJZER", "PAID"] {
            #expect(try ipr8(version, status: "\(code)^^HL70571", checksum: "") == [.conditionalFieldMissing],
                    "v\(version) \(code)")
        }
        for code in ["ACK", "PEND", "PRED", "REJECT", ""] {
            #expect(try ipr8(version, status: code.isEmpty ? "" : "\(code)^^HL70571", checksum: "").isEmpty,
                    "v\(version) \(code)")
        }
    }

    @Test("IPR-8 is not permitted with REJECT, and draws nothing beside any other status",
          arguments: ["2.6", "2.7.1", "2.8.2", "2.9", "2.9.1"])
    func ipr8ProhibitedWithReject(version: String) throws {
        #expect(try ipr8(version, status: "REJECT^Reject^HL70571", checksum: "CHK1") == [.conditionalFieldProhibited],
                "v\(version)")
        for code in ["ACK", "PEND", "ADJZER", "ADJSUB", "ADJ", "PAID", "PRED", ""] {
            #expect(try ipr8(version, status: code.isEmpty ? "" : "\(code)^^HL70571", checksum: "CHK1").isEmpty,
                    "v\(version) \(code)")
        }
    }
}
