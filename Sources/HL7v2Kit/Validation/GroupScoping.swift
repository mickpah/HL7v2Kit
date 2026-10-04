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
///
/// The scope rule (P8b-17, fix round 2), for one lookup of a peer segment ID
/// `peer` from an anchor segment whose ID is `anchor`:
///
/// - **Own level.** A group's own level is its segments and those of the
///   unnamed choices in it (an unnamed choice opens no span), not those of
///   nested groups or named choices.
/// - **Pairing boundary.** A group or named choice N is a pairing boundary for
///   the lookup when N's own level holds `peer` and some `anchor` segment inside
///   N (at N's own level, or in a nested group whose own level does not hold
///   `peer`) first finds `peer` at N's own level. N then pairs its own segments,
///   as ORDER_PRIOR { [ORC] OBR ... {OBSERVATION_PRIOR { OBX }} } does for ORC,
///   OBR and OBX anchors. A pairing boundary is never transparent.
/// - **Transparency.** A child group or named choice that occurs at most once
///   per occurrence of its parent (maximum 1) and is not a pairing boundary is
///   transparent: its own-level segments count as part of the parent's own
///   level, recursively (a transparent child's transparent children too). A
///   bracket that cannot repeat makes segments optional together; it is not a
///   scope of its own.
/// - **Extended own level** of a group: its own level plus that of every
///   transparent descendant reached through transparent groups only.
///
/// The peer is taken (`context(around:of:for:)`) from the first of: the
/// extended own level of the anchor's innermost group; anywhere inside that
/// group except nested pairing boundaries; the extended own level of each
/// enclosing group, outward to the top level (the message). The first of these
/// whose definition holds `peer` decides; if its occurrence has none, the peer
/// is absent. So a peer is never taken from a repeating sibling group (a
/// cousin), nor from a nested pairing boundary.
///
/// Termination: `context` and `group` move strictly outward along the span
/// parent chain, which ends at the message (nil). Every `ScopeLookup` function
/// recurses strictly inward over the children of a finite definition tree;
/// `transparent` calls `pairing`, `extended` and `inside` call those two, and
/// none of them calls back into a lookup. `region` visits each span at most
/// once (pre-order, skipping a cut subtree). The cost of one lookup is linear
/// in the spans and in the definition's size times its depth.
struct GroupSpanIndex: Sendable {
    let spans: [GroupSpan]
    /// The matched structure's top-level elements; a span's `position` indexes them.
    let elements: [StructureElement]
    /// The message's segment IDs, in order.
    let ids: [String]

    /// The message indices, in order, where a peer `peer` of the segment at
    /// `anchor` (whose ID is `anchorID`) may be taken from: the scope rule above.
    func context(around anchor: Int, of anchorID: String, for peer: String) -> [Int] {
        let lookup = ScopeLookup(anchor: anchorID, peer: peer)
        let own = spans.lastIndex { $0.indices.contains(anchor) }
        if lookup.extended(children(own)).contains(peer) { return extendedRegion(own, lookup) }
        if lookup.inside(children(own)).contains(peer) { return insideRegion(own, anchor: anchor, lookup) }
        var level = own
        while let at = level {
            level = spans[at].parent
            if lookup.extended(children(level)).contains(peer) { return extendedRegion(level, lookup) }
        }
        return []
    }

    /// The `head`-headed group of the segment at `anchor`, for the group-scope
    /// cardinality rules counting `counted` (`.obrObxGroup`: head OBR): starting
    /// from the anchor's innermost group, groups transparent for (`counted`,
    /// `head`) are dissolved into their parent; the first group from there
    /// outward whose extended own level holds `head` is the group, and its
    /// occurrence without nested pairing boundaries is returned. Nil when no
    /// enclosing group holds `head`.
    func group(around anchor: Int, holding head: String, counting counted: String) -> [Int]? {
        let lookup = ScopeLookup(anchor: counted, peer: head)
        var level = spans.lastIndex { $0.indices.contains(anchor) }
        while let at = level, lookup.transparent(element(at: spans[at].position)) {
            level = spans[at].parent
        }
        while true {
            if lookup.extended(children(level)).contains(head) { return insideRegion(level, anchor: anchor, lookup) }
            guard let at = level else { return nil }
            level = spans[at].parent
        }
    }

