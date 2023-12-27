// BatchParserTests.swift
// v0.3-T2: FHS/BHS batch parsing. Exercises the FHS/BHS/BTS/FTS framing
// recognition + per-message Parser delegation across the common shapes:
// fully-wrapped (FHS + BHS + msgs + BTS + FTS), batch-only (BHS + msgs +
// BTS), bare multi-MSH (no markers), multi-batch files, and the
// regression pin for the existing Parser-only multi-MSH behaviour.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Batch parser (v0.3-T2: FHS / BHS / BTS / FTS framing)")
struct BatchParserTests {

    // MARK: - Bare multi-MSH (no framing markers)

    @Test("Bare multi-MSH stream produces one batch group with N messages")
    func bareMultiMSHSplits() throws {
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG1|P|2.5.1\r\
        PID|1||111\r\
        MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120100||ADT^A01|MSG2|P|2.5.1\r\
        PID|2||222\r
        """
        let batch = try BatchParser().parse(wire)
        #expect(batch.fileHeader == nil)
        #expect(batch.fileTrailer == nil)
        #expect(batch.batches.count == 1)
        #expect(batch.batches[0].header == nil)
        #expect(batch.batches[0].trailer == nil)
        #expect(batch.batches[0].messages.count == 2)
        #expect(batch.allMessages.count == 2)
        #expect(batch.allMessages[0].firstSegment(MSH.self)?.messageControlID == "MSG1")
        #expect(batch.allMessages[1].firstSegment(MSH.self)?.messageControlID == "MSG2")
        #expect(batch.allMessages[0].firstSegment(PID.self)?.setID == "1")
        #expect(batch.allMessages[1].firstSegment(PID.self)?.setID == "2")
    }

    @Test("Single MSH with no framing still produces one batch / one message")
    func singleMessageNoFraming() throws {
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG1|P|2.5.1\r\
        PID|1||111\r
        """
        let batch = try BatchParser().parse(wire)
        #expect(batch.batches.count == 1)
        #expect(batch.allMessages.count == 1)
        #expect(batch.allMessages[0].firstSegment(MSH.self)?.messageControlID == "MSG1")
    }

    // MARK: - Batch-only framing (BHS + msgs + BTS)

    @Test("BHS + msgs + BTS produces one batch group with header + trailer captured")
    func batchOnlyFraming() throws {
        let wire = """
        BHS|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||SAMPLE-BATCH\r\
        MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG1|P|2.5.1\r\
        PID|1||111\r\
        MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120100||ADT^A01|MSG2|P|2.5.1\r\
        PID|2||222\r\
        BTS|2\r
        """
        let batch = try BatchParser().parse(wire)
        #expect(batch.fileHeader == nil)
        #expect(batch.fileTrailer == nil)
        #expect(batch.batches.count == 1)
        let group = try #require(batch.batches.first)
        #expect(group.header?.hasPrefix("BHS|") == true)
        #expect(group.trailer == "BTS|2")
        #expect(group.messages.count == 2)
    }

    // MARK: - Fully-wrapped (FHS + BHS + msgs + BTS + FTS)

    @Test("FHS + BHS + msgs + BTS + FTS yields all four markers + messages")
    func fullyWrappedFraming() throws {
        let wire = """
        FHS|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||SAMPLE-FILE\r\
        BHS|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||SAMPLE-BATCH\r\
        MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG1|P|2.5.1\r\
        PID|1||111\r\
        BTS|1\r\
        FTS|1\r
        """
        let batch = try BatchParser().parse(wire)
        #expect(batch.fileHeader?.hasPrefix("FHS|") == true)
        #expect(batch.fileTrailer == "FTS|1")
        #expect(batch.batches.count == 1)
        let group = try #require(batch.batches.first)
        #expect(group.header?.hasPrefix("BHS|") == true)
        #expect(group.trailer == "BTS|1")
        #expect(group.messages.count == 1)
        #expect(group.messages[0].firstSegment(MSH.self)?.messageControlID == "MSG1")
    }

    // MARK: - Multi-batch file

    @Test("Two BHS / BTS pairs inside one FHS / FTS yield two batch groups")
    func multipleBatchesInOneFile() throws {
        let wire = """
        FHS|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||MULTI-BATCH-FILE\r\
        BHS|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||BATCH-ONE\r\
        MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|B1M1|P|2.5.1\r\
        PID|1||111\r\
        MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120100||ADT^A01|B1M2|P|2.5.1\r\
        PID|2||222\r\
        BTS|2\r\
        BHS|^~\\&|HIS|FAC|HOSP|FAC|20240101120200||BATCH-TWO\r\
        MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120200||ORU^R01|B2M1|P|2.5.1\r\
        PID|3||333\r\
        BTS|1\r\
        FTS|2\r
        """
        let batch = try BatchParser().parse(wire)
        #expect(batch.fileHeader?.contains("MULTI-BATCH-FILE") == true)
        #expect(batch.fileTrailer == "FTS|2")
        #expect(batch.batches.count == 2)
        #expect(batch.batches[0].header?.contains("BATCH-ONE") == true)
        #expect(batch.batches[1].header?.contains("BATCH-TWO") == true)
        #expect(batch.batches[0].messages.count == 2)
        #expect(batch.batches[1].messages.count == 1)
        #expect(batch.batches[0].trailer == "BTS|2")
        #expect(batch.batches[1].trailer == "BTS|1")
        #expect(batch.allMessages.count == 3)
        #expect(batch.allMessages[2].firstSegment(MSH.self)?.messageControlID == "B2M1")
    }

    // MARK: - Empty batch (BHS + BTS with no MSHs between)

