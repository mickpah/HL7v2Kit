// Validator+MessageStructure.swift
// ADR-019: check a message's segment sequence against its abstract message
// structure. Runs only when ValidationOptions.messageStructureSeverity is set.

extension Validator {
    /// Resolve the message's structure, then report every missing and
    /// unexpected segment the matcher finds.
    func checkMessageStructure(message: Message, severity: IssueSeverity, issues: inout [ValidationIssue]) {
        let resolution = resolveStructure(message, severity: severity)
        issues += resolution.issues
        guard let structure = resolution.structure else { return }
        issues += matchStructure(structure, message: message, severity: severity)
    }

    /// The structure to match, or the one issue saying why none is matched.
    ///
    /// Version rule (ADR-019 "Structure resolution and version"): structures
    /// apply only when MSH-12 reads as a recognised version whose grammar
    /// version is the message's; an empty, unresolved or different reading
    /// (for example `ParserOptions.versionOverride`) is not matched.
    /// Lookup: MSH-9.3 when valued, else MSH-9.1^9.2 through the caption-line
    /// triggers when exactly one structure prints it. An MSH-9.3 whose
    /// structure does not print MSH-9.1^9.2 is reported as a mismatch alone,
    /// with no body match. Table 0354 is not consulted.
    func resolveStructure(_ message: Message, severity: IssueSeverity) -> (structure: MessageStructure?, issues: [ValidationIssue]) {
        let code = message.messageCode ?? ""
        let event = message.triggerEvent ?? ""
        let trigger = event.isEmpty ? code : "\(code)^\(event)"
        let declared = message.messageStructure ?? ""
        let name = declared.isEmpty ? trigger : declared

        let msh12 = message.segments.first.flatMap { $0.segmentID == "MSH" ? $0.field(12) : nil }
        let reading = Version.reading(msh12: msh12, subcomponentSeparator: message.encodingCharacters.subcomponentSeparator)
        guard case .recognised(let wire) = reading, wire.grammarVersion == message.version.grammarVersion else {
            let why = reading == .empty
                ? "MSH-12 is empty"
                : "MSH-12 does not resolve to v\(message.version.rawValue), the version validated"
            return (nil, [notModelled(name, message: message, reason: why)])
        }

        guard !declared.isEmpty else {
            let byTrigger = MessageStructureTable.structures(messageCode: code, triggerEvent: event, version: message.version)
            guard byTrigger.count == 1 else { return (nil, [notModelled(trigger, message: message)]) }
            return (byTrigger[0], [])
        }
        guard let structure = MessageStructureTable.structure(declared, version: message.version) else {
            return (nil, [notModelled(declared, message: message)])
        }
        guard structure.accepts(messageCode: code, triggerEvent: event) else {
            return (nil, [ValidationIssue(
                severity: severity,
                code: .messageStructureMismatch(declared: declared, trigger: trigger),
                location: IssueLocation(segmentID: "MSH", segmentIndex: 1, fieldIndex: 9, componentIndex: 3),
                message: "MSH-9.3 \(declared) is not printed for \(trigger) in v\(message.version.rawValue) (\(structure.citation)); segment order and groups were not checked (ADR-019)."
            )])
        }
        return (structure, [])
    }

    /// Match the message body against `structure`: fragments and structures
    /// that fail the determinism lint are reported as not modelled; otherwise
    /// every finding is located on a real segment of the message.
    func matchStructure(_ structure: MessageStructure, message: Message, severity: IssueSeverity) -> [ValidationIssue] {
        let ids = message.segments.map(\.segmentID)
        if let why = fragmentReason(message, structure: structure) {
            return [notModelled(structure.id, message: message, reason: "the message is a fragment (\(why))")]
        }
        guard StructureMatcher.lint(structure.elements).isDeterministic else {
            return [notModelled(structure.id, message: message, reason: "\(structure.id) fails the determinism lint")]
        }

        // Segments the version grammar lacks already raise
        // segmentNotInVersionGrammar; Z and ADD are skipped by the matcher.
        let grammar = Self.grammarTable(for: message.version)
        let outside = Set(ids.filter { grammar[$0] == nil })
        let match = StructureMatcher(structure: structure).match(ids, transparent: outside)
        guard !match.findings.isEmpty, !ids.isEmpty else { return [] }

        var seen: [String: Int] = [:]
        let occurrence = ids.map { id -> Int in
            let n = (seen[id] ?? 0) + 1
            seen[id] = n
            return n
        }
        func location(_ index: Int) -> IssueLocation {
            IssueLocation(segmentID: ids[index], segmentIndex: occurrence[index])
        }

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
                    message: "\(finding.segmentID) has no place in \(structure.id) at this point\(why) (\(structure.citation))."
                )
            }
        }
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
    /// `[DSC]` is matched.
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
