// Validator.swift
// Structural + cardinality + Z-segment-policy validation. Reads the
// codegen-emitted `SegmentGrammarTable.v2_5_1` table (Path C from STATUS
// decisions log 2026-06-13). Non-fatal: returns a `ValidationReport`,
// never throws.

import Foundation

/// Validate a parsed `Message` against the loaded segment grammars.
public struct Validator: Sendable {
    public let options: ValidationOptions

    /// The locale this validator was configured with. Default `.international`.
    /// Propagates onto every `ValidationReport.locale` produced by
    /// `validate(_:)`. See ADR-007.
    public let locale: HL7Locale

    /// Test-only seam (not public API, no `@testable` consumer outside this
    /// package): when set, `validate(_:)` uses this profile instead of
    /// resolving one from `locale` via `Profile.load(for:)`. Lets a test
    /// exercise profile-composite-override edge cases (e.g. `yieldsToBase`
    /// interacting with `effectiveDataType`) without adding synthetic
    /// fixtures to the shipped AU profile data. P3-5 fix round 1.
    let testProfileOverride: Profile?

    public init(options: ValidationOptions = .default, locale: HL7Locale = .international) {
        self.options = options
        self.locale = locale
        self.testProfileOverride = nil
    }

    init(options: ValidationOptions = .default, locale: HL7Locale = .international, testProfileOverride: Profile) {
        self.options = options
        self.locale = locale
        self.testProfileOverride = testProfileOverride
    }

    /// Validate a message. Returns a non-empty report only when at least
    /// one check produced an issue.
    public func validate(_ message: Message) -> ValidationReport {
        var issues: [ValidationIssue] = []
        // ADR-018: report how MSH-12 relates to the grammar applied, then
        // validate a copy that declares the grammar version, so every
        // version-keyed lookup below (segment grammar, tables, datatype
        // grammar, version-gated ORC/OBR pairs) uses the same release.
        appendVersionIssues(for: message, issues: &issues)
        let declared = message.declaring(message.version.grammarVersion)
        // P8b-17 (ADR-019): group spans, or the fallback, for the
        // group-dependent predicates, whatever messageStructureSeverity is.
        let message = declared.scoped(groupScoping(for: declared))
        var segmentOccurrence: [String: Int] = [:]
        // v0.11-S3 (ADR-010 Extension 2): dedupe fired cardinality
        // violations by (scope, groupHeadIndex, rule identity) so a
        // rule attached to a head segment (e.g. HL7au:000008 on OBR)
        // that would be re-evaluated for each candidate segment in the
        // group only fires once per distinct group.
        var firedCardinalityKeys: Set<String> = []

        let grammar = Self.grammarTable(for: message.version)
        let withdrawnSegments = MessageStructureTable.withdrawnSegments(for: message.version)
        // v0.4-S5-A / v0.5-S5-B: load the profile once per `validate(_:)`
        // call. nil for `.international`; for `.auLocalisation` returns
        // the AU ADRM-2021 profile with field-override narrowings layered
        // on top of base v2.4 / v2.5.1 grammar. See ADR-007.
        let profile = testProfileOverride ?? Profile.load(for: locale)

        // v0.7-S1 (ADR-008): iterate with the 0-based segment index so
        // cross-segment / message-context predicates can resolve peers
        // and group boundaries against the full message. The index is
        // plumbed through `checkSegment` → `checkConditional` →
        // predicate evaluators; the evaluator productions stay
        // single-segment in S1 and gain cross-segment grammar in S2.
        for (segmentIndex, segment) in message.segments.enumerated() {
            let id = segment.segmentID
            let occurrence = (segmentOccurrence[id] ?? 0) + 1
            segmentOccurrence[id] = occurrence

            guard let baseGrammar = grammar[id] else {
                // No grammar entry. Only a `Z` ID is a Z-segment (ADR-003);
                // any other ID is a segment this version does not define
                // (ADR-018), reported whatever the Z-segment policy.
                if id.hasPrefix("Z") {
                    appendZSegmentIssue(id: id, occurrence: occurrence, issues: &issues)
                } else if let withdrawn = withdrawnSegments[id] {
                    // ADR-019 S2-1: the version lists it as withdrawn and prints
                    // no definition; CH02 2.8.4 leaves its use to site agreement.
                    issues.append(ValidationIssue(
                        severity: .info,
                        code: .segmentWithdrawnInVersion,
                        location: IssueLocation(segmentID: id, segmentIndex: occurrence),
                        message: "Segment '\(id)' is listed as \(withdrawn.printed) by HL7 v\(message.version.grammarVersion.rawValue) "
                            + "Appendix A and defined through v\(withdrawn.definedThrough); its fields were not validated"
                    ))
                } else {
                    issues.append(ValidationIssue(
                        severity: .warning,
                        code: .segmentNotInVersionGrammar,
                        location: IssueLocation(segmentID: id, segmentIndex: occurrence),
                        message: "Segment '\(id)' is not defined by the HL7 v\(message.version.rawValue) grammar; its fields were not validated"
                    ))
                }
                continue
            }

            // v0.5-S5-D: merge the profile's grammar extensions for
            // this segment (if any) onto the base grammar. Used for
            // AU pre-adoption of v2.5+ PID-35..38 on v2.4 wires under
            // `.auLocalisation`. v0.11-S3 (ADR-010): also merge the
            // profile's cardinality extensions.
            let segGrammar = mergeGrammarExtension(
                base: baseGrammar,
                profileExtension: profile?.grammarExtensions[id],
                profileCardinalityExtension: profile?.cardinalityExtensions[id]
            )

            checkSegment(
                segment,
                segmentIndex: segmentIndex,
                message: message,
                grammar: segGrammar,
                occurrence: occurrence,
                profile: profile,
                issues: &issues
            )

            // v0.11-S3 (ADR-010 Extension 2): group-scope cardinality
            // rules attached to this segment's (merged) grammar.
            // Deduped by (scope, groupHeadIndex, rule identity) so the
            // rule fires once per distinct group even when the anchor
            // segment appears multiple times.
            checkCardinalityRules(
                grammar: segGrammar,
                anchorIndex: segmentIndex,
                anchorOccurrence: occurrence,
                message: message,
                firedKeys: &firedCardinalityKeys,
                issues: &issues
            )
        }

        // M6-B-9: message-wide field-uniqueness rules (HL7au:000028/.2).
        if let profile {
            checkUniquenessRules(profile: profile, message: message, issues: &issues)
            // M7-P3: prohibited escape-sequence scan (ADRM-prose:P-4).
            checkEscapeProhibitions(profile: profile, message: message, issues: &issues)
            // M12: OBX-4 sub-ID trees (ADRM-prose:P-8..P-10, the HL7v2 VMR).
            checkSubIDTrees(profile: profile, message: message, issues: &issues)
            // P12 S2-2: in-group ordering (HL7au:000008.1.5).
            checkGroupOrderingRules(profile: profile, message: message, issues: &issues)
        }

        // M8-B1: base-spec ORC/OBR paired-field equality (items
        // 00216/00217) — runs for every locale and version; the pairs
        // are the base standard's own identity assertions.
        checkOrcObrPairEquality(message: message, issues: &issues)

        // ADR-019: abstract message syntax (segment order, groups, required
        // segments per structure). Opt-in.
        if let severity = options.messageStructureSeverity {
            checkMessageStructure(message: message, severity: severity, issues: &issues)
        }

        // S1-4 (owner decision 9): say so when the P8b-17 fallback gate
        // skipped the order-number predicates.
        checkGatedConditions(message: message, issues: &issues)

        return ValidationReport(issues: issues, locale: locale)
    }

    // MARK: - Internals

    /// Merge a profile's grammar extension into a base segment
    /// grammar. The extension's fields APPEND to the base when their
    /// index doesn't already exist; they REPLACE the base field when
    /// the index does exist. v0.5-S5-D.
    ///
    /// The replacement semantic lets a profile both add new fields
    /// (typical case — AU PID-35..38 on v2.4) AND override an
    /// existing field's optionality / condition if needed in the
    /// future. Today only the additive case is exercised.
    private func mergeGrammarExtension(
        base: SegmentGrammar,
        profileExtension: [FieldGrammar]?,
        profileCardinalityExtension: [SegmentCardinalityRule]? = nil
    ) -> SegmentGrammar {
        let profileCardinality = profileCardinalityExtension ?? []
        // Fast path: no extensions of either kind.
        if (profileExtension?.isEmpty ?? true) && profileCardinality.isEmpty {
            return base
        }
        // Field merge (v0.5-S5-D behaviour).
        let mergedFields: [FieldGrammar]
        if let profileExtension, !profileExtension.isEmpty {
            let extensionByIndex = Dictionary(
                uniqueKeysWithValues: profileExtension.map { ($0.index, $0) }
            )
            var merged = base.fields.map { extensionByIndex[$0.index] ?? $0 }
            let baseIndices = Set(base.fields.map(\.index))
            let added = profileExtension
                .filter { !baseIndices.contains($0.index) }
                .sorted(by: { $0.index < $1.index })
            merged.append(contentsOf: added)
            mergedFields = merged
        } else {
            mergedFields = base.fields
        }
        // Cardinality merge (v0.11-S3 behaviour). Profile rules append
        // to base rules; no replace semantic — locale-scoped rules
        // and base-spec universal rules coexist.
        let mergedCardinality = base.segmentCardinalityRules + profileCardinality
        return SegmentGrammar(
            segmentID: base.segmentID,
            version: base.version,
            fields: mergedFields,
            segmentCardinalityRules: mergedCardinality
        )
    }

    /// v0.11-S3 (ADR-010 Extension 2). For each cardinality rule
    /// attached to this segment's merged grammar, resolve the rule's
    /// group scope, count segments in that group whose predicate
    /// evaluation is `true`, and fire `.segmentCardinalityBelowMinimum`
    /// when the count is below the rule's minimum.
    ///
    /// `firedKeys` is a set of `(scope, groupHeadIndex, rule identity)`
    /// strings threaded across the per-segment loop so a rule attached
    /// to a head segment (e.g. HL7au:000008 on OBR) that would be
    /// re-evaluated for each candidate segment in the group only fires
    /// once per distinct group.
    ///
    /// Fail-safe semantics: an unparseable predicate, an unresolvable
    /// `applicableWhen` gate, or an out-of-bounds group yields no
    /// violation (the atom returns `false`; the group scan returns
    /// zero matches; the check silently skips). Consistent with the
    /// v0.2-V1 invariant that a malformed schema must never make a
    /// previously-accepted message non-conformant.
    private func checkCardinalityRules(
        grammar: SegmentGrammar,
        anchorIndex: Int,
        anchorOccurrence: Int,
        message: Message,
        firedKeys: inout Set<String>,
        issues: inout [ValidationIssue]
    ) {
        for rule in grammar.segmentCardinalityRules {
            // `applicableWhen` gate — evaluated against the anchor
            // segment. Reuses the v0.7 predicate DSL. If the gate is
            // set and evaluates false, skip this rule entirely.
            if let gate = rule.applicableWhen, !gate.isEmpty {
                guard conditionTriggers(
                    gate,
                    in: message.segments[anchorIndex],
                    segmentIndex: anchorIndex,
                    message: message,
                    currentSegmentID: grammar.segmentID
                ) else { continue }
            }

            guard let group = resolveGroup(
                scope: rule.scope,
                anchorIndex: anchorIndex,
                counted: rule.countedSegmentID,
                message: message
            ) else { continue }

            let key = "\(rule.scope.rawValue)|\(group.headIndex)|\(rule.countedSegmentID)|\(rule.predicate)|\(rule.minCount)|\(rule.maxCount.map(String.init) ?? "-")|\(rule.activationPredicate ?? "-")"
            if firedKeys.contains(key) { continue }
            firedKeys.insert(key)

            // M6-B-9 relational cardinality: when an activation
            // predicate is set, the rule applies only if at least one
            // segment in the group matches it (e.g. HL7au:000008.3.2 —
            // the HTML/PDF/TXT sibling requirement activates only when
            // an RTF display OBX exists in the group).
            if let activation = rule.activationPredicate, !activation.isEmpty {
                let activated = group.segments.enumerated().contains { offset, seg in
                    guard seg.segmentID == rule.countedSegmentID else { return false }
                    return conditionTriggers(
                        activation,
                        in: seg,
                        segmentIndex: group.indices[offset],
                        message: message,
                        currentSegmentID: seg.segmentID
                    )
                }
                guard activated else { continue }
            }

            // Iterate only candidate segments matching the rule's
            // `countedSegmentID`. This ensures the predicate resolves
            // against the current candidate's own fields (same-segment
            // path) rather than cross-segment-resolving to a peer
            // outside the current sub-group. Without this constraint,
            // e.g. `OBX-3.3 = AUSPDI` evaluated on an OBR candidate
            // would resolve via `associatedSegment("OBX", ...)` which
            // uses ORC-scoped group semantics and can find an OBX
            // belonging to a different OBR sub-group — false positive.
            var matches = 0
            for (offset, seg) in group.segments.enumerated() {
                // M6-B-2: a trailing `*` makes the counted ID a prefix
                // pattern — `"Z*"` counts every user-defined Z segment
                // (HL7au:000023.1). Exact match otherwise.
                if rule.countedSegmentID.hasSuffix("*") {
                    guard seg.segmentID.hasPrefix(rule.countedSegmentID.dropLast())
                    else { continue }
                } else {
                    guard seg.segmentID == rule.countedSegmentID else { continue }
                }
                // An empty predicate counts every segment of this ID —
                // whole-segment prohibitions have no field to test.
                if rule.predicate.isEmpty {
                    matches += 1
                    continue
                }
                let absoluteIndex = group.indices[offset]
                if conditionTriggers(
                    rule.predicate,
                    in: seg,
                    segmentIndex: absoluteIndex,
                    message: message,
                    currentSegmentID: seg.segmentID
                ) {
                    matches += 1
                }
            }

            if matches < rule.minCount {
                let citation = rule.specCitation.map { " (\($0))" } ?? ""
                issues.append(ValidationIssue(
                    severity: .error,
                    code: .segmentCardinalityBelowMinimum(
                        segmentID: rule.countedSegmentID,
                        minCount: rule.minCount,
                        actual: matches,
                        groupScope: rule.scope.rawValue
                    ),
                    location: IssueLocation(
                        segmentID: grammar.segmentID,
                        segmentIndex: anchorOccurrence
                    ),
                    message: "Group requires at least \(rule.minCount) \(rule.countedSegmentID) segment(s) matching '\(rule.predicate)'; found \(matches)\(citation)"
                ))
            }

            // M6-A-3: upper bound. `maxCount: 0` is a prohibition.
            if let maxCount = rule.maxCount, matches > maxCount {
                let citation = rule.specCitation.map { " (\($0))" } ?? ""
                let matching = rule.predicate.isEmpty
                    ? "" : " matching '\(rule.predicate)'"
                issues.append(ValidationIssue(
                    severity: .error,
                    code: .segmentCardinalityAboveMaximum(
                        segmentID: rule.countedSegmentID,
                        maxCount: maxCount,
                        actual: matches,
                        groupScope: rule.scope.rawValue
                    ),
                    location: IssueLocation(
                        segmentID: grammar.segmentID,
                        segmentIndex: anchorOccurrence
                    ),
                    message: maxCount == 0
                        ? "Group must contain no \(rule.countedSegmentID) segment(s)\(matching); found \(matches)\(citation)"
                        : "Group allows at most \(maxCount) \(rule.countedSegmentID) segment(s)\(matching); found \(matches)\(citation)"
                ))
            }
        }
    }

