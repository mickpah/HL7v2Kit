// SignatureCompatibilityTests.swift
// ADR-014: public initialisers keep their released signatures. Each test names the
// initialiser by its full argument-label list and function type, so it fails to compile
// if a parameter is added to, removed from or reordered in that exact signature.

import Testing
import HL7v2Kit

@Suite("Public initialiser signatures (ADR-014)")
struct SignatureCompatibilityTests {

    @Test("P10-6 Version.v2_7_1 is additive: wire value 2.7.1, its own grammar version")
    func version271Case() {
        let version: Version = .v2_7_1
        #expect(version.rawValue == "2.7.1")
        #expect(Version(wireValue: "2.7.1") == .v2_7_1)
        #expect(version.grammarVersion == .v2_7_1)
        #expect(Version.allCases.contains(.v2_7_1))
    }

    @Test("P10-6 Version.v2_7 is additive: wire value 2.7, validated as v2.7.1 (G11)")
    func version27Case() {
        let version: Version = .v2_7
        #expect(version.rawValue == "2.7")
        #expect(Version(wireValue: "2.7") == .v2_7)
        #expect(version.grammarVersion == .v2_7_1)
        #expect(Version.allCases.contains(.v2_7))
    }

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

    @Test("S1-1 IssueCode.componentLengthOutOfRange is additive with a (length:actual:) payload")
    func componentLengthIssueCode() {
        let make: (String, Int) -> IssueCode = IssueCode.componentLengthOutOfRange(length:actual:)
        #expect(make("1..6", 7) == .componentLengthOutOfRange(length: "1..6", actual: 7))
        #expect(make("1..6", 7) != .fieldLengthOutOfRange(length: "1..6", actual: 7))
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

    @Test("P8-5 message-structure setting and issue codes are additive; presets per G2 (b) since P8b-18")
    func messageStructure() {
        let severity: WritableKeyPath<ValidationOptions, IssueSeverity?> = \.messageStructureSeverity
        #expect(ValidationOptions.default[keyPath: severity] == .warning)
        #expect(ValidationOptions.strict[keyPath: severity] == .error)
        #expect(ValidationOptions.lenient[keyPath: severity] == nil)
        let missing: (String, String, String?) -> IssueCode = IssueCode.messageStructureSegmentMissing(structure:segmentID:group:)
        let unexpected: (String, String) -> IssueCode = IssueCode.messageStructureSegmentUnexpected(structure:segmentID:)
        let mismatch: (String, String) -> IssueCode = IssueCode.messageStructureMismatch(declared:trigger:)
        let notModelled: (String) -> IssueCode = IssueCode.messageStructureNotModelled(structure:)
        #expect(missing("ADT_A01", "EVN", nil) == .messageStructureSegmentMissing(structure: "ADT_A01", segmentID: "EVN", group: nil))
        #expect(unexpected("ADT_A01", "PID") == .messageStructureSegmentUnexpected(structure: "ADT_A01", segmentID: "PID"))
        #expect(mismatch("ADT_A01", "ADT^A02") == .messageStructureMismatch(declared: "ADT_A01", trigger: "ADT^A02"))
        #expect(notModelled("SIU_S12") == .messageStructureNotModelled(structure: "SIU_S12"))
    }

    @Test("P8-7 acknowledgment builder: static method, Table 0008 codes and the additive BuilderError case")
    func acknowledgment() throws {
        let make: (Message, AcknowledgmentCode, String, String) throws -> Message =
            MessageBuilder.acknowledgment(to:code:messageControlID:dateTime:)
        #expect(AcknowledgmentCode.allCases.map(\.rawValue) == ["AA", "AE", "AR", "CA", "CE", "CR"])
        let error: BuilderError = .acknowledgedMessageControlIDMissing
        let original = try Parser().parse("MSH|^~\\&|A|B|C|D|20240101120000||ADT^A01^ADT_A01|M1|P|2.5.1")
        #expect(try make(original, .applicationAccept, "X1", "20240101120001")["MSA-2"] == "M1")
        let headerless = Message(version: .v2_5_1, encodingCharacters: .default, segments: [])
        #expect(throws: error) { try make(headerless, .applicationAccept, "X1", "20240101120001") }
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

    // Deliberate pin of new, unreleased API (P9-3): generated composite component
    // accessors, one per extended view. CompositeComponentTests pins every one of
    // them by key path; CompositeReleasedSurfaceTests pins the v3.13.0 surface.
    @Test("Generated composite component accessors keep their names and String? type")
    func generatedCompositeAccessors() {
        let cxPin: KeyPath<CX, String?> = \.securityCheckScheme
        let _: KeyPath<XPN, String?> = \.calledBy
        let _: KeyPath<XAD, String?> = \.addressIdentifier
        let _: KeyPath<XCN, String?> = \.securityCheckScheme
        let _: KeyPath<XTN, String?> = \.preferenceOrder
        let _: KeyPath<PL, String?> = \.assigningAuthorityForLocation
        let _: KeyPath<CWE, String?> = \.secondAltValueSetVersionID
        let _: KeyPath<CNE, String?> = \.codingSystemVersionID
        let _: KeyPath<XON, String?> = \.nameRepresentationCode
        let parts = (1...12).map { Component(subcomponents: [Subcomponent("c\($0)")]) }
        let cx = CX(field: Field(repetitions: [Repetition(components: parts)]))
        #expect(cx[keyPath: cxPin] == "c12")
    }

    // Deliberate pin of new, unreleased API (P8-3, ADR-019): the message structure
    // model and its lookups. MessageStructureTableTests pins the pilot data.
    // The memberwise init is internal (P8 final review): this file imports
    // HL7v2Kit without @testable, so it reads a generated structure instead.
    @Test("MessageStructure, StructureElement and MessageStructureTable keep their signatures")
    func messageStructureModel() throws {
        let segment: (String, Int, Int?) -> StructureElement = StructureElement.segment(_:min:max:)
        let group: (String, Int, Int?, [StructureElement]) -> StructureElement = StructureElement.group(_:min:max:elements:)
        let byID: (String, Version) -> MessageStructure? = MessageStructureTable.structure(_:version:)
        let byTrigger: (String, String, Version) -> [MessageStructure] =
            MessageStructureTable.structures(messageCode:triggerEvent:version:)
        let _: KeyPath<MessageStructure, String> = \.id
        let _: KeyPath<MessageStructure, String> = \.version
        let _: KeyPath<MessageStructure, [String]> = \.triggers
        let _: KeyPath<MessageStructure, String> = \.citation
        let _: KeyPath<MessageStructure, [StructureElement]> = \.elements
        let minimum: KeyPath<StructureElement, Int> = \.min
        let maximum: KeyPath<StructureElement, Int?> = \.max
        let element = group("G", 0, nil, [segment("PID", 1, 1)])
        let structure = try #require(byID("ACK", .v2_5_1))
        let accepts: (MessageStructure) -> (String, String) -> Bool = MessageStructure.accepts(messageCode:triggerEvent:)
        #expect(accepts(structure)("ACK", "A01"))
        #expect(!accepts(structure)("ADT", "A01"))
        #expect(element[keyPath: minimum] == 0 && element[keyPath: maximum] == nil)
        #expect(byID("ZZZ_Z01", .v2_5_1) == nil)
        #expect(byTrigger("ZZZ", "Z01", .v2_5_1).isEmpty)
    }

    // Deliberate pin of new, unreleased API (P8b-6, ADR-019 amendment): the choice
    // case of the open StructureElement enum and the tree walker that covers every
    // case, so a consumer never silently skips the segments inside a choice.
    @Test("StructureElement.choice, children and segmentIDs keep their signatures")
    func structureChoiceAndWalker() {
        let choice: (String?, Int, Int?, [StructureElement]) -> StructureElement =
            StructureElement.choice(_:min:max:alternatives:)
        let children: KeyPath<StructureElement, [StructureElement]> = \.children
        let segmentIDs: KeyPath<StructureElement, Set<String>> = \.segmentIDs
        let element = choice("RES", 0, nil, [
            .segment("AIS", min: 1, max: 1),
            .group("G", min: 1, max: 1, elements: [.segment("AIG", min: 1, max: 1)]),
        ])
        #expect(element[keyPath: children].count == 2)
        #expect(element[keyPath: segmentIDs] == ["AIS", "AIG"])
        #expect(element.min == 0 && element.max == nil)
    }
}
