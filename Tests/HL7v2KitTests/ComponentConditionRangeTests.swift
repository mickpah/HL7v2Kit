// ComponentConditionRangeTests.swift
// TXA-22 task 1: range terms in the component-condition language. `<a>-<b> populated` holds
// when any component from a to b is populated; `<a>-<b> empty` when none is.

import Testing
@testable import HL7v2Kit

@Suite("Component conditions: range terms")
struct ComponentConditionRangeTests {
    static func holds(_ expression: String, _ populated: Set<Int>) -> Bool {
        ComponentCondition.holds(expression, populated: { populated.contains($0) })
    }

    @Test("a-b populated is any member; a-b empty is none", arguments: [
        ("1-14 populated", Set([3]), true), ("1-14 populated", Set([15]), false), ("1-14 populated", Set<Int>(), false),
        ("16-26 populated", Set([26]), true), ("16-26 populated", Set([15]), false),
        ("1-14 empty", Set([15]), true), ("1-14 empty", Set([14]), false), ("5-5 populated", Set([5]), true),
    ] as [(expression: String, populated: Set<Int>, expected: Bool)])
    func range(_ row: (expression: String, populated: Set<Int>, expected: Bool)) {
        #expect(Self.holds(row.expression, row.populated) == row.expected, "\(row.expression) over \(row.populated.sorted())")
    }

    @Test("The TXA-22 conditions read as printed")
    func txa22() {
        let newer = "1-14 populated OR 16-26 populated"
        #expect(Self.holds(newer, [2]) && Self.holds(newer, [20]) && !Self.holds(newer, [15]) && !Self.holds(newer, []))
        #expect(Self.holds("1-10 populated", [10]) && !Self.holds("1-10 populated", [11, 16]))
    }

    @Test("Ranges combine with NOT, AND, OR and parentheses")
    func combined() {
        #expect(Self.holds("NOT 1-14 empty", [7]))
        #expect(!Self.holds("NOT 1-14 populated", [7]))
        #expect(Self.holds("15 populated AND (1-14 empty AND 16-26 empty)", [15]))
        #expect(!Self.holds("15 populated AND (1-14 empty AND 16-26 empty)", [15, 16]))
    }

    @Test("Malformed ranges are false and do not parse", arguments: [
        "5-3 populated", "0-2 populated", "1- populated", "-3 populated", "1-2-3 populated", "a-b populated",
        "1-14 hl7Table", "1-14",
    ])
    func malformed(_ expression: String) {
        #expect(!Self.holds(expression, Set(1...30)))
        #expect(!ComponentCondition.parses(expression))
    }

    @Test("parses accepts ranges; range(_:) reads a-b with 1 <= a <= b only")
    func parsesAndHelper() {
        #expect(ComponentCondition.parses("1-14 populated OR 16-26 populated"))
        #expect(ComponentCondition.parses("1-10 empty"))
        #expect(ComponentCondition.range("1-14") == 1...14)
        #expect(ComponentCondition.range("5-5") == 5...5)
        #expect(ComponentCondition.range("5-3") == nil)
        #expect(ComponentCondition.range("0-2") == nil)
        #expect(ComponentCondition.range("14") == nil)
    }
}