    /// Resolved group for a `GroupScope` anchored at `anchorIndex`.
    /// `indices` are the group's 0-based indices into `message.segments`
    /// in document order (contiguous under the walk; with spans, the
    /// anchor's own occurrence without nested pairing groups, P8b-17);
    /// `headIndex` is the first; `segments` are the segments at `indices`.
    struct ResolvedGroup {
        let indices: [Int]
        let segments: [Segment]
        var headIndex: Int { indices.first ?? 0 }

        init(indices: [Int], in all: [Segment]) {
            self.indices = indices
            self.segments = indices.map { all[$0] }
        }
    }

    func resolveGroup(
        scope: GroupScope,
        anchorIndex: Int,
        counted: String,
        message: Message
    ) -> ResolvedGroup? {
        let segs = message.segments
        guard anchorIndex >= 0, anchorIndex < segs.count else { return nil }
        switch scope {
        case .messageWide:
            return ResolvedGroup(indices: Array(segs.indices), in: segs)
        case .orcObxGroup:
            if case .spans(let spans) = message.groupScoping {
                return spans.group(around: anchorIndex, holding: "ORC", counting: counted)
                    .map { ResolvedGroup(indices: $0, in: segs) }
            }
            return ResolvedGroup(indices: Array(message.orcGroupRange(around: anchorIndex)), in: segs)
        case .obrObxGroup:
            if case .spans(let spans) = message.groupScoping {
                return spans.group(around: anchorIndex, holding: "OBR", counting: counted)
                    .map { ResolvedGroup(indices: $0, in: segs) }
            }
            var head = anchorIndex
            while head > 0 && segs[head].segmentID != "OBR" {
                head -= 1
            }
            // No OBR at or before the anchor → no OBR group here.
            guard segs[head].segmentID == "OBR" else { return nil }
            // S6-2: an SPM opens a specimen group (v2.5.1 to v2.8.2 ORU_R01
            // SPECIMEN { SPM [{OBX}] }), whose OBX are the specimen's, not
            // the OBR's, as the span rule reads it (GroupSpanIndex.owned).
            var end = head + 1
            while end < segs.count
                    && segs[end].segmentID != "OBR"
                    && segs[end].segmentID != "ORC"
                    && segs[end].segmentID != "SPM" {
                end += 1
            }
            return ResolvedGroup(indices: Array(head..<end), in: segs)
        }
    }

    /// The segment grammar table for `version` (ADR-018 substitution for
    /// `v2_8` and `v2_7`). Internal, not private, so tests can derive a per-version
    /// table list from `Version.allCases` instead of hand-maintaining one
    /// (P4-15, folded from the P4-25 review).
    static func grammarTable(for version: Version) -> [String: SegmentGrammar] {
        switch version {
        case .v2_3:   return SegmentGrammarTable.v2_3
        case .v2_3_1: return SegmentGrammarTable.v2_3_1
        case .v2_4:   return SegmentGrammarTable.v2_4
        case .v2_5_1: return SegmentGrammarTable.v2_5_1
        case .v2_6:   return SegmentGrammarTable.v2_6     // v0.14 (ADR-012)
        case .v2_7_1: return SegmentGrammarTable.v2_7_1   // plan P10 (ADR-018)
        case .v2_7:   return SegmentGrammarTable.v2_7_1   // ADR-018 substitution (G11)
        case .v2_8_2: return SegmentGrammarTable.v2_8_2   // v0.15 (ADR-013)
        case .v2_8:   return SegmentGrammarTable.v2_8_2   // ADR-018 substitution
        }
    }

    /// ADR-018: at most one MSH-12 issue describing how the declared
    /// version maps to the grammar applied.
    private func appendVersionIssues(for message: Message, issues: inout [ValidationIssue]) {
        let location = IssueLocation(segmentID: "MSH", segmentIndex: 1, fieldIndex: 12)
        let applied = message.version.grammarVersion
        // A populated MSH-12 from which no version resolves is reported here
        // (an empty one is the required-field check's business).
        let msh12 = message.segments.first.flatMap { $0.segmentID == "MSH" ? $0.field(12) : nil }
        let reading = Version.reading(
            msh12: msh12, subcomponentSeparator: message.encodingCharacters.subcomponentSeparator
        )
        if case .unresolved(let vid1) = reading {
            let what = vid1.isEmpty
                ? "MSH-12 is populated but its version ID (VID.1) is empty"
                : "MSH-12 version '\(vid1)' is not a version HL7v2Kit models"
            issues.append(ValidationIssue(
                severity: .warning,
                code: .versionNotRecognised(wireValue: vid1),
                location: location,
                message: "\(what); validated against the v\(applied.rawValue) grammar instead (ADR-018)"
            ))
            return
        }
        let declared = message.version
        guard applied != declared else { return }
        // Message.version may not come from the wire (ParserOptions.versionOverride,
        // or a Message built directly); say so, so the note never misquotes MSH-12.
        let source = reading == .recognised(declared)
            ? "MSH-12 declares \(declared.rawValue)"
            : "Message.version is \(declared.rawValue), which MSH-12 does not declare (for example, set by ParserOptions.versionOverride)"
        issues.append(ValidationIssue(
            severity: .info,
            code: .versionGrammarSubstituted(declared: declared, validatedAs: applied),
            location: location,
            message: "\(source); HL7v2Kit has no v\(declared.rawValue) grammar and validated this message against v\(applied.rawValue). Differences between the two releases are not verified (ADR-018)"
        ))
    }

    private func appendZSegmentIssue(
        id: String,
        occurrence: Int,
        issues: inout [ValidationIssue]
    ) {
        let location = IssueLocation(segmentID: id, segmentIndex: occurrence)
        switch options.zSegmentPolicy {
        case .ignore:
            return
        case .warnPresence:
            issues.append(ValidationIssue(
                severity: .info,
                code: .zSegmentPresent,
                location: location,
                message: "Z-segment '\(id)' present at occurrence \(occurrence)"
            ))
        case .reject:
            issues.append(ValidationIssue(
                severity: .error,
                code: .zSegmentPresent,
                location: location,
                message: "Z-segment '\(id)' rejected under .reject policy"
            ))
        }
    }

    private func checkSegment(
        _ segment: Segment,
        segmentIndex: Int,
        message: Message,
        grammar: SegmentGrammar,
        occurrence: Int,
        profile: Profile?,
        issues: inout [ValidationIssue]
    ) {
        for fieldGrammar in grammar.fields {
            checkField(
                fieldGrammar,
                at: fieldGrammar.index,
                requiredApplies: true,
                segment: segment,
                segmentIndex: segmentIndex,
                message: message,
                grammar: grammar,
                occurrence: occurrence,
                profile: profile,
                issues: &issues
            )
            // Track B: a SEQ 1-n field recurs by POSITION. Apply the same
            // grammar to every later wire column. Later columns are
            // individually optional (the spec bounds the count, never a
            // minimum), so the required check applies to column 1 only.
            guard fieldGrammar.variableColumns else { continue }
            let lastPosition = segment.fields.count - 1   // fields[0] is the segment ID
            if lastPosition > fieldGrammar.index {
                for position in (fieldGrammar.index + 1)...lastPosition {
                    checkField(
                        fieldGrammar,
                        at: position,
                        requiredApplies: false,
                        segment: segment,
                        segmentIndex: segmentIndex,
                        message: message,
                        grammar: grammar,
                        occurrence: occurrence,
                        profile: profile,
                        issues: &issues
                    )
                }
            }
        }
    }

    /// One field position's base-spec checks. `position` is the wire
    /// index the checks read and report; it equals `fieldGrammar.index`
    /// except for `variableColumns` grammars (Track B), where the same
    /// grammar is re-applied at each later column.
    private func checkField(
        _ fieldGrammar: FieldGrammar,
        at position: Int,
        requiredApplies: Bool,
        segment: Segment,
        segmentIndex: Int,
        message: Message,
        grammar: SegmentGrammar,
        occurrence: Int,
        profile: Profile?,
        issues: inout [ValidationIssue]
    ) {
        let location = IssueLocation(
            segmentID: grammar.segmentID,
            segmentIndex: occurrence,
            fieldIndex: position
        )

        let parsedField = segment.field(position)
        let isPopulated = parsedField.map { isFieldPopulated($0) } ?? false
        // v2.3 / v2.3.1 section 4.4.6: a single-repeat TQ field's repetitions 2..n are its
        // TQ.6 Priority repeat, not field repetitions (priorityContinuationTrimmed).
        let field = parsedField.map {
            Self.priorityContinuationTrimmed($0, grammar: fieldGrammar,
                                             dataType: effectiveDataType(of: fieldGrammar, in: segment),
                                             version: message.version)
        }

        if options.checkRequiredFields, requiredApplies {
            checkRequired(
                fieldGrammar,
                isPopulated: isPopulated,
                location: location,
                issues: &issues
            )
        }

        if options.checkConditionalFields {
            checkConditional(
                fieldGrammar,
                segment: segment,
                segmentIndex: segmentIndex,
                message: message,
                isPopulated: isPopulated,
                location: location,
                issues: &issues
            )
            // M8-D: the inverse case — populated while prohibited.
            checkProhibition(
                fieldGrammar,
                segment: segment,
                segmentIndex: segmentIndex,
                message: message,
                isPopulated: isPopulated,
                field: field,
                location: location,
                issues: &issues
            )
        }

        if options.checkComponentGrammar, let field, isPopulated {
            checkComponents(
                fieldGrammar,
                field: field,
                fieldIndex: position,
                segmentID: grammar.segmentID,
                segmentIndex: occurrence,
                version: message.version,
                issues: &issues
            )
        }

        if options.warnDeprecatedFields, isPopulated {
            checkDeprecation(
                fieldGrammar,
                location: location,
                issues: &issues
            )
            // S1-2: a B or W component, unless the field itself is already reported.
            switch fieldGrammar.optionality {
            case .backwardCompat, .notSupported, .withdrawn:
                break
            default:
                if let field {
                    checkComponentDeprecation(field: field, version: message.version,
                                              dataType: effectiveDataType(of: fieldGrammar, in: segment),
                                              location: location, issues: &issues)
                }
            }
        }

        if options.checkCardinality, let field, isPopulated {
            checkCardinality(
                fieldGrammar,
                field: field,
                location: location,
                issues: &issues
            )
        }

        // P6-6: LEN, per era (FieldLengthRule).
        if let field, isPopulated {
            checkFieldLength(fieldGrammar, field: field, segmentID: grammar.segmentID,
                             version: message.version,
                             dataType: effectiveDataType(of: fieldGrammar, in: segment),
                             encoding: message.encodingCharacters,
                             location: location, issues: &issues)
            // S1-1: v2.7+ normative length on each primitive component.
            checkComponentLength(field: field, version: message.version,
                                 dataType: effectiveDataType(of: fieldGrammar, in: segment),
                                 encoding: message.encodingCharacters,
                                 location: location, issues: &issues)
            // P6-13 / P6-14: content after the value of a primitive field or component.
            checkExtraPrimitiveComponents(fieldGrammar, field: field,
                                          dataType: effectiveDataType(of: fieldGrammar, in: segment),
                                          version: message.version,
                                          location: location, issues: &issues)
            // P6-7: primitive lexical rules (PrimitiveFormat).
            checkValueFormat(dataType: effectiveDataType(of: fieldGrammar, in: segment), field: field,
                             version: message.version, location: location, issues: &issues)
        }

        if options.checkCodeTables, let field, isPopulated, let tableNumber = fieldGrammar.table {
            checkCodeTable(fieldGrammar, tableNumber: tableNumber, field: field,
                           version: message.version, location: location, issues: &issues)
        }
        if options.checkCodeTables, let field, isPopulated {
            checkComponentCodeTables(dataType: effectiveDataType(of: fieldGrammar, in: segment),
                                     field: field, version: message.version,
                                     location: location, issues: &issues)
        }

        // v0.5-S5-B-1: layer the loaded profile's field overrides
        // on top of the base-spec checks. Only fires when locale
        // is non-international (profile != nil) AND the field has
        // an override AND the field is actually populated.
        if let profile, let field, isPopulated {
            checkProfileFieldOverrides(
                profile: profile,
                fieldGrammar: fieldGrammar,
                field: field,
                fieldIndex: position,
                segment: segment,
                segmentArrayIndex: segmentIndex,
                message: message,
                segmentID: grammar.segmentID,
                occurrence: occurrence,
                issues: &issues
            )
            // v0.5-S5-B-2: datatype-level composite overrides.
            checkProfileCompositeOverrides(
                profile: profile,
                fieldGrammar: fieldGrammar,
                field: field,
                fieldIndex: position,
                segment: segment,
                segmentArrayIndex: segmentIndex,
                message: message,
                segmentID: grammar.segmentID,
                segmentIndex: occurrence,
                issues: &issues
            )
            // P4-24: explicit, cited "must not be valued" rules.
            checkProfileFieldProhibitions(
                profile: profile,
                field: field,
                segment: segment,
                segmentArrayIndex: segmentIndex,
                message: message,
                location: location,
                issues: &issues
            )
            // P4-31: C fields whose condition is the full predicate.
            checkFullPredicateConditional(
                profile: profile,
                fieldGrammar: fieldGrammar,
                grammarVersion: grammar.version,
                field: field,
                segment: segment,
                segmentArrayIndex: segmentIndex,
                message: message,
                location: location,
                issues: &issues
            )
        }
        // v0.5-S5-D-2 (post-S5-D substage): profile usage dispatch.
        // Fires when the override declares `profileUsage = .required`
        // and the field is empty. Runs regardless of population
        // state because the absent case is what this check exists
        // to detect.
        if let profile {
            checkProfileFieldUsage(
                profile: profile,
                fieldGrammar: fieldGrammar,
                isPopulated: isPopulated,
                segment: segment,
                segmentArrayIndex: segmentIndex,
                message: message,
                location: location,
                issues: &issues
            )
        }
    }

