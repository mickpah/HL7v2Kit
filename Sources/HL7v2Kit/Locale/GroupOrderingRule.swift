// GroupOrderingRule.swift
// P12 S2-2: an in-group ordering rule (HL7au:000008.1.5).

/// "Nothing but kind B after the first of kind A" within each group instance.
///
/// Within each group of `scope` (resolved as the cardinality rules resolve it:
/// the matched structure's spans, or the walk where spans are withheld), once a
/// `orderedSegmentID` segment matching `startPredicate` has been seen, every
/// later `orderedSegmentID` segment of the same group must match
/// `allowedAfterPredicate`; each one that does not is reported once at its own
/// segment. A group with no starting segment is not checked. The predicates use
/// the condition language (ADR-009) and are evaluated on the candidate segment.
struct GroupOrderingRule: Sendable, Equatable, Hashable {
    /// The group the order is checked within (e.g. `.obrObxGroup`).
    let scope: GroupScope

    /// The segment that heads the group (e.g. "OBR"); one check per group.
    let anchorSegmentID: String

    /// The segment whose order is checked (e.g. "OBX").
    let orderedSegmentID: String

    /// The first segment matching this opens the tail (e.g. a display OBX).
    let startPredicate: String

    /// Every later segment must match this (e.g. a display or signature OBX).
    let allowedAfterPredicate: String

    /// Message-level gate, evaluated on MSH; `nil` applies everywhere.
    let applicableWhen: String?

    /// The cited rule reported as `.profileConstraintViolation(localeRule:)`.
    let specCitation: String
}
