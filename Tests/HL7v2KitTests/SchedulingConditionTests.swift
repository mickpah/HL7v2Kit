// SchedulingConditionTests.swift
// P4: scheduling (SCH / ARQ / AIS / AIG / AIL / AIP / RGS) conditionals
// moved out of the permanent-limitations register. Synthetic wires only.

import Testing
import Foundation
@testable import HL7v2Kit

private let schedulingVersions = ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.8.2"]

/// Field indexes per appointment-information segment.
struct ResourceSlots: Sendable, CustomStringConvertible {
    let id: String
    let start: Int
    let offset: Int
    let units: Int
    let substitution: Int
    let fillerStatus: Int
    var description: String { id }
}

private let resourceSegments = [
    ResourceSlots(id: "AIS", start: 4, offset: 5, units: 6, substitution: 9, fillerStatus: 10),
    ResourceSlots(id: "AIG", start: 8, offset: 9, units: 10, substitution: 13, fillerStatus: 14),
    ResourceSlots(id: "AIL", start: 6, offset: 7, units: 8, substitution: 11, fillerStatus: 12),
    ResourceSlots(id: "AIP", start: 6, offset: 7, units: 8, substitution: 11, fillerStatus: 12),
]

/// Versions whose Chapter 10 defines SQR^S25 carrying the AIx segments
/// (v2.3 to v2.6; the query is withdrawn as of v2.7, v2.8.2 §10.5.3).
private let sqrVersions: Set<String> = ["2.3", "2.3.1", "2.4", "2.5.1", "2.6"]

@Suite("Scheduling conditions (P4)")
struct SchedulingConditionTests {

    private func missing(_ wire: String, _ seg: String, _ idx: Int) throws -> [ValidationIssue] {
        Validator().validate(try Parser().parse(wire)).errors.filter {
            $0.code == .conditionalFieldMissing
                && $0.location.segmentID == seg && $0.location.fieldIndex == idx
        }
    }

    // MARK: - SCH / ARQ identifiers (V251-C03)

    @Test("SCH-1 / SCH-2: the placer or the filler appointment ID", arguments: ["2.3.1", "2.4", "2.5.1", "2.6", "2.8.2"])
    func schAppointmentIDs(version: String) throws {
        let neither = TestWires.wire("SIU^S12", version, TestWires.segment("SCH", [5: "SCHED1"]))
        #expect(try missing(neither, "SCH", 1).count == 1, "v\(version)")
        #expect(try missing(neither, "SCH", 2).count == 1, "v\(version)")
        let placer = TestWires.wire("SIU^S12", version, TestWires.segment("SCH", [1: "PL1", 5: "SCHED1"]))
        #expect(try missing(placer, "SCH", 1).isEmpty, "v\(version)")
        #expect(try missing(placer, "SCH", 2).isEmpty, "v\(version)")
    }

    @Test("SCH-27 / ARQ-25: the filler order number when the placer order number is present",
          arguments: ["2.4", "2.5.1", "2.6", "2.8.2"])
    func fillerOrderNumbers(version: String) throws {
        let sch = TestWires.wire("SIU^S12", version, TestWires.segment("SCH", [1: "PL1", 26: "PON1"]))
        #expect(try missing(sch, "SCH", 27).count == 1, "v\(version)")
        let schNone = TestWires.wire("SIU^S12", version, TestWires.segment("SCH", [1: "PL1"]))
        #expect(try missing(schNone, "SCH", 27).isEmpty, "v\(version)")
        let arq = TestWires.wire("SRM^S01", version, TestWires.segment("ARQ", [1: "PL1", 24: "PON1"]))
        #expect(try missing(arq, "ARQ", 25).count == 1, "v\(version)")
        let arqNone = TestWires.wire("SRM^S01", version, TestWires.segment("ARQ", [1: "PL1"]))
        #expect(try missing(arqNone, "ARQ", 25).isEmpty, "v\(version)")
    }

    // MARK: - AIS / AIG / AIL / AIP (V251-C04)

    private func resource(_ version: String, _ messageType: String, _ slots: ResourceSlots,
                          _ fields: [Int: String]) -> String {
        TestWires.wire(messageType, version,
                       TestWires.segment("SCH", [1: "PL1", 2: "FL1"]),
                       TestWires.segment(slots.id, fields.merging([1: "1", 3: "RES1"]) { current, _ in current }))
    }

