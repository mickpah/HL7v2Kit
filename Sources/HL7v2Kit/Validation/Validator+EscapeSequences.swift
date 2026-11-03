// Validator+EscapeSequences.swift
// 3.31.0 (G3): an escape sequence the message's version does not define, or an escape character
// with no closing one (v2.5.1 section 2.7; v2.3 and v2.3.1 section 2.9, v2.4 section 2.10).

extension Validator {
    /// Reports ``IssueCode/escapeSequenceUndefined`` at ``ValidationOptions/escapeSequenceSeverity``
    /// once for each value whose text, as the serialiser writes it, holds an undefined or unclosed
    /// escape, quoting the first. Every segment is read, whatever its grammar: the escape rules
    /// are Chapter 2 encoding rules, as the character-set check's are. MSH-1 and MSH-2 (and their
    /// BHS and FHS twins) hold the delimiters and are skipped. The location names the component
    /// when the repetition has more than one or the component has subcomponents, and the
    /// subcomponent when there are several.
    func checkEscapeSequences(message: Message, issues: inout [ValidationIssue]) {
        guard let severity = options.escapeSequenceSeverity else { return }
        let encoding = message.encodingCharacters
        let version = message.version
        // `\P\` is reported only when MSH-12 names a modelled version that does not define it. An
        // unmodelled one (2.9, 2.8.1) validates as v2.5.1, but its own print may define `\P\`, so
        // that reading stays quiet and fails safe.
        let msh12 = message.segments.first.flatMap { $0.segmentID == "MSH" ? $0.field(12) : nil }
        let reportsTruncation: Bool
        if case .recognised(let declared) = Version.reading(
            msh12: msh12, subcomponentSeparator: encoding.subcomponentSeparator) {
            reportsTruncation = !declared.definesTruncationEscape
        } else {
            reportsTruncation = false
        }
        // Most values hold no escape. A byte scan settles those: `encode` only writes escapes the
        // standard defines, so a value with no wire text and no escape character cannot draw this.
        let escapeByte = encoding.escapeCharacter.asciiValue
        var occurrenceBySegmentID: [String: Int] = [:]
        for segment in message.segments {
            let occurrence = (occurrenceBySegmentID[segment.segmentID] ?? 0) + 1
            occurrenceBySegmentID[segment.segmentID] = occurrence
            let separatorSegment = Parser.isSeparatorSegment(segment.segmentID)
            for (fieldIndex, field) in segment.fields.enumerated() where fieldIndex >= 1 {
                if separatorSegment, fieldIndex <= 2 { continue }
                for repetition in field.repetitions {
                    for (componentOffset, component) in repetition.components.enumerated() {
                        for (subcomponentOffset, subcomponent) in component.subcomponents.enumerated() {
                            if subcomponent.wire == nil, let escapeByte,
                               !subcomponent.value.utf8.contains(escapeByte) { continue }
                            let wire = EscapeSequences.wireForm(of: subcomponent, encoding: encoding)
                            guard let sequence = Self.undefinedEscape(in: wire, encoding: encoding,
                                                                  reportsTruncation: reportsTruncation)
                            else { continue }
                            let single = repetition.components.count == 1 && component.subcomponents.count == 1
                            let location = IssueLocation(
                                segmentID: segment.segmentID, segmentIndex: occurrence, fieldIndex: fieldIndex,
                                componentIndex: single ? nil : componentOffset + 1,
                                subcomponentIndex: component.subcomponents.count > 1 ? subcomponentOffset + 1 : nil)
                            issues.append(ValidationIssue(
                                severity: severity,
                                code: .escapeSequenceUndefined,
                                location: location,
                                message: "Escape sequence \(options.quoted(sequence)) is not defined by HL7 "
                                    + "v\(version.rawValue) (section \(version.escapeSequenceSection))"
                            ))
                        }
                    }
                }
            }
        }
    }

    /// The first escape in `wire` that `version` does not define, escape characters included, or
    /// nil. Sequences are read left to right, each from an escape character to the next (v2.5.1
    /// section 2.7.1), so the `\` closing `\E\` never opens another. A body is defined when it
    /// decodes (`F`, `S`, `T`, `R`, `E`, `X` and hex pairs) or is one the decoder keeps (`H`, `N`,
    /// `Z…`, `Cxxyy`, `Mxxyy(zz)`, a formatting command), except `P` where `reportsTruncation`. An escape
    /// character with no closing one is undefined from there to the end of the value.
    static func undefinedEscape(in wire: String, encoding: EncodingCharacters,
                                reportsTruncation: Bool) -> String? {
        let escape = encoding.escapeCharacter
        guard wire.contains(where: { $0.isDelimiter(escape) }) else { return nil }
        let chars = Array(wire)
        var start = 0
        while let open = chars[start...].firstIndex(where: { $0.isDelimiter(escape) }) {
            guard let close = chars[(open + 1)...].firstIndex(where: { $0.isDelimiter(escape) }) else {
                return String(chars[open...])
            }
            let body = chars[(open + 1)..<close]
            let defined = EscapeSequences.decodeBody(body, encoding: encoding) != nil
                || (EscapeSequences.isRepertoireBody(body) && (body.first != "P" || !reportsTruncation))
            if !defined { return String(chars[open...close]) }
            start = close + 1
        }
        return nil
    }
}
