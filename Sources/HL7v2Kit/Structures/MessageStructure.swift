// MessageStructure.swift
// The abstract message syntax of one HL7 message structure (ADR-019): an
// ordered tree of segments and segment groups, each with a minimum and a
// maximum occurrence. Data lives in Resources/structures/ and is emitted
// into MessageStructureTable by HL7v2KitCodegen; nothing is parsed at runtime.

/// One element of an abstract message syntax: a segment, a segment group,
/// or a choice between alternatives.
///
/// `min` is 0 for an optional element (`[ ]`) and 1 otherwise; `max` is `nil`
/// for a repeating element (`{ }`) and 1 otherwise (v2.5.1 CH02 section 2.5.2).
/// The print's `{[X]}` reads the same as `[{X}]`: `min` 0, `max` `nil`.
///
/// - Note: This is an **open** enum per the API evolution policy (ADR-014):
///   a later release may add cases, as P8b-6 added ``choice(_:min:max:alternatives:)``.
///   Code that walks the tree must handle `@unknown default`; ``children``
///   and ``segmentIDs`` cover every case, so a walker that recurses through
///   them never skips the segments inside a case it does not know.
public indirect enum StructureElement: Sendable, Equatable, Hashable {
    /// A segment, by its three-character ID.
    case segment(String, min: Int, max: Int?)
    /// A named segment group and its ordered elements.
    case group(String, min: Int, max: Int?, elements: [StructureElement])
    /// One of several alternatives, printed `< A | B >`: each occurrence
    /// takes exactly one alternative (v2.5.1 CH02 section 2.5.2). The name
    /// is the one the print gives (named choices appear from v2.7.1), or
    /// nil; `alternatives` holds at least two elements, each with its own
    /// occurrence bounds.
    case choice(String?, min: Int, max: Int?, alternatives: [StructureElement])

    /// The minimum number of occurrences: 0 for an optional element.
    public var min: Int {
        switch self {
        case .segment(_, let min, _), .group(_, let min, _, _), .choice(_, let min, _, _): return min
        }
    }

    /// The maximum number of occurrences; `nil` when unbounded.
    public var max: Int? {
        switch self {
        case .segment(_, _, let max), .group(_, _, let max, _), .choice(_, _, let max, _): return max
        }
    }

    /// The elements directly inside this one: a group's elements in order,
    /// a choice's alternatives in order, and none for a segment.
    public var children: [StructureElement] {
        switch self {
        case .segment: return []
        case .group(_, _, _, let elements): return elements
        case .choice(_, _, _, let alternatives): return alternatives
        }
    }

    /// Every segment ID this element can contain, at any depth and in any
    /// alternative.
    public var segmentIDs: Set<String> {
        if case .segment(let id, _, _) = self { return [id] }
        return children.reduce(into: Set<String>()) { $0.formUnion($1.segmentIDs) }
    }

    /// The group or choice name, or nil for a segment and an unnamed choice.
    var groupName: String? {
        switch self {
        case .segment: return nil
        case .group(let name, _, _, _): return name
        case .choice(let name, _, _, _): return name
        }
    }

    /// How the lint names this element in a path: the segment ID, the group
    /// or choice name, or `<A|B>` (the alternatives' labels) for an unnamed choice.
    var label: String {
        switch self {
        case .segment(let id, _, _): return id
        case .group(let name, _, _, _): return name
        case .choice(let name, _, _, let alternatives):
            return name ?? "<" + alternatives.map(\.label).joined(separator: "|") + ">"
        }
    }

    /// The segment IDs that can begin one occurrence of this element; for a
    /// choice, the union over its alternatives.
    var firstSet: Set<String> {
        switch self {
        case .segment(let id, _, _): return [id]
        case .group(_, _, _, let elements): return StructureElement.firstSet(of: elements[...])
        case .choice(_, _, _, let alternatives):
            return alternatives.reduce(into: Set<String>()) { $0.formUnion($1.firstSet) }
        }
    }

    /// Whether this element can match no segment at all: it is optional, or
    /// it is a group all of whose elements are nullable, or a choice one of
    /// whose alternatives is nullable.
    var isNullable: Bool {
        switch self {
        case .segment(_, let min, _):
            return min == 0
        case .group(_, let min, _, let elements):
            return min == 0 || elements.allSatisfy(\.isNullable)
        case .choice(_, let min, _, let alternatives):
            return min == 0 || alternatives.contains(where: \.isNullable)
        }
    }

    /// The segment reported when this element is required and absent: the
    /// first non-nullable segment it contains, or its first segment; for a
    /// choice, its first alternative's.
    var headSegmentID: String {
        switch self {
        case .segment(let id, _, _):
            return id
        case .group(_, _, _, let elements):
            let head = elements.first { !$0.isNullable } ?? elements.first
            return head?.headSegmentID ?? ""
        case .choice(_, _, _, let alternatives):
            return alternatives.first?.headSegmentID ?? ""
        }
    }

    /// FIRST set of a sequence: the union of each element's FIRST set up to
    /// and including the first element that is not nullable.
    static func firstSet(of elements: ArraySlice<StructureElement>) -> Set<String> {
        var result: Set<String> = []
        for element in elements {
            result.formUnion(element.firstSet)
            if !element.isNullable { break }
        }
        return result
    }
}

