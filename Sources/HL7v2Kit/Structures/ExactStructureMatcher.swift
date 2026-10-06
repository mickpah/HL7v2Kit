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
/// message index, and the match's `expectedHere` lists the segments the live
/// parses could consume there (each once, in structure order, so at most the
/// structure's distinct segment IDs) with `endExpectedHere` when one is
/// complete: when a required segment is absent mid-message the finding sits
/// on the segment after it, and this names the absent one (P8b-final, F-I3);
/// if the message ended with no parse complete, `.missing`
/// at `ids.count` naming the first segment of the shortest completion from
/// any live parse (ties broken by structure order) and its innermost
/// enclosing group or named choice. `.exceededMaximum` is never reported,
/// and there is no recovery after the first divergence.
///
/// An open slot (S3-1, controller ruling) compiles like a segment whose state
/// consumes any segment except MSH, its occurrences bounded by the slot's
/// `min` and `max`. It is nondeterministic: a segment that could begin what
/// follows the slot may also stay in it, and a sequence is rejected only when
/// no parse accepts. A finding that names the slot uses its printed name.
///
/// Group spans (P8b-17, amending P8b-12): an exact match can be ambiguous,
/// several parses accepting the same sequence. An accepted sequence has spans
/// only when every accepting parse assigns every segment to the same group
/// occurrences; then `spans` is that one assignment, in the form
/// ``StructureMatcher`` gives. When accepting parses disagree, `spans` is empty
/// and `spansWithheld` is true. A rejected sequence has no spans. The verdict
/// and the finding do not depend on this.
struct ExactStructureMatcher: Sendable {
    let structure: MessageStructure
    private let automaton: ExactAutomaton

    init(structure: MessageStructure) {
        self.structure = structure
        self.automaton = ExactAutomaton(structure.elements)
    }

    /// The number of automaton states: the bound on the memo held per position.
    var stateCount: Int { automaton.labels.count }

