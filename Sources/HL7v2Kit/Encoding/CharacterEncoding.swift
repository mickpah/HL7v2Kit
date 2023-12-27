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

    /// The canonical MSH-18 wire string for this charset.
    public var wireValue: String {
        switch self {
        case .utf8: return "UNICODE UTF-8"
        case .ascii: return "ASCII"
        case .iso8859_1: return "8859/1"
        }
    }

    /// Map an MSH-18 wire string to a known charset. Returns `nil` if the
    /// value is empty (caller should treat as "default to UTF-8") or if it
    /// is non-empty but unrecognised (caller should throw).
    ///
    /// The match is case-insensitive and tolerates the common aliases each
    /// charset is known by in real-world AU traffic.
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
    /// terminate at `\r` or `\n`) is split on the field separator and field
    /// 18 is mapped via `from(mshField18:)`. If no MSH line exists, or
    /// MSH-18 is absent or empty, defaults to `.utf8`. If MSH-18 is present
    /// but names a charset HL7v2Kit does not recognise, throws
    /// `ParseError.unsupportedCharacterEncoding(declared:)`.
    ///
    /// The probe is structural — it doesn't require a fully-decoded message,
    /// only enough of the leading bytes to find the field-separator and
    /// MSH-18 slot. Callers building byte-level workflows can pass a Latin-1
    /// 1:1 decode of the input bytes.
    public static func detect(in raw: String) throws -> CharacterEncoding {
        guard let declared = probeMSH18(raw), !declared.isEmpty else {
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
            let lineEnd = probe[lineStart...].firstIndex(where: { $0 == "\r" || $0 == "\n" })
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
                let parts = line.split(separator: fieldSep, omittingEmptySubsequences: false)
                guard parts.count > 17 else { return nil }
                return String(parts[17])
            }
            guard lineEnd < probe.endIndex else { return nil }
            lineStart = probe.index(after: lineEnd)
        }
        return nil
    }
}
