// StructureDeterminism.swift
// P8b-12 (G15): the ADR-019 determinism lint, run by the codegen over every
// structure it emits, so the generated table records `requiresExactMatch`
// and the Validator never lints a message. The codegen target does not
// depend on the library (Package.swift), so this is a port of
// `StructureMatcher.lint` (Sources/HL7v2Kit/Structures/StructureLint.swift)
// reduced to its verdict. Keep the two in step: the suite's
// StructureGuardTests (guard 1) re-lints every generated structure with the
// library and compares, and scripts/check-structure-codegen.sh checks the
// flag on lint-failing and exempt synthetic shapes.

/// Whether greedy one-pass matching is exact for `elements`: no conflict
/// under the library's lint rule (exempt overlaps allowed). A structure
/// holding an open slot (S3-1) never is: the one-pass matcher enters an
/// element by its FIRST set, and a slot's is every segment (MSH aside), so
/// the current segment never settles whether the slot goes on or ends. The
/// library's lint reports every slot as a conflict; the exact matcher keeps
/// both readings alive and rejects a message only when no parse accepts it.
func structureIsDeterministic(_ elements: [StructureElementSchema]) -> Bool {
    guard !containsSlot(elements) else { return false }
    var deterministic = true
    lintSequence(elements, inherited: LintFollow(), &deterministic)
    return deterministic
}

private func containsSlot(_ elements: [StructureElementSchema]) -> Bool {
    elements.contains { $0.isSlot || containsSlot(($0.elements ?? []) + ($0.alternatives ?? [])) }
}

private struct LintReentry {
    let first: Set<String>
    var prefixNullable = true
    var prefixFirst: Set<String> = []
}

private struct LintFollow {
    var plain: Set<String> = []
    var reentries: [LintReentry] = []
}

private extension StructureElementSchema {
    var children: [StructureElementSchema] {
        if segment != nil { return [] }
        return (isChoice ? alternatives : elements) ?? []
    }

    var firstSet: Set<String> {
        if let id = segment { return [id] }
        if isChoice { return children.reduce(into: Set<String>()) { $0.formUnion($1.firstSet) } }
        return sequenceFirst(children[...])
    }

    var isNullable: Bool {
        if segment != nil { return min == 0 }
        if isChoice { return min == 0 || children.contains(where: \.isNullable) }
        return min == 0 || children.allSatisfy(\.isNullable)
    }
}

private func sequenceFirst(_ elements: ArraySlice<StructureElementSchema>) -> Set<String> {
    var result: Set<String> = []
    for element in elements {
        result.formUnion(element.firstSet)
        if !element.isNullable { break }
    }
    return result
}

private func lintSequence(_ elements: [StructureElementSchema], inherited: LintFollow, _ deterministic: inout Bool) {
    for (i, element) in elements.enumerated() {
        let before = elements[..<i]
        let levelNullable = before.allSatisfy(\.isNullable)
        let levelFirst = before.reduce(into: Set<String>()) { $0.formUnion($1.firstSet) }
        var follow = LintFollow()
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
        let children = element.children
        if element.isChoice, element.key == nil {
            // Choice rule: pairwise-disjoint FIRST sets, no nullable alternative. A keyed
            // choice (S4-1) is decided by its key, so the rule does not apply to it.
            var seen: Set<String> = []
            for alternative in children {
                if !seen.isDisjoint(with: alternative.firstSet) || alternative.isNullable { deterministic = false }
                seen.formUnion(alternative.firstSet)
            }
        }
        if element.isNullable || element.max != 1 {
            for id in first {
                if follow.plain.contains(id) { deterministic = false; continue }
                let hits = follow.reentries.filter { $0.first.contains(id) }
                guard !hits.isEmpty else { continue }
                let sound = levelNullable && !levelFirst.contains(id)
                    && hits.allSatisfy { $0.prefixNullable && !$0.prefixFirst.contains(id) }
                if !sound { deterministic = false }
            }
        }
        if !children.isEmpty {
            var childInherited = follow
            for k in childInherited.reentries.indices {
                childInherited.reentries[k].prefixNullable = childInherited.reentries[k].prefixNullable && levelNullable
                childInherited.reentries[k].prefixFirst.formUnion(levelFirst)
            }
            if element.max == nil {
                childInherited.reentries.append(LintReentry(first: first))
            } else if element.max != 1 {
                childInherited.plain.formUnion(first)
            }
            if element.isChoice {
                for alternative in children {
                    lintSequence([alternative], inherited: childInherited, &deterministic)
                }
            } else {
                lintSequence(children, inherited: childInherited, &deterministic)
            }
        }
    }
}
