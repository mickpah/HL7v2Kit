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
    struct Example: Decodable { let source: String; let index: Int; let segments: [String] }

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
                lines.append("SPECEX\t\(example.source)\t\(example.index)\t\(issue.code)\t\(issue.location.pathDescription)\t\(issue.message)")
            }
        }
        let out = ProcessInfo.processInfo.environment["SPEC_EXAMPLE_REPORT"] ?? "/tmp/spec-example-report.tsv"
        try lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
    }
}
