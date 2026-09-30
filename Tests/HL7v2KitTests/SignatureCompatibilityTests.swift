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
}
