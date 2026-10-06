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
        groupSpanOutcome(for: message, complete: complete).spans
    }

    /// The group spans of `message` as ``groupSpans(for:complete:)`` gives
    /// them, or, when there are none, the first reason in the same order of
    /// checks, phrased for ``IssueCode/conditionNotEvaluated(fields:)`` (S1-4).
    func groupSpanOutcome(for message: Message, complete: Set<Version>? = nil)
        -> (spans: GroupSpanIndex?, cause: String?) {
        guard MessageStructureTable.isComplete(message.version,
                                               completeVersions: complete ?? MessageStructureTable.completeVersions)
        else { return (nil, "the v\(message.version.rawValue) structures are not complete") }
        let resolution = resolveStructure(message, severity: .info)
        guard let declared = resolution.structure else {
            switch resolution.issues.first?.code {
            case .messageStructureMismatch(let declared, let trigger)?:
                return (nil, "MSH-9.3 \(declared) is not printed for \(trigger)")
            case .messageStructureNotModelled(let name)? where name.isEmpty:
                return (nil, "MSH-9 is empty, so no structure is resolved")
            case .messageStructureNotModelled(let name)?:
                return (nil, "no abstract message syntax is applied to \(name)")
            default:
                return (nil, "no message structure was resolved")
            }
        }
        let structure: MessageStructure
        switch declared.resolvingKeyedChoices(in: message) {
        case .resolved(let resolved):
            structure = resolved
        case .unmapped(let key, let value):
            return (nil, Self.unmappedReason(key, value, structure: declared.id))
        }
        if let reason = fragmentReason(message, structure: structure) {
            return (nil, "the message is a fragment (\(reason)), so \(structure.id) is not matched")
        }
        let match = structureMatch(structure, message: message)
        let ids = message.segments.map(\.segmentID)
        if let finding = match.findings.first {
            let more = match.findings.count > 1 ? " (and \(match.findings.count - 1) more structure findings)" : ""
            return (nil, Self.describe(finding, structure: structure.id, segmentCount: ids.count) + more)
        }
        if match.spansWithheld {
            return (nil, "the accepting parses of \(structure.id) place a segment in different group occurrences")
        }
        return (Self.spanIndex(match, structure: structure, ids: ids), nil)
    }

    /// One structure finding in words, for the fallback issue.
    private static func describe(_ finding: StructureFinding, structure: String, segmentCount: Int) -> String {
        switch finding.kind {
        case .missing:
            let place = finding.index >= segmentCount ? "at the end" : "before segment \(finding.index + 1)"
            let group = finding.group.map { " group \($0)" } ?? ""
            return "\(structure)\(group) is missing \(finding.segmentID) \(place)"
        case .unexpected:
            return "\(finding.segmentID) at segment \(finding.index + 1) has no place in \(structure)"
        case .exceededMaximum:
            return "\(finding.segmentID) at segment \(finding.index + 1) exceeds its maximum in \(structure)"
        }
    }

    /// Owner decision 9 (S1-4): when the fallback gates the order-number
    /// predicates off (``GroupScoping/gated(_:)``) and the message carries an
    /// ORC or OBR, one `.info` issue at the first gated field of the first
    /// such segment, naming the gated fields and the structure finding that
    /// withheld the spans. `message` already carries its scoping.
    func checkGatedConditions(message: Message, issues: inout [ValidationIssue]) {
        guard case .gated(let gated) = message.groupScoping else { return }
        func split(_ name: String) -> (segment: String, field: Int) {
            let parts = name.split(separator: "-")
            return (String(parts[0]), Int(parts[1]) ?? 0)
        }
        let carried = Set(message.segments.map(\.segmentID))
        let fields = gated.map(split).filter { carried.contains($0.segment) }
            .sorted { ($0.segment, $0.field) < ($1.segment, $1.field) }
        guard let first = message.segments.first(where: { segment in fields.contains { $0.segment == segment.segmentID } }),
              let field = fields.first(where: { $0.segment == first.segmentID })
        else { return }
        let names = fields.map { "\($0.segment)-\($0.field)" }
        let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1] : names[0]
        let cause = groupSpanOutcome(for: message).cause ?? "no group spans are known"
        let code = message.messageCode.map { $0.isEmpty ? "an empty MSH-9.1" : $0 } ?? "an empty MSH-9.1"
        issues.append(ValidationIssue(
            severity: .info,
            code: .conditionNotEvaluated(fields: names),
            location: IssueLocation(segmentID: first.segmentID, segmentIndex: 1, fieldIndex: field.field),
            message: "The conditions of \(list) were not evaluated: they pair the ORC and OBR of one order group, "
                + "and no group spans are known because \(cause); without spans the v\(message.version.rawValue) "
                + "gate applies to \(code), so these order-number conditions are not evaluated (ADR-019, P8b-17)."
        ))
    }

    /// The span index of `match` against `structure`, or nil when it has a
    /// finding or withholds its spans.
    static func spanIndex(_ match: StructureMatch, structure: MessageStructure, ids: [String]) -> GroupSpanIndex? {
        guard match.findings.isEmpty, !match.spansWithheld else { return nil }
        return GroupSpanIndex(spans: match.spans, elements: structure.elements, ids: ids)
    }
}
