// Validator+Correlations.swift
// 3.23.0: cited cross-segment correlations (ROL-4 against STF-2 and STF-3, v2.6 to v2.8.2).

extension Validator {
    /// For each populated repetition, the components a correlation maps must, where this field
    /// values them, all equal the mapped components of one repetition of the peer field. The
    /// peer is the segment group scoping associates (``Message`` `associatedSegment`, as the
    /// `STF absent` condition reads it); no peer, an empty peer field, or a part this repetition
    /// leaves empty compares nothing. Reported as ``IssueCode/correlatedValueMismatch`` at the
    /// field, at ``ValidationOptions/correlationSeverity``.
    func checkCorrelations(_ grammar: FieldGrammar, field: Field, segmentIndex: Int, message: Message,
                           location: IssueLocation, severity: IssueSeverity, issues: inout [ValidationIssue]) {
        for correlation in grammar.correlations {
            guard let peer = message.associatedSegment(correlation.segment, fromIndex: segmentIndex),
                  let peerField = peer.field(correlation.field) else { continue }
            let candidates = peerField.repetitions.filter(isRepetitionPopulated)
            guard let first = candidates.first else { continue }
            for (offset, repetition) in field.repetitions.enumerated() where isRepetitionPopulated(repetition) {
                let valued = correlation.components.sorted { $0.key < $1.key }
                    .compactMap { own, theirs in Self.correlationValue(repetition, own).map { (own, theirs, $0) } }
                guard !valued.isEmpty, !candidates.contains(where: { candidate in
                    valued.allSatisfy { Self.correlationValue(candidate, $0.1) == $0.2 }
                }) else { continue }
                let differing = valued.first { Self.correlationValue(first, $0.1) != $0.2 } ?? valued[0]
                let theirs = Self.correlationValue(first, differing.1)?.joined(separator: "&") ?? ""
                let own = "\(location.segmentID)-\(location.fieldIndex ?? 0).\(differing.0)"
                issues.append(ValidationIssue(
                    severity: severity,
                    code: .correlatedValueMismatch,
                    location: location,
                    message: "\(location.pathDescription) repetition \(offset + 1): its \(correlation.part) matches no \(correlation.segment)-\(correlation.field) repetition (\(own) \(options.quoted(differing.2.joined(separator: "&"))) against \(correlation.segment)-\(correlation.field).\(differing.1) \(options.quoted(theirs)))."
                ))
            }
        }
    }

    /// A component's subcomponent values with trailing empties dropped; nil when it carries no
    /// value (absent, empty, or the explicit null `""`).
    static func correlationValue(_ repetition: Repetition, _ index: Int) -> [String]? {
        guard index >= 1, index <= repetition.components.count else { return nil }
        var values = repetition.components[index - 1].subcomponents.map(\.value)
        while values.last?.isEmpty == true { values.removeLast() }
        return values.isEmpty || values == ["\"\""] ? nil : values
    }
}
