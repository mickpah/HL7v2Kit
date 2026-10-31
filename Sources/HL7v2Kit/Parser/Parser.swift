// PORTABLE KERNEL — keep this file Foundation-free and byte/character-level.
// A future Rust/Go port translates this file directly. No NSRegularExpression,
// NSString, DateFormatter, CharacterSet, locale-aware ops, protocols, or
// generics in the parse path. `Data` only at the edges (to/from [UInt8]).
// See docs/design/architecture-decisions.md#adr-006-portable-core-boundary

// Parser.swift
// Single-message HL7 v2 parser. Structural only — splits segments, fields,
// repetitions, components, subcomponents. Does NOT hydrate typed segments,
// and does NOT validate field grammar (that's the Validator's job).
//
// v0.1.0 sprint-1 deliverable.

import Foundation

public struct Parser: Sendable {
    public let options: ParserOptions

    /// The locale this parser was configured with. Default `.international`.
    /// Propagates onto every `Message.locale` produced by `parse(_:)`. See
    /// ADR-007.
    public let locale: HL7Locale

    public init(options: ParserOptions = .default, locale: HL7Locale = .international) {
        self.options = options
        self.locale = locale
    }

    /// Parse a v2 message from raw bytes. Character encoding is taken from
    /// MSH-18 if declared; if absent or empty, defaults to UTF-8. If MSH-18
    /// is present but names a charset HL7v2Kit does not recognise, throws
    /// `ParseError.unsupportedCharacterEncoding`.
    ///
    /// A leading UTF-8 BOM (`EF BB BF`) is tolerated as a no-op prefix —
    /// the 3 bytes are stripped before charset detection. Windows-side
    /// senders occasionally emit one; the kit accepts it identically on
    /// macOS and Linux (Foundation's `String(data:encoding:.utf8)` strips
    /// the BOM on macOS but not on Linux Swift, so the explicit strip
    /// makes the byte path portable). The serializer never re-emits the
    /// BOM. A BOM-only input still throws `.emptyInput`.
    ///
    /// Embedded NUL bytes (`0x00`) are rejected with
    /// `ParseError.truncatedMessage(atByte:)`. Real HL7 v2 messages never
    /// carry NUL; if one appears it is almost always transport truncation
    /// (a fixed-size buffer NUL-padded beyond the real message). Rejecting
    /// up-front keeps the round-trip byte-equality invariant (spec §5)
    /// honest: every accepted message is NUL-free, so no carve-out is
    /// needed for serialise round-trips. The reported byte offset is into
    /// the post-BOM-strip payload, not the original buffer.
    public func parse(_ data: Data) throws -> Message {
        let (decoded, characterEncoding) = try Parser.decodeWirePayload(data)
        return try parse(decoded, characterEncoding: characterEncoding)
    }

    /// Decode a raw wire buffer into text: strip a leading UTF-8 BOM
    /// (v0.2-P1), reject NUL bytes (v0.2-P2), detect the MSH-18 charset
    /// via an ISO-8859-1 probe — Latin-1 maps every byte to a code point,
    /// so the probe never fails and the structural ASCII (MSH, `|`, the
    /// encoding chars) survives untouched — then decode with the detected
    /// charset. Shared by ``Parser`` and ``BatchParser`` so the two Data
    /// entry points cannot drift (pinned by the BatchParserTests R5-C3
    /// rows).
    static func decodeWirePayload(_ data: Data) throws -> (decoded: String, characterEncoding: CharacterEncoding) {
        guard !data.isEmpty else { throw ParseError.emptyInput }
        let payload: Data = data.starts(with: [0xEF, 0xBB, 0xBF])
            ? data.dropFirst(3)
            : data
        guard !payload.isEmpty else { throw ParseError.emptyInput }
        if let nulIndex = payload.firstIndex(of: 0x00) {
            throw ParseError.truncatedMessage(
                atByte: payload.distance(from: payload.startIndex, to: nulIndex)
            )
        }
        let probe = String(data: payload, encoding: .isoLatin1) ?? ""
        let characterEncoding = try CharacterEncoding.detect(in: probe)
        guard let decoded = String(data: payload, encoding: characterEncoding.stringEncoding) else {
            throw ParseError.unsupportedCharacterEncoding(declared: characterEncoding.wireValue)
        }
        return (decoded, characterEncoding)
    }

