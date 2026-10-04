// StructureExactMatchFlagTests.swift
// P8b-12 (G15): the codegen lints every structure it emits and records the
// result as `requiresExactMatch`, so the Validator never lints a message.
// The re-lint of every committed structure (flag equals lint) moved to
// StructureGuardTests (P8b-7, guard 1); this suite keeps the synthetic default.

import Testing
@testable import HL7v2Kit

@Suite("Structure exact-match flag")
struct StructureExactMatchFlagTests {

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
