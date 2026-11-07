// Anonymiser+Rules.swift
// The fields the anonymiser covers and how each is replaced. Moved from the
// HL7v2KitAnonymise tool, whose per-segment functions became the coverage table.

extension Anonymiser {
    /// How a covered field is replaced.
    enum Rule: Sendable {
        /// CX, or an identifier held as text (PID-19, IN2-2): the ID (component 1) replaced.
        case identifier
        /// XPN: family and given names replaced, the middle name emptied.
        case name
        /// TS or DTM: moved by one to four whole weeks, or whole months when given to the month; a
        /// year is kept. A repetition moves only in the shape its type defines: component 1 a DTM,
        /// and on a TS a TS.2 that is empty or one of its codes, which is kept. Any other repetition,
        /// a value that is no DTM included, becomes `[REDACTED]` whole.
        case date
        /// DR: both ends moved as by `date`, by one shift at the coarser end's precision, so the range
        /// keeps its order; beside a year end, a finer end is cut to its year. A repetition whose ends
        /// are not both a DTM, `""` or empty, or that holds more than two components, becomes `[REDACTED]`.
        case dateRange
        /// EI: the entity identifier (component 1) replaced; components 2 to 4, its assigning
        /// authority (CH02A 2A.2.25), kept. No CX, so the caller's identifier closure is not asked.
        /// PRT-24 and PRD-7, a PLN, take it too: the ID number replaced, its type, qualifier and expiry date
        /// kept; and IN1-14, an AUI: the authorisation number replaced, its date and source kept. On a version
        /// that types the field EIP (ORC-4 on v2.8.2), `entityIdentifierPair`.
        case entityIdentifier
        /// EIP: the placer's and the filler's EI (components 1 and 2), each held as subcomponents, each with its
        /// entity identifier (subcomponent 1) replaced as `entityIdentifier` replaces it, so a parent or
        /// specimen reference still names what the same order number or specimen ID becomes.
        case entityIdentifierPair
        /// HD: as MSH-3 to MSH-6 are, but only when populated. Under the tool, MSH-4's slot, so a facility
        /// equal to the sending facility is written as it is.
        case facility
        /// XAD.
        case address
        /// XTN.
        case phone
        /// XCN: ID, family and given names.
        case provider
        /// Free text that identifies (a birth place, a device's lot or serial number, its brand, model,
        /// catalogue or software version, a certification code, a county, a military unit), a coded value
        /// about the person (GSP-5), a participating organisation (XON) or location (PL), or an employer or
        /// place of worship (XON), which no other rule covers: replaced by `[REDACTED]`.
        case redact
    }

