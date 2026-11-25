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
}