    @Test("Empty batch (BHS immediately followed by BTS) yields an empty message list")
    func emptyBatch() throws {
        let wire = """
        BHS|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||EMPTY-BATCH\r\
        BTS|0\r
        """
        let batch = try BatchParser().parse(wire)
        #expect(batch.batches.count == 1)
        #expect(batch.batches[0].header?.hasPrefix("BHS|") == true)
        #expect(batch.batches[0].messages.isEmpty)
        #expect(batch.batches[0].trailer == "BTS|0")
    }

    // MARK: - Data-path parity with Parser

    @Test("BatchParser delegates per-message parsing to Parser — composite accessors work")
    func parsedMessagesUseFullParserPipeline() throws {
        let wire = """
        BHS|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||SAMPLE\r\
        MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG1|P|2.5.1\r\
        PID|1||000001^^^HOSP^MR||Smith^John\r\
        BTS|1\r
        """
        let batch = try BatchParser().parse(wire)
        let pid = try #require(batch.allMessages.first?.firstSegment(PID.self))
        // Typed composite XPN exposed by the C1 promotion — proves
        // BatchParser doesn't bypass the typed-segment hydration pass.
        #expect(pid.patientName?.familyName == "Smith")
        #expect(pid.patientName?.givenName == "John")
        #expect(pid.patientIdentifierList?.id == "000001")
    }

    @Test("BatchParser.parse(Data:) handles UTF-8 BOM + NUL rejection like Parser.parse(_ data:)")
    func dataPathStripsBOMAndRejectsNUL() throws {
        let baseWire = """
        MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG1|P|2.5.1\r\
        PID|1||111\r
        """
        var bomBytes = Data([0xEF, 0xBB, 0xBF])
        bomBytes.append(Data(baseWire.utf8))
        let batch = try BatchParser().parse(bomBytes)
        #expect(batch.allMessages.count == 1)

        var nulBytes = Data(baseWire.utf8)
        nulBytes.insert(0x00, at: nulBytes.count / 2)
        #expect(throws: ParseError.self) {
            _ = try BatchParser().parse(nulBytes)
        }
    }

    // MARK: - R5-C3: MSH-18 charset detection on the Data path

    // Characterization pins for the R5/F20 wire-decode dedup: the batch
    // Data path must honour MSH-18 exactly like `Parser.parse(_ data:)`.
    // Before R5 this path was pinned only for BOM strip + NUL rejection;
    // the Latin-1 decode leg had no batch-side coverage.
    @Test("BatchParser.parse(Data:) honours MSH-18 = 8859/1 — 0xE9 decodes to é")
    func dataPathHonoursLatin1() throws {
        let bhs = "BHS|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||SAMPLE\r"
        let msh = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG1|P|2.5.1||||||8859/1\r"
        let pidPrefix = "PID|1||111||Caf"
        var bytes = Data(bhs.utf8)
        bytes.append(Data(msh.utf8))
        bytes.append(Data(pidPrefix.utf8))
        bytes.append(0xE9)                     // 'é' in Latin-1; invalid as UTF-8
        bytes.append(Data("\rBTS|1\r".utf8))
        let batch = try BatchParser().parse(bytes)
        let message = try #require(batch.allMessages.first)
        #expect(message["PID-5"] == "Café")
        #expect(message.characterEncoding == .iso8859_1)
    }

    @Test("BatchParser.parse(Data:) throws on unrecognised MSH-18")
    func dataPathUnrecognisedEncodingThrows() {
        let wire = "MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG1|P|2.5.1||||||EBCDIC\r"
        #expect(throws: ParseError.unsupportedCharacterEncoding(declared: "EBCDIC")) {
            _ = try BatchParser().parse(Data(wire.utf8))
        }
    }

    // MARK: - Lenient line terminators

    @Test("LF-terminated batch wire parses identically to CR-terminated")
    func lenientLineTerminators() throws {
        let crWire = """
        BHS|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||SAMPLE\r\
        MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG1|P|2.5.1\r\
        PID|1||111\r\
        BTS|1\r
        """
        let lfWire = crWire.replacingOccurrences(of: "\r", with: "\n")
        let crBatch = try BatchParser().parse(crWire)
        let lfBatch = try BatchParser().parse(lfWire)
        #expect(crBatch.allMessages.count == lfBatch.allMessages.count)
        #expect(crBatch.allMessages.first?.firstSegment(MSH.self)?.messageControlID
                == lfBatch.allMessages.first?.firstSegment(MSH.self)?.messageControlID)
    }

    // MARK: - Empty input

    @Test("Empty input throws ParseError.emptyInput")
    func emptyInputThrows() {
        #expect(throws: ParseError.self) {
            _ = try BatchParser().parse(Data())
        }
    }

    // MARK: - Regression: Parser-only multi-MSH behaviour preserved

    @Test("Parser.parse() on a bare multi-MSH wire still produces ONE Message (v0.1.0 pin preserved)")
    func parserMultiMSHBehaviourUnchanged() throws {
        // The v0.1.0 ParseErrorTests.multipleMSHSegmentsAcceptedAsIs pin
        // documents that Parser.parse() on a stream with multiple MSH
        // returns one Message with multiple MSH segments. After v0.3-T2
        // that pin must still hold — BatchParser is the opt-in
        // alternative; bare Parser is unchanged.
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120000||ADT^A01|MSG1|P|2.5.1\r\
        PID|1\r\
        MSH|^~\\&|HIS|FAC|HOSP|FAC|20240101120100||ADT^A01|MSG2|P|2.5.1\r\
        PID|2\r
        """
        let message = try Parser().parse(wire)
        let mshCount = message.segments.filter { $0.segmentID == "MSH" }.count
        #expect(mshCount == 2, "Parser.parse() contract unchanged: multi-MSH yields ONE Message")
    }
}