    /// Append a `.profileConstraintViolation` error. All seven profile
    /// dispatch tracks construct their issues through here so severity /
    /// code / location plumbing cannot drift between tracks; the message
    /// is fully formatted at the call site (pinned exactly by the
    /// LocaleAUProfileTests R4-C2 characterization rows).
    func appendProfileIssue(
        citation: String,
        location: IssueLocation,
        message: String,
        into issues: inout [ValidationIssue]
    ) {
        issues.append(ValidationIssue(
            severity: .error,
            code: .profileConstraintViolation(localeRule: citation),
            location: location,
            message: message
        ))
    }

    /// Composite (datatype-keyed) override dispatch — v0.5-S5-B-2 +
    /// v0.5-S5-B-3. For every populated field whose HL7 dataType
    /// matches a `CompositeOverride` in the profile, evaluate two
    /// sub-rule tracks against each populated repetition:
    ///
    /// 1. **`requiredComponents`** (v0.5-S5-B-3) — each listed
    ///    component must be populated when the field is populated.
    ///    Used for HL7au:00044.1.2 (CX-4) / 00044.1.3 (CX-5).
    /// 2. **`pairRules`** (v0.5-S5-B-2) — pair-conditional rules.
    ///    Used for HL7au:00044.4/5/6 (CE/CNE/CWE).
    ///
    /// Both tracks emit `.profileConstraintViolation(localeRule:)`
    /// with the override's spec citation.
    private func checkProfileCompositeOverrides(
        profile: Profile,
        fieldGrammar: FieldGrammar,
        field: Field,
        fieldIndex: Int,
        segment: Segment,
        segmentArrayIndex: Int,
        message: Message,
        segmentID: String,
        segmentIndex: Int,
        issues: inout [ValidationIssue]
    ) {
        // M6-B-7: OBX-5's grammar dataType is the variable placeholder
        // (`varies` from v2.5.1, `*` on the pre-v2.5 tables) — its
        // EFFECTIVE type is whatever OBX-2 names at runtime. Resolving
        // it here is what makes the ED/RP datatype points
        // (HL7au:00044.10/.11) reachable at all: no field declares ED
        // or RP statically except CER-6.
        let effectiveDataType = effectiveDataType(of: fieldGrammar, in: segment)
        guard let composite = profile.compositeOverrides.first(where: {
            $0.dataType == effectiveDataType
        }) else { return }
        // M6-D4: the whole override is scoped to the message types its
        // conformance points name. No gate means "every message".
        if let gate = composite.condition, !gate.isEmpty {
            guard conditionTriggers(
                gate,
                in: segment,
                segmentIndex: segmentArrayIndex,
                message: message,
                currentSegmentID: segmentID
            ) else { return }
        }

        for repetition in field.repetitions where isRepetitionPopulated(repetition) {
            // Track 1: required-components (v0.5-S5-B-3).
            for requirement in composite.requiredComponents {
                if let gate = requirement.condition, !gate.isEmpty,
                   !conditionTriggers(gate, in: segment, segmentIndex: segmentArrayIndex,
                                      message: message, currentSegmentID: segmentID) {
                    continue
                }
                // P3-4: a restated base rule defers to the base check where
                // the grammar version's composite already requires it.
                // `message` is the grammar-version copy made in `validate`.
                // Only defer when that base check actually runs
                // (`options.checkComponentGrammar`, gating `checkComponents`
                // above): under `.lenient` it doesn't, so yielding here
                // would silently drop the finding altogether (P3-5).
                //
                // The lookup must key on `fieldGrammar.dataType` — the
                // field's STATIC declared datatype — not `effectiveDataType`:
                // `checkComponents` (the base check this defers to) keys on
                // that same static type. On OBX-5 the static type is always
                // the "varies" placeholder, which has no component grammar,
                // so the base check never fires there regardless of the
                // effective type; deferring on `effectiveDataType` would
                // silently suppress a future OBX-5-eligible `yieldsToBase`
                // requirement (P3-5 fix round 1).
                if options.checkComponentGrammar, requirement.yieldsToBase, requirement.subcomponent == nil,
                   requiredComponents(forCompositeCode: fieldGrammar.dataType, segmentID: segmentID,
                                      fieldIndex: fieldIndex, version: message.version)
                       .contains(where: { $0.index == requirement.component }) {
                    continue
                }
                if isComponentPopulated(repetition,
                                        componentIndex: requirement.component,
                                        subcomponentIndex: requirement.subcomponent) {
                    continue
                }
                let location = IssueLocation(
                    segmentID: segmentID,
                    segmentIndex: segmentIndex,
                    fieldIndex: fieldIndex,
                    componentIndex: requirement.component
                )
                let citation = requirement.specCitation
                    ?? "\(profile.locale.rawValue):\(effectiveDataType).\(requirement.component)"
                appendProfileIssue(
                    citation: citation,
                    location: location,
                    message: "AU profile rule violated at \(location.pathDescription): \(effectiveDataType)-\(requirement.component) must be populated when \(effectiveDataType) field is populated (\(citation))",
                    into: &issues
                )
            }
            // Track 2: pair-conditional rules (v0.5-S5-B-2).
            for rule in composite.pairRules {
                let ifPopulated = isComponentPopulated(repetition, componentIndex: rule.ifComponent)
                let triggered = (rule.condition == .populated) == ifPopulated
                guard triggered else { continue }

                let thenPopulated = isComponentPopulated(repetition, componentIndex: rule.thenComponent)
                let satisfied = (rule.requirement == .mustBePopulated) == thenPopulated
                guard !satisfied else { continue }

                let location = IssueLocation(
                    segmentID: segmentID,
                    segmentIndex: segmentIndex,
                    fieldIndex: fieldIndex,
                    componentIndex: rule.thenComponent
                )
                let citation = rule.specCitation
                    ?? "\(profile.locale.rawValue):\(effectiveDataType).\(rule.thenComponent)"
                let condDesc = rule.condition == .populated ? "is populated" : "is empty"
                let reqDesc = rule.requirement == .mustBePopulated ? "must be populated" : "must be empty"
                appendProfileIssue(
                    citation: citation,
                    location: location,
                    message: "AU profile rule violated at \(location.pathDescription): \(effectiveDataType)-\(rule.thenComponent) \(reqDesc) when \(effectiveDataType)-\(rule.ifComponent) \(condDesc) (\(citation))",
                    into: &issues
                )
            }
            // Track 3: component-value inequality (v0.13, ADR-011).
            // Fires when both named components are populated and carry
            // the same (first-subcomponent) value.
            for rule in composite.componentInequalities {
                guard isComponentPopulated(repetition, componentIndex: rule.componentA),
                      isComponentPopulated(repetition, componentIndex: rule.componentB)
                else { continue }
                let valueA = valueSetScalarValue(in: repetition, component: rule.componentA, subcomponent: nil)
                let valueB = valueSetScalarValue(in: repetition, component: rule.componentB, subcomponent: nil)
                guard valueA == valueB else { continue }
                let location = IssueLocation(
                    segmentID: segmentID,
                    segmentIndex: segmentIndex,
                    fieldIndex: fieldIndex,
                    componentIndex: rule.componentB
                )
                let citation = rule.specCitation
                    ?? "\(profile.locale.rawValue):\(effectiveDataType).\(rule.componentA)!=\(rule.componentB)"
                appendProfileIssue(
                    citation: citation,
                    location: location,
                    message: "AU profile rule violated at \(location.pathDescription): \(effectiveDataType)-\(rule.componentA) and \(effectiveDataType)-\(rule.componentB) must differ but both are \"\(valueA)\" (\(citation))",
                    into: &issues
                )
            }
            // Track 4: value-conditional denylist (v0.13, ADR-011).
            // Fires when the named component carries a denied value and
            // the optional message-context gate (if set) evaluates true.
            for rule in composite.valueConditionals {
                if let gate = rule.condition, !gate.isEmpty {
                    guard conditionTriggers(
                        gate,
                        in: segment,
                        segmentIndex: segmentArrayIndex,
                        message: message,
                        currentSegmentID: segmentID
                    ) else { continue }
                }
                let value = valueSetScalarValue(in: repetition, component: rule.component, subcomponent: nil)
                guard rule.deniedValues.contains(value) else { continue }
                let location = IssueLocation(
                    segmentID: segmentID,
                    segmentIndex: segmentIndex,
                    fieldIndex: fieldIndex,
                    componentIndex: rule.component
                )
                let citation = rule.specCitation
                    ?? "\(profile.locale.rawValue):\(effectiveDataType).\(rule.component)"
                appendProfileIssue(
                    citation: citation,
                    location: location,
                    message: "AU profile rule violated at \(location.pathDescription): \(effectiveDataType)-\(rule.component) must not be \"\(value)\" (\(citation))",
                    into: &issues
                )
            }
            // Track 4b (M33): literal-shape restrictions, the composite twin
            // of the FieldOverride track M32 added. Emptiness policy is the
            // rule's own (`ComponentPattern.allowEmpty`).
            for pattern in composite.componentPatterns {
                if let gate = pattern.condition, !gate.isEmpty,
                   !conditionTriggers(gate, in: segment, segmentIndex: segmentArrayIndex,
                                      message: message, currentSegmentID: segmentID) {
                    continue
                }
                let actual = valueSetScalarValue(in: repetition, component: pattern.component, subcomponent: nil)
                guard let failure = pattern.failure(for: actual) else { continue }
                let location = IssueLocation(
                    segmentID: segmentID,
                    segmentIndex: segmentIndex,
                    fieldIndex: fieldIndex,
                    componentIndex: pattern.component
                )
                let citation = pattern.specCitation
                    ?? "\(profile.locale.rawValue):\(effectiveDataType).\(pattern.component)"
                appendProfileIssue(
                    citation: citation,
                    location: location,
                    message: "AU profile shape rule violated at \(location.pathDescription): \(failure) (\(citation))",
                    into: &issues
                )
            }
            // Track 5: component value sets (allow lists) — M6-B-5.
            // POPULATED-ONLY: an empty (sub)component does not fire;
            // presence is track 1's job, and firing here too would
            // double-report every missing component.
            for valueSet in composite.componentValueSets {
                if let gate = valueSet.condition, !gate.isEmpty {
                    guard conditionTriggers(
                        gate,
                        in: segment,
                        segmentIndex: segmentArrayIndex,
                        message: message,
                        currentSegmentID: segmentID
                    ) else { continue }
                }
                let value = valueSetScalarValue(
                    in: repetition,
                    component: valueSet.component,
                    subcomponent: valueSet.subcomponent
                )
                guard !value.isEmpty, !valueSet.allows(value) else { continue }
                let location = IssueLocation(
                    segmentID: segmentID,
                    segmentIndex: segmentIndex,
                    fieldIndex: fieldIndex,
                    componentIndex: valueSet.component
                )
                let citation = valueSet.specCitation
                    ?? "\(profile.locale.rawValue):\(effectiveDataType).\(valueSet.component)"
                appendProfileIssue(
                    citation: citation,
                    location: location,
                    message: "AU profile value-set rule violated at \(location.pathDescription): \(effectiveDataType)-\(valueSet.component) value \"\(value)\" is not in the allowed set (\(citation))",
                    into: &issues
                )
            }
            // Track 6: per-repetition key⇒value correspondences (M6-B-8).
            checkCorrespondences(
                composite.componentCorrespondences,
                repetition: repetition,
                dataTypeLabel: effectiveDataType,
                segment: segment,
                segmentArrayIndex: segmentArrayIndex,
                message: message,
                segmentID: segmentID,
                occurrence: segmentIndex,
                fieldIndex: fieldIndex,
                profile: profile,
                issues: &issues
            )
            // Track 7 (M6-B-9, HL7au:00044.8.1): a timestamp with
            // hour-or-greater precision (≥10 leading digits) must carry
            // a +/-ZZZZ offset. Date-only values skip — the TS section
            // conditions the offset on time being transmitted. Only
            // offset PRESENCE is checkable; correctness is not.
            if let citation = composite.timezoneRequiredCitation {
                let value = valueSetScalarValue(in: repetition, component: 1, subcomponent: nil)
                let digits = value.prefix(while: \.isNumber)
                let tail = value.dropFirst(digits.count)
                let hasOffset = (tail.first == "+" || tail.first == "-")
                    || tail.contains("+") || tail.contains("-")
                if digits.count >= 10, !hasOffset {
                    let location = IssueLocation(
                        segmentID: segmentID,
                        segmentIndex: segmentIndex,
                        fieldIndex: fieldIndex,
                        componentIndex: 1
                    )
                    appendProfileIssue(
                        citation: citation,
                        location: location,
                        message: "AU profile rule violated at \(location.pathDescription): a timestamp with hour-or-greater precision must carry a +/-ZZZZ timezone offset; got \"\(value)\" (\(citation))",
                        into: &issues
                    )
                }
            }
        }
    }

    /// M6-B-9 (HL7au:000028 / 000028.2): every populated occurrence of
    /// the named field must carry a distinct key across the message.
    private func checkUniquenessRules(
        profile: Profile,
        message: Message,
        issues: inout [ValidationIssue]
    ) {
        for rule in profile.uniquenessRules {
            if let gate = rule.applicableWhen, !gate.isEmpty {
                guard let first = message.segments.first else { continue }
                guard conditionTriggers(
                    gate, in: first, segmentIndex: 0,
                    message: message, currentSegmentID: first.segmentID
                ) else { continue }
            }
            var seen: [String: Int] = [:]   // key -> first occurrence
            var occurrence = 0
            for segment in message.segments where segment.segmentID == rule.segmentID {
                occurrence += 1
                guard let field = segment.field(rule.fieldIndex),
                      let rep = field.repetitions.first else { continue }
                let key = rep.components.indices.contains(rule.component - 1)
                    ? (rep.components[rule.component - 1].subcomponents.first?.value ?? "")
                    : ""
                guard !key.isEmpty else { continue }
                if let firstOccurrence = seen[key] {
                    let citation = rule.specCitation
                        ?? "\(profile.locale.rawValue):unique:\(rule.segmentID)-\(rule.fieldIndex)"
                    let location = IssueLocation(
                        segmentID: rule.segmentID,
                        segmentIndex: occurrence,
                        fieldIndex: rule.fieldIndex,
                        componentIndex: rule.component
                    )
                    appendProfileIssue(
                        citation: citation,
                        location: location,
                        message: "AU profile uniqueness rule violated at \(location.pathDescription): value \"\(key)\" already used by \(rule.segmentID)[\(firstOccurrence)]-\(rule.fieldIndex) (\(citation))",
                        into: &issues
                    )
                } else {
                    seen[key] = occurrence
                }
            }
        }
    }

