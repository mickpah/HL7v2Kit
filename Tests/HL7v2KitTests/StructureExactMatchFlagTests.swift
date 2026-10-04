// StructureExactMatchFlagTests.swift
// P8b-12 (G15): the codegen lints every structure it emits and records the
// result as `requiresExactMatch`, so the Validator never lints a message.
// This suite re-lints every committed structure and asserts the flag equals
// the lint result, so the codegen's lint cannot drift from the library's.

import Testing
@testable import HL7v2Kit

@Suite("Structure exact-match flag")
struct StructureExactMatchFlagTests {

    @Test("Every generated structure's flag equals the determinism lint result")
    func flagMatchesLint() {
        var checked = 0
        for version in Version.allCases {
            for (id, structure) in MessageStructureTable.structures(for: version) {
                let fails = !StructureMatcher.lint(structure.elements).isDeterministic
                #expect(structure.requiresExactMatch == fails, "\(version.rawValue) \(id)")
                checked += 1
            }
        }
        #expect(checked > 0)
    }

    @Test("A structure built without the flag takes it from the lint")
    func defaultFromLint() {
        func flag(_ elements: [StructureElement]) -> Bool {
            MessageStructure(id: "T", version: "2.5.1", triggers: [], citation: "test", elements: elements).requiresExactMatch
        }
        #expect(flag(StructureShapes.counterExample))
        #expect(flag(StructureShapes.preV25))
        #expect(!flag(StructureShapes.allOptionalGroup))
        #expect(!flag(StructureShapes.simpleChoice))
    }
}
