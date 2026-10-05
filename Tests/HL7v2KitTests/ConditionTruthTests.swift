// ConditionTruthTests.swift
// P4-31 (ADR-021): the condition evaluator's three-state core. Every
// condition evaluates to true, false or unknown; AND and OR are Kleene's
// strong three-valued connectives; and the released two-state
// `conditionTriggers` is exactly `conditionTruth(...) == .true`.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Three-state condition evaluator (P4-31, ADR-021)")
struct ConditionTruthTests {

    private let all: [ConditionTruth] = [.true, .false, .unknown]

    // MARK: - Kleene truth tables

    @Test("AND is Kleene's strong conjunction")
    func kleeneAnd() {
        let expected: [ConditionTruth: [ConditionTruth: ConditionTruth]] = [
            .true: [.true: .true, .false: .false, .unknown: .unknown],
            .false: [.true: .false, .false: .false, .unknown: .false],
            .unknown: [.true: .unknown, .false: .false, .unknown: .unknown],
        ]
        for a in all {
            for b in all {
                #expect(ConditionTruth.and(a, b) == expected[a]?[b], "\(a) AND \(b)")
            }
        }
    }

    @Test("OR is Kleene's strong disjunction")
    func kleeneOr() {
        let expected: [ConditionTruth: [ConditionTruth: ConditionTruth]] = [
            .true: [.true: .true, .false: .true, .unknown: .true],
            .false: [.true: .true, .false: .false, .unknown: .unknown],
            .unknown: [.true: .true, .false: .unknown, .unknown: .unknown],
        ]
        for a in all {
            for b in all {
                #expect(ConditionTruth.or(a, b) == expected[a]?[b], "\(a) OR \(b)")
            }
        }
    }

    @Test("The empty conjunction is true and the empty disjunction is false")
    func identities() {
        #expect(ConditionTruth.all([]) == .true)
        #expect(ConditionTruth.any([]) == .false)
        #expect(ConditionTruth.all([.true, .unknown, .false]) == .false)
        #expect(ConditionTruth.any([.false, .unknown, .true]) == .true)
        #expect(ConditionTruth.all([.true, .unknown]) == .unknown)
        #expect(ConditionTruth.any([.false, .unknown]) == .unknown)
    }

    // MARK: - Evaluator

    /// Evaluate `condition` on the first segment `id` of `wire`, both ways.
    private func evaluate(_ condition: String, on id: String,
                          in wire: String) throws -> (ConditionTruth, Bool) {
        let message = try Parser().parse(wire)
        let index = try #require(message.segments.firstIndex { $0.segmentID == id })
        let validator = Validator()
        let truth = validator.conditionTruth(condition, in: message.segments[index],
                                             segmentIndex: index, message: message,
                                             currentSegmentID: id)
        let triggers = validator.conditionTriggers(condition, in: message.segments[index],
                                                   segmentIndex: index, message: message,
                                                   currentSegmentID: id)
        return (truth, triggers)
    }

    private let oru = TestWires.msh("ORU^R01", "2.4")
        + "PID|1||123^^^HOSP^MR||DOE^JOHN\r"
        + "OBR|1||FILLER456^LAB|GLU^Glucose^L|||||||||||||||||||||F\r"
        + "OBX|1|NM|GLU^Glucose^L||5.2|mmol/L||||||F\r"

    @Test("A referent that resolves gives a definite answer")
    func definite() throws {
        #expect(try evaluate("OBR-3 populated", on: "OBR", in: oru) == (.true, true))
        #expect(try evaluate("OBR-2 populated", on: "OBR", in: oru) == (.false, false))
        #expect(try evaluate("OBR-2 empty", on: "OBR", in: oru) == (.true, true))
        #expect(try evaluate("messageCode = ORM", on: "OBR", in: oru) == (.false, false))
        #expect(try evaluate("ORC absent", on: "OBR", in: oru) == (.true, true))
    }

