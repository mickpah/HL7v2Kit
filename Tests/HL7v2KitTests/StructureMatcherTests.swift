// StructureMatcherTests.swift
// ADR-019 "Matcher": greedy recursive-descent matching of a message's
// segment-ID sequence against the v2.5.1 pilot structures. Positions are
// message indices (MSH is 0); Z-segments and ADD are transparent.

import Testing
@testable import HL7v2Kit

@Suite("Structure matcher")
struct StructureMatcherTests {

    private func run(_ structureID: String, _ ids: [String], transparent: Set<String> = []) throws -> StructureMatch {
        let structure = try #require(MessageStructureTable.structure(structureID, version: .v2_5_1))
        return StructureMatcher(structure: structure).match(ids, transparent: transparent)
    }

    private func match(_ structureID: String, _ ids: [String], transparent: Set<String> = []) throws -> [StructureFinding] {
        try run(structureID, ids, transparent: transparent).findings
    }

    private func missing(_ id: String, _ group: String?, _ index: Int) -> StructureFinding {
        StructureFinding(kind: .missing, segmentID: id, group: group, index: index)
    }

    private func unexpected(_ id: String, _ index: Int) -> StructureFinding {
        StructureFinding(kind: .unexpected, segmentID: id, group: nil, index: index)
    }

    private func exceeded(_ id: String, _ index: Int) -> StructureFinding {
        StructureFinding(kind: .exceededMaximum, segmentID: id, group: nil, index: index)
    }

    // MARK: - ADT_A01 (CH03 3.3.1)

    @Test("MSH EVN PID PV1 is a complete ADT_A01")
    func adtMinimal() throws {
        #expect(try match("ADT_A01", ["MSH", "EVN", "PID", "PV1"]).isEmpty)
    }

    @Test("A missing EVN is reported at the segment it was expected before")
    func adtMissingEVN() throws {
        #expect(try match("ADT_A01", ["MSH", "PID", "PV1"]) == [missing("EVN", nil, 1)])
    }

    @Test("A missing PV1 at the end is reported at the sequence length")
    func adtMissingPV1() throws {
        #expect(try match("ADT_A01", ["MSH", "EVN", "PID"]) == [missing("PV1", nil, 3)])
    }

    @Test("Missing at the end after a trailing Z-segment: index is the segment count (end of message)")
    func missingAtEndAfterZ() throws {
        #expect(try match("ADT_A01", ["MSH", "EVN", "PID", "ZPI"]) == [missing("PV1", nil, 4)])
        #expect(try match("ADT_A01", ["MSH", "EVN", "PID", "ZPI", "ADD"]) == [missing("PV1", nil, 5)])
    }

    @Test("Cascade (ADR-019 ceiling 2): PV1 before PID gives PID missing, then PID unexpected")
    func adtOutOfOrder() throws {
        #expect(try match("ADT_A01", ["MSH", "EVN", "PV1", "PID"]) == [missing("PID", nil, 2), unexpected("PID", 3)])
    }

    @Test("A second PID exceeds PID's maximum; matching resumes at PV1")
    func adtRepeatedNonRepeating() throws {
        #expect(try match("ADT_A01", ["MSH", "EVN", "PID", "PID", "PV1"]) == [exceeded("PID", 3)])
    }

    @Test("A segment ADT_A01 does not contain is unexpected and skipped")
    func adtForeignSegment() throws {
        #expect(try match("ADT_A01", ["MSH", "EVN", "PID", "OBR", "PV1"]) == [unexpected("OBR", 3)])
    }

    @Test("INSURANCE repeats; IN3 repeats inside it")
    func adtGroupRepetition() throws {
        let result = try run("ADT_A01", ["MSH", "EVN", "PID", "PV1", "IN1", "IN2", "IN1", "IN3", "IN3"])
        #expect(result.findings.isEmpty)
        #expect(result.spans.map(\.description) == ["INSURANCE 4...5", "INSURANCE 6...8"])
    }

    @Test("IN2 twice in one INSURANCE instance exceeds IN2's maximum")
    func adtRepeatedInGroup() throws {
        #expect(try match("ADT_A01", ["MSH", "EVN", "PID", "PV1", "IN1", "IN2", "IN2"]) == [exceeded("IN2", 6)])
    }

    @Test("ROL is accepted in each of its four printed places")
    func adtRolePlaces() throws {
        #expect(try match("ADT_A01", ["MSH", "EVN", "PID", "ROL", "PV1", "ROL", "PR1", "ROL", "IN1", "ROL"]).isEmpty)
    }

