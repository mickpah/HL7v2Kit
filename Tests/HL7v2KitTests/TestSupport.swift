// TestSupport.swift
// Shared arrange helpers for the typed-segment suites (R7 — the parse →
// `#require(firstSegment(…))` pair opened ~140 test bodies verbatim).
// Failures attribute to the CALLER's line via the sourceLocation default.

import Foundation
import Testing
@testable import HL7v2Kit

/// Parse `wire` and hydrate the first segment of `type`.
func hydrated<S: TypedSegment>(
    _ type: S.Type,
    from wire: String,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> S {
    let message = try Parser().parse(wire)
    return try #require(message.firstSegment(S.self), sourceLocation: sourceLocation)
}

/// Variant that also returns the parsed ``Message``, for tests that
/// cross-check path access against the typed accessors (or hydrate
/// further segments from the same wire).
func hydratedMessage<S: TypedSegment>(
    _ type: S.Type,
    from wire: String,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> (message: Message, segment: S) {
    let message = try Parser().parse(wire)
    let segment = try #require(message.firstSegment(S.self), sourceLocation: sourceLocation)
    return (message, segment)
}

/// Byte-wire overload for fixture-loaded tests.
func hydratedMessage<S: TypedSegment>(
    _ type: S.Type,
    from wire: Data,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> (message: Message, segment: S) {
    let message = try Parser().parse(wire)
    let segment = try #require(message.firstSegment(S.self), sourceLocation: sourceLocation)
    return (message, segment)
}

/// Every `seg-index` position left `C` with no `condition` and no
/// `prohibitedWhen` axis in `table` — the "bare" conditionals the
/// permanent-limitations register tracks (P4-15). Shared by the per-version
/// guards in `BareConditionalGuardTests` and the v2.8.2 guard in
/// `MultiVersionTests` so the set-construction rule cannot drift between them.
func bareConditionals(_ table: [String: SegmentGrammar]) -> Set<String> {
    var bare = Set<String>()
    for (seg, grammar) in table {
        for f in grammar.fields
        where f.optionality == .conditional && f.condition == nil && f.prohibitedWhen == nil {
            bare.insert("\(seg)-\(f.index)")
        }
    }
    return bare
}
