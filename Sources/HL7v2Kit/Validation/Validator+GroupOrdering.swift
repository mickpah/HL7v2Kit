// Validator+GroupOrdering.swift
// P12 S2-2: in-group ordering rules (HL7au:000008.1.5; see `GroupOrderingRule`).

extension Validator {
    /// For each group a rule's anchor heads, report every ordered segment after the
    /// first one matching `startPredicate` that does not match `allowedAfterPredicate`.
    /// Groups resolve through `resolveGroup`, as the cardinality rules over the same
    /// scope do (HL7au:000008's display-OBX count), so both read one group, resolved
    /// once per call through `groupCache` (P12 S3-2); an anchor with no resolvable
    /// group is not checked.
    func checkGroupOrderingRules(
        profile: Profile,
        message: Message,
        groupCache: inout GroupResolutionCache,
        issues: inout [ValidationIssue]
    ) {
        guard !profile.groupOrderingRules.isEmpty, let first = message.segments.first else { return }
        let segments = message.segments
        for rule in profile.groupOrderingRules {
            if let gate = rule.applicableWhen, !gate.isEmpty {
                guard conditionTriggers(
                    gate, in: first, segmentIndex: 0,
                    message: message, currentSegmentID: first.segmentID
                ) else { continue }
            }
            var checkedHeads: Set<Int> = []
            var reported: Set<Int> = []
            for (anchorIndex, anchor) in segments.enumerated() where anchor.segmentID == rule.anchorSegmentID {
                guard let group = resolveGroup(
                    scope: rule.scope, anchorIndex: anchorIndex,
                    counted: rule.orderedSegmentID, message: message,
                    cache: &groupCache
                ), checkedHeads.insert(group.headIndex).inserted else { continue }
                var started = false
                for index in group.indices where segments[index].segmentID == rule.orderedSegmentID {
                    let segment = segments[index]
                    if started {
                        guard !conditionTriggers(
                            rule.allowedAfterPredicate, in: segment, segmentIndex: index,
                            message: message, currentSegmentID: segment.segmentID
                        ), reported.insert(index).inserted else { continue }
                        let occurrence = segments[...index].filter { $0.segmentID == rule.orderedSegmentID }.count
                        let location = IssueLocation(segmentID: rule.orderedSegmentID, segmentIndex: occurrence)
                        appendProfileIssue(
                            citation: rule.specCitation,
                            location: location,
                            message: "AU profile rule violated at \(location.pathDescription): \(rule.orderedSegmentID) follows one matching '\(rule.startPredicate)' in the same group but does not match '\(rule.allowedAfterPredicate)' (\(rule.specCitation))",
                            into: &issues
                        )
                    } else if conditionTriggers(
                        rule.startPredicate, in: segment, segmentIndex: index,
                        message: message, currentSegmentID: segment.segmentID
                    ) {
                        started = true
                    }
                }
            }
        }
    }
}