    /// Parse a v2 message from an already-decoded string.
    ///
    /// Even though the input is already-decoded text, MSH-18 is still
    /// consulted so that the resulting `Message.characterEncoding` reflects
    /// the wire declaration. **An unrecognised MSH-18 value throws
    /// `ParseError.unsupportedCharacterEncoding`** — same behaviour as
    /// `parse(_ data: Data)`. If you want to parse structurally without
    /// MSH-18 validation, decode the bytes yourself and call a future
    /// `parse(structural:)` overload (not in v0.1.0).
    public func parse(_ raw: String) throws -> Message {
        let characterEncoding = try CharacterEncoding.detect(in: raw)
        return try parse(raw, characterEncoding: characterEncoding)
    }

    private func parse(_ raw: String, characterEncoding: CharacterEncoding) throws -> Message {
        guard !raw.isEmpty else { throw ParseError.emptyInput }

        // Normalise line terminators per policy. Whether the input ended with \r is
        // recorded on the message so serialise() can put it back (P00 S1-1).
        let normalised = normaliseLineTerminators(raw)

        // Split on the carriage-return scalar (the HL7 segment terminator), not on
        // Characters: "\r\n" is one Character in Swift, so a Character split would fold a
        // CRLF line into the segment before it (P00 S1-3). Keep empty trailing entries
        // out — they represent the final \r after the last segment.
        var segmentStrings = normalised.unicodeScalars
            .split(separator: "\r", omittingEmptySubsequences: false)
            .map { String(String.UnicodeScalarView($0)) }
        // Trailing empty string after final \r is expected; drop it for parsing.
        if segmentStrings.last == "" {
            segmentStrings.removeLast()
        }

        // Under .strict only \r ends a segment, so a line starting with \n is a CRLF line
        // ending, not a segment (.lenient has already rewritten it).
        if options.lineTerminator == .strict,
           let index = segmentStrings.firstIndex(where: { $0.unicodeScalars.first == "\n" }) {
            throw ParseError.lineFeedAfterSegmentTerminator(position: index + 1)
        }

        guard !segmentStrings.isEmpty else { throw ParseError.missingMSH }

        // MSH must come first.
        let mshLine = segmentStrings[0]
        guard mshLine.hasPrefix("MSH") else { throw ParseError.missingMSH }

        // MSH-1 is the field separator (the character right after "MSH").
        guard mshLine.count >= 8 else {
            throw ParseError.invalidMSH(reason: "too short")
        }
        let mshChars = Array(mshLine)
        let fieldSep = mshChars[3]

        // MSH-2 is four encoding characters (component, repetition, escape, subcomponent),
        // optionally followed by the v2.7+ truncation character, then the field separator
        // (P00 S1-2). MSH-2 is kept as one literal, so the fifth character round-trips; the
        // validator reports it where the version prints MSH-2 as four characters.
        let truncation: Character?
        if mshChars.count >= 9, mshChars[8] == fieldSep {
            truncation = nil
        } else if mshChars.count >= 10, mshChars[9] == fieldSep {
            truncation = mshChars[8]
        } else {
            throw ParseError.invalidMSH(reason: "MSH-2 not followed by field separator")
        }
        let encoding = EncodingCharacters(
            fieldSeparator: fieldSep,
            componentSeparator: mshChars[4],
            repetitionSeparator: mshChars[5],
            escapeCharacter: mshChars[6],
            subcomponentSeparator: mshChars[7]
        )
        // The truncation character cannot be the field separator (the branch above), and
        // must not repeat any of the four.
        guard encoding.isValid, truncation.map({ !mshChars[4...7].contains($0) }) ?? true else {
            throw ParseError.invalidMSH(reason: "encoding characters not distinct")
        }

        // Parse all segments.
        var segments: [Segment] = []
        for (i, segLine) in segmentStrings.enumerated() {
            if segLine.isEmpty { continue }   // tolerate blank lines mid-message
            let segment = try parseSegment(segLine, encoding: encoding,
                                           separatorSegment: i == 0 || Self.isSeparatorSegment(segLine))
            // Enforce strict mode: if the registry returned `.unknown`, the
            // segment ID is not in the codegen-emitted typed-segment table.
            // Under `allowUnknownSegments: false` we reject it.
            if !options.allowUnknownSegments, case .unknown(let unk) = segment {
                throw ParseError.unknownSegment(id: unk.segmentID, position: i + 1)
            }
            segments.append(segment)
        }

        // Determine version from MSH-12 (or override). Read it off the
        // unified Segment.fields accessor so we don't care whether the MSH
        // came back as .typed (hydrated) or .unknown (fallback).
        let version: Version
        if let override = options.versionOverride {
            version = override
        } else {
            let msh12 = segments.first.flatMap { $0.segmentID == "MSH" ? $0.field(12) : nil }
            switch Version.reading(msh12: msh12, subcomponentSeparator: encoding.subcomponentSeparator) {
            case .recognised(let declared):
                version = declared
            case .unresolved(let vid1):
                // MSH-12 is populated but names no modelled version. Strict
                // parsing rejects it; otherwise parse against v2.5.1 and let
                // the Validator report `versionNotRecognised` (ADR-018).
                if options.rejectUnknownVersion {
                    throw ParseError.unsupportedVersion(found: vid1)
                }
                version = .v2_5_1
            case .empty:
                // No MSH or an empty MSH-12: fall back to v2.5.1 in every
                // mode. MSH-12 is required, so the Validator's required-field
                // check reports it; this is not a parser concern.
                version = .v2_5_1
            }
        }

        var message = Message(
            version: version,
            encodingCharacters: encoding,
            segments: segments,
            characterEncoding: characterEncoding,
            locale: locale
        )
        // Unicode scalars, not Characters: "\r\n" is one Character in Swift.
        message.trailingSegmentTerminator = normalised.unicodeScalars.last == "\r"
        return message
    }

