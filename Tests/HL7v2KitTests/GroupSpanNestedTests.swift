// GroupSpanNestedTests.swift
// P8b-17 fix round 1: OML_O21, OML_O33 and OML_O35 nest a prior-result
// ORDER_PRIOR { [ORC] OBR ... } inside the order's OBSERVATION_REQUEST. A
// peer is taken from the anchor's own group occurrence, never from a nested
// group that pairs its own ORC and OBR.

import Testing
@testable import HL7v2Kit

@Suite("Group spans: prior results nested in an order (P8b-17 fix round 1)")
struct GroupSpanNestedTests {
    /// The structures and the versions that print them with PRIOR_RESULT.
    static let cases: [String] = ["2.4 OML_O21", "2.5.1 OML_O21", "2.6 OML_O21", "2.7.1 OML_O21", "2.8.2 OML_O21",
                                  "2.5.1 OML_O33", "2.6 OML_O33", "2.7.1 OML_O33", "2.8.2 OML_O33",
                                  "2.5.1 OML_O35", "2.6 OML_O35", "2.7.1 OML_O35", "2.8.2 OML_O35"]

    /// One order with one prior result. The second PID can only open
    /// PATIENT_PRIOR, so the parse is unique. `mainOBX` adds an OBX to the
    /// order's own OBSERVATION group.
    static func wire(_ key: String, mainORC: String, mainOBR: String, priorORC: String?, priorOBR: String,
                     mainOBX: Bool = false) -> String {
        let parts = key.split(separator: " ").map(String.init)
        let head: [String] = switch parts[1] {
        case "OML_O33": ["PID|1", "SPM|1"]
        case "OML_O35": ["PID|1", "SPM|1", "SAC|1"]
        default: ["PID|1"]
        }
        let trigger = parts[1].replacingOccurrences(of: "_", with: "^")
        let body = head + [mainORC, mainOBR] + (mainOBX ? ["OBX|1"] : []) + ["PID|1"]
            + (priorORC.map { [$0] } ?? []) + [priorOBR, "OBX|1"]
        return TestWires.msh("\(trigger)^\(parts[1])", parts[0]) + body.map { $0 + "\r" }.joined()
    }

    static func check(_ wire: String, _ key: String) throws -> [String] {
        let all = try GroupSpanPredicateTests.issues(wire, structure: .warning)
        #expect(GroupSpanPredicateTests.structureFindings(all).isEmpty, "\(key) does not conform: \(GroupSpanPredicateTests.structureFindings(all))")
        #expect(try GroupSpanSeamTests.scoping(wire) == "spans", "\(key): no spans")
        return GroupSpanPredicateTests.groupFindings(all)
    }

    @Test("The order's numbers only in its ORC: the order's OBR reads its own ORC, not the prior result's",
          arguments: cases)
    func numbersInMainORC(_ key: String) throws {
        let wire = Self.wire(key, mainORC: "ORC|NW|PON1", mainOBR: "OBR|1|||X", priorORC: "ORC|NW", priorOBR: "OBR|2|PON9||X")
        let found = try Self.check(wire, key); #expect(found.isEmpty, "\(key)")
    }

    /// v2.3 to v2.6: OBR-29 is required for a child order whose ORC-8 is empty
    /// (v2.5.1 CH04 4.5.3.29), and ORC-8 when OBR-29 is empty (4.5.1.8). The
    /// prior result's ORC is optional on v2.4 to v2.6 only (v2.7.1 and v2.8.2
    /// print ORDER_PRIOR { ORC OBR ... }), and ORC-8 / OBR-29 are conditional
    /// on those versions only.
    @Test("A child order with no parent and a prior result with no ORC: the order's OBR still reads its own ORC",
          arguments: cases.filter { ["2.4", "2.5.1", "2.6"].contains(String($0.prefix { $0 != " " })) })
    func childOrderWithoutPriorORC(_ key: String) throws {
        let wire = Self.wire(key, mainORC: "ORC|CH|PON1", mainOBR: "OBR|1|PON1||X", priorORC: nil, priorOBR: "OBR|2|PON9||X")
        let found = try Self.check(wire, key); #expect(found == ["OBR[1]-29 missing", "ORC[1]-8 missing"], "\(key)")
    }

