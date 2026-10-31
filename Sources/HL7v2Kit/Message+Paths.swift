// Message+Paths.swift
// Reads that name more than one location (P00 S2-1) and the populated-path listing
// (P00 S2-2).

extension Message {
    /// Every value `path` names, in document order: each matching segment occurrence in
    /// turn and, within it, each matching repetition. A path with no wildcard yields at most
    /// one value, the one the path subscript reads. As with the subscript, a location that
    /// holds more than one value (a structured field read whole) is skipped, and an empty
    /// value is included.
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
                    if let value = Self.value(in: segment, at: path, repetition: repetition) {
                        result.append(value)
                    }
                }
            } else if let value = Self.value(in: segment, at: path, repetition: path.repetition ?? 1) {
                result.append(value)
            }
        }
        return result
    }
}
