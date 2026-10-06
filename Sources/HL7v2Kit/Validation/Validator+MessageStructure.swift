// Validator+MessageStructure.swift
// ADR-019: check a message's segment sequence against its abstract message
// structure. Runs only when ValidationOptions.messageStructureSeverity is set.

extension Validator {
    /// Resolve the message's structure, then report every missing and
    /// unexpected segment the matcher finds.
    func checkMessageStructure(message: Message, severity: IssueSeverity, issues: inout [ValidationIssue]) {
        let resolution = resolveStructure(message, severity: severity)
        issues += resolution.issues
        guard let declared = resolution.structure else { return }
        let structure: MessageStructure
        switch declared.resolvingKeyedChoices(in: message) {
        case .resolved(let resolved):
            structure = resolved
        case .unmapped(let key, let value):
            issues.append(notModelled(declared.id, message: message, reason: Self.unmappedReason(key, value, structure: declared.id)))
            return
        }
        let findings = matchStructure(structure, message: message, severity: severity)
        let governed = matchProfileStructure(over: structure, baseFindings: findings, message: message, severity: severity)
        issues += governed.base
        issues += governed.profile
    }

    /// The structure to match, or the one issue saying why none is matched.
    ///
    /// Version rule (ADR-019 "Structure resolution and version"): structures
    /// apply only when MSH-12 reads as a recognised version whose grammar
    /// version is the message's; an empty, unresolved or different reading
    /// (for example `ParserOptions.versionOverride`) is not matched.
    /// Lookup (ADR-019 "Structure resolution and version", rules 1 to 4):
    /// MSH-9.3 when valued; else MSH-9.1^9.2 (a bare `ACK` as `ACK^`) through
    /// the caption-line triggers, `ACK^*` matching any event. A trigger no
    /// loaded structure prints, or one printed under two (B6, ambiguous), is
    /// not modelled. An MSH-9.3 whose structure does not print MSH-9.1^9.2 is
    /// reported as a mismatch alone, with no body match. An MSH-9.3 ID that is
    /// not loaded is a mismatch on a complete version (rule 1, completeness
    /// read through the grammar version) and not modelled on an incomplete
    /// one. A structure the version registers as not modelled (an
    /// unexpandable placeholder, a Table 0354 row with no printed syntax) is
    /// not modelled on any version, with its register reason, and its
    /// triggers count towards an ambiguous trigger (P8b-9).
    /// On a complete version a locally defined message (a Z message type,
    /// trigger event or structure ID, whose trigger the version prints under no
    /// structure) is not modelled rather than a mismatch, and on any version a
    /// Z trigger the version prints under no structure may declare a printed
    /// structure without a mismatch (P8b-10).
    /// Table 0354 is not consulted at runtime: the extractor merges its rows
    /// into each structure's triggers (and every v2.3.1 structure ID comes
    /// from it), and its IDs with no printed syntax are registered as not
    /// modelled, so a structure ID the version's print gives is never a
    /// mismatch (P8b-final, ruling F-I1); a printed pair whose ID is modelled
    /// for other triggers (completeness.json `printedPairs`) is not modelled.
    /// Rule 3 (P8b-15): v2.3 defines no MSH-9.3 (MSH-9 is CM <message type>
    /// ^ <trigger event>, v2.3 Chapter 2 section 2.24.1.9) and its structure
    /// IDs are synthesised, so a v2.3 message resolves from MSH-9.1^9.2 only
    /// and a populated third component is ignored for resolution.
    ///
    /// `structures` replaces the version's loaded table, `complete` the
    /// generated completeness set and `gaps` the registered not-modelled
    /// structures; tests pass synthetic ones.
    func resolveStructure(_ message: Message, severity: IssueSeverity,
                          structures: [String: MessageStructure]? = nil,
                          complete: Set<Version>? = nil,
                          gaps: [String: NotModelledStructure]? = nil) -> (structure: MessageStructure?, issues: [ValidationIssue]) {
        let code = message.messageCode ?? ""
        let event = message.triggerEvent ?? ""
        let trigger = event.isEmpty ? code : "\(code)^\(event)"
        let printedID = message.messageStructure ?? ""
        let name = printedID.isEmpty ? trigger : printedID

        let msh12 = message.segments.first.flatMap { $0.segmentID == "MSH" ? $0.field(12) : nil }
        let reading = Version.reading(msh12: msh12, subcomponentSeparator: message.encodingCharacters.subcomponentSeparator)
        guard case .recognised(let wire) = reading, wire.grammarVersion == message.version.grammarVersion else {
            let why = reading == .empty
                ? "MSH-12 is empty"
                : "MSH-12 does not resolve to v\(message.version.rawValue), the version validated"
            return (nil, [notModelled(name, message: message, reason: why)])
        }
        // Lookup rule 3: v2.3 defines no MSH-9.3, so once MSH-12 reads as v2.3 a third component
        // is ignored and the message resolves from MSH-9.1^9.2 only.
        let declared = wire.grammarVersion == .v2_3 ? "" : printedID

        let table = structures ?? MessageStructureTable.structures(for: message.version.grammarVersion)
        let registered = gaps ?? MessageStructureTable.notModelled(for: message.version.grammarVersion)
        // The generated tables are read through a trigger index built once (P8b-18);
        // synthetic tables from tests are scanned.
        let indexed = structures == nil && gaps == nil
            ? MessageStructureTable.owners(messageCode: code, triggerEvent: event, version: message.version) : nil
        let byTrigger = indexed?.modelled ?? table.values
            .filter { $0.accepts(messageCode: code, triggerEvent: event) }
            .map(\.id).sorted()
        let gapsByTrigger = indexed?.registered
            ?? registered.filter { $0.value.accepts(messageCode: code, triggerEvent: event) }.keys.sorted()
        let ver = "v\(message.version.rawValue)"
        // A locally defined trigger (CH02 reserves message types and trigger events
        // beginning with Z for local definition) that the version prints under no
        // structure may declare any printed structure: no mismatch (P8b-10).
        let localTrigger = (code.hasPrefix("Z") || event.hasPrefix("Z")) && byTrigger.isEmpty && gapsByTrigger.isEmpty

        guard !declared.isEmpty else {
            let owners = (byTrigger + gapsByTrigger).sorted()
            if owners.count > 1 {
                let both = owners.dropLast().joined(separator: ", ") + " and " + owners[owners.count - 1]
                return (nil, [notModelled(trigger, message: message,
                    reason: "the trigger is ambiguous, printed under \(both) in \(ver), and MSH-9.3 does not say which")])
            }
            if let gap = gapsByTrigger.first, let entry = registered[gap] {
                return (nil, [notModelled(trigger, message: message,
                    reason: "\(ver) prints \(trigger) under \(gap), which is not modelled: \(entry.reason)")])
            }
            guard let only = byTrigger.first, let structure = table[only] else {
                return (nil, [notModelled(trigger, message: message)])
            }
            return (structure, [])
        }
        if table[declared] == nil, let entry = registered[declared] {
            // Its captions print other triggers: the print gives this event another structure.
            if !localTrigger, !entry.triggers.isEmpty, !entry.accepts(messageCode: code, triggerEvent: event) {
                return (nil, [ValidationIssue(
                    severity: severity,
                    code: .messageStructureMismatch(declared: declared, trigger: trigger),
                    location: IssueLocation(segmentID: "MSH", segmentIndex: 1, fieldIndex: 9, componentIndex: 3),
                    message: "MSH-9.3 \(declared) is not printed for \(trigger) in \(ver) (it is printed for "
                        + "\(entry.triggers.joined(separator: ", ")) and not modelled); segment order and groups were not checked (ADR-019)."
                )])
            }
            return (nil, [notModelled(declared, message: message,
                reason: "\(declared) is not modelled in \(ver): \(entry.reason)")])
        }
        guard let structure = table[declared] else {
            // An ID that matches a loaded structure once trimmed and
            // upper-cased is named as such; IDs still match exactly.
            let near = String(declared.drop(while: \.isWhitespace).reversed()
                .drop(while: \.isWhitespace).reversed()).uppercased()
            let isNear = near != declared && table[near] != nil
            // Rule 1, complete version: every structure the version prints
            // is loaded, so an unknown ID is a mismatch, not a gap.
            if MessageStructureTable.isComplete(message.version, completeVersions: complete ?? MessageStructureTable.completeVersions) {
                // A locally defined message is never a mismatch (P8b-10): CH02 reserves
                // message types and trigger events beginning with Z for local definition,
                // and a Z structure ID (CODE_Znn) is site-defined (v2.6 CH08 8.4.3
                // MFN^M14^MFN_Znn), when the version prints the trigger under no structure.
                let zStructure = declared.split(separator: "_").dropFirst().first?.hasPrefix("Z") == true
                if !isNear, localTrigger || (zStructure && byTrigger.isEmpty && gapsByTrigger.isEmpty) {
                    return (nil, [notModelled(declared, message: message,
                        reason: "MSH-9 names a locally defined message (Z message type, trigger event or structure); "
                            + "HL7 defines no abstract message syntax for it")])
                }
                let hint = isNear ? "; it differs from \(near) only by case or whitespace, and structure IDs are matched exactly" : ""
                return (nil, [ValidationIssue(
                    severity: severity,
                    code: .messageStructureMismatch(declared: declared, trigger: trigger),
                    location: IssueLocation(segmentID: "MSH", segmentIndex: 1, fieldIndex: 9, componentIndex: 3),
                    message: "MSH-9.3 \(declared) is not an abstract message structure of \(ver), whose structures are all modelled\(hint); segment order and groups were not checked (ADR-019 lookup rule 1)."
                )])
            }
            if isNear {
                return (nil, [notModelled(declared, message: message,
                    reason: "MSH-9.3 \"\(declared)\" differs from the modelled structure ID \(near) only by case or whitespace; structure IDs are matched exactly")])
            }
            let printed = byTrigger.isEmpty ? nil
                : "no \(ver) abstract message syntax is modelled for \(declared); \(ver) prints \(trigger) under "
                + byTrigger.joined(separator: ", ")
                + ", but an unmodelled MSH-9.3 is reported as a mismatch only once every \(ver) structure is modelled"
            return (nil, [notModelled(declared, message: message, reason: printed)])
        }
        guard localTrigger || structure.accepts(messageCode: code, triggerEvent: event) else {
            // A pair the version prints although the structure is modelled for other
            // triggers (a query profile's response row) is not modelled, never a
            // mismatch (P8b-final, ruling F-I1).
            if structures == nil, let why = MessageStructureTable.printedPairReason(trigger: trigger, structure: declared, version: message.version) {
                return (nil, [notModelled(declared, message: message,
                    reason: "\(ver) prints \(trigger) with \(declared), which is modelled for other triggers: \(why)")])
            }
            return (nil, [ValidationIssue(
                severity: severity,
                code: .messageStructureMismatch(declared: declared, trigger: trigger),
                location: IssueLocation(segmentID: "MSH", segmentIndex: 1, fieldIndex: 9, componentIndex: 3),
                message: "MSH-9.3 \(declared) is not printed for \(trigger) in v\(message.version.rawValue) (\(structure.citation)); segment order and groups were not checked (ADR-019)."
            )])
        }
        return (structure, [])
    }