    // MARK: - Segment parsing

    /// Segments whose field 1 IS the field separator and field 2 the encoding characters
    /// (HL7 v2 §2.x: MSH-1/MSH-2, and identically BHS-1/BHS-2 and FHS-1/FHS-2 for the batch
    /// and file envelopes). Sprint 0 §3C: before this, an envelope line inside a message was
    /// numbered plainly, so every BHS/FHS field read one position off the spec.
    static func isSeparatorSegment(_ line: String) -> Bool {
        line.hasPrefix("MSH") || line.hasPrefix("BHS") || line.hasPrefix("FHS")
    }

    func parseSegment(
        _ line: String,
        encoding: EncodingCharacters,
        separatorSegment: Bool
    ) throws -> Segment {
        let chars = Array(line)
        guard chars.count >= 3 else {
            throw ParseError.invalidMSH(reason: "segment too short: '\(line)'")
        }

        let segmentID = String(chars[0..<3])

        // Split into raw field strings.
        // MSH / BHS / FHS are special: the field separator IS field 1, so the raw split
        // looks like ["MSH", "^~\\&", ...] but the SEMANTIC fields are:
        //   fields[0] = "MSH"  (segment ID)
        //   fields[1] = fieldSeparator (single character)
        //   fields[2] = encoding chars
        //   fields[3] = sending application
        //   ...
        var rawFields: [String]
        if separatorSegment {
            if chars.count <= 3 {
                // "BHS" or "FHS" alone: no separator, so no fields.
                rawFields = [segmentID]
            } else {
                // Slice off the ID + field separator. Reconstruct fields[1] and [2] manually.
                // line == "MSH|^~\\&|sendingApp|..."
                let afterPrefix = String(chars[4...])   // everything after "MSH|"
                let rest = afterPrefix.split(separator: encoding.fieldSeparator,
                                              omittingEmptySubsequences: false)
                                       .map(String.init)
                // The first element of `rest` is "^~\\&" (field 2), then the actual fields.
                // Build the canonical array:
                rawFields = [segmentID, String(encoding.fieldSeparator)] + rest
            }
        } else {
            let afterID = String(chars[3...])
            // afterID starts with field separator. Remove the leading one then split.
            let trimmed: String
            if afterID.first == encoding.fieldSeparator {
                trimmed = String(afterID.dropFirst())
            } else {
                trimmed = afterID
            }
            let parts = trimmed.split(separator: encoding.fieldSeparator,
                                       omittingEmptySubsequences: false)
                                .map(String.init)
            rawFields = [segmentID] + parts
        }

        // Parse each field. Index 0 (segment ID) stays as a placeholder empty field.
        var fields: [Field] = []
        for (i, rawField) in rawFields.enumerated() {
            if i == 0 {
                // Segment ID slot — not a real field, but keep array indices 1-based.
                fields.append(Field(repetitions: []))
            } else if separatorSegment && i == 1 {
                // MSH-1 (BHS-1, FHS-1) is the field separator as a single character.
                fields.append(.scalar(rawField))
            } else if separatorSegment && i == 2 {
                // MSH-2 (BHS-2, FHS-2) is the encoding characters (four, or five with the truncation character) as one literal value (no internal split).
                fields.append(.scalar(rawField))
            } else {
                fields.append(parseField(rawField, encoding: encoding))
            }
        }

        let unknown = UnknownSegment(segmentID: segmentID, fields: fields)
        return SegmentRegistry.hydrate(unknown)
    }

