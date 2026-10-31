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
//   on serialize a parsed value is written from its wire text (below) and a
//   value built in code is encoded. Callers therefore see real text and never
//   have to know about the escape grammar.
//
// - A parsed `Subcomponent` also keeps the wire text it was read from when that
//   text holds the escape character (#13). `wireForm(of:encoding:)` returns it
//   while it is still a faithful encoding under the target delimiters, so a parsed
//   value is written back as read; otherwise the value is encoded below.
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
//     anything else (`\H\`, `\.br\`, …) → kept verbatim on decode. On encode a
//     value with no wire text copies a run only when the standard defines it
//     (`isRepertoireBody`); any other run is text (#13).
//
// - Passthrough means: the literal characters of the escape sequence
//   (including the surrounding escape characters) remain in the decoded
//   string. A parsed value is written back from its wire text; a value built
//   in code copies a run the standard defines and escapes any other.
//
// - Round-trip invariants (covered by tests):
//     decode(encode(x)) == x   for all plain decoded inputs `x`
//     encode(decode(y)) == y   for canonical encoded wire inputs `y`
//   Non-canonical wire inputs (e.g. `\X41\` for "A") decode to the underlying
//   character; `encode` writes the canonical form, but a parsed value keeps and
//   serialises its wire text as sent (#13).

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

    // MARK: - Wire form

    /// The wire text of `subcomponent` under `encoding`: the text it was parsed from while that
    /// text is still a faithful encoding of its value there, otherwise ``encode(_:encoding:)``
    /// of the value (#13). The serialiser and the escape and length checks all read this.
    static func wireForm(of subcomponent: Subcomponent, encoding: EncodingCharacters) -> String {
        if let wire = subcomponent.wire, isFaithful(wire, to: subcomponent.value, encoding: encoding) {
            return wire
        }
        return encode(subcomponent.value, encoding: encoding)
    }

    /// Faithful: holds no delimiter or control character of `encoding` and decodes to `value`.
    /// A value copied into a message with other delimiters fails this and is encoded.
    private static func isFaithful(_ wire: String, to value: String, encoding: EncodingCharacters) -> Bool {
        isPlainBody(ArraySlice(wire), encoding: encoding) && decode(wire, encoding: encoding) == value
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

            // A `\…\` run the standard defines (#13) is copied as the escape it is;
            // any other run is text and its escape characters are escaped below.
            if c == esc,
               let closingIdx = chars[(i + 1)...].firstIndex(of: esc),
               isRepertoireBody(chars[(i + 1)..<closingIdx]),
               isPlainBody(chars[(i + 1)..<closingIdx], encoding: encoding) {
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

    /// A body the encoder may copy verbatim holds no delimiter and no control character. A parsed
    /// value holds one when its escapes decode to it (`\E\a\F\b\E\` decodes to `\a|b\`), and a
    /// value written in code can hold one; copying it would split a field or start a segment
    /// (P00 S3).
    private static func isPlainBody(_ body: ArraySlice<Character>, encoding: EncodingCharacters) -> Bool {
        for c in body {
            if c == encoding.fieldSeparator || c == encoding.componentSeparator
                || c == encoding.repetitionSeparator || c == encoding.subcomponentSeparator
                || needsHexEncoding(c) {
                return false
            }
        }
        return true
    }

    /// A body the standard defines as an escape the decoder keeps verbatim (v2.5.1 Chapter 2,
    /// sections 2.7.1 to 2.7.6; `\P\` from v2.7): highlighting `H` and `N`, the truncation
    /// character `P`, locally defined `Z…`, the character-set escapes `Cxxyy` and `Mxxyy(zz)`,
    /// and the formatting commands. Anything else written in code is text (#13). `P` is
    /// accepted on every version: the encoding characters do not carry MSH-2's fifth character.
    private static func isRepertoireBody(_ body: ArraySlice<Character>) -> Bool {
        guard let first = body.first else { return false }
        let rest = body.dropFirst()
        switch first {
        case "H", "N", "P": return rest.isEmpty
        case "Z": return !rest.isEmpty
        case "C": return rest.count == 4 && rest.allSatisfy { hexDigitValue($0) != nil }
        case "M": return (rest.count == 4 || rest.count == 6) && rest.allSatisfy { hexDigitValue($0) != nil }
        case ".": return isFormattingCommand(rest)
        default: return false
        }
    }

    /// A formatting command after its period (v2.5.1 section 2.7.6): `br`, `fi`, `nf`, `ce`;
    /// `sp` with an optional unsigned integer; `in` and `ti` with an optionally signed integer;
    /// `sk` with an unsigned integer. One space may stand before the number (`.sp <number>`).
    private static func isFormattingCommand(_ body: ArraySlice<Character>) -> Bool {
        let name = String(body.prefix(2))
        var number = body.dropFirst(2)
        switch name {
        case "br", "fi", "nf", "ce": return number.isEmpty
        case "sp": if number.isEmpty { return true }   // `.sp` alone; with a number, checked below
        case "in", "ti", "sk": break
        default: return false
        }
        if number.first == " ", number.count > 1 { number = number.dropFirst() }
        if name == "in" || name == "ti", let sign = number.first, sign == "+" || sign == "-" {
            number = number.dropFirst()
        }
        return !number.isEmpty && number.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