    @Test("A missing peer segment is unknown, not false (an ORU with no ORC)")
    func missingPeerIsUnknown() throws {
        #expect(try evaluate("ORC-2 empty", on: "OBR", in: oru) == (.unknown, false))
        #expect(try evaluate("ORC-2 populated", on: "OBR", in: oru) == (.unknown, false))
        #expect(try evaluate("associatedSegment(ORC).ORC-1 = RE", on: "OBR", in: oru) == (.unknown, false))
        #expect(try evaluate("previousSegment(ORC).ORC-1 = RE", on: "OBR", in: oru) == (.unknown, false))
        #expect(try evaluate("anyRepeat(ORC-2) populated", on: "OBR", in: oru) == (.unknown, false))
    }

    @Test("An unparseable atom is unknown")
    func unparseableIsUnknown() throws {
        #expect(try evaluate("OBR-2 frobnicated", on: "OBR", in: oru) == (.unknown, false))
        #expect(try evaluate("nonsense", on: "OBR", in: oru) == (.unknown, false))
    }

    @Test("An empty-domain quantifier is unknown")
    func emptyDomainIsUnknown() throws {
        #expect(try evaluate("noRepeat(OBR-2) = X", on: "OBR", in: oru) == (.unknown, false))
        #expect(try evaluate("anyRepeat(OBR-2) = X", on: "OBR", in: oru) == (.unknown, false))
        #expect(try evaluate("anyRepeat(OBR-40) = X", on: "OBR", in: oru) == (.unknown, false))
        #expect(try evaluate("noRepeat(OBR-40) = X", on: "OBR", in: oru) == (.unknown, false))
        // An empty slot that itself satisfies the predicate stays definite.
        #expect(try evaluate("anyRepeat(OBR-2) empty", on: "OBR", in: oru) == (.true, true))
        #expect(try evaluate("anyRepeat(OBR-3) = FILLER456", on: "OBR", in: oru) == (.true, true))
        #expect(try evaluate("noRepeat(OBR-3) = FILLER456", on: "OBR", in: oru) == (.false, false))
    }

    @Test("Predicates that fail safe on an empty or non-numeric referent are unknown")
    func failSafePredicatesAreUnknown() throws {
        #expect(try evaluate("OBR-2 not in (A, B)", on: "OBR", in: oru) == (.unknown, false))
        #expect(try evaluate("OBR-2 not startsWith Z", on: "OBR", in: oru) == (.unknown, false))
        #expect(try evaluate("OBR-3 > 1", on: "OBR", in: oru) == (.unknown, false))
        #expect(try evaluate("OBR-3 not in (A, B)", on: "OBR", in: oru) == (.true, true))
        #expect(try evaluate("OBX-5 > 1", on: "OBX", in: oru) == (.true, true))
    }

    @Test("Compound conditions combine atoms by Kleene AND and OR")
    func compound() throws {
        // false AND unknown is false; true AND unknown is unknown.
        #expect(try evaluate("OBR-2 populated AND ORC-2 empty", on: "OBR", in: oru) == (.false, false))
        #expect(try evaluate("OBR-3 populated AND ORC-2 empty", on: "OBR", in: oru) == (.unknown, false))
        // true OR unknown is true; false OR unknown is unknown.
        #expect(try evaluate("ORC-2 empty OR OBR-3 populated", on: "OBR", in: oru) == (.true, true))
        #expect(try evaluate("ORC-2 empty OR OBR-2 populated", on: "OBR", in: oru) == (.unknown, false))
        // The stored v2.4 OBR-2 condition on this ORC-less wire: both
        // clauses open with `OBR-3 empty`, which is definitely false
        // (OBR-3 is valued), so the unresolvable ORC atoms do not matter.
        let obr2 = try #require(SegmentGrammarTable.v2_4["OBR"]?.field(2)?.condition)
        #expect(try evaluate(obr2, on: "OBR", in: oru) == (.false, false))
    }

    // MARK: - Frozen two-state answers

    /// The wire the frozen table reads: an ORU with no ORC, a PID-3 with
    /// three repetitions (the third has no PID-3.5), an empty PID-4.
    private let frozenWire = TestWires.msh("ORU^R01", "2.4")
        + "PID|1||123^^^HOSP^MR~456^^^HOSP^PI~789||DOE^JOHN\r"
        + "OBR|1||FILLER456^LAB|GLU^Glucose^L\r"
        + "OBX|1|NM|GLU^Glucose^L||5.2|mmol/L|||||F\r"

