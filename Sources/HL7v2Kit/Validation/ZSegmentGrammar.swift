// ZSegmentGrammar.swift
// A caller-supplied grammar for a Z-segment (P00 S4-1; ADR-003, amended). HL7v2Kit ships
// none: a Z-segment's layout is the sender's to state, and only the caller knows it.

/// A grammar for one Z-segment, supplied through ``ValidationOptions/zSegmentGrammars``.
///
/// The validator checks a Z-segment that has a grammar as it checks any segment (usage,
/// repetition, length, data type, table), and ``ValidationOptions/zSegmentPolicy`` no longer
/// applies to it. It is used only for an ID beginning with `Z` that the version grammar does
/// not define. Parsing is unchanged: the segment stays an ``UnknownSegment``, with no typed
/// accessors, and path access reads it as before.
public struct ZSegmentGrammar: Sendable, Equatable, Hashable {
    /// The segment's grammar. Its ``SegmentGrammar/segmentID`` names the Z-segment. Its
    /// version is not consulted: the grammar applies to a message of any version.
    public let grammar: SegmentGrammar

    /// The sending applications (MSH-3.1) the grammar applies to. Empty means every sender.
    public let sendingApplications: Set<String>

    /// Creates a Z-segment grammar, optionally only for messages whose MSH-3.1 is one of
    /// `sendingApplications`.
    public init(_ grammar: SegmentGrammar, sendingApplications: Set<String> = []) {
        self.grammar = grammar
        self.sendingApplications = sendingApplications
    }

    /// Whether the grammar applies to segment `id` in a message from `sendingApplication`.
    func applies(to id: String, sendingApplication: String?) -> Bool {
        guard grammar.segmentID == id else { return false }
        guard !sendingApplications.isEmpty else { return true }
        guard let sendingApplication else { return false }
        return sendingApplications.contains(sendingApplication)
    }
}

extension Validator {
    /// The caller's grammar for Z-segment `id`: the first of
    /// ``ValidationOptions/zSegmentGrammars`` whose ID matches and whose scope admits the
    /// message's MSH-3.1, or `nil`.
    func zSegmentGrammar(for id: String, in message: Message) -> SegmentGrammar? {
        guard id.hasPrefix("Z"), !options.zSegmentGrammars.isEmpty else { return nil }
        let sender = message["MSH-3.1"]
        return options.zSegmentGrammars.first { $0.applies(to: id, sendingApplication: sender) }?.grammar
    }
}
