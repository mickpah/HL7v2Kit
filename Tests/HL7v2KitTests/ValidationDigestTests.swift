// ValidationDigestTests.swift
// P4-31 (ADR-021): a reproducible digest of every issue the validator
// reports, for proving that a refactor changes no output. It validates the
// extracted spec example messages (SPEC_EXAMPLE_MESSAGES, optional) and
// every test fixture, under both locales, with default options and with the
// three AU caller assertions on, and writes one line per issue to
// VALIDATION_DIGEST_OUT. Run it before and after a change and `cmp` the
// two files. Skipped unless VALIDATION_DIGEST_OUT is set.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Validation digest", .enabled(if: ProcessInfo.processInfo.environment["VALIDATION_DIGEST_OUT"] != nil,
                                     "Set VALIDATION_DIGEST_OUT to the digest path"))
struct ValidationDigestTests {
    struct Example: Decodable { let source: String; let index: Int; let segments: [String] }

    @Test("Digest: every issue on the spec examples and fixtures, both locales")
    func digest() throws {
        let env = ProcessInfo.processInfo.environment
        var wires: [(String, String)] = []
        if let path = env["SPEC_EXAMPLE_MESSAGES"] {
            let examples = try JSONDecoder().decode([Example].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            wires += examples.map { ("\($0.source)#\($0.index)", $0.segments.joined(separator: "\r") + "\r") }
        }
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures")
        let files = (FileManager.default.enumerator(atPath: dir.path)?.allObjects as? [String] ?? [])
            .filter { $0.hasSuffix(".hl7") }.sorted()
        for file in files {
            let text = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
            wires.append((file, text.replacingOccurrences(of: "\n", with: "\r")))
        }
        var asserted = ValidationOptions.default
        asserted.auPathologySender = true
        asserted.auDisplayIntended = true
        asserted.auNASHTransport = true
        var lines: [String] = []
        for (name, wire) in wires {
            for locale in [HL7Locale.international, .auLocalisation] {
                guard let message = try? Parser(locale: locale).parse(wire) else {
                    lines.append("\(name)\t\(locale)\tPARSE")
                    continue
                }
                let validators = [Validator(locale: locale), Validator(options: asserted, locale: locale)]
                for (variant, validator) in validators.enumerated() {
                    for issue in validator.validate(message).issues {
                        lines.append("\(name)\t\(locale)\t\(variant)\t\(issue.severity)\t\(issue.code)\t\(issue.location.pathDescription)\t\(issue.message)")
                    }
                }
            }
        }
        let out = try #require(env["VALIDATION_DIGEST_OUT"])
        try lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
    }
}
