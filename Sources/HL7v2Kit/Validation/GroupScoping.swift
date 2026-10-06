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
/// The scope rule (P8b-17, fix rounds 2 to 4) is one principle: **a group or
/// named choice that occurs at most once per occurrence of its parent is
/// transparent, for the anchor, the peer and the group scope alike; only a
/// repeating nested group that pairs is a boundary; a peer never comes from a
/// repeating sibling.** For one lookup of a peer ID `peer` from an anchor whose
/// ID is `anchor`:
///
/// - **Own level.** A group's own level is its segments and those of the
///   unnamed choices in it (an unnamed choice opens no span), not those of
///   nested groups or named choices.
/// - **Transparency.** A child group or named choice with maximum 1 is
///   transparent: its own-level segments count as part of its parent's own
///   level, recursively. A bracket that cannot repeat makes segments optional
///   together; it is not a scope of its own and never a pairing boundary.
/// - **Pairing boundary.** A *repeating* nested group or named choice N is a
///   boundary for the lookup when it claims its own segments: N's extended own
///   level holds `peer`, and some `anchor` inside N first finds `peer` there
///   (the anchor sits at N's extended own level, or in a nested repeating group
///   whose extended own level does not hold `peer`). Transparency applies here
///   too: v2.4 OML_O21 ORDER { ORC ... [OBSERVATION_REQUEST { OBR ...
///   [{OBSERVATION { OBX }}] }] } claims its OBR for OBX anchors, so a
///   container OBX of the enclosing ORDER_GENERAL does not take it.
///   ORDER_PRIOR { ORC OBR ... {OBSERVATION_PRIOR { OBX }} } is one for ORC, OBR
///   and OBX anchors.
/// - **Extended own level** of a group: its own level plus that of every
///   transparent descendant reached through transparent groups only.
/// - **The anchor's scope.** The anchor's innermost group occurrence, lifted
///   through transparent groups to the nearest repeating enclosing occurrence
///   (fix round 4): an OBR in DFT `[ORDER { OBR }]` is scoped at its
///   COMMON_ORDER occurrence. It is never lifted to the message: when every
///   enclosing group is transparent up to the root, the scope is the innermost
///   group occurrence itself, as before fix round 4.
///
/// The peer (`context(around:of:for:)`) is taken from the anchor's scope when
/// its definition holds `peer` anywhere outside nested pairing boundaries:
/// first from its extended own level, then from the rest of its occurrence
/// except nested pairing boundaries. Otherwise from the extended own level of
/// each enclosing group, outward to the message. The first of these whose
/// definition holds `peer` decides; if its occurrence has none, the peer is
/// absent. So a peer comes from the anchor's scope or the extended own level of
/// a group enclosing it, never from a repeating sibling of the scope, nor from a
/// nested pairing boundary.
///
/// Termination: `context` and `group` move strictly outward along the span
/// parent chain, which ends at the message (nil). Every `ScopeLookup` function
/// recurses strictly inward over the children of a finite definition tree:
/// `transparent` reads the cardinality only and calls nothing; `extended` calls
/// `transparent`; `pairing` calls `claims`, which calls `extended` and
/// `transparent`; `inside` calls `pairing`. None of them calls back into a
/// lookup (`context`, `group`), so every chain of calls ends at the
/// definition's leaves. `region` visits each span at most
/// once (pre-order, skipping a cut subtree). The anchor's innermost span is
/// read from an index built once per message; the rest of a lookup is linear
/// in the region's spans and in the definition's size times its depth.
struct GroupSpanIndex: Sendable {
    let spans: [GroupSpan]
    /// The matched structure's top-level elements; a span's `position` indexes them.
    let elements: [StructureElement]
    /// The message's segment IDs, in order.
    let ids: [String]
    /// The innermost group occurrence holding each message index (nil: none):
    /// the last span, in `spans` order, whose indices contain it. Built once
    /// per message, so a lookup no longer searches the spans (P8b-18).
    let innermost: [Int?]

    init(spans: [GroupSpan], elements: [StructureElement], ids: [String]) {
        self.spans = spans
        self.elements = elements
        self.ids = ids
        var innermost = [Int?](repeating: nil, count: ids.count)
        for (s, span) in spans.enumerated() {
            for index in span.indices where innermost.indices.contains(index) { innermost[index] = s }
        }
        self.innermost = innermost
    }

    /// The message indices, in order, where a peer `peer` of the segment at
    /// `anchor` (whose ID is `anchorID`) may be taken from: the scope rule above.
    func context(around anchor: Int, of anchorID: String, for peer: String) -> [Int] {
        let lookup = ScopeLookup(anchor: anchorID, peer: peer)
        let own = scope(of: anchor, lookup)
        if lookup.inside(children(own)).contains(peer) {
            let near = extendedRegion(own, lookup)
            let nearSet = Set(near)
            return near + insideRegion(own, anchor: anchor, lookup).filter { !nearSet.contains($0) }
        }
        var level = own
        while let at = level {
            level = spans[at].parent
            if lookup.extended(children(level)).contains(peer) { return extendedRegion(level, lookup) }
        }
        return []
    }