    /// An ORC/OBR field pair the base spec declares to be the SAME data
    /// element (shared HL7 ITEM number — the spec's own identity
    /// assertion). M8-B1/B2.
    private struct OrcObrPair {
        let orcField: Int
        let obrField: Int
        let name: String
        let item: String
        /// `nil` = every version. The parent pair moves between OBR
        /// positions across versions, so its two legs are enumerated.
        let versions: Set<Version>?
    }

    /// M8-B1/B2: the pairs and their citations.
    /// - ORC-2/OBR-2 (00216), ORC-3/OBR-3 (00217): v2.4 §4.5.1.2 "If
    ///   both fields ... are valued, they must contain the same value"
    ///   ("This rule is the same for other identical fields in the ORC
    ///   and OBR", §4.5.1.3); v2.8.2 §4.5.3.2 "This field is identical
    ///   to ORC-2-Placer Order Number."
    /// - ORC-12/OBR-16 (00226, XCN, repeats): v2.4 §4.5.1.12 "If both,
    ///   ORC-12 Ordering provider and OBR-16 Ordering Provider are
    ///   valued, then both must contain the same value." Both print
    ///   item 00226 on every version (B usage from v2.7 — deprecated
    ///   but accepted, so the rule still applies when populated).
    /// - Parent (EIP): v2.3–v2.6 pair ORC-8 with OBR-29 (both named
    ///   "Parent"; v2.4 §4.5.1.8: "ORC-8-parent is the same as
    ///   OBR-29-parent"). v2.8.2 repurposes OBR-29 (item 00261, Parent
    ///   Result Observation Identifier) and pairs ORC-8 with OBR-54:
    ///   "Condition: Where the message has matching ORC/OBR pairs,
    ///   ORC-8 and OBR-54 Must carry the same value" (§4.5.1.8);
    ///   "neither one is the same as OBR-29". A `.v2_8` message is
    ///   validated as v2.8.2 (ADR-018), so it gets the ORC-8/OBR-54 leg.
    ///   v2.7.1 already repurposes OBR-29 (CH04 §4.5.3.29 p65, Parent
    ///   Result Observation Identifier) and §4.5.3.54 p74 prints "ORC-8
    ///   and OBR-54 must carry the same value"; its §4.5.1.8 p37 prints
    ///   "ORC-8 and OBR-?? Must carry the same value", a text defect
    ///   resolved by §4.5.3.54 and by the "ORC-8/OBR-54 – parent order"
    ///   line both sections print.
    /// - ORC-7/OBR-27 (TQ) is deliberately ABSENT: the v2.4 prose says
    ///   the pair "should be valued exactly the same" — advisory, not
    ///   normative — and both fields are withdrawn (`W`) from v2.7.
    ///   An error-level rule would over-read (req #4). Recorded in
    ///   `m7-adrm-prose-sweep.md` §C.
    private static let orcObrEqualityPairs: [OrcObrPair] = [
        OrcObrPair(orcField: 2, obrField: 2, name: "Placer Order Number", item: "00216", versions: nil),
        OrcObrPair(orcField: 3, obrField: 3, name: "Filler Order Number", item: "00217", versions: nil),
        OrcObrPair(orcField: 12, obrField: 16, name: "Ordering Provider", item: "00226", versions: nil),
        OrcObrPair(orcField: 8, obrField: 29, name: "Parent", item: "00222",
                   versions: [.v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6]),
        OrcObrPair(orcField: 8, obrField: 54, name: "Parent Order", item: "00222",
                   versions: [.v2_7_1, .v2_8_2]),
    ]

    /// M8-B1/B2: within each ORC/OBR group, a paired field populated on
    /// BOTH segments must carry the same value (whole-field wire
    /// comparison including repetitions). Empty on either side skips:
    /// the presence half of the prose ("if not present in the ORC, it
    /// must be present in the associated OBR") is
    /// message-shape-dependent (ORU needs no ORC at all) and is not
    /// asserted here. Version-gated pairs (parent) apply only where
    /// their version set says. Each ORC's OBR is its associated segment
    /// (`Message.associatedIndex`): its own group with spans (P8b-17), else
    /// the first OBR in the ORC walk.
    private func checkOrcObrPairEquality(
        message: Message,
        issues: inout [ValidationIssue]
    ) {
        var obrOccurrence = 0
        var obrOccurrenceByIndex: [Int: Int] = [:]
        for (index, segment) in message.segments.enumerated() where segment.segmentID == "OBR" {
            obrOccurrence += 1
            obrOccurrenceByIndex[index] = obrOccurrence
        }
        for (index, segment) in message.segments.enumerated() where segment.segmentID == "ORC" {
            guard let obrIndex = message.associatedIndex("OBR", fromIndex: index) else { continue }
            let obr = message.segments[obrIndex]
            for pair in Self.orcObrEqualityPairs {
                if let versions = pair.versions, !versions.contains(message.version.grammarVersion) { continue }
                guard let orcValue = flattenedField(segment.field(pair.orcField)),
                      let obrValue = flattenedField(obr.field(pair.obrField)),
                      orcValue != obrValue
                else { continue }
                let location = IssueLocation(
                    segmentID: "OBR",
                    segmentIndex: obrOccurrenceByIndex[obrIndex] ?? 1,
                    fieldIndex: pair.obrField,
                    componentIndex: nil
                )
                issues.append(ValidationIssue(
                    severity: .error,
                    code: .pairedFieldMismatch(item: pair.item),
                    location: location,
                    message: "ORC-\(pair.orcField) and OBR-\(pair.obrField) are the same data element (\(pair.name), item \(pair.item)) but carry different values in one order group: ORC has \"\(orcValue)\", OBR has \"\(obrValue)\" (HL7 v2.4 §4.5.1; v2.8.2 §4.5.3)"
                ))
            }
        }
    }

    /// Flatten a whole field to wire form for whole-field comparison,
    /// normalising trailing empty components/subcomponents (`A^B` and
    /// `A^B^^` carry the same value) and dropping empty repetitions.
    /// Returns `nil` when the field is absent or entirely empty.
    /// `Repetition.stringValue` cannot be used here — it has
    /// strict-scalar semantics and returns `nil` for multi-component
    /// values. Repetition-aware since M8-B2: the XCN pair
    /// (ORC-12/OBR-16) repeats, and "both must contain the same value"
    /// covers every repetition. M8-B1/B2.
    private func flattenedField(_ field: Field?) -> String? {
        guard let field else { return nil }
        let repetitions = field.repetitions.compactMap { rep -> String? in
            var components = rep.components.map { component -> String in
                var subs = component.subcomponents.map(\.value)
                while subs.count > 1, subs.last?.isEmpty == true { subs.removeLast() }
                return subs.joined(separator: "&")
            }
            while components.count > 1, components.last?.isEmpty == true { components.removeLast() }
            let joined = components.joined(separator: "^")
            return joined.isEmpty ? nil : joined
        }
        return repetitions.isEmpty ? nil : repetitions.joined(separator: "~")
    }

    /// M7-P3: scan every populated subcomponent for prohibited escape
    /// sequences (ADRM-prose:P-4 — the ADRM's §3.1.1.5/.6 variances
    /// remove \X...\, \C...\ and \M...\ from the escape repertoire).
    ///
    /// The parser DECODES escapes into the stored value (\X0D\ becomes
    /// a literal CR; \E\ becomes a literal backslash), so the stored
    /// value cannot be scanned directly — a decoded \E\ next to a
    /// literal X would false-positive, and a decoded \X..\ is
    /// invisible. `EscapeSequences.encode` restores the exact wire form
    /// (the round-trip is byte-for-byte; verified for all three
    /// families plus \E\-adjacency), so the scan runs on the
    /// RE-ENCODED value. MSH-1 / MSH-2 are exempt (they carry the
    /// delimiter literals).
    /// OBX-4 sub-ID tree rules (M12; see `SubIDTreeRule`). Per observation group — the
    /// OBX run after each OBR — find the header OBX; without one the group is skipped.
    /// Then every other OBX whose sub-ID is the root or lies under it must instantiate a
    /// row of the element table, and must not instantiate a virtual row.
    private func checkSubIDTrees(
        profile: Profile,
        message: Message,
        issues: inout [ValidationIssue]
    ) {
        guard !profile.subIDTrees.isEmpty, let first = message.segments.first else { return }
        let active = profile.subIDTrees.filter { rule in
            guard let gate = rule.applicableWhen, !gate.isEmpty else { return true }
            return conditionTriggers(gate, in: first, segmentIndex: 0, message: message, currentSegmentID: first.segmentID)
        }
        guard !active.isEmpty else { return }

        // Observation groups, each OBX paired with its 1-based OBX occurrence in the message.
        var groups: [[(segment: Segment, occurrence: Int)]] = [[]]
        var obxCount = 0
        for segment in message.segments {
            if segment.segmentID == "OBR" { groups.append([]) }
            if segment.segmentID == "OBX" {
                obxCount += 1
                groups[groups.count - 1].append((segment, obxCount))
            }
        }
        func subID(_ segment: Segment) -> String { segment.field(4)?.stringValue ?? "" }
        func isDottedDecimal(_ s: String) -> Bool {
            !s.isEmpty && s.split(separator: ".", omittingEmptySubsequences: false)
                .allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        }

        for rule in active {
            for group in groups {
                guard let header = group.first(where: {
                    $0.segment.field(3)?.first?.components.first?.stringValue == rule.headerObservationID
                }) else { continue }
                let root = subID(header.segment)
                func at(_ occurrence: Int) -> IssueLocation {
                    IssueLocation(segmentID: "OBX", segmentIndex: occurrence, fieldIndex: 4, componentIndex: nil)
                }
                guard isDottedDecimal(root) else {
                    appendProfileIssue(
                        citation: rule.headerShapeCitation, location: at(header.occurrence),
                        message: "AU profile rule violated at \(at(header.occurrence).pathDescription): the template header's OBX-4 sub-ID \"\(root)\" is not a dotted decimal value.",
                        into: &issues)
                    continue   // no usable root: the group's other sub-IDs cannot be judged
                }
                for entry in group where entry.occurrence != header.occurrence {
                    let value = subID(entry.segment)
                    guard value == root || value.hasPrefix(root + ".") else { continue }
                    let relative = rule.tableRoot + value.dropFirst(root.count)
                    let location = at(entry.occurrence)
                    guard let element = VMRImplementationTable.element(matching: relative, in: rule.elements) else {
                        appendProfileIssue(
                            citation: rule.unknownPathCitation, location: location,
                            message: "AU profile rule violated at \(location.pathDescription): sub-ID \"\(value)\" shares the template root \"\(root)\" but matches no element of the implementation table.",
                            into: &issues)
                        continue
                    }
                    if element.kind == rule.virtualKind {
                        appendProfileIssue(
                            citation: rule.virtualRowCitation, location: location,
                            message: "AU profile rule violated at \(location.pathDescription): sub-ID \"\(value)\" is the \(element.kind) row '\(element.name)', which is virtual and must not be written as an OBX.",
                            into: &issues)
                    }
                }
            }
        }
    }

