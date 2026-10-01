// ConditionLanguage.swift
// The parse half of the condition DSL (ADR-010): tokenising and classifying a
// condition string into clauses, atoms, referents and predicates. The
// Validator's evaluator reads conditions only through these helpers, and
// `Validator.conditionParseErrors(_:)` reports what they reject, so the
// evaluator and the parse-validity check cannot drift apart (P4-25).

import Foundation

/// The predicate half of an atom: `populated`, `empty`, `= v`, `!= v`,
/// `> n`, `startsWith v`, `not startsWith v`, `in (...)`, `not in (...)`.
enum ConditionPredicate: Equatable, Sendable {
    case populated
    case empty
    case equals(String)
    case notEquals(String)
    case greaterThan(Double)
    case startsWith(String)
    case notStartsWith(String)
    case isIn([String])
    case notIn([String])
}

/// The referent half of a value atom.
enum ConditionReferent: Equatable, Sendable {
    /// `messageCode`, `messageStructure`, `triggerEvent`: MSH-9.1 / .3 / .2.
    case messageCode, messageStructure, triggerEvent
    /// Caller assertions from ``ValidationOptions`` (M29, M30, M32).
    case auPathologySender, auDisplayIntended, auNASHTransport
    /// `nextSegmentID(<ID>|...)`: the next segment ID after skipping the listed IDs.
    case nextSegmentID(skipping: Set<String>)
    /// `previousSegment(<ID>).<fieldref>`.
    case previousSegment(String, Path)
    /// `associatedSegment(<ID>).<fieldref>`.
    case associatedSegment(String, Path)
    /// `<segmentID>-<field>[.<component>[.<subcomponent>]]`.
    case field(Path)
}

/// One classified atom of a condition.
enum ConditionAtom: Equatable, Sendable {
    /// `<segmentID> present` / `<segmentID> absent`.
    case segmentPresence(String, present: Bool)
    /// `anyRepeat(<fieldref>) <predicate>`.
    case anyRepeat(Path, ConditionPredicate)
    /// `noRepeat(<fieldref>) <predicate>`.
    case noRepeat(Path, ConditionPredicate)
    /// `<referent> <predicate>`.
    case value(ConditionReferent, ConditionPredicate)
}

enum ConditionLanguage {
    /// Split a condition into its OR clauses, each a list of AND atoms. The
    /// language is paren-free DNF: AND binds tighter than OR.
    static func clauses(_ condition: String) -> [[String]] {
        condition.components(separatedBy: " OR ").map { $0.components(separatedBy: " AND ") }
    }

