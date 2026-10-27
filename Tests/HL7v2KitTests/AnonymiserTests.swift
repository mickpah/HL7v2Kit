// AnonymiserTests.swift
// X1 task 4b: the Anonymiser library API. Under one key the same original value gives the
// same synthetic value in every message, so linkage across messages survives; the output
// keeps the input's shape, so it validates as the input did.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Anonymiser (library)")
struct AnonymiserTests {
    static func anonymised(_ wire: String, key: UInt64 = 7,
                           replacingIdentifier: (@Sendable (Anonymiser.Identifier) -> String)? = nil) throws -> Message {
        let input = try Parser().parse(wire)
        return try Parser().parse(Anonymiser(key: key, replacingIdentifier: replacingIdentifier).anonymise(input).serialize())
    }

    static func wire(control: String, _ segments: String...) -> String {
        (["MSH|^~\\&|LAB|FAC|EMR|FAC|20240101120000||ADT^A01^ADT_A01|\(control)|P|2.4"] + segments)
            .joined(separator: "\r") + "\r"
    }

    static let pid = "PID|1||MRN12345^^^HOSP^MR||MARKERFAM^MARKERGIV"

    @Test("Under one key the same value gives the same output in messages with different MSH-10")
    func sameValueSameOutputUnderOneKey() throws {
        let a = try Self.anonymised(Self.wire(control: "CTRL1", Self.pid))
        let b = try Self.anonymised(Self.wire(control: "CTRL2", Self.pid))
        #expect(a["PID-3.1"] == b["PID-3.1"] && a["PID-3.1"] != "MRN12345")
        #expect(a["PID-5.1"] == "Edwards" && a["PID-5.2"] == "Taylor")   // key 7, from the seed rule
        #expect(b["PID-5.1"] == "Edwards" && b["PID-5.2"] == "Taylor")
    }

    @Test("A different key gives a different name")
    func differentKeyDifferentOutput() throws {
        let eight = try Self.anonymised(Self.wire(control: "CTRL1", Self.pid), key: 8)
        #expect(eight["PID-5.1"] == "Jensen" && eight["PID-5.2"] == "Casey")
    }

    @Test("The identifier seed is the shared FNV-1a value")
    func seedMatchesSharedLiteral() {
        #expect(anonymiserSeed(key: 42, kind: "identifier", original: "8003608166690503") == 13_496_976_630_852_856_219)
    }

