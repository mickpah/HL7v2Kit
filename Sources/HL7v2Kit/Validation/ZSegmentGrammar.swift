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
///
/// The grammar applies to a message of any version. Its LEN cells are read as its own declared
/// version prints LEN (through v2.6 a number is a maximum; from v2.7.1 a range `m..n` or a list
/// `x,y,z`, and a plain number is not checked), falling back to the message's version if the
/// declared one is not modelled. Data types, components and tables are read in the message's
/// version, and a data type that version does not define is not checked. Conditions use the
/// condition language in <doc:Validation>; one that does not parse never fires. Under the AU
/// locale the profile's data-type rules reach a Z field of that type, as they reach any field.
public struct ZSegmentGrammar: Sendable, Equatable, Hashable {
    /// The segment's grammar. Its ``SegmentGrammar/segmentID`` names the Z-segment. Its
    /// LEN cells are read in its own version (see the type documentation).
    public let grammar: SegmentGrammar

    /// The sending applications (MSH-3.1) the grammar applies to. Empty means every sender.
    /// Matched exactly and case-sensitively against the decoded MSH-3.1; a message with no
    /// MSH-3.1 matches no scoped grammar; a sender named only by MSH-3.2 cannot be scoped.
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
        // P00 S4 fix: an empty MSH-3.1 is absent.
        guard let sendingApplication, !sendingApplication.isEmpty else { return false }
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