    // MARK: - Transparent segments

    @Test("Z-segments are skipped, and a missing segment is located at the next non-Z segment")
    func zSegmentsTransparent() throws {
        #expect(try match("ADT_A01", ["MSH", "ZXX", "EVN", "PID", "ZPI", "PV1", "ZZ9"]).isEmpty)
        #expect(try match("ADT_A01", ["MSH", "ZXX", "PID", "PV1"]) == [missing("EVN", nil, 2)])
    }

    @Test("ADD is transparent on v2.5.1 (CH02 2.10.2.1)")
    func addTransparentV251() throws {
        #expect(try match("ADT_A01", ["MSH", "EVN", "PID", "ADD", "PV1", "ADD"]).isEmpty)
        #expect(try match("ACK", ["MSH", "ADD", "MSA"]).isEmpty)
    }

    @Test("ADD is transparent on v2.3 (CH2 2.23.2): ADD first after MSH")
    func addTransparentV23() {
        // v2.3 CH2 prints ACK as MSH MSA [ERR]; no v2.3 structure is modelled
        // yet, so the shape is built here.
        let ack = MessageStructure(id: "ACK", version: "2.3", triggers: ["ACK^*"], citation: "test", elements: [
            .segment("MSH", min: 1, max: 1), .segment("MSA", min: 1, max: 1), .segment("ERR", min: 0, max: 1),
        ])
        let matcher = StructureMatcher(structure: ack)
        #expect(matcher.match(["MSH", "ADD", "MSA", "ERR", "ADD"]).findings.isEmpty)
        #expect(matcher.match(["MSH", "ADD"]).findings == [missing("MSA", nil, 2)])
    }

    @Test("Caller-supplied transparent IDs (segments outside the version grammar) are skipped")
    func callerTransparent() throws {
        #expect(try match("ADT_A01", ["MSH", "EVN", "PID", "XYZ", "PV1"], transparent: ["XYZ"]).isEmpty)
        #expect(try match("ADT_A01", ["MSH", "EVN", "PID", "XYZ", "PV1"]) == [unexpected("XYZ", 3)])
    }

    // MARK: - ORU_R01 (CH07 7.3.1)

    @Test("MSH PID OBR OBX OBX is a complete ORU_R01")
    func oruMinimal() throws {
        #expect(try match("ORU_R01", ["MSH", "PID", "OBR", "OBX", "OBX"]).isEmpty)
    }

