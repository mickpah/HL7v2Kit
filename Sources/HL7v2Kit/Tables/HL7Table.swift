// HL7Table.swift
// One HL7 code table as printed by one spec version (Appendix A;
// v2.8.2 Chapter 2C). Instances are emitted by HL7v2KitCodegen from
// Resources/tables/<version>/<NNNN>.json — see HL7TableRegistry.

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
    /// Value rows in printed order.
    public let entries: [Entry]

    /// Create a code table.
    public init(
        number: String,
        name: String,
        kind: Kind,
        permitsLocalExtensions: Bool = false,
        entries: [Entry]
    ) {
        self.number = number
        self.name = name
        self.kind = kind
        self.permitsLocalExtensions = permitsLocalExtensions
        self.entries = entries
    }

    /// Exact, case-sensitive membership.
    public func contains(_ code: String) -> Bool {
        entries.contains { $0.code == code }
    }

    /// The codes in printed order.
    public var codes: [String] { entries.map(\.code) }

    /// `true` when the Validator may treat the table as a closed set:
    /// HL7-defined, no local extensions permitted, and at least one
    /// printed row. Anything else is informational only (req #4).
    public var isClosed: Bool {
        kind == .hl7 && !permitsLocalExtensions && !entries.isEmpty
    }
}
