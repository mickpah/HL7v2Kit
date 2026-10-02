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

    @Test("P6-6 length settings are mutable IssueSeverity? properties defaulting to .warning")
    func lengthSeverities() {
        let maximum: WritableKeyPath<ValidationOptions, IssueSeverity?> = \.fieldLengthSeverity
        let normative: WritableKeyPath<ValidationOptions, IssueSeverity?> = \.normativeLengthSeverity
        #expect(ValidationOptions.default[keyPath: maximum] == .warning)
        #expect(ValidationOptions.default[keyPath: normative] == .warning)
        #expect(ValidationOptions.strict[keyPath: normative] == .warning)
        #expect(ValidationOptions.lenient[keyPath: maximum] == nil)
        #expect(ValidationOptions.lenient[keyPath: normative] == nil)
    }

    @Test("IssueCode.fieldLengthOutOfRange keeps its (length:actual:) payload")
    func fieldLengthIssueCode() {
        let make: (String, Int) -> IssueCode = IssueCode.fieldLengthOutOfRange(length:actual:)
        #expect(make("20", 21) == .fieldLengthOutOfRange(length: "20", actual: 21))
    }

    @Test("P6-13 extra-component setting and issue code are additive")
    func extraComponents() {
        let severity: WritableKeyPath<ValidationOptions, IssueSeverity?> = \.extraComponentsSeverity
        #expect(ValidationOptions.default[keyPath: severity] == .warning)
        #expect(ValidationOptions.strict[keyPath: severity] == .warning)
        #expect(ValidationOptions.lenient[keyPath: severity] == nil)
        let code: IssueCode = .extraComponentsInPrimitiveField
        #expect(code != .fieldNotSupported)
        let composite: IssueCode = .extraComponentsInCompositeField
        #expect(composite != code)
    }

    @Test("P6-7 value-format setting and issue code are additive")
    func valueFormat() {
        let severity: WritableKeyPath<ValidationOptions, IssueSeverity?> = \.valueFormatSeverity
        #expect(ValidationOptions.default[keyPath: severity] == .warning)
        #expect(ValidationOptions.strict[keyPath: severity] == .warning)
        #expect(ValidationOptions.lenient[keyPath: severity] == nil)
        let make: (String) -> IssueCode = IssueCode.valueFormatInvalid(dataType:)
        #expect(make("NM") == .valueFormatInvalid(dataType: "NM"))
    }

    @Test("P6-4 repetition-bound severity is a mutable IssueSeverity? property defaulting to .warning")
    func repetitionBoundSeverity() {
        let severity: WritableKeyPath<ValidationOptions, IssueSeverity?> = \.repetitionBoundSeverity
        #expect(ValidationOptions.default[keyPath: severity] == .warning)
        #expect(ValidationOptions.strict[keyPath: severity] == .warning)
        #expect(ValidationOptions.lenient[keyPath: severity] == nil)
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

    @Test("FieldGrammar.init additionalProhibitions: is a separate overload")
    func fieldGrammarAdditionalProhibitionsInit() {
        let rule = FieldProhibition(condition: "RXR-2.3 = HL70163", severity: .warning)
        #expect(rule.condition == "RXR-2.3 = HL70163" && rule.severity == .warning)

        let make: (Int, String, String, FieldOptionality, FieldRepeatability, String?, String?, Bool, String?, String?, Bool, IssueSeverity, [FieldProhibition]) -> FieldGrammar =
            FieldGrammar.init(index:name:dataType:optionality:repeatability:condition:prohibitedWhen:variableColumns:table:length:tableOpen:prohibitedSeverity:additionalProhibitions:)
        let rxr6 = make(6, "n", "CWE", .optional, .single, nil, "RXR-2 empty", false, nil, nil, false, .error, [rule])
        #expect(rxr6.additionalProhibitions == [rule] && rxr6.prohibitedSeverity == .error && !rxr6.tableOpen)
        #expect(rxr6.maxRepetitions == nil)
    }

    // Deliberate pin of new, unreleased API (P6-4): maxRepetitions: is its own overload,
    // after the shared tail (tableOpen, prohibitedSeverity, additionalProhibitions).
    @Test("FieldGrammar.init maxRepetitions: is a separate overload")
    func fieldGrammarMaxRepetitionsInit() {
        let make: (Int, String, String, FieldOptionality, FieldRepeatability, String?, String?, Bool, String?, String?, Bool, IssueSeverity, [FieldProhibition], Int?) -> FieldGrammar =
            FieldGrammar.init(index:name:dataType:optionality:repeatability:condition:prohibitedWhen:variableColumns:table:length:tableOpen:prohibitedSeverity:additionalProhibitions:maxRepetitions:)
        let obr17 = make(17, "n", "XTN", .optional, .multiple, nil, nil, false, nil, nil, false, .error, [], 2)
        #expect(obr17.maxRepetitions == 2 && obr17.additionalProhibitions.isEmpty)

        let bounded = FieldGrammar(index: 18, name: "n", dataType: "ID", optionality: .optional,
                                   repeatability: .multiple, maxRepetitions: 3)
        #expect(bounded.maxRepetitions == 3 && !bounded.tableOpen && bounded.prohibitedSeverity == .error)
        let released = FieldGrammar(index: 3, name: "n", dataType: "CX", optionality: .required, repeatability: .multiple)
        #expect(released.maxRepetitions == nil)
    }

    // Deliberate pin of new, unreleased API (P4-21 / P4-26): FieldProhibition has one
    // public initialiser, with `permitsNull` defaulted to false.
    @Test("FieldProhibition has one init(condition:severity:permitsNull:), permitsNull defaulting to false")
    func fieldProhibitionInit() {
        let make: (String, IssueSeverity, Bool) -> FieldProhibition = FieldProhibition.init(condition:severity:permitsNull:)
        let rule = make("OBX-11 = O", .error, true)
        #expect(rule.condition == "OBX-11 = O" && rule.severity == .error && rule.permitsNull)
        let plain = FieldProhibition(condition: "OBX-11 = O", severity: .error)
        #expect(!plain.permitsNull)
        #expect(rule != plain)
    }

    // Deliberate pin of new, unreleased API (P5-5): the field-local composite lookup is an
    // additive static function beside grammar(_:version:), which keeps its own signature.
    @Test("DataTypeGrammarTable.grammar(segment:field:version:) is additive beside grammar(_:version:)")
    func fieldLocalGrammarLookup() {
        let byField: (String, Int, Version) -> DataTypeGrammar? = DataTypeGrammarTable.grammar(segment:field:version:)
        let byType: (String, Version) -> DataTypeGrammar? = DataTypeGrammarTable.grammar(_:version:)
        #expect(byField("IN3", 20, .v2_4)?.dataType == "CM")
        #expect(byType("CX", .v2_5_1)?.dataType == "CX")
    }

    // Deliberate pin of new, unreleased API (P9-2): additive access helpers.
    @Test("CompositeView.component(_:as:), viewed(as:) and TypedSegment.repetitions(_:) keep their signatures")
    func accessHelpers() {
        let sub: (CX) -> (Int, HD.Type) -> HD? = { cx in { cx.component($0, as: $1) } }
        let view: (CX) -> (EI.Type) -> EI = { cx in { cx.viewed(as: $0) } }
        let reps: (PID) -> (Int) -> [Field] = { pid in { pid.repetitions($0) } }
        let cx = CX(field: Field(repetitions: [Repetition(components: [Component(subcomponents: [Subcomponent("1")])])]))
        #expect(sub(cx)(1, HD.self)?.namespaceID == "1")
        #expect(view(cx)(EI.self).field == cx.field)
        #expect(reps(PID(fields: [Field(repetitions: [])]))(3).isEmpty)
    }
}
