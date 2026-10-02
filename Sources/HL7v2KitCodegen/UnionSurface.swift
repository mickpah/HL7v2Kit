// UnionSurface.swift
// P9-5 (V282-C10, ADR-020): the typed accessors a segment struct gains from
// the other supported HL7 versions on top of its base schema (canonical
// v2.5.1, else the earliest version that defines the segment), and the DocC
// that says which versions each accessor applies to.
//
// Elements are keyed by position and P6-9-normalised swiftName. A later
// version that prints a different element name at a position gets its own
// accessor (a rename and a redefinition are treated alike, so no accessor
// named for one element silently stands for another); each accessor's DocC
// names the other elements at its position. An earlier version that prints
// another name at a base position is noted on the base accessor, which is the
// only accessor for that position on an older wire.

import Foundation

/// Numeric HL7 version order: "2.3" < "2.3.1" < "2.4" < "2.10".
func versionLess(_ a: String, _ b: String) -> Bool {
    let x = a.split(separator: ".").map { Int($0) ?? 0 }
    let y = b.split(separator: ".").map { Int($0) ?? 0 }
    return x.lexicographicallyPrecedes(y)
}

/// "v2.3, v2.3.1, v2.4".
func versionList(_ versions: [String]) -> String {
    versions.map { "v" + $0 }.joined(separator: ", ")
}

/// The verb in agreement with a version list: one version "prints", several "print".
private func agree(_ versions: [String], _ verb: String) -> String {
    versions.count == 1 ? verb + "s" : verb
}

/// One accessor contributed by another version: a later element name, or `<name>As<T>`.
struct UnionAccessor {
    /// The defining version's field: index, printed name, type.
    let field: FieldSchema
    let swiftName: String
    let notes: [String]
    /// Emit `<swiftName>All`.
    let all: Bool
}

/// Everything the other versions add to one segment struct.
struct UnionSurface {
    /// Every supported version that defines the segment, ascending.
    var segmentVersions: [String] = []
    var accessors: [UnionAccessor] = []
    /// Extra DocC sentences for base-schema accessors, keyed by field index.
    var notes: [Int: [String]] = [:]
    /// Base fields that get `<name>All`: those that repeat in any version.
    var repeats: [Int: Bool] = [:]
}

/// One element at one position, with every version that prints it.
private struct Slot {
    let index: Int
    let swiftName: String
    /// The printed name in the first version of the slot.
    let name: String
    var entries: [(version: String, field: FieldSchema)]
    /// Earlier versions that print the base element under another name.
    var renames: [(version: String, name: String)] = []

    var defining: [String] { entries.filter { !$0.field.dataType.isEmpty }.map(\.version) }
    var repeating: [String] {
        entries.filter { !$0.field.dataType.isEmpty && fieldRepeats($0.field) }.map(\.version)
    }
}

/// Group `(version, value)` pairs by value, in first-appearance order.
private func runs(_ pairs: [(version: String, value: String)]) -> [(versions: [String], value: String)] {
    var out: [(versions: [String], value: String)] = []
    for pair in pairs {
        if let i = out.firstIndex(where: { $0.value == pair.value }) {
            out[i].versions.append(pair.version)
        } else {
            out.append(([pair.version], pair.value))
        }
    }
    return out
}

private func unionFailure(_ message: String) -> ExitCode {
    FileHandle.standardError.write(Data("HL7v2KitCodegen: \(message)\n".utf8))
    return ExitCode.failure
}

