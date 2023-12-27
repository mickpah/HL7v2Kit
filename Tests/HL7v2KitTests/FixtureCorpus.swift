// FixtureCorpus.swift
// Shared fixture discovery for the test suites (R8 — the directory
// resolution + `.hl7` filter chain had been re-implemented in six files).
// Auto-discovering suites (round-trip, fuzz, component-grammar,
// conditional, locale, batch) all resolve the corpus through here.

import Foundation

enum FixtureCorpus {
    /// `Tests/Fixtures/`, via `Bundle.module` when populated
    /// (Package.swift bundles it via `.copy("../Fixtures")`), with a
    /// `#filePath` walk-up fallback for test-runner edge cases.
    static func fixturesDirectory() -> URL {
        if let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil) {
            return url
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()       // HL7v2KitTests
            .deletingLastPathComponent()       // Tests
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    /// All top-level `.hl7` fixtures, sorted by file name.
    static func allFixtureURLs() throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: fixturesDirectory(), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "hl7" }
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
    }

    /// The valid corpus — excludes `malformed_*.hl7`.
    static func validFixtureURLs() throws -> [URL] {
        try allFixtureURLs().filter { !$0.lastPathComponent.hasPrefix("malformed_") }
    }

    /// The malformed corpus — `malformed_*.hl7` only.
    static func malformedFixtureURLs() throws -> [URL] {
        try allFixtureURLs().filter { $0.lastPathComponent.hasPrefix("malformed_") }
    }

    /// Batch fixtures under `Fixtures/Batches/`, sorted by file name.
    static func batchFixtureURLs() throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(
                at: fixturesDirectory().appendingPathComponent("Batches", isDirectory: true),
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "hl7" }
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
    }

    /// A single named fixture at the corpus root.
    static func fixtureURL(named name: String) -> URL {
        fixturesDirectory().appendingPathComponent(name)
    }

    /// A single named fixture under `Fixtures/Batches/`.
    static func batchFixtureURL(named name: String) -> URL {
        fixturesDirectory()
            .appendingPathComponent("Batches", isDirectory: true)
            .appendingPathComponent(name)
    }
}
