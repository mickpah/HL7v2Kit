// GroupSpanScopeTests.swift
// P8b-17 fix round 2: a peer comes from the anchor's own scope (the extended
// own level of an ancestor-or-self group, or inside the anchor's own group),
// never from a repeating sibling group; a child group that occurs at most once
// per parent occurrence and is not a pairing boundary is transparent; a pairing
// boundary holds for every anchor it pairs.

import Dispatch
import Testing
@testable import HL7v2Kit

@Suite("Group spans: the anchor's own scope and transparent groups (P8b-17 fix round 2)")
struct GroupSpanScopeTests {
    static func message(_ msh9: String, _ version: String, _ body: [String]) throws -> Message {
        try Parser().parse(TestWires.msh(msh9, version) + body.map { $0 + "\r" }.joined())
    }

    /// The message with the Validator's scoping, after asserting it conforms and has spans.
    static func scoped(_ msh9: String, _ version: String, _ body: [String]) throws -> Message {
        let message = try Self.message(msh9, version, body)
        let wire = TestWires.msh(msh9, version) + body.map { $0 + "\r" }.joined()
        let all = try GroupSpanPredicateTests.issues(wire, structure: .warning)
        #expect(GroupSpanPredicateTests.structureFindings(all).isEmpty, "v\(version) \(msh9): \(GroupSpanPredicateTests.structureFindings(all))")
        let scoping = Validator().groupScoping(for: message)
        #expect(GroupSpanSeamTests.describe(scoping) == "spans", "v\(version) \(msh9): no spans")
        return message.scoped(scoping)
    }

    static func findings(_ msh9: String, _ version: String, _ body: [String]) throws -> [String] {
        let wire = TestWires.msh(msh9, version) + body.map { $0 + "\r" }.joined()
        return GroupSpanPredicateTests.groupFindings(try GroupSpanPredicateTests.issues(wire))
    }

    // MARK: - CSU_C09: the pharmacy ORC has no OBR

    /// CSU_C09 prints STUDY_SCHEDULE { [CSS] {STUDY_OBSERVATION { [ORC] OBR ... OBX }}
    /// {STUDY_PHARM { [ORC] {RX_ADMIN { RXA ... }} }} } (v2.8.2 CH07 pp 103 to 104
    /// wraps the ORCs in STUDY_OBSERVATION_ORDER and COMMON_ORDER). STUDY_OBSERVATION
    /// repeats, so the pharmacy ORC's OBR is never the study observation's.
    static let csuVersions = ["2.3", "2.3.1", "2.4", "2.5.1", "2.6", "2.7.1", "2.8.2"]

    static func csu(_ version: String, studyORC: String, studyOBR: String, pharmacyORC: String) throws -> [String] {
        let structure = try #require(MessageStructureTable.structure("CSU_C09", version: GroupSpanPredicateTests.version(version)))
        let rxr = structure.elements.contains { $0.segmentIDs.contains("RXR") } ? ["RXR|1"] : []
        return ["PID|1", "CSR|1", studyORC, studyOBR, "OBX|1", pharmacyORC, "RXA|1"] + rxr
    }

    @Test("CSU_C09: a pharmacy ORC whose numbers differ from the study OBR's draws no pair mismatch", arguments: csuVersions)
    func csuPharmacyNumbers(version: String) throws {
        let body = try Self.csu(version, studyORC: "ORC|RE|S1|SF1", studyOBR: "OBR|1|S1|SF1|X", pharmacyORC: "ORC|RE|PH1|PF1")
        _ = try Self.scoped("CSU^C09^CSU_C09", version, body)
        let found = try Self.findings("CSU^C09^CSU_C09", version, body)
        #expect(found.isEmpty, "v\(version)")
    }

    /// CH04 4.5.1.2 / 4.5.1.3 (v2.5.1; v2.8.2 adds the Send Number exception):
    /// with no associated OBR, the ORC must carry its own placer or filler number.
    @Test("CSU_C09: a pharmacy ORC with no number is reported, as an ORC with no OBR", arguments: csuVersions)
    func csuPharmacyWithoutNumbers(version: String) throws {
        let body = try Self.csu(version, studyORC: "ORC|RE|S1|SF1", studyOBR: "OBR|1|S1|SF1|X", pharmacyORC: "ORC|RE")
        _ = try Self.scoped("CSU^C09^CSU_C09", version, body)
        let found = try Self.findings("CSU^C09^CSU_C09", version, body)
        #expect(found == ["ORC[2]-2 missing", "ORC[2]-3 missing"], "v\(version)")
    }

