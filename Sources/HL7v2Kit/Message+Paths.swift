// Message+Paths.swift
// Reads that name more than one location (P00 S2-1) and the populated-path listing
// (P00 S2-2).

/// One populated leaf of a message: its fully indexed path and its decoded value.
public struct PathValue: Sendable, Equatable, Hashable {
    /// The leaf's location, with the segment occurrence, repetition, component and
    /// subcomponent all set.
    public let path: Path

    /// The value as the path subscript reads it: decoded as <doc:EscapeSequences> describes (a locally defined or unrecognised escape stays as written).
    public let value: String

    /// Creates a path and its value.
    public init(path: Path, value: String) {
        self.path = path
        self.value = value
    }
}

extension Message {
    /// Every non-empty value `path` names, in document order: each matching segment
    /// occurrence in turn and, within it, each matching repetition. A path with no wildcard
    /// yields at most one value: the one the path subscript reads, when it is not empty. An
    /// empty value is skipped, as an omitted one is (HL7 v2 treats both as no value), so the
    /// result does not depend on trailing delimiters; the HL7 null `""` is a value and is kept.
    /// As with the subscript, a location that holds more than one value (a structured field
    /// read whole) is skipped: `PID-3[*]` reads nothing from a CX, `PID-3[*].1` reads each
    /// identifier.
    ///
    /// ```swift
    /// message.values(at: try Path("OBX[*]-5"))     // OBX-5 of every OBX
    /// message.values(at: try Path("PID-3[*].1"))   // PID-3.1 of every repetition
    /// ```
    public func values(at path: Path) -> [String] {
        var result: [String] = []
        var occurrence = 0
        for segment in segments where segment.segmentID == path.segmentID {
            occurrence += 1
            guard path.segmentWildcard || occurrence == (path.segmentIndex ?? 1) else { continue }
            if path.repetitionWildcard {
                let count = segment.field(path.field)?.repetitions.count ?? 0
                for repetition in stride(from: 1, through: count, by: 1) {
                    if let value = Self.value(in: segment, at: path, repetition: repetition), !value.isEmpty {
                        result.append(value)
                    }
                }
            } else if let value = Self.value(in: segment, at: path, repetition: path.repetition ?? 1), !value.isEmpty {
                result.append(value)
            }
        }
        return result
    }

    /// Every non-empty value in the message with its path, in document order: segments in
    /// turn, then fields, repetitions, components and subcomponents. Each path has every index
    /// set (`PID[1]-5~1.1.1`), so the same location has the same path in every message; drop
    /// the indices a use does not need. The HL7 null `""` is a value and is listed. MSH-1 and
    /// MSH-2 are listed as their literal characters. Calling it twice gives the same list.
    /// The parser takes the first three characters of a segment line as its ID, so a malformed
    /// line (such as `Z-1|`) can yield a path whose `description` does not parse back.
    public func populatedPaths() -> [PathValue] {
        var result: [PathValue] = []
        var occurrenceByID: [String: Int] = [:]
        for segment in segments {
            let id = segment.segmentID
            let occurrence = (occurrenceByID[id] ?? 0) + 1
            occurrenceByID[id] = occurrence
            // Index 0 is the segment ID's placeholder, not a field.
            for (fieldIndex, field) in segment.fields.enumerated() where fieldIndex >= 1 {
                for (r, repetition) in field.repetitions.enumerated() {
                    for (c, component) in repetition.components.enumerated() {
                        for (s, subcomponent) in component.subcomponents.enumerated() where !subcomponent.value.isEmpty {
                            let path = Path(segmentID: id, segmentIndex: occurrence, field: fieldIndex,
                                            repetition: r + 1, component: c + 1, subcomponent: s + 1)
                            result.append(PathValue(path: path, value: subcomponent.value))
                        }
                    }
                }
            }
        }
        return result
    }
}
