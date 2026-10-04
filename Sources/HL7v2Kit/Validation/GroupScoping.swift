// GroupScoping.swift
// P8b-17 (ADR-019 "Interaction with the existing ORC-group scoping"): how the
// group-dependent predicates find the group of a segment. Internal only.

/// The group a group-dependent predicate reads: the matched structure's group
/// spans, the ORC walk, or the ORC walk with the former message-code gate.
enum GroupScoping: Sendable {
    /// `Message.orcGroupRange(around:)`: from the most recent ORC to the next.
    case walk
    /// The group instances of a clean structure match.
    case spans(GroupSpanIndex)
    /// No spans for a message code the P4-7 and P10-5a gates covered on this
    /// version: the conditions of these fields (`SEG-n`) are not evaluated, as
    /// under the gate; every other lookup uses the ORC walk.
    case gated(Set<String>)
}

/// The group spans of one message (ADR-019): every group instance of a clean
/// match, in pre-order, with the segment IDs its definition contains.
struct GroupSpanIndex: Sendable {
    let spans: [GroupSpan]
    let segmentCount: Int

    /// The message indices of the innermost group instance that contains
    /// `index` and whose definition contains `id` at any depth, or of the
    /// whole message when no enclosing group does (the top level). The last
    /// span in pre-order that contains `index` is the innermost one.
    func range(around index: Int, containing id: String) -> Range<Int> {
        var cursor = spans.lastIndex { $0.indices.contains(index) }
        while let at = cursor {
            if spans[at].members.contains(id) {
                return spans[at].indices.lowerBound..<(spans[at].indices.upperBound + 1)
            }
            cursor = spans[at].parent
        }
        return 0..<segmentCount
    }
}
