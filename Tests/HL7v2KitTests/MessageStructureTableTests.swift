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

    @Test("Lookup by trigger line: ADT^A08 resolves to ADT_A01, ACK^A13 to ACK")
    func triggerLookup() {
        #expect(MessageStructureTable.structures(messageCode: "ADT", triggerEvent: "A08", version: .v2_5_1).map(\.id) == ["ADT_A01"])
        #expect(MessageStructureTable.structures(messageCode: "ACK", triggerEvent: "A13", version: .v2_5_1).map(\.id) == ["ACK"])
        #expect(MessageStructureTable.structures(messageCode: "ADT", triggerEvent: "A02", version: .v2_5_1).isEmpty)
    }

    @Test("No trigger line maps to two structures in one version")
    func triggersAreUnique() {
        for version in Version.allCases {
            var owner: [String: String] = [:]
            for structure in MessageStructureTable.structures(for: version).values {
                for trigger in structure.triggers {
                    #expect(owner[trigger] == nil, "\(version.rawValue) \(trigger): \(owner[trigger] ?? "") and \(structure.id)")
                    owner[trigger] = structure.id
                }
            }
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
}
