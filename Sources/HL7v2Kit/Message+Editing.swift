// PORTABLE KERNEL — keep this file Foundation-free and byte/character-level.
// A future Rust/Go port translates this file directly. No NSRegularExpression,
// NSString, DateFormatter, CharacterSet, locale-aware ops, protocols, or
// generics in the parse path. `Data` only at the edges (to/from [UInt8]).
// See docs/design/architecture-decisions.md#adr-006-portable-core-boundary

// Message+Editing.swift
// Path-addressed writes (P00 S3-1). An edit replaces one field of one segment in the
// tree; the serialiser rebuilds every segment from the tree, so every node the edit does
// not touch serialises as it was read.

/// Why a path-addressed edit was refused. A refused edit leaves the message unchanged.
///
/// - Note: **Open** enum per ADR-014 — may gain cases in a minor release;
///   switch with `@unknown default`.
public enum MessageEditError: Error, Equatable, Sendable {
    /// The message has no occurrence `occurrence` of segment `segmentID`. Edits never add
    /// a segment.
    case segmentNotFound(segmentID: String, occurrence: Int)
    /// Field 1 or 2 of MSH, BHS or FHS: they hold the delimiters, which
    /// ``Message/encodingCharacters`` decides.
    case delimiterField(segmentID: String, field: Int)
    /// The path names more than one location (`[*]`); an edit names one.
    case wildcardPath(Path)
    /// ``Message/insertRepetition(_:at:)`` needs a path ending at a repetition
    /// (`PID-3~2` or `PID-3[2]`).
    case notARepetition(Path)
    /// An index below 1, a subcomponent without a component (only the memberwise ``Path``
    /// initialiser builds one), or an edit that would create a node above index 9,999.
    case invalidPath(Path)
    /// An edit to MSH-18 names a character set HL7v2Kit does not support, so the message could
    /// not be serialised in it.
    case unsupportedCharacterEncoding(declared: String)
    /// The edit would put a character into the message that its character set cannot encode:
    /// the new value, or, for an MSH-18 edit, a value already in the message. Serialising it
    /// would re-encode the whole message. The value is not named, so the error carries no
    /// message content.
    case characterNotEncodable(CharacterEncoding)
}

extension Message {
    static let maxEditIndex = 9_999

    /// Whether `value` can be written in `encoding`.
    static func encodable(_ value: String, in encoding: CharacterEncoding) -> Bool {
        let limit: UInt32
        switch encoding {
        case .utf8:
            return true
        case .ascii:
            limit = 0x7F
        case .iso8859_1:
            limit = 0xFF
        }
        for scalar in value.unicodeScalars where scalar.value > limit {
            return false
        }
        return true
    }

    /// Whether the edit would create a node at an index above `maxEditIndex`. Existing nodes
    /// stay writable at any index; only padding is capped, since it would otherwise run
    /// without limit (P00 S3).
    static func padsPastCap(_ path: Path, in segment: Segment) -> Bool {
        let cap = maxEditIndex
        let fields = segment.fields
        if path.field > cap && path.field >= fields.count { return true }
        let repetitions = path.field < fields.count ? fields[path.field].repetitions : []
        let r = path.repetition ?? 1
        if r > cap && r > repetitions.count { return true }
        let components = r <= repetitions.count ? repetitions[r - 1].components : []
        let c = path.component ?? 1
        if c > cap && c > components.count { return true }
        let subcomponents = c <= components.count ? components[c - 1].subcomponents : []
        let s = path.subcomponent ?? 1
        if s > cap && s > subcomponents.count { return true }
        return false
    }

