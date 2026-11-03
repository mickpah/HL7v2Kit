// CharacterEncoding.swift
// MSH-18 character-set declarations. This file is intentionally the
// Foundation edge of the kernel — String ↔ Data conversion happens here.
// Not added to the PORTABLE KERNEL set; ports will substitute their own
// charset lookup (Rust `encoding_rs`, Go `golang.org/x/text/encoding`, etc.).

import Foundation

/// The HL7 v2 character sets HL7v2Kit can decode and re-emit.
///
/// MSH-18 carries a free-form character-set name on the wire. Senders we
/// care about for v0.1.0 use one of a small set of canonical strings; this
/// type maps those strings to the `String.Encoding` used to convert between
/// `Data` and `String`. Unrecognised declarations cause `Parser.parse(_:)`
/// to throw `ParseError.unsupportedCharacterEncoding(declared:)`.
public enum CharacterEncoding: Sendable, Equatable, Hashable {
    /// `UNICODE UTF-8` (or no MSH-18 declared). The default.
    case utf8
    /// 7-bit `ASCII` / `US-ASCII`.
    case ascii
    /// `8859/1` / ISO-8859-1 / Latin-1. Common in legacy AU senders.
    case iso8859_1

    /// `String.Encoding` used to encode and decode message bytes.
    public var stringEncoding: String.Encoding {
        switch self {
        case .utf8: return .utf8
        case .ascii: return .ascii
        case .iso8859_1: return .isoLatin1
        }
    }

    /// Message bytes as text in this character set, or nil when they do not fit it. ISO 8859-1 is
    /// read by hand: swift-corelibs-foundation 6.0 on Linux answers nil for any ISO Latin 1 text or
    /// bytes holding a CR, which is every HL7 message. Text that is all ASCII reads the same in
    /// every set, so it takes the UTF-8 path.
    func decode(_ data: Data) -> String? {
        guard self == .iso8859_1 else { return String(data: data, encoding: stringEncoding) }
        if data.allSatisfy({ $0 < 0x80 }) { return String(decoding: data, as: UTF8.self) }
        // Each byte is the scalar of its value: one UTF-8 byte below 0x80, two from there up.
        var utf8: [UInt8] = []
        utf8.reserveCapacity(data.count + data.count / 2)
        for byte in data {
            if byte < 0x80 {
                utf8.append(byte)
            } else {
                utf8.append(0xC0 | byte >> 6)
                utf8.append(0x80 | byte & 0x3F)
            }
        }
        return String(decoding: utf8, as: UTF8.self)
    }