    /// `conditionTriggers` answers frozen before the three-state refactor
    /// (each row checked against commit 237f0b5). One row per atom kind
    /// and per fail-safe path; a change here is a behaviour change.
    private let frozen: [(segment: String, condition: String, expected: Bool)] = [
        // value atoms, same segment
        ("OBR", "OBR-3 populated", true), ("OBR", "OBR-2 populated", false),
        ("OBR", "OBR-2 empty", true), ("OBR", "OBR-3.2 = LAB", true),
        ("OBR", "OBR-3 = FILLER456", true), ("OBR", "OBR-3 != FILLER456", false),
        ("OBR", "OBR-2 != X", true),
        ("OBR", "OBR-3 startsWith FILL", true), ("OBR", "OBR-2 startsWith F", false),
        ("OBR", "OBR-3 not startsWith Z", true), ("OBR", "OBR-2 not startsWith Z", false),
        ("OBR", "OBR-3 in (A, FILLER456)", true), ("OBR", "OBR-2 in (A)", false),
        ("OBR", "OBR-3 not in (A)", true), ("OBR", "OBR-2 not in (A)", false),
        ("OBX", "OBX-5 > 5", true), ("OBX", "OBX-5 > 6", false), ("OBX", "OBX-3 > 1", false),
        // message-context and caller-assertion referents
        ("OBR", "messageCode = ORU", true), ("OBR", "triggerEvent = R01", true),
        ("OBR", "messageStructure = ORU_R01", false), ("OBR", "auPathologySender populated", false),
        // lookahead and position atoms
        ("OBR", "nextSegmentID(NTE) = OBX", true), ("OBX", "nextSegmentID(NTE) = OBR", false),
        ("OBR", "previousSegment(PID).PID-3 populated", true),
        ("OBR", "previousSegment(ORC).ORC-1 = RE", false),
        ("OBR", "associatedSegment(ORC).ORC-1 = RE", false),
        // cross-segment peer that does not resolve
        ("OBR", "ORC-2 empty", false), ("OBR", "ORC-2 populated", false),
        // segment presence
        ("OBR", "ORC absent", true), ("OBR", "ORC present", false),
        // quantifiers
        ("PID", "anyRepeat(PID-3.5) = PI", true), ("PID", "anyRepeat(PID-3.5) = XX", false),
        ("PID", "anyRepeat(PID-3.5) empty", true), ("PID", "anyRepeat(PID-4) = X", false),
        ("PID", "noRepeat(PID-3.5) = XX", true), ("PID", "noRepeat(PID-3.5) = PI", false),
        ("PID", "noRepeat(PID-3.5) not in (MR, PI)", true), ("PID", "noRepeat(PID-4) = X", false),
        ("OBR", "anyRepeat(ORC-2) populated", false), ("OBR", "noRepeat(ORC-2) = X", false),
        // unparseable atoms
        ("OBR", "OBR-2 frobnicated", false), ("OBR", "nonsense", false),
        // compounds (AND binds tighter than OR)
        ("OBR", "OBR-3 populated AND ORC-2 empty", false),
        ("OBR", "ORC-2 empty OR OBR-3 populated", true),
        ("OBR", "OBR-2 populated OR OBR-3 empty", false),
        ("OBR", "OBR-3 populated AND OBR-2 empty", true),
        ("OBR", "OBR-2 populated AND ORC-2 empty OR messageCode = ORU", true),
    ]

    @Test("conditionTriggers keeps its frozen answer for every atom kind and fail-safe path")
    func frozenTwoStateAnswers() throws {
        let message = try Parser().parse(frozenWire)
        let validator = Validator()
        for row in frozen {
            let index = try #require(message.segments.firstIndex { $0.segmentID == row.segment })
            let got = validator.conditionTriggers(row.condition, in: message.segments[index],
                                                  segmentIndex: index, message: message,
                                                  currentSegmentID: row.segment)
            #expect(got == row.expected, "\(row.segment): \(row.condition)")
        }
    }
}