    private func checkEscapeProhibitions(
        profile: Profile,
        message: Message,
        issues: inout [ValidationIssue]
    ) {
        guard !profile.escapeProhibitions.isEmpty,
              let first = message.segments.first else { return }
        let active = profile.escapeProhibitions.filter { rule in
            guard let gate = rule.applicableWhen, !gate.isEmpty else { return true }
            return conditionTriggers(
                gate, in: first, segmentIndex: 0,
                message: message, currentSegmentID: first.segmentID
            )
        }
        guard !active.isEmpty else { return }
        var occurrenceBySegmentID: [String: Int] = [:]
        for segment in message.segments {
            let occurrence = (occurrenceBySegmentID[segment.segmentID] ?? 0) + 1
            occurrenceBySegmentID[segment.segmentID] = occurrence
            for (fieldIndex, field) in segment.fields.enumerated() where fieldIndex >= 1 {
                if segment.segmentID == "MSH", fieldIndex <= 2 { continue }
                for repetition in field.repetitions {
                    for component in repetition.components {
                        for subcomponent in component.subcomponents {
                            let wireValue = EscapeSequences.encode(
                                subcomponent.value,
                                encoding: message.encodingCharacters
                            )
                            let escape = String(message.encodingCharacters.escapeCharacter)
                            guard wireValue.contains(escape) else { continue }
                            for rule in active where containsProhibitedEscape(wireValue, lead: rule.lead, escape: escape) {
                                let citation = rule.specCitation
                                    ?? "\(profile.locale.rawValue):escape:\\\(rule.lead)"
                                let location = IssueLocation(
                                    segmentID: segment.segmentID,
                                    segmentIndex: occurrence,
                                    fieldIndex: fieldIndex,
                                    componentIndex: nil
                                )
                                appendProfileIssue(
                                    citation: citation,
                                    location: location,
                                    message: "AU profile rule violated at \(location.pathDescription): the \\\(rule.lead)...\\ escape sequence must not be used (\(citation))",
                                    into: &issues
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    /// True when the wire-form `value` contains a complete
    /// `\<lead>...\` sequence.
    ///
    /// Splitting on the escape delimiter alternates literal and escape
    /// content: in `a\X0D\b` the parts are ["a", "X0D", "b"] and every
    /// odd index is escape content. A naive substring search for `\X`
    /// would false-positive on `...\E\X...`, where the `\` is the
    /// CLOSING delimiter of `\E\` and `X` is literal text (req #4). An
    /// odd-indexed part that is also the last part lacks its closing
    /// delimiter — unterminated, skip.
    private func containsProhibitedEscape(_ value: String, lead: String, escape: String) -> Bool {
        let parts = value.components(separatedBy: escape)
        guard parts.count >= 3 else { return false }
        for index in stride(from: 1, to: parts.count - 1, by: 2)
            where parts[index].hasPrefix(lead) {
            return true
        }
        return false
    }

    /// M6-B-8: evaluate key⇒value correspondence rules against one
    /// repetition. Keys the map does not state SKIP (fail-safe — the
    /// source tables enumerate correspondences for named keys only),
    /// unless the rule gives `unlistedKeyValues` (P12 S2-2);
    /// an EMPTY value component skips too (presence belongs to the
    /// required-component / membership rules, and firing here as well
    /// would double-report). Case-insensitive on both sides: the
    /// ADRM's own examples mix `TEXT^RTF` and `text^html`.
    private func checkCorrespondences(
        _ rules: [ComponentCorrespondence],
        repetition: Repetition,
        dataTypeLabel: String,
        segment: Segment,
        segmentArrayIndex: Int,
        message: Message,
        segmentID: String,
        occurrence: Int,
        fieldIndex: Int,
        profile: Profile,
        issues: inout [ValidationIssue]
    ) {
        for rule in rules {
            if let gate = rule.condition, !gate.isEmpty {
                guard conditionTriggers(
                    gate,
                    in: segment,
                    segmentIndex: segmentArrayIndex,
                    message: message,
                    currentSegmentID: segmentID
                ) else { continue }
            }
            let key = valueSetScalarValue(
                in: repetition, component: rule.keyComponent, subcomponent: nil)
            guard !key.isEmpty else { continue }
            let lowerKey = key.lowercased()
            let mapped: [String]
            if let listed = rule.map[lowerKey] {
                mapped = listed
            } else if let unlisted = rule.unlistedKeyValues, !rule.exemptKeys.contains(lowerKey) {
                mapped = unlisted
            } else {
                continue
            }
            let value = valueSetScalarValue(
                in: repetition, component: rule.valueComponent, subcomponent: nil)
            guard !value.isEmpty else { continue }
            let listed = mapped.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame })
            let expectation: String
            switch rule.valueRule {
            case .allowed:
                guard !listed else { continue }
                expectation = "in [\(mapped.joined(separator: ", "))]"
            case .forbidden(let prefixes):
                let lowered = value.lowercased()
                guard listed || prefixes.contains(where: { lowered.hasPrefix($0.lowercased()) })
                else { continue }
                expectation = "not in [\(mapped.joined(separator: ", "))] and not beginning with [\(prefixes.joined(separator: ", "))]"
            }
            let location = IssueLocation(
                segmentID: segmentID,
                segmentIndex: occurrence,
                fieldIndex: fieldIndex,
                componentIndex: rule.valueComponent
            )
            let citation = rule.specCitation
                ?? "\(profile.locale.rawValue):\(dataTypeLabel).\(rule.keyComponent)=>\(rule.valueComponent)"
            appendProfileIssue(
                citation: citation,
                location: location,
                message: "AU profile correspondence rule violated at \(location.pathDescription): \(dataTypeLabel)-\(rule.keyComponent) \"\(key)\" requires \(dataTypeLabel)-\(rule.valueComponent) \(expectation) but got \"\(value)\" (\(citation))",
                into: &issues
            )
        }
    }

    /// AU profile override dispatch. For each populated field that has
    /// a `FieldOverride` in the loaded profile, check the override's
    /// `requiredComponents` rule: every listed 1-based component index
    /// must be populated in every populated repetition. Failures emit
    /// `.profileConstraintViolation(localeRule:)`.
    ///
    /// v0.5-S5-B-1 ships the OBR-2/3 + ORC-2/3/4 EI-completeness rules
    /// from HL7au:000003 / 000004.1 / 000005 / 000006 / 000007. The
    /// `localeRule` value carries the HL7au identifier so consumers
    /// can attribute the failure precisely. See
    /// `Sources/HL7v2Kit/Locale/Profile+au_adrm_2021.swift`.
    private func checkProfileFieldOverrides(
        profile: Profile,
        fieldGrammar: FieldGrammar,
        field: Field,
        fieldIndex: Int,
        segment: Segment,
        segmentArrayIndex: Int,
        message: Message,
        segmentID: String,
        occurrence: Int,
        issues: inout [ValidationIssue]
    ) {
        guard let override = profile.fieldOverrides.first(where: {
            $0.segmentID == segmentID && $0.fieldIndex == fieldGrammar.index
        }) else { return }
        guard !override.requiredComponents.isEmpty || !override.componentValueSets.isEmpty
                || !override.componentPatterns.isEmpty else { return }
        // M6-D3: `requiredComponents` shares the override-level gate with
        // `profileUsage`. `componentValueSets` are gated individually
        // below — they can be scoped more narrowly than their field.
        let requiredComponents: [Int]
        if let gate = override.condition, !gate.isEmpty, !conditionTriggers(
            gate, in: segment, segmentIndex: segmentArrayIndex,
            message: message, currentSegmentID: segmentID
        ) {
            requiredComponents = []
        } else {
            requiredComponents = override.requiredComponents
        }
        guard !requiredComponents.isEmpty || !override.componentValueSets.isEmpty else { return }

        for repetition in field.repetitions where isRepetitionPopulated(repetition) {
            // Track 1 (v0.5-S5-B-1): required-component narrowings.
            for componentIndex in requiredComponents {
                if isComponentPopulated(repetition, componentIndex: componentIndex) {
                    continue
                }
                let location = IssueLocation(
                    segmentID: segmentID,
                    segmentIndex: occurrence,
                    fieldIndex: fieldIndex,
                    componentIndex: componentIndex
                )
                let citation = override.specCitation
                    ?? "\(profile.locale.rawValue):\(segmentID)-\(fieldGrammar.index).\(componentIndex)"
                appendProfileIssue(
                    citation: citation,
                    location: location,
                    message: "AU profile rule violated at \(location.pathDescription): \(fieldGrammar.dataType) component \(componentIndex) must be populated when \(segmentID)-\(fieldGrammar.index) ('\(fieldGrammar.name)') is populated (\(citation))",
                    into: &issues
                )
            }
            // Track 2 (v0.5-S5-C): per-component value-set narrowings.
            // v0.8 (ADR-009): each value-set may declare an optional
            // condition gating its application + an optional
            // subcomponent index for granular reads.
            for valueSet in override.componentValueSets {
                // Conditional gating (ADR-009). If the predicate is
                // false (or unresolvable — fail-safe per ADR-008),
                // skip this value-set entirely.
                if let condition = valueSet.condition, !condition.isEmpty {
                    let gated = conditionTriggers(
                        condition,
                        in: segment,
                        segmentIndex: segmentArrayIndex,
                        message: message,
                        currentSegmentID: segmentID
                    )
                    if !gated { continue }
                }
                let actual = valueSetScalarValue(
                    in: repetition,
                    component: valueSet.component,
                    subcomponent: valueSet.subcomponent
                )
                if valueSet.allows(actual) { continue }
                // P12 S2-2: a table the caller extends locally (0363 vendors).
                let extended = valueSet.localTableExtension
                    .flatMap { options.localTableExtensions[$0] }?.sorted() ?? []
                if extended.contains(actual) { continue }
                let location = IssueLocation(
                    segmentID: segmentID,
                    segmentIndex: occurrence,
                    fieldIndex: fieldIndex,
                    componentIndex: valueSet.component
                )
                let citation = valueSet.specCitation
                    ?? "\(profile.locale.rawValue):\(segmentID)-\(fieldGrammar.index).\(valueSet.component)"
                let allowedList = (valueSet.allowedValues + extended).map { "\"\($0)\"" }.joined(separator: ", ")
                let pathSuffix = valueSet.subcomponent.map { ".\($0)" } ?? ""
                appendProfileIssue(
                    citation: citation,
                    location: location,
                    message: "AU profile value-set rule violated at \(location.pathDescription)\(pathSuffix): expected one of [\(allowedList)] but got \"\(actual)\" (\(citation))",
                    into: &issues
                )
            }
            // Track 2b (M32): literal-shape restrictions. An EMPTY
            // component fails, unlike the composite value-set track: a
            // pattern states a shape the spec requires, and the rules that
            // use one (HL7au:00044.2.2 under a NASH assertion, where
            // HL7au:000043.1 spells MSH-4 out as
            // "name^1.2.36.1.2001.1003.0.<hpio>^ISO") are violated by a
            // missing identifier exactly as by a malformed one. Scope with
            // `condition`, not with emptiness. Matches the FieldOverride
            // value-set track, which does not skip empty either.
            for pattern in override.componentPatterns {
                if let gate = pattern.condition, !gate.isEmpty,
                   !conditionTriggers(gate, in: segment, segmentIndex: segmentArrayIndex,
                                      message: message, currentSegmentID: segmentID) {
                    continue
                }
                let actual = valueSetScalarValue(in: repetition, component: pattern.component, subcomponent: nil)
                guard let failure = pattern.failure(for: actual) else { continue }
                let location = IssueLocation(
                    segmentID: segmentID,
                    segmentIndex: occurrence,
                    fieldIndex: fieldIndex,
                    componentIndex: pattern.component
                )
                let citation = pattern.specCitation
                    ?? "\(profile.locale.rawValue):\(segmentID)-\(fieldGrammar.index).\(pattern.component)"
                appendProfileIssue(
                    citation: citation,
                    location: location,
                    message: "AU profile shape rule violated at \(location.pathDescription): \(failure) (\(citation))",
                    into: &issues
                )
            }
            // Track 3 (M6-B-8): per-repetition key⇒value correspondences.
            checkCorrespondences(
                override.componentCorrespondences,
                repetition: repetition,
                dataTypeLabel: "\(segmentID)-\(fieldGrammar.index)",
                segment: segment,
                segmentArrayIndex: segmentArrayIndex,
                message: message,
                segmentID: segmentID,
                occurrence: occurrence,
                fieldIndex: fieldIndex,
                profile: profile,
                issues: &issues
            )
        }
    }

    /// Resolve the scalar string for a value-set comparison. When
    /// `subcomponent` is nil (default), reads the named component's
    /// FIRST subcomponent — the v0.5-S5-C behaviour. When set, reads
    /// the named subcomponent specifically. Returns the empty string
    /// when the component or subcomponent is out of bounds — matches
    /// "empty / missing" so a fail-safe miss surfaces a clear
    /// expected-vs-got message. v0.8 (ADR-009).
    private func valueSetScalarValue(
        in repetition: Repetition,
        component: Int,
        subcomponent: Int?
    ) -> String {
        guard repetition.components.indices.contains(component - 1) else { return "" }
        let comp = repetition.components[component - 1]
        let subIndex = (subcomponent ?? 1) - 1
        guard comp.subcomponents.indices.contains(subIndex) else { return "" }
        return comp.subcomponents[subIndex].value
    }

    /// Profile-usage dispatch — when an override declares the field
    /// is profile-required (`.required`) and the field is empty,
    /// emit `.profileConstraintViolation`. Closes the S5-C scope gap
    /// where MSH-17 / MSH-19 were enforced for VALUE when populated
    /// but not enforced for PRESENCE.
    ///
    /// `.requiredEmpty` (RE) is treated as informational: the spec
    /// says the sender must be able to provide the value if it has
    /// one, but receivers must accept absence — so no violation when
    /// empty. `.notUsed` (X) flags presence (the base
    /// `checkDeprecation` already handles `notSupported` populated;
    /// this path leaves X alone). Other usage codes don't drive a
    /// presence rule.
    private func checkProfileFieldUsage(
        profile: Profile,
        fieldGrammar: FieldGrammar,
        isPopulated: Bool,
        segment: Segment,
        segmentArrayIndex: Int,
        message: Message,
        location: IssueLocation,
        issues: inout [ValidationIssue]
    ) {
        guard let override = profile.fieldOverrides.first(where: {
            $0.segmentID == location.segmentID && $0.fieldIndex == fieldGrammar.index
        }) else { return }
        guard override.profileUsage == .required else { return }
        guard !isPopulated else { return }
        // M6-D3: the usage narrowing only applies to the message types
        // the conformance point names. No gate means "every message".
        if let gate = override.condition, !gate.isEmpty {
            guard conditionTriggers(
                gate,
                in: segment,
                segmentIndex: segmentArrayIndex,
                message: message,
                currentSegmentID: location.segmentID
            ) else { return }
        }

        let citation = override.specCitation
            ?? "\(profile.locale.rawValue):\(location.segmentID)-\(fieldGrammar.index)"
        appendProfileIssue(
            citation: citation,
            location: location,
            message: "AU profile rule violated at \(location.pathDescription): field is profile-required (\(profile.locale.rawValue) usage = R) but missing (\(citation))",
            into: &issues
        )
    }

    private func checkRequired(
        _ grammar: FieldGrammar,
        isPopulated: Bool,
        location: IssueLocation,
        issues: inout [ValidationIssue]
    ) {
        guard grammar.optionality == .required, !isPopulated else { return }
        issues.append(ValidationIssue(
            severity: .error,
            code: .requiredFieldMissing,
            location: location,
            message: "Required field \(location.pathDescription) ('\(grammar.name)') is missing"
        ))
    }

    private func checkDeprecation(
        _ grammar: FieldGrammar,
        location: IssueLocation,
        issues: inout [ValidationIssue]
    ) {
        switch grammar.optionality {
        case .backwardCompat:
            issues.append(ValidationIssue(
                severity: .warning,
                code: .fieldNotSupported,
                location: location,
                message: "Field \(location.pathDescription) ('\(grammar.name)') is deprecated (B) but populated"
            ))
        case .notSupported:
            issues.append(ValidationIssue(
                severity: .warning,
                code: .fieldNotSupported,
                location: location,
                message: "Field \(location.pathDescription) ('\(grammar.name)') is not supported (X) but populated"
            ))
        case .withdrawn:
            issues.append(ValidationIssue(
                severity: .warning,
                code: .fieldNotSupported,
                location: location,
                message: "Field \(location.pathDescription) ('\(grammar.name)') was withdrawn from the standard (W) but populated"
            ))
        default:
            return
        }
    }

    private func checkCardinality(
        _ grammar: FieldGrammar,
        field: Field,
        location: IssueLocation,
        issues: inout [ValidationIssue]
    ) {
        let count = field.repetitions.count
        guard count > 1 else { return }
        let severity: IssueSeverity
        let detail: String
        switch grammar.repeatability {
        case .single:
            severity = .error
            detail = "is single-cardinality but has \(count) repetitions"
        case .multiple:
            // P6-4: a printed RP/# bound, severity set by repetitionBoundSeverity (G4).
            // Single-cardinality errors above are unaffected by this option.
            guard let bound = grammar.maxRepetitions, count > bound,
                  let boundSeverity = options.repetitionBoundSeverity else { return }
            severity = boundSeverity
            detail = "allows at most \(bound) repetitions but has \(count)"
        }
        issues.append(ValidationIssue(
            severity: severity,
            code: .cardinalityExceeded,
            location: location,
            message: "Field \(location.pathDescription) ('\(grammar.name)') \(detail)"
        ))
    }

    /// Closed-set check for an `ID`-typed field (M6-O6). Double-gated:
    /// the field's datatype must be `ID` AND the table must be closed
    /// for this version. A repetition whose value is not a bare scalar
    /// is a structure fault, not a table fault — skipped, never misfired.
    /// The datatype a field actually carries. OBX-5's grammar datatype is the variable
    /// placeholder (`varies` from v2.5.1, `*` on the pre-v2.5 tables); its effective type
    /// is whatever OBX-2 names at runtime (M6-B-7). Every other field carries its own.
    private func effectiveDataType(of grammar: FieldGrammar, in segment: Segment) -> String {
        guard segment.segmentID == "OBX", grammar.index == 5,
              ["varies", "*", "Variable"].contains(grammar.dataType),
              let declared = segment.field(2)?.stringValue, !declared.isEmpty else { return grammar.dataType }
        return declared
    }

    /// Component-level code-table check (M10-C / M11, ADR-017). For a field whose datatype
    /// has a component table on the message's version, every populated `ID` component bound
    /// to exactly one closed HL7-defined table must carry one of its codes. A component that
    /// is itself a composite is descended into once (HL7 v2 has no deeper level): the HD in
    /// `CX.4` makes `CX.4.3` a checked universal ID type.
    ///
    /// The same guards as the field-level rule: `IS` and user-defined or open tables are
    /// never enforced; empty and HL7-null values are never checked; a locale's rendering of
    /// the table widens the check and never narrows it. A datatype the version gives no
    /// component grammar (``fieldGrammar(segment:field:dataType:version:)``, which keeps a
    /// primitive primitive, P5-3, and gives a pre-v2.5 `CM` field the components its own
    /// definition prints, P5-6) is not checked. The value of an `ID` component is its first
    /// subcomponent (P6-14; section 2.6.2 a), located at subcomponent 1 when more follow.
    ///
    /// A top-level `CE` component bound to one closed HL7 table (P5-6: OBR-15.1 0070,
    /// OBR-15.4 0163, ERR-1.4 0357, SAC-6 and TCC-3) is checked on its identifier, located at
    /// subcomponent 1, only when its coding system explicitly names that table, compared
    /// case-insensitively; its alternate identifier (CE.4, located at subcomponent 4) likewise
    /// when the alternate coding system CE.6 names it, the alternate components being "defined
    /// analogously" (v2.4 2.9.3.6): "When an HL7 table is used for a CE data type, the name of coding
    /// system component is defined as HL7nnnn where nnnn is the HL7 table number" (v2.3 /
    /// v2.3.1 2.8.3.3, v2.4 2.9.3.3). An empty CE.3 leaves the system unstated and is silent:
    /// the spec's own ERR-1 example sends `X3L` with none, "the locally-established code"
    /// (v2.3 / v2.3.1 2.25.2, v2.4 2.18.2). Any other coding system is not that table, so
    /// OBR-15's "Veterinary medicine may choose the tables supported for the components of
    /// this field" (v2.4 7.4.1.15) stays silent. The rule applies to any CE component a
    /// grammar binds to one closed HL7 table, type-level included (v2.5.1 ELD.4 0357).
    private func checkComponentCodeTables(
        dataType: String,
        field: Field,
        version: Version,
        location: IssueLocation,
        issues: inout [ValidationIssue]
    ) {
        // P6-14: the grammar version, so a 2.8 message reads the v2.8.2 tables directly
        // (validate(_:) already declares it; this keeps the lookup right on its own).
        let version = version.grammarVersion
        guard let grammar = Self.fieldGrammar(segment: location.segmentID, field: location.fieldIndex,
                                              dataType: dataType, version: version) else { return }

        /// The closed table an `ID` entry is bound to, or nil when it is not enforceable.
        func closedTable(_ entry: ComponentGrammar) -> HL7Table? {
            guard entry.dataType == "ID", entry.tables.count == 1,
                  let table = HL7TableRegistry.table(entry.tables[0], version: version), table.isClosed else { return nil }
            return table
        }
        /// The closed table a `CE` entry is bound to, or nil (P5-6: OBR-15.1 0070, ERR-1.4 0357).
        func closedCodedTable(_ entry: ComponentGrammar) -> HL7Table? {
            guard entry.dataType == "CE", entry.tables.count == 1,
                  let table = HL7TableRegistry.table(entry.tables[0], version: version), table.isClosed else { return nil }
            return table
        }
        func report(_ value: String?, table: HL7Table, name: String, component: Int, subcomponent: Int?, repetition: Int) {
            guard let value, !value.isEmpty, value != "\"\"", !table.contains(value),
                  HL7TableRegistry.table(table.number, locale: locale)?.contains(value) != true,
                  options.localTableExtensions[table.number]?.contains(value) != true else { return }
            let where_ = IssueLocation(segmentID: location.segmentID, segmentIndex: location.segmentIndex,
                                       fieldIndex: location.fieldIndex, componentIndex: component,
                                       subcomponentIndex: subcomponent)
            issues.append(ValidationIssue(
                severity: .error,
                code: .valueNotInTable(table: table.number),
                location: where_,
                message: "Component \(where_.pathDescription) ('\(name)') repetition \(repetition) value \"\(value)\" is not in HL7 Table \(table.number) (\(table.name)) for v\(grammar.version)."
            ))
        }

        for (offset, repetition) in field.repetitions.enumerated() {
            for entry in grammar.components where repetition.components.count >= entry.index {
                let component = repetition.components[entry.index - 1]
                if let table = closedTable(entry) {
                    // P6-14: the value is the first subcomponent (section 2.6.2 a); with
                    // subcomponents after it, the issue is located at that subcomponent and
                    // the rest is reported as extraComponentsInPrimitiveField.
                    let partial = component.subcomponents.dropFirst().contains { !$0.value.isEmpty }
                    report(component.subcomponents.first?.value, table: table, name: entry.name,
                           component: entry.index, subcomponent: partial ? 1 : nil, repetition: offset + 1)
                    continue
                }
                if let table = closedCodedTable(entry) {
                    // A CE names its coding system in CE.3, "HL7nnnn" for an HL7 table. Only
                    // that explicit claim is checked: an unstated system may carry a local code
                    // (the spec's own ERR-1 "X3L"), and another system (OBR-15: "Veterinary
                    // medicine may choose the tables supported for the components of this
                    // field") is not the HL7 table.
                    // The alternate triplet CE.4-6 is "defined analogously" (v2.4 2.9.3.6), so
                    // CE.4 is checked when CE.6 names the table, reported at subcomponent 4.
                    let parts = component.subcomponents.map(\.value)
                    func part(_ i: Int) -> String { parts.count >= i ? parts[i - 1] : "" }
                    for (identifier, system) in [(1, 3), (4, 6)]
                    where part(system).caseInsensitiveCompare("HL7\(table.number)") == .orderedSame {
                        report(part(identifier), table: table, name: entry.name,
                               component: entry.index, subcomponent: identifier, repetition: offset + 1)
                    }
                }
                if let nested = Self.componentGrammar(entry.dataType, version: version) {
                    for inner in nested.components where component.subcomponents.count >= inner.index {
                        guard let table = closedTable(inner) else { continue }
                        report(component.subcomponents[inner.index - 1].value, table: table, name: inner.name,
                               component: entry.index, subcomponent: inner.index, repetition: offset + 1)
                    }
                }
            }
        }
    }

    private func checkCodeTable(
        _ grammar: FieldGrammar,
        tableNumber: String,
        field: Field,
        version: Version,
        location: IssueLocation,
        issues: inout [ValidationIssue]
    ) {
        // A field whose own prose leaves the table open (P2-15) is never checked, even
        // when other fields cite the same table "for valid values".
        guard grammar.dataType == "ID", !grammar.tableOpen,
              let table = HL7TableRegistry.table(tableNumber, version: version),
              table.isClosed else { return }
        for (offset, repetition) in field.repetitions.enumerated() where isRepetitionPopulated(repetition) {
            // P6-13: a primitive field's value is its first component (a recipient ignores
            // the rest, v2.5.1 / v2.8.2 section 2.6.2 a); the extras are reported apart.
            guard let value = Self.primitiveValue(repetition), !value.isEmpty, value != "\"\"",
                  !table.contains(value) else { continue }
            let partial = Self.hasExtraPrimitiveContent(repetition)
            // A localisation may print its own rendering of the table (AU ADRM-2021 back-ports
            // UNICODE UTF-8 into v2.4 Table 0211). It WIDENS the check as a union with the base
            // version's rows, so it can never reject what the message's own version prints;
            // narrowing is the profile's job, not this rule's.
            if HL7TableRegistry.table(tableNumber, locale: locale)?.contains(value) == true { continue }
            // A caller-declared local extension (ValidationOptions.localTableExtensions) also
            // widens the check, same as a locale rendering: every supported version allows an
            // HL7 table to be extended locally (v2.3 / v2.3.1 CH2 sec 2.6.6, v2.4 CH02 sec 2.7.6,
            // v2.5.1 / v2.6 CH02 sec 2.5.3.6, v2.8.2 CH02C 2.C.1.2).
            if options.localTableExtensions[tableNumber]?.contains(value) == true { continue }
            issues.append(ValidationIssue(
                severity: .error,
                code: .valueNotInTable(table: table.number),
                location: partial ? IssueLocation(segmentID: location.segmentID, segmentIndex: location.segmentIndex,
                                                  fieldIndex: location.fieldIndex, componentIndex: 1) : location,
                message: "Field \(location.pathDescription) ('\(grammar.name)') repetition \(offset + 1) \(partial ? "first component " : "")value \"\(value)\" is not in HL7 Table \(table.number) (\(table.name)) for v\(version.rawValue)"
            ))
        }
    }

    /// Component-level grammar check (v0.2-V2 + v0.4-S4). When a
    /// composite-typed field is populated, walks every repetition and
    /// dispatches two kinds of conformance check:
    ///
    /// 1. **Flat required-component check.** For each component listed
    ///    in the composite's `requiredComponents`, emits one
    ///    ``IssueCode/requiredComponentMissing`` if the component is
    ///    empty. Models simple "this component must always be populated"
    ///    rules (XPN-1 family, CX-1 ID, XAD-1 street, etc.).
    ///
    /// 2. **OR-rule check** (v0.4-S4). For composites whose v2.5.1
    ///    conformance is "at least one of these components" or "this
    ///    group OR at least one of those" — `CWE`, `XTN`, `HD`, `PL`,
    ///    `EIP` — dispatches to the composite's `requiredComponentSet`
    ///    and emits one issue when the OR-rule is violated. See
    ///    ``RequiredComponentSet`` for the semantics.
    ///
    /// Composite types HL7v2Kit doesn't have typed metadata for skip
    /// silently in both dispatches.
    /// Conditional components (M26, ADR-017): for every populated repetition of a field
    /// whose datatype has a component grammar (``componentGrammar(_:version:)``), a component carrying a `condition` must be
    /// populated when that predicate holds over its sibling components. One level of
    /// nesting is descended, as for the code-table check (the CNN inside NDL). Reported at
    /// the component with ``IssueCode/conditionalComponentMissing`` at
    /// ``ValidationOptions/requiredComponentSeverity``.
    private func checkConditionalComponents(
        _ grammar: FieldGrammar,
        field: Field,
        fieldIndex: Int,
        segmentID: String,
        segmentIndex: Int,
        version: Version,
        issues: inout [ValidationIssue]
    ) {
        guard let dataType = Self.fieldGrammar(segment: segmentID, field: fieldIndex, dataType: grammar.dataType,
                                               version: version) else { return }
        let repeated = field.repetitions.filter(isRepetitionPopulated).count > 1
        func check(_ entries: [ComponentGrammar], values: [String?], typeName: String,
                   component: Int?, subcomponent: (Int) -> Int?) {
            func populated(_ i: Int) -> Bool {
                guard i >= 1, i <= values.count, let v = values[i - 1] else { return false }
                return !v.isEmpty && v != "\"\""
            }
            for entry in entries {
                for (condition, severity, code) in [
                    (entry.condition, Optional(options.requiredComponentSeverity), IssueCode.conditionalComponentMissing),
                    (entry.conformanceCondition, options.conformanceConditionSeverity, IssueCode.conformanceConditionMissing),
                ] {
                    guard let condition, let severity, !populated(entry.index),
                          ComponentCondition.holds(condition, populated: populated, repeated: repeated) else { continue }
                    let location = IssueLocation(segmentID: segmentID, segmentIndex: segmentIndex, fieldIndex: fieldIndex,
                                                 componentIndex: component ?? entry.index,
                                                 subcomponentIndex: subcomponent(entry.index))
                    issues.append(ValidationIssue(
                        severity: severity,
                        code: code,
                        location: location,
                        message: "Conditional component \(location.pathDescription) ('\(entry.name)') in \(typeName) is empty while its condition holds: \(condition)."
                    ))
                }
            }
        }
        for repetition in field.repetitions where isRepetitionPopulated(repetition) {
            let values = repetition.components.map(\.stringValue)
            check(dataType.components, values: values, typeName: grammar.dataType, component: nil, subcomponent: { _ in nil })
            for entry in dataType.components where repetition.components.count >= entry.index {
                guard let nested = Self.componentGrammar(entry.dataType, version: version),
                      nested.components.contains(where: { $0.condition != nil || $0.conformanceCondition != nil }) else { continue }
                let subs = repetition.components[entry.index - 1].subcomponents.map { Optional($0.value) }
                check(nested.components, values: subs, typeName: "\(grammar.dataType).\(entry.index) (\(entry.dataType))",
                      component: entry.index, subcomponent: { $0 })
            }
        }
    }

    private func checkComponents(
        _ grammar: FieldGrammar,
        field: Field,
        fieldIndex: Int,
        segmentID: String,
        segmentIndex: Int,
        version: Version,
        issues: inout [ValidationIssue]
    ) {
        checkConditionalComponents(grammar, field: field, fieldIndex: fieldIndex, segmentID: segmentID,
                                   segmentIndex: segmentIndex, version: version, issues: &issues)
        let required = requiredComponents(forCompositeCode: grammar.dataType, segmentID: segmentID,
                                          fieldIndex: fieldIndex, version: version)
        let requiredSet = requiredComponentSet(forCompositeCode: grammar.dataType)
        guard !required.isEmpty || requiredSet != nil else { return }
        for repetition in field.repetitions where isRepetitionPopulated(repetition) {
            // (1) Flat required-component check.
            for spec in required {
                if !isComponentPopulated(repetition, componentIndex: spec.index) {
                    let location = IssueLocation(
                        segmentID: segmentID,
                        segmentIndex: segmentIndex,
                        fieldIndex: fieldIndex,
                        componentIndex: spec.index
                    )
                    issues.append(ValidationIssue(
                        severity: options.requiredComponentSeverity,
                        code: .requiredComponentMissing,
                        location: location,
                        message: "Required component \(location.pathDescription) ('\(spec.name)') in \(grammar.dataType) field '\(grammar.name)' is missing"
                    ))
                }
            }
            // (2) OR-rule check.
            if let set = requiredSet {
                let populatedIndices = populatedComponentIndices(in: repetition)
                if !set.isSatisfied(populatedIndices: populatedIndices) {
                    let location = IssueLocation(
                        segmentID: segmentID,
                        segmentIndex: segmentIndex,
                        fieldIndex: fieldIndex
                    )
                    issues.append(ValidationIssue(
                        severity: options.requiredComponentSeverity,
                        code: .requiredComponentMissing,
                        location: location,
                        message: "OR-rule violated in \(grammar.dataType) field \(location.pathDescription) ('\(grammar.name)'): "
                            + set.violationMessage(populatedIndices: populatedIndices, compositeCode: grammar.dataType)
                    ))
                }
            }
        }
    }

    /// Map an HL7 composite data-type code (e.g. `"XPN"`) to the type's
    /// `requiredComponents` metadata. Unknown codes return an empty list
    /// so the check is a no-op for composites HL7v2Kit hasn't typed yet.
    /// The components a composite REQUIRES when it is populated: exactly those its
    /// version's component table prints as `R` (M14, ADR-017).
    ///
    /// This replaces hand-written per-type lists that were applied to every version and
    /// cited v2.5.1 sections whose tables print the opposite: XAD.1, XPN.1, XCN.1, XON.1,
    /// CE.1, EI.1, PT.1 and VID.1 are all printed `O` in v2.5.1, so an address with no
    /// street line (`^^Sydney^NSW^2000`) or a name with no family name was reported as an
    /// error against the spec (req #4). The grammar also carries what a fixed list could
    /// not: CX.5, PT.1, VID.1 and XTN.3 become `R` in v2.8.2.
    ///
    /// v2.3 to v2.4 define components in prose and print no optionality, so nothing is
    /// required of them here; nor of a field-local `CM` grammar (P5-6), whose Components
    /// line prints none either, though it resolves through the same
    /// ``fieldGrammar(segment:field:dataType:version:)`` as every other composite check. `.v2_8` is validated as v2.8.2 (ADR-018), so it is checked
    /// against that table like any other version. `RE` (required but may be empty) is,
    /// by its own definition, never a missing value.
    func requiredComponents(forCompositeCode code: String, segmentID: String, fieldIndex: Int,
                                    version: Version) -> [RequiredComponent] {
        guard let grammar = Self.fieldGrammar(segment: segmentID, field: fieldIndex, dataType: code,
                                              version: version) else { return [] }
        return grammar.components
            .filter { $0.optionalityCode == "R" }
            .map { RequiredComponent(index: $0.index, name: $0.name) }
    }

    /// Map an HL7 composite data-type code to the type's OR-rule
    /// `requiredComponentSet` metadata, if it publishes one. Returns nil
    /// for composites whose spec conformance is a flat "all-of" rule
    /// (no OR-rule disjunction). v0.4-S4.
    private func requiredComponentSet(forCompositeCode code: String) -> RequiredComponentSet? {
        switch code {
        case "CWE": return CWE.requiredComponentSet
        case "XTN": return XTN.requiredComponentSet
        case "HD":  return HD.requiredComponentSet
        case "PL":  return PL.requiredComponentSet
        case "EIP": return EIP.requiredComponentSet
        default:    return nil
        }
    }

    /// Collect the 1-based component indices that are populated in a
    /// repetition. Used by the OR-rule check to evaluate
    /// `RequiredComponentSet.isSatisfied(populatedIndices:)`. v0.4-S4.
    private func populatedComponentIndices(in repetition: Repetition) -> Set<Int> {
        var indices: Set<Int> = []
        for (offset, component) in repetition.components.enumerated() {
            let oneBased = offset + 1
            for subcomponent in component.subcomponents {
                if !subcomponent.value.isEmpty {
                    indices.insert(oneBased)
                    break
                }
            }
        }
        return indices
    }

    /// True if the repetition has at least one component with at least
    /// one non-empty subcomponent. Used to skip empty repetitions on
    /// multi-rep composite fields.
    private func isRepetitionPopulated(_ repetition: Repetition) -> Bool {
        repetition.components.contains { component in
            component.subcomponents.contains { !$0.value.isEmpty }
        }
    }

    /// True if the 1-based `componentIndex`-th component of `repetition`
    /// has at least one non-empty subcomponent value. Returns false for
    /// out-of-bounds component indices, which is the correct semantic for
    /// "required component is missing".
    private func isComponentPopulated(
        _ repetition: Repetition,
        componentIndex: Int,
        subcomponentIndex: Int? = nil
    ) -> Bool {
        guard repetition.components.indices.contains(componentIndex - 1) else { return false }
        let subs = repetition.components[componentIndex - 1].subcomponents
        // M6-A-2: a named subcomponent must itself be populated. Without
        // an index, any populated subcomponent satisfies the check.
        guard let subcomponentIndex else { return subs.contains { !$0.value.isEmpty } }
        guard subs.indices.contains(subcomponentIndex - 1) else { return false }
        return !subs[subcomponentIndex - 1].value.isEmpty
    }

    /// `.conditional` field check (v0.2-V1). Fires `.conditionalFieldMissing`
    /// when the field's `grammar.condition` predicate evaluates to true and
    /// the field is empty. Same-segment predicates only; cross-segment or
    /// malformed predicates skip silently (treated as no-trigger).
    private func checkConditional(
        _ grammar: FieldGrammar,
        segment: Segment,
        segmentIndex: Int,
        message: Message,
        isPopulated: Bool,
        location: IssueLocation,
        issues: inout [ValidationIssue]
    ) {
        // P8b-17: a formerly gated field on a message with no group spans.
        if case .gated(let fields) = message.groupScoping,
           fields.contains("\(location.segmentID)-\(grammar.index)") { return }
        guard grammar.optionality == .conditional,
              !isPopulated,
              let condition = grammar.condition,
              !condition.isEmpty,
              conditionTriggers(
                condition,
                in: segment,
                segmentIndex: segmentIndex,
                message: message,
                currentSegmentID: location.segmentID
              )
        else { return }
        issues.append(ValidationIssue(
            severity: .error,
            code: .conditionalFieldMissing,
            location: location,
            message: "Conditional field \(location.pathDescription) ('\(grammar.name)') is required by condition '\(condition)' but missing"
        ))
    }

    /// Conditional-prohibition check (M8-D). Fires
    /// `.conditionalFieldProhibited` when the field IS populated while
    /// its `grammar.prohibitedWhen` predicate is true — the inverse of
    /// `checkConditional`. "PRT-6 may only be valued if PRT-5 is
    /// valued" encodes as `prohibitedWhen: "PRT-5 empty"`. Same
    /// fail-safe semantics: an unresolvable predicate never fires.
    /// Each of `grammar.additionalProhibitions` is evaluated the same
    /// way at its own severity, and each rule that holds reports its
    /// own issue (P4-21). A rule with `permitsNull` skips a field that
    /// holds only the HL7 null; every other rule treats `""` as a
    /// value (P4-26). `field` is required (not defaulted) so a caller
    /// cannot drop the exemption by omission; the null walk over it
    /// runs only when some rule has `permitsNull`, and a `nil` field
    /// carries no non-null value. Internal so tests can drive it with
    /// a hand-built grammar.
    func checkProhibition(
        _ grammar: FieldGrammar,
        segment: Segment,
        segmentIndex: Int,
        message: Message,
        isPopulated: Bool,
        field: Field?,
        location: IssueLocation,
        issues: inout [ValidationIssue]
    ) {
        guard isPopulated else { return }
        var rules = grammar.additionalProhibitions
        if let prohibition = grammar.prohibitedWhen {
            rules.insert(FieldProhibition(condition: prohibition, severity: grammar.prohibitedSeverity), at: 0)
        }
        let hasNonNullValue = !rules.contains(where: \.permitsNull)
            || field.map { carriesNonNullValue($0) } ?? false
        for rule in rules where !rule.condition.isEmpty
            && (hasNonNullValue || !rule.permitsNull)
            && conditionTriggers(
                rule.condition,
                in: segment,
                segmentIndex: segmentIndex,
                message: message,
                currentSegmentID: location.segmentID
            ) {
            issues.append(ValidationIssue(
                severity: rule.severity,
                code: .conditionalFieldProhibited,
                location: location,
                message: "Field \(location.pathDescription) ('\(grammar.name)') is populated but prohibited while '\(rule.condition)' holds"
            ))
        }
    }

    /// Evaluate a condition predicate against a single segment.
    /// v0.2-V1 introduced the single-atom DSL; v0.4-S4 extends it with
    /// compound `AND` / `OR` combinators and `in (…)` / `not in (…)`
    /// set-membership operators so the v2.5.1 spec's compound
    /// conditional rules (ORC-2 "required when ORC-1 in {NW, CA, CR,
    /// DC, …}", OBR-1 / OBR-7 / OBR-22 etc.) can be expressed
    /// faithfully.
    ///
    /// Grammar (recursive descent, precedence AND-binds-tighter-than-OR):
    /// ```
    /// <predicate>    := <or-expr>
    /// <or-expr>      := <and-expr> (" OR " <and-expr>)*
    /// <and-expr>     := <atom> (" AND " <atom>)*
    /// <atom>         := <field-atom> | <segment-atom> | <repeat-atom>
    /// <field-atom>   := <fieldref> " " <op>
    /// <fieldref>     := <segmentID> "-" <int> <subcomp-tail>?   // ADR-010
    /// <subcomp-tail> := "." <int> | "." <int> "." <int>
    /// <segment-atom> := <segmentID> " " <segment-op>            // ADR-010
    /// <segment-op>   := "present" | "absent"
    /// <repeat-atom>  := ("anyRepeat(" | "noRepeat(") <fieldref> ") " <op>   // M6-B-1, P4
    /// <op>           := "populated"
    ///                 | "empty"
    ///                 | "= <value>"
    ///                 | "!= <value>"
    ///                 | "in (<values>)"
    ///                 | "not in (<values>)"
    /// <values>       := <value> ("," " "* <value>)*
    /// ```
    /// The parser is paren-free: compound predicates must be expressed
    /// in DNF (AND-of-atoms clauses joined by OR). AND binds tighter
    /// than OR, so `A AND B OR C AND D` parses as `(A AND B) OR
    /// (C AND D)`. Rules that read naturally as `X AND (Y OR Z)` must
    /// be encoded as `X AND Y OR X AND Z`.
    ///
    /// Cross-segment references (segmentID ≠ currentSegmentID) and any
    /// malformed sub-expression fail safe — that sub-expression returns
    /// `false`. Per v0.2-V1 design: a malformed schema must never make a
    /// previously-accepted message non-conformant.
    ///
    /// v0.7-S1 (ADR-008) widens the signature to carry `segmentIndex`
    /// and `message`. v0.7-S2 uses those arguments to resolve cross-
    /// segment field refs, message-context atoms (`messageCode` /
    /// `messageStructure` / `triggerEvent`), and position atoms
    /// (`previousSegment(<ID>).<fieldref>` / `associatedSegment(<ID>)
    /// .<fieldref>`). v0.11-S1 (ADR-010) adds segment-presence atoms
    /// (`<segmentID> present` / `<segmentID> absent`) to distinguish
    /// "peer segment does not exist" from "peer field is empty" — the
    /// §4.5.1.8 XOR softening unblock. v0.11-S2 extends `<fieldref>`
    /// with an optional `.<component>[.<subcomponent>]` tail so atoms
    /// can read a specific composite slot (`OBX-3.3 = AUSPDI` gates
    /// HL7au:000008.1). `populated` / `empty` still evaluate the
    /// whole field; slot-specific presence checks should use `= v` /
    /// `!= v` against the expected scalar.
    /// P4 adds the lookahead referent `nextSegmentID(<ID>|...)` (next segment ID after skipping the listed IDs; "" at the end of the message).
    /// It always skips Z-segments as well, because they are site extensions
    /// outside the standard structure (ADR-003) and may appear anywhere.
    ///
    /// Internal (not private) access so the v0.7 production unit tests
    /// can call the evaluator directly via `@testable import`. Not
    /// part of the public API.
    ///
    /// P4-31 (ADR-021): this is exactly `conditionTruth(...) == .true`.
    /// An unknown condition does not trigger, which is the v0.2-V1
    /// fail-safe every "required when" caller relies on.
    func conditionTriggers(
        _ condition: String,
        in segment: Segment,
        segmentIndex: Int,
        message: Message,
        currentSegmentID: String
    ) -> Bool {
        conditionTruth(
            condition,
            in: segment,
            segmentIndex: segmentIndex,
            message: message,
            currentSegmentID: currentSegmentID
        ) == .true
    }

    /// The three-state core (P4-31, ADR-021): `.true`, `.false`, or
    /// `.unknown` when the message cannot decide the condition. Only a
    /// caller that acts on a definitely false condition (the AU
    /// HL7au:00060.4 full-predicate check) needs more than
    /// ``conditionTriggers(_:in:segmentIndex:message:currentSegmentID:)``.
    func conditionTruth(
        _ condition: String,
        in segment: Segment,
        segmentIndex: Int,
        message: Message,
        currentSegmentID: String
    ) -> ConditionTruth {
        evaluateOrExpression(
            condition,
            in: segment,
            segmentIndex: segmentIndex,
            message: message,
            currentSegmentID: currentSegmentID
        )
    }

    /// OR of AND clauses (``ConditionLanguage/clauses(_:)``), combined by
    /// Kleene's connectives. Short-circuits like the DNF it is: a clause
    /// stops at its first false atom, the whole at its first true clause.
    private func evaluateOrExpression(
        _ expression: String,
        in segment: Segment,
        segmentIndex: Int,
        message: Message,
        currentSegmentID: String
    ) -> ConditionTruth {
        var result = ConditionTruth.false
        for atoms in ConditionLanguage.clauses(expression) {
            var clause = ConditionTruth.true
            for atom in atoms {
                clause = .and(clause, evaluateAtom(
                    atom,
                    in: segment,
                    segmentIndex: segmentIndex,
                    message: message,
                    currentSegmentID: currentSegmentID
                ))
                if clause == .false { break }
            }
            result = .or(result, clause)
            if result == .true { break }
        }
        return result
    }

    /// A referent resolved to a scalar string value plus a "is this
    /// genuinely populated?" bit. The predicate (populated / empty /
    /// = / != / in / not in) applies to this pair regardless of where
    /// the value came from (current segment, cross-segment peer,
    /// message-context noun, or position lookup).
    private struct ResolvedReferent {
        let raw: String
        let isPopulated: Bool
    }

    /// Single atomic predicate, classified by
    /// ``ConditionLanguage/parseAtom(_:)`` (the same parse
    /// `Validator.conditionParseErrors(_:)` checks, P4-25). The forms:
    ///
    /// 1. **Same-segment field ref** — `<currentSegmentID>-<index>`.
    /// 2. **Cross-segment field ref** — `<otherSegmentID>-<index>`,
    ///    resolved via `Message.associatedSegment` (ORC/OBR group
    ///    semantics).
    /// 3. **Message-context atom** — `messageCode`, `triggerEvent`,
    ///    or `messageStructure` (reads MSH-9.1 / .2 / .3).
    /// 4. **Position atom** — `previousSegment(<ID>).<fieldref>` or
    ///    `associatedSegment(<ID>).<fieldref>`.
    /// 5. **Any-repetition atom** — `anyRepeat(<fieldref>)` applies the
    ///    predicate to every repetition of the field with ∃-semantics
    ///    (M6-B-1; repeating fields like PRD-1 need more than the
    ///    first-repetition scalar convention).
    /// 6. **No-repetition atom** — `noRepeat(<fieldref>)` is the
    ///    universal negation of `anyRepeat`: true iff the field has a
    ///    populated repetition and no repetition satisfies the
    ///    predicate (P4; SPM-13's "SPM-11 has no G repetition").
    /// 7. **Segment-presence atom** — `<segmentID> present` / `absent`
    ///    (ADR-010).
    ///
    /// An atom that does not parse, or whose referent cannot be
    /// resolved, is `.unknown` (P4-31, ADR-021). The two-state
    /// `conditionTriggers` reads that as "does not fire", the v0.2-V1
    /// fail-safe.
    private func evaluateAtom(
        _ atom: String,
        in segment: Segment,
        segmentIndex: Int,
        message: Message,
        currentSegmentID: String
    ) -> ConditionTruth {
        guard case .success(let parsed) = ConditionLanguage.parseAtom(atom) else { return .unknown }
        switch parsed {
        case .segmentPresence(let id, let present):
            // True iff a segment of that ID exists in the current
            // segment's ORC/OBR group. Distinct from `<fieldref>
            // populated` / `empty`, which fail safe when the peer is
            // missing and so conflate "peer absent" with "peer field empty".
            return ConditionTruth(message.segmentExists(id, inGroupOf: segmentIndex) == present)

        case .anyRepeat(let path, let predicate):
            // M6-B-1: the scalar field-ref convention reads the FIRST
            // repetition only, so `PRD-1 = AP` misses a spec-compliant
            // `RP~AP`. ∃-semantics over every repetition's slot. An
            // unresolvable peer is unknown, and so is a field with no
            // populated slot (an empty domain, as for `noRepeat` below)
            // unless an empty slot itself satisfies the predicate
            // (`anyRepeat(X) empty`). P4-31.
            guard let slots = resolveRepetitionSlots(
                path,
                in: segment,
                segmentIndex: segmentIndex,
                message: message,
                currentSegmentID: currentSegmentID
            ) else { return .unknown }
            let found = ConditionTruth.any(slots.map { applyPredicate(predicate, to: $0) })
            guard found == .true || slots.contains(where: { $0.isPopulated }) else { return .unknown }
            return found

        case .noRepeat(let path, let predicate):
            // P4 universal negation: true iff the field has at least one
            // populated repetition slot and NO slot satisfies the
            // predicate. SPM-13 "would only be valued if the specimen
            // role attribute has the value G" needs "no repetition of
            // SPM-11 is G", which `anyRepeat(...) != G` cannot state (it
            // is true for `P~G`). An absent or all-empty field is unknown:
            // there is no definite value to negate (P4-31; the v0.2-V1
            // fail-safe). Over a populated domain a slot the predicate
            // cannot judge counts as not matching, as it always has.
            guard let slots = resolveRepetitionSlots(
                path,
                in: segment,
                segmentIndex: segmentIndex,
                message: message,
                currentSegmentID: currentSegmentID
            ), slots.contains(where: { $0.isPopulated }) else { return .unknown }
            return ConditionTruth(!slots.contains { applyPredicate(predicate, to: $0) == .true })

        case .value(let referent, let predicate):
            guard let resolved = resolveReferent(
                referent,
                in: segment,
                segmentIndex: segmentIndex,
                message: message,
                currentSegmentID: currentSegmentID
            ) else { return .unknown }
            return applyPredicate(predicate, to: resolved)
        }
    }

    /// Resolve a classified referent. Returns `nil` when the target
    /// cannot be located — the atom then fails safe per the v0.2-V1
    /// invariant.
    private func resolveReferent(
        _ referent: ConditionReferent,
        in segment: Segment,
        segmentIndex: Int,
        message: Message,
        currentSegmentID: String
    ) -> ResolvedReferent? {
        func scalar(_ v: String?) -> ResolvedReferent {
            ResolvedReferent(raw: v ?? "", isPopulated: !(v ?? "").isEmpty)
        }
        func flag(_ on: Bool) -> ResolvedReferent {
            ResolvedReferent(raw: on ? "true" : "", isPopulated: on)
        }
        switch referent {
        case .messageCode: return scalar(message.messageCode)
        case .messageStructure: return scalar(message.messageStructure)
        case .triggerEvent: return scalar(message.triggerEvent)
        // M29 / M30 / M32 — caller assertions, not wire properties (see
        // ValidationOptions). M32 is "when using SMD with NASH certificates".
        case .auPathologySender: return flag(options.auPathologySender)
        case .auDisplayIntended: return flag(options.auDisplayIntended)
        case .auNASHTransport: return flag(options.auNASHTransport)
        case .auAssigningAuthorityTable: return flag(options.auAssigningAuthorityTable)

        case .nextSegmentID(let skip):
            // P4 lookahead: the ID of the first segment after the current
            // one whose ID is not in the skip list and does not start with
            // "Z", or "" at the end of the message. Z-segments are always
            // skipped: they are site extensions outside the standard
            // structure (ADR-003) and may appear anywhere, so one between
            // chained TQ1s must not stop the lookahead short. TQ1-12 "If
            // the TQ1 segment is repeated ... indicating the sequencing of
            // the following TQ1 segment" encodes as `nextSegmentID(TQ2) =
            // TQ1`: the timing group is {TQ1 [{TQ2}]}, so only TQ2 may sit
            // between chained TQ1s.
            var next = segmentIndex + 1
            while next < message.segments.count,
                  skip.contains(message.segments[next].segmentID)
                    || message.segments[next].segmentID.hasPrefix("Z") {
                next += 1
            }
            let id = next < message.segments.count ? message.segments[next].segmentID : ""
            return scalar(id)

        // Position atoms (ADR-008): a missing preceding / associated
        // segment of that ID fails safe. The ref's own segment-ID part is
        // not re-checked against the target, which was resolved positionally.
        case .previousSegment(let id, let path):
            guard let target = message.previousSegment(id, beforeIndex: segmentIndex) else { return nil }
            return readField(target, fieldIndex: path.field,
                             componentIndex: path.component, subcomponentIndex: path.subcomponent)
        case .associatedSegment(let id, let path):
            guard let target = message.associatedSegment(id, fromIndex: segmentIndex) else { return nil }
            return readField(target, fieldIndex: path.field,
                             componentIndex: path.component, subcomponentIndex: path.subcomponent)

        case .field(let path):
            // Same-segment reads directly; cross-segment resolves the peer
            // via `Message.associatedSegment`, and an unlocatable peer
            // fails safe (ADR-008) rather than reading as "empty".
            guard let target = targetSegment(path, in: segment, segmentIndex: segmentIndex,
                                             message: message, currentSegmentID: currentSegmentID)
            else { return nil }
            return readField(target, fieldIndex: path.field,
                             componentIndex: path.component, subcomponentIndex: path.subcomponent)
        }
    }

    /// The segment a field-ref reads: the current segment when the IDs
    /// match, otherwise the associated peer (`nil` when there is none).
    private func targetSegment(
        _ path: Path,
        in segment: Segment,
        segmentIndex: Int,
        message: Message,
        currentSegmentID: String
    ) -> Segment? {
        path.segmentID == currentSegmentID
            ? segment
            : message.associatedSegment(path.segmentID, fromIndex: segmentIndex)
    }

    /// Resolve every repetition of a field-ref to its own
    /// `(raw, isPopulated)` pair at the ref's component/subcomponent
    /// slot, for the `anyRepeat(...)` / `noRepeat(...)` atoms (M6-B-1).
    /// Same same-segment / cross-segment resolution as a plain field
    /// ref; `isPopulated` here is per-repetition-slot (the slot value is
    /// non-empty), unlike the whole-field convention of `readField` —
    /// under ∃-semantics a field-scope answer would be meaningless.
    /// Returns `nil` on an unresolvable peer; an absent field resolves
    /// to `[]`. Both make the quantifier `.unknown` (P4-31).
    private func resolveRepetitionSlots(
        _ path: Path,
        in segment: Segment,
        segmentIndex: Int,
        message: Message,
        currentSegmentID: String
    ) -> [ResolvedReferent]? {
        guard let target = targetSegment(path, in: segment, segmentIndex: segmentIndex,
                                         message: message, currentSegmentID: currentSegmentID)
        else { return nil }
        guard let field = target.field(path.field) else { return [] }
        let comp = (path.component ?? 1) - 1
        let sub = (path.subcomponent ?? 1) - 1
        return field.repetitions.map { rep in
            let raw: String = {
                guard rep.components.indices.contains(comp) else { return "" }
                let subs = rep.components[comp].subcomponents
                guard subs.indices.contains(sub) else { return "" }
                return subs[sub].value
            }()
            return ResolvedReferent(raw: raw, isPopulated: !raw.isEmpty)
        }
    }

    /// Project a `Segment` + 1-based field index (and optional
    /// component / subcomponent indices) into the `(raw, isPopulated)`
    /// pair the predicate consumes.
    ///
    /// When `componentIndex` / `subcomponentIndex` are nil, the raw
    /// value is the first repetition's first component's first
    /// subcomponent — the v0.4-S4 scalar-reading convention. When
    /// set, the raw is the specified component's specified
    /// subcomponent (defaulting to subcomponent 1 when only the
    /// component index is provided). ADR-010 Extension 3.
    ///
    /// `isPopulated` reflects the WHOLE field's population (any
    /// non-empty subcomponent anywhere in the field) regardless of
    /// which slot the raw value came from. Predicates that need
    /// slot-specific presence should use `= v` / `!= v` against the
    /// specific value; `populated` / `empty` remain field-scope.
    private func readField(
        _ segment: Segment,
        fieldIndex: Int,
        componentIndex: Int? = nil,
        subcomponentIndex: Int? = nil
    ) -> ResolvedReferent {
        let field = segment.field(fieldIndex)
        let isPopulated = field.map { isFieldPopulated($0) } ?? false
        let comp = (componentIndex ?? 1) - 1
        let sub = (subcomponentIndex ?? 1) - 1
        let raw: String = {
            guard let rep = field?.repetitions.first,
                  rep.components.indices.contains(comp)
            else { return "" }
            let subs = rep.components[comp].subcomponents
            guard subs.indices.contains(sub) else { return "" }
            return subs[sub].value
        }()
        return ResolvedReferent(raw: raw, isPopulated: isPopulated)
    }

    /// Apply a classified predicate to a resolved referent. A predicate
    /// that cannot judge the referent (the fail-safe cases below) is
    /// `.unknown` (P4-31, ADR-021).
    private func applyPredicate(_ predicate: ConditionPredicate, to resolved: ResolvedReferent) -> ConditionTruth {
        switch predicate {
        case .populated: return ConditionTruth(resolved.isPopulated)
        case .empty: return ConditionTruth(!resolved.isPopulated)
        case .equals(let v): return ConditionTruth(resolved.raw == v)
        case .notEquals(let v): return ConditionTruth(resolved.raw != v)
        case .greaterThan(let threshold):
            // M8-D: PAC-2's "If SHP-8 Number of Packages in Shipment is
            // greater than 1". A non-numeric or empty referent fails safe.
            guard let value = Double(resolved.raw) else { return .unknown }
            return ConditionTruth(value > threshold)
        // M6-B-2 prefix ops: ADRM-2021 reserves everything beginning `Z`
        // (HL7au:000020 message/trigger codes, 000023.1 segments).
        // `startsWith` on an empty referent is false (an absent value
        // begins with nothing); `not startsWith` mirrors `not in` — it
        // asserts only on populated referents, per the fail-safe rule.
        case .startsWith(let prefix): return ConditionTruth(resolved.raw.hasPrefix(prefix))
        case .notStartsWith(let prefix):
            guard resolved.isPopulated else { return .unknown }
            return ConditionTruth(!resolved.raw.hasPrefix(prefix))
        case .isIn(let values): return ConditionTruth(values.contains(resolved.raw))
        case .notIn(let values):
            // not-in fires only if the referent is actually populated —
            // an empty referent is not a meaningful "non-member"
            // assertion, so the conditional only requires the dependent
            // field when the referent carries a definite excluded value.
            guard resolved.isPopulated else { return .unknown }
            return ConditionTruth(!values.contains(resolved.raw))
        }
    }

    /// A field is "populated" if at least one repetition has at least one
    /// component with a non-empty subcomponent value. Distinguishes the
    /// "present but empty" wire shape from genuinely absent fields.
    private func isFieldPopulated(_ field: Field) -> Bool {
        field.repetitions.contains(where: isRepetitionPopulated)
    }
}

private extension Message {
    /// A copy of this message declaring `version`. Used to validate under
    /// ``Version/grammarVersion`` (ADR-018); segments are shared, not copied.
    func declaring(_ version: Version) -> Message {
        guard version != self.version else { return self }
        return Message(
            version: version,
            encodingCharacters: encodingCharacters,
            segments: segments,
            characterEncoding: characterEncoding,
            locale: locale
        )
    }
}
