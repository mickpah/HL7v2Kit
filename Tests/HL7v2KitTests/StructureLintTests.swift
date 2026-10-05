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

    // P8b-9: lint-failing structures are committed from v2.5.1 on, flagged for the
    // exact matcher (P8b-12); the three pilots still pass the lint.
    @Test("Every modelled structure passes the lint or is flagged for the exact matcher")
    func modelledStructuresAreDeterministic() {
        for version in Version.allCases {
            for structure in MessageStructureTable.structures(for: version).values {
                #expect(StructureMatcher.lint(structure.elements).isDeterministic == !structure.requiresExactMatch,
                        "\(version.rawValue) \(structure.id)")
            }
        }
        for id in ["ACK", "ADT_A01", "ORU_R01"] {
            let pilot = MessageStructureTable.structures(for: .v2_5_1)[id]
            #expect(pilot.map { StructureMatcher.lint($0.elements).isDeterministic } == true, "\(id)")
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
        let result = StructureMatcher.lint(StructureShapes.trailingThenSibling)
        #expect(!result.isDeterministic)
        #expect(result.conflicts == [overlap(["OBSERVATION", "NTE"], ["NTE"])])
        #expect(result.exempt.isEmpty)
    }

    @Test("The pre-v2.5 shape OBR {[NTE]} {[OBX] {[NTE]}} fails on the sibling NTE only")
    func preV25Shape() {
        // Top NTE against the sibling group's FIRST {OBX, NTE}: a conflict.
        // Inside OBSERVATION, OBX and NTE overlap only the re-entry of the
        // unbounded group itself with an empty prefix: exempt (ruling 3).
        let result = StructureMatcher.lint(StructureShapes.preV25)
        #expect(result.conflicts == [overlap(["NTE"], ["NTE"])])
        #expect(result.exempt == [
            overlap(["OBSERVATION", "OBX"], ["OBX"], via: "OBSERVATION"),
            overlap(["OBSERVATION", "NTE"], ["NTE"], via: "OBSERVATION"),
        ])
    }

    @Test("{G: [X] [{N}]}: a non-repeating optional first child is exempt (ruling 3)")
    func allOptionalGroup() {
        let result = StructureMatcher.lint(StructureShapes.allOptionalGroup)
        #expect(result.conflicts.isEmpty)
        #expect(result.exempt == [overlap(["G", "X"], ["X"], via: "G"), overlap(["G", "N"], ["N"], via: "G")])
    }

    @Test("{G: [A] [X] [{N}]}: a nullable prefix that cannot begin with the segment keeps the exemption")
    func nullablePrefix() {
        let result = StructureMatcher.lint(StructureShapes.nullablePrefix)
        #expect(result.conflicts.isEmpty)
        #expect(result.exempt.map(\.path) == [["G", "A"], ["G", "X"], ["G", "N"]])
    }

    @Test("Reviewer's counter-example {G: X {Q: X Y}}: a required prefix voids the exemption")
    func counterExample() {
        let result = StructureMatcher.lint(StructureShapes.counterExample)
        #expect(result.conflicts == [overlap(["G", "Q"], ["X"])])
        #expect(result.exempt.isEmpty)
    }

    @Test("{G: [X] {Q: X Y}}: a nullable prefix that can begin with the segment voids the exemption")
    func prefixBeginsWithSegment() {
        let result = StructureMatcher.lint(StructureShapes.prefixBeginsWithSegment)
        #expect(result.conflicts == [overlap(["G", "X"], ["X"]), overlap(["G", "Q"], ["X"])])
        #expect(result.exempt.isEmpty)
    }

    @Test("The exemption needs an unbounded enclosing group: a finite maximum fails")
    func finiteEnclosingGroup() {
        #expect(StructureMatcher.lint(StructureShapes.finiteEnclosing).conflicts == [overlap(["P", "O"], ["A", "B"])])
    }

    @Test("FOLLOW looks past a nullable required group")
    func nullableGroupInFollow() {
        #expect(StructureMatcher.lint(StructureShapes.nullableFollow).conflicts == [overlap(["X"], ["X"])])
    }

    // MARK: - Choices (P8b-6)

    @Test("<A|B> with disjoint alternatives passes")
    func simpleChoice() {
        let result = StructureMatcher.lint(StructureShapes.simpleChoice)
        #expect(result.conflicts.isEmpty)
        #expect(result.exempt.isEmpty)
    }

    @Test("[{<A|{B}>}]: B against the choice's own re-entry is exempt, like a group's")
    func repeatingChoice() {
        let result = StructureMatcher.lint(StructureShapes.repeatingChoice)
        #expect(result.conflicts.isEmpty)
        #expect(result.exempt == [overlap(["<A|B>", "B"], ["B"], via: "<A|B>")])
    }

    @Test("A named choice of groups: the trailing N meets only the choice's re-entry, which N cannot begin")
    func namedChoice() {
        let result = StructureMatcher.lint(StructureShapes.namedChoice)
        #expect(result.conflicts.isEmpty)
        #expect(result.exempt.isEmpty)
    }

    @Test("Two alternatives that can begin with the same segment are a conflict")
    func overlappingChoice() {
        let result = StructureMatcher.lint(StructureShapes.overlappingChoice)
        #expect(result.conflicts == [overlap(["<A|G>"], ["A"])])
    }

    @Test("A nullable alternative is a conflict: the one-pass matcher cannot attribute an empty occurrence")
    func optionalAlternatives() {
        let result = StructureMatcher.lint(StructureShapes.optionalAlternatives)
        #expect(!result.isDeterministic)
        #expect(result.conflicts.contains(overlap(["<A|B>", "A"], ["A"])))
        #expect(result.conflicts.contains(overlap(["<A|B>", "B"], ["B"])))
    }

    @Test("An optional choice is checked against its FOLLOW like any element")
    func choiceThenSibling() {
        #expect(StructureMatcher.lint(StructureShapes.choiceThenSibling).conflicts == [overlap(["<A|B>"], ["A"])])
    }

    @Test("A required group of optional children followed by a required segment passes")
    func nullableGroup() {
        let result = StructureMatcher.lint(StructureShapes.nullableGroup)
        #expect(result.isDeterministic)
        #expect(result.exempt.isEmpty)
    }
}
