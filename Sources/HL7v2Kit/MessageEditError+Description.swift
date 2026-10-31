// MessageEditError+Description.swift
// The text of a refused edit (P00 S3-1). It interpolates Path's string form, a skin
// conformance, so it lives outside the kernel file (ADR-006).

extension MessageEditError: CustomStringConvertible {
    /// A sentence naming why the edit was refused.
    public var description: String {
        switch self {
        case .segmentNotFound(let id, let occurrence):
            return "The message has no occurrence \(occurrence) of segment \(id)"
        case .delimiterField(let id, let field):
            return "\(id)-\(field) holds the delimiters and is not writable; they come from encodingCharacters"
        case .wildcardPath(let path):
            return "The path \(path) names more than one location; an edit names one"
        case .notARepetition(let path):
            return "The path \(path) does not end at a repetition"
        case .invalidPath(let path):
            return "The path \(path) has an index below 1 or above 9,999, or a subcomponent without a component"
        case .unsupportedCharacterEncoding(let declared):
            return "MSH-18 '\(declared)' names a character set HL7v2Kit does not support"
        }
    }
}