    /// Match the message body against `structure`: fragments are reported as
    /// not modelled; otherwise every finding is located on a real segment of
    /// the message. A structure that fails the determinism lint (its
    /// `requiresExactMatch` flag, set at codegen time) is matched by
    /// `ExactStructureMatcher`: at most one finding (ADR-019 ceiling 1, P8b-12),
    /// and group spans only for an accepted sequence whose accepting parses all
    /// agree on the groups (P8b-17); every other structure by the one-pass
    /// `StructureMatcher`. No message is linted here. The segments at the
    /// message indices in `skipping` are passed over without a finding (the
    /// AU profile's re-match of an exact-matched base, P8b-4a).
    func matchStructure(_ structure: MessageStructure, message: Message, severity: IssueSeverity,
                        skipping: Set<Int> = []) -> [ValidationIssue] {
        let ids = message.segments.map(\.segmentID)
        if let why = fragmentReason(message, structure: structure) {
            return [notModelled(structure.id, message: message, reason: "the message is a fragment (\(why))")]
        }
        let match = structureMatch(structure, message: message, skipping: skipping)
        guard !match.findings.isEmpty, !ids.isEmpty else { return [] }
        let location = Self.segmentLocations(ids)

        return match.findings.map { finding in
            let atEnd = finding.index >= ids.count
            let anchor = location(min(finding.index, ids.count - 1))
            switch finding.kind {
            case .missing:
                let place = atEnd ? "at the end of the message" : "before \(anchor.pathDescription)"
                let scope = finding.group.map { " in group \($0)" } ?? ""
                return ValidationIssue(
                    severity: severity,
                    code: .messageStructureSegmentMissing(structure: structure.id, segmentID: finding.segmentID, group: finding.group),
                    location: anchor,
                    message: "\(structure.id) requires \(finding.segmentID)\(scope) \(place) (\(structure.citation))."
                )
            case .unexpected, .exceededMaximum:
                let why = finding.kind == .exceededMaximum ? " (beyond its maximum repetitions)" : ""
                return ValidationIssue(
                    severity: severity,
                    code: .messageStructureSegmentUnexpected(structure: structure.id, segmentID: finding.segmentID),
                    location: anchor,
                    message: "\(finding.segmentID) has no place in \(structure.id) at this point\(why)\(Self.expectedText(match)) (\(structure.citation))."
                )
            }
        }
    }

