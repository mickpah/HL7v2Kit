// Anonymiser+Rules.swift
// The fields the anonymiser covers and how each is replaced. Moved from the
// HL7v2KitAnonymise tool, whose per-segment functions became the coverage table.

extension Anonymiser {
    /// How a covered field is replaced.
    enum Rule: Sendable {
        /// CX, or an identifier held as text: the ID (component 1) replaced.
        case identifier
        /// XPN: family and given names replaced, the middle name emptied.
        case name
        /// TS or DTM: moved by one to four whole weeks.
        case date
        /// XAD.
        case address
        /// XTN.
        case phone
        /// XCN: ID, family and given names.
        case provider
    }

    /// The covered fields of each segment, besides MSH-3 to MSH-6, OBX-5 and NTE-3.
    static let coverage: [String: [(field: Int, rule: Rule)]] = [
        "PID": [(2, .identifier), (3, .identifier), (4, .identifier), (5, .name), (6, .name),
                (7, .date), (9, .name), (11, .address), (13, .phone), (14, .phone),
                (18, .identifier), (19, .identifier), (20, .identifier)],
        "PD1": [(4, .provider)],
        "NK1": [(2, .name), (4, .address), (5, .phone), (6, .phone)],
        "PV1": [(7, .provider), (8, .provider), (9, .provider), (17, .provider), (52, .provider)],
        "IN1": [(16, .name), (18, .date), (19, .address)],
        "ORC": [(10, .provider), (11, .provider), (12, .provider)],
        "OBR": [(10, .provider), (16, .provider), (28, .provider), (32, .provider), (33, .provider),
                (34, .provider), (35, .provider)],
        "OBX": [(16, .provider)],
    ]

    /// True under a caller's key; false under the tool's rule.
    var keyed: Bool {
        if case .keyed = source { true } else { false }
    }

    /// Component `k` (0-based) of `repetition`, its first subcomponent; nil when empty or absent.
    static func value(_ repetition: Repetition, _ k: Int) -> String? {
        guard repetition.components.indices.contains(k),
              let value = repetition.components[k].subcomponents.first?.value, !value.isEmpty else { return nil }
        return value
    }

    /// Each repetition of field `index` mapped by `transform`, when the field is populated.
    func redactEach(_ fields: inout [Field], _ index: Int, _ transform: (Repetition) -> Repetition) {
        guard fields.indices.contains(index), isPopulated(fields[index]) else { return }
        fields[index] = Field(repetitions: fields[index].repetitions.map(transform))
    }

    /// A component as text: its subcomponents joined by `&`, whatever the message's delimiters.
    static func text(_ component: Component) -> String {
        component.subcomponents.map(\.value).joined(separator: "&")
    }

    /// A repetition as text: its components joined by `^`.
    static func text(_ repetition: Repetition) -> String {
        repetition.components.map(text).joined(separator: "^")
    }

    /// True when any subcomponent holds a value: an empty field (`||`) is one empty subcomponent.
    func isPopulated(_ field: Field) -> Bool {
        field.repetitions.contains { $0.components.contains { $0.subcomponents.contains { !$0.value.isEmpty } } }
    }

    /// Field `index` set to `field`, when the segment has it.
    func replace(_ fields: inout [Field], _ index: Int, with field: Field) {
        if fields.indices.contains(index) { fields[index] = field }
    }

    /// MSH-3 to MSH-6, the sending and receiving applications and facilities. Under a key only
    /// a populated one is replaced, and only its namespace ID.
    func replaceFacilities(_ fields: inout [Field]) {
        for (slot, index) in (3...6).enumerated() where fields.indices.contains(index) {
            let original = fields[index]
            if keyed, !isPopulated(original) { continue }
            let pick = source.pick("facility", original.first.map(Self.text) ?? "", slot: slot)
            let facility = syntheticFacility(salt: pick.salt, slot: pick.slot)
            fields[index] = keyed ? Field(repetitions: original.repetitions.map { setting($0, [0: facility]) })
                                  : .scalar(facility)
        }
    }

    /// OBX-5 when it holds text (TX, FT, ST) or encapsulated data (ED); a number, code or date
    /// is kept. Under a key each repetition is replaced, and an ED keeps its type and encoding,
    /// its data becoming `[REDACTED]` (Base64-encoded when ED-4 says Base64).
    func redactObservationValue(_ fields: inout [Field], valueType: String?) {
        guard let valueType, ["TX", "FT", "ST", "ED"].contains(valueType.uppercased()) else { return }
        guard keyed else { return replace(&fields, 5, with: .scalar("[REDACTED]")) }
        redactEach(&fields, 5) { repetition in
            valueType.uppercased() == "ED"
                ? setting(repetition, [4: Self.value(repetition, 3) == "Base64" ? "W1JFREFDVEVEXQ==" : "[REDACTED]"])
                : .scalar("[REDACTED]")
        }
    }