    /// Matches `ids`, the segment IDs of a message in order (MSH first);
    /// `transparent` as for ``StructureMatcher/match(_:transparent:)``.
    func match(_ ids: [String], transparent: Set<String> = []) -> StructureMatch {
        let a = automaton
        var mark = [Int](repeating: -1, count: a.labels.count)
        var live = a.closure([a.start], stamp: 0, &mark)
        var lives = [live]
        var steps: [(index: Int, id: String)] = []
        for (index, id) in ids.enumerated() where !StructureMatcher.isTransparent(id) && !transparent.contains(id) {
            var next: [Int] = []
            for state in live where a.consumes(state, id) {
                next += a.edges[state]
            }
            guard !next.isEmpty else {
                // What the live parses could consume here, each ID once in structure
                // order (states are numbered in structure order): the absent segment
                // when a required one is missing before this one (F-I3).
                var seen = Set<String>()
                let expected = live.sorted().compactMap { a.labels[$0] }.filter { seen.insert($0).inserted }
                var match = StructureMatch(findings: [StructureFinding(kind: .unexpected, segmentID: id, group: nil, index: index)], spans: [])
                match.expectedHere = expected
                match.endExpectedHere = live.contains(a.accept)
                return match
            }
            steps.append((index, id))
            live = a.closure(next, stamp: steps.count, &mark)
            lives.append(live)
        }
        if live.contains(a.accept) {
            guard let spans = a.spans(lives: lives, steps: steps) else {
                return StructureMatch(findings: [], spans: [], spansWithheld: true)
            }
            return StructureMatch(findings: [], spans: spans)
        }
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
struct ExactAutomaton: Sendable {
    private(set) var labels: [String?] = []
    /// For a segment state, the innermost enclosing group or named choice.
    private(set) var groups: [String?] = []
    /// For the entry state of a group (or named choice) occurrence, the group.
    private(set) var entries: [Int?] = []
    /// For a segment state, the groups enclosing it, outermost first.
    private(set) var ancestry: [[Int]] = []
    /// The groups and named choices, by structure position.
    private(set) var groupTable: [(name: String, position: [Int])] = []
    private(set) var edges: [[Int]] = []
    private(set) var start = 0
    private(set) var accept = 0
    /// The fewest segments that lead from each state to `accept`.
    private(set) var distance: [Int] = []
    /// Whether each state is a slot state (S3-1). A slot state's label is the
    /// slot's printed name, for findings only; it consumes any segment but MSH.
    private(set) var slots: [Bool] = []

    init(_ elements: [StructureElement]) {
        start = add(nil, group: nil)
        accept = elements.indices.reduce(start) { element(elements[$1], from: $0, group: nil, position: [$1], ancestry: []) }
        distance = distancesToAccept()
    }

    /// Whether `state` consumes a segment with ID `id`.
    func consumes(_ state: Int, _ id: String) -> Bool {
        slots[state] ? id != "MSH" : labels[state] == id
    }

    private mutating func add(_ label: String?, group: String?) -> Int {
        labels.append(label)
        groups.append(group)
        entries.append(nil)
        ancestry.append([])
        edges.append([])
        slots.append(false)
        return labels.count - 1
    }

    private mutating func link(_ from: Int, _ to: Int) { edges[from].append(to) }

    /// The fragment for `element` with all its occurrences, entered at
    /// `from`; returns its exit state (always a new state).
    private mutating func element(_ element: StructureElement, from: Int, group: String?,
                                  position: [Int], ancestry: [Int]) -> Int {
        var current = from
        for _ in 0..<element.min {
            current = occurrence(element, from: current, group: group, position: position, ancestry: ancestry)
        }
        guard let max = element.max else {
            let hub = add(nil, group: nil)
            link(current, hub)
            link(occurrence(element, from: hub, group: group, position: position, ancestry: ancestry), hub)
            return hub
        }
        let exit = add(nil, group: nil)
        link(current, exit)
        for _ in element.min..<Swift.max(element.min, max) {
            current = occurrence(element, from: current, group: group, position: position, ancestry: ancestry)
            link(current, exit)
        }
        return exit
    }

    /// The table index of the group or named choice at `position`.
    private mutating func groupID(_ name: String, _ position: [Int]) -> Int {
        if let id = groupTable.firstIndex(where: { $0.position == position }) { return id }
        groupTable.append((name, position))
        return groupTable.count - 1
    }

    /// An unlabelled state that marks entering an occurrence of group `id`.
    private mutating func entry(_ id: Int, from: Int) -> Int {
        let state = add(nil, group: nil)
        entries[state] = id
        link(from, state)
        return state
    }

    /// One occurrence of `element` entered at `from`; returns a new exit state.
    private mutating func occurrence(_ element: StructureElement, from: Int, group: String?,
                                     position: [Int], ancestry: [Int]) -> Int {
        switch element {
        case .segment(let id, _, _):
            let consume = add(id, group: group)
            self.ancestry[consume] = ancestry
            link(from, consume)
            let exit = add(nil, group: nil)
            link(consume, exit)
            return exit
        case .group(let name, _, _, let children):
            let exit = add(nil, group: nil)
            let id = groupID(name, position)
            let start = entry(id, from: from)
            link(children.indices.reduce(start) {
                self.element(children[$1], from: $0, group: name, position: position + [$1], ancestry: ancestry + [id])
            }, exit)
            return exit
        case .choice(let name, _, _, let alternatives), .keyedChoice(let name, _, _, _, let alternatives):
            // A keyed choice is resolved before matching (S4-1); one left
            // unresolved is matched as its plain choice.
            let exit = add(nil, group: nil)
            var start = from, inner = ancestry
            if let name {
                let id = groupID(name, position)
                start = entry(id, from: from)
                inner.append(id)
            }
            for a in alternatives.indices {
                link(self.element(alternatives[a], from: start, group: name ?? group,
                                  position: position + [a], ancestry: inner), exit)
            }
            return exit
        case .slot:
            // One segment of the slot's run: any but MSH. Whether a segment
            // stays in the slot or begins what follows is left open; the
            // breadth-first state sets keep both parses alive. It opens no
            // group, so its segments lie in the enclosing spans.
            let consume = add(element.label, group: group)
            self.ancestry[consume] = ancestry
            slots[consume] = true
            link(from, consume)
            let exit = add(nil, group: nil)
            link(consume, exit)
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
