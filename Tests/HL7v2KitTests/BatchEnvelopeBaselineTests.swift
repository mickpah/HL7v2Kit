// BatchEnvelopeBaselineTests.swift
// Batch envelopes task 1: BatchParser's raw envelope and BatchValidator's output for every
// batch fixture, captured on 3.19.0 before the envelope was parsed or checked. A deliberate
// change rewrites it (BASELINE_WRITE=1) for review.

import Foundation
import Testing
import HL7v2Kit

@Suite("Batch output matches the 3.19.0 baseline")
struct BatchEnvelopeBaselineTests {
    @Test("Raw envelope and batch validation output for every batch fixture")
    func batchOutputMatchesBaseline() throws {
        var lines: [String] = []
        for url in try FixtureCorpus.batchFixtureURLs() {
            let file = try BatchParser().parse(Data(contentsOf: url))
            lines.append("# \(url.lastPathComponent)")
            lines.append("fileHeader|\(file.fileHeader ?? "")")
            for (index, group) in file.batches.enumerated() {
                lines.append("batch \(index + 1)|header|\(group.header ?? "")|trailer|\(group.trailer ?? "")|messages|\(group.messages.count)")
            }
            lines.append("fileTrailer|\(file.fileTrailer ?? "")")
            for (preset, options, locale) in [("default", ValidationOptions.default, HL7Locale.international),
                                              ("strict-au", ValidationOptions.strict, HL7Locale.auLocalisation)] {
                let report = BatchValidator(options: options, locale: locale).validate(file)
                for issue in report.batchIssues {
                    lines.append("\(preset)|batch|\(issue.severity)|\(issue.location.pathDescription)|\(issue.message)")
                }
                for (n, message) in report.messageReports.enumerated() {
                    for issue in message.issues {
                        lines.append("\(preset)|message \(n + 1)|\(issue.severity)|\(issue.location.pathDescription)|\(issue.message)")
                    }
                }
            }
        }
        try Baseline.check(lines, against: "batch-validator-v3.19.0.txt")
    }
}
