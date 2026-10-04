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
    /// structure's rule, at `severity`. A base segment the profile removed is not a
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
    /// `profiles` replaces the generated table; tests pass synthetic ones.
    func matchProfileStructure(over base: MessageStructure, baseFindings: [ValidationIssue], message: Message,
                               severity: IssueSeverity,
                               profiles: [String: MessageStructure]? = nil) -> (base: [ValidationIssue], profile: [ValidationIssue]) {
        let table = profiles ?? MessageStructureTable.profileStructures(for: locale)
        guard let profile = table[base.id], let rule = profile.rule, profile.baseVersion == base.version,
              profile.accepts(messageCode: message.messageCode ?? "", triggerEvent: message.triggerEvent ?? ""),
              fragmentReason(message, structure: base) == nil else { return (baseFindings, []) }

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
        let kept = baseFindings.filter { issue in
            let here = issue.location.pathDescription
            guard !unsettled.contains(here) else { return true }
            switch issue.code {
            case .messageStructureSegmentUnexpected: return !placed.contains(here)
            case .messageStructureSegmentMissing(_, let segmentID, _): return profileMissing.contains(segmentID)
            default: return true
            }
        }

        let reported = Set(kept.compactMap { issue -> String? in
            guard case .messageStructureSegmentMissing(_, let segmentID, _) = issue.code else { return nil }
            return "\(segmentID)@\(issue.location.pathDescription)"
        })
        return (kept, match.findings.indices.compactMap { n in
            let finding = match.findings[n]
            guard finding.kind == .missing else { return nil }
            let index = expectedAt[n]
            let atEnd = index >= ids.count
            let anchor = location(min(index, ids.count - 1))
            guard !reported.contains("\(finding.segmentID)@\(anchor.pathDescription)") else { return nil }
            let place = atEnd ? "at the end of the message" : "before \(anchor.pathDescription)"
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
