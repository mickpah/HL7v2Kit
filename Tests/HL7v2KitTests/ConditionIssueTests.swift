// ConditionIssueTests.swift
// 3.31.0 (G8): SegmentGrammar.conditionIssues() lists each condition atom the condition language
// cannot read, so a caller can lint a grammar it builds; such an atom never fires.

import Testing
import HL7v2Kit

@Suite("Condition issues")
struct ConditionIssueTests {
    static func field(_ index: Int, condition: String? = nil, prohibitedWhen: String? = nil,
                      additional: [String] = []) -> FieldGrammar {
        FieldGrammar(index: index, name: "Field \(index)", dataType: "ST", optionality: .conditional,
                     repeatability: .single, condition: condition, prohibitedWhen: prohibitedWhen,
                     additionalProhibitions: additional.map { FieldProhibition(condition: $0, severity: .error) },
                     maxRepetitions: nil)
    }

    static func zau(_ fields: [FieldGrammar]) -> SegmentGrammar {
        SegmentGrammar(segmentID: "ZAU", version: "2.5.1", fields: fields)
    }

    @Test("Each parse failure has its reason", arguments: [
        ("ZAU-3", ConditionIssue.Reason.missingPredicate),
        ("ZAU-3 isPopulated", .malformedPredicate),
        ("ZAU-3 = A B", .malformedPredicate),
        ("anyRepeat(ZAU3) populated", .malformedFieldReference),
        ("ZAU3 populated", .unknownReferent),
    ])
    func reasons(_ row: (atom: String, reason: ConditionIssue.Reason)) {
        let issues = Self.zau([Self.field(2, condition: row.atom)]).conditionIssues()
        #expect(issues == [ConditionIssue(fieldIndex: 2, source: .condition, atom: row.atom, reason: row.reason)])
    }

    @Test("Each source is named, an additional prohibition by its index, in field and atom order")
    func sources() {
        let grammar = Self.zau([
            Self.field(1, condition: "ZAU-2 populated", prohibitedWhen: "ZAU-3 bogus",
                       additional: ["ZAU-4 empty", "ZAU-5"]),
            Self.field(3, condition: "ZAU-1 populated AND ZAU-2 nope OR zz populated"),
        ])
        #expect(grammar.conditionIssues() == [
            ConditionIssue(fieldIndex: 1, source: .prohibitedWhen, atom: "ZAU-3 bogus", reason: .malformedPredicate),
            ConditionIssue(fieldIndex: 1, source: .additionalProhibition(index: 1), atom: "ZAU-5",
                           reason: .missingPredicate),
            ConditionIssue(fieldIndex: 3, source: .condition, atom: "ZAU-2 nope", reason: .malformedPredicate),
            ConditionIssue(fieldIndex: 3, source: .condition, atom: "zz populated", reason: .unknownReferent),
        ])
    }

    @Test("A grammar whose conditions all parse, or that has none, returns no issue")
    func cleanGrammar() {
        let clean = Self.zau([
            Self.field(1, condition: "ZAU-2 populated AND messageCode in (ADT, ORU) OR PV1 present",
                       prohibitedWhen: "anyRepeat(ZAU-3) = X", additional: ["ZAU-4.1 != Y"]),
            Self.field(2),
            Self.field(3, condition: ""),
        ])
        #expect(clean.conditionIssues().isEmpty)
    }

    @Test("Every shipped grammar's conditions parse")
    func shippedGrammarsClean() {
        let tables = [SegmentGrammarTable.v2_3, SegmentGrammarTable.v2_3_1, SegmentGrammarTable.v2_4,
                      SegmentGrammarTable.v2_5_1, SegmentGrammarTable.v2_6, SegmentGrammarTable.v2_7_1,
                      SegmentGrammarTable.v2_8_2]
        let issues = tables.flatMap(\.values).flatMap { $0.conditionIssues() }
        #expect(issues.isEmpty, "\(issues.prefix(5))")
    }

    @Test("A ZSegmentGrammar's grammar is linted: the misspelt condition never fires, the corrected one does",
          arguments: [("ZAU-1 = A AND ZAU-1 popluated", false), ("ZAU-1 = A AND ZAU-1 populated", true)])
    func zSegmentGrammar(_ row: (condition: String, fires: Bool)) throws {
        let grammar = ZSegmentGrammar(Self.zau([
            FieldGrammar(index: 1, name: "Code", dataType: "ST", optionality: .optional, repeatability: .single),
            Self.field(2, condition: row.condition),
        ]))
        let expected = row.fires ? [] : [ConditionIssue(fieldIndex: 2, source: .condition, atom: "ZAU-1 popluated",
                                                        reason: .malformedPredicate)]
        #expect(grammar.grammar.conditionIssues() == expected)
        var options = ValidationOptions.default
        options.zSegmentGrammars = [grammar]
        let message = try Parser().parse(TestWires.adt("PID|1", "ZAU|A"))
        let missing = Validator(options: options).validate(message).issues.filter { $0.code == .conditionalFieldMissing }
        #expect(missing.map(\.location.pathDescription) == (row.fires ? ["ZAU[1]-2"] : []))
    }
}