    @Test("The prior result's numbers only in its own ORC: clean", arguments: cases)
    func numbersInPriorORC(_ key: String) throws {
        let wire = Self.wire(key, mainORC: "ORC|NW|PON1", mainOBR: "OBR|1|||X", priorORC: "ORC|NW|PON9", priorOBR: "OBR|2|||X")
        let found = try Self.check(wire, key); #expect(found.isEmpty, "\(key)")
    }

    /// CH04 4.5.1.2 and 4.5.3.2: the number must be in the ORC or in the
    /// associated OBR; the prior result's ORC and OBR are each other's.
    @Test("No number in the prior result's ORC or OBR: reported on the prior result only", arguments: cases)
    func numbersInNeitherPrior(_ key: String) throws {
        let wire = Self.wire(key, mainORC: "ORC|NW|PON1", mainOBR: "OBR|1|||X", priorORC: "ORC|NW", priorOBR: "OBR|2|||X")
        let found = try Self.check(wire, key); #expect(found == ["OBR[2]-2 missing", "OBR[2]-3 missing", "ORC[2]-2 missing", "ORC[2]-3 missing"], "\(key)")
    }

    @Test("Pair equality pairs each ORC with the OBR of its own group", arguments: cases)
    func pairEquality(_ key: String) throws {
        let same = Self.wire(key, mainORC: "ORC|NW|PON1", mainOBR: "OBR|1|PON1||X", priorORC: "ORC|NW|PON9", priorOBR: "OBR|2|PON9||X")
        let found = try Self.check(same, key); #expect(found.isEmpty, "\(key)")
        let differ = Self.wire(key, mainORC: "ORC|NW|PON1", mainOBR: "OBR|1|PON1||X", priorORC: "ORC|NW|PON9", priorOBR: "OBR|2|PON8||X")
        let differs = try Self.check(differ, key); #expect(differs == ["OBR[2]-2 mismatch 00216"], "\(key)")
    }

    /// The message indices the `.obrObxGroup` scope gives around `anchor`.
    static func obrGroup(_ wire: String, around anchor: Int) throws -> [Int] {
        let message = try Parser().parse(wire)
        let spans = try #require(Validator().groupSpans(for: message))
        return try #require(spans.group(around: anchor, holding: "OBR", counting: "OBX"))
    }

    @Test("Each OBX is scoped to its own OBR: the order's OBR group holds no prior-result segment", arguments: cases)
    func obxScoping(_ key: String) throws {
        let wire = Self.wire(key, mainORC: "ORC|NW|PON1", mainOBR: "OBR|1|PON1||X", priorORC: "ORC|NW|PON9",
                             priorOBR: "OBR|2|PON9||X", mainOBX: true)
        let message = try Parser().parse(wire)
        let ids = message.segments.map(\.segmentID)
        let obrs = ids.indices.filter { ids[$0] == "OBR" }, obxs = ids.indices.filter { ids[$0] == "OBX" }
        try #require(obrs.count == 2 && obxs.count == 2)
        let scoped = message.scoped(Validator().groupScoping(for: message))
        #expect(scoped.associatedIndex("OBR", fromIndex: obxs[0]) == obrs[0], "\(key)")
        #expect(scoped.associatedIndex("OBR", fromIndex: obxs[1]) == obrs[1], "\(key)")
        let main = try Self.obrGroup(wire, around: obrs[0])
        #expect(main.contains(obxs[0]) && !main.contains(obxs[1]) && !main.contains(obrs[1]), "\(key): \(main)")
        let prior = try Self.obrGroup(wire, around: obrs[1])
        #expect(prior.contains(obxs[1]) && !prior.contains(obxs[0]) && !prior.contains(obrs[0]), "\(key): \(prior)")
    }
}
