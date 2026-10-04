// GroupSpanBoundaryTests.swift
// P8b-17 fix round 3: a group that occurs at most once per occurrence of its
// parent is transparent and never a pairing boundary; only a repeating nested
// group can be one. The v2.8.2 COMMON_ORDER { ORC ... [ORDER_DOCUMENT { OBX ...
// TXA }] } occurs once per order, so an OBX elsewhere in the order still finds
// the order's ORC.

import Testing
@testable import HL7v2Kit

@Suite("Group spans: a non-repeating group is never a pairing boundary (P8b-17 fix round 3)")
struct GroupSpanBoundaryTests {
    /// v2.8.2 ORU_R01 ORDER_OBSERVATION { [COMMON_ORDER { ORC ... }] OBR ...
    /// [{OBSERVATION { OBX ... }}] ... } (CH07): the OBX's order has one ORC.
    static let oru = ("ORU^R01^ORU_R01", ["PID|1", "ORC|NW|P1", "OBR|1|P1||X", "OBX|1"])
    /// v2.8.2 OUL_R22 SPECIMEN { SPM [{SPECIMEN_OBSERVATION { OBX }}] ... [{ORDER { OBR
    /// [COMMON_ORDER { ORC ... }] ... [{RESULT { OBX ... }}] }}] } (CH07 7.3.8): the
    /// RESULT OBX's order has one ORC; the SPECIMEN_OBSERVATION OBX belongs to the
    /// specimen, whose orders repeat, so the print gives it no ORC.
    static let oulR22 = ("OUL^R22^OUL_R22", ["SPM|1", "OBX|1", "OBR|1|P1||X", "ORC|SC|P1", "OBX|2"])
    /// v2.8.2 OUL_R23: the same, with the order inside CONTAINER (CH07 7.3.9).
    static let oulR23 = ("OUL^R23^OUL_R23", ["SPM|1", "OBX|1", "SAC|1", "OBR|1|P1||X", "ORC|SC|P1", "OBX|2"])

    @Test("v2.8.2 ORU_R01: the OBSERVATION OBX finds its order's ORC")
    func oruOBXFindsORC() throws {
        let message = try GroupSpanScopeTests.scoped(Self.oru.0, "2.8.2", Self.oru.1)
        #expect(message.associatedIndex("ORC", fromIndex: 4) == 2)
    }

    @Test("v2.8.2 OUL_R22 and OUL_R23: the RESULT OBX finds its order's ORC; the specimen's OBX has none")
    func oulOBXFindsORC() throws {
        let r22 = try GroupSpanScopeTests.scoped(Self.oulR22.0, "2.8.2", Self.oulR22.1)
        #expect(r22.associatedIndex("ORC", fromIndex: 5) == 4, "R22 RESULT OBX")
        #expect(r22.associatedIndex("ORC", fromIndex: 2) == nil, "R22 SPECIMEN_OBSERVATION OBX")
        let r23 = try GroupSpanScopeTests.scoped(Self.oulR23.0, "2.8.2", Self.oulR23.1)
        #expect(r23.associatedIndex("ORC", fromIndex: 6) == 5, "R23 RESULT OBX")
        #expect(r23.associatedIndex("ORC", fromIndex: 2) == nil, "R23 SPECIMEN_OBSERVATION OBX")
    }

    /// A custom `.orcObxGroup` rule on OBX requiring two ORCs in the group: it
    /// resolves (and so reports one ORC found) for every OBX inside an order,
    /// and is skipped for the specimen's OBX, which has no ORC group.
    @Test("A custom orcObxGroup rule anchored at OBX resolves and is evaluated",
          arguments: ["ORU", "R22", "R23"])
    func customOrcObxGroupRule(_ which: String) throws {
        let (msh9, body, resolved) = switch which {
        case "ORU": (Self.oru.0, Self.oru.1, 1)
        case "R22": (Self.oulR22.0, Self.oulR22.1, 1)
        default: (Self.oulR23.0, Self.oulR23.1, 1)
        }
        let rule = SegmentCardinalityRule(countedSegmentID: "ORC", scope: .orcObxGroup, minCount: 2,
                                          predicate: "", specCitation: "test-only:orcObxGroup")
        let profile = Profile(locale: .international, cardinalityExtensions: ["OBX": [rule]])
        let message = try GroupSpanScopeTests.message(msh9, "2.8.2", body)
        let issues = Validator(locale: .international, testProfileOverride: profile).validate(message).issues
        let fired = issues.filter {
            $0.code == .segmentCardinalityBelowMinimum(segmentID: "ORC", minCount: 2, actual: 1, groupScope: "orcObxGroup")
        }
        #expect(fired.count == resolved, "\(which): \(issues.map(\.message))")
    }
}
