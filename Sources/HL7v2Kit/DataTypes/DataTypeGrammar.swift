// DataTypeGrammar.swift
// The HL7 datatype component tables (Chapter 2A), per version. The per-version
// dictionaries live in `Generated/DataTypeGrammarTable+v<X_Y_Z>.swift`, emitted
// by `HL7v2KitCodegen` from `Resources/datatypes/<version>/`, which
// `scripts/extract-datatype-components.py` extracts from the spec PDFs. To
// correct a datatype, fix the extractor and re-extract; never edit the JSON.

/// One component of an HL7 datatype, as its version's component table prints it.
public struct ComponentGrammar: Sendable, Equatable, Hashable {
    /// 1-based position within the datatype (`CX.5` is `5`).
    public let index: Int
    /// The printed component name.
    public let name: String
    /// The component's own datatype code, or `""` for a withdrawn component,
    /// which the spec prints without one.
    public let dataType: String
    /// The printed optionality code, verbatim: `R`, `O`, `C`, `B`, `W`, or
    /// `RE` (required but may be empty, v2.7+). Kept as printed because `RE`
    /// has no `FieldOptionality` equivalent and mapping it would misstate it.
    public let optionalityCode: String
    /// The HL7 table numbers the component's TBL# cell binds. `9999` is the
    /// spec's "no table assigned" sentinel (v2.7+), not a table.
    public let tables: [String]

    /// Creates a component grammar entry.
    public init(index: Int, name: String, dataType: String, optionalityCode: String, tables: [String] = []) {
        self.index = index
        self.name = name
        self.dataType = dataType
        self.optionalityCode = optionalityCode
        self.tables = tables
    }
}

/// An HL7 datatype's component table for one version.
public struct DataTypeGrammar: Sendable, Equatable, Hashable {
    /// The datatype code, e.g. `"CX"`.
    public let dataType: String
    /// The HL7 version string the table was printed by, e.g. `"2.5.1"`.
    public let version: String
    /// The printed datatype name.
    public let name: String
    /// The components in index order, contiguous from 1.
    public let components: [ComponentGrammar]

    /// Creates a datatype grammar.
    public init(dataType: String, version: String, name: String, components: [ComponentGrammar]) {
        self.dataType = dataType
        self.version = version
        self.name = name
        self.components = components
    }

    /// The component at 1-based `index`, or `nil` when the datatype has none there.
    public func component(_ index: Int) -> ComponentGrammar? {
        index >= 1 && index <= components.count ? components[index - 1] : nil
    }
}

/// Per-version lookup of datatype component tables. Only v2.5.1, v2.6 and
/// v2.8.2 print them; earlier versions define components in prose, so their
/// lookups return `nil` (ADR-017).
public enum DataTypeGrammarTable {
    /// The component table of `dataType` as printed by `version`, or `nil`
    /// when that version prints none (or has withdrawn the datatype).
    public static func grammar(_ dataType: String, version: Version) -> DataTypeGrammar? {
        grammars(for: version)[dataType]
    }

    /// Every datatype component table printed by `version`, keyed by code.
    static func grammars(for version: Version) -> [String: DataTypeGrammar] {
        switch version {
        case .v2_5_1: return v2_5_1
        case .v2_6:   return v2_6
        case .v2_8_2: return v2_8_2
        default:      return [:]
        }
    }
}
