// StructureChoiceKey.swift
// S4-1 (ADR-019 amendment 2026-10-06): the field whose value selects a keyed
// choice's alternative, and the resolution of a structure's keyed choices
// against a message before it is matched.

/// The key of a ``StructureElement/keyedChoice(_:min:max:key:alternatives:)``:
/// the field of the message whose value selects the alternative, and the
/// printed map from each value to the alternative it selects (S4-1).
///
/// v2.5.1 CH08 8.8.3 to 8.8.7 note "MFI-1 - Master File Identifier = OMA for
/// numeric observations" and so on, so MFN_M03's key is MFI-1 component 1
/// with OMA to OME mapped to the MFN^M08 to MFN^M12 groups.
public struct StructureChoiceKey: Sendable, Equatable, Hashable {
    /// The segment that carries the key, e.g. `"MFI"`; its first occurrence
    /// in the message is read.
    public let segmentID: String
    /// The field's sequence number in that segment, e.g. `1`.
    public let field: Int
    /// The component read from the field's first repetition (1 for the
    /// identifier of a CE or CWE).
    public let component: Int
    /// Each printed value and the name of the alternative it selects.
    public let alternatives: [String: String]
    /// Where the print gives the map.
    public let citation: String

    /// A key read from `segmentID`-`field`, component `component`, mapping
    /// each value in `alternatives` to an alternative's name.
    public init(segmentID: String, field: Int, component: Int, alternatives: [String: String], citation: String) {
        self.segmentID = segmentID
        self.field = field
        self.component = component
        self.alternatives = alternatives
        self.citation = citation
    }

    /// The key field as the print names it: `MFI-1`, or `MFI-1.2` for a
    /// later component.
    var fieldName: String {
        "\(segmentID)-\(field)" + (component > 1 ? ".\(component)" : "")
    }

    /// The key's value in `message`: the first occurrence of the key
    /// segment, the field's first repetition, the component's first
    /// subcomponent; nil when the segment is absent or the value empty.
    func value(in message: Message) -> String? {
        guard let segment = message.segments.first(where: { $0.segmentID == segmentID }),
              let repetition = segment.field(field)?.first,
              repetition.components.indices.contains(component - 1),
              let value = repetition.components[component - 1].subcomponents.first?.value,
              !value.isEmpty, value != "\"\"" else { return nil }
        return value
    }
}

/// A structure with its keyed choices resolved for one message, or the key
/// value the print's map does not hold.
enum KeyedResolution: Sendable, Equatable {
    case resolved(MessageStructure)
    case unmapped(key: StructureChoiceKey, value: String)
}

extension MessageStructure {
    /// Whether any element, at any depth, is a keyed choice.
    var hasKeyedChoice: Bool {
        func holds(_ elements: [StructureElement]) -> Bool {
            elements.contains {
                if case .keyedChoice = $0 { return true }
                return holds($0.children)
            }
        }
        return holds(elements)
    }

    /// This structure with each keyed choice replaced by the alternative its
    /// key value selects, as a group with the choice's bounds; a key with no
    /// value (`value` returns nil) leaves the plain choice of every
    /// alternative. The first value the map does not hold is returned
    /// instead. A structure with no keyed choice is returned unchanged.
    func resolvingKeyedChoices(_ value: (StructureChoiceKey) -> String?) -> KeyedResolution {
        guard hasKeyedChoice else { return .resolved(self) }
        var selections: [String] = []
        var unmapped: (StructureChoiceKey, String)?
        func resolve(_ elements: [StructureElement]) -> [StructureElement] {
            elements.map { element in
                switch element {
                case .keyedChoice(_, let min, let max, let key, let alternatives):
                    guard let found = value(key) else {
                        selections.append("\(key.fieldName) absent")
                        return .choice(element.groupName, min: min, max: max, alternatives: resolve(alternatives))
                    }
                    guard let name = key.alternatives[found],
                          case .group(_, _, _, let inner)? = alternatives.first(where: { $0.groupName == name }) else {
                        if unmapped == nil { unmapped = (key, found) }
                        return element
                    }
                    selections.append("\(key.fieldName)=\(found)")
                    return .group(name, min: min, max: max, elements: resolve(inner))
                case .group(let name, let min, let max, let inner):
                    return .group(name, min: min, max: max, elements: resolve(inner))
                case .choice(let name, let min, let max, let alternatives):
                    return .choice(name, min: min, max: max, alternatives: resolve(alternatives))
                default:
                    return element
                }
            }
        }
        let resolved = resolve(elements)
        if let (key, found) = unmapped { return .unmapped(key: key, value: found) }
        return .resolved(MessageStructure(id: id, version: version, triggers: triggers, citation: citation,
                                          profile: profile, baseVersion: baseVersion, rule: rule,
                                          aliasOf: aliasOf, keySelection: selections.joined(separator: ","),
                                          errorResponse: errorResponse, elements: resolved))
    }

    /// ``resolvingKeyedChoices(_:)`` with each key read from `message`.
    func resolvingKeyedChoices(in message: Message) -> KeyedResolution {
        resolvingKeyedChoices { $0.value(in: message) }
    }
}
