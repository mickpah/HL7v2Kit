// Validator+CharacterSet.swift
// 3.29.0 (#16): a field whose text the message's character set cannot encode.

extension Validator {
    /// Reports ``IssueCode/characterNotEncodable(declared:)``, an error, once for each field
    /// holding a subcomponent whose text, as the serialiser writes it, the message's
    /// character set cannot encode. MSH-1 and MSH-2 (and their BHS and FHS twins) hold the
    /// delimiters and are skipped. A UTF-8 message returns at once.
    func checkCharacterSet(message: Message, issues: inout [ValidationIssue]) {
        let encoding = message.characterEncoding
        guard encoding != .utf8 else { return }
        var occurrenceBySegmentID: [String: Int] = [:]
        for segment in message.segments {
            let occurrence = (occurrenceBySegmentID[segment.segmentID] ?? 0) + 1
            occurrenceBySegmentID[segment.segmentID] = occurrence
            for (fieldIndex, field) in segment.fields.enumerated() where fieldIndex >= 1 {
                if Parser.isSeparatorSegment(segment.segmentID), fieldIndex <= 2 { continue }
                let fits = field.repetitions.allSatisfy { repetition in
                    repetition.components.allSatisfy { component in
                        component.subcomponents.allSatisfy {
                            encoding.encodes(EscapeSequences.wireForm(of: $0, encoding: message.encodingCharacters))
                        }
                    }
                }
                guard !fits else { continue }
                let location = IssueLocation(segmentID: segment.segmentID, segmentIndex: occurrence,
                                             fieldIndex: fieldIndex)
                issues.append(ValidationIssue(
                    severity: .error,
                    code: .characterNotEncodable(declared: encoding.wireValue),
                    location: location,
                    message: "\(location.pathDescription) holds a character the message's character set (\(encoding.wireValue)) cannot encode; serialize() would write the whole message as UTF-8."
                ))
            }
        }
    }
}
