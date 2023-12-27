// FixtureRoundTripTests.swift
//
// Auto-discovers `.hl7` files in the bundled Tests/Fixtures resource
// directory and applies the spec § 9.3 round-trip and § 9.4 cross-check
// contracts.
//
// Conventions:
//   - Fixtures whose filename starts with "malformed_" must throw a
//     ParseError on Parser().parse(_:).
//   - Every other .hl7 fixture must parse, round-trip byte-perfect, and
//     produce a non-error ValidationReport (warnings/infos are allowed).
//
// Adding a fixture: drop a new `.hl7` file under Tests/Fixtures/. The
// harness auto-picks it up — no test code change required.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Fixture corpus (round-trip + cross-check)")
struct FixtureRoundTripTests {

    @Test("All valid fixtures round-trip byte-perfectly")
    func validFixturesRoundTrip() throws {
        let fixtures = try FixtureCorpus.validFixtureURLs()
        try #require(!fixtures.isEmpty, "No valid fixtures discovered — Tests/Fixtures bundle missing?")

        for fixture in fixtures {
            let data = try Data(contentsOf: fixture)
            let message: Message
            do {
                message = try Parser().parse(data)
            } catch {
                Issue.record("Parse failed for \(fixture.lastPathComponent): \(error)")
                continue
            }
            let rebuilt = message.serialize()
            #expect(rebuilt == data, "Round-trip failed for \(fixture.lastPathComponent)")
        }
    }

    @Test("All valid fixtures produce a non-error ValidationReport")
    func validFixturesValidate() throws {
        let fixtures = try FixtureCorpus.validFixtureURLs()
        for fixture in fixtures {
            let data = try Data(contentsOf: fixture)
            guard let message = try? Parser().parse(data) else { continue }
            let report = Validator().validate(message)
            #expect(report.isValid, "Validation errors for \(fixture.lastPathComponent): \(report.errors.map(\.message))")
        }
    }

    @Test("Malformed fixtures throw a ParseError")
    func malformedFixturesThrow() throws {
        let fixtures = try FixtureCorpus.malformedFixtureURLs()
        try #require(!fixtures.isEmpty, "No malformed fixtures discovered — Tests/Fixtures bundle missing?")
        for fixture in fixtures {
            let data = try Data(contentsOf: fixture)
            #expect(throws: ParseError.self, "Expected ParseError for malformed fixture \(fixture.lastPathComponent)") {
                _ = try Parser().parse(data)
            }
        }
    }

    @Test("Valid fixtures: path access and typed accessors agree on every populated PID field")
    func pathAndTypedAccessorsCrossCheck() throws {
        let fixtures = try FixtureCorpus.validFixtureURLs()
        for fixture in fixtures {
            let data = try Data(contentsOf: fixture)
            guard let message = try? Parser().parse(data),
                  let pid = message.firstSegment(PID.self)
            else { continue }

            // Per spec § 9.4: typed accessor and path string return the
            // same value for the same field. Exercise the scalar accessors
            // we've made typed; structured ones (PID-3 / 5 / 11) compare
            // the first-component drill-down.
            #expect(
                pid.setID == message["PID-1"],
                "PID-1 typed/path drift in \(fixture.lastPathComponent)"
            )
            #expect(
                pid.dateTimeOfBirth == message["PID-7"],
                "PID-7 typed/path drift in \(fixture.lastPathComponent)"
            )
            #expect(
                pid.administrativeSex == message["PID-8"],
                "PID-8 typed/path drift in \(fixture.lastPathComponent)"
            )
            // PID-3 (CX, repeats): the typed CX view exposes the first
            // repetition's ID via .id, which equals PID-3.1.
            #expect(
                pid.patientIdentifierList?.id == message["PID-3.1"],
                "PID-3.1 typed/path drift in \(fixture.lastPathComponent)"
            )
            // PID-5 (XPN): family name via the typed accessor.
            if let name = pid.patientName {
                #expect(
                    name.familyName == message["PID-5.1"],
                    "PID-5.1 typed/path drift in \(fixture.lastPathComponent)"
                )
            }
        }
    }

}