    @Test("Several patients, several orders, PATIENT omitted in one result: spans")
    func oruRepeatingGroups() throws {
        let result = try run("ORU_R01", [
            "MSH", "PID", "PV1", "ORC", "OBR", "OBX", "NTE", "ORC", "OBR", "OBX",
            "PID", "OBR", "OBX", "SPM", "OBX", "OBR",
        ])
        #expect(result.findings.isEmpty)
        #expect(result.spans.map(\.description) == [
            "PATIENT_RESULT 1...9",
            "PATIENT_RESULT/PATIENT 1...2",
            "PATIENT_RESULT/PATIENT/VISIT 2...2",
            "PATIENT_RESULT/ORDER_OBSERVATION 3...6",
            "PATIENT_RESULT/ORDER_OBSERVATION/OBSERVATION 5...6",
            "PATIENT_RESULT/ORDER_OBSERVATION 7...9",
            "PATIENT_RESULT/ORDER_OBSERVATION/OBSERVATION 9...9",
            "PATIENT_RESULT 10...15",
            "PATIENT_RESULT/PATIENT 10...10",
            "PATIENT_RESULT/ORDER_OBSERVATION 11...14",
            "PATIENT_RESULT/ORDER_OBSERVATION/OBSERVATION 12...12",
            "PATIENT_RESULT/ORDER_OBSERVATION/SPECIMEN 13...14",
            "PATIENT_RESULT/ORDER_OBSERVATION 15...15",
        ])
        #expect(result.spans.map(\.parent) == [nil, 0, 1, 0, 3, 0, 5, nil, 7, 7, 9, 9, 7])
    }

    @Test("A span covers the Z-segments inside it")
    func spanCoversZSegments() throws {
        let result = try run("ORU_R01", ["MSH", "PID", "OBR", "ZZ1", "OBX", "ZZ2"])
        #expect(result.findings.isEmpty)
        #expect(result.spans.map(\.description) == [
            "PATIENT_RESULT 1...4",
            "PATIENT_RESULT/PATIENT 1...1",
            "PATIENT_RESULT/ORDER_OBSERVATION 2...4",
            "PATIENT_RESULT/ORDER_OBSERVATION/OBSERVATION 4...4",
        ])
    }

    @Test("ORC with no OBR: OBR missing in ORDER_OBSERVATION")
    func oruMissingOBR() throws {
        #expect(try match("ORU_R01", ["MSH", "PID", "ORC", "OBX"]) == [missing("OBR", "ORDER_OBSERVATION", 3)])
    }

    @Test("First order lacks OBR, second is complete: one finding, not a cascade")
    func oruRecoversAtNextOrder() throws {
        #expect(try match("ORU_R01", ["MSH", "PID", "ORC", "OBX", "ORC", "OBR", "OBX"]) == [
            missing("OBR", "ORDER_OBSERVATION", 3),
        ])
    }

    @Test("OBX before any OBR is unexpected")
    func oruObxBeforeObr() throws {
        #expect(try match("ORU_R01", ["MSH", "PID", "OBX", "OBR"]) == [unexpected("OBX", 2)])
    }

    @Test("A second PV1 exceeds VISIT's PV1")
    func oruRepeatedPV1() throws {
        #expect(try match("ORU_R01", ["MSH", "PID", "PV1", "PV1", "OBR"]) == [exceeded("PV1", 3)])
    }

    @Test("No result group at all: the required PATIENT_RESULT is reported by its head segment")
    func oruEmpty() throws {
        #expect(try match("ORU_R01", ["MSH"]) == [missing("OBR", "PATIENT_RESULT", 1)])
    }

    // MARK: - ACK (CH02 2.14.1)

    @Test("ACK: MSA required, ERR repeats")
    func ack() throws {
        #expect(try match("ACK", ["MSH", "MSA"]).isEmpty)
        #expect(try match("ACK", ["MSH", "MSA", "ERR", "ERR"]).isEmpty)
        #expect(try match("ACK", ["MSH"]) == [missing("MSA", nil, 1)])
        #expect(try match("ACK", ["MSH", "ERR"]) == [missing("MSA", nil, 1)])
        #expect(try match("ACK", ["MSH", "MSA", "MSA"]) == [exceeded("MSA", 2)])
        #expect(try match("ACK", ["MSH", "MSA", "ERR", "MSA"]) == [exceeded("MSA", 3)])
        #expect(try match("ACK", ["MSH", "ERR", "MSA"]) == [missing("MSA", nil, 1), unexpected("MSA", 2)])
    }

    // MARK: - Nullable groups (P8-3 review)

    /// MSH, a required group whose children are all optional, then C.
    private let nullable = MessageStructure(id: "X_N01", version: "2.5.1", triggers: [], citation: "test",
                                            elements: StructureShapes.nullableGroup)

    @Test("A required group of optional children is nullable, and FIRST looks past it")
    func nullableFirstSet() {
        let group = nullable.elements[1]
        #expect(group.isNullable)
        #expect(!nullable.elements[2].isNullable)
        #expect(StructureElement.firstSet(of: nullable.elements[1...]) == ["A", "B", "C"])
        #expect(group.headSegmentID == "A")
    }

    @Test("A nullable required group matches nothing without a finding")
    func nullableMatch() {
        let matcher = StructureMatcher(structure: nullable)
        #expect(matcher.match(["MSH", "C"]).findings.isEmpty)
        #expect(matcher.match(["MSH", "B", "C"]).findings.isEmpty)
        #expect(matcher.match(["MSH", "B", "C"]).spans.map(\.description) == ["G 1...1"])
        #expect(matcher.match(["MSH", "B", "A"]).findings == [unexpected("A", 2), missing("C", nil, 3)])
    }

    @Test("{G: [X] [{N}]}: a second X closes the instance and re-enters G (fix round 1, ruling 3)")
    func allOptionalGroupReentry() {
        let matcher = StructureMatcher(structure: MessageStructure(
            id: "X_G01", version: "2.5.1", triggers: [], citation: "test", elements: StructureShapes.allOptionalGroup))
        let result = matcher.match(["MSH", "X", "N", "X", "X", "N", "N"])
        #expect(result.findings.isEmpty)
        #expect(result.spans.map(\.description) == ["G 1...2", "G 3...3", "G 4...6"])
        #expect(matcher.match(["MSH", "N", "X"]).spans.map(\.description) == ["G 1...1", "G 2...2"])
    }
}