func unionSurface(base: SegmentSchema, others: [SegmentSchema]) throws -> UnionSurface {
    let id = base.segmentID
    var surface = UnionSurface()
    surface.segmentVersions = ([base] + others).map(\.version).sorted(by: versionLess)

    var slots = base.fields.map {
        Slot(index: $0.index, swiftName: $0.swiftName, name: $0.name, entries: [(base.version, $0)])
    }
    let baseCount = slots.count
    for schema in others.sorted(by: { versionLess($0.version, $1.version) }) {
        let later = versionLess(base.version, schema.version)
        for field in schema.fields where !field.dataType.isEmpty {
            if let s = slots.firstIndex(where: { $0.index == field.index && $0.swiftName == field.swiftName }) {
                slots[s].entries.append((schema.version, field))
            } else if later {
                slots.append(Slot(index: field.index, swiftName: field.swiftName, name: field.name,
                                  entries: [(schema.version, field)]))
            } else if let s = slots.prefix(baseCount).firstIndex(where: { $0.index == field.index }) {
                slots[s].entries.append((schema.version, field))
                slots[s].renames.append((schema.version, field.name))
            } else {
                throw unionFailure("\(id)-\(field.index): v\(schema.version) defines a field v\(base.version) lacks")
            }
        }
    }

    for i in slots.indices { slots[i].entries.sort { versionLess($0.version, $1.version) } }

    // Every accessor name in the struct names exactly one field.
    var owner: [String: String] = [:]
    func claim(_ name: String, _ who: String) throws {
        if let other = owner[name] {
            throw unionFailure("\(id): accessor `\(name)` would name \(other) and \(who)")
        }
        owner[name] = who
    }
    for member in typedSegmentMembers { try claim(member, "TypedSegment") }
    for field in base.fields {
        let who = "\(id)-\(field.index)"
        try claim(field.swiftName, who)
        for alias in field.deprecatedSwiftNames ?? [] { try claim(alias, who) }
        if let columns = field.variableColumns { try claim(columns, who) }
    }

    for (n, slot) in slots.enumerated() {
        let isBase = n < baseCount
        let sid = "\(id)-\(slot.index)"
        // The accessor's own type: the base field's, else the first defining version's.
        let ref = isBase ? base.fields[n] : slot.entries[0].field
        let defining = slot.defining
        let repeating = slot.repeating
        var notes: [String] = []
        if defining.isEmpty {
            notes.append("v\(base.version) reserves \(sid) without defining an element; this returns whatever \(sid) holds on the wire.")
        } else if defining != surface.segmentVersions {
            notes.append("Defined in \(versionList(defining)). On a message of another version this returns whatever \(sid) holds on the wire.")
        }
        for run in runs(slot.renames.map { ($0.version, $0.name) }) {
            notes.append("\(versionList(run.versions)) \(agree(run.versions, "print")) this element as `\(run.value)`.")
        }
        for other in slots where other.index == slot.index && other.swiftName != slot.swiftName {
            for run in runs(other.entries.map { ($0.version, $0.field.name) }) {
                notes.append("\(versionList(run.versions)) \(agree(run.versions, "define")) \(sid) as `\(run.value)`: use `\(other.swiftName)`.")
            }
        }

        // Versions that print a composite this accessor does not return.
        let retyped = runs(slot.entries.compactMap { entry in
            guard case .view(let t) = accessorKind(entry.field.dataType),
                  accessorKind(ref.dataType) != .view(t) else { return nil }
            return (entry.version, t)
        })
        var asAccessors: [UnionAccessor] = []
        for run in retyped {
            let t = run.value
            let printed = agree(run.versions, "print")
            if case .view = accessorKind(ref.dataType) {
                notes.append("\(versionList(run.versions)) \(printed) `\(t)`: use `viewed(as: \(t).self)`.")
                continue
            }
            let asName = slot.swiftName + "As" + t
            notes.append("\(versionList(run.versions)) \(printed) `\(t)`: use `\(asName)`.")
            let entries = slot.entries.filter { run.versions.contains($0.version) }
            let asRepeating = entries.filter { fieldRepeats($0.field) }.map(\.version)
            let otherTypes = runs(slot.entries.filter { !run.versions.contains($0.version) && !$0.field.dataType.isEmpty }
                .map { ($0.version, $0.field.dataType) })
                .map { "\(versionList($0.versions)) \(agree($0.versions, "print")) `\($0.value)`" }
            var asNotes = ["\(sid) viewed as the `\(t)` that \(versionList(run.versions)) \(printed) (\(otherTypes.joined(separator: "; "))). On a message of another version this views whatever \(sid) holds on the wire."]
            if !asRepeating.isEmpty && asRepeating != run.versions {
                asNotes.append("Repeats in \(versionList(asRepeating)) only.")
            }
            try claim(asName, sid)
            if !asRepeating.isEmpty { try claim(asName + "All", sid) }
            asAccessors.append(UnionAccessor(field: entries[0].field, swiftName: asName, notes: asNotes,
                                             all: !asRepeating.isEmpty))
        }
        if !repeating.isEmpty && repeating != defining {
            notes.append("Repeats in \(versionList(repeating)) only.")
        }

        if isBase {
            surface.notes[slot.index] = notes
            surface.repeats[slot.index] = !repeating.isEmpty
            if !repeating.isEmpty { try claim(slot.swiftName + "All", sid) }
        } else {
            try claim(slot.swiftName, sid)
            if !repeating.isEmpty { try claim(slot.swiftName + "All", sid) }
            surface.accessors.append(UnionAccessor(field: ref, swiftName: slot.swiftName, notes: notes,
                                                   all: !repeating.isEmpty))
        }
        surface.accessors += asAccessors
    }
    // Union accessors in field order (stable within a position).
    surface.accessors = surface.accessors.enumerated()
        .sorted { ($0.element.field.index, $0.offset) < ($1.element.field.index, $1.offset) }
        .map(\.element)
    return surface
}
