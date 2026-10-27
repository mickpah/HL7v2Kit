// Baseline.swift
// Committed expected outputs under Tests/Fixtures/Baselines/. A test compares its lines with
// the file; BASELINE_WRITE=1 rewrites the file instead, and the diff is reviewed before commit.

import Foundation
import Testing

enum Baseline {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // HL7v2KitTests
        .deletingLastPathComponent()   // Tests
        .appendingPathComponent("Fixtures/Baselines", isDirectory: true)

    /// Compares `lines` with the baseline `name`, or writes it when `BASELINE_WRITE` is set.
    static func check(_ lines: [String], against name: String) throws {
        let url = directory.appendingPathComponent(name)
        if ProcessInfo.processInfo.environment["BASELINE_WRITE"] != nil {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            return
        }
        let expected = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
        let first = zip(lines, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset
            ?? min(lines.count, expected.count)
        #expect(lines == expected, "\(name) differs from line \(first + 1); BASELINE_WRITE=1 rewrites it")
    }
}