    @Test("CSU_C09: a mismatch inside one STUDY_OBSERVATION is still reported", arguments: csuVersions)
    func csuStudyMismatch(version: String) throws {
        let body = try Self.csu(version, studyORC: "ORC|RE|S1|SF1", studyOBR: "OBR|1|S2|SF1|X", pharmacyORC: "ORC|RE|PH1|PF1")
        _ = try Self.scoped("CSU^C09^CSU_C09", version, body)
        let found = try Self.findings("CSU^C09^CSU_C09", version, body)
        #expect(found == ["OBR[1]-2 mismatch 00216"], "v\(version)")
    }

    // MARK: - OBX to OBR

    /// OML_O21: the order's OBX is in OBSERVATION, whose parent OBSERVATION_REQUEST
    /// holds the order's OBR; the prior result's OBR is in ORDER_PRIOR, a pairing
    /// group nested in PRIOR_RESULT, never in the OBX's scope (not just later in it).
    @Test("OML_O21: the order's OBX scope holds the order's OBR and not the prior result's",
          arguments: ["2.5.1", "2.6", "2.7.1", "2.8.2"])
    func omlMainOBX(version: String) throws {
        let body = ["PID|1", "ORC|NW|PON1", "OBR|1|PON1||X", "OBX|1", "PID|1", "ORC|NW|PON9", "OBR|2|PON9||X", "OBX|1"]
        let message = try Self.scoped("OML^O21^OML_O21", version, body)
        guard case .spans(let index) = message.groupScoping else { return }
        let context = index.context(around: 4, of: "OBX", for: "OBR")
        #expect(context.contains(3) && !context.contains(7), "v\(version): \(context)")
        #expect(message.associatedIndex("OBR", fromIndex: 4) == 3)
    }

    /// OMQ_O42 v2.8.2 (CH04): ORDER { ORC OBX TXA [{OBSERVATION { OBX ... }}]
    /// [{PRIOR_RESULT { ... {ORDER_PRIOR { ORC OBR ... {OBSERVATION_PRIOR { OBX }} }} }}] }.
    /// The order has no OBR; ORDER_PRIOR pairs its own OBX with its own OBR.
    @Test("OMQ_O42: the order's OBX has no OBR; the prior result's OBX has its own")
    func omqMainOBX() throws {
        let body = ["ORC|NW|PON1", "OBX|1", "TXA|1", "OBX|2", "ORC|NW|PON9", "OBR|1|PON9||X", "OBX|1"]
        let message = try Self.scoped("OMQ^O42^OMQ_O42", "2.8.2", body)
        #expect(message.associatedIndex("OBR", fromIndex: 2) == nil, "order-level OBX")
        #expect(message.associatedIndex("OBR", fromIndex: 4) == nil, "OBSERVATION OBX")
        #expect(message.associatedIndex("OBR", fromIndex: 7) == 6, "prior OBX")
    }

    /// DFT_P03 and DFT_P11 print COMMON_ORDER { [ORC] ... [ORDER { OBR [{NTE}] }]
    /// [{OBSERVATION { OBX [{NTE}] }}] } (v2.5.1 CH06 6.4.3 and 6.4.11): ORDER
    /// occurs at most once per COMMON_ORDER, so it is transparent and the OBX
    /// finds the OBR of its own COMMON_ORDER occurrence. Through the Validator a
    /// DFT with an OBX has no spans: every COMMON_ORDER element is optional, so an
    /// OBX may also open a new COMMON_ORDER and the accepting parses disagree. The
    /// rule is shown on the one-pass matcher's parse (the OBX stays in the open
    /// COMMON_ORDER), read against the printed structure.
    @Test("DFT: the OBX in OBSERVATION finds the OBR of its own COMMON_ORDER; the OBR's group takes in that OBX only",
          arguments: ["2.4 DFT_P03", "2.5.1 DFT_P03", "2.6 DFT_P03", "2.7.1 DFT_P03", "2.8.2 DFT_P03",
                      "2.5.1 DFT_P11", "2.6 DFT_P11", "2.7.1 DFT_P11", "2.8.2 DFT_P11"])
    func dftOBX(_ key: String) throws {
        let parts = key.split(separator: " ").map(String.init)
        let structure = try #require(MessageStructureTable.structure(parts[1], version: GroupSpanPredicateTests.version(parts[0])))
        let ids = ["MSH", "EVN", "PID", "ORC", "OBR", "OBX", "ORC", "OBR", "OBX", "FT1"]
        let exact = ExactStructureMatcher(structure: structure).match(ids)
        #expect(exact.findings.isEmpty && exact.spansWithheld, "\(key): the print is ambiguous here")
        let orderOnly = ExactStructureMatcher(structure: structure).match(["MSH", "EVN", "PID", "ORC", "OBR", "FT1"])
        #expect(orderOnly.findings.isEmpty && orderOnly.spansWithheld, "\(key): ORC then OBR is ambiguous too")
        let match = StructureMatcher(structure: structure).match(ids)
        #expect(match.findings.isEmpty, "\(key)")
        let index = GroupSpanIndex(spans: match.spans, elements: structure.elements, ids: ids)
        #expect(index.context(around: 5, of: "OBX", for: "OBR").filter { ids[$0] == "OBR" } == [4], "\(key) first OBX")
        #expect(index.context(around: 8, of: "OBX", for: "OBR").filter { ids[$0] == "OBR" } == [7], "\(key) second OBX")
        #expect(index.group(around: 4, holding: "OBR", counting: "OBX") == [3, 4, 5], "\(key) first OBR's group")
        #expect(index.group(around: 7, holding: "OBR", counting: "OBX") == [6, 7, 8], "\(key) second OBR's group")
    }

