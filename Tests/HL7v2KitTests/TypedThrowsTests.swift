// TypedThrowsTests.swift
// The parsers throw ParseError and nothing else; Path.init throws PathError (P01 R8). The
// editing functions throw MessageEditError and the builders BuilderError (P02 R17).
// Each `do throws(E)` below compiles only while the call inside it is typed.

import Foundation
import Testing
import HL7v2Kit

@Suite("Typed throws")
struct TypedThrowsTests {
    @Test("Parser.parse throws ParseError")
    func parser() {
        do throws(ParseError) {
            _ = try Parser().parse("")
            Issue.record("empty input parsed")
        } catch {
            #expect(error == .emptyInput)
        }
        do throws(ParseError) {
            _ = try Parser().parse(Data())
            Issue.record("empty data parsed")
        } catch {
            #expect(error == .emptyInput)
        }
    }

    @Test("BatchParser.parse and StreamingBatchParser throw ParseError")
    func batchParsers() {
        do throws(ParseError) {
            _ = try BatchParser().parse("")
            Issue.record("empty input parsed")
        } catch {
            #expect(error == .emptyInput)
        }
        do throws(ParseError) {
            var streaming = StreamingBatchParser()
            _ = try streaming.feed(Data([0x00]))
            _ = try streaming.finish()
            Issue.record("a NUL byte parsed")
        } catch {
            #expect(error == .truncatedMessage(atByte: 0))
        }
        do throws(ParseError) {
            _ = try CharacterEncoding.detect(in: "MSH|^~\\&|A|B|C|D|||ADT^A01|1|P|2.5.1||||||KLINGON\r")
            Issue.record("an unknown character set was accepted")
        } catch {
            #expect(error == .unsupportedCharacterEncoding(declared: "KLINGON"))
        }
    }

    @Test("Path.init throws PathError")
    func path() {
        do throws(PathError) {
            _ = try Path("not a path")
            Issue.record("a malformed path parsed")
        } catch {
            #expect(error == .malformed(input: "not a path", position: 3))
        }
    }

    @Test("Message.set, clear and insertRepetition throw MessageEditError")
    func editing() throws {
        var message = try Parser().parse("MSH|^~\\&|A|B|C|D|||ADT^A01|1|P|2.5.1\rPID|1||12345\r")
        let missing = try Path("ZZZ-1")
        do throws(MessageEditError) {
            try message.set("x", at: missing)
            Issue.record("a missing segment was set")
        } catch {
            #expect(error == .segmentNotFound(segmentID: "ZZZ", occurrence: 1))
        }
        do throws(MessageEditError) {
            try message.clear(at: missing)
            Issue.record("a missing segment was cleared")
        } catch {
            #expect(error == .segmentNotFound(segmentID: "ZZZ", occurrence: 1))
        }
        let field = try Path("PID-3")
        do throws(MessageEditError) {
            try message.insertRepetition("x", at: field)
            Issue.record("a repetition was inserted at a path naming none")
        } catch {
            #expect(error == .notARepetition(field))
        }
    }

    @Test("MessageBuilder.build and the acknowledgment builder throw BuilderError")
    func builders() throws {
        do throws(BuilderError) {
            _ = try MessageBuilder(version: .v2_5_1).build()
            Issue.record("a message with no MSH was built")
        } catch {
            #expect(error == .missingMSH)
        }
        let noControlID = try Parser().parse("MSH|^~\\&|A|B|C|D|||ADT^A01||P|2.5.1\r")
        do throws(BuilderError) {
            _ = try MessageBuilder.acknowledgment(to: noControlID, code: .applicationAccept,
                                                  messageControlID: "ACK1", dateTime: "20260101")
            Issue.record("a message with no MSH-10 was acknowledged")
        } catch {
            #expect(error == .acknowledgedMessageControlIDMissing)
        }
    }
}