    /// The covered fields of each segment, besides MSH-3 to MSH-6, OBX-5 and NTE-3. Each field takes the
    /// rule its type takes elsewhere. XON and PL are kept outside PRT, ROL and DEV, but for an employer or
    /// place of worship (NK1-13, PD1-14, IN1-11, GT1-51, IN2-70), which ties the organisation to a person.
    static let coverage: [String: [(field: Int, rule: Rule)]] = [
        // Network addresses (2.9.1 CH02 2.13.9.24 and 25, pp 75 to 76), as the facilities.
        "MSH": [(24, .facility), (25, .facility)],
        // PID-12, the county of PID-11's address (CH03 3.4.2.12 p 122); PID-34, a facility (p 128).
        "PID": [(2, .identifier), (3, .identifier), (4, .identifier), (5, .name), (6, .name),
                (7, .date), (9, .name), (11, .address), (12, .redact), (13, .phone), (14, .phone),
                (18, .identifier), (19, .identifier), (20, .identifier), (21, .identifier),
                (23, .redact), (29, .date), (34, .facility), (40, .phone)],
        "PD1": [(4, .provider), (10, .identifier), (14, .redact)],
        "NK1": [(2, .name), (4, .address), (5, .phone), (6, .phone), (12, .identifier), (13, .redact), (16, .date),
                (26, .name), (30, .name), (31, .phone), (32, .address), (33, .identifier),
                (37, .identifier), (38, .redact), (40, .phone), (41, .phone)],
        "PV1": [(5, .identifier), (7, .provider), (8, .provider), (9, .provider), (17, .provider),
                (19, .identifier), (50, .identifier), (52, .provider), (54, .identifier)],
        "PV2": [(13, .provider)],
        // 2.9.1 CH03 3.4.10, pp 193 to 196: the prior identifiers and name, as PID-3, PV1-19 and PID-5.
        "MRG": [(1, .identifier), (2, .identifier), (3, .identifier), (4, .identifier), (5, .identifier),
                (6, .identifier), (7, .name)],
        // IN1-28, an admission's certification code held as text (CH06 6.5.6.28 p 91).
        "IN1": [(3, .identifier), (5, .address), (6, .name), (7, .phone), (10, .identifier), (11, .redact),
                (14, .entityIdentifier), (16, .name), (18, .date), (19, .address), (28, .redact), (30, .provider),
                (36, .identifier), (44, .address), (49, .identifier), (52, .redact), (54, .identifier),
                (56, .identifier)],
        // 2.9.1 CH06 6.5.7, pp 100 to 120: the identifiers, held as CX or text (the social security, Medicare,
        // Medicaid and military numbers), names, phones, the employer, and the military unit and station.
        "IN2": [(1, .identifier), (2, .identifier), (3, .provider), (6, .identifier), (7, .name), (8, .identifier),
                (9, .name), (10, .identifier), (12, .redact), (13, .redact), (22, .name), (25, .identifier),
                (26, .identifier), (40, .name), (49, .name), (50, .phone), (52, .name), (53, .phone), (58, .phone),
                (61, .identifier), (63, .phone), (64, .phone), (70, .redact)],
        "GT1": [(2, .identifier), (3, .name), (4, .name), (5, .address), (6, .phone), (7, .phone),
                (8, .date), (12, .identifier), (16, .name), (17, .address), (18, .phone),
                (19, .identifier), (24, .date), (29, .identifier), (42, .name), (45, .name),
                (46, .phone), (51, .redact), (56, .redact)],
        // The providers of EVN, DG1, PR1, PV2, TXA and RF1, and PRD's provider. RF1-21 and RF1-23 name and reach
        // the person contacted (2.9.1 CH11 11.8.1.21 p 59); TXA-14 and TXA-15 are ORC-2 and ORC-3 (CH09 9.7.3.14
        // p 38). Their other fields pass through.
        "EVN": [(5, .provider)],
        "DG1": [(16, .provider)],
        "PR1": [(8, .provider), (11, .provider), (12, .provider)],
        "TXA": [(5, .provider), (9, .provider), (10, .provider), (11, .provider), (14, .entityIdentifier),
                (15, .entityIdentifier), (22, .provider), (23, .provider)],
        "RF1": [(20, .provider), (21, .redact), (23, .phone)],
        "PRD": [(2, .name), (3, .address), (5, .phone), (7, .entityIdentifier), (11, .address), (13, .phone)],
        // The order numbers (2.9.1 CH04 4.5.1, pp 59 to 69) and their parents, as PRT-10 is.
        "ORC": [(2, .entityIdentifier), (3, .entityIdentifier), (4, .entityIdentifier), (8, .entityIdentifierPair),
                (10, .provider), (11, .provider), (12, .provider), (14, .phone), (19, .provider), (22, .address),
                (23, .phone), (24, .address), (33, .identifier), (38, .entityIdentifier)],
        "OBR": [(2, .entityIdentifier), (3, .entityIdentifier), (10, .provider), (16, .provider), (17, .phone),
                (28, .provider), (29, .entityIdentifierPair), (32, .provider), (33, .provider), (34, .provider),
                (35, .provider), (51, .entityIdentifier), (52, .entityIdentifier), (53, .identifier),
                (54, .entityIdentifierPair)],
        // OBX-33 names the specimen as SPM-2 does (2.9.1 CH07 7.4.2.33 p 78).
        "OBX": [(16, .provider), (18, .entityIdentifier), (21, .entityIdentifier), (24, .address), (25, .provider),
                (33, .entityIdentifierPair)],
        "SPM": [(2, .entityIdentifierPair), (3, .entityIdentifierPair), (30, .identifier), (31, .identifier),
                (32, .entityIdentifier)],
        "NTE": [(5, .provider)],
        // An event date is kept, as MSH-7, ORC-9 and OBR-7 are: the tool moves every date of a file by one
        // shift, so a moved event date beside the same instant in clear would give away every date of birth.
        // 2.9.1 CH03 3.4.19 to 3.4.21: all but the set ID, action code, GSR-8 (acquisition date) and GSC-6
        // and GSC-7 (ERL pointers). A validity range moves: it may start at the date of birth.
        "GSP": [(3, .entityIdentifier), (4, .redact), (5, .redact), (6, .dateRange), (7, .redact)],
        "GSR": [(3, .entityIdentifier), (4, .redact), (5, .redact), (6, .redact), (7, .redact),
                (9, .dateRange), (10, .redact)],
        "GSC": [(3, .entityIdentifier), (4, .redact), (5, .dateRange), (8, .redact)],
        // 2.9.1 CH07 7.4.4, pp 89 to 99: all but the action code, the coded fields (PRT-3, 4, 6, 7, 13, 22
        // and 23) and the event dates (PRT-11, 12, 17 and 18; the device dates must match the UDI, p 95).
        // PRT-22 is a device type: a UDI with a serial number goes in PRT-10 (7.4.4.10, p 95). Kept, its UDI
        // can still hold the lot number PRT-19 must match (p 95).
        "PRT": [(1, .entityIdentifier), (5, .provider), (8, .redact), (9, .redact), (10, .entityIdentifier),
                (14, .address), (15, .phone), (16, .entityIdentifier), (19, .redact), (20, .redact),
                (21, .entityIdentifier), (24, .entityIdentifier)],
        // 2.8.2 CH15 15.4.7, pp 31 to 36 (2.9.1 p 38 prints the same fields): all but the action code, the
        // coded fields (ROL-3 and ROL-7 to ROL-10) and the event dates (ROL-5 and ROL-6).
        "ROL": [(1, .entityIdentifier), (4, .provider), (11, .address), (12, .phone), (13, .redact), (14, .redact)],
        // 2.9.1 CH17 17.7.1, pp 66 to 70: all but the action code, the coded fields (DEV-3, 4, 14 and 17) and
        // the device dates (DEV-12 and 13), as in PRT. DEV-2 must equal PRT-10 (p 67), and the same value
        // maps alike, so the two still match. DEV-3, kept as PRT-22 is, can hold a UDI's lot number.
        "DEV": [(2, .entityIdentifier), (5, .redact), (6, .redact), (7, .redact), (8, .redact),
                (9, .entityIdentifier), (10, .redact), (11, .redact), (15, .entityIdentifier), (16, .redact)],
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

    /// Field `index` replaced under `rule`, when populated; an empty or absent field is kept. `ts` is
    /// true when the message's version types the field TS, so a date may carry TS.2.
    func apply(_ rule: Rule, to fields: inout [Field], at index: Int, ts: Bool) {
        guard fields.indices.contains(index), isPopulated(fields[index]) else { return }
        let original = fields[index]
        fields[index] = Field(repetitions: original.repetitions.enumerated().map { i, repetition in
            replaced(repetition, under: rule, repetition: i, ts: ts)
        })
    }

    /// What TS.2, the degree of precision, may hold and be kept: nothing, or a code of Table 0529
    /// (v2.5.1 2.A.77.2 p 2-225; v2.3 2.8.42 p 2-45, v2.3.1 2.8.44 p 2-52 and v2.4 2.9.47 p 2-69 list
    /// the same six). A code names a precision and holds no part of the date; TS.1's digits decide
    /// how the date moves.
    static let degreesOfPrecision: Set<String> = ["", "Y", "L", "D", "H", "M", "S"]

    /// True for a DTM, the HL7 null `""` or nothing: what a date component may hold and be kept or moved.
    static func isDate(_ raw: String) -> Bool {
        raw.isEmpty || raw == "\"\"" || datePrecision(raw) != nil
    }

    /// One repetition of a covered field; `i` is its index in the field.
    func replaced(_ repetition: Repetition, under rule: Rule, repetition i: Int, ts: Bool) -> Repetition {
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
            // Components as text, so a subcomponent makes component 1 no DTM and TS.2 no code.
            let parts = repetition.components.map(Self.text), raw = parts.first ?? ""
            let defined = parts.count <= 1 || (ts && parts.count == 2 && Self.degreesOfPrecision.contains(parts[1]))
            guard defined, Self.isDate(raw) else { return .scalar("[REDACTED]") }
            return raw.isEmpty ? repetition : setting(repetition, [0: scrubDOB(raw, salt: source.pick("date", raw).salt)])
        case .dateRange:
            let ends = repetition.components.map(Self.text)
            guard ends.count <= 2, ends.allSatisfy(Self.isDate) else { return .scalar("[REDACTED]") }
            // One shift, chosen from the start (or the end when it stands alone), at the coarser end's
            // precision, keeps the range in order.
            let start = ends.first ?? "", end = ends.count == 2 ? ends[1] : ""
            let salt = source.pick("date", start.isEmpty ? end : start).salt
            let coarser = [start, end].compactMap(datePrecision).min() ?? .day
            return setting(repetition, [0: scrubDOB(start, salt: salt, at: coarser),
                                        1: scrubDOB(end, salt: salt, at: coarser)])
        case .entityIdentifier:
            let id = repetition.components.first.map(Self.text) ?? ""
            return setting(repetition, [0: syntheticIdentifier(matching: id, salt: source.pick("identifier", id, offset: i).salt)])
        case .entityIdentifierPair:
            // Each EI as `setting` treats a component: under a key only a populated entity identifier. Under the
            // tool, at the first repetition's offset, so every repetition names what the same ID becomes in a
            // field that does not repeat (OBX-33's second as the second specimen's SPM-2).
            return Repetition(components: repetition.components.enumerated().map { k, component in
                let id = component.subcomponents.first?.value ?? ""
                guard k < 2, !keyed || !id.isEmpty else { return component }
                let replacement = syntheticIdentifier(matching: id, salt: source.pick("identifier", id).salt)
                return Component(subcomponents: [Subcomponent(replacement)] + component.subcomponents.dropFirst())
            })
        case .facility:
            let pick = source.pick("facility", Self.text(repetition), slot: 1)
            let facility = syntheticFacility(salt: pick.salt, slot: pick.slot)
            return keyed ? setting(repetition, [0: facility]) : .scalar(facility)
        case .redact:
            return .scalar("[REDACTED]")
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