    /// v2.8.2 CCR_I16 CLINICAL_ORDER_DETAIL { CLINICAL_ORDER_OBJECT <OBR | ...>
    /// [{CLINICAL_ORDER_OBSERVATION { OBX ... }}] }, and the CLINICAL_HISTORY_DETAIL
    /// of CCI_I22: the named choice occurs once per detail, so it is transparent.
    @Test("CC*: the OBX in CLINICAL_*_OBSERVATION finds the OBR of its detail's object choice",
          arguments: ["CCR^I16^CCR_I16|RF1|1;PRD|1;ORC|NW|P1;OBR|1|P1||X;OBX|1;PID|1;PV1|1",
                      "CCI^I22^CCI_I22|MSA|AA|1;PID|1;ORC|NW|P1;OBR|1|P1||X;OBX|1;PV1|1"])
    func ccOBX(_ spec: String) throws {
        let msh9 = String(spec.prefix { $0 != "|" })
        let body = spec.dropFirst(msh9.count + 1).split(separator: ";").map(String.init)
        let message = try Self.scoped(msh9, "2.8.2", body)
        let ids = message.segments.map(\.segmentID)
        let obr = try #require(ids.firstIndex(of: "OBR")), obx = try #require(ids.firstIndex(of: "OBX"))
        #expect(message.associatedIndex("OBR", fromIndex: obx) == obr, "\(msh9)")
    }

    // MARK: - Only a repeating group can be a pairing boundary

    /// `MSH ORDER{ ORC [DETAIL{OBR}] PRIOR*{ORC OBR [OBX]} [OBX] }` against the same
    /// structure with PRIOR printed as non-repeating. Fix round 3 (the controller's
    /// ruling, replacing round 2's "a pairing boundary is never transparent"): a
    /// group that occurs at most once per parent occurrence is transparent and
    /// never a boundary, so a non-repeating PRIOR's ORC and OBR join ORDER's own
    /// level; a repeating PRIOR that claims its own ORC/OBR/OBX stays cut. No
    /// printed structure has a non-repeating group that claims an ORC/OBR pair
    /// (guarded by `noNonRepeatingPairingGroup`), so the first case is synthetic.
    @Test("A repeating pairing group is cut; the same group printed non-repeating is transparent")
    func onlyRepeatingGroupsPair() {
        func elements(priorMax: Int?) -> [StructureElement] {
            [.segment("MSH", min: 1, max: 1),
             .group("ORDER", min: 1, max: 1, elements: [
                .segment("ORC", min: 1, max: 1),
                .group("DETAIL", min: 0, max: 1, elements: [.segment("OBR", min: 1, max: 1)]),
                .group("PRIOR", min: 0, max: priorMax, elements: [
                    .segment("ORC", min: 1, max: 1), .segment("OBR", min: 1, max: 1), .segment("OBX", min: 0, max: 1)]),
                .segment("OBX", min: 0, max: 1),
             ])]
        }
        let ids = ["MSH", "ORC", "OBR", "ORC", "OBR", "OBX", "OBX"]
        for priorMax in [nil, 1] as [Int?] {
            let structure = MessageStructure(id: "T", version: "2.5.1", triggers: [], citation: "test",
                                             elements: elements(priorMax: priorMax))
            let match = ExactStructureMatcher(structure: structure).match(ids)
            #expect(match.findings.isEmpty && !match.spansWithheld)
            let index = GroupSpanIndex(spans: match.spans, elements: structure.elements, ids: ids)
            let obrs = index.context(around: 1, of: "ORC", for: "OBR").filter { ids[$0] == "OBR" }
            let orderOBX = index.context(around: 6, of: "OBX", for: "OBR").filter { ids[$0] == "OBR" }
            if priorMax == nil {
                #expect(obrs == [2], "repeating PRIOR is cut for the order's ORC")
                #expect(orderOBX == [2], "repeating PRIOR is cut for the order's OBX")
                #expect(index.context(around: 4, of: "OBR", for: "ORC").filter { ids[$0] == "ORC" } == [3])
                #expect(index.context(around: 5, of: "OBX", for: "OBR").filter { ids[$0] == "OBR" } == [4])
            } else {
                #expect(obrs == [2, 4], "non-repeating PRIOR is transparent: its OBR joins ORDER's level")
                #expect(orderOBX == [2, 4])
            }
        }
    }

