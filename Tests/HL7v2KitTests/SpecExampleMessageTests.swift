import Foundation
import Testing
@testable import HL7v2Kit

/// M18 — the complete example messages the specification prints, validated end to end.
///
/// The messages are spec text, which stays out of the repository like the PDFs they come
/// from: `scripts/extract-example-messages.py` writes them to a local JSON file and this
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

    @Test("Report: what the Validator says about every example message")
    func report() throws {
        let path = try #require(ProcessInfo.processInfo.environment["SPEC_EXAMPLE_MESSAGES"])
        let examples = try JSONDecoder().decode([Example].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        var lines: [String] = []
        for example in examples {
            let wire = example.segments.joined(separator: "\r") + "\r"
            guard let message = try? Parser().parse(wire) else {
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
