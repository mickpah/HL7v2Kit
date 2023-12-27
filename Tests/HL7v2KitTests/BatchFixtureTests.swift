// BatchFixtureTests.swift
// v0.3-Z2: file-loaded coverage for the batch parser. The synthetic
// fixtures under Tests/Fixtures/Batches/ exercise the three real-world
// batch shapes: BHS-only (a single batch with no file wrapper),
// fully-wrapped (FHS + BHS + msgs + BTS + FTS), and multi-batch (one
// FHS/FTS containing two BHS/BTS groups). Auto-discovers files in
// the subdirectory so future additions need no test changes.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Batch fixture corpus (v0.3-Z2)")
struct BatchFixtureTests {

    @Test("Every batch fixture parses via BatchParser without throwing")
    func everyBatchFixtureParses() throws {
        let urls = try FixtureCorpus.batchFixtureURLs()
        #expect(!urls.isEmpty, "No batch fixtures discovered under Tests/Fixtures/Batches/")
        for url in urls {
            let bytes = try Data(contentsOf: url)
            #expect(throws: Never.self, "\(url.lastPathComponent) failed to parse") {
                _ = try BatchParser().parse(bytes)
            }
        }
    }

    @Test("batch_bhs_minimal.hl7 — single batch group with one message")
    func bhsMinimal() throws {
        let url = FixtureCorpus.batchFixtureURL(named: "batch_bhs_minimal.hl7")
        let bytes = try Data(contentsOf: url)
        let batch = try BatchParser().parse(bytes)
        #expect(batch.fileHeader == nil)
        #expect(batch.fileTrailer == nil)
        #expect(batch.batches.count == 1)
        let group = try #require(batch.batches.first)
        #expect(group.header?.hasPrefix("BHS|") == true)
        #expect(group.trailer == "BTS|1")
        #expect(group.messages.count == 1)
        #expect(group.messages[0].firstSegment(MSH.self)?.messageControlID == "SYN-BM-1")
        #expect(group.messages[0].firstSegment(PID.self)?.patientName?.familyName == "Singh")
    }

    @Test("batch_file_full.hl7 — FHS + BHS + 2 MSH + BTS + FTS")
    func fullyWrappedFile() throws {
        let url = FixtureCorpus.batchFixtureURL(named: "batch_file_full.hl7")
        let bytes = try Data(contentsOf: url)
        let batch = try BatchParser().parse(bytes)
        #expect(batch.fileHeader?.hasPrefix("FHS|") == true)
        #expect(batch.fileTrailer == "FTS|1")
        #expect(batch.batches.count == 1)
        #expect(batch.batches[0].header?.contains("SYN-BATCH-001") == true)
        #expect(batch.batches[0].trailer == "BTS|2")
        #expect(batch.batches[0].messages.count == 2)
        #expect(batch.allMessages[0].firstSegment(MSH.self)?.messageControlID == "SYN-BF-1")
        #expect(batch.allMessages[1].firstSegment(MSH.self)?.messageControlID == "SYN-BF-2")
    }

    @Test("batch_multi_groups.hl7 — one FHS/FTS containing two BHS/BTS groups")
    func multiBatchFile() throws {
        let url = FixtureCorpus.batchFixtureURL(named: "batch_multi_groups.hl7")
        let bytes = try Data(contentsOf: url)
        let batch = try BatchParser().parse(bytes)
        #expect(batch.fileHeader?.contains("SYN-FILE-MULTI") == true)
        #expect(batch.fileTrailer == "FTS|2")
        #expect(batch.batches.count == 2)
        #expect(batch.batches[0].header?.contains("SYN-BATCH-ADT") == true)
        #expect(batch.batches[1].header?.contains("SYN-BATCH-ORU") == true)
        #expect(batch.allMessages.count == 2)
        #expect(batch.allMessages[0].firstSegment(MSH.self)?.messageType?.triggerEvent == "A01")
        #expect(batch.allMessages[1].firstSegment(MSH.self)?.messageType?.triggerEvent == "R01")
        #expect(batch.allMessages[1].firstSegment(OBX.self)?.observationValue == "145")
    }

    @Test("Batch fixtures also round-trip cleanly through StreamingBatchParser")
    func batchFixturesStreamingRoundTrip() throws {
        for url in try FixtureCorpus.batchFixtureURLs() {
            let bytes = try Data(contentsOf: url)
            var streamingParser = StreamingBatchParser()
            var emitted = try streamingParser.feed(bytes)
            emitted.append(contentsOf: try streamingParser.finish())
            let nonStreamingCount = try BatchParser().parse(bytes).allMessages.count
            #expect(emitted.count == nonStreamingCount,
                    "\(url.lastPathComponent): streaming yielded \(emitted.count) messages, non-streaming yielded \(nonStreamingCount)")
        }
    }
}
