// BatchEnvelopeParseTests.swift
// Batch envelopes task 1: BatchParser parses FHS, BHS, BTS and FTS into typed segments beside
// the raw strings, takes BTS and FTS delimiters from their header, records an envelope line
// out of the grammar's order instead of overwriting, and never traps on a short header line.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Batch envelope parsing")
struct BatchEnvelopeParseTests {
    static func msh(_ id: String, separator: String = "|", version: String = "2.5.1") -> String {
        ["MSH", "^~\\&", "SYNTH_HIS", "SYNTH_FAC", "SYNTH_HOSP", "SYNTH_FAC", "20240101120000", "",
         "ADT^A01^ADT_A01", id, "P", version].joined(separator: separator) + "\rPID\(separator)1"
    }

    @Test("Each envelope line becomes a typed segment, FHS and BHS numbered like MSH")
    func envelopeIsTyped() throws {
        let file = try BatchParser().parse(Data(contentsOf: FixtureCorpus.batchFixtureURL(named: "batch_file_full.hl7")))
        let fhs = try #require(file.fileHeaderSegment)
        if case .unknown = fhs { Issue.record("FHS was not hydrated to its typed struct") }
        #expect(fhs.field(1)?.stringValue == "|" && fhs.field(2)?.stringValue == "^~\\&")
        #expect(fhs.field(9)?.stringValue == "SYN-FILE-001")
        #expect(file.batches[0].headerSegment?.field(9)?.stringValue == "SYN-BATCH-001")
        guard case .typed(let bts)? = file.batches[0].trailerSegment else { Issue.record("BTS was not hydrated"); return }
        #expect(bts.cast(to: BTS.self)?.batchMessageCount == "2")
        #expect(file.fileTrailerSegment?.field(1)?.stringValue == "1")
        #expect(file.fileHeader?.hasPrefix("FHS|") == true && file.batches[0].trailer == "BTS|2")
    }

    @Test("BTS and FTS take their header's delimiters, else the first message's")
    func trailerDelimiters() throws {
        let hash = ["FHS#^~\\&#APP", "BHS#^~\\&#APP", Self.msh("H1", separator: "#"), "BTS#1", "FTS#1"]
        let file = try BatchParser().parse(hash.joined(separator: "\r") + "\r")
        #expect(file.batches[0].trailerSegment?.field(1)?.stringValue == "1")
        #expect(file.fileTrailerSegment?.field(1)?.stringValue == "1")
        let bare = [Self.msh("B1", separator: "#"), "BTS#1", "FTS#1"]
        let fromMessage = try BatchParser().parse(bare.joined(separator: "\r") + "\r")
        #expect(fromMessage.batches[0].trailerSegment?.field(1)?.stringValue == "1")
        #expect(fromMessage.fileTrailerSegment?.field(1)?.stringValue == "1")
    }

    @Test("A hand-built group derives its segments from the raw strings")
    func handBuiltGroup() {
        let group = BatchGroup(header: "BHS|^~\\&|APP||||||NAME", messages: [], trailer: "BTS|0")
        #expect(group.headerSegment?.field(9)?.stringValue == "NAME")
        #expect(group.trailerSegment?.field(1)?.stringValue == "0")
    }

    @Test("Out-of-order envelope lines are recorded and nothing is dropped")
    func orderFindings() throws {
        let wire = ["BHS|^~\\&|APP", Self.msh("O1"), "BTS|1", "FHS|^~\\&|FIRST", "FHS|^~\\&|SECOND",
                    "FTS|1", "FTS|9", Self.msh("O2")].joined(separator: "\r") + "\r"
        let file = try BatchParser().parse(wire)
        #expect(file.fileHeader == "FHS|^~\\&|FIRST")
        #expect(file.fileTrailer == "FTS|1")
        #expect(file.allMessages.count == 2)
        #expect(file.envelopeOrderFindings.map { "\($0.segmentID) \($0.occurrence) \($0.reason)" } == [
            "FHS 1 fileHeaderNotFirst", "FHS 2 fileHeaderNotFirst", "FTS 2 secondFileTrailer", "MSH 2 afterFileTrailer",
        ])
        #expect(file.envelopeOrderFindings[1].line == "FHS|^~\\&|SECOND")
    }

    @Test("A conforming file records no order finding")
    func conformingFileHasNoFinding() throws {
        for url in try FixtureCorpus.batchFixtureURLs() {
            #expect(try BatchParser().parse(Data(contentsOf: url)).envelopeOrderFindings.isEmpty, "\(url.lastPathComponent)")
        }
    }

    @Test("A header line with no separator does not trap, in a batch or in a message")
    func shortHeaderLineDoesNotTrap() throws {
        let file = try BatchParser().parse("BHS\r" + Self.msh("S1") + "\rBTS|1\r")
        #expect(file.batches[0].headerSegment?.segmentID == "BHS")
        #expect(file.batches[0].headerSegment?.field(1) == nil)
        let message = try Parser().parse(Self.msh("S2") + "\rFHS\r")
        #expect(message.segments.last?.segmentID == "FHS")
    }

    @Test("Header delimiters are read from 4 or 5 encoding characters and must be distinct")
    func headerDelimiters() {
        #expect(Parser.headerDelimiters("BHS|^~\\&|X") == .default)
        #expect(Parser.headerDelimiters("BHS|^~\\&") == .default)
        #expect(Parser.headerDelimiters("BHS|^~\\&#|X") == .default)
        #expect(Parser.headerDelimiters("BHS|^^\\&|X") == nil)
        #expect(Parser.headerDelimiters("BHS|^~|X") == nil)
        #expect(Parser.headerDelimiters("BHS") == nil)
    }
}
