// Parser+CarriedText.swift
// Text a person carried (pasted from an email or a log, saved by an interface engine) back
// into wire form. Not a kernel file, and never called by Parser.parse.

import Foundation

extension Parser {
    /// Wire form of a message that was pasted or saved as text: a leading byte-order mark,
    /// an MLLP start byte at the start, an MLLP end byte at the end (each dropped where present,
    /// with or without the other) and blank lines are dropped, `\r\n` and `\n` are folded to
    /// `\r`, and every segment ends with one `\r`.
    ///
    /// The result is not the original bytes, so nothing <doc:RoundTripGuarantee> promises
    /// holds from the carried text; it holds from the result. `Parser` never applies this
    /// itself. Every line break is taken as a segment boundary, as
    /// ``LineTerminatorPolicy/lenient`` takes it, so a line feed inside a value becomes a segment boundary.
    /// A message that ends every segment with `\r` and holds no line feed and no blank line
    /// comes back unchanged. A line feed inside a value does not survive: it becomes a segment
    /// break here, so a later read of the result under `.strict`, which would have kept that
    /// line feed in the value, sees two segments. Input that may hold one and is to be read
    /// under `.strict` should not be passed through this function.
    public static func wire(fromCarried data: Data) -> Data {
        var bytes = data[...]
        func isBreak(_ byte: UInt8) -> Bool { byte == 0x0D || byte == 0x0A }
        func dropLeading() {
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
            while let first = bytes.first, isBreak(first) { bytes = bytes.dropFirst() }
        }
        dropLeading()
        if bytes.first == MLLP.startByte {
            bytes = bytes.dropFirst()
            dropLeading()
        }
        while let last = bytes.last, isBreak(last) { bytes = bytes.dropLast() }
        if bytes.last == MLLP.endBodyByte { bytes = bytes.dropLast() }
        var wire = Data(capacity: bytes.count + 1)
        for line in bytes.split(whereSeparator: isBreak) {
            wire.append(contentsOf: line)
            wire.append(0x0D)
        }
        return wire
    }

    /// As ``wire(fromCarried:)-(Data)``, for text already decoded.
    public static func wire(fromCarried text: String) -> String {
        String(decoding: wire(fromCarried: Data(text.utf8)), as: UTF8.self)
    }

    /// Where each message lies in input that was pasted or saved and may hold several: a log,
    /// a capture of MLLP traffic, a file of messages one after another.
    ///
    /// The ranges index `data` itself, so `data[range]` is one message's bytes as given, line
    /// endings included, ready for ``parse(_:)-(Data)`` or ``sourceMap(of:)``. Nothing is
    /// normalised, parsed or validated.
    ///
    /// A message starts at a line that begins `MSH` followed by a punctuation character, its
    /// own field separator (MSH-1); `MSHX|1` and a line of text starting `MSH is` do not start
    /// one. It runs to the end of its last non-blank line, that line's terminator included. A
    /// byte-order mark, MLLP start and end bytes, blank lines around a message and anything
    /// before the first message fall in no range. A batch envelope line (FHS, BHS, BTS, FTS)
    /// ends the message before it and falls in no range; read a batch file with
    /// ``BatchParser``. A line that follows a message and starts neither a message nor an
    /// envelope is taken as part of that message, as `parse` would read it, so a line feed
    /// inside a value does not end a message unless the text after it starts `MSH` and a
    /// separator. Input with no such line gives no range.
    public static func messageRanges(inCarried data: Data) -> [Range<Int>] {
        func isLineBreak(_ byte: UInt8) -> Bool { byte == 0x0D || byte == 0x0A }
        func isBreak(_ byte: UInt8) -> Bool {
            isLineBreak(byte) || byte == MLLP.startByte || byte == MLLP.endBodyByte
        }
        // A separator is printable ASCII that is no letter, digit or space.
        func isSeparator(_ byte: UInt8) -> Bool {
            (0x21...0x7E).contains(byte) && !(UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                && !(UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
                && !(UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
        }
        var ranges: [Range<Int>] = []
        var open: Range<Int>?
        func close() {
            if let range = open { ranges.append(range) }
            open = nil
        }
        var i = data.startIndex
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { i += 3 }
        while i < data.endIndex {
            guard !isBreak(data[i]) else { i += 1; continue }
            let start = i
            while i < data.endIndex, !isBreak(data[i]) { i += 1 }
            let line = data[start..<i]
            // The line's own terminator: CR, LF or CRLF. An MLLP byte is not one.
            if i < data.endIndex, isLineBreak(data[i]) {
                i += data[i] == 0x0D && i + 1 < data.endIndex && data[i + 1] == 0x0A ? 2 : 1
            }
            let id = line.prefix(3)
            let fourth = line.dropFirst(3).first
            if id.elementsEqual("MSH".utf8), let fourth, isSeparator(fourth) {
                close()
                open = start..<i
            } else if ["FHS", "BHS", "BTS", "FTS"].contains(where: { id.elementsEqual($0.utf8) }),
                      fourth.map(isSeparator) ?? true {
                close()
            } else if let range = open {
                open = range.lowerBound..<i
            }
        }
        close()
        return ranges
    }
}
