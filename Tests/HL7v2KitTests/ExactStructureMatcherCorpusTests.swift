// ExactStructureMatcherCorpusTests.swift
// P8b-12 (G15) proof on real structures: the 44 lint-failing structures on
// which the P8b-3b run found the one-pass matcher wrong (p8b-3b-lint.tsv,
// "N disagree" with N > 0). Their JSON is not committed: it is read from an
// extractor dump (`extract-message-structures.py --dump DIR`, never under
// Resources/) through StructureJSONDecoder (the codegen's acceptance
// rules, P8b-7). On each, the exact matcher must agree with the reference recogniser on every generated sequence:
// `bound` per structure (default 500: about 12 s in a debug build; 3,000
// takes about 70 s), seeded derivations of the grammar of at most 120
// segments with the property test's four single-edit mutations each. The
// property test's own generator drops derivations longer than its length
// bound, which on CSU_C09 costs seconds per hundred sequences. Skipped unless
// STRUCTURE_LINT_CORPUS is set; EXACT_CORPUS_BOUND overrides the bound.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Exact matcher on the P8b-3b disagreeing structures",
       .enabled(if: ProcessInfo.processInfo.environment["STRUCTURE_LINT_CORPUS"] != nil,
                "Set STRUCTURE_LINT_CORPUS to an extractor --dump directory"))
struct ExactStructureMatcherCorpusTests {
    static let disagreeing: [(version: String, id: String)] = [
        ("2.3.1", "CSU_C09"), ("2.3.1", "OMD_O01"), ("2.3.1", "ORD_O02"), ("2.4", "CSU_C09"), ("2.4", "OMD_O03"),
        ("2.5.1", "CSU_C09"), ("2.5.1", "OMD_O03"), ("2.5.1", "OMG_O19"), ("2.5.1", "OML_O21"), ("2.5.1", "OML_O33"),
        ("2.5.1", "OML_O35"), ("2.5.1", "ORD_O04"), ("2.5.1", "ORL_O34"), ("2.5.1", "OUL_R24"), ("2.6", "CSU_C09"),
        ("2.6", "EHC_E15"), ("2.6", "OMD_O03"), ("2.6", "OMG_O19"), ("2.6", "OML_O21"), ("2.6", "OML_O33"),
        ("2.6", "OML_O35"), ("2.6", "ORD_O04"), ("2.6", "OUL_R24"), ("2.7.1", "CSU_C09"), ("2.7.1", "EHC_E15"),
        ("2.7.1", "OMD_O03"), ("2.7.1", "OMG_O19"), ("2.7.1", "OML_O21"), ("2.7.1", "OML_O33"), ("2.7.1", "OML_O35"),
        ("2.7.1", "ORD_O04"), ("2.7.1", "OUL_R24"), ("2.8.2", "CSU_C09"), ("2.8.2", "OMD_O03"), ("2.8.2", "OMG_O19"),
        ("2.8.2", "OML_O21"), ("2.8.2", "OML_O33"), ("2.8.2", "OML_O35"), ("2.8.2", "OMQ_O42"), ("2.8.2", "OPL_O37"),
        ("2.8.2", "ORD_O04"), ("2.8.2", "OUL_R22"), ("2.8.2", "OUL_R23"), ("2.8.2", "OUL_R24"),
    ]

    /// Derivations of at most 120 segments and four mutations of each, `bound` in all.
    static func sequences(_ elements: [StructureElement], bound: Int) -> [[String]] {
        let letters = StructureMatcherPropertyTests.alphabet(elements).filter { $0 != "MSH" }
        var rng = StructureMatcherPropertyTests.Seeded(state: 1_2)
        var result: [[String]] = []
        var attempts = 0
        while result.count < bound, attempts < 100_000 {
            attempts += 1
            let valid = StructureMatcherPropertyTests.derive(elements, &rng)
            guard valid.count <= 120 else { continue }
            result.append(valid)
            result += StructureMatcherPropertyTests.mutations(valid, letters, &rng)
        }
        return Array(result.prefix(bound))
    }

    @Test("The exact matcher agrees with the reference on all 44; the one-pass matcher does not")
    func disagreeingStructures() throws {
        let env = ProcessInfo.processInfo.environment
        let root = URL(fileURLWithPath: try #require(env["STRUCTURE_LINT_CORPUS"]))
        let bound = env["EXACT_CORPUS_BOUND"].flatMap(Int.init) ?? 500
        var checked = 0, onePassWrong = 0, acceptedCount = 0, maxStates = 0
        for (version, id) in Self.disagreeing {
            let url = root.appendingPathComponent("v\(version)/\(id).json")
            let elements = try StructureJSONDecoder.decode(Data(contentsOf: url), id: id, version: version).elements
            let structure = MessageStructure(id: id, version: version, triggers: [], citation: "corpus", elements: elements)
            #expect(structure.requiresExactMatch, "\(version) \(id) passes the lint")
            let sequences = Self.sequences(elements, bound: bound)
            #expect(sequences.count == bound, "\(version) \(id): \(sequences.count) sequences")
            let exact = ExactStructureMatcher(structure: structure)
            maxStates = max(maxStates, exact.stateCount)
            let onePass = StructureMatcher(structure: structure)
            var wrong: [String] = []
            for sequence in sequences {
                let accepted = StructureMatcherPropertyTests.referenceAccepts(elements, sequence)
                if accepted { acceptedCount += 1 }
                if exact.match(sequence).findings.isEmpty != accepted { wrong.append(sequence.joined(separator: " ")) }
                if onePass.match(sequence).findings.isEmpty != accepted { onePassWrong += 1 }
            }
            checked += sequences.count
            #expect(wrong.isEmpty, "\(version) \(id): \(wrong.prefix(2))")
        }
        print("exact-corpus: \(Self.disagreeing.count) structures, \(checked) sequences, bound \(bound), \(acceptedCount) accepted, one-pass wrong on \(onePassWrong), at most \(maxStates) automaton states")
        #expect(onePassWrong > 0)
    }
}