    /// `text` as bytes in this character set, or nil when it holds a character the set cannot
    /// write. ISO 8859-1 is written by hand, for the reason `decode(_:)` gives.
    func encode(_ text: String) -> Data? {
        guard self == .iso8859_1 else { return text.data(using: stringEncoding) }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            guard scalar.value <= 0xFF else { return nil }
            bytes.append(UInt8(scalar.value))
        }
        return Data(bytes)
    }

    /// The canonical MSH-18 wire string for this charset.
    public var wireValue: String {
        switch self {
        case .utf8: return "UNICODE UTF-8"
        case .ascii: return "ASCII"
        case .iso8859_1: return "8859/1"
        }
    }

    /// Whether `text` can be written in this character set: UTF-8 writes every character,
    /// ASCII the scalars up to 0x7F, ISO 8859-1 those up to 0xFF. Shared by the MSH-18 edit,
    /// `Parser.parse(_: String)` and the validator (#16).
    func encodes(_ text: String) -> Bool {
        let limit: UInt32
        switch self {
        case .utf8: return true
        case .ascii: limit = 0x7F
        case .iso8859_1: limit = 0xFF
        }
        return !text.unicodeScalars.contains { $0.value > limit }
    }

    /// Whether MSH-18's first repetition is unvalued: empty, or the HL7 null `""` (v2.5.1
    /// section 2.5.3). Either is read as UTF-8 (#17), a documented departure from section
    /// 2.15.9.18, which reads both as 7-bit ASCII. Shared by ``detect(in:)`` and the MSH-18 edit.
    static func isUnvalued(_ declared: String) -> Bool {
        declared.isEmpty || declared == "\"\""
    }

    /// Map an MSH-18 wire string to a known charset. Returns `nil` if the
    /// value is empty (caller should treat as "default to UTF-8") or if it
    /// is non-empty but unrecognised (caller should throw).
    ///
    /// The match is case-insensitive and tolerates the common aliases each
    /// charset is known by in real-world AU traffic.
    ///
    /// The string is one value: a repeated MSH-18 (`8859/1~ISO IR87`) maps to `nil`.
    /// ``detect(in:)`` reads the first repetition.
    public static func from(mshField18 raw: String) -> CharacterEncoding? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch trimmed.uppercased() {
        case "UNICODE UTF-8", "UTF-8", "UTF8":
            return .utf8
        case "ASCII", "US-ASCII":
            return .ascii
        case "8859/1", "ISO-8859-1", "ISO 8859-1", "ISO-IR-100", "LATIN1", "LATIN-1":
            return .iso8859_1
        default:
            return nil
        }
    }

    /// Detect the character set declared in MSH-18 of a v2 message header.
    ///
    /// The first MSH line (batch FHS / BHS envelope lines are skipped; lines
    /// terminate at `\r` or `\n`) is split on the field separator, and the first
    /// repetition of field 18 is mapped via `from(mshField18:)`. MSH-18 repeats: the
    /// first repetition names the message's character set, and later ones name
    /// alternate sets used through the `\C..\` and `\M..\` escapes, which HL7v2Kit keeps
    /// verbatim (v2.5.1 section 2.15.9.18). If no MSH line exists, or MSH-18 or its first
    /// repetition is absent, empty or the HL7 null `""`, defaults to `.utf8`; the print reads
    /// an unvalued MSH-18 as 7-bit ASCII, which UTF-8 contains, so a conformant message
    /// decodes the same. If the first repetition names a charset HL7v2Kit does not recognise,
    /// throws `ParseError.unsupportedCharacterEncoding(declared:)` with that repetition.
    ///
    /// The probe is structural — it doesn't require a fully-decoded message,
    /// only enough of the leading bytes to find the field-separator and
    /// MSH-18 slot. Callers building byte-level workflows can pass a Latin-1
    /// 1:1 decode of the input bytes.
    public static func detect(in raw: String) throws -> CharacterEncoding {
        guard let declared = probeMSH18(raw), !isUnvalued(declared) else {
            return .utf8
        }
        guard let known = from(mshField18: declared) else {
            throw ParseError.unsupportedCharacterEncoding(declared: declared)
        }
        return known
    }

    /// Pull MSH-18 (the character-set declaration) out of the first MSH
    /// line of the probe. Batch wires carry FHS / BHS envelope lines ahead
    /// of the first message header, so the scan walks lines until it finds
    /// one prefixed `MSH`. Returns nil when no MSH line exists, the header
    /// is malformed, or it simply does not have an 18th field.
    private static func probeMSH18(_ probe: String) -> String? {
        var lineStart = probe.startIndex
        while lineStart < probe.endIndex {
            // "\r\n" is one Character (#15); isNewline would also take U+0085, Latin-1 byte 0x85.
            let lineEnd = probe[lineStart...].firstIndex(where: { $0 == "\r" || $0 == "\n" || $0 == "\r\n" })
                ?? probe.endIndex
            let line = probe[lineStart..<lineEnd]
            if line.hasPrefix("MSH") {
                guard line.count >= 4 else { return nil }
                let fieldSep = line[line.index(line.startIndex, offsetBy: 3)]
                // Splitting "MSH|^~\\&|sendingApp|..." on '|' gives:
                //   parts[0] = "MSH"
                //   parts[1] = MSH-2 (encoding chars)
                //   parts[N - 1] = MSH-N for N >= 2
                // So MSH-18 lives at parts[17].
                let parts = line.split(omittingEmptySubsequences: false) { $0.isDelimiter(fieldSep) }
                guard parts.count > 17 else { return nil }
                let field = parts[17]
                // MSH-18 repeats; its first repetition names the message's character set
                // (v2.5.1 section 2.15.9.18). The repetition separator is MSH-2's second
                // character (#15).
                let head = Array(line.prefix(6))
                guard head.count == 6, !head[5].isDelimiter(fieldSep),
                      let end = field.firstIndex(where: { $0.isDelimiter(head[5]) }) else { return String(field) }
                return String(field[..<end])
            }
            guard lineEnd < probe.endIndex else { return nil }
            lineStart = probe.index(after: lineEnd)
        }
        return nil
    }
}