    /// The `head`-headed group of the segment at `anchor`, for the group-scope
    /// cardinality rules counting `counted` (`.obrObxGroup`: head OBR): from the
    /// anchor's scope (the same lifting as a peer lookup, for (`counted`,
    /// `head`)), the first group outward whose extended own level holds `head`
    /// is the group, and its occurrence without nested pairing boundaries is
    /// returned, less the `counted` segments that are not the head's own
    /// (S6-2, below). Nil when no enclosing group holds `head`.
    func group(around anchor: Int, holding head: String, counting counted: String) -> [Int]? {
        let lookup = ScopeLookup(anchor: counted, peer: head)
        var level = scope(of: anchor, lookup)
        while true {
            if lookup.extended(children(level)).contains(head) {
                return owned(insideRegion(level, anchor: anchor, lookup), level: level, head: head, counted: counted)
            }
            guard let at = level else { return nil }
            level = spans[at].parent
        }
    }

    /// `region` (the occurrence of `level`) without the `counted` segments that
    /// are not the head's own (S6-2, ADR-019 S6 amendment): those before the
    /// first `head` of the region (v2.8.2 COMMON_ORDER's ORDER_DOCUMENT OBX before
    /// the OBR; the patient OBX before a message-level OBR on ORU_R30), and
    /// those inside a nested group occurrence that does not hold that head and
    /// whose definition cannot begin with `counted`, so another segment heads it
    /// (SPECIMEN { SPM [{OBX}] } on v2.5.1 to v2.8.2 ORU_R01). A nested group
    /// holding the head (OML_O21's OBSERVATION_REQUEST { OBR ... }) or one that
    /// can begin with `counted` (OBSERVATION { OBX ... }, v2.4 `{ [OBX] {NTE} }`)
    /// is the head's, and its own nested groups are read by the same rule. Every
    /// other segment of the region is kept, so the group's first index is
    /// unchanged unless it is such a segment.
    private func owned(_ region: [Int], level: Int?, head: String, counted: String) -> [Int] {
        guard let first = region.first(where: { ids[$0] == head }) else { return region }
        var foreign = Set(region.filter { $0 < first && ids[$0] == counted })
        var s = (level ?? -1) + 1
        while s < spans.count, isDescendant(s, of: level) {
            let starts = element(at: spans[s].position).firstSet
            guard !spans[s].indices.contains(first), !starts.contains(counted),
                  !starts.contains(StructureElement.anySegment) else { s += 1; continue }
            foreign.formUnion(spans[s].indices.filter { ids[$0] == counted })
            let root = s
            s += 1
            while s < spans.count, isDescendant(s, of: root) { s += 1 }
        }
        return region.filter { !foreign.contains($0) }
    }

    /// The anchor's scope: the group occurrence an anchor is treated as sitting
    /// at. Its innermost group occurrence, lifted through transparent
    /// (non-repeating) groups to the nearest repeating enclosing occurrence.
    /// Never the message: when every enclosing group is transparent up to the
    /// root, the innermost group occurrence itself (no lifting).
    private func scope(of anchor: Int, _ lookup: ScopeLookup) -> Int? {
        let innermost = self.innermost.indices.contains(anchor)
            ? self.innermost[anchor] : spans.lastIndex { $0.indices.contains(anchor) }
        var level = innermost
        while let at = level, lookup.transparent(element(at: spans[at].position)) {
            guard let parent = spans[at].parent else { return innermost }
            level = parent
        }
        return level
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
            switch child.unkeyed {
            case .segment(let id, _, _): result.insert(id)
            case .choice(.none, _, _, let alternatives): result.formUnion(ownLevel(alternatives))
            default: break
            }
        }
    }

    /// Whether the group or named choice `group` is a pairing boundary: it
    /// repeats and claims its own segments.
    func pairing(_ group: StructureElement) -> Bool {
        group.max != 1 && claims(group)
    }

    /// Whether `group`'s extended own level holds the peer and an anchor inside it
    /// first finds the peer there, whatever its cardinality.
    func claims(_ group: StructureElement) -> Bool {
        guard extended(group.children).contains(peer) else { return false }
        // An anchor inside `group` finds the peer at `group`'s extended own level
        // unless a repeating group between them holds the peer at its own
        // extended level first; a non-repeating group in between is transparent.
        func unclaimed(_ children: [StructureElement]) -> Bool {
            children.contains { child in
                switch child.unkeyed {
                case .segment(let id, _, _): return id == anchor
                case .choice(.none, _, _, let alternatives): return unclaimed(alternatives)
                default:
                    if transparent(child) { return unclaimed(child.children) }
                    return !extended(child.children).contains(peer) && unclaimed(child.children)
                }
            }
        }
        return unclaimed(group.children)
    }

    /// Whether the group or named choice `group` is transparent: it occurs at
    /// most once per occurrence of its parent.
    func transparent(_ group: StructureElement) -> Bool {
        group.max == 1
    }

    /// The segment IDs of the extended own level of a group with `children`.
    func extended(_ children: [StructureElement]) -> Set<String> {
        children.reduce(into: Set<String>()) { result, child in
            switch child.unkeyed {
            case .segment(let id, _, _): result.insert(id)
            case .choice(.none, _, _, let alternatives): result.formUnion(extended(alternatives))
            default: if transparent(child) { result.formUnion(extended(child.children)) }
            }
        }
    }

    /// The segment IDs defined anywhere in `children` outside pairing boundaries.
    func inside(_ children: [StructureElement]) -> Set<String> {
        children.reduce(into: Set<String>()) { result, child in
            switch child.unkeyed {
            case .segment(let id, _, _): result.insert(id)
            case .choice(.none, _, _, let alternatives): result.formUnion(inside(alternatives))
            default: if !pairing(child) { result.formUnion(inside(child.children)) }
            }
        }
    }
}
