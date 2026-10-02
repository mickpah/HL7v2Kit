// MessageStructure.swift
// The abstract message syntax of one HL7 message structure (ADR-019): an
// ordered tree of segments and segment groups, each with a minimum and a
// maximum occurrence. Data lives in Resources/structures/ and is emitted
// into MessageStructureTable by HL7v2KitCodegen; nothing is parsed at runtime.

/// One element of an abstract message syntax: a segment or a segment group.
///
/// `min` is 0 for an optional element (`[ ]`) and 1 otherwise; `max` is `nil`
/// for a repeating element (`{ }`) and 1 otherwise (v2.5.1 CH02 section 2.5.2).
/// The print's `{[X]}` reads the same as `[{X}]`: `min` 0, `max` `nil`.
///
/// - Note: This is an **open** enum per the API evolution policy (ADR-014):
///   ADR-019 adds a choice element before the first modelled version that
///   prints `< X | Y >`. Exhaustive `switch` over it must include
///   `@unknown default`.
public indirect enum StructureElement: Sendable, Equatable, Hashable {
    /// A segment, by its three-character ID.
    case segment(String, min: Int, max: Int?)
    /// A named segment group and its ordered elements.
    case group(String, min: Int, max: Int?, elements: [StructureElement])

    /// The minimum number of occurrences: 0 for an optional element.
    public var min: Int {
        switch self {
        case .segment(_, let min, _), .group(_, let min, _, _): return min
        }
    }

    /// The maximum number of occurrences; `nil` when unbounded.
    public var max: Int? {
        switch self {
        case .segment(_, _, let max), .group(_, _, let max, _): return max
        }
    }

    /// The group name, or nil for a segment.
    var groupName: String? {
        if case .group(let name, _, _, _) = self { return name }
        return nil
    }

    /// The segment IDs that can begin one occurrence of this element.
    var firstSet: Set<String> {
        switch self {
        case .segment(let id, _, _): return [id]
        case .group(_, _, _, let elements): return StructureElement.firstSet(of: elements[...])
        }
    }

    /// The segment reported when this element is required and absent: the
    /// first required segment it contains, or its first segment.
    var headSegmentID: String {
        switch self {
        case .segment(let id, _, _):
            return id
        case .group(_, _, _, let elements):
            let head = elements.first { $0.min > 0 } ?? elements.first
            return head?.headSegmentID ?? ""
        }
    }

    /// FIRST set of a sequence: the union of each element's FIRST set up to
    /// and including the first required element.
    static func firstSet(of elements: ArraySlice<StructureElement>) -> Set<String> {
        var result: Set<String> = []
        for element in elements {
            result.formUnion(element.firstSet)
            if element.min > 0 { break }
        }
        return result
    }
}

/// One HL7 message structure (the MSH-9.3 value, e.g. `ADT_A01`) as one
/// version's chapters print it.
public struct MessageStructure: Sendable, Equatable, Hashable {
    /// The structure ID, e.g. `"ORU_R01"`.
    public let id: String
    /// The HL7 version that prints this structure, e.g. `"2.5.1"`.
    public let version: String
    /// Every `CODE^EVENT` caption line printed for this structure; the event
    /// `*` stands for "varies" (`ACK^varies^ACK`).
    public let triggers: [String]
    /// Where the structure is printed, and where any group name the print
    /// omits was taken from.
    public let citation: String
    /// The ordered top-level elements, starting with MSH.
    public let elements: [StructureElement]

    /// Creates a structure from its parts; the generated table uses this.
    public init(id: String, version: String, triggers: [String], citation: String, elements: [StructureElement]) {
        self.id = id
        self.version = version
        self.triggers = triggers
        self.citation = citation
        self.elements = elements
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

    /// Every modelled structure of exactly `version`, keyed by ID (no
    /// grammar-version substitution).
    static func structures(for version: Version) -> [String: MessageStructure] {
        switch version {
        case .v2_5_1: return v2_5_1
        default:      return [:]
        }
    }
}
