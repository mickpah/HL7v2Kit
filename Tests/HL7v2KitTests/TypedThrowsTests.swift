// TypedThrowsTests.swift
// The parsers throw ParseError and nothing else; Path.init throws PathError (P01 R8).
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
}
