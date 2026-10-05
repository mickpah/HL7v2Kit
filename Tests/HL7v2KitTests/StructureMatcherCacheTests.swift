// StructureMatcherCacheTests.swift
// P8b-7: the Validator compiles each structure's matcher once (the exact
// matcher's automaton, the one-pass matcher's FIRST sets) and reuses it for
// every message, and its choice of matcher is the codegen flag.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Structure matcher cache")
struct StructureMatcherCacheTests {
    /// A lint-failing structure (the pre-v2.5 ORU shape) on real segment IDs,
    /// under an ID no other test uses, so the build count is this suite's alone.
    static func flagged(_ id: String) -> MessageStructure {
        MessageStructure(id: id, version: "2.5.1", triggers: ["ORU^R01"], citation: "synthetic", elements: StructureShapes.preV25)
    }

    static func message(_ body: [String]) throws -> Message {
        try Parser().parse(MessageStructureValidationTests.wire("ORU^R01^ORU_R01", body))
    }

    @Test("Validating 1,000 messages against one flagged structure builds one automaton")
    func thousandMessagesOneBuild() throws {
        let structure = Self.flagged("P8B7_CACHE_A")
        #expect(structure.requiresExactMatch)
        let clean = try Self.message(["OBR|1", "NTE|1", "OBX|1", "NTE|2", "OBX|2"])
        let broken = try Self.message(["NTE|1", "OBR|1"])
        let validator = Validator()
        let clock = ContinuousClock()
        let cached = clock.measure {
            for i in 0..<1_000 {
                let issues = validator.matchStructure(structure, message: i % 2 == 0 ? clean : broken, severity: .error)
                #expect(issues.isEmpty == (i % 2 == 0))
            }
        }
        #expect(StructureMatcherCache.shared.buildCount(version: "2.5.1", id: "P8B7_CACHE_A") == 1)
        let rebuilt = clock.measure {
            for _ in 0..<1_000 { _ = ExactStructureMatcher(structure: structure).match(["MSH", "OBR", "NTE", "OBX"]) }
        }
        print("structure-cache: 1,000 messages through the cache \(cached); 1,000 automaton builds \(rebuilt)")
    }

    @Test("A different structure under the same version and ID is rebuilt, never served stale")
    func changedStructureRebuilt() {
        let cache = StructureMatcherCache()
        let first = Self.flagged("P8B7_CACHE_B")
        let second = MessageStructure(id: "P8B7_CACHE_B", version: "2.5.1", triggers: ["ORU^R01"], citation: "synthetic",
                                      elements: [.segment("MSH", min: 1, max: 1), .segment("PID", min: 1, max: 1)])
        #expect(cache.matcher(for: first).match(["MSH", "OBR"]).findings.isEmpty)
        #expect(cache.matcher(for: first).match(["MSH", "OBR"]).findings.isEmpty)
        #expect(cache.buildCount(version: "2.5.1", id: "P8B7_CACHE_B") == 1)
        #expect(!cache.matcher(for: second).match(["MSH", "OBR"]).findings.isEmpty)
        #expect(cache.buildCount(version: "2.5.1", id: "P8B7_CACHE_B") == 2)
    }

    @Test("The cached matcher for every committed structure is the one its flag selects, built once")
    func selectionEqualsFlag() {
        let cache = StructureMatcherCache()
        for version in StructureGuardTests.grammarVersions {
            for (id, structure) in MessageStructureTable.structures(for: version) {
                let compiled = cache.matcher(for: structure)
                _ = cache.matcher(for: structure)
                #expect(compiled.isExact == structure.requiresExactMatch, "\(version.rawValue) \(id)")
                #expect(cache.buildCount(version: structure.version, id: id) == 1, "\(version.rawValue) \(id)")
            }
        }
    }

    @Test("Concurrent lookups of one structure all receive a working matcher")
    func concurrentLookups() async {
        let cache = StructureMatcherCache()
        let structure = Self.flagged("P8B7_CACHE_C")
        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<64 {
                group.addTask { cache.matcher(for: structure).match(["MSH", "OBR", "OBX"]).findings.isEmpty }
            }
            return await group.reduce(into: [Bool]()) { $0.append($1) }
        }
        #expect(results.count == 64 && results.allSatisfy { $0 })
        // Simultaneous first lookups may each build; every later one is a hit.
        #expect((1...64).contains(cache.buildCount(version: "2.5.1", id: "P8B7_CACHE_C")))
    }
}
