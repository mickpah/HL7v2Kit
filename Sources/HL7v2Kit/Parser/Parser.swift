// PORTABLE KERNEL — keep this file Foundation-free and byte/character-level.
// A future Rust/Go port translates this file directly. No NSRegularExpression,
// NSString, DateFormatter, CharacterSet, locale-aware ops, protocols, or
// generics in the parse path. `Data` only at the edges (to/from [UInt8]).
// See docs/design/ADR-006-portable-core-boundary.md

// Parser.swift
// Single-message HL7 v2 parser. Structural only — splits segments, fields,
// repetitions, components, subcomponents. Does NOT hydrate typed segments,
// and does NOT validate field grammar (that's the Validator's job).
//
// v0.1.0 sprint-1 deliverable.

import Foundation

public struct Parser: Sendable {
    public let options: ParserOptions

    public init(options: ParserOptions = .default) {
        self.options = options
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
    public func parse(_ data: Data) throws -> Message {
        guard !data.isEmpty else { throw ParseError.emptyInput }

        // Strip a leading UTF-8 BOM before any structural work. v0.2-P1.
        let payload: Data = data.starts(with: [0xEF, 0xBB, 0xBF])
            ? data.dropFirst(3)
            : data
        guard !payload.isEmpty else { throw ParseError.emptyInput }

        // Probe via an ISO-8859-1 1:1 decode — Latin-1 maps every byte to a
        // code point, so the probe never fails, and the structural ASCII
        // characters (MSH, `|`, the encoding chars) survive untouched.
        let probe = String(data: payload, encoding: .isoLatin1) ?? ""
        let characterEncoding = try CharacterEncoding.detect(in: probe)

        guard let decoded = String(data: payload, encoding: characterEncoding.stringEncoding) else {
            throw ParseError.unsupportedCharacterEncoding(declared: characterEncoding.wireValue)
        }
        return try parse(decoded, characterEncoding: characterEncoding)
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

        // Normalise line terminators per policy. Always *preserve* trailing
        // structure so serialise() can put it back.
        let normalised = normaliseLineTerminators(raw)

        // Split by \r (the HL7 segment terminator). Keep empty trailing entries
        // out — they represent the final \r after the last segment.
        var segmentStrings = normalised.components(separatedBy: "\r")
        // Trailing empty string after final \r is expected; drop it for parsing.
        if segmentStrings.last == "" {
            segmentStrings.removeLast()
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

        // MSH-2 is the next four characters: component, repetition, escape, subcomponent.
        // After "MSH|" we expect 4 encoding chars then another field separator.
        guard mshChars.count >= 9, mshChars[8] == fieldSep else {
            throw ParseError.invalidMSH(reason: "MSH-2 not followed by field separator")
        }
        let encoding = EncodingCharacters(
            fieldSeparator: fieldSep,
            componentSeparator: mshChars[4],
            repetitionSeparator: mshChars[5],
            escapeCharacter: mshChars[6],
            subcomponentSeparator: mshChars[7]
        )
        guard encoding.isValid else {
            throw ParseError.invalidMSH(reason: "encoding characters not distinct")
        }

        // Parse all segments.
        var segments: [Segment] = []
        for (i, segLine) in segmentStrings.enumerated() {
            if segLine.isEmpty { continue }   // tolerate blank lines mid-message
            let segment = try parseSegment(segLine, encoding: encoding, isMSH: i == 0)
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
        } else if let mshSegment = segments.first,
                  let v12 = mshSegment.field(12)?.stringValue,
                  let parsed = Version(wireValue: v12) {
            version = parsed
        } else {
            // Fall back to v2.5.1 (the most common AU dialect) rather than
            // throwing — this keeps the parser useful for older fixtures
            // where MSH-12 is absent or non-canonical. v0.2 will tighten this.
            version = .v2_5_1
        }

        return Message(
            version: version,
            encodingCharacters: encoding,
            segments: segments,
            characterEncoding: characterEncoding
        )
    }

    // MARK: - Segment parsing

    private func parseSegment(
        _ line: String,
        encoding: EncodingCharacters,
        isMSH: Bool
    ) throws -> Segment {
        let chars = Array(line)
        guard chars.count >= 3 else {
            throw ParseError.invalidMSH(reason: "segment too short: '\(line)'")
        }

        let segmentID = String(chars[0..<3])

        // Split into raw field strings.
        // MSH is special: the field separator IS field 1, so the raw split looks
        // like ["MSH", "^~\\&", ...] but the SEMANTIC fields are:
        //   fields[0] = "MSH"  (segment ID)
        //   fields[1] = fieldSeparator (single character)
        //   fields[2] = encoding chars
        //   fields[3] = sending application
        //   ...
        var rawFields: [String]
        if isMSH {
            // Slice off "MSH" + field separator. Reconstruct fields[1] and [2] manually.
            // line == "MSH|^~\\&|sendingApp|..."
            let afterPrefix = String(chars[4...])   // everything after "MSH|"
            let rest = afterPrefix.split(separator: encoding.fieldSeparator,
                                          omittingEmptySubsequences: false)
                                   .map(String.init)
            // The first element of `rest` is "^~\\&" (MSH-2), then the actual fields.
            // Build the canonical array:
            rawFields = ["MSH", String(encoding.fieldSeparator)] + rest
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
            } else if isMSH && i == 1 {
                // MSH-1 is the field separator as a single character.
                fields.append(.scalar(rawField))
            } else if isMSH && i == 2 {
                // MSH-2 is the 4 encoding chars as a single literal value (no internal split).
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
            return Field(repetitions: [Repetition(components: [Component(subcomponents: [Subcomponent("")])])])
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
                       .map { Subcomponent(EscapeSequences.decode(String($0), encoding: encoding)) }
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
