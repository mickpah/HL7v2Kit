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
    /// comes back unchanged; do not pass input that is already wire form, and read under
    /// `.strict`, through it.
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
}
