// AnonymiseGoldenTests.swift
// X1 task 4a: the HL7v2KitAnonymise output for every valid fixture and for the AnonymiseTests
// marker message, captured before the scrubbing rules moved into the library. The tool must
// reproduce it byte for byte; a deliberate change rewrites it (BASELINE_WRITE=1) for review.

import Foundation
import Testing
import HL7v2Kit
@testable import HL7v2KitAnonymise

@Suite("Anonymise tool output is unchanged")
struct AnonymiseGoldenTests {
    /// The tool's output for `data`, read as the tool reads a file, one segment per line.
    static func output(_ data: Data) throws -> [String] {
        let message = try Parser().parse(data)
        return String(decoding: scrub(message, salt: deriveSalt(from: message)).serialize(), as: UTF8.self)
            .split(separator: "\r", omittingEmptySubsequences: false).map(String.init)
    }

    @Test("The tool's output for every input matches the golden file")
    func outputMatchesGolden() throws {
        var lines = ["# AnonymiseTests.wire"] + (try Self.output(Data(AnonymiseTests.wire.utf8)))
        for url in try FixtureCorpus.validFixtureURLs() {
            lines.append("# \(url.lastPathComponent)")
            lines += try Self.output(Data(contentsOf: url))
        }
        try Baseline.check(lines, against: "anonymise-tool-v3.18.0.txt")
    }
}
