// ConditionDSLExtensionTests.swift
// P4 DSL extensions: the noRepeat(...) universal-negation atom (SPM-13)
// and the nextSegmentID(...) lookahead referent (TQ1-12). Evaluated
// directly through Validator.conditionTriggers, so the atom semantics are
// pinned apart from any schema.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Condition DSL extensions (P4)")
struct ConditionDSLExtensionTests {

    /// Evaluate `condition` against the `occurrence`-th (1-based) segment `id`.
    private func evaluate(_ condition: String, on id: String, occurrence: Int = 1,
                          in wire: String) throws -> Bool {
        let message = try Parser().parse(wire)
        let indices = message.segments.indices.filter { message.segments[$0].segmentID == id }
        let index = try #require(indices.count >= occurrence ? indices[occurrence - 1] : nil)
        return Validator().conditionTriggers(condition, in: message.segments[index],
                                             segmentIndex: index, message: message,
                                             currentSegmentID: id)
    }

    private func spm(_ roles: String) -> String {
        TestWires.wire("OML^O33^OML_O33", "2.6", TestWires.segment("SPM", [1: "1", 11: roles]))
    }

    // MARK: - noRepeat

    @Test("noRepeat(SPM-11) = G holds when no repetition is G")
    func noRepeatHolds() throws {
        #expect(try evaluate("noRepeat(SPM-11) = G", on: "SPM",
                             in: spm("P^Patient^HL70369~Q^Control^HL70369")))
    }

    @Test("noRepeat(SPM-11) = G fails when any repetition is G")
    func noRepeatFailsOnAnyMatch() throws {
        #expect(!(try evaluate("noRepeat(SPM-11) = G", on: "SPM",
                               in: spm("P^Patient^HL70369~G^Group^HL70369"))))
    }

    @Test("noRepeat on an empty field is false (no definite value to negate)")
    func noRepeatEmptyIsFalse() throws {
        #expect(!(try evaluate("noRepeat(SPM-11) = G", on: "SPM", in: spm(""))))
    }

    @Test("noRepeat with a malformed field ref is false (fail-safe)")
    func noRepeatMalformed() throws {
        #expect(!(try evaluate("noRepeat(SPM-x) = G", on: "SPM", in: spm("P^Patient^HL70369"))))
    }

    @Test("noRepeat(SPM-11) = G holds for a single non-G occurrence (no repetition marker)")
    func noRepeatHoldsSingleOccurrence() throws {
        #expect(try evaluate("noRepeat(SPM-11) = G", on: "SPM",
                             in: spm("P^Patient^HL70369")))
    }

    @Test("noRepeat(SPM-11) = G fails for a single G occurrence (no repetition marker)")
    func noRepeatFailsSingleOccurrence() throws {
        #expect(!(try evaluate("noRepeat(SPM-11) = G", on: "SPM",
                               in: spm("G^Group^HL70369"))))
    }

    // MARK: - noRepeat composition (full universal negation, P4-4)

    @Test("SPM-11 empty OR noRepeat(SPM-11) = G fires on a wholly empty SPM-11")
    func noRepeatCompositionCoversEmpty() throws {
        #expect(try evaluate("SPM-11 empty OR noRepeat(SPM-11) = G", on: "SPM", in: spm("")))
    }

    @Test("SPM-11 empty OR noRepeat(SPM-11) = G does not fire when a repetition is G")
    func noRepeatCompositionRespectsMatch() throws {
        #expect(!(try evaluate("SPM-11 empty OR noRepeat(SPM-11) = G", on: "SPM",
                               in: spm("G^Group^HL70369"))))
    }

    // MARK: - nextSegmentID

    private let chainedTiming = TestWires.wire("OMG^O19^OMG_O19", "2.5.1",
        "ORC|NW|PL1", "TQ1|1", "TQ2|1|S|PL2^SYS", "TQ1|2", "OBR|1|PL1")

    @Test("nextSegmentID(TQ2) = TQ1 holds on a TQ1 that another TQ1 follows across its TQ2s")
    func nextSegmentHolds() throws {
        #expect(try evaluate("nextSegmentID(TQ2) = TQ1", on: "TQ1", occurrence: 1, in: chainedTiming))
    }

    @Test("nextSegmentID(TQ2) = TQ1 fails on the last TQ1 of the chain")
    func nextSegmentFailsOnLast() throws {
        #expect(!(try evaluate("nextSegmentID(TQ2) = TQ1", on: "TQ1", occurrence: 2, in: chainedTiming)))
    }

    @Test("nextSegmentID() reads the immediate next segment; the end of the message is empty")
    func nextSegmentImmediateAndEnd() throws {
        let wire = TestWires.wire("OMG^O19^OMG_O19", "2.5.1", "ORC|NW|PL1", "TQ1|1")
        #expect(try evaluate("nextSegmentID() = TQ1", on: "ORC", in: wire))
        #expect(try evaluate("nextSegmentID() empty", on: "TQ1", in: wire))
    }

    @Test("nextSegmentID skips Z-segments between chained TQ1s (ADR-003 site extensions)")
    func nextSegmentSkipsZSegments() throws {
        let direct = TestWires.wire("OMG^O19^OMG_O19", "2.5.1",
            "ORC|NW|PL1", "TQ1|1", "ZXX|1", "TQ1|2", "OBR|1|PL1")
        #expect(try evaluate("nextSegmentID(TQ2) = TQ1", on: "TQ1", occurrence: 1, in: direct))
        let afterTQ2 = TestWires.wire("OMG^O19^OMG_O19", "2.5.1",
            "ORC|NW|PL1", "TQ1|1", "TQ2|1|S|PL2^SYS", "ZXX|1", "TQ1|2", "OBR|1|PL1")
        #expect(try evaluate("nextSegmentID(TQ2) = TQ1", on: "TQ1", occurrence: 1, in: afterTQ2))
    }
}
