// SegmentGrammar+ConditionIssues.swift
// 3.31.0 (G8): a lint for the conditions of a grammar the caller builds. A condition that does not
// parse never fires, so without this a typo in a Z-segment grammar fails silently.

/// One atom of a field grammar's condition that the condition language cannot read, found by
/// ``SegmentGrammar/conditionIssues()``. The validator treats such an atom as undecided, so
/// the condition it belongs to can never fire on it.
public struct ConditionIssue: Sendable, Equatable, Hashable {
    /// Which of a field grammar's conditions holds the atom.
    ///
    /// - Note: **Open** enum per ADR-014: it may gain cases in a minor release; switch with
    ///   `@unknown default`.
    public enum Source: Sendable, Equatable, Hashable {
        /// ``FieldGrammar/condition``.
        case condition
        /// ``FieldGrammar/prohibitedWhen``.
        case prohibitedWhen
        /// The ``FieldProhibition/condition`` of the entry of
        /// ``FieldGrammar/additionalProhibitions`` at `index` (0-based).
        case additionalProhibition(index: Int)
    }

    /// Why the atom cannot be read.
    ///
    /// - Note: **Open** enum per ADR-014: it may gain cases in a minor release; switch with
    ///   `@unknown default`.
    public enum Reason: Sendable, Equatable, Hashable {
        /// The atom has a referent and no predicate (`PID-3`).
        case missingPredicate
        /// The predicate is not one the language defines (`PID-3 isPopulated`, `PID-3 = A B`).
        case malformedPredicate
        /// The field reference inside `anyRepeat(...)` or `noRepeat(...)` does not parse
        /// (`anyRepeat(PID3) populated`).
        case malformedFieldReference
        /// The referent is not a field reference, a segment presence or a named referent
        /// (`PID3 populated`).
        case unknownReferent
    }

    /// The 1-based index of the field whose grammar holds the condition.
    public let fieldIndex: Int
    /// The condition the atom is in.
    public let source: Source
    /// The atom's text, as it stands between `AND` and `OR` in the condition.
    public let atom: String
    /// Why the atom cannot be read.
    public let reason: Reason

    /// Creates a condition issue.
    public init(fieldIndex: Int, source: Source, atom: String, reason: Reason) {
        self.fieldIndex = fieldIndex
        self.source = source
        self.atom = atom
        self.reason = reason
    }
}

extension SegmentGrammar {
    /// Every atom of this grammar's field conditions that the condition language in
    /// <doc:Validation> cannot read: for each of ``SegmentGrammar/fields`` in order, its
    /// ``FieldGrammar/condition``, then its ``FieldGrammar/prohibitedWhen``, then each of its
    /// ``FieldGrammar/additionalProhibitions``, atom by atom. Empty when every condition
    /// parses; an empty condition is skipped, as the validator skips it. Such an atom never
    /// fires and validation does not report it, so run this on a ``ZSegmentGrammar/grammar``
    /// when building one.
    public func conditionIssues() -> [ConditionIssue] {
        fields.flatMap { field -> [ConditionIssue] in
            var sources: [(ConditionIssue.Source, String?)] = [(.condition, field.condition),
                                                               (.prohibitedWhen, field.prohibitedWhen)]
            for (index, prohibition) in field.additionalProhibitions.enumerated() {
                sources.append((.additionalProhibition(index: index), prohibition.condition))
            }
            return sources.flatMap { source, condition -> [ConditionIssue] in
                guard let condition, !condition.isEmpty else { return [] }
                return ConditionLanguage.clauses(condition).flatMap { $0 }.compactMap { atom in
                    guard case .failure(let error) = ConditionLanguage.parseAtom(atom) else { return nil }
                    return ConditionIssue(fieldIndex: field.index, source: source, atom: atom, reason: .init(error))
                }
            }
        }
    }
}

extension ConditionIssue.Reason {
    /// The public reason for the parser's internal error, whose payload the atom already carries.
    init(_ error: ConditionParseError) {
        switch error {
        case .missingPredicate: self = .missingPredicate
        case .malformedPredicate: self = .malformedPredicate
        case .malformedFieldRef: self = .malformedFieldReference
        case .unknownReferent: self = .unknownReferent
        }
    }
}
