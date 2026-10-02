// UnionSurface.swift
// P9-5 (V282-C10, ADR-020): the typed accessors a segment struct gains from
// the other supported HL7 versions on top of its base schema (canonical
// v2.5.1, else the earliest version that defines the segment), and the DocC
// that says which versions each accessor applies to.
//
// The rules (ADR-020, P9-5 rulings 1 to 3):
// - A position the base schema defines is the same element in every version.
//   A version that prints it under another name joins the base accessor (a
//   DocC note) unless its Swift type differs, in which case the later name gets
//   its own accessor, typed as that version prints it, and the two DocC blocks
//   cross-reference each other as a rename. One accessor per element and type.
// - A position the base reserves (no data type), or one past the base maximum,
//   that a later version defines is a redefinition: a separate accessor, with
//   DocC naming the other elements at the position.
// - A version that types an accessor's position as a composite view where the
//   accessor is scalar or raw gets `<name>As<T>`. A view accessor gets a DocC
//   note instead: `viewed(as:)` for another view, the scalar type for a scalar.

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

/// The Swift type of the singular accessor for an HL7 data type.
private func swiftType(_ dataType: String) -> String {
    accessorShape(dataType, index: 0).type
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

/// One accessor's element at one position, with every version that prints it.
private struct Slot {
    let index: Int
    let swiftName: String
    /// The printed name in the first version of the slot.
    let name: String
    /// The accessor's own data type: the base field's, else the first defining version's.
    let dataType: String
    var entries: [(version: String, field: FieldSchema)]
    /// For a later rename kept as its own accessor (ruling 1), the base slot's position in `slots`.
    var renameOf: Int?

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
        Slot(index: $0.index, swiftName: $0.swiftName, name: $0.name, dataType: $0.dataType,
             entries: [(base.version, $0)])
    }
    let baseCount = slots.count
    for schema in others.sorted(by: { versionLess($0.version, $1.version) }) {
        let later = versionLess(base.version, schema.version)
        for field in schema.fields where !field.dataType.isEmpty {
            // An earlier version only ever reaches the base accessor for its position.
            let candidates = later ? slots.indices : slots.indices.prefix(baseCount)
            if let s = candidates.first(where: { slots[$0].index == field.index && slots[$0].swiftName == field.swiftName }) {
                slots[s].entries.append((schema.version, field))
                continue
            }
            let b = slots.prefix(baseCount).firstIndex { $0.index == field.index && !$0.dataType.isEmpty }
            if let b, !later || swiftType(field.dataType) == swiftType(slots[b].dataType) {
                // The same element under another name, same accessor type: one accessor.
                slots[b].entries.append((schema.version, field))
            } else if later {
                slots.append(Slot(index: field.index, swiftName: field.swiftName, name: field.name,
                                  dataType: field.dataType, entries: [(schema.version, field)], renameOf: b))
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
        // A rename family: the base accessor and the later names kept beside it.
        let root = slot.renameOf ?? n
        let family = [root] + slots.indices.filter { slots[$0].renameOf == root }
        let familyVersions = family.flatMap { slots[$0].defining }.sorted(by: versionLess)
        let defining = family.count > 1 ? familyVersions : slot.defining
        let repeating = slot.repeating
        var notes: [String] = []
        if slot.dataType.isEmpty {
            notes.append("v\(base.version) reserves \(sid) without defining an element; this returns whatever \(sid) holds on the wire.")
        } else if defining != surface.segmentVersions {
            notes.append("Defined in \(versionList(defining)). On a message of another version this returns whatever \(sid) holds on the wire.")
        }
        // The first version after the base that prints a family member's name: a same-type
        // version merged into the base accessor can carry the rename before the type changes.
        func renamedIn(_ m: Int) -> String {
            family.flatMap { slots[$0].entries }
                .filter { $0.field.swiftName == slots[m].swiftName && versionLess(base.version, $0.version) }
                .map(\.version).min(by: versionLess) ?? slots[m].entries[0].version
        }
        if let b = slot.renameOf {
            let first = slot.entries[0].version
            notes.append("Same element as `\(slots[b].swiftName)`, renamed in v\(renamedIn(n)); typed as v\(first) prints it.")
        }
        // Every printed name of this element, with the accessor whose type matches that version.
        for m in family {
            for run in runs(slots[m].entries.filter { !$0.field.dataType.isEmpty }.map { entry in
                let match = family.first { swiftType(slots[$0].dataType) == swiftType(entry.field.dataType) } ?? m
                return (entry.version, "\(entry.field.name)\u{1F}\(slots[match].swiftName)\u{1F}\(entry.field.dataType)")
            }) {
                let parts = run.value.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
                let (name, accessor, type) = (parts[0], parts[1], parts[2])
                let verb = agree(run.versions, "print")
                if m == n && name == slot.name { continue }
                if m == n {
                    notes.append("\(versionList(run.versions)) \(verb) this element as `\(name)`.")
                } else if accessor == slot.swiftName {
                    notes.append("\(versionList(run.versions)) \(verb) this element as `\(name)` (`\(type)`), which this accessor reads.")
                } else if slots[m].renameOf != nil && name == slots[m].name {
                    let renamed = renamedIn(m)
                    let typedBy = renamed == run.versions[0] ? "which types it" : "and v\(run.versions[0]) types it"
                    notes.append("Renamed `\(name)` in v\(renamed), \(typedBy) `\(type)`: use `\(accessor)`.")
                } else {
                    notes.append("\(versionList(run.versions)) \(verb) this element as `\(name)` (`\(type)`): use `\(accessor)`.")
                }
            }
        }
        // Redefinitions: other elements at a reserved or past-maximum position.
        for (m, other) in slots.enumerated() where other.index == slot.index && !family.contains(m) && m != n {
            for run in runs(other.entries.map { ($0.version, $0.field.name) }) {
                notes.append("\(versionList(run.versions)) \(agree(run.versions, "define")) \(sid) as `\(run.value)`: use `\(other.swiftName)`.")
            }
        }

        // Versions that type the position differently from this accessor.
        let refKind = accessorKind(slot.dataType)
        let scalars = runs(slot.entries.compactMap { entry in
            guard case .view = refKind, accessorKind(entry.field.dataType) == .scalar else { return nil }
            return (entry.version, entry.field.dataType)
        })
        for run in scalars {
            notes.append("\(versionList(run.versions)) \(agree(run.versions, "print")) `\(run.value)`, a scalar: the value reads as the first component.")
        }
        let retyped = runs(slot.entries.compactMap { entry in
            guard case .view(let t) = accessorKind(entry.field.dataType), refKind != .view(t) else { return nil }
            return (entry.version, t)
        })
        var asAccessors: [UnionAccessor] = []
        for run in retyped {
            let t = run.value
            let printed = agree(run.versions, "print")
            if case .view = refKind {
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
        if !repeating.isEmpty && repeating != slot.defining {
            notes.append("Repeats in \(versionList(repeating)) only.")
        }

        if isBase {
            surface.notes[slot.index] = notes
            surface.repeats[slot.index] = !repeating.isEmpty
            if !repeating.isEmpty { try claim(slot.swiftName + "All", sid) }
        } else {
            try claim(slot.swiftName, sid)
            if !repeating.isEmpty { try claim(slot.swiftName + "All", sid) }
            surface.accessors.append(UnionAccessor(field: slot.entries[0].field, swiftName: slot.swiftName,
                                                   notes: notes, all: !repeating.isEmpty))
        }
        surface.accessors += asAccessors
    }
    // Union accessors in field order (stable within a position).
    surface.accessors = surface.accessors.enumerated()
        .sorted { ($0.element.field.index, $0.offset) < ($1.element.field.index, $1.offset) }
        .map(\.element)
    return surface
}
