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

    // MARK: - Cross-segment helpers (v0.7-S1, ADR-008)

    /// MSH-9.1 — message code (e.g. "ORU", "ADT", "ORM").
    /// Reads the first component of MSH-9 via the path subscript.
    /// Used by the cross-segment / message-context predicate DSL.
    var messageCode: String? {
        self["MSH-9.1"]
    }

    /// MSH-9.2 — trigger event (e.g. "R01", "A01", "O01").
    var triggerEvent: String? {
        self["MSH-9.2"]
    }

    /// MSH-9.3 — message structure (e.g. "ORU_R01", "ADT_A01").
    /// Returns `nil` when MSH-9 carries only the legacy two-component
    /// form (`code^event`) common on v2.3 wires.
    var messageStructure: String? {
        self["MSH-9.3"]
    }

    /// Resolve the segment of `id` "associated" with the segment at
    /// `fromIndex`, per ADR-008's ORC/OBR group semantics.
    ///
    /// The group is delimited by ORC segments: the group head is the
    /// most recent ORC at or before `fromIndex`; the group ends at the
    /// next ORC (or the end of the segment list). The first segment of
    /// `id` within that range, excluding `fromIndex` itself, is the
    /// associated peer.
    ///
    /// Returns `nil` when no match is found in the group — fail-safe
    /// for the predicate evaluator per ADR-008's invariant ("a malformed
    /// schema must never make a previously-accepted message
    /// non-conformant").
    func associatedSegment(_ id: String, fromIndex: Int) -> Segment? {
        guard fromIndex >= 0, fromIndex < segments.count else { return nil }

        // Walk backward to the group head (most recent ORC at or before
        // fromIndex). If no ORC exists in the message, treat the whole
        // message as one degenerate group.
        var groupHead = fromIndex
        while groupHead > 0 && segments[groupHead].segmentID != "ORC" {
            groupHead -= 1
        }

        // Walk forward to the group end (one past the next ORC after
        // groupHead, or the end of the segment list).
        var groupEnd = groupHead + 1
        while groupEnd < segments.count && segments[groupEnd].segmentID != "ORC" {
            groupEnd += 1
        }

        for i in groupHead..<groupEnd {
            if i == fromIndex { continue }
            if segments[i].segmentID == id { return segments[i] }
        }
        return nil
    }

    /// True when a segment of `id` exists in the same ORC/OBR group as
    /// the segment at `inGroupOf` (excluding the segment at that index
    /// itself). Uses the same group-boundary walk as
    /// `associatedSegment(_:fromIndex:)`.
    ///
    /// ADR-010 segment-presence atom (`<segmentID> present` /
    /// `<segmentID> absent`). Distinguishes "peer segment does not
    /// exist" from "peer segment exists but field is empty" — the
    /// unblock for §4.5.1.8 XOR softening on ORC-8 / OBR-29 where
    /// today's `<fieldref> empty` fails safe to `false` on a missing
    /// peer and cannot express the softening.
    func segmentExists(_ id: String, inGroupOf index: Int) -> Bool {
        associatedSegment(id, fromIndex: index) != nil
    }

    /// Resolve the most recent segment of `id` that occurs strictly
    /// before `beforeIndex`. Returns `nil` when none exists.
    ///
    /// Used by the `previousSegment(<ID>)` DSL atom (ADR-008) — for
    /// example, ORC-8's parent-child rule reads `previousSegment(ORC)
    /// .ORC-1`.
    func previousSegment(_ id: String, beforeIndex: Int) -> Segment? {
        guard beforeIndex > 0, beforeIndex <= segments.count else { return nil }
        for i in stride(from: beforeIndex - 1, through: 0, by: -1) {
            if segments[i].segmentID == id { return segments[i] }
        }
        return nil
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
