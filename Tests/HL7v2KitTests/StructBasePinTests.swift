// StructBasePinTests.swift
// P10-3 (ADR-020 amendment, ruling D2): a released segment struct keeps its
// union base for ever. Each generated struct names its base in its
// `// Source schema: Resources/schemas/v<version>/<ID>.json` header. The
// codegen takes the base from `Resources/struct-bases.json` where the segment
// is listed there, else from the canonical v2.5.1 schema. This guard fails if
// any generated struct's base differs from that rule, so a struct based on
// anything other than v2.5.1 must be listed (a new segment's base is added in
// the commit that introduces it), and a listed base can never move.

import Testing
import Foundation

@Suite("Released segment-struct bases are pinned (P10-3)")
struct StructBasePinTests {

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // HL7v2KitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repository root

    static let generated = root.appendingPathComponent("Sources/HL7v2Kit/Segment/Generated")

    /// The pinned `segment -> base version` map the codegen honours.
    static func pins() throws -> [String: String] {
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/struct-bases.json"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["bases"] as? [String: String] ?? [:]
    }

    /// `segment -> base version` read from every generated struct's header.
    static func generatedBases() throws -> [String: String] {
        var bases: [String: String] = [:]
        let prefix = "// Source schema: Resources/schemas/v"
        for url in try FileManager.default.contentsOfDirectory(at: generated, includingPropertiesForKeys: nil)
        where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            guard let line = text.components(separatedBy: "\n").first(where: { $0.hasPrefix(prefix) }) else { continue }
            let parts = line.dropFirst(prefix.count).split(separator: "/")
            bases[String(parts[1].dropLast(".json".count))] = String(parts[0])
        }
        return bases
    }

    /// The struct names released in v3.13.0 (the `SegmentGrammar+…` files are not structs).
    static func releasedStructs() throws -> Set<String> {
        let snapshot = root.appendingPathComponent("Tests/Fixtures/APISurface/segment-structs-v3.13.0.txt")
        return Set(try String(contentsOf: snapshot, encoding: .utf8)
            .components(separatedBy: "\n").filter { !$0.isEmpty }
            .map { String($0.split(separator: "|")[0]) }
            .filter { !$0.contains("+") })
    }

    @Test("Every generated struct is based on its pinned version, or on v2.5.1 when it has no pin")
    func everyStructHonoursItsPin() throws {
        let pins = try Self.pins()
        let bases = try Self.generatedBases()
        #expect(bases.count >= 188)
        for (segment, base) in bases {
            let expected = pins[segment] ?? "2.5.1"
            #expect(base == expected,
                    "\(segment) is based on v\(base) but the pin is v\(expected); add or correct it in Resources/struct-bases.json")
        }
    }

    @Test("Every pin names a generated struct and is not the default v2.5.1")
    func everyPinIsLive() throws {
        let bases = try Self.generatedBases()
        for (segment, version) in try Self.pins() {
            #expect(bases[segment] != nil, "\(segment) is pinned but no struct is generated")
            #expect(version != "2.5.1", "\(segment): v2.5.1 is the default base and needs no pin")
        }
    }

    @Test("Every struct released in v3.13.0 is still generated, and the 38 non-v2.5.1 bases are pinned")
    func releasedStructsArePinned() throws {
        let bases = try Self.generatedBases()
        let pins = try Self.pins()
        let released = try Self.releasedStructs()
        for segment in released {
            #expect(bases[segment] != nil, "\(segment) was released in v3.13.0 but is no longer generated")
        }
        #expect(released.filter { pins[$0] != nil }.count == 38)
        #expect(pins["IAR"] == "2.8.2" && pins["PAC"] == "2.8.2" && pins["PRT"] == "2.8.2" && pins["SHP"] == "2.8.2")
    }
}