    /// Classify one atom, or return why it cannot be read.
    static func parseAtom(_ atom: String) -> Result<ConditionAtom, ConditionParseError> {
        let trimmed = atom.trimmingCharacters(in: .whitespaces)

        // ADR-010 segment-presence atom, recognised before the general
        // referent/predicate split. HL7 segment IDs are 3 ASCII uppercase
        // alphanumerics, which rejects field refs, position atoms and the
        // lower-case message-context nouns.
        let words = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if words.count == 2, words[0].count == 3,
           words[0].allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }),
           words[1] == "present" || words[1] == "absent" {
            return .success(.segmentPresence(words[0], present: words[1] == "present"))
        }

        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                           .map(String.init)
        guard parts.count == 2 else { return .failure(.missingPredicate) }
        let referent = parts[0]
        let predicate: ConditionPredicate
        switch parsePredicate(parts[1]) {
        case .success(let p): predicate = p
        case .failure(let e): return .failure(e)
        }

        for (function, make) in [("anyRepeat(", ConditionAtom.anyRepeat), ("noRepeat(", ConditionAtom.noRepeat)]
        where referent.hasPrefix(function) && referent.hasSuffix(")") {
            let inner = String(referent.dropFirst(function.count).dropLast())
            guard let path = fieldRef(inner) else { return .failure(.malformedFieldRef(inner)) }
            return .success(make(path, predicate))
        }
        guard let resolved = parseReferent(referent) else { return .failure(.unknownReferent(referent)) }
        return .success(.value(resolved, predicate))
    }

    /// Classify a referent, or `nil` when no production recognises it.
    static func parseReferent(_ referent: String) -> ConditionReferent? {
        switch referent {
        case "messageCode": return .messageCode
        case "messageStructure": return .messageStructure
        case "triggerEvent": return .triggerEvent
        case "auPathologySender": return .auPathologySender
        case "auDisplayIntended": return .auDisplayIntended
        case "auNASHTransport": return .auNASHTransport
        default: break
        }
        if referent.hasPrefix("nextSegmentID("), referent.hasSuffix(")") {
            let skip = referent.dropFirst("nextSegmentID(".count).dropLast()
                .split(separator: "|").map(String.init)
            guard skip.allSatisfy(isSegmentIDShape) else { return nil }
            return .nextSegmentID(skipping: Set(skip))
        }
        if let (id, path) = positionForm(referent, function: "previousSegment") {
            return .previousSegment(id, path)
        }
        if let (id, path) = positionForm(referent, function: "associatedSegment") {
            return .associatedSegment(id, path)
        }
        return fieldRef(referent).map(ConditionReferent.field)
    }

    /// Classify a predicate clause.
    static func parsePredicate(_ predicate: String) -> Result<ConditionPredicate, ConditionParseError> {
        if predicate == "populated" { return .success(.populated) }
        if predicate == "empty" { return .success(.empty) }
        // `=` / `!=` / `startsWith` literals are single tokens (ADR-010): a
        // literal containing whitespace is rejected rather than accepted as
        // one wide value. Without this, a misspelt lower-case connector
        // (`PID-3 = A and PID-4 populated`, meant as two AND-joined atoms)
        // reads as one atom whose `= ` literal swallows the rest of the
        // string, which silently never matches a real field value
        // (requirement 4; P4-15, folded from the P4-25 review).
        if predicate.hasPrefix("= ") {
            let literal = String(predicate.dropFirst(2))
            guard !literal.contains(where: \.isWhitespace) else { return .failure(.malformedPredicate(predicate)) }
            return .success(.equals(literal))
        }
        if predicate.hasPrefix("!= ") {
            let literal = String(predicate.dropFirst(3))
            guard !literal.contains(where: \.isWhitespace) else { return .failure(.malformedPredicate(predicate)) }
            return .success(.notEquals(literal))
        }
        if predicate.hasPrefix("> ") {
            guard let threshold = Double(predicate.dropFirst(2)) else { return .failure(.malformedPredicate(predicate)) }
            return .success(.greaterThan(threshold))
        }
        for (op, make) in [("startsWith ", ConditionPredicate.startsWith), ("not startsWith ", ConditionPredicate.notStartsWith)]
        where predicate.hasPrefix(op) {
            let prefix = String(predicate.dropFirst(op.count))
            guard !prefix.isEmpty, !prefix.contains(where: \.isWhitespace) else { return .failure(.malformedPredicate(predicate)) }
            return .success(make(prefix))
        }
        for (op, make) in [("in (", ConditionPredicate.isIn), ("not in (", ConditionPredicate.notIn)]
        where predicate.hasPrefix(op) && predicate.hasSuffix(")") {
            let values = predicate.dropFirst(op.count).dropLast().split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            // Each comma-separated item is a single token (ADR-010, matching the
            // `=`/`!=`/`startsWith` literal guard above): an item that still
            // contains whitespace after trimming is rejected rather than
            // accepted as one wide value, so a misspelt separator cannot
            // silently merge two intended items into one that never matches.
            guard !values.isEmpty, !values.contains(where: \.isEmpty),
                  !values.contains(where: { $0.contains(where: \.isWhitespace) })
            else {
                return .failure(.malformedPredicate(predicate))
            }
            return .success(make(values))
        }
        return .failure(.malformedPredicate(predicate))
    }

    /// A DSL field-ref (`SEG-f`, `SEG-f.c`, `SEG-f.c.s`) through the shared
    /// ``Path`` parser, rejecting the Path-only segment-index (`SEG[N]-f`) and
    /// repetition (`SEG-f~r`) axes the condition grammar excludes. ADR-010
    /// Extension 3.
    static func fieldRef(_ referent: String) -> Path? {
        guard let path = try? Path(referent), path.segmentIndex == nil, path.repetition == nil
        else { return nil }
        return path
    }

    /// A bare HL7 segment ID: 2 to 4 letters/digits, the same shape `Path`
    /// accepts for the segment half of a field reference (P4 final-review
    /// fix). Used to reject a `nextSegmentID(...)` / `previousSegment(...)` /
    /// `associatedSegment(...)` argument that is not a plausible segment ID.
    private static func isSegmentIDShape(_ id: String) -> Bool {
        !id.isEmpty && id.count >= 2 && id.count <= 4
            && id.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// `<function>(<ID>).<fieldref>`, or `nil` when the shape does not match.
    private static func positionForm(_ referent: String, function: String) -> (String, Path)? {
        let prefix = "\(function)("
        guard referent.hasPrefix(prefix) else { return nil }
        let afterPrefix = referent.dropFirst(prefix.count)
        guard let closeIdx = afterPrefix.firstIndex(of: ")") else { return nil }
        let id = String(afterPrefix[..<closeIdx])
        let after = afterPrefix[afterPrefix.index(after: closeIdx)...]
        guard isSegmentIDShape(id), after.hasPrefix("."), let path = fieldRef(String(after.dropFirst()))
        else { return nil }
        return (id, path)
    }
}

/// Why an atom of a condition cannot be read.
enum ConditionParseError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingPredicate
    case malformedPredicate(String)
    case malformedFieldRef(String)
    case unknownReferent(String)

    var description: String {
        switch self {
        case .missingPredicate: return "no predicate after the referent"
        case .malformedPredicate(let p): return "unrecognised predicate '\(p)'"
        case .malformedFieldRef(let r): return "malformed field reference '\(r)'"
        case .unknownReferent(let r): return "unknown referent '\(r)'"
        }
    }
}

extension Validator {
    /// The parse errors in a condition string, one per atom the evaluator
    /// cannot read (an unreadable atom never fires). Empty for a condition that
    /// parses, and for an empty condition, which is not checked. P4-25.
    static func conditionParseErrors(_ condition: String) -> [String] {
        guard !condition.isEmpty else { return [] }
        return ConditionLanguage.clauses(condition).flatMap { $0 }.compactMap { atom in
            if case .failure(let error) = ConditionLanguage.parseAtom(atom) {
                return "atom '\(atom)': \(error)"
            }
            return nil
        }
    }
}
