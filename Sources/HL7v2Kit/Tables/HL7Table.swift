// HL7Table.swift
// One HL7 code table as printed by one spec version (Appendix A;
// v2.8.2 Chapter 2C). Instances are emitted by HL7v2KitCodegen from
// Resources/tables/<version>/<NNNN>.json — see HL7TableRegistry.

import Foundation

/// An HL7 code table: its number, printed name, ownership kind and the
/// value rows the spec prints for one version. M6-O6.
public struct HL7Table: Sendable, Equatable, Hashable {
    /// Who defines the table's values. `ID`-typed fields draw from
    /// `hl7` tables ("the value must be from the table"); `IS`-typed
    /// fields draw from `userDefined` tables (suggested values only).
    public enum Kind: String, Sendable, Equatable, Hashable {
        /// HL7-defined values — the spec fixes the value set.
        case hl7 = "HL7"
        /// Site-defined values — the spec's rows are suggestions only.
        case userDefined = "User"
    }

    /// One printed value row.
    public struct Entry: Sendable, Equatable, Hashable {
        /// The value as printed in the table's Value column.
        public let code: String
        /// The value's printed description.
        public let description: String

        /// Create one value row.
        public init(code: String, description: String) {
            self.code = code
            self.description = description
        }
    }

    /// A printed row that names a family of codes rather than one code:
    /// Table 0203 `NNxxx`, "National Person Identifier where the xxx is the
    /// ISO table 3166 3-character (alphabetic) country code" (v2.3.1 to v2.8.2).
    /// The row is not itself a code; a value is a member when it matches
    /// ``regex`` in full.
    public struct CodePattern: Sendable, Equatable, Hashable {
        /// The row's Value column as printed, e.g. `"NNxxx"`.
        public let code: String
        /// The row's printed description.
        public let description: String
        /// An anchored regular expression (`^...$`) for the family, e.g. `"^NN[A-Z]{3}$"`.
        public let regex: String

        /// Create one pattern row.
        public init(code: String, description: String, regex: String) {
            self.code = code
            self.description = description
            self.regex = regex
        }

        /// `true` when `value` belongs to the family the row names: the whole
        /// value matches ``regex``, not merely a substring of it. `regex` is
        /// wrapped in `\A(?:...)\z` so this holds even when the caller-supplied
        /// pattern itself omits `^`/`$` anchors.
        public func matches(_ value: String) -> Bool {
            guard let full = try? NSRegularExpression(pattern: "\\A(?:\(regex))\\z") else { return false }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            return full.firstMatch(in: value, range: range) != nil
        }
    }

    /// Four-digit table number as printed, e.g. `"0074"`.
    public let number: String
    /// Printed table name, e.g. `"Diagnostic Service Section ID"`.
    public let name: String
    /// Who defines the table's values.
    public let kind: Kind
    /// `true` when the spec text explicitly permits values outside the
    /// printed rows (0003 / 0076 Z-codes, 0396 `99zzz` local coding
    /// systems, 0399 ISO 3166 by reference, 0104 local version IDs).
    /// Such a table is never enforced as a closed set.
    public let permitsLocalExtensions: Bool
    /// Value rows in printed order. Pattern rows are not here; see ``patterns``.
    public let entries: [Entry]
    /// Printed rows that name a family of codes. Empty for almost every table.
    public let patterns: [CodePattern]

    /// Create a code table.
    public init(
        number: String,
        name: String,
        kind: Kind,
        permitsLocalExtensions: Bool = false,
        entries: [Entry],
        patterns: [CodePattern] = []
    ) {
        self.number = number
        self.name = name
        self.kind = kind
        self.permitsLocalExtensions = permitsLocalExtensions
        self.entries = entries
        self.patterns = patterns
    }

    /// Exact, case-sensitive membership in the printed rows, or a full match
    /// of one of the table's pattern rows.
    public func contains(_ code: String) -> Bool {
        entries.contains { $0.code == code } || patterns.contains { $0.matches(code) }
    }

    /// The literal codes in printed order (pattern rows excluded).
    public var codes: [String] { entries.map(\.code) }

    /// `true` when the Validator may treat the table as a closed set:
    /// HL7-defined, no local extensions permitted, and at least one
    /// printed row. Anything else is informational only (req #4).
    public var isClosed: Bool {
        kind == .hl7 && !permitsLocalExtensions && !entries.isEmpty
    }
}
