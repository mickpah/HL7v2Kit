// PORTABLE KERNEL — keep this file Foundation-free and byte/character-level.
// A future Rust/Go port translates this file directly. No NSRegularExpression,
// NSString, DateFormatter, CharacterSet, locale-aware ops, protocols, or
// generics in the parse path. `Data` only at the edges (to/from [UInt8]).
// See docs/design/architecture-decisions.md#adr-006-portable-core-boundary

// EscapeSequences.swift
// HL7 v2 escape-sequence codec for subcomponent leaf values.
//
// Design (recorded so the inverse-property tests stay grounded):
//
// - `Subcomponent.value` stores the DECODED form. Wire-level escape sequences
//   (`\F\`, `\S\`, `\T\`, `\R\`, `\E\`, `\X..\`) are resolved at parse time;
//   the serializer re-emits them at serialize time. Callers therefore see
//   real text and never have to know about the escape grammar.
//
// - The recognised escape bodies, all delimited by the escape character
//   (default `\`):
//     F        → field separator literal           (default `|`)
//     S        → component separator literal       (default `^`)
//     T        → subcomponent separator literal    (default `&`)
//     R        → repetition separator literal      (default `~`)
//     E        → escape character literal          (default `\`)
//     X<hex>   → UTF-8 bytes; pairs of hex digits  (e.g. `\X0D\` → CR)
//     Z<...>   → locally-defined; passes through verbatim
//     anything else (`\H\`, `\.br\`, …) → passes through verbatim
//
// - Passthrough means: the literal characters of the escape sequence
//   (including the surrounding escape characters) remain in the decoded
//   string. The encoder recognises a passthrough sequence and re-emits it
//   verbatim rather than double-escaping its backslashes.
//
// - Round-trip invariants (covered by tests):
//     decode(encode(x)) == x   for all plain decoded inputs `x`
//     encode(decode(y)) == y   for canonical encoded wire inputs `y`
//   Non-canonical wire inputs (e.g. `\X41\` for "A") are decoded to the
//   underlying character and re-emitted in canonical form on serialize.

import Foundation

enum EscapeSequences {

    // MARK: - Decode