    private func parseField(_ raw: String, encoding: EncodingCharacters) -> Field {
        if raw.isEmpty {
            return .scalar("")
        }
        let reps = raw.split(separator: encoding.repetitionSeparator,
                              omittingEmptySubsequences: false)
                       .map { parseRepetition(String($0), encoding: encoding) }
        return Field(repetitions: reps)
    }

    private func parseRepetition(_ raw: String, encoding: EncodingCharacters) -> Repetition {
        let comps = raw.split(separator: encoding.componentSeparator,
                                omittingEmptySubsequences: false)
                        .map { parseComponent(String($0), encoding: encoding) }
        return Repetition(components: comps)
    }

    private func parseComponent(_ raw: String, encoding: EncodingCharacters) -> Component {
        let subs = raw.split(separator: encoding.subcomponentSeparator,
                               omittingEmptySubsequences: false)
                       .map { part -> Subcomponent in
                           let text = String(part)
                           // #13: keep the wire text of an escaped value.
                           let wire = text.contains(encoding.escapeCharacter) ? text : nil
                           return Subcomponent(EscapeSequences.decode(text, encoding: encoding), wire: wire)
                       }
        return Component(subcomponents: subs)
    }

    // MARK: - Line terminator normalisation

    private func normaliseLineTerminators(_ raw: String) -> String {
        switch options.lineTerminator {
        case .strict:
            // No normalisation — input must use \r already.
            return raw
        case .lenient:
            // Accept any combination. Order matters: \r\n must become \r before
            // standalone \n becomes \r, otherwise \r\n becomes \r\r.
            return raw
                .replacingOccurrences(of: "\r\n", with: "\r")
                .replacingOccurrences(of: "\n", with: "\r")
        }
    }
}

// Batch envelopes: the FHS, BHS, BTS and FTS lines BatchParser keeps beside each batch.
extension Parser {
    /// The delimiters an FHS or BHS line declares, or nil when they cannot be read: the field
    /// separator after the ID, then four distinct encoding characters (a fifth, the v2.7+
    /// truncation character, is allowed), then the end of the line or the field separator.
    static func headerDelimiters(_ line: String) -> EncodingCharacters? {
        let chars = Array(line)
        guard chars.count >= 8 else { return nil }
        let separator = chars[3]
        let encodingEnd = chars.count > 8 && chars[8] != separator ? 9 : 8
        guard chars.count == encodingEnd || chars[encodingEnd] == separator else { return nil }
        let encoding = EncodingCharacters(fieldSeparator: separator, componentSeparator: chars[4],
                                          repetitionSeparator: chars[5], escapeCharacter: chars[6],
                                          subcomponentSeparator: chars[7])
        return encoding.isValid ? encoding : nil
    }

    /// One envelope line as a segment. FHS and BHS use their own delimiters when they can be
    /// read, else `inherited`; BTS and FTS use `inherited`. Never throws: the line starts with
    /// its three-character ID, and a header with no separator becomes a segment with no fields.
    static func envelopeSegment(_ line: String, inherited: EncodingCharacters) -> Segment {
        let id = String(line.prefix(3))
        let header = id == "FHS" || id == "BHS"
        let encoding = header ? headerDelimiters(line) ?? inherited : inherited
        let parsed = try? Parser().parseSegment(line, encoding: encoding, separatorSegment: header)
        return parsed ?? .unknown(UnknownSegment(segmentID: id, fields: [Field(repetitions: [])]))
    }
}
