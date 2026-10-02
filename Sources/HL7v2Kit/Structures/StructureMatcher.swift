// StructureMatcher.swift
// ADR-019 "Matcher": greedy recursive-descent matching of a message's
// segment-ID sequence against a MessageStructure, with FOLLOW-set recovery
// and a group-span index. A pure function over the model; the Validator
// decides when to call it (structure resolution, version, fragments, lint).

/// One departure of a segment sequence from its message structure.
struct StructureFinding: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        /// A required segment, or the head segment of a required group, is absent.
        case missing
        /// A segment has no place at this point: out of order, or a segment
        /// the structure does not contain.
        case unexpected
        /// A stray segment that is a further occurrence past a maximum. It
        /// is chosen by looking, in the sequences still open (innermost
        /// first, latest element first), for the nearest element already
        /// passed whose FIRST set contains the segment: if that element
        /// reached its maximum the stray is `.exceededMaximum`, otherwise
        /// `.unexpected`. Elements inside group instances already closed
        /// are not considered. Both map to `messageStructureSegmentUnexpected`.
        case exceededMaximum
    }

    let kind: Kind
    let segmentID: String
    /// For `.missing`: the group the absent element belongs to, or the
    /// absent group itself; nil at top level. Always nil for `.unexpected`
    /// and `.exceededMaximum`.
    let group: String?
    /// The message index (MSH is 0). For `.missing`, the index of the next
    /// matched (non-transparent) segment it was expected before, or
    /// `ids.count` (one past the last segment, after any trailing Z-segment
    /// or ADD) when it was expected at the end; the consumer maps that value
    /// to "end of message" (ADR-019 locates it at the last segment).
    let index: Int
}

/// One matched group instance: its path from the top level and the message
/// indices it covers, first to last matched segment inclusive (so it also
/// covers any transparent segment between them). Exact only when the match
/// has no finding (ADR-019 ceiling 4).
struct GroupSpan: Sendable, Equatable, CustomStringConvertible {
    let path: [String]
    let indices: ClosedRange<Int>
    /// Index into `StructureMatch.spans` of the enclosing group instance.
    let parent: Int?

    var name: String { path.last ?? "" }
    var description: String { "\(path.joined(separator: "/")) \(indices)" }
}

/// The result of matching one message: findings in message order of
/// discovery, and every group instance in pre-order.
struct StructureMatch: Sendable, Equatable {
    let findings: [StructureFinding]
    let spans: [GroupSpan]
}

/// Matches segment IDs against an HL7 abstract message syntax in one pass.
///
/// An element is entered, and repeated, while the current segment is in its
/// FIRST set and its maximum is not reached. Exact for structures that pass
/// `lint(_:)`; the caller must not match a structure that fails it. Recovery:
/// a segment that neither the current element nor anything after it, at any
/// enclosing level, can begin is reported and skipped. After the first
/// divergence a second finding can describe the same defect (an out-of-order
/// segment is reported missing, then unexpected); the first is always
/// accurate. No backtracking.
struct StructureMatcher: Sendable {
    let structure: MessageStructure

    /// Z-segments and ADD continuations are never matched (ADR-019): they
    /// are skipped without a finding on every version.
    static func isTransparent(_ id: String) -> Bool {
        id.hasPrefix("Z") || id == "ADD"
    }

    /// Matches `ids`, the segment IDs of a message in order (MSH first).
    /// `transparent` names further IDs to skip without a finding: the
    /// caller passes the non-Z segments its version grammar does not define,
    /// which already raise `segmentNotInVersionGrammar`.
    func match(_ ids: [String], transparent: Set<String> = []) -> StructureMatch {
        let positions = ids.indices.filter { !Self.isTransparent(ids[$0]) && !transparent.contains(ids[$0]) }
        var state = State(ids: ids, positions: positions)
        matchSequence(structure.elements, path: [], parent: nil, follow: [], &state)
        return StructureMatch(findings: state.findings, spans: state.spans.map {
            GroupSpan(path: $0.path, indices: $0.start...$0.end, parent: $0.parent)
        })
    }

    private struct OpenSpan {
        let path: [String]
        let start: Int
        var end: Int
        let parent: Int?
    }

    private struct State {
        let ids: [String]
        let positions: [Int]
        var cursor = 0
        var lastConsumed = 0
        var findings: [StructureFinding] = []
        var spans: [OpenSpan] = []
        /// Per open sequence, innermost last: the FIRST set of each element
        /// already passed and whether it reached its maximum.
        var frames: [[(first: Set<String>, saturated: Bool)]] = []

        var current: String? { cursor < positions.count ? ids[positions[cursor]] : nil }
        var index: Int { cursor < positions.count ? positions[cursor] : ids.count }

        mutating func consume() {
            lastConsumed = positions[cursor]
            cursor += 1
        }

        /// A stray is an excess occurrence when the nearest passed element
        /// that can begin with it is at its maximum.
        func strayKind(_ id: String) -> StructureFinding.Kind {
            for frame in frames.reversed() {
                if let entry = frame.last(where: { $0.first.contains(id) }) {
                    return entry.saturated ? .exceededMaximum : .unexpected
                }
            }
            return .unexpected
        }
    }

    private func matchSequence(
        _ elements: [StructureElement],
        path: [String],
        parent: Int?,
        follow: Set<String>,
        _ state: inout State
    ) {
        state.frames.append([])
        for (i, element) in elements.enumerated() {
            let own = element.firstSet
            let later = elements[(i + 1)...].reduce(into: follow) { $0.formUnion($1.firstSet) }
            let keep = own.union(later)
            skipStrays(keeping: keep, &state)
            var count = 0
            while element.max.map({ count < $0 }) ?? true, let id = state.current, own.contains(id) {
                let before = state.cursor
                switch element {
                case .segment:
                    state.consume()
                case .group(let name, _, let max, let children):
                    let span = state.spans.count
                    state.spans.append(OpenSpan(path: path + [name], start: state.index, end: state.index, parent: parent))
                    let inner = max == 1 ? later : later.union(own)
                    matchSequence(children, path: path + [name], parent: span, follow: inner, &state)
                    if state.cursor == before {
                        state.spans.removeLast()
                    } else {
                        state.spans[span].end = state.lastConsumed
                    }
                }
                if state.cursor == before { break }
                count += 1
                skipStrays(keeping: keep, &state)
            }
            if count < element.min && !element.isNullable {
                state.findings.append(StructureFinding(
                    kind: .missing, segmentID: element.headSegmentID,
                    group: element.groupName ?? path.last, index: state.index
                ))
            }
            let saturated = element.max.map { count >= $0 } ?? false
            state.frames[state.frames.count - 1].append((own, saturated))
        }
        skipStrays(keeping: follow, &state)
        state.frames.removeLast()
    }

    private func skipStrays(keeping keep: Set<String>, _ state: inout State) {
        while let id = state.current, !keep.contains(id) {
            state.findings.append(StructureFinding(kind: state.strayKind(id), segmentID: id, group: nil, index: state.index))
            state.cursor += 1
        }
    }
}
