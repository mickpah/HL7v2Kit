// AnonymiserCoverageTests.swift
// The identifying fields of the covered segments that their coverage rows did not name, and MRG, SPM, IN2
// and the providers of EVN, DG1, PR1, PV2, TXA, RF1 and PRD, with RF1's source and TXA's order numbers, which
// link to ORC-2 and ORC-3. Each takes the rule its type takes
// elsewhere, under the tool's rule and under a key, and is written as that type's model field writes the same
// value; a value linked to another field (MRG-1 to PID-3, OBX-33 to SPM-2, OBR-29 and TXA-14 to OBR-2) maps
// alike. A field left out by ruling is kept, with its reason.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Anonymiser coverage of identifying fields")
struct AnonymiserCoverageTests {
    static let header = "MSH|^~\\&|SYNTH_APP|SYNFACA|SYNTH_RCV|TESTFAC|20240301120000||ADT^A01^ADT_A01|CTRLCV01|P|2.9.1"

    /// The shape of a field's value; each identifying component holds the marker. `id` is an identifier
    /// held as text (as PID-19); `text` is text that becomes `[REDACTED]`.
    enum Form { case cx, xcn, xpn, xad, xtn, ei, eip, hd, id, text, aui, pln, xon }

    static func value(_ form: Form, _ m: String) -> String {
        switch form {
        case .cx: "\(m)^^^TESTFAC^MR"
        case .xcn: "\(m)^\(m)F^\(m)G"
        case .xpn: "\(m)F^\(m)G"
        case .xad: "\(m)^^\(m)C^NSW^2000^AU^H"
        case .xtn: "\(m)^PRN^PH"
        case .ei: "\(m)^TESTFAC"
        case .eip: "\(m)P&TESTFAC^\(m)F&TESTFAC"
        case .hd: "\(m)^2.999.1^ISO"
        case .id, .text: m
        case .aui: "\(m)^20240101^SYN-SOURCE"
        case .pln: "\(m)^SYN^NSW^20301231"
        case .xon: "\(m)^L^^^^TESTFAC^XX^^^\(m)I"
        }
    }

    /// Every newly covered field, by the form of its type (v2.9.1 schemas; withdrawn fields by their last print).
    static let covered: [String: [(Int, Form)]] = [
        "MSH": [(24, .hd), (25, .hd)],
        "PID": [(12, .text), (34, .hd)],
        "PD1": [(14, .xon)],
        "NK1": [(13, .xon)],
        "PV1": [(5, .cx), (19, .cx), (50, .cx), (54, .cx)],
        "IN1": [(3, .cx), (5, .xad), (6, .xpn), (7, .xtn), (10, .cx), (11, .xon), (14, .aui), (28, .text), (30, .xcn),
                (54, .cx), (56, .cx)],
        "GT1": [(51, .xon)],
        "ORC": [(2, .ei), (3, .ei), (4, .ei), (8, .eip), (14, .xtn), (19, .xcn), (22, .xad), (23, .xtn), (24, .xad),
                (33, .cx), (38, .ei)],
        "OBR": [(2, .ei), (3, .ei), (17, .xtn), (29, .eip), (51, .ei), (52, .ei), (53, .cx), (54, .eip)],
        "OBX": [(18, .ei), (21, .ei), (24, .xad), (25, .xcn), (33, .eip)],
        "NTE": [(5, .xcn)],
        "MRG": [(1, .cx), (2, .cx), (3, .cx), (4, .cx), (5, .cx), (6, .cx), (7, .xpn)],
        "SPM": [(2, .eip), (3, .eip), (30, .cx), (31, .cx), (32, .ei)],
        "IN2": [(1, .cx), (2, .id), (3, .xcn), (6, .id), (7, .xpn), (8, .id), (9, .xpn), (10, .id),
                (12, .text), (13, .text), (22, .xpn), (25, .cx), (26, .cx), (40, .xpn), (49, .xpn), (50, .xtn),
                (52, .xpn), (53, .xtn), (58, .xtn), (61, .cx), (63, .xtn), (64, .xtn), (70, .xon)],
        "EVN": [(5, .xcn)],
        "DG1": [(16, .xcn)],
        "PR1": [(8, .xcn), (11, .xcn), (12, .xcn)],
        "PV2": [(13, .xcn)],
        "TXA": [(5, .xcn), (9, .xcn), (10, .xcn), (11, .xcn), (14, .ei), (15, .ei), (22, .xcn), (23, .xcn)],
        "RF1": [(20, .xcn), (21, .text), (23, .xtn)],
        "PRD": [(2, .xpn), (3, .xad), (5, .xtn), (7, .pln), (11, .xad), (13, .xtn)],
    ]

