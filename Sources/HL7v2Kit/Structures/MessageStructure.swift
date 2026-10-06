// MessageStructure.swift
// The abstract message syntax of one HL7 message structure (ADR-019): an
// ordered tree of segments and segment groups, each with a minimum and a
// maximum occurrence. Data lives in Resources/structures/ and is emitted
// into MessageStructureTable by HL7v2KitCodegen; nothing is parsed at runtime.

/// One element of an abstract message syntax: a segment, a segment group,
/// a choice between alternatives, or an open slot.
///
/// `min` is 0 for an optional element (`[ ]`) and 1 otherwise; `max` is `nil`
/// for a repeating element (`{ }`) and 1 otherwise (v2.5.1 CH02 section 2.5.2).
/// The print's `{[X]}` reads the same as `[{X}]`: `min` 0, `max` `nil`.
///
/// - Note: This is an **open** enum per the API evolution policy (ADR-014):
///   a later release may add cases, as P8b-6 added ``choice(_:min:max:alternatives:)``
///   and v3.15.0 ``slot(_:min:max:citation:)``.
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
    /// An open slot (S3-1, ADR-019 amendment 2026-10-06): the print's
    /// "Order Detail Segment OBR, etc." or `< OBR | etc. >`, whose filling
    /// segments the standard does not enumerate (CH04 4.2.2.4 names only
    /// examples). `min` and `max` bound the number of segments it takes. It
    /// takes any segment except MSH, including one that could begin what
    /// follows it: a message is reported only when no reading of it fits the
    /// structure. The consequences:
    ///
    /// - A required segment after the slot is still enforced, and a defect
    ///   before it is still found.
    /// - A misplaced optional segment after the slot may be read as slot
    ///   content and is then not reported: the faithful reading of an
    ///   unbounded "etc.".
    /// - Z-segments and ADD are skipped as everywhere, so they never fill
    ///   the slot: a slot holding only them counts as empty.
    /// - A finding at a point where the slot could still take a segment
    ///   names the slot among the segments expected there, and a finding
    ///   about an absent slot names it.
    /// - With the slot inside a repeating group, two or more occurrences of
    ///   that group make the readings disagree on the group boundaries, so
    ///   the group spans are withheld for that message (one occurrence
    ///   keeps its span).
    ///
    /// The name is the one the print gives ("Order Detail Segment"), or nil.
    /// `citation` gives where the slot is printed and what says it is open.
    /// A slot has no ``children`` and no ``segmentIDs``; a structure holding
    /// one is matched exactly.
    case slot(String?, min: Int, max: Int?, citation: String)

    /// The minimum number of occurrences: 0 for an optional element.
    public var min: Int {
        switch self {
        case .segment(_, let min, _), .group(_, let min, _, _), .choice(_, let min, _, _),
             .slot(_, let min, _, _): return min
        }
    }

    /// The maximum number of occurrences; `nil` when unbounded.
    public var max: Int? {
        switch self {
        case .segment(_, _, let max), .group(_, _, let max, _), .choice(_, _, let max, _),
             .slot(_, _, let max, _): return max
        }
    }

    /// The elements directly inside this one: a group's elements in order,
    /// a choice's alternatives in order, and none for a segment or a slot.
    public var children: [StructureElement] {
        switch self {
        case .segment, .slot: return []
        case .group(_, _, _, let elements): return elements
        case .choice(_, _, _, let alternatives): return alternatives
        }
    }

    /// Every segment ID this element can contain, at any depth and in any
    /// alternative. A slot names no segment, so it contributes none: the
    /// segments that fill it are not part of the structure's definition.
    public var segmentIDs: Set<String> {
        if case .segment(let id, _, _) = self { return [id] }
        return children.reduce(into: Set<String>()) { $0.formUnion($1.segmentIDs) }
    }

    /// The group or choice name, or nil for a segment and an unnamed choice.
    var groupName: String? {
        switch self {
        case .segment, .slot: return nil
        case .group(let name, _, _, _): return name
        case .choice(let name, _, _, _): return name
        }
    }

    /// How the lint names this element in a path: the segment ID, the group
    /// or choice name, or `<A|B>` (the alternatives' labels) for an unnamed
    /// choice; a slot's printed name, or `open slot`. Findings about an
    /// absent slot name it by this label.
    var label: String {
        switch self {
        case .segment(let id, _, _): return id
        case .group(let name, _, _, _): return name
        case .choice(let name, _, _, let alternatives):
            return name ?? "<" + alternatives.map(\.label).joined(separator: "|") + ">"
        case .slot(let name, _, _, _): return name ?? "open slot"
        }
    }

    /// The FIRST-set member that stands for a slot: any segment. No segment
    /// ID is `*`, so it meets another element's FIRST set only at a slot.
    static let anySegment = "*"

    /// The segment IDs that can begin one occurrence of this element; for a
    /// choice, the union over its alternatives; for a slot, ``anySegment``.
    var firstSet: Set<String> {
        switch self {
        case .segment(let id, _, _): return [id]
        case .group(_, _, _, let elements): return StructureElement.firstSet(of: elements[...])
        case .choice(_, _, _, let alternatives):
            return alternatives.reduce(into: Set<String>()) { $0.formUnion($1.firstSet) }
        case .slot: return [StructureElement.anySegment]
        }
    }

    /// Whether this element can match no segment at all: it is optional, or
    /// it is a group all of whose elements are nullable, or a choice one of
    /// whose alternatives is nullable.
    var isNullable: Bool {
        switch self {
        case .segment(_, let min, _), .slot(_, let min, _, _):
            return min == 0
        case .group(_, let min, _, let elements):
            return min == 0 || elements.allSatisfy(\.isNullable)
        case .choice(_, let min, _, let alternatives):
            return min == 0 || alternatives.contains(where: \.isNullable)
        }
    }

    /// The segment reported when this element is required and absent: the
    /// first non-nullable segment it contains, or its first segment; for a
    /// choice, its first alternative's; for a slot, its label.
    var headSegmentID: String {
        switch self {
        case .segment(let id, _, _):
            return id
        case .slot:
            return label
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
    /// The profile a constrained structure belongs to (`"au-adrm-2021"`), or
    /// nil for a base structure (P8b-4, ADR-019 data model, ruling G9).
    let profile: String?
    /// The base version a profile structure constrains (`"2.4"`); nil for a
    /// base structure.
    let baseVersion: String?
    /// The conformance point a profile structure enforces
    /// (`"HL7au:00060.1"`); nil for a base structure.
    let rule: String?

    // Internal (P8 final review): there is no public matcher, so a structure
    // built outside the package has no use. The generated tables and the
    // tests (`@testable`) use it. `requiresExactMatch` nil means "lint now"
    // (tests and synthetic structures); the generated tables always pass the
    // codegen's result. The profile tags are set only for the generated
    // profile tables (P8b-4).
    init(id: String, version: String, triggers: [String], citation: String,
         profile: String? = nil, baseVersion: String? = nil, rule: String? = nil,
         requiresExactMatch: Bool? = nil, elements: [StructureElement]) {
        self.id = id
        self.version = version
        self.triggers = triggers
        self.citation = citation
        self.profile = profile
        self.baseVersion = baseVersion
        self.rule = rule
        self.elements = elements
        self.requiresExactMatch = requiresExactMatch ?? !StructureMatcher.lint(elements).isDeterministic
    }

    /// Whether the chapters print `messageCode^triggerEvent` for this structure.
    public func accepts(messageCode: String, triggerEvent: String) -> Bool {
        triggers.contains("\(messageCode)^\(triggerEvent)") || triggers.contains("\(messageCode)^*")
    }
}

/// The message structures each HL7 version defines, generated from
/// `Resources/structures/` (ADR-019). Every supported version is complete:
/// each structure its print gives is either modelled here or registered as
/// not modelled with a reason (an unexpandable placeholder or template, a
/// print naming segments the version does not define, a Table 0354 row with
/// no printed syntax). A ``structure(_:version:)`` miss therefore means the ID
/// is not a modelled structure of that version: it may be a registered one,
/// or one the version does not print at all. ``registration(_:version:)``
/// tells the two apart, returning a registered structure's triggers and
/// reason and nil for an unprinted ID (owner decision 8, 2026-10-06). The
/// ``Validator`` draws the same line, reporting a registered structure as
/// ``IssueCode/messageStructureNotModelled(structure:)`` with its reason and
/// an unprinted ID as ``IssueCode/messageStructureMismatch(declared:trigger:)``.
///
/// Lookups resolve ``Version/grammarVersion`` first, so ``Version/v2_8``
/// reads the v2.8.2 structures, as the ``Validator`` does for its grammar.
public enum MessageStructureTable {
    /// The structure `id` as `version` prints it, or nil when not modelled.
    public static func structure(_ id: String, version: Version) -> MessageStructure? {
        structures(for: version.grammarVersion)[id]
    }

    /// The structures whose caption lines include `messageCode^triggerEvent`,
    /// sorted by ID. More than one entry occurs only where the print shares
    /// the trigger between structures (a declared shared trigger, ADR-019
    /// lookup rule 2); a test forbids any other.
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

    /// The structures `version`'s grammar version prints, or its Table 0354
    /// lists, that are registered as not modelled, keyed by ID (P8b-9).
    static func notModelled(for version: Version) -> [String: NotModelledStructure] {
        generatedNotModelled(for: version)
    }

    /// The reason a (trigger, structure ID) pair that `version`'s grammar
    /// version prints is not modelled although the structure is modelled for
    /// other triggers (a query profile's response row, P8b-final), or nil.
    static func printedPairReason(trigger: String, structure: String, version: Version) -> String? {
        generatedPrintedPairs(for: version.grammarVersion)["\(trigger) \(structure)"]
    }

    /// The segments `version`'s grammar version lists in Appendix A as
    /// withdrawn or deprecated, with no definition, that its structures may
    /// still name (ADR-019 S2-1 amendment), keyed by segment ID.
    static func withdrawnSegments(for version: Version) -> [String: WithdrawnSegment] {
        withdrawnIndex[version.grammarVersion] ?? [:]
    }

    // Built once: the Validator reads it for every message.
    private static let withdrawnIndex: [Version: [String: WithdrawnSegment]] = Dictionary(
        uniqueKeysWithValues: Set(Version.allCases.map(\.grammarVersion)).map { ($0, generatedWithdrawnSegments(for: $0)) })

    /// The modelled and the registered structure IDs whose triggers accept
    /// `messageCode`^`triggerEvent` on `version`'s grammar version, each
    /// sorted: the same sets as filtering ``structures(for:)`` and
    /// ``notModelled(for:)`` with `accepts`, read from an index built once
    /// per grammar version (P8b-18, performance).
    static func owners(messageCode: String, triggerEvent: String,
                       version: Version) -> (modelled: [String], registered: [String]) {
        guard let index = triggerIndex[version.grammarVersion] else { return ([], []) }
        func look(_ map: [String: [String]]) -> [String] {
            let exact = map["\(messageCode)^\(triggerEvent)"] ?? []
            let any = map["\(messageCode)^*"] ?? []
            return any.isEmpty ? exact : Array(Set(exact + any)).sorted()
        }
        return (look(index.modelled), look(index.registered))
    }

    private static let triggerIndex: [Version: (modelled: [String: [String]], registered: [String: [String]])] = {
        func build(_ entries: [(id: String, triggers: [String])]) -> [String: [String]] {
            var map: [String: [String]] = [:]
            for entry in entries {
                for trigger in Set(entry.triggers) { map[trigger, default: []].append(entry.id) }
            }
            return map.mapValues { $0.sorted() }
        }
        var index: [Version: (modelled: [String: [String]], registered: [String: [String]])] = [:]
        for version in Set(Version.allCases.map(\.grammarVersion)) {
            index[version] = (build(structures(for: version).values.map { ($0.id, $0.triggers) }),
                              build(notModelled(for: version).map { ($0.key, $0.value.triggers) }))
        }
        return index
    }()

    /// The constrained structures `locale`'s profile prints, keyed by the
    /// base structure ID they constrain (P8b-4): the ADRM-2021 structures for
    /// ``HL7Locale/auLocalisation``, none otherwise. Generated from
    /// `Resources/structures/profiles/<locale raw value>/`.
    static func profileStructures(for locale: HL7Locale) -> [String: MessageStructure] {
        switch locale {
        case .auLocalisation: return auADRM2021
        case .international: return [:]
        }
    }
}

/// A structure a version prints (or its Table 0354 lists) that is registered
/// as not modelled: the triggers its captions print and the reason
/// (permanent-limitations register section E). A message naming it is
/// reported as not modelled, never as a mismatch.
struct NotModelledStructure: Sendable, Equatable {
    let triggers: [String]
    let reason: String

    func accepts(messageCode: String, triggerEvent: String) -> Bool {
        triggers.contains("\(messageCode)^\(triggerEvent)") || triggers.contains("\(messageCode)^*")
    }
}

/// A segment a version lists in Appendix A as withdrawn or deprecated with no
/// definition (`Resources/structures/overrides.json` withdrawnSegments): the
/// status as printed, the last version that defines it and the citation. A
/// structure of the version may name it; it is matched by segment ID and its
/// fields are not validated (ADR-019 S2-1 amendment).
struct WithdrawnSegment: Sendable, Equatable {
    let printed: String
    let definedThrough: String
    let citation: String
}
