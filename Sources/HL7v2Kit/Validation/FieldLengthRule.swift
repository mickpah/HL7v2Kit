// FieldLengthRule.swift
// The printed shapes of a FieldGrammar.length cell, and the enforceable reading of
// one (P6-6, V231-C15). PrintedLength mirrors the audit's LENGTH_TOKEN grammar
// (scripts/audit-schemas.py) plus the two shapes the schemas store verbatim that the
// token leaves to its whitelists: `*` (variable) and the open range `m..`.

import Foundation

/// The shape of one printed LEN or C.LEN cell, before any era reading.
enum PrintedLength: Equatable, Sendable {
    /// A positive integer of at most five digits: `20`. Pre-v2.7 a maximum length
    /// (v2.3.1 §2.6.2); from v2.7 a bare conformance length (v2.8.2 §2.5.5.3).
    case number(Int)
    /// The kilobyte abbreviation `64K` / `10K` printed before v2.7.
    case kilo(Int)
    /// `*`: a variable length (OBX-5).
    case variable
    /// `m..n`, or `m..` with no upper bound (v2.8.2 §2.5.5.0; v2.8.2 TQ2-6 prints `2..`).
    case range(min: Int, max: Int?)
    /// `x,y,z`: the allowed lengths (v2.8.2 §2.5.5.0).
    case list([Int])
    /// `n=` (never truncated) or `n#` (truncation pattern applies), v2.8.2 §2.5.5.3.
    case conformance(Int, truncatable: Bool)

    /// Reads a stored cell, or nil when it is in none of the printed shapes. Bounds
    /// are positive with no leading zero ("The minimum length is always 1 or more",
    /// v2.8.2 §2.5.5.0) and a range's upper bound is not below its lower.
    init?(_ cell: String) {
        func positive(_ text: Substring, maxDigits: Int = .max) -> Int? {
            guard !text.isEmpty, text.count <= maxDigits, text.first != "0",
                  text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(text)
        }
        let text = Substring(cell)
        if text == "*" { self = .variable; return }
        if let dots = text.range(of: "..") {
            guard let lower = positive(text[..<dots.lowerBound]) else { return nil }
            let upperText = text[dots.upperBound...]
            if upperText.isEmpty { self = .range(min: lower, max: nil); return }
            guard let upper = positive(upperText), upper >= lower else { return nil }
            self = .range(min: lower, max: upper)
            return
        }
        if text.contains(",") {
            let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            let values = parts.compactMap { positive($0) }
            guard parts.count >= 2, values.count == parts.count else { return nil }
            self = .list(values)
            return
        }
        if let last = text.last, last == "=" || last == "#" {
            guard let n = positive(text.dropLast()) else { return nil }
            self = .conformance(n, truncatable: last == "#")
            return
        }
        if let last = text.last, last == "K" || last == "k" {
            guard let n = positive(text.dropLast(), maxDigits: 2) else { return nil }
            self = .kilo(n)
            return
        }
        guard let n = positive(text, maxDigits: 5) else { return nil }
        self = .number(n)
    }
}

/// How one printed LEN cell constrains a field occurrence.
enum FieldLengthRule: Equatable, Sendable {
    /// Pre-v2.7 maximum length: the characters one occurrence may occupy,
    /// component and subcomponent separators included (v2.3.1 §2.6.2).
    case maximum(Int)
    /// v2.7+ normative length `m..n`, or `m..` with no upper bound (v2.8.2 §2.5.5.0).
    case range(min: Int, max: Int?)
    /// v2.7+ normative length as the allowed lengths `x,y,z` (v2.8.2 §2.5.5.0).
    case oneOf([Int])

    /// The rule a printed cell asserts on `version`, or nil when it asserts none a
    /// message can violate: a pre-v2.7 cell that is not a plain integer (`*`, `64K`),
    /// or is the v2.4 to v2.6 symbol 65536 or 99999 (all registered in the
    /// permanent-limitations register), and every v2.7+ cell in
    /// neither normative form. Those are conformance lengths (`32`, `40=`, `250#`),
    /// a storage minimum for receivers, not a limit on the message (v2.8.2 §2.5.5.3).
    static func parse(_ printed: String, version: Version) -> FieldLengthRule? {
        guard let cell = PrintedLength(printed.trimmingCharacters(in: .whitespaces)) else { return nil }
        switch (version.grammarVersion.printsMaximumLength, cell) {
        case (true, .number(let n)):
            // The very-large-number and variable-length symbols are not limits (v2.5.1
            // section 2.5.3.2 b, c), like the `64K` they replace.
            if version.grammarVersion.printsLengthSymbols, n == 65536 || n == 99999 { return nil }
            return .maximum(n)
        case (false, .range(let lower, let upper)): return .range(min: lower, max: upper)
        case (false, .list(let values)): return .oneOf(values)
        default: return nil
        }
    }

    /// Whether an occurrence of `length` characters satisfies the rule.
    func admits(_ length: Int) -> Bool {
        switch self {
        case .maximum(let n): return length <= n
        case .range(let lower, let upper): return length >= lower && (upper.map { length <= $0 } ?? true)
        case .oneOf(let values): return values.contains(length)
        }
    }
}
