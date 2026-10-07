import Foundation
import Testing
@testable import HL7v2Kit

/// M18 — the complete example messages the specification prints, validated end to end.
///
/// The messages are spec text, which stays out of the repository like the PDFs they come
/// from: `scripts/private/extract-example-messages.py` writes them to a local JSON file and this
/// suite reads the path from `SPEC_EXAMPLE_MESSAGES`. Without it the suite is skipped.
@Suite("Spec example messages", .enabled(if: ProcessInfo.processInfo.environment["SPEC_EXAMPLE_MESSAGES"] != nil,
                                         "Set SPEC_EXAMPLE_MESSAGES to the extracted examples JSON"))
struct SpecExampleMessageTests {
    /// P4-22 fix round 1 (brief Part 1 rule 3, "mark it"): one segment repetition
    /// `extract-example-messages.py`'s elision rule (a field whose whole content is `...`)
    /// truncated — `fromField` is the first HL7 field number no longer present.
    struct TruncatedSegment: Decodable { let segment: String; let repetition: Int; let fromField: Int }

    struct Example: Decodable {
        let source: String
        let index: Int
        let segments: [String]
        let truncatedSegments: [TruncatedSegment]
        let mshVersionElided: Bool
    }

    /// `SEG[N]-F` or `SEG[N]-F.C` (a component-level issue) — the segment ID, its
    /// repetition and the HL7 field number, ignoring any component suffix, since a
    /// truncated field has no components to distinguish.
    private static let locationField = try! NSRegularExpression(pattern: #"^([A-Z][A-Z0-9]{2})\[(\d+)\]-(\d+)"#)

    /// True when `location` names a field that `truncatedSegments` records as absent only
    /// because the printed example elided it — not a genuine finding.
    private func isElisionOnly(_ location: String, truncatedSegments: [TruncatedSegment]) -> Bool {
        let range = NSRange(location.startIndex..<location.endIndex, in: location)
        guard let match = Self.locationField.firstMatch(in: location, range: range),
              let segRange = Range(match.range(at: 1), in: location),
              let repRange = Range(match.range(at: 2), in: location),
              let fieldRange = Range(match.range(at: 3), in: location),
              let repetition = Int(location[repRange]), let field = Int(location[fieldRange])
        else { return false }
        let segment = String(location[segRange])
        return truncatedSegments.contains {
            $0.segment == segment && $0.repetition == repetition && field >= $0.fromField
        }
    }

    /// The version of the document that prints the example: `source` is
    /// `"<version>/<file>"`, for example `"v2.3/CH04.pdf"`.
    static func sourceVersion(_ source: String) -> Version? {
        guard let prefix = source.split(separator: "/").first, prefix.hasPrefix("v") else { return nil }
        return Version(rawValue: String(prefix.dropFirst()))
    }

    /// P7-8 (P6-14 review): an example whose MSH-12 the print elided declares no
    /// version, so the parser would fall back to v2.5.1 (ADR-018) and a v2.3 example
    /// would draw v2.5.1 findings. Parse it under the version of its source document.
    static func parserOptions(for example: Example) -> ParserOptions {
        guard example.mshVersionElided, let version = sourceVersion(example.source) else { return .default }
        return ParserOptions(versionOverride: version)
    }

    @Test("Report: what the Validator says about every example message")
    func report() throws {
        let path = try #require(ProcessInfo.processInfo.environment["SPEC_EXAMPLE_MESSAGES"])
        let examples = try JSONDecoder().decode([Example].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        var lines: [String] = []
        for example in examples {
            let wire = example.segments.joined(separator: "\r") + "\r"
            guard let message = try? Parser(options: Self.parserOptions(for: example)).parse(wire) else {
                lines.append("SPECEX\t\(example.source)\t\(example.index)\tPARSE\t-\t-")
                continue
            }
            for issue in Validator().validate(message).errors {
                var line = "SPECEX\t\(example.source)\t\(example.index)\t\(issue.code)\t\(issue.location.pathDescription)\t\(issue.message)"
                if isElisionOnly(issue.location.pathDescription, truncatedSegments: example.truncatedSegments) {
                    line += "\tELIDED"
                }
                lines.append(line)
            }
        }
        let out = ProcessInfo.processInfo.environment["SPEC_EXAMPLE_REPORT"] ?? "/tmp/spec-example-report.tsv"
        try lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
    }
}

/// The harness logic that runs without the extracted examples (always enabled).
@Suite("Spec example harness")
struct SpecExampleHarnessTests {
    @Test("An elided-version example is parsed under its source document's version")
    func elidedVersionUsesSourceVersion() throws {
        let elided = SpecExampleMessageTests.Example(source: "v2.3/CH04.pdf", index: 1, segments: [],
                                                     truncatedSegments: [], mshVersionElided: true)
        let declared = SpecExampleMessageTests.Example(source: "v2.3/CH04.pdf", index: 2, segments: [],
                                                       truncatedSegments: [], mshVersionElided: false)
        #expect(SpecExampleMessageTests.parserOptions(for: elided).versionOverride == .v2_3)
        #expect(SpecExampleMessageTests.parserOptions(for: declared).versionOverride == nil)
        #expect(SpecExampleMessageTests.sourceVersion("v2.3.1/Hl7V231.pdf") == .v2_3_1)
        #expect(SpecExampleMessageTests.sourceVersion("v2.8.2/V282_CH02.pdf") == .v2_8_2)
    }
}
