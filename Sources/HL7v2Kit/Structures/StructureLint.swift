// StructureLint.swift
// ADR-019 "Determinism lint": the precondition for matching a structure
// greedily. A structure that fails is never matched; the Validator reports
// it as not modelled.

/// The outcome of the determinism lint over one element tree.
struct StructureLint: Sendable, Equatable {
    /// An optional or repeating element whose FIRST set meets its FOLLOW set.
    struct Overlap: Sendable, Equatable {
        /// Enclosing group names, then the element's own name (a group name
        /// or a segment ID).
        let path: [String]
        /// The shared segment IDs, sorted.
        let segmentIDs: [String]
        /// For an exempt overlap, the enclosing unbounded repeating group
        /// whose re-entry it meets; nil for a conflict.
        let exemptVia: String?
    }

    /// Overlaps that make greedy matching inexact: any one fails the lint.
    let conflicts: [Overlap]
    /// The one accepted case: a repeating element against the re-entry of
    /// an enclosing repeating group with unbounded maximum. The matcher
    /// attributes the segment to the innermost open group.
    let exempt: [Overlap]

    var isDeterministic: Bool { conflicts.isEmpty }
}

extension StructureMatcher {
    /// The follow set of one element, split into segments that may follow
    /// it outright and the re-entries of enclosing unbounded groups
    /// (innermost last).
    private struct Follow {
        var plain: Set<String> = []
        var reentries: [(group: String, first: Set<String>)] = []
    }

    /// The single ADR-019 rule. For every optional or repeating element E,
    /// FIRST(E) must be disjoint from FOLLOW(E): the FIRST sets of the
    /// siblings after E up to and including the next one that is not
    /// nullable (E's own re-entry excluded), extended, when E is trailing,
    /// with the inherited follow set of the enclosing level, which includes
    /// the enclosing group's re-entry when that group repeats. The one exempt
    /// overlap is between a repeating E and the re-entry of an enclosing
    /// group whose maximum is unbounded. Z-segments and ADD never appear in
    /// a structure, so they are not checked.
    static func lint(_ elements: [StructureElement]) -> StructureLint {
        var conflicts: [StructureLint.Overlap] = []
        var exempt: [StructureLint.Overlap] = []
        lintSequence(elements, path: [], inherited: Follow(), &conflicts, &exempt)
        return StructureLint(conflicts: conflicts, exempt: exempt)
    }

    private static func lintSequence(
        _ elements: [StructureElement],
        path: [String],
        inherited: Follow,
        _ conflicts: inout [StructureLint.Overlap],
        _ exempt: inout [StructureLint.Overlap]
    ) {
        for (i, element) in elements.enumerated() {
            var follow = Follow()
            var trailing = true
            for sibling in elements[(i + 1)...] {
                follow.plain.formUnion(sibling.firstSet)
                if !sibling.isNullable { trailing = false; break }
            }
            if trailing {
                follow.plain.formUnion(inherited.plain)
                follow.reentries = inherited.reentries
            }
            let first = element.firstSet
            let name: String
            switch element {
            case .segment(let id, _, _): name = id
            case .group(let group, _, _, _): name = group
            }
            if element.isNullable || element.max != 1 {
                let repeating = element.max != 1
                var hard = first.intersection(follow.plain)
                var viaGroup: [(group: String, ids: Set<String>)] = []
                for id in first.sorted() where !hard.contains(id) {
                    guard let via = follow.reentries.last(where: { $0.first.contains(id) }) else { continue }
                    if !repeating {
                        hard.insert(id)
                    } else if let at = viaGroup.firstIndex(where: { $0.group == via.group }) {
                        viaGroup[at].ids.insert(id)
                    } else {
                        viaGroup.append((via.group, [id]))
                    }
                }
                if !hard.isEmpty {
                    conflicts.append(.init(path: path + [name], segmentIDs: hard.sorted(), exemptVia: nil))
                }
                for entry in viaGroup {
                    exempt.append(.init(path: path + [name], segmentIDs: entry.ids.sorted(), exemptVia: entry.group))
                }
            }
            if case .group(let group, _, let max, let children) = element {
                var childInherited = follow
                if max == nil {
                    childInherited.reentries.append((group, first))
                } else if max != 1 {
                    childInherited.plain.formUnion(first)
                }
                lintSequence(children, path: path + [group], inherited: childInherited, &conflicts, &exempt)
            }
        }
    }
}