    /// The occurrence of `level` (nil: the message) without its descendants
    /// that are not transparent: its extended own level.
    private func extendedRegion(_ level: Int?, _ lookup: ScopeLookup) -> [Int] {
        region(level) { span in !lookup.transparent(element(at: span.position)) }
    }

    /// The occurrence of `level` without the nested pairing boundaries that do
    /// not contain the anchor.
    private func insideRegion(_ level: Int?, anchor: Int, _ lookup: ScopeLookup) -> [Int] {
        region(level) { span in !span.indices.contains(anchor) && lookup.pairing(element(at: span.position)) }
    }

    /// The occurrence of `level` minus every descendant span `cut` selects
    /// (with its own descendants). Spans are in pre-order, so the descendants
    /// of `level` follow it contiguously; a cut span's subtree is skipped.
    private func region(_ level: Int?, cut: (GroupSpan) -> Bool) -> [Int] {
        let range = level.map { spans[$0].indices } ?? 0...max(0, ids.count - 1)
        var excluded = Set<Int>()
        var s = (level ?? -1) + 1
        while s < spans.count, isDescendant(s, of: level) {
            guard cut(spans[s]) else { s += 1; continue }
            excluded.formUnion(spans[s].indices)
            let root = s
            s += 1
            while s < spans.count, isDescendant(s, of: root) { s += 1 }
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

    private func children(_ level: Int?) -> [StructureElement] {
        level.map { element(at: spans[$0].position).children } ?? elements
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
}

/// The definition-level parts of the scope rule for one (anchor, peer) lookup.
/// Each function recurses only into the children of the element it is given.
struct ScopeLookup {
    let anchor: String
    let peer: String

    /// The segment IDs at the own level of `children` (segments, and those of
    /// unnamed choices among them).
    static func ownLevel(_ children: [StructureElement]) -> Set<String> {
        children.reduce(into: Set<String>()) { result, child in
            switch child {
            case .segment(let id, _, _): result.insert(id)
            case .choice(.none, _, _, let alternatives): result.formUnion(ownLevel(alternatives))
            default: break
            }
        }
    }

    /// Whether the group or named choice `group` is a pairing boundary.
    func pairing(_ group: StructureElement) -> Bool {
        guard Self.ownLevel(group.children).contains(peer) else { return false }
        func unclaimed(_ children: [StructureElement]) -> Bool {
            children.contains { child in
                switch child {
                case .segment(let id, _, _): return id == anchor
                case .choice(.none, _, _, let alternatives): return unclaimed(alternatives)
                default: return !Self.ownLevel(child.children).contains(peer) && unclaimed(child.children)
                }
            }
        }
        return unclaimed(group.children)
    }

    /// Whether the group or named choice `group` is transparent.
    func transparent(_ group: StructureElement) -> Bool {
        group.max == 1 && !pairing(group)
    }

    /// The segment IDs of the extended own level of a group with `children`.
    func extended(_ children: [StructureElement]) -> Set<String> {
        children.reduce(into: Set<String>()) { result, child in
            switch child {
            case .segment(let id, _, _): result.insert(id)
            case .choice(.none, _, _, let alternatives): result.formUnion(extended(alternatives))
            default: if transparent(child) { result.formUnion(extended(child.children)) }
            }
        }
    }

    /// The segment IDs defined anywhere in `children` outside pairing boundaries.
    func inside(_ children: [StructureElement]) -> Set<String> {
        children.reduce(into: Set<String>()) { result, child in
            switch child {
            case .segment(let id, _, _): result.insert(id)
            case .choice(.none, _, _, let alternatives): result.formUnion(inside(alternatives))
            default: if !pairing(child) { result.formUnion(inside(child.children)) }
            }
        }
    }
}
