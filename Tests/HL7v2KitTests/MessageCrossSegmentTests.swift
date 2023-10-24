// MessageCrossSegmentTests.swift
// v0.7-S1 plumbing pins for the cross-segment / message-context helpers
// on `Message`. Per ADR-008, these accessors expose MSH-9 components
// and resolve segment peers within the current ORC/OBR group; the
// predicate evaluator productions land in v0.7-S2 and rely on these.

import Testing
@testable import HL7v2Kit

@Suite("Message cross-segment helpers (v0.7-S1)")
struct MessageCrossSegmentTests {

    // MSH-9 carries the three-component form (code ^ event ^ structure).
    // ORU^R01^ORU_R01 matches the v2.5.1 report-message shape used by
    // the OBR-25 cross-segment rule.
    private let oruWithStructure = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|20260619120000||ORU^R01^ORU_R01|MSG0001|P|2.5.1\r\
    PID|1||123^^^HOSP^MR||Doe^Jane||19800101|F\r\
    ORC|RE|ORD001||GROUP001|CM\r\
    OBR|1|ORD001|FIL001|GLUC^Glucose\r\
    OBX|1|NM|GLUC^Glucose||5.5|mmol/L||N|||F\r
    """

    // Legacy two-component MSH-9 (no message structure component).
    // Common on v2.3 / v2.4 wires.
    private let legacyTwoComponent = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20260619120000||ADT^A01|MSG0001|P|2.4\r\
    PID|1||123^^^HOSP^MR||Smith^John||19800101|M\r
    """

    // Two ORC/OBR groups in a single message — exercises group-boundary
    // resolution. Each ORC heads a group; the OBR within each group is
    // its associated peer.
    private let twoGroupMessage = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|20260619120000||ORU^R01^ORU_R01|MSG0002|P|2.5.1\r\
    PID|1||123^^^HOSP^MR||Doe^Jane||19800101|F\r\
    ORC|RE|ORD001||GROUP001|CM\r\
    OBR|1|ORD001|FIL001|GLUC^Glucose\r\
    ORC|RE|ORD002||GROUP002|CM\r\
    OBR|2|ORD002|FIL002|HBA1C^HbA1c\r
    """

    // MARK: - MSH-9 accessors

    @Test("messageCode reads MSH-9.1 component")
    func messageCodeReadsFirstComponent() throws {
        let message = try Parser().parse(oruWithStructure)
        #expect(message.messageCode == "ORU")
    }

    @Test("triggerEvent reads MSH-9.2 component")
    func triggerEventReadsSecondComponent() throws {
        let message = try Parser().parse(oruWithStructure)
        #expect(message.triggerEvent == "R01")
    }

    @Test("messageStructure reads MSH-9.3 component when present")
    func messageStructureReadsThirdComponent() throws {
        let message = try Parser().parse(oruWithStructure)
        #expect(message.messageStructure == "ORU_R01")
    }

    @Test("messageStructure returns nil when MSH-9 has only two components")
    func messageStructureNilOnLegacyTwoComponent() throws {
        let message = try Parser().parse(legacyTwoComponent)
        #expect(message.messageCode == "ADT")
        #expect(message.triggerEvent == "A01")
        #expect(message.messageStructure == nil)
    }

    // MARK: - associatedSegment

    @Test("associatedSegment finds OBR forward from ORC in same group")
    func associatedOBRFromORC() throws {
        let message = try Parser().parse(oruWithStructure)
        let orcIndex = try #require(
            message.segments.firstIndex { $0.segmentID == "ORC" }
        )
        let peer = try #require(message.associatedSegment("OBR", fromIndex: orcIndex))
        #expect(peer.segmentID == "OBR")
        // OBR-2 carries the placer order; confirm we found the right one.
        #expect(peer.field(2)?.repetitions.first?.stringValue == "ORD001")
    }

    @Test("associatedSegment finds preceding ORC from OBR in same group")
    func associatedORCFromOBR() throws {
        let message = try Parser().parse(oruWithStructure)
        let obrIndex = try #require(
            message.segments.firstIndex { $0.segmentID == "OBR" }
        )
        let peer = try #require(message.associatedSegment("ORC", fromIndex: obrIndex))
        #expect(peer.segmentID == "ORC")
        #expect(peer.field(2)?.repetitions.first?.stringValue == "ORD001")
    }

    @Test("associatedSegment honours ORC group boundary across multi-group wires")
    func associatedSegmentRespectsGroupBoundaries() throws {
        let message = try Parser().parse(twoGroupMessage)
        let orcIndices = message.segments.enumerated().compactMap { (i, s) in
            s.segmentID == "ORC" ? i : nil
        }
        #expect(orcIndices.count == 2)

        // First ORC → its OBR carries ORD001, not ORD002.
        let firstPeer = try #require(
            message.associatedSegment("OBR", fromIndex: orcIndices[0])
        )
        #expect(firstPeer.field(2)?.repetitions.first?.stringValue == "ORD001")

        // Second ORC → its OBR carries ORD002, not ORD001.
        let secondPeer = try #require(
            message.associatedSegment("OBR", fromIndex: orcIndices[1])
        )
        #expect(secondPeer.field(2)?.repetitions.first?.stringValue == "ORD002")
    }

    @Test("associatedSegment from second OBR resolves to second ORC")
    func associatedSecondORCFromSecondOBR() throws {
        let message = try Parser().parse(twoGroupMessage)
        let obrIndices = message.segments.enumerated().compactMap { (i, s) in
            s.segmentID == "OBR" ? i : nil
        }
        let secondPeer = try #require(
            message.associatedSegment("ORC", fromIndex: obrIndices[1])
        )
        #expect(secondPeer.field(2)?.repetitions.first?.stringValue == "ORD002")
    }

    @Test("associatedSegment returns nil when target ID not in group")
    func associatedSegmentReturnsNilWhenAbsent() throws {
        let message = try Parser().parse(oruWithStructure)
        let orcIndex = try #require(
            message.segments.firstIndex { $0.segmentID == "ORC" }
        )
        #expect(message.associatedSegment("NTE", fromIndex: orcIndex) == nil)
    }

    // MARK: - previousSegment

    @Test("previousSegment finds nearest preceding match")
    func previousSegmentFindsNearest() throws {
        let message = try Parser().parse(twoGroupMessage)
        let obrIndices = message.segments.enumerated().compactMap { (i, s) in
            s.segmentID == "OBR" ? i : nil
        }
        // Second OBR — most recent preceding ORC is the second ORC.
        let prev = try #require(
            message.previousSegment("ORC", beforeIndex: obrIndices[1])
        )
        #expect(prev.field(2)?.repetitions.first?.stringValue == "ORD002")
    }

    @Test("previousSegment returns nil at index 0")
    func previousSegmentNilAtIndexZero() throws {
        let message = try Parser().parse(oruWithStructure)
        #expect(message.previousSegment("MSH", beforeIndex: 0) == nil)
    }

    @Test("previousSegment returns nil when no preceding match exists")
    func previousSegmentNilWhenNoMatch() throws {
        let message = try Parser().parse(oruWithStructure)
        // Looking backward from PID for an ORC — none precedes.
        let pidIndex = try #require(
            message.segments.firstIndex { $0.segmentID == "PID" }
        )
        #expect(message.previousSegment("ORC", beforeIndex: pidIndex) == nil)
    }
}
