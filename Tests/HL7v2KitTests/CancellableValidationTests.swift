// CancellableValidationTests.swift
// Validation that stops between segments when the caller says so (P01 R7).

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Cancellable validation")
struct CancellableValidationTests {
    @Test("Never cancelled, the report equals validate(_:) for every valid fixture")
    func sameReport() throws {
        for url in try FixtureCorpus.validFixtureURLs() {
            let message = try Parser().parse(try Data(contentsOf: url))
            let validator = Validator(locale: .auLocalisation)
            let plain = validator.validate(message)
            let cancellable = try validator.validate(message, isCancelled: { false })
            #expect(cancellable == plain, "\(url.lastPathComponent)")
        }
    }

    @Test("Cancelled after the first segment, the 2 MB ORU throws and looks at one more segment at most")
    func stopsEarly() throws {
        let message = try Parser().parse(try PerformanceTests.largeORU())
        var asked = 0
        #expect(throws: CancellationError.self) {
            _ = try Validator().validate(message, isCancelled: {
                asked += 1
                return asked > 1
            })
        }
        #expect(asked == 2)
    }

    @Test("A message-wide check is asked once more after the last segment")
    func asksOnceBeforeMessageWideChecks() throws {
        let message = try Parser().parse(try Data(contentsOf: FixtureCorpus.fixtureURL(named: "adt_a01_minimal.hl7")))
        let segments = message.segments.count
        var asked = 0
        do {
            // False for each segment, true on the question before the message-wide checks.
            _ = try Validator().validate(message, isCancelled: {
                asked += 1
                return asked > segments
            })
            Issue.record("expected CancellationError")
        } catch {
            #expect(asked == segments + 1)
        }
    }

    @Test("A batch stops between messages, after the first message's segments")
    func batchStopsBetweenMessages() throws {
        let file = try BatchParser().parse(try Data(contentsOf: FixtureCorpus.batchFixtureURL(named: "au_batch_oru_r01.hl7")))
        let messages = file.allMessages
        try #require(messages.count >= 2)
        // The first message asks once per segment, then once before its message-wide checks;
        // the first question of the second message is the next one, and it answers true.
        let firstMessageAsks = messages[0].segments.count + 1
        var asked = 0
        do {
            _ = try BatchValidator().validate(file, isCancelled: {
                asked += 1
                return asked > firstMessageAsks
            })
            Issue.record("expected CancellationError")
        } catch {
            #expect(asked == firstMessageAsks + 1)
        }
        #expect(throws: CancellationError.self) {
            _ = try BatchValidator().validate(file, isCancelled: { true })
        }
    }

    @Test("A batch asks once more after its last message, before the envelope checks")
    func batchAsksBeforeEnvelope() throws {
        let file = try BatchParser().parse(try Data(contentsOf: FixtureCorpus.batchFixtureURL(named: "au_batch_oru_r01.hl7")))
        // Each message asks once per segment and once before its message-wide checks.
        let messageAsks = file.allMessages.map { $0.segments.count + 1 }.reduce(0, +)
        var asked = 0
        do {
            _ = try BatchValidator().validate(file, isCancelled: {
                asked += 1
                return asked > messageAsks
            })
            Issue.record("expected CancellationError")
        } catch {
            #expect(asked == messageAsks + 1)
        }
    }

    @Test("Never cancelled, a batch report equals validate(_:) for every batch fixture and locale")
    func batchSameReport() throws {
        for url in try FixtureCorpus.batchFixtureURLs() {
            let file = try BatchParser().parse(try Data(contentsOf: url))
            for locale in [HL7Locale.international, .auLocalisation] {
                let validator = BatchValidator(locale: locale)
                let cancellable = try validator.validate(file, isCancelled: { false })
                let plain = validator.validate(file)
                #expect(cancellable == plain, "\(url.lastPathComponent)")
            }
        }
    }
}