    @Test("The closure sees CX-1, CX-5, CX-4.1 and the seed, nil where absent, and its value is written")
    func identifierClosureSeesContext() throws {
        final class Seen: @unchecked Sendable { var calls: [Anonymiser.Identifier] = [] }
        let seen = Seen()
        let out = try Self.anonymised(
            Self.wire(control: "C1", "PID|1||8003608166690503^^^AUSHIC^NI~ABC123||FAM^GIV"), key: 42
        ) { identifier in
            seen.calls.append(identifier)
            return "REPLACED\(seen.calls.count)"
        }
        #expect(seen.calls == [
            Anonymiser.Identifier(value: "8003608166690503", typeCode: "NI", assigningAuthority: "AUSHIC",
                                  seed: 13_496_976_630_852_856_219),
            Anonymiser.Identifier(value: "ABC123", typeCode: nil, assigningAuthority: nil,
                                  seed: anonymiserSeed(key: 42, kind: "identifier", original: "ABC123")),
        ])
        #expect(out["PID-3.1"] == "REPLACED1" && out["PID-3~2.1"] == "REPLACED2")
        #expect(out["PID-3.4"] == "AUSHIC" && out["PID-3.5"] == "NI")
    }

    @Test("An identifier held in subcomponents is still replaced")
    func identifierInSubcomponentsReplaced() throws {
        let out = try Self.anonymised(Self.wire(control: "C1", "PID|1||MARKERA&MARKERB^^^H^MR||FAM"))
        #expect(!String(decoding: out.serialize(), as: UTF8.self).contains("MARKER"))
        #expect(out["PID-3.4"] == "H" && out["PID-3.5"] == "MR")
    }

    @Test("Every repetition is replaced, an escaped name round-trips")
    func repetitionsAndEscapes() throws {
        let out = try Self.anonymised(Self.wire(control: "C1", #"PID|1||1^^^H^MR||SMITH^JOHN~O\T\BRIEN^MARY"#))
        let bytes = out.serialize()
        let text = String(decoding: bytes, as: UTF8.self)
        for original in ["SMITH", "JOHN", "BRIEN", "MARY"] { #expect(!text.contains(original), "\(original)") }
        #expect(out["PID-5~2.1"] != nil)
        #expect(try Parser().parse(bytes).serialize() == bytes)
    }

    @Test("An empty or absent field or component stays empty: nothing is invented")
    func emptyStaysEmpty() throws {
        let wire = "MSH|^~\\&|LAB|FAC||FAC|20240101120000||ADT^A01^ADT_A01|C1|P|2.4\rPID|1||1^^^H^MR||FAM\rGT1|1||GUARFAM^GUARGIV|||\rNTE|1||\r"
        let out = try Parser().parse(Anonymiser(key: 7).anonymise(try Parser().parse(wire)).serialize())
        for path in ["MSH-5", "PID-5.2", "PID-13", "GT1-6", "NTE-3"] { #expect((out[path] ?? "").isEmpty, "\(path)") }
    }

    @Test("Type codes, authorities and use codes are kept")
    func shapeKept() throws {
        let out = try Self.anonymised(Self.wire(control: "C1",
            "PID|1||1^^^H^MR||FAM^GIV||||||1 Main St^^Town^NSW^2000^AU^H||^PRN^PH^^^^5551234",
            "PV1|1|O|||||1234567A^DOC^ANNE^^^DR^^^AUSHICPR^^^^PRN"))
        #expect(out["PID-3.4"] == "H" && out["PID-3.5"] == "MR")
        #expect(out["PID-11.6"] == "AU" && out["PID-11.7"] == "H" && out["PID-11.1"] != "1 Main St")
        #expect(out["PID-13.2"] == "PRN" && out["PID-13.3"] == "PH" && out["PID-13.7"] != "5551234")
        #expect(out["PV1-7.6"] == "DR" && out["PV1-7.9"] == "AUSHICPR" && out["PV1-7.13"] == "PRN")
        #expect(out["PV1-7.1"] != "1234567A")
    }

    @Test("Under a key, every covered field loses its original value", arguments: AnonymiseTests.covered)
    func coveredFieldScrubbedUnderAKey(_ field: String) throws {
        let out = Anonymiser(key: 7).anonymise(try Parser().parse(AnonymiseTests.wire)).serialize()
        #expect(!String(decoding: out, as: UTF8.self).contains(AnonymiseTests.marker(field)))
    }

    @Test("Key 42 output for two fixtures matches the committed baseline (every run, macOS and Linux)")
    func pinnedOutputForKey42() throws {
        var lines: [String] = []
        for name in ["adt_a01_with_insurance.hl7", "adt_a01_with_nk1.hl7"] {
            let message = try Parser().parse(Data(contentsOf: FixtureCorpus.fixtureURL(named: name)))
            lines.append("# \(name)")
            lines += String(decoding: Anonymiser(key: 42).anonymise(message).serialize(), as: UTF8.self)
                .split(separator: "\r", omittingEmptySubsequences: false).map(String.init)
        }
        try Baseline.check(lines, against: "anonymiser-key42.txt")
    }

    /// Findings the anonymiser changes by design, as `fixture|number@path`, with the reason.
    static let expectedChanges: [String: String] = [:]

    @Test("Each AU fixture validates the same after anonymising (strict, AU profile)")
    func outputValidatesLikeInput() throws {
        let validator = Validator(options: .strict, locale: .auLocalisation)
        func findings(_ message: Message) -> [String] {
            validator.validate(message).issues.map { "\($0.code.number)@\($0.location.pathDescription)" }.sorted()
        }
        for url in try FixtureCorpus.validFixtureURLs() where url.lastPathComponent.hasPrefix("au_") {
            let name = url.lastPathComponent
            let input = try Parser().parse(Data(contentsOf: url))
            let output = try Parser().parse(Anonymiser(key: 42).anonymise(input).serialize())
            let kept = { (finding: String) in Self.expectedChanges["\(name)|\(finding)"] == nil }
            #expect(findings(input).filter(kept) == findings(output).filter(kept), "\(name)")
        }
    }

    @Test("No synthetic value depends on Swift's per-process hashing")
    func noProcessHashing() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/HL7v2Kit/Anonymiser")
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let source = try String(contentsOf: url, encoding: .utf8)
            #expect(!source.contains("Hasher") && !source.contains("hashValue"), "\(url.lastPathComponent)")
        }
    }
}
