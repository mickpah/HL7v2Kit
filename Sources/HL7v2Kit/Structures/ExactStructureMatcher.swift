// ExactStructureMatcher.swift
// ADR-019 amendment (P8b-12, owner decision G15): exact matching for the
// structures that fail the determinism lint, where the one-pass greedy
// matcher can accept or reject the wrong messages. The codegen selects it
// (`MessageStructure.requiresExactMatch`); the Validator never lints a message.

/// Matches segment IDs against an HL7 abstract message syntax exactly: it
/// accepts a sequence if and only if some way of matching the whole
/// structure consumes it, however the structure's optional, repeating and
/// choice elements overlap.
///
/// Algorithm: memoisation over (element path, position), evaluated forward.
/// The structure is compiled once into a nondeterministic automaton whose
/// states are the points between elements of the tree (each finite
/// repetition expanded into its copies, each unbounded one a loop, each
/// choice a fork over its alternatives). Matching keeps, at each message
/// position, the set of states some parse can be in there, and advances the
/// whole set by one segment; a (state, position) pair is visited at most
/// once, so no parse is explored twice. This is the backtracking search
/// with every (path, position) result memoised, run breadth first.
///
/// Bounds: the memo held at any moment is one set of at most `stateCount`
/// states (a function of the structure alone, independent of the message),
/// so memory is O(S) and time O(n x (S + E)) for n segments and an
/// automaton of S states and E transitions. S grows with the sum of each
/// element's expanded size; a structure with large finite maxima inside
/// one another grows multiplicatively. HL7 structures have maxima of 1 or
/// unbounded, so S is a few times the structure's element count.
///
/// Z-segments, ADD and the caller's `transparent` IDs are skipped exactly as
/// ``StructureMatcher`` skips them.
///
/// Findings: none when the sequence is accepted. On rejection exactly one:
/// at the furthest position any parse reached. If a segment there cannot be
/// consumed by any live parse, `.unexpected` with that segment and its
/// message index; if the message ended with no parse complete, `.missing`
/// at `ids.count` naming the first segment of the shortest completion from
/// any live parse (ties broken by structure order) and its innermost
/// enclosing group or named choice. `.exceededMaximum` is never reported,
/// and there is no recovery after the first divergence.
///
/// No group spans: an exact match can be ambiguous (several parses accept
/// the same sequence with different group boundaries), so `spans` is always
/// empty (ADR-019 ceiling 3 amendment). Predicates derived from spans skip
/// structures matched this way.
struct ExactStructureMatcher: Sendable {
    let structure: MessageStructure
    private let automaton: Automaton

    init(structure: MessageStructure) {
        self.structure = structure
        self.automaton = Automaton(structure.elements)
    }

    /// The number of automaton states: the bound on the memo held per position.
    var stateCount: Int { automaton.labels.count }

    /// Matches `ids`, the segment IDs of a message in order (MSH first);
    /// `transparent` as for ``StructureMatcher/match(_:transparent:)``.
    func match(_ ids: [String], transparent: Set<String> = []) -> StructureMatch {
        let a = automaton
        var mark = [Int](repeating: -1, count: a.labels.count)
        var live = a.closure([a.start], stamp: 0, &mark)
        var step = 0
        for (index, id) in ids.enumerated() where !StructureMatcher.isTransparent(id) && !transparent.contains(id) {
            var next: [Int] = []
            for state in live where a.labels[state] == id {
                next += a.edges[state]
            }
            guard !next.isEmpty else {
                return StructureMatch(findings: [StructureFinding(kind: .unexpected, segmentID: id, group: nil, index: index)], spans: [])
            }
            step += 1
            live = a.closure(next, stamp: step, &mark)
        }
        if live.contains(a.accept) { return StructureMatch(findings: [], spans: []) }
        let expected = live.filter { a.labels[$0] != nil }
            .min { (a.distance[$0], $0) < (a.distance[$1], $1) }
        let finding = expected.map {
            StructureFinding(kind: .missing, segmentID: a.labels[$0] ?? "", group: a.groups[$0], index: ids.count)
        }
        return StructureMatch(findings: finding.map { [$0] } ?? [], spans: [])
    }
}