    /// Resolve HL7 escape sequences in a raw subcomponent string.
    static func decode(_ raw: String, encoding: EncodingCharacters) -> String {
        // Fast path: no escape characters → nothing to decode.
        let esc = encoding.escapeCharacter
        if !raw.contains(esc) { return raw }

        let chars = Array(raw)
        var result = ""
        result.reserveCapacity(chars.count)

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c != esc {
                result.append(c)
                i += 1
                continue
            }
            // Look for the closing escape character.
            guard let j = chars[(i + 1)...].firstIndex(of: esc) else {
                // No closing — treat the lone escape char as a literal.
                result.append(c)
                i += 1
                continue
            }
            let body = chars[(i + 1)..<j]
            if let decoded = decodeBody(body, encoding: encoding) {
                result.append(decoded)
            } else {
                // Unknown or passthrough (\Z…\, \H\, \.br\, etc.) — keep the
                // whole sequence verbatim, escape characters and all.
                result.append(c)
                result.append(contentsOf: body)
                result.append(chars[j])
            }
            i = j + 1
        }
        return result
    }

    private static func decodeBody(
        _ body: ArraySlice<Character>,
        encoding: EncodingCharacters
    ) -> String? {
        guard let first = body.first else { return nil }
        if body.count == 1 {
            switch first {
            case "F": return String(encoding.fieldSeparator)
            case "S": return String(encoding.componentSeparator)
            case "T": return String(encoding.subcomponentSeparator)
            case "R": return String(encoding.repetitionSeparator)
            case "E": return String(encoding.escapeCharacter)
            default: return nil
            }
        }
        if first == "X" {
            return decodeHex(body.dropFirst())
        }
        // `Z…` and anything else: caller emits verbatim.
        return nil
    }

    private static func decodeHex(_ hex: ArraySlice<Character>) -> String? {
        if hex.isEmpty || hex.count % 2 != 0 { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let nextIdx = hex.index(after: idx)
            guard let hi = hexDigitValue(hex[idx]),
                  let lo = hexDigitValue(hex[nextIdx]) else {
                return nil
            }
            bytes.append(UInt8(hi << 4 | lo))
            idx = hex.index(after: nextIdx)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// ASCII-gated wrapper over stdlib `Character.hexDigitValue` — the
    /// stdlib property also accepts fullwidth compatibility digits, which
    /// are not valid in a wire `\X…\` body, so non-ASCII stays rejected.
    private static func hexDigitValue(_ c: Character) -> Int? {
        c.isASCII ? c.hexDigitValue : nil
    }

    // MARK: - Encode

    /// Encode a decoded subcomponent value back into HL7 wire form.
    static func encode(_ value: String, encoding: EncodingCharacters) -> String {
        if !needsEncoding(value, encoding: encoding) { return value }

        let esc = encoding.escapeCharacter
        let chars = Array(value)
        var result = ""
        result.reserveCapacity(chars.count)

        var i = 0
        while i < chars.count {
            let c = chars[i]

            // If this `\` is the start of a passthrough sequence (e.g. `\Z…\`),
            // copy the whole thing verbatim. This is the only way the round
            // trip works for sequences whose backslashes are themselves part
            // of the encoded value.
            if c == esc,
               let closingIdx = chars[(i + 1)...].firstIndex(of: esc),
               isPassthroughBody(chars[(i + 1)..<closingIdx]) {
                for k in i...closingIdx { result.append(chars[k]) }
                i = closingIdx + 1
                continue
            }

            if c == encoding.fieldSeparator {
                appendAtomicEscape("F", into: &result, escape: esc)
            } else if c == encoding.componentSeparator {
                appendAtomicEscape("S", into: &result, escape: esc)
            } else if c == encoding.subcomponentSeparator {
                appendAtomicEscape("T", into: &result, escape: esc)
            } else if c == encoding.repetitionSeparator {
                appendAtomicEscape("R", into: &result, escape: esc)
            } else if c == esc {
                appendAtomicEscape("E", into: &result, escape: esc)
            } else if needsHexEncoding(c) {
                // Coalesce a run of control characters into a single hex
                // block so multi-byte inputs round-trip canonically.
                var runEnd = i
                while runEnd < chars.count && needsHexEncoding(chars[runEnd]) {
                    runEnd += 1
                }
                result.append(esc)
                result.append("X")
                for k in i..<runEnd { appendHex(chars[k], into: &result) }
                result.append(esc)
                i = runEnd
                continue
            } else {
                result.append(c)
            }
            i += 1
        }
        return result
    }

    private static func needsEncoding(_ value: String, encoding: EncodingCharacters) -> Bool {
        value.contains { c in
            c == encoding.fieldSeparator
                || c == encoding.componentSeparator
                || c == encoding.subcomponentSeparator
                || c == encoding.repetitionSeparator
                || c == encoding.escapeCharacter
                || needsHexEncoding(c)
        }
    }

    /// Control characters cannot appear inside a subcomponent on the wire —
    /// CR is the segment terminator — so hex-encode them on serialize. Some
    /// control sequences (notably `\r\n`) form a single Swift Character with
    /// multiple scalars, so we check each scalar.
    private static func needsHexEncoding(_ c: Character) -> Bool {
        for scalar in c.unicodeScalars {
            if scalar.value < 0x20 { return true }
        }
        return false
    }

    private static func appendAtomicEscape(
        _ code: Character,
        into result: inout String,
        escape: Character
    ) {
        result.append(escape)
        result.append(code)
        result.append(escape)
    }

    private static func appendHex(_ c: Character, into result: inout String) {
        let digits: [Character] = [
            "0", "1", "2", "3", "4", "5", "6", "7",
            "8", "9", "A", "B", "C", "D", "E", "F",
        ]
        for byte in c.utf8 {
            result.append(digits[Int(byte >> 4)])
            result.append(digits[Int(byte & 0x0F)])
        }
    }

    /// A body is "passthrough" if the decoder would have emitted the whole
    /// `\body\` verbatim rather than substituting a decoded value. That is:
    /// not one of F/S/T/R/E (atomic) and not a hex `X<hex>` block.
    private static func isPassthroughBody(_ body: ArraySlice<Character>) -> Bool {
        guard let first = body.first else { return false }
        if body.count == 1 {
            switch first {
            case "F", "S", "T", "R", "E": return false
            default: return true
            }
        }
        if first == "X" { return false }
        return true
    }
}
