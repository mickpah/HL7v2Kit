// StructureVariantTests.swift
// S6-1 (ADR-019 S6): the per-trigger prints of a structure ID as the generated tables carry
// them, their selection by MSH-9.1^9.2, the compiled matcher of each, and the group spans,
// which come from the print that governs the message's trigger.

import Testing
@testable import HL7v2Kit

@Suite("Per-trigger structure variants")
struct StructureVariantTests {

    @Test("The variant governs its printed triggers; every other trigger takes the default print")
    func selection() throws {
        let a30 = try #require(MessageStructureTable.structure("ADT_A30", version: .v2_6))
        let printed = try #require(a30.variant(messageCode: "ADT", triggerEvent: "A48"))
        #expect(printed.triggers == ["ADT^A30", "ADT^A35", "ADT^A48", "ADT^A49"])
        #expect(!printed.elements.flatMap(\.segmentIDs).contains("ARV"))
        #expect(a30.elements.flatMap(\.segmentIDs).contains("ARV"))
        #expect(a30.variant(messageCode: "ADT", triggerEvent: "A34") == nil)
        #expect(a30.selectingVariant(messageCode: "ADT", triggerEvent: "A34") == a30)
        let selected = a30.selectingVariant(messageCode: "ADT", triggerEvent: "A30")
        #expect(selected.elements == printed.elements && selected.variants.isEmpty && selected.variantIndex == 0)
        #expect(selected.citation == printed.citation && selected.id == "ADT_A30")

        // v2.6 ACK: the CH02 general acknowledgment is the default for every trigger ("varies");
        // the CH10 print governs only the scheduling triggers it lists.
        let ack = try #require(MessageStructureTable.structure("ACK", version: .v2_6))
        #expect(ack.triggers == ["ACK^*"])
        #expect(ack.elements.contains(.segment("UAC", min: 0, max: 1)))
        #expect(ack.variant(messageCode: "ACK", triggerEvent: "A01") == nil)
        let scheduling = try #require(ack.variant(messageCode: "ACK", triggerEvent: "S26"))
        #expect(scheduling.elements.contains(.segment("UAC", min: 0, max: nil)))
        #expect(ack.variant(messageCode: "ACK", triggerEvent: "S25") == nil)
    }

    static let expected: [String: Set<String>] = [
        "2.3": ["ACK"],
        "2.3.1": ["ACK", "MFK_M01"],
        "2.4": ["ACK", "ADT_A09", "MFK_M01", "RQC_I05"],
        "2.5.1": ["ACK", "ADT_A05", "RDE_O11", "RQC_I05", "RRE_O12", "RSP_K21"],
        "2.6": ["ACK", "ADT_A01", "ADT_A30", "ADT_A43", "MFK_M01", "QRY_PC4", "RDE_O11", "RQC_I05", "RRE_O12", "RSP_K21"],
        "2.7.1": ["ACK", "RDE_O11", "RQC_I05"],
        "2.8.2": ["ACK", "RDE_O11"],
    ]

    @Test("Every variant is cited, exact, accepted by its structure and differs from the default print")
    func generated() {
        for version in Version.allCases where version.grammarVersion == version {
            let table = MessageStructureTable.structures(for: version)
            let varied = Set(table.values.filter { !$0.variants.isEmpty }.map(\.id))
            #expect(varied == Self.expected[version.rawValue] ?? [], "v\(version.rawValue)")
            for structure in table.values {
                var seen: Set<String> = []
                for variant in structure.variants {
                    #expect(variant.citation.contains("overrides.json variantPrints"), "\(structure.id)")
                    #expect(variant.elements != structure.elements, "\(structure.id)")
                    #expect(variant.requiresExactMatch == !StructureMatcher.lint(variant.elements).isDeterministic)
                    for trigger in variant.triggers {
                        let parts = trigger.split(separator: "^").map(String.init)
                        #expect(parts.count == 2 && parts[1] != "*", "\(structure.id) \(trigger)")
                        #expect(structure.accepts(messageCode: parts[0], triggerEvent: parts[1]), "\(structure.id) \(trigger)")
                        #expect(seen.insert(trigger).inserted, "\(structure.id) \(trigger) twice")
                    }
                }
            }
        }
    }

    @Test("Each print is compiled once, apart from the default")
    func cache() throws {
        let k21 = try #require(MessageStructureTable.structure("RSP_K21", version: .v2_5_1))
        let selected = k21.selectingVariant(messageCode: "RSP", triggerEvent: "K21")
        let cache = StructureMatcherCache()
        #expect(cache.matcher(for: selected).structure.elements == selected.elements)
        #expect(cache.matcher(for: k21).structure.elements == k21.elements)
        #expect(cache.matcher(for: selected).structure == selected)
        #expect(cache.buildCount(version: "2.5.1", id: "RSP_K21") == 1)
    }

    @Test("The group spans come from the print that governs the trigger")
    func spans() throws {
        func outcome(_ msh9: String) throws -> (spans: GroupSpanIndex?, cause: String?) {
            let wire = (["MSH|^~\\&|SND|SFAC|RCV|RFAC|20240101120000||\(msh9)|MSG00001|P|2.6"]
                        + StructureVariantProbeTests.merge).joined(separator: "\r")
            return Validator(options: .default).groupSpanOutcome(for: try Parser().parse(wire))
        }
        let a34 = try outcome("ADT^A34^ADT_A30")
        #expect(a34.spans != nil && a34.cause == nil)
        let a30 = try outcome("ADT^A30^ADT_A30")
        #expect(a30.spans == nil)
        #expect(a30.cause?.contains("ARV") == true, "\(a30.cause ?? "nil")")
    }
}
