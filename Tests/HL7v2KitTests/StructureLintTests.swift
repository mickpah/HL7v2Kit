// StructureLintTests.swift
// ADR-019 "Determinism lint": for every optional or repeating element E,
// FIRST(E) must be disjoint from FOLLOW(E), with one exempt overlap (a
// repeating element against the re-entry of an enclosing unbounded
// repeating group). Expectations below are derived by hand from the print.

import Testing
@testable import HL7v2Kit

@Suite("Structure determinism lint")
struct StructureLintTests {

    private func lint(_ id: String) throws -> StructureLint {
        StructureMatcher.lint(try #require(MessageStructureTable.structure(id, version: .v2_5_1)).elements)
    }

    private func overlap(_ path: [String], _ ids: [String], via: String? = nil) -> StructureLint.Overlap {
        StructureLint.Overlap(path: path, segmentIDs: ids, exemptVia: via)
    }

    @Test("Every modelled structure is deterministic for the greedy matcher")
    func modelledStructuresAreDeterministic() {
        for version in Version.allCases {
            for structure in MessageStructureTable.structures(for: version).values {
                #expect(StructureMatcher.lint(structure.elements).isDeterministic, "\(version.rawValue) \(structure.id)")
            }
        }
    }

    @Test("ACK: no overlap")
    func ack() throws {
        let result = try lint("ACK")
        #expect(result.conflicts.isEmpty)
        #expect(result.exempt.isEmpty)
    }

    @Test("ADT_A01: no overlap, ROL's four places included")
    func adt() throws {
        let result = try lint("ADT_A01")
        #expect(result.conflicts.isEmpty)
        #expect(result.exempt.isEmpty)
    }

    @Test("ORU_R01: exactly one exempt overlap, ORDER_OBSERVATION against PATIENT_RESULT re-entry on ORC and OBR")
    func oru() throws {
        let result = try lint("ORU_R01")
        #expect(result.conflicts.isEmpty)
        #expect(result.exempt == [overlap(["PATIENT_RESULT", "ORDER_OBSERVATION"], ["OBR", "ORC"], via: "PATIENT_RESULT")])
    }

    @Test("ADR-019's example: a trailing NTE in a group followed by a sibling NTE fails")
    func trailingThenSibling() {
        let elements: [StructureElement] = [
            .segment("OBR", min: 1, max: 1),
            .group("OBSERVATION", min: 0, max: nil, elements: [
                .segment("OBX", min: 1, max: 1),
                .segment("NTE", min: 0, max: nil),
            ]),
            .segment("NTE", min: 0, max: nil),
        ]
        let result = StructureMatcher.lint(elements)
        #expect(!result.isDeterministic)
        #expect(result.conflicts == [overlap(["OBSERVATION", "NTE"], ["NTE"])])
        #expect(result.exempt.isEmpty)
    }

    @Test("The pre-v2.5 shape OBR {[NTE]} {[OBX] {[NTE]}} fails")
    func preV25Shape() {
        // Top NTE against the sibling group's FIRST {OBX, NTE}: a conflict.
        // OBX is optional but not repeating, so its overlap with the group's
        // own re-entry is not exempt. The inner NTE repeats and overlaps only
        // the unbounded enclosing group's re-entry: exempt.
        let elements: [StructureElement] = [
            .segment("OBR", min: 1, max: 1),
            .segment("NTE", min: 0, max: nil),
            .group("OBSERVATION", min: 0, max: nil, elements: [
                .segment("OBX", min: 0, max: 1),
                .segment("NTE", min: 0, max: nil),
            ]),
        ]
        let result = StructureMatcher.lint(elements)
        #expect(result.conflicts == [overlap(["NTE"], ["NTE"]), overlap(["OBSERVATION", "OBX"], ["OBX"])])
        #expect(result.exempt == [overlap(["OBSERVATION", "NTE"], ["NTE"], via: "OBSERVATION")])
    }

    @Test("The exemption needs an unbounded enclosing group: a finite maximum fails")
    func finiteEnclosingGroup() {
        let elements: [StructureElement] = [
            .segment("MSH", min: 1, max: 1),
            .group("P", min: 1, max: 2, elements: [
                .segment("H", min: 0, max: 1),
                .group("O", min: 1, max: nil, elements: [.segment("A", min: 0, max: 1), .segment("B", min: 1, max: 1)]),
            ]),
        ]
        #expect(StructureMatcher.lint(elements).conflicts == [overlap(["P", "O"], ["A", "B"])])
    }

    @Test("FOLLOW looks past a nullable required group")
    func nullableGroupInFollow() {
        let elements: [StructureElement] = [
            .segment("MSH", min: 1, max: 1),
            .segment("X", min: 0, max: nil),
            .group("G", min: 1, max: 1, elements: [.segment("Y", min: 0, max: 1)]),
            .segment("X", min: 1, max: 1),
        ]
        #expect(StructureMatcher.lint(elements).conflicts == [overlap(["X"], ["X"])])
    }
}
