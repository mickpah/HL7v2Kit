// Validator+GroupSpans.swift
// P8b-17 (ADR-019 "Interaction with the existing ORC-group scoping", decisions
// 5 and 6): the matched structure's group spans scope the group-dependent
// predicates; without spans, the ORC walk, or the former message-code gate.

extension Validator {
    /// The message codes the P4-7 (v2.5.1, v2.6, v2.8.2) and P10-5a (v2.7.1)
    /// schema gates `messageCode not in (...)` covered, and the fields whose
    /// conditions carried the gate. The gates are removed from the schemas;
    /// a message of one of these codes that gets no group spans keeps the
    /// gate's outcome, because the ORC walk is unsound for them: these
    /// structures print OBR before ORC inside one group, and the walk starts a
    /// group at the ORC, so it never sees that OBR and reads the next group's.
    /// - v2.5.1 OUL: CH07 7.3.7 to 7.3.9 (pp 7-21 to 7-26), OUL_R22 and OUL_R23
    ///   `ORDER { OBR [ORC] ... }` inside SPECIMEN or CONTAINER, OUL_R24
    ///   `ORDER { OBR [ORC] ... }`.
    /// - v2.6 OUL, OPU, OPL: CH07 7.3.7 to 7.3.10 (pp 7-18 to 7-23), the same
    ///   OUL groups and OPU_R25 `ORDER { OBR [ORC] ... }`; CH04 4.4.14
    ///   (pp 4-21 to 4-23), OPL_O37 PRIOR_RESULT `ORDER_PRIOR { OBR [ORC] ... }`.
    /// - v2.7.1 OUL, OPU, OPL: CH07 7.2.8 to 7.2.11 (pp 19 to 26) and CH04
    ///   4.4.16 (pp 28 to 31), the same groups.
    /// - v2.8.2 OUL, OPU, OPL: CH07 7.3.8 to 7.3.11 (pp 21 to 29), OUL_R22,
    ///   OUL_R23 and OPU_R25 `ORDER { OBR [COMMON_ORDER { ORC ... }] ... }`,
    ///   OUL_R24 `ORDER { OBR [ORC] ... }`; CH04 4.4.16 (pp 35 to 38), OPL_O37
    ///   `ORDER_PRIOR { OBR [ORC] ... }`.
    /// v2.7.1 and v2.8.2 print ORC-8 and OBR-29 without a group condition, so
    /// only the order-number fields were gated there.
    static let formerlyGated: [Version: (codes: Set<String>, fields: Set<String>)] = [
        .v2_5_1: (["OUL"], ["ORC-2", "ORC-3", "ORC-8", "OBR-2", "OBR-3", "OBR-29"]),
        .v2_6: (["OUL", "OPU", "OPL"], ["ORC-2", "ORC-3", "ORC-8", "OBR-2", "OBR-3", "OBR-29"]),
        .v2_7_1: (["OUL", "OPU", "OPL"], ["ORC-2", "ORC-3", "OBR-2", "OBR-3"]),
        .v2_8_2: (["OUL", "OPU", "OPL"], ["ORC-2", "ORC-3", "OBR-2", "OBR-3"]),
    ]

    /// The scoping for `message`, already declaring its grammar version: its
    /// group spans when it has them, else the fallback. `complete` replaces
    /// the generated completeness set; tests pass a synthetic one.
    func groupScoping(for message: Message, complete: Set<Version>? = nil) -> GroupScoping {
        if let spans = groupSpans(for: message, complete: complete) { return .spans(spans) }
        return Self.fallbackScoping(version: message.version.grammarVersion, messageCode: message.messageCode)
    }

    /// Without spans: the former gate for a formerly gated message code, the
    /// ORC walk for every other. The gate leg `messageCode not in (...)` held
    /// only for a populated code outside the list, so an empty MSH-9.1 keeps
    /// the gate's outcome too.
    static func fallbackScoping(version: Version, messageCode: String?) -> GroupScoping {
        guard let gate = formerlyGated[version] else { return .walk }
        let code = messageCode ?? ""
        return code.isEmpty || gate.codes.contains(code) ? .gated(gate.fields) : .walk
    }

    /// The group spans of a clean match: the version's structures are
    /// complete, the message's structure resolves and is not a fragment, the
    /// base match (before any profile structure governs it, P8b-4a) has no
    /// finding, and its accepting parses agree on the groups. Computed
    /// whatever `messageStructureSeverity` is (ADR-019 decision 5).
    func groupSpans(for message: Message, complete: Set<Version>? = nil) -> GroupSpanIndex? {
        guard MessageStructureTable.isComplete(message.version,
                                               completeVersions: complete ?? MessageStructureTable.completeVersions),
              let structure = resolveStructure(message, severity: .info).structure,
              fragmentReason(message, structure: structure) == nil
        else { return nil }
        return Self.spanIndex(structureMatch(structure, message: message), segmentCount: message.segments.count)
    }

    /// The span index of `match`, or nil when it has a finding or withholds
    /// its spans.
    static func spanIndex(_ match: StructureMatch, segmentCount: Int) -> GroupSpanIndex? {
        guard match.findings.isEmpty, !match.spansWithheld else { return nil }
        return GroupSpanIndex(spans: match.spans, segmentCount: segmentCount)
    }
}
