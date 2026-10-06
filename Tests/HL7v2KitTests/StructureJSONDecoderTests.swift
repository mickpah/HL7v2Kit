// StructureJSONDecoderTests.swift
// P8b-7 decoder parity: the corpus tests' decoder accepts and rejects
// exactly the structure files the codegen does. Every structure-file case of
// scripts/check-structure-codegen.sh (the completeness and directory cases
// concern the codegen's walk, not one file, and the P8b-4 profile-file cases
// concern files the corpus decoder never reads) is rebuilt here from the
// committed pilots and fed through StructureJSONDecoder, expecting the
// script's verdict and, for a rejection, the same error text.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Structure JSON decoder parity with the codegen")
struct StructureJSONDecoderTests {
    typealias JSON = [String: Any]

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/structures")

    static func load(_ id: String) throws -> JSON {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("v2.5.1/\(id).json"))) as? JSON)
    }

    /// The decoder's verdict on `d` as the file `id`.json under `version`:
    /// nil when accepted, else the error text.
    static func verdict(_ d: JSON, _ id: String, version: String = "2.5.1") throws -> String? {
        let data = try JSONSerialization.data(withJSONObject: d)
        do {
            _ = try StructureJSONDecoder.decode(data, id: id, version: version)
            return nil
        } catch {
            return String(describing: error)
        }
    }

    /// Applies `change` to the first group found depth first.
    static func firstGroup(_ elements: [JSON], _ change: (inout JSON) -> Void) -> [JSON] {
        var done = false
        func walk(_ list: [JSON]) -> [JSON] {
            list.map { item in
                var e = item
                guard !done else { return e }
                if e["group"] != nil { change(&e); done = true; return e }
                if let children = e["elements"] as? [JSON] { e["elements"] = walk(children) }
                return e
            }
        }
        return walk(elements)
    }

    /// ORU_R01 with its first group's nameSource set to `source`, cited by
    /// `fragment`; on v2.3 the bundle names are re-derived through v2.4.
    static func oru(_ source: String, _ fragment: String, version: String = "2.5.1") throws -> JSON {
        var d = try load("ORU_R01")
        d["version"] = version
        var elements = try #require(d["elements"] as? [JSON])
        if version != "2.5.1" {
            d["citation"] = (d["citation"] as? String ?? "").replacingOccurrences(of: "HL7-xml v2.5.1/", with: "HL7-xml v2.4/")
            func derive(_ list: [JSON]) -> [JSON] {
                list.map { item in
                    var e = item
                    if e["nameSource"] as? String == "v2xml" { e["nameSource"] = "v2xml-v2.4" }
                    if let children = e["elements"] as? [JSON] { e["elements"] = derive(children) }
                    return e
                }
            }
            elements = derive(elements)
        }
        d["elements"] = firstGroup(elements) { $0["nameSource"] = source }
        d["citation"] = (d["citation"] as? String ?? "") + " " + fragment
        return d
    }

    /// ACK with MSA turned into a choice between MSA and UAC, then `change`.
    static func ackChoice(_ change: (inout JSON) -> Void = { _ in }) throws -> JSON {
        var d = try load("ACK")
        var elements = try #require(d["elements"] as? [JSON])
        var c: JSON = ["choice": NSNull(), "min": 1, "max": 1,
                       "alternatives": [elements[2], ["segment": "UAC", "min": 1, "max": 1] as JSON]]
        change(&c)
        elements[2] = c
        d["elements"] = elements
        return d
    }

    /// A slot as the codegen reads it (S3-1).
    static var slotJSON: JSON {
        ["slot": "Order Detail Segment", "min": 1, "max": NSNull(), "citation": "synthetic, after v2.3 CH04 4.2.1 p 4-4"]
    }

    /// ACK with a slot inserted after MSA, then `change` applied to the slot.
    static func ackSlot(_ change: (inout JSON) -> Void = { _ in }) throws -> JSON {
        var d = try load("ACK")
        var elements = try #require(d["elements"] as? [JSON])
        var slot = slotJSON
        change(&slot)
        elements.insert(slot, at: 3)
        d["elements"] = elements
        return d
    }

    /// v2.5.1 MFN_M03 with `change` applied to its keyed choice (S4-1: MF_TEST, after MFE OM1).
    static func mfnKeyed(_ change: (inout JSON) -> Void = { _ in }) throws -> JSON {
        try element(load("MFN_M03"), 3) { group in
            var inner = group["elements"] as? [JSON] ?? []
            change(&inner[2])
            group["elements"] = inner
        }
    }

    /// `choice`'s key with `change` applied.
    static func rekey(_ choice: inout JSON, _ change: (inout JSON) -> Void) {
        var key = choice["key"] as? JSON ?? [:]
        change(&key)
        choice["key"] = key
    }

    static func element(_ d: JSON, _ index: Int, _ change: (inout JSON) -> Void) -> JSON {
        var d = d
        var elements = d["elements"] as? [JSON] ?? []
        change(&elements[index])
        d["elements"] = elements
        return d
    }

    @Test("The committed pilots decode to exactly the generated structures")
    func pilotsDecode() throws {
        for id in ["ACK", "ADT_A01", "ORU_R01"] {
            let data = try Data(contentsOf: Self.root.appendingPathComponent("v2.5.1/\(id).json"))
            let decoded = try StructureJSONDecoder.decode(data, id: id, version: "2.5.1")
            #expect(decoded == MessageStructureTable.structure(id, version: .v2_5_1), "\(id)")
        }
    }

    @Test("Structure-file cases of check-structure-codegen.sh: same verdict, same text")
    func scriptCases() throws {
        let unprinted = " Unprinted group names"
        var cases: [(label: String, verdict: String?, expected: String?)] = []
        func reject(_ label: String, _ text: String, _ d: JSON, _ id: String, version: String = "2.5.1") throws {
            cases.append((label, try Self.verdict(d, id, version: version), text))
        }
        func accept(_ label: String, _ d: JSON, _ id: String, version: String = "2.5.1") throws {
            cases.append((label, try Self.verdict(d, id, version: version), nil))
        }
        var adt = try Self.load("ADT_A01"); adt["comment"] = "x"
        try reject("unknown key in a structure file", "unknown key(s) [\"comment\"]", adt, "ADT_A01")
        // P8b-4: the profile keys belong to profiles/<profile>/ files only (the script's other
        // profile cases concern those files, which the corpus decoder never reads).
        var tagged = try Self.load("ADT_A01"); tagged["profile"] = "au-adrm-2021"
        try reject("profile key in a version file", "unknown key(s) [\"profile\"]", tagged, "ADT_A01")
        try reject("unknown key in an element", "unknown key(s) [\"repeat\"]",
                   Self.element(try Self.load("ADT_A01"), 1) { $0["repeat"] = true }, "ADT_A01")
        try reject("missing max", "missing key \"max\"", Self.element(try Self.load("ACK"), 0) { $0["max"] = nil }, "ACK")
        var oru = try Self.load("ORU_R01")
        oru["elements"] = Self.firstGroup(oru["elements"] as? [JSON] ?? []) { $0["nameSource"] = "guessed" }
        try reject("nameSource outside the accepted set", "needs nameSource", oru, "ORU_R01")
        oru["elements"] = Self.firstGroup(oru["elements"] as? [JSON] ?? []) { $0["nameSource"] = nil }
        try reject("group without nameSource", "needs nameSource", oru, "ORU_R01")
        try accept("nameSource v2xml cited", try Self.oru("v2xml", "PATIENT_RESULT (HL7-xml v2.5.1/ORU_R01.xsd, ORU_R01.PATIENT_RESULT.CONTENT)."), "ORU_R01")
        try accept("nameSource v2xml-v2.4 on v2.3", try Self.oru("v2xml-v2.4", "PATIENT_RESULT (HL7-xml v2.4/ORU_R01.xsd, ORU_R01.PATIENT_RESULT.CONTENT, derived for v2.3 ORU_R01).", version: "2.3"), "ORU_R01", version: "2.3")
        try accept("nameSource synthesised", try Self.oru("synthesised", "PATIENT_RESULT (synthesised: no HL7-xml group matches)."), "ORU_R01")
        try accept("nameSource override", try Self.oru("override", "PATIENT_RESULT (overrides.json: a cited name)."), "ORU_R01")
        oru = try Self.load("ORU_R01")
        oru["citation"] = (oru["citation"] as? String ?? "").components(separatedBy: unprinted)[0]
        try reject("a non-printed name the citation does not cite", "is not cited", oru, "ORU_R01")
        // P8b-14: v2.3.1 has its own bundle, cited by its folder as on disk (no "v").
        try accept("nameSource v2xml on v2.3.1", try Self.oru("v2xml", "PATIENT_RESULT (HL7-xml 2.3.1/ORU_R01.xsd, ORU_R01.PATIENT_RESULT.CONTENT, generator HL7-Database).", version: "2.3.1"), "ORU_R01", version: "2.3.1")
        try reject("nameSource v2xml on v2.3.1 cited to a folder that does not exist", "is not cited", try Self.oru("v2xml", "PATIENT_RESULT (HL7-xml v2.3.1/ORU_R01.xsd, ORU_R01.PATIENT_RESULT.CONTENT).", version: "2.3.1"), "ORU_R01", version: "2.3.1")
        try reject("nameSource v2xml on v2.3", "for v2.3 and v2.3.1 only", try Self.oru("v2xml", "PATIENT_RESULT (HL7-xml v2.3/ORU_R01.xsd, ORU_R01.PATIENT_RESULT.CONTENT).", version: "2.3"), "ORU_R01", version: "2.3")
        try reject("nameSource v2xml-v2.4 outside v2.3 and v2.3.1", "for v2.3 and v2.3.1 only", try Self.oru("v2xml-v2.4", "PATIENT_RESULT (HL7-xml v2.4/ORU_R01.xsd, ORU_R01.PATIENT_RESULT.CONTENT)."), "ORU_R01")
        // P8b-15: v2.3 names derived through the v2.3.1 bundle first, cited by its folder as on disk.
        try accept("nameSource v2xml-v2.3.1 on v2.3", try Self.oru("v2xml-v2.3.1", "PATIENT_RESULT (HL7-xml 2.3.1/ORU_R01.xsd, ORU_R01.PATIENT_RESULT.CONTENT, generator HL7-Database, derived for v2.3 ORU_R01).", version: "2.3"), "ORU_R01", version: "2.3")
        try reject("nameSource v2xml-v2.3.1 outside v2.3", "v2xml-v2.3.1 for v2.3 only", try Self.oru("v2xml-v2.3.1", "PATIENT_RESULT (HL7-xml 2.3.1/ORU_R01.xsd, ORU_R01.PATIENT_RESULT.CONTENT, generator HL7-Database).", version: "2.3.1"), "ORU_R01", version: "2.3.1")
        try reject("nameSource v2xml-v2.3.1 cited to a folder that does not exist", "is not cited", try Self.oru("v2xml-v2.3.1", "PATIENT_RESULT (HL7-xml v2.3.1/ORU_R01.xsd, ORU_R01.PATIENT_RESULT.CONTENT, derived for v2.3 ORU_R01).", version: "2.3"), "ORU_R01", version: "2.3")
        try reject("max below min", "bad occurrence bounds", Self.element(try Self.load("ACK"), 0) { $0["min"] = 2 }, "ACK")
        adt = try Self.load("ADT_A01"); adt["triggers"] = ["ADT-A01"] + ((adt["triggers"] as? [String] ?? []).dropFirst())
        try reject("malformed trigger", "triggers must be", adt, "ADT_A01")
        var ack = try Self.load("ACK"); ack["version"] = "2.6"
        try reject("version not matching the directory", "do not match the path", ack, "ACK")

        // P8b-6 choice cases.
        try accept("unnamed choice", try Self.ackChoice(), "ACK")
        try accept("named choice with a printed name", try Self.ackChoice {
            $0["choice"] = "ACKNOWLEDGMENT"; $0["nameSource"] = "printed"; $0["min"] = 0; $0["max"] = NSNull()
        }, "ACK")
        try accept("an unnamed choice as an alternative of a choice", try Self.ackChoice {
            var alternatives = $0["alternatives"] as? [JSON] ?? []
            alternatives[1] = ["choice": NSNull(), "min": 1, "max": 1, "alternatives": [
                ["segment": "UAC", "min": 1, "max": 1] as JSON, ["segment": "ERR", "min": 1, "max": 1] as JSON]]
            $0["alternatives"] = alternatives
        }, "ACK")
        let two = "needs at least two \"alternatives\""
        try reject("choice with one alternative", two, try Self.ackChoice { $0["alternatives"] = Array(($0["alternatives"] as? [JSON] ?? []).prefix(1)) }, "ACK")
        try reject("choice with no alternatives", two, try Self.ackChoice { $0["alternatives"] = [JSON]() }, "ACK")
        try reject("choice with elements in place of alternatives", two, try Self.ackChoice { $0["elements"] = $0["alternatives"]; $0["alternatives"] = nil }, "ACK")
        try reject("choice with max 0", "bad occurrence bounds", try Self.ackChoice { $0["min"] = 0; $0["max"] = 0 }, "ACK")
        try reject("element that is both a choice and a group", "exactly one of \"segment\", \"group\", \"choice\" or \"slot\"",
                   try Self.ackChoice { $0["group"] = "X"; $0["nameSource"] = "printed" }, "ACK")
        try reject("unnamed choice with a nameSource", "unnamed choice cannot have a nameSource", try Self.ackChoice { $0["nameSource"] = "printed" }, "ACK")
        try reject("named choice without nameSource", "choice ACKNOWLEDGMENT needs nameSource", try Self.ackChoice { $0["choice"] = "ACKNOWLEDGMENT" }, "ACK")
        try reject("named choice with a bad name", "bad choice name", try Self.ackChoice { $0["choice"] = "ack-x"; $0["nameSource"] = "printed" }, "ACK")
        try reject("named choice from a bundle the citation does not cite", "choice ACKNOWLEDGMENT (nameSource v2xml) is not cited",
                   try Self.ackChoice { $0["choice"] = "ACKNOWLEDGMENT"; $0["nameSource"] = "v2xml" }, "ACK")
        try reject("a bad segment inside an alternative", "bad segment ID", try Self.ackChoice {
            var alternatives = $0["alternatives"] as? [JSON] ?? []
            alternatives[1]["segment"] = "uac"
            $0["alternatives"] = alternatives
        }, "ACK")
        try reject("segment with alternatives", "cannot have elements, alternatives or a nameSource",
                   Self.element(try Self.load("ACK"), 2) { $0["alternatives"] = [JSON]() }, "ACK")

        // S3-1 open-slot cases.
        try accept("slot with a printed name", try Self.ackSlot(), "ACK")
        try accept("unnamed slot", try Self.ackSlot { $0["slot"] = NSNull() }, "ACK")
        try reject("uncited slot", "a slot needs a non-empty \"citation\"", try Self.ackSlot { $0["citation"] = nil }, "ACK")
        try reject("slot with an empty citation", "a slot needs a non-empty \"citation\"", try Self.ackSlot { $0["citation"] = " " }, "ACK")
        try reject("slot named like a segment", "bad slot name \"OBR\"", try Self.ackSlot { $0["slot"] = "OBR" }, "ACK")
        try reject("slot with elements", "a slot cannot have elements, alternatives or a nameSource",
                   try Self.ackSlot { $0["elements"] = [Self.slotJSON] }, "ACK")
        try reject("citation on a segment", "only a slot has a \"citation\"",
                   Self.element(try Self.load("ACK"), 2) { $0["citation"] = "CH02" }, "ACK")
        try reject("slot inside a choice", "a slot cannot be inside a choice", try Self.ackChoice {
            var alternatives = $0["alternatives"] as? [JSON] ?? []
            alternatives[1] = Self.slotJSON
            $0["alternatives"] = alternatives
        }, "ACK")
        var adjacent = try Self.ackSlot()
        var list = adjacent["elements"] as? [JSON] ?? []
        list.insert(Self.slotJSON, at: 3)
        adjacent["elements"] = list
        try reject("two adjacent slots", "two adjacent slots", adjacent, "ACK")

        // S4-1 keyed-choice cases (v2.5.1 MFN_M03, keyed by MFI-1).
        let every = "every alternative must be a group occurring once, with a distinct name"
        try accept("keyed choice as committed", try Self.mfnKeyed(), "MFN_M03")
        try reject("key on a group", "only a choice has a \"key\"", try Self.element(Self.load("MFN_M03"), 3) {
            $0["key"] = ["segment": "MFI", "field": 1, "component": 1, "values": ["OMA": "MF_TEST"], "citation": "CH08"] as JSON
        }, "MFN_M03")
        try reject("keyed value mapping to no alternative", "values map to no alternative: [\"MF_NOPE\"]",
                   try Self.mfnKeyed { Self.rekey(&$0) { var v = $0["values"] as? [String: String] ?? [:]; v["ZZZ"] = "MF_NOPE"; $0["values"] = v } }, "MFN_M03")
        try reject("keyed alternative no value selects", "no value selects [\"MF_OBS_ATTRIBUTES\"]",
                   try Self.mfnKeyed { Self.rekey(&$0) { var v = $0["values"] as? [String: String] ?? [:]; v["OME"] = nil; $0["values"] = v } }, "MFN_M03")
        try reject("keyed alternative that is a segment", every, try Self.mfnKeyed {
            var alternatives = $0["alternatives"] as? [JSON] ?? []
            alternatives[4] = ["segment": "OM7", "min": 1, "max": 1]
            $0["alternatives"] = alternatives
        }, "MFN_M03")
        try reject("optional keyed alternative", every, try Self.mfnKeyed {
            var alternatives = $0["alternatives"] as? [JSON] ?? []
            alternatives[4]["min"] = 0
            $0["alternatives"] = alternatives
        }, "MFN_M03")
        try reject("key with an empty citation", "the key needs a non-empty \"citation\"",
                   try Self.mfnKeyed { Self.rekey(&$0) { $0["citation"] = " " } }, "MFN_M03")
        try reject("key segment not in the structure", "a keyed choice's key segment PID is not in the structure",
                   try Self.mfnKeyed { Self.rekey(&$0) { $0["segment"] = "PID" } }, "MFN_M03")
        try reject("unknown key in a key", "key: unknown key(s) [\"name\"]",
                   try Self.mfnKeyed { Self.rekey(&$0) { $0["name"] = "MFI-1" } }, "MFN_M03")

        try accept("keyed choice whose two values select one alternative",
                   try Self.mfnKeyed { Self.rekey(&$0) { var v = $0["values"] as? [String: String] ?? [:]; v["OMX"] = "MF_TEST_NUMERIC"; $0["values"] = v } }, "MFN_M03")
        // The S4-2 alias cases concern the codegen's directory walk (validateAliases), not one file.

        #expect(cases.count == 54)
        for c in cases {
            if let expected = c.expected {
                #expect(c.verdict?.contains(expected) == true, "\(c.label): \(c.verdict ?? "accepted")")
            } else {
                #expect(c.verdict == nil, "\(c.label): \(c.verdict ?? "")")
            }
        }
    }
}