    /// The most segment IDs named in an exact-matched finding's text.
    static let expectedTextLimit = 8

    /// For an exact-matched structure's unexpected segment, what the structure
    /// accepts at that point (P8b-final, F-I3): "; expected here: " and the
    /// first `expectedTextLimit` segment IDs in structure order, then "and N
    /// more" for the rest, with "or the end of the message" when a parse is
    /// complete there. The list is bounded by the limit and, before it, by the
    /// structure's distinct segment IDs. Empty for the one-pass matcher, which
    /// leaves the list empty.
    static func expectedText(_ match: StructureMatch) -> String {
        var items = Array(match.expectedHere.prefix(expectedTextLimit))
        let more = match.expectedHere.count - items.count
        guard !items.isEmpty || match.endExpectedHere else { return "" }
        if more > 0 {
            return "; expected here: " + items.joined(separator: ", ") + " and \(more) more"
                + (match.endExpectedHere ? ", or the end of the message" : "")
        }
        if match.endExpectedHere { items.append("the end of the message") }
        let last = items.removeLast()
        return "; expected here: " + (items.isEmpty ? last : items.joined(separator: ", ") + " or " + last)
    }

    /// The matcher's result for the message body, the segments at the indices
    /// in `skipping` passed over. Segments the version grammar lacks already
    /// raise segmentNotInVersionGrammar and are transparent; Z and ADD are
    /// skipped by the matcher. A segment the version lists as withdrawn is
    /// matched by ID (ADR-019 S2-1). Shared with the group spans (P8b-17).
    func structureMatch(_ structure: MessageStructure, message: Message,
                        skipping: Set<Int> = []) -> StructureMatch {
        let ids = message.segments.map(\.segmentID)
        let grammar = Self.grammarTable(for: message.version)
        let withdrawn = MessageStructureTable.withdrawnSegments(for: message.version)
        // A skipped segment is matched as "", which no grammar defines.
        let matched = ids.indices.map { skipping.contains($0) ? "" : ids[$0] }
        let outside = Set(matched.filter { grammar[$0] == nil && withdrawn[$0] == nil })
        return StructureMatcherCache.shared.matcher(for: structure).match(matched, transparent: outside)
    }

