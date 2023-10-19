// Message.swift
// The top-level type representing a parsed HL7 v2 message.

import Foundation

/// A parsed HL7 v2 message.
///
/// Lossless: round-trips to wire bytes byte-for-byte when the original was
/// syntactically valid and accepted by the parser. See `serialize()`.
public struct Message: Sendable, Equatable, Hashable {
    /// The HL7 version declared in MSH-12.
    public let version: Version

    /// The five encoding characters declared in MSH-1 and MSH-2.
    public let encodingCharacters: EncodingCharacters

    /// The segments in document order. The first segment is always MSH.
    public let segments: [Segment]

    /// The character set declared in MSH-18 (or `.utf8` when absent).
    /// `serialize()` re-emits bytes in this encoding.
    public let characterEncoding: CharacterEncoding

    /// The locale the parser was configured with. Default is `.international`.
    /// Downstream consumers (e.g. a FHIR mapping layer) can read this to
    /// know which localisation promises the validator made. See ADR-007.
    public let locale: HL7Locale

    public init(
        version: Version,
        encodingCharacters: EncodingCharacters,
        segments: [Segment],
        characterEncoding: CharacterEncoding = .utf8,
        locale: HL7Locale = .international
    ) {
        self.version = version
        self.encodingCharacters = encodingCharacters
        self.segments = segments
        self.characterEncoding = characterEncoding
        self.locale = locale
    }

    // MARK: - Path access (ad-hoc)

    /// Read a field, component, or subcomponent by HL7 path string.
    ///
    /// Examples:
    /// ```
    /// msg["MSH-9"]      // message type field
    /// msg["MSH-9.1"]    // message code
    /// msg["PID-5.1"]    // family name (first repetition, first component)
    /// msg["OBX[2]-5"]   // second OBX segment, field 5
    /// ```
    ///
    /// Returns `nil` if the path doesn't resolve or refers to a non-scalar
    /// node. For structured access, use the typed segment accessors.
    public subscript(pathString: String) -> String? {
        guard let path = try? Path(pathString) else { return nil }
        return self[path]
    }

    /// Read a value by parsed `Path`.
    public subscript(path: Path) -> String? {
        // Find the matching segment.
        let segmentIndex = path.segmentIndex ?? 1
        let matching = segments.enumerated()
            .filter { _, seg in seg.segmentID == path.segmentID }
        guard segmentIndex >= 1, segmentIndex <= matching.count else { return nil }
        let segment = matching[segmentIndex - 1].element

        // Access the field.
        guard let field = segment.field(path.field) else { return nil }

        // Repetition (default 1).
        let repIndex = path.repetition ?? 1
        guard repIndex >= 1, repIndex <= field.repetitions.count else { return nil }
        let repetition = field.repetitions[repIndex - 1]

        // No component → return the whole repetition as a flattened string.
        guard let componentIndex = path.component else {
            return repetition.stringValue
        }
        guard componentIndex >= 1, componentIndex <= repetition.components.count else { return nil }
        let component = repetition.components[componentIndex - 1]

        // No subcomponent → return the component scalar.
        guard let subIndex = path.subcomponent else {
            return component.stringValue
        }
        guard subIndex >= 1, subIndex <= component.subcomponents.count else { return nil }
        return component.subcomponents[subIndex - 1].value
    }

    // MARK: - Typed segment access

    /// Find the first segment of the given typed-segment type, if present.
    public func firstSegment<S: TypedSegment>(_ type: S.Type) -> S? {
        for segment in segments {
            if case .typed(let any) = segment, let typed = any.cast(to: S.self) {
                return typed
            }
        }
        return nil
    }

    /// Find all segments of the given typed-segment type, in document order.
    public func allSegments<S: TypedSegment>(_ type: S.Type) -> [S] {
        segments.compactMap { segment -> S? in
            if case .typed(let any) = segment {
                return any.cast(to: S.self)
            }
            return nil
        }
    }

    // MARK: - Serialisation

    /// Serialise this message back to wire bytes.
    ///
    /// For messages produced by `Parser`, the output equals the input bytes
    /// (modulo the documented round-trip exceptions in the spec).
    public func serialize() -> Data {
        Serializer.serialize(self)
    }
}
