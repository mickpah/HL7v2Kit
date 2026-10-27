// Anonymiser.swift
// De-identifies a parsed message (spec section 10): the identifying fields of the patient,
// next of kin, insured and providers become synthetic values. The HL7v2KitAnonymise tool
// calls it with its per-file salt.

import Foundation

/// Replaces the identifying fields of a message with synthetic values.
package struct Anonymiser: Sendable {
    let source: SyntheticSource

    /// The command-line tool's rule: every value chosen from one salt per file.
    package init(legacySalt: Int) {
        source = .legacy(salt: legacySalt)
    }

    /// `message` with its covered fields replaced. A segment with no covered field is kept as
    /// it is; a covered one is rebuilt as an unknown segment, which serialises the same way and
    /// becomes typed again when re-parsed.
    package func anonymise(_ message: Message) -> Message {
        let segments = message.segments.map { segment -> Segment in
            let id = segment.segmentID
            guard id == "MSH" || id == "NTE" || Self.coverage[id] != nil else { return segment }
            var fields = segment.fields
            switch id {
            case "MSH": replaceFacilities(&fields)
            case "NTE": redactComment(&fields)
            case "OBX": redactObservationValue(&fields, valueType: segment.field(2)?.stringValue)
            default: break
            }
            for (index, rule) in Self.coverage[id] ?? [] { apply(rule, to: &fields, at: index) }
            return .unknown(UnknownSegment(segmentID: id, fields: fields))
        }
        return Message(version: message.version, encodingCharacters: message.encodingCharacters,
                       segments: segments, characterEncoding: message.characterEncoding,
                       locale: message.locale)
    }
}