    /// Fields left out by ruling, with their reasons: each is kept, byte for byte, under both rules.
    static let kept: [String: [Int: (value: String, reason: String)]] = [
        "MSH": [21: ("SYN-PROFILE^TESTFAC^2.999.2^ISO", "a published message profile (CH02 2.13.9.21 p 74)"),
                22: ("SYNORGA^L", "XON, an organisation: kept outside PRT, ROL and DEV"),
                23: ("SYNORGB^L", "XON, an organisation")],
        "PD1": [3: ("SYNCLINIC^L", "XON, a care facility (CH03 3.4.11.3 p 197)"),
                18: ("20240101", "an event date: a status's effective date"),
                23: ("20500101", "a date, but no birth, death or validity date (p 202)")],
        "NK1": [8: ("20240101", "an event date: the contact role's start (p 167)")],
        "PV1": [3: ("SYNWARD^1^A^TESTFAC", "PL, a place in the facility: kept outside PRT, ROL and DEV"),
                37: ("SYN-DL^20240301", "DLD, a discharge facility and an event date (p 146)")],
        "IN1": [4: ("SYNINSURER^L", "XON, the insurer (CH06 6.5.6.4 p 83)"),
                8: ("SYN-GROUP", "a group plan's number, shared by its members (p 85)"),
                9: ("SYNGROUP^L", "XON, the group plan (p 85)"),
                12: ("20240101", "an event date")],
        "GT1": [21: ("SYNGUARANTOR^L", "XON, the guarantor as an organisation, a paying party (p 70)")],
        "ORC": [13: ("SYNWARD^1^A^TESTFAC", "PL, the enterer's location"),
                21: ("SYNFACILITY^L", "XON, the ordering facility"),
                34: ("SYN-WF^Synthetic workflow^L", "a workflow profile (CH04 4.5.1.34 p 67)")],
        "OBR": [13: ("SYN-CI^Synthetic clinical information^L", "clinical information, no identifier (p 77)"),
                18: ("SYN-PF1", "site-defined, as a Z-segment is (p 78)"), 19: ("SYN-PF2", "site-defined"),
                20: ("SYN-FF1", "site-defined"), 21: ("SYN-FF2", "site-defined")],
        "OBX": [2: ("NM", "the value type"), 15: ("SYN-LAB^Synthetic producer^L", "a coded producing service (p 71)"),
                23: ("SYNLAB^L", "XON, the performing organisation")],
        "SPM": [14: ("Synthetic description", "a description of the specimen"),
                17: ("20240301^20240302", "an event range: the collection")],
        "IN2": [69: ("SYNINSURED^L", "XON, the insured as an organisation (CH06 6.5.7.69 p 120)")],
        // EVN, DG1, PR1, PV2, TXA, RF1 and PRD are covered for their providers and the values linked to a
        // covered field (TXA-14 and TXA-15, the order numbers); an unlinked identifier there is kept.
        "EVN": [7: ("SYNFACB", "an unlinked facility (HD)")],
        "DG1": [20: ("SYN-DG^TESTFAC", "an unlinked diagnosis identifier"), 22: ("SYN-DG^TESTFAC", "its parent")],
        "PR1": [19: ("SYN-PR^TESTFAC", "an unlinked procedure identifier"), 25: ("SYN-PR^TESTFAC", "its parent")],
        "PV2": [23: ("SYNCLINIC^L", "XON, a clinic")],
        "TXA": [12: ("SYN-DOC^TESTFAC", "an unlinked document number"), 13: ("SYN-DOC^TESTFAC", "its parent"),
                16: ("SYN-DOC.PDF", "an unlinked document file name"), 27: ("SYNFACC", "an unlinked facility (HD)"),
                31: ("SYN-FOLDER^TESTFAC", "an unlinked folder instance")],
        "RF1": [6: ("SYN-REF^TESTFAC", "an unlinked referral identifier"), 11: ("SYN-REF^TESTFAC", "an unlinked one"),
                19: ("SYNPROVIDERORG^L", "XON, the authorised provider organisation (CH11 11.8.1.19 p 58)")],
        "PRD": [4: ("SYNWARD^1^A^TESTFAC", "PL, the provider's location"),
                8: ("20240101", "an event date: the provider role's start"),
                10: ("SYNPROVIDERORG^L", "XON, the provider as an organisation (CH11 11.8.3.10 p 73)"),
                12: ("SYNWARD^1^A^TESTFAC", "PL")],
    ]