    @Test("Start date/time without an offset; offset units with one",
          arguments: resourceSegments, schedulingVersions)
    func startAndOffset(slots: ResourceSlots, version: String) throws {
        let noOffset = resource(version, "SIU^S12", slots, [:])
        #expect(try missing(noOffset, slots.id, slots.start).count == 1, "\(slots.id) v\(version)")
        #expect(try missing(noOffset, slots.id, slots.units).isEmpty, "\(slots.id) v\(version)")
        let withOffset = resource(version, "SIU^S12", slots, [slots.offset: "30"])
        #expect(try missing(withOffset, slots.id, slots.start).isEmpty, "\(slots.id) v\(version)")
        #expect(try missing(withOffset, slots.id, slots.units).count == 1, "\(slots.id) v\(version)")
    }

    // AIG-9 / AIL-7 / AIP-7 state the converse rule ("If a value for AIG-8-Start
    // date/time is not provided, then a value is required for this field"). AIS-5
    // instead repeats its own name ("If a value for AIS-5 ... is not provided"), so
    // it stays bare.
    @Test("Start date/time offset without a start date/time (AIG / AIL / AIP)",
          arguments: resourceSegments, schedulingVersions)
    func offsetWithoutStart(slots: ResourceSlots, version: String) throws {
        let neither = resource(version, "SIU^S12", slots, [:])
        let expected = slots.id == "AIS" ? 0 : 1
        #expect(try missing(neither, slots.id, slots.offset).count == expected, "\(slots.id) v\(version)")
        let withStart = resource(version, "SIU^S12", slots, [slots.start: "20260101090000"])
        #expect(try missing(withStart, slots.id, slots.offset).isEmpty, "\(slots.id) v\(version)")
        #expect(try missing(withStart, slots.id, slots.start).isEmpty, "\(slots.id) v\(version)")
        #expect(try missing(withStart, slots.id, slots.units).isEmpty, "\(slots.id) v\(version)")
    }

    @Test("Allow substitution on requests; filler status on filler messages",
          arguments: resourceSegments, schedulingVersions)
    func requestAndFiller(slots: ResourceSlots, version: String) throws {
        let request = resource(version, "SRM^S01", slots, [:])
        #expect(try missing(request, slots.id, slots.substitution).count == 1, "\(slots.id) v\(version)")
        #expect(try missing(request, slots.id, slots.fillerStatus).isEmpty, "\(slots.id) v\(version)")
        let notification = resource(version, "SIU^S12", slots, [:])
        #expect(try missing(notification, slots.id, slots.substitution).isEmpty, "\(slots.id) v\(version)")
        #expect(try missing(notification, slots.id, slots.fillerStatus).count == 1, "\(slots.id) v\(version)")
        let response = resource(version, "SRR^S01", slots, [:])
        #expect(try missing(response, slots.id, slots.fillerStatus).count == 1, "\(slots.id) v\(version)")
        let query = resource(version, "SQR^S25", slots, [:])
        let expected = sqrVersions.contains(version) ? 1 : 0
        #expect(try missing(query, slots.id, slots.fillerStatus).count == expected, "\(slots.id) v\(version)")
        #expect(try missing(query, slots.id, slots.substitution).isEmpty, "\(slots.id) v\(version)")
    }

    // P4-12 minor 5: the SQM query side of the S25 pair ("This field is optional
    // for all transactions originating from placer, querying and auxiliary
    // applications"; substitution: "optional ... for all query messages").
    // Only defined alongside SQR, v2.3 to v2.6 (withdrawn as of v2.7).
    @Test("Allow substitution and filler status stay silent on the SQM query",
          arguments: resourceSegments, sqrVersions)
    func substitutionAndFillerStatusSilentOnQuery(slots: ResourceSlots, version: String) throws {
        let query = resource(version, "SQM^S25", slots, [:])
        #expect(try missing(query, slots.id, slots.substitution).isEmpty, "\(slots.id) v\(version)")
        #expect(try missing(query, slots.id, slots.fillerStatus).isEmpty, "\(slots.id) v\(version)")
    }

    // P4-12 minor 5: a wire that values start, offset and units together stays
    // silent on all three (each rule is satisfied, not merely inapplicable).
    @Test("Start date/time, offset and units populated together: silent on all three",
          arguments: resourceSegments, schedulingVersions)
    func startOffsetUnitsPopulatedTogether(slots: ResourceSlots, version: String) throws {
        let wire = resource(version, "SIU^S12", slots,
                             [slots.start: "20260101090000", slots.offset: "30", slots.units: "min"])
        #expect(try missing(wire, slots.id, slots.start).isEmpty, "\(slots.id) v\(version)")
        #expect(try missing(wire, slots.id, slots.offset).isEmpty, "\(slots.id) v\(version)")
        #expect(try missing(wire, slots.id, slots.units).isEmpty, "\(slots.id) v\(version)")
    }

