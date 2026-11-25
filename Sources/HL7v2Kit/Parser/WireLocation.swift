// WireLocation.swift
// A place in a message, as the source map looks it up (P01 R4, #37).

/// A place in a message: a segment, or a field, repetition, component or subcomponent in it.
///
/// Every index is 1-based. A nil index stops the place at the level above it: a location with
/// no field is the segment, one with no repetition the field, and so on, except that a component
/// named without a repetition is read in repetition 1.
public struct WireLocation: Sendable, Equatable, Hashable {
    /// The segment identifier as the parse read it.
    public let segmentID: String
    /// 1-based occurrence among the segments with that identifier.
    public let segmentIndex: Int
    /// 1-based field, or nil for the segment as a whole.
    public let fieldIndex: Int?
    /// 1-based repetition of the field, or nil for the field as a whole.
    public let repetitionIndex: Int?
    /// 1-based component, or nil for the repetition as a whole.
    public let componentIndex: Int?
    /// 1-based subcomponent, or nil for the component as a whole.
    public let subcomponentIndex: Int?

    /// A place named by its indices; the ones left out are nil.
    public init(segmentID: String, segmentIndex: Int, fieldIndex: Int? = nil, repetitionIndex: Int? = nil,
                componentIndex: Int? = nil, subcomponentIndex: Int? = nil) {
        self.segmentID = segmentID
        self.segmentIndex = segmentIndex
        self.fieldIndex = fieldIndex
        self.repetitionIndex = repetitionIndex
        self.componentIndex = componentIndex
        self.subcomponentIndex = subcomponentIndex
    }

    /// The place a validation issue names. An issue that names a component without a
    /// repetition is placed in the first repetition.
    public init(_ issue: IssueLocation) {
        self.init(segmentID: issue.segmentID, segmentIndex: issue.segmentIndex, fieldIndex: issue.fieldIndex,
                  repetitionIndex: issue.repetitionIndex ?? (issue.componentIndex == nil ? nil : 1),
                  componentIndex: issue.componentIndex, subcomponentIndex: issue.subcomponentIndex)
    }

    /// The same place as a path, or nil for a segment alone. A subcomponent named without a
    /// component is left out, as the place stops above it.
    public var path: Path? {
        fieldIndex.map {
            Path(segmentID: segmentID, segmentIndex: segmentIndex, field: $0, repetition: repetitionIndex,
                 component: componentIndex, subcomponent: componentIndex == nil ? nil : subcomponentIndex)
        }
    }
}
