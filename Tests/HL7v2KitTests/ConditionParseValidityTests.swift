// ConditionParseValidityTests.swift
// P4-25: every condition string the package ships must parse. The evaluator
// fails safe on an unparseable predicate (it never fires), so a misspelt
// condition would pass codegen and the audit and then silently never trigger
// (requirement 4). These tests walk every grammar table and the AU profile and
// prove each condition parses under the evaluator's own grammar.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Condition parse validity (P4-25)")
struct ConditionParseValidityTests {

    private static let segmentTables: [(String, [String: SegmentGrammar])] = [
        ("2.3", SegmentGrammarTable.v2_3), ("2.3.1", SegmentGrammarTable.v2_3_1),
        ("2.4", SegmentGrammarTable.v2_4), ("2.5.1", SegmentGrammarTable.v2_5_1),
        ("2.6", SegmentGrammarTable.v2_6), ("2.8.2", SegmentGrammarTable.v2_8_2),
    ]

    /// Every non-empty condition in a field grammar, labelled for the failure message.
    private static func conditions(of field: FieldGrammar, label: String) -> [(String, String)] {
        var out: [(String, String)] = []
        if let c = field.condition { out.append(("\(label) condition", c)) }
        if let c = field.prohibitedWhen { out.append(("\(label) prohibitedWhen", c)) }
        for (i, rule) in field.additionalProhibitions.enumerated() {
            out.append(("\(label) additionalProhibitions[\(i)]", rule.condition))
        }
        return out
    }

    private static func conditions(of rule: SegmentCardinalityRule, label: String) -> [(String, String)] {
        [("\(label) predicate", rule.predicate)]
            + [rule.activationPredicate.map { ("\(label) activationPredicate", $0) },
               rule.applicableWhen.map { ("\(label) applicableWhen", $0) }].compactMap { $0 }
    }

    private static func failures(_ labelled: [(String, String)]) -> [String] {
        labelled.filter { !$0.1.isEmpty }.flatMap { label, condition in
            Validator.conditionParseErrors(condition).map { "\(label): '\(condition)': \($0)" }
        }
    }

    @Test("Every segment grammar condition parses, in all six versions")
    func segmentGrammarConditionsParse() {
        var labelled: [(String, String)] = []
        for (version, table) in Self.segmentTables {
            for (id, grammar) in table {
                for field in grammar.fields {
                    labelled += Self.conditions(of: field, label: "v\(version) \(id)-\(field.index)")
                }
                for (i, rule) in grammar.segmentCardinalityRules.enumerated() {
                    labelled += Self.conditions(of: rule, label: "v\(version) \(id) cardinality[\(i)]")
                }
            }
        }
        #expect(labelled.count > 100)
        let failed = Self.failures(labelled)
        #expect(failed.isEmpty, "\(failed.count) unparseable:\n\(failed.joined(separator: "\n"))")
    }

    @Test("Every datatype component condition parses, in all six versions")
    func componentConditionsParse() {
        var checked = 0
        var failed: [String] = []
        for version in Version.allCases {
            for (name, grammar) in DataTypeGrammarTable.grammars(for: version) {
                for component in grammar.components {
                    for condition in [component.condition, component.conformanceCondition].compactMap({ $0 }) {
                        checked += 1
                        if !ComponentCondition.parses(condition) {
                            failed.append("v\(version.rawValue) \(name).\(component.index): '\(condition)'")
                        }
                    }
                }
            }
        }
        #expect(checked > 30)
        #expect(failed.isEmpty, "\(failed.count) unparseable:\n\(failed.joined(separator: "\n"))")
    }

