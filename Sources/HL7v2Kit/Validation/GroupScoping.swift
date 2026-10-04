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
/// match, in pre-order, with the structure they were matched against.
struct GroupSpanIndex: Sendable {
    let spans: [GroupSpan]
    /// The matched structure's top-level elements; a span's `position` indexes them.
    let elements: [StructureElement]
    /// The message's segment IDs, in order.
    let ids: [String]

    /// The anchor's pairing context for `peer` (P8b-17 fix round 1): the
    /// message indices, in order, where a peer of the segment at `anchor`
    /// (whose ID is `anchorID`) may be taken from.
    ///
    /// A *boundary* is a group instance whose own level (its segments, and
    /// those of unnamed choices in it, not those of nested groups) holds
    /// `anchorID`: it pairs its own segments, as ORDER_PRIOR { [ORC] OBR }
    /// does inside an order's OBSERVATION_REQUEST (v2.5.1 CH04 4.4.6 OML_O21).
    ///
    /// Walk outward from the innermost group instance containing the anchor
    /// to the top level. Stop at the first level whose definition holds
    /// `peer` outside every nested boundary group other than the one the
    /// anchor is in; the top level always stops. The context is that level's
    /// instance (the whole message at the top) minus every nested boundary
    /// instance that does not contain the anchor. So a peer comes from the
    /// anchor's own group occurrence, or a non-pairing group nested in it,
    /// never from another occurrence or from a nested group that pairs its own
    /// ORC and OBR. A level whose definition holds the peer but whose instance
    /// has none answers "absent".
    func context(around anchor: Int, of anchorID: String, for peer: String) -> [Int] {
        var chain: [Int] = []
        var cursor = spans.lastIndex { $0.indices.contains(anchor) }
        while let at = cursor {
            chain.append(at)
            cursor = spans[at].parent
        }
        var below: Int?
        for level in chain {
            let base = spans[level].position
            let keep = below.map { spans[$0].position.dropFirst(base.count) }
            if Self.paired(element(at: base).children, anchor: anchorID, keep: keep).contains(peer) {
                return region(level, anchor: anchor, anchorID: anchorID)
            }
            below = level
        }
        return region(nil, anchor: anchor, anchorID: anchorID)
    }

    /// The instance of `level` (nil: the whole message) without the nested
    /// boundary instances that do not contain the anchor.
    private func region(_ level: Int?, anchor: Int, anchorID: String) -> [Int] {
        let range = level.map { spans[$0].indices } ?? 0...max(0, ids.count - 1)
        var excluded = Set<Int>()
        for (s, span) in spans.enumerated()
        where !span.indices.contains(anchor) && isDescendant(s, of: level)
            && Self.ownLevel(element(at: span.position).children).contains(anchorID) {
            excluded.formUnion(span.indices)
        }
        return range.filter { !excluded.contains($0) }
    }

    private func isDescendant(_ span: Int, of level: Int?) -> Bool {
        guard let level else { return true }
        var cursor = spans[span].parent
        while let at = cursor {
            if at == level { return true }
            cursor = spans[at].parent
        }
        return false
    }

    /// The element at a span's structure position.
    private func element(at position: [Int]) -> StructureElement {
        var list = elements
        var found = elements[position[0]]
        for index in position {
            found = list[index]
            list = found.children
        }
        return found
    }

    /// The segment IDs at the own level of `children`: their segments and
    /// those of unnamed choices among them (an unnamed choice opens no span).
    static func ownLevel(_ children: [StructureElement]) -> Set<String> {
        children.reduce(into: Set<String>()) { result, child in
            switch child {
            case .segment(let id, _, _): result.insert(id)
            case .choice(.none, _, _, let alternatives): result.formUnion(ownLevel(alternatives))
            default: break
            }
        }
    }

    /// The segment IDs `children` define outside every nested boundary group
    /// (one whose own level holds `anchor`), except the child on the path
    /// `keep` (relative positions) to the group the anchor is in.
    static func paired(_ children: [StructureElement], anchor: String, keep: ArraySlice<Int>?) -> Set<String> {
        var result = Set<String>()
        for (index, child) in children.enumerated() {
            let path = keep?.first == index ? keep?.dropFirst() : nil
            switch child {
            case .segment(let id, _, _):
                result.insert(id)
            case .choice(.none, _, _, let alternatives):
                result.formUnion(paired(alternatives, anchor: anchor, keep: path))
            default:
                if path != nil || !ownLevel(child.children).contains(anchor) {
                    result.formUnion(paired(child.children, anchor: anchor, keep: nil))
                }
            }
        }
        return result
    }
}
