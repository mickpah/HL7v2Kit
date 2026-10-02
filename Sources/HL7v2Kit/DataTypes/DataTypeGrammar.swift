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
    /// which the spec prints without one, and for a v2.3 to v2.4 component
    /// whose Components / Format line prints no code (`TS.1`, `TS.2`, and
    /// `CD.1` on v2.3 and v2.3.1).
    public let dataType: String
    /// The printed optionality code, verbatim: `R`, `O`, `C`, `B`, `W`, or
    /// `RE` (required but may be empty, v2.7+). Kept as printed because `RE`
    /// has no `FieldOptionality` equivalent and mapping it would misstate it.
    /// `""` on v2.3 to v2.4, whose prose definitions print no optionality.
    public let optionalityCode: String
    /// The HL7 table numbers the component's TBL# cell binds. `9999` is the
    /// spec's "no table assigned" sentinel (v2.7+), not a table.
    public let tables: [String]
    /// The LEN cell the component table prints, verbatim, or `nil` (the prose
    /// definitions of v2.3 to v2.4 print none). Recorded, never enforced (M25).
    public let length: String?
    /// For a component the table prints `C`: the condition under which it is
    /// required, as the spec's prose states it, in a small predicate language
    /// over the sibling components of the same repetition: `"5 populated"`,
    /// `"2 empty"`, joined by `AND` / `OR` with parentheses. `nil` for every
    /// other component, and for a `C` component whose prose states no
    /// condition the model can carry (`Resources/datatypes/conditions.json`
    /// lists those with their reasons). When the predicate holds and the
    /// component is empty, ``IssueCode/conditionalComponentMissing`` is
    /// reported. M26.
    public let condition: String?
    /// A stated condition of the same language that the specification's own
    /// example messages violate: the "as of v2.7" conformance sentences (a
    /// coding system whenever a code is valued, an assigning authority
    /// whenever an identifier is valued, and kin). Never checked by default;
    /// ``ValidationOptions/conformanceConditionSeverity`` opts in, reporting
    /// ``IssueCode/conformanceConditionMissing``. The measurements are in
    /// `Resources/datatypes/conditions.json`. M27.
    public let conformanceCondition: String?

    /// Creates a component grammar entry.
    public init(index: Int, name: String, dataType: String, optionalityCode: String, tables: [String] = [], length: String? = nil, condition: String? = nil, conformanceCondition: String? = nil) {
        self.index = index
        self.name = name
        self.dataType = dataType
        self.optionalityCode = optionalityCode
        self.tables = tables
        self.length = length
        self.condition = condition
        self.conformanceCondition = conformanceCondition
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

/// Per-version lookup of datatype component tables. v2.5.1, v2.6 and v2.8.2
/// print them as figures. v2.3, v2.3.1 and v2.4 define components in numbered
/// prose subsections; their grammar is recovered from those headings, a table
/// binding is kept only when it names one table whose number and stated name
/// both match the version's own registry, and `optionalityCode` is `""`
/// because the prose prints none (ADR-017 addendum, M13).
public enum DataTypeGrammarTable {
    /// The component table of `dataType` as printed by `version`, or `nil`
    /// when that version prints none (or has withdrawn the datatype).
    public static func grammar(_ dataType: String, version: Version) -> DataTypeGrammar? {
        grammars(for: version)[dataType]
    }

    /// Every datatype component table printed by `version`, keyed by code.
    static func grammars(for version: Version) -> [String: DataTypeGrammar] {
        switch version {
        case .v2_3:   return v2_3
        case .v2_3_1: return v2_3_1
        case .v2_4:   return v2_4
        case .v2_5_1: return v2_5_1
        case .v2_6:   return v2_6
        case .v2_8_2: return v2_8_2
        case .v2_8:   return [:]
        }
    }
}

/// The predicate language of ``ComponentGrammar/condition``: `<n> populated`,
/// `<n> empty`, `repeated` (the field has more than one populated
/// repetition; XAD.7), `AND`, `OR`, parentheses. Fail-safe: an unparseable
/// expression evaluates `false`, so a malformed rule can never fire (req #4).
enum ComponentCondition {
    static func holds(_ expression: String, populated: (Int) -> Bool, repeated: Bool = false) -> Bool {
        var tokens = tokenize(expression)[...]
        // Index 0 is not a component; parseAtom asks for it on the `repeated` token.
        let p: (Int) -> Bool = { $0 == 0 ? repeated : populated($0) }
        guard let value = parseOr(&tokens, p), tokens.isEmpty else { return false }
        return value
    }

    /// Whether `expression` parses: the same parse ``holds(_:populated:repeated:)``
    /// runs, with every atom false. An unparseable condition would never fire (P4-25).
    static func parses(_ expression: String) -> Bool {
        var tokens = tokenize(expression)[...]
        return parseOr(&tokens, { _ in false }) != nil && tokens.isEmpty
    }

    private static func tokenize(_ s: String) -> [String] {
        s.replacingOccurrences(of: "(", with: " ( ").replacingOccurrences(of: ")", with: " ) ")
            .split(separator: " ").map { String($0).uppercased() }
    }

    private static func parseOr(_ t: inout ArraySlice<String>, _ p: (Int) -> Bool) -> Bool? {
        guard var value = parseAnd(&t, p) else { return nil }
        while t.first == "OR" {
            t.removeFirst()
            guard let rhs = parseAnd(&t, p) else { return nil }
            value = value || rhs
        }
        return value
    }

    private static func parseAnd(_ t: inout ArraySlice<String>, _ p: (Int) -> Bool) -> Bool? {
        guard var value = parseAtom(&t, p) else { return nil }
        while t.first == "AND" {
            t.removeFirst()
            guard let rhs = parseAtom(&t, p) else { return nil }
            value = value && rhs
        }
        return value
    }

    private static func parseAtom(_ t: inout ArraySlice<String>, _ p: (Int) -> Bool) -> Bool? {
        guard let first = t.first else { return nil }
        if first == "(" {
            t.removeFirst()
            guard let inner = parseOr(&t, p), t.first == ")" else { return nil }
            t.removeFirst()
            return inner
        }
        if first == "REPEATED" {
            t.removeFirst()
            return p(0)
        }
        guard let index = Int(first), index >= 1, t.count >= 2 else { return nil }
        let state = t[t.startIndex + 1]
        t.removeFirst(2)
        switch state {
        case "POPULATED": return p(index)
        case "EMPTY":     return !p(index)
        default:          return nil
        }
    }
}