    private func prohibited(_ wire: String, _ seg: String, _ idx: Int) throws -> [ValidationIssue] {
        Validator().validate(try Parser().parse(wire)).issues.filter {
            $0.code == .conditionalFieldProhibited
                && $0.location.segmentID == seg && $0.location.fieldIndex == idx
        }
    }

    // Findings closed: AIS/AIG/AIL/AIP filler status "It is recommended that this
    // field be left unvalued in transactions originating from applications other
    // than the filler application"; AIP-12 additionally "It should not be valued
    // in any request transactions from the placer application to the filler
    // application" (identical text in all six versions). Ships as a warning on the
    // request message type (SRM); the P4-12 condition axis already covers the
    // filler-originated required half.
    @Test("Filler status code should not be valued on a request (warning)",
          arguments: resourceSegments, schedulingVersions)
    func fillerStatusProhibitedOnRequest(slots: ResourceSlots, version: String) throws {
        let requestValued = resource(version, "SRM^S01", slots, [slots.fillerStatus: "Booked"])
        let fires = try prohibited(requestValued, slots.id, slots.fillerStatus)
        #expect(fires.count == 1, "\(slots.id) v\(version)")
        #expect(fires.first?.severity == .warning, "\(slots.id) v\(version)")
        let requestEmpty = resource(version, "SRM^S01", slots, [:])
        #expect(try prohibited(requestEmpty, slots.id, slots.fillerStatus).isEmpty, "\(slots.id) v\(version)")
        let notification = resource(version, "SIU^S12", slots, [slots.fillerStatus: "Booked"])
        #expect(try prohibited(notification, slots.id, slots.fillerStatus).isEmpty, "\(slots.id) v\(version)")
        let response = resource(version, "SRR^S01", slots, [slots.fillerStatus: "Booked"])
        #expect(try prohibited(response, slots.id, slots.fillerStatus).isEmpty, "\(slots.id) v\(version)")
    }

    // Folded intake (P4 hand-off): "This field is required for all unsolicited
    // transactions from the filler application" (AIG-3 / AIL-3 / AIP-3, all six
    // versions). The new-request clause depends on what the placer asks for.
    @Test("Resource identifier on unsolicited filler transactions",
          arguments: ["AIG", "AIL", "AIP"], schedulingVersions)
    func resourceIdentifier(id: String, version: String) throws {
        func wire(_ messageType: String, _ resource: String) -> String {
            TestWires.wire(messageType, version, TestWires.segment("SCH", [1: "PL1", 2: "FL1"]),
                           TestWires.segment(id, [1: "1", 3: resource, 4: "TYPE1"]))
        }
        #expect(try missing(wire("SIU^S12", ""), id, 3).count == 1, "\(id) v\(version)")
        #expect(try missing(wire("SIU^S12", "RES1"), id, 3).isEmpty, "\(id) v\(version)")
        #expect(try missing(wire("SRM^S01", ""), id, 3).isEmpty, "\(id) v\(version)")
    }

    // v2.5.1 onward print AIL-4 / AIP-4 as C: "For all messages, this field is
    // conditionally required if a specific location is not identified in AIL-3"
    // (AIP-4 reads the same against AIP-3). Earlier versions print them R.
    @Test("Location / personnel type when no specific resource is identified",
          arguments: ["AIL", "AIP"], ["2.5.1", "2.6", "2.8.2"])
    func resourceType(id: String, version: String) throws {
        func wire(_ resource: String) -> String {
            TestWires.wire("SRM^S01", version, TestWires.segment("SCH", [1: "PL1", 2: "FL1"]),
                           TestWires.segment(id, [1: "1", 3: resource]))
        }
        #expect(try missing(wire(""), id, 4).count == 1, "\(id) v\(version)")
        #expect(try missing(wire("RES1"), id, 4).isEmpty, "\(id) v\(version)")
    }

    @Test("Segment Action Code stays bare: Chapter 10 names no closed event set")
    func segmentActionCodeRegistered() {
        let tables = [SegmentGrammarTable.v2_3_1, SegmentGrammarTable.v2_4, SegmentGrammarTable.v2_5_1,
                      SegmentGrammarTable.v2_6, SegmentGrammarTable.v2_8_2]
        for table in tables {
            for id in ["AIS", "AIG", "AIL", "AIP", "RGS"] {
                #expect(table[id]?.field(2)?.optionality == .conditional, "\(id)-2")
                #expect(table[id]?.field(2)?.condition == nil, "\(id)-2")
            }
        }
    }
}
