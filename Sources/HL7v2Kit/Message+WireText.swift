// Message+WireText.swift
// The text of a value as the serialiser writes it (P01 R13). Not a kernel file (ADR-006).

extension Message {
    /// The text ``serialize()`` writes for the value `path` names, under the message's own
    /// delimiters: escapes kept, parts joined by their separators, so it parses back to the
    /// same value. Use it to show or copy a value that has parts; the path subscript gives a
    /// leaf's decoded text, which may hold a delimiter character that was escaped on the wire.
    ///
    /// ```swift
    /// // OBX|1|ST|X||A\S\B^C~D
    /// message.wireText(at: try Path("OBX-5"))      // "A\S\B^C~D", the whole field
    /// message.wireText(at: try Path("OBX-5~1"))    // "A\S\B^C"
    /// message.wireText(at: try Path("OBX-5.1"))    // "A\S\B"
    /// message["OBX-5.1"]                           // "A^B", decoded
    /// ```
    ///
    /// A path with a field and nothing below it names the whole field, every repetition; this
    /// differs from the path subscript, which reads the first. A component without a repetition
    /// is read in the first repetition, as the subscript reads it. A value read from the wire
    /// comes back as it was written; a value set in code is encoded (see <doc:EscapeSequences>).
    /// MSH-1 and MSH-2 (BHS, FHS) are their literal characters.
    ///
    /// `nil` for a wildcard path, a path that names a segment alone, a subcomponent without a
    /// component, and a place the message does not have.
    public func wireText(at path: Path) -> String? {
        guard !path.repetitionWildcard, let segment = segment(at: path),
              let field = segment.field(path.field) else { return nil }
        if path.subcomponent != nil && path.component == nil { return nil }
        let encoding = encodingCharacters
        // The serialiser writes these two as literals, never through the escape encoder.
        if path.field <= 2, Parser.isSeparatorSegment(segment.segmentID) {
            guard (path.repetition ?? 1) == 1, (path.component ?? 1) == 1, (path.subcomponent ?? 1) == 1 else {
                return nil
            }
            return path.field == 1 ? String(encoding.fieldSeparator) : field.stringValue ?? encoding.msh2String
        }
        if path.repetition == nil && path.component == nil {
            return Serializer.serializeField(field, encoding: encoding)
        }
        let repetitionIndex = path.repetition ?? 1
        guard repetitionIndex >= 1, repetitionIndex <= field.repetitions.count else { return nil }
        let repetition = field.repetitions[repetitionIndex - 1]
        guard let componentIndex = path.component else {
            return Serializer.serializeRepetition(repetition, encoding: encoding)
        }
        guard componentIndex >= 1, componentIndex <= repetition.components.count else { return nil }
        let component = repetition.components[componentIndex - 1]
        guard let subcomponentIndex = path.subcomponent else {
            return Serializer.serializeComponent(component, encoding: encoding)
        }
        guard subcomponentIndex >= 1, subcomponentIndex <= component.subcomponents.count else { return nil }
        return EscapeSequences.wireForm(of: component.subcomponents[subcomponentIndex - 1], encoding: encoding)
    }
}
