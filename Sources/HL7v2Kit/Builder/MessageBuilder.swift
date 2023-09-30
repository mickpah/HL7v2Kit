// MessageBuilder.swift
// Programmatic construction of HL7 v2 messages. Sprint-3 builder API per spec.

import Foundation

public enum BuilderError: Error, Equatable, Sendable {
    case missingMSH
    case invalidEncodingCharacters
    case duplicateMSH
}

/// Builds an HL7 v2 `Message` segment-by-segment.
///
/// Typical usage:
///
/// ```swift
/// var b = MessageBuilder(version: .v2_5_1)
/// b.msh(
///     messageType: (code: "ADT", triggerEvent: "A01"),
///     messageControlID: "MSG00001"
/// )
/// b.appendSegment(id: "PID", fields: [Field.scalar("1")])
/// let message = try b.build()
/// ```
public struct MessageBuilder: Sendable {
    public let version: Version
    public let encodingCharacters: EncodingCharacters
    public let characterEncoding: CharacterEncoding
    private var segments: [Segment] = []

    public init(
        version: Version,
        encodingCharacters: EncodingCharacters = .default,
        characterEncoding: CharacterEncoding = .utf8
    ) {
        self.version = version
        self.encodingCharacters = encodingCharacters
        self.characterEncoding = characterEncoding
    }

    /// Append an unknown segment (Z-segment or pre-built raw segment).
    public mutating func append(unknown: UnknownSegment) {
        segments.append(.unknown(unknown))
    }

    /// Append a segment built from raw field data.
    ///
    /// `fields` is 1-indexed in v2 numbering — i.e. `fields[0]` becomes the
    /// segment's first wire field. The builder always prepends an empty
    /// `Field` to occupy the segment-ID placeholder slot at array index 0;
    /// callers should NOT pre-include it.
    public mutating func appendSegment(id: String, fields: [Field]) {
        let withPlaceholder = [Field(repetitions: [])] + fields
        segments.append(.unknown(UnknownSegment(segmentID: id, fields: withPlaceholder)))
    }

    /// Build the message. Throws if MSH is missing.
    public func build() throws -> Message {
        guard let first = segments.first, first.segmentID == "MSH" else {
            throw BuilderError.missingMSH
        }
        return Message(
            version: version,
            encodingCharacters: encodingCharacters,
            segments: segments,
            characterEncoding: characterEncoding
        )
    }
}

// MARK: - Fluent helpers

public extension MessageBuilder {
    /// Build and append an MSH segment with the most common fields populated.
    /// This is a convenience for v0.1.0 testing; v0.2+ will offer fully-typed
    /// MSH construction.
    @discardableResult
    mutating func msh(
        messageType: (code: String, triggerEvent: String),
        sendingApplication: String? = nil,
        sendingFacility: String? = nil,
        receivingApplication: String? = nil,
        receivingFacility: String? = nil,
        messageControlID: String,
        processingID: String = "P"
    ) -> Self {
        // Fields are 1-based. Index 0 is reserved for the segment ID slot.
        // For MSH specifically:
        //   fields[1] = field separator (single char)
        //   fields[2] = MSH-2 (encoding characters as a 4-char string)
        //   fields[3] = sending application
        //   fields[4] = sending facility
        //   fields[5] = receiving application
        //   fields[6] = receiving facility
        //   fields[7] = date/time of message (omitted in v0.1)
        //   fields[8] = security (empty)
        //   fields[9] = message type (composite: code^triggerEvent^structure)
        //   fields[10] = message control ID
        //   fields[11] = processing ID
        //   fields[12] = version
        var fields: [Field] = []
        let empty = Field(repetitions: [Repetition(components: [Component(subcomponents: [Subcomponent("")])])])
        fields.append(Field(repetitions: []))                                            // 0: segment ID placeholder
        fields.append(.scalar(String(encodingCharacters.fieldSeparator)))                // 1: MSH-1
        fields.append(.scalar(encodingCharacters.msh2String))                            // 2: MSH-2
        fields.append(.scalar(sendingApplication ?? ""))                                 // 3
        fields.append(.scalar(sendingFacility ?? ""))                                    // 4
        fields.append(.scalar(receivingApplication ?? ""))                               // 5
        fields.append(.scalar(receivingFacility ?? ""))                                  // 6
        fields.append(empty)                                                              // 7: date/time
        fields.append(empty)                                                              // 8: security
        fields.append(.components([messageType.code, messageType.triggerEvent]))         // 9
        fields.append(.scalar(messageControlID))                                          // 10
        fields.append(.scalar(processingID))                                              // 11
        fields.append(.scalar(version.rawValue))                                          // 12

        segments.append(.unknown(UnknownSegment(segmentID: "MSH", fields: fields)))
        return self
    }
}
