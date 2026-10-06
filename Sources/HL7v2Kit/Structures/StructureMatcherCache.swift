// StructureMatcherCache.swift
// P8b-7: the Validator compiles each structure's matcher once and reuses it
// for every message (ADR-019 amendment). Compiling is the exact matcher's
// automaton for a structure flagged `requiresExactMatch`, and the one-pass
// matcher's FIRST and FOLLOW sets for every other.

import Foundation

/// A structure's compiled matcher: the one the codegen flag selects.
enum CompiledStructureMatcher: Sendable {
    case onePass(StructureMatcher)
    case exact(ExactStructureMatcher)

    init(_ structure: MessageStructure) {
        self = structure.requiresExactMatch
            ? .exact(ExactStructureMatcher(structure: structure))
            : .onePass(StructureMatcher(structure: structure))
    }

    var structure: MessageStructure {
        switch self {
        case .onePass(let matcher): return matcher.structure
        case .exact(let matcher): return matcher.structure
        }
    }

    var isExact: Bool {
        if case .exact = self { return true }
        return false
    }

    func match(_ ids: [String], transparent: Set<String> = []) -> StructureMatch {
        switch self {
        case .onePass(let matcher): return matcher.match(ids, transparent: transparent)
        case .exact(let matcher): return matcher.match(ids, transparent: transparent)
        }
    }
}

/// Compiled matchers keyed by structure version and ID, built on first use.
///
/// Why a locked dictionary rather than precomputed statics in the generated
/// table: the Validator also matches structures that are not in the table
/// (tests pass synthetic ones through `resolveStructure(structures:)`), a
/// lazily filled cache compiles only the structures a process actually
/// validates (about 1,200 once every version is modelled), and the codegen
/// stays unchanged. The class is `@unchecked Sendable` because every access
/// to its mutable state is under `lock` (NSLock: the deployment targets
/// predate `Synchronization.Mutex` and `OSAllocatedUnfairLock`).
///
/// A hit requires the cached matcher's structure to equal the one asked
/// for, so a different structure under the same version and ID (a synthetic
/// one in a test) is rebuilt, never served stale. For a generated structure
/// the comparison is cheap: its arrays share storage with the cached copy,
/// and `Array ==` returns on identical storage. Two threads missing at once
/// may both compile; the last one stored wins and both results are correct.
final class StructureMatcherCache: @unchecked Sendable {
    /// The cache the Validator uses.
    static let shared = StructureMatcherCache()

    private struct Key: Hashable {
        let version: String
        let id: String
        /// The keyed-choice selection (S4-1), so each is compiled once.
        var selection: String? = nil
        /// The per-trigger print (S6-1), so each is compiled once.
        var variant: Int? = nil
    }

    private let lock = NSLock()
    private var matchers: [Key: CompiledStructureMatcher] = [:]
    private var builds: [Key: Int] = [:]

    /// The compiled matcher for `structure`, built on the first request.
    func matcher(for structure: MessageStructure) -> CompiledStructureMatcher {
        let key = Key(version: structure.version, id: structure.id, selection: structure.keySelection,
                      variant: structure.variantIndex)
        if let hit = locked({ matchers[key] }), hit.structure == structure { return hit }
        let compiled = CompiledStructureMatcher(structure)
        locked {
            matchers[key] = compiled
            builds[key, default: 0] += 1
        }
        return compiled
    }

    /// How many times the matcher for `version` and `id` has been compiled.
    func buildCount(version: String, id: String) -> Int {
        locked { builds[Key(version: version, id: id)] ?? 0 }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
