// IssueMessageBaselineTests.swift
// X1 task 3: every issue message the validator writes over the valid corpus, under the
// default options and under strict with the AU profile, as 3.18.0 wrote it. Captured before
// ValidationOptions.valueExcerpts existed, so the default output is pinned byte for byte.

import Foundation
import Testing
import HL7v2Kit

@Suite("Issue messages match the 3.18.0 baseline")
struct IssueMessageBaselineTests {
    @Test("Default options write the same issue messages as 3.18.0")
    func defaultMessagesUnchanged() throws {
        let presets: [(name: String, validator: Validator)] = [
            ("default", Validator()),
            ("strict-au", Validator(options: .strict, locale: .auLocalisation)),
        ]
        var lines: [String] = []
        for url in try FixtureCorpus.validFixtureURLs() {
            let message = try Parser().parse(Data(contentsOf: url))
            for preset in presets {
                lines += preset.validator.validate(message).issues.map {
                    "\(url.lastPathComponent)|\(preset.name)|\($0.location.pathDescription)|\($0.message)"
                }
            }
        }
        try Baseline.check(lines, against: "issue-messages-v3.18.0.txt")
    }
}
