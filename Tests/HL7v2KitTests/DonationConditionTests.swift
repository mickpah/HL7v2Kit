// DonationConditionTests.swift
// DON-3 to DON-33, less DON-9 to DON-11, on v2.8.2, v2.9 and v2.9.1 (CH04 4.17.1). The attribute table prints
// them R, while DON-1 and DON-2 read "mandatory except when using an eligibility message type in which only DON-9,
// DON-10, and DON-11 are populated", so they are required on a DPR alone. Within a DPR, 19 definitions apply only
// when a fact holds, and each is required only where another field shows it:
// - DON-3 to DON-6, DON-8 and DON-22, the phlebotomy itself: when DON-12 is NIN or ABR (Table 0923: not
//   interrupted, or interrupted after the needle went in) or DON-21 is SUC or UL5 (Table 0926: drawn).
// - DON-23 and DON-24, who starts and ends "the blood flow into the container": when DON-21 is SUC or UL5.
// - DON-13, the interruption reason: when DON-12 is WOT or ABR, Table 0923's two "Process interrupted" codes.
// - DON-14, "a problem or issue with the phlebotomy itself": when DON-13 is DNI, "Phlebotomy Issue".
// - DON-16 to DON-20, "If this donation has an intended recipient (autologous, directed, dedicated, designated)":
//   when DON-15 is Y, or another of DON-16 to DON-20 carries a value.
// - DON-15 names only a directed, dedicated or designated recipient, which no printed field shows, so it is never
//   required.
// - DON-25 and DON-26, "if used": when DON-8 includes THA (Therapeutic Apheresis), DON-13 is ASC (Apheresis
//   Software Crash), or the other of the two carries a value.
// - DON-31, the identifier of "the sample collected": when DON-30, the number of tubes collected, is above 0.
// Synthetic wires only.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("DON fields follow their definitions")
struct DonationConditionTests {
    private static let versions = ["2.8.2", "2.9", "2.9.1"]
    private static let dpr = "DPR^O48^DPR_O48"
    /// The 28 printed R, and the 19 of them that a DPR requires only when another field shows their condition.
    private static let donationFields = Array(3...8) + Array(12...33)
    private static let factFields = [3, 4, 5, 6, 8, 13, 14, 15, 16, 17, 18, 19, 20, 22, 23, 24, 25, 26, 31]
    private static let recipient = [16: "DOE^JANE", 17: "19800101", 18: "FAC", 19: "20261201", 20: "SMITH^JOHN"]
    private static let phlebotomy: Set = [3, 4, 5, 6, 8, 22]
    private static let bloodFlow: Set = [23, 24]

    /// Every missing-field finding on DON, by field, for a DON carrying DON-9 to DON-11 and `extra`.
    private func missing(_ type: String, _ version: String, _ extra: [Int: String] = [:]) throws -> [Int: [IssueCode]] {
        let fields = [9: "Y", 10: "DPR^^HL70933", 11: "20260101"].merging(extra) { _, new in new }
        let wire = TestWires.wire(type, version, TestWires.segment("DON", fields))
        let found = Validator().validate(try Parser().parse(wire)).issues.filter {
            $0.location.segmentID == "DON" && ($0.code == .requiredFieldMissing || $0.code == .conditionalFieldMissing)
        }
        let pairs = found.compactMap { issue in issue.location.fieldIndex.map { ($0, [issue.code]) } }
        return Dictionary(pairs, uniquingKeysWith: +)
    }

    @Test("A DPR with DON-9 to DON-11 alone misses the nine fields a walk-out can still fill, conditional on DPR",
          arguments: versions)
    func donationFieldsRequiredOnDPR(version: String) throws {
        let always = Self.donationFields.filter { !Self.factFields.contains($0) }
        #expect(always == [7, 12, 21, 27, 28, 29, 30, 32, 33])
        let positions = always + (version == "2.8.2" ? [] : [1, 2])
        let expected = Dictionary(uniqueKeysWithValues: positions.map { ($0, [IssueCode.conditionalFieldMissing]) })
        #expect(try missing(Self.dpr, version) == expected, "v\(version)")
    }

    @Test("An eligibility DON with DON-9 to DON-11 alone draws no missing field outside DPR",
          arguments: versions, ["DEL^O46^DEL_O46", "RSP^K34^RSP_O34"])
    func eligibilityDONIsCompliant(version: String, type: String) throws {
        #expect(try missing(type, version).isEmpty, "v\(version) \(type)")
        let facts = [8: "THA^^HL70933", 12: "ABR^^HL70923", 13: "DNI^^HL70935", 15: "Y", 21: "SUC^^HL70926", 30: "2"]
        #expect(try missing(type, version, facts).isEmpty, "v\(version) \(type) with every fact shown")
    }

