// MessageStructureTableTests.swift
// ADR-019 pilot: the v2.5.1 message structures load from the generated table
// and match the chapter print; the structure JSON keeps the ADR-019 schema and
// agrees with the generated table.

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Message structure table")
struct MessageStructureTableTests {

    private func names(_ elements: [StructureElement]) -> [String] {
        elements.map { element in
            switch element {
            case .segment(let id, _, _): return id
            case .group(let name, _, _, _): return name
            case .choice(let name, _, _, _), .keyedChoice(let name, _, _, _, _): return name ?? "<choice>"
            case .slot(let name, _, _, _): return name ?? "<slot>"
            }
        }
    }

    @Test("v2.5.1 ACK is MSH [{SFT}] MSA [{ERR}] for any trigger event (CH02 2.14.1)")
    func ackStructure() throws {
        let ack = try #require(MessageStructureTable.structure("ACK", version: .v2_5_1))
        #expect(ack.elements == [
            .segment("MSH", min: 1, max: 1),
            .segment("SFT", min: 0, max: nil),
            .segment("MSA", min: 1, max: 1),
            .segment("ERR", min: 0, max: nil),
        ])
        #expect(ack.triggers == ["ACK^*"])
        #expect(ack.accepts(messageCode: "ACK", triggerEvent: "A01"))
        #expect(ack.accepts(messageCode: "ACK", triggerEvent: ""))
        #expect(!ack.accepts(messageCode: "ADT", triggerEvent: "A01"))
    }

    @Test("v2.5.1 ADT_A01 top level follows CH03 3.3.1 in order")
    func adtA01TopLevel() throws {
        let adt = try #require(MessageStructureTable.structure("ADT_A01", version: .v2_5_1))
        #expect(names(adt.elements) == [
            "MSH", "SFT", "EVN", "PID", "PD1", "ROL", "NK1", "PV1", "PV2", "ROL", "DB1", "OBX",
            "AL1", "DG1", "DRG", "PROCEDURE", "GT1", "INSURANCE", "ACC", "UB1", "UB2", "PDA",
        ])
        #expect(adt.triggers == ["ADT^A01", "ADT^A04", "ADT^A08", "ADT^A13"])
        #expect(adt.version == "2.5.1")
        #expect(!adt.accepts(messageCode: "ADT", triggerEvent: "A02"))
    }

    @Test("v2.5.1 ADT_A01 INSURANCE is an optional, repeating IN1 [IN2] [{IN3}] [{ROL}]")
    func adtA01Insurance() throws {
        let adt = try #require(MessageStructureTable.structure("ADT_A01", version: .v2_5_1))
        #expect(adt.elements.contains(.group("INSURANCE", min: 0, max: nil, elements: [
            .segment("IN1", min: 1, max: 1),
            .segment("IN2", min: 0, max: 1),
            .segment("IN3", min: 0, max: nil),
            .segment("ROL", min: 0, max: nil),
        ])))
    }

    @Test("v2.5.1 ORU_R01 nests a required, repeating ORDER_OBSERVATION in PATIENT_RESULT (CH07 7.3.1)")
    func oruR01Nesting() throws {
        let oru = try #require(MessageStructureTable.structure("ORU_R01", version: .v2_5_1))
        #expect(names(oru.elements) == ["MSH", "SFT", "PATIENT_RESULT", "DSC"])
        let result = oru.elements[2]
        #expect(result.min == 1 && result.max == nil)
        #expect(result.groupName == "PATIENT_RESULT")
        guard case .group(_, _, _, let children) = result else {
            Issue.record("PATIENT_RESULT is not a group")
            return
        }
        #expect(names(children) == ["PATIENT", "ORDER_OBSERVATION"])
        let order = children[1]
        #expect(order.min == 1 && order.max == nil)
        #expect(order.headSegmentID == "OBR")
        #expect(order.firstSet == ["ORC", "OBR"])
        #expect(result.firstSet == ["PID", "ORC", "OBR"])
        guard case .group(_, _, _, let orderChildren) = order else {
            Issue.record("ORDER_OBSERVATION is not a group")
            return
        }
        #expect(names(orderChildren) == [
            "ORC", "OBR", "NTE", "TIMING_QTY", "CTD", "OBSERVATION", "FT1", "CTI", "SPECIMEN",
        ])
        // {[NTE]} and {[CTI]} in the print normalise to min 0, max unbounded (ADR-019).
        #expect(orderChildren[2] == .segment("NTE", min: 0, max: nil))
        #expect(orderChildren[7] == .segment("CTI", min: 0, max: nil))
    }

    @Test("Lookup by trigger line: ADT^A08 resolves to ADT_A01, ACK^A13 to ACK, SIU^S26 to SIU_S12")
    func triggerLookup() {
        #expect(MessageStructureTable.structures(messageCode: "ADT", triggerEvent: "A08", version: .v2_5_1).map(\.id) == ["ADT_A01"])
        #expect(MessageStructureTable.structures(messageCode: "ACK", triggerEvent: "A13", version: .v2_5_1).map(\.id) == ["ACK"])
        #expect(MessageStructureTable.structures(messageCode: "ADT", triggerEvent: "A02", version: .v2_5_1).map(\.id) == ["ADT_A02"])
        #expect(MessageStructureTable.structures(messageCode: "SIU", triggerEvent: "S26", version: .v2_5_1).map(\.id) == ["SIU_S12"])
        #expect(MessageStructureTable.structures(messageCode: "ADT", triggerEvent: "A02", version: .v2_6).map(\.id) == ["ADT_A02"])
        #expect(MessageStructureTable.structures(messageCode: "ADT", triggerEvent: "A02", version: .v2_7_1).map(\.id) == ["ADT_A02"])
        // v2.3 (P8b-15): each CH03 event prints its own table, under a synthesised CODE_EVT ID.
        #expect(MessageStructureTable.structures(messageCode: "ADT", triggerEvent: "A02", version: .v2_3).map(\.id) == ["ADT_A02"])
        #expect(MessageStructureTable.structures(messageCode: "ADT", triggerEvent: "A08", version: .v2_3).map(\.id) == ["ADT_A08"])
        #expect(MessageStructureTable.structures(messageCode: "ACK", triggerEvent: "A13", version: .v2_3).map(\.id) == ["ACK"])
    }

    // P8b-9: spot checks against the v2.5.1 print.
    @Test("v2.5.1 spot checks: SIU_S12 (CH10 10.4), MDM_T02 (CH09 9.5.2, erratum), ORM_O01's choice (CH04 4.4.1)")
    func v251SpotChecks() throws {
        let table = MessageStructureTable.structures(for: .v2_5_1)
        let siu = try #require(table["SIU_S12"])
        #expect(names(siu.elements) == ["MSH", "SCH", "TQ1", "NTE", "PATIENT", "RESOURCES"])
        #expect(siu.triggers.count == 14)
        let mdm = try #require(table["MDM_T02"])
        #expect(names(mdm.elements) == ["MSH", "SFT", "EVN", "PID", "PV1", "COMMON_ORDER", "TXA", "OBSERVATION"])
        let orm = try #require(table["ORM_O01"])
        #expect("\(orm.elements)".contains("choice("))
        #expect(table["RSP_K11"] == nil && MessageStructureTable.notModelled(for: .v2_5_1)["RSP_K11"] != nil)
    }

    /// overrides.json `sharedTriggers` as "<version> <trigger>" to the declared structure IDs.
    static func declaredSharedTriggers() throws -> [String: Set<String>] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/structures/overrides.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let entries = object?["sharedTriggers"] as? [[String: Any]] ?? []
        return Dictionary(uniqueKeysWithValues: entries.map { entry -> (String, Set<String>) in
            let version = entry["version"] as? String ?? ""
            let trigger = entry["trigger"] as? String ?? ""
            return (version + " " + trigger, Set(entry["structures"] as? [String] ?? []))
        })
    }

    @Test("No trigger line maps to two structures in one version, loaded or registered, unless declared shared")
    func triggersAreUnique() throws {
        let declared = try Self.declaredSharedTriggers()
        for version in Version.allCases where version == version.grammarVersion {
            var owners: [String: Set<String>] = [:]
            for structure in MessageStructureTable.structures(for: version).values {
                for trigger in structure.triggers { owners[trigger, default: []].insert(structure.id) }
            }
            for (id, gap) in MessageStructureTable.notModelled(for: version) {
                for trigger in gap.triggers { owners[trigger, default: []].insert(id) }
            }
            for (trigger, ids) in owners where ids.count > 1 {
                let names = declared["\(version.rawValue) \(trigger)"] ?? []
                #expect(ids.isSubset(of: names), "\(version.rawValue) \(trigger): \(ids.sorted()) not declared shared")
            }
        }
    }

    @Test("A registered not-modelled structure is never a loaded one, and carries a reason", arguments: Version.allCases)
    func registeredGapsAreNotLoaded(version: Version) {
        let loaded = MessageStructureTable.structures(for: version)
        for (id, gap) in MessageStructureTable.notModelled(for: version) {
            #expect(loaded[id] == nil, "\(version.rawValue) \(id)")
            #expect(!gap.reason.isEmpty)
        }
    }

    @Test("An unknown structure ID is a lookup miss, not a guess")
    func unknownStructure() {
        for version in Version.allCases {
            #expect(MessageStructureTable.structure("ZZZ_Z99", version: version) == nil)
            #expect(MessageStructureTable.structures(messageCode: "ZZZ", triggerEvent: "Z99", version: version).isEmpty)
        }
    }

    @Test("Public lookups resolve the grammar version (ADR-019, ADR-018): 2.8 reads the 2.8.2 table")
    func grammarVersionResolution() {
        for version in Version.allCases {
            let own = MessageStructureTable.structures(for: version.grammarVersion)
            for id in own.keys {
                #expect(MessageStructureTable.structure(id, version: version) == own[id])
            }
            #expect(MessageStructureTable.structures(messageCode: "ADT", triggerEvent: "A01", version: version)
                == MessageStructureTable.structures(messageCode: "ADT", triggerEvent: "A01", version: version.grammarVersion))
        }
    }

    // P8b-1: the version switch and the completeness set are generated from
    // Resources/structures/completeness.json.
    @Test("v2.3 (P8b-15), v2.3.1 (P8b-14), v2.4 (P8b-13), v2.5.1 (P8b-9), v2.6 (P8b-10), v2.7.1 (P8b-16) and v2.8.2 (P8b-11) are complete, substituted versions included", arguments: Version.allCases)
    func noVersionComplete(version: Version) {
        #expect(MessageStructureTable.isComplete(version) == [Version.v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_7_1, .v2_8_2].contains(version.grammarVersion))
        #expect(MessageStructureTable.completeVersions == [.v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_7_1, .v2_8_2])
    }

    @Test("The generated switch: 159 structures on v2.3 (P8b-15; eleven slot structures S3-3; ERP S4-1), 112 on v2.3.1 (P8b-14; MCF P8b-15; eleven S3-3; ERP_R09 S4-1), 159 on v2.4 (P8b-13; eight S3-3; ERP_R09, MFN_M03 S4-1, QRY_P04 S4-2), 184 on v2.5.1 (P8b-9; ERP_R09 registered P8b-13; eight S3-3; ERP_R09, MFN_M03 S4-1, QRY_P04 S4-2), 199 on v2.6 (P8b-10; RSP_K21 P8b-11; eight S3-3; MFN_M03 S4-1), with QRY_Q02 and QCK_Q02 on all three (P8b-13 fix round 1), 177 on v2.7.1 (P8b-16; the five naming withdrawn segments S2-2; eight S3-3), 190 on v2.8.2 (P8b-11; UDM_Q05 S2-2; four S3-3), none on any other version",
          arguments: Version.allCases)
    func generatedSwitch(version: Version) {
        let ids = MessageStructureTable.structures(for: version).keys.sorted()
        #expect(ids.count == (version == .v2_3 ? 159 : version == .v2_3_1 ? 112 : version == .v2_4 ? 159 : version == .v2_5_1 ? 184 : version.grammarVersion == .v2_6 ? 199 : version.grammarVersion == .v2_7_1 ? 177 : version.grammarVersion == .v2_8_2 ? 190 : 0))
        #expect(![Version.v2_3, .v2_3_1, .v2_4, .v2_5_1, .v2_6, .v2_7_1, .v2_8_2].contains(version.grammarVersion) || Set(["ACK", "ADT_A01", "ORU_R01"]).isSubset(of: ids))
        #expect(MessageStructureTable.structures(for: version) == MessageStructureTable.structures(for: version.grammarVersion))
    }

    @Test("Completeness is looked up through the grammar version (pre-flight C3)")
    func completenessThroughGrammarVersion() {
        #expect(MessageStructureTable.isComplete(.v2_8, completeVersions: [.v2_8_2]))
        #expect(MessageStructureTable.isComplete(.v2_7, completeVersions: [.v2_7_1]))
        #expect(!MessageStructureTable.isComplete(.v2_8, completeVersions: [.v2_7_1]))
    }

    @Test("The trigger index gives the same owners as scanning every structure and registered gap (P8b-18)")
    func triggerIndexEqualsScan() {
        for version in Version.allCases {
            let table = MessageStructureTable.structures(for: version)
            let gaps = MessageStructureTable.notModelled(for: version)
            var keys = Set(table.values.flatMap(\.triggers) + gaps.values.flatMap(\.triggers))
            keys.formUnion(["ADT^A99", "ACK^", "ACK^A01", "ZZZ^Z01", "ORU^"])
            for key in keys {
                let parts = key.split(separator: "^", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                let code = parts[0], event = parts.count > 1 ? parts[1] : ""
                for event in event == "*" ? ["*", "Q99"] : [event] {
                    let scan = (table.values.filter { $0.accepts(messageCode: code, triggerEvent: event) }.map(\.id).sorted(),
                                gaps.filter { $0.value.accepts(messageCode: code, triggerEvent: event) }.keys.sorted())
                    let index = MessageStructureTable.owners(messageCode: code, triggerEvent: event, version: version)
                    #expect(index.modelled == scan.0 && index.registered == scan.1, "\(version) \(code)^\(event)")
                }
            }
        }
    }
}