    /// The fix-round-3 principle is safe on the prints only if no structure has
    /// a non-repeating nested group that claims an ORC/OBR pair (a non-repeating
    /// prior-result style group): such a group would now leak its ORC or OBR
    /// into the enclosing order.
    @Test("No printed structure has a non-repeating group that claims its own ORC/OBR pair")
    func noNonRepeatingPairingGroup() {
        var found: [String] = []
        for version in [Version.v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_7_1, .v2_8_2] {
            for structure in MessageStructureTable.structures(for: version).values {
                for group in Self.groups(structure.elements) where group.max == 1 {
                    for (anchor, peer) in [("ORC", "OBR"), ("OBR", "ORC")]
                    where ScopeLookup(anchor: anchor, peer: peer).claims(group) {
                        found.append("v\(version.rawValue) \(structure.id) \(group.groupName ?? "?") \(anchor)>\(peer)")
                    }
                }
            }
        }
        #expect(found.isEmpty, "\(found)")
    }

    // MARK: - Every lookup the predicates make terminates, fast

    /// The cross-segment (anchor, peer) pairs the base conditions of `version`
    /// use, plus the group-scope pairs (counting OBX under OBR or ORC).
    static func predicatePairs(_ grammar: [String: SegmentGrammar]) -> Set<[String]> {
        var pairs: Set<[String]> = [["OBX", "OBR"], ["OBX", "ORC"], ["OBR", "OBR"]]
        let pattern = /\b([A-Z][A-Z0-9]{2})(?:-[0-9]| present| absent)/
        for (id, segment) in grammar {
            for field in segment.fields {
                let conditions = [field.condition, field.prohibitedWhen].compactMap { $0 }
                    + field.additionalProhibitions.map(\.condition)
                for condition in conditions {
                    for match in condition.matches(of: pattern) where String(match.1) != id {
                        pairs.insert([id, String(match.1)])
                    }
                }
            }
        }
        return pairs
    }

    static func groups(_ elements: [StructureElement]) -> [StructureElement] {
        elements.flatMap { element -> [StructureElement] in
            switch element {
            case .segment: return []
            case .choice(.none, _, _, let alternatives): return groups(alternatives)
            default: return [element] + groups(element.children)
            }
        }
    }

    /// Runs `work` on another thread and waits at most `seconds`: a lookup that
    /// does not terminate fails the test (the thread is left behind) instead of
    /// hanging the run. Returns the elapsed time, or nil on a timeout.
    static func watchdog(_ seconds: Int, _ work: @escaping @Sendable () -> Void) -> Duration? {
        let done = DispatchSemaphore(value: 0)
        let start = ContinuousClock.now
        DispatchQueue.global().async {
            work()
            done.signal()
        }
        guard done.wait(timeout: .now() + .seconds(seconds)) == .success else { return nil }
        return ContinuousClock.now - start
    }

    /// Every message-level lookup (`context`, `group`, and so `region`) for every
    /// segment of a conforming message of every structure on every version, with
    /// the group-dependent pairs.
    @Test("Message-level lookups terminate, fast, on a conforming message of every structure")
    func everyMessageLookupTerminates() {
        final class Count: @unchecked Sendable { var structures = 0; var lookups = 0 }
        let count = Count()
        let elapsed = Self.watchdog(120) {
            for version in [Version.v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_7_1, .v2_8_2] {
                let pairs = Self.predicatePairs(Validator.grammarTable(for: version))
                for structure in MessageStructureTable.structures(for: version).values {
                    let ids = GroupSpanPredicateTests.skeleton(structure.elements)
                    let match = StructureMatcherCache.shared.matcher(for: structure).match(ids)
                    guard match.findings.isEmpty, !match.spansWithheld else { continue }
                    let index = GroupSpanIndex(spans: match.spans, elements: structure.elements, ids: ids)
                    count.structures += 1
                    for (anchor, id) in ids.enumerated() {
                        for pair in pairs where pair[0] == id {
                            _ = index.context(around: anchor, of: id, for: pair[1])
                            count.lookups += 1
                        }
                        for head in ["ORC", "OBR"] {
                            _ = index.group(around: anchor, holding: head, counting: "OBX")
                            count.lookups += 1
                        }
                    }
                }
            }
        }
        // The suite runs tests in parallel, so wall-clock time here depends on the
        // load; the watchdog catches a lookup that does not terminate, and the
        // long-message test below checks the growth rate.
        #expect(elapsed != nil, "message-level lookups did not finish within 120 s")
        #expect(count.structures > 500, "\(count.structures) structures")
        if let elapsed { print("message-level lookups: \(count.lookups) on \(count.structures) structures in \(elapsed)") }
    }