    /// The fact fields that draw `conditionalFieldMissing` on a DPR carrying `extra`.
    private func factsMissed(_ version: String, _ extra: [Int: String]) throws -> Set<Int> {
        let hits = try missing(Self.dpr, version, extra)
        for field in Self.factFields {
            #expect((hits[field] ?? [.conditionalFieldMissing]) == [.conditionalFieldMissing], "DON-\(field)")
        }
        return Set(Self.factFields.filter { hits[$0] != nil })
    }

    @Test("The phlebotomy fields need the needle in; the blood-flow fields need blood drawn", arguments: versions)
    func phlebotomyAndBloodFlow(version: String) throws {
        let both = Self.phlebotomy.union(Self.bloodFlow)
        #expect(try factsMissed(version, [12: "NIN^^HL70923"]) == Self.phlebotomy, "v\(version) NIN")
        #expect(try factsMissed(version, [12: "ABR^^HL70923"]) == Self.phlebotomy.union([13]), "v\(version) ABR")
        #expect(try factsMissed(version, [12: "WOT^^HL70923"]) == [13], "v\(version) WOT, a walk-out")
        #expect(try factsMissed(version, [12: "ZZZ^^L"]).isEmpty, "v\(version) a site code")
        #expect(try factsMissed(version, [21: "SUC^^HL70926"]) == both, "v\(version) SUC")
        #expect(try factsMissed(version, [21: "UL5^^HL70926"]) == both, "v\(version) UL5")
        #expect(try factsMissed(version, [21: "NDR^^HL70926"]).isEmpty, "v\(version) NDR")
        #expect(try factsMissed(version, [12: "WOT^^HL70923", 21: "NDR^^HL70926", 30: "0"]) == [13],
                "v\(version) a walk-out filled truthfully")
    }

    @Test("DON-13 is required when DON-12 reports an interruption, DON-14 when DON-13 reports a phlebotomy issue",
          arguments: versions)
    func interruptionReasonAndIssue(version: String) throws {
        #expect(try factsMissed(version, [12: "ABR^^HL70923"]).contains(13), "v\(version) ABR")
        #expect(try factsMissed(version, [12: "WOT^^HL70923"]).contains(13), "v\(version) WOT")
        #expect(try !factsMissed(version, [12: "NIN^^HL70923"]).contains(13), "v\(version) NIN")
        #expect(try !factsMissed(version, [:]).contains(13), "v\(version) empty")
        #expect(try factsMissed(version, [13: "DNI^^HL70935"]) == [14], "v\(version) DNI")
        #expect(try factsMissed(version, [13: "NRG^^HL70935"]).isEmpty, "v\(version) NRG")
    }

    @Test("DON-16 to DON-20 are required once the donation shows an intended recipient; DON-15 never is",
          arguments: versions)
    func intendedRecipient(version: String) throws {
        let all: Set = [16, 17, 18, 19, 20]
        #expect(try factsMissed(version, [15: "Y"]) == all, "v\(version) DON-15 Y")
        #expect(try factsMissed(version, [15: "N"]).isEmpty, "v\(version) DON-15 N")
        for (field, value) in Self.recipient {
            #expect(try factsMissed(version, [field: value]) == all.subtracting([field]), "v\(version) DON-\(field)")
            #expect(try factsMissed(version, [field: "\"\""]).isEmpty, "v\(version) DON-\(field) null")
        }
        #expect(try factsMissed(version, Self.recipient).isEmpty, "v\(version) every recipient field, DON-15 empty")
    }

    @Test("DON-25 and DON-26 are required once the donation shows an aphaeresis machine", arguments: versions)
    func aphaeresisMachine(version: String) throws {
        let both: Set = [25, 26]
        #expect(try factsMissed(version, [8: "THA^^HL70933"]) == both, "v\(version) THA")
        #expect(try factsMissed(version, [8: "WBL^^HL70933~THA^^HL70933"]) == both, "v\(version) WBL~THA")
        #expect(try factsMissed(version, [8: "WBL^^HL70933"]).isEmpty, "v\(version) WBL")
        #expect(try factsMissed(version, [13: "ASC^^HL70935"]) == both, "v\(version) ASC")
        #expect(try factsMissed(version, [25: "Trima"]) == [26], "v\(version) DON-25")
        #expect(try factsMissed(version, [26: "SN1"]) == [25], "v\(version) DON-26")
        #expect(try factsMissed(version, [25: "\"\""]).isEmpty, "v\(version) DON-25 null")
        #expect(try factsMissed(version, [26: "\"\""]).isEmpty, "v\(version) DON-26 null")
    }

    @Test("DON-31 is required when DON-30 counts a tube collected", arguments: versions)
    func sampleIdentifier(version: String) throws {
        #expect(try factsMissed(version, [30: "2"]) == [31], "v\(version) two tubes")
        #expect(try factsMissed(version, [30: "0"]).isEmpty, "v\(version) none")
    }
}