    static let order = ["PID", "PD1", "NK1", "PV1", "PV2", "MRG", "IN1", "IN2", "GT1", "DG1", "PR1", "EVN", "ORC",
                        "OBR", "OBX", "NTE", "SPM", "TXA", "RF1", "PRD"]

    /// One segment: `values` at their field numbers, every other field empty.
    static func segment(_ id: String, _ values: [Int: String]) -> String {
        ([id] + (1...(values.keys.max() ?? 1)).map { values[$0] ?? "" }).joined(separator: "|")
    }

    static func marker(_ id: String, _ n: Int) -> String { "ORIG\(id)\(n)X" }

    /// Every covered field holding two repetitions, each marked, and every kept field.
    static let message: String = {
        func values(_ id: String) -> [Int: String] {
            var values = (kept[id] ?? [:]).mapValues(\.value)
            for (n, form) in covered[id] ?? [] {
                values[n] = value(form, marker(id, n)) + "~" + value(form, marker(id, n) + "R")
            }
            return values
        }
        let msh = header + "|||||||||" + [21, 22, 23, 24, 25].map { values("MSH")[$0] ?? "" }.joined(separator: "|")
        return ([msh] + order.map { segment($0, values($0)) }).joined(separator: "\r") + "\r"
    }()

    /// `wire` anonymised under key 7, or under the tool's rule with salt 41.
    static func anonymised(_ wire: String, keyed: Bool) throws -> String {
        let anonymiser = keyed ? Anonymiser(key: 7) : Anonymiser(legacySalt: 41)
        return String(decoding: anonymiser.anonymise(try Parser().parse(wire)).serialize(), as: UTF8.self)
    }

