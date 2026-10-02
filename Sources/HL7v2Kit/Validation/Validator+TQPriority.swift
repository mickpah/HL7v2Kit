// P5 final review: the TQ.6 Priority repeat on v2.3 and v2.3.1.

extension Validator {
    /// The repetitions the base-spec checks read for `field`: all of them, except on a
    /// single-repeat `TQ` field on v2.3 or v2.3.1, where only the first.
    ///
    /// v2.3 and v2.3.1 section 4.4.6 (Priority component) let TQ.6 repeat through the repeat
    /// delimiter inside the one TQ occurrence (`1^Q6H^^200001011200^^S~A^^^S`). The parser
    /// gives the repeat delimiter one meaning, a new field repetition, so on a field that
    /// may not repeat, repetitions 2 to n are read as the priority's continuation: they
    /// raise no `cardinalityExceeded` and no component, format, length or table check runs
    /// on them. Repetition 1 is validated as usual. v2.4 section 4.3.6 separates repeated
    /// priorities with a space, so v2.4 on is unaffected.
    ///
    /// Known limit (permanent-limitations-register.md section C): on those versions a
    /// genuinely wrong second repetition of such a field goes unreported.
    static func priorityContinuationTrimmed(
        _ field: Field,
        grammar: FieldGrammar,
        dataType: String,
        version: Version
    ) -> Field {
        guard field.repetitions.count > 1, dataType == "TQ", grammar.repeatability == .single,
              version == .v2_3 || version == .v2_3_1 else { return field }
        return Field(repetitions: [field.repetitions[0]])
    }
}
