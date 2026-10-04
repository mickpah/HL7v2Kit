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
    /// The one accepted case: an element against the re-entry of an
    /// enclosing group with unbounded maximum that can begin with the
    /// segment only through the element itself (see `lint(_:)`). The
    /// matcher attributes the segment to the innermost open group.
    let exempt: [Overlap]

    var isDeterministic: Bool { conflicts.isEmpty }
}

extension StructureMatcher {
    /// The re-entry of an enclosing group with unbounded maximum, as seen
    /// from one sequence inside it: the group's FIRST set, and the elements
    /// that precede the path down to this sequence at every level between
    /// (whether all are nullable, and the union of their FIRST sets).
    private struct Reentry {
        let group: String
        let first: Set<String>
        var prefixNullable = true
        var prefixFirst: Set<String> = []
    }

    /// The follow set of one element, split into segments that may follow
    /// it outright and the re-entries of enclosing unbounded groups
    /// (innermost last).
    private struct Follow {
        var plain: Set<String> = []
        var reentries: [Reentry] = []
    }

    /// The single ADR-019 rule. For every element E that is nullable or may
    /// repeat, FIRST(E) must be disjoint from FOLLOW(E): the FIRST sets of
    /// the siblings after E up to and including the next one that is not
    /// nullable (E's own re-entry excluded), extended, when E is trailing,
    /// with the inherited follow set of the enclosing level, which includes
    /// the enclosing group's re-entry when that group repeats.
    ///
    /// One overlap is exempt: segment S of FIRST(E) that S reaches only
    /// through the re-entry of enclosing groups G with unbounded maximum,
    /// where for each such G the re-entry can begin with S only through E
    /// itself: on the path from G down to E, every element that precedes
    /// the path at each level is nullable and none of their FIRST sets
    /// contains S. Staying in E and opening a new G instance then lead to
    /// the same remaining match, so the greedy choice (stay in E) loses
    /// nothing. This holds whether or not E repeats; for a non-repeating E
    /// the only other parse inserts an instance boundary at E. The
    /// reference-recogniser property test is the guard on this rule.
    ///
    /// A choice is an element like any other here (its FIRST set is the
    /// union of its alternatives'); each alternative is linted as the one
    /// element of a sequence whose follow set is the choice's, with the
    /// choice's re-entry when it repeats, and the choice rule
    /// (`choiceConflicts`) adds its own conflicts. An unnamed choice is
    /// named `<A|B>` in paths.
    /// Z-segments and ADD never appear in a structure, so they are not
    /// checked.
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
            let before = elements[..<i]
            let levelNullable = before.allSatisfy(\.isNullable)
            let levelFirst = before.reduce(into: Set<String>()) { $0.formUnion($1.firstSet) }
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
            let name = element.label
            if case .choice(_, _, _, let alternatives) = element {
                choiceConflicts(alternatives, path: path + [name], &conflicts)
            }
            if element.isNullable || element.max != 1 {
                var hard = first.intersection(follow.plain)
                var viaGroup: [(group: String, ids: Set<String>)] = []
                for id in first.sorted() where !hard.contains(id) {
                    let hits = follow.reentries.filter { $0.first.contains(id) }
                    guard let via = hits.last else { continue }
                    let sound = levelNullable && !levelFirst.contains(id)
                        && hits.allSatisfy { $0.prefixNullable && !$0.prefixFirst.contains(id) }
                    if !sound {
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
            let children = element.children
            if !children.isEmpty {
                let max = element.max
                var childInherited = follow
                for k in childInherited.reentries.indices {
                    childInherited.reentries[k].prefixNullable = childInherited.reentries[k].prefixNullable && levelNullable
                    childInherited.reentries[k].prefixFirst.formUnion(levelFirst)
                }
                if max == nil {
                    childInherited.reentries.append(Reentry(group: name, first: first))
                } else if max != 1 {
                    childInherited.plain.formUnion(first)
                }
                if case .choice = element {
                    // Each alternative is the one element of its own sequence:
                    // what follows it is what follows the choice.
                    for alternative in children {
                        lintSequence([alternative], path: path + [name], inherited: childInherited, &conflicts, &exempt)
                    }
                } else {
                    lintSequence(children, path: path + [name], inherited: childInherited, &conflicts, &exempt)
                }
            }
        }
    }

    /// The choice rule (P8b-6): the one-pass matcher picks an alternative by
    /// the current segment alone, so the alternatives' FIRST sets must be
    /// pairwise disjoint; and no alternative may be nullable, since an empty
    /// occurrence could then be taken through it or through the choice's own
    /// bounds, and the matcher does not decide between them. Overlapping
    /// segments are reported at the choice; a nullable alternative at the
    /// alternative, with its FIRST set.
    private static func choiceConflicts(
        _ alternatives: [StructureElement],
        path: [String],
        _ conflicts: inout [StructureLint.Overlap]
    ) {
        var seen: Set<String> = []
        var shared: Set<String> = []
        for alternative in alternatives {
            shared.formUnion(seen.intersection(alternative.firstSet))
            seen.formUnion(alternative.firstSet)
        }
        if !shared.isEmpty {
            conflicts.append(.init(path: path, segmentIDs: shared.sorted(), exemptVia: nil))
        }
        for alternative in alternatives where alternative.isNullable {
            conflicts.append(.init(path: path + [alternative.label], segmentIDs: alternative.firstSet.sorted(), exemptVia: nil))
        }
    }
}
