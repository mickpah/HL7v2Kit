// Validator+ProfileStructure.swift
// P8b-4 (ADR-019 "HL7au:00060.1", decisions 7 and 8; P8b-4a): under a locale whose profile
// prints constrained message structures (the ADRM-2021 for .auLocalisation), the
// message is matched against the constrained structure as well as the base one,
// and the profile structure governs the base findings (P8b-4a, decision 7 as amended).

extension Validator {
    /// The profile findings for a message whose base structure `base` resolved and
    /// was matched with `baseFindings`.
    ///
    /// The profile structure applies when the locale's profile constrains `base`
    /// (same ID, same base version) and prints the message's MSH-9.1^9.2, so every
    /// version, lookup and mismatch rule of the base resolution has already passed;
    /// a fragment is not matched (the base match reported it). Only `missing`
    /// findings are reported, as `profileConstraintViolation(localeRule:)` with the
    /// structure's rule, at `severity`. Where a variant of the profile structure is
    /// selected by the profile the message declares in MSH-12.3.1 (P12 S1-1), that
    /// print is matched in place of the structure's own. A base segment the profile removed is not a
    /// finding (decision 7): every segment the profile structure does not name is
    /// passed over, as a segment outside the version grammar is, and `unexpected`
    /// findings are dropped. A segment the base match already reports missing at the
    /// same place is not reported again.
    ///
    /// The profile structure also governs the base findings (P8b-4a, ADR-019
    /// decision 7 as amended): a base finding is dropped where the profile structure
    /// accepts the message at that point, that is where no profile finding is
    /// located there and either the base reports `unexpected` a segment the profile
    /// structure places there, or the base reports `missing` a segment the profile
    /// structure does not report missing anywhere (it makes it optional, or removes
    /// it). Every other base finding is kept; where no profile applies, all of them.
    /// An exact-matched base, which reports its first divergence only, is matched
    /// again past each dropped `unexpected` until a finding is kept or none is left.
    func matchProfileStructure(over base: MessageStructure, baseFindings: [ValidationIssue], message: Message,
                               severity: IssueSeverity) -> (base: [ValidationIssue], profile: [ValidationIssue]) {
        let table = MessageStructureTable.profileStructures(for: locale)
        let code = message.messageCode ?? "", event = message.triggerEvent ?? ""
        guard let structure = table[base.id], let rule = structure.rule, structure.baseVersion == base.version,
              structure.accepts(messageCode: code, triggerEvent: event),
              fragmentReason(message, structure: base) == nil else { return (baseFindings, []) }
        // P12 S1-1 (owner ruling G-AU3): a print the message's declared profile selects
        // (MSH-12.3.1, the ADRM-2021 Appendix 8 simplified REF profile) replaces the structure.
        let profile = structure.selectingVariant(messageCode: code, triggerEvent: event, declaredProfile: message["MSH-12.3.1"])

        let ids = message.segments.map(\.segmentID)
        guard !ids.isEmpty else { return (baseFindings, []) }
        let grammar = Self.grammarTable(for: message.version)
        let named = profile.elements.reduce(into: Set<String>()) { $0.formUnion($1.segmentIDs) }
        let passedOver = Set(ids.filter { grammar[$0] == nil || !named.contains($0) })
        let match = StructureMatcherCache.shared.matcher(for: profile).match(ids, transparent: passedOver)

        let location = Self.segmentLocations(ids)
        let expectedAt = Self.missingPositions(match.findings, ids: ids, passedOver: passedOver)
        func at(_ index: Int) -> String { location(min(index, ids.count - 1)).pathDescription }
        // Where the profile does not accept the message (both places of a relocated
        // missing finding), what it reports missing, and the segments it places.
        let unsettled = Set(match.findings.map { at($0.index) } + expectedAt.map(at))
        let profileMissing = Set(match.findings.filter { $0.kind == .missing }.map(\.segmentID))
        let placed = Set(ids.indices.filter { !StructureMatcher.isTransparent(ids[$0]) && !passedOver.contains(ids[$0]) }.map(at))
        func keeps(_ issue: ValidationIssue) -> Bool {
            let here = issue.location.pathDescription
            guard !unsettled.contains(here) else { return true }
            switch issue.code {
            case .messageStructureSegmentUnexpected: return !placed.contains(here)
            case .messageStructureSegmentMissing(_, let segmentID, _): return profileMissing.contains(segmentID)
            default: return true
            }
        }
        var kept = baseFindings.filter(keeps)
        // An exact-matched base reports its first divergence only. When that is a
        // dropped `unexpected`, the base is matched again with the dropped occurrence
        // passed over, so a later divergence is found. Each round passes over one more
        // message index, so the loop ends within the message's length; a dropped
        // `missing` is located at the end, after every segment was consumed, so
        // nothing follows it.
        // P8b-18: a segment the base structure does not name anywhere is unexpected
        // wherever a base parse reaches it, and dropped when the profile places it
        // there, so the loop would pass over every such occurrence one round at a
        // time. They are passed over together on entry (one pass), which leaves the
        // result unchanged and keeps the loop for the segments the base does name.
        var skipped: Set<Int> = []
        var findings = baseFindings
        if base.requiresExactMatch, kept.isEmpty, let first = findings.first,
           case .messageStructureSegmentUnexpected = first.code {
            let inBase = base.elements.reduce(into: Set<String>()) { $0.formUnion($1.segmentIDs) }
            let alien = ids.indices.filter { index in
                guard !inBase.contains(ids[index]), !passedOver.contains(ids[index]),
                      !StructureMatcher.isTransparent(ids[index]) else { return false }
                let here = at(index)
                return placed.contains(here) && !unsettled.contains(here)
            }
            if !alien.isEmpty {
                skipped = Set(alien)
                findings = matchStructure(base, message: message, severity: severity, skipping: skipped)
                kept = findings.filter(keeps)
            }
        }
        while base.requiresExactMatch, kept.isEmpty, let dropped = findings.first,
              case .messageStructureSegmentUnexpected = dropped.code,
              let index = ids.indices.first(where: { at($0) == dropped.location.pathDescription }),
              skipped.insert(index).inserted {
            findings = matchStructure(base, message: message, severity: severity, skipping: skipped)
            kept = findings.filter(keeps)
        }

        let reported = Set(kept.compactMap { issue -> String? in
            guard case .messageStructureSegmentMissing(_, let segmentID, _) = issue.code else { return nil }
            return "\(segmentID)@\(issue.location.pathDescription)"
        })
        // P8b-18: a requirement the matcher reaches the end with, while segments follow
        // the last one the profile matched (RQD in place of OBR on ORM^O01, or a
        // Z-segment), belongs after that last matched segment: the segments after it
        // are transparent to the profile match, so the required one may stand before,
        // between or after them. The finding stays located at the last segment
        // (fix round 2: "no later than the last segment" was false).
        let lastMatched = ids.indices.last { !StructureMatcher.isTransparent(ids[$0]) && !passedOver.contains(ids[$0]) }
        let endPlace = lastMatched.flatMap { $0 < ids.count - 1 ? "after \(location($0).pathDescription)" : nil }
            ?? "at the end of the message"
        // S6-3 (owner ruling 2026-10-06, decision 7 as amended): an occurrence beyond a
        // maximum the profile narrows is information, once per occurrence, where the
        // base kept no finding of its own at that place (the base accepts it).
        let keptPlaces = Set(kept.map(\.location.pathDescription))
        let beyond = match.findings.compactMap { finding -> ValidationIssue? in
            guard finding.kind == .exceededMaximum, finding.index < ids.count else { return nil }
            let anchor = location(finding.index)
            guard !keptPlaces.contains(anchor.pathDescription) else { return nil }
            let clause = Self.beyondMaximumClause(
                segmentID: finding.segmentID,
                maximum: Self.profileMaximum(of: finding.segmentID, in: profile.elements),
                structure: "the \(profile.id) structure of the \(profile.profile ?? "profile") profile")
            return ValidationIssue(
                severity: .info,
                code: .profileMaximumExceeded(localeRule: rule),
                location: anchor,
                message: "\(rule): \(clause); the base v\(base.version) "
                    + "\(base.id) structure accepts it (\(profile.citation)). Reported at information (ADR-019 decision 7, "
                    + "owner ruling 2026-10-06)."
            )
        }
        return (kept, beyond + match.findings.indices.compactMap { n in
            let finding = match.findings[n]
            guard finding.kind == .missing else { return nil }
            let index = expectedAt[n]
            let atEnd = index >= ids.count
            let anchor = location(min(index, ids.count - 1))
            guard !reported.contains("\(finding.segmentID)@\(anchor.pathDescription)") else { return nil }
            let place = atEnd ? endPlace : "before \(anchor.pathDescription)"
            let scope = finding.group.map { " in group \($0)" } ?? ""
            return ValidationIssue(
                severity: severity,
                code: .profileConstraintViolation(localeRule: rule),
                location: anchor,
                message: "\(rule): the \(profile.id) structure of the \(profile.profile ?? "profile") profile requires "
                    + "\(finding.segmentID)\(scope) \(place) (\(profile.citation))."
            )
        })
    }

