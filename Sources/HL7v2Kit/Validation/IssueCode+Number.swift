// IssueCode+Number.swift
// X1 task 2: the stable numeric code of each check, apart from ValidationIssue.swift, which
// is past 300 lines. The switch is exhaustive inside the module, so a new case does not
// compile until it has a number.

extension IssueCode {
    /// A stable number for this check, in six bands: 1xxx structure and profile, 2xxx
    /// cardinality and type, 3xxx primitive and value, 4xxx binding and terminology, 5xxx
    /// invariant, and 9xxx not evaluated.
    ///
    /// Stable: a number is never renumbered or reused, and a new case takes the next free
    /// number in its band. Associated values do not change it. The Validation article lists
    /// every number.
    public var number: Int {
        switch self {
        case .fieldNotSupported: 1001
        case .zSegmentPresent: 1002
        case .profileConstraintViolation: 1003
        case .segmentNotInVersionGrammar: 1004
        case .segmentWithdrawnInVersion: 1005
        case .versionGrammarSubstituted: 1006
        case .versionNotRecognised: 1007
        case .componentNotSupported: 1008
        case .messageStructureSegmentMissing: 1009
        case .messageStructureSegmentUnexpected: 1010
        case .messageStructureMismatch: 1011
        case .messageStructureNotModelled: 1012
        case .batchEnvelopeMalformed: 1013
        case .requiredFieldMissing: 2001
        case .requiredComponentMissing: 2002
        case .cardinalityExceeded: 2003
        case .profileMaximumExceeded: 2004
        case .segmentCardinalityBelowMinimum: 2005
        case .segmentCardinalityAboveMaximum: 2006
        case .extraComponentsInPrimitiveField: 2007
        case .extraComponentsInCompositeField: 2008
        case .batchCountMismatch: 2009
        case .pairedFieldMismatch: 3001
        case .fieldLengthOutOfRange: 3002
        case .componentLengthOutOfRange: 3003
        case .valueFormatInvalid: 3004
        case .valueNotInTable: 4001
        case .conditionalFieldMissing: 5001
        case .conditionalComponentMissing: 5002
        case .conformanceConditionMissing: 5003
        case .conditionalFieldProhibited: 5004
        case .conditionNotEvaluated: 9001
        }
    }
}
