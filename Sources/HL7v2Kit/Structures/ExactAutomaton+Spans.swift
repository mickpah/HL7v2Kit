// ExactAutomaton+Spans.swift
// P8b-17 (ADR-019, amending P8b-12): group spans for an accepted exact match,
// given only when every accepting parse puts every segment in the same group
// occurrences.

extension ExactAutomaton {
    /// One parse's account of a consumed segment: the groups enclosing it,
    /// outermost first, and those of them whose occurrence it begins.
    private struct Placement: Hashable {
        let ancestry: [Int]
        let fresh: Set<Int>
    }

    private struct Visit: Hashable {
        let state: Int
        let entered: Set<Int>
    }

    /// The group spans of an accepted sequence, or nil when two accepting
    /// parses place some segment differently. `lives[k]` is the state set
    /// after `k` consumed segments; `steps[k]` the message index and ID of
    /// the segment consumed `k + 1`th.
    ///
    /// A parse places the segment it consumes at state `t` in the groups of
    /// `t`'s ancestry, and begins a new occurrence of each of them whose entry
    /// state lies on the path from the previous consumed segment (a group
    /// occurrence cannot be left and that group re-entered without passing
    /// its entry again). Only states on some accepting parse are counted:
    /// those reachable forward (`lives`) from which the rest of the sequence
    /// can still be consumed and the structure completed. Every such move
    /// extends to an accepting parse, so the parses agree exactly when each
    /// step admits one placement.
    func spans(lives: [[Int]], steps: [(index: Int, id: String)]) -> [GroupSpan]? {
        let n = steps.count
        guard n > 0 else { return [] }
        // useful[k]: the states consuming segment k + 1 on some accepting parse.
        var useful = [Set<Int>](repeating: [], count: n)
        // What `t` reaches depends on `t` alone: computed once per state (P8b-18).
        var reachFrom: [Int: Set<Int>] = [:]
        for k in stride(from: n - 1, through: 0, by: -1) {
            for t in lives[k] where labels[t] == steps[k].id {
                let reach = reachFrom[t] ?? reachable(from: edges[t])
                reachFrom[t] = reach
                if k == n - 1 ? reach.contains(accept) : !reach.isDisjoint(with: useful[k + 1]) {
                    useful[k].insert(t)
                }
            }
        }
        var placements: [Placement] = []
        for k in 0..<n {
            let sources = k == 0 ? [start] : useful[k - 1].flatMap { edges[$0] }
            var found: Set<Placement> = []
            var seen: Set<Visit> = []
            var stack = sources.map { Visit(state: $0, entered: []) }
            while let visit = stack.popLast() {
                guard seen.insert(visit).inserted else { continue }
                let state = visit.state
                if labels[state] != nil {
                    if useful[k].contains(state) {
                        found.insert(Placement(ancestry: ancestry[state],
                                               fresh: visit.entered.intersection(ancestry[state])))
                    }
                    continue
                }
                var entered = visit.entered
                if let id = entries[state] { entered.insert(id) }
                stack += edges[state].map { Visit(state: $0, entered: entered) }
            }
            guard found.count == 1, let only = found.first else { return nil }
            placements.append(only)
        }
        return build(placements, steps: steps)
    }

    /// Every state reachable from `states` through unlabelled states.
    private func reachable(from states: [Int]) -> Set<Int> {
        var result: Set<Int> = []
        var stack = states
        while let state = stack.popLast() {
            guard result.insert(state).inserted else { continue }
            if labels[state] == nil { stack += edges[state] }
        }
        return result
    }

    /// The spans, in pre-order, of one placement per consumed segment.
    private func build(_ placements: [Placement], steps: [(index: Int, id: String)]) -> [GroupSpan] {
        var spans: [(group: Int, start: Int, end: Int, parent: Int?)] = []
        var open: [(group: Int, span: Int)] = []
        for (k, placement) in placements.enumerated() {
            let index = steps[k].index
            var keep = 0
            while keep < open.count, keep < placement.ancestry.count,
                  open[keep].group == placement.ancestry[keep],
                  !placement.fresh.contains(placement.ancestry[keep]) {
                keep += 1
            }
            open.removeLast(open.count - keep)
            for group in placement.ancestry[keep...] {
                spans.append((group, index, index, open.last?.span))
                open.append((group, spans.count - 1))
            }
            for entry in open { spans[entry.span].end = index }
        }
        var paths: [[String]] = []
        for span in spans {
            paths.append((span.parent.map { paths[$0] } ?? []) + [groupTable[span.group].name])
        }
        return spans.indices.map { i in
            let group = groupTable[spans[i].group]
            return GroupSpan(path: paths[i], indices: spans[i].start...spans[i].end, parent: spans[i].parent,
                             position: group.position)
        }
    }
}
