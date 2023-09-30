// PORTABLE KERNEL — keep this file Foundation-free and byte/character-level.
// A future Rust/Go port translates this file directly. No NSRegularExpression,
// NSString, DateFormatter, CharacterSet, locale-aware ops, protocols, or
// generics in the parse path. `Data` only at the edges (to/from [UInt8]).
// See docs/design/ADR-006-portable-core-boundary.md

// Serializer.swift
// Converts a Message back to wire bytes. The round-trip pair for Parser.

import Foundation

/// Internal-style namespace for serialisation. Public surface is
/// `Message.serialize()`.
enum Serializer {
    static func serialize(_ message: Message) -> Data {
        var lines: [String] = []
        let enc = message.encodingCharacters

        for (i, segment) in message.segments.enumerated() {
            let isMSH = (i == 0 && segment.segmentID == "MSH")
            lines.append(serializeSegment(segment, encoding: enc, isMSH: isMSH))
        }

        // HL7 spec: segments separated by \r, message terminated by \r.
        let body = lines.joined(separator: "\r") + "\r"
        return body.data(using: message.characterEncoding.stringEncoding) ?? Data(body.utf8)
    }

    private static func serializeSegment(
        _ segment: Segment,
        encoding enc: EncodingCharacters,
        isMSH: Bool
    ) -> String {
        let id = segment.segmentID
        let fields = segment.fields

        // Build the field strings from index 1 onwards (index 0 is the segment ID).
        var fieldStrings: [String] = []
        for (i, field) in fields.enumerated() {
            if i == 0 { continue }   // segment ID is emitted as the prefix
            if isMSH && i == 1 {
                // MSH-1 is the field separator itself, emitted as part of the
                // header, not as a value between separators.
                continue
            }
            if isMSH && i == 2 {
                // MSH-2 is the 4 encoding chars, emitted directly.
                fieldStrings.append(field.stringValue ?? enc.msh2String)
                continue
            }
            fieldStrings.append(serializeField(field, encoding: enc))
        }

        let sep = String(enc.fieldSeparator)
        if isMSH {
            // "MSH" + sep + (MSH-2 value) + sep + rest...
            // MSH-2 is in fieldStrings[0] now (since we skipped i==1).
            // Sanity: if MSH-2 missing, default it.
            if fieldStrings.isEmpty {
                return id + sep + enc.msh2String
            }
            let msh2 = fieldStrings[0]
            let rest = fieldStrings.dropFirst()
            if rest.isEmpty {
                return id + sep + msh2
            }
            return id + sep + msh2 + sep + rest.joined(separator: sep)
        } else {
            if fieldStrings.isEmpty {
                return id
            }
            return id + sep + fieldStrings.joined(separator: sep)
        }
    }

    private static func serializeField(_ field: Field, encoding enc: EncodingCharacters) -> String {
        field.repetitions
            .map { serializeRepetition($0, encoding: enc) }
            .joined(separator: String(enc.repetitionSeparator))
    }

    private static func serializeRepetition(_ rep: Repetition, encoding enc: EncodingCharacters) -> String {
        rep.components
            .map { serializeComponent($0, encoding: enc) }
            .joined(separator: String(enc.componentSeparator))
    }

    private static func serializeComponent(_ comp: Component, encoding enc: EncodingCharacters) -> String {
        comp.subcomponents
            .map { EscapeSequences.encode($0.value, encoding: enc) }
            .joined(separator: String(enc.subcomponentSeparator))
    }
}
