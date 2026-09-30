// SignatureCompatibilityTests.swift
// ADR-014: public initialisers keep their released signatures. Each test names the
// initialiser by its full argument-label list and function type, so it fails to compile
// if a parameter is added to, removed from or reordered in that exact signature.

import Testing
import HL7v2Kit

@Suite("Public initialiser signatures (ADR-014)")
struct SignatureCompatibilityTests {

    @Test("ValidationOptions.init keeps its six-parameter signature")
    func validationOptionsInit() {
        let make: (ZSegmentPolicy, Bool, Bool, Bool, Bool, Bool) -> ValidationOptions =
            ValidationOptions.init(zSegmentPolicy:checkRequiredFields:checkConditionalFields:checkComponentGrammar:checkCardinality:warnDeprecatedFields:)
        let options = make(.ignore, true, true, true, true, true)
        #expect(options.localTableExtensions.isEmpty, "set by mutation, not an init parameter")
    }

    @Test("HL7Table.init keeps its five-parameter signature; patterns: is a separate overload")
    func hl7TableInit() {
        let entries = [HL7Table.Entry(code: "A", description: "a")]
        let make: (String, String, HL7Table.Kind, Bool, [HL7Table.Entry]) -> HL7Table =
            HL7Table.init(number:name:kind:permitsLocalExtensions:entries:)
        let plain = make("0001", "n", .hl7, false, entries)
        #expect(plain.isClosed && plain.patterns.isEmpty)

        let makeWithPatterns: (String, String, HL7Table.Kind, Bool, [HL7Table.Entry], [HL7Table.CodePattern]) -> HL7Table =
            HL7Table.init(number:name:kind:permitsLocalExtensions:entries:patterns:)
        let pattern = HL7Table.CodePattern(code: "NNxxx", description: "d", regex: "^NN[A-Z]{3}$")
        #expect(makeWithPatterns("0203", "n", .hl7, false, entries, [pattern]).contains("NNAUS"))
    }

    @Test("FieldGrammar.init keeps its ten-parameter signature; tableOpen: and prohibitedSeverity: are separate overloads")
    func fieldGrammarInit() {
        let make: (Int, String, String, FieldOptionality, FieldRepeatability, String?, String?, Bool, String?, String?) -> FieldGrammar =
            FieldGrammar.init(index:name:dataType:optionality:repeatability:condition:prohibitedWhen:variableColumns:table:length:)
        let plain = make(1, "n", "ID", .optional, .single, nil, nil, false, "0136", nil)
        #expect(!plain.tableOpen)
        #expect(plain.prohibitedSeverity == .error)

        let makeOpen: (Int, String, String, FieldOptionality, FieldRepeatability, String?, String?, Bool, String?, String?, Bool) -> FieldGrammar =
            FieldGrammar.init(index:name:dataType:optionality:repeatability:condition:prohibitedWhen:variableColumns:table:length:tableOpen:)
        #expect(makeOpen(1, "n", "ID", .optional, .single, nil, nil, false, "0136", nil, true).tableOpen)
        #expect(makeOpen(1, "n", "ID", .optional, .single, nil, "X empty", false, nil, nil, false).prohibitedSeverity == .error)

        let makeSeverity: (Int, String, String, FieldOptionality, FieldRepeatability, String?, String?, Bool, String?, String?, Bool, IssueSeverity) -> FieldGrammar =
            FieldGrammar.init(index:name:dataType:optionality:repeatability:condition:prohibitedWhen:variableColumns:table:length:tableOpen:prohibitedSeverity:)
        let advisory = makeSeverity(7, "n", "ID", .conditional, .single, nil, "TQ2-2 != C", false, nil, nil, false, .warning)
        #expect(advisory.prohibitedSeverity == .warning && !advisory.tableOpen)
        #expect(advisory.additionalProhibitions.isEmpty)
    }

    @Test("FieldGrammar.init additionalProhibitions: is a separate overload; FieldProhibition.init keeps two parameters")
    func fieldGrammarAdditionalProhibitionsInit() {
        let makeRule: (String, IssueSeverity) -> FieldProhibition = FieldProhibition.init(condition:severity:)
        let rule = makeRule("RXR-2.3 = HL70163", .warning)
        #expect(rule.condition == "RXR-2.3 = HL70163" && rule.severity == .warning)

        let make: (Int, String, String, FieldOptionality, FieldRepeatability, String?, String?, Bool, String?, String?, Bool, IssueSeverity, [FieldProhibition]) -> FieldGrammar =
            FieldGrammar.init(index:name:dataType:optionality:repeatability:condition:prohibitedWhen:variableColumns:table:length:tableOpen:prohibitedSeverity:additionalProhibitions:)
        let rxr6 = make(6, "n", "CWE", .optional, .single, nil, "RXR-2 empty", false, nil, nil, false, .error, [rule])
        #expect(rxr6.additionalProhibitions == [rule] && rxr6.prohibitedSeverity == .error && !rxr6.tableOpen)
    }
}
