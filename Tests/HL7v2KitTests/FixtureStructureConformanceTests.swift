// FixtureStructureConformanceTests.swift
// P8b-5 (G14): every valid-corpus fixture conforms to its declared message
// structure, so the structure rollout probes start from a clean baseline.
// Always on (no environment gate). A fixture whose purpose is a structural
// defect is listed in `deliberatelyNonConformant` with its reason and must
// keep raising at least one structure finding, so a marked fixture that
// becomes valid is noticed. `StructureMatcherCorpusTests` remains the
// env-gated measurement tool for the spec examples.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Fixture structure conformance")
struct FixtureStructureConformanceTests {
    /// Fixtures that are structurally non-conformant by design (ADR-019),
    /// each with the reason; mirrored in `Tests/Fixtures/README.md`.
    static let deliberatelyNonConformant: [String: String] = [
        "msh_with_z_only.hl7": "heartbeat-style MSH plus one Z-segment; ADT_A01's EVN, PID and PV1 are absent on purpose",
    ]

    /// Structure findings: every message-structure issue except
    /// `messageStructureNotModelled` (an unmodelled structure or version is
    /// not a defect in the fixture).
    static func structureFindings(_ report: ValidationReport) -> [ValidationIssue] {
        report.issues.filter {
            switch $0.code {
            case .messageStructureSegmentMissing, .messageStructureSegmentUnexpected, .messageStructureMismatch:
                return true
            default:
                return false
            }
        }
    }

    @Test("Every valid-corpus fixture parses and conforms to its message structure, except the marked ones")
    func corpusConforms() throws {
        var options = ValidationOptions.default
        options.messageStructureSeverity = .error
        let validator = Validator(options: options)
        var checked = 0
        for url in try FixtureCorpus.validFixtureURLs() {
            let name = url.lastPathComponent
            // The valid corpus must parse: a parse failure is a failure, never a skip.
            let message: Message
            do {
                message = try Parser().parse(Data(contentsOf: url))
            } catch {
                Issue.record("\(name) is in the valid corpus but does not parse: \(error)")
                continue
            }
            checked += 1
            let findings = Self.structureFindings(validator.validate(message))
            if let reason = Self.deliberatelyNonConformant[name] {
                #expect(!findings.isEmpty, "\(name) is marked non-conformant (\(reason)) but raised no structure finding")
            } else {
                #expect(findings.isEmpty, "\(name): \(findings.map(\.message))")
            }
        }
        #expect(checked > 0)
    }

    @Test("Every marked fixture exists in the valid corpus")
    func markedFixturesExist() throws {
        let names = Set(try FixtureCorpus.validFixtureURLs().map(\.lastPathComponent))
        for name in Self.deliberatelyNonConformant.keys {
            #expect(names.contains(name), "\(name) is marked but not in the valid corpus")
        }
    }
}