/// The compiled structure. A state with a label consumes that segment and
/// moves to its `edges`; a state without one moves along its edges freely.
/// States are numbered in structure order.
private struct Automaton: Sendable {
    private(set) var labels: [String?] = []
    /// For a segment state, the innermost enclosing group or named choice.
    private(set) var groups: [String?] = []
    private(set) var edges: [[Int]] = []
    private(set) var start = 0
    private(set) var accept = 0
    /// The fewest segments that lead from each state to `accept`.
    private(set) var distance: [Int] = []

    init(_ elements: [StructureElement]) {
        start = add(nil, group: nil)
        accept = elements.reduce(start) { element($1, from: $0, group: nil) }
        distance = distancesToAccept()
    }

    private mutating func add(_ label: String?, group: String?) -> Int {
        labels.append(label)
        groups.append(group)
        edges.append([])
        return labels.count - 1
    }

    private mutating func link(_ from: Int, _ to: Int) { edges[from].append(to) }

    /// The fragment for `element` with all its occurrences, entered at
    /// `from`; returns its exit state (always a new state).
    private mutating func element(_ element: StructureElement, from: Int, group: String?) -> Int {
        var current = from
        for _ in 0..<element.min {
            current = occurrence(element, from: current, group: group)
        }
        guard let max = element.max else {
            let hub = add(nil, group: nil)
            link(current, hub)
            link(occurrence(element, from: hub, group: group), hub)
            return hub
        }
        let exit = add(nil, group: nil)
        link(current, exit)
        for _ in element.min..<Swift.max(element.min, max) {
            current = occurrence(element, from: current, group: group)
            link(current, exit)
        }
        return exit
    }

    /// One occurrence of `element` entered at `from`; returns a new exit state.
    private mutating func occurrence(_ element: StructureElement, from: Int, group: String?) -> Int {
        switch element {
        case .segment(let id, _, _):
            let consume = add(id, group: group)
            link(from, consume)
            let exit = add(nil, group: nil)
            link(consume, exit)
            return exit
        case .group(let name, _, _, let children):
            let exit = add(nil, group: nil)
            link(children.reduce(from) { self.element($1, from: $0, group: name) }, exit)
            return exit
        case .choice(let name, _, _, let alternatives):
            let exit = add(nil, group: nil)
            for alternative in alternatives {
                link(self.element(alternative, from: from, group: name ?? group), exit)
            }
            return exit
        }
    }

    /// Shortest paths backwards from `accept`, one bucket per distance:
    /// leaving a segment state costs one segment, any other move nothing.
    private func distancesToAccept() -> [Int] {
        var reverse = [[Int]](repeating: [], count: labels.count)
        for (from, targets) in edges.enumerated() {
            for to in targets { reverse[to].append(from) }
        }
        var result = [Int](repeating: Int.max, count: labels.count)
        result[accept] = 0
        var buckets: [[Int]] = [[accept]]
        var d = 0
        while d < buckets.count {
            var i = 0
            while i < buckets[d].count {
                let state = buckets[d][i]
                i += 1
                guard result[state] == d else { continue }
                for from in reverse[state] {
                    let next = d + (labels[from] == nil ? 0 : 1)
                    guard next < result[from] else { continue }
                    result[from] = next
                    if buckets.count <= next { buckets.append([]) }
                    buckets[next].append(from)
                }
            }
            d += 1
        }
        return result
    }

    /// Every state reachable from `states` through unlabelled states only.
    func closure(_ states: [Int], stamp: Int, _ mark: inout [Int]) -> [Int] {
        var result: [Int] = []
        var stack = states
        while let state = stack.popLast() {
            guard mark[state] != stamp else { continue }
            mark[state] = stamp
            result.append(state)
            if labels[state] == nil { stack += edges[state] }
        }
        return result
    }
}