    /// Each segment's fields as written, by segment ID; MSH counted as the path does (MSH-1 the separator).
    static func fields(_ wire: String) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for line in wire.split(separator: "\r") {
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            out[fields[0]] = fields[0] == "MSH" ? ["MSH", "|"] + fields.dropFirst() : fields
        }
        return out
    }

    /// On v2.4 the grammar has no SPM, OBX-33 or ORC-38, so an EIP there is known by its row alone.
    @Test("Every newly covered field has every repetition replaced, and no marker survives",
          arguments: [true, false], ["2.9.1", "2.4"])
    func newlyCovered(keyed: Bool, version: String) throws {
        #expect(Self.message.contains(Self.marker("IN2", 70) + "R"))
        let wire = Self.message.replacingOccurrences(of: "|P|2.9.1", with: "|P|\(version)")
        let text = try Self.anonymised(wire, keyed: keyed)
        let input = Self.fields(wire), output = Self.fields(text)
        for (id, rows) in Self.covered {
            let before = try #require(input[id]), after = try #require(output[id])
            #expect(after.count == before.count, "\(id) field count")
            for (n, _) in rows {
                let was = before[n].split(separator: "~"), now = after[n].split(separator: "~")
                #expect(now.count == 2 && now.count == was.count, "\(id)-\(n) repetitions, \(version), keyed \(keyed)")
                for (a, b) in zip(was, now) { #expect(!b.isEmpty && b != a, "\(id)-\(n), \(version), keyed \(keyed): \(b)") }
            }
        }
        #expect(!text.contains("ORIG"), "\(version), keyed \(keyed)")
    }

    @Test("A field left out by ruling is kept, byte for byte", arguments: [true, false])
    func keptByRuling(keyed: Bool) throws {
        let output = Self.fields(try Self.anonymised(Self.message, keyed: keyed))
        #expect(output["MSH"]?[10] == "CTRLCV01")   // the message control ID: names the message (CH02 2.13.9.10 p 70)
        for (id, rows) in Self.kept {
            let after = try #require(output[id])
            for (n, row) in rows { #expect(after[n] == row.value, "\(id)-\(n), \(row.reason), keyed \(keyed)") }
        }
    }

    /// Each form's model field, whose rule a covered field of that form mirrors, and the value both hold.
    static let models: [Form: (path: String, value: String)] = [
        .cx: ("PID-3", "ORIGCXX^^^TESTFAC^MR"), .xcn: ("PV1-7", "ORIGXCNX^ORIGXCNFX^ORIGXCNGX"),
        .xpn: ("PID-5", "ORIGXPNFX^ORIGXPNGX"), .xad: ("PID-11", "ORIGXADX^^ORIGXADCX^NSW^2000^AU^H"),
        .xtn: ("PID-13", "ORIGXTNX^PRN^PH"), .id: ("PID-19", "ORIGIDX"), .hd: ("MSH-4", "ORIGHDX"),
        .ei: ("PRT-10", "ORIGEIX^TESTFAC"),
    ]

    /// The value of `form` whose identifying part equals its model's: an EIP, AUI and PLN hold the EI's ID.
    static func modelValue(_ form: Form) -> String {
        switch form {
        case .eip: "ORIGEIX&TESTFAC^ORIGEIX&TESTFAC"
        case .aui: "ORIGEIX^20240101^SYN-SOURCE"
        case .pln: "ORIGEIX^SYN^NSW^20301231"
        case .text, .xon: "ORIGTEXTX"
        default: models[form]?.value ?? ""
        }
    }

    /// Every covered field and every model field, each holding its form's model value once.
    static let modelMessage: String = {
        func values(_ id: String) -> [Int: String] {
            var values: [Int: String] = [:]
            for (n, form) in covered[id] ?? [] { values[n] = modelValue(form) }
            for (form, model) in models where model.path.hasPrefix(id + "-") && id != "MSH" {
                values[Int(model.path.dropFirst(4))!] = modelValue(form)
            }
            return values
        }
        let msh = "MSH|^~\\&|SYNTH_APP|ORIGHDX|SYNTH_RCV|TESTFAC|20240301120000||ADT^A01^ADT_A01|CTRLCV03|P|2.9.1|||||||||"
            + [21, 22, 23, 24, 25].map { values("MSH")[$0] ?? "" }.joined(separator: "|")
        return ([msh] + (order + ["PRT"]).map { segment($0, values($0)) }).joined(separator: "\r") + "\r"
    }()

    @Test("Every covered field is written as its type's model field writes the same value", arguments: [true, false])
    func everyFieldMapsAsItsModel(keyed: Bool) throws {
        let output = Self.fields(try Self.anonymised(Self.modelMessage, keyed: keyed))
        func at(_ path: String) -> String {
            let parts = path.split(separator: "-")
            return output[String(parts[0])]?[Int(parts[1])!] ?? ""
        }
        let ei = String(at("PRT-10").prefix { $0 != "^" })
        #expect(!ei.isEmpty && !ei.contains("ORIG"), "keyed \(keyed)")
        for (id, rows) in Self.covered {
            for (n, form) in rows {
                let got = at("\(id)-\(n)"), label = "\(id)-\(n), keyed \(keyed)"
                switch form {
                case .text, .xon: #expect(got == "[REDACTED]", "\(label)")
                case .ei, .aui, .pln: #expect(got.prefix { $0 != "^" } == ei, "\(label): \(got)")
                case .eip:
                    let halves = got.split(separator: "^").map { $0.prefix { $0 != "&" } }
                    #expect(halves.count == 2 && halves.allSatisfy { $0 == ei }, "\(label): \(got)")
                default:
                    let model = try #require(Self.models[form]).path
                    #expect(got == at(model) && !got.contains("ORIG"), "\(label) as \(model): \(got)")
                }
            }
        }
    }

    /// Linked values: the same value in each pair of fields. OBX-33 names two specimens, the second at
    /// repetition 2, and each SPM-2 is written as OBX-33's repetition naming it.
    static let links: String = {
        let (cx, visit, alt) = ("ORIGIDX^^^TESTFAC^MR", "ORIGVISITX^^^TESTFAC^VN", "ORIGALTX^^^TESTFAC^VN")
        let (name, maiden) = ("ORIGFAMX^ORIGGIVX", "ORIGMAIDENX^ORIGMAIDENGX")
        let (placer, filler) = ("ORIGPLACERX^TESTFAC", "ORIGFILLERX^TESTFAC")
        let parent = "ORIGPLACERX&TESTFAC^ORIGFILLERX&TESTFAC"
        let (specimen, second) = ("ORIGSPECPX&TESTFAC^ORIGSPECFX&TESTFAC", "ORIGSPEC2PX&TESTFAC^ORIGSPEC2FX&TESTFAC")
        return [
            header + "||||||||||||SYNFACA",
            segment("PID", [1: "1", 3: cx, 5: name, 6: maiden, 7: "19000101", 8: "U", 19: "ORIGSSNX", 34: "SYNFACA"]),
            segment("PV1", [1: "1", 2: "O", 19: visit, 50: alt]),
            segment("MRG", [1: cx, 5: visit, 6: alt, 7: name]),
            segment("IN2", [2: "ORIGSSNX", 40: maiden]),
            segment("ORC", [1: "NW", 2: placer, 3: filler, 8: parent]),
            segment("OBR", [1: "1", 2: placer, 3: filler, 29: parent, 53: "ORIGPLACERX^^^TESTFAC", 54: parent]),
            segment("OBX", [1: "1", 2: "NM", 33: specimen + "~" + second]),
            segment("SPM", [1: "1", 2: specimen]), segment("SPM", [1: "2", 2: second]),
            segment("TXA", [1: "1", 14: placer, 15: filler]),
        ].joined(separator: "\r") + "\r"
    }()

    @Test("A linked value maps alike: MRG to PID and PV1, the order numbers and their parents, OBX-33 to each SPM-2",
          arguments: [true, false])
    func linkedValuesMapAlike(keyed: Bool) throws {
        let text = try Self.anonymised(Self.links, keyed: keyed)
        let out = try Parser().parse(text), fields = Self.fields(text)
        // A field as written; a component or subcomponent by its path.
        func read(_ path: String) -> String? {
            guard !path.contains(".") else { return out[path] }
            let parts = path.split(separator: "-")
            return fields[String(parts[0])].flatMap { f in Int(parts[1]).flatMap { f.indices.contains($0) ? f[$0] : nil } }
        }
        #expect(out["PID-3.1"] != "ORIGIDX" && out["ORC-2.1"] != "ORIGPLACERX" && out["SPM-2.1.1"] != "ORIGSPECPX")
        let pairs: [(String, String)] = [
            ("MRG-1", "PID-3"), ("MRG-5", "PV1-19"), ("MRG-6", "PV1-50"), ("MRG-7", "PID-5"),   // CX, XPN
            ("IN2-2", "PID-19"), ("IN2-40", "PID-6"),
            ("OBR-2", "ORC-2"), ("OBR-3", "ORC-3"), ("OBR-53.1", "ORC-2.1"),                     // a CX and an EI alike
            ("TXA-14", "ORC-2"), ("TXA-15", "ORC-3"),
            ("ORC-8", "OBR-29"), ("OBR-54", "OBR-29"), ("ORC-8.1.1", "ORC-2.1"), ("ORC-8.2.1", "ORC-3.1"),
            ("PID-34", "MSH-4"), ("MSH-24", "MSH-4"),                                            // HD, as MSH-4
        ]
        for (a, b) in pairs { #expect(read(a) == read(b) && read(a) != nil, "\(a) = \(b), keyed \(keyed)") }
        // Each SPM-2 against the OBX-33 repetition that names it.
        let specimens = text.split(separator: "\r").filter { $0.hasPrefix("SPM|") }
            .map { String($0.split(separator: "|", omittingEmptySubsequences: false)[2]) }
        let named = (read("OBX-33") ?? "").split(separator: "~").map(String.init)
        #expect(specimens.count == 2 && named == specimens && !specimens[1].contains("ORIG"), "keyed \(keyed)")
    }

    @Test("Under a key the identifier closure is asked for each CX and identifier held as text, and only those")
    func closureAsked() throws {
        final class Seen: @unchecked Sendable { var values: Set<String> = [] }
        let seen = Seen()
        _ = Anonymiser(key: 7) { identifier in
            seen.values.insert(identifier.value)
            return "REPLACED"
        }.anonymise(try Parser().parse(Self.message))
        let asked = Self.covered.flatMap { id, rows in
            rows.filter { [.cx, .id].contains($0.1) }.flatMap { [Self.marker(id, $0.0), Self.marker(id, $0.0) + "R"] }
        }
        #expect(seen.values == Set(asked))
    }

    @Test("EI, EIP, HD, AUI and PLN keep their other components and subcomponents", arguments: [true, false])
    func shapeKept(keyed: Bool) throws {
        let out = try Parser().parse(try Self.anonymised(Self.message, keyed: keyed))
        for path in ["ORC-2.2", "OBR-29.1.2", "OBR-29.2.2", "SPM-2.1.2", "SPM-2.2.2", "OBX-33.2.2"] {
            #expect(out[path] == "TESTFAC", "\(path), keyed \(keyed)")
        }
        #expect(out["OBR-29.1.1"]?.hasPrefix("SYN-") == true && out["OBR-29.2.1"]?.hasPrefix("SYN-") == true)
        #expect(out["IN1-14.2"] == "20240101" && out["IN1-14.3"] == "SYN-SOURCE", "AUI, keyed \(keyed)")
        #expect(out["PRD-7.2"] == "SYN" && out["PRD-7.3"] == "NSW" && out["PRD-7.4"] == "20301231", "PLN, keyed \(keyed)")
        if keyed {   // the facility rule: under a key only HD-1, as in MSH-3 to MSH-6
            #expect(out["MSH-24.2"] == "2.999.1" && out["PID-34.3"] == "ISO")
        }
    }

    @Test("ORC-4 is an EIP on v2.8.2 and an EI elsewhere: each is replaced as its type is", arguments: [true, false])
    func orderGroupNumberByVersion(keyed: Bool) throws {
        for (version, value, expected) in [("2.8.2", "ORIGGRPPX&TESTFAC^ORIGGRPFX&TESTFAC", ["ORC-4.1.2", "ORC-4.2.2"]),
                                           ("2.9.1", "ORIGGRPX^TESTFAC", ["ORC-4.2"])] {
            let wire = "MSH|^~\\&|SYNTH_APP|SYNFACA|SYNTH_RCV|TESTFAC|20240301120000||ORM^O01^ORM_O01|CTRLCV02|P|\(version)\r"
                + "ORC|NW|||\(value)\r"
            let text = try Self.anonymised(wire, keyed: keyed)
            #expect(!text.contains("ORIG"), "\(version), keyed \(keyed)")
            let out = try Parser().parse(text)
            for path in expected { #expect(out[path] == "TESTFAC", "\(path) on \(version), keyed \(keyed)") }
        }
    }

    @Test("A second pass under the tool's rule writes every segment byte for byte alike")
    func secondPassUnderTheTool() throws {
        let first = try Self.anonymised(Self.message, keyed: false)
        #expect(try Self.anonymised(first, keyed: false) == first)
        #expect(first != Self.message)
    }

    @Test("A second pass under a key keeps the kept fields, [REDACTED] and every repetition count")
    func secondPassUnderAKey() throws {
        let first = try Self.anonymised(Self.message, keyed: true)
        let once = Self.fields(first), twice = Self.fields(try Self.anonymised(first, keyed: true))
        for id in Self.order {
            let a = try #require(once[id]), b = try #require(twice[id])
            #expect(a.count == b.count, "\(id)")
            for n in 1..<min(a.count, b.count) {
                if Self.kept[id]?[n] != nil || a[n].contains("[REDACTED]") { #expect(b[n] == a[n], "\(id)-\(n)") }
                #expect(b[n].split(separator: "~").count == a[n].split(separator: "~").count, "\(id)-\(n)")
            }
        }
    }
}
