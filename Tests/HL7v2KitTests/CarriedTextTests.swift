// CarriedTextTests.swift
// Parser.wire(fromCarried:) turns pasted or saved text into wire form (P01 R9).

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Carried text")
struct CarriedTextTests {
    static let plain = "MSH|^~\\&|SND|FAC|RCV|FAC|20260101120000||ADT^A01^ADT_A01|M1|P|2.5.1\rPID|1||MRN12345\r"
    static let lf = plain.replacingOccurrences(of: "\r", with: "\n")
    static let crlf = plain.replacingOccurrences(of: "\r", with: "\r\n")

    static let carried: [(String, String)] = [
        ("LF endings", lf),
        ("CRLF endings", crlf),
        ("a byte-order mark", "\u{FEFF}" + plain),
        ("two leading blank lines", "\n\n" + lf),
        ("trailing blank lines", crlf + "\r\n\r\n"),
        ("no final terminator", String(plain.dropLast())),
        ("an MLLP frame", "\u{0B}" + plain + "\u{1C}\r"),
        ("everything together", "\u{FEFF}\r\n\n\u{0B}" + crlf + "\u{1C}\r\n\n"),
    ]

    @Test("Each carried form normalises to the plain CR message")
    func normalises() {
        for (name, text) in Self.carried {
            #expect(Parser.wire(fromCarried: text) == Self.plain, "\(name)")
            #expect(Parser.wire(fromCarried: Data(text.utf8)) == Data(Self.plain.utf8), "\(name)")
        }
    }

    @Test("Plain CR wire form is unchanged, and the LF fixture result parses under .strict")
    func wireFormUnchanged() throws {
        let data = Data(Self.plain.utf8)
        #expect(Parser.wire(fromCarried: data) == data)
        let message = try Parser(options: .strict).parse(Parser.wire(fromCarried: Data(Self.lf.utf8)))
        #expect(message.segments.count == 2)
    }

