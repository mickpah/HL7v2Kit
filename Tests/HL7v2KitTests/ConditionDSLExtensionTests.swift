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
}
