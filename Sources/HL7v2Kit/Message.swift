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

    /// How group-dependent predicates find a segment's group (P8b-17). The
    /// Validator sets it on its own copy; it takes no part in equality.
    var groupScoping: GroupScoping = .walk

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

    public static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.version == rhs.version && lhs.encodingCharacters == rhs.encodingCharacters
            && lhs.segments == rhs.segments && lhs.characterEncoding == rhs.characterEncoding
            && lhs.locale == rhs.locale
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(version)
        hasher.combine(encodingCharacters)
        hasher.combine(segments)
        hasher.combine(characterEncoding)
        hasher.combine(locale)
    }

    /// A copy whose group-dependent predicates use `scoping`.
    func scoped(_ scoping: GroupScoping) -> Message {
        var copy = self
        copy.groupScoping = scoping
        return copy
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
    /// With group spans (P8b-17, ADR-019) the group is the anchor's own
    /// scope (`GroupSpanIndex.context(around:of:for:)`): the extended own
    /// level of an enclosing group, or inside the anchor's own group, never
    /// a repeating sibling group or a nested pairing group. Otherwise it is
    /// delimited by ORC segments: the group head is the
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
        associatedIndex(id, fromIndex: fromIndex).map { segments[$0] }
    }

    /// The message index of `associatedSegment(_:fromIndex:)`.
    func associatedIndex(_ id: String, fromIndex: Int) -> Int? {
        guard fromIndex >= 0, fromIndex < segments.count else { return nil }
        let range: [Int]
        if case .spans(let index) = groupScoping {
            range = index.context(around: fromIndex, of: segments[fromIndex].segmentID, for: id)
        } else {
            range = Array(orcGroupRange(around: fromIndex))
        }
        return range.first { $0 != fromIndex && segments[$0].segmentID == id }
    }

    /// The ORC-delimited group range around `index`: from the most
    /// recent ORC at or before `index` (or the start of the message when
    /// no ORC precedes it — the degenerate whole-prefix group) up to the
    /// next ORC (or the end of the segment list). Shared by
    /// `associatedSegment(_:fromIndex:)` and the Validator's group-scope
    /// cardinality resolution so the two group definitions cannot drift.
    /// Callers guarantee `index` is in bounds.
    func orcGroupRange(around index: Int) -> Range<Int> {
        var groupHead = index
        while groupHead > 0 && segments[groupHead].segmentID != "ORC" {
            groupHead -= 1
        }
        var groupEnd = groupHead + 1
        while groupEnd < segments.count && segments[groupEnd].segmentID != "ORC" {
            groupEnd += 1
        }
        return groupHead..<groupEnd
    }

    /// True when a segment of `id` exists in the same ORC/OBR group as
    /// the segment at `inGroupOf` (excluding the segment at that index
    /// itself). Uses the same group as `associatedSegment(_:fromIndex:)`.
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
