// FullPredicateConditions.swift
// P4-31 (ADR-021): which stored C conditions are the spec's complete
// predicate. The set itself is generated from the schemas'
// `conditionIsPredicate` marker into
// `Segment/Generated/FullPredicateConditions+Generated.swift`.

/// The fields whose stored `condition` is the spec's complete C predicate
/// on a given version: required when true, must not be sent when false.
/// Every other stored condition is a "required when" trigger only, and
/// its false branch says nothing. Internal; not public API (ADR-014).
enum FullPredicateConditions {
    /// The `version|SEG-n` key for a field.
    static func key(version: String, segmentID: String, fieldIndex: Int) -> String {
        "\(version)|\(segmentID)-\(fieldIndex)"
    }

    /// True when the schema marks this field's condition as a full predicate.
    static func isMarked(version: String, segmentID: String, fieldIndex: Int) -> Bool {
        generated.contains(key(version: version, segmentID: segmentID, fieldIndex: fieldIndex))
    }
}