/// One HL7 message structure (the MSH-9.3 value, e.g. `ADT_A01`) as one
/// version's chapters print it.
public struct MessageStructure: Sendable, Equatable, Hashable {
    /// The structure ID, e.g. `"ORU_R01"`.
    public let id: String
    /// The printed HL7 version string of the chapters this structure comes
    /// from, e.g. `"2.5.1"`, as ``DataTypeGrammar/version`` and
    /// ``SegmentGrammar/version`` carry it.
    public let version: String
    /// Every caption line printed for this structure, each as
    /// `"CODE^EVENT"` (MSH-9.1 and MSH-9.2, e.g. `"ADT^A04"`). `"CODE^*"`
    /// means any event with that message code: the print's "varies"
    /// (`ACK^varies^ACK` is stored as `"ACK^*"`).
    public let triggers: [String]
    /// Where the structure is printed, and where any group name the print
    /// omits was taken from.
    public let citation: String
    /// The ordered top-level elements, starting with MSH.
    public let elements: [StructureElement]
    /// Whether the structure fails the ADR-019 determinism lint, so the
    /// Validator matches it with `ExactStructureMatcher` instead of the
    /// one-pass matcher (P8b-12). The codegen lints each structure it emits
    /// and renders the result; a test re-lints every generated structure.
    let requiresExactMatch: Bool

    // Internal (P8 final review): there is no public matcher, so a structure
    // built outside the package has no use, and the AU overlay will add
    // fields. The generated table and the tests (`@testable`) use it.
    // `requiresExactMatch` nil means "lint now" (tests and synthetic
    // structures); the generated table always passes the codegen's result.
    init(id: String, version: String, triggers: [String], citation: String,
         requiresExactMatch: Bool? = nil, elements: [StructureElement]) {
        self.id = id
        self.version = version
        self.triggers = triggers
        self.citation = citation
        self.elements = elements
        self.requiresExactMatch = requiresExactMatch ?? !StructureMatcher.lint(elements).isDeterministic
    }

    /// Whether the chapters print `messageCode^triggerEvent` for this structure.
    public func accepts(messageCode: String, triggerEvent: String) -> Bool {
        triggers.contains("\(messageCode)^\(triggerEvent)") || triggers.contains("\(messageCode)^*")
    }
}

/// The message structures each HL7 version defines, generated from
/// `Resources/structures/` (ADR-019). Only the versions and structures
/// modelled so far are present; a lookup miss means "not modelled".
///
/// Lookups resolve ``Version/grammarVersion`` first, so ``Version/v2_8``
/// reads the v2.8.2 structures, as the ``Validator`` does for its grammar.
public enum MessageStructureTable {
    /// The structure `id` as `version` prints it, or nil when not modelled.
    public static func structure(_ id: String, version: Version) -> MessageStructure? {
        structures(for: version.grammarVersion)[id]
    }

    /// The structures whose caption lines include `messageCode^triggerEvent`,
    /// sorted by ID. More than one entry would be a data defect; a test
    /// forbids it.
    public static func structures(messageCode: String, triggerEvent: String, version: Version) -> [MessageStructure] {
        structures(for: version.grammarVersion).values
            .filter { $0.accepts(messageCode: messageCode, triggerEvent: triggerEvent) }
            .sorted { $0.id < $1.id }
    }

    /// Every modelled structure of `version`'s grammar version, keyed by ID.
    /// The switch is generated from Resources/structures/completeness.json
    /// (`MessageStructureTable+Versions.swift`).
    static func structures(for version: Version) -> [String: MessageStructure] {
        generatedStructures(for: version)
    }

    /// Whether every structure `version`'s grammar version prints is modelled
    /// (ADR-019 lookup rule 1). `completeVersions` replaces the generated set;
    /// tests pass a synthetic one.
    static func isComplete(_ version: Version, completeVersions: Set<Version> = MessageStructureTable.completeVersions) -> Bool {
        completeVersions.contains(version.grammarVersion)
    }
}
