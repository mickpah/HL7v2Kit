// ComponentConditionTermTests.swift
// Coding-system version ID task 1: the component-condition language's value terms.
// `<n> hl7Table` is HL7 and four digits (Table 0396 HL7nnnn); `<n> userTable` is such a value
// whose table is user-defined; `NOT` negates one atom and binds tighter than AND.

import Testing
@testable import HL7v2Kit

@Suite("Component conditions: value terms")
struct ComponentConditionTermTests {
    static func holds(_ expression: String, _ values: [Int: String], kinds: [String: HL7Table.Kind] = [:]) -> Bool {
        ComponentCondition.holds(expression, populated: { !(values[$0] ?? "").isEmpty },
                                 value: { values[$0] }, tableKind: { kinds[$0] })
    }

    static let newer = "3 populated AND (NOT 3 hl7Table OR 3 userTable)"
    static let older = "3 populated AND NOT 3 hl7Table"
    static let kinds: [String: HL7Table.Kind] = ["0001": .userDefined, "0002": .hl7]

    @Test("hl7Table is HL7 and four ASCII digits, exactly", arguments: [
        ("HL70001", true), ("HL7", false), ("hl70001", false), ("HL700012", false), ("HL7000A", false),
        ("XHL70001", false), ("LN", false), ("", false),
    ] as [(value: String, expected: Bool)])
    func hl7Table(_ row: (value: String, expected: Bool)) {
        #expect(Self.holds("3 hl7Table", [3: row.value]) == row.expected, "\(row.value)")
        #expect(ComponentCondition.hl7TableNumber(row.value) == (row.expected ? String(row.value.dropFirst(3)) : nil))
    }

    @Test("A component with no single value (subcomponents) is not HL7nnnn")
    func noSingleValue() {
        #expect(!ComponentCondition.holds("3 hl7Table", populated: { _ in true }, value: { _ in nil }))
    }

    @Test("userTable needs HL7nnnn and a user-defined kind; an unlisted table is false")
    func userTable() {
        #expect(Self.holds("3 userTable", [3: "HL70001"], kinds: Self.kinds))
        #expect(!Self.holds("3 userTable", [3: "HL70002"], kinds: Self.kinds))
        #expect(!Self.holds("3 userTable", [3: "HL79999"], kinds: Self.kinds))
        #expect(!Self.holds("3 userTable", [3: "LN"], kinds: Self.kinds))
    }

    @Test("NOT negates one atom and binds tighter than AND")
    func notPrecedence() {
        // (NOT 3 hl7Table) AND 4 populated: false when 4 is empty; NOT over the whole AND would be true.
        #expect(!Self.holds("NOT 3 hl7Table AND 4 populated", [3: "LN"]))
        #expect(Self.holds("NOT 3 hl7Table AND 4 populated", [3: "LN", 4: "x"]))
        #expect(Self.holds("NOT (3 hl7Table AND 4 populated)", [3: "HL70001"]))
        #expect(!Self.holds("NOT NOT 3 hl7Table", [3: "LN"]))
    }

    @Test("The newer wording: other than HL7nnnn, or a user-defined table", arguments: [
        ("LN", true), ("99ABC", true), ("HL70001", true), ("HL70002", false), ("HL79999", false), ("", false),
    ] as [(value: String, expected: Bool)])
    func newerWording(_ row: (value: String, expected: Bool)) {
        #expect(Self.holds(Self.newer, [3: row.value], kinds: Self.kinds) == row.expected, "\(row.value)")
    }

    @Test("The older wording: any system other than an HL7 coding system", arguments: [
        ("LN", true), ("HL70001", false), ("HL70002", false), ("HL79999", false), ("", false),
    ] as [(value: String, expected: Bool)])
    func olderWording(_ row: (value: String, expected: Bool)) {
        #expect(Self.holds(Self.older, [3: row.value], kinds: Self.kinds) == row.expected, "\(row.value)")
    }

    @Test("parses accepts the new terms; malformed text is false")
    func parsing() {
        #expect(ComponentCondition.parses(Self.newer) && ComponentCondition.parses(Self.older))
        for malformed in ["NOT", "3 hl7Table extra", "3 userTables", "NOT AND 3 populated", "3 hl7Table OR"] {
            #expect(!ComponentCondition.parses(malformed), "\(malformed)")
            #expect(!Self.holds(malformed, [3: "LN"]), "\(malformed)")
        }
    }

    @Test("Without values the value terms are false, so existing callers are unchanged")
    func defaultsKnowNothing() {
        #expect(!ComponentCondition.holds("3 hl7Table", populated: { _ in true }))
        #expect(!ComponentCondition.holds("3 userTable", populated: { _ in true }))
        #expect(ComponentCondition.holds("3 populated AND repeated", populated: { _ in true }, repeated: true))
    }
}