    /// Writes `value` at `path`, which may use either path syntax.
    ///
    /// - A path that ends at the field and names no repetition (`PID-3`) replaces the
    ///   whole field, every repetition; `PID-3[1]` (or `PID-3~1`) writes repetition 1
    ///   only. Otherwise an omitted repetition is the first (`PID-5.1` writes
    ///   `PID-5~1.1`), as reads treat it.
    /// - Missing fields, repetitions, components and subcomponents are created empty on
    ///   the way to the target. Nothing is trimmed.
    /// - `value` is text: delimiters, the escape character and control characters in it are
    ///   escaped when the message is serialised (`A^B` is written `A\S\B`). One exception
    ///   comes from the decoded-value model: a run between two escape characters, other
    ///   than the standard escapes (`\F\`, `\X41\` and the rest), with no delimiter or
    ///   control character inside (`C:\Users\me`) is kept as that escape sequence. Write a structure one path at a time.
    /// - The segment occurrence must exist. A wildcard path is refused, and so are fields 1
    ///   and 2 of MSH, BHS and FHS, which hold the delimiters. An edit may create nodes up to
    ///   index 9,999; an existing node at any index stays writable.
    /// - An edit to MSH-12 or MSH-18 of the message header re-reads `version` or
    ///   `characterEncoding`, as the parser does with default options (a version override, or a stricter parser's
    ///   refusal, is not applied); an unknown character set is refused.
    ///
    /// - Throws: ``MessageEditError``; the message is then unchanged.
    public mutating func set(_ value: String, at path: Path) throws {
        let index = try editTarget(path)
        guard Self.encodable(value, in: characterEncoding) else {
            throw MessageEditError.characterNotEncodable(characterEncoding)
        }
        var fields = segments[index].fields
        fields = padded(fields, to: path.field, segmentID: segments[index].segmentID)
        fields[path.field] = Self.setting(value, in: fields[path.field], at: path)
        try commit(fields, at: index, field: path.field)
    }

    /// Empties the node at `path`: ``set(_:at:)`` with an empty value, so a field-level
    /// path with no repetition empties every repetition.
    ///
    /// - Throws: ``MessageEditError``; the message is then unchanged.
    public mutating func clear(at path: Path) throws {
        try set("", at: path)
    }

    /// Inserts a repetition holding `value` before the repetition `path` names
    /// (`PID-3~2` or `PID-3[2]`). Past the last repetition it pads with empty ones. A field
    /// that is empty on the wire counts as having no repetitions.
    ///
    /// - Throws: ``MessageEditError``; the message is then unchanged.
    public mutating func insertRepetition(_ value: String, at path: Path) throws {
        let index = try editTarget(path)
        guard let position = path.repetition, path.component == nil else {
            throw MessageEditError.notARepetition(path)
        }
        guard Self.encodable(value, in: characterEncoding) else {
            throw MessageEditError.characterNotEncodable(characterEncoding)
        }
        var fields = segments[index].fields
        fields = padded(fields, to: path.field, segmentID: segments[index].segmentID)
        var repetitions = fields[path.field] == .scalar("") ? [] : fields[path.field].repetitions
        while repetitions.count < position - 1 { repetitions.append(.scalar("")) }
        repetitions.insert(.scalar(value), at: position - 1)
        fields[path.field] = Field(repetitions: repetitions)
        try commit(fields, at: index, field: path.field)
    }

    /// The index in `segments` of the segment `path` edits, after the checks every edit
    /// shares.
    private func editTarget(_ path: Path) throws -> Int {
        if path.segmentWildcard || path.repetitionWildcard {
            throw MessageEditError.wildcardPath(path)
        }
        let indices = [path.field, path.segmentIndex ?? 1, path.repetition ?? 1,
                       path.component ?? 1, path.subcomponent ?? 1]
        for index in indices where index < 1 {
            throw MessageEditError.invalidPath(path)
        }
        if path.subcomponent != nil && path.component == nil {
            throw MessageEditError.invalidPath(path)
        }
        if path.field <= 2, path.segmentID == "MSH" || path.segmentID == "BHS" || path.segmentID == "FHS" {
            throw MessageEditError.delimiterField(segmentID: path.segmentID, field: path.field)
        }
        let occurrence = path.segmentIndex ?? 1
        var seen = 0
        for (index, segment) in segments.enumerated() where segment.segmentID == path.segmentID {
            seen += 1
            if seen == occurrence {
                if Self.padsPastCap(path, in: segment) { throw MessageEditError.invalidPath(path) }
                return index
            }
        }
        throw MessageEditError.segmentNotFound(segmentID: path.segmentID, occurrence: occurrence)
    }

