// StructureJSONDecoderTests.swift
// P8b-7 decoder parity: the corpus tests' decoder accepts and rejects
// exactly the structure files the codegen does. Every structure-file case of
// scripts/check-structure-codegen.sh (the completeness and directory cases
// concern the codegen's walk, not one file) is rebuilt here from the
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
        try reject("nameSource v2xml on v2.3", "for v2.3 and v2.3.1 only", try Self.oru("v2xml", "PATIENT_RESULT (HL7-xml v2.3/ORU_R01.xsd, ORU_R01.PATIENT_RESULT.CONTENT).", version: "2.3"), "ORU_R01", version: "2.3")
        try reject("nameSource v2xml-v2.4 outside v2.3 and v2.3.1", "for v2.3 and v2.3.1 only", try Self.oru("v2xml-v2.4", "PATIENT_RESULT (HL7-xml v2.4/ORU_R01.xsd, ORU_R01.PATIENT_RESULT.CONTENT)."), "ORU_R01")
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
        try reject("element that is both a choice and a group", "exactly one of \"segment\", \"group\" or \"choice\"",
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

        #expect(cases.count == 29)
        for c in cases {
            if let expected = c.expected {
                #expect(c.verdict?.contains(expected) == true, "\(c.label): \(c.verdict ?? "accepted")")
            } else {
                #expect(c.verdict == nil, "\(c.label): \(c.verdict ?? "")")
            }
        }
    }
}