    /// NTE-3, the comment. The tool replaces it even when empty; under a key an empty one is kept.
    func redactComment(_ fields: inout [Field]) {
        guard keyed else { return replace(&fields, 3, with: .scalar("[REDACTED]")) }
        redactEach(&fields, 3) { _ in .scalar("[REDACTED]") }
    }

    /// Field `index` replaced under `rule`, when populated; an empty or absent field is kept.
    func apply(_ rule: Rule, to fields: inout [Field], at index: Int) {
        guard fields.indices.contains(index), isPopulated(fields[index]) else { return }
        let original = fields[index]
        if rule == .date {
            guard let raw = original.stringValue, !raw.isEmpty else { return }
            fields[index] = .scalar(scrubDOB(raw, salt: source.pick("date", raw).salt))
            return
        }
        fields[index] = Field(repetitions: original.repetitions.enumerated().map { i, repetition in
            replaced(repetition, under: rule, repetition: i)
        })
    }

    /// One repetition of a covered field; `i` is its index in the field.
    func replaced(_ repetition: Repetition, under rule: Rule, repetition i: Int) -> Repetition {
        switch rule {
        case .identifier:
            guard case .keyed(let key) = source else {
                let id = repetition.components.first?.stringValue ?? ""
                return setting(repetition, [0: syntheticIdentifier(matching: id, salt: source.pick("identifier", id, offset: i).salt)])
            }
            // CX-1 as text, so one held in subcomponents is replaced too; an empty one is kept.
            guard let first = repetition.components.first,
                  first.subcomponents.contains(where: { !$0.value.isEmpty }) else { return repetition }
            let id = Self.text(first)
            let seed = anonymiserSeed(key: key, kind: "identifier", original: id)
            let replacement = replacingIdentifier?(Identifier(
                value: id, typeCode: Self.value(repetition, 4), assigningAuthority: Self.value(repetition, 3), seed: seed))
                ?? syntheticIdentifier(matching: id, salt: Int(truncatingIfNeeded: seed & 0x7FFF_FFFF))
            return setting(repetition, [0: replacement, 1: ""])   // CX-2: the original's check digit
        case .name:
            let family = source.pick("family", repetition.components.first.map(Self.text) ?? "", offset: i)
            let given = source.pick("given", repetition.components.dropFirst().first.map(Self.text) ?? "", offset: i)
            return setting(repetition, [0: syntheticName(salt: family.salt, slot: family.slot).family,
                                        1: syntheticName(salt: given.salt, slot: given.slot).given, 2: ""])
        case .address:
            let pick = source.pick("address", Self.text(repetition), slot: i)
            let a = syntheticAddress(salt: pick.salt, slot: pick.slot)
            return keyed
                ? setting(repetition, [0: a.street, 1: "", 2: a.city, 3: a.state, 4: a.postcode,
                                       7: "", 8: "", 9: "", 18: "", 19: "", 22: ""])
                : .components([a.street, "", a.city, a.state, a.postcode, "AU"])
        case .phone:
            let pick = source.pick("phone", Self.text(repetition), slot: i)
            let phone = syntheticPhone(salt: pick.salt, slot: pick.slot)
            let local = String(phone.filter(\.isNumber).suffix(8))
            return keyed
                ? setting(repetition, [0: phone, 3: "anonymised@example.invalid", 5: "2", 6: local,
                                       7: "", 8: "", 9: "", 10: "", 11: "02" + local, 17: ""])
                : .scalar(phone)
        case .provider:
            let pick = source.pick("provider", Self.text(repetition), slot: i)
            let id = syntheticProviderID(salt: pick.salt, slot: pick.slot)
            let name = syntheticName(salt: pick.salt &+ 100, slot: pick.slot)
            return keyed
                ? setting(repetition, [0: id, 1: name.family, 2: name.given, 3: "", 10: ""])
                : .components([id, name.family, name.given])
        case .date:
            return repetition   // a date is replaced whole, in apply(_:to:at:)
        }
    }

    /// `repetition` with each component in `values` replaced where the repetition has it.
    /// Under a key only a populated component is replaced, so an empty one stays empty.
    func setting(_ repetition: Repetition, _ values: [Int: String]) -> Repetition {
        Repetition(components: repetition.components.enumerated().map { k, component in
            guard let value = values[k],
                  !keyed || component.subcomponents.contains(where: { !$0.value.isEmpty }) else { return component }
            return .scalar(value)
        })
    }
}