    /// Replaces the segment's fields and re-hydrates it, so a typed segment stays typed. An
    /// edit to MSH-12 or MSH-18 of the message header re-reads the version or the character
    /// set, as the parser does; an unknown character set throws before anything changes.
    private mutating func commit(_ fields: [Field], at index: Int, field: Int) throws {
        let id = segments[index].segmentID
        let header = index == 0 && id == "MSH"
        var encoding = characterEncoding
        if header && field == 18 {
            // The parser reads MSH-18 as the field's raw text, so the editor does too: a
            // repeated or structured MSH-18 the parser would reject is refused here.
            let declared = Serializer.serializeField(fields[18], encoding: encodingCharacters)
            if declared.isEmpty {
                encoding = .utf8
            } else if let known = CharacterEncoding.from(mshField18: declared) {
                encoding = known
            } else {
                throw MessageEditError.unsupportedCharacterEncoding(declared: declared)
            }
            for (i, segment) in segments.enumerated() {
                for field in (i == index ? fields : segment.fields) {
                    for repetition in field.repetitions {
                        for component in repetition.components {
                            // The check reads the text the serialiser will write (#13).
                            for subcomponent in component.subcomponents
                            where !Self.encodable(EscapeSequences.wireForm(of: subcomponent, encoding: encodingCharacters), in: encoding) {
                                throw MessageEditError.characterNotEncodable(encoding)
                            }
                        }
                    }
                }
            }
        }
        segments[index] = SegmentRegistry.hydrate(UnknownSegment(segmentID: id, fields: fields))
        characterEncoding = encoding
        if header && field == 12 {
            switch Version.reading(msh12: fields[12], subcomponentSeparator: encodingCharacters.subcomponentSeparator) {
            case .recognised(let declared):
                version = declared
            case .unresolved, .empty:
                version = .v2_5_1
            }
        }
    }

    /// `fields` padded to hold index `field`. Fields 1 and 2 of MSH, BHS and FHS hold the
    /// delimiters, so padding writes them from `encodingCharacters`, not empty.
    private func padded(_ fields: [Field], to field: Int, segmentID: String) -> [Field] {
        var fields = fields
        let separatorSegment = segmentID == "MSH" || segmentID == "BHS" || segmentID == "FHS"
        while fields.count <= field {
            if separatorSegment && fields.count == 1 {
                fields.append(.scalar(String(encodingCharacters.fieldSeparator)))
            } else if separatorSegment && fields.count == 2 {
                fields.append(.scalar(encodingCharacters.msh2String))
            } else {
                fields.append(.scalar(""))
            }
        }
        return fields
    }

    /// `field` with `value` written at `path`'s repetition, component and subcomponent,
    /// creating empty nodes on the way.
    static func setting(_ value: String, in field: Field, at path: Path) -> Field {
        // A path ending at the field with no repetition replaces the whole field.
        guard path.repetition != nil || path.component != nil else { return .scalar(value) }
        var repetitions = field.repetitions
        let r = (path.repetition ?? 1) - 1
        while repetitions.count <= r { repetitions.append(.scalar("")) }
        guard let componentIndex = path.component else {
            repetitions[r] = .scalar(value)
            return Field(repetitions: repetitions)
        }
        var components = repetitions[r].components
        let c = componentIndex - 1
        while components.count <= c { components.append(.scalar("")) }
        if let subcomponentIndex = path.subcomponent {
            var subcomponents = components[c].subcomponents
            let s = subcomponentIndex - 1
            while subcomponents.count <= s { subcomponents.append(Subcomponent("")) }
            subcomponents[s] = Subcomponent(value)
            components[c] = Component(subcomponents: subcomponents)
        } else {
            components[c] = .scalar(value)
        }
        repetitions[r] = Repetition(components: components)
        return Field(repetitions: repetitions)
    }
}