    /// Why the message is a fragment of a logical message, or nil (ADR-019
    /// ceiling 6). A fragment's segment list is a slice of its structure, so
    /// it is not matched. v2.5.1 CH02 2.10.2.2: "the logical message is broken
    /// after an arbitrary segment"; "The DSC-1-Continuation pointer field will
    /// contain a unique value that is used to match a subsequent message";
    /// "The DSC terminates the first fragment of the logical message"; "The
    /// presence of a value in MSH-14 indicates that the message is a fragment
    /// of an earlier message"; "The receiver can tell that a given incoming
    /// message is a fragment by the presence of the trailing DSC". DSC-1
    /// (2.15.4.1): "If the responder returns a value of null or not present,
    /// then there is no more data". DSC-2 (2.15.4.2, Table 0398: F
    /// Fragmentation, I Interactive Continuation) is not consulted, so a
    /// complete message that carries a continuation pointer (an interactive
    /// query response, CH05 5.6.3.1) is not matched either.
    ///
    /// The rule: MSH-14 populated; or the last segment (Z and ADD ignored) is
    /// DSC with DSC-1 populated, whatever the structure defines; or the last
    /// segment is DSC and the structure's last top-level element is not DSC.
    /// A trailing DSC with an empty or null DSC-1 on a structure that ends in
    /// `[DSC]` is matched. MSH-14 is read the same way: it carries the unique
    /// value that matched a previous DSC-1, and the HL7 null `""` is not a
    /// value that can match one, so it does not mark a fragment.
    func fragmentReason(_ message: Message, structure: MessageStructure) -> String? {
        func populated(_ field: Field?) -> Bool {
            let value = field?.stringValue ?? ""
            return !value.isEmpty && value != "\"\""
        }
        if populated(message.segments.first?.field(14)) { return "MSH-14 is populated" }
        guard let last = message.segments.last(where: { !StructureMatcher.isTransparent($0.segmentID) }),
              last.segmentID == "DSC" else { return nil }
        if populated(last.field(1)) { return "it ends in a DSC whose DSC-1 continuation pointer is populated" }
        if case .segment("DSC", _, _) = structure.elements.last { return nil }
        return "it ends in a DSC, which \(structure.id) does not define there"
    }

