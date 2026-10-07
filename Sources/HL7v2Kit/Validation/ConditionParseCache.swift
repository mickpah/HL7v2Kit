// ConditionParseCache.swift
// P12 S3-2: the parsed form of each condition string, built on first use.

import Foundation

/// The OR clauses of a condition, each a list of AND atoms parsed by
/// ``ConditionLanguage/parseAtom(_:)`` (`nil` where an atom does not parse),
/// keyed by the condition string.
///
/// Why: the Validator evaluated a condition by splitting and parsing its text
/// on every evaluation, and a profile gate such as `messageCode in (ORU, REF)`
/// is evaluated once per populated field it governs; on a long AU message the
/// parse was the largest single cost (P12 S3-2). The parse is a pure function
/// of the string, and the strings are the finite set the grammar tables and
/// profiles declare, so each is parsed once per process. The pattern and the
/// locking follow `StructureMatcherCache`: `@unchecked Sendable` because every
/// access to the mutable state is under `lock` (NSLock: the deployment targets
/// predate `Synchronization.Mutex` and `OSAllocatedUnfairLock`). Two threads
/// missing at once may both parse; both results are equal.
///
/// The cache is bounded by the condition strings declared in grammars and
/// profiles: message content never enters it, so it cannot grow with input.
final class ConditionParseCache: @unchecked Sendable {
    /// The cache the Validator uses.
    static let shared = ConditionParseCache()

    private let lock = NSLock()
    private var parsed: [String: [[ConditionAtom?]]] = [:]

    /// The clauses of `condition` with each atom parsed.
    func clauses(_ condition: String) -> [[ConditionAtom?]] {
        if let hit = locked({ parsed[condition] }) { return hit }
        let clauses = ConditionLanguage.clauses(condition).map { atoms in
            atoms.map { atom -> ConditionAtom? in
                guard case .success(let parsed) = ConditionLanguage.parseAtom(atom) else { return nil }
                return parsed
            }
        }
        locked { parsed[condition] = clauses }
        return clauses
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