    @Test("A line feed in a value splits, blank lines collapse, and MLLP bytes drop where present")
    func documentedBehaviour() {
        let head = "MSH|^~\\&|SND\r"
        #expect(Parser.wire(fromCarried: head + "OBX|1|TX|||line1\nline2\r")
            == head + "OBX|1|TX|||line1\rline2\r")
        #expect(Parser.wire(fromCarried: head + "\r" + "PID|1\r") == head + "PID|1\r")
        #expect(Parser.wire(fromCarried: head + "\u{1C}") == head)
        #expect(Parser.wire(fromCarried: "\u{0B}" + head) == head)
        #expect(Parser.wire(fromCarried: "\u{0B}\u{FEFF}" + head) == head)
    }

    @Test("ISO 8859-1 bytes above 0x7F pass through untouched")
    func latin1() {
        let bytes: [UInt8] = Array("PID|1||M".utf8) + [0xFC] + Array("ller\n".utf8)
        #expect(Parser.wire(fromCarried: Data(bytes)) == Data(bytes.dropLast() + [0x0D]))
    }

    @Test("Blank input gives nothing")
    func blank() {
        #expect(Parser.wire(fromCarried: "\n\n") == "")
    }

    // MARK: - The messages in carried input (P02 R14)

    static let second = "MSH|^~\\&|SND|FAC|RCV|FAC|20260101120100||ADT^A08^ADT_A01|M2|P|2.5.1\rPID|1||MRN67890\r"
    static let third = "MSH|^~\\&|SND|FAC|RCV|FAC|20260101120200||ADT^A03^ADT_A03|M3|P|2.5.1\rPID|1||MRN24680\r"

    /// The text of each message `messageRanges(inCarried:)` finds in `text`.
    static func messages(in text: String) -> [String] {
        let data = Data(text.utf8)
        return Parser.messageRanges(inCarried: data).map { String(decoding: data[$0], as: UTF8.self) }
    }

    @Test("One message is one range holding all of it")
    func oneMessage() throws {
        let data = Data(Self.plain.utf8)
        #expect(Parser.messageRanges(inCarried: data) == [0..<data.count])
        #expect(try Parser().parse(data[Parser.messageRanges(inCarried: data)[0]]) == Parser().parse(data))
        #expect(Self.messages(in: String(Self.plain.dropLast())) == [String(Self.plain.dropLast())])   // no final terminator
    }

    @Test("Three messages come back as their own bytes, line endings kept",
          arguments: ["\r", "\n", "\r\n"])
    func threeMessages(_ ending: String) {
        let each = [Self.plain, Self.second, Self.third].map { $0.replacingOccurrences(of: "\r", with: ending) }
        #expect(Self.messages(in: each.joined()) == each)
        // Blank lines between messages, before the first and after the last, fall in no range.
        #expect(Self.messages(in: ending + each.joined(separator: ending + ending) + ending + ending) == each)
    }

    @Test("A byte-order mark, MLLP framing and leading text fall in no range")
    func framingIsOutside() {
        #expect(Self.messages(in: "\u{FEFF}" + Self.plain) == [Self.plain])
        let framed = "\u{0B}" + Self.plain + "\u{1C}\r" + "\u{0B}" + Self.second + "\u{1C}\r"
        #expect(Self.messages(in: framed) == [Self.plain, Self.second])
        #expect(Self.messages(in: "2026-01-01 12:00 received:\n" + Self.lf + "-- end --\n" + Self.second)
                == [Self.lf + "-- end --\n", Self.second])   // a line after a message is that message's, as Parser reads it
        #expect(Self.messages(in: "From: someone\nSubject: sample\n\n" + Self.plain) == [Self.plain])
    }

    @Test("Only a line that starts MSH and a separator starts a message")
    func whatStartsAMessage() {
        #expect(Self.messages(in: Self.plain + "MSHX|1|2\r") == [Self.plain + "MSHX|1|2\r"])
        #expect(Self.messages(in: Self.lf + "MSH is the header segment\n") == [Self.lf + "MSH is the header segment\n"])
        #expect(Self.messages(in: Self.plain + "MSH\r") == [Self.plain + "MSH\r"])
        #expect(Self.messages(in: Self.plain + " MSH|^~\\&|X\r") == [Self.plain + " MSH|^~\\&|X\r"])   // indented: not a line start
        let hashes = "MSH#^~\\&#SND#FAC#RCV#FAC#20260101120100##ADT^A08#M2#P#2.5.1\rPID#1##MRN67890\r"
        #expect(Self.messages(in: Self.plain + hashes) == [Self.plain, hashes])   // each message names its own separator
    }

    @Test("Batch envelope lines fall in no range")
    func batchEnvelope() {
        let batch = "FHS|^~\\&|SND\rBHS|^~\\&|SND\r" + Self.plain + Self.second + "BTS|2\rFTS|1\r"
        #expect(Self.messages(in: batch) == [Self.plain, Self.second])
        #expect(Self.messages(in: Self.plain + "BTS\r") == [Self.plain])
        #expect(Self.messages(in: Self.plain + "BTSX|1\r") == [Self.plain + "BTSX|1\r"])
    }

    @Test("Input with no message gives no range")
    func noMessage() {
        #expect(Parser.messageRanges(inCarried: Data()) == [])
        #expect(Self.messages(in: "\r\n\n") == [])
        #expect(Self.messages(in: "PID|1||MRN12345\r") == [])
        #expect(Self.messages(in: "not HL7 at all") == [])
    }

    @Test("The ranges index the data given, a slice included")
    func rangesIndexTheData() {
        let whole = Data(("xxxx" + Self.plain + Self.second).utf8)
        let slice = whole[4...]
        let ranges = Parser.messageRanges(inCarried: slice)
        #expect(ranges.map { String(decoding: slice[$0], as: UTF8.self) } == [Self.plain, Self.second])
        #expect(ranges.first?.lowerBound == 4)
    }
}