    /// Why a structure whose keyed choice the message's key value does not
    /// select is not matched (S4-1): the print's map is the only list of
    /// values it gives, so another value is not a mismatch.
    static func unmappedReason(_ key: StructureChoiceKey, _ value: String, structure: String) -> String {
        let known = key.alternatives.keys.sorted().joined(separator: ", ")
        return "\(key.fieldName) is \"\(value)\", which the print does not map to a body of \(structure) "
            + "(it maps \(known); \(key.citation))"
    }

    /// The info issue for a message no structure is applied to. An empty
    /// `name` means MSH-9 is empty.
    func notModelled(_ name: String, message: Message,
                     reason: String? = nil) -> ValidationIssue {
        let subject = name.isEmpty ? "this message" : name
        let why = reason.map { name.isEmpty ? "MSH-9 is empty; \($0)" : $0 }
            ?? (name.isEmpty ? "MSH-9 is empty, so no structure can be resolved"
                : "no v\(message.version.rawValue) abstract message syntax is modelled for \(name)")
        return ValidationIssue(
            severity: .info,
            code: .messageStructureNotModelled(structure: name),
            location: IssueLocation(segmentID: "MSH", segmentIndex: 1, fieldIndex: 9),
            message: "Segment order and groups were not checked for \(subject): \(why) (ADR-019)."
        )
    }
}