    /// The message index each finding is located at. The one-pass matcher's
    /// recovery skips the segments nothing can begin (`unexpected` findings) and
    /// reports a required element missing after them; with no segment consumed
    /// in between, the element was already expected before the first of those
    /// segments, so a `missing` finding that directly follows such a run is
    /// located at the run's start. The profile drops the `unexpected` findings
    /// (decision 7), so the location must not depend on them being read first.
    static func missingPositions(_ findings: [StructureFinding], ids: [String], passedOver: Set<String>) -> [Int] {
        let matched = ids.indices.filter { !StructureMatcher.isTransparent(ids[$0]) && !passedOver.contains(ids[$0]) }
        let rank = Dictionary(uniqueKeysWithValues: matched.enumerated().map { ($1, $0) })
        func position(_ index: Int) -> Int { rank[index] ?? matched.count }
        var runStart: Int?
        var runLast = -2
        return findings.map { finding in
            let here = position(finding.index)
            if finding.kind != .missing {
                if runStart == nil || here != runLast + 1 { runStart = finding.index }
                runLast = here
                return finding.index
            }
            guard let start = runStart, here == runLast + 1 else { return finding.index }
            return start
        }
    }

    /// How many times `segmentID` may occur at its first place in `elements`: the
    /// product of the maxima on the path to that segment element, nil when one
    /// of them is unbounded or the segment is not named.
    /// The first clause of a beyond-maximum finding: the profile's maximum where one product of
    /// the printed cardinalities gives it, else that the occurrence is more than the profile allows
    /// (S6 fix wave M4: no vague "bounded number of times").
    static func beyondMaximumClause(segmentID: String, maximum: Int?, structure: String) -> String {
        guard let maximum else { return "\(segmentID) occurs here more times than \(structure) allows" }
        let most = maximum == 1 ? "at most once" : "at most \(maximum) times"
        return "\(structure) allows \(segmentID) \(most) here, and this occurrence is beyond it"
    }

    static func profileMaximum(of segmentID: String, in elements: [StructureElement]) -> Int? {
        for element in elements {
            if case .segment(segmentID, _, let max) = element { return max }
            guard element.segmentIDs.contains(segmentID), case .group = element else { continue }
            guard let outer = element.max, let inner = profileMaximum(of: segmentID, in: element.children) else { return nil }
            return outer * inner
        }
        return nil
    }

    /// The location of each segment of `ids`, by index: its ID and its 1-based
    /// occurrence among segments with that ID.
    static func segmentLocations(_ ids: [String]) -> (Int) -> IssueLocation {
        var seen: [String: Int] = [:]
        let occurrence = ids.map { id -> Int in
            let n = (seen[id] ?? 0) + 1
            seen[id] = n
            return n
        }
        return { IssueLocation(segmentID: ids[$0], segmentIndex: occurrence[$0]) }
    }
}