    @Test("Every AU profile condition parses")
    func auProfileConditionsParse() {
        let profile = Profile.auADRM2021
        var labelled: [(String, String?)] = []
        for o in profile.fieldOverrides {
            let label = "field override \(o.segmentID)-\(o.fieldIndex)"
            labelled.append((label, o.condition))
            labelled += o.componentValueSets.map { ("\(label) valueSet", $0.condition) }
            labelled += o.componentPatterns.map { ("\(label) pattern", $0.condition) }
            labelled += o.componentCorrespondences.map { ("\(label) correspondence", $0.condition) }
            labelled += o.prohibitions.map { ("\(label) prohibition", $0.condition) }
        }
        for o in profile.compositeOverrides {
            let label = "composite override \(o.dataType)"
            labelled.append((label, o.condition))
            labelled += o.requiredComponents.map { ("\(label) requiredComponent", $0.condition) }
            labelled += o.valueConditionals.map { ("\(label) valueConditional", $0.condition) }
            labelled += o.componentValueSets.map { ("\(label) valueSet", $0.condition) }
            labelled += o.componentPatterns.map { ("\(label) pattern", $0.condition) }
            labelled += o.componentCorrespondences.map { ("\(label) correspondence", $0.condition) }
        }
        var flat = labelled.compactMap { label, c in c.map { (label, $0) } }
        for (id, fields) in profile.grammarExtensions {
            for field in fields { flat += Self.conditions(of: field, label: "extension \(id)-\(field.index)") }
        }
        for (id, rules) in profile.cardinalityExtensions {
            for (i, rule) in rules.enumerated() {
                flat += Self.conditions(of: rule, label: "extension \(id) cardinality[\(i)]")
            }
        }
        flat += profile.uniquenessRules.compactMap { r in r.applicableWhen.map { ("uniqueness", $0) } }
        flat += profile.escapeProhibitions.compactMap { r in r.applicableWhen.map { ("escape prohibition", $0) } }
        flat += profile.subIDTrees.compactMap { r in r.applicableWhen.map { ("sub-ID tree", $0) } }
        #expect(flat.count > 20)
        let failed = Self.failures(flat)
        #expect(failed.isEmpty, "\(failed.count) unparseable:\n\(failed.joined(separator: "\n"))")
    }

    // MARK: - The parse-only entry point rejects what the evaluator cannot read

    @Test("Malformed conditions report parse errors", arguments: [
        "RXR-2.3 == HL70163",
        "PID-3 populatd",
        "messageCode in (ORU",
        "fooBar populated",
        "noRepeat(PID-3 = X",
        "anyRepeat(PID-3x) populated",
        "previousSegment(ORC).ORC populated",
        "PID-3",
        "PID-3 populated AND ",
        "SPM-12 > many",
        "messageCode in ()",
    ])
    func malformedConditionsReportErrors(condition: String) {
        #expect(!Validator.conditionParseErrors(condition).isEmpty)
    }

    @Test("Well-formed conditions of every production parse", arguments: [
        "PID-3 populated",
        "PID-3.4.1 empty",
        "OBR-25 = F",
        "OBR-25 != F",
        "messageCode in (ORU, OML)",
        "triggerEvent not in (A01,A04)",
        "messageStructure startsWith ADT",
        "messageCode not startsWith Z",
        "SHP-8 > 1",
        "ORC present",
        "OBX absent",
        "nextSegmentID(TQ2) = TQ1",
        "anyRepeat(PRD-1) = AP",
        "noRepeat(SPM-11) = G",
        "previousSegment(OBR).OBR-4 populated",
        "associatedSegment(ORC).ORC-1 = NW",
        "auPathologySender populated AND OBR-25 = F OR auNASHTransport populated",
    ])
    func wellFormedConditionsParse(condition: String) {
        #expect(Validator.conditionParseErrors(condition).isEmpty)
    }

    @Test("An empty condition is not checked")
    func emptyConditionNotChecked() {
        #expect(Validator.conditionParseErrors("").isEmpty)
    }

    @Test("An unreadable noRepeat predicate fails safe instead of holding")
    func noRepeatWithUnreadablePredicateFailsSafe() throws {
        let wire = "MSH|^~\\&|A|B|C|D|20260101||ADT^A01^ADT_A01|1|P|2.5.1\rPID|1||123~456"
        let message = try Parser().parse(wire)
        let pid = try #require(message.segments.firstIndex { $0.segmentID == "PID" })
        func fires(_ condition: String) -> Bool {
            Validator().conditionTriggers(condition, in: message.segments[pid], segmentIndex: pid,
                                          message: message, currentSegmentID: "PID")
        }
        #expect(fires("noRepeat(PID-3) = 789"))
        #expect(!fires("noRepeat(PID-3) == 789"))
    }

    @Test("Malformed component conditions are rejected")
    func malformedComponentConditions() {
        #expect(ComponentCondition.parses("5 populated OR (2 empty AND repeated)"))
        #expect(!ComponentCondition.parses("5 populatd"))
        #expect(!ComponentCondition.parses("(5 populated"))
        #expect(!ComponentCondition.parses("5 populated OR"))
    }
}
