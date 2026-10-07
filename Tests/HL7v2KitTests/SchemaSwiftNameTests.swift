// SchemaSwiftNameTests.swift
// P6-9: pins the `swiftName` of every schema field to its printed element name. The schema
// extractor once let definition prose bleed into a name (TQ2-10 reached 873 characters) and
// cut others short (v2.8.2 RXA-2 "nistrationSubIdCounter"). Two of the bad names shipped as
// public accessors in v3.13.0 and keep a deprecated alias (ADR-014).

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Schema swiftName integrity")
struct SchemaSwiftNameTests {
    private struct Schema: Decodable {
        struct Field: Decodable {
            let index: Int
            let swiftName: String
            let name: String
        }
        let segmentID: String
        let fields: [Field]
    }

    /// The longest legitimate name is 66 characters (v2.8.2 OM1-56, "Observation/Identifier
    /// associated with Producer's Service/Test/Observation ID"); every prose bleed was 94 or
    /// more. Mirrors `SWIFT_NAME_MAX` in scripts/private/audit-schemas.py.
    private static let maxLength = 70

    private static var schemasRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HL7v2KitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("Resources/schemas")
    }

    private func schemas() throws -> [(version: String, schema: Schema)] {
        let fm = FileManager.default
        var out: [(String, Schema)] = []
        for dir in try fm.contentsOfDirectory(atPath: Self.schemasRoot.path).sorted() where dir.hasPrefix("v") {
            let url = Self.schemasRoot.appendingPathComponent(dir)
            for file in try fm.contentsOfDirectory(atPath: url.path).sorted() where file.hasSuffix(".json") {
                let data = try Data(contentsOf: url.appendingPathComponent(file))
                out.append((dir, try JSONDecoder().decode(Schema.self, from: data)))
            }
        }
        return out
    }

    private func swiftName(_ version: String, _ segment: String, _ index: Int) throws -> String {
        let url = Self.schemasRoot.appendingPathComponent("v\(version)/\(segment).json")
        let schema = try JSONDecoder().decode(Schema.self, from: Data(contentsOf: url))
        return try #require(schema.fields.first { $0.index == index }, "\(segment)-\(index)").swiftName
    }

    @Test("Every swiftName is a lowerCamelCase identifier of sane length, unique in its segment")
    func shape() throws {
        for (version, schema) in try schemas() {
            var seen: Set<String> = []
            for field in schema.fields {
                let slot = "\(version) \(schema.segmentID)-\(field.index) \(field.swiftName.prefix(60))"
                #expect(field.swiftName.count <= Self.maxLength, "\(slot): \(field.swiftName.count) characters")
                #expect(field.swiftName.range(of: "^[a-z][A-Za-z0-9]*$", options: .regularExpression) != nil,
                        "\(slot): not a lowerCamelCase identifier")
                #expect(seen.insert(field.swiftName).inserted, "\(slot): duplicate swiftName")
            }
        }
    }

    /// An element name reduced for comparison: lower case, a trailing "(deprecated)" or
    /// "(withdrawn)" dropped, alphanumerics only. Mirrors `normalised_name` in the audit.
    private static func normalised(_ name: String) -> String {
        let lower = name.lowercased()
            .replacingOccurrences(of: "\\s*\\((deprecated|withdrawn)\\)\\s*$", with: "", options: .regularExpression)
        return String(lower.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    @Test("Every swiftName follows the naming convention: canonical name where the element matches, else anchored to the element name")
    func anchoredToElementName() throws {
        let all = try schemas()
        var canonical: [String: (swiftName: String, name: String)] = [:]
        for (version, schema) in all where version == "v2.5.1" {
            for field in schema.fields { canonical["\(schema.segmentID)-\(field.index)"] = (field.swiftName, field.name) }
        }
        for (version, schema) in all {
            for field in schema.fields {
                let slot = "\(version) \(schema.segmentID)-\(field.index): \(field.swiftName) vs \(field.name)"
                let base = version == "v2.5.1" ? nil : canonical["\(schema.segmentID)-\(field.index)"]
                // The same element as the canonical slot takes the canonical name, possessive "S" included.
                if let base, Self.normalised(base.name) == Self.normalised(field.name) {
                    #expect(field.swiftName == base.swiftName, "\(slot): canonical is \(base.swiftName)")
                }
                // Non-canonical versions inherit the canonical v2.5.1 name by index by design, even
                // where the element was later renamed (v2.3 PID-8 "Sex" is `administrativeSex`).
                if base?.swiftName == field.swiftName { continue }
                let words = field.name.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
                var name = field.swiftName.lowercased()
                if name.range(of: "^f[0-9]", options: .regularExpression) != nil { name.removeFirst() }
                let head = String(name.prefix(4))
                let anchored = words.indices.contains { words[$0...].joined().hasPrefix(head) }
                #expect(anchored, "\(slot)")
            }
        }
    }

    @Test("Every element name reads as a title, not definition prose")
    func elementNamesAreTitles() throws {
        // Mirrors ELEMENT_NAME_WORDS_MAX / ELEMENT_NAME_LOWER_RUN_MAX in scripts/private/audit-schemas.py:
        // the corpus maximum is 10 words and a run of 4 lowercase-led words.
        for (version, schema) in try schemas() {
            for field in schema.fields {
                let words = field.name.split(separator: " ")
                var run = 0, longest = 0
                for word in words {
                    run = word.first?.isLowercase == true ? run + 1 : 0
                    longest = max(longest, run)
                }
                let slot = "\(version) \(schema.segmentID)-\(field.index) \(field.name.prefix(60))"
                #expect(words.count <= 11, "\(slot): \(words.count) words")
                #expect(longest <= 5, "\(slot): \(longest) lowercase words in a row")
            }
        }
    }

    @Test("Slots the extractor corrupted carry the printed element name")
    func pinnedSlots() throws {
        let expected: [(String, String, Int, String)] = [
            ("2.5.1", "TQ2", 10, "specialServiceRequestRelationship"),
            ("2.6", "TQ2", 10, "specialServiceRequestRelationship"),
            ("2.8.2", "TQ2", 10, "specialServiceRequestRelationship"),
            ("2.4", "QPD", 2, "queryTag"),
            ("2.5.1", "QPD", 2, "queryTag"),
            ("2.6", "QPD", 2, "queryTag"),
            ("2.8.2", "QPD", 2, "queryTag"),
            ("2.8.2", "BPX", 21, "bpDispensingIndividual"),
            ("2.8.2", "BTX", 20, "bpUniqueId"),
            ("2.8.2", "ITM", 16, "approvingRegulatoryAgency"),
            ("2.8.2", "OM1", 56, "observationIdentifierAssociatedWithProducerServiceTestObservationId"),
            ("2.8.2", "RXA", 2, "administrationSubIdCounter"),
            ("2.8.2", "RXD", 1, "dispenseSubIdCounter"),
            ("2.8.2", "RXO", 2, "requestedGiveAmountMinimum"),
            ("2.4", "RXE", 1, "quantityTiming"),
            ("2.3.1", "RXE", 2, "giveCode"),
            ("2.4", "LOC", 6, "locationPhone"),
            ("2.3", "QRF", 2, "whenDataStartDateTime"),
            ("2.3.1", "RXE", 3, "giveAmountMinimum"),
            ("2.4", "LOC", 3, "locationTypeLoc"),
            ("2.8.2", "RXA", 3, "dateTimeStartOfAdministration"),
            ("2.6", "TQ1", 14, "totalOccurrenceS"),
            ("2.8.2", "TXA", 23, "distributedCopiesCodeAndNameOfRecipients"),
        ]
        for (version, segment, index, name) in expected {
            #expect(try swiftName(version, segment, index) == name, "v\(version) \(segment)-\(index)")
        }
    }

    @Test("The public accessors use the printed element name")
    func renamedAccessors() throws {
        let wire = "MSH|^~\\&|A|B|C|D|20240101120000||QBP^Q11^QBP_Q11|M1|P|2.5.1\r"
            + "QPD|Q1^Query^HL7|tag1\r" + "TQ2|1|S|PL2^SYS|||||||C\r"
        let message = try Parser().parse(wire)
        let qpd = try #require(message.firstSegment(QPD.self))
        #expect(qpd.queryTag == "tag1")
        let tq2 = try #require(message.firstSegment(TQ2.self))
        #expect(tq2.specialServiceRequestRelationship == "C")
        #expect(tq2.specialServiceRequestRelationship == message["TQ2-10"])
    }

    @Test("The v3.13.0 accessor names still compile and read the same field (deprecated aliases)")
    func deprecatedAliases() throws {
        let wire = "MSH|^~\\&|A|B|C|D|20240101120000||QBP^Q11^QBP_Q11|M1|P|2.5.1\r"
            + "QPD|Q1^Query^HL7|tag1\r" + "TQ2|1|S|PL2^SYS|||||||C\r"
        let message = try Parser().parse(wire)
        let qpd = try #require(message.firstSegment(QPD.self))
        let tq2 = try #require(message.firstSegment(TQ2.self))
        let legacy: any LegacyAccessorNames = LegacyAccessors()
        #expect(legacy.queryTag(qpd) == "tag1")
        #expect(legacy.specialServiceRequestRelationship(tq2) == "C")
    }
}

/// Reaches the deprecated v3.13.0 names through a protocol so the call site carries no
/// deprecation warning: the build stays warning-free while still compiling the old names.
private protocol LegacyAccessorNames {
    func queryTag(_ segment: QPD) -> String?
    func specialServiceRequestRelationship(_ segment: TQ2) -> String?
}

private struct LegacyAccessors: LegacyAccessorNames {
    @available(*, deprecated, message: "exercises the v3.13.0 accessor names on purpose")
    func queryTag(_ segment: QPD) -> String? {
        segment.queryTagUserParametersInSuccessiveFields
    }

    @available(*, deprecated, message: "exercises the v3.13.0 accessor names on purpose")
    func specialServiceRequestRelationship(_ segment: TQ2) -> String? {
        // The full 873-character v3.13.0 name, prose bleed included.
        segment.specialServiceRequestRelationshipRequestsUsingTheParentChildParadigmTheFollowingOccursEcifiesThatItFollowTheFirstChildServiceRequestCifiesThatItFollowTheSecondChildServiceRequestEcifiesThatItFollowTheThirdServiceRequestStsInACyclicMannerTheFollowingOccursCifiesThatItIsToBeExecutedOnceWithoutAnyIceRequestsItsSecondExecutionFollowsTheSeeExampleInSection4152RxoSegmentFieldRequestsToBeReportedBackAtTheLevelOfTheParentRequestByFollowingTheStatusOfTheCorrespondingSentAsAGroupOfFourServiceRequestsWithoutANTheirQuantityTimingFieldsInThisCaseThereIsTheServiceRequestStatusOfTheGroupAsAWholeFTheFourSeparateServiceRequestsEventsFTheReferencedPredecessorServiceRequestThusAPredecessorServiceRequestImpliesTheCancellationQuentServiceRequestsInTheChainNCanceledOrDiscontinuedOrHeldTheCurrentOldOfThePredecessorImpliesARemovalOfTheHoldThenBeExecutedAccordingToTheSpecificationInThe
    }
}