    /// A long message through the whole Validator: ORU_R01 and OUL_R22 v2.5.1
    /// with 300 orders of 10 results each (over 3,600 segments, over 3,000 group
    /// occurrences), against the same message with 30 orders. Validation is
    /// linear in the segments, so ten times the orders should cost about ten
    /// times as much; a lookup quadratic in the group occurrences would make it
    /// about a hundred. The ratio, not the wall-clock time, is bounded, because
    /// the suite runs tests in parallel; each run sits under a watchdog.
    @Test("A long ORU_R01 and OUL_R22 validate in time linear in their length", arguments: ["ORU", "OUL"])
    func longMessage(_ which: String) throws {
        func message(orders: Int) throws -> Message {
            var body: [String] = which == "ORU" ? ["PID|1"] : ["PID|1", "SPM|1"]
            for order in 1...orders {
                let pair = which == "ORU"
                    ? ["ORC|RE|P\(order)|F\(order)", "OBR|\(order)|P\(order)|F\(order)|X"]
                    : ["OBR|\(order)|P\(order)|F\(order)|X", "ORC|SC|P\(order)|F\(order)"]
                body += pair + (1...10).map { "OBX|\($0)|ST|C^Code||v" }
            }
            let msh9 = which == "ORU" ? "ORU^R01^ORU_R01" : "OUL^R22^OUL_R22"
            return try GroupSpanScopeTests.message(msh9, "2.5.1", body)
        }
        let long = try message(orders: 300), short = try message(orders: 30)
        #expect(GroupSpanSeamTests.describe(Validator().groupScoping(for: long)) == "spans")
        final class Box: @unchecked Sendable { var findings: [String] = [] }
        let box = Box()
        func timed(_ message: Message) -> Duration? {
            Self.watchdog(120) { box.findings = GroupSpanPredicateTests.groupFindings(Validator().validate(message).issues) }
        }
        let shortTimes = [timed(short), timed(short)].compactMap { $0 }
        let longTime = timed(long)
        #expect(longTime != nil && shortTimes.count == 2, "\(which): validation did not finish within 120 s")
        #expect(box.findings.isEmpty, "\(which): \(box.findings.prefix(3))")
        if let longTime, let shortTime = shortTimes.min() {
            let ratio = longTime / shortTime
            print("long-message \(which): \(long.segments.count) segments in \(longTime), \(short.segments.count) in \(shortTime), ratio \(ratio)")
            #expect(ratio < 30, "\(which): \(longTime) against \(shortTime)")
        }
    }

    @Test("The scope rule terminates, fast, for every predicate pair on every structure of every version")
    func everyLookupTerminates() {
        var checked = 0
        let elapsed = ContinuousClock().measure {
            for version in [Version.v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_7_1, .v2_8_2] {
                let pairs = Self.predicatePairs(Validator.grammarTable(for: version))
                for structure in MessageStructureTable.structures(for: version).values {
                    let ids = structure.elements.reduce(into: Set<String>()) { $0.formUnion($1.segmentIDs) }
                    let groups = Self.groups(structure.elements)
                    for pair in pairs where ids.contains(pair[0]) && ids.contains(pair[1]) {
                        let lookup = ScopeLookup(anchor: pair[0], peer: pair[1])
                        _ = lookup.extended(structure.elements)
                        _ = lookup.inside(structure.elements)
                        for group in groups {
                            _ = lookup.transparent(group)
                            _ = lookup.extended(group.children)
                            _ = lookup.inside(group.children)
                        }
                        checked += 1
                    }
                }
            }
        }
        #expect(checked >= 900, "\(checked) lookups")
        #expect(elapsed < .seconds(10), "\(elapsed) for \(checked) lookups")
    }
}

