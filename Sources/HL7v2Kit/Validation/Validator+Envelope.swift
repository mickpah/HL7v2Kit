// Validator+Envelope.swift
// Batch envelopes task 2: the per-field checks on one batch envelope segment (FHS, BHS, BTS,
// FTS), which BatchValidator runs outside any message.

extension Validator {
    /// The per-field issues for `segment` against `version`'s attribute table, located at
    /// `occurrence` (the batch number for BHS and BTS, 1 for FHS and FTS): required fields,
    /// repetitions, length, value format, code tables and components, each under the option
    /// that governs it in a message. Empty when the version has no table for the segment.
    func envelopeIssues(_ segment: Segment, occurrence: Int, version: Version) -> [ValidationIssue] {
        let version = version.grammarVersion
        guard let base = Self.grammarTable(for: version)[segment.segmentID] else { return [] }
        let profile = testProfileOverride ?? Profile.load(for: locale)
        let grammar = mergeGrammarExtension(
            base: base,
            profileExtension: profile?.grammarExtensions[segment.segmentID],
            profileCardinalityExtension: profile?.cardinalityExtensions[segment.segmentID]
        )
        // The envelope tables hold no predicate that reads another segment (pinned by
        // BatchEnvelopeFieldTests), so a one-segment message is all checkSegment reads.
        let message = Message(version: version, encodingCharacters: .default, segments: [segment])
        var issues: [ValidationIssue] = []
        checkSegment(segment, segmentIndex: 0, message: message, grammar: grammar,
                     occurrence: occurrence, profile: profile, issues: &issues)
        return issues
    }
}
